--!strict
--[[
	ComponentsNative — descriptor specs for the native engine components particles, beam, trail, light and sound
	(docs/COMPONENTS_SPEC.md §2-4, §7, §8).

	Real instances (Lune reflection-checked, or the real engine in Studio) are built through
	Tests.Specs.Helpers.ComponentHarness. Engine methods (Emit, Clear, Play, Stop) are recorded by the Lune fakes;
	tests reading those records only run in Lune (T.itIf).

	Structure:
	  1. Spec fidelity per type: property keys/kinds/defaults/ranges/flags, channels, events, Codec round trip of every
	     default, enum items exist in the Roblox Enum.
	  2. Generic controller contract per build variant: tagging, physics-free hosts, cost counts = built instances,
	     disabled until active, history independence (scrubbing) and seed independence, reset() = built state,
	     destroy() leaves nothing, unknown channels ignored.
	  3. Type-specific behaviour (emission, attachment geometry, clamps, quality, events, preview audio).
]]

type Expected = {
	name: string,
	kind: string,
	default: any,
	min: number?,
	max: number?,
	scale: string?,
	quality: string?,
	advanced: boolean?,
	enumType: string?,
	enum: { string }?,
}

type ExpectedChannel = {
	name: string,
	kind: string,
	baseProperty: string?,
	scale: string?,
	min: number?,
	max: number?,
}

type ExpectedType = {
	category: string,
	properties: { Expected },
	channels: { ExpectedChannel },
	events: { string },
	tailTime: boolean,
}

local NORMAL_IDS = { "Top", "Bottom", "Front", "Back", "Left", "Right" }
local TEXTURE_MODES = { "Stretch", "Wrap", "Static" }

local function transformChannels(withScale: boolean): { ExpectedChannel }
	local out: { ExpectedChannel } = {
		{ name = "position", kind = "vector3", scale = "length" },
		{ name = "rotation", kind = "vector3" },
	}
	if withScale then
		table.insert(out, { name = "scale", kind = "number", min = 0 })
	end
	return out
end

local function concat(a: { ExpectedChannel }, b: { ExpectedChannel }): { ExpectedChannel }
	local out = table.clone(a)
	for _, x in b do
		table.insert(out, x)
	end
	return out
end

-- Transcription of docs/COMPONENTS_SPEC.md (property tables, channels, events).
local SPEC: { [string]: ExpectedType } = {
	particles = {
		category = "Particles",
		properties = {
			{ name = "texture", kind = "asset", default = "rbxasset://textures/particles/sparkles_main.dds" },
			{ name = "color", kind = "colorSequence", default = "#FFFFFF" },
			{ name = "transparency", kind = "numberSequence", default = 0, min = 0, max = 1 },
			{ name = "size", kind = "numberSequence", default = 1, min = 0, max = 100, scale = "length" },
			{ name = "squash", kind = "numberSequence", default = 0, min = -3, max = 3, advanced = true },
			{ name = "lifetime", kind = "numberRange", default = { 1, 2 }, min = 0, max = 20 },
			{ name = "rate", kind = "number", default = 20, min = 0, max = 400, quality = "count" },
			{ name = "burst", kind = "integer", default = 0, min = 0, max = 10000, quality = "count" },
			{ name = "speed", kind = "numberRange", default = { 5, 5 }, min = -1000, max = 1000, scale = "length" },
			{ name = "spreadAngle", kind = "vector2", default = { 0, 0 }, min = -360, max = 360 },
			{ name = "acceleration", kind = "vector3", default = { 0, 0, 0 }, scale = "length" },
			{ name = "drag", kind = "number", default = 0, min = 0, max = 100 },
			{ name = "rotation", kind = "numberRange", default = { 0, 0 }, min = -360, max = 360 },
			{ name = "rotSpeed", kind = "numberRange", default = { 0, 0 }, min = -3600, max = 3600 },
			{ name = "emissionDirection", kind = "enum", default = "Top", enumType = "NormalId", enum = NORMAL_IDS },
			{
				name = "shape",
				kind = "enum",
				default = "Point",
				enum = { "Point", "Box", "Sphere", "Cylinder", "Disc" },
			},
			{ name = "emitterSize", kind = "vector3", default = { 1, 1, 1 }, min = 0, max = 2048, scale = "length" },
			{
				name = "shapeStyle",
				kind = "enum",
				default = "Volume",
				enumType = "ParticleEmitterShapeStyle",
				enum = { "Volume", "Surface" },
			},
			{
				name = "shapeInOut",
				kind = "enum",
				default = "Outward",
				enumType = "ParticleEmitterShapeInOut",
				enum = { "Outward", "Inward", "InAndOut" },
			},
			{ name = "shapePartial", kind = "number", default = 1, min = 0, max = 1 },
			{
				name = "orientation",
				kind = "enum",
				default = "FacingCamera",
				enumType = "ParticleOrientation",
				enum = { "FacingCamera", "FacingCameraWorldUp", "VelocityParallel", "VelocityPerpendicular" },
			},
			{ name = "lightEmission", kind = "number", default = 0, min = 0, max = 1 },
			{ name = "lightInfluence", kind = "number", default = 0, min = 0, max = 1 },
			{ name = "brightness", kind = "number", default = 1, min = 0, max = 100 },
			{ name = "zOffset", kind = "number", default = 0, min = -100, max = 100 },
			{ name = "timeScale", kind = "number", default = 1, min = 0, max = 1 },
			{ name = "lockedToPart", kind = "boolean", default = false },
			{ name = "velocityInheritance", kind = "number", default = 0, min = 0, max = 1, advanced = true },
			{ name = "windAffectsDrag", kind = "boolean", default = false, advanced = true },
			{
				name = "flipbookLayout",
				kind = "enum",
				default = "None",
				enumType = "ParticleFlipbookLayout",
				enum = { "None", "Grid2x2", "Grid4x4", "Grid8x8" },
			},
			{
				name = "flipbookMode",
				kind = "enum",
				default = "Loop",
				enumType = "ParticleFlipbookMode",
				enum = { "Loop", "OneShot", "PingPong", "Random" },
			},
			{ name = "flipbookFramerate", kind = "numberRange", default = { 1, 1 }, min = 0, max = 30 },
			{ name = "flipbookStartRandom", kind = "boolean", default = false },
			{ name = "spin", kind = "vector3", default = { 0, 0, 0 } },
		},
		channels = concat(transformChannels(true), {
			{ name = "transparency", kind = "number", min = 0, max = 1 },
			{ name = "tint", kind = "color3" },
			{ name = "rate", kind = "number", baseProperty = "rate", min = 0, max = 400 },
			{ name = "brightness", kind = "number", baseProperty = "brightness", min = 0, max = 100 },
			{ name = "lightEmission", kind = "number", baseProperty = "lightEmission", min = 0, max = 1 },
			{ name = "acceleration", kind = "vector3", baseProperty = "acceleration", scale = "length" },
			{ name = "timeScale", kind = "number", baseProperty = "timeScale", min = 0, max = 1 },
		}),
		events = { "emit", "clear", "enable", "disable" },
		tailTime = true,
	},
	beam = {
		category = "Beams & Trails",
		properties = {
			{ name = "from", kind = "vector3", default = { 0, 0, 0 }, scale = "length" },
			{ name = "to", kind = "vector3", default = { 0, 0, -10 }, scale = "length" },
			{ name = "curveDirection", kind = "vector3", default = { 0, 1, 0 } },
			{ name = "roll", kind = "number", default = 0, min = -360, max = 360 },
			{ name = "texture", kind = "asset", default = "" },
			{ name = "color", kind = "colorSequence", default = "#FFFFFF" },
			{ name = "transparency", kind = "numberSequence", default = 0, min = 0, max = 1 },
			{ name = "width0", kind = "number", default = 1, min = 0, max = 1000, scale = "length" },
			{ name = "width1", kind = "number", default = 1, min = 0, max = 1000, scale = "length" },
			{ name = "curveSize0", kind = "number", default = 0, min = -1000, max = 1000, scale = "length" },
			{ name = "curveSize1", kind = "number", default = 0, min = -1000, max = 1000, scale = "length" },
			{ name = "segments", kind = "integer", default = 10, min = 1, max = 1000 }, -- not quality-scaled (K14)
			{ name = "textureLength", kind = "number", default = 1, min = 0.01, max = 1000, scale = "length" },
			{
				name = "textureMode",
				kind = "enum",
				default = "Stretch",
				enumType = "TextureMode",
				enum = TEXTURE_MODES,
			},
			{ name = "textureSpeed", kind = "number", default = 1, min = -100, max = 100 },
			{ name = "faceCamera", kind = "boolean", default = true },
			{ name = "lightEmission", kind = "number", default = 0, min = 0, max = 1 },
			{ name = "lightInfluence", kind = "number", default = 0, min = 0, max = 1 },
			{ name = "brightness", kind = "number", default = 1, min = 0, max = 100 },
			{ name = "zOffset", kind = "number", default = 0 },
			{ name = "spin", kind = "vector3", default = { 0, 0, 0 } },
		},
		channels = concat(transformChannels(true), {
			{ name = "transparency", kind = "number", min = 0, max = 1 },
			{ name = "tint", kind = "color3" },
			{ name = "width0", kind = "number", baseProperty = "width0", scale = "length", min = 0, max = 1000 },
			{ name = "width1", kind = "number", baseProperty = "width1", scale = "length", min = 0, max = 1000 },
			{
				name = "curveSize0",
				kind = "number",
				baseProperty = "curveSize0",
				scale = "length",
				min = -1000,
				max = 1000,
			},
			{
				name = "curveSize1",
				kind = "number",
				baseProperty = "curveSize1",
				scale = "length",
				min = -1000,
				max = 1000,
			},
			{ name = "from", kind = "vector3", baseProperty = "from", scale = "length" },
			{ name = "to", kind = "vector3", baseProperty = "to", scale = "length" },
			{ name = "brightness", kind = "number", baseProperty = "brightness", min = 0, max = 100 },
			{ name = "textureSpeed", kind = "number", baseProperty = "textureSpeed", min = -100, max = 100 },
		}),
		events = { "enable", "disable" },
		tailTime = false,
	},
	trail = {
		category = "Beams & Trails",
		properties = {
			{ name = "width", kind = "number", default = 1, min = 0, max = 100, scale = "length" },
			{ name = "widthDirection", kind = "vector3", default = { 0, 1, 0 } },
			{ name = "lifetime", kind = "number", default = 0.5, min = 0.01, max = 20 },
			{ name = "minLength", kind = "number", default = 0.1, min = 0, max = 100, scale = "length" },
			{ name = "maxLength", kind = "number", default = 0, min = 0, max = 10000, scale = "length" },
			{ name = "widthScale", kind = "numberSequence", default = 1, min = 0, max = 1 },
			{ name = "color", kind = "colorSequence", default = "#FFFFFF" },
			{ name = "transparency", kind = "numberSequence", default = 0, min = 0, max = 1 },
			{ name = "texture", kind = "asset", default = "" },
			{ name = "textureLength", kind = "number", default = 1, scale = "length" },
			{
				name = "textureMode",
				kind = "enum",
				default = "Stretch",
				enumType = "TextureMode",
				enum = TEXTURE_MODES,
			},
			{ name = "faceCamera", kind = "boolean", default = false },
			{ name = "lightEmission", kind = "number", default = 0, min = 0, max = 1 },
			{ name = "lightInfluence", kind = "number", default = 0, min = 0, max = 1 },
			{ name = "brightness", kind = "number", default = 1, min = 0, max = 100 },
			{ name = "clearOnStart", kind = "boolean", default = true },
			{ name = "spin", kind = "vector3", default = { 0, 0, 0 } },
		},
		channels = concat(transformChannels(true), {
			{ name = "width", kind = "number", baseProperty = "width", scale = "length", min = 0, max = 100 },
			{ name = "transparency", kind = "number", min = 0, max = 1 },
			{ name = "tint", kind = "color3" },
			{ name = "brightness", kind = "number", baseProperty = "brightness", min = 0, max = 100 },
		}),
		events = { "enable", "disable", "clear" },
		tailTime = true,
	},
	light = {
		category = "Lighting",
		properties = {
			{ name = "lightType", kind = "enum", default = "Point", enum = { "Point", "Spot", "Surface" } },
			{ name = "color", kind = "color3", default = "#FFFFFF" },
			{ name = "brightness", kind = "number", default = 1, min = 0, max = 100 },
			{ name = "range", kind = "number", default = 8, min = 0, max = 120, scale = "length" },
			{ name = "angle", kind = "number", default = 90, min = 0, max = 180 },
			{
				name = "face",
				kind = "enum",
				default = "Front",
				enumType = "NormalId",
				enum = { "Front", "Back", "Top", "Bottom", "Left", "Right" },
			},
			{ name = "shadows", kind = "boolean", default = false },
			{ name = "surfaceSize", kind = "vector3", default = { 4, 4, 0.2 }, scale = "length" },
		},
		channels = concat(transformChannels(false), {
			{ name = "brightness", kind = "number", baseProperty = "brightness", min = 0, max = 100 },
			{ name = "range", kind = "number", baseProperty = "range", scale = "length", min = 0, max = 120 },
			{ name = "color", kind = "color3", baseProperty = "color" },
			{ name = "angle", kind = "number", baseProperty = "angle", min = 0, max = 180 },
		}),
		events = { "enable", "disable" },
		tailTime = false,
	},
	sound = {
		category = "Audio",
		properties = {
			{ name = "soundId", kind = "asset", default = "" },
			{ name = "volume", kind = "number", default = 0.5, min = 0, max = 10 },
			{ name = "playbackSpeed", kind = "number", default = 1, min = 0.01, max = 10 },
			{ name = "rollOffMinDistance", kind = "number", default = 10, min = 0, max = 10000, scale = "length" },
			{ name = "rollOffMaxDistance", kind = "number", default = 100, min = 0, max = 10000, scale = "length" },
			{ name = "looped", kind = "boolean", default = false },
			{ name = "playOnStart", kind = "boolean", default = true },
		},
		channels = {
			{ name = "position", kind = "vector3", scale = "length" },
			{ name = "volume", kind = "number", baseProperty = "volume", min = 0, max = 10 },
			{ name = "playbackSpeed", kind = "number", baseProperty = "playbackSpeed", min = 0.01, max = 10 },
		},
		events = { "play", "stop" },
		tailTime = false,
	},
}

