--!strict
-- Construction-level tests for the plugin UI toolkit (Theme, New, Maid, Input). Rendering is not verified here.
return function(T: any, use: (string) -> any, ctx: any)
	local Theme = use("Plugin.UI.Theme")
	local New = use("Plugin.UI.New")
	local Maid = use("Plugin.UI.Maid")
	local Input = use("Plugin.UI.Input")

	T.describe("Theme", function()
		T.it("exposes colour tokens and fonts", function()
			T.expect(Theme.color("accent")).toBeA("Color3")
			T.expect(Theme.fonts.regular).toBeA("Font")
			T.expect(function()
				Theme.color("doesNotExist")
			end).toThrow("unknown colour token")
		end)
	end)

	T.describe("New", function()
		T.it("creates instances with properties, children and parent", function()
			local parent = Instance.new("Frame")
			local button = New("TextButton", {
				Name = "Play",
				Text = "Play",
				Size = UDim2.new(0, 80, 0, 24),
				BackgroundColor3 = Theme.color("bg2"),
				FontFace = Theme.fonts.medium,
				Parent = parent,
			}, {
				New("UICorner", { CornerRadius = UDim.new(0, 4) }),
			})
			T.expect(button.Parent).toBe(parent)
			T.expect(button:FindFirstChildOfClass("UICorner")).never.toBeNil()
			T.expect(button.Text).toBe("Play")
		end)
		T.it("rejects invalid properties (reflection database)", function()
			T.expect(function()
				New("Frame", { NotAProperty = 1 })
			end).toThrow()
		end)
		T.itIf(ctx.environment == "lune", "connects On<Event> handlers", function()
			local hits = 0
			local f = New("Frame", {
				OnMouseEnter = function()
					hits += 1
				end,
			})
			ctx.fakes:signalFor(f, "MouseEnter"):Fire()
			T.expect(hits).toBe(1)
		end)
	end)

	T.describe("Maid", function()
		T.it("runs tasks once in reverse order and survives failing tasks", function()
			local log = {}
			local m = Maid.new()
			m:give(function()
				table.insert(log, "a")
			end)
			m:give(function()
				error("boom")
			end)
			m:give(function()
				table.insert(log, "c")
			end)
			local inst = m:give(Instance.new("Folder"))
			m:clean()
			m:clean()
			T.expect(log).toEqual({ "c", "a" })
			T.expect(inst.Parent).toBeNil()
		end)
	end)

	T.describe("Input", function()
		T.it("creates a full-size active input catcher", function()
			local root = Instance.new("Frame")
			local catcher = Input.catcher(root)
			T.expect(catcher.Active).toBe(true)
			T.expect(catcher.Size).toEqual(UDim2.fromScale(1, 1))
		end)
		T.itIf(ctx.environment == "lune", "reads the widget mouse position", function()
			local widget = ctx.plugin.newWidget("W")
			widget.mouse = Vector2.new(12, 34)
			T.expect(Input.mousePosition(widget)).toEqual(Vector2.new(12, 34))
		end)
	end)
end
