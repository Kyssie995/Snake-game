--!strict
-- Review of the value editors (UI/Editors) against the widget contract (docs/UI_WIDGETS.md §1 and §6 "Editoren"):
-- * one final report per gesture, and no report at all for edits that change nothing (no empty undo steps);
-- * setEnabled(false) closes a running gesture with exactly one final and ignores the rest of it;
-- * a setValue that changes the keypoint count under a gesture ends the gesture (like CurveGraph.setKeyframes);
-- * values handed to the host are copies;
-- * no equal keypoint times (engine question U13, decision K3 in docs/ROBLOX_API_CONSTRAINTS.md);
-- * popups on the popup layer (ControlKit.Z) and no Heartbeat connection left behind.
-- Rendering and real mouse input are NOT verified here (Lune: ControlKit.geometry reports position 0 and the
-- Size offsets, or 100 px for axes without a positive offset).
return function(T: any, use: (string) -> any, ctx: any)
	local Kit = use("Plugin.UI.Widgets.ControlKit")
	local ColorPicker = use("Plugin.UI.Editors.ColorPicker")
	local GradientEditor = use("Plugin.UI.Editors.GradientEditor")
	local SequenceEditor = use("Plugin.UI.Editors.SequenceEditor")
	local EasingPicker = use("Plugin.UI.Editors.EasingPicker")
	local CurveGraph = use("Plugin.UI.Editors.CurveGraph")
	local Codec = use("AstraVFX.Core.Codec")
	local Easing = use("AstraVFX.Core.Easing")

	local lune = ctx.environment == "lune"

	local hostCounter = 0
	local function makeHost(): any
		hostCounter += 1
		local root = Instance.new("Frame")
		root.Name = "Root"
		root.Size = UDim2.fromOffset(600, 500)
		local widget = ctx.plugin.newWidget("AstraVFX_EditorsReview" .. hostCounter)
		root.Parent = widget.gui
		return { plugin = ctx.plugin.newPlugin(), widget = widget, root = root }
	end

	local function fire(inst: any, event: string, ...: any)
		ctx.fakes:signalFor(inst, event):Fire(...)
	end

	local function mouseInput(button: Enum.UserInputType?): any
		local input: any = {
			UserInputType = button or Enum.UserInputType.MouseButton1,
			UserInputState = Enum.UserInputState.Begin,
			Position = Vector3.new(0, 0, 0),
			KeyCode = nil, -- Lune's enum database has no KeyCode.Unknown
		}
		function input.IsModifierKeyDown(_self: any, _key: any): boolean
			return false
		end
		return input
	end

	-- Press at `from` and move through `path` (one Heartbeat each) without releasing; returns the press input.
	local function beginDrag(host: any, gui: any, from: Vector2, path: { Vector2 }): any
		host.widget.mouse = from
		local input = mouseInput()
		fire(gui, "InputBegan", input)
		for _, pos in path do
			host.widget.mouse = pos
			ctx.fakes:step(1 / 60)
		end
		return input
	end

	local function moveTo(host: any, pos: Vector2)
		host.widget.mouse = pos
		ctx.fakes:step(1 / 60)
	end

	local function release(input: any)
		input.UserInputState = Enum.UserInputState.End
		ctx.fakes:step(1 / 60)
	end

	local function drag(host: any, gui: any, from: Vector2, path: { Vector2 })
		release(beginDrag(host, gui, from, path))
	end

	local function recorder(): ({ { any } }, (...any) -> ())
		local log: { { any } } = {}
		return log, function(...: any)
			table.insert(log, { ... })
		end
	end

	local function finals(log: { { any } }): number
		local n = 0
		for _, entry in log do
			if entry[2] == true then
				n += 1
			end
		end
		return n
	end

	local function heartbeatCount(): number
		return ctx.fakes.heartbeat:connectionCount()
	end

	-- mixed-type array (the old type solver infers literal arrays from their first element)
	local function L(...: any): { any }
		return { ... }
	end

	local function hex(r: number, g: number, b: number): string
		return string.format("#%02X%02X%02X", r, g, b)
	end

	local function times(editor: any): { number }
		local out: { number } = {}
		for _, kp in editor:getKeypoints() do
			table.insert(out, kp[1])
		end
		return out
	end

	-- Valid JSON (Codec.check) with strictly increasing keypoint times (no equal times, engine question U13).
	local function expectStrictSequence(kind: string, value: any, spec: any?)
		local ok, message = Codec.check(kind, value, spec)
		if not ok then
			T.fail("invalid " .. kind .. ": " .. tostring(message))
		end
		if type(value) == "table" and type(value[1]) == "table" then
			for i = 2, #value do
				if not (value[i][1] > value[i - 1][1]) then
					T.fail(kind .. " has equal keypoint times at " .. i .. ": " .. tostring(value[i][1]))
				end
			end
		end
	end

	local BW = L(L(0, "#000000"), L(1, "#FFFFFF"))
	local RGB = L(L(0, "#FF0000"), L(0.5, "#00FF00"), L(1, "#0000FF"))

	-- GradientEditor --------------------------------------------------------------------------------------------

	T.describe("Review: GradientEditor", function()
		T.itIf(lune, "reports and returns copies, so a host editing them cannot corrupt the editor", function()
			local host = makeHost()
			local reported: any = nil
			local editor = GradientEditor.new({
				value = RGB,
				host = host,
				onChange = function(v: any, _final: boolean)
					reported = v
				end,
			})
			editor:addKeypoint(0.25)
			local before = editor:getKeypoints()
			T.expect(type(reported)).toBe("table")
			reported[2][2] = "#123456" -- the host keeps the reported table and edits it
			local got = editor:getValue()
			got[3][2] = "#ABCDEF"
			T.expect(editor:getKeypoints()).toEqual(before)
			T.expect(editor:getValue()).toEqual(Codec.normalize("colorSequence", before))
			-- the host writes its edited copy back: the editor shows it
			editor:setValue(reported)
			T.expect(editor:getKeypoints()[2]).toEqual(L(0.25, "#123456"))
			editor:destroy()
		end)

		T.itIf(lune, "never creates equal keypoint times (adding, clicking the bar edges, dragging, typing)", function()
			local host = makeHost()
			local log, onChange = recorder()
			local editor = GradientEditor.new({ value = BW, host = host, onChange = onChange })
			T.expect(editor:addKeypoint(0)).toBe(2)
			T.expect(editor:addKeypoint(1)).toBe(3)
			T.expect(times(editor)).toEqual({ 0, 0.001, 0.999, 1 })
			T.expect(editor:addKeypoint(0.0004)).toBeNil() -- no room next to the first keypoint
			T.expect(editor:addKeypoint(0.9995)).toBeNil()
			-- clicking the very edges of the bar (Lune: 100 px wide at x = 0)
			editor:setValue(BW)
			drag(host, editor.barHit, Vector2.new(0, 10), {})
			drag(host, editor.barHit, Vector2.new(100, 10), {})
			T.expect(times(editor)).toEqual({ 0, 0.001, 0.999, 1 })
			local count = #log
			drag(host, editor.barHit, Vector2.new(0, 10), {}) -- no room left at the edge: nothing happens
			T.expect(#log).toBe(count)
			T.expect(editor:keypointCount()).toBe(4)
			-- dragging onto a neighbour stops one step (0.001) before it
			editor:setValue(L(L(0, "#FF0000"), L(0.3, "#00FF00"), L(0.6, "#0000FF"), L(1, "#FFFFFF")))
			drag(host, editor.handles[2].button, Vector2.new(30, 8), { Vector2.new(95, 8) })
			T.expect(times(editor)).toEqual({ 0, 0.599, 0.6, 1 })
			drag(host, editor.handles[3].button, Vector2.new(60, 8), { Vector2.new(-200, 8) })
			T.expect(times(editor)).toEqual({ 0, 0.599, 0.6, 1 })
			-- the time field's range and programmatic times follow the same rule
			editor:selectKeypoint(2)
			T.expect(editor.timeInput._min).toBe(0.001)
			T.expect(editor.timeInput._max).toBe(0.599)
			editor:setKeypointTime(3, 0.2)
			T.expect(times(editor)).toEqual({ 0, 0.599, 0.6, 1 })
			editor:setKeypointTime(2, 0)
			T.expect(times(editor)).toEqual({ 0, 0.001, 0.6, 1 })
			for _, entry in log do
				expectStrictSequence("colorSequence", entry[1])
			end
			-- documents that already contain equal times are shown unchanged
			editor:setValue(L(L(0, "#000000"), L(0.5, "#FF0000"), L(0.5, "#00FF00"), L(1, "#FFFFFF")))
			T.expect(times(editor)).toEqual({ 0, 0.5, 0.5, 1 })
			editor:destroy()
		end)

		T.itIf(lune, "setEnabled(false) ends a running gesture with one final and ignores the rest of it", function()
			local host = makeHost()
			local log, onChange = recorder()
			local baseline = heartbeatCount()
			local editor = GradientEditor.new({ value = BW, host = host, onChange = onChange })
			local input = beginDrag(host, editor.barHit, Vector2.new(30, 10), { Vector2.new(40, 10) })
			T.expect(log[#log][2]).toBe(false)
			editor:setEnabled(false)
			T.expect(finals(log)).toBe(1)
			T.expect(log[#log]).toEqual(L(editor:getValue(), true))
			local count = #log
			local before = editor:getKeypoints()
			moveTo(host, Vector2.new(80, 10))
			release(input)
			T.expect(#log).toBe(count)
			T.expect(editor:getKeypoints()).toEqual(before)
			T.expect(heartbeatCount()).toBe(baseline)
			-- the programmatic edits act like the user: ignored while disabled
			T.expect(editor:addKeypoint(0.7)).toBeNil()
			T.expect(editor:removeKeypoint(2)).toBe(false)
			T.expect(editor:setKeypointTime(2, 0.9)).toBe(false)
			T.expect(editor:setKeypointColor(2, "#FF00FF")).toBe(false)
			T.expect(editor:applyPreset("fire")).toBe(false)
			T.expect(editor:getKeypoints()).toEqual(before)
			T.expect(#log).toBe(count)
			editor:destroy()

			-- a popup or inline picker drag and a time scrub end the same way
			for _, mode in { "popup", "inline", "time" } do
				table.clear(log)
				local other = GradientEditor.new({
					value = RGB,
					host = host,
					inlinePicker = mode == "inline",
					onChange = onChange,
				})
				other.instance.Parent = host.root
				other:selectKeypoint(2)
				local press
				if mode == "popup" then
					local popup = other:openPicker()
					press = beginDrag(host, popup.svHit, Vector2.new(0, 0), { Vector2.new(20, 20) })
				elseif mode == "inline" then
					press = beginDrag(host, other.picker.svHit, Vector2.new(0, 0), { Vector2.new(20, 20) })
				else
					press = beginDrag(host, other.timeInput.scrub, Vector2.new(5, 5), { Vector2.new(15, 5) })
				end
				T.expect(log[#log][2]).toBe(false)
				other:setEnabled(false)
				T.expect(finals(log)).toBe(1)
				T.expect(log[#log][2]).toBe(true)
				moveTo(host, Vector2.new(40, 5))
				release(press)
				T.expect(finals(log)).toBe(1)
				T.expect(log[#log][2]).toBe(true)
				T.expect(host.root:FindFirstChild("AstraColorPicker")).toBeNil()
				other:destroy()
			end
			T.expect(heartbeatCount()).toBe(baseline)
		end)

		T.itIf(lune, "a scrub that changed nothing before setEnabled(false) does not block the next scrub", function()
			local host = makeHost()
			local log, onChange = recorder()
			local editor = GradientEditor.new({ value = RGB, host = host, onChange = onChange })
			editor:selectKeypoint(2)
			-- vertical movement: the scrub starts (past the drag threshold) but changes nothing
			local input = beginDrag(host, editor.timeInput.scrub, Vector2.new(5, 5), { Vector2.new(5, 15) })
			T.expect(editor.timeInput:isDragging()).toBe(true)
			editor:setEnabled(false)
			release(input)
			T.expect(#log).toBe(0)
			editor:setEnabled(true)
			drag(host, editor.timeInput.scrub, Vector2.new(5, 5), { Vector2.new(15, 5) })
			T.expect(times(editor)).toEqual({ 0, 0.6, 1 })
			T.expect(#log).toBe(2)
			T.expect(log[2][2]).toBe(true)
			editor:destroy()
		end)

		T.itIf(lune, "rejects invalid programmatic input without errors", function()
			local host = makeHost()
			local log, onChange = recorder()
			local editor = GradientEditor.new({ value = RGB, host = host, onChange = onChange })
			T.expect(editor:addKeypoint(0 / 0)).toBeNil()
			T.expect(editor:addKeypoint(math.huge)).toBeNil()
			T.expect(editor:addKeypoint(0.25, "nope")).toBeNil()
			T.expect(editor:setKeypointTime(2, 0 / 0)).toBe(false)
			T.expect(editor:setKeypointColor(2, 42)).toBe(false)
			T.expect(editor:getValue()).toEqual(RGB)
			T.expect(#log).toBe(0)
			editor:destroy()
		end)

		T.itIf(lune, "closes the popup picker without writing when setValue removes its keypoint", function()
			local host = makeHost()
			local log, onChange = recorder()
			local editor = GradientEditor.new({ value = RGB, host = host, onChange = onChange })
			editor.instance.Parent = host.root
			editor:selectKeypoint(2)
			local popup = editor:openPicker()
			local input = beginDrag(host, popup.svHit, Vector2.new(0, 0), { Vector2.new(30, 30) })
			T.expect(log[#log][2]).toBe(false)
			-- Studio undo while the picker is open: the document no longer has keypoint 2
			editor:setValue(BW)
			T.expect(popup:isOpen()).toBe(false)
			T.expect(editor._popup).toBeNil()
			T.expect(host.root:FindFirstChild("AstraColorPicker")).toBeNil()
			-- the open gesture is closed once, with the document's value (not the stale drag value)
			T.expect(finals(log)).toBe(1)
			T.expect(log[#log]).toEqual(L(BW, true))
			moveTo(host, Vector2.new(60, 60))
			release(input)
			T.expect(finals(log)).toBe(1)
			T.expect(editor:getValue()).toEqual(BW)
			-- with an unchanged keypoint count the popup stays open and follows the document
			table.clear(log)
			editor:setValue(RGB)
			editor:selectKeypoint(2)
			local second = editor:openPicker()
			editor:setValue(L(L(0, "#FF0000"), L(0.5, "#123456"), L(1, "#0000FF")))
			T.expect(second:isOpen()).toBe(true)
			T.expect(second:getValue()).toBe("#123456")
			T.expect(#log).toBe(0)
			second:close()
			editor:destroy()
		end)

		T.itIf(lune, "the inline picker reverts to the selected keypoint's colour", function()
			local host = makeHost()
			local log, onChange = recorder()
			local editor = GradientEditor.new({ value = RGB, host = host, inlinePicker = true, onChange = onChange })
			editor:selectKeypoint(3)
			editor.picker:setHex("#FFFFFF")
			T.expect(editor:getKeypoints()[3]).toEqual(L(1, "#FFFFFF"))
			fire(editor.picker.original, "Activated") -- the "original" half of the preview
			T.expect(editor:getKeypoints()[3]).toEqual(L(1, "#0000FF"))
			T.expect(editor:getKeypoints()[1]).toEqual(L(0, "#FF0000"))
			T.expect(finals(log)).toBe(2)
			editor:destroy()
		end)
	end)

	-- ColorPicker ------------------------------------------------------------------------------------------------

	T.describe("Review: ColorPicker", function()
		T.itIf(lune, "setEnabled(false) ends a running drag with one final; later input changes nothing", function()
			local host = makeHost()
			local log, onChange = recorder()
			local baseline = heartbeatCount()
			local picker = ColorPicker.new({ value = "#FF0000", host = host, onChange = onChange })
			local input = beginDrag(host, picker.svHit, Vector2.new(100, 10), { Vector2.new(120, 40) })
			T.expect(log[#log][2]).toBe(false)
			picker:setEnabled(false)
			T.expect(finals(log)).toBe(1)
			T.expect(picker:isDragging()).toBe(false)
			local value = picker:getValue()
			local count = #log
			moveTo(host, Vector2.new(10, 100))
			release(input)
			T.expect(picker:getValue()).toBe(value)
			T.expect(#log).toBe(count)
			T.expect(heartbeatCount()).toBe(baseline)
			-- the methods that act like the user are ignored while disabled
			T.expect(picker:setHex("#00FF00")).toBe(false)
			picker:setHSV(0.5, 1, 1)
			picker:setRGB(1, 2, 3)
			T.expect(picker:getValue()).toBe(value)
			T.expect(#log).toBe(count)
			picker:setEnabled(true)
			T.expect(picker:setHex("#00FF00")).toBe(true)
			T.expect(log[#log]).toEqual(L("#00FF00", true))
			picker:destroy()
		end)

		T.itIf(lune, "the popup closes when the widget loses focus (like Dropdown and EasingPicker)", function()
			local host = makeHost()
			local log, onChange = recorder()
			local closed = 0
			local baseline = heartbeatCount()
			local picker = ColorPicker.open(host, {
				value = "#FF0000",
				onChange = onChange,
				onClose = function()
					closed += 1
				end,
			})
			beginDrag(host, picker.svHit, Vector2.new(100, 40), { Vector2.new(120, 60) })
			T.expect(log[#log][2]).toBe(false)
			host.widget.WindowFocusReleased:Fire()
			T.expect(picker:isOpen()).toBe(false)
			T.expect(closed).toBe(1)
			T.expect(finals(log)).toBe(1)
			T.expect(log[#log][2]).toBe(true)
			T.expect(host.root:FindFirstChild("AstraColorPicker")).toBeNil()
			T.expect(host.root:FindFirstChild("AstraColorPickerOverlay")).toBeNil()
			T.expect(heartbeatCount()).toBe(baseline)
			T.expect(host.widget.WindowFocusReleased:connectionCount()).toBe(0)
		end)
	end)

	-- SequenceEditor ---------------------------------------------------------------------------------------------

	T.describe("Review: SequenceEditor", function()
		T.itIf(lune, "edits that change nothing report nothing (no empty undo steps)", function()
			local host = makeHost()
			local log, onChange = recorder()
			local editor = SequenceEditor.new({
				value = L(L(0, 0), L(0.5, 1, 0.1), L(1, 0)),
				host = host,
				onChange = onChange,
			})
			editor:setKeypointValue(2, 1)
			editor:setKeypointTime(2, 0.5)
			editor:setKeypointEnvelope(2, 0.1)
			editor:setKeypointTime(1, 0.3) -- the first keypoint's time is locked
			editor:setKeypointValue(3, -5) -- clamped to the limit it already has
			T.expect(#log).toBe(0)
			T.expect(editor:applyPreset("pulse")).toBe(true)
			T.expect(#log).toBe(1)
			T.expect(editor:applyPreset("pulse")).toBe(true) -- already this preset
			T.expect(#log).toBe(1)
			-- right-click on an envelope handle that is already 0
			editor:setValue(L(L(0, 0), L(0.5, 1), L(1, 0)))
			editor:selectKeypoint(2)
			local top = editor:handlePixels()
			host.widget.mouse = top
			fire(editor.plot, "InputBegan", mouseInput(Enum.UserInputType.MouseButton2))
			T.expect(#log).toBe(1)
			-- a scrub whose last step equals the value still closes with one final
			table.clear(log)
			editor:setKeypointValue(2, 0.8, false)
			editor:setKeypointValue(2, 0.8, true)
			T.expect(log).toEqual(L(L(editor:getValue(), false), L(editor:getValue(), true)))
			editor:destroy()
		end)

		T.itIf(lune, "a keypoint removed during a drag closes the drag first", function()
			local host = makeHost()
			local log, onChange = recorder()
			local editor =
				SequenceEditor.new({ value = L(L(0, 0), L(0.5, 0.5), L(1, 0)), host = host, onChange = onChange })
			local from = editor:pointToPixel(0.5, 0.5)
			local input = beginDrag(host, editor.plot, from, { from + Vector2.new(0, -10) })
			T.expect(log[#log][2]).toBe(false)
			-- right-click on the dragged keypoint while the left button is still held
			fire(editor.plot, "InputBegan", mouseInput(Enum.UserInputType.MouseButton2))
			T.expect(editor:getKeypointCount()).toBe(2)
			T.expect(editor:isDragging()).toBe(false)
			T.expect(finals(log)).toBe(2) -- the drag's final, then the removal's
			local count = #log
			moveTo(host, from + Vector2.new(0, -40))
			release(input)
			T.expect(#log).toBe(count)
			T.expect(editor:getValue()).toBe(0) -- the remaining keypoints were not touched
			editor:destroy()
		end)

		T.itIf(lune, "setValue with another keypoint count during a drag ends the drag with one final", function()
			local host = makeHost()
			local log, onChange = recorder()
			local baseline = heartbeatCount()
			local editor =
				SequenceEditor.new({ value = L(L(0, 0), L(0.5, 0.5), L(1, 0)), host = host, onChange = onChange })
			local from = editor:pointToPixel(0.5, 0.5)
			local input = beginDrag(host, editor.plot, from, { from + Vector2.new(5, -10) })
			-- the document echoing the reported value keeps the drag alive
			editor:setValue(log[#log][1])
			T.expect(editor:isDragging()).toBe(true)
			-- Studio undo during the drag: another keypoint count
			local undone = L(L(0, 0.2), L(0.3, 0.4), L(0.7, 0.8), L(1, 0.1))
			editor:setValue(undone)
			T.expect(editor:isDragging()).toBe(false)
			T.expect(finals(log)).toBe(1)
			T.expect(log[#log]).toEqual(L(undone, true))
			local count = #log
			moveTo(host, from + Vector2.new(20, -40))
			release(input)
			T.expect(#log).toBe(count)
			T.expect(editor:getValue()).toEqual(undone)
			T.expect(heartbeatCount()).toBe(baseline)
			editor:destroy()
		end)

		T.itIf(lune, "setEnabled(false) during a field scrub closes the scrub's gesture once", function()
			local host = makeHost()
			local log, onChange = recorder()
			local editor =
				SequenceEditor.new({ value = L(L(0, 0), L(0.5, 0.5), L(1, 0)), host = host, onChange = onChange })
			editor:selectKeypoint(2)
			local input = beginDrag(host, editor.fields.value.scrub, Vector2.new(5, 5), { Vector2.new(15, 5) })
			T.expect(log[#log][2]).toBe(false)
			editor:setEnabled(false)
			T.expect(finals(log)).toBe(1)
			release(input) -- the field's own final arrives while the editor is disabled
			T.expect(finals(log)).toBe(1)
			T.expect(log[#log][2]).toBe(true)
			editor:destroy()
		end)

		T.itIf(lune, "a scrub that changed nothing before setEnabled(false) does not block the next scrub", function()
			local host = makeHost()
			local log, onChange = recorder()
			local editor =
				SequenceEditor.new({ value = L(L(0, 0), L(0.5, 0.5), L(1, 0)), host = host, onChange = onChange })
			editor:selectKeypoint(2)
			local input = beginDrag(host, editor.fields.value.scrub, Vector2.new(5, 5), { Vector2.new(5, 15) })
			T.expect(editor.fields.value:isDragging()).toBe(true)
			editor:setEnabled(false)
			release(input)
			T.expect(#log).toBe(0)
			editor:setEnabled(true)
			drag(host, editor.fields.value.scrub, Vector2.new(5, 5), { Vector2.new(15, 5) })
			T.expect(editor:getKeypoints()[2][2]).toBeGreaterThan(0.5)
			T.expect(#log).toBe(2)
			T.expect(log[2][2]).toBe(true)
			editor:destroy()
		end)

		T.it("ignores non-finite programmatic input", function()
			local log, onChange = recorder()
			local value = L(L(0, 0), L(0.5, 0.5), L(1, 0))
			local editor = SequenceEditor.new({ value = value, onChange = onChange })
			editor:setKeypointTime(2, 0 / 0)
			editor:setKeypointValue(2, 0 / 0)
			editor:setKeypointEnvelope(2, 0 / 0)
			editor:setKeypointValue(2, math.huge)
			T.expect(editor:addKeypoint(0.25, 0 / 0)).toBeNil()
			T.expect(editor:addKeypoint(0.25, nil, 0 / 0)).toBeNil()
			T.expect(editor:getValue()).toEqual(value)
			T.expect(#log).toBe(0)
			editor:destroy()
		end)
	end)

	-- EasingPicker -----------------------------------------------------------------------------------------------

	T.describe("Review: EasingPicker", function()
		T.itIf(lune, "presets and choices equal to the current value report nothing", function()
			local host = makeHost()
			local log, onChange = recorder()
			local picker = EasingPicker.new({
				value = { bezier = { 0.42, 0, 0.58, 1 } },
				host = host,
				onChange = onChange,
			})
			T.expect(picker:applyPreset("ease-in-out")).toBe(true)
			T.expect(picker:choose({ bezier = { 0.42, 0, 0.58, 1 } })).toBe(true)
			picker:setBezier(0.42, 0, 0.58, 1)
			T.expect(#log).toBe(0)
			picker:applyPreset("ease")
			T.expect(log).toEqual(L(L({ bezier = { 0.25, 0.1, 0.25, 1 } }, true)))
			-- a scrub whose last step equals the value still closes with one final
			table.clear(log)
			picker:setBezier(0.3, 0.1, 0.25, 1, false)
			picker:setBezier(0.3, 0.1, 0.25, 1, true)
			T.expect(log)
				.toEqual(L(L({ bezier = { 0.3, 0.1, 0.25, 1 } }, false), L({ bezier = { 0.3, 0.1, 0.25, 1 } }, true)))
			picker:destroy()
		end)

		T.itIf(lune, "setEnabled(false) during a bezier field scrub closes its gesture once", function()
			local host = makeHost()
			local log, onChange = recorder()
			local baseline = heartbeatCount()
			local picker =
				EasingPicker.new({ value = { bezier = { 0.25, 0.1, 0.25, 1 } }, host = host, onChange = onChange })
			picker.instance.Parent = host.root
			picker:open()
			local input = beginDrag(host, picker.bezierInputs[2].scrub, Vector2.new(5, 5), { Vector2.new(15, 5) })
			T.expect(log[#log][2]).toBe(false)
			picker:setEnabled(false)
			T.expect(picker:isOpen()).toBe(false)
			T.expect(finals(log)).toBe(1)
			T.expect(log[#log][2]).toBe(true)
			release(input)
			T.expect(finals(log)).toBe(1)
			T.expect(heartbeatCount()).toBe(baseline)
			-- destroying the picker during a scrub closes it once as well
			table.clear(log)
			picker:setEnabled(true)
			picker:open()
			beginDrag(host, picker.bezierInputs[1].scrub, Vector2.new(5, 5), { Vector2.new(25, 5) })
			T.expect(log[#log][2]).toBe(false)
			picker:destroy()
			T.expect(finals(log)).toBe(1)
			T.expect(log[#log][2]).toBe(true)
			T.expect(heartbeatCount()).toBe(baseline)
			for _, entry in log do
				T.expect(Easing.check(entry[1])).toBe(true)
			end
		end)
	end)

	-- CurveGraph -------------------------------------------------------------------------------------------------

	T.describe("Review: CurveGraph", function()
		T.it("moves and easings that change nothing report nothing", function()
			local log, onChange = recorder()
			local graph = CurveGraph.new({
				keyframes = { { time = 0, value = 0 }, { time = 1, value = 1 } },
				duration = 2,
				onChange = onChange,
			})
			graph:moveSelected(0.5, 0.5) -- nothing selected
			graph:select({ 1 })
			graph:moveSelected(0, 0)
			graph:moveSelected(-1, 0) -- already at time 0
			T.expect(#log).toBe(0)
			T.expect(graph:setEasing(1, "Quad.Out")).toBe(true)
			T.expect(#log).toBe(1)
			T.expect(graph:setEasing(1, "Quad.Out")).toBe(true)
			T.expect(#log).toBe(1)
			-- a programmatic scrub is still closed by a final without a further change
			table.clear(log)
			graph:moveSelected(0.25, 0, false)
			graph:moveSelected(0, 0, true)
			T.expect(#log).toBe(2)
			T.expect(log[1][2]).toBe(false)
			T.expect(log[2][2]).toBe(true)
			T.expect(log[2][1][1].time).toBe(0.25)
			graph:destroy()
		end)
	end)

	-- Fuzz -------------------------------------------------------------------------------------------------------

	-- Deterministic pseudo-random numbers (LCG), so failures reproduce.
	local function rng(seed: number): (number?, number?) -> number
		local state = seed
		return function(a: number?, b: number?): number
			state = (state * 1103515245 + 12345) % 2147483648
			local u = state / 2147483648
			if a == nil then
				return u
			end
			local lo, hi = if b == nil then 1 else a, if b == nil then a else b
			return lo + math.floor(u * (hi - lo + 1))
		end
	end

	-- Runs `steps` random operations; after each one, every report made during it is checked by `check`, and if
	-- the operation reported anything its last report must be final (no gesture left open).
	local function fuzz(steps: number, log: { { any } }, op: (step: number) -> string, check: (value: any) -> ())
		for step = 1, steps do
			local first = #log + 1
			local name = op(step)
			for i = first, #log do
				check(log[i][1])
			end
			if #log >= first and log[#log][2] ~= true then
				T.fail("step " .. step .. " (" .. name .. ") left a gesture open")
			end
		end
	end

	T.describe("Review: fuzzed gestures", function()
		T.itIf(lune, "GradientEditor: random edits keep every report valid and close every gesture", function()
			local host = makeHost()
			local random = rng(7)
			local log: { { any } } = {}
			local editor: any
			editor = GradientEditor.new({
				value = RGB,
				host = host,
				onChange = function(v: any, final: boolean)
					table.insert(log, { v, final })
					editor:setValue(v) -- the inspector re-renders with the document's value
				end,
			})
			local baseline = heartbeatCount()
			local function randomPath(): { Vector2 }
				local path: { Vector2 } = {}
				for _ = 1, random(0, 3) do
					table.insert(path, Vector2.new(random(-20, 120), 8))
				end
				return path
			end
			local function randomDocument(): any
				local n = random(2, 6)
				local list: { any } = { L(0, "#000000") }
				local t = 0
				for i = 2, n - 1 do
					t += random(1, math.floor((1 - t) * 1000 / (n - i + 1)) - 1) / 1000
					table.insert(list, L(t, hex(random(0, 255), random(0, 255), random(0, 255))))
				end
				table.insert(list, L(1, "#FFFFFF"))
				return list
			end
			fuzz(400, log, function(_step: number): string
				local kind = random(1, 9)
				local n = editor:keypointCount()
				if kind == 1 then
					drag(host, editor.barHit, Vector2.new(random(0, 100), 10), randomPath())
					return "bar"
				elseif kind == 2 then
					local i = random(1, n)
					local t = editor:getKeypoints()[i][1]
					drag(host, editor.handles[i].button, Vector2.new(t * 100, 8), randomPath())
					return "handle"
				elseif kind == 3 then
					editor:addKeypoint(random())
					return "add"
				elseif kind == 4 then
					editor:removeKeypoint(random(1, n))
					return "remove"
				elseif kind == 5 then
					local i = random(1, n)
					editor:setKeypointTime(i, random(), false)
					editor:setKeypointTime(i, random(), true)
					return "time"
				elseif kind == 6 then
					editor:setKeypointColor(random(1, n), hex(random(0, 255), random(0, 255), random(0, 255)))
					return "colour"
				elseif kind == 7 then
					local ids = { "solid", "twoTone", "fire", "ice", "energy" }
					editor:applyPreset(ids[random(1, #ids)])
					return "preset"
				elseif kind == 8 then
					editor:setValue(randomDocument()) -- external change (never reports)
					return "setValue"
				end
				-- a bar drag interrupted by an external change of the keypoint count
				local input = beginDrag(host, editor.barHit, Vector2.new(random(5, 95), 10), randomPath())
				editor:setValue(randomDocument())
				moveTo(host, Vector2.new(random(0, 100), 10))
				release(input)
				return "interrupted"
			end, function(value: any)
				expectStrictSequence("colorSequence", value)
			end)
			T.expect(finals(log)).toBeGreaterThan(100) -- the run really edits
			T.expect(heartbeatCount()).toBe(baseline)
			editor:destroy()
		end)

		T.itIf(lune, "SequenceEditor: random edits keep every report valid and close every gesture", function()
			local host = makeHost()
			local random = rng(11)
			local log: { { any } } = {}
			local spec = { min = 0, max = 10 }
			local editor: any
			editor = SequenceEditor.new({
				value = L(L(0, 1), L(0.5, 4, 0.5), L(1, 2)),
				min = 0,
				max = 10,
				range = { 0, 5 },
				host = host,
				onChange = function(v: any, final: boolean)
					table.insert(log, { v, final })
					editor:setValue(v)
				end,
			})
			local baseline = heartbeatCount()
			local function randomPath(from: Vector2): { Vector2 }
				local path: { Vector2 } = {}
				for _ = 1, random(0, 3) do
					table.insert(path, from + Vector2.new(random(-40, 40), random(-40, 40)))
				end
				return path
			end
			fuzz(400, log, function(_step: number): string
				local kind = random(1, 9)
				local keys = editor:getKeypoints()
				local n = #keys
				if kind <= 2 then
					local kp = keys[random(1, n)]
					local from = editor:pointToPixel(kp[1], kp[2])
					drag(host, editor.plot, from, randomPath(from))
					return "drag"
				elseif kind == 3 then
					editor:addKeypoint(random(), random(0, 10), if random(1, 2) == 1 then random() else nil)
					return "add"
				elseif kind == 4 then
					editor:removeKeypoint(random(1, n))
					return "remove"
				elseif kind == 5 then
					local i = random(1, n)
					local setter = ({ "setKeypointTime", "setKeypointValue", "setKeypointEnvelope" })[random(1, 3)]
					editor[setter](editor, i, random() * 12 - 1, false)
					editor[setter](editor, i, random() * 12 - 1, true)
					return setter
				elseif kind == 6 then
					editor:applyPreset(SequenceEditor.PRESETS[random(1, #SequenceEditor.PRESETS)].value)
					return "preset"
				elseif kind == 7 then
					editor:smooth()
					return "smooth"
				elseif kind == 8 then
					editor:setEnabled(false)
					editor:setEnabled(true)
					return "toggle"
				end
				-- a drag interrupted by a structural edit
				local kp = keys[random(1, n)]
				local from = editor:pointToPixel(kp[1], kp[2])
				local input = beginDrag(host, editor.plot, from, randomPath(from))
				if random(1, 2) == 1 then
					editor:addKeypoint(random())
				else
					editor:removeKeypoint(random(1, n))
				end
				moveTo(host, from + Vector2.new(random(-30, 30), random(-30, 30)))
				release(input)
				return "interrupted"
			end, function(value: any)
				expectStrictSequence("numberSequence", value, spec)
				if type(value) == "table" and #value > SequenceEditor.MAX_KEYPOINTS then
					T.fail("more than 20 keypoints")
				end
			end)
			T.expect(finals(log)).toBeGreaterThan(100)
			T.expect(heartbeatCount()).toBe(baseline)
			editor:destroy()
		end)

		T.itIf(lune, "CurveGraph: random edits keep every report a valid track and close every gesture", function()
			local host = makeHost()
			local random = rng(5)
			local log: { { any } } = {}
			local graph: any
			local keyframes: { any } = {
				{ time = 0, value = 0 },
				{ time = 0.5, value = 1, easing = { bezier = { 0.25, 0.1, 0.25, 1 } } },
				{ time = 1, value = 0.5, easing = "Quad.Out" },
				{ time = 1.5, value = 0.2 },
			}
			graph = CurveGraph.new({
				keyframes = keyframes,
				duration = 2,
				min = -1,
				max = 2,
				host = host,
				onChange = function(v: any, final: boolean)
					table.insert(log, { v, final })
					graph:setKeyframes(v)
				end,
			})
			local baseline = heartbeatCount()
			fuzz(300, log, function(_step: number): string
				local kind = random(1, 6)
				local keys = graph:getKeyframes()
				if #keys == 0 then
					graph:setKeyframes({ { time = 0, value = 0 }, { time = 1, value = 1 } })
					return "refill"
				end
				if kind <= 2 then
					local key = keys[random(1, #keys)]
					local from = graph:pointToPixel(key.time, key.value)
					local path: { Vector2 } = {}
					for _ = 1, random(1, 3) do
						table.insert(path, from + Vector2.new(random(-30, 30), random(-30, 30)))
					end
					drag(host, graph.plot, from, path)
					return "drag"
				elseif kind == 3 then
					graph:select({ random(1, #keys), random(1, #keys) })
					graph:moveSelected(random() - 0.5, random() - 0.5, false)
					graph:moveSelected(0, 0, true)
					return "move"
				elseif kind == 4 then
					local easings: { any } = { "Linear", "Back.InOut", { bezier = { 0.42, 0, 0.58, 1 } }, "Constant" }
					graph:setEasing(random(1, #keys), easings[random(1, #easings)])
					return "easing"
				elseif kind == 5 then
					-- drag a bezier handle when one is visible
					for i = 1, #keys - 1 do
						local p = graph:handlePixel(i, 1)
						if p then
							graph:select({ i })
							drag(host, graph.plot, p, { p + Vector2.new(random(-20, 20), random(-20, 20)) })
							return "handle"
						end
					end
					return "no handle"
				end
				if #keys > 2 then
					graph:select({ random(1, #keys) })
					graph:deleteSelected()
				end
				return "delete"
			end, function(value: any)
				T.expect(#value).toBeGreaterThan(0)
				local previous = -math.huge
				for _, key in value do
					if not (key.time >= 0 and key.time <= 2 and key.time >= previous) then
						T.fail("keyframe time out of order or range: " .. tostring(key.time))
					end
					previous = key.time
					if not (key.value >= -1 and key.value <= 2) then
						T.fail("keyframe value outside the limits: " .. tostring(key.value))
					end
					local ok, message = Easing.check(key.easing)
					if not ok then
						T.fail("invalid easing: " .. tostring(message))
					end
				end
			end)
			T.expect(finals(log)).toBeGreaterThan(60)
			T.expect(heartbeatCount()).toBe(baseline)
			graph:destroy()
		end)
	end)

	-- Layers and leaks -------------------------------------------------------------------------------------------

	T.describe("Review: popups and Heartbeat", function()
		T.itIf(lune, "popups sit on the popup layer above dialogs and toasts, below tooltips", function()
			local host = makeHost()
			local function expectLayer(popup: Instance, overlayName: string)
				local overlay = host.root:FindFirstChild(overlayName) :: GuiObject
				T.expect(overlay).toBeTruthy()
				T.expect(overlay.ZIndex).toBe(Kit.Z.popup)
				T.expect((popup :: GuiObject).ZIndex).toBe(Kit.Z.popup + 1)
				for _, d in popup:GetDescendants() do
					if d:IsA("GuiObject") then
						local z = (d :: GuiObject).ZIndex
						if z <= Kit.Z.popup or z >= Kit.Z.tooltip then
							T.fail(d:GetFullName() .. " has ZIndex " .. z)
						end
					end
				end
			end
			local picker = ColorPicker.open(host, { value = "#FF0000" })
			expectLayer(picker.instance, "AstraColorPickerOverlay")
			-- inside the square: gradient layers < cursor < hit area (survives ControlKit.raise)
			local shade = picker.svArea:FindFirstChild("Shade") :: GuiObject
			T.expect(shade.ZIndex).toBeGreaterThan(picker._hueLayer.ZIndex)
			T.expect(picker.svCursor.ZIndex).toBeGreaterThan(shade.ZIndex)
			T.expect(picker.svHit.ZIndex).toBeGreaterThan(picker.svCursor.ZIndex)
			T.expect(picker.hueHit.ZIndex).toBeGreaterThan(picker.hueCursor.ZIndex)
			picker:close()
			local easing = EasingPicker.new({ value = "Quad.Out", host = host, parent = host.root })
			easing:open()
			expectLayer(easing.popup, "AstraEasingOverlay")
			easing:destroy()
		end)

		T.itIf(lune, "every editor drag ends on focus loss with one final and drops its Heartbeat", function()
			local host = makeHost()
			local baseline = heartbeatCount()
			local cases: { { make: (onChange: any) -> any, gui: (e: any) -> any, from: (e: any) -> Vector2 } } = {
				{
					make = function(onChange: any): any
						return ColorPicker.new({ value = "#FF0000", host = host, onChange = onChange })
					end,
					gui = function(e: any): any
						return e.hueHit
					end,
					from = function(_e: any): Vector2
						return Vector2.new(10, 5)
					end,
				},
				{
					make = function(onChange: any): any
						return GradientEditor.new({ value = RGB, host = host, onChange = onChange })
					end,
					gui = function(e: any): any
						return e.handles[2].button
					end,
					from = function(_e: any): Vector2
						return Vector2.new(50, 8)
					end,
				},
				{
					make = function(onChange: any): any
						return SequenceEditor.new({
							value = L(L(0, 0), L(0.5, 0.5), L(1, 0)),
							host = host,
							onChange = onChange,
						})
					end,
					gui = function(e: any): any
						return e.plot
					end,
					from = function(e: any): Vector2
						return e:pointToPixel(0.5, 0.5)
					end,
				},
				{
					make = function(onChange: any): any
						return CurveGraph.new({
							keyframes = { { time = 0, value = 0 }, { time = 1, value = 1 } },
							duration = 1,
							host = host,
							onChange = onChange,
						})
					end,
					gui = function(e: any): any
						return e.plot
					end,
					from = function(e: any): Vector2
						return e:pointToPixel(1, 1)
					end,
				},
			}
			for _, case in cases do
				local log, onChange = recorder()
				local editor = case.make(onChange)
				local from = case.from(editor)
				beginDrag(host, case.gui(editor), from, { from + Vector2.new(10, 10), from + Vector2.new(20, 15) })
				T.expect(#log).toBeGreaterThan(0)
				T.expect(heartbeatCount()).toBe(baseline + 1)
				host.widget.WindowFocusReleased:Fire()
				T.expect(finals(log)).toBe(1)
				T.expect(log[#log][2]).toBe(true)
				T.expect(heartbeatCount()).toBe(baseline)
				editor:destroy()
				T.expect(finals(log)).toBe(1)
			end
		end)
	end)
end
