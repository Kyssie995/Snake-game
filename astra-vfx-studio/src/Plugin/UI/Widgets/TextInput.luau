--!strict
--[[
	TextInput — framed TextBox that commits on FocusLost / Enter (ClearTextOnFocus = false).

		local name = TextInput.new({
			value = "Feuerball",
			placeholder = "Name",
			validate = function(text)        -- optional: return an error message to reject the text
				return if text == "" then "Name darf nicht leer sein" else nil
			end,
			onChange = function(text, final) editor:rename(text) end, -- final is always true (commit)
			onSubmit = function(text) end,   -- optional: Enter pressed with valid text
			parent = row,
		})
		local notes = TextInput.new({ multiline = true, height = 72, value = "..." })
		name:setValue("Eisball")             -- updates the text without firing callbacks

	Behaviour: Escape reverts to the last committed text. Invalid text keeps a red border (Theme.colors.error) and
	is not committed. onChange only fires when the committed text actually changes. props.onInput(text) runs on
	every keystroke (GetPropertyChangedSignal("Text")). Multi-line inputs commit on focus loss (Enter = newline).
]]

local Theme = require(script.Parent.Parent.Theme)
local Maid = require(script.Parent.Parent.Maid)
local Kit = require(script.Parent.ControlKit)
local Tooltip = require(script.Parent.Tooltip)

export type Props = {
	value: string?,
	placeholder: string?,
	multiline: boolean?,
	height: number?, -- multi-line height (default 72)
	size: UDim2?,
	mono: boolean?,
	textSize: number?,
	validate: ((text: string) -> string?)?,
	onChange: ((text: string, final: boolean) -> ())?,
	onSubmit: ((text: string) -> ())?,
	onInput: ((text: string) -> ())?,
	tooltip: string?, -- shown when there is no error (needs host)
	host: Kit.Host?, -- optional: enables the error/tooltip text on hover
	enabled: boolean?,
	name: string?,
	layoutOrder: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	parent: Instance?,
}

local TextInput = {}
TextInput.__index = TextInput

type TextInputData = {
	instance: Frame,
	box: TextBox,
	_maid: any, -- Maid (any: generic Maid methods do not unify across modules in the old solver)
	_stroke: UIStroke,
	_props: Props,
	_committed: string,
	_lastText: string,
	_error: string?,
	_focused: boolean,
	_enabled: boolean,
	_hovered: boolean,
}

export type TextInput = typeof(setmetatable({} :: TextInputData, TextInput))

local c = Theme.colors

function TextInput.new(props: Props): TextInput
	local maid = Maid.new()
	local multiline = props.multiline == true
	local root = Instance.new("Frame")
	root.Name = "TextInput"
	root.BackgroundColor3 = c.bg2
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.Size = props.size
		or (if multiline then UDim2.new(1, 0, 0, props.height or 72) else UDim2.new(1, 0, 0, Theme.metrics.rowHeight))
	Kit.applyCommon(root, props :: any)
	Kit.corner().Parent = root
	local stroke = Kit.stroke()
	stroke.Parent = root
	maid:give(root)

	local box = Instance.new("TextBox")
	box.Name = "Box"
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.Size = UDim2.fromScale(1, 1)
	box.ClearTextOnFocus = false
	box.MultiLine = multiline
	box.TextWrapped = multiline
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = if multiline then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center
	box.FontFace = if props.mono then Theme.fonts.mono else Theme.fonts.regular
	box.TextSize = props.textSize or (if props.mono then Theme.textSize.small else Theme.textSize.normal)
	box.TextColor3 = c.text
	box.PlaceholderText = props.placeholder or ""
	box.PlaceholderColor3 = c.textMuted
	box.Text = props.value or ""
	box.Selectable = false
	Kit.padding(6, 6, if multiline then 4 else 0).Parent = box
	box.Parent = root

	local self = setmetatable({
		instance = root,
		box = box,
		_maid = maid,
		_stroke = stroke,
		_props = props,
		_committed = props.value or "",
		_lastText = props.value or "",
		_error = nil :: string?,
		_focused = false,
		_enabled = props.enabled ~= false,
		_hovered = false,
	}, TextInput)

	maid:give(box:GetPropertyChangedSignal("Text"):Connect(function()
		self:_onText()
	end))
	maid:give(box.Focused:Connect(function()
		self._focused = true
		self:_refresh()
	end))
	maid:give(box.FocusLost:Connect(function(enterPressed: boolean, input: InputObject?)
		self._focused = false
		self:_onFocusLost(enterPressed, input)
	end))
	maid:give(root.MouseEnter:Connect(function()
		self._hovered = true
		self:_refresh()
	end))
	maid:give(root.MouseLeave:Connect(function()
		self._hovered = false
		self:_refresh()
	end))
	if props.host then
		maid:give(Tooltip.attach(props.host, root, function(): string?
			return self._error or props.tooltip
		end))
	end

	self:_refresh()
	if props.parent then
		root.Parent = props.parent
	end
	return self
