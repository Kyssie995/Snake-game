--!strict
--[[
	AssetInput — asset reference field: thumbnail preview, a TextInput for "rbxassetid://…" / "rbxasset://…"
	strings and a "Wählen…" button that opens Studio's asset picker (plugin:PromptForExistingAssetIdAsync).

		local texture = AssetInput.new({
			value = "rbxassetid://243660364",
			host = host,                             -- { plugin, widget, root }; the picker needs host.plugin
			assetType = "Image",                     -- passed to PromptForExistingAssetIdAsync (default "Image")
			onChange = function(asset, final) ... end, -- canonical string (Codec "asset" kind), final = true
			parent = row,
		})
		texture:setValue("rbxasset://textures/particles/sparkles_main.dds") -- display only

	Typed text is canonicalised with Codec ("123" and "https://www.roblox.com/asset/?id=123" become
	"rbxassetid://123", "" clears); anything else is rejected with an error border. The preview uses
	rbxthumb://type=Asset&id=<n>&w=150&h=150 for numeric ids and the raw path for rbxasset:// files.
	The picker yields, so it runs in task.spawn and is pcall-wrapped (cancel / -1 / errors change nothing).
]]

local Theme = require(script.Parent.Parent.Theme)
local New = require(script.Parent.Parent.New)
local Maid = require(script.Parent.Parent.Maid)
local TextInput = require(script.Parent.TextInput)
local Button = require(script.Parent.Button)
local Codec = require(script.Parent.Parent.Parent.Parent.AstraVFX.Core.Codec)

local AssetInput = {}
AssetInput.__index = AssetInput

export type Props = {
	value: string?,
	assetType: string?, -- default "Image"
	placeholder: string?,
	host: any?,
	enabled: boolean?,
	previewSize: number?, -- px (default Theme.metrics.rowHeight); larger values make the row taller
	onChange: ((asset: string, final: boolean) -> ())?,
	name: string?,
	size: UDim2?,
	position: UDim2?,
	layoutOrder: number?,
	parent: Instance?,
}

type AssetInputData = {
	instance: Frame,
	preview: ImageLabel,
	input: any, -- TextInput
	button: any, -- Button
	maid: Maid.Maid,
	_props: Props,
	_value: string,
	_enabled: boolean,
	_picking: boolean,
	_destroyed: boolean,
}

export type AssetInput = typeof(setmetatable({} :: AssetInputData, AssetInput))

AssetInput.ERROR_TEXT = "Ungültige Asset-ID – erwartet rbxassetid://123, rbxasset://pfad oder eine Zahl"

-- Canonical asset string for typed text, or (nil, message).
function AssetInput.parse(text: string): (string?, string?)
	local trimmed = string.match(text, "^%s*(.-)%s*$") or ""
	local value: any = trimmed
	if string.match(trimmed, "^%d+$") then
		value = tonumber(trimmed)
	end
	local ok, result = pcall(Codec.normalize, "asset", value)
	if ok and type(result) == "string" then
		return result, nil
	end
	return nil, AssetInput.ERROR_TEXT
end

-- Image shown by the preview for a canonical asset string ("" when there is nothing to show).
function AssetInput.thumbnail(asset: string): string
	local id = string.match(asset, "^rbxassetid://(%d+)$")
	if id then
		return "rbxthumb://type=Asset&id=" .. id .. "&w=150&h=150"
	end
	if string.sub(asset, 1, 11) == "rbxasset://" then
		return asset
	end
	return ""
end

