--!strict
-- Colour value editors (UI/Editors): the shared Draw helper, ColorPicker (inline + popup) and GradientEditor
-- (ColorSequence). Every editor is constructed (property names/values are validated by Lune's reflection database)
-- and driven through its public methods and simulated mouse gestures (widget.mouse + fake InputObjects +
-- ctx.fakes:step). Outputs are checked against Codec (JSON form) and the engine limits. Rendering, layout and real
-- mouse input are NOT verified here (Lune: ControlKit.geometry reports position 0 and the Size offsets).
return function(T: any, use: (string) -> any, ctx: any)
	local Theme = use("Plugin.UI.Theme")
	local Kit = use("Plugin.UI.Widgets.ControlKit")
	local Draw = use("Plugin.UI.Editors.Draw")
	local ColorPicker = use("Plugin.UI.Editors.ColorPicker")
	local GradientEditor = use("Plugin.UI.Editors.GradientEditor")
	local Codec = use("AstraVFX.Core.Codec")
	local Curves = use("AstraVFX.Core.Curves")

	local lune = ctx.environment == "lune"
	local colors = Theme.colors

	local hostCounter = 0
	local function makeHost(): any
		hostCounter += 1
		local root = Instance.new("Frame")
		root.Name = "Root"
		root.Size = UDim2.fromOffset(600, 500)
		if lune then
			local widget = ctx.plugin.newWidget("AstraVFX_EditorsColor" .. hostCounter)
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

	-- Press at `from`, move through `path` (one Heartbeat each), release (UserInputState = End).
	local function drag(host: any, gui: any, from: Vector2, path: { Vector2 })
		host.widget.mouse = from
		local input = mouseInput()
		fire(gui, "InputBegan", input)
		for _, pos in path do
			host.widget.mouse = pos
			ctx.fakes:step(1 / 60)
		end
		input.UserInputState = Enum.UserInputState.End
		ctx.fakes:step(1 / 60)
	end

	-- Press and move, without releasing (returns the press input).
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

	local function release(input: any)
		input.UserInputState = Enum.UserInputState.End
		ctx.fakes:step(1 / 60)
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

	-- Every reported value is valid JSON (Codec.check) and a gesture ends with exactly one final report.
	local function expectValid(kind: string, log: { { any } }, spec: any?)
		for _, entry in log do
			local ok, message = Codec.check(kind, entry[1], spec)
			if not ok then
				T.fail("invalid " .. kind .. " reported: " .. tostring(message))
			end
		end
	end

	-- mixed-type array (the old type solver infers literal arrays from their first element)
	local function L(...: any): { any }
		return { ... }
	end

	local function hex(r: number, g: number, b: number): string
		return string.format("#%02X%02X%02X", r, g, b)
	end

	-- Draw ------------------------------------------------------------------------------------------------------

	T.describe("Draw", function()
		T.it("draws a line as one rotated frame placed at the midpoint", function()
			local parent = Instance.new("Frame")
			local line = Draw.line(parent, Vector2.new(0, 0), Vector2.new(10, 0), 2, colors.border)
			T.expect(line.Parent).toBe(parent)
			T.expect(line.Position).toEqual(UDim2.fromOffset(5, 0))
			T.expect(line.Size).toEqual(UDim2.fromOffset(10, 2))
			T.expect(line.Rotation).toBe(0)
			T.expect(line.AnchorPoint).toEqual(Vector2.new(0.5, 0.5))
			T.expect(line.BackgroundColor3).toEqual(colors.border)
			T.expect(line.Active).toBe(false)
			T.expect(line.Interactable).toBe(false)
			Draw.setLine(line, Vector2.new(0, 0), Vector2.new(10, 10))
			T.expect(line.Rotation).toBeCloseTo(45, 1e-6)
			T.expect(line.Size.X.Offset).toBe(math.ceil(math.sqrt(200))) -- whole pixels, rounded up
			T.expect(line.Size.Y.Offset).toBe(2)
			T.expect(line.Position).toEqual(UDim2.fromOffset(5, 5))
			Draw.setLine(line, Vector2.new(10, 10), Vector2.new(0, 10))
			T.expect(math.abs(line.Rotation)).toBeCloseTo(180, 1e-6)
			local unparented = Draw.line(nil, Vector2.zero, Vector2.new(0, 4))
			T.expect(unparented.Parent).toBeNil()
			T.expect(unparented.BackgroundColor3).toEqual(colors.accent)
			T.expect(unparented.Rotation).toBeCloseTo(90, 1e-6)
			-- degenerate and non-finite input never produces NaN geometry
			Draw.setLine(unparented, Vector2.new(3, 3), Vector2.new(3, 3))
			T.expect(unparented.Size.X.Offset).toBe(0)
			Draw.setLine(unparented, Vector2.new(0 / 0, 0), Vector2.new(1, 1))
			T.expect(unparented.Size).toEqual(UDim2.fromOffset(0, 0))
			parent:Destroy()
		end)

		T.it("reuses polyline segments when the points change", function()
			local parent = Instance.new("Frame")
			local pts = { Vector2.new(0, 0), Vector2.new(10, 0), Vector2.new(10, 10), Vector2.new(20, 10) }
			local poly = Draw.polyline(parent, pts, 2, colors.teal)
			T.expect(poly.Name).toBe("Polyline")
			T.expect(poly.BackgroundTransparency).toBe(1)
			T.expect(Draw.segmentCount(poly)).toBe(3)
			local first = poly:FindFirstChild("Segment") :: Frame
			T.expect(first.BackgroundColor3).toEqual(colors.teal)
			-- square caps: segments are lengthened by the thickness
			local lengths: { number } = {}
			for _, child in poly:GetChildren() do
				table.insert(lengths, (child :: Frame).Size.X.Offset)
			end
			T.expect(lengths).toEqual({ 12, 12, 12 })
			local more: { Vector2 } = {}
			for i = 0, 5 do
				table.insert(more, Vector2.new(i * 10, i))
			end
			Draw.setPolyline(poly, more)
			T.expect(Draw.segmentCount(poly)).toBe(5)
			T.expect(first.Parent).toBe(poly) -- reused, not recreated
			Draw.setPolyline(poly, { Vector2.zero, Vector2.one })
			T.expect(Draw.segmentCount(poly)).toBe(1)
			Draw.setPolyline(poly, { Vector2.zero })
			T.expect(Draw.segmentCount(poly)).toBe(0)
			local noCaps = Draw.polyline(parent, { Vector2.zero, Vector2.new(5, 0) }, 3, nil, { caps = false })
			T.expect((noCaps:FindFirstChild("Segment") :: Frame).Size.X.Offset).toBe(5)
			parent:Destroy()
		end)

		T.it("draws dots, rings and rectangles", function()
			local parent = Instance.new("Frame")
			local dot = Draw.dot(parent, Vector2.new(20, 30), 4, colors.keyframe)
			T.expect(dot.Position).toEqual(UDim2.fromOffset(20, 30))
			T.expect(dot.Size).toEqual(UDim2.fromOffset(8, 8))
			T.expect(dot.BackgroundColor3).toEqual(colors.keyframe)
			T.expect(dot:FindFirstChildOfClass("UICorner")).toBeTruthy()
			T.expect(dot:FindFirstChildOfClass("UIStroke")).toBeNil()
			Draw.setDot(dot, Vector2.new(1, 2), 6)
			T.expect(dot.Size).toEqual(UDim2.fromOffset(12, 12))
			local ring = Draw.dot(parent, Vector2.zero, 5, colors.text, { hollow = true })
			T.expect(ring.BackgroundTransparency).toBe(1)
			local stroke = ring:FindFirstChildOfClass("UIStroke") :: UIStroke
			T.expect(stroke.Color).toEqual(colors.text)
			local rect = Draw.rect(parent, Vector2.new(30, 40), Vector2.new(10, 10), nil, { stroke = colors.accent })
			T.expect(rect.Position).toEqual(UDim2.fromOffset(10, 10))
			T.expect(rect.Size).toEqual(UDim2.fromOffset(20, 30))
			T.expect(rect.BackgroundColor3).toEqual(colors.selection)
			T.expect((rect:FindFirstChildOfClass("UIStroke") :: UIStroke).Color).toEqual(colors.accent)
			Draw.clear(parent)
			T.expect(#parent:GetChildren()).toBe(0)
			parent:Destroy()
		end)

		T.it("draws scale-positioned grids with major lines", function()
			local grid = Draw.grid(nil, 4, 2)
			T.expect(grid.Name).toBe("Grid")
			T.expect(#grid:GetChildren()).toBe(3 + 1)
			local v2 = grid:FindFirstChild("V2") :: Frame
			T.expect(v2.Position).toEqual(UDim2.fromScale(0.5, 0))
			T.expect(v2.Size).toEqual(UDim2.new(0, 1, 1, 0))
			T.expect(v2.BackgroundColor3).toEqual(colors.gridMinor)
			local edged = Draw.grid(nil, 4, 2, { edges = true, majorEvery = 2, thickness = 2 })
			T.expect(#edged:GetChildren()).toBe(5 + 3)
			T.expect((edged:FindFirstChild("V2") :: Frame).BackgroundColor3).toEqual(colors.gridMajor)
			T.expect((edged:FindFirstChild("V1") :: Frame).BackgroundColor3).toEqual(colors.gridMinor)
			T.expect((edged:FindFirstChild("H2") :: Frame).AnchorPoint).toEqual(Vector2.new(0, 1))
			T.expect((edged:FindFirstChild("H1") :: Frame).Size).toEqual(UDim2.new(1, 0, 0, 2))
			grid:Destroy()
			edged:Destroy()
		end)

		T.it("maps normalised points and samples beziers", function()
			local size = Vector2.new(200, 100)
			T.expect(Draw.toPixel(Vector2.new(0.25, 0.25), size)).toEqual(Vector2.new(50, 25))
			T.expect(Draw.toPixel(Vector2.new(0.25, 0.25), size, true)).toEqual(Vector2.new(50, 75))
			T.expect(Draw.fromPixel(Vector2.new(50, 75), size, true)).toEqual(Vector2.new(0.25, 0.25))
			local pts = Draw.bezier(Vector2.zero, Vector2.new(0, 1), Vector2.new(1, 1), Vector2.new(1, 0), 10)
			T.expect(#pts).toBe(11)
			T.expect(pts[1]).toEqual(Vector2.zero)
			T.expect(pts[11]).toEqual(Vector2.new(1, 0))
			T.expect(pts[6]).toBeCloseTo(Vector2.new(0.5, 0.75), 1e-6)
		end)
	end)

	-- ColorPicker -----------------------------------------------------------------------------------------------

	T.describe("ColorPicker", function()
		T.it("converts between HSV and RGB", function()
			local function rgb(h: number, s: number, v: number): { number }
				local r, g, b = ColorPicker.hsvToRgb(h, s, v)
				return { r, g, b }
			end
			T.expect(rgb(0, 1, 1)).toEqual({ 1, 0, 0 })
			T.expect(rgb(1 / 3, 1, 1)).toBeCloseTo({ 0, 1, 0 }, 1e-9)
			T.expect(rgb(2 / 3, 1, 1)).toBeCloseTo({ 0, 0, 1 }, 1e-9)
			T.expect(rgb(1, 1, 1)).toEqual({ 1, 0, 0 }) -- hue wraps
			T.expect(rgb(0.5, 0, 0.5)).toEqual({ 0.5, 0.5, 0.5 })
			for i = 0, 40 do
				local h, s, v = (i * 0.137) % 1, ((i * 0.31) % 1), 0.2 + (i % 5) * 0.2
				local r, g, b = ColorPicker.hsvToRgb(h, s, v)
				local h2, s2, v2 = ColorPicker.rgbToHsv(r, g, b)
				T.expect(v2).toBeCloseTo(v, 1e-9)
				T.expect(s2).toBeCloseTo(s, 1e-9)
				if s > 1e-6 then
					T.expect(h2).toBeCloseTo(h, 1e-9)
				end
			end
		end)

		T.it("parses typed hex and palette references", function()
			local palette = { accent = "#8B6CFF" }
			T.expect(ColorPicker.parseInput("#ff8a3d")).toBe("#FF8A3D")
			T.expect(ColorPicker.parseInput("  ff8a3d ")).toBe("#FF8A3D")
			T.expect(ColorPicker.parseInput("#abc")).toBe("#AABBCC")
			T.expect(ColorPicker.parseInput("abc")).toBe("#AABBCC")
			T.expect(ColorPicker.parseInput("#abcd")).toBeNil()
			T.expect(ColorPicker.parseInput("red")).toBeNil()
			T.expect(ColorPicker.parseInput("")).toBeNil()
			T.expect(ColorPicker.parseInput("$accent", palette)).toBe("$accent")
			T.expect(ColorPicker.parseInput("$accent")).toBeNil()
			T.expect(ColorPicker.parseInput("$nope", palette)).toBeNil()
		end)

		T.itIf(lune, "constructs unparented with square, hue bar, hex and RGB fields", function()
			local host = makeHost()
			local log, onChange = recorder()
			local picker = ColorPicker.new({ value = "#FF8A3D", host = host, onChange = onChange })
			T.expect(picker.instance.Parent).toBeNil()
			T.expect(picker:getValue()).toBe("#FF8A3D")
			T.expect(picker:getHex()).toBe("#FF8A3D")
			-- two stacked gradients: white -> hue, transparent -> black
			local hueLayer = picker.svArea:FindFirstChild("Hue") :: Frame
			local shade = picker.svArea:FindFirstChild("Shade") :: Frame
			local hueGradient = hueLayer:FindFirstChildOfClass("UIGradient") :: UIGradient
			local shadeGradient = shade:FindFirstChildOfClass("UIGradient") :: UIGradient
			T.expect(hueLayer.BackgroundColor3).toEqual(Color3.new(1, 1, 1))
			T.expect(hueGradient.Color.Keypoints[1].Value).toEqual(Color3.new(1, 1, 1))
			local h = picker:getHSV()
			local r, g, b = ColorPicker.hsvToRgb(h, 1, 1)
			T.expect(hueGradient.Color.Keypoints[2].Value).toBeCloseTo(Color3.new(r, g, b), 1e-5)
			T.expect(shade.BackgroundColor3).toEqual(Color3.new(0, 0, 0))
			T.expect(shadeGradient.Rotation).toBe(90)
			T.expect(shadeGradient.Transparency.Keypoints[1].Value).toBe(1)
			T.expect(shadeGradient.Transparency.Keypoints[2].Value).toBe(0)
			local spectrum = (picker.hueArea:FindFirstChild("Spectrum") :: Frame):FindFirstChildOfClass(
					"UIGradient"
				) :: UIGradient
			T.expect(#spectrum.Color.Keypoints).toBe(7)
			T.expect(spectrum.Color.Keypoints[1].Value).toEqual(Color3.new(1, 0, 0))
			T.expect(spectrum.Color.Keypoints[7].Value).toEqual(Color3.new(1, 0, 0))
			T.expect(picker.hexInput:getValue()).toBe("#FF8A3D")
			T.expect(picker.rgbInputs[1]:getValue()).toBe(255)
			T.expect(picker.rgbInputs[2]:getValue()).toBe(138)
			T.expect(picker.rgbInputs[3]:getValue()).toBe(61)
			-- display-only updates
			picker:setValue("#00f")
			T.expect(picker:getValue()).toBe("#0000FF")
			picker:setValue({ 255, 0, 0 })
			T.expect(picker:getValue()).toBe("#FF0000")
			picker:setValue(Color3.fromRGB(1, 2, 3))
			T.expect(picker:getValue()).toBe("#010203")
			picker:setValue("not a colour")
			T.expect(picker:getValue()).toBe("#FFFFFF")
			T.expect(#log).toBe(0)
			local parent = Instance.new("Frame")
			local parented = ColorPicker.new({ value = "#000000", parent = parent, showPreview = false })
			T.expect(parented.instance.Parent).toBe(parent)
			T.expect(parented.original).toBeNil()
			T.expect(parented.recentRow).toBeNil() -- no host, no recent colours
			picker:destroy()
			picker:destroy() -- idempotent
			parented:destroy()
		end)

		T.itIf(lune, "drags on the saturation/value square: false while dragging, one final", function()
			local host = makeHost()
			local log, onChange = recorder()
			local picker = ColorPicker.new({ value = "#FF0000", host = host, onChange = onChange })
			local _, size = Kit.geometry(picker.svArea)
			local baseline = heartbeatCount()
			drag(host, picker.svHit, Vector2.new(size.X / 2, 0), { Vector2.new(size.X, size.Y / 2) })
			T.expect(log).toEqual(L(L("#FF8080", false), L("#800000", false), L("#800000", true)))
			expectValid("color3", log)
			T.expect(heartbeatCount()).toBe(baseline)
			local h, s, v = picker:getHSV()
			T.expect({ h, s, v }).toEqual({ 0, 1, 0.5 })
			T.expect(picker.svCursor.Position).toEqual(UDim2.fromScale(1, 0.5))
			T.expect(picker.hexInput:getValue()).toBe("#800000")
			T.expect(picker:getRecent()).toEqual({ "#800000" })
			-- outside the square clamps; a click without movement still reports false + true
			table.clear(log)
			drag(host, picker.svHit, Vector2.new(-50, size.Y * 4), {})
			T.expect(log).toEqual(L(L("#000000", false), L("#000000", true)))
			-- pressing where the value already is reports nothing
			table.clear(log)
			drag(host, picker.svHit, Vector2.new(-50, size.Y * 4), {})
			T.expect(log).toEqual({})
			picker:destroy()
		end)

		T.itIf(lune, "drags on the hue bar and keeps the hue for greys and black", function()
			local host = makeHost()
			local log, onChange = recorder()
			local picker = ColorPicker.new({ value = "#FF0000", host = host, onChange = onChange })
			local _, size = Kit.geometry(picker.hueArea)
			drag(host, picker.hueHit, Vector2.new(size.X / 3, 6), { Vector2.new(size.X * 2 / 3, 6) })
			T.expect(log).toEqual(L(L("#00FF00", false), L("#0000FF", false), L("#0000FF", true)))
			expectValid("color3", log)
			T.expect(picker.hueCursor.Position.X.Scale).toBeCloseTo(2 / 3, 1e-6) -- UDim scale is float32
			-- black / grey keep the hue (and black keeps the saturation)
			picker:setHSV(2 / 3, 1, 0)
			T.expect(picker:getValue()).toBe("#000000")
			local h, s = picker:getHSV()
			T.expect(h).toBeCloseTo(2 / 3, 1e-9)
			T.expect(s).toBe(1)
			picker:setRGB(128, 128, 128)
			T.expect(picker:getValue()).toBe("#808080")
			h, s = picker:getHSV()
			T.expect(h).toBeCloseTo(2 / 3, 1e-9)
			T.expect(s).toBe(0)
			-- a re-render with the same value does not reset the editing state
			picker:setValue("#808080")
			T.expect((picker:getHSV())).toBeCloseTo(2 / 3, 1e-9)
			picker:destroy()
		end)

		T.itIf(lune, "commits typed hex text and rejects invalid text", function()
			local host = makeHost()
			local log, onChange = recorder()
			local picker = ColorPicker.new({ value = "#FF0000", host = host, onChange = onChange })
			local box = picker.hexInput.box
			box.Text = "00ff00"
			fire(box, "FocusLost", true, nil)
			T.expect(log).toEqual(L(L("#00FF00", true)))
			T.expect(picker.hexInput:getValue()).toBe("#00FF00")
			T.expect(picker.rgbInputs[2]:getValue()).toBe(255)
			box.Text = "grün"
			fire(box, "FocusLost", true, nil)
			T.expect(#log).toBe(1)
			T.expect(picker.hexInput:getError()).toBeTruthy()
			T.expect(picker:getValue()).toBe("#00FF00")
			T.expect(picker:setHex("#12")).toBe(false)
			T.expect(picker:setHex("#123")).toBe(true)
			T.expect(log[2]).toEqual(L("#112233", true))
			picker:destroy()
		end)

		T.itIf(lune, "edits R/G/B through the number fields (scrub and typing)", function()
			local host = makeHost()
			local log, onChange = recorder()
			local picker = ColorPicker.new({ value = "#102030", host = host, onChange = onChange })
			local red = picker.rgbInputs[1]
			drag(host, red.scrub, Vector2.new(5, 5), { Vector2.new(15, 5), Vector2.new(25, 5) })
			T.expect(log[1]).toEqual(L(hex(26, 32, 48), false))
			T.expect(log[#log]).toEqual(L(hex(36, 32, 48), true))
			T.expect(finals(log)).toBe(1)
			expectValid("color3", log)
			table.clear(log)
			local blue = picker.rgbInputs[3]
			blue.box.Text = "300"
			fire(blue.box, "FocusLost", true, nil)
			T.expect(log).toEqual(L(L(hex(36, 32, 255), true))) -- clamped to 0..255
			picker:setRGB(-5, 999, 12.4)
			T.expect(log[2]).toEqual(L(hex(0, 255, 12), true))
			picker:destroy()
		end)

		T.itIf(lune, "offers palette chips that return $references", function()
			local host = makeHost()
			local log, onChange = recorder()
			local palette = { accent = "#8B6CFF", ember = Color3.fromRGB(200, 30, 10), ["bad key"] = "#FFFFFF" }
			local picker = ColorPicker.new({ value = "$accent", palette = palette, host = host, onChange = onChange })
			T.expect(picker:getValue()).toBe("$accent")
			T.expect(picker:getHex()).toBe("#8B6CFF")
			T.expect(picker.hexInput:getValue()).toBe("$accent")
			T.expect(picker.paletteChips.accent).toBeTruthy()
			T.expect(picker.paletteChips.ember.BackgroundColor3).toEqual(Color3.fromRGB(200, 30, 10))
			T.expect(picker.paletteChips["bad key"]).toBeNil()
			local stroke = picker.paletteChips.accent:FindFirstChild("Outline") :: UIStroke
			T.expect(stroke.Color).toEqual(colors.accent)
			fire(picker.paletteChips.ember, "Activated")
			T.expect(log).toEqual(L(L("$ember", true)))
			T.expect(picker:getHex()).toBe("#C81E0A")
			T.expect(stroke.Color).toEqual(colors.borderStrong)
			T.expect(picker:setHex("$accent")).toBe(true)
			T.expect(log[2]).toEqual(L("$accent", true))
			T.expect(picker:choosePalette("missing")).toBe(false)
			T.expect(picker:getRecent()).toEqual({}) -- references are not recorded as recent colours
			-- editing the colour turns the reference into a hex value
			picker:setHSV(0, 1, 1)
			T.expect(log[3]).toEqual(L("#FF0000", true))
			expectValid("color3", log)
			picker:destroy()
		end)

		T.itIf(lune, "keeps at most 8 recent colours per host, newest first", function()
			local host = makeHost()
			local other = makeHost()
			local log, onChange = recorder()
			local picker = ColorPicker.new({ value = "#000000", host = host, onChange = onChange })
			for i = 1, 10 do
				picker:setHex(hex(i, i, i))
			end
			picker:setHex(hex(3, 3, 3)) -- already recent: moves to the front
			local recent = picker:getRecent()
			T.expect(#recent).toBe(ColorPicker.MAX_RECENT)
			T.expect(recent[1]).toBe(hex(3, 3, 3))
			T.expect(recent[2]).toBe(hex(10, 10, 10))
			T.expect(table.find(recent, hex(1, 1, 1))).toBeNil()
			T.expect(#picker.recentChips).toBe(8)
			T.expect(picker.recentChips[2].BackgroundColor3).toEqual(Color3.fromRGB(10, 10, 10))
			-- clicking a recent chip chooses it
			table.clear(log)
			fire(picker.recentChips[2], "Activated")
			T.expect(log).toEqual(L(L(hex(10, 10, 10), true)))
			T.expect(picker:getRecent()[1]).toBe(hex(10, 10, 10))
			-- shared by every picker of the host, separate per host
			local second = ColorPicker.new({ value = "#000000", host = host })
			T.expect(#second.recentChips).toBe(8)
			local foreign = ColorPicker.new({ value = "#000000", host = other })
			T.expect(#foreign.recentChips).toBe(0)
			T.expect(foreign:chooseRecent(1)).toBe(false)
			picker:destroy()
			second:destroy()
			foreign:destroy()
		end)

		T.itIf(lune, "reverts to the original colour from the preview", function()
			local host = makeHost()
			local log, onChange = recorder()
			local picker = ColorPicker.new({ value = "#336699", host = host, onChange = onChange })
			picker:setHex("#FFFFFF")
			T.expect((picker.current :: Frame).BackgroundColor3).toEqual(Color3.new(1, 1, 1))
			T.expect((picker.original :: TextButton).BackgroundColor3).toEqual(Color3.fromRGB(0x33, 0x66, 0x99))
			fire(picker.original, "Activated")
			T.expect(log[#log]).toEqual(L("#336699", true))
			picker:destroy()
		end)

		T.itIf(lune, "opens as a popup in host.root and closes on an outside click", function()
			local host = makeHost()
			local anchor = Instance.new("Frame")
			anchor.Size = UDim2.fromOffset(120, 24)
			anchor.Parent = host.root
			local log, onChange = recorder()
			local closed = 0
			local picker = ColorPicker.open(host, {
				value = "#FF0000",
				anchor = anchor,
				onChange = onChange,
				onClose = function()
					closed += 1
				end,
			})
			T.expect(picker:isOpen()).toBe(true)
			T.expect(picker.instance.Parent).toBe(host.root)
			T.expect(picker.instance.Position).toEqual(UDim2.fromOffset(4, 26)) -- below the anchor, clamped
			T.expect(picker.instance.ZIndex).toBeGreaterThan(Kit.Z.popup)
			-- raised as a whole, but the hit areas stay above the gradient layers and cursors
			local shade = picker.svArea:FindFirstChild("Shade") :: Frame
			T.expect(shade.ZIndex).toBeGreaterThan(Kit.Z.popup)
			T.expect(picker.svCursor.ZIndex).toBeGreaterThan(shade.ZIndex)
			T.expect(picker.svHit.ZIndex).toBeGreaterThan(picker.svCursor.ZIndex)
			T.expect(picker.hueHit.ZIndex).toBeGreaterThan(picker.hueCursor.ZIndex)
			local overlay = host.root:FindFirstChild("AstraColorPickerOverlay") :: TextButton
			T.expect(overlay).toBeTruthy()
			T.expect(overlay.ZIndex).toBe(Kit.Z.popup)
			T.expect(picker.closeButton).toBeTruthy()
			fire(overlay, "Activated")
			T.expect(picker:isOpen()).toBe(false)
			T.expect(closed).toBe(1)
			T.expect(host.root:FindFirstChild("AstraColorPickerOverlay")).toBeNil()
			T.expect(host.root:FindFirstChild("AstraColorPicker")).toBeNil()
			T.expect(#log).toBe(0)
			picker:close() -- idempotent
			T.expect(closed).toBe(1)
			-- only one popup per host; the header button closes it too
			local a = ColorPicker.open(host, { value = "#FF0000" })
			local b = ColorPicker.open(host, { value = "#00FF00", at = Vector2.new(1000, 1000) })
			T.expect(a:isOpen()).toBe(false)
			T.expect(b:isOpen()).toBe(true)
			T.expect(b.instance.Position.X.Offset).toBe(600 - b.instance.Size.X.Offset - 4)
			fire(b.closeButton.instance, "Activated")
			T.expect(b:isOpen()).toBe(false)
			-- a destroyed anchor closes its popup
			local c = ColorPicker.open(host, { value = "#0000FF", anchor = anchor })
			fire(anchor, "Destroying")
			T.expect(c:isOpen()).toBe(false)
		end)

		T.itIf(lune, "ends a running drag with final = true when closed or destroyed", function()
			local host = makeHost()
			local log, onChange = recorder()
			local baseline = heartbeatCount()
			local picker = ColorPicker.open(host, { value = "#FF0000", onChange = onChange })
			local input = beginDrag(host, picker.svHit, Vector2.new(0, 0), { Vector2.new(10, 10) })
			T.expect(heartbeatCount()).toBe(baseline + 1)
			T.expect(log[#log][2]).toBe(false)
			fire(host.root:FindFirstChild("AstraColorPickerOverlay"), "Activated")
			T.expect(log[#log][2]).toBe(true)
			T.expect(finals(log)).toBe(1)
			T.expect(heartbeatCount()).toBe(baseline)
			release(input)
			T.expect(finals(log)).toBe(1)
			-- inline destroy mid-drag
			table.clear(log)
			local inline = ColorPicker.new({ value = "#FF0000", host = host, onChange = onChange })
			beginDrag(host, inline.hueHit, Vector2.new(100, 5), { Vector2.new(120, 5) })
			inline:destroy()
			T.expect(log[#log][2]).toBe(true)
			T.expect(finals(log)).toBe(1)
			T.expect(heartbeatCount()).toBe(baseline)
			-- destroy while an R/G/B field is scrubbed: exactly one final (the field's own end is swallowed)
			table.clear(log)
			local scrubbed = ColorPicker.new({ value = "#102030", host = host, onChange = onChange })
			beginDrag(host, scrubbed.rgbInputs[1].scrub, Vector2.new(5, 5), { Vector2.new(25, 5) })
			T.expect(log[#log]).toEqual(L(hex(36, 32, 48), false))
			scrubbed:destroy()
			T.expect(log[#log]).toEqual(L(hex(36, 32, 48), true))
			T.expect(finals(log)).toBe(1)
			T.expect(heartbeatCount()).toBe(baseline)
		end)

		T.itIf(lune, "ignores input while disabled", function()
			local host = makeHost()
			local log, onChange = recorder()
			local picker = ColorPicker.new({ value = "#FF0000", host = host, onChange = onChange, enabled = false })
			drag(host, picker.svHit, Vector2.new(10, 10), { Vector2.new(50, 50) })
			drag(host, picker.hueHit, Vector2.new(10, 5), { Vector2.new(50, 5) })
			T.expect(picker:choosePalette("x")).toBe(false)
			T.expect(#log).toBe(0)
			T.expect(picker.svHit.Interactable).toBe(false)
			picker:setEnabled(true)
			drag(host, picker.svHit, Vector2.new(10, 10), {})
			T.expect(finals(log)).toBe(1)
			picker:destroy()
		end)
	end)

	-- GradientEditor --------------------------------------------------------------------------------------------

	T.describe("GradientEditor", function()
		local BW = L(L(0, "#000000"), L(1, "#FFFFFF"))

		local function times(editor: any): { number }
			local out: { number } = {}
			for _, kp in editor:getKeypoints() do
				table.insert(out, kp[1])
			end
			return out
		end

		T.itIf(lune, "constructs unparented with a UIGradient preview and one handle per keypoint", function()
			local host = makeHost()
			local log, onChange = recorder()
			local value = L(L(0, "#FFFFFF"), L(0.4, "#FFB23D"), L(1, "#C81E0A"))
			local editor = GradientEditor.new({ value = value, host = host, onChange = onChange })
			T.expect(editor.instance.Parent).toBeNil()
			T.expect(editor:getValue()).toEqual(value)
			T.expect(#editor.handles).toBe(3)
			T.expect(editor.handles[2].button.Position).toEqual(UDim2.new(0.4, 0, 0, 0))
			T.expect(editor.handles[2].chip.BackgroundColor3).toEqual(Color3.fromRGB(0xFF, 0xB2, 0x3D))
			local decoded = Codec.decode("colorSequence", value)
			T.expect(editor.gradient.Color).toEqual(decoded)
			T.expect(editor.bar.BackgroundColor3).toEqual(Color3.new(1, 1, 1))
			T.expect(editor:getSelected()).toBe(1)
			T.expect(editor.swatch:getValue()).toBe("#FFFFFF")
			-- a plain colour shows two handles
			editor:setValue("#33C3B0")
			T.expect(#editor.handles).toBe(2)
			T.expect(editor:getValue()).toBe("#33C3B0")
			T.expect(editor:getKeypoints()).toEqual(L(L(0, "#33C3B0"), L(1, "#33C3B0")))
			-- invalid values fall back to white without errors
			editor:setValue(L(L(0.5, "#FF0000")))
			T.expect(editor:getValue()).toBe("#FFFFFF")
			T.expect(#log).toBe(0)
			local parent = Instance.new("Frame")
			local parented = GradientEditor.new({ value = BW, parent = parent })
			T.expect(parented.instance.Parent).toBe(parent)
			editor:destroy()
			editor:destroy()
			parented:destroy()
		end)

		T.itIf(lune, "adds keypoints with the evaluated colour (method and click on the bar)", function()
			local host = makeHost()
			local log, onChange = recorder()
			local selected: { number } = {}
			local editor = GradientEditor.new({
				value = BW,
				host = host,
				onChange = onChange,
				onSelect = function(i: number)
					table.insert(selected, i)
				end,
			})
			T.expect(editor:addKeypoint(0.5)).toBe(2)
			T.expect(editor:getKeypoints()).toEqual(L(L(0, "#000000"), L(0.5, "#808080"), L(1, "#FFFFFF")))
			T.expect(log).toEqual(L(L(editor:getValue(), true))) -- a discrete edit: one final report
			T.expect(editor:getSelected()).toBe(2)
			T.expect(selected).toEqual({ 2 })
			-- click on the bar (Lune: the bar is 100 px wide at x = 0)
			table.clear(log)
			drag(host, editor.barHit, Vector2.new(25, 10), {})
			local kps = editor:getKeypoints()
			T.expect(#kps).toBe(4)
			T.expect(kps[2]).toEqual(L(0.25, hex(64, 64, 64)))
			T.expect(Codec.parseColor(kps[2][2]))
				.toBeCloseTo(Curves.evaluateColorSequence(Codec.decode("colorSequence", BW), 0.25), 1 / 255)
			T.expect(#log).toBe(2)
			T.expect(log[1][2]).toBe(false)
			T.expect(log[2]).toEqual(L(editor:getValue(), true))
			T.expect(editor:getSelected()).toBe(2)
			-- press + drag on the bar: add and move in one gesture
			table.clear(log)
			drag(host, editor.barHit, Vector2.new(60, 10), { Vector2.new(70, 10), Vector2.new(75, 10) })
			T.expect(times(editor)).toEqual({ 0, 0.25, 0.5, 0.75, 1 })
			T.expect(finals(log)).toBe(1)
			T.expect(log[#log][2]).toBe(true)
			expectValid("colorSequence", log)
			-- at time 0 and 1 the new keypoint goes inside the fixed end points
			editor:addKeypoint(0)
			editor:addKeypoint(1)
			local all = times(editor)
			T.expect(all[1]).toBe(0)
			T.expect(all[2]).toBe(0)
			T.expect(all[#all]).toBe(1)
			T.expect(all[#all - 1]).toBe(1)
			T.expect(Codec.check("colorSequence", editor:getValue())).toBe(true)
			editor:destroy()
		end)

		T.itIf(lune, "moves handles by dragging, clamped between neighbours; ends stay fixed", function()
			local host = makeHost()
			local log, onChange = recorder()
			local editor = GradientEditor.new({
				value = L(L(0, "#FF0000"), L(0.3, "#00FF00"), L(0.6, "#0000FF"), L(1, "#FFFFFF")),
				host = host,
				onChange = onChange,
			})
			local baseline = heartbeatCount()
			-- grab handle 2 px right of its time: the grab offset is kept (no jump)
			drag(host, editor.handles[2].button, Vector2.new(32, 8), { Vector2.new(42, 8), Vector2.new(47, 8) })
			T.expect(times(editor)).toEqual({ 0, 0.45, 0.6, 1 })
			T.expect(editor:getSelected()).toBe(2)
			T.expect(#log).toBe(3)
			T.expect(log[1][2]).toBe(false)
			T.expect(log[2][2]).toBe(false)
			T.expect(log[3]).toEqual(L(editor:getValue(), true))
			T.expect(editor.handles[2].button.Position).toEqual(UDim2.new(0.45, 0, 0, 0))
			T.expect(heartbeatCount()).toBe(baseline)
			-- clamped at the right neighbour (equal times are allowed by the engine: a hard edge)
			table.clear(log)
			drag(host, editor.handles[2].button, Vector2.new(45, 8), { Vector2.new(95, 8) })
			T.expect(times(editor)).toEqual({ 0, 0.6, 0.6, 1 })
			drag(host, editor.handles[3].button, Vector2.new(60, 8), { Vector2.new(-200, 8) })
			T.expect(times(editor)).toEqual({ 0, 0.6, 0.6, 1 }) -- cannot pass its left neighbour either
			T.expect(finals(log)).toBe(1) -- the second drag changed nothing, so it reported nothing
			-- the ends only select
			table.clear(log)
			drag(host, editor.handles[1].button, Vector2.new(0, 8), { Vector2.new(30, 8) })
			drag(host, editor.handles[4].button, Vector2.new(100, 8), { Vector2.new(50, 8) })
			T.expect(times(editor)).toEqual({ 0, 0.6, 0.6, 1 })
			T.expect(#log).toBe(0)
			T.expect(editor:getSelected()).toBe(4)
			T.expect(editor.handles[4].stroke.Color).toEqual(colors.accent)
			T.expect(editor.handles[1].stroke.Color).toEqual(colors.borderStrong)
			editor:destroy()
		end)

		T.itIf(lune, "keeps a drag alive when the owner re-renders with the reported value", function()
			local host = makeHost()
			local editor: any
			local log: { { any } } = {}
			editor = GradientEditor.new({
				value = L(L(0, "#FF0000"), L(0.5, "#00FF00"), L(1, "#0000FF")),
				host = host,
				onChange = function(v: any, final: boolean)
					table.insert(log, { v, final })
					editor:setValue(v) -- like an inspector refresh after editor:updateGesture
				end,
			})
			drag(host, editor.handles[2].button, Vector2.new(50, 8), {
				Vector2.new(60, 8),
				Vector2.new(70, 8),
				Vector2.new(80, 8),
			})
			T.expect(times(editor)).toEqual({ 0, 0.8, 1 })
			T.expect(#log).toBe(4)
			T.expect(finals(log)).toBe(1)
			editor:destroy()
		end)

		T.itIf(lune, "removes keypoints (button, right-click, method) but never the ends", function()
			local host = makeHost()
			local log, onChange = recorder()
			local editor = GradientEditor.new({
				value = L(L(0, "#FF0000"), L(0.25, "#00FF00"), L(0.5, "#0000FF"), L(1, "#FFFFFF")),
				host = host,
				onChange = onChange,
			})
			T.expect(editor:removeKeypoint(1)).toBe(false)
			T.expect(editor:removeKeypoint(4)).toBe(false)
			T.expect(editor:removeKeypoint(9)).toBe(false)
			T.expect(#log).toBe(0)
			-- delete button: disabled for the ends, removes the selected keypoint
			T.expect(editor.deleteButton._enabled).toBe(false)
			editor:selectKeypoint(3)
			T.expect(editor.deleteButton._enabled).toBe(true)
			fire(editor.deleteButton.instance, "Activated")
			T.expect(editor:getKeypoints()).toEqual(L(L(0, "#FF0000"), L(0.25, "#00FF00"), L(1, "#FFFFFF")))
			T.expect(log).toEqual(L(L(editor:getValue(), true)))
			T.expect(editor:getSelected()).toBe(2)
			-- right-click on a handle
			fire(editor.handles[2].button, "InputBegan", mouseInput(Enum.UserInputType.MouseButton2))
			T.expect(editor:keypointCount()).toBe(2)
			T.expect(#editor.handles).toBe(2)
			fire(editor.handles[1].button, "InputBegan", mouseInput(Enum.UserInputType.MouseButton2))
			T.expect(editor:keypointCount()).toBe(2) -- minimum: first and last
			T.expect(editor.deleteButton._enabled).toBe(false)
			T.expect(log[2]).toEqual(L(L(L(0, "#FF0000"), L(1, "#FFFFFF")), true))
			expectValid("colorSequence", log)
			editor:destroy()
		end)

		T.itIf(lune, "stops adding at the keypoint limit (button disabled with a tooltip)", function()
			local host = makeHost()
			local log, onChange = recorder()
			local full: { any } = {}
			for i = 0, 19 do
				table.insert(full, L(i / 19, hex(i * 10, 0, 0)))
			end
			local editor = GradientEditor.new({ value = full, host = host, onChange = onChange })
			T.expect(editor:keypointCount()).toBe(GradientEditor.MAX_KEYPOINTS)
			T.expect(editor:canAdd()).toBe(false)
			T.expect(editor.addButton._enabled).toBe(false)
			T.expect(editor.addButton._tooltip).toBeTruthy()
			T.expect(editor:addKeypoint(0.5)).toBeNil()
			drag(host, editor.barHit, Vector2.new(50, 10), { Vector2.new(60, 10) })
			fire(editor.addButton.instance, "Activated")
			T.expect(editor:keypointCount()).toBe(20)
			T.expect(#log).toBe(0)
			-- removing one re-enables adding
			editor:removeKeypoint(10)
			T.expect(editor:canAdd()).toBe(true)
			T.expect(editor.addButton._enabled).toBe(true)
			fire(editor.addButton.instance, "Activated")
			T.expect(editor:keypointCount()).toBe(20)
			expectValid("colorSequence", log, { maxKeypoints = 20 })
			editor:destroy()
			-- a smaller limit from the property spec
			local small = GradientEditor.new({ value = BW, host = host, maxKeypoints = 3 })
			T.expect(small:addKeypoint(0.5)).toBe(2)
			T.expect(small:addKeypoint(0.7)).toBeNil()
			T.expect(small:getMaxKeypoints()).toBe(3)
			T.expect(Codec.check("colorSequence", small:getValue(), { maxKeypoints = 3 })).toBe(true)
			small:destroy()
		end)

		T.itIf(lune, "edits the selected keypoint's time through the time field", function()
			local host = makeHost()
			local log, onChange = recorder()
			local editor = GradientEditor.new({
				value = L(L(0, "#FF0000"), L(0.5, "#00FF00"), L(0.8, "#0000FF"), L(1, "#FFFFFF")),
				host = host,
				onChange = onChange,
			})
			T.expect(editor.timeInput._enabled).toBe(false) -- first keypoint: fixed
			editor:selectKeypoint(2)
			T.expect(editor.timeInput._enabled).toBe(true)
			T.expect(editor.timeInput:getValue()).toBe(0.5)
			local box = editor.timeInput.box
			box.Text = "0.25"
			fire(box, "FocusLost", true, nil)
			T.expect(times(editor)).toEqual({ 0, 0.25, 0.8, 1 })
			T.expect(log).toEqual(L(L(editor:getValue(), true)))
			box.Text = "0.95" -- beyond the right neighbour: clamped
			fire(box, "FocusLost", true, nil)
			T.expect(times(editor)).toEqual({ 0, 0.8, 0.8, 1 })
			-- scrubbing the time field: false while scrubbing, one final
			table.clear(log)
			drag(host, editor.timeInput.scrub, Vector2.new(5, 5), { Vector2.new(0, 5), Vector2.new(-25, 5) })
			T.expect(times(editor)).toEqual({ 0, 0.5, 0.8, 1 }) -- 0.8 - 30 px × 0.01
			T.expect(finals(log)).toBe(1)
			T.expect(log[#log][2]).toBe(true)
			-- programmatic
			T.expect(editor:setKeypointTime(1, 0.5)).toBe(false)
			T.expect(editor:setKeypointTime(4, 0.5)).toBe(false)
			T.expect(editor:setKeypointTime(2, 0.1234)).toBe(true)
			T.expect(times(editor)[2]).toBe(0.123)
			expectValid("colorSequence", log)
			editor:destroy()
		end)

		T.itIf(lune, "edits keypoint colours through the popup picker", function()
			local host = makeHost()
			local log, onChange = recorder()
			local editor = GradientEditor.new({ value = BW, host = host, onChange = onChange })
			editor.instance.Parent = host.root
			editor:selectKeypoint(2)
			fire(editor.swatch.instance, "Activated")
			local picker = editor._popup
			T.expect(picker).toBeTruthy()
			T.expect(picker:isOpen()).toBe(true)
			T.expect(picker.instance.Parent).toBe(host.root)
			T.expect(picker:getValue()).toBe("#FFFFFF")
			drag(host, picker.hueHit, Vector2.new(0, 5), {})
			picker:setHex("#123456")
			T.expect(editor:getKeypoints()[2]).toEqual(L(1, "#123456"))
			T.expect(editor.swatch:getValue()).toBe("#123456")
			T.expect(editor.handles[2].chip.BackgroundColor3).toEqual(Color3.fromRGB(0x12, 0x34, 0x56))
			T.expect(log[#log]).toEqual(L(L(L(0, "#000000"), L(1, "#123456")), true))
			fire(host.root:FindFirstChild("AstraColorPickerOverlay"), "Activated")
			T.expect(picker:isOpen()).toBe(false)
			T.expect(editor._popup).toBeNil()
			-- equal end colours collapse into the plain colour
			table.clear(log)
			editor:setKeypointColor(1, "#123456")
			T.expect(log).toEqual(L(L("#123456", true)))
			T.expect(editor:getValue()).toBe("#123456")
			T.expect(editor:setKeypointColor(1, "nope")).toBe(false)
			editor:destroy()
		end)

		T.itIf(lune, "edits keypoint colours through an inline picker with drags", function()
			local host = makeHost()
			local log, onChange = recorder()
			local editor = GradientEditor.new({
				value = L(L(0, "#FF0000"), L(0.5, "#00FF00"), L(1, "#0000FF")),
				host = host,
				inlinePicker = true,
				onChange = onChange,
			})
			T.expect(editor.picker).toBeTruthy()
			T.expect(editor.swatch).toBeNil()
			T.expect(editor.instance.Size.Y.Offset).toBeGreaterThan(editor.picker.instance.Size.Y.Offset)
			editor:selectKeypoint(2)
			T.expect(editor.picker:getValue()).toBe("#00FF00")
			local _, size = Kit.geometry(editor.picker.svArea)
			drag(host, editor.picker.svHit, Vector2.new(size.X, 0), { Vector2.new(size.X, size.Y / 2) })
			T.expect(editor:getKeypoints()[2]).toEqual(L(0.5, "#008000"))
			T.expect(finals(log)).toBe(1)
			T.expect(log[#log][2]).toBe(true)
			expectValid("colorSequence", log)
			-- selecting another keypoint shows its colour in the picker
			editor:selectKeypoint(3)
			T.expect(editor.picker:getValue()).toBe("#0000FF")
			editor:destroy()
		end)

		T.itIf(lune, "applies presets (solid, two-tone, fire, ice, energy)", function()
			local host = makeHost()
			local log, onChange = recorder()
			local start = L(L(0, "#FF0000"), L(0.5, "#00FF00"), L(1, "#0000FF"))
			local editor = GradientEditor.new({ value = start, host = host, onChange = onChange })
			T.expect(#GradientEditor.PRESETS).toBe(5)
			for _, id in { "fire", "ice", "energy" } do
				T.expect(editor:applyPreset(id)).toBe(true)
				T.expect(editor:getValue()).toEqual(GradientEditor.PRESET_VALUES[id])
				T.expect(Codec.check("colorSequence", GradientEditor.PRESET_VALUES[id])).toBe(true)
			end
			editor:setValue(start)
			editor:applyPreset("twoTone")
			T.expect(editor:getValue()).toEqual(L(L(0, "#FF0000"), L(1, "#0000FF")))
			editor:setValue(start)
			editor:selectKeypoint(2)
			editor:applyPreset("solid")
			T.expect(editor:getValue()).toBe("#00FF00")
			T.expect(#editor.handles).toBe(2)
			T.expect(editor:applyPreset("unknown")).toBe(false)
			-- through the dropdown: the choice is applied and the dropdown shows its placeholder again
			table.clear(log)
			editor.presets:open()
			editor.presets:choose("ice")
			T.expect(log).toEqual(L(L(GradientEditor.PRESET_VALUES.ice, true)))
			T.expect(editor.presets:getValue()).toBeNil()
			editor.presets:choose("ice") -- the same preset again still applies (after edits)
			T.expect(#log).toBe(1) -- unchanged value: nothing to report
			editor:addKeypoint(0.1)
			editor.presets:choose("ice")
			T.expect(log[#log]).toEqual(L(GradientEditor.PRESET_VALUES.ice, true))
			expectValid("colorSequence", log)
			-- the result respects a smaller keypoint limit
			local small = GradientEditor.new({ value = start, host = host, maxKeypoints = 3 })
			T.expect(small:applyPreset("fire")).toBe(false)
			T.expect(small:getValue()).toEqual(start)
			small:destroy()
			editor:destroy()
		end)

		T.itIf(lune, "resolves $palette colours for the preview and keeps the references", function()
			local host = makeHost()
			local log, onChange = recorder()
			local palette = { ember = "#C81E0A" }
			local editor = GradientEditor.new({
				value = L(L(0, "$ember"), L(1, "#FFFFFF")),
				palette = palette,
				host = host,
				onChange = onChange,
			})
			T.expect(editor.gradient.Color.Keypoints[1].Value).toEqual(Color3.fromRGB(0xC8, 0x1E, 0x0A))
			T.expect(editor.handles[1].chip.BackgroundColor3).toEqual(Color3.fromRGB(0xC8, 0x1E, 0x0A))
			editor:addKeypoint(0.5)
			local kps = editor:getKeypoints()
			T.expect(kps[1][2]).toBe("$ember")
			T.expect(kps[2][2]).toBe(Codec.toHex(Color3.fromRGB(0xC8, 0x1E, 0x0A):Lerp(Color3.new(1, 1, 1), 0.5)))
			expectValid("colorSequence", log)
			-- unknown references show grey instead of failing
			editor:setPalette(nil)
			T.expect(editor.gradient.Color.Keypoints[1].Value).toEqual(colors.textMuted)
			editor:setPalette(palette)
			T.expect(editor.gradient.Color.Keypoints[1].Value).toEqual(Color3.fromRGB(0xC8, 0x1E, 0x0A))
			editor:destroy()
		end)

		T.itIf(lune, "ends a running drag with final = true on destroy and cleans up", function()
			local host = makeHost()
			local log, onChange = recorder()
			local baseline = heartbeatCount()
			local editor = GradientEditor.new({ value = BW, host = host, onChange = onChange })
			editor.instance.Parent = host.root
			local input = beginDrag(host, editor.barHit, Vector2.new(30, 10), { Vector2.new(40, 10) })
			T.expect(editor:isDragging()).toBe(true)
			T.expect(heartbeatCount()).toBe(baseline + 1)
			editor:destroy()
			T.expect(log[#log][2]).toBe(true)
			T.expect(finals(log)).toBe(1)
			T.expect(heartbeatCount()).toBe(baseline)
			T.expect(editor.instance.Parent).toBeNil()
			release(input)
			T.expect(finals(log)).toBe(1)
			-- while the time field is scrubbed, and while a popup picker is dragged
			for _, mode in { "time", "popup" } do
				table.clear(log)
				local other = GradientEditor.new({
					value = L(L(0, "#000000"), L(0.5, "#808080"), L(1, "#FFFFFF")),
					host = host,
					onChange = onChange,
				})
				other.instance.Parent = host.root
				other:selectKeypoint(2)
				if mode == "time" then
					beginDrag(host, other.timeInput.scrub, Vector2.new(5, 5), { Vector2.new(15, 5) })
					T.expect(other:getKeypoints()[2][1]).toBe(0.6)
				else
					local popup = other:openPicker()
					beginDrag(host, popup.svHit, Vector2.new(0, 0), { Vector2.new(20, 20) })
				end
				T.expect(log[#log][2]).toBe(false)
				other:destroy()
				T.expect(log[#log][2]).toBe(true)
				T.expect(finals(log)).toBe(1)
				T.expect(heartbeatCount()).toBe(baseline)
				T.expect(host.root:FindFirstChild("AstraColorPicker")).toBeNil()
			end
		end)

		T.itIf(lune, "ignores input while disabled", function()
			local host = makeHost()
			local log, onChange = recorder()
			local editor = GradientEditor.new({
				value = L(L(0, "#FF0000"), L(0.5, "#00FF00"), L(1, "#0000FF")),
				host = host,
				onChange = onChange,
				enabled = false,
			})
			drag(host, editor.barHit, Vector2.new(20, 10), {})
			drag(host, editor.handles[2].button, Vector2.new(50, 8), { Vector2.new(70, 8) })
			fire(editor.handles[2].button, "InputBegan", mouseInput(Enum.UserInputType.MouseButton2))
			T.expect(#log).toBe(0)
			T.expect(editor.addButton._enabled).toBe(false)
			T.expect(editor.timeInput._enabled).toBe(false)
			T.expect(editor:openPicker()).toBeNil()
			editor:setEnabled(true)
			drag(host, editor.barHit, Vector2.new(20, 10), {})
			T.expect(finals(log)).toBe(1)
			editor:destroy()
		end)
	end)

	-- Theme colours ---------------------------------------------------------------------------------------------

	T.describe("Colour editors: Theme colours", function()
		local function key(c: Color3): string
			return string.format("%d,%d,%d", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
		end

		-- user content (edited colours) and the technical white/black gradient bases
		local USER_CONTENT = {
			Chip = true,
			Preview = true,
			Hue = true,
			Shade = true,
			Spectrum = true,
		}

		local function isUserContent(inst: Instance): boolean
			local node: Instance? = inst
			while node do
				if USER_CONTENT[node.Name] then
					return true
				end
				node = node.Parent
			end
			return false
		end

		T.itIf(lune, "every other visible colour comes from Theme", function()
			local allowed: { [string]: boolean } = {}
			for _, group in { Theme.colors, Kit.derived } do
				for _, colour in group :: { [string]: Color3 } do
					allowed[key(colour)] = true
				end
			end
			local host = makeHost()
			local palette = { accent = "#8B6CFF", ember = "#C81E0A" }
			local picker = ColorPicker.new({ value = "$ember", palette = palette, host = host, parent = host.root })
			picker:setHex("#13579B")
			local gradient = GradientEditor.new({
				value = L(L(0, "#FF0000"), L(0.5, "$accent"), L(1, "#0000FF")),
				palette = palette,
				host = host,
				parent = host.root,
			})
			gradient:selectKeypoint(2)
			local inline =
				GradientEditor.new({ value = "#FF8A3D", host = host, inlinePicker = true, parent = host.root })
			local disabled = GradientEditor.new({ value = "#FF8A3D", host = host, enabled = false, parent = host.root })
			gradient:openPicker()
			local canvas = Instance.new("Frame")
			canvas.BackgroundTransparency = 1
			canvas.Parent = host.root
			Draw.line(canvas, Vector2.zero, Vector2.one)
			Draw.polyline(canvas, { Vector2.zero, Vector2.one, Vector2.new(2, 0) })
			Draw.dot(canvas, Vector2.zero, 3, nil, { stroke = colors.bg0 })
			Draw.grid(canvas, 4, 4, { majorEvery = 2, edges = true })

			local offenders: { string } = {}
			local checked = 0
			local function check(inst: Instance, property: string, colour: Color3)
				checked += 1
				if not allowed[key(colour)] then
					table.insert(offenders, inst:GetFullName() .. "." .. property .. " = " .. key(colour))
				end
			end
			for _, inst in host.root:GetDescendants() do
				if isUserContent(inst) then
					continue
				end
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
						if gui:IsA("TextBox") and text.PlaceholderText ~= "" then
							check(gui, "PlaceholderColor3", text.PlaceholderColor3)
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
			T.expect(checked).toBeGreaterThan(150)
			picker:destroy()
			gradient:destroy()
			inline:destroy()
			disabled:destroy()
		end)
	end)
end