end

function TextInput._refresh(self: TextInput)
	local stroke = self._stroke
	if self._error then
		stroke.Color = c.error
	elseif self._focused then
		stroke.Color = c.accent
	elseif self._hovered and self._enabled then
		stroke.Color = c.borderStrong
	else
		stroke.Color = c.border
	end
	self.box.TextColor3 = if self._enabled then c.text else c.textMuted
	self.box.TextEditable = self._enabled
	self.instance.Interactable = self._enabled
	self.instance.BackgroundColor3 = if self._enabled then c.bg2 else c.bg1
end

-- Runs the validator; returns the error message (nil when valid) and updates the border.
function TextInput._check(self: TextInput, text: string): string?
	local validate = self._props.validate
	local err: string? = nil
	if validate then
		local ok, result = pcall(validate :: any, text)
		if not ok then
			err = tostring(result)
		elseif type(result) == "string" and result ~= "" then
			err = result
		end
	end
	if err ~= self._error then
		self._error = err
		self:_refresh()
	end
	return err
end

-- Text changed (typing or programmatic). Deduplicated, so calling it twice for one change is harmless.
function TextInput._onText(self: TextInput)
	local text = self.box.Text
	if text == self._lastText then
		return
	end
	self._lastText = text
	if self._props.validate then
		self:_check(text)
	end
	if self._props.onInput then
		self._props.onInput(text)
	end
end

function TextInput._onFocusLost(self: TextInput, enterPressed: boolean, input: InputObject?)
	if input ~= nil then
		local ok, key = pcall(function()
			return (input :: any).KeyCode
		end)
		if ok and key == Enum.KeyCode.Escape then
			self:_revert()
			return
		end
	end
	self:commit(enterPressed)
end

function TextInput._revert(self: TextInput)
	self._lastText = self._committed
	self.box.Text = self._committed
	self._error = nil
	self:_refresh()
end

-- Commits the current text (as FocusLost would). Returns true when the text is valid.
function TextInput.commit(self: TextInput, submitted: boolean?): boolean
	self:_onText()
	local text = self.box.Text
	local err = self:_check(text)
	if err then
		self:_refresh()
		return false
	end
	local changed = text ~= self._committed
	self._committed = text
	self:_refresh()
	if changed and self._props.onChange then
		self._props.onChange(text, true)
	end
	if submitted and self._props.onSubmit then
		self._props.onSubmit(text)
	end
	return true
end

-- Sets the text without firing callbacks (clears any error state).
function TextInput.setValue(self: TextInput, text: string)
	self._committed = text
	self._lastText = text
	self._error = nil
	self.box.Text = text
	self:_refresh()
end

-- Last committed text.
function TextInput.getValue(self: TextInput): string
	return self._committed
end

-- Current (possibly uncommitted) text in the box.
function TextInput.getText(self: TextInput): string
	return self.box.Text
end

function TextInput.getError(self: TextInput): string?
	return self._error
end

-- Shows an external error message (e.g. a name collision found by the editor); nil clears it.
function TextInput.setError(self: TextInput, message: string?)
	self._error = if message == "" then nil else message
	self:_refresh()
end

function TextInput.focus(self: TextInput, selectAll: boolean?)
	if not self._enabled then
		return
	end
	self.box:CaptureFocus()
	if selectAll then
		self.box.SelectionStart = 1
		self.box.CursorPosition = #self.box.Text + 1
	end
end

function TextInput.setPlaceholder(self: TextInput, text: string)
	self.box.PlaceholderText = text
end

function TextInput.setEnabled(self: TextInput, enabled: boolean)
	self._enabled = enabled
	if not enabled and self.box:IsFocused() then
		self.box:ReleaseFocus()
	end
	self:_refresh()
end

function TextInput.destroy(self: TextInput)
	self._maid:clean()
end

return TextInput
