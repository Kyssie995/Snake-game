--!strict
--[[
	screenFlash — impact frame / screen flash (docs/COMPONENTS_SPEC.md §18).

	A ColorCorrectionEffect parented to workspace.CurrentCamera. Post effects render only with Enabled = true under
	Lighting (every player) or Workspace.CurrentCamera (the local player only) — VERIFIED,
	docs/ROBLOX_API_CONSTRAINTS.md §9.2. ASTRA never touches Lighting.

	Envelope — pure function of local time t (A = attack, H = hold, D = decay), as for `flash` (§10):
	  e(t) = t / A                  for 0 <= t < A        (A = 0: peak immediately)
	       = 1                      for A <= t < A + H
	       = 1 − (t − A − H) / D    for A + H <= t < A + H + D
	       = 0                      otherwise (also t < 0)
	  Brightness = brightness × e   Contrast = contrast × e   Saturation = saturation × e
	  TintColor  = white + (tint − white) × e       (e = 0 is the neutral ColorCorrection 0 / 0 / 0 / white)
	`tint` is the rest value of the `tint` channel, which replaces it while tracked.

	Instance lifecycle: the effect exists only while the component is active, not released and e(t) > 0, so no
	idle full-screen pass remains after the flash. It is created when first needed (Name "AstraVFX_<name>",
	Archivable = false, Enabled = true, tagged with ctx.tagInstance, values written before it is parented) and
	destroyed when the envelope ends, on deactivation, release, reset and destroy. While it exists it is the only
	entry of controller.instances (the list is empty otherwise). If the current camera changes — or the effect was
	destroyed together with the old camera — a fresh effect is created under the new camera.

	Where it runs: clients at runtime (Players.LocalPlayer ~= nil); servers: no-op (no instances). Preview
	(ctx.isPreview): on the Studio camera when previewInStudio (default true). Viewport: never (no post-processing
	in a ViewportFrame — VERIFIED). Each property is written only when its value changes (4 writes per frame during
	attack and decay, none while holding).

	Engine range note: Brightness is documented as −1 (black) … 1 (white) (VERIFIED); the authoring range allows up
	to 2 and values are written as authored — what the engine does above 1 is unverified.
]]

local Common = require(script.Parent.Common)
local Types = require(script.Parent.Parent.Types)

type CompiledComponent = Types.CompiledComponent
type ComponentInstance = Types.ComponentInstance
type FrameContext = Types.FrameContext
type CostEstimate = Types.CostEstimate

-- Envelope values below this count as 0 (float residue at the end of the decay must not keep the effect alive).
local ENVELOPE_EPSILON = 1e-9

-- Envelope value (0..1) at local time t.
local function envelope(t: number, attack: number, hold: number, decay: number): number
	if t < 0 then
		return 0
	end
	if t < attack then
		return t / attack
	end
	local decayStart = attack + hold
	if t < decayStart then
		return 1
	end
	if decay <= 0 then
		return 0
	end
	local e = 1 - (t - decayStart) / decay
	if e <= ENVELOPE_EPSILON then
		return 0
	end
	return e
end

local function towards(tint: Color3, e: number): Color3
	if e >= 1 then
		return tint
	end
	return Color3.new(1 + (tint.R - 1) * e, 1 + (tint.G - 1) * e, 1 + (tint.B - 1) * e)
end