function AssetInput.new(props: Props): AssetInput
	local previewSize = props.previewSize or Theme.metrics.rowHeight
	local height = math.max(previewSize, Theme.metrics.rowHeight)

	local root = New("Frame", {
		Name = props.name or "AssetInput",
		Size = props.size or UDim2.new(1, 0, 0, height),
		Position = props.position or UDim2.new(),
		LayoutOrder = props.layoutOrder or 0,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, {
		New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 4),
		}),
	}) :: Frame

	local preview = New("ImageLabel", {
		Name = "Preview",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(previewSize, previewSize),
		BackgroundColor3 = Theme.colors.bg0,
		BorderSizePixel = 0,
		Image = "",
		ScaleType = Enum.ScaleType.Fit,
		Parent = root,
	}, {
		New("UICorner", { CornerRadius = UDim.new(0, Theme.metrics.corner) }),
		New("UIStroke", {
			Color = Theme.colors.border,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	}) :: ImageLabel

	local self: AssetInput
	local input = TextInput.new({
		name = "Text",
		layoutOrder = 2,
		value = "",
		placeholder = props.placeholder or "rbxassetid://…",
		mono = true,
		textSize = Theme.textSize.small,
		host = props.host,
		enabled = props.enabled,
		size = UDim2.new(0, 0, 0, Theme.metrics.rowHeight),
		validate = function(text: string): string?
			local _, err = AssetInput.parse(text)
			return err
		end,
		onChange = function(text: string)
			self:_typed(text)
		end,
		parent = root,
	})
	New("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = input.instance })

	local button = Button.new({
		name = "Pick",
		layoutOrder = 3,
		text = "Wählen…",
		variant = "secondary",
		host = props.host,
		tooltip = "Asset aus Studio auswählen",
		enabled = props.enabled,
		onActivate = function()
			self:pick()
		end,
		parent = root,
	})

	self = setmetatable({
		instance = root,
		preview = preview,
		input = input,
		button = button,
		maid = Maid.new(),
		_props = props,
		_value = "",
		_enabled = props.enabled ~= false,
		_picking = false,
		_destroyed = false,
	}, AssetInput)
	self.maid:give(input)
	self.maid:give(button)

	self:setValue(props.value or "")
	if not self._enabled then
		self:setEnabled(false)
	end
	if props.parent then
		root.Parent = props.parent
	end
	return self
end

function AssetInput._typed(self: AssetInput, text: string)
	local asset = AssetInput.parse(text)
	if asset == nil then
		return
	end
	self:_commit(asset)
end

function AssetInput._commit(self: AssetInput, asset: string)
	local changed = asset ~= self._value
	self:setValue(asset)
	if changed and self._props.onChange then
		self._props.onChange(asset, true)
	end
end

-- Display only (no callbacks). Unparseable values are shown as typed, without preview.
function AssetInput.setValue(self: AssetInput, value: string)
	local asset = AssetInput.parse(value or "")
	local shown = asset or value or ""
	self._value = shown
	self.input:setValue(shown)
	self.preview.Image = if asset then AssetInput.thumbnail(asset) else ""
end

function AssetInput.getValue(self: AssetInput): string
	return self._value
end

-- Opens Studio's asset picker (non-blocking). The chosen id is committed like a typed value.
function AssetInput.pick(self: AssetInput)
	if not self._enabled or self._picking or self._destroyed then
		return
	end
	local host = self._props.host
	local plugin = if host then host.plugin else nil
	if plugin == nil then
		return
	end
	self._picking = true
	task.spawn(function()
		local ok, id = pcall(function()
			return plugin:PromptForExistingAssetIdAsync(self._props.assetType or "Image")
		end)
		self._picking = false
		if self._destroyed then
			return
		end
		if ok and type(id) == "number" and id > 0 and id == math.floor(id) then
			self:_commit("rbxassetid://" .. string.format("%.0f", id))
		elseif not ok then
			warn("[AstraVFX] asset picker failed: " .. tostring(id))
		end
	end)
end

function AssetInput.isPicking(self: AssetInput): boolean
	return self._picking
end

function AssetInput.setEnabled(self: AssetInput, enabled: boolean)
	self._enabled = enabled
	self.input:setEnabled(enabled)
	self.button:setEnabled(enabled)
	self.preview.ImageTransparency = if enabled then 0 else 0.5
end

function AssetInput.destroy(self: AssetInput)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self.maid:clean()
	self.instance:Destroy()
end

return AssetInput
