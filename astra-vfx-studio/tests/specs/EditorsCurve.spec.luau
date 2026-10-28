--!strict
-- Curve value editors (UI/Editors): SequenceEditor (NumberSequence), EasingPicker (EasingDef) and CurveGraph (one
-- number channel track). Every editor is constructed with real Lune instances and driven through its public
-- methods and simulated mouse gestures (widget.mouse + fake InputObjects + ctx.fakes:step). Outputs are checked
-- in their JSON form with Codec.check / Easing.check. Rendering, layout and real mouse input are NOT verified here.
return function(T: any, use: (string) -> any, ctx: any)
	local Theme = use("Plugin.UI.Theme")
	local Kit = use("Plugin.UI.Widgets.ControlKit")
	local SequenceEditor = use("Plugin.UI.Editors.SequenceEditor")
	local EasingPicker = use("Plugin.UI.Editors.EasingPicker")
	local CurveGraph = use("Plugin.UI.Editors.CurveGraph")
	local Easing = use("AstraVFX.Core.Easing")
	local Codec = use("AstraVFX.Core.Codec")
	local Curves = use("AstraVFX.Core.Curves")

	local isLune = ctx.environment == "lune"

	-- helpers ----------------------------------------------------------------------------------------------------

	local function newHost(): any
		local root = Instance.new("Frame")
		root.Name = "Root"
		root.Size = UDim2.fromOffset(800, 600)
		if isLune then
			local widget = ctx.plugin.newWidget("AstraVFX_EditorsCurve")
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

	-- Fake InputObject; `mods` lists held modifiers by Enum.ModifierKey name, e.g. { Alt = true }.
	local function mouseInput(button: Enum.UserInputType?, mods: { [string]: boolean }?): any
		local input: any = {
			UserInputType = button or Enum.UserInputType.MouseButton1,
			UserInputState = Enum.UserInputState.Begin,
			Position = Vector3.new(0, 0, 0),
			KeyCode = nil,
		}
		function input.IsModifierKeyDown(_self: any, key: EnumItem): boolean
			return mods ~= nil and mods[key.Name] == true
		end
		return input
	end

	-- Press at `from`, move through `path` (one Heartbeat each), release (UserInputState = End + Heartbeat).
	local function drag(
		host: any,
		gui: any,
		from: Vector2,
		path: { Vector2 },
		mods: { [string]: boolean }?,
		button: Enum.UserInputType?
	)
		host.widget.mouse = from
		local input = mouseInput(button, mods)
		fire(gui, "InputBegan", input)
		for _, pos in path do
			host.widget.mouse = pos
			ctx.fakes:step(1 / 60)
		end
		input.UserInputState = Enum.UserInputState.End
		ctx.fakes:step(1 / 60)
	end

	-- mixed-type array (the old type solver infers literal arrays from their first element)
	local function tuple(...: any): { any }
		return { ... }
	end

	-- Records onChange(value, final) calls.
	local function recorder(): ({ { any } }, (...any) -> ())
		local log: { { any } } = {}
		return log, function(...: any)
			table.insert(log, { ... })
		end
	end

	local function finals(log: { { any } }): number
		local n = 0
		for _, call in log do
			if call[2] == true then
				n += 1
			end
		end
		return n
	end

	local function expectSequence(value: any, spec: any?)
		local ok, message = Codec.check("numberSequence", value, spec)
		if not ok then
			error("invalid numberSequence: " .. tostring(message), 2)
		end
	end

	local function countVisible(parent: Instance, name: string): number
		local n = 0
		for _, child in parent:GetDescendants() do
			if child.Name == name and child:IsA("GuiObject") and (child :: GuiObject).Visible then
				n += 1
			end
		end
		return n
	end

	-- SequenceEditor -----------------------------------------------------------------------------------------------

	T.describe("SequenceEditor", function()
		T.it("constructs unparented with the canonical value and honours props.parent / enabled", function()
			local editor = SequenceEditor.new({ value = { { 0, 0 }, { 0.5, 1, 0.2 }, { 1, 0 } } })
			T.expect(editor.instance.Parent).toBeNil()
			T.expect(editor.instance.Name).toBe("SequenceEditor")
			T.expect(editor:getValue()).toEqual({ { 0, 0 }, { 0.5, 1, 0.2 }, { 1, 0 } })
			T.expect(editor:getKeypointCount()).toBe(3)
			editor:destroy()

			local parent = Instance.new("Frame")
			local disabled = SequenceEditor.new({ value = 0.5, parent = parent, enabled = false })
			T.expect(disabled.instance.Parent).toBe(parent)
			T.expect(disabled:addKeypoint(0.5, 0.2)).toBeNil()
			T.expect(disabled:getValue()).toBe(0.5)
			disabled:destroy()
			disabled:destroy() -- idempotent
			T.expect(#parent:GetChildren()).toBe(0)
		end)

		T.it("setValue never fires callbacks and accepts numbers, keypoint lists and NumberSequences", function()
			local log, onChange = recorder()
			local editor = SequenceEditor.new({ value = 0, onChange = onChange })
			editor:setValue(0.25)
			T.expect(editor:getValue()).toBe(0.25)
			T.expect(editor:getKeypoints()).toEqual({ { 0, 0.25, 0 }, { 1, 0.25, 0 } })
			editor:setValue({ { 0, 1 }, { 1, 0 } })
			T.expect(editor:getValue()).toEqual({ { 0, 1 }, { 1, 0 } })
			editor:setValue(NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.5),
				NumberSequenceKeypoint.new(0.25, 1, 0.1),
				NumberSequenceKeypoint.new(1, 0),
			}))
			T.expect(#editor:getValue()).toBe(3)
			T.expect(editor:setValue({ { 0.5, 1 } })).toBe(false) -- invalid: state unchanged
			T.expect(#editor:getValue()).toBe(3)
			editor:setValue(4) -- clamped into the default limits 0..1
			T.expect(editor:getValue()).toBe(1)
			T.expect(#log).toBe(0)
			editor:destroy()
		end)

		T.it("adds keypoints in time order up to the engine limit of 20", function()
			local log, onChange = recorder()
			local editor = SequenceEditor.new({ value = { { 0, 0 }, { 1, 1 } }, onChange = onChange })
			local index = editor:addKeypoint(0.5)
			T.expect(index).toBe(2)
			T.expect(editor:getSelected()).toBe(2)
			T.expect(editor:getValue()).toEqual({ { 0, 0 }, { 0.5, 0.5 }, { 1, 1 } }) -- value from the curve
			T.expect(#log).toBe(1)
			T.expect(log[1][2]).toBe(true)
			T.expect(editor:addKeypoint(0.25, 0.9)).toBe(2)
			T.expect(editor:getKeypoints()[2]).toEqual({ 0.25, 0.9, 0 })
			T.expect(editor:addKeypoint(0.2504)).toBeNil() -- closer than MIN_GAP to an existing keypoint
			for i = 1, 30 do
				editor:addKeypoint(0.5 + i * 0.015)
			end
			T.expect(editor:getKeypointCount()).toBe(20)
			T.expect(editor:addKeypoint(0.1)).toBeNil()
			expectSequence(editor:getValue())
			for _, call in log do
				expectSequence(call[1])
			end
			editor:destroy()
		end)

		T.it("keeps the first and last keypoint and at least two keypoints when removing", function()
			local log, onChange = recorder()
			local editor =
				SequenceEditor.new({ value = { { 0, 0 }, { 0.3, 1 }, { 0.6, 0.2 }, { 1, 1 } }, onChange = onChange })
			T.expect(editor:removeKeypoint(1)).toBe(false)
			T.expect(editor:removeKeypoint(4)).toBe(false)
			T.expect(#log).toBe(0)
			editor:selectKeypoint(3)
			T.expect(editor:removeKeypoint(2)).toBe(true)
			T.expect(editor:getSelected()).toBe(2) -- selection follows its keypoint
			T.expect(editor:removeKeypoint(2)).toBe(true)
			T.expect(editor:getSelected()).toBeNil()
			T.expect(editor:getValue()).toEqual({ { 0, 0 }, { 1, 1 } })
			T.expect(editor:removeKeypoint(1)).toBe(false)
			T.expect(#log).toBe(2)
			editor:destroy()
		end)

		T.it("locks the end times and keeps middle times between their neighbours", function()
			local editor = SequenceEditor.new({ value = { { 0, 0 }, { 0.4, 1 }, { 0.6, 0.5 }, { 1, 0 } } })
			editor:setKeypointTime(1, 0.3)
			editor:setKeypointTime(4, 0.7)
			T.expect(editor:getKeypoints()[1][1]).toBe(0)
			T.expect(editor:getKeypoints()[4][1]).toBe(1)
			editor:setKeypointTime(2, 0.9)
			T.expect(editor:getKeypoints()[2][1]).toBeCloseTo(0.6 - SequenceEditor.MIN_GAP, 1e-6)
			editor:setKeypointTime(3, -1)
			T.expect(editor:getKeypoints()[3][1]).toBeCloseTo(0.6, 1e-6) -- no room left: stays
			editor:setKeypointTime(2, 0.25)
			editor:setKeypointTime(3, 0.1)
			T.expect(editor:getKeypoints()[3][1]).toBeCloseTo(0.25 + SequenceEditor.MIN_GAP, 1e-6)
			expectSequence(editor:getValue())
			editor:destroy()
		end)

		T.it("clamps values to the limits and envelopes to 0 .. span", function()
			local spec = { min = 0, max = 10 }
			local editor = SequenceEditor.new({ value = { { 0, 1 }, { 1, 1 } }, min = 0, max = 10 })
			editor:setKeypointValue(1, 25)
			editor:setKeypointValue(2, -3)
			editor:setKeypointEnvelope(1, -1)
			editor:setKeypointEnvelope(2, 40)
			T.expect(editor:getKeypoints()).toEqual({ { 0, 10, 0 }, { 1, 0, 10 } })
			expectSequence(editor:getValue(), spec)
			editor:destroy()
		end)

		T.it("field scrubs report final = false and then one final = true", function()
			local log, onChange = recorder()
			local editor = SequenceEditor.new({ value = { { 0, 0 }, { 1, 1 } }, onChange = onChange })
			editor:selectKeypoint(2)
			editor:setKeypointValue(2, 0.9, false)
			editor:setKeypointValue(2, 0.8, false)
			editor:setKeypointValue(2, 0.8, true)
			T.expect(#log).toBe(3)
			T.expect(log[1][2]).toBe(false)
			T.expect(log[3][2]).toBe(true)
			T.expect(log[3][1]).toEqual({ { 0, 0 }, { 1, 0.8 } })
			-- the numeric fields show the selected keypoint and route edits back
			T.expect(editor.fields.value:getValue()).toBe(0.8)
			editor:destroy()
		end)

		T.itIf(isLune, "drags a keypoint (time + value) as one gesture and clamps it to the view", function()
			local host = newHost()
			local log, onChange = recorder()
			local editor = SequenceEditor.new({
				value = { { 0, 0 }, { 0.5, 0.5 }, { 1, 0 } },
				host = host,
				onChange = onChange,
				parent = host.root,
			})
			local from = editor:pointToPixel(0.5, 0.5)
			local to = editor:pointToPixel(0.7, 0.8)
			drag(host, editor.plot, from, { from + Vector2.new(4, -4), to })
			T.expect(editor:getSelected()).toBe(2)
			T.expect(#log).toBeGreaterThanOrEqual(2)
			T.expect(finals(log)).toBe(1)
			T.expect(log[#log][2]).toBe(true)
			local kp = editor:getKeypoints()[2]
			T.expect(kp[1]).toBeCloseTo(0.7, 1e-3)
			T.expect(kp[2]).toBeCloseTo(0.8, 1e-3)
			for _, call in log do
				expectSequence(call[1], { min = 0, max = 1 })
			end
			-- far beyond the graph: value clamps to 1, time stays below the last keypoint
			local start = editor:pointToPixel(kp[1], kp[2])
			drag(host, editor.plot, start, { start + Vector2.new(500, -500) })
			kp = editor:getKeypoints()[2]
			T.expect(kp[2]).toBe(1)
			T.expect(kp[1]).toBeCloseTo(1 - SequenceEditor.MIN_GAP, 1e-6)
			-- the end keypoints only move vertically
			local last = editor:pointToPixel(1, 0)
			drag(host, editor.plot, last, { last + Vector2.new(-30, -20) })
			T.expect(editor:getKeypoints()[3][1]).toBe(1)
			T.expect(editor:getKeypoints()[3][2]).toBeGreaterThan(0)
			expectSequence(editor:getValue(), { min = 0, max = 1 })
			editor:destroy()
		end)

		T.itIf(isLune, "edits envelopes with Alt-drag and with the envelope handles", function()
			local host = newHost()
			local log, onChange = recorder()
			local editor = SequenceEditor.new({
				value = { { 0, 0.5 }, { 1, 0.5 } },
				host = host,
				onChange = onChange,
				parent = host.root,
			})
			local p = editor:pointToPixel(0, 0.5)
			drag(host, editor.plot, p, { p + Vector2.new(0, -5), p + Vector2.new(0, -20) }, { Alt = true })
			T.expect(finals(log)).toBe(1)
			T.expect(editor:getKeypoints()[1][3]).toBeCloseTo(0.2, 1e-3) -- 20 px of a 100 px plot, span 1
			T.expect(editor:getKeypoints()[1][2]).toBe(0.5) -- value untouched
			expectSequence(editor:getValue())
			-- handle of the selected keypoint (keypoint 1 after the Alt-drag)
			local top, bottom = editor:handlePixels()
			T.expect(top).never.toBeNil()
			T.expect(bottom).never.toBeNil()
			drag(host, editor.plot, bottom :: Vector2, { (bottom :: Vector2) + Vector2.new(0, 10) })
			T.expect(editor:getKeypoints()[1][3]).toBeCloseTo(0.3, 1e-3)
			T.expect(finals(log)).toBe(2)
			-- dragging the handle far down can not make the envelope negative or larger than the span
			top, bottom = editor:handlePixels()
			drag(host, editor.plot, top :: Vector2, { (top :: Vector2) + Vector2.new(0, 400) })
			T.expect(editor:getKeypoints()[1][3]).toBe(0)
			T.expect(editor.band.Visible).toBe(false)
			editor:setKeypointEnvelope(2, 0.25)
			T.expect(editor.band.Visible).toBe(true)
			T.expect(countVisible(editor.band, "Column")).toBe(64)
			editor:destroy()
		end)

		T.itIf(isLune, "double-click on empty space adds a keypoint, right-click removes it", function()
			local host = newHost()
			local log, onChange = recorder()
			local editor = SequenceEditor.new({
				value = { { 0, 0 }, { 1, 1 } },
				host = host,
				onChange = onChange,
				parent = host.root,
			})
			host.widget.mouse = editor:pointToPixel(0.3, 0.6)
			fire(editor.plot, "Activated", mouseInput(), 1) -- single click: nothing
			T.expect(editor:getKeypointCount()).toBe(2)
			fire(editor.plot, "Activated", mouseInput(), 2)
			T.expect(editor:getKeypointCount()).toBe(3)
			local kp = editor:getKeypoints()[2]
			T.expect(kp[1]).toBeCloseTo(0.3, 1e-3)
			T.expect(kp[2]).toBeCloseTo(0.6, 1e-3)
			T.expect(editor:getSelected()).toBe(2)
			-- double-click on an existing keypoint does not add another one
			fire(editor.plot, "Activated", mouseInput(), 2)
			T.expect(editor:getKeypointCount()).toBe(3)
			-- right-click removes it; right-click on an end keypoint does nothing
			fire(editor.plot, "InputBegan", mouseInput(Enum.UserInputType.MouseButton2))
			T.expect(editor:getKeypointCount()).toBe(2)
			host.widget.mouse = editor:pointToPixel(1, 1)
			fire(editor.plot, "InputBegan", mouseInput(Enum.UserInputType.MouseButton2))
			T.expect(editor:getKeypointCount()).toBe(2)
			T.expect(#log).toBe(2)
			T.expect(finals(log)).toBe(2)
			editor:destroy()
		end)

		T.itIf(isLune, "a click on empty space deselects", function()
			local host = newHost()
			local editor = SequenceEditor.new({ value = { { 0, 0 }, { 1, 1 } }, host = host, parent = host.root })
			local selections: { any } = {}
			editor._props.onSelect = function(index: number?)
				table.insert(selections, if index then tostring(index) else "none")
			end
			drag(host, editor.plot, editor:pointToPixel(1, 1), {})
			T.expect(editor:getSelected()).toBe(2)
			drag(host, editor.plot, editor:pointToPixel(0.5, 0.1), {})
			T.expect(editor:getSelected()).toBeNil()
			T.expect(selections).toEqual({ "2", "none" })
			editor:destroy()
		end)

		T.it("presets produce valid sequences between presetLow and presetHigh", function()
			local log, onChange = recorder()
			local editor = SequenceEditor.new({ value = 0, presetLow = 1, presetHigh = 0, onChange = onChange })
			for _, preset in SequenceEditor.PRESETS do
				T.expect(editor:applyPreset(preset.value)).toBe(true)
				expectSequence(editor:getValue(), { min = 0, max = 1 })
			end
			-- "constant" (presetHigh = 0) equals the start value 0: an edit that changes nothing reports nothing
			T.expect(#log).toBe(#SequenceEditor.PRESETS - 1)
			T.expect(finals(log)).toBe(#SequenceEditor.PRESETS - 1)
			editor:applyPreset("constant")
			T.expect(editor:getValue()).toBe(0) -- plain number when constant
			editor:applyPreset("fadeInOut")
			T.expect(editor:getValue()).toEqual({ { 0, 1 }, { 0.2, 0 }, { 0.8, 0 }, { 1, 1 } })
			editor:applyPreset("easeOut")
			local baked = editor:getValue()
			T.expect(#baked).toBeGreaterThan(2)
			T.expect(#baked).toBeLessThanOrEqual(20)
			local seq = Codec.decode("numberSequence", baked)
			-- Quad.Out from 0 to 1: 0.75 at t = 0.5
			T.expect(Curves.evaluateNumberSequence(seq, 0.5)).toBeCloseTo(0.75, 0.005)
			T.expect(editor:applyPreset("nope")).toBe(false)
			-- the preset dropdown applies its choice and returns to the placeholder
			editor.presets:choose("linearIn")
			T.expect(editor:getValue()).toEqual({ { 0, 1 }, { 1, 0 } })
			T.expect(editor.presets:getValue()).toBeNil()
			editor:destroy()
		end)

		T.it("smoothing bakes a monotone curve through the keypoints into <= 20 linear keypoints", function()
			local log, onChange = recorder()
			local original = { { 0, 0 }, { 0.25, 1, 0.1 }, { 0.6, 0.3 }, { 1, 0.9 } }
			local editor = SequenceEditor.new({ value = original, onChange = onChange })
			local maxError = editor:smooth()
			T.expect(maxError).never.toBeNil()
			T.expect(maxError :: number).toBeLessThan(0.02) -- 20-keypoint budget on a curve with two sharp turns
			local value = editor:getValue()
			expectSequence(value, { min = 0, max = 1 })
			T.expect(#value).toBeGreaterThan(4)
			T.expect(#value).toBeLessThanOrEqual(20)
			T.expect(#log).toBe(1)
			T.expect(log[1][2]).toBe(true)
			local seq = Codec.decode("numberSequence", value)
			for _, kp in original do
				T.expect(Curves.evaluateNumberSequence(seq, kp[1])).toBeCloseTo(kp[2], 0.02)
			end
			-- monotone cubic: no overshoot above the peak or below 0
			for i = 0, 100 do
				local v = Curves.evaluateNumberSequence(seq, i / 100)
				T.expect(v).toBeLessThanOrEqual(1)
				T.expect(v).toBeGreaterThanOrEqual(0)
			end
			-- the envelope is smoothed too and never negative
			T.expect(Curves.evaluateNumberSequenceEnvelope(seq, 0.25)).toBeCloseTo(0.1, 0.01)
			-- static helper with an explicit spec
			local smoothed = SequenceEditor.smoothKeypoints({ { 0, 2 }, { 0.5, 8 }, { 1, 2 } }, { min = 0, max = 10 })
			expectSequence(smoothed, { min = 0, max = 10 })
			editor:destroy()
		end)

		T.it("auto range grows the view (up to max) to fit the data and shrinks back", function()
			local editor = SequenceEditor.new({ value = 0.5, min = 0, max = 10, range = { 0, 1 } })
			local lo, hi = editor:getRange()
			T.expect(lo).toBe(0)
			T.expect(hi).toBe(1)
			editor:setValue(3)
			lo, hi = editor:getRange()
			T.expect(hi).toBeGreaterThanOrEqual(3)
			T.expect(hi).toBeLessThanOrEqual(10)
			editor:setValue({ { 0, 0.2 }, { 1, 0.4 } })
			lo, hi = editor:getRange()
			T.expect(hi).toBe(1)
			editor:setKeypointValue(1, 50)
			lo, hi = editor:getRange()
			T.expect(hi).toBe(10)
			T.expect(editor:getKeypoints()[1][2]).toBe(10)
			editor:destroy()

			-- without a narrower range the view is the limits and never changes
			local fixed = SequenceEditor.new({ value = 0.5 })
			fixed:setValue(1)
			lo, hi = fixed:getRange()
			T.expect(lo).toBe(0)
			T.expect(hi).toBe(1)
			fixed:destroy()
		end)

		T.itIf(isLune, "releasing a drag at the top of an auto range expands the view", function()
			local host = newHost()
			local editor = SequenceEditor.new({
				value = 0.5,
				min = 0,
				max = 10,
				range = { 0, 1 },
				host = host,
				parent = host.root,
			})
			local p = editor:pointToPixel(0, 0.5)
			drag(host, editor.plot, p, { p + Vector2.new(0, -200) })
			T.expect(editor:getKeypoints()[1][2]).toBe(1)
			local _, hi = editor:getRange()
			T.expect(hi).toBeGreaterThan(1)
			editor:destroy()
		end)

		T.itIf(isLune, "draws the curve through the keypoints and one dot per keypoint", function()
			local editor = SequenceEditor.new({ value = { { 0, 0 }, { 0.5, 1 }, { 0.75, 0.5 }, { 1, 0 } } })
			T.expect(countVisible(editor.curve, "Segment")).toBe(3)
			T.expect(countVisible(editor.pointsLayer, "Point")).toBe(4)
			editor:setValue(0.5)
			T.expect(countVisible(editor.curve, "Segment")).toBe(1)
			T.expect(countVisible(editor.pointsLayer, "Point")).toBe(2)
			T.expect(editor.countLabel.Text).toBe("2/20")
			editor:destroy()
		end)

		T.itIf(isLune, "destroy during a drag ends the gesture with final = true and drops the Heartbeat", function()
			local host = newHost()
			local log, onChange = recorder()
			local editor = SequenceEditor.new({ value = { { 0, 0 }, { 1, 1 } }, host = host, onChange = onChange })
			local before = ctx.fakes.heartbeat:connectionCount()
			local p = editor:pointToPixel(0, 0)
			host.widget.mouse = p
			fire(editor.plot, "InputBegan", mouseInput())
			host.widget.mouse = p + Vector2.new(0, -30)
			ctx.fakes:step(1 / 60)
			T.expect(editor:isDragging()).toBe(true)
			T.expect(#log).toBe(1)
			editor:destroy()
			T.expect(ctx.fakes.heartbeat:connectionCount()).toBe(before)
			T.expect(#log).toBe(2)
			T.expect(log[2][2]).toBe(true)
			expectSequence(log[2][1])
		end)
	end)

	-- EasingPicker -------------------------------------------------------------------------------------------------

	T.describe("EasingPicker", function()
		local function expectEasing(value: any)
			local ok, message = Easing.check(value)
			if not ok then
				error("invalid easing: " .. tostring(message), 2)
			end
		end

		T.it("constructs a compact button with the name and a thumbnail of the current easing", function()
			local picker = EasingPicker.new({ value = "Quad" })
			T.expect(picker.instance.Parent).toBeNil()
			T.expect(picker.instance.Name).toBe("EasingPicker")
			T.expect(picker:getValue()).toBe("Quad.Out") -- explicit direction
			T.expect(picker.label.Text).toBe("Quad.Out")
			T.expect(countVisible(picker.thumbCurve, "Segment")).toBe(16)
			picker:destroy()
			local parent = Instance.new("Frame")
			local disabled =
				EasingPicker.new({ value = { bezier = { 0.42, 0, 0.58, 1 } }, parent = parent, enabled = false })
			T.expect(disabled.instance.Parent).toBe(parent)
			T.expect(disabled.label.Text).toBe("ease-in-out")
			T.expect(disabled:choose("Linear")).toBe(false)
			disabled:open()
			T.expect(disabled:isOpen()).toBe(false)
			disabled:destroy()
			disabled:destroy()
			T.expect(#parent:GetChildren()).toBe(0)
		end)

		T.it("names definitions and normalises them to the explicit JSON form", function()
			T.expect(EasingPicker.explicit(nil)).toBe("Linear")
			T.expect(EasingPicker.explicit("Linear.In")).toBe("Linear")
			T.expect(EasingPicker.explicit("Constant")).toBe("Constant")
			T.expect(EasingPicker.explicit("Elastic.InOut")).toBe("Elastic.InOut")
			T.expect(EasingPicker.explicit("Bounce")).toBe("Bounce.Out")
			T.expect(EasingPicker.explicit("quad")).toBeNil()
			T.expect(EasingPicker.explicit({ bezier = { 2, 0, 1, 1 } })).toBeNil()
			T.expect(EasingPicker.label({ bezier = { 0.25, 0.1, 0.25, 1 } })).toBe("ease")
			T.expect(EasingPicker.label({ bezier = { 0.1, 0.2, 0.3, 1.5 } })).toBe("Bezier 0.1, 0.2, 0.3, 1.5")
		end)

		T.it("setValue never fires callbacks and ignores invalid definitions", function()
			local log, onChange = recorder()
			local picker = EasingPicker.new({ value = "Linear", onChange = onChange })
			T.expect(picker:setValue("Back.In")).toBe(true)
			T.expect(picker:getValue()).toBe("Back.In")
			T.expect(picker:setValue("Spring")).toBe(false)
			T.expect(picker:getValue()).toBe("Back.In")
			picker:setValue({ bezier = { 0, 0, 0.58, 1 } })
			T.expect(picker:getValue()).toEqual({ bezier = { 0, 0, 0.58, 1 } })
			T.expect(picker:getMode()).toBe("bezier")
			T.expect(#log).toBe(0)
			picker:destroy()
		end)

		T.itIf(isLune, "opens a style × direction grid in host.root; a choice reports it and closes", function()
			local host = newHost()
			local log, onChange = recorder()
			local picker = EasingPicker.new({ value = "Linear", host = host, onChange = onChange, parent = host.root })
			fire(picker.instance, "Activated", mouseInput(), 1)
			T.expect(picker:isOpen()).toBe(true)
			T.expect(picker.popup).never.toBeNil()
			T.expect((picker.popup :: any).Parent).toBe(host.root)
			local count = 0
			for _ in picker.cells do
				count += 1
			end
			T.expect(count).toBe(2 + 10 * 3) -- Linear, Constant + 10 styles × In/Out/InOut
			for _, style in Easing.STYLES do
				if style ~= "Linear" and style ~= "Constant" then
					for _, direction in Easing.DIRECTIONS do
						local cell = picker.cells[style .. "." .. direction]
						T.expect(cell).never.toBeNil()
						T.expect(countVisible(cell, "Segment")).toBeGreaterThan(10)
					end
				end
			end
			T.expect(picker.cells.Linear.BackgroundColor3).toEqual(Theme.colors.accentDim) -- current value
			fire(picker.cells["Elastic.InOut"], "Activated", mouseInput(), 1)
			T.expect(picker:isOpen()).toBe(false)
			T.expect(picker:getValue()).toBe("Elastic.InOut")
			T.expect(log).toEqual({ tuple("Elastic.InOut", true) })
			T.expect(picker.label.Text).toBe("Elastic.InOut")
			-- the same choice again changes nothing
			picker:choose("Elastic.InOut")
			T.expect(#log).toBe(1)
			-- every popup instance is gone again
			T.expect(host.root:FindFirstChild("AstraEasingPopup")).toBeNil()
			T.expect(host.root:FindFirstChild("AstraEasingOverlay")).toBeNil()
			picker:destroy()
		end)

		T.itIf(isLune, "closes the popup on outside clicks, focus loss, setEnabled(false) and destroy", function()
			local host = newHost()
			local picker = EasingPicker.new({ value = "Sine.In", host = host, parent = host.root })
			picker:open()
			fire(picker.overlay, "Activated", mouseInput(), 1)
			T.expect(picker:isOpen()).toBe(false)
			picker:open()
			fire(picker.overlay, "InputBegan", mouseInput(Enum.UserInputType.MouseButton2))
			T.expect(picker:isOpen()).toBe(false)
			picker:open()
			host.widget.WindowFocusReleased:Fire()
			T.expect(picker:isOpen()).toBe(false)
			picker:open()
			picker:setEnabled(false)
			T.expect(picker:isOpen()).toBe(false)
			picker:setEnabled(true)
			picker:open()
			picker:destroy()
			T.expect(host.root:FindFirstChild("AstraEasingPopup")).toBeNil()
			T.expect(host.root:FindFirstChild("AstraEasingOverlay")).toBeNil()
		end)

		T.itIf(isLune, "bezier fields and CSS presets report valid bezier definitions", function()
			local host = newHost()
			local log, onChange = recorder()
			local picker =
				EasingPicker.new({ value = "Quad.Out", host = host, onChange = onChange, parent = host.root })
			picker:open()
			T.expect(picker:getMode()).toBe("styles")
			picker:setMode("bezier")
			T.expect((picker.bezierPage :: any).Visible).toBe(true)
			T.expect((picker.stylesPage :: any).Visible).toBe(false)
			T.expect(#log).toBe(0) -- switching modes does not change the value
			T.expect(#picker.bezierInputs).toBe(4)
			-- typing into x1 (clamped to 0..1 by the field)
			local x1 = picker.bezierInputs[1]
			x1.box.Text = "1.7"
			fire(x1.box, "FocusLost", false, nil)
			T.expect(#log).toBe(1)
			T.expect(log[1][1]).toEqual({ bezier = { 1, 0.1, 0.25, 1 } })
			T.expect(log[1][2]).toBe(true)
			expectEasing(log[1][1])
			T.expect(picker:isOpen()).toBe(true) -- bezier edits keep the popup open
			T.expect(picker:applyPreset("ease-out")).toBe(true)
			T.expect(picker:getValue()).toEqual({ bezier = { 0, 0, 0.58, 1 } })
			T.expect(picker.label.Text).toBe("ease-out")
			fire(picker.presetButtons["ease-in"].instance, "Activated", mouseInput(), 1)
			T.expect(picker:getValue()).toEqual({ bezier = { 0.42, 0, 1, 1 } })
			T.expect(picker:applyPreset("nope")).toBe(false)
			-- programmatic edits clamp x to 0..1 and y to -2..3
			picker:setBezier(-1, 9, 0.5, -9)
			T.expect(picker:getValue()).toEqual({ bezier = { 0, 3, 0.5, -2 } })
			for _, call in log do
				expectEasing(call[1])
			end
			-- the returned tables are copies
			local value = picker:getValue()
			value.bezier[1] = 0.9
			T.expect(picker:getValue().bezier[1]).toBe(0)
			picker:destroy()
		end)

		T.itIf(isLune, "dragging a bezier handle is one gesture with valid intermediate values", function()
			local host = newHost()
			local log, onChange = recorder()
			local picker = EasingPicker.new({
				value = { bezier = { 0.25, 0.1, 0.25, 1 } },
				host = host,
				onChange = onChange,
				parent = host.root,
			})
			picker:open()
			T.expect(picker:getMode()).toBe("bezier")
			local from = picker:handlePixel(1)
			local to = picker:previewPointToPixel(0.6, 1.2)
			drag(host, picker.preview, from, { from + Vector2.new(5, 0), to })
			T.expect(#log).toBeGreaterThanOrEqual(2)
			T.expect(finals(log)).toBe(1)
			T.expect(log[#log][2]).toBe(true)
			local b = picker:getValue().bezier
			T.expect(b[1]).toBeCloseTo(0.6, 0.01)
			T.expect(b[2]).toBeCloseTo(1.2, 0.01)
			T.expect(b[3]).toBe(0.25)
			T.expect(b[4]).toBe(1)
			for _, call in log do
				expectEasing(call[1])
			end
			-- handle 2 dragged beyond the preview: x clamps to 1
			local from2 = picker:handlePixel(2)
			drag(host, picker.preview, from2, { from2 + Vector2.new(400, 0) })
			T.expect(picker:getValue().bezier[3]).toBe(1)
			T.expect(finals(log)).toBe(2)
			-- a press away from both handles does nothing
			local before = #log
			local empty = picker:previewPointToPixel(0.9, -0.4)
			drag(host, picker.preview, empty, { empty + Vector2.new(-20, -20) })
			T.expect(#log).toBe(before)
			T.expect(picker.label.Text).toMatch("^Bezier")
			picker:destroy()
		end)

		T.itIf(isLune, "closing during a handle drag ends the gesture with final = true", function()
			local host = newHost()
			local log, onChange = recorder()
			local picker = EasingPicker.new({
				value = { bezier = { 0.25, 0.1, 0.25, 1 } },
				host = host,
				onChange = onChange,
				parent = host.root,
			})
			picker:open()
			local before = ctx.fakes.heartbeat:connectionCount()
			local from = picker:handlePixel(1)
			host.widget.mouse = from
			fire(picker.preview, "InputBegan", mouseInput())
			host.widget.mouse = from + Vector2.new(20, -20)
			ctx.fakes:step(1 / 60)
			T.expect(picker:isDragging()).toBe(true)
			T.expect(log[#log][2]).toBe(false)
			picker:destroy()
			T.expect(log[#log][2]).toBe(true)
			T.expect(finals(log)).toBe(1)
			T.expect(ctx.fakes.heartbeat:connectionCount()).toBe(before)
		end)
	end)

	-- CurveGraph ---------------------------------------------------------------------------------------------------

	T.describe("CurveGraph", function()
		local function keyframes(): { any }
			return {
				{ time = 0, value = 0, easing = "Quad.Out" },
				{ time = 1, value = 1 },
				{ time = 2, value = 0.5, easing = "Constant" },
			}
		end

		-- every reported keyframe list is sorted, inside 0..duration and valid JSON
		local function expectKeyframes(list: { any }, duration: number?, spec: any?)
			local previous = -math.huge
			for i, kf in list do
				if type(kf.time) ~= "number" or kf.time < previous then
					error("keyframe " .. i .. " is out of order", 2)
				end
				if kf.time < 0 or (duration ~= nil and kf.time > duration) then
					error("keyframe " .. i .. " time " .. tostring(kf.time) .. " is outside the duration", 2)
				end
				previous = kf.time
				local ok, message = Codec.check("number", kf.value, spec)
				if not ok then
					error("keyframe " .. i .. ": " .. tostring(message), 2)
				end
				local okEasing, easingMessage = Easing.check(kf.easing)
				if not okEasing then
					error("keyframe " .. i .. ": " .. tostring(easingMessage), 2)
				end
			end
		end

		local function wheelInput(z: number, mods: { [string]: boolean }?): any
			local input = mouseInput(Enum.UserInputType.MouseWheel, mods)
			input.Position = Vector3.new(0, 0, z)
			return input
		end

		local function newGraph(host: any, extra: { [string]: any }?): (any, { { any } }, { { number } })
			local log, onChange = recorder()
			local selections: { { number } } = {}
			local props: { [string]: any } = {
				keyframes = keyframes(),
				duration = 2,
				host = host,
				onChange = onChange,
				onSelect = function(indices: { number })
					table.insert(selections, indices)
				end,
				parent = host.root,
			}
			local overrides: { [string]: any } = extra or {}
			for k, v in overrides do
				props[k] = v
			end
			return CurveGraph.new(props), log, selections
		end

		local function keyPixel(graph: any, index: number): Vector2
			local kf = graph:getKeyframes()[index]
			return graph:pointToPixel(kf.time, kf.value)
		end

		T.it("constructs, frames the duration and the data, and evaluates the compiled track", function()
			local graph = CurveGraph.new({ keyframes = keyframes(), duration = 2 })
			T.expect(graph.instance.Parent).toBeNil()
			T.expect(graph.instance.Name).toBe("CurveGraph")
			local view = graph:getView()
			T.expect(view.t0).toBeLessThan(0)
			T.expect(view.t1).toBeGreaterThan(2)
			T.expect(view.v0).toBeLessThan(0)
			T.expect(view.v1).toBeGreaterThan(1)
			T.expect(graph:evaluate(0.5)).toBeCloseTo(0.75, 1e-9) -- Quad.Out from 0 to 1
			T.expect(graph:evaluate(1.5)).toBeCloseTo(0.75, 1e-9) -- Linear from 1 to 0.5
			T.expect(graph:evaluate(3)).toBe(0.5)
			graph:destroy()

			local fixed = CurveGraph.new({ keyframes = keyframes(), minValue = -2, maxValue = 3 })
			T.expect(fixed:getView().v0).toBe(-2)
			T.expect(fixed:getView().v1).toBe(3)
			T.expect(fixed:getView().t1).toBeGreaterThan(2) -- no duration: frames the last key
			fixed:destroy()

			local empty = CurveGraph.new({})
			T.expect(empty:evaluate(0)).toBeNil()
			T.expect(empty:getKeyframes()).toEqual({})
			empty:destroy()
		end)

		T.it("auto range includes easing overshoot", function()
			local graph = CurveGraph.new({
				keyframes = tuple({ time = 0, value = 0, easing = "Back.Out" }, { time = 1, value = 1 }),
			})
			T.expect(graph:getView().v1).toBeGreaterThan(1.1) -- Back.Out peaks at ~1.1
			graph:destroy()
		end)

		T.itIf(isLune, "draws clipped curve segments, one diamond per visible key and grid labels", function()
			local graph = CurveGraph.new({ keyframes = keyframes(), duration = 2 })
			T.expect(countVisible(graph.curveLayer, "Segment")).toBeGreaterThan(20)
			T.expect(countVisible(graph.keyLayer, "Key")).toBe(3)
			T.expect(countVisible(graph.timeAxis, "Label")).toBeGreaterThan(0)
			T.expect(countVisible(graph.valueAxis, "Label")).toBeGreaterThan(0)
			-- zoomed far into the middle of the first segment: keys leave the view, segments stay inside the plot
			graph:setView(0.49, 0.51, 0.7, 0.8)
			T.expect(countVisible(graph.keyLayer, "Key")).toBe(0)
			for _, seg in graph.curveLayer:GetChildren() do
				local frame = seg :: Frame
				if frame.Visible then
					T.expect(frame.Size.X.Offset).toBeLessThan(200) -- clipped to the 100 px plot (+ margin)
				end
			end
			graph:destroy()
		end)

		T.it("setKeyframes never fires callbacks, sorts and keeps extra fields", function()
			local log, onChange = recorder()
			local graph = CurveGraph.new({ keyframes = {}, onChange = onChange })
			graph:setKeyframes({
				{ time = 1, value = 2, id = "b" },
				{ time = 0, value = 1, easing = { bezier = { 0.1, 0.2, 0.3, 0.4 } }, id = "a" },
			})
			local list = graph:getKeyframes()
			T.expect(list[1].id).toBe("a")
			T.expect(list[2].id).toBe("b")
			T.expect(list[1].easing).toEqual({ bezier = { 0.1, 0.2, 0.3, 0.4 } })
			list[1].easing.bezier[1] = 0.9 -- copies
			T.expect(graph:getKeyframes()[1].easing.bezier[1]).toBe(0.1)
			T.expect(#log).toBe(0)
			graph:destroy()
		end)

		T.it("follows undo / redo back to the last reported keyframes", function()
			local log, onChange = recorder()
			local graph = CurveGraph.new({ keyframes = keyframes(), duration = 2, onChange = onChange })
			graph:select({ 2 })
			graph:moveSelected(0.25, 0)
			local edited = log[#log][1]
			graph:setKeyframes(keyframes()) -- undo
			T.expect(graph:getKeyframes()).toEqual(keyframes())
			graph:setKeyframes(edited) -- redo
			T.expect(graph:getKeyframes()).toEqual(edited)
			T.expect(graph:getSelection()).toEqual({ 2 }) -- kept by index
			T.expect(#log).toBe(1)
			graph:destroy()
		end)

		T.it("selects by index with replace / add / toggle / remove and reports changes", function()
			local selections: { { number } } = {}
			local graph = CurveGraph.new({
				keyframes = keyframes(),
				onSelect = function(indices: { number })
					table.insert(selections, indices)
				end,
			})
			graph:select({ 2 })
			graph:select({ 3 }, "add")
			graph:select({ 2 }, "toggle")
			graph:select({ 3 }, "add") -- no change: not reported
			graph:select({ 1, 3 }, "toggle")
			graph:select({ 1 }, "remove")
			T.expect(selections).toEqual({ { 2 }, { 2, 3 }, { 3 }, { 1 }, {} })
			T.expect(graph:getSelection()).toEqual({})
			graph:destroy()
		end)

		T.itIf(isLune, "dragging a key moves time and value as one gesture", function()
			local host = newHost()
			local graph, log, selections = newGraph(host)
			local from = keyPixel(graph, 2)
			local to = graph:pointToPixel(1.4, 0.8)
			drag(host, graph.plot, from, { from + Vector2.new(3, 0), to })
			T.expect(selections[1]).toEqual({ 2 })
			T.expect(#log).toBeGreaterThanOrEqual(2)
			T.expect(finals(log)).toBe(1)
			T.expect(log[#log][2]).toBe(true)
			local kf = graph:getKeyframes()[2]
			T.expect(kf.time).toBeCloseTo(1.4, 0.01)
			T.expect(kf.value).toBeCloseTo(0.8, 0.01)
			for _, call in log do
				expectKeyframes(call[1], 2)
			end
			graph:destroy()
		end)

		T.itIf(isLune, "re-sorts keys that cross each other and reports the new indices", function()
			local host = newHost()
			local graph, log, selections = newGraph(host)
			local from = keyPixel(graph, 1)
			drag(host, graph.plot, from, { from + Vector2.new(4, 0), graph:pointToPixel(1.5, 0) })
			local list = graph:getKeyframes()
			T.expect(list[1].time).toBe(1)
			T.expect(list[2].time).toBeCloseTo(1.5, 0.01)
			T.expect(list[2].easing).toBe("Quad.Out") -- the key keeps its easing
			T.expect(graph:getSelection()).toEqual({ 2 })
			T.expect(selections[#selections]).toEqual({ 2 })
			for _, call in log do
				expectKeyframes(call[1], 2)
			end
			graph:destroy()
		end)

		T.itIf(isLune, "multi-selection drags all selected keys, snapped and clamped to 0..duration", function()
			local host = newHost()
			local graph, log = newGraph(host, {
				snap = function(t: number): number
					return math.round(t * 4) / 4
				end,
			})
			drag(host, graph.plot, keyPixel(graph, 1), {})
			drag(host, graph.plot, keyPixel(graph, 2), {}, { Shift = true })
			T.expect(graph:getSelection()).toEqual({ 1, 2 })
			local from = keyPixel(graph, 2)
			drag(host, graph.plot, from, { from + Vector2.new(4, 0), graph:pointToPixel(1.3, 1) })
			local list = graph:getKeyframes()
			T.expect(list[1].time).toBe(0.25) -- moved by the snapped offset of the grabbed key (1 -> 1.25)
			T.expect(list[2].time).toBe(1.25)
			T.expect(list[3].time).toBe(2) -- not selected
			T.expect(finals(log)).toBe(1)
			-- far to the left: the earliest selected key stops at 0, the others keep their distance
			from = keyPixel(graph, 2)
			drag(host, graph.plot, from, { from + Vector2.new(-400, 0) })
			list = graph:getKeyframes()
			T.expect(list[1].time).toBe(0)
			T.expect(list[2].time).toBe(1)
			-- far to the right: the latest selected key stops at the duration
			graph:select({ 2, 3 })
			from = keyPixel(graph, 3)
			drag(host, graph.plot, from, { from + Vector2.new(400, 0) })
			list = graph:getKeyframes()
			T.expect(list[3].time).toBe(2)
			T.expect(list[2].time).toBe(1)
			for _, call in log do
				expectKeyframes(call[1], 2)
			end
			-- a click on one key of the multi-selection reduces the selection to it
			drag(host, graph.plot, keyPixel(graph, 3), {})
			T.expect(graph:getSelection()).toEqual({ 3 })
			-- Ctrl toggles
			drag(host, graph.plot, keyPixel(graph, 1), {}, { Ctrl = true })
			T.expect(graph:getSelection()).toEqual({ 1, 3 })
			drag(host, graph.plot, keyPixel(graph, 3), {}, { Ctrl = true })
			T.expect(graph:getSelection()).toEqual({ 1 })
			-- a click on empty space clears
			drag(host, graph.plot, graph:pointToPixel(0.5, -0.1), {})
			T.expect(graph:getSelection()).toEqual({})
			graph:destroy()
		end)

		T.itIf(isLune, "values respect the channel limits", function()
			local host = newHost()
			local graph, log = newGraph(host, { min = 0, max = 1 })
			local from = keyPixel(graph, 2)
			drag(host, graph.plot, from, { from + Vector2.new(0, -500) })
			T.expect(graph:getKeyframes()[2].value).toBe(1)
			from = keyPixel(graph, 2)
			drag(host, graph.plot, from, { from + Vector2.new(0, 900) })
			T.expect(graph:getKeyframes()[2].value).toBe(0)
			for _, call in log do
				expectKeyframes(call[1], 2, { min = 0, max = 1 })
			end
			graph:destroy()
		end)

		T.itIf(isLune, "box selection on empty space selects the keys inside", function()
			local host = newHost()
			local graph, _, selections = newGraph(host)
			local from = graph:pointToPixel(0.5, 1.2)
			drag(host, graph.plot, from, { from + Vector2.new(3, 3), graph:pointToPixel(2.05, 0.3) })
			T.expect(graph:getSelection()).toEqual({ 2, 3 })
			T.expect(selections[#selections]).toEqual({ 2, 3 })
			T.expect(graph.boxRect.Visible).toBe(false) -- hidden again after the gesture
			-- with Shift the box adds to the selection
			graph:select({ 1 })
			drag(host, graph.plot, from, { from + Vector2.new(3, 3), graph:pointToPixel(1.2, 0.8) }, { Shift = true })
			T.expect(graph:getSelection()).toEqual({ 1, 2 })
			graph:destroy()
		end)

		T.itIf(isLune, "bezier handles of selected segments edit the easing", function()
			local host = newHost()
			local graph, log = newGraph(host)
			T.expect(graph:setEasing(1, { bezier = { 0.25, 0.1, 0.25, 1 } })).toBe(true)
			T.expect(graph:setEasing(1, "Spring")).toBe(false)
			T.expect(finals(log)).toBe(1)
			T.expect(graph:handlePixel(1, 1)).never.toBeNil()
			T.expect(countVisible(graph.handleLayer, "Handle")).toBe(0) -- only for selected segments
			graph:select({ 2 })
			T.expect(countVisible(graph.handleLayer, "Handle")).toBe(2)
			local t, v = graph:handlePoint(1, 1)
			T.expect(t).toBeCloseTo(0.25, 1e-9)
			T.expect(v).toBeCloseTo(0.1, 1e-9)
			local from = graph:handlePixel(1, 1) :: Vector2
			drag(host, graph.plot, from, { from + Vector2.new(3, 0), graph:pointToPixel(0.6, 1.3) })
			local easing = graph:getKeyframes()[1].easing
			T.expect(easing.bezier[1]).toBeCloseTo(0.6, 0.02)
			T.expect(easing.bezier[2]).toBeCloseTo(1.3, 0.02)
			T.expect(easing.bezier[3]).toBe(0.25)
			T.expect(finals(log)).toBe(2)
			-- x is clamped into the segment
			from = graph:handlePixel(1, 2) :: Vector2
			drag(host, graph.plot, from, { from + Vector2.new(3, 0), graph:pointToPixel(1.8, 1) })
			T.expect(graph:getKeyframes()[1].easing.bezier[3]).toBe(1)
			for _, call in log do
				expectKeyframes(call[1], 2)
			end
			T.expect(graph:getKeyframes()[2].time).toBe(1) -- the keys did not move
			graph:destroy()
		end)

		T.itIf(isLune, "wheel zooms around the mouse, Ctrl+wheel zooms values, middle-drag pans", function()
			local host = newHost()
			local graph = newGraph(host)
			local view = graph:getView()
			local anchor = graph:pointToPixel(1, 0.5)
			host.widget.mouse = anchor
			fire(graph.plot, "InputChanged", wheelInput(1))
			local zoomed = graph:getView()
			T.expect(zoomed.t1 - zoomed.t0).toBeCloseTo((view.t1 - view.t0) / 1.2, 1e-9)
			local t = graph:pixelToPoint(anchor)
			T.expect(t).toBeCloseTo(1, 1e-9) -- the time under the mouse stays put
			T.expect(zoomed.v0).toBe(view.v0)
			fire(graph.plot, "InputChanged", wheelInput(-1))
			T.expect(graph:getView().t1 - graph:getView().t0).toBeCloseTo(view.t1 - view.t0, 1e-9)
			fire(graph.plot, "InputChanged", wheelInput(1, { Ctrl = true }))
			local valueZoom = graph:getView()
			T.expect(valueZoom.v1 - valueZoom.v0).toBeCloseTo((view.v1 - view.v0) / 1.2, 1e-9)
			fire(graph.plot, "InputChanged", wheelInput(1, { Shift = true }))
			T.expect(graph:getView().t0).toBeLessThan(valueZoom.t0) -- scrolled
			-- middle-drag pans both axes; keys are not edited
			local before = graph:getView()
			local from = graph:pointToPixel(1, 0.5)
			drag(
				host,
				graph.plot,
				from,
				{ from + Vector2.new(10, 0), from + Vector2.new(20, 10) },
				nil,
				Enum.UserInputType.MouseButton3
			)
			local after = graph:getView()
			T.expect(after.t0).toBeLessThan(before.t0)
			T.expect(after.v0).toBeGreaterThan(before.v0)
			T.expect(after.t1 - after.t0).toBeCloseTo(before.t1 - before.t0, 1e-9)
			T.expect(graph:getKeyframes()).toEqual(keyframes())
			graph:frameAll()
			T.expect(graph:getView().t0).toBeCloseTo(view.t0, 1e-9)
			graph:destroy()
		end)

		T.it("programmatic moves, easing changes and deletion report keyframes", function()
			local log, onChange = recorder()
			local selections: { { number } } = {}
			local graph = CurveGraph.new({
				keyframes = keyframes(),
				duration = 2,
				onChange = onChange,
				onSelect = function(indices: { number })
					table.insert(selections, indices)
				end,
			})
			graph:select({ 1 })
			graph:moveSelected(1.5, 0.25, false) -- relative to the current position
			graph:moveSelected(0, 0, true) -- closes the gesture
			T.expect(#log).toBe(2)
			T.expect(log[1][2]).toBe(false)
			T.expect(log[2][2]).toBe(true)
			local list = graph:getKeyframes()
			T.expect(list[2].time).toBe(1.5)
			T.expect(list[2].value).toBe(0.25)
			T.expect(graph:getSelection()).toEqual({ 2 })
			T.expect(graph:deleteSelected()).toBe(1)
			T.expect(#graph:getKeyframes()).toBe(2)
			T.expect(graph:getSelection()).toEqual({})
			T.expect(selections[#selections]).toEqual({})
			T.expect(graph:deleteSelected()).toBe(0)
			for _, call in log do
				expectKeyframes(call[1], 2)
			end
			graph:destroy()
		end)

		T.itIf(isLune, "the document echoing an edit during a drag does not disturb the gesture", function()
			local host = newHost()
			local graph: any
			local log: { { any } } = {}
			graph = CurveGraph.new({
				keyframes = keyframes(),
				duration = 2,
				host = host,
				parent = host.root,
				onChange = function(list: { any }, final: boolean)
					table.insert(log, tuple(list, final))
					-- the document stores the keys and hands them back as new tables
					local copy = {}
					for i, kf in list do
						copy[i] = table.clone(kf)
					end
					graph:setKeyframes(copy)
				end,
			})
			local view = graph:getView()
			local from = keyPixel(graph, 2)
			drag(host, graph.plot, from, { from + Vector2.new(5, 0), from + Vector2.new(10, -10) })
			T.expect(finals(log)).toBe(1)
			T.expect(graph:getView()).toEqual(view)
			local kf = graph:getKeyframes()[2]
			local t, v = graph:pixelToPoint(from + Vector2.new(10, -10))
			T.expect(kf.time).toBeCloseTo(t, 0.001)
			T.expect(kf.value).toBeCloseTo(v, 0.001)
			-- an external change with a different key count ends a gesture in progress
			host.widget.mouse = keyPixel(graph, 1)
			local input = mouseInput()
			fire(graph.plot, "InputBegan", input)
			host.widget.mouse = keyPixel(graph, 1) + Vector2.new(0, -20)
			ctx.fakes:step(1 / 60)
			local count = #log
			graph._props.onChange = function(list: { any }, final: boolean)
				table.insert(log, tuple(list, final))
			end
			graph:setKeyframes({ { time = 0, value = 0 } })
			T.expect(#log).toBe(count + 1)
			T.expect(log[#log][2]).toBe(true)
			T.expect(graph:isDragging()).toBe(false)
			input.UserInputState = Enum.UserInputState.End
			ctx.fakes:step(1 / 60)
			T.expect(#log).toBe(count + 1)
			graph:destroy()
		end)

		T.itIf(isLune, "destroy during a drag ends the gesture with final = true", function()
			local host = newHost()
			local graph, log = newGraph(host)
			local before = ctx.fakes.heartbeat:connectionCount()
			local from = keyPixel(graph, 2)
			host.widget.mouse = from
			fire(graph.plot, "InputBegan", mouseInput())
			host.widget.mouse = from + Vector2.new(0, -15)
			ctx.fakes:step(1 / 60)
			T.expect(graph:isDragging()).toBe(true)
			T.expect(log[#log][2]).toBe(false)
			graph:destroy()
			T.expect(log[#log][2]).toBe(true)
			T.expect(finals(log)).toBe(1)
			T.expect(ctx.fakes.heartbeat:connectionCount()).toBe(before)
		end)

		T.itIf(isLune, "a disabled graph ignores mouse edits", function()
			local host = newHost()
			local graph, log = newGraph(host, { enabled = false })
			local from = keyPixel(graph, 2)
			drag(host, graph.plot, from, { from + Vector2.new(30, -30) })
			T.expect(#log).toBe(0)
			T.expect(graph:getKeyframes()).toEqual(keyframes())
			graph:setEnabled(true)
			drag(host, graph.plot, from, { from + Vector2.new(30, -30) })
			T.expect(finals(log)).toBe(1)
			graph:destroy()
		end)
	end)

	-- Theme --------------------------------------------------------------------------------------------------------

	T.describe("Curve editors: Theme colours", function()
		T.itIf(isLune, "every visible colour comes from Theme (or ControlKit.derived)", function()
			local function key(colour: Color3): string
				return string.format(
					"%d,%d,%d",
					math.round(colour.R * 255),
					math.round(colour.G * 255),
					math.round(colour.B * 255)
				)
			end
			local allowed: { [string]: boolean } = {}
			for _, group in { Theme.colors, Theme.categoryColors, Theme.pinColors, Kit.derived } do
				for _, colour in group :: { [string]: Color3 } do
					allowed[key(colour)] = true
				end
			end
			local host = newHost()
			local editors: { any } = {}
			local sequence = SequenceEditor.new({
				value = { { 0, 0 }, { 0.5, 1, 0.2 }, { 1, -1 } },
				min = -3,
				max = 3,
				range = { -1, 1 },
				host = host,
				parent = host.root,
			})
			sequence:selectKeypoint(2)
			sequence.presets:open()
			table.insert(editors, sequence)
			local styles = EasingPicker.new({ value = "Back.InOut", host = host, parent = host.root })
			styles:open()
			table.insert(editors, styles)
			local bezier =
				EasingPicker.new({ value = { bezier = { 0.3, 1.4, 0.7, -0.4 } }, host = host, parent = host.root })
			bezier:open()
			table.insert(editors, bezier)
			table.insert(editors, EasingPicker.new({ value = "Linear", enabled = false, parent = host.root }))
			local graph = CurveGraph.new({
				keyframes = tuple(
					{ time = 0, value = -1, easing = { bezier = { 0.2, 1.5, 0.8, -0.5 } } },
					{ time = 1, value = 1 },
					{ time = 1.5, value = 0.5 }
				),
				duration = 1.2,
				host = host,
				parent = host.root,
			})
			graph:select({ 1, 2 })
			graph:setPlayhead(0.5)
			graph.boxRect.Visible = true
			table.insert(editors, graph)
			table.insert(
				editors,
				CurveGraph.new({ keyframes = { { time = 0, value = 1 } }, enabled = false, parent = host.root })
			)

			local offenders: { string } = {}
			local checked = 0
			local function check(inst: Instance, property: string, colour: Color3)
				checked += 1
				if not allowed[key(colour)] then
					table.insert(offenders, inst:GetFullName() .. "." .. property .. " = " .. key(colour))
				end
			end
			for _, inst in host.root:GetDescendants() do
				if inst:IsA("GuiObject") then
					local gui = inst :: GuiObject
					if gui.BackgroundTransparency < 1 then
						check(gui, "BackgroundColor3", gui.BackgroundColor3)
					end
					if gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox") then
						local text = gui :: any
						if text.Text ~= "" and text.TextTransparency < 1 then
							check(gui, "TextColor3", text.TextColor3)
						end
					end
				elseif inst:IsA("UIStroke") and (inst :: UIStroke).Enabled then
					check(inst, "Color", (inst :: UIStroke).Color)
				end
			end
			T.expect(offenders).toEqual({})
			T.expect(checked).toBeGreaterThan(50)
			for _, editor in editors do
				editor:destroy()
			end
		end)
	end)
end