local NATIVE = { "particles", "beam", "trail", "light", "sound" }

type Variant = { label: string, type: string, props: { [string]: any } }

local VARIANTS: { Variant } = {
	{ label = "particles (Point)", type = "particles", props = {} },
	{ label = "particles (Box)", type = "particles", props = { shape = "Box" } },
	{ label = "particles (Sphere)", type = "particles", props = { shape = "Sphere" } },
	{ label = "particles (Cylinder)", type = "particles", props = { shape = "Cylinder" } },
	{ label = "particles (Disc)", type = "particles", props = { shape = "Disc" } },
	{ label = "beam", type = "beam", props = {} },
	{ label = "trail", type = "trail", props = {} },
	{ label = "light (Point)", type = "light", props = {} },
	{ label = "light (Spot)", type = "light", props = { lightType = "Spot" } },
	{ label = "light (Surface)", type = "light", props = { lightType = "Surface" } },
	{ label = "sound", type = "sound", props = { soundId = "rbxassetid://1" } },
}

local HIGH = {
	level = "High",
	countScale = 1,
	segmentScale = 1,
	sizeCompensation = 1,
	lightShadows = true,
	maxLights = math.huge,
}

local LOW = {
	level = "Low",
	countScale = 0.5,
	segmentScale = 0.5,
	sizeCompensation = 1.5,
	lightShadows = false,
	maxLights = 4,
}

-- JSON colour-sequence keypoint [time, "#RRGGBB"] (mixed array, typed as any for the analyzer).
local function colorKey(t: number, color: string): { any }
	return { t :: any, color }
end

-- Snapshot formatting: rounded strings so float noise never matters and toEqual shows the differing key.
local function round(x: number): string
	local r = math.floor(x * 1e4 + 0.5) / 1e4
	if r == 0 then
		r = 0
	end
	return string.format("%.4f", r)
end

local function fmt(v: any): string
	local t = typeof(v)
	if t == "number" then
		return round(v)
	elseif t == "boolean" or t == "string" then
		return tostring(v)
	elseif t == "Vector3" then
		return round(v.X) .. "," .. round(v.Y) .. "," .. round(v.Z)
	elseif t == "Vector2" then
		return round(v.X) .. "," .. round(v.Y)
	elseif t == "Color3" then
		return round(v.R) .. "," .. round(v.G) .. "," .. round(v.B)
	elseif t == "CFrame" then
		local parts = {}
		for _, c in { v:GetComponents() } do
			table.insert(parts, round(c))
		end
		return table.concat(parts, ",")
	elseif t == "NumberRange" then
		return round(v.Min) .. ".." .. round(v.Max)
	elseif t == "NumberSequence" then
		local parts = {}
		for _, k in v.Keypoints do
			table.insert(parts, round(k.Time) .. ":" .. round(k.Value) .. "±" .. round(k.Envelope))
		end
		return table.concat(parts, " ")
	elseif t == "ColorSequence" then
		local parts = {}
		for _, k in v.Keypoints do
			table.insert(parts, round(k.Time) .. ":" .. fmt(k.Value))
		end
		return table.concat(parts, " ")
	elseif t == "EnumItem" then
		return tostring(v)
	end
	return tostring(v)
end

-- Properties a controller may change at runtime (plus transforms), per class.
local WATCHED: { [string]: { string } } = {
	ParticleEmitter = {
		"Enabled",
		"Rate",
		"Size",
		"Transparency",
		"Color",
		"Brightness",
		"LightEmission",
		"Acceleration",
		"TimeScale",
	},
	Beam = {
		"Enabled",
		"Width0",
		"Width1",
		"CurveSize0",
		"CurveSize1",
		"Transparency",
		"Color",
		"Brightness",
		"TextureSpeed",
	},
	Trail = { "Enabled", "Transparency", "Color", "Brightness", "Lifetime" },
	PointLight = { "Enabled", "Brightness", "Color", "Range", "Shadows" },
	SpotLight = { "Enabled", "Brightness", "Color", "Range", "Angle", "Face", "Shadows" },
	SurfaceLight = { "Enabled", "Brightness", "Color", "Range", "Angle", "Face", "Shadows" },
	Sound = { "Volume", "PlaybackSpeed", "Looped", "SoundId" },
	Attachment = { "CFrame" },
	Part = { "CFrame", "Size", "Transparency" },
}

local function snapshot(controller: any): { [string]: string }
	local out = {}
	for i, inst in controller.instances do
		local watched = WATCHED[inst.ClassName]
		assert(watched, "no watched properties for " .. inst.ClassName)
		for _, p in watched do
			out[i .. "." .. inst.ClassName .. "." .. p] = fmt((inst :: any)[p])
		end
	end
	return out
end

