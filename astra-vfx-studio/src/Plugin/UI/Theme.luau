--!strict
--[[
	Theme — ASTRA's fixed dark anthracite design tokens (does not follow the Studio theme by design).
	See docs/PLUGIN_CONTRACTS.md §9.
]]

local Theme = {}

local function hex(s: string): Color3
	local r = tonumber(string.sub(s, 2, 3), 16) or 0
	local g = tonumber(string.sub(s, 4, 5), 16) or 0
	local b = tonumber(string.sub(s, 6, 7), 16) or 0
	return Color3.fromRGB(r, g, b)
end
Theme.hex = hex

Theme.colors = {
	bg0 = hex("#17181B"), -- window background
	bg1 = hex("#1F2024"), -- panel
	bg2 = hex("#27292E"), -- raised surfaces, inputs
	bg3 = hex("#30333A"), -- hover
	bg4 = hex("#3A3E46"), -- pressed
	border = hex("#34373E"),
	borderStrong = hex("#454952"),
	text = hex("#E4E6EB"),
	textDim = hex("#A1A5AE"),
	textMuted = hex("#6C717B"),
	accent = hex("#8B6CFF"),
	accentHover = hex("#9D83FF"),
	accentDim = hex("#3B2F6E"),
	teal = hex("#33C3B0"),
	warning = hex("#F0B54A"),
	error = hex("#F2555A"),
	success = hex("#48C08A"),
	keyframe = hex("#F2C14E"),
	keyframeSelected = hex("#FFFFFF"),
	playhead = hex("#FF4F6E"),
	loop = hex("#2E7DFF"),
	selection = hex("#3B2F6E"),
	selectionStrong = hex("#5A47A8"),
	gridMajor = hex("#2C2F35"),
	gridMinor = hex("#23252A"),
}

-- Colours of node-graph pin kinds (also used for channel kinds in the timeline).
Theme.pinColors = {
	exec = hex("#F2F2F2"),
	number = hex("#7FD1FF"),
	vector3 = hex("#FFC857"),
	color3 = hex("#FF7AB6"),
	boolean = hex("#E36A6A"),
	string = hex("#B5E48C"),
	component = hex("#8B6CFF"),
	any = hex("#A1A5AE"),
}

-- Accent per component category (explorer icons, timeline bars).
Theme.categoryColors = {
	Particles = hex("#FF9F43"),
	["Beams & Trails"] = hex("#4FC3F7"),
	Geometry = hex("#9CCC65"),
	Lighting = hex("#FFE066"),
	Audio = hex("#BA68C8"),
	Procedural = hex("#8B6CFF"),
	Camera = hex("#F48FB1"), -- rose: screen-space effects (camera shake, screen flash)
	Structure = hex("#A1A5AE"),
}

Theme.fonts = {
	regular = Font.fromEnum(Enum.Font.BuilderSans),
	medium = Font.fromEnum(Enum.Font.BuilderSansMedium),
	bold = Font.fromEnum(Enum.Font.BuilderSansBold),
	mono = Font.fromEnum(Enum.Font.RobotoMono),
}

Theme.textSize = {
	title = 14,
	normal = 13,
	small = 12,
	tiny = 11,
}

Theme.metrics = {
	rowHeight = 24,
	headerHeight = 28,
	toolbarHeight = 32,
	padding = 8,
	paddingSmall = 4,
	corner = 4,
	indent = 14,
	scrollBar = 6,
	labelWidth = 0.42, -- fraction of a property row used by its label
}

function Theme.color(token: string): Color3
	local c = (Theme.colors :: any)[token]
	assert(c, "Theme: unknown colour token " .. token)
	return c
end

function Theme.categoryColor(category: string): Color3
	return (Theme.categoryColors :: any)[category] or Theme.colors.textDim
end

function Theme.pinColor(kind: string): Color3
	return (Theme.pinColors :: any)[kind] or Theme.pinColors.any
end

return Theme
