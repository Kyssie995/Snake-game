--!strict
--[[
	Builder — CompiledEffect -> BuiltEffect: the Roblox Instances of one playing copy plus one controller
	(Types.ComponentInstance) per compiled component. See docs/MODULE_CONTRACTS.md §16, docs/ARCHITECTURE.md §5
	and docs/COMPONENTS_SPEC.md §0.

	  Builder.build(compiled, options?) -> BuiltEffect
	    options = { parent: Instance?, isPreview: boolean?, viewport: boolean?, name: string? }
	  built:destroy()      controllers (children first), then the container; idempotent
	  built:reset()        extension for Core/Pool: controller:reset() for every component (topological order)

	Layout:
	  Folder "AstraVFX_<name>"                 container; attribute AstraEffect = <name>
	    Part "Root"                            anchored, invisible, 0.2 studs, physics-free (the settings of
	                                           Common.newPart), Locked = not isPreview, CFrame = identity.
	                                           Attachments of all components live on it; the Player moves it.
	    <component parts / attachments ...>   created by descriptor.build (Common.newPart / newAttachment)
	  <name> = options.name or compiled.name.

	Rules:
	  * Every component is built with descriptor.build(ctx, component) in the compiled (topological) order, so
	    ctx.parentOf(componentId) — the controller of that component's parent — is always already built.
	  * ctx.tagInstance(inst, id) sets the attribute AstraComponent = id; in preview mode also Archivable = false
	    and AstraPreview = true. After each component is built, its controller.instances and their descendants
	    that a descriptor forgot to tag are tagged with the component id. In preview mode every instance below the
	    container, the container and the root carry Archivable = false and AstraPreview = true (the container and
	    the root are shared, so they get no AstraComponent attribute).
	  * Viewport mode (options.viewport): components whose descriptor has supportsViewport = false (particles,
	    beams, trails, lights, sounds — the ViewportFrame does not render them) get a placeholder controller: a
	    small neon Ball part (Common.newPart, 0.5 studs) that is visible only while the component is active and
	    follows the component transform through frame.moveParts. Other components build normally (descriptors
	    read ctx.viewport themselves, e.g. lightning switches to part mode).
	  * The container is built unparented and parented to options.parent only after every component has been
	    built, so the copy never replicates or renders half-built (one parent change at the end). Without
	    options.parent it stays unparented (the caller parents it).
	  * A descriptor error during the build destroys everything built so far and re-raises the error with the
	    component id.
	  * destroy(): controller:destroy() in reverse build order (children before parents; an error in one
	    controller is reported with warn() and does not stop the others), then container:Destroy(). Calling it
	    again does nothing.
]]

local Common = require(script.Parent.Components.Common)
local Components = require(script.Parent.Components)
local Constants = require(script.Parent.Constants)
local Types = require(script.Parent.Types)

type CompiledEffect = Types.CompiledEffect
type CompiledComponent = Types.CompiledComponent
type ComponentInstance = Types.ComponentInstance
type BuildContext = Types.BuildContext
type FrameContext = Types.FrameContext

export type BuildOptions = {
	parent: Instance?,
	isPreview: boolean?,
	viewport: boolean?,
	name: string?,
}

export type BuiltEffect = {
	container: Folder,
	root: BasePart,
	controllers: { [string]: ComponentInstance },
	order: { string }, -- component ids in build (topological) order
	effect: CompiledEffect, -- extension: the compiled effect this copy was built from
	isPreview: boolean,
	viewport: boolean,
	destroyed: boolean,
	reset: (self: BuiltEffect) -> (),
	destroy: (self: BuiltEffect) -> (),
}

local Builder = {}

local ATTR_EFFECT = Constants.ATTR_EFFECT
local ATTR_COMPONENT = Constants.ATTR_COMPONENT
local ATTR_PREVIEW = Constants.ATTR_PREVIEW
local ROOT_SIZE = 0.2
local PLACEHOLDER_SIZE = 0.5
local PLACEHOLDER_COLOR = Color3.fromRGB(255, 64, 200)

Builder.ROOT_SIZE = ROOT_SIZE
Builder.PLACEHOLDER_SIZE = PLACEHOLDER_SIZE

-- Physics-free, invisible root part (same settings as Common.newPart).
local function newRoot(isPreview: boolean): Part
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Massless = true
	root.AudioCanCollide = false
	root.Locked = not isPreview
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Transparency = 1
	root.Size = Vector3.new(ROOT_SIZE, ROOT_SIZE, ROOT_SIZE)
	root.CFrame = CFrame.new()
	return root
end

local function markPreview(inst: Instance)
	inst.Archivable = false
	inst:SetAttribute(ATTR_PREVIEW, true)
end