-- Deterministic channel values for history tests (phase 1 = intermediate history, phase 2 = final value).
local function channelValue(spec: any, phase: number): any
	if spec.kind == "number" then
		local lo: number = spec.min or 0
		local hi: number = spec.max or (lo + 4)
		return lo + (hi - lo) * (if phase == 1 then 0.3 else 0.7)
	elseif spec.kind == "vector3" then
		local offset = Vector3.new(#spec.name, 0, 0)
		return offset + (if phase == 1 then Vector3.new(1, 2, 3) else Vector3.new(-2, 0.5, 4))
	elseif spec.kind == "color3" then
		return if phase == 1 then Color3.new(1, 0.5, 0.25) else Color3.new(0.2, 0.4, 1)
	end
	return phase == 2
end

-- Channel -> property of the main instance (instances[1]) the channel writes; used to prove value caching.
local CACHE_PROBES: { [string]: { [string]: string } } = {
	particles = {
		transparency = "Transparency",
		tint = "Color",
		rate = "Rate",
		brightness = "Brightness",
		lightEmission = "LightEmission",
		acceleration = "Acceleration",
		timeScale = "TimeScale",
		scale = "Size",
	},
	beam = {
		scale = "Width0",
		transparency = "Transparency",
		tint = "Color",
		width0 = "Width0",
		width1 = "Width1",
		curveSize0 = "CurveSize0",
		curveSize1 = "CurveSize1",
		brightness = "Brightness",
		textureSpeed = "TextureSpeed",
	},
	trail = { transparency = "Transparency", tint = "Color", brightness = "Brightness" },
	light = { brightness = "Brightness", color = "Color", range = "Range" },
	sound = { volume = "Volume", playbackSpeed = "PlaybackSpeed" },
}

local function sentinelFor(value: any): any
	local t = typeof(value)
	if t == "number" then
		return 0.123
	elseif t == "Vector3" then
		return Vector3.new(9, 8, 7)
	elseif t == "Color3" then
		return Color3.new(0.1, 0.2, 0.3)
	elseif t == "NumberSequence" then
		return NumberSequence.new(0.123)
	elseif t == "ColorSequence" then
		return ColorSequence.new(Color3.new(0.1, 0.2, 0.3))
	elseif t == "CFrame" then
		return CFrame.new(9, 8, 7)
	end
	error("no sentinel for " .. t)
end

return function(T: any, use: (string) -> any, ctx: any)
	local Harness = use("Tests.Specs.Helpers.ComponentHarness")
	local Codec = use("AstraVFX.Core.Codec")
	local Components = use("AstraVFX.Core.Components")
	local Constants = use("AstraVFX.Core.Constants")
	local Env = use("AstraVFX.Core.Env")
	local isLune = ctx.environment == "lune"
	local fakes = ctx.fakes

	-- Every harness created by a test is cleaned up after it (also when an expectation failed).
	local open: { any } = {}
	local function harness(): any
		local h = Harness.new(use)
		table.insert(open, h)
		return h
	end

	local function frame(h: any, seeking: boolean?): any
		return h:frame(0, if seeking then 0 else 1 / 60, seeking)
	end

	-- Builds with a custom BuildContext / CompiledComponent (e.g. effect time scale or post-Compiler values).
	local function buildWith(h: any, componentType: string, props: { [string]: any }?, options: any?, mutate: any?)
		local component = h:compile(componentType, props, options)
		local bctx = h:context({ [component.id] = component }, options)
		if mutate then
			mutate(component, bctx)
		end
		local controller = Components.get(componentType).build(bctx, component)
		table.insert(h.controllers, controller)
		return controller, component, bctx
	end

	local function clearsOf(inst: any): number
		local n = 0
		for _, c in fakes.clears do
			if c == inst then
				n += 1
			end
		end
		return n
	end

	local function emitCalls(inst: any): { number }
		local out = {}
		for _, e in fakes.emits do
			if e.instance == inst then
				table.insert(out, e.count)
			end
		end
		return out
	end

	local function soundActions(inst: any): { string }
		local out = {}
		for _, s in fakes.sounds do
			if s.instance == inst then
				table.insert(out, s.action)
			end
		end
		return out
	end

	local function firstOfClass(list: { any }, className: string): any
		for _, inst in list do
			if inst:IsA(className) then
				return inst
			end
		end
		return nil
	end

	local function keypointValues(seq: any): { number }
		local out = {}
		for _, k in seq.Keypoints do
			table.insert(out, k.Value)
		end
		return out
	end

	T.describe("ComponentsNative", function()
		T.afterEach(function()
			for _, h in open do
				h:cleanup()
			end
			table.clear(open)
		end)

		-- ─────────────────────────────────────────────────────────────────────
		-- 1. Spec fidelity
		-- ─────────────────────────────────────────────────────────────────────
		for _, typeName in NATIVE do
			local expected = SPEC[typeName]
			T.describe(typeName .. " spec", function()
				T.it("is discovered by the registry with category, viewport flag and tail time", function()
					local d = Components.get(typeName)
					T.expect(d).never.toBeNil()
					T.expect(d.type).toBe(typeName)
					T.expect(d.category).toBe(expected.category)
					T.expect(d.supportsViewport).toBe(false)
					T.expect(Components.types()).toContain(typeName)
					T.expect(type(d.build)).toBe("function")
					T.expect(type(d.estimateCost)).toBe("function")
					T.expect(d.tailTime ~= nil).toBe(expected.tailTime)
				end)

				T.it("declares exactly the spec properties (keys, order, kinds, defaults, ranges, flags)", function()
					local actual = {}
					for _, p in Components.get(typeName).properties do
						table.insert(actual, {
							name = p.name,
							kind = p.kind,
							default = p.default,
							min = p.min,
							max = p.max,
							scale = p.scale,
							quality = p.quality,
							advanced = if p.advanced then true else nil,
							enumType = p.enumType,
							enum = p.enum,
						})
						T.expect(type(p.description)).toBe("string")
						T.expect(#p.description > 0).toBe(true)
					end
					T.expect(actual).toEqual(expected.properties)
				end)

				T.it("declares exactly the spec channels and events", function()
					local actual = {}
					for _, c in Components.get(typeName).channels do
						table.insert(actual, {
							name = c.name,
							kind = c.kind,
							baseProperty = c.baseProperty,
							scale = c.scale,
							min = c.min,
							max = c.max,
						})
					end
					T.expect(actual).toEqual(expected.channels)
					local events = {}
					for _, e in Components.get(typeName).events do
						table.insert(events, e.action)
						T.expect(type(e.description)).toBe("string")
					end
					T.expect(events).toEqual(expected.events)
				end)

				T.it("every property default passes Codec.check and decodes", function()
					for _, p in Components.get(typeName).properties do
						local value = Codec.default(p)
						local ok, message = Codec.check(p.kind, value, p)
						T.expect({ p.name, ok, message }).toEqual({ p.name, true, nil })
						local decoded = Codec.decode(p.kind, value, p)
						T.expect({ p.name, decoded ~= nil }).toEqual({ p.name, true })
					end
				end)

				T.it("every enum item with an enumType is a real Roblox Enum item", function()
					for _, p in Components.get(typeName).properties do
						if p.kind == "enum" and p.enumType then
							for _, item in p.enum do
								local v = Codec.decode("enum", item, p)
								T.expect(typeof(v)).toBe("EnumItem")
								T.expect(v.Name).toBe(item)
							end
						end
					end
				end)

				T.it("channel baseProperty names a property of the same value kind", function()
					local compatible = {
						number = { number = true, integer = true },
						vector3 = { vector3 = true },
						color3 = { color3 = true },
						boolean = { boolean = true },
					}
					for _, c in Components.get(typeName).channels do
						if c.baseProperty then
							local p = Components.propertySpec(typeName, c.baseProperty)
							T.expect({ c.name, p ~= nil }).toEqual({ c.name, true })
							T.expect({ c.name, compatible[c.kind][p.kind] == true }).toEqual({ c.name, true })
						end
					end
				end)
			end)
		end

		-- ─────────────────────────────────────────────────────────────────────
		-- 2. Generic controller contract per build variant
		-- ─────────────────────────────────────────────────────────────────────
		for _, variant in VARIANTS do
			T.describe(variant.label .. " controller", function()
				local descriptor = Components.get(variant.type)

				T.it("builds with defaults; every instance is tagged, listed and inside the container", function()
					local h = harness()
					local c, comp = h:build(variant.type, variant.props)
					T.expect(c.component).toBe(comp)
					local tagged = h:instancesOf(comp.id)
					T.expect(#tagged).toBe(#c.instances)
					for _, inst in c.instances do
						T.expect(inst:GetAttribute("AstraComponent")).toBe(comp.id)
						T.expect(inst:IsDescendantOf(h.container)).toBe(true)
					end
				end)

				T.it("parts are physics-free, shadowless and invisible hosts", function()
					local h = harness()
					local _, comp = h:build(variant.type, variant.props)
					for _, inst in h:instancesOf(comp.id) do
						if inst:IsA("BasePart") then
							T.expect(inst.Anchored).toBe(true)
							T.expect(inst.CanCollide).toBe(false)
							T.expect(inst.CanQuery).toBe(false)
							T.expect(inst.CanTouch).toBe(false)
							T.expect(inst.CastShadow).toBe(false)
							T.expect(inst.Transparency).toBe(1)
						end
					end
				end)

				T.it("estimateCost counts equal the built instances", function()
					local h = harness()
					local c, comp = h:build(variant.type, variant.props)
					local tagged = h:instancesOf(comp.id)
					local counts = {
						instances = #tagged,
						parts = 0,
						attachments = 0,
						emitters = 0,
						beams = 0,
						trails = 0,
						lights = 0,
						sounds = 0,
					}
					for _, inst in tagged do
						if inst:IsA("BasePart") then
							counts.parts += 1
						elseif inst:IsA("Attachment") then
							counts.attachments += 1
						elseif inst:IsA("ParticleEmitter") then
							counts.emitters += 1
						elseif inst:IsA("Beam") then
							counts.beams += 1
						elseif inst:IsA("Trail") then
							counts.trails += 1
						elseif inst:IsA("Light") then
							counts.lights += 1
						elseif inst:IsA("Sound") then
							counts.sounds += 1
						end
					end
					local cost = descriptor.estimateCost(comp, HIGH)
					T.expect({
						instances = cost.instances,
						parts = cost.parts,
						attachments = cost.attachments,
						emitters = cost.emitters,
						beams = cost.beams,
						trails = cost.trails,
						lights = cost.lights,
						sounds = cost.sounds,
					}).toEqual(counts)
					T.expect(#c.instances).toBe(cost.instances)
					for _, key in { "continuousRate", "burstCount", "maxLifetime", "movingParts", "propertyUpdates" } do
						T.expect(type(cost[key])).toBe("number")
					end
					T.expect(cost.overdrawWeight >= 0).toBe(true)
				end)

				if variant.type ~= "sound" then
					T.it("is disabled until setActive(true) and disabled again by setActive(false)", function()
						local h = harness()
						local c = h:build(variant.type, variant.props)
						local main = c.instances[1]
						T.expect(main.Enabled).toBe(false)
						c:setActive(true, frame(h))
						T.expect(main.Enabled).toBe(true)
						c:setActive(false, frame(h))
						T.expect(main.Enabled).toBe(false)
					end)

					T.it("release() disables gracefully and channels cannot re-enable it until reset()", function()
						local h = harness()
						local c = h:build(variant.type, variant.props)
						local main = c.instances[1]
						c:setActive(true, frame(h))
						c:release()
						T.expect(main.Enabled).toBe(false)
						for _, spec in descriptor.channels do
							c:apply(spec.name, channelValue(spec, 2))
						end
						c:onAction({ action = "enable", source = "event", order = 1, time = 0 }, frame(h))
						T.expect(main.Enabled).toBe(false)
						c:reset()
						c:setActive(true, frame(h))
						T.expect(main.Enabled).toBe(true)
					end)
				end

				T.it(
					"state is a pure function of channel values and transform (history and seed independent)",
					function()
						local h = harness()
						local cfA = CFrame.new(3, 1, -2) * CFrame.Angles(0.3, 0.2, 0.1)
						local cfB = CFrame.new(-1, 4, 2) * CFrame.Angles(0, 1.2, 0)
						local c1 = h:build(variant.type, variant.props, { seed = 1, id = "a" })
						local c2 = h:build(variant.type, variant.props, { seed = 98765, id = "b" })
						local f = frame(h)
						c1:setActive(true, f)
						c2:setActive(true, f)
						-- c1: a long, different history; c2: straight to the final values.
						for _, phase in { 1, 2, 1, 2 } do
							for _, spec in descriptor.channels do
								c1:apply(spec.name, channelValue(spec, phase))
							end
							local cf = if phase == 1 then cfA else cfB
							c1:setTransform(cf, h.root.CFrame * cf, f)
							h:flush(f)
						end
						for _, spec in descriptor.channels do
							c2:apply(spec.name, channelValue(spec, 2))
						end
						c2:setTransform(cfB, h.root.CFrame * cfB, f)
						h:flush(f)
						T.expect(snapshot(c1)).toEqual(snapshot(c2))
					end
				)

				T.it("reset() restores the freshly built state", function()
					local h = harness()
					local c = h:build(variant.type, variant.props)
					local built = snapshot(c)
					local f = frame(h)
					c:setActive(true, f)
					for _, spec in descriptor.channels do
						c:apply(spec.name, channelValue(spec, 2))
					end
					local cf = CFrame.new(4, 5, 6) * CFrame.Angles(0.5, 0, 0)
					c:setTransform(cf, h.root.CFrame * cf, f)
					h:flush(f)
					T.expect(snapshot(c)).never.toEqual(built)
					c:release()
					c:reset()
					T.expect(snapshot(c)).toEqual(built)
				end)

				T.it("caches channel values and transforms: re-applying the same value writes nothing", function()
					local h = harness()
					local c = h:build(variant.type, variant.props)
					local main = c.instances[1] :: any
					local f = frame(h)
					c:setActive(true, f)
					local cf = CFrame.new(1, 2, 3) * CFrame.Angles(0.2, 0.4, 0)
					for _, spec in descriptor.channels do
						c:apply(spec.name, channelValue(spec, 2))
					end
					c:setTransform(cf, h.root.CFrame * cf, f)
					h:flush(f)
					-- Overwrite every written property behind the controller's back ...
					local probes = CACHE_PROBES[variant.type]
					local sentinels = {}
					for channelName, property in probes do
						sentinels[channelName] = sentinelFor(main[property])
						main[property] = sentinels[channelName]
					end
					local attachments = {}
					for _, inst in c.instances do
						if inst:IsA("Attachment") then
							inst.CFrame = CFrame.new(9, 8, 7)
							table.insert(attachments, inst)
						end
					end
					-- ... re-applying identical values must not touch them.
					for _, spec in descriptor.channels do
						c:apply(spec.name, channelValue(spec, 2))
					end
					c:setTransform(cf, h.root.CFrame * cf, f)
					T.expect(#f.moveParts).toBe(0)
					for channelName, property in probes do
						T.expect({ channelName, fmt(main[property]) }).toEqual({
							channelName,
							fmt(sentinels[channelName]),
						})
					end
					for _, a in attachments do
						T.expect(a.CFrame).toBeCloseTo(CFrame.new(9, 8, 7))
					end
				end)

				T.it("after reset() the controller behaves exactly like a freshly built one", function()
					local h = harness()
					local used = h:build(variant.type, variant.props, { id = "used" })
					local fresh = h:build(variant.type, variant.props, { id = "fresh" })
					local f = frame(h)
					used:setActive(true, f)
					for _, phase in { 1, 2 } do
						for _, spec in descriptor.channels do
							used:apply(spec.name, channelValue(spec, phase))
						end
						local cf = CFrame.new(phase, 2 * phase, 0)
						used:setTransform(cf, h.root.CFrame * cf, f)
						h:flush(f)
					end
					used:onAction({ action = "disable", source = "event", order = 1, time = 0 }, f)
					used:release()
					used:reset()
					-- Replay exactly the values and transform used before the reset (a pooled copy replaying the
					-- same effect): stale caches would skip these writes.
					local last = CFrame.new(2, 4, 0)
					for _, c in { used, fresh } do
						c:setActive(true, f)
						for _, spec in descriptor.channels do
							c:apply(spec.name, channelValue(spec, 2))
						end
						c:setTransform(last, h.root.CFrame * last, f)
						h:flush(f)
					end
					T.expect(snapshot(used)).toEqual(snapshot(fresh))
					-- Replay with the same transform but no channel values (authored values only): stale channel
					-- state or a stale transform cache would leak into the replay.
					local h2 = harness()
					local used2 = h2:build(variant.type, variant.props, { id = "used2" })
					local fresh2 = h2:build(variant.type, variant.props, { id = "fresh2" })
					local f2 = frame(h2)
					local x = CFrame.new(1, 2, 3) * CFrame.Angles(0, 0.5, 0)
					used2:setActive(true, f2)
					for _, spec in descriptor.channels do
						used2:apply(spec.name, channelValue(spec, 2))
					end
					used2:setTransform(x, h2.root.CFrame * x, f2)
					h2:flush(f2)
					used2:reset()
					for _, c in { used2, fresh2 } do
						c:setActive(true, f2)
						c:setTransform(x, h2.root.CFrame * x, f2)
						h2:flush(f2)
					end
					T.expect(snapshot(used2)).toEqual(snapshot(fresh2))
				end)

				T.it("ignores unknown channels and mistyped channel values", function()
					local h = harness()
					local c = h:build(variant.type, variant.props)
					local before = snapshot(c)
					T.expect(function()
						c:apply("doesNotExist", 1)
						for _, spec in descriptor.channels do
							c:apply(spec.name, if spec.kind == "number" then "text" else 7)
						end
						c:onAction({ action = "doesNotExist", source = "event", order = 1, time = 0 }, frame(h))
					end).never
						.toThrow()
					T.expect(snapshot(c)).toEqual(before)
				end)

				T.it("destroy() removes every instance it created", function()
					local h = harness()
					local c, comp = h:build(variant.type, variant.props)
					c:setActive(true, frame(h))
					c:destroy()
					T.expect(#h:instancesOf(comp.id)).toBe(0)
					T.expect(#c.instances).toBe(0)
					T.expect(#h.root:GetChildren()).toBe(0)
					T.expect(#h.container:GetChildren()).toBe(1) -- only the harness Root remains
				end)
			end)
		end

		-- ─────────────────────────────────────────────────────────────────────
		-- 3a. particles
		-- ─────────────────────────────────────────────────────────────────────
		T.describe("particles behaviour", function()
			T.it("Point shape: ParticleEmitter inside an Attachment on the Root, no parts", function()
				local h = harness()
				local c, comp = h:build("particles")
				local emitter = c.instances[1]
				T.expect(emitter.ClassName).toBe("ParticleEmitter")
				T.expect(emitter.Parent.ClassName).toBe("Attachment")
				T.expect(emitter.Parent.Parent).toBe(h.root)
				T.expect(firstOfClass(h:instancesOf(comp.id), "BasePart")).toBeNil()
			end)

			T.it(
				"volume shapes: emitter in an invisible host part with Shape set and Size = emitterSize × scale",
				function()
					for _, shape in { "Box", "Sphere", "Cylinder", "Disc" } do
						local h = harness()
						local c = h:build("particles", { shape = shape, emitterSize = { 2, 3, 4 } }, { scale = 2 })
						local emitter = c.instances[1]
						local host = emitter.Parent
						T.expect(host:IsA("BasePart")).toBe(true)
						T.expect(host.Parent).toBe(h.container)
						T.expect(emitter.Shape).toBe((Enum.ParticleEmitterShape :: any)[shape])
						T.expect(host.Size).toBeCloseTo(Vector3.new(4, 6, 8))
						T.expect(host.Transparency).toBe(1)
					end
				end
			)

			T.it("writes every authored property explicitly (ASTRA values over engine defaults)", function()
				local h = harness()
				local c = h:build("particles", {
					texture = "rbxasset://textures/particles/fire_main.dds",
					color = { colorKey(0, "#FF0000"), colorKey(1, "#0000FF") },
					transparency = { { 0, 0.2 }, { 1, 1 } },
					squash = 0.5,
					lifetime = { 0.5, 1.5 },
					rate = 33,
					speed = { 2, 8 },
					spreadAngle = { 15, 30 },
					acceleration = { 0, -10, 0 },
					drag = 2,
					rotation = { -90, 90 },
					rotSpeed = { 10, 20 },
					emissionDirection = "Front",
					shape = "Sphere",
					shapeStyle = "Surface",
					shapeInOut = "Inward",
					shapePartial = 0.5,
					orientation = "VelocityParallel",
					lightEmission = 1,
					lightInfluence = 0.75,
					brightness = 3,
					zOffset = 2,
					timeScale = 0.5,
					lockedToPart = true,
					velocityInheritance = 0.25,
					windAffectsDrag = true,
					flipbookLayout = "Grid4x4",
					flipbookMode = "OneShot",
					flipbookFramerate = { 10, 20 },
					flipbookStartRandom = true,
				})
				local e = c.instances[1]
				T.expect(e.Texture).toBe("rbxasset://textures/particles/fire_main.dds")
				T.expect(e.Color.Keypoints[1].Value).toBeCloseTo(Color3.new(1, 0, 0))
				T.expect(e.Color.Keypoints[2].Value).toBeCloseTo(Color3.new(0, 0, 1))
				T.expect(keypointValues(e.Transparency)[1]).toBeCloseTo(0.2)
				T.expect(keypointValues(e.Squash)[1]).toBeCloseTo(0.5)
				T.expect(e.Lifetime.Min).toBeCloseTo(0.5)
				T.expect(e.Lifetime.Max).toBeCloseTo(1.5)
				T.expect(e.Rate).toBe(33)
				T.expect(e.Speed.Min).toBeCloseTo(2)
				T.expect(e.Speed.Max).toBeCloseTo(8)
				T.expect(e.SpreadAngle).toBeCloseTo(Vector2.new(15, 30))
				T.expect(e.Acceleration).toBeCloseTo(Vector3.new(0, -10, 0))
				T.expect(e.Drag).toBe(2)
				T.expect(e.Rotation.Min).toBeCloseTo(-90)
				T.expect(e.RotSpeed.Max).toBeCloseTo(20)
				T.expect(e.EmissionDirection).toBe(Enum.NormalId.Front)
				T.expect(e.Shape).toBe(Enum.ParticleEmitterShape.Sphere)
				T.expect(e.ShapeStyle).toBe(Enum.ParticleEmitterShapeStyle.Surface)
				T.expect(e.ShapeInOut).toBe(Enum.ParticleEmitterShapeInOut.Inward)
				T.expect(e.ShapePartial).toBeCloseTo(0.5)
				T.expect(e.Orientation).toBe(Enum.ParticleOrientation.VelocityParallel)
				T.expect(e.LightEmission).toBe(1)
				T.expect(e.LightInfluence).toBeCloseTo(0.75)
				T.expect(e.Brightness).toBe(3)
				T.expect(e.ZOffset).toBe(2)
				T.expect(e.TimeScale).toBeCloseTo(0.5)
				T.expect(e.LockedToPart).toBe(true)
				T.expect(e.VelocityInheritance).toBeCloseTo(0.25)
				T.expect(e.WindAffectsDrag).toBe(true)
				T.expect(e.FlipbookLayout).toBe(Enum.ParticleFlipbookLayout.Grid4x4)
				T.expect(e.FlipbookMode).toBe(Enum.ParticleFlipbookMode.OneShot)
				T.expect(e.FlipbookFramerate.Min).toBeCloseTo(10)
				T.expect(e.FlipbookStartRandom).toBe(true)
			end)

			T.it("defaults override engine defaults (Lifetime 1..2 instead of 5..10, LightInfluence 0)", function()
				local h = harness()
				local e = h:build("particles").instances[1]
				T.expect(e.Lifetime.Min).toBeCloseTo(1)
				T.expect(e.Lifetime.Max).toBeCloseTo(2)
				T.expect(e.LightInfluence).toBe(0)
				T.expect(e.Rate).toBe(20)
				T.expect(e.Texture).toBe("rbxasset://textures/particles/sparkles_main.dds")
			end)

			T.it("Size = size × scale × quality.sizeCompensation (build, scale channel, host part)", function()
				local h = harness()
				local c = h:build("particles", { size = { { 0, 2 }, { 1, 4, 1 } }, shape = "Box" }, {
					scale = 2,
					quality = LOW,
				})
				local e = c.instances[1]
				T.expect(keypointValues(e.Size)[1]).toBeCloseTo(6)
				T.expect(keypointValues(e.Size)[2]).toBeCloseTo(12)
				T.expect(e.Size.Keypoints[2].Envelope).toBeCloseTo(3)
				T.expect(e.Parent.Size).toBeCloseTo(Vector3.new(2, 2, 2))
				c:apply("scale", 3)
				T.expect(keypointValues(e.Size)[1]).toBeCloseTo(9)
				T.expect(e.Parent.Size).toBeCloseTo(Vector3.new(3, 3, 3))
				c:apply("scale", -1)
				T.expect(keypointValues(e.Size)[1]).toBeCloseTo(0)
			end)

			T.it(
				"rate 0: Enabled stays false while active (bursts only); the rate channel turns emission on",
				function()
					local h = harness()
					local c = h:build("particles", { rate = 0 })
					local e = c.instances[1]
					c:setActive(true, frame(h))
					T.expect(e.Enabled).toBe(false)
					c:apply("rate", 10)
					T.expect(e.Enabled).toBe(true)
					T.expect(e.Rate).toBe(10)
					c:apply("rate", 0)
					T.expect(e.Enabled).toBe(false)
				end
			)

			-- The channel shares the compiled domain of its baseProperty `rate` (already × countScale), so values are
			-- written as given (see ComponentsReview.spec: applying the rest value must not change the built Rate).
			T.it("rate channel values are written as given and clamped to the 400/s engine cap", function()
				local h = harness()
				local c = h:build("particles", nil, { quality = LOW })
				local e = c.instances[1]
				c:apply("rate", 100)
				T.expect(e.Rate).toBe(100)
				c:apply("rate", 5000)
				T.expect(e.Rate).toBe(Constants.MAX_PARTICLE_RATE)
				c:apply("rate", -5)
				T.expect(e.Rate).toBe(0)
			end)

			T.itIf(isLune, "emits `burst` once on activation, never while seeking", function()
				local h = harness()
				local c = h:build("particles", { burst = 40 })
				local e = c.instances[1]
				T.expect(#emitCalls(e)).toBe(0)
				c:setActive(true, frame(h))
				T.expect(emitCalls(e)).toEqual({ 40 })
				c:setActive(true, frame(h)) -- already active: no second burst
				T.expect(emitCalls(e)).toEqual({ 40 })
				c:setActive(false, frame(h))
				c:setActive(true, frame(h, true))
				T.expect(emitCalls(e)).toEqual({ 40 })
				-- Seek = no emission at all: continuous emission stays off until the next playback frame.
				T.expect(e.Enabled).toBe(false)
				c:setTransform(CFrame.new(), CFrame.new(), frame(h))
				T.expect(e.Enabled).toBe(true)
				T.expect(emitCalls(e)).toEqual({ 40 })
			end)

			T.itIf(isLune, "burst 0 never calls Emit", function()
				local h = harness()
				local c = h:build("particles")
				c:setActive(true, frame(h))
				T.expect(#emitCalls(c.instances[1])).toBe(0)
			end)

			T.itIf(
				isLune,
				"emit events call Emit(count) (default 16 × countScale), clamped, skipped while seeking",
				function()
					local h = harness()
					local c = h:build("particles")
					local e = c.instances[1]
					c:setActive(true, frame(h))
					c:onAction({ action = "emit", count = 25, source = "event", order = 1, time = 0 }, frame(h))
					c:onAction({ action = "emit", source = "event", order = 2, time = 0 }, frame(h))
					c:onAction({ action = "emit", count = 99999, source = "event", order = 3, time = 0 }, frame(h))
					c:onAction({ action = "emit", count = 0, source = "event", order = 4, time = 0 }, frame(h))
					c:onAction({ action = "emit", count = 5, source = "event", order = 5, time = 0 }, frame(h, true))
					T.expect(emitCalls(e)).toEqual({ 25, 16, Constants.MAX_EMIT_COUNT })

					local h2 = harness()
					local low = h2:build("particles", nil, { quality = LOW })
					low:onAction({ action = "emit", source = "event", order = 1, time = 0 }, frame(h2))
					T.expect(emitCalls(low.instances[1])).toEqual({ 8 })
				end
			)

			T.itIf(isLune, "release(): no more Emit, live particles finish (no Clear)", function()
				local h = harness()
				local c = h:build("particles", { burst = 5 })
				local e = c.instances[1]
				c:setActive(true, frame(h))
				c:release()
				T.expect(e.Enabled).toBe(false)
				c:onAction({ action = "emit", count = 10, source = "event", order = 1, time = 0 }, frame(h))
				T.expect(emitCalls(e)).toEqual({ 5 })
				T.expect(clearsOf(e)).toBe(0)
			end)

			T.itIf(isLune, "clear event calls Clear(); reset() clears too", function()
				local h = harness()
				local c = h:build("particles")
				local e = c.instances[1]
				c:onAction({ action = "clear", source = "event", order = 1, time = 0 }, frame(h))
				T.expect(clearsOf(e)).toBe(1)
				c:reset()
				T.expect(clearsOf(e)).toBe(2)
			end)

			T.it("enable / disable events gate continuous emission while active", function()
				local h = harness()
				local c = h:build("particles")
				local e = c.instances[1]
				c:onAction({ action = "disable", source = "event", order = 1, time = 0 }, frame(h))
				c:setActive(true, frame(h))
				T.expect(e.Enabled).toBe(false)
				c:onAction({ action = "enable", source = "event", order = 2, time = 0 }, frame(h))
				T.expect(e.Enabled).toBe(true)
				c:setActive(false, frame(h))
				c:onAction({ action = "enable", source = "event", order = 3, time = 0 }, frame(h))
				T.expect(e.Enabled).toBe(false) -- inactive components never emit
			end)

			T.it("transparency channel fades the authored sequence and rebuilds only when the value changes", function()
				local h = harness()
				local c = h:build("particles", { transparency = { { 0, 0.2 }, { 1, 0.6 } } })
				local e = c.instances[1]
				c:apply("transparency", 0.5)
				T.expect(keypointValues(e.Transparency)[1]).toBeCloseTo(0.6) -- 1 - 0.8 × 0.5
				T.expect(keypointValues(e.Transparency)[2]).toBeCloseTo(0.8) -- 1 - 0.4 × 0.5
				local sentinel = NumberSequence.new(0.123)
				e.Transparency = sentinel
				c:apply("transparency", 0.5)
				T.expect(keypointValues(e.Transparency)[1]).toBeCloseTo(0.123) -- cached: no write
				c:apply("transparency", 0)
				T.expect(keypointValues(e.Transparency)).toEqual(keypointValues(NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.2),
					NumberSequenceKeypoint.new(1, 0.6),
				})))
				c:apply("transparency", 3)
				T.expect(keypointValues(e.Transparency)[1]).toBeCloseTo(1)
			end)

			T.it("tint channel multiplies the colour sequence and rebuilds only when the value changes", function()
				local h = harness()
				local c = h:build("particles", { color = { colorKey(0, "#FFFFFF"), colorKey(1, "#808080") } })
				local e = c.instances[1]
				c:apply("tint", Color3.new(1, 0, 0.5))
				T.expect(e.Color.Keypoints[1].Value).toBeCloseTo(Color3.new(1, 0, 0.5))
				T.expect(e.Color.Keypoints[2].Value).toBeCloseTo(Color3.new(128 / 255, 0, 64 / 255))
				e.Color = ColorSequence.new(Color3.new(0, 1, 0))
				c:apply("tint", Color3.new(1, 0, 0.5))
				T.expect(e.Color.Keypoints[1].Value).toBeCloseTo(Color3.new(0, 1, 0)) -- cached: no write
				c:apply("tint", Color3.new(1, 1, 1))
				T.expect(e.Color.Keypoints[2].Value).toBeCloseTo(Color3.fromRGB(128, 128, 128))
			end)

			T.it("brightness, lightEmission and acceleration channels write the emitter (clamped)", function()
				local h = harness()
				local c = h:build("particles")
				local e = c.instances[1]
				c:apply("brightness", 7)
				c:apply("lightEmission", 0.4)
				c:apply("acceleration", Vector3.new(0, -50, 3))
				T.expect(e.Brightness).toBe(7)
				T.expect(e.LightEmission).toBeCloseTo(0.4)
				T.expect(e.Acceleration).toBeCloseTo(Vector3.new(0, -50, 3))
				c:apply("brightness", 500)
				c:apply("lightEmission", 2)
				T.expect(e.Brightness).toBe(100)
				T.expect(e.LightEmission).toBe(1)
			end)

			T.it("TimeScale = clamp(clamp(timeScale, 0, 1) × effect time scale, 0, 1)", function()
				local h = harness()
				local slow = buildWith(h, "particles", { timeScale = 0.8 }, nil, function(_comp: any, bctx: any)
					bctx.effect.timeScale = 0.5
				end)
				local e = slow.instances[1]
				T.expect(e.TimeScale).toBeCloseTo(0.4)
				slow:apply("timeScale", 2)
				T.expect(e.TimeScale).toBeCloseTo(0.5)
				slow:apply("timeScale", 0.2)
				T.expect(e.TimeScale).toBeCloseTo(0.1)
				-- the engine range ends at 1: fast motion cannot speed particles up beyond normal speed
				local fast = buildWith(h, "particles", { timeScale = 0.8 }, { id = "fast" }, function(_c: any, b: any)
					b.effect.timeScale = 3
				end)
				T.expect(fast.instances[1].TimeScale).toBeCloseTo(1)
				local half = buildWith(h, "particles", { timeScale = 0.25 }, { id = "half" }, function(_c: any, b: any)
					b.effect.timeScale = 2
				end)
				T.expect(half.instances[1].TimeScale).toBeCloseTo(0.5)
			end)

			T.it(
				"setTimeScale(s) rescales TimeScale (authored × s, clamped to 0..1); reset restores the build",
				function()
					local h = harness()
					local c = buildWith(h, "particles", { timeScale = 0.8 }, nil, function(_comp: any, bctx: any)
						bctx.effect.timeScale = 0.5
					end)
					local e = c.instances[1]
					T.expect(type(c.setTimeScale)).toBe("function")
					c:setTimeScale(0.25)
					T.expect(e.TimeScale).toBeCloseTo(0.2)
					c:setTimeScale(0) -- paused: the engine freezes the particles
					T.expect(e.TimeScale).toBe(0)
					c:setTimeScale(4)
					T.expect(e.TimeScale).toBeCloseTo(1)
					c:apply("timeScale", 0.1) -- the channel keeps the current scale
					T.expect(e.TimeScale).toBeCloseTo(0.4)
					c:setTimeScale(1)
					T.expect(e.TimeScale).toBeCloseTo(0.1)
					for _, bad in { -1, 0 / 0, math.huge } do
						c:setTimeScale(bad) -- ignored: negative, NaN and infinite scales leave the emitter alone
						T.expect(e.TimeScale).toBeCloseTo(0.1)
					end
					c:reset() -- the freshly built state: authored timeScale × the definition's timeScale
					T.expect(e.TimeScale).toBeCloseTo(0.4)
					c:setTimeScale(0.5)
					T.expect(e.TimeScale).toBeCloseTo(0.4)
				end
			)

			T.it("Point: setTransform writes the attachment CFrame (relative to Root), never moveParts", function()
				local h = harness()
				local c = h:build("particles")
				local f = frame(h)
				local cf = CFrame.new(1, 2, 3) * CFrame.Angles(0, math.pi / 2, 0)
				c:setTransform(cf, h.root.CFrame * cf, f)
				T.expect(#f.moveParts).toBe(0)
				T.expect(c.instances[1].Parent.CFrame).toBeCloseTo(cf)
			end)

			T.it("volume: setTransform batches the host part through moveParts and skips unchanged CFrames", function()
				local h = harness()
				h.root.CFrame = CFrame.new(100, 0, 0)
				local c = h:build("particles", { shape = "Cylinder" })
				local host = c.instances[1].Parent
				local f = frame(h)
				local cf = CFrame.new(1, 2, 3)
				c:setTransform(cf, h.root.CFrame * cf, f)
				T.expect(f.moveParts).toEqual({ host })
				T.expect(f.moveCFrames[1]).toBeCloseTo(CFrame.new(101, 2, 3))
				h:flush(f)
				T.expect(host.CFrame).toBeCloseTo(CFrame.new(101, 2, 3))
				c:setTransform(cf, h.root.CFrame * cf, f)
				T.expect(#f.moveParts).toBe(0)
			end)

			T.it(
				"tailTime = lifetime.Max; cost reports rate, bursts (+ emit events), lifetime and moving parts",
				function()
					local h = harness()
					local d = Components.get("particles")
					local comp = h:compile(
						"particles",
						{ lifetime = { 0.5, 3 }, rate = 50, burst = 10, shape = "Box" },
						{
							tracks = { position = {}, transparency = {} },
						}
					)
					comp.events = {
						{ id = "e1", time = 0.1, action = "emit", count = 30 },
						{ id = "e2", time = 0.2, action = "emit" },
						{ id = "e3", time = 0.3, action = "clear" },
					} :: { any }
					T.expect(d.tailTime(comp)).toBeCloseTo(3)
					local cost = d.estimateCost(comp, HIGH)
					T.expect(cost.continuousRate).toBe(50)
					T.expect(cost.burstCount).toBe(10 + 30 + 16)
					T.expect(cost.maxLifetime).toBeCloseTo(3)
					T.expect(cost.movingParts).toBe(1)
					T.expect(cost.propertyUpdates).toBe(1)
					T.expect(cost.overdrawWeight).toBeGreaterThan(0)
					local still = d.estimateCost(h:compile("particles"), HIGH)
					T.expect(still.movingParts).toBe(0)
					T.expect(still.propertyUpdates).toBe(0)
				end
			)

			T.it("cost notes flag mobile rate caps and flipbooks", function()
				local h = harness()
				local d = Components.get("particles")
				T.expect(d.estimateCost(h:compile("particles"), HIGH).notes).toBeNil()
				local cost = d.estimateCost(h:compile("particles", { rate = 200, flipbookLayout = "Grid2x2" }), HIGH)
				T.expect(cost.notes).toHaveLength(2)
			end)
		end)

		-- ─────────────────────────────────────────────────────────────────────
		-- 3b. beam
		-- ─────────────────────────────────────────────────────────────────────
		T.describe("beam behaviour", function()
			local function beamParts(c: any): (any, any, any)
				return c.instances[1], c.instances[2], c.instances[3]
			end

			local function assertOrthonormal(cf: CFrame)
				T.expect(cf.RightVector.Magnitude).toBeCloseTo(1, 1e-4)
				T.expect(cf.UpVector.Magnitude).toBeCloseTo(1, 1e-4)
				T.expect(cf.RightVector:Dot(cf.UpVector)).toBeCloseTo(0, 1e-4)
				T.expect(cf.RightVector:Dot(cf.LookVector)).toBeCloseTo(0, 1e-4)
				T.expect(cf.Position.X == cf.Position.X).toBe(true) -- not NaN
			end

			T.it("Beam parented to the Root with Attachment0/1 on the Root", function()
				local h = harness()
				local c = h:build("beam")
				local beam, a0, a1 = beamParts(c)
				T.expect(beam.ClassName).toBe("Beam")
				T.expect(beam.Parent).toBe(h.root)
				T.expect(a0.Parent).toBe(h.root)
				T.expect(a1.Parent).toBe(h.root)
				T.expect(beam.Attachment0).toBe(a0)
				T.expect(beam.Attachment1).toBe(a1)
			end)

			T.it("writes authored properties (Transparency 0 and FaceCamera true over engine defaults)", function()
				local h = harness()
				local beam = h:build("beam").instances[1]
				T.expect(keypointValues(beam.Transparency)).toEqual({ 0, 0 })
				T.expect(beam.FaceCamera).toBe(true)
				T.expect(beam.Segments).toBe(10)
				local h2 = harness()
				local b = h2:build("beam", {
					texture = "rbxasset://textures/particles/sparkles_main.dds",
					width0 = 2,
					width1 = 0.5,
					curveSize0 = 3,
					curveSize1 = -1,
					segments = 24,
					textureLength = 4,
					textureMode = "Wrap",
					textureSpeed = -2,
					faceCamera = false,
					lightEmission = 1,
					lightInfluence = 0.5,
					brightness = 5,
					zOffset = 0.25,
				}).instances[1]
				T.expect(b.Texture).toBe("rbxasset://textures/particles/sparkles_main.dds")
				T.expect(b.Width0).toBe(2)
				T.expect(b.Width1).toBe(0.5)
				T.expect(b.CurveSize0).toBe(3)
				T.expect(b.CurveSize1).toBe(-1)
				T.expect(b.Segments).toBe(24)
				T.expect(b.TextureLength).toBe(4)
				T.expect(b.TextureMode).toBe(Enum.TextureMode.Wrap)
				T.expect(b.TextureSpeed).toBe(-2)
				T.expect(b.FaceCamera).toBe(false)
				T.expect(b.LightEmission).toBe(1)
				T.expect(b.LightInfluence).toBe(0.5)
				T.expect(b.Brightness).toBe(5)
				T.expect(b.ZOffset).toBe(0.25)
			end)

			T.it("A0 +X = curveDirection, A1 +X = −curveDirection at from/to; both share the up axis", function()
				local h = harness()
				local _, a0, a1 = beamParts(h:build("beam"))
				T.expect(a0.CFrame.Position).toBeCloseTo(Vector3.new(0, 0, 0))
				T.expect(a1.CFrame.Position).toBeCloseTo(Vector3.new(0, 0, -10))
				T.expect(a0.CFrame.RightVector).toBeCloseTo(Vector3.new(0, 1, 0))
				T.expect(a1.CFrame.RightVector).toBeCloseTo(Vector3.new(0, -1, 0))
				T.expect(a0.CFrame.UpVector).toBeCloseTo(a1.CFrame.UpVector)
				-- The attachments face each other: A0 looks along the beam (from → to), A1 looks back.
				T.expect(a0.CFrame.LookVector).toBeCloseTo(Vector3.new(0, 0, -1))
				T.expect(a1.CFrame.LookVector).toBeCloseTo(Vector3.new(0, 0, 1))
				assertOrthonormal(a0.CFrame)
				assertOrthonormal(a1.CFrame)
			end)

			T.it("Bézier handles arch towards curveDirection for positive curve sizes", function()
				local h = harness()
				local beam, a0, a1 = beamParts(h:build("beam", { curveSize0 = 4, curveSize1 = 4 }))
				-- Engine: P1 = A0 + A0.Axis·CurveSize0, P2 = A1 − A1.Axis·CurveSize1 (Axis = +X).
				local p1 = a0.CFrame.Position + a0.CFrame.RightVector * beam.CurveSize0
				local p2 = a1.CFrame.Position - a1.CFrame.RightVector * beam.CurveSize1
				T.expect(p1).toBeCloseTo(Vector3.new(0, 4, 0))
				T.expect(p2).toBeCloseTo(Vector3.new(0, 4, -10))
			end)

			T.it("non-unit or oblique curveDirection is normalised; frames stay orthonormal", function()
				local h = harness()
				local _, a0 = beamParts(h:build("beam", { curveDirection = { 0, 5, 0 } }))
				T.expect(a0.CFrame.RightVector).toBeCloseTo(Vector3.new(0, 1, 0))
				local h2 = harness()
				local _, b0, b1 = beamParts(h2:build("beam", { curveDirection = { 0, 1, -1 } }))
				T.expect(b0.CFrame.RightVector).toBeCloseTo(Vector3.new(0, 1, -1).Unit)
				T.expect(b1.CFrame.RightVector).toBeCloseTo(-Vector3.new(0, 1, -1).Unit)
				assertOrthonormal(b0.CFrame)
				assertOrthonormal(b1.CFrame)
			end)

			T.it(
				"curveDirection parallel to the beam axis, zero direction or zero length still yield valid frames",
				function()
					local cases: { any } = {
						{ curveDirection = { 0, 0, -1 } },
						{ curveDirection = { 0, 0, 0 } },
						{ from = { 1, 1, 1 }, to = { 1, 1, 1 } },
						{ curveDirection = { 0, 1, 0 }, from = { 0, 0, 0 }, to = { 0, 10, 0 } },
					}
					for _, props in cases do
						local h = harness()
						local _, a0, a1 = beamParts(h:build("beam", props))
						assertOrthonormal(a0.CFrame)
						assertOrthonormal(a1.CFrame)
						T.expect(a0.CFrame.RightVector).toBeCloseTo(-a1.CFrame.RightVector)
					end
				end
			)

			T.it("roll rotates both attachments about the beam axis", function()
				local h = harness()
				local _, a0, a1 = beamParts(h:build("beam", { roll = 90 }))
				-- Axis d = (0, 0, -1); rotating +X = (0, 1, 0) by +90° about d gives (1, 0, 0).
				T.expect(a0.CFrame.RightVector).toBeCloseTo(Vector3.new(1, 0, 0))
				T.expect(a1.CFrame.RightVector).toBeCloseTo(Vector3.new(-1, 0, 0))
				T.expect(a0.CFrame.UpVector).toBeCloseTo(a1.CFrame.UpVector)
				T.expect(a0.CFrame.Position).toBeCloseTo(Vector3.new(0, 0, 0))
				T.expect(a1.CFrame.Position).toBeCloseTo(Vector3.new(0, 0, -10))
				-- The axis itself is unaffected: the ribbon plane turns, the beam line does not move.
				local h2 = harness()
				local _, r0 = beamParts(h2:build("beam", { roll = 0 }))
				T.expect(a0.CFrame.UpVector:Dot(Vector3.new(0, 0, -1)))
					.toBeCloseTo(r0.CFrame.UpVector:Dot(Vector3.new(0, 0, -1)))
			end)

			T.it("transform composes: A = component localCFrame × from / to", function()
				local h = harness()
				local c = h:build("beam", { from = { 0, 1, 0 }, to = { 0, 1, -6 } })
				local _, a0, a1 = beamParts(c)
				local cf = CFrame.new(5, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
				local f = frame(h)
				c:setTransform(cf, h.root.CFrame * cf, f)
				T.expect(#f.moveParts).toBe(0)
				T.expect(a0.CFrame.Position).toBeCloseTo(cf * Vector3.new(0, 1, 0))
				T.expect(a1.CFrame.Position).toBeCloseTo(cf * Vector3.new(0, 1, -6))
				T.expect(a1.CFrame.Position).toBeCloseTo(Vector3.new(-1, 1, 0))
				T.expect(a0.CFrame.RightVector).toBeCloseTo(cf:VectorToWorldSpace(Vector3.new(0, 1, 0)))
			end)

			T.it("moving only one end rewrites only that attachment", function()
				local h = harness()
				local c = h:build("beam")
				local _, a0, a1 = c.instances[1], c.instances[2], c.instances[3]
				a0.CFrame = CFrame.new(9, 8, 7) -- sentinel: A0 keeps its frame when `to` moves along the axis
				c:apply("to", Vector3.new(0, 0, -20))
				T.expect(a0.CFrame).toBeCloseTo(CFrame.new(9, 8, 7))
				T.expect(a1.CFrame.Position).toBeCloseTo(Vector3.new(0, 0, -20))
			end)

			T.it("from / to channels move the attachments and re-orient them", function()
				local h = harness()
				local c = h:build("beam")
				local _, a0, a1 = beamParts(c)
				c:apply("from", Vector3.new(2, 0, 0))
				c:apply("to", Vector3.new(2, 0, -4))
				T.expect(a0.CFrame.Position).toBeCloseTo(Vector3.new(2, 0, 0))
				T.expect(a1.CFrame.Position).toBeCloseTo(Vector3.new(2, 0, -4))
				c:apply("to", Vector3.new(6, 0, 0)) -- axis now +X, curveDirection +Y stays the attachment +X
				T.expect(a0.CFrame.RightVector).toBeCloseTo(Vector3.new(0, 1, 0))
				T.expect(a0.CFrame.UpVector:Dot(Vector3.new(1, 0, 0))).toBeCloseTo(0)
			end)

			T.it(
				"width channels × scale channel; curve sizes, brightness and textureSpeed × effect time scale",
				function()
					local h = harness()
					local c = buildWith(
						h,
						"beam",
						{ width0 = 2, width1 = 1, textureSpeed = 2 },
						{ scale = 2 },
						function(_comp: any, bctx: any)
							bctx.effect.timeScale = 0.5
						end
					)
					local beam = c.instances[1]
					T.expect(beam.Width0).toBe(4)
					T.expect(beam.Width1).toBe(2)
					T.expect(beam.TextureSpeed).toBe(1)
					c:apply("scale", 3)
					T.expect(beam.Width0).toBe(6)
					T.expect(beam.Width1).toBe(3)
					c:apply("width0", 0.5)
					c:apply("width1", -2)
					T.expect(beam.Width0).toBe(1.5)
					T.expect(beam.Width1).toBe(0)
					c:apply("curveSize0", 7)
					c:apply("curveSize1", -3)
					T.expect(beam.CurveSize0).toBe(7)
					T.expect(beam.CurveSize1).toBe(-3)
					c:apply("brightness", 8)
					T.expect(beam.Brightness).toBe(8)
					c:apply("textureSpeed", -4)
					T.expect(beam.TextureSpeed).toBe(-2)
				end
			)

			T.it("setTimeScale(s) rescales TextureSpeed (authored × s); reset restores the build", function()
				local h = harness()
				local c = buildWith(h, "beam", { textureSpeed = 2 }, nil, function(_comp: any, bctx: any)
					bctx.effect.timeScale = 0.5
				end)
				local beam = c.instances[1]
				T.expect(beam.TextureSpeed).toBe(1)
				T.expect(type(c.setTimeScale)).toBe("function")
				c:setTimeScale(3) -- beams have no engine time factor, so fast motion works too
				T.expect(beam.TextureSpeed).toBe(6)
				c:apply("textureSpeed", -1)
				T.expect(beam.TextureSpeed).toBe(-3)
				c:setTimeScale(0) -- paused: the texture stops scrolling
				T.expect(beam.TextureSpeed).toBe(0)
				c:setTimeScale(-2)
				T.expect(beam.TextureSpeed).toBe(0)
				c:reset()
				T.expect(beam.TextureSpeed).toBe(1)
			end)

			T.it("transparency fade and tint rebuild the sequences only when the value changes", function()
				local h = harness()
				local c = h:build("beam", { transparency = 0.5, color = "#FF8000" })
				local beam = c.instances[1]
				c:apply("transparency", 0.5)
				T.expect(keypointValues(beam.Transparency)[1]).toBeCloseTo(0.75)
				beam.Transparency = NumberSequence.new(0.1)
				c:apply("transparency", 0.5)
				T.expect(keypointValues(beam.Transparency)[1]).toBeCloseTo(0.1)
				c:apply("tint", Color3.new(0, 1, 1))
				T.expect(beam.Color.Keypoints[1].Value).toBeCloseTo(Color3.new(0, 128 / 255, 0))
			end)

			T.it("enable / disable events; release hides the beam", function()
				local h = harness()
				local c = h:build("beam")
				local beam = c.instances[1]
				c:setActive(true, frame(h))
				c:onAction({ action = "disable", source = "event", order = 1, time = 0 }, frame(h))
				T.expect(beam.Enabled).toBe(false)
				c:onAction({ action = "enable", source = "event", order = 2, time = 0 }, frame(h))
				T.expect(beam.Enabled).toBe(true)
				c:release()
				T.expect(beam.Enabled).toBe(false)
			end)

			T.it("cost: 2 attachments + 1 beam; transform tracks rewrite both attachments", function()
				local h = harness()
				local d = Components.get("beam")
				local still = d.estimateCost(h:compile("beam"), HIGH)
				T.expect(still.propertyUpdates).toBe(0)
				T.expect(still.movingParts).toBe(0)
				T.expect(still.overdrawWeight).toBeCloseTo(10)
				local moving = d.estimateCost(h:compile("beam", nil, { tracks = { rotation = {}, width0 = {} } }), HIGH)
				T.expect(moving.propertyUpdates).toBe(3)
				T.expect(d.tailTime).toBeNil()
			end)
		end)

		-- ─────────────────────────────────────────────────────────────────────
		-- 3c. trail
		-- ─────────────────────────────────────────────────────────────────────
		T.describe("trail behaviour", function()
			T.it("Trail parented to the Root; attachments at ±width/2 along widthDirection", function()
				local h = harness()
				local c = h:build("trail")
				local trail, a0, a1 = c.instances[1], c.instances[2], c.instances[3]
				T.expect(trail.ClassName).toBe("Trail")
				T.expect(trail.Parent).toBe(h.root)
				T.expect(trail.Attachment0).toBe(a0)
				T.expect(trail.Attachment1).toBe(a1)
				T.expect(a0.Parent).toBe(h.root)
				T.expect(a0.CFrame.Position).toBeCloseTo(Vector3.new(0, -0.5, 0))
				T.expect(a1.CFrame.Position).toBeCloseTo(Vector3.new(0, 0.5, 0))
				local h2 = harness()
				local c2 = h2:build("trail", { width = 4, widthDirection = { 2, 0, 0 } }, { scale = 0.5 })
				T.expect(c2.instances[2].CFrame.Position).toBeCloseTo(Vector3.new(-1, 0, 0))
				T.expect(c2.instances[3].CFrame.Position).toBeCloseTo(Vector3.new(1, 0, 0))
			end)

			T.it("writes authored properties (Transparency 0 over the engine's 0.5, Lifetime, lengths)", function()
				local h = harness()
				local trail = h:build("trail", {
					lifetime = 1.25,
					minLength = 0.3,
					maxLength = 40,
					widthScale = { { 0, 1 }, { 1, 0 } },
					color = "#00FF00",
					texture = "rbxasset://textures/particles/sparkles_main.dds",
					textureLength = 3,
					textureMode = "Static",
					faceCamera = true,
					lightEmission = 0.5,
					lightInfluence = 1,
					brightness = 4,
				}).instances[1]
				T.expect(keypointValues(trail.Transparency)).toEqual({ 0, 0 })
				T.expect(trail.Lifetime).toBeCloseTo(1.25)
				T.expect(trail.MinLength).toBeCloseTo(0.3)
				T.expect(trail.MaxLength).toBe(40)
				T.expect(keypointValues(trail.WidthScale)).toEqual({ 1, 0 })
				T.expect(trail.Color.Keypoints[1].Value).toBeCloseTo(Color3.new(0, 1, 0))
				T.expect(trail.Texture).toBe("rbxasset://textures/particles/sparkles_main.dds")
				T.expect(trail.TextureLength).toBe(3)
				T.expect(trail.TextureMode).toBe(Enum.TextureMode.Static)
				T.expect(trail.FaceCamera).toBe(true)
				T.expect(trail.LightEmission).toBe(0.5)
				T.expect(trail.LightInfluence).toBe(1)
				T.expect(trail.Brightness).toBe(4)
			end)

			T.it("setTransform composes the component transform and never re-assigns the attachments", function()
				local h = harness()
				local c = h:build("trail", { width = 2 })
				local trail, a0, a1 = c.instances[1], c.instances[2], c.instances[3]
				local f = frame(h)
				for i = 1, 5 do
					local cf = CFrame.new(i, 0, -i) * CFrame.Angles(0, 0, math.pi / 2)
					c:setTransform(cf, h.root.CFrame * cf, f)
					T.expect(a0.CFrame.Position).toBeCloseTo(cf * Vector3.new(0, -1, 0))
					T.expect(a1.CFrame.Position).toBeCloseTo(cf * Vector3.new(0, 1, 0))
				end
				T.expect(#f.moveParts).toBe(0)
				T.expect(trail.Attachment0).toBe(a0)
				T.expect(trail.Attachment1).toBe(a1)
			end)

			T.it("width channel × scale channel set the attachment separation", function()
				local h = harness()
				local c = h:build("trail")
				local a0, a1 = c.instances[2], c.instances[3]
				c:apply("width", 3)
				T.expect((a1.CFrame.Position - a0.CFrame.Position).Magnitude).toBeCloseTo(3)
				c:apply("scale", 2)
				T.expect((a1.CFrame.Position - a0.CFrame.Position).Magnitude).toBeCloseTo(6)
				c:apply("width", -1)
				T.expect((a1.CFrame.Position - a0.CFrame.Position).Magnitude).toBeCloseTo(0)
			end)

			T.it("transparency fade, tint and brightness channels", function()
				local h = harness()
				local c = h:build("trail", { transparency = { { 0, 0 }, { 1, 1 } } })
				local trail = c.instances[1]
				c:apply("transparency", 0.25)
				T.expect(keypointValues(trail.Transparency)[1]).toBeCloseTo(0.25)
				T.expect(keypointValues(trail.Transparency)[2]).toBeCloseTo(1)
				c:apply("tint", Color3.new(0.5, 0.5, 0.5))
				T.expect(trail.Color.Keypoints[1].Value).toBeCloseTo(Color3.new(0.5, 0.5, 0.5))
				c:apply("brightness", 9)
				T.expect(trail.Brightness).toBe(9)
			end)

			T.itIf(isLune, "clearOnStart: Clear() on activation and once more after the first transform", function()
				local h = harness()
				local c = h:build("trail")
				local trail = c.instances[1]
				local f = frame(h)
				c:setActive(true, f)
				T.expect(clearsOf(trail)).toBe(1)
				c:setTransform(CFrame.new(5, 0, 0), h.root.CFrame * CFrame.new(5, 0, 0), f)
				T.expect(clearsOf(trail)).toBe(2)
				c:setTransform(CFrame.new(6, 0, 0), h.root.CFrame * CFrame.new(6, 0, 0), f)
				T.expect(clearsOf(trail)).toBe(2)
				c:setActive(false, f)
				c:setTransform(CFrame.new(7, 0, 0), h.root.CFrame * CFrame.new(7, 0, 0), f)
				T.expect(clearsOf(trail)).toBe(2)
			end)

			T.itIf(isLune, "clearOnStart = false keeps drawn segments; the clear event always clears", function()
				local h = harness()
				local c = h:build("trail", { clearOnStart = false })
				local trail = c.instances[1]
				local f = frame(h)
				c:setActive(true, f)
				c:setTransform(CFrame.new(5, 0, 0), h.root.CFrame * CFrame.new(5, 0, 0), f)
				T.expect(clearsOf(trail)).toBe(0)
				c:onAction({ action = "clear", source = "event", order = 1, time = 0 }, f)
				T.expect(clearsOf(trail)).toBe(1)
			end)

			T.it("enable / disable events; release stops drawing (segments fade out)", function()
				local h = harness()
				local c = h:build("trail")
				local trail = c.instances[1]
				c:setActive(true, frame(h))
				T.expect(trail.Enabled).toBe(true)
				c:onAction({ action = "disable", source = "event", order = 1, time = 0 }, frame(h))
				T.expect(trail.Enabled).toBe(false)
				c:onAction({ action = "enable", source = "event", order = 2, time = 0 }, frame(h))
				T.expect(trail.Enabled).toBe(true)
				c:release()
				T.expect(trail.Enabled).toBe(false)
			end)

			T.it("tailTime = lifetime; cost flags trails that never move", function()
				local h = harness()
				local d = Components.get("trail")
				local comp = h:compile("trail", { lifetime = 2.5 })
				T.expect(d.tailTime(comp)).toBeCloseTo(2.5)
				local still = d.estimateCost(comp, HIGH)
				T.expect(still.maxLifetime).toBeCloseTo(2.5)
				T.expect(still.notes).toHaveLength(1)
				local moving = d.estimateCost(h:compile("trail", nil, { tracks = { position = {} } }), HIGH)
				T.expect(moving.notes).toBeNil()
				T.expect(moving.propertyUpdates).toBe(2)
				local spinning = d.estimateCost(h:compile("trail", { spin = { 0, 90, 0 } }), HIGH)
				T.expect(spinning.notes).toBeNil()
			end)
		end)

		-- ─────────────────────────────────────────────────────────────────────
		-- 3d. light
		-- ─────────────────────────────────────────────────────────────────────
		T.describe("light behaviour", function()
			T.it("Point / Spot: light inside an Attachment on the Root", function()
				for lightType, className in { Point = "PointLight", Spot = "SpotLight" } do
					local h = harness()
					local c, comp = h:build("light", { lightType = lightType })
					local light = c.instances[1]
					T.expect(light.ClassName).toBe(className)
					T.expect(light.Parent.ClassName).toBe("Attachment")
					T.expect(light.Parent.Parent).toBe(h.root)
					T.expect(firstOfClass(h:instancesOf(comp.id), "BasePart")).toBeNil()
				end
			end)

			T.it("Surface: SurfaceLight inside an invisible host part sized surfaceSize", function()
				local h = harness()
				local c = h:build("light", { lightType = "Surface", surfaceSize = { 6, 2, 0.5 }, face = "Top" })
				local light = c.instances[1]
				T.expect(light.ClassName).toBe("SurfaceLight")
				T.expect(light.Parent:IsA("BasePart")).toBe(true)
				T.expect(light.Parent.Size).toBeCloseTo(Vector3.new(6, 2, 0.5))
				T.expect(light.Parent.Transparency).toBe(1)
				T.expect(light.Face).toBe(Enum.NormalId.Top)
			end)

			T.it("writes colour, brightness, range, angle and face", function()
				local h = harness()
				local spot = h:build(
					"light",
					{ lightType = "Spot", color = "#FF0000", brightness = 4, range = 20, angle = 45 }
				).instances[1]
				T.expect(spot.Color).toBeCloseTo(Color3.new(1, 0, 0))
				T.expect(spot.Brightness).toBe(4)
				T.expect(spot.Range).toBe(20)
				T.expect(spot.Angle).toBe(45)
				T.expect(spot.Face).toBe(Enum.NormalId.Front)
				T.expect(spot.Shadows).toBe(false)
			end)

			T.it(
				"Range is clamped to MAX_LIGHT_RANGE after the Compiler's scaling and for the range channel",
				function()
					local h = harness()
					local c = buildWith(h, "light", nil, nil, function(comp: any, _bctx: any)
						comp.props.range = 300 -- e.g. range 120 × effect scale 2.5
					end)
					local light = c.instances[1]
					T.expect(light.Range).toBe(Constants.MAX_LIGHT_RANGE)
					c:apply("range", 50)
					T.expect(light.Range).toBe(50)
					c:apply("range", 1000)
					T.expect(light.Range).toBe(120)
					c:apply("range", -3)
					T.expect(light.Range).toBe(0)
				end
			)

			T.it("Shadows only when the quality profile allows light shadows", function()
				local h = harness()
				T.expect(h:build("light", { shadows = true }, { quality = HIGH, id = "hi" }).instances[1].Shadows)
					.toBe(true)
				T.expect(h:build("light", { shadows = true }, { quality = LOW, id = "lo" }).instances[1].Shadows)
					.toBe(false)
				T.expect(h:build("light", { shadows = false }, { quality = HIGH, id = "off" }).instances[1].Shadows)
					.toBe(false)
				local d = Components.get("light")
				T.expect(d.estimateCost(h:compile("light", { shadows = true }), HIGH).shadowLights).toBe(1)
				T.expect(d.estimateCost(h:compile("light", { shadows = true }), LOW).shadowLights).toBe(0)
				T.expect(d.estimateCost(h:compile("light"), HIGH).shadowLights).toBe(0)
			end)

			T.it("brightness, colour and angle channels (angle clamped; ignored by Point lights)", function()
				local h = harness()
				local c = h:build("light", { lightType = "Surface" })
				local light = c.instances[1]
				c:apply("brightness", 12)
				c:apply("color", Color3.new(0, 0, 1))
				c:apply("angle", 30)
				T.expect(light.Brightness).toBe(12)
				T.expect(light.Color).toBeCloseTo(Color3.new(0, 0, 1))
				T.expect(light.Angle).toBe(30)
				c:apply("angle", 400)
				T.expect(light.Angle).toBe(180)
				local point = h:build("light", nil, { id = "p" })
				T.expect(function()
					point:apply("angle", 30)
				end).never
					.toThrow()
			end)

			T.it("Point/Spot move the attachment; Surface batches the host part through moveParts", function()
				local h = harness()
				local spot = h:build("light", { lightType = "Spot" })
				local f = frame(h)
				local cf = CFrame.new(0, 3, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
				spot:setTransform(cf, h.root.CFrame * cf, f)
				T.expect(spot.instances[1].Parent.CFrame).toBeCloseTo(cf)
				T.expect(#f.moveParts).toBe(0)
				local surface = h:build("light", { lightType = "Surface" }, { id = "s" })
				surface:setTransform(cf, h.root.CFrame * cf, f)
				T.expect(f.moveParts).toEqual({ surface.instances[1].Parent })
				h:flush(f)
				T.expect(surface.instances[1].Parent.CFrame).toBeCloseTo(h.root.CFrame * cf)
			end)

			T.it("enable / disable events and release", function()
				local h = harness()
				local c = h:build("light")
				local light = c.instances[1]
				c:setActive(true, frame(h))
				c:onAction({ action = "disable", source = "event", order = 1, time = 0 }, frame(h))
				T.expect(light.Enabled).toBe(false)
				c:onAction({ action = "enable", source = "event", order = 2, time = 0 }, frame(h))
				T.expect(light.Enabled).toBe(true)
				c:release()
				T.expect(light.Enabled).toBe(false)
			end)

			T.it("cost: Surface lights that move count as moving parts", function()
				local h = harness()
				local d = Components.get("light")
				local tracks = { tracks = { position = {}, brightness = {} } }
				local surface = d.estimateCost(h:compile("light", { lightType = "Surface" }, tracks), HIGH)
				T.expect(surface.movingParts).toBe(1)
				T.expect(surface.propertyUpdates).toBe(1)
				local point = d.estimateCost(h:compile("light", nil, tracks), HIGH)
				T.expect(point.movingParts).toBe(0)
				T.expect(point.propertyUpdates).toBe(2)
			end)
		end)

		-- ─────────────────────────────────────────────────────────────────────
		-- 3e. sound
		-- ─────────────────────────────────────────────────────────────────────
		T.describe("sound behaviour", function()
			local ID = "rbxassetid://1234"

			T.it("Sound inside an Attachment on the Root with every authored property", function()
				local h = harness()
				local c = h:build("sound", {
					soundId = ID,
					volume = 2,
					playbackSpeed = 1.5,
					rollOffMinDistance = 5,
					rollOffMaxDistance = 80,
					looped = true,
				})
				local sound = c.instances[1]
				T.expect(sound.ClassName).toBe("Sound")
				T.expect(sound.Parent.ClassName).toBe("Attachment")
				T.expect(sound.Parent.Parent).toBe(h.root)
				T.expect(sound.SoundId).toBe(ID)
				T.expect(sound.Volume).toBe(2)
				T.expect(sound.PlaybackSpeed).toBe(1.5)
				T.expect(sound.RollOffMinDistance).toBe(5)
				T.expect(sound.RollOffMaxDistance).toBe(80)
				T.expect(sound.Looped).toBe(true)
				T.expect(sound.PlayOnRemove).toBe(false)
				T.expect(sound.Playing).toBe(false)
			end)

			T.itIf(isLune, "playOnStart plays on activation only (not while seeking, not twice)", function()
				local h = harness()
				local c = h:build("sound", { soundId = ID })
				local sound = c.instances[1]
				T.expect(soundActions(sound)).toEqual({})
				c:setActive(true, frame(h))
				c:setActive(true, frame(h))
				T.expect(soundActions(sound)).toEqual({ "Play" })
				local h2 = harness()
				local seek = h2:build("sound", { soundId = ID })
				seek:setActive(true, frame(h2, true))
				T.expect(soundActions(seek.instances[1])).toEqual({})
			end)

			T.itIf(isLune, "playOnStart = false and an empty soundId never play on activation", function()
				local h = harness()
				local manual = h:build("sound", { soundId = ID, playOnStart = false }, { id = "m" })
				local silent = h:build("sound", nil, { id = "s" })
				manual:setActive(true, frame(h))
				silent:setActive(true, frame(h))
				silent:onAction({ action = "play", source = "event", order = 1, time = 0 }, frame(h))
				T.expect(soundActions(manual.instances[1])).toEqual({})
				T.expect(soundActions(silent.instances[1])).toEqual({})
			end)

			T.itIf(isLune, "play / stop events (play skipped while seeking)", function()
				local h = harness()
				local c = h:build("sound", { soundId = ID, playOnStart = false })
				local sound = c.instances[1]
				c:setActive(true, frame(h))
				c:onAction({ action = "play", source = "event", order = 1, time = 0 }, frame(h))
				c:onAction({ action = "play", source = "event", order = 2, time = 0 }, frame(h, true))
				c:onAction({ action = "stop", source = "event", order = 3, time = 0 }, frame(h))
				c:onAction({ action = "stop", source = "event", order = 4, time = 0 }, frame(h)) -- not playing
				T.expect(soundActions(sound)).toEqual({ "Play", "Stop" })
			end)

			T.itIf(isLune, "span end stops looped sounds; one-shot sounds play out", function()
				local h = harness()
				local loop = h:build("sound", { soundId = ID, looped = true }, { id = "loop" })
				local shot = h:build("sound", { soundId = ID }, { id = "shot" })
				for _, c in { loop, shot } do
					c:setActive(true, frame(h))
					c:setActive(false, frame(h))
				end
				T.expect(soundActions(loop.instances[1])).toEqual({ "Play", "Stop" })
				T.expect(soundActions(shot.instances[1])).toEqual({ "Play" })
			end)

			T.itIf(isLune, "release stops looped sounds and blocks new plays until reset", function()
				local h = harness()
				local c = h:build("sound", { soundId = ID, looped = true })
				local sound = c.instances[1]
				c:setActive(true, frame(h))
				c:release()
				c:onAction({ action = "play", source = "event", order = 1, time = 0 }, frame(h))
				T.expect(soundActions(sound)).toEqual({ "Play", "Stop" })
				c:reset()
				c:setActive(true, frame(h))
				T.expect(soundActions(sound)).toEqual({ "Play", "Stop", "Play" })
			end)

			T.itIf(isLune, "preview plays through SoundService:PlayLocalSound instead of Sound:Play()", function()
				local played = {}
				Env.override("SoundService", {
					PlayLocalSound = function(_self: any, s: any)
						table.insert(played, s)
					end,
				})
				local ok, err = pcall(function()
					local h = harness()
					local c = h:build("sound", { soundId = ID }, { isPreview = true })
					c:setActive(true, frame(h))
					c:onAction({ action = "play", source = "event", order = 1, time = 0 }, frame(h))
					T.expect(played).toEqual({ c.instances[1], c.instances[1] })
					T.expect(soundActions(c.instances[1])).toEqual({})
				end :: any)
				Env.override("SoundService", nil)
				if not ok then
					error(err, 0)
				end
			end)

			T.itIf(isLune, "preview falls back to Sound:Play() when PlayLocalSound fails", function()
				Env.override("SoundService", {
					PlayLocalSound = function()
						error("PlayLocalSound unavailable")
					end,
				})
				local ok, err = pcall(function()
					local h = harness()
					local c = h:build("sound", { soundId = ID }, { isPreview = true })
					c:setActive(true, frame(h))
					T.expect(soundActions(c.instances[1])).toEqual({ "Play" })
				end :: any)
				Env.override("SoundService", nil)
				if not ok then
					error(err, 0)
				end
			end)

			T.it("volume and playbackSpeed channels clamp and cache", function()
				local h = harness()
				local c = h:build("sound", { soundId = ID })
				local sound = c.instances[1]
				c:apply("volume", 3)
				c:apply("playbackSpeed", 2)
				T.expect(sound.Volume).toBe(3)
				T.expect(sound.PlaybackSpeed).toBe(2)
				c:apply("volume", 50)
				c:apply("playbackSpeed", 0)
				T.expect(sound.Volume).toBe(10)
				T.expect(sound.PlaybackSpeed).toBeCloseTo(0.01)
				sound.Volume = 0.25
				c:apply("volume", 50)
				T.expect(sound.Volume).toBe(0.25) -- cached: no write
			end)

			T.it("setTransform positions the attachment (positional audio)", function()
				local h = harness()
				local c = h:build("sound", { soundId = ID })
				local f = frame(h)
				c:setTransform(CFrame.new(0, 0, -8), h.root.CFrame * CFrame.new(0, 0, -8), f)
				T.expect(c.instances[1].Parent.CFrame.Position).toBeCloseTo(Vector3.new(0, 0, -8))
				T.expect(#f.moveParts).toBe(0)
			end)

			T.it("cost: one attachment + one sound; notes a missing soundId", function()
				local h = harness()
				local d = Components.get("sound")
				T.expect(d.estimateCost(h:compile("sound"), HIGH).notes).toHaveLength(1)
				local cost = d.estimateCost(
					h:compile("sound", { soundId = ID }, { tracks = { position = {}, volume = {} } }),
					HIGH
				)
				T.expect(cost.notes).toBeNil()
				T.expect(cost.sounds).toBe(1)
				T.expect(cost.propertyUpdates).toBe(2)
			end)
		end)
	end)
end
