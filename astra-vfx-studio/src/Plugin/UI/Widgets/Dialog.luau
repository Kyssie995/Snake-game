--!strict
--[[
	Dialog — modal dialogs inside host.root (a dimmed full-size backdrop blocks the panel underneath).

		Dialog.confirm(host, "Effekt löschen?", "„Feuerball“ wird entfernt.", "Löschen", function(ok)
			if ok then editor:deleteEffect() end
		end, { danger = true })

		Dialog.prompt(host, "Umbenennen", "Name", "Feuerball", function(text)  -- nil when cancelled
			if text then editor:rename(text) end
		end, { validate = function(t) return if t == "" then "Name fehlt" else nil end })

		-- Long, selectable text (plugins have no clipboard API): the user copies with Ctrl+A / Ctrl+C.
		Dialog.text(host, "Export (JSON)", json, { readOnly = true })
		-- Editable variant, e.g. to paste JSON for an import:
		Dialog.text(host, "Import", "", { readOnly = false, confirmText = "Importieren", onResult = function(t) end })

	Each call returns a handle { instance, panel, close(), ... }; close() counts as cancel. The read-only text box
	stays TextEditable (otherwise Studio blocks selecting/copying) and restores its text when it is changed.
	Default labels are German ("Abbrechen", "OK", "Schließen", "Alles markieren"). Keyboard is not required.
]]

local Theme = require(script.Parent.Parent.Theme)
local Maid = require(script.Parent.Parent.Maid)
local Kit = require(script.Parent.ControlKit)
local Button = require(script.Parent.Button)
local TextInput = require(script.Parent.TextInput)

type Host = Kit.Host

export type ConfirmOptions = { cancelText: string?, danger: boolean? }

export type PromptOptions = {
	cancelText: string?,
	confirmText: string?,
	placeholder: string?,
	validate: ((text: string) -> string?)?,
}

export type TextOptions = {
	readOnly: boolean?, -- default true
	closeText: string?,
	confirmText: string?, -- editable mode: label of the confirm button (default "Übernehmen")
	hint: string?,
	onResult: ((text: string?) -> ())?, -- editable: text or nil; read-only: nil on close
}

export type DialogHandle = {
	instance: TextButton,
	panel: Frame,
	close: (self: DialogHandle) -> (),
	isOpen: (self: DialogHandle) -> boolean,
	[string]: any,
}

local Dialog = {}

local c = Theme.colors

type Built = {
	z: number,
	overlay: TextButton,
	panel: Frame,
	body: Frame,
	footer: Frame,
	maid: Maid.Maid,
	finish: (fn: (() -> ())?) -> (),
	isOpen: () -> boolean,
}

local function titleLabel(text: string): TextLabel
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 20)
	title.FontFace = Theme.fonts.bold
	title.TextSize = Theme.textSize.title
	title.TextColor3 = c.text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = text
	title.LayoutOrder = 1
	return title
end

local function footerFrame(): Frame
	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.BackgroundTransparency = 1
	footer.Size = UDim2.new(1, 0, 0, Theme.metrics.rowHeight)
	footer.LayoutOrder = 100
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = footer
	return footer
end

-- Builds backdrop + panel. `fixed` gives the panel a fixed size (long text), otherwise its height is automatic.
local function build(host: Host, title: string, fixed: boolean): Built
	local state = Kit.hostState(host, "dialog")
	state.depth = (state.depth or 0) + 1
	local z = Kit.Z.dialog + (state.depth - 1) * 20
	local maid = Maid.new()

	local overlay = Instance.new("TextButton")
	overlay.Name = "AstraDialog"
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.BackgroundColor3 = c.bg0
	overlay.BackgroundTransparency = 0.35
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Active = true -- modal: swallows clicks meant for the panel underneath
	overlay.Selectable = false
	maid:give(overlay)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = c.bg1
	panel.BorderSizePixel = 0
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Active = true
	Kit.corner().Parent = panel
	Kit.stroke(c.borderStrong).Parent = panel
	local constraint = Instance.new("UISizeConstraint")
	panel.Parent = overlay

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	local footer = footerFrame()

	if fixed then
		panel.Size = UDim2.new(1, -32, 1, -32)
		constraint.MaxSize = Vector2.new(760, 600)
		Kit.padding(16, 16, 14, 14).Parent = panel
		titleLabel(title).Parent = panel
		body.Position = UDim2.fromOffset(0, 30)
		body.Size = UDim2.new(1, 0, 1, -(30 + Theme.metrics.rowHeight + 12))
		body.Parent = panel
		footer.AnchorPoint = Vector2.new(0, 1)
		footer.Position = UDim2.fromScale(0, 1)
		footer.Parent = panel
	else
		panel.Size = UDim2.new(1, -32, 0, 0)
		panel.AutomaticSize = Enum.AutomaticSize.Y
		constraint.MaxSize = Vector2.new(420, math.huge)
		Kit.padding(16, 16, 14, 14).Parent = panel
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 12)
		layout.Parent = panel
		titleLabel(title).Parent = panel
		body.Size = UDim2.fromScale(1, 0)
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.LayoutOrder = 2
		local bodyLayout = Instance.new("UIListLayout")
		bodyLayout.FillDirection = Enum.FillDirection.Vertical
		bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
		bodyLayout.Padding = UDim.new(0, 6)
		bodyLayout.Parent = body
		body.Parent = panel
		footer.Parent = panel
	end
	constraint.Parent = panel

	local open = true
	local function finish(fn: (() -> ())?)
		if not open then
			return
		end
		open = false
		state.depth = math.max(0, (state.depth or 1) - 1)
		maid:clean()
		if fn then
			fn()
		end
	end

	return {
		z = z,
		overlay = overlay,
		panel = panel,
		body = body,
		footer = footer,
		maid = maid,
		finish = finish,
		isOpen = function(): boolean
			return open
		end,
	}