-- Viewport stand-in for components the ViewportFrame cannot render: a neon ball visible while active.
local function placeholder(ctx: BuildContext, component: CompiledComponent): ComponentInstance
	local part = Common.newPart(ctx, component.id, component.name .. " (placeholder)") :: Part
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Color = PLACEHOLDER_COLOR
	part.Size = Vector3.new(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)
	local builtCFrame = part.CFrame
	local visible = false
	local lastCFrame: CFrame? = nil

	local controller = Common.controller(component, { part })
	function controller.setActive(_self: ComponentInstance, active: boolean, _frame: FrameContext)
		if active ~= visible then
			visible = active
			part.Transparency = if active then 0 else 1
		end
	end
	function controller.setTransform(
		_self: ComponentInstance,
		_localCFrame: CFrame,
		worldCFrame: CFrame,
		frame: FrameContext
	)
		if lastCFrame ~= worldCFrame then
			lastCFrame = worldCFrame
			table.insert(frame.moveParts, part)
			table.insert(frame.moveCFrames, worldCFrame)
		end
	end
	function controller.reset(_self: ComponentInstance)
		visible = false
		lastCFrame = nil
		part.Transparency = 1
		part.CFrame = builtCFrame
	end
	return controller
end

local function destroyControllers(controllers: { [string]: ComponentInstance }, order: { string })
	for i = #order, 1, -1 do
		local controller = controllers[order[i]]
		if controller then
			local ok, err = pcall(controller.destroy :: any, controller)
			if not ok then
				warn("[AstraVFX] destroying component " .. order[i] .. " failed: " .. tostring(err))
			end
		end
	end
end

-- Builds one playing copy of a compiled effect (see the module header).
function Builder.build(compiled: CompiledEffect, options: BuildOptions?): BuiltEffect
	if type(compiled) ~= "table" or type((compiled :: any).components) ~= "table" then
		error("Builder.build: expected a CompiledEffect (Compiler.compile), got " .. typeof(compiled), 2)
	end
	local o: BuildOptions = options or {}
	local isPreview = o.isPreview == true
	local viewport = o.viewport == true
	local name = if type(o.name) == "string" and o.name ~= "" then o.name else compiled.name

	local container = Instance.new("Folder")
	container.Name = Constants.CONTAINER_PREFIX .. name
	container:SetAttribute(ATTR_EFFECT, name)
	local root = newRoot(isPreview)
	if isPreview then
		markPreview(container)
		markPreview(root)
	end
	root.Parent = container

	local controllers: { [string]: ComponentInstance } = {}
	local order: { string } = {}

	local function tagInstance(inst: Instance, componentId: string)
		inst:SetAttribute(ATTR_COMPONENT, componentId)
		if isPreview then
			markPreview(inst)
		end
	end

	local ctx: BuildContext = {
		effect = compiled,
		container = container,
		root = root,
		parentOf = function(componentId: string): ComponentInstance?
			local component = compiled.byId[componentId]
			local parentId = if component then component.parentId else nil
			return if parentId then controllers[parentId] else nil
		end,
		isPreview = isPreview,
		viewport = viewport,
		tagInstance = tagInstance,
	}

	local current = "?"
	local function buildAll()
		for _, component in compiled.components do
			current = component.id
			local descriptor = Components.get(component.type)
			if descriptor == nil then
				error("unknown component type " .. tostring(component.type), 0)
			end
			local controller: ComponentInstance
			if viewport and not descriptor.supportsViewport then
				controller = placeholder(ctx, component)
			else
				controller = descriptor.build(ctx, component)
			end
			controllers[component.id] = controller
			table.insert(order, component.id)
			for _, inst in controller.instances do
				if inst:GetAttribute(ATTR_COMPONENT) == nil then
					tagInstance(inst, component.id)
				end
				for _, d in inst:GetDescendants() do
					if d:GetAttribute(ATTR_COMPONENT) == nil then
						tagInstance(d, component.id)
					end
				end
			end
		end
	end

	local ok, err = pcall(buildAll :: any)
	if not ok then
		destroyControllers(controllers, order)
		container:Destroy()
		error("Builder.build: component " .. string.format("%q", current) .. ": " .. tostring(err), 2)
	end

	if isPreview then
		for _, inst in container:GetDescendants() do
			if inst.Archivable or inst:GetAttribute(ATTR_PREVIEW) ~= true then
				markPreview(inst)
			end
		end
	end

	local built: BuiltEffect = {
		container = container,
		root = root,
		controllers = controllers,
		order = order,
		effect = compiled,
		isPreview = isPreview,
		viewport = viewport,
		destroyed = false,
		reset = function(self: BuiltEffect)
			if self.destroyed then
				return
			end
			for _, id in self.order do
				local controller = self.controllers[id]
				if controller then
					controller:reset()
				end
			end
		end,
		destroy = function(self: BuiltEffect)
			if self.destroyed then
				return
			end
			self.destroyed = true
			destroyControllers(self.controllers, self.order)
			self.container:Destroy()
		end,
	}

	-- Parent last: the copy appears in one step, fully built.
	if o.parent ~= nil then
		container.Parent = o.parent
	end
	return built
end

return Builder
