--!strict
--[[
	group — a transform-only node. Children (components whose `parent` is this group) inherit its position,
	rotation and spin, which makes orbits, sweeping motions and rotating magic circles easy:
	animate or spin the group, offset the children.

	Reference implementation for descriptor modules: properties via Common.prop, controller via
	Common.controller, cost via Common.cost.
]]

local Common = require(script.Parent.Common)
local Types = require(script.Parent.Parent.Types)

local descriptor: Types.ComponentDescriptor = {
	type = "group",
	displayName = "Group",
	category = "Structure",
	description = "Transform-only node. Children inherit its position, rotation and spin.",
	icon = "▣",
	properties = {
		Common.spinProperty(),
	},
	channels = {
		Common.channel("position", "vector3", "Offset from the parent/effect origin in studs.", { scale = "length" }),
		Common.channel("rotation", "vector3", "Rotation in degrees (Orientation order X, Y, Z)."),
	},
	events = {},
	canParent = true,
	supportsViewport = true,
	build = function(ctx: Types.BuildContext, component: Types.CompiledComponent): Types.ComponentInstance
		local instances: { Instance } = {}
		local marker: Attachment? = nil
		if ctx.isPreview and not ctx.viewport then
			-- Visible pivot gizmo in Studio so authors can see where the group sits.
			local a = Common.newAttachment(ctx, component.id, component.name)
			a.Visible = true
			marker = a
			table.insert(instances, a)
		end
		local controller = Common.controller(component, instances)
		function controller.setTransform(_self, localCFrame: CFrame, _worldCFrame: CFrame, _frame: Types.FrameContext)
			if marker then
				marker.CFrame = localCFrame
			end
		end
		return controller
	end,
	estimateCost = function(_component: Types.CompiledComponent, _quality: Types.QualityProfile): Types.CostEstimate
		return Common.cost()
	end,
}

return descriptor
