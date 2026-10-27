--!strict
-- Basic UI controls (UI/Widgets): Button, IconButton, Label, TextInput, NumberInput, Slider, Checkbox, Dropdown,
-- SearchBox, Tooltip, Toast, Dialog and the shared ControlKit helpers. Every widget is constructed (property names
-- and values are validated by the reflection database in Lune); behaviour is driven by firing fake GUI events.
-- Rendering, layout and real mouse input are NOT verified here.
return function(T: any, use: (string) -> any, ctx: any)
	local Theme = use("Plugin.UI.Theme")
	local Kit = use("Plugin.UI.Widgets.ControlKit")
	local Button = use("Plugin.UI.Widgets.Button")
	local IconButton = use("Plugin.UI.Widgets.IconButton")
	local Label = use("Plugin.UI.Widgets.Label")
	local TextInput = use("Plugin.UI.Widgets.TextInput")
	local NumberInput = use("Plugin.UI.Widgets.NumberInput")
	local Slider = use("Plugin.UI.Widgets.Slider")
	local Checkbox = use("Plugin.UI.Widgets.Checkbox")
	local Dropdown = use("Plugin.UI.Widgets.Dropdown")
	local SearchBox = use("Plugin.UI.Widgets.SearchBox")
	local Tooltip = use("Plugin.UI.Widgets.Tooltip")
	local Toast = use("Plugin.UI.Widgets.Toast")
	local Dialog = use("Plugin.UI.Widgets.Dialog")

	local lune = ctx.environment == "lune"
	local colors = Theme.colors

	-- Host = { plugin, widget, root } with a 400×300 root (Lune: ControlKit.geometry falls back to Size offsets).
	local function makeHost(): any
		local root = Instance.new("Frame")
		root.Name = "Root"
		root.Size = UDim2.fromOffset(400, 300)
		if lune then
			local widget = ctx.plugin.newWidget("AstraVFX_WidgetsTest")
			root.Parent = widget.gui
			return { plugin = ctx.plugin.newPlugin(), widget = widget, root = root }
		end
		return {
			plugin = nil,
			widget = {
				GetRelativeMousePosition = function(_self: any): Vector2
					return Vector2.zero
				end,
			},
			root = root,
		}
	end

	local function fire(inst: any, event: string, ...: any)
		ctx.fakes:signalFor(inst, event):Fire(...)
	end

	-- Enum.KeyCode.Unknown exists in Studio but not in Lune's reflection database.
	local okUnknown, unknownKey = pcall(function()
		return (Enum.KeyCode :: any).Unknown
	end)
	local UNKNOWN_KEY = if okUnknown then unknownKey else nil

	-- Fake InputObject. `mods` lists held modifiers by Enum.ModifierKey name, e.g. { Shift = true }.
	local function mouseInput(mods: { [string]: boolean }?): any
		local input = {
			UserInputType = Enum.UserInputType.MouseButton1,
			UserInputState = Enum.UserInputState.Begin,
			Position = Vector3.new(0, 0, 0),
			KeyCode = UNKNOWN_KEY,
		}
		function input.IsModifierKeyDown(_self: any, key: EnumItem): boolean
			return mods ~= nil and mods[key.Name] == true
		end
		return input
	end

	local function keyInput(key: Enum.KeyCode): any
		return {
			UserInputType = Enum.UserInputType.Keyboard,
			UserInputState = Enum.UserInputState.Begin,
			Position = Vector3.new(0, 0, 0),
			KeyCode = key,
			IsModifierKeyDown = function()
				return false
			end,
		}
	end

	-- Press at `from`, move through `path` (one Heartbeat each), release by UserInputState = End.
	local function drag(host: any, gui: any, from: Vector2, path: { Vector2 }, mods: { [string]: boolean }?)
		host.widget.mouse = from
		local input = mouseInput(mods)
		fire(gui, "InputBegan", input)
		for _, pos in path do
			host.widget.mouse = pos
			ctx.fakes:step(1 / 60)
		end
		input.UserInputState = Enum.UserInputState.End
		ctx.fakes:step(1 / 60)
	end

	-- One recorded callback invocation (keeps mixed-type rows `any` for the type checker).
	local function call(...: any): { any }
		return { ... }
	end

	local function recorder(): ({ { any } }, (...any) -> ())
		local log: { { any } } = {}
		return log, function(...: any)
			table.insert(log, { ... })
		end
	end

	local function childNamed(parent: Instance, name: string): Instance?
		return parent:FindFirstChild(name)
	end

	local function countNamed(parent: Instance, name: string): number
		local n = 0
		for _, child in parent:GetChildren() do
			if child.Name == name then
				n += 1
			end
		end
		return n
	end

	T.describe("ControlKit", function()
		T.it("formats numbers with precision and drops trailing zeros", function()
			T.expect(Kit.format(1.5, 2)).toBe("1.5")
			T.expect(Kit.format(2, 2)).toBe("2")
			T.expect(Kit.format(1.256, 2)).toBe("1.26")
			T.expect(Kit.format(-0.0001, 2)).toBe("0")
			T.expect(Kit.format(12.7, 0)).toBe("13")
		end)
		T.it("evaluates arithmetic typed into number fields", function()
			T.expect(Kit.evaluate("2*3")).toBe(6)
			T.expect(Kit.evaluate(" 7 ")).toBe(7)
			T.expect(Kit.evaluate("1,5")).toBe(1.5)
			T.expect(Kit.evaluate("(4+2)/3")).toBe(2)
			T.expect(Kit.evaluate("-2^2")).toBe(-4)
			T.expect(Kit.evaluate("2e2 + .5")).toBe(200.5)
			T.expect(Kit.evaluate("10 % 4")).toBe(2)
			T.expect(Kit.evaluate("abc")).toBeNil()
			T.expect(Kit.evaluate("1+")).toBeNil()
			T.expect(Kit.evaluate("1/0")).toBeNil()
			T.expect(Kit.evaluate("")).toBeNil()
			T.expect(Kit.evaluate("print(1)")).toBeNil()
		end)
		T.it("rounds, clamps and counts decimals", function()
			T.expect(Kit.round(0.1 + 0.2, 3)).toBe(0.3)
			T.expect(Kit.clamp(5, 0, 1)).toBe(1)
			T.expect(Kit.clamp(-5, 0)).toBe(0)
			T.expect(Kit.decimals(0.25)).toBe(2)
			T.expect(Kit.decimals(3)).toBe(0)
		end)
		T.itIf(lune, "falls back to Size offsets when no layout engine exists", function()
			local f = Instance.new("Frame")
			f.Size = UDim2.fromOffset(50, 20)
			local pos, size = Kit.geometry(f)
			T.expect(pos).toEqual(Vector2.zero)
			T.expect(size).toEqual(Vector2.new(50, 20))
			f.Size = UDim2.fromScale(1, 1)
			local _, scaled = Kit.geometry(f)
			T.expect(scaled).toEqual(Vector2.new(Kit.FALLBACK_SIZE, Kit.FALLBACK_SIZE))
		end)
		T.it("raises a popup subtree above its siblings", function()
			local f = Instance.new("Frame")
			local child = Instance.new("TextLabel")
			child.Parent = f
			Kit.raise(f, 500)
			T.expect(f.ZIndex).toBe(500)
			T.expect(child.ZIndex).toBe(501)
		end)
	end)

	T.describe("Button", function()
		T.it("constructs every variant unparented, with icon glyph and theme colours", function()
			for _, variant in { "primary", "secondary", "ghost", "danger" } do
				local b = Button.new({ text = "Speichern", variant = variant, icon = "+" })
				T.expect(b.instance:IsA("TextButton")).toBe(true)
				T.expect(b.instance.Parent).toBeNil()
				T.expect(b.instance.Text).toBe("+  Speichern")
				T.expect(b.instance.AutoButtonColor).toBe(false)
				T.expect(b.instance.Size.Y.Offset).toBe(Theme.metrics.rowHeight)
				b:destroy()
			end
			local primary = Button.new({ text = "OK", variant = "primary" })
			T.expect(primary.instance.BackgroundColor3).toEqual(colors.accent)
			local ghost = Button.new({ text = "Mehr", variant = "ghost" })
			T.expect(ghost.instance.BackgroundTransparency).toBe(1)
			local parent = Instance.new("Frame")
			local sized = Button.new({ text = "X", size = UDim2.fromOffset(80, 20), parent = parent })
			T.expect(sized.instance.Parent).toBe(parent)
			T.expect(sized.instance.Size).toEqual(UDim2.fromOffset(80, 20))
			primary:destroy()
			ghost:destroy()
			sized:destroy()
		end)
		T.itIf(lune, "fires onActivate, respects setEnabled and stops after destroy", function()
			local clicks = 0
			local b = Button.new({
				text = "Play",
				onActivate = function()
					clicks += 1
				end,
			})
			fire(b.instance, "Activated")
			T.expect(clicks).toBe(1)
			b:setEnabled(false)
			fire(b.instance, "Activated")
			T.expect(clicks).toBe(1)
			T.expect(b.instance.TextColor3).toEqual(colors.textMuted)
			T.expect(b.instance.Interactable).toBe(false)
			b:setEnabled(true)
			fire(b.instance, "Activated")
			T.expect(clicks).toBe(2)
			local inst = b.instance
			b:destroy()
			T.expect(inst.Parent).toBeNil()
			fire(inst, "Activated")
			T.expect(clicks).toBe(2)
		end)
		T.itIf(lune, "shows hover and pressed states", function()
			local b = Button.new({ text = "Hover" })
			T.expect(b.instance.BackgroundColor3).toEqual(colors.bg2)
			fire(b.instance, "MouseEnter")
			T.expect(b.instance.BackgroundColor3).toEqual(colors.bg3)
			fire(b.instance, "InputBegan", mouseInput())
			T.expect(b.instance.BackgroundColor3).toEqual(colors.bg4)
			fire(b.instance, "MouseLeave")
			T.expect(b.instance.BackgroundColor3).toEqual(colors.bg2)
			b:setText("Neu")
			T.expect(b.instance.Text).toBe("Neu")
			b:destroy()
		end)
		T.itIf(lune, "shows its tooltip after hovering", function()
			local host = makeHost()
			local saved = Tooltip.DELAY
			Tooltip.DELAY = 0.01
			local ok, err = pcall(function()
				local b = Button.new({ text = "?", tooltip = "Hilfe anzeigen", host = host, parent = host.root })
				fire(b.instance, "MouseEnter")
				T.expect(Tooltip.current(host)).toBeNil()
				task.wait(0.05)
				local tip = Tooltip.current(host)
				T.expect(tip).never.toBeNil()
				T.expect(((tip :: any).Text :: TextLabel).Text).toBe("Hilfe anzeigen")
				fire(b.instance, "MouseLeave")
				T.expect(Tooltip.current(host)).toBeNil()
				b:destroy()
			end)
			Tooltip.DELAY = saved
			if not ok then
				error(err, 0)
			end
		end)
	end)

	T.describe("IconButton", function()
		T.it("constructs a square glyph button and an image button", function()
			local g = IconButton.new({ glyph = "▶" })
			T.expect(g.instance.Size).toEqual(UDim2.fromOffset(Theme.metrics.rowHeight, Theme.metrics.rowHeight))
			T.expect(g.instance.Text).toBe("▶")
			local img = IconButton.new({ image = "rbxassetid://1234", size = 28 })
			T.expect(img.instance.Text).toBe("")
			T.expect(img.image).never.toBeNil()
			T.expect(img.image.Image).toBe("rbxassetid://1234")
			g:destroy()
			img:destroy()
		end)
		T.itIf(lune, "toggles, reports the state and updates without callbacks via setValue", function()
			local log, onChange = recorder()
			local activations = 0
			local b = IconButton.new({
				glyph = "↻",
				toggle = true,
				onChange = onChange,
				onActivate = function()
					activations += 1
				end,
			})
			fire(b.instance, "Activated")
			T.expect(log).toEqual({ call(true, true) })
			T.expect(b:getValue()).toBe(true)
			T.expect(activations).toBe(1)
			T.expect(b.instance.BackgroundColor3).toEqual(colors.accentDim)
			b:setValue(false)
			T.expect(#log).toBe(1)
			T.expect(b:getValue()).toBe(false)
			b:setEnabled(false)
			fire(b.instance, "Activated")
			T.expect(#log).toBe(1)
			T.expect(activations).toBe(1)
			b:destroy()
		end)
	end)

	T.describe("Label", function()
		T.it("applies variants, truncation and wrapping", function()
			local l = Label.new({ text = "Emitter" })
			T.expect(l.instance.TextTruncate).toBe(Enum.TextTruncate.AtEnd)
			T.expect(l.instance.TextColor3).toEqual(colors.text)
			T.expect(l.instance.TextSize).toBe(Theme.textSize.normal)
			local dim = Label.new({ text = "a", variant = "dim" })
			T.expect(dim.instance.TextColor3).toEqual(colors.textDim)
			local muted = Label.new({ text = "b", variant = "muted" })
			T.expect(muted.instance.TextColor3).toEqual(colors.textMuted)
			local wrapped = Label.new({ text = "lang", wrap = true })
			T.expect(wrapped.instance.TextWrapped).toBe(true)
			T.expect(wrapped.instance.AutomaticSize).toBe(Enum.AutomaticSize.Y)
			l:setValue("Beam")
			T.expect(l:getText()).toBe("Beam")
			l:setEnabled(false)
			T.expect(l.instance.TextColor3).toEqual(colors.textMuted)
			l:setVariant("title")
			T.expect(l.instance.TextSize).toBe(Theme.textSize.title)
			for _, w in { l, dim, muted, wrapped } do
				w:destroy()
			end
		end)
	end)

	T.describe("TextInput", function()
		T.it("constructs single- and multi-line inputs", function()
			local t = TextInput.new({ value = "Feuer", placeholder = "Name" })
			T.expect(t.box.ClearTextOnFocus).toBe(false)
			T.expect(t.box.PlaceholderText).toBe("Name")
			T.expect(t.box.Text).toBe("Feuer")
			T.expect(t.box.MultiLine).toBe(false)
			local m = TextInput.new({ multiline = true, height = 90 })
			T.expect(m.box.MultiLine).toBe(true)
			T.expect(m.box.TextWrapped).toBe(true)
			T.expect(m.instance.Size.Y.Offset).toBe(90)
			t:destroy()
			m:destroy()
		end)
		T.itIf(lune, "commits typed text on FocusLost, only when changed", function()
			local log, onChange = recorder()
			local submitted = {}
			local t = TextInput.new({
				value = "Feuer",
				onChange = onChange,
				onSubmit = function(text: string)
					table.insert(submitted, text)
				end,
			})
			t.box.Text = "Eis"
			fire(t.box, "FocusLost", false, nil)
			T.expect(log).toEqual({ call("Eis", true) })
			T.expect(t:getValue()).toBe("Eis")
			fire(t.box, "FocusLost", true, nil)
			T.expect(#log).toBe(1) -- unchanged
			T.expect(submitted).toEqual({ "Eis" })
			t:setValue("Wind")
			T.expect(t.box.Text).toBe("Wind")
			T.expect(#log).toBe(1)
			t:destroy()
		end)
		T.itIf(lune, "reverts on Escape", function()
			local log, onChange = recorder()
			local t = TextInput.new({ value = "A", onChange = onChange })
			t.box.Text = "B"
			fire(t.box, "FocusLost", false, keyInput(Enum.KeyCode.Escape))
			T.expect(t.box.Text).toBe("A")
			T.expect(#log).toBe(0)
			t:destroy()
		end)
		T.itIf(lune, "rejects invalid text with a red border", function()
			local log, onChange = recorder()
			local t = TextInput.new({
				value = "ok",
				onChange = onChange,
				validate = function(text: string): string?
					return if text == "" then "darf nicht leer sein" else nil
				end,
			})
			local stroke = t.instance:FindFirstChildOfClass("UIStroke") :: UIStroke
			t.box.Text = ""
			fire(t.box, "Changed:Text")
			T.expect(stroke.Color).toEqual(colors.error)
			fire(t.box, "FocusLost", true, nil)
			T.expect(#log).toBe(0)
			T.expect(t:getError()).toBe("darf nicht leer sein")
			t.box.Text = "neu"
			fire(t.box, "FocusLost", true, nil)
			T.expect(log).toEqual({ call("neu", true) })
			T.expect(t:getError()).toBeNil()
			T.expect(stroke.Color).toEqual(colors.border)
			t:destroy()
		end)
		T.itIf(lune, "reports keystrokes through onInput and highlights focus", function()
			local typed = {}
			local t = TextInput.new({
				onInput = function(text: string)
					table.insert(typed, text)
				end,
			})
			t.box.Text = "a"
			fire(t.box, "Changed:Text")
			fire(t.box, "Changed:Text") -- duplicate notifications are ignored
			t.box.Text = "ab"
			fire(t.box, "Changed:Text")
			T.expect(typed).toEqual({ "a", "ab" })
			fire(t.box, "Focused")
			local stroke = t.instance:FindFirstChildOfClass("UIStroke") :: UIStroke
			T.expect(stroke.Color).toEqual(colors.accent)
			t:focus(true)
			T.expect(t.box:IsFocused()).toBe(true)
			t:destroy()
		end)
	end)

	T.describe("NumberInput", function()
		T.it("shows the formatted value with suffix and label", function()
			local n = NumberInput.new({ value = 1.5, precision = 2, suffix = "s", label = "Dauer" })
			T.expect(n.box.Text).toBe("1.5s")
			T.expect(n.scrub.Text).toBe("Dauer")
			T.expect(n.box.ClearTextOnFocus).toBe(false)
			n:setValue(2.25)
			T.expect(n.box.Text).toBe("2.25s")
			n:setMixed(true)
			T.expect(n.box.Text).toBe("—")
			local grip = NumberInput.new({ value = 3 })
			T.expect(grip.scrub:FindFirstChild("Grip")).never.toBeNil()
			n:destroy()
			grip:destroy()
		end)
		T.itIf(lune, "commits typed values (expressions, clamping) and reverts invalid text", function()
			local log, onChange = recorder()
			local n = NumberInput.new({ value = 1, min = 0, max = 100, precision = 2, onChange = onChange })
			fire(n.box, "Focused")
			T.expect(n.box.Text).toBe("1")
			n.box.Text = "2*3"
			fire(n.box, "FocusLost", true, nil)
			T.expect(log).toEqual({ call(6, true) })
			T.expect(n.box.Text).toBe("6")
			n.box.Text = "5000"
			fire(n.box, "FocusLost", true, nil)
			T.expect(n:getValue()).toBe(100)
			n.box.Text = "abc"
			fire(n.box, "FocusLost", true, nil)
			T.expect(n.box.Text).toBe("100")
			T.expect(#log).toBe(2)
			n.box.Text = "7"
			fire(n.box, "FocusLost", false, keyInput(Enum.KeyCode.Escape))
			T.expect(n:getValue()).toBe(100)
			T.expect(n.box.Text).toBe("100")
			n.box.Text = "0,125"
			fire(n.box, "FocusLost", true, nil)
			T.expect(n:getValue()).toBe(0.13)
			n:destroy()
		end)
		T.itIf(lune, "scrubs by step per pixel and groups the drag into one final change", function()
			local host = makeHost()
			local log, onChange = recorder()
			local n = NumberInput.new({
				value = 1,
				step = 0.1,
				precision = 2,
				label = "X",
				host = host,
				onChange = onChange,
				parent = host.root,
			})
			drag(host, n.scrub, Vector2.new(10, 5), { Vector2.new(20, 5), Vector2.new(30, 5) })
			T.expect(log).toEqual({ call(2, false), call(3, false), call(3, true) })
			T.expect(n:getValue()).toBe(3)
			T.expect(n.box.Text).toBe("3")
			T.expect(n:isDragging()).toBe(false)
			-- dragging left
			table.clear(log)
			drag(host, n.scrub, Vector2.new(50, 5), { Vector2.new(35, 5) })
			T.expect(log).toEqual({ call(1.5, false), call(1.5, true) })
			n:destroy()
		end)
		T.itIf(lune, "uses shift ×10 and ctrl ×0.1 and clamps while scrubbing", function()
			local host = makeHost()
			local log, onChange = recorder()
			local n =
				NumberInput.new({ value = 0, step = 1, max = 40, precision = 2, host = host, onChange = onChange })
			drag(host, n.scrub, Vector2.new(0, 0), { Vector2.new(3, 0) }, { Shift = true })
			T.expect(n:getValue()).toBe(30)
			drag(host, n.scrub, Vector2.new(0, 0), { Vector2.new(5, 0) }, { Ctrl = true })
			T.expect(n:getValue()).toBe(30.5)
			drag(host, n.scrub, Vector2.new(0, 0), { Vector2.new(100, 0) })
			T.expect(n:getValue()).toBe(40)
			local finals = 0
			for _, entry in log do
				if entry[2] == true then
					finals += 1
				end
			end
			T.expect(finals).toBe(3)
			n:destroy()
		end)
		T.itIf(lune, "focuses the field on a click without movement and ignores input when disabled", function()
			local host = makeHost()
			local log, onChange = recorder()
			local n = NumberInput.new({ value = 5, step = 1, host = host, onChange = onChange })
			drag(host, n.scrub, Vector2.new(10, 10), {})
			T.expect(n.box:IsFocused()).toBe(true)
			T.expect(#log).toBe(0)
			n.box:ReleaseFocus()
			n:setEnabled(false)
			drag(host, n.scrub, Vector2.new(0, 0), { Vector2.new(50, 0) })
			T.expect(#log).toBe(0)
			T.expect(n:getValue()).toBe(5)
			n:destroy()
		end)
		T.itIf(lune, "commits the drag when the widget loses focus or on InputEnded", function()
			local host = makeHost()
			local log, onChange = recorder()
			local n = NumberInput.new({ value = 0, step = 1, precision = 0, host = host, onChange = onChange })
			host.widget.mouse = Vector2.new(0, 0)
			fire(n.scrub, "InputBegan", mouseInput())
			host.widget.mouse = Vector2.new(8, 0)
			ctx.fakes:step(1 / 60)
			T.expect(n:isDragging()).toBe(true)
			host.widget.WindowFocusReleased:Fire()
			T.expect(log).toEqual({ call(8, false), call(8, true) })
			table.clear(log)
			local input = mouseInput()
			host.widget.mouse = Vector2.new(0, 0)
			fire(n.scrub, "InputBegan", input)
			host.widget.mouse = Vector2.new(4, 0)
			ctx.fakes:step(1 / 60)
			fire(n.scrub, "InputEnded", input)
			T.expect(log).toEqual({ call(12, false), call(12, true) })
			n:destroy()
		end)
	end)

	T.describe("Slider", function()
		T.it("constructs track, fill, thumb and value field", function()
			local s = Slider.new({ value = 0.25, min = 0, max = 1 })
			T.expect(s.fill.Size).toEqual(UDim2.fromScale(0.25, 1))
			T.expect(s.thumb.Position).toEqual(UDim2.fromScale(0.25, 0.5))
			T.expect(s.box).never.toBeNil()
			T.expect(s.box.Text).toBe("0.25")
			s:setValue(2)
			T.expect(s:getValue()).toBe(1)
			local bare = Slider.new({ showValue = false })
			T.expect(bare.box).toBeNil()
			s:destroy()
			bare:destroy()
		end)
		T.itIf(lune, "jumps to a clicked position and drags with step snapping", function()
			local host = makeHost()
			local log, onChange = recorder()
			-- In Lune the rail measures 100 px wide at x = 0 (geometry fallback).
			local s = Slider.new({ value = 0, min = 0, max = 1, host = host, onChange = onChange })
			drag(host, s.hit, Vector2.new(50, 5), {})
			T.expect(log).toEqual({ call(0.5, false), call(0.5, true) })
			s:destroy()

			table.clear(log)
			local stepped = Slider.new({ value = 0, min = 0, max = 10, step = 1, host = host, onChange = onChange })
			drag(host, stepped.hit, Vector2.new(20, 5), { Vector2.new(73, 5), Vector2.new(250, 5) })
			T.expect(log).toEqual({ call(2, false), call(7, false), call(10, false), call(10, true) })
			T.expect(stepped.fill.Size).toEqual(UDim2.fromScale(1, 1))
			stepped:destroy()
		end)
		T.itIf(lune, "accepts typed values and ignores input when disabled", function()
			local host = makeHost()
			local log, onChange = recorder()
			local s = Slider.new({ value = 0, min = 0, max = 1, host = host, onChange = onChange })
			local box = s.box :: TextBox
			box.Text = "0.3"
			fire(box, "FocusLost", true, nil)
			T.expect(log).toEqual({ call(0.3, true) })
			s:setEnabled(false)
			drag(host, s.hit, Vector2.new(90, 5), {})
			T.expect(#log).toBe(1)
			T.expect(s:getValue()).toBe(0.3)
			s:destroy()
		end)
	end)

	T.describe("Checkbox", function()
		T.it("constructs with label and check mark", function()
			local cb = Checkbox.new({ value = true, text = "Schleife" })
			T.expect(cb.mark.Text).toBe("✓")
			T.expect(cb.label.Text).toBe("Schleife")
			T.expect(cb.box.BackgroundColor3).toEqual(colors.accent)
			cb:setValue(false)
			T.expect(cb.mark.Text).toBe("")
			cb:destroy()
		end)
		T.itIf(lune, "toggles on Activated and supports the mixed state", function()
			local log, onChange = recorder()
			local cb = Checkbox.new({ value = false, onChange = onChange })
			fire(cb.instance, "Activated")
			T.expect(log).toEqual({ call(true, true) })
			fire(cb.instance, "Activated")
			T.expect(log[2]).toEqual({ false, true })
			cb:setMixed(true)
			T.expect(cb.mark.Text).toBe("–")
			fire(cb.instance, "Activated")
			T.expect(log[3]).toEqual({ true, true })
			cb:setValue(false)
			T.expect(#log).toBe(3)
			cb:setEnabled(false)
			fire(cb.instance, "Activated")
			T.expect(#log).toBe(3)
			cb:destroy()
		end)
	end)

	T.describe("Dropdown", function()
		local function popupOf(host: any): Instance?
			return childNamed(host.root, "AstraDropdownPopup")
		end

		T.it("shows the current option or the placeholder", function()
			local d = Dropdown.new({ options = { "Linear", "Quad" }, value = "Quad" })
			T.expect(d.label.Text).toBe("Quad")
			d:setValue("nope")
			T.expect(d.label.Text).toBe("Auswählen…")
			d:setOptions({ { value = 1, label = "Eins" } :: any, { 2 :: any, "Zwei", "positional" } })
			d:setValue(2)
			T.expect(d.label.Text).toBe("Zwei")
			d:destroy()
		end)
		T.itIf(lune, "opens a popup in host.root and chooses an option", function()
			local host = makeHost()
			local log, onChange = recorder()
			local d = Dropdown.new({
				options = {
					{ value = "Additive", label = "Additiv", description = "Hellt auf" } :: any,
					{ value = "Normal", label = "Normal" },
				},
				value = "Normal",
				host = host,
				onChange = onChange,
				parent = host.root,
			})
			fire(d.instance, "Activated")
			T.expect(d:isOpen()).toBe(true)
			T.expect(popupOf(host)).never.toBeNil()
			T.expect(childNamed(host.root, "AstraDropdownOverlay")).never.toBeNil()
			T.expect(#d.items).toBe(2)
			T.expect(d.items[1].button:FindFirstChild("Description")).never.toBeNil()
			T.expect(d.search).toBeNil() -- only 2 options
			T.expect((popupOf(host) :: any).ZIndex).toBeGreaterThan(Kit.Z.popup)
			fire(d.items[1].button, "Activated")
			T.expect(log).toEqual({ call("Additive", true) })
			T.expect(d.label.Text).toBe("Additiv")
			T.expect(d:isOpen()).toBe(false)
			T.expect(popupOf(host)).toBeNil()
			T.expect(childNamed(host.root, "AstraDropdownOverlay")).toBeNil()
			-- choosing the current value again does not fire
			d:open()
			fire(d.items[1].button, "Activated")
			T.expect(#log).toBe(1)
			d:destroy()
		end)
		T.itIf(lune, "closes on outside click, focus loss, second click and destroy", function()
			local host = makeHost()
			local log, onChange = recorder()
			local d = Dropdown.new({ options = { "A", "B" }, host = host, onChange = onChange })
			d:open()
			fire(d.overlay, "Activated")
			T.expect(d:isOpen()).toBe(false)
			d:open()
			host.widget.WindowFocusReleased:Fire()
			T.expect(d:isOpen()).toBe(false)
			fire(d.instance, "Activated")
			T.expect(d:isOpen()).toBe(true)
			fire(d.instance, "Activated")
			T.expect(d:isOpen()).toBe(false)
			d:open()
			d:setEnabled(false)
			T.expect(d:isOpen()).toBe(false)
			fire(d.instance, "Activated")
			T.expect(d:isOpen()).toBe(false)
			d:setEnabled(true)
			d:open()
			d:destroy()
			T.expect(popupOf(host)).toBeNil()
			T.expect(#log).toBe(0)
		end)
		T.itIf(lune, "filters long option lists with a search box", function()
			local host = makeHost()
			local log, onChange = recorder()
			local names = { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Circular", "Back" }
			local d = Dropdown.new({ options = names, host = host, onChange = onChange })
			d:open()
			T.expect(d.search).never.toBeNil()
			T.expect(#d.items).toBe(9)
			local box = d.search.box
			box.Text = "qu"
			fire(box, "Changed:Text")
			T.expect(#d.items).toBe(3)
			box.Text = "zzz"
			fire(box, "Changed:Text")
			T.expect(#d.items).toBe(0)
			T.expect(d.list:FindFirstChild("Empty")).never.toBeNil()
			box.Text = "back"
			fire(box, "Changed:Text")
			T.expect(#d.items).toBe(1)
			fire(d.items[1].button, "Activated")
			T.expect(log).toEqual({ call("Back", true) })
			d:destroy()
		end)
		T.it("does nothing without a host", function()
			local d = Dropdown.new({ options = { "A" } })
			d:open()
			T.expect(d:isOpen()).toBe(false)
			d:destroy()
		end)
	end)

	T.describe("SearchBox", function()
		T.it("constructs with magnifier, placeholder and hidden clear button", function()
			local s = SearchBox.new({ placeholder = "Suchen…" })
			T.expect(s.instance:FindFirstChild("Magnifier")).never.toBeNil()
			T.expect(s.box.PlaceholderText).toBe("Suchen…")
			T.expect(s.box.ClearTextOnFocus).toBe(false)
			T.expect(s.clearButton.Visible).toBe(false)
			s:destroy()
		end)
		T.itIf(lune, "reports every text change and clears", function()
			local changes = {}
			local submitted = {}
			local s = SearchBox.new({
				onChange = function(text: string)
					table.insert(changes, text)
				end,
				onSubmit = function(text: string)
					table.insert(submitted, text)
				end,
			})
			s.box.Text = "f"
			fire(s.box, "Changed:Text")
			s.box.Text = "fe"
			fire(s.box, "Changed:Text")
			fire(s.box, "Changed:Text")
			T.expect(changes).toEqual({ "f", "fe" })
			T.expect(s.clearButton.Visible).toBe(true)
			fire(s.box, "FocusLost", true, nil)
			T.expect(submitted).toEqual({ "fe" })
			fire(s.clearButton, "Activated")
			T.expect(s.box.Text).toBe("")
			T.expect(changes[3]).toBe("")
			T.expect(s.clearButton.Visible).toBe(false)
			s.box.Text = "x"
			fire(s.box, "Changed:Text")
			fire(s.box, "FocusLost", false, keyInput(Enum.KeyCode.Escape))
			T.expect(s.box.Text).toBe("")
			T.expect(changes).toEqual({ "f", "fe", "", "x", "" })
			s:setValue("still")
			T.expect(#changes).toBe(5)
			s:destroy()
		end)
	end)

	T.describe("Tooltip", function()
		T.itIf(lune, "shows after the hover delay and hides on leave", function()
			local host = makeHost()
			local target = Instance.new("Frame")
			target.Parent = host.root
			local handle = Tooltip.attach(host, target, "Rate in Partikeln/s", { delay = 0.01 })
			fire(target, "MouseEnter")
			T.expect(Tooltip.current(host)).toBeNil()
			task.wait(0.05)
			local tip = Tooltip.current(host)
			T.expect(tip).never.toBeNil()
			T.expect((tip :: any).Parent).toBe(host.root)
			T.expect((tip :: any).ZIndex).toBe(Kit.Z.tooltip)
			fire(target, "MouseLeave")
			T.expect(Tooltip.current(host)).toBeNil()
			-- leaving before the delay cancels it
			fire(target, "MouseEnter")
			fire(target, "MouseLeave")
			task.wait(0.05)
			T.expect(Tooltip.current(host)).toBeNil()
			-- clicking hides it
			fire(target, "MouseEnter")
			task.wait(0.05)
			T.expect(Tooltip.current(host)).never.toBeNil()
			fire(target, "InputBegan", mouseInput())
			T.expect(Tooltip.current(host)).toBeNil()
			handle:Disconnect()
			fire(target, "MouseEnter")
			task.wait(0.05)
			T.expect(Tooltip.current(host)).toBeNil()
		end)
		T.itIf(lune, "evaluates text functions and keeps one tooltip per host", function()
			local host = makeHost()
			local a = Instance.new("Frame")
			local b = Instance.new("Frame")
			a.Parent = host.root
			b.Parent = host.root
			local value = 1
			Tooltip.attach(host, a, function()
				return "Wert " .. tostring(value)
			end, { delay = 0.01 })
			Tooltip.attach(host, b, function()
				return nil
			end, { delay = 0.01 })
			value = 2
			fire(a, "MouseEnter")
			task.wait(0.05)
			local tip = Tooltip.current(host) :: any
			T.expect(tip.Text.Text).toBe("Wert 2")
			Tooltip.show(host, "anderer", b)
			T.expect(countNamed(host.root, "AstraTooltip")).toBe(1)
			fire(b, "MouseEnter") -- text function returns nil: nothing new is shown
			Tooltip.hide(host)
			task.wait(0.05)
			T.expect(Tooltip.current(host)).toBeNil()
		end)
	end)

	T.describe("Toast", function()
		T.itIf(lune, "stacks toasts bottom-right and dismisses them", function()
			local host = makeHost()
			local t1 = Toast.show(host, "Gespeichert", "success", 0)
			local t2 = Toast.show(host, "Fehler", "error", 0)
			local stack = childNamed(host.root, "AstraToasts") :: Frame
			T.expect(stack).never.toBeNil()
			T.expect(stack.AnchorPoint).toEqual(Vector2.new(1, 1))
			T.expect(#Toast.list(host)).toBe(2)
			T.expect((t2.instance:FindFirstChild("Severity") :: Frame).BackgroundColor3).toEqual(colors.error)
			T.expect((t1.instance:FindFirstChild("Message") :: TextLabel).Text).toBe("Gespeichert")
			T.expect(t2.instance.LayoutOrder).toBeGreaterThan(t1.instance.LayoutOrder)
			fire(t1.instance:FindFirstChild("Close"), "Activated")
			T.expect(t1:isOpen()).toBe(false)
			T.expect(t1.instance.Parent).toBeNil()
			T.expect(#Toast.list(host)).toBe(1)
			Toast.clear(host)
			T.expect(#Toast.list(host)).toBe(0)
		end)
		T.itIf(lune, "auto-dismisses after the duration and caps the stack", function()
			local host = makeHost()
			local t = Toast.show(host, "kurz", "info", 0.01)
			T.expect(t:isOpen()).toBe(true)
			task.wait(0.05)
			T.expect(t:isOpen()).toBe(false)
			for i = 1, Toast.MAX_VISIBLE + 2 do
				Toast.show(host, "Nachricht " .. i, "warning", 0)
			end
			local list = Toast.list(host)
			T.expect(#list).toBe(Toast.MAX_VISIBLE)
			T.expect(list[1].message).toBe("Nachricht 3")
			Toast.clear(host)
		end)
	end)

	T.describe("Dialog", function()
		T.itIf(lune, "confirm resolves once with true or false", function()
			local host = makeHost()
			local results = {}
			local d = Dialog.confirm(host, "Löschen?", "Wirklich?", "Löschen", function(ok: boolean)
				table.insert(results, ok)
			end, { danger = true })
			T.expect(d.instance.Parent).toBe(host.root)
			T.expect(d.instance.Active).toBe(true)
			T.expect(d.confirmButton.instance.Text).toBe("Löschen")
			T.expect(d.cancelButton.instance.Text).toBe("Abbrechen")
			T.expect(Dialog.count(host)).toBe(1)
			fire(d.confirmButton.instance, "Activated")
			T.expect(results).toEqual({ true })
			T.expect(d:isOpen()).toBe(false)
			T.expect(d.instance.Parent).toBeNil()
			d:close()
			T.expect(results).toEqual({ true })
			local d2 = Dialog.confirm(host, "Frage", "?", nil, function(ok: boolean)
				table.insert(results, ok)
			end)
			fire(d2.cancelButton.instance, "Activated")
			T.expect(results).toEqual({ true, false })
			T.expect(Dialog.count(host)).toBe(0)
		end)
		T.itIf(lune, "prompt returns typed text, validates and cancels with nil", function()
			local host = makeHost()
			local results = {}
			local function onResult(text: string?)
				table.insert(results, text or "<nil>")
			end
			local d = Dialog.prompt(host, "Umbenennen", "Name", "Feuer", onResult, {
				validate = function(text: string): string?
					return if text == "" then "Name fehlt" else nil
				end,
			})
			T.expect(d.input.box.Text).toBe("Feuer")
			T.expect(d.input.box:IsFocused()).toBe(true)
			d.input.box.Text = ""
			fire(d.confirmButton.instance, "Activated")
			T.expect(#results).toBe(0)
			T.expect(d.input:getError()).toBe("Name fehlt")
			T.expect(d:isOpen()).toBe(true)
			d.input.box.Text = "Eis"
			fire(d.input.box, "FocusLost", true, nil) -- Enter submits
			T.expect(results).toEqual({ "Eis" })
			T.expect(d:isOpen()).toBe(false)
			local d2 = Dialog.prompt(host, "Name", nil, nil, onResult)
			fire(d2.cancelButton.instance, "Activated")
			T.expect(results).toEqual({ "Eis", "<nil>" })
		end)
		T.itIf(lune, "text dialog shows selectable read-only text and restores edits", function()
			local host = makeHost()
			local json = '{\n  "name": "Feuerball",\n  "duration": 1.5\n}'
			local d = Dialog.text(host, "Export", json, { readOnly = true })
			local box = d.box :: TextBox
			T.expect(box.Text).toBe(json)
			T.expect(box.TextEditable).toBe(true)
			T.expect(box.ClearTextOnFocus).toBe(false)
			T.expect(box.MultiLine).toBe(true)
			T.expect(box:IsFocused()).toBe(true) -- selected on open for Ctrl+A / Ctrl+C
			T.expect(box.SelectionStart).toBe(1)
			T.expect(box.CursorPosition).toBe(#json + 1)
			box.Text = "kaputt"
			fire(box, "Changed:Text")
			T.expect(box.Text).toBe(json)
			fire(d.selectButton.instance, "Activated")
			T.expect(box:IsFocused()).toBe(true)
			fire(d.closeButton.instance, "Activated")
			T.expect(d:isOpen()).toBe(false)
			T.expect(childNamed(host.root, "AstraDialog")).toBeNil()
		end)
		T.itIf(lune, "editable text dialog returns the edited text and stacks above other dialogs", function()
			local host = makeHost()
			local got: { any } = {}
			local under = Dialog.confirm(host, "Unten", "", "OK")
			local d = Dialog.text(host, "Import", "", {
				readOnly = false,
				confirmText = "Importieren",
				onResult = function(text: string?)
					table.insert(got, text)
				end,
			})
			T.expect(d.instance.ZIndex).toBeGreaterThan(under.instance.ZIndex)
			d.box.Text = '{"a":1}'
			fire(d.box, "Changed:Text")
			T.expect(d.box.Text).toBe('{"a":1}')
			fire(d.confirmButton.instance, "Activated")
			T.expect(got).toEqual({ '{"a":1}' })
			under:close()
			T.expect(Dialog.count(host)).toBe(0)
		end)
	end)
end