end

local function show(host: Host, d: Built)
	Kit.raise(d.overlay, d.z)
	d.overlay.Parent = host.root
end

local function messageLabel(text: string, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Message"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.FontFace = Theme.fonts.regular
	label.TextSize = Theme.textSize.normal
	label.TextColor3 = c.textDim
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = text
	label.LayoutOrder = order
	return label
end

local function footerButton(d: Built, props: Button.Props, order: number): Button.Button
	local button = Button.new(props)
	button.instance.LayoutOrder = order
	button.instance.Parent = d.footer
	d.maid:give(button)
	return button
end

function Dialog.confirm(
	host: Host,
	title: string,
	message: string,
	confirmText: string?,
	onResult: ((ok: boolean) -> ())?,
	options: ConfirmOptions?
): DialogHandle
	local o: ConfirmOptions = options or {}
	local d = build(host, title, false)
	messageLabel(message, 1).Parent = d.body

	local function result(ok: boolean)
		d.finish(function()
			if onResult then
				onResult(ok)
			end
		end)
	end
	local cancel = footerButton(d, {
		text = o.cancelText or "Abbrechen",
		variant = "secondary",
		onActivate = function()
			result(false)
		end,
	}, 1)
	local confirm = footerButton(d, {
		text = confirmText or "OK",
		variant = if o.danger then "danger" else "primary",
		onActivate = function()
			result(true)
		end,
	}, 2)
	show(host, d)

	local handle = {
		instance = d.overlay,
		panel = d.panel,
		confirmButton = confirm,
		cancelButton = cancel,
	} :: any
	function handle.close(_self: DialogHandle)
		result(false)
	end
	function handle.isOpen(_self: DialogHandle): boolean
		return d.isOpen()
	end
	return handle :: DialogHandle
end

function Dialog.prompt(
	host: Host,
	title: string,
	label: string?,
	default: string?,
	onResult: ((text: string?) -> ())?,
	options: PromptOptions?
): DialogHandle
	local o: PromptOptions = options or {}
	local d = build(host, title, false)
	if label and label ~= "" then
		local l = messageLabel(label, 1)
		l.TextSize = Theme.textSize.small
		l.Parent = d.body
	end

	local function result(text: string?)
		d.finish(function()
			if onResult then
				onResult(text)
			end
		end)
	end

	local input: TextInput.TextInput
	local function submit()
		local text = input:getText()
		if o.validate then
			local ok, err = pcall(o.validate :: any, text)
			local message = if not ok then tostring(err) elseif type(err) == "string" and err ~= "" then err else nil
			if message then
				input:setError(message)
				return
			end
		end
		result(text)
	end

	input = TextInput.new({
		name = "Input",
		value = default or "",
		placeholder = o.placeholder,
		validate = o.validate,
		host = host,
		layoutOrder = 2,
		onSubmit = function(_text: string)
			submit()
		end,
	})
	input.instance.Parent = d.body
	d.maid:give(input)

	local cancel = footerButton(d, {
		text = o.cancelText or "Abbrechen",
		variant = "secondary",
		onActivate = function()
			result(nil)
		end,
	}, 1)
	local confirm = footerButton(d, {
		text = o.confirmText or "OK",
		variant = "primary",
		onActivate = submit,
	}, 2)
	show(host, d)
	input:focus(true)

	local handle = {
		instance = d.overlay,
		panel = d.panel,
		input = input,
		confirmButton = confirm,
		cancelButton = cancel,
	} :: any
	function handle.close(_self: DialogHandle)
		result(nil)
	end
	function handle.isOpen(_self: DialogHandle): boolean
		return d.isOpen()
	end
	return handle :: DialogHandle
end

function Dialog.text(host: Host, title: string, longText: string, options: TextOptions?): DialogHandle
	local o: TextOptions = options or {}
	local readOnly = o.readOnly ~= false
	local d = build(host, title, true)

	local hintHeight = 18
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.BackgroundColor3 = c.bg0
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.new(1, 0, 1, -hintHeight)
	scroll.ScrollingDirection = Enum.ScrollingDirection.XY
	scroll.ScrollBarThickness = Theme.metrics.scrollBar
	scroll.ScrollBarImageColor3 = c.borderStrong
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	scroll.HorizontalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	Kit.corner().Parent = scroll
	Kit.stroke().Parent = scroll
	scroll.Parent = d.body

	local textSize = Theme.textSize.small
	local box = Instance.new("TextBox")
	box.Name = "Text"
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.Size = UDim2.fromScale(1, 1)
	box.ClearTextOnFocus = false
	box.MultiLine = true
	box.TextEditable = true -- must stay editable so the user can select and copy (read-only restores the text)
	box.TextWrapped = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Top
	box.FontFace = Theme.fonts.mono
	box.TextSize = textSize
	box.TextColor3 = c.text
	box.PlaceholderColor3 = c.textMuted
	box.PlaceholderText = if readOnly then "" else "Text hier einfügen…"
	box.Text = longText
	box.Selectable = false
	Kit.padding(8, 8, 6, 6).Parent = box
	box.Parent = scroll

	local function fitCanvas()
		local bounds = Kit.measure(box.Text, textSize, nil, Kit.FONT_ENUM.mono)
		scroll.CanvasSize = UDim2.fromOffset(bounds.X + 24, bounds.Y + 20)
	end
	fitCanvas()

	local restoring = false
	d.maid:give(box:GetPropertyChangedSignal("Text"):Connect(function()
		if readOnly then
			if box.Text ~= longText and not restoring then
				restoring = true
				box.Text = longText
				restoring = false
			end
		else
			fitCanvas()
		end
	end))

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.AnchorPoint = Vector2.new(0, 1)
	hint.Position = UDim2.fromScale(0, 1)
	hint.Size = UDim2.new(1, 0, 0, hintHeight - 4)
	hint.FontFace = Theme.fonts.regular
	hint.TextSize = Theme.textSize.tiny
	hint.TextColor3 = c.textMuted
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	hint.Text = o.hint
		or (
			if readOnly
				then "„Alles markieren“, dann Strg+C (Cmd+C) zum Kopieren."
				else "Text einfügen mit Strg+V (Cmd+V)."
		)
	hint.Parent = d.body

	local function selectAll()
		box:CaptureFocus()
		box.SelectionStart = 1
		box.CursorPosition = #box.Text + 1
	end

	local function result(text: string?)
		d.finish(function()
			if o.onResult then
				o.onResult(text)
			end
		end)
	end

	local handle = {
		instance = d.overlay,
		panel = d.panel,
		box = box,
		selectAll = function(_self: any)
			selectAll()
		end,
		getText = function(_self: any): string
			return box.Text
		end,
	} :: any

	if readOnly then
		handle.selectButton = footerButton(d, {
			text = "Alles markieren",
			variant = "secondary",
			onActivate = selectAll,
		}, 1)
		handle.closeButton = footerButton(d, {
			text = o.closeText or "Schließen",
			variant = "primary",
			onActivate = function()
				result(nil)
			end,
		}, 2)
	else
		handle.cancelButton = footerButton(d, {
			text = o.closeText or "Abbrechen",
			variant = "secondary",
			onActivate = function()
				result(nil)
			end,
		}, 1)
		handle.confirmButton = footerButton(d, {
			text = o.confirmText or "Übernehmen",
			variant = "primary",
			onActivate = function()
				result(box.Text)
			end,
		}, 2)
	end
	show(host, d)
	if readOnly then
		selectAll()
	else
		box:CaptureFocus()
	end

	function handle.close(_self: DialogHandle)
		result(nil)
	end
	function handle.isOpen(_self: DialogHandle): boolean
		return d.isOpen()
	end
	return handle :: DialogHandle
end

-- Number of open dialogs in `host`.
function Dialog.count(host: Host): number
	return Kit.hostState(host, "dialog").depth or 0
end

return Dialog
