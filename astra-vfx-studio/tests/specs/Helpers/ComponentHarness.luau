--!strict
--[[
	ComponentHarness — builds single components outside the Compiler/Player for descriptor specs.

	Usage inside a spec:
		local Harness = use("Tests.Specs.Helpers.ComponentHarness")
		local h = Harness.new(use)
		local controller, component = h:build("particles", { rate = 50, color = "#FF0000" })
		local frame = h:frame(0.5, 1 / 60)
		controller:setActive(true, frame)
		controller:setTransform(CFrame.new(), h.root.CFrame, frame)
		h:flush(frame)            -- applies frame.moveParts / moveCFrames like the Player's BulkMoveTo
		h:cleanup()

	JSON-form properties are merged over the descriptor defaults and decoded with Core/Codec, so specs exercise the
	same value conversion the Compiler uses. Quality and effect scale are NOT applied here (the Compiler owns that);
	pass `props` already adjusted if a test needs it, or set `options.quality`.
]]

local Harness = {}
Harness.__index = Harness

export type Options = {
	isPreview: boolean?,
	viewport: boolean?,
	quality: any?, -- Types.QualityProfile
	scale: number?, -- component transform.scale (rest value)
	startTime: number?,
	endTime: number?,
	tracks: { [string]: any }?, -- already compiled tracks
	palette: { [string]: Color3 }?,
	seed: number?,
	name: string?,
	id: string?,
}

local HIGH = {
	level = "High",
	countScale = 1,
	segmentScale = 1,
	sizeCompensation = 1,
	lightShadows = true,
	maxLights = math.huge,
}

function Harness.new(use: (string) -> any)
	local self = setmetatable({}, Harness) :: any
	self.use = use
	self.Components = use("AstraVFX.Core.Components")
	self.Codec = use("AstraVFX.Core.Codec")
	self.container = Instance.new("Folder")
	self.container.Name = "HarnessContainer"
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.Transparency = 1
	root.Parent = self.container
	self.root = root
	self.tagged = {} :: { [Instance]: string }
	self.controllers = {}
	self.fired = {} :: { string }
	return self
end

-- Decodes JSON-form props (merged over descriptor defaults) into a CompiledComponent.
function Harness.compile(self: any, componentType: string, jsonProps: { [string]: any }?, options: Options?): any
	local o: Options = options or {}
	local descriptor = self.Components.get(componentType)
	assert(descriptor, "unknown component type " .. componentType)
	local props = {}
	local source = jsonProps or {}
	for _, spec in descriptor.properties do
		local value = source[spec.name]
		if value == nil then
			value = self.Codec.default(spec)
		end
		props[spec.name] = self.Codec.decode(spec.kind, value, spec, o.palette)
	end
	for key in pairs(source) do
		assert(self.Components.propertySpec(componentType, key), componentType .. ": unknown property " .. key)
	end
	return {
		id = o.id or (componentType .. "1"),
		name = o.name or componentType,
		type = componentType,
		parentId = nil,
		depth = 0,
		startTime = o.startTime or 0,
		endTime = o.endTime or 2,
		props = props,
		position = Vector3.zero,
		rotation = Vector3.zero,
		scale = o.scale or 1,
		tracks = o.tracks or {},
		events = {},
		seed = o.seed or 12345,
	}
end

function Harness.context(self: any, componentsById: { [string]: any }?, options: Options?): any
	local o: Options = options or {}
	local effect = {
		id = "harness",
		name = "Harness",
		duration = 2,
		loop = false,
		timeScale = 1,
		seed = 1,
		scale = 1,
		quality = o.quality or HIGH,
		palette = o.palette or {},
		components = {},
		byId = componentsById or {},
		markers = {},
		schedule = {},
		maxTail = 0,
		definition = {},
	}
	return {
		effect = effect,
		container = self.container,
		root = self.root,
		parentOf = function(_id: string)
			return nil
		end,
		isPreview = o.isPreview == true,
		viewport = o.viewport == true,
		tagInstance = function(inst: Instance, componentId: string)
			self.tagged[inst] = componentId
			inst:SetAttribute("AstraComponent", componentId)
		end,
	}
end

-- Builds one component; returns (controller, compiledComponent, buildContext).
function Harness.build(
	self: any,
	componentType: string,
	jsonProps: { [string]: any }?,
	options: Options?
): (any, any, any)
	local component = self:compile(componentType, jsonProps, options)
	local ctx = self:context({ [component.id] = component }, options)
	local descriptor = self.Components.get(componentType)
	local controller = descriptor.build(ctx, component)
	table.insert(self.controllers, controller)
	return controller, component, ctx
end

function Harness.frame(self: any, time: number, dt: number?, seeking: boolean?): any
	return {
		time = time,
		dt = dt or 0,
		seeking = seeking == true,
		rootCFrame = self.root.CFrame,
		moveParts = {},
		moveCFrames = {},
		fire = function(name: string)
			table.insert(self.fired, name)
		end,
	}
end

-- Applies batched part moves (what the Player does with WorldRoot:BulkMoveTo).
function Harness.flush(_self: any, frame: any)
	for i, part in frame.moveParts do
		part.CFrame = frame.moveCFrames[i]
	end
	table.clear(frame.moveParts)
	table.clear(frame.moveCFrames)
end

-- All instances below the container that belong to a component id.
function Harness.instancesOf(self: any, componentId: string): { Instance }
	local out = {}
	for _, inst in self.container:GetDescendants() do
		if inst:GetAttribute("AstraComponent") == componentId then
			table.insert(out, inst)
		end
	end
	return out
end

function Harness.cleanup(self: any)
	for _, c in self.controllers do
		c:destroy()
	end
	table.clear(self.controllers)
	self.container:Destroy()
end

return Harness
