--!strict
-- Cross-widget contract checks for UI/Widgets (review pass): construction conventions (unparented root,
-- props.parent, props.enabled = false), setValue never fires callbacks, destroy() removes everything including the
-- Heartbeat connection of a drag in progress, external updates while a field is focused, overlay layering in
-- host.root (ZIndexBehavior.Sibling), overlays of destroyed owners, the callback `final` flag, Theme-only colours
-- and the Tree drop-target bookkeeping. Rendering, layout and real mouse input are NOT verified here.
return function(T: any, use: (string) -> any, ctx: any)
	local Theme = use("Plugin.UI.Theme")
	local Kit = use("Plugin.UI.Widgets.ControlKit")
	local Tooltip = use("Plugin.UI.Widgets.Tooltip")
	local Toast = use("Plugin.UI.Widgets.Toast")
	local Dialog = use("Plugin.UI.Widgets.Dialog")

	local W: { [string]: any } = {}
	for _, name in
		{
			"Button",
			"IconButton",
			"Label",
			"TextInput",
			"NumberInput",
			"Slider",
			"Checkbox",
			"Dropdown",
			"SearchBox",
			"Panel",
			"Toolbar",
			"ScrollList",
			"Tree",
			"Splitter",
			"Tabs",
			"PropertyRow",
			"Section",
			"Vector3Input",
			"Vector2Input",
			"NumberRangeInput",
			"ColorSwatch",
			"AssetInput",
		}
	do
		W[name] = use("Plugin.UI.Widgets." .. name)
	end

	local isLune = ctx.environment == "lune"

	-- helpers ----------------------------------------------------------------------------------------------------

	-- mixed-type array (the old type solver infers literal arrays from their first element)
	local function tuple(...: any): { any }
		return { ... }
	end

	local function fire(inst: any, event: string, ...: any)
		ctx.fakes:signalFor(inst, event):Fire(...)
	end

	local function mouseInput(): any
		local input: any = {
			UserInputType = Enum.UserInputType.MouseButton1,
			UserInputState = Enum.UserInputState.Begin,
			Position = Vector3.new(0, 0, 0),
			KeyCode = nil, -- Lune's enum database has no KeyCode.Unknown
		}
		function input.IsModifierKeyDown(_self: any, _key: any): boolean
			return false
		end
		return input
	end

	local function newHost(): any
		local root = Instance.new("Frame")
		root.Name = "Root"
		root.Size = UDim2.fromOffset(800, 600)
		if isLune then
			local widget = ctx.plugin.newWidget("AstraVFX_Contract")
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

	local function heartbeatCount(): number
		return ctx.fakes.heartbeat:connectionCount()
	end

	-- Starts a drag on `gui` (press + one Heartbeat with the mouse moved by `delta`); returns the press input.
	local function beginDrag(host: any, gui: any, from: Vector2, delta: Vector2): any
		host.widget.mouse = from
		local input = mouseInput()
		fire(gui, "InputBegan", input)
		host.widget.mouse = from + delta
		ctx.fakes:step(1 / 60)
		return input
	end

	local function treeItems(): { any }
		return {
			{ id = "a", label = "A", depth = 0, expandable = true, expanded = true, selected = true },
			{ id = "b", label = "B", depth = 1 },
			{ id = "c", label = "C", depth = 0 },
		}
	end

	-- One factory per widget: (host, extra props) -> widget. Extra props are merged over the defaults.
	local function merge(base: { [string]: any }, extra: { [string]: any }?): { [string]: any }
		local out = table.clone(base)
		local e: { [string]: any } = extra or {}
		for k, v in e do
			out[k] = v
		end
		return out
	end

	local FACTORIES: { { name: string, make: (host: any, extra: { [string]: any }?) -> any } } = {
		{
			name = "Button",
			make = function(_host: any, extra: { [string]: any }?)
				return W.Button.new(merge({ text = "OK" }, extra))
			end,
		},
		{
			name = "IconButton",
			make = function(_host: any, extra: { [string]: any }?)
				return W.IconButton.new(merge({ glyph = "▶" }, extra))
			end,
		},
		{
			name = "Label",
			make = function(_host: any, extra: { [string]: any }?)
				return W.Label.new(merge({ text = "Rate" }, extra))
			end,
		},
		{
			name = "TextInput",
			make = function(host: any, extra: { [string]: any }?)
				return W.TextInput.new(merge({ value = "a", host = host }, extra))
			end,
		},
		{
			name = "NumberInput",
			make = function(host: any, extra: { [string]: any }?)
				return W.NumberInput.new(merge({ value = 1, label = "X", host = host }, extra))
			end,
		},
		{
			name = "Slider",
			make = function(host: any, extra: { [string]: any }?)
				return W.Slider.new(merge({ value = 0.5, host = host }, extra))
			end,
		},
		{
			name = "Checkbox",
			make = function(host: any, extra: { [string]: any }?)
				return W.Checkbox.new(merge({ value = true, text = "Loop", host = host }, extra))
			end,
		},
		{
			name = "Dropdown",
			make = function(host: any, extra: { [string]: any }?)
				return W.Dropdown.new(merge({ options = { "A", "B" }, value = "A", host = host }, extra))
			end,
		},
		{
			name = "SearchBox",
			make = function(_host: any, extra: { [string]: any }?)
				return W.SearchBox.new(merge({}, extra))
			end,
		},
		{
			name = "Panel",
			make = function(_host: any, extra: { [string]: any }?)
				return W.Panel.new(merge({ title = "Explorer" }, extra))
			end,
		},
		{
			name = "Toolbar",
			make = function(_host: any, extra: { [string]: any }?)
				return W.Toolbar.new(merge({ items = { W.IconButton.new({ glyph = "▶" }), "separator" } }, extra))
			end,
		},
		{
			name = "ScrollList",
			make = function(_host: any, extra: { [string]: any }?)
				return W.ScrollList.new(merge({
					count = 3,
					render = function(_row: TextButton, _index: number) end,
				}, extra))
			end,
		},
		{
			name = "Tree",
			make = function(host: any, extra: { [string]: any }?)
				return W.Tree.new(merge({
					items = treeItems,
					host = host,
					onDragDrop = function() end,
				}, extra))
			end,
		},
		{
			name = "Splitter",
			make = function(host: any, extra: { [string]: any }?)
				return W.Splitter.new(merge({ host = host, size = UDim2.fromOffset(400, 200) }, extra))
			end,
		},
		{
			name = "Tabs",
			make = function(_host: any, extra: { [string]: any }?)
				return W.Tabs.new(merge({ tabs = { { id = "a", text = "A" }, { id = "b", text = "B" } } }, extra))
			end,
		},
		{
			name = "PropertyRow",
			make = function(host: any, extra: { [string]: any }?)
				return W.PropertyRow.new(merge({
					label = "Rate",
					host = host,
					field = W.NumberInput.new({ value = 1, host = host }),
					value = 1,
					default = 1,
					keyframe = "none",
				}, extra))
			end,
		},
		{
			name = "Section",
			make = function(_host: any, extra: { [string]: any }?)
				return W.Section.new(merge({ title = "Emission" }, extra))
			end,
		},
		{
			name = "Vector3Input",
			make = function(host: any, extra: { [string]: any }?)
				return W.Vector3Input.new(merge({ value = { 1, 2, 3 }, host = host }, extra))
			end,
		},
		{
			name = "Vector2Input",
			make = function(host: any, extra: { [string]: any }?)
				return W.Vector2Input.new(merge({ value = { 1, 2 }, host = host }, extra))
			end,
		},
		{
			name = "NumberRangeInput",
			make = function(host: any, extra: { [string]: any }?)
				return W.NumberRangeInput.new(merge({ value = { 1, 2 }, host = host }, extra))
			end,
		},
		{
			name = "ColorSwatch",
			make = function(host: any, extra: { [string]: any }?)
				return W.ColorSwatch.new(merge({ value = "#FF8A3D", host = host }, extra))
			end,
		},
		{
			name = "AssetInput",
			make = function(host: any, extra: { [string]: any }?)
				return W.AssetInput.new(merge({ value = "rbxassetid://1", host = host }, extra))
			end,
		},
	}

	-- construction -----------------------------------------------------------------------------------------------

	T.describe("Widget contract: construction", function()
		T.it("every widget builds an unparented GuiObject root, honours props.parent and destroys cleanly", function()
			local host = newHost()
			for _, f in FACTORIES do
				local w = f.make(host, nil)
				T.expect(typeof(w.instance)).toBe("Instance")
				T.expect(w.instance:IsA("GuiObject")).toBe(true)
				if w.instance.Parent ~= nil then
					error(f.name .. ": root must not be parented without props.parent", 0)
				end
				T.expect(type(w.setEnabled)).toBe("function")
				T.expect(type(w.destroy)).toBe("function")
				w:destroy()
				w:destroy() -- idempotent

				local parent = Instance.new("Frame")
				local parented = f.make(host, { parent = parent })
				if parented.instance.Parent ~= parent then
					error(f.name .. ": props.parent was not applied", 0)
				end
				local inst = parented.instance
				parented:destroy()
				if inst.Parent ~= nil or #parent:GetChildren() ~= 0 then
					error(f.name .. ": destroy() left instances behind", 0)
				end
			end
		end)

		T.it("every widget accepts props.enabled = false", function()
			local host = newHost()
			for _, f in FACTORIES do
				local w = f.make(host, { enabled = false })
				local disabled = if w._enabled ~= nil then w._enabled == false else w.instance.Interactable == false
				if not disabled then
					error(f.name .. ": props.enabled = false was ignored", 0)
				end
				w:setEnabled(true)
				w:destroy()
			end
		end)
	end)

	-- setValue ---------------------------------------------------------------------------------------------------

	T.describe("Widget contract: setValue", function()
		T.itIf(isLune, "never fires callbacks", function()
			local host = newHost()
			local calls: { string } = {}
			local function spy(name: string): () -> ()
				return function()
					table.insert(calls, name)
				end
			end
			local cases: { { name: string, widget: any, value: any, expected: any? } } = {
				{
					name = "IconButton",
					widget = W.IconButton.new({ glyph = "↻", toggle = true, onChange = spy("IconButton") }),
					value = true,
				},
				{
					name = "TextInput",
					widget = W.TextInput.new({
						value = "a",
						onChange = spy("TextInput"),
						onInput = spy("TextInput.onInput"),
						onSubmit = spy("TextInput.onSubmit"),
					}),
					value = "b",
				},
				{
					name = "NumberInput",
					widget = W.NumberInput.new({ value = 1, onChange = spy("NumberInput") }),
					value = 5,
				},
				{
					name = "Slider",
					widget = W.Slider.new({ value = 0, onChange = spy("Slider") }),
					value = 0.75,
				},
				{
					name = "Checkbox",
					widget = W.Checkbox.new({ value = false, onChange = spy("Checkbox") }),
					value = true,
				},
				{
					name = "Dropdown",
					widget = W.Dropdown.new({
						options = { "A", "B" },
						value = "A",
						host = host,
						onChange = spy("Dropdown"),
					}),
					value = "B",
				},
				{
					name = "SearchBox",
					widget = W.SearchBox.new({ onChange = spy("SearchBox"), onSubmit = spy("SearchBox.onSubmit") }),
					value = "feuer",
				},
				{
					name = "Tabs",
					widget = W.Tabs.new({
						tabs = { { id = "a", text = "A" }, { id = "b", text = "B" } },
						onChange = spy("Tabs"),
					}),
					value = "b",
				},
				{
					name = "Section",
					widget = W.Section.new({ title = "S", onToggle = spy("Section") }),
					value = false,
				},
				{
					name = "Splitter",
					widget = W.Splitter.new({ size = UDim2.fromOffset(400, 200), onChange = spy("Splitter") }),
					value = 0.25,
				},
				{
					name = "PropertyRow",
					widget = W.PropertyRow.new({
						label = "Rate",
						field = W.NumberInput.new({ value = 1, onChange = spy("PropertyRow.field") }),
						value = 1,
						default = 1,
						onReset = spy("PropertyRow.onReset"),
						onKeyframe = spy("PropertyRow.onKeyframe"),
						keyframe = "none",
					}),
					value = 3,
				},
				{
					name = "Vector3Input",
					widget = W.Vector3Input.new({ value = { 0, 0, 0 }, onChange = spy("Vector3Input") }),
					value = { 4, 5, 6 },
				},
				{
					name = "NumberRangeInput",
					widget = W.NumberRangeInput.new({ value = { 0, 1 }, onChange = spy("NumberRangeInput") }),
					value = { 5, 2 },
					expected = { 2, 5 },
				},
				{
					name = "ColorSwatch",
					widget = W.ColorSwatch.new({
						value = "#FF0000",
						onChange = spy("ColorSwatch"),
						onPick = spy("ColorSwatch.onPick"),
					}),
					value = "#00FF00",
				},
				{
					name = "AssetInput",
					widget = W.AssetInput.new({ value = "", host = host, onChange = spy("AssetInput") }),
					value = "rbxassetid://42",
				},
			}
			for _, case in cases do
				local w = case.widget
				w:setValue(case.value)
				-- the engine fires Text change signals for programmatic Text writes; simulate them
				for _, inst in w.instance:GetDescendants() do
					if inst:IsA("TextBox") then
						fire(inst, "Changed:Text")
					end
				end
				if type(w.getValue) == "function" then
					T.expect(w:getValue()).toEqual(if case.expected ~= nil then case.expected else case.value)
				end
			end
			-- an open dropdown re-renders without firing either
			local dropdown = cases[6].widget
			dropdown:open()
			dropdown:setValue("A")
			T.expect(calls).toEqual({})
			for _, case in cases do
				case.widget:destroy()
			end
		end)
	end)

	-- drags and destroy ------------------------------------------------------------------------------------------

	T.describe("Widget contract: drags", function()
		T.itIf(isLune, "destroy() during a drag disconnects the Heartbeat poll and closes the gesture", function()
			local host = newHost()
			local baseline = heartbeatCount()

			local log: { { any } } = {}
			local number = W.NumberInput.new({
				value = 0,
				step = 1,
				precision = 0,
				label = "X",
				host = host,
				onChange = function(v: number, final: boolean)
					table.insert(log, tuple(v, final))
				end,
			})
			beginDrag(host, number.scrub, Vector2.new(0, 0), Vector2.new(6, 0))
			T.expect(number:isDragging()).toBe(true)
			T.expect(heartbeatCount()).toBe(baseline + 1)
			number:destroy()
			T.expect(heartbeatCount()).toBe(baseline)
			T.expect(log[#log]).toEqual(tuple(6, true)) -- the editor's gesture is committed, not left open

			local slider = W.Slider.new({ value = 0, host = host })
			beginDrag(host, slider.hit, Vector2.new(10, 5), Vector2.new(20, 0))
			T.expect(slider:isDragging()).toBe(true)
			T.expect(heartbeatCount()).toBe(baseline + 1)
			slider:destroy()
			T.expect(heartbeatCount()).toBe(baseline)

			local split = W.Splitter.new({ host = host, size = UDim2.fromOffset(400, 200) })
			beginDrag(host, split.divider, Vector2.new(200, 50), Vector2.new(30, 0))
			T.expect(split:isDragging()).toBe(true)
			split:destroy()
			T.expect(heartbeatCount()).toBe(baseline)

			local tree = W.Tree.new({
				items = treeItems,
				host = host,
				onDragDrop = function() end,
				parent = host.root,
			})
			beginDrag(host, tree.list:rowAt(1), Vector2.new(20, 12), Vector2.new(0, 30))
			T.expect(tree:isDragging()).toBe(true)
			T.expect(heartbeatCount()).toBe(baseline + 1)
			tree:destroy()
			T.expect(heartbeatCount()).toBe(baseline)
		end)

		T.itIf(isLune, "a completed drag leaves no Heartbeat connection behind", function()
			local host = newHost()
			local baseline = heartbeatCount()
			local vector = W.Vector3Input.new({ value = { 0, 0, 0 }, host = host })
			local input = beginDrag(host, vector.fields[2].scrub, Vector2.new(0, 0), Vector2.new(5, 0))
			T.expect(vector:isDragging()).toBe(true)
			input.UserInputState = Enum.UserInputState.End
			ctx.fakes:step(1 / 60)
			T.expect(vector:isDragging()).toBe(false)
			T.expect(heartbeatCount()).toBe(baseline)
			vector:destroy()
		end)
	end)

	-- focused fields and external updates -------------------------------------------------------------------------

	T.describe("Widget contract: external updates while focused", function()
		T.itIf(isLune, "NumberInput keeps an external value when the field is left without typing", function()
			local log: { { any } } = {}
			local n = W.NumberInput.new({
				value = 20,
				suffix = "/s",
				onChange = function(v: number, final: boolean)
					table.insert(log, tuple(v, final))
				end,
			})
			fire(n.box, "Focused")
			T.expect(n.box.Text).toBe("20")
			n:setValue(10) -- e.g. Studio undo while the field has focus
			T.expect(n.box.Text).toBe("10")
			fire(n.box, "FocusLost", false, nil)
			T.expect(#log).toBe(0)
			T.expect(n:getValue()).toBe(10)
			T.expect(n.box.Text).toBe("10/s")
			-- what the user typed wins over an external update that arrives mid-edit
			fire(n.box, "Focused")
			n.box.Text = "7"
			n:setValue(12)
			T.expect(n.box.Text).toBe("7")
			fire(n.box, "FocusLost", true, nil)
			T.expect(log).toEqual({ tuple(7, true) })
			n:destroy()
		end)

		T.itIf(isLune, "Slider value box keeps an external value when left without typing", function()
			local log: { { any } } = {}
			local s = W.Slider.new({
				value = 0.5,
				onChange = function(v: number, final: boolean)
					table.insert(log, tuple(v, final))
				end,
			})
			local box = s.box :: TextBox
			fire(box, "Focused")
			s:setValue(0.2)
			T.expect(box.Text).toBe("0.2")
			fire(box, "FocusLost", false, nil)
			T.expect(#log).toBe(0)
			T.expect(s:getValue()).toBe(0.2)
			fire(box, "Focused")
			box.Text = "0.9"
			s:setValue(0.1)
			fire(box, "FocusLost", true, nil)
			T.expect(log).toEqual({ tuple(0.9, true) })
			s:destroy()
		end)

		T.itIf(isLune, "TextInput follows external values until the user types, then keeps the edit", function()
			local log: { any } = {}
			local t = W.TextInput.new({
				value = "Feuer",
				onChange = function(text: string)
					table.insert(log, text)
				end,
			})
			fire(t.box, "Focused")
			t:setValue("Eis")
			T.expect(t.box.Text).toBe("Eis")
			fire(t.box, "FocusLost", false, nil)
			T.expect(#log).toBe(0)
			T.expect(t:getValue()).toBe("Eis")
			fire(t.box, "Focused")
			t.box.Text = "Wind"
			fire(t.box, "Changed:Text")
			t:setValue("Erde")
			T.expect(t.box.Text).toBe("Wind")
			fire(t.box, "FocusLost", true, nil)
			T.expect(log).toEqual({ "Wind" })
			T.expect(t:getValue()).toBe("Wind")
			t:destroy()
		end)
	end)

	-- layering ---------------------------------------------------------------------------------------------------

	T.describe("Widget contract: overlay layering", function()
		T.itIf(
			isLune,
			"Panel switches its widget to Sibling ZIndexBehavior and overlays stack above content",
			function()
				local widget = ctx.plugin.newWidget("AstraVFX_Layers")
				widget.gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
				local panel = W.Panel.new({ title = "Inspector", parent = widget.gui })
				T.expect(widget.gui.ZIndexBehavior).toBe(Enum.ZIndexBehavior.Sibling)
				local host = { plugin = ctx.plugin.newPlugin(), widget = widget, root = panel.instance }

				-- content with its own ZIndex values (tree drop indicator, splitter divider, rename box …)
				local split = W.Splitter.new({ host = host, parent = panel.body })
				local tree = W.Tree.new({ items = treeItems, host = host, parent = split.first })
				local dropdown = W.Dropdown.new({ options = { "A", "B" }, host = host, parent = split.second })
				local contentMax = 0
				for _, inst in panel.instance:GetDescendants() do
					if inst:IsA("GuiObject") then
						contentMax = math.max(contentMax, (inst :: GuiObject).ZIndex)
					end
				end

				dropdown:open()
				local tip = Tooltip.show(host, "Hilfe") :: Frame
				Toast.show(host, "Gespeichert", "success", 0)
				local toasts = panel.instance:FindFirstChild("AstraToasts") :: Frame
				local dialog = Dialog.confirm(host, "Löschen?", "Wirklich?")

				for _, layer in { dropdown.overlay, dropdown.popup, tip, toasts, dialog.instance } do
					T.expect((layer :: any).Parent).toBe(panel.instance)
				end
				T.expect(dialog.instance.ZIndex).toBeGreaterThan(contentMax)
				T.expect(toasts.ZIndex).toBeGreaterThan(dialog.instance.ZIndex)
				T.expect(dropdown.overlay.ZIndex).toBeGreaterThan(toasts.ZIndex)
				T.expect(dropdown.popup.ZIndex).toBeGreaterThan(dropdown.overlay.ZIndex)
				T.expect(tip.ZIndex).toBeGreaterThan(dropdown.popup.ZIndex)
				-- overlays must not be laid out by a layout object in host.root
				T.expect(panel.instance:FindFirstChildWhichIsA("UIGridStyleLayout")).toBeNil()
				T.expect(panel.instance:FindFirstChildOfClass("UIPadding")).toBeNil()

				dialog:close()
				Toast.clear(host)
				Tooltip.hide(host)
				dropdown:destroy()
				tree:destroy()
				split:destroy()
				panel:destroy()
			end
		)

		T.it("useSiblingZIndex sets LayerCollectors and tolerates other objects", function()
			local gui = Instance.new("ScreenGui")
			gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
			T.expect(Kit.useSiblingZIndex(gui)).toBe(true)
			T.expect(gui.ZIndexBehavior).toBe(Enum.ZIndexBehavior.Sibling)
			T.expect(Kit.useSiblingZIndex(Instance.new("Frame"))).toBe(false)
		end)

		T.itIf(isLune, "popups and tooltips disappear when their owner instance is destroyed", function()
			local host = newHost()
			local dropdown = W.Dropdown.new({ options = { "A", "B" }, host = host, parent = host.root })
			dropdown:open()
			local overlay = dropdown.overlay :: TextButton
			fire(dropdown.instance, "Destroying") -- e.g. the inspector rebuilt its rows without calling destroy()
			T.expect(dropdown:isOpen()).toBe(false)
			T.expect(overlay.Parent).toBeNil()

			local target = Instance.new("Frame")
			target.Parent = host.root
			Tooltip.attach(host, target, "Rate", { delay = 0.01 })
			fire(target, "MouseEnter")
			task.wait(0.05)
			T.expect(Tooltip.current(host)).never.toBeNil()
			fire(target, "Destroying")
			T.expect(Tooltip.current(host)).toBeNil()

			local pending = Instance.new("Frame")
			pending.Parent = host.root
			Tooltip.attach(host, pending, "Später", { delay = 0.01 })
			fire(pending, "MouseEnter")
			fire(pending, "Destroying")
			task.wait(0.05)
			T.expect(Tooltip.current(host)).toBeNil()
			dropdown:destroy()
		end)
	end)

	-- callbacks --------------------------------------------------------------------------------------------------

	T.describe("Widget contract: callbacks", function()
		T.itIf(isLune, "SearchBox and Tabs report onChange(value, final = true)", function()
			local log: { { any } } = {}
			local function record(...: any)
				table.insert(log, { ... })
			end
			local search = W.SearchBox.new({ onChange = record })
			search.box.Text = "fx"
			fire(search.box, "Changed:Text")
			T.expect(log).toEqual({ tuple("fx", true) })
			local tabs =
				W.Tabs.new({ tabs = { { id = "a", text = "A" }, { id = "b", text = "B" } }, onChange = record })
			fire(tabs.strip:FindFirstChild("Tab_b"), "Activated")
			T.expect(log[2]).toEqual(tuple("b", true))
			search:destroy()
			tabs:destroy()
		end)

		T.itIf(isLune, "Vector3Input reports the edited axis", function()
			local log: { { any } } = {}
			local v = W.Vector3Input.new({
				value = { 1, 2, 3 },
				onChange = function(values: { number }, final: boolean, axis: number)
					table.insert(log, tuple(values, final, axis))
				end,
			})
			local z = v.fields[3]
			z.box.Text = "9"
			fire(z.box, "FocusLost", true, nil)
			T.expect(log).toEqual({ tuple({ 1, 2, 9 }, true, 3) })
			v:destroy()
		end)

		T.it("Checkbox:setText creates the label when built without one", function()
			local cb = W.Checkbox.new({ value = true })
			T.expect(cb.label).toBeNil()
			cb:setText("Schleife")
			T.expect(cb.label).never.toBeNil()
			T.expect(cb.label.Text).toBe("Schleife")
			T.expect(cb.label.Parent).toBe(cb.instance)
			cb:destroy()
		end)

		T.it("IconButton accepts a UDim2 size like the other widgets", function()
			local b = W.IconButton.new({ glyph = "+", size = UDim2.fromOffset(20, 20) })
			T.expect(b.instance.Size).toEqual(UDim2.fromOffset(20, 20))
			local n = W.IconButton.new({ glyph = "+", size = 18 })
			T.expect(n.instance.Size).toEqual(UDim2.fromOffset(18, 18))
			b:destroy()
			n:destroy()
		end)

		T.it("Section and Splitter expose getValue next to setValue", function()
			local section = W.Section.new({ title = "S", expanded = false })
			T.expect(section:getValue()).toBe(false)
			section:setValue(true)
			T.expect(section:getValue()).toBe(true)
			local split = W.Splitter.new({ ratio = 0.4 })
			T.expect(split:getValue()).toBe(split:getRatio())
			section:destroy()
			split:destroy()
		end)
	end)

	-- Theme tokens -----------------------------------------------------------------------------------------------

	T.describe("Widget contract: Theme colours", function()
		local function key(c: Color3): string
			return string.format("%d,%d,%d", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
		end

		T.itIf(isLune, "every visible colour comes from Theme (or ControlKit.derived)", function()
			local allowed: { [string]: boolean } = {}
			for _, group in { Theme.colors, Theme.categoryColors, Theme.pinColors, Kit.derived } do
				for _, colour in group :: { [string]: Color3 } do
					allowed[key(colour)] = true
				end
			end
			local host = newHost()
			local root = host.root
			local widgets: { any } = {}
			local function add(w: any): any
				w.instance.Parent = root
				table.insert(widgets, w)
				return w
			end
			for _, variant in { "primary", "secondary", "ghost", "danger" } do
				add(W.Button.new({ text = variant, variant = variant, icon = "+" }))
				add(W.Button.new({ text = variant, variant = variant, enabled = false }))
			end
			local hovered = add(W.Button.new({ text = "hover", variant = "danger" }))
			fire(hovered.instance, "MouseEnter")
			add(W.IconButton.new({ glyph = "↻", toggle = true, toggled = true }))
			add(W.IconButton.new({ image = "rbxassetid://1", enabled = false }))
			for _, variant in { "normal", "dim", "muted", "title", "mono", "error" } do
				add(W.Label.new({ text = variant, variant = variant }))
			end
			local invalid = add(W.TextInput.new({
				value = "x",
				placeholder = "Name",
				validate = function(): string?
					return "Fehler"
				end,
			}))
			invalid:commit()
			add(W.NumberInput.new({ value = 1, label = "X", labelColor = Theme.colors.error }))
			add(W.NumberInput.new({ value = 1 }))
			add(W.Slider.new({ value = 0.3 }))
			add(W.Checkbox.new({ value = true, text = "an" }))
			add(W.Checkbox.new({ value = false, text = "aus", enabled = false })):setMixed(true)
			local dd = add(W.Dropdown.new({
				options = {
					"A",
					"B",
					"C",
					"D",
					"E",
					"F",
					"G",
					"H",
					{ value = "I", label = "I", description = "Info" } :: any,
				},
				value = "B",
				host = host,
			}))
			dd:open()
			add(W.SearchBox.new({ value = "fx" }))
			Tooltip.show(host, "Tooltip")
			for _, severity in { "info", "success", "warning", "error" } do
				Toast.show(host, severity, severity, 0)
			end
			Dialog.confirm(host, "Bestätigen", "Text", "OK", nil, { danger = true })
			Dialog.prompt(host, "Prompt", "Name", "a")
			Dialog.text(host, "Export", "{ }")
			local panel = add(W.Panel.new({ title = "Panel", icon = "◆", scroll = true }))
			panel:setToolbar(W.Toolbar.new({ autoWidth = true, items = { W.IconButton.new({ glyph = "▶" }) } }))
			add(W.Toolbar.new({ items = { W.Button.new({ text = "A" }), "separator", "spacer" } }))
			add(W.Tree.new({
				items = function(): { any }
					return {
						{
							id = "a",
							label = "A",
							icon = "◆",
							color = Theme.categoryColor("Particles"),
							selected = true,
							hint = "Emitter",
							expandable = true,
							expanded = true,
						},
						{ id = "b", label = "B", depth = 1, muted = true },
					}
				end,
				emptyText = "leer",
			}))
			add(W.Splitter.new({}))
			local tabSpecs: { any } = { { id = "a", text = "A", badge = "3" }, { id = "b", text = "B" } }
			local tabs = add(W.Tabs.new({ tabs = tabSpecs }))
			fire(tabs.strip:FindFirstChild("Tab_b"), "MouseEnter")
			add(W.PropertyRow.new({ label = "Rate", value = 2, default = 1, keyframe = "key-at-playhead" }))
			add(W.PropertyRow.new({ label = "Size", keyframe = "has-track" }))
			add(W.Section.new({ title = "Emission", badge = "2" }))
			add(W.Vector3Input.new({ value = { 1, 2, 3 } }))
			add(W.NumberRangeInput.new({ value = { 1, 2 } }))
			add(W.ColorSwatch.new({ value = "#123456" }))
			add(W.AssetInput.new({ value = "nope" }))

			local offenders: { string } = {}
			local checked = 0
			local function check(inst: Instance, property: string, colour: Color3)
				checked += 1
				if not allowed[key(colour)] then
					table.insert(offenders, inst:GetFullName() .. "." .. property .. " = " .. key(colour))
				end
			end
			for _, inst in root:GetDescendants() do
				-- user content: colour chips show the edited colour, previews show the asset
				local userContent = inst.Name == "Chip" or inst.Name == "Preview"
				if inst:IsA("GuiObject") and not userContent then
					local gui = inst :: GuiObject
					if gui.BackgroundTransparency < 1 then
						check(gui, "BackgroundColor3", gui.BackgroundColor3)
					end
					if gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox") then
						local text = gui :: any
						if text.Text ~= "" and text.TextTransparency < 1 then
							check(gui, "TextColor3", text.TextColor3)
						end
						if gui:IsA("TextBox") and text.PlaceholderText ~= "" then
							check(gui, "PlaceholderColor3", text.PlaceholderColor3)
						end
					end
					if gui:IsA("ImageLabel") or gui:IsA("ImageButton") then
						-- Lune cannot read an Image that was never assigned (no default in its database)
						local ok, image = pcall(function(): any
							return (gui :: any).Image
						end)
						if ok and image ~= "" then
							check(gui, "ImageColor3", (gui :: any).ImageColor3)
						end
					end
					if gui:IsA("ScrollingFrame") and (gui :: ScrollingFrame).ScrollBarThickness > 0 then
						check(gui, "ScrollBarImageColor3", (gui :: ScrollingFrame).ScrollBarImageColor3)
					end
				elseif inst:IsA("UIStroke") and (inst :: UIStroke).Enabled then
					check(inst, "Color", (inst :: UIStroke).Color)
				end
			end
			T.expect(offenders).toEqual({})
			T.expect(checked).toBeGreaterThan(200) -- the scan really covered the widget tree

			Toast.clear(host)
			Tooltip.hide(host)
			for _, w in widgets do
				w:destroy()
			end
		end)
	end)

	-- Tree drop targets ------------------------------------------------------------------------------------------

	T.describe("Widget contract: Tree drop targets", function()
		-- reference: the dragged rows plus every following row deeper than the dragged one (flattened descendants)
		local function bruteForce(items: { any }, index: number, ids: { string }): boolean
			local indexById: { [string]: number } = {}
			for i, item in items do
				indexById[item.id] = i
			end
			for _, id in ids do
				local start = indexById[id]
				if start == index then
					return true
				end
				if start and index > start then
					local base = items[start].depth or 0
					local inside = true
					for i = start + 1, index do
						if (items[i].depth or 0) <= base then
							inside = false
							break
						end
					end
					if inside then
						return true
					end
				end
			end
			return false
		end

		T.itIf(isLune, "excludes dragged rows and their descendants (matches the per-row reference)", function()
			-- deterministic pseudo-random tree: depth changes by at most +1 per row
			local items: { any } = {}
			local seed = 12345
			local depth = 0
			for i = 1, 400 do
				seed = (seed * 1103515245 + 12345) % 2147483648
				local r = seed % 4
				if i > 1 then
					depth = if r == 0 then depth + 1 elseif r == 1 then math.max(0, depth - 2) else depth
				end
				items[i] = { id = "n" .. i, label = "N" .. i, depth = depth, selected = i == 1 or i % 37 == 0 }
			end
			local host = newHost()
			local tree = W.Tree.new({
				items = function(): { any }
					return items
				end,
				host = host,
				onDragDrop = function() end,
				parent = host.root,
			})
			beginDrag(host, tree.list:rowAt(1), Vector2.new(20, 12), Vector2.new(0, 40))
			T.expect(tree:isDragging()).toBe(true)
			local ids = tree._drag.ids
			T.expect(#ids).toBe(11) -- rows 1, 37, 74, …, 370
			local mismatches = 0
			for index = 1, #items do
				if tree:_isDraggedOrDescendant(index, ids) ~= bruteForce(items, index, ids) then
					mismatches += 1
				end
			end
			T.expect(mismatches).toBe(0)
			-- a refresh during the drag (external data change) recomputes the exclusion set
			items[2].depth = 0
			tree:refresh()
			T.expect(tree:_isDraggedOrDescendant(2, ids)).toBe(bruteForce(items, 2, ids))
			tree:destroy()
		end)
	end)
end
