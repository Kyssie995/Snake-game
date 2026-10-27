--!strict
--[[
	Core/Builder — CompiledEffect -> Instances + controllers (docs/MODULE_CONTRACTS.md §16).

	Builds the realistic fixture (every component type, tests/specs/Helpers/EffectFixtures.luau) into real Lune
	Instances (property names/types are validated against the reflection database) and checks the container
	layout, tagging, preview/viewport modes, instance counts against the descriptors' cost estimates and cleanup.
]]
return function(T: any, use: (string) -> any, ctx: any)
	local Builder = use("AstraVFX.Core.Builder")
	local Compiler = use("AstraVFX.Core.Compiler")
	local Components = use("AstraVFX.Core.Components")
	local Constants = use("AstraVFX.Core.Constants")
	local Json = use("AstraVFX.Core.Json")
	local Fixtures = use("Tests.Specs.Helpers.EffectFixtures")
	local expect = T.expect
	local isLune = ctx.environment == "lune"

	local function compileFull(quality: string?, options: { [string]: any }?): any
		local o: { [string]: any } = { quality = quality or "High" }
		local extra: { [string]: any } = options or {}
		for k, v in extra do
			o[k] = v
		end
		return (Compiler.compile(Fixtures.full(Json), o))
	end

	local function frame(): any
		return {
			time = 0,
			dt = 0,
			seeking = false,
			rootCFrame = CFrame.new(),
			moveParts = {},
			moveCFrames = {},
			fire = function(_name: string) end,
		}
	end

	-- Instances below the container tagged with a component id.
	local function owned(container: Instance, id: string): { Instance }
		local out = {}
		for _, inst in container:GetDescendants() do
			if inst:GetAttribute(Constants.ATTR_COMPONENT) == id then
				table.insert(out, inst)
			end
		end
		return out
	end

	local function countClass(list: { Instance }, className: string): number
		local n = 0
		for _, inst in list do
			if inst:IsA(className) then
				n += 1
			end
		end
		return n
	end

	-- Temporarily wraps descriptor.build of `componentType`.
	local function withBuild(
		componentType: string,
		wrapper: (original: any, ctx: any, component: any) -> any,
		fn: () -> ()
	)
		local descriptor = Components.get(componentType)
		local original = descriptor.build
		descriptor.build = function(buildCtx: any, component: any): any
			return wrapper(original, buildCtx, component)
		end
		local ok, err = pcall(fn :: any)
		descriptor.build = original
		if not ok then
			error(err, 0)
		end
	end

	T.describe("Builder.build", function()
		T.it("builds a container Folder with a physics-free Root part", function()
			local compiled = compileFull()
			local parent = Instance.new("Folder")
			local built = Builder.build(compiled, { parent = parent })
			local container = built.container
			expect(container.ClassName).toBe("Folder")
			expect(container.Name).toBe("AstraVFX_Violet Impact")
			expect(container:GetAttribute(Constants.ATTR_EFFECT)).toBe("Violet Impact")
			expect(container.Parent).toBe(parent)
			local root = built.root
			expect(root.ClassName).toBe("Part")
			expect(root.Name).toBe("Root")
			expect(root.Parent).toBe(container)
			expect(root.Anchored).toBe(true)
			expect(root.CanCollide).toBe(false)
			expect(root.CanQuery).toBe(false)
			expect(root.CanTouch).toBe(false)
			expect(root.CastShadow).toBe(false)
			expect(root.Massless).toBe(true)
			expect(root.Transparency).toBe(1)
			expect(root.Size).toBeCloseTo(Vector3.new(0.2, 0.2, 0.2), 1e-4) -- float32
			expect(root.Locked).toBe(true)
			expect(root.CFrame).toBeCloseTo(CFrame.new(), 1e-9)
			expect(container.Archivable).toBe(true)
			expect(container:GetAttribute(Constants.ATTR_PREVIEW)).toBeNil()
			-- one controller per compiled component, in compiled (topological) order
			expect(#built.order).toBe(#compiled.components)
			for i, c in compiled.components do
				expect(built.order[i]).toBe(c.id)
				expect(built.controllers[c.id]).never.toBeNil()
				expect(built.controllers[c.id].component).toBe(c)
			end
			expect(built.effect).toBe(compiled)
			built:destroy()
			parent:Destroy()
		end)

		T.it("uses options.name for the container and stays unparented without options.parent", function()
			local built = Builder.build(compileFull(), { name = "Hit" })
			expect(built.container.Name).toBe("AstraVFX_Hit")
			expect(built.container:GetAttribute(Constants.ATTR_EFFECT)).toBe("Hit")
			expect(built.container.Parent).toBeNil()
			built:destroy()
		end)

		T.it("parents the container only after every component is built", function()
			local parent = Instance.new("Folder")
			local parentsSeen: { any } = {}
			local seenRoot: { any } = {}
			local function record(original: any, buildCtx: any, component: any): any
				table.insert(parentsSeen, buildCtx.container.Parent == nil)
				table.insert(seenRoot, buildCtx.root.Parent == buildCtx.container)
				return original(buildCtx, component)
			end
			withBuild("part", record, function()
				withBuild("lightning", record, function()
					local built = Builder.build(compileFull(), { parent = parent })
					expect(built.container.Parent).toBe(parent)
					built:destroy()
				end)
			end)
			expect(parentsSeen).toEqual({ true, true })
			expect(seenRoot).toEqual({ true, true })
			parent:Destroy()
		end)

		T.it("gives descriptors the already-built parent controller through ctx.parentOf", function()
			local compiled = compileFull()
			local seen: { [string]: any } = {}
			withBuild("particles", function(original: any, buildCtx: any, component: any): any
				seen[component.id] = buildCtx.parentOf(component.id) or false
				return original(buildCtx, component)
			end, function()
				withBuild("beam", function(original: any, buildCtx: any, component: any): any
					seen[component.id] = buildCtx.parentOf(component.id) or false
					return original(buildCtx, component)
				end, function()
					local built = Builder.build(compiled)
					expect(seen.sparks).toBe(built.controllers.pivot) -- sparks is a child of the pivot group
					expect(seen.slash).toBe(false) -- root component
					built:destroy()
				end)
			end)
		end)

		T.it("builds instance counts matching every descriptor's cost estimate (High and Low)", function()
			for _, level in { "High", "Low" } do
				local compiled = compileFull(level)
				local built = Builder.build(compiled)
				local total = 0
				for _, c in compiled.components do
					local cost = Components.get(c.type).estimateCost(c, compiled.quality)
					local list = owned(built.container, c.id)
					local label = level .. " " .. c.id
					expect({ label, #list }).toEqual({ label, cost.instances })
					expect({ label, countClass(list, "BasePart") }).toEqual({ label, cost.parts })
					expect({ label, countClass(list, "Attachment") }).toEqual({ label, cost.attachments })
					expect({ label, countClass(list, "ParticleEmitter") }).toEqual({ label, cost.emitters })
					expect({ label, countClass(list, "Beam") }).toEqual({ label, cost.beams })
					expect({ label, countClass(list, "Trail") }).toEqual({ label, cost.trails })
					expect({ label, countClass(list, "Light") }).toEqual({ label, cost.lights })
					expect({ label, countClass(list, "Sound") }).toEqual({ label, cost.sounds })
					total += #list
				end
				-- nothing else besides the root
				expect(#built.container:GetDescendants()).toBe(total + 1)
				built:destroy()
			end
			-- quality reaches the instances: debris count 20 -> 7 parts on Low
			local low = Builder.build(compileFull("Low"))
			expect(#owned(low.container, "rocks")).toBe(7)
			low:destroy()
		end)

		T.it("tags every component instance, including ones a descriptor forgot to tag", function()
			local compiled = compileFull()
			withBuild("part", function(original: any, buildCtx: any, component: any): any
				local controller = original(buildCtx, component)
				local extra = Instance.new("Attachment") -- deliberately untagged child of the part
				extra.Name = "Extra"
				extra.Parent = controller.instances[1]
				return controller
			end, function()
				local built = Builder.build(compiled)
				local core = built.controllers.core.instances[1]
				local extra = core:FindFirstChild("Extra")
				expect(extra).never.toBeNil()
				expect(extra:GetAttribute(Constants.ATTR_COMPONENT)).toBe("core")
				for _, inst in built.container:GetDescendants() do
					if inst ~= built.root then
						expect(inst:GetAttribute(Constants.ATTR_COMPONENT)).never.toBeNil()
					end
				end
				expect(built.root:GetAttribute(Constants.ATTR_COMPONENT)).toBeNil()
				built:destroy()
			end)
		end)

		T.it("marks every instance as preview-only in preview mode", function()
			local built = Builder.build(compileFull(), { isPreview = true })
			local all = built.container:GetDescendants()
			table.insert(all, built.container)
			expect(#all > 100).toBe(true)
			for _, inst in all do
				expect({ inst:GetFullName(), inst.Archivable }).toEqual({ inst:GetFullName(), false })
				expect({ inst:GetFullName(), inst:GetAttribute(Constants.ATTR_PREVIEW) }).toEqual({
					inst:GetFullName(),
					true,
				})
				if inst:IsA("BasePart") then
					expect((inst :: BasePart).Locked).toBe(false)
				end
			end
			-- the group shows a pivot gizmo in the editor preview only
			expect(#owned(built.container, "pivot")).toBe(1)
			built:destroy()
			local game = Builder.build(compileFull())
			expect(#owned(game.container, "pivot")).toBe(0)
			for _, inst in game.container:GetDescendants() do
				expect(inst:GetAttribute(Constants.ATTR_PREVIEW)).toBeNil()
				expect(inst.Archivable).toBe(true)
			end
			game:destroy()
		end)

		T.it("builds placeholders for components the viewport cannot render", function()
			local compiled = compileFull()
			local built = Builder.build(compiled, { viewport = true })
			for _, c in compiled.components do
				local descriptor = Components.get(c.type)
				local list = owned(built.container, c.id)
				if not descriptor.supportsViewport then
					expect({ c.id, #list }).toEqual({ c.id, 1 })
					local part = list[1] :: Part
					expect(part.ClassName).toBe("Part")
					expect(part.Shape).toBe(Enum.PartType.Ball)
					expect(part.Material).toBe(Enum.Material.Neon)
					expect(part.Transparency).toBe(1) -- hidden until active
					expect(part.Anchored).toBe(true)
					expect(part.CanCollide).toBe(false)
				end
				for _, inst in list do
					expect(inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail")).toBe(false)
					expect(inst:IsA("Light") or inst:IsA("Sound")).toBe(false)
				end
			end
			-- geometry components build normally; lightning switches to part mode (Neon parts, no beams)
			local bolt = owned(built.container, "bolt")
			expect(#bolt > 0).toBe(true)
			expect(countClass(bolt, "BasePart")).toBe(#bolt)
			expect(#owned(built.container, "rocks")).toBe(20)
			-- placeholder behaviour: visible while active, moved through frame.moveParts
			local placeholder = built.controllers.sparks
			local part = placeholder.instances[1] :: BasePart
			local f = frame()
			placeholder:setActive(true, f)
			expect(part.Transparency).toBe(0)
			local cf = CFrame.new(1, 2, 3)
			placeholder:setTransform(cf, cf, f)
			expect(f.moveParts).toEqual({ part })
			expect(f.moveCFrames).toEqual({ cf })
			placeholder:setTransform(cf, cf, f) -- unchanged: no second move
			expect(#f.moveParts).toBe(1)
			placeholder:apply("rate", 50) -- channels are ignored
			placeholder:setActive(false, f)
			expect(part.Transparency).toBe(1)
			placeholder:setActive(true, f)
			placeholder:reset()
			expect(part.Transparency).toBe(1)
			built:destroy()
		end)

		T.it("destroy() removes every instance and is idempotent", function()
			local parent = Instance.new("Folder")
			local built = Builder.build(compileFull(), { parent = parent, isPreview = true })
			local all = built.container:GetDescendants()
			expect(#parent:GetChildren()).toBe(1)
			built:destroy()
			expect(built.destroyed).toBe(true)
			expect(#parent:GetChildren()).toBe(0)
			expect(built.container.Parent).toBeNil()
			for _, inst in all do
				expect(inst.Parent == nil or inst:IsDescendantOf(built.container)).toBe(true)
			end
			built:destroy() -- second call is a no-op
			built:reset() -- reset after destroy is a no-op
			parent:Destroy()
		end)

		T.it("destroys controllers children-first and keeps going when one fails", function()
			local compiled = compileFull()
			local parent = Instance.new("Folder")
			local built = Builder.build(compiled, { parent = parent })
			local calls: { string } = {}
			for _, id in built.order do
				local controller = built.controllers[id]
				local original = controller.destroy
				controller.destroy = function(self: any)
					table.insert(calls, id)
					if id == "core" then
						error("boom")
					end
					original(self)
				end
			end
			built:destroy()
			local expected = {}
			for i = #built.order, 1, -1 do
				table.insert(expected, built.order[i])
			end
			expect(calls).toEqual(expected)
			expect(#parent:GetChildren()).toBe(0) -- the container is destroyed anyway
			parent:Destroy()
		end)

		T.it("cleans up and reports the component when a descriptor fails", function()
			local parent = Instance.new("Folder")
			withBuild("ring", function(_original: any, _buildCtx: any, _component: any): any
				error("ring exploded")
			end, function()
				expect(function()
					Builder.build(compileFull(), { parent = parent })
				end).toThrow('component "circle"')
			end)
			expect(#parent:GetChildren()).toBe(0)
			parent:Destroy()
		end)

		T.it("reset() restores every controller's built state", function()
			local built = Builder.build(compileFull())
			local core = built.controllers.core
			local part = core.instances[1] :: BasePart
			local f = frame()
			core:setActive(true, f)
			expect(part.Transparency < 1).toBe(true)
			built:reset()
			expect(part.Transparency).toBe(1)
			built:destroy()
		end)

		T.itIf(isLune, "built controllers drive the engine (burst through the fakes)", function()
			local fakes = ctx.fakes
			local logged = #fakes.emits
			local built = Builder.build(compileFull("Low"))
			local sparks = built.controllers.sparks
			local emitter = sparks.instances[1]
			local ok, err = pcall(function()
				expect(emitter.ClassName).toBe("ParticleEmitter")
				expect(emitter.Enabled).toBe(false) -- inactive after build
				sparks:setActive(true, frame())
				expect(fakes:totalEmitted(emitter)).toBe(9) -- burst 25 × 0.35
				expect(emitter.Enabled).toBe(true)
				expect(emitter.Rate).toBeCloseTo(14, 1e-4)
			end :: any)
			built:destroy()
			-- leave the shared emit log as we found it (other specs assert on global totals)
			while #fakes.emits > logged do
				table.remove(fakes.emits)
			end
			if not ok then
				error(err, 0)
			end
		end)

		T.it("rejects anything that is not a compiled effect", function()
			expect(function()
				Builder.build(nil :: any)
			end).toThrow("CompiledEffect")
		end)
	end)
end