local descriptor: Types.ComponentDescriptor = {
	type = "screenFlash",
	displayName = "Screen Flash",
	category = "Camera",
	description = "Impact frame: a short full-screen ColorCorrection pulse (contrast, desaturation, tint) on the "
		.. "local player's camera. Client only.",
	icon = "◐",
	properties = {
		Common.prop("brightness", "number", 0.35, "ColorCorrection Brightness at the peak.", {
			category = "Look",
			min = -1,
			max = 2,
			step = 0.05,
		}),
		Common.prop("contrast", "number", 0.8, "ColorCorrection Contrast at the peak.", {
			category = "Look",
			min = -1,
			max = 3,
			step = 0.05,
		}),
		Common.prop("saturation", "number", -0.6, "ColorCorrection Saturation at the peak (−1 = greyscale).", {
			category = "Look",
			min = -1,
			max = 2,
			step = 0.05,
		}),
		Common.prop("tint", "color3", "#FFFFFF", "TintColor at the peak (multiplies the image; white = none).", {
			category = "Look",
		}),
		Common.prop("attack", "number", 0.02, "Seconds from neutral to the peak (linear).", {
			category = "Envelope",
			min = 0,
			max = 2,
			step = 0.01,
		}),
		Common.prop("hold", "number", 0.05, "Seconds held at the peak.", {
			category = "Envelope",
			min = 0,
			max = 2,
			step = 0.01,
		}),
		Common.prop("decay", "number", 0.18, "Seconds from the peak back to neutral (linear).", {
			category = "Envelope",
			min = 0.01,
			max = 5,
			step = 0.01,
		}),
		Common.prop(
			"previewInStudio",
			"boolean",
			true,
			"Show the flash on the Studio camera in the editor preview.",
			{ category = "Preview" }
		),
	},
	channels = {
		Common.channel("tint", "color3", "TintColor at the peak (replaces the tint property while tracked).", {
			baseProperty = "tint",
		}),
	},
	events = {},
	canParent = true,
	supportsViewport = false,
	build = function(ctx: Types.BuildContext, component: CompiledComponent): ComponentInstance
		local props = component.props
		local instances: { Instance } = {}
		local controller = Common.controller(component, instances)

		local enabled: boolean
		if ctx.viewport then
			enabled = false
		elseif ctx.isPreview then
			enabled = props.previewInStudio == true
		else
			enabled = Common.hasLocalPlayer()
		end
		local workspaceService: any = if enabled then Common.tryService("Workspace") else nil

		local attack: number = props.attack
		local hold: number = props.hold
		local decay: number = props.decay
		local brightness: number = props.brightness
		local contrast: number = props.contrast
		local saturation: number = props.saturation

		local alive = true
		local active = false
		local released = false
		local localTime = 0
		local tint: Color3 = props.tint

		local effect: ColorCorrectionEffect? = nil
		local writtenBrightness: number? = nil
		local writtenContrast: number? = nil
		local writtenSaturation: number? = nil
		local writtenTint: Color3? = nil

		local function removeEffect()
			local current = effect
			if current == nil then
				return
			end
			effect = nil
			local index = table.find(instances, current)
			if index then
				table.remove(instances, index)
			end
			current:Destroy()
		end

		local function refresh()
			if not alive then
				return
			end
			local e = if enabled and active and not released then envelope(localTime, attack, hold, decay) else 0
			local camera = if e > 0 then Common.currentCamera(workspaceService) else nil
			local current = effect
			if current and (camera == nil or current.Parent ~= camera) then
				removeEffect()
				current = nil
			end
			if camera == nil then
				return
			end
			local target: ColorCorrectionEffect
			local created = false
			if current then
				target = current
			else
				target = Instance.new("ColorCorrectionEffect")
				target.Name = "AstraVFX_" .. component.name
				target.Archivable = false
				target.Enabled = true
				writtenBrightness, writtenContrast, writtenSaturation, writtenTint = nil, nil, nil, nil
				created = true
			end
			local b = brightness * e
			if b ~= writtenBrightness then
				writtenBrightness = b
				target.Brightness = b
			end
			local c = contrast * e
			if c ~= writtenContrast then
				writtenContrast = c
				target.Contrast = c
			end
			local s = saturation * e
			if s ~= writtenSaturation then
				writtenSaturation = s
				target.Saturation = s
			end
			local color = towards(tint, e)
			if color ~= writtenTint then
				writtenTint = color
				target.TintColor = color
			end
			if created then
				ctx.tagInstance(target, component.id)
				target.Parent = camera
				effect = target
				table.insert(instances, target)
			end
		end

		function controller.setActive(_self: ComponentInstance, isActive: boolean, frame: FrameContext)
			if not alive then
				return
			end
			active = isActive
			if isActive then
				localTime = math.max(frame.time - component.startTime, 0)
			end
			refresh()
		end

		function controller.apply(_self: ComponentInstance, channel: string, value: any)
			if channel == "tint" and typeof(value) == "Color3" then
				tint = value
				refresh()
			end
		end

		controller.update = function(_self: ComponentInstance, time: number, _frame: FrameContext)
			localTime = time
			refresh()
		end

		function controller.release(_self: ComponentInstance)
			released = true
			refresh()
		end

		function controller.reset(_self: ComponentInstance)
			active = false
			released = false
			localTime = 0
			tint = props.tint
			refresh()
		end

		function controller.destroy(self: ComponentInstance)
			if alive then
				removeEffect()
				alive = false
			end
			table.clear(self.instances)
		end

		return controller
	end,
	estimateCost = function(component: CompiledComponent, _quality: Types.QualityProfile): CostEstimate
		local props = component.props
		local cost = Common.cost()
		cost.instances = 1
		-- Brightness, Contrast, Saturation and TintColor while the envelope moves (cached while holding).
		cost.propertyUpdates = 4
		local notes = { "post effect: full-screen pass" }
		if component.endTime - component.startTime < props.attack + props.hold + props.decay then
			table.insert(notes, "Component span is shorter than attack + hold + decay; the flash is cut off.")
		end
		cost.notes = notes
		return cost
	end,
}

return descriptor
