--!strict
-- Layout, list and compound-input widgets (UI/Widgets): Panel, Toolbar, ScrollList, Tree, Splitter, Tabs,
-- PropertyRow, Section, Vector3Input, Vector2Input, NumberRangeInput, ColorSwatch, AssetInput, Menus.
-- Every widget is constructed with real Instances (property names/types are validated by Lune's reflection
-- database); behaviour is driven by firing fake GUI events (ctx.fakes:signalFor) and stepping Heartbeat.
-- Tests that depend on the Lune layout fallback (no AbsoluteSize: sizes come from Size offsets) or on fakes are
-- Lune-only.
return function(T: any, use: (string) -> any, ctx: any)
	local Theme = use("Plugin.UI.Theme")
	local Panel = use("Plugin.UI.Widgets.Panel")
	local Toolbar = use("Plugin.UI.Widgets.Toolbar")
	local ScrollList = use("Plugin.UI.Widgets.ScrollList")
	local Tree = use("Plugin.UI.Widgets.Tree")
	local Splitter = use("Plugin.UI.Widgets.Splitter")
	local Tabs = use("Plugin.UI.Widgets.Tabs")
	local PropertyRow = use("Plugin.UI.Widgets.PropertyRow")
	local Section = use("Plugin.UI.Widgets.Section")
	local Vector3Input = use("Plugin.UI.Widgets.Vector3Input")
	local Vector2Input = use("Plugin.UI.Widgets.Vector2Input")
	local NumberRangeInput = use("Plugin.UI.Widgets.NumberRangeInput")
	local ColorSwatch = use("Plugin.UI.Widgets.ColorSwatch")
	local AssetInput = use("Plugin.UI.Widgets.AssetInput")
	local Menus = use("Plugin.UI.Widgets.Menus")
	local IconButton = use("Plugin.UI.Widgets.IconButton")
	local NumberInput = use("Plugin.UI.Widgets.NumberInput")

	local isLune = ctx.environment == "lune"

	-- helpers ----------------------------------------------------------------------------------------------------

	local function fire(inst: any, event: string, ...: any)
		ctx.fakes:signalFor(inst, event):Fire(...)
	end

	-- mixed-type array (the old type solver infers literal arrays from their first element)
	local function tuple(...: any): { any }
		return { ... }
	end

	local function changed(inst: any, property: string)
		ctx.fakes:signalFor(inst, "Changed:" .. property):Fire()
	end

	type Mods = { ctrl: boolean?, shift: boolean?, alt: boolean? }

	local function mouseInput(kind: any?, mods: Mods?, position: Vector3?): any
		local m: Mods = mods or {}
		local input: any = {
			UserInputType = kind or Enum.UserInputType.MouseButton1,
			UserInputState = Enum.UserInputState.Begin,
			Position = position or Vector3.new(0, 0, 0),
			KeyCode = nil, -- Lune's enum database has no KeyCode.Unknown
		}
		function input.IsModifierKeyDown(_self: any, key: any): boolean
			if key == Enum.ModifierKey.Ctrl then
				return m.ctrl == true
			elseif key == Enum.ModifierKey.Shift then
				return m.shift == true
			elseif key == Enum.ModifierKey.Alt then
				return m.alt == true
			end
			return false
		end
		return input
	end

	local function keyInput(keyCode: any): any
		local input = mouseInput(Enum.UserInputType.Keyboard)
		input.KeyCode = keyCode
		return input
	end

	local function newHost(): any
		local root = Instance.new("Frame")
		root.Size = UDim2.fromOffset(800, 600)
		return { plugin = ctx.plugin.newPlugin(), widget = ctx.plugin.newWidget("AstraVFX_Test"), root = root }
	end

	-- press at the current widget.mouse, then move to each position (one Heartbeat per step), then release
	local function drag(host: any, gui: any, from: Vector2, to: { Vector2 }, mods: Mods?): any
		host.widget.mouse = from
		local input = mouseInput(Enum.UserInputType.MouseButton1, mods)
		fire(gui, "InputBegan", input)
		ctx.fakes:step(1 / 60)
		for _, pos in to do
			host.widget.mouse = pos
			ctx.fakes:step(1 / 60)
		end
		input.UserInputState = Enum.UserInputState.End
		ctx.fakes:step(1 / 60)
		return input
	end

	local function fakeWidget(): any
		local w: any = { instance = Instance.new("TextButton"), enabled = true, destroyed = false }
		function w.setEnabled(self: any, enabled: boolean)
			self.enabled = enabled
		end
		function w.destroy(self: any)
			self.destroyed = true
			self.instance:Destroy()
		end
		return w
	end

	local function sized(w: number, h: number): Frame
		local f = Instance.new("Frame")
		f.Size = UDim2.fromOffset(w, h)
		return f
	end

	-- Panel ------------------------------------------------------------------------------------------------------

	T.describe("Panel", function()
		T.it("builds header (title, toolbar slot) and a padded body", function()
			local parent = sized(400, 300)
			local panel = Panel.new({ title = "Explorer", icon = "◆", parent = parent })
			T.expect(panel.instance.Parent).toBe(parent)
			T.expect(panel.titleLabel.Text).toBe("Explorer")
			T.expect(panel.header.Size.Y.Offset).toBe(Theme.metrics.headerHeight)
			T.expect(panel.body.Position.Y.Offset).toBe(Theme.metrics.headerHeight)
			T.expect(panel.instance.BackgroundColor3).toEqual(Theme.colors.bg1)
			local padding = panel.body:FindFirstChildOfClass("UIPadding")
			T.expect(padding.PaddingLeft.Offset).toBe(Theme.metrics.padding)
			T.expect(panel.iconLabel).never.toBeNil()
			panel:setTitle("Inspector")
			T.expect(panel.titleLabel.Text).toBe("Inspector")
			panel:destroy()
			T.expect(panel.instance.Parent).toBeNil()
		end)

		T.it("owns its toolbar and given tasks", function()
			local panel = Panel.new({ title = "Timeline" })
			local first = fakeWidget()
			panel:setToolbar(first)
			T.expect(first.instance.Parent).toBe(panel.toolbarSlot)
			local second = fakeWidget()
			panel:setToolbar(second)
			T.expect(first.destroyed).toBe(true)
			local cleaned = false
			panel:give(function()
				cleaned = true
			end)
			panel:setEnabled(false)
			T.expect(second.enabled).toBe(false)
			panel:destroy()
			T.expect(second.destroyed).toBe(true)
			T.expect(cleaned).toBe(true)
			panel:destroy() -- idempotent
		end)

		T.it("supports a scrolling body and no header", function()
			local panel = Panel.new({ title = "Inspector", scroll = true, header = false })
			T.expect(panel.body.ClassName).toBe("ScrollingFrame")
			T.expect(panel.body.AutomaticCanvasSize).toBe(Enum.AutomaticSize.Y)
			T.expect(panel.header.Visible).toBe(false)
			T.expect(panel.body.Position.Y.Offset).toBe(0)
			panel:destroy()
		end)
	end)

	-- Toolbar ----------------------------------------------------------------------------------------------------

	T.describe("Toolbar", function()
		T.it("lays out widgets, GuiObjects, separators and spacers in order", function()
			local a = fakeWidget()
			local plain = Instance.new("TextButton")
			local icon = IconButton.new({ glyph = "▶" })
			local bar = Toolbar.new({ items = { a, "separator", icon, "spacer", plain } })
			local children = {}
			for _, child in bar.content:GetChildren() do
				if child:IsA("GuiObject") then
					children[child.LayoutOrder] = child
				end
			end
			T.expect(children[1]).toBe(a.instance)
			T.expect(children[2].Name).toBe("Separator")
			T.expect(children[3]).toBe(icon.instance)
			T.expect(children[4].Name).toBe("Spacer")
			T.expect(children[4]:FindFirstChildOfClass("UIFlexItem")).never.toBeNil()
			T.expect(children[5]).toBe(plain)
			T.expect(bar.content:FindFirstChildOfClass("UIListLayout").FillDirection)
				.toBe(Enum.FillDirection.Horizontal)
			T.expect(bar.instance.Size.Y.Offset).toBe(Theme.metrics.toolbarHeight)

			bar:setEnabled(false)
			T.expect(a.enabled).toBe(false)
			T.expect(plain.Interactable).toBe(false)
			local late = bar:add(fakeWidget())
			T.expect(late.enabled).toBe(false) -- added while disabled
			bar:destroy()
			T.expect(a.destroyed).toBe(true)
			T.expect(late.destroyed).toBe(true)
			T.expect(icon.instance.Parent).toBeNil()
			T.expect(plain.Parent).toBeNil()
		end)

		T.it("auto-sizes for header slots and rejects unknown items", function()
			local bar = Toolbar.new({ autoWidth = true })
			T.expect(bar.instance.AutomaticSize).toBe(Enum.AutomaticSize.X)
			T.expect(bar.instance.BackgroundTransparency).toBe(1)
			T.expect(function()
				bar:add(42)
			end).toThrow("Toolbar:add")
			bar:clear()
			bar:destroy()
		end)
	end)

	-- ScrollList -------------------------------------------------------------------------------------------------

	T.describe("ScrollList", function()
		local function makeList(count: number, parent: Instance?): (any, { [number]: number })
			local renders: { [number]: number } = {}
			local list = ScrollList.new({
				rowHeight = 24,
				count = count,
				createRow = function(row: TextButton)
					local label = Instance.new("TextLabel")
					label.Name = "Label"
					label.Parent = row
				end,
				render = function(row: TextButton, index: number)
					renders[index] = (renders[index] or 0) + 1
					(row:FindFirstChild("Label") :: TextLabel).Text = "Row " .. index
				end,
				parent = parent or sized(300, 240),
			})
			return list, renders
		end

		local function shownRows(list: any): number
			local n = 0
			for _, child in list.instance:GetChildren() do
				if child.Name == "Row" and child.Visible then
					n += 1
				end
			end
			return n
		end

		T.itIf(isLune, "creates rows only for the visible range of 10 000 rows", function()
			local list, renders = makeList(10000)
			T.expect(list.instance.CanvasSize.Y.Offset).toBe(240000)
			-- 240px viewport / 24px rows = 10 rows + 4 buffer rows below
			T.expect(list:visibleRowCount()).toBe(14)
			T.expect(shownRows(list)).toBe(14)
			T.expect(list:createdRowCount()).toBeLessThanOrEqual(20)
			local first, last = list:getVisibleRange()
			T.expect(first).toBe(1)
			T.expect(last).toBe(14)
			T.expect(renders[1]).toBe(1)
			T.expect(renders[15]).toBeNil()
			T.expect((list:rowAt(3):FindFirstChild("Label") :: TextLabel).Text).toBe("Row 3")
			list:destroy()
		end)

		T.itIf(isLune, "re-renders and recycles rows on scroll", function()
			local list, renders = makeList(10000)
			local created = list:createdRowCount()
			list.instance.CanvasPosition = Vector2.new(0, 24 * 5000)
			changed(list.instance, "CanvasPosition")
			T.expect(list:rowAt(1)).toBeNil()
			T.expect(list:rowAt(5001)).never.toBeNil()
			T.expect(renders[5001]).toBe(1)
			T.expect((list:rowAt(5001):FindFirstChild("Label") :: TextLabel).Text).toBe("Row 5001")
			T.expect(list:rowAt(5001).Position.Y.Offset).toBe(24 * 5000)
			T.expect(list:indexOf(list:rowAt(5002))).toBe(5002)
			-- a hovered row that scrolls away loses its hover state
			fire(list:rowAt(5001), "MouseEnter")
			T.expect(list.hoverIndex).toBe(5001)
			list.instance.CanvasPosition = Vector2.new(0, 0)
			changed(list.instance, "CanvasPosition")
			T.expect(list.hoverIndex).toBeNil()
			list.instance.CanvasPosition = Vector2.new(0, 24 * 5000)
			changed(list.instance, "CanvasPosition")
			-- pooled rows are re-used: the instance count does not grow with the scroll distance
			T.expect(list:createdRowCount()).toBeLessThanOrEqual(created + 4)
			T.expect(shownRows(list)).toBeLessThanOrEqual(20)
			list:destroy()
		end)

		T.itIf(isLune, "setCount clamps the scroll position and refresh re-renders", function()
			local list, renders = makeList(500)
			list:scrollToIndex(400, "top")
			T.expect(list:rowAt(400)).never.toBeNil()
			list:setCount(3)
			T.expect(list.instance.CanvasPosition.Y).toBe(0)
			T.expect(list.instance.CanvasSize.Y.Offset).toBe(72)
			T.expect(list:visibleRowCount()).toBe(3)
			T.expect(shownRows(list)).toBe(3)
			local before = renders[2]
			list:refresh()
			T.expect(renders[2]).toBe(before + 1)
			list:setCount(0)
			T.expect(list:visibleRowCount()).toBe(0)
			list:destroy()
		end)

		T.itIf(isLune, "scrollToIndex keeps the row in view", function()
			local list = makeList(1000)
			list:scrollToIndex(100)
			-- nearest: the row's bottom edge aligns with the viewport bottom
			T.expect(list.instance.CanvasPosition.Y).toBe(100 * 24 - 240)
			T.expect(list:rowAt(100)).never.toBeNil()
			list:scrollToIndex(50, "center")
			T.expect(list.instance.CanvasPosition.Y).toBe(49 * 24 - (240 - 24) / 2)
			list:scrollToIndex(1000, "top") -- clamped to the end
			T.expect(list.instance.CanvasPosition.Y).toBe(1000 * 24 - 240)
			list:destroy()
		end)

		T.itIf(isLune, "reports activation, row input and hover", function()
			local log = {}
			local hovered: { any } = {}
			local list
			list = ScrollList.new({
				count = 10,
				render = function(row: TextButton, index: number)
					row.BackgroundTransparency = if list and list:isHovered(index) then 0 else 1
				end,
				onRowActivated = function(index: number, _input: any, clickCount: number)
					table.insert(log, tuple(index, clickCount))
				end,
				onRowInput = function(index: number, input: any)
					table.insert(log, tuple(index, input.UserInputType.Name))
				end,
				onHoverChanged = function(index: number?)
					table.insert(hovered, index or "none")
				end,
				parent = sized(200, 240),
			})
			local row = list:rowAt(2)
			fire(row, "Activated", mouseInput(), 2)
			fire(row, "InputBegan", mouseInput(Enum.UserInputType.MouseButton2))
			T.expect(log).toEqual({ tuple(2, 2), tuple(2, "MouseButton2") })
			fire(row, "MouseEnter")
			T.expect(list:isHovered(2)).toBe(true)
			T.expect(row.BackgroundTransparency).toBe(0)
			fire(row, "MouseLeave")
			T.expect(list:isHovered(2)).toBe(false)
			T.expect(row.BackgroundTransparency).toBe(1)
			T.expect(hovered).toEqual(tuple(2, "none"))
			list:setEnabled(false)
			fire(row, "Activated", mouseInput(), 1)
			T.expect(#log).toBe(2)
			list:destroy()
		end)
	end)

	-- Tree -------------------------------------------------------------------------------------------------------

	T.describe("Tree", function()
		-- fx ▸ burst, sparks, group ▸ ring ; light
		local NODES = {
			{ id = "fx", label = "Effect" },
			{ id = "burst", label = "Burst", parent = "fx" },
			{ id = "sparks", label = "Sparks", parent = "fx" },
			{ id = "group", label = "Group", parent = "fx" },
			{ id = "ring", label = "Ring", parent = "group" },
			{ id = "light", label = "Light" },
		}

		local function model(): any
			local m: any = {
				expanded = { fx = true, group = true },
				selected = {},
				labels = {},
				log = {},
			}
			local function hasChildren(id: string): boolean
				for _, n in NODES do
					if n.parent == id then
						return true
					end
				end
				return false
			end
			function m.items(): { any }
				local out = {}
				local function visit(parentId: string?, depth: number)
					for _, n in NODES do
						if n.parent == parentId then
							local expandable = hasChildren(n.id)
							table.insert(out, {
								id = n.id,
								label = m.labels[n.id] or n.label,
								depth = depth,
								icon = "◆",
								color = Theme.categoryColor("Particles"),
								expandable = expandable,
								expanded = m.expanded[n.id] == true,
								selected = m.selected[n.id] == true,
								muted = n.id == "light",
								hint = if n.id == "light" then "PointLight" else nil,
							})
							if expandable and m.expanded[n.id] then
								visit(n.id, depth + 1)
							end
						end
					end
				end
				visit(nil, 0)
				return out
			end
			function m.onToggle(id: string, expanded: boolean)
				table.insert(m.log, tuple("toggle", id, expanded))
				m.expanded[id] = expanded
			end
			function m.onSelect(ids: { string }, mode: string, clicked: string?)
				table.insert(m.log, tuple("select", table.concat(ids, ","), mode, clicked or ""))
				if mode == "replace" then
					m.selected = {}
				end
				for _, id in ids do
					if mode == "toggle" then
						m.selected[id] = not m.selected[id] or nil
					else
						m.selected[id] = true
					end
				end
			end
			return m
		end

		local function makeTree(m: any, extra: { [string]: any }?): any
			local props: { [string]: any } = {
				items = m.items,
				onToggle = m.onToggle,
				onSelect = m.onSelect,
				parent = sized(300, 240),
			}
			local extras: { [string]: any } = extra or {}
			for k, v in extras do
				props[k] = v
			end
			return Tree.new(props)
		end

		local function label(tree: any, index: number): TextLabel
			return tree.list:rowAt(index):FindFirstChild("Label") :: TextLabel
		end

		T.it("renders the flattened rows with indentation, icons and states", function()
			local m = model()
			m.selected.sparks = true
			local tree = makeTree(m, { emptyText = "Keine Komponenten" })
			T.expect(#tree:getItems()).toBe(6)
			T.expect(tree.list.count).toBe(6)
			T.expect(label(tree, 1).Text).toBe("Effect")
			T.expect(label(tree, 5).Text).toBe("Ring")
			T.expect(label(tree, 5).Position.X.Offset).toBeGreaterThan(label(tree, 2).Position.X.Offset)
			T.expect(label(tree, 2).Position.X.Offset).toBeGreaterThan(label(tree, 1).Position.X.Offset)
			local row1 = tree.list:rowAt(1)
			T.expect((row1:FindFirstChild("Expander") :: TextButton).Visible).toBe(true)
			T.expect((row1:FindFirstChild("Expander") :: TextButton).Rotation).toBe(90)
			T.expect((tree.list:rowAt(2):FindFirstChild("Expander") :: TextButton).Visible).toBe(false)
			T.expect((row1:FindFirstChild("IconGlyph") :: TextLabel).TextColor3)
				.toEqual(Theme.categoryColor("Particles"))
			local selectedRow = tree.list:rowAt(3)
			T.expect(selectedRow.BackgroundColor3).toEqual(Theme.colors.selection)
			T.expect((selectedRow:FindFirstChild("SelectionBar") :: Frame).Visible).toBe(true)
			T.expect(label(tree, 6).TextColor3).toEqual(Theme.colors.textMuted)
			T.expect((tree.list:rowAt(6):FindFirstChild("Hint") :: TextLabel).Text).toBe("PointLight")
			T.expect(tree._emptyLabel.Visible).toBe(false)
			tree:destroy()
			T.expect(tree.instance.Parent).toBeNil()
		end)

		T.itIf(isLune, "expands and collapses through the expander", function()
			local m = model()
			local tree = makeTree(m)
			fire(tree.list:rowAt(4):FindFirstChild("Expander"), "Activated", mouseInput(), 1)
			T.expect(m.log[1]).toEqual(tuple("toggle", "group", false))
			T.expect(#tree:getItems()).toBe(5) -- ring hidden
			fire(tree.list:rowAt(1):FindFirstChild("Expander"), "Activated", mouseInput(), 1)
			T.expect(#tree:getItems()).toBe(2)
			T.expect(label(tree, 2).Text).toBe("Light")
			T.expect(tree.list:rowAt(3)).toBeNil()
			tree:destroy()
		end)

		T.itIf(isLune, "selects with click, ctrl-toggle and shift-range", function()
			local m = model()
			local tree = makeTree(m)
			fire(tree.list:rowAt(2), "InputBegan", mouseInput())
			T.expect(m.log[1]).toEqual({ "select", "burst", "replace", "burst" })
			T.expect(tree.list:rowAt(2).BackgroundColor3).toEqual(Theme.colors.selection)
			fire(tree.list:rowAt(4), "InputBegan", mouseInput(nil, { ctrl = true }))
			T.expect(m.log[2]).toEqual({ "select", "group", "toggle", "group" })
			T.expect(m.selected.burst and m.selected.group).toBe(true)
			-- shift: range from the anchor (group, last ctrl/plain click) to ring
			fire(tree.list:rowAt(6), "InputBegan", mouseInput(nil, { shift = true }))
			T.expect(m.log[3]).toEqual(tuple("select", "group,ring,light", "replace", "light"))
			-- ctrl+shift adds the range
			fire(tree.list:rowAt(1), "InputBegan", mouseInput(nil, { ctrl = true, shift = true }))
			T.expect(m.log[4]).toEqual(tuple("select", "fx,burst,sparks,group", "add", "fx"))
			tree:destroy()
		end)

		T.itIf(isLune, "right click selects the row and opens the context hook", function()
			local m = model()
			local contexts: { any } = {}
			local tree = makeTree(m, {
				onContext = function(id: string?, input: any)
					table.insert(contexts, tuple(id or "empty", input.UserInputType.Name))
				end,
			})
			fire(tree.list:rowAt(3), "InputBegan", mouseInput(Enum.UserInputType.MouseButton2))
			T.expect(m.log[1]).toEqual({ "select", "sparks", "replace", "sparks" })
			T.expect(contexts[1]).toEqual({ "sparks", "MouseButton2" })
			-- right click on a selected row keeps the selection
			fire(tree.list:rowAt(3), "InputBegan", mouseInput(Enum.UserInputType.MouseButton2))
			T.expect(#m.log).toBe(1)
			-- empty space below the six rows (y = 200 > 6 × 24)
			local empty = mouseInput(Enum.UserInputType.MouseButton2, nil, Vector3.new(20, 200, 0))
			fire(tree.list.instance, "InputBegan", empty)
			T.expect(contexts[3]).toEqual({ "empty", "MouseButton2" })
			-- a press over a row on the frame itself is left to the row
			fire(
				tree.list.instance,
				"InputBegan",
				mouseInput(Enum.UserInputType.MouseButton1, nil, Vector3.new(20, 30, 0))
			)
			T.expect(#m.log).toBe(1)
			-- left click on empty space clears the selection
			fire(
				tree.list.instance,
				"InputBegan",
				mouseInput(Enum.UserInputType.MouseButton1, nil, Vector3.new(20, 200, 0))
			)
			T.expect(m.log[2]).toEqual({ "select", "", "replace", "" })
			tree:destroy()
		end)

		T.itIf(isLune, "renames inline on double click (Enter commits, Escape cancels)", function()
			local m = model()
			local renames: { any } = {}
			local tree = makeTree(m, {
				onRename = function(id: string, text: string)
					table.insert(renames, tuple(id, text))
					m.labels[id] = text
				end,
			})
			fire(tree.list:rowAt(2), "Activated", mouseInput(), 2)
			local box = tree.list.instance:FindFirstChild("RenameBox") :: TextBox
			T.expect(box).never.toBeNil()
			T.expect(box.Text).toBe("Burst")
			T.expect(box.ClearTextOnFocus).toBe(false)
			T.expect(box:IsFocused()).toBe(true)
			T.expect(tree:isRenaming()).toBe(true)
			T.expect(label(tree, 2).Visible).toBe(false)
			box.Text = "  Big Burst "
			fire(box, "FocusLost", true, nil)
			T.expect(renames).toEqual({ { "burst", "Big Burst" } })
			T.expect(tree.list.instance:FindFirstChild("RenameBox")).toBeNil()
			T.expect(label(tree, 2).Text).toBe("Big Burst")
			T.expect(label(tree, 2).Visible).toBe(true)

			tree:beginRename("sparks")
			local box2 = tree.list.instance:FindFirstChild("RenameBox") :: TextBox
			box2.Text = "Nope"
			fire(box2, "FocusLost", false, keyInput(Enum.KeyCode.Escape))
			T.expect(#renames).toBe(1)
			T.expect(tree:isRenaming()).toBe(false)
			-- single clicks do not rename; without onRename a double click activates
			fire(tree.list:rowAt(3), "Activated", mouseInput(), 1)
			T.expect(tree:isRenaming()).toBe(false)
			tree:destroy()

			local activated: { string } = {}
			local plain = makeTree(model(), {
				onActivate = function(id: string)
					table.insert(activated, id)
				end,
			})
			fire(plain.list:rowAt(6), "Activated", mouseInput(), 2)
			T.expect(activated).toEqual({ "light" })
			plain:destroy()
		end)

		T.itIf(isLune, "drag & drop reports target and position (before/after/inside)", function()
			local m = model()
			local drops: { any } = {}
			local host = newHost()
			local tree = makeTree(m, {
				host = host,
				onDragDrop = function(ids: { string }, target: string, position: string)
					table.insert(drops, tuple(table.concat(ids, ","), target, position))
				end,
			})
			-- burst (row 2) onto the lower half of light (row 6, no children) -> after
			drag(host, tree.list:rowAt(2), Vector2.new(20, 36), { Vector2.new(20, 90), Vector2.new(20, 5 * 24 + 18) })
			T.expect(drops[1]).toEqual({ "burst", "light", "after" })
			T.expect(m.log[1]).toEqual({ "select", "burst", "replace", "burst" }) -- pressed row got selected
			T.expect(tree.indicator.Visible).toBe(false)
			T.expect(tree:isDragging()).toBe(false)
			-- into the middle of group (row 4, has children) -> inside
			drag(host, tree.list:rowAt(3), Vector2.new(20, 2 * 24 + 12), { Vector2.new(20, 3 * 24 + 12) })
			T.expect(drops[2]).toEqual({ "sparks", "group", "inside" })
			-- top quarter of group -> before
			drag(host, tree.list:rowAt(6), Vector2.new(20, 5 * 24 + 12), { Vector2.new(20, 3 * 24 + 3) })
			T.expect(drops[3]).toEqual({ "light", "group", "before" })
			tree:destroy()
		end)

		T.itIf(isLune, "drags the whole selection and shows the drop indicator", function()
			local m = model()
			m.selected.burst = true
			m.selected.sparks = true
			local drops: { any } = {}
			local host = newHost()
			local tree = makeTree(m, {
				host = host,
				onDragDrop = function(ids: { string }, target: string, position: string)
					table.insert(drops, tuple(table.concat(ids, ","), target, position))
				end,
			})
			host.widget.mouse = Vector2.new(20, 36)
			local input = mouseInput()
			fire(tree.list:rowAt(2), "InputBegan", input)
			T.expect(#m.log).toBe(0) -- pressing a selected row keeps the multi-selection
			host.widget.mouse = Vector2.new(20, 5 * 24 + 4)
			ctx.fakes:step(1 / 60)
			T.expect(tree:isDragging()).toBe(true)
			T.expect(tree.indicator.Visible).toBe(true)
			T.expect(tree.indicator.Position.Y.Offset).toBe(5 * 24 - 1) -- line above light
			T.expect(tree.indicator.Size.Y.Offset).toBe(2)
			T.expect(label(tree, 2).TextTransparency).toBe(0.5) -- dragged rows are dimmed
			input.UserInputState = Enum.UserInputState.End
			ctx.fakes:step(1 / 60)
			T.expect(drops[1]).toEqual(tuple("burst,sparks", "light", "before"))
			T.expect(#m.log).toBe(0)
			-- a click without movement on a selected row collapses the selection to it
			drag(host, tree.list:rowAt(3), Vector2.new(20, 60), {})
			T.expect(m.log[1]).toEqual({ "select", "sparks", "replace", "sparks" })
			tree:destroy()
		end)

		T.itIf(isLune, "rejects drops onto the dragged rows, their descendants and vetoed targets", function()
			local m = model()
			local drops: { any } = {}
			local host = newHost()
			local tree = makeTree(m, {
				host = host,
				onDragDrop = function(ids: { string }, target: string, position: string)
					table.insert(drops, tuple(table.concat(ids, ","), target, position))
				end,
				canDrop = function(_ids: { string }, target: string, _position: string): boolean
					return target ~= "sparks"
				end,
			})
			-- fx (row 1) onto its grandchild ring (row 5)
			host.widget.mouse = Vector2.new(20, 12)
			local input = mouseInput()
			fire(tree.list:rowAt(1), "InputBegan", input)
			host.widget.mouse = Vector2.new(20, 4 * 24 + 12)
			ctx.fakes:step(1 / 60)
			T.expect(tree.indicator.Visible).toBe(false)
			input.UserInputState = Enum.UserInputState.End
			ctx.fakes:step(1 / 60)
			-- light onto sparks: vetoed by canDrop
			drag(host, tree.list:rowAt(6), Vector2.new(20, 5 * 24 + 12), { Vector2.new(20, 2 * 24 + 6) })
			T.expect(#drops).toBe(0)
			-- focus loss cancels a drag
			host.widget.mouse = Vector2.new(20, 5 * 24 + 12)
			local pending = mouseInput()
			fire(tree.list:rowAt(6), "InputBegan", pending)
			host.widget.mouse = Vector2.new(20, 1 * 24 + 4)
			ctx.fakes:step(1 / 60)
			host.widget.WindowFocusReleased:Fire()
			T.expect(tree:isDragging()).toBe(false)
			T.expect(#drops).toBe(0)
			tree:destroy()
		end)

		T.itIf(isLune, "navigates with the keyboard", function()
			local m = model()
			local modsSeen: { any } = {}
			local renamed: { string } = {}
			local tree = makeTree(m, {
				onSelect = function(ids: { string }, mode: string, clicked: string?, mods: any)
					table.insert(modsSeen, mods)
					m.onSelect(ids, mode, clicked)
				end,
				onRename = function(id: string, _text: string)
					table.insert(renamed, id)
				end,
			})
			fire(tree.list:rowAt(2), "InputBegan", mouseInput(nil, { ctrl = true }))
			T.expect(modsSeen[1].ctrl).toBe(true)
			T.expect(tree:handleKey(Enum.KeyCode.Down)).toBe(true)
			T.expect(m.log[2]).toEqual(tuple("select", "sparks", "replace", "sparks"))
			T.expect(tree:handleKey(Enum.KeyCode.Down, { ctrl = false, shift = true, alt = false })).toBe(true)
			T.expect(m.log[3]).toEqual(tuple("select", "sparks,group", "replace", "group"))
			-- Left on an expanded item collapses it, then moves to the parent
			tree:handleKey(Enum.KeyCode.Left)
			T.expect(m.expanded.group).toBe(false)
			tree:handleKey(Enum.KeyCode.Left)
			T.expect(m.log[#m.log]).toEqual(tuple("select", "fx", "replace", "fx"))
			-- Right expands a collapsed item, then enters it
			tree:handleKey(Enum.KeyCode.End)
			T.expect(m.log[#m.log]).toEqual(tuple("select", "light", "replace", "light"))
			tree:handleKey(Enum.KeyCode.Home)
			tree:handleKey(Enum.KeyCode.Down)
			tree:handleKey(Enum.KeyCode.Down)
			tree:handleKey(Enum.KeyCode.Down) -- group (collapsed)
			tree:handleKey(Enum.KeyCode.Right)
			T.expect(m.expanded.group).toBe(true)
			tree:handleKey(Enum.KeyCode.Right)
			T.expect(m.log[#m.log]).toEqual(tuple("select", "ring", "replace", "ring"))
			tree:handleKey(Enum.KeyCode.F2)
			T.expect(tree:isRenaming()).toBe(true)
			T.expect(tree:handleKey(Enum.KeyCode.Down)).toBe(false) -- ignored while renaming
			tree:endRename(false)
			T.expect(#renamed).toBe(0)
			T.expect(tree:handleKey(Enum.KeyCode.Q)).toBe(false)
			tree:destroy()
		end)

		T.it("stays virtualised with 10 000 items", function()
			local items = {}
			for i = 1, 10000 do
				items[i] = { id = "c" .. i, label = "Component " .. i, depth = i % 3 }
			end
			local tree = Tree.new({
				items = function()
					return items
				end,
				parent = sized(300, 240),
			})
			local rows = 0
			for _, child in tree.list.instance:GetChildren() do
				if child.Name == "Row" then
					rows += 1
				end
			end
			T.expect(rows).toBeLessThanOrEqual(20)
			T.expect(tree.list.instance.CanvasSize.Y.Offset).toBe(240000)
			tree:scrollTo("c9000")
			T.expect(tree.list:rowAt(9000)).never.toBeNil()
			T.expect(tree:indexOf("c9000")).toBe(9000)
			tree:destroy()
		end)
	end)

	-- Splitter ---------------------------------------------------------------------------------------------------

	T.describe("Splitter", function()
		T.itIf(isLune, "lays out both directions and clamps the ratio by min sizes", function()
			local split = Splitter.new({ ratio = 0.3, size = UDim2.fromOffset(400, 300), minFirst = 100 })
			T.expect(split.first.Size.X.Scale).toBeCloseTo(0.3, 1e-6)
			T.expect(split.second.Position.X.Scale).toBeCloseTo(0.3, 1e-6)
			T.expect(split.second.Size.X.Scale).toBeCloseTo(0.7, 1e-6)
			T.expect(split.divider.Position.X.Scale).toBeCloseTo(0.3, 1e-6)
			split:setRatio(0.1) -- 100px of 400 is the minimum
			T.expect(split:getRatio()).toBeCloseTo(0.25, 1e-6)
			split:setRatio(0.99) -- minSecond default 60px
			T.expect(split:getRatio()).toBeCloseTo(1 - 60 / 400, 1e-6)
			split:destroy()
			T.expect(split.instance.Parent).toBeNil()

			local vertical = Splitter.new({ direction = "vertical", ratio = 0.6, size = UDim2.fromOffset(200, 500) })
			T.expect(vertical.first.Size.Y.Scale).toBeCloseTo(0.6, 1e-6)
			T.expect(vertical.second.Position.Y.Scale).toBeCloseTo(0.6, 1e-6)
			T.expect(vertical.divider.Size.X.Scale).toBe(1)
			vertical:destroy()
		end)

		T.itIf(isLune, "drags the divider (streaming + final onChange) and resets on double click", function()
			local host = newHost()
			local log: { any } = {}
			local split = Splitter.new({
				ratio = 0.3,
				size = UDim2.fromOffset(400, 300),
				host = host,
				onChange = function(ratio: number, final: boolean)
					table.insert(log, tuple(ratio, final))
				end,
			})
			fire(split.divider, "MouseEnter")
			T.expect(host.plugin.mouse.Icon).toBe("rbxasset://SystemCursors/SplitEW")
			drag(host, split.divider, Vector2.new(120, 10), { Vector2.new(160, 10), Vector2.new(200, 10) })
			T.expect(split:getRatio()).toBeCloseTo(0.5, 1e-6)
			T.expect(log[1][2]).toBe(false)
			T.expect(log[#log - 1][1]).toBeCloseTo(0.5, 1e-6)
			T.expect(log[#log]).toEqual(tuple(0.5, true))
			T.expect(split.first.Size.X.Scale).toBeCloseTo(0.5, 1e-6)
			fire(split.divider, "MouseLeave")
			T.expect(host.plugin.mouse.Icon).toBe("")
			fire(split.divider, "Activated", mouseInput(), 2)
			T.expect(split:getRatio()).toBeCloseTo(0.3, 1e-6)
			T.expect(log[#log]).toEqual(tuple(0.3, true))
			split:setEnabled(false)
			local count = #log
			drag(host, split.divider, Vector2.new(120, 10), { Vector2.new(300, 10) })
			T.expect(#log).toBe(count)
			split:destroy()
		end)
	end)

	-- Tabs -------------------------------------------------------------------------------------------------------

	T.describe("Tabs", function()
		T.itIf(isLune, "switches pages on click and setValue", function()
			local changes: { string } = {}
			local tabs = Tabs.new({
				tabs = { { id = "props", text = "Eigenschaften" }, { id = "events", text = "Events", badge = "3" } },
				onChange = function(id: string)
					table.insert(changes, id)
				end,
			})
			T.expect(tabs:getValue()).toBe("props")
			T.expect(tabs:page("props").Visible).toBe(true)
			T.expect(tabs:page("events").Visible).toBe(false)
			local eventsButton = tabs.strip:FindFirstChild("Tab_events") :: TextButton
			T.expect(eventsButton.RichText).toBe(true)
			T.expect(eventsButton.Text).toMatch("Events")
			T.expect(eventsButton.Text).toMatch(">3<")
			fire(eventsButton, "Activated", mouseInput(), 1)
			T.expect(changes).toEqual({ "events" })
			T.expect(tabs:page("events").Visible).toBe(true)
			T.expect(tabs:page("props").Visible).toBe(false)
			T.expect((eventsButton:FindFirstChild("Underline") :: Frame).Visible).toBe(true)
			fire(eventsButton, "Activated", mouseInput(), 1) -- already selected
			T.expect(#changes).toBe(1)
			tabs:setValue("props")
			T.expect(#changes).toBe(1)
			T.expect(tabs:page("props").Visible).toBe(true)

			local notes = tabs:addTab({ id = "notes", text = "Notizen" })
			T.expect(notes.Parent).toBe(tabs.content)
			T.expect(tabs:tabIds()).toEqual({ "props", "events", "notes" })
			T.expect(function()
				tabs:addTab({ id = "notes", text = "Doppelt" })
			end).toThrow("duplicate")
			tabs:removeTab("props")
			T.expect(tabs:getValue()).toBe("events")
			T.expect(tabs:page("props")).toBeNil()
			tabs:setEnabled(false)
			fire(tabs.strip:FindFirstChild("Tab_notes"), "Activated", mouseInput(), 1)
			T.expect(tabs:getValue()).toBe("events")
			tabs:destroy()
		end)
	end)

	-- PropertyRow ------------------------------------------------------------------------------------------------

	T.describe("PropertyRow", function()
		T.it("splits label column and field slot", function()
			local row = PropertyRow.new({ label = "Rate", field = Instance.new("Frame") })
			T.expect(row.label.Text).toBe("Rate")
			T.expect(row.label.Size.X.Scale).toBeCloseTo(Theme.metrics.labelWidth, 1e-6)
			T.expect(row.slot.Position.X.Scale).toBeCloseTo(Theme.metrics.labelWidth, 1e-6)
			T.expect(row.instance.Size.Y.Offset).toBe(Theme.metrics.rowHeight)
			T.expect(row.resetButton).toBeNil()
			T.expect(row.keyframeButton).toBeNil()
			row:destroy()
		end)

		T.itIf(isLune, "shows the reset button while the value differs from the default", function()
			local host = newHost()
			local resets = 0
			local field = NumberInput.new({ value = 20, host = host })
			local row = PropertyRow.new({
				label = "Rate",
				description = "Partikel pro Sekunde",
				host = host,
				field = field,
				value = 20,
				default = 20,
				onReset = function()
					resets += 1
				end,
			})
			T.expect(field.instance.Parent).toBe(row.slot)
			T.expect(row:isModified()).toBe(false)
			T.expect(row.resetButton.instance.Visible).toBe(false)
			T.expect(row.label.TextColor3).toEqual(Theme.colors.textDim)
			row:setValue(42)
			T.expect(field:getValue()).toBe(42)
			T.expect(row.resetButton.instance.Visible).toBe(true)
			T.expect(row.label.TextColor3).toEqual(Theme.colors.text)
			fire(row.resetButton.instance, "Activated", mouseInput(), 1)
			T.expect(resets).toBe(1)
			row:setValue(20)
			T.expect(row.resetButton.instance.Visible).toBe(false)
			row:setModified(true)
			T.expect(row.resetButton.instance.Visible).toBe(true)
			row:setModified(nil)
			row:setEnabled(false)
			T.expect(field._enabled).toBe(false)
			row:destroy()
			T.expect(field.instance.Parent).toBeNil()
		end)

		T.it("compares vector defaults structurally", function()
			local row = PropertyRow.new({ label = "Offset", value = { 0, 0, 0 }, default = { 0, 0, 0 } })
			T.expect(row:isModified()).toBe(false)
			row:setValue({ 0, 1, 0 })
			T.expect(row:isModified()).toBe(true)
			T.expect(PropertyRow.deepEqual(tuple(1, { 2 }), tuple(1, { 2 }))).toBe(true)
			T.expect(PropertyRow.deepEqual({ 1 }, { 1, 2 })).toBe(false)
			T.expect(PropertyRow.deepEqual(0.1 + 0.2, 0.3)).toBe(true)
			row:destroy()
		end)

		T.itIf(isLune, "shows keyframe states and reports clicks", function()
			local clicks: { string } = {}
			local row = PropertyRow.new({
				label = "Brightness",
				keyframe = "none",
				onKeyframe = function(state: string)
					table.insert(clicks, state)
				end,
			})
			local button = row.keyframeButton.instance
			local diamond = button:FindFirstChild("Diamond") :: Frame
			local stroke = diamond:FindFirstChildOfClass("UIStroke") :: UIStroke
			T.expect(diamond.Rotation).toBe(45)
			T.expect(diamond.BackgroundTransparency).toBe(1)
			T.expect(stroke.Color).toEqual(Theme.colors.textMuted)
			row:setKeyframeState("has-track")
			T.expect(stroke.Color).toEqual(Theme.colors.keyframe)
			T.expect(diamond.BackgroundTransparency).toBe(1)
			row:setKeyframeState("key-at-playhead")
			T.expect(diamond.BackgroundTransparency).toBe(0)
			T.expect(diamond.BackgroundColor3).toEqual(Theme.colors.keyframe)
			fire(button, "Activated", mouseInput(), 1)
			T.expect(clicks).toEqual({ "key-at-playhead" })
			row:setKeyframeState(nil)
			T.expect(button.Visible).toBe(false)
			row:destroy()
		end)
	end)

	-- Section ----------------------------------------------------------------------------------------------------

	T.describe("Section", function()
		T.itIf(isLune, "collapses, expands and owns its rows", function()
			local toggles: { boolean } = {}
			local section = Section.new({
				title = "Emission",
				badge = "2",
				onToggle = function(expanded: boolean)
					table.insert(toggles, expanded)
				end,
			})
			T.expect(section:isExpanded()).toBe(true)
			T.expect(section.body.Visible).toBe(true)
			T.expect((section.header:FindFirstChild("Arrow") :: TextLabel).Rotation).toBe(90)
			T.expect((section.header:FindFirstChild("Badge") :: TextLabel).Text).toBe("2")
			local a = section:add(fakeWidget())
			local b = section:add(Instance.new("Frame"))
			T.expect(a.instance.LayoutOrder).toBe(1)
			T.expect(b.LayoutOrder).toBe(2)
			T.expect(b.Parent).toBe(section.body)
			fire(section.header, "Activated", mouseInput(), 1)
			T.expect(toggles).toEqual({ false })
			T.expect(section.body.Visible).toBe(false)
			section:setExpanded(true)
			T.expect(#toggles).toBe(1)
			T.expect(section.body.Visible).toBe(true)
			section:setEnabled(false)
			T.expect(a.enabled).toBe(false)
			fire(section.header, "Activated", mouseInput(), 1)
			T.expect(#toggles).toBe(1)
			section:clear()
			T.expect(a.destroyed).toBe(true)
			T.expect(b.Parent).toBeNil()
			section:destroy()
			T.expect(section.instance.Parent).toBeNil()
		end)
	end)

	-- Vector inputs ----------------------------------------------------------------------------------------------

	T.describe("Vector3Input", function()
		T.it("builds X/Y/Z NumberInputs with coloured axis labels", function()
			local v = Vector3Input.new({ value = { 1, 2, 3 } })
			T.expect(#v.fields).toBe(3)
			T.expect(v.fields[1].scrub.Text).toBe("X")
			T.expect(v.fields[1].scrub.TextColor3).toEqual(Theme.colors.error)
			T.expect(v.fields[2].scrub.TextColor3).toEqual(Theme.colors.success)
			T.expect(v.fields[3].scrub.TextColor3).toEqual(Theme.colors.loop)
			T.expect(v.fields[1].instance:FindFirstChildOfClass("UIFlexItem")).never.toBeNil()
			T.expect(v:getValue()).toEqual({ 1, 2, 3 })
			v:setValue(Vector3.new(4, 5, 6))
			T.expect(v:getValue()).toEqual({ 4, 5, 6 })
			T.expect(Vector3Input.toArray({ 1 }, 3)).toEqual({ 1, 0, 0 })
			v:destroy()
			T.expect(v.instance.Parent).toBeNil()
		end)

		T.itIf(isLune, "reports typed values as fresh arrays", function()
			local log: { any } = {}
			local v = Vector3Input.new({
				value = { 0, 0, 0 },
				onChange = function(value: { number }, final: boolean)
					table.insert(log, tuple(value, final))
				end,
			})
			local box = v.fields[2].box
			box.Text = "2,5"
			fire(box, "FocusLost", true, nil)
			T.expect(log[1]).toEqual(tuple({ 0, 2.5, 0 }, true))
			log[1][1][1] = 99 -- the widget keeps its own copy
			v.fields[3].box.Text = "1+1"
			fire(v.fields[3].box, "FocusLost", true, nil)
			T.expect(log[2]).toEqual(tuple({ 0, 2.5, 2 }, true))
			v:setValue({ 7, 8, 9 }) -- no callback
			T.expect(#log).toBe(2)
			v:setMixed({ false, true, false })
			T.expect(v.fields[2].box.Text).toBe("—")
			v:destroy()
		end)

		T.itIf(isLune, "streams scrub drags on an axis label and ends with final = true", function()
			local host = newHost()
			local log: { any } = {}
			local v = Vector3Input.new({
				value = { 0, 0, 0 },
				host = host,
				onChange = function(value: { number }, final: boolean)
					table.insert(log, tuple(value, final))
				end,
			})
			drag(host, v.fields[1].scrub, Vector2.new(10, 10), { Vector2.new(20, 10), Vector2.new(30, 10) })
			T.expect(#log).toBeGreaterThanOrEqual(2)
			T.expect(log[1][2]).toBe(false)
			T.expect(log[#log]).toEqual(tuple({ 2, 0, 0 }, true)) -- 20px × default step 0.1
			T.expect(v:isDragging()).toBe(false)
			v:setEnabled(false)
			T.expect(v.fields[1]._enabled).toBe(false)
			v:destroy()
		end)
	end)

	T.describe("Vector2Input", function()
		T.itIf(isLune, "edits { x, y }", function()
			local log: { any } = {}
			local v = Vector2Input.new({
				value = Vector2.new(0.5, 0.25),
				precision = 3,
				onChange = function(value: { number }, final: boolean)
					table.insert(log, tuple(value, final))
				end,
			})
			T.expect(#v.fields).toBe(2)
			T.expect(v.instance.Name).toBe("Vector2Input")
			T.expect(v:getValue()).toEqual({ 0.5, 0.25 })
			v.fields[1].box.Text = "1"
			fire(v.fields[1].box, "FocusLost", true, nil)
			T.expect(log[1]).toEqual(tuple({ 1, 0.25 }, true))
			v:destroy()
		end)
	end)

	T.describe("NumberRangeInput", function()
		T.itIf(isLune, "keeps min <= max", function()
			local log: { any } = {}
			local r = NumberRangeInput.new({
				value = 2,
				onChange = function(value: { number }, final: boolean)
					table.insert(log, tuple(value, final))
				end,
			})
			T.expect(r:getValue()).toEqual({ 2, 2 })
			T.expect(r.fields[1].scrub.Text).toBe("Min")
			r.fields[2].box.Text = "3"
			fire(r.fields[2].box, "FocusLost", true, nil)
			T.expect(log[1]).toEqual(tuple({ 2, 3 }, true))
			-- min above max pushes max up
			r.fields[1].box.Text = "5"
			fire(r.fields[1].box, "FocusLost", true, nil)
			T.expect(log[2]).toEqual(tuple({ 5, 5 }, true))
			T.expect(r:getValue()).toEqual({ 5, 5 })
			-- max below min pulls min down
			r.fields[2].box.Text = "1"
			fire(r.fields[2].box, "FocusLost", true, nil)
			T.expect(log[3]).toEqual(tuple({ 1, 1 }, true))
			-- external values are ordered
			r:setValue({ 4, 1 })
			T.expect(r:getValue()).toEqual({ 1, 4 })
			r:setValue(NumberRange.new(0.5, 2))
			T.expect(r:getValue()).toEqual({ 0.5, 2 })
			T.expect(#log).toBe(3)
			r:destroy()
		end)
	end)

	-- ColorSwatch ------------------------------------------------------------------------------------------------

	T.describe("ColorSwatch", function()
		T.it("previews hex, palette, rgb and gradient values", function()
			local swatch = ColorSwatch.new({ value = "#FF8A3D", palette = { accent = Theme.colors.accent } })
			T.expect(swatch.chip.BackgroundColor3).toEqual(Color3.fromRGB(255, 138, 61))
			T.expect(swatch.text.Text).toBe("#FF8A3D")
			T.expect(swatch.gradient.Enabled).toBe(false)
			swatch:setValue("$accent")
			T.expect(swatch:getColor()).toEqual(Theme.colors.accent)
			T.expect(swatch.text.Text).toBe("$accent")
			swatch:setValue({ 0, 128, 255 })
			T.expect(swatch.text.Text).toBe("#0080FF")
			swatch:setValue(Color3.new(1, 1, 1))
			T.expect(swatch.text.Text).toBe("#FFFFFF")
			swatch:setValue("not a colour")
			T.expect(swatch:getColor()).toBeNil()
			T.expect(swatch.text.TextColor3).toEqual(Theme.colors.textMuted)
			swatch:setValue({ tuple(0, "#FF0000"), tuple(0.5, "#00FF00"), tuple(1, "#0000FF") })
			T.expect(swatch.gradient.Enabled).toBe(true)
			T.expect(#swatch.gradient.Color.Keypoints).toBe(3)
			T.expect(swatch.text.Visible).toBe(false)
			T.expect(swatch:getSequence()).never.toBeNil()
			swatch:destroy()
			T.expect(swatch.instance.Parent).toBeNil()
		end)

		T.itIf(isLune, "calls onPick on click and commit() reports changes", function()
			local picks: { any } = {}
			local changes: { any } = {}
			local swatch
			swatch = ColorSwatch.new({
				value = "#112233",
				onPick = function(s: any, current: any)
					table.insert(picks, current)
					T.expect(s).toBe(swatch)
				end,
				onChange = function(value: any, final: boolean)
					table.insert(changes, tuple(value, final))
				end,
			})
			fire(swatch.instance, "Activated", mouseInput(), 1)
			T.expect(picks).toEqual({ "#112233" })
			swatch:commit("#445566", false)
			swatch:commit("#778899")
			T.expect(changes).toEqual({ tuple("#445566", false), tuple("#778899", true) })
			T.expect(swatch.text.Text).toBe("#778899")
			swatch:setValue("#000000")
			T.expect(#changes).toBe(2)
			swatch:setEnabled(false)
			fire(swatch.instance, "Activated", mouseInput(), 1)
			T.expect(#picks).toBe(1)
			swatch:destroy()
		end)
	end)

	-- AssetInput -------------------------------------------------------------------------------------------------

	T.describe("AssetInput", function()
		T.it("parses asset strings and builds thumbnails", function()
			T.expect(AssetInput.parse("123")).toBe("rbxassetid://123")
			T.expect(AssetInput.parse(" rbxassetid://99 ")).toBe("rbxassetid://99")
			T.expect(AssetInput.parse("https://www.roblox.com/asset/?id=77")).toBe("rbxassetid://77")
			T.expect(AssetInput.parse("rbxasset://textures/particles/sparkles_main.dds"))
				.toBe("rbxasset://textures/particles/sparkles_main.dds")
			T.expect(AssetInput.parse("")).toBe("")
			local bad, err = AssetInput.parse("hello")
			T.expect(bad).toBeNil()
			T.expect(err).toMatch("Ungültige")
			T.expect(AssetInput.thumbnail("rbxassetid://123")).toBe("rbxthumb://type=Asset&id=123&w=150&h=150")
			T.expect(AssetInput.thumbnail("rbxasset://textures/x.png")).toBe("rbxasset://textures/x.png")
			T.expect(AssetInput.thumbnail("")).toBe("")

			local input = AssetInput.new({ value = "rbxassetid://123" })
			T.expect(input.preview.Image).toBe("rbxthumb://type=Asset&id=123&w=150&h=150")
			T.expect(input.input.box.Text).toBe("rbxassetid://123")
			T.expect(input.button.instance.Text).toMatch("Wählen")
			input:setValue("rbxasset://textures/x.png")
			T.expect(input.preview.Image).toBe("rbxasset://textures/x.png")
			input:destroy()
			T.expect(input.instance.Parent).toBeNil()
		end)

		T.itIf(isLune, "commits typed ids canonically and rejects invalid text", function()
			local log: { any } = {}
			local input = AssetInput.new({
				value = "",
				onChange = function(asset: string, final: boolean)
					table.insert(log, tuple(asset, final))
				end,
			})
			local box = input.input.box
			box.Text = "456"
			fire(box, "FocusLost", true, nil)
			T.expect(log).toEqual({ tuple("rbxassetid://456", true) })
			T.expect(box.Text).toBe("rbxassetid://456")
			T.expect(input.preview.Image).toBe("rbxthumb://type=Asset&id=456&w=150&h=150")
			box.Text = "kaputt"
			fire(box, "FocusLost", true, nil)
			T.expect(#log).toBe(1)
			T.expect(input.input:getError()).never.toBeNil()
			T.expect(input:getValue()).toBe("rbxassetid://456")
			input:destroy()
		end)

		T.itIf(isLune, "opens Studio's asset picker through host.plugin", function()
			local host = newHost()
			local requested: { string } = {}
			local answer: any = 4242
			host.plugin.PromptForExistingAssetIdAsync = function(_self: any, assetType: string)
				table.insert(requested, assetType)
				if answer == "error" then
					error("picker unavailable")
				end
				return answer
			end
			local log: { any } = {}
			local input = AssetInput.new({
				host = host,
				onChange = function(asset: string, final: boolean)
					table.insert(log, tuple(asset, final))
				end,
			})
			fire(input.button.instance, "Activated", mouseInput(), 1)
			T.expect(requested).toEqual({ "Image" })
			T.expect(log).toEqual({ tuple("rbxassetid://4242", true) })
			T.expect(input.preview.Image).toBe("rbxthumb://type=Asset&id=4242&w=150&h=150")
			answer = -1 -- cancelled
			input:pick()
			answer = "error" -- pcall-wrapped
			input:pick()
			T.expect(#requested).toBe(3)
			T.expect(#log).toBe(1)
			T.expect(input:isPicking()).toBe(false)
			input:setEnabled(false)
			input:pick()
			T.expect(#requested).toBe(3)
			input:destroy()
		end)
	end)

	-- Menus ------------------------------------------------------------------------------------------------------

	T.describe("Menus", function()
		local function trackedPlugin(): (any, { any })
			local plugin = ctx.plugin.newPlugin()
			local created: { any } = {}
			local original = plugin.CreatePluginMenu
			plugin.CreatePluginMenu = function(self: any, id: string, title: string?, icon: string?)
				local menu = original(self, id, title, icon)
				menu.destroyed = false
				function menu.Destroy(m: any)
					m.destroyed = true
				end
				table.insert(created, menu)
				return menu
			end
			return plugin, created
		end

		local ITEMS: { any } = {
			{ id = "rename", text = "Umbenennen" },
			{ separator = true },
			{ id = "add", text = "Hinzufügen", items = { { id = "particles", text = "Partikel" } } },
			{ separator = true },
			{ id = "delete", text = "Löschen", disabled = true },
			{ separator = true },
		}

		T.itIf(isLune, "builds prefixed actions and maps the choice back to the item id", function()
			local plugin, created = trackedPlugin()
			local menus = Menus.new(plugin)
			local menu = menus:build("explorer", ITEMS)
			T.expect(#created).toBe(2) -- root + submenu
			-- rename, separator, submenu; disabled entry and dangling separators are dropped
			T.expect(#menu.items).toBe(3)
			T.expect(menu.items[1].action.ActionId).toBe("explorer/rename")
			T.expect(menu.items[2].kind).toBe("separator")
			T.expect(menu.items[3].kind).toBe("menu")
			T.expect(menu.items[3].menu.Title).toBe("Hinzufügen")
			T.expect(menu.items[3].menu.items[1].action.ActionId).toBe("explorer/add/particles")

			menu.nextChoice = "explorer/rename"
			T.expect(menus:show("explorer", ITEMS)).toBe("rename")
			menu.nextChoice = "explorer/add/particles"
			T.expect(menus:show("explorer", ITEMS)).toBe("particles")
			T.expect(menus:show("explorer", ITEMS)).toBeNil() -- dismissed
			T.expect(#created).toBe(2) -- cached
			menus:destroy()
		end)

		T.itIf(isLune, "rebuilds only when items change and destroys everything", function()
			local plugin, created = trackedPlugin()
			local menus = Menus.new(plugin)
			local activated = 0
			local items = {
				{ id = "a", text = "A" },
				{
					id = "b",
					text = "B",
					checked = true,
					onActivate = function()
						activated += 1
					end,
				},
			}
			local menu = menus:build("ctx", items)
			T.expect(menu.items[2].action.Text).toBe("✓ B")
			local firstAction = menu.items[1].action
			menus:build("ctx", items)
			T.expect(menu.items[1].action).toBe(firstAction) -- unchanged: no rebuild
			menus:build("ctx", { { id = "c", text = "C" } })
			T.expect(#menu.items).toBe(1)
			T.expect(menu.items[1].action.ActionId).toBe("ctx/c")
			T.expect(#created).toBe(1)

			local chosen: { string } = {}
			menu = menus:build("ctx", items)
			menu.nextChoice = "ctx/b"
			menus:open("ctx", items, function(id: string)
				table.insert(chosen, id)
			end)
			T.expect(chosen).toEqual({ "b" })
			T.expect(activated).toBe(1)
			T.expect(menus:isShowing("ctx")).toBe(false)

			menus:build("other", { { id = "x", text = "X", items = { { id = "y", text = "Y" } } } })
			T.expect(#created).toBe(3)
			menus:destroy()
			for _, m in created do
				T.expect(m.destroyed).toBe(true)
			end
			T.expect(menus:show("ctx", items)).toBeNil()
			T.expect(function()
				menus:build("ctx", items)
			end).toThrow("destroy")
		end)

		T.itIf(isLune, "uses the latest item callbacks when the cached menu is reused", function()
			local plugin = ctx.plugin.newPlugin()
			local menus = Menus.new(plugin)
			local hits: { string } = {}
			local function items(target: string): { any }
				return {
					{
						id = "delete",
						text = "Löschen",
						onActivate = function()
							table.insert(hits, target)
						end,
					},
				}
			end
			menus:build("row", items("first"))
			plugin.menus.row.nextChoice = "row/delete"
			T.expect(menus:show("row", items("second"))).toBe("delete")
			T.expect(hits).toEqual({ "second" })
			menus:destroy()
		end)

		T.it("computes stable signatures", function()
			local withSeparator: { any } = { { id = "a", text = "A" }, { separator = true } }
			local a = Menus.signature(withSeparator)
			local b = Menus.signature(table.clone(withSeparator))
			local c = Menus.signature({ { id = "a", text = "A2" } })
			T.expect(a).toBe(b)
			T.expect(a).never.toBe(c)
		end)
	end)
end
