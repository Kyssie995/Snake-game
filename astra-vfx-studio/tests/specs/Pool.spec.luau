--!strict
--[[
	Core/Pool — keyed reuse of built effect copies (docs/MODULE_CONTRACTS.md §18). Copies are real Builder output;
	"a pooled replay equals a fresh build" is checked by snapshotting every instance property after playing both
	copies to the same time.
]]
return function(T: any, use: (string) -> any, ctx: any)
	local Builder = use("AstraVFX.Core.Builder")
	local Json = use("AstraVFX.Core.Json")
	local Player = use("AstraVFX.Core.Player")
	local Pool = use("AstraVFX.Core.Pool")
	local Fixtures = use("Tests.Specs.Helpers.EffectFixtures")
	local HarnessModule = use("Tests.Specs.Helpers.PlaybackHarness")
	local expect = T.expect

	-- Builds a mixed-type array (the type checker infers homogeneous arrays from literals).
	local function R(...: any): { any }
		return { ... }
	end
	local isLune = ctx.environment == "lune"

	local H: any = nil
	local compiled: any = nil
	T.beforeEach(function()
		H = HarnessModule.new(use, ctx)
		Pool.clear()
		Pool.setCapacity(Pool.DEFAULT_CAPACITY)
	end)
	T.afterEach(function()
		Pool.clear()
		Pool.setCapacity(Pool.DEFAULT_CAPACITY)
		H:cleanup()
	end)

	local function simpleDef(): any
		return {
			schemaVersion = 1,
			id = "pooled",
			name = "Pooled",
			duration = 1,
			components = R({ id = "core", name = "Core", type = "part", transform = { position = { 0, 2, 0 } } }, {
				id = "sparks",
				name = "Sparks",
				type = "particles",
				properties = { rate = 30, burst = 5, lifetime = { 0.2, 0.3 } },
			}),
		}
	end

	local function build(): any
		compiled = compiled or H:compile(simpleDef())
		local built = Builder.build(compiled)
		return built
	end

	T.describe("Pool", function()
		T.it("starts empty and hands back released copies (reset, unparented, LIFO)", function()
			expect(Pool.acquire("k")).toBeNil()
			local parent = H:folder("Parent")
			local a = build()
			local b = build()
			a.container.Parent = parent
			b.container.Parent = parent
			-- dirty a: activate the part
			local part = a.controllers.core.instances[1]
			a.controllers.core:setActive(true, {
				time = 0,
				dt = 0,
				seeking = false,
				rootCFrame = CFrame.new(),
				moveParts = {},
				moveCFrames = {},
				fire = function(_name: string) end,
			})
			expect(part.Transparency).toBe(0)
			expect(Pool.release("k", a)).toBe(true)
			expect(Pool.release("k", b)).toBe(true)
			expect(Pool.count("k")).toBe(2)
			expect(Pool.count()).toBe(2)
			expect(a.container.Parent).toBeNil()
			expect(part.Transparency).toBe(1) -- reset() restored the built state
			expect(Pool.acquire("k")).toBe(b)
			expect(Pool.acquire("k")).toBe(a)
			expect(Pool.acquire("k")).toBeNil()
			expect(Pool.count()).toBe(0)
			a:destroy()
			b:destroy()
		end)

		T.it("keeps at most `capacity` idle copies per key and never destroys what it rejects", function()
			local copies = { build(), build(), build() }
			expect(Pool.capacity()).toBe(2)
			expect(Pool.release("k", copies[1])).toBe(true)
			expect(Pool.release("k", copies[2])).toBe(true)
			expect(Pool.release("k", copies[3])).toBe(false)
			expect(copies[3].destroyed).toBe(false)
			expect(Pool.release("other", copies[3])).toBe(true) -- capacity is per key
			-- double release and destroyed copies are refused
			expect(Pool.release("k", copies[1])).toBe(false)
			local dead = build()
			dead:destroy()
			expect(Pool.release("x", dead)).toBe(false)
			-- shrinking the capacity destroys the excess
			Pool.setCapacity(1)
			expect(Pool.count("k")).toBe(1)
			expect(copies[1].destroyed).toBe(true) -- oldest first
			expect(copies[2].destroyed).toBe(false)
			Pool.setCapacity(0, "other")
			expect(Pool.count("other")).toBe(0)
			expect(copies[3].destroyed).toBe(true)
			expect(Pool.capacity("other")).toBe(0)
			expect(Pool.capacity("k")).toBe(1)
		end)

		T.it("prewarm builds up to `count` copies and raises that key's capacity", function()
			local calls = 0
			local function factory(): any
				calls += 1
				local built = build()
				built.container.Parent = H:folder("Elsewhere")
				return built
			end
			expect(Pool.prewarm("k", factory, 3)).toBe(3)
			expect(calls).toBe(3)
			expect(Pool.count("k")).toBe(3)
			expect(Pool.capacity("k")).toBe(3)
			expect(Pool.prewarm("k", factory, 2)).toBe(0) -- already warm
			local copy = Pool.acquire("k")
			expect(copy.container.Parent).toBeNil() -- prewarmed copies are unparented
			expect(Pool.release("k", copy)).toBe(true)
			expect(function()
				Pool.prewarm("k", factory, 1.5)
			end).toThrow("whole number")
			expect(function()
				Pool.prewarm("k", nil :: any, 1)
			end).toThrow("factory")
		end)

		T.it("clear(key) / clear() destroy idle copies; acquire skips copies destroyed while pooled", function()
			local a, b, c = build(), build(), build()
			Pool.release("a", a)
			Pool.release("b", b)
			Pool.release("b", c)
			c:destroy() -- destroyed behind the pool's back
			expect(Pool.acquire("b")).toBe(b)
			expect(Pool.acquire("b")).toBeNil()
			Pool.release("b", b)
			Pool.clear("a")
			expect(a.destroyed).toBe(true)
			expect(Pool.count("a")).toBe(0)
			expect(Pool.count("b")).toBe(1)
			Pool.clear()
			expect(b.destroyed).toBe(true)
			expect(Pool.count()).toBe(0)
		end)

		T.it("rejects bad keys and values", function()
			expect(function()
				Pool.acquire(1 :: any)
			end).toThrow("key")
			expect(function()
				Pool.release("k", {} :: any)
			end).toThrow("BuiltEffect")
			expect(function()
				Pool.setCapacity(-1)
			end).toThrow("capacity")
		end)

		T.itIf(isLune, "a pooled replay equals a fresh build at every checked time", function()
			local full = H:compile(Fixtures.full(Json), { quality = "High" })
			local origin = CFrame.new(4, 1, -3)
			local function playTo(built: any, steps: number): any
				local player = Player.new(full, built, {
					cframe = origin,
					release = function(b: any): boolean
						return Pool.release("full", b)
					end,
				})
				table.insert(H.players, player)
				player:start()
				H:steps(player, steps, 1 / 60)
				return player
			end
			local parent = H:folder("PoolParent")
			-- first copy: play 1.3 s (particles, sounds, procedural parts, graph actions), then return it
			local first = Builder.build(full, { parent = parent })
			local p1 = playTo(first, 78)
			p1:fire("Detonate")
			p1:step(1 / 60)
			p1:destroy()
			expect(Pool.count("full")).toBe(1)
			expect(first.destroyed).toBe(false)
			expect(first.container.Parent).toBeNil()
			-- replay the pooled copy and a fresh copy to the same times; every property must match
			local pooled = Pool.acquire("full")
			expect(pooled).toBe(first)
			pooled.container.Parent = parent
			local fresh = Builder.build(full, { parent = parent })
			local a = Player.new(full, pooled, { cframe = origin })
			local b = Player.new(full, fresh, { cframe = origin })
			table.insert(H.players, a)
			table.insert(H.players, b)
			a:start()
			b:start()
			expect(H:snapshot(pooled.container)).toEqual(H:snapshot(fresh.container))
			for _, steps in { 1, 20, 30, 45 } do
				H:steps(a, steps, 1 / 60)
				H:steps(b, steps, 1 / 60)
				expect(H:snapshot(pooled.container)).toEqual(H:snapshot(fresh.container))
			end
		end)
	end)
end
