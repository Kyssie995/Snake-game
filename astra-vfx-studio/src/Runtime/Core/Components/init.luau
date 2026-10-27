--!strict
--[[
	Components — registry of component descriptors.

	Every ModuleScript child of this module (except "Common") is a component descriptor module that returns a
	Types.ComponentDescriptor. Descriptors are discovered automatically and sorted by `type`, so adding a new
	component type means adding one file. The registry is the single source of truth for:
	  - which component types exist,
	  - their properties (JSON keys, kinds, defaults, ranges) → used by Validation, the Inspector UI,
	    the JSON schema generator and the docs,
	  - their animatable channels and events,
	  - how they are built into Roblox Instances.
]]

local Types = require(script.Parent.Types)

type ComponentDescriptor = Types.ComponentDescriptor
type PropertySpec = Types.PropertySpec
type ChannelSpec = Types.ChannelSpec
type EventSpec = Types.EventSpec

local Components = {}

local descriptors: { [string]: ComponentDescriptor } = {}
local ordered: { ComponentDescriptor } = {}
local propertyIndex: { [string]: { [string]: PropertySpec } } = {}
local channelIndex: { [string]: { [string]: ChannelSpec } } = {}
local eventIndex: { [string]: { [string]: EventSpec } } = {}

local function register(descriptor: ComponentDescriptor)
	assert(type(descriptor) == "table" and type(descriptor.type) == "string", "invalid component descriptor")
	assert(descriptors[descriptor.type] == nil, "duplicate component type " .. descriptor.type)
	descriptors[descriptor.type] = descriptor
	table.insert(ordered, descriptor)
	local props = {}
	for _, spec in descriptor.properties do
		assert(props[spec.name] == nil, descriptor.type .. ": duplicate property " .. spec.name)
		props[spec.name] = spec
	end
	propertyIndex[descriptor.type] = props
	local channels = {}
	for _, spec in descriptor.channels do
		assert(channels[spec.name] == nil, descriptor.type .. ": duplicate channel " .. spec.name)
		channels[spec.name] = spec
	end
	channelIndex[descriptor.type] = channels
	local events = {}
	for _, spec in descriptor.events do
		events[spec.action] = spec
	end
	eventIndex[descriptor.type] = events
end

do
	local modules = {}
	for _, child in script:GetChildren() do
		if child:IsA("ModuleScript") and child.Name ~= "Common" then
			table.insert(modules, child)
		end
	end
	table.sort(modules, function(a, b)
		return a.Name < b.Name
	end)
	for _, module in modules do
		register((require :: any)(module))
	end
	table.sort(ordered, function(a, b)
		return a.type < b.type
	end)
end

-- Returns the descriptor for a component type, or nil.
function Components.get(componentType: string): ComponentDescriptor?
	return descriptors[componentType]
end

-- All descriptors sorted by type name.
function Components.list(): { ComponentDescriptor }
	return table.clone(ordered)
end

function Components.types(): { string }
	local out = {}
	for _, d in ordered do
		table.insert(out, d.type)
	end
	return out
end

function Components.propertySpec(componentType: string, name: string): PropertySpec?
	local props = propertyIndex[componentType]
	return if props then props[name] else nil
end

function Components.channelSpec(componentType: string, name: string): ChannelSpec?
	local channels = channelIndex[componentType]
	return if channels then channels[name] else nil
end

function Components.eventSpec(componentType: string, action: string): EventSpec?
	local events = eventIndex[componentType]
	return if events then events[action] else nil
end

return Components
