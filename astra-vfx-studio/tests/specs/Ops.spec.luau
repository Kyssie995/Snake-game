--!strict
--[[
	Ops / Ids — authoring document mutations (docs/MODULE_CONTRACTS.md §20).

	Unit tests for every op (incl. edge cases: duplicating a subtree twice, pasting into another document, moving
	keyframes past each other, removing a parent with children, connect rejection reasons) and a property-based
	test: 200 random op sequences (fixed seed) run like the editor's transact() — each op on a working copy, a
	raising op is discarded — and after every applied op Validation must report zero errors and the authoring
	invariants (unique ids across the effect scope, sorted keyframes / events / markers) must hold.
]]
return function(T: any, use: (string) -> any, _ctx: any)
	local expect = T.expect
	local Ops = use("Authoring.Ops")
	local Ids = use("Authoring.Ids")
	local Codec = use("AstraVFX.Core.Codec")
	local Compiler = use("AstraVFX.Core.Compiler")
	local Components = use("AstraVFX.Core.Components")
	local Constants = use("AstraVFX.Core.Constants")
	local Graph = use("AstraVFX.Core.Graph")
	local Json = use("AstraVFX.Core.Json")
	local Migration = use("AstraVFX.Core.Migration")
	local Random = use("AstraVFX.Core.Random")
	local Validation = use("AstraVFX.Core.Validation")
	local Fixtures = use("Tests.Specs.Helpers.EffectFixtures")

	local NodeTypes = Graph.NodeTypes

	-- ─────────────────────────────────────────────────────────────────────────
	-- Helpers
	-- ─────────────────────────────────────────────────────────────────────────

	local function errorLines(doc: any, strict: boolean?): { string }
		local result = Validation.validate(doc, { strict = strict == true })
		local lines = {}
		for _, d in result.errors do
			table.insert(lines, d.code .. " @ " .. d.path .. ": " .. d.message)
		end
		return lines
	end

	local function expectValid(doc: any)
		local lines = errorLines(doc)
		if #lines > 0 then
			T.fail("validation errors:\n  " .. table.concat(lines, "\n  "))
		end
	end

	local function roundTrip(value: any): any
		local ok, decoded = Json.decode(Json.encode(value))
		assert(ok, decoded)
		return decoded
	end

	local function ids(list: { any }): { string }
		local out = {}
		for _, entry in list do
			table.insert(out, entry.id)
		end
		return out
	end

	local function find(doc: any, id: string): any
		local component = Ops.find(doc, id)
		assert(component, "no component " .. id)
		return component
	end

	local function node(doc: any, id: string): any
		for _, n in doc.graph.nodes do
			if n.id == id then
				return n
			end
		end
		error("no node " .. id)
	end

	local function links(doc: any): { string }
		local out = {}
		for _, link in (doc.graph and doc.graph.links) or {} do
			table.insert(out, link.from .. ">" .. link.to)
		end
		return out
	end

	local function times(track: any): { number }
		local out = {}
		for _, key in track.keyframes do
			table.insert(out, key.time)
		end
		return out
	end

	local function newDoc(): any
		return Ops.newEffect("Test Effect")
	end

	-- root (group) > child (particles) > grand (beam); other (part) at the root
	local function hierarchyDoc(): any
		local doc = newDoc()
		Ops.addComponent(doc, "group", { name = "Root" })
		Ops.addComponent(doc, "particles", { name = "Child", parent = "root", properties = { rate = 10 } })
		Ops.addComponent(doc, "beam", { name = "Grand", parent = "child" })
		Ops.addComponent(doc, "part", { name = "Other" })
		Ops.addKeyframe(doc, "child", "rate", 0, 10)
		Ops.addKeyframe(doc, "child", "rate", 1, 0)
		Ops.addEvent(doc, "child", "emit", 0.5, { count = 5 })
		return doc
	end

	-- ─────────────────────────────────────────────────────────────────────────
	-- Ids
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("Ids", function()
		T.it("slug follows Migration.slug", function()
			expect(Ids.slug("Violet Impact")).toBe("violet-impact")
			expect(Ids.slug("VioletImpact")).toBe(Migration.slug("VioletImpact"))
			expect(Ids.slug("  --Hello__World!!  ")).toBe("hello__world")
			expect(Ids.slug("")).toBe("id")
			expect(Ids.slug("!!!", "fallback")).toBe("fallback")
			expect(Ids.slug(nil)).toBe("id")
			expect(#Ids.slug(string.rep("abc ", 40)) <= Constants.ID_MAX_LENGTH).toBe(true)
			expect(#Ids.slug(string.rep("a", 80))).toBe(Constants.ID_MAX_LENGTH)
			expect(Ids.isValid(Ids.slug(string.rep("abc ", 40)))).toBe(true)
		end)

		T.it("isValid checks pattern and length", function()
			expect(Ids.isValid("a-b_C9")).toBe(true)
			expect(Ids.isValid("")).toBe(false)
			expect(Ids.isValid("a b")).toBe(false)
			expect(Ids.isValid(string.rep("a", 65))).toBe(false)
			expect(Ids.isValid(5)).toBe(false)
		end)

		T.it("unique returns the base or the next free counter and marks it taken", function()
			local taken: { [string]: boolean } = {}
			expect(Ids.unique("core", taken)).toBe("core")
			expect(taken.core).toBe(true)
			expect(Ids.unique("core", taken)).toBe("core-2")
			expect(Ids.unique("core", taken)).toBe("core-3")
			expect(Ids.unique("core-2", taken)).toBe("core-4") -- continues the counter of "core-2"
			expect(Ids.unique("slash-1", { ["slash-1"] = true })).toBe("slash-2")
			expect(Ids.unique("Not An Id!", {})).toBe("not-an-id")
			local long = string.rep("x", 64)
			local t2 = { [long] = true }
			local second = Ids.unique(long, t2)
			expect(#second <= 64).toBe(true)
			expect(string.sub(second, -2)).toBe("-2")
			expect(Ids.unique(long, t2)).never.toBe(second)
			expect(function()
				Ids.unique("x", nil :: any)
			end).toThrow("taken must be a table")
		end)

		T.it("collect gathers every id of the effect scope (not the effect id)", function()
			local doc = hierarchyDoc()
			Ops.addMarker(doc, 0.5, "Impact")
			Ops.addNode(doc, "OnPlay", { 0, 0 })
			local set = Ids.collect(doc)
			for _, id in { "root", "child", "grand", "other", "child-rate", "child-emit", "impact", "onplay" } do
				expect(set[id]).toBe(true)
			end
			expect(set["test-effect"]).toBeNil()
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- Effect
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("Ops.newEffect / clone / setEffectField", function()
		T.it("produces a minimal valid definition", function()
			local doc = Ops.newEffect("Violet Impact")
			expect(doc).toEqual({
				schemaVersion = Constants.SCHEMA_VERSION,
				id = "violet-impact",
				name = "Violet Impact",
				duration = 2,
				components = {},
			})
			local result = Validation.validate(doc)
			expect(#result.errors).toBe(0)
			expect(result.ok).toBe(true)
			expect(Json.encode(doc, { pretty = false })).toBe(
				'{"schemaVersion":1,"id":"violet-impact","name":"Violet Impact","duration":2,"components":[]}'
			)
		end)

		T.it("accepts id and duration options and rejects bad ids", function()
			local doc = Ops.newEffect("X", { id = "custom_ID", duration = 120 })
			expect(doc.id).toBe("custom_ID")
			expect(doc.duration).toBe(Constants.MAX_DURATION)
			expect(Ops.newEffect("X", { duration = -1 }).duration).toBe(Ops.MIN_DURATION)
			expect(Ops.newEffect("   ").name).toBe("Effect")
			expect(Ops.newEffect("!!!").id).toBe("effect")
			expect(function()
				Ops.newEffect("X", { id = "bad id" })
			end).toThrow("Ops.newEffect: id must be")
			expect(function()
				Ops.newEffect("X", { duration = 0 / 0 })
			end).toThrow("finite")
		end)

		T.it("clone is deep and keeps Json sentinels", function()
			local ok, doc =
				Json.decode('{"schemaVersion":1,"id":"a","name":"A","duration":1,"components":[],"metadata":{}}')
			assert(ok, "fixture decodes")
			local copy = Ops.clone(doc)
			expect(copy).toEqual(doc)
			expect(rawequal(copy.components, doc.components)).toBe(false)
			expect(rawequal(copy.metadata, Json.EMPTY_OBJECT)).toBe(true)
		end)

		T.it("sets, clamps and removes effect fields", function()
			local doc = newDoc()
			Ops.setEffectField(doc, "name", "Renamed")
			Ops.setEffectField(doc, "duration", 999)
			Ops.setEffectField(doc, "description", "desc")
			Ops.setEffectField(doc, "loop", true)
			Ops.setEffectField(doc, "seed", 41.6)
			Ops.setEffectField(doc, "timeScale", 50)
			Ops.setEffectField(doc, "tags", { "a", "b", "a" })
			Ops.setEffectField(doc, "palette", { primary = "#f0a", dark = { 10, 20, 30 } })
			expect(doc.name).toBe("Renamed")
			expect(doc.duration).toBe(Constants.MAX_DURATION)
			expect(doc.loop).toBe(true)
			expect(doc.seed).toBe(42)
			expect(doc.timeScale).toBe(Constants.MAX_TIME_SCALE)
			expect(doc.tags).toEqual({ "a", "b" })
			expect(doc.palette).toEqual({ primary = "#FF00AA", dark = "#0A141E" })
			expectValid(doc)
			Ops.setEffectField(doc, "loop", false)
			Ops.setEffectField(doc, "description", nil)
			Ops.setEffectField(doc, "seed", Json.NULL)
			Ops.setEffectField(doc, "timeScale", nil)
			Ops.setEffectField(doc, "tags", {})
			Ops.setEffectField(doc, "palette", nil)
			expect(doc.loop).toBeNil()
			expect(doc.description).toBeNil()
			expect(doc.seed).toBeNil()
			expect(doc.timeScale).toBeNil()
			expect(doc.tags).toBeNil()
			expect(doc.palette).toBeNil()
			expect(function()
				Ops.setEffectField(doc, "name", "   ")
			end).toThrow("must not be empty")
			expect(function()
				Ops.setEffectField(doc, "colour", 1)
			end).toThrow("unknown effect field")
			expect(function()
				Ops.setEffectField(doc, "palette", { ["bad key"] = "#FFFFFF" })
			end).toThrow("palette key")
			expect(function()
				Ops.setEffectField(doc, "palette", { a = "$b" })
			end).toThrow("cannot reference")
		end)

		T.it("rejects a palette that drops a referenced key", function()
			local doc = newDoc()
			Ops.setEffectField(doc, "palette", { primary = "#FF0000", spare = "#00FF00" })
			Ops.addComponent(doc, "part", { properties = { color = "$primary" } })
			Ops.setEffectField(doc, "palette", { primary = "#0000FF" }) -- spare is unused
			expect(doc.palette).toEqual({ primary = "#0000FF" })
			expect(function()
				Ops.setEffectField(doc, "palette", { other = "#FFFFFF" })
			end).toThrow('"$primary" is still used')
			Ops.addMarker(doc, 0, "M", { color = "$primary" })
			Ops.resetProperty(doc, { "part" }, "color")
			expect(function()
				Ops.setEffectField(doc, "palette", nil)
			end).toThrow('"$primary" is still used')
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- Components
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("Ops queries", function()
		T.it("find, children and descendants", function()
			local doc = hierarchyDoc()
			local component, index = Ops.find(doc, "grand")
			expect(component.name).toBe("Grand")
			expect(index).toBe(3)
			expect(Ops.find(doc, "missing")).toBeNil()
			expect(ids(Ops.children(doc))).toEqual({ "root", "other" })
			expect(ids(Ops.children(doc, "root"))).toEqual({ "child" })
			expect(ids(Ops.descendants(doc, "root"))).toEqual({ "child", "grand" })
			expect(ids(Ops.descendants(doc, "other"))).toEqual({})
			expect(function()
				Ops.children(doc, "missing")
			end).toThrow("Ops.children: unknown component id")
			expect(function()
				Ops.descendants(doc, "missing")
			end).toThrow("unknown component id")
		end)
	end)

	T.describe("Ops.addComponent", function()
		T.it("writes only explicit properties and assigns timing", function()
			local doc = newDoc()
			local id = Ops.addComponent(doc, "particles")
			expect(id).toBe("particles")
			expect(doc.components[1]).toEqual({
				id = "particles",
				name = "Particles",
				type = "particles",
				startTime = 0,
				duration = 2,
			})
			local id2 = Ops.addComponent(doc, "particles", {
				name = "Sparks",
				startTime = 0.5,
				properties = { rate = 1000, color = "#f00", size = { { 0, 1 }, { 1, 1 } } },
			})
			expect(id2).toBe("sparks")
			local sparks = find(doc, "sparks")
			expect(sparks.startTime).toBe(0.5)
			expect(sparks.duration).toBe(1.5)
			expect(sparks.properties).toEqual({ rate = 400, color = "#FF0000", size = 1 })
			expect(Ops.addComponent(doc, "particles")).toBe("particles-2")
			expect(Ops.addComponent(doc, "part", { startTime = -3, duration = 0 })).toBe("part")
			expect(find(doc, "part").startTime).toBe(0)
			expect(find(doc, "part").duration).toBe(Ops.MIN_DURATION)
			expectValid(doc)
		end)

		T.it("honours parent and index and rejects bad input", function()
			local doc = newDoc()
			Ops.addComponent(doc, "group", { name = "Pivot" })
			Ops.addComponent(doc, "light", { name = "Glow", parent = "pivot", index = 1 })
			expect(ids(doc.components)).toEqual({ "glow", "pivot" })
			expect(find(doc, "glow").parent).toBe("pivot")
			expect(Ops.addComponent(doc, "part", { parent = "" })).toBe("part")
			expect(find(doc, "part").parent).toBeNil()
			expect(function()
				Ops.addComponent(doc, "nope")
			end).toThrow('Ops.addComponent: unknown component type "nope"')
			expect(function()
				Ops.addComponent(doc, "part", { parent = "missing" })
			end).toThrow("unknown component id")
			expect(function()
				Ops.addComponent(doc, "part", { properties = { bogus = 1 } })
			end).toThrow('part has no property "bogus"')
			expect(function()
				Ops.addComponent(doc, "part", { properties = { color = "nope" } })
			end).toThrow("color")
			expect(function()
				Ops.addComponent(doc, "part", { properties = { color = "$missing" } })
			end).toThrow('palette colour "$missing" does not exist')
			expect(#doc.components).toBe(3)
			expectValid(doc)
		end)

		T.it("enforces the component limit", function()
			local doc = newDoc()
			for _ = 1, Constants.MAX_COMPONENTS do
				Ops.addComponent(doc, "group")
			end
			expect(function()
				Ops.addComponent(doc, "group")
			end).toThrow("at most " .. Constants.MAX_COMPONENTS .. " components")
			expect(function()
				Ops.duplicateComponents(doc, { "group" })
			end).toThrow("at most")
		end)
	end)

	T.describe("Ops.removeComponents", function()
		T.it("removes a parent with its children and grandchildren", function()
			local doc = hierarchyDoc()
			local affected = Ops.removeComponents(doc, { "root" })
			expect(affected).toEqual({})
			expect(ids(doc.components)).toEqual({ "other" })
			expectValid(doc)
		end)

		T.it("removes Component nodes of removed components and clears other graph references", function()
			local doc = hierarchyDoc()
			Ops.addNode(doc, "OnPlay", { 0, 0 })
			Ops.addNode(doc, "Emit", { 200, 0 }, { target = "child", count = 3 })
			Ops.addNode(doc, "Component", { 0, 100 }, { component = "child" })
			Ops.addNode(doc, "Emit", { 200, 100 })
			Ops.addNode(doc, "Component", { 0, 200 }, { component = "other" })
			Ops.addNode(doc, "SetEnabled", { 200, 200 })
			expect(Ops.connect(doc, "onplay.out", "emit.in")).toBe(true)
			expect(Ops.connect(doc, "emit.out", "emit-2.in")).toBe(true)
			expect(Ops.connect(doc, "component.component", "emit-2.target")).toBe(true)
			expect(Ops.connect(doc, "emit-2.out", "setenabled.in")).toBe(true)
			expect(Ops.connect(doc, "component-2.component", "setenabled.target")).toBe(true)
			expectValid(doc)
			local affected = Ops.removeComponents(doc, { "child" })
			expect(affected).toEqual({ "emit", "component", "emit-2" })
			expect(ids(doc.graph.nodes)).toEqual({ "onplay", "emit", "emit-2", "component-2", "setenabled" })
			expect(node(doc, "emit").params).toEqual({ target = "", count = 3 })
			expect(links(doc)).toEqual({
				"onplay.out>emit.in",
				"emit.out>emit-2.in",
				"emit-2.out>setenabled.in",
				"component-2.component>setenabled.target",
			})
			expect(ids(doc.components)).toEqual({ "root", "other" })
			expectValid(doc)
			local warnings = Validation.validate(doc).warnings
			local codes = {}
			for _, w in warnings do
				codes[w.code] = true
			end
			expect(codes["graph.target_missing"]).toBe(true)
		end)

		T.it("keeps Component nodes with an empty reference on request", function()
			local doc = hierarchyDoc()
			Ops.addNode(doc, "OnPlay", { 0, 0 })
			Ops.addNode(doc, "Emit", { 200, 0 })
			Ops.addNode(doc, "Component", { 0, 100 }, { component = "child" })
			Ops.connect(doc, "onplay.out", "emit.in")
			Ops.connect(doc, "component.component", "emit.target")
			local affected = Ops.removeComponents(doc, { "root" }, { keepComponentNodes = true })
			expect(affected).toEqual({ "component" })
			expect(node(doc, "component").params).toEqual({ component = "" })
			expect(#links(doc)).toBe(2)
			expectValid(doc)
		end)

		T.it("rejects unknown ids without changing anything", function()
			local doc = hierarchyDoc()
			expect(function()
				Ops.removeComponents(doc, { "other", "missing" })
			end).toThrow('Ops.removeComponents: unknown component id "missing"')
			expect(#doc.components).toBe(4)
			expect(function()
				Ops.removeComponents(doc, "other" :: any)
			end).toThrow("array of ids")
		end)
	end)

	T.describe("Ops.duplicateComponents", function()
		T.it("duplicates a subtree twice with fresh ids and remapped parents", function()
			local doc = hierarchyDoc()
			local original = Ops.clone(doc)
			local first = Ops.duplicateComponents(doc, { "root" })
			local second = Ops.duplicateComponents(doc, { "root" })
			expect(first).toEqual({ "root-2" })
			expect(second).toEqual({ "root-3" })
			expect(ids(doc.components)).toEqual({
				"root",
				"child",
				"grand",
				"root-3",
				"child-3",
				"grand-3",
				"root-2",
				"child-2",
				"grand-2",
				"other",
			})
			local copyRoot, copyChild, copyGrand = find(doc, "root-2"), find(doc, "child-2"), find(doc, "grand-2")
			expect(copyRoot.name).toBe("Root Copy")
			expect(copyRoot.parent).toBeNil()
			expect(copyChild.name).toBe("Child")
			expect(copyChild.parent).toBe("root-2")
			expect(copyGrand.parent).toBe("child-2")
			expect(find(doc, "child-3").parent).toBe("root-3")
			-- tracks and events copied with fresh ids, values identical
			expect(copyChild.tracks[1].id).never.toBe("child-rate")
			expect(copyChild.tracks[1].keyframes).toEqual(find(doc, "child").tracks[1].keyframes)
			expect(copyChild.events[1].id).never.toBe("child-emit")
			expect(copyChild.events[1].count).toBe(5)
			-- the originals are untouched
			for _, id in { "root", "child", "grand", "other" } do
				expect(find(doc, id)).toEqual(find(original, id))
			end
			expectValid(doc)
		end)

		T.it("duplicates the copy and a selected parent+child once", function()
			local doc = hierarchyDoc()
			local copy = Ops.duplicateComponents(doc, { "root" })[1]
			local copyOfCopy = Ops.duplicateComponents(doc, { copy })[1]
			expect(find(doc, copyOfCopy).name).toBe("Root Copy Copy")
			local before = #doc.components
			local result = Ops.duplicateComponents(doc, { "child", "root", "child", "other" })
			expect(result).toEqual({ "root-4", "other-2" })
			expect(#doc.components).toBe(before + 4)
			expect(find(doc, "child-4").parent).toBe("root-4")
			expect(find(doc, "other-2").name).toBe("Other Copy")
			expectValid(doc)
		end)

		T.it("keeps names within the length limit", function()
			local doc = newDoc()
			local long = string.rep("é", Constants.NAME_MAX_LENGTH)
			Ops.addComponent(doc, "part", { name = long })
			local copy = Ops.duplicateComponents(doc, { "part" })[1]
			local name = find(doc, copy).name
			expect(utf8.len(name)).toBe(Constants.NAME_MAX_LENGTH)
			expect(string.sub(name, -5)).toBe(" Copy")
			expectValid(doc)
		end)
	end)

	T.describe("Ops component fields", function()
		T.it("renames, enables and disables", function()
			local doc = hierarchyDoc()
			Ops.renameComponent(doc, "other", "Renamed")
			expect(find(doc, "other").name).toBe("Renamed")
			Ops.renameComponent(doc, "other", string.rep("n", 150))
			expect(#find(doc, "other").name).toBe(Constants.NAME_MAX_LENGTH)
			expect(function()
				Ops.renameComponent(doc, "other", "")
			end).toThrow("must not be empty")
			Ops.setEnabled(doc, { "root", "other" }, false)
			expect(find(doc, "root").enabled).toBe(false)
			Ops.setEnabled(doc, { "root" }, true)
			expect(find(doc, "root").enabled).toBeNil()
			expect(function()
				Ops.setEnabled(doc, { "root" }, "yes" :: any)
			end).toThrow("boolean")
			expectValid(doc)
		end)

		T.it("re-parents and rejects cycles", function()
			local doc = hierarchyDoc()
			Ops.setParent(doc, "other", "grand")
			expect(find(doc, "other").parent).toBe("grand")
			expect(function()
				Ops.setParent(doc, "root", "other")
			end).toThrow("cycle")
			expect(function()
				Ops.setParent(doc, "root", "root")
			end).toThrow("own parent")
			expect(function()
				Ops.setParent(doc, "root", "missing")
			end).toThrow("unknown component id")
			Ops.setParent(doc, "child", nil)
			expect(find(doc, "child").parent).toBeNil()
			Ops.setParent(doc, "grand", "")
			expect(find(doc, "grand").parent).toBeNil()
			expectValid(doc)
		end)

		T.it("moves components in the document order (clamped)", function()
			local doc = hierarchyDoc()
			Ops.moveComponent(doc, "other", 1)
			expect(ids(doc.components)).toEqual({ "other", "root", "child", "grand" })
			Ops.moveComponent(doc, "other", 99)
			expect(ids(doc.components)).toEqual({ "root", "child", "grand", "other" })
			Ops.moveComponent(doc, "grand", -5)
			expect(ids(doc.components)).toEqual({ "grand", "root", "child", "other" })
			expectValid(doc)
		end)

		T.it("sets timing with clamping", function()
			local doc = hierarchyDoc()
			Ops.setTiming(doc, "other", 0.25, 1.5)
			expect(find(doc, "other").startTime).toBe(0.25)
			expect(find(doc, "other").duration).toBe(1.5)
			Ops.setTiming(doc, "other", -1, nil)
			expect(find(doc, "other").startTime).toBe(0)
			expect(find(doc, "other").duration).toBe(1.5)
			Ops.setTiming(doc, "other", nil, -2)
			expect(find(doc, "other").duration).toBe(Ops.MIN_DURATION)
			Ops.setTiming(doc, "other", 0.1 + 0.2, nil)
			expect(find(doc, "other").startTime).toBe(0.3)
			expect(function()
				Ops.setTiming(doc, "other", math.huge, nil)
			end).toThrow("finite")
			expectValid(doc)
		end)

		T.it("sets and removes transform fields", function()
			local doc = hierarchyDoc()
			Ops.setTransform(doc, "other", "position", { 1, 2, 3 })
			Ops.setTransform(doc, "other", "rotation", 5)
			Ops.setTransform(doc, "other", "scale", -2)
			expect(find(doc, "other").transform).toEqual({ position = { 1, 2, 3 }, rotation = { 5, 5, 5 }, scale = 0 })
			Ops.setTransform(doc, "other", "position", nil)
			Ops.setTransform(doc, "other", "rotation", Json.NULL)
			Ops.setTransform(doc, "other", "scale", nil)
			expect(find(doc, "other").transform).toBeNil()
			Ops.setTransform(doc, "other", "scale", nil) -- no transform at all: no-op
			expect(find(doc, "other").transform).toBeNil()
			expect(function()
				Ops.setTransform(doc, "other", "size", 1)
			end).toThrow("position, rotation or scale")
			expect(function()
				Ops.setTransform(doc, "other", "position", "up")
			end).toThrow("position")
		end)

		T.it("sets phase, minQuality and notes", function()
			local doc = hierarchyDoc()
			Ops.setComponentField(doc, { "root", "other" }, "phase", "impact")
			Ops.setComponentField(doc, { "other" }, "minQuality", "Medium")
			Ops.setComponentField(doc, { "other" }, "notes", "hello")
			expect(find(doc, "root").phase).toBe("impact")
			expect(find(doc, "other").minQuality).toBe("Medium")
			expect(find(doc, "other").notes).toBe("hello")
			expectValid(doc)
			Ops.setComponentField(doc, { "other" }, "phase", nil)
			expect(find(doc, "other").phase).toBeNil()
			expect(function()
				Ops.setComponentField(doc, { "other" }, "phase", "boom")
			end).toThrow("phase must be one of")
			expect(function()
				Ops.setComponentField(doc, { "other" }, "type", "part")
			end).toThrow("unknown field")
			expect(function()
				Ops.setComponentField(doc, { "other" }, "type", nil)
			end).toThrow("unknown field")
		end)
	end)

	T.describe("Ops properties", function()
		T.it("sets canonical values on several components and resets them", function()
			local doc = hierarchyDoc()
			Ops.addComponent(doc, "part", { name = "Second" })
			Ops.setProperty(doc, { "other", "second" }, "color", { 255, 0, 0 })
			Ops.setProperty(doc, { "other" }, "transparency", 5)
			expect(find(doc, "other").properties).toEqual({ color = "#FF0000", transparency = 1 })
			expect(find(doc, "second").properties).toEqual({ color = "#FF0000" })
			Ops.resetProperty(doc, { "second" }, "color")
			expect(find(doc, "second").properties).toBeNil()
			Ops.resetProperty(doc, { "second" }, "color") -- nothing to reset
			expect(find(doc, "second").properties).toBeNil()
			Ops.setProperty(doc, { "other" }, "material", "ForceField")
			expect(find(doc, "other").properties.material).toBe("ForceField")
			expectValid(doc)
		end)

		T.it("validates names, values and references before changing anything", function()
			local doc = hierarchyDoc()
			expect(function()
				Ops.setProperty(doc, { "other", "root" }, "color", "#FFFFFF")
			end).toThrow('group has no property "color"')
			expect(find(doc, "other").properties).toBeNil()
			expect(function()
				Ops.setProperty(doc, { "other" }, "material", "Lava")
			end).toThrow("material")
			expect(function()
				Ops.setProperty(doc, { "other" }, "color", "$nope")
			end).toThrow("does not exist")
			expect(function()
				Ops.resetProperty(doc, { "other" }, "bogus")
			end).toThrow("no property")
		end)

		T.it("normalises easing-valued string properties", function()
			local doc = newDoc()
			Ops.addComponent(doc, "shockwave")
			Ops.setProperty(doc, { "shockwave" }, "expandEasing", "Quad.Out")
			expect(find(doc, "shockwave").properties.expandEasing).toBe("Quad")
			expect(function()
				Ops.setProperty(doc, { "shockwave" }, "fadeEasing", "Wobble")
			end).toThrow("fadeEasing")
		end)

		T.it("writes into documents decoded from JSON (empty objects are sentinels)", function()
			local ok, doc = Json.decode([[{"schemaVersion":1,"id":"a","name":"A","duration":2,"components":[
				{"id":"p","name":"P","type":"part","properties":{},"transform":{},"tracks":{},"events":{}}]}]])
			assert(ok, "fixture decodes")
			expectValid(doc)
			Ops.setProperty(doc, { "p" }, "transparency", 0.5)
			Ops.setTransform(doc, "p", "scale", 2)
			Ops.addKeyframe(doc, "p", "transparency", 0, 1)
			Ops.addEvent(doc, "p", "fire", 0.1, { name = "Hit" })
			local p = find(doc, "p")
			expect(p.properties).toEqual({ transparency = 0.5 })
			expect(p.transform).toEqual({ scale = 2 })
			expect(#p.tracks).toBe(1)
			expect(#p.events).toBe(1)
			expectValid(doc)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- Keyframes
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("Ops keyframes", function()
		T.it("adds keyframes sorted into one track per channel", function()
			local doc = hierarchyDoc()
			local a = Ops.addKeyframe(doc, "other", "transparency", 1, 0.5, "Quad.Out")
			local b = Ops.addKeyframe(doc, "other", "transparency", 0, 0)
			local c = Ops.addKeyframe(doc, "other", "transparency", 0.5, 2, "Linear")
			expect(a).toEqual({ trackId = "other-transparency", index = 1 })
			expect(b).toEqual({ trackId = "other-transparency", index = 1 })
			expect(c).toEqual({ trackId = "other-transparency", index = 2 })
			local track = find(doc, "other").tracks[1]
			expect(times(track)).toEqual({ 0, 0.5, 1 })
			expect(track.keyframes[2]).toEqual({ time = 0.5, value = 1 }) -- clamped, Linear implicit
			expect(track.keyframes[3].easing).toBe("Quad")
			-- same time: value replaced, easing kept unless given
			local d = Ops.addKeyframe(doc, "other", "transparency", 1, 0.25)
			expect(d.index).toBe(3)
			expect(track.keyframes[3]).toEqual({ time = 1, value = 0.25, easing = "Quad" })
			Ops.addKeyframe(doc, "other", "position", 0, { 1, 2, 3 })
			expect(#find(doc, "other").tracks).toBe(2)
			expect(Ops.addKeyframe(doc, "other", "transparency", -1, 0).index).toBe(1)
			expect(#track.keyframes).toBe(3)
			expectValid(doc)
		end)

		T.it("uses the existing track (first enabled) and unique track ids across the effect", function()
			local doc = newDoc()
			Ops.addComponent(doc, "part", { name = "A" })
			Ops.addComponent(doc, "part", { name = "A-transparency" })
			Ops.addKeyframe(doc, "a", "transparency", 0, 1)
			-- "a-transparency" is taken by the component, so the track id gets a counter
			expect(find(doc, "a").tracks[1].id).toBe("a-transparency-2")
			local ref = Ops.addKeyframe(doc, "a", "color", 0, "#00FF00")
			expect(ref.trackId).toBe("a-color")
			expectValid(doc)
		end)

		T.it("rejects unknown channels, bad values and the keyframe limit", function()
			local doc = hierarchyDoc()
			expect(function()
				Ops.addKeyframe(doc, "other", "rate", 0, 1)
			end).toThrow('part has no animatable channel "rate"')
			expect(function()
				Ops.addKeyframe(doc, "other", "position", 0, "up")
			end).toThrow("position")
			expect(function()
				Ops.addKeyframe(doc, "other", "transparency", 0, 1, "Bogus")
			end).toThrow("easing")
			expect(function()
				Ops.addKeyframe(doc, "missing", "transparency", 0, 1)
			end).toThrow("unknown component id")
			for i = 1, Constants.MAX_KEYFRAMES_PER_TRACK do
				Ops.addKeyframe(doc, "other", "transparency", i / 100, 0)
			end
			expect(function()
				Ops.addKeyframe(doc, "other", "transparency", 99, 0)
			end).toThrow("limit")
			Ops.addKeyframe(doc, "other", "transparency", 0.01, 1) -- replacing is still fine
			expectValid(doc)
		end)

		T.it("moves keyframes past each other and returns re-sorted refs", function()
			local doc = newDoc()
			Ops.addComponent(doc, "part", { name = "P" })
			for i, t in { 0, 0.5, 1 } do
				Ops.addKeyframe(doc, "p", "transparency", t, i / 10)
			end
			local track = "p-transparency"
			local refs = Ops.moveKeyframes(doc, { { component = "p", track = track, index = 1 } }, 0.75)
			expect(refs).toEqual({ { component = "p", track = track, index = 2 } })
			local keys = find(doc, "p").tracks[1].keyframes
			expect(times(find(doc, "p").tracks[1])).toEqual({ 0.5, 0.75, 1 })
			expect(keys[2].value).toBe(0.1)
			-- move two keys left past the first one; clamped at 0
			refs = Ops.moveKeyframes(doc, {
				{ component = "p", track = track, index = 3 },
				{ component = "p", track = track, index = 2 },
			}, -2)
			expect(times(find(doc, "p").tracks[1])).toEqual({ 0, 0, 0.5 })
			expect(refs).toEqual({
				{ component = "p", track = track, index = 2 },
				{ component = "p", track = track, index = 1 },
			})
			expect(keys[1].value).toBe(0.1) -- equal times keep their previous order (stable)
			expect(keys[2].value).toBe(0.3)
			-- the same key twice moves once
			refs = Ops.moveKeyframes(doc, {
				{ component = "p", track = track, index = 3 },
				{ component = "p", track = track, index = 3 },
			}, 0.25)
			expect(times(find(doc, "p").tracks[1])).toEqual({ 0, 0, 0.75 })
			expect(refs[1]).toEqual(refs[2])
			expect(function()
				Ops.moveKeyframes(doc, { { component = "p", track = track, index = 9 } }, 1)
			end).toThrow("has no keyframe 9")
			expect(function()
				Ops.moveKeyframes(doc, { { component = "p", track = "nope", index = 1 } }, 1)
			end).toThrow('has no track "nope"')
			expect(function()
				Ops.moveKeyframes(doc, {}, 0 / 0)
			end).toThrow("finite")
			expectValid(doc)
		end)

		T.it("sets keyframe fields and returns the new ref", function()
			local doc = newDoc()
			Ops.addComponent(doc, "part", { name = "P" })
			Ops.addKeyframe(doc, "p", "transparency", 0, 0)
			Ops.addKeyframe(doc, "p", "transparency", 1, 1, "Back.In")
			local ref = { component = "p", track = "p-transparency", index = 1 }
			local moved = Ops.setKeyframe(doc, ref, { time = 2, value = -1, easing = "Sine.InOut" })
			expect(moved).toEqual({ component = "p", track = "p-transparency", index = 2 })
			local keys = find(doc, "p").tracks[1].keyframes
			expect(keys[2]).toEqual({ time = 2, value = 0, easing = "Sine.InOut" })
			Ops.setKeyframe(doc, moved, { easing = "Linear" })
			expect(keys[2].easing).toBeNil()
			Ops.setKeyframe(doc, { component = "p", track = "p-transparency", index = 1 }, { easing = Json.NULL })
			expect(keys[1].easing).toBeNil()
			expect(function()
				Ops.setKeyframe(doc, moved, { speed = 1 } :: any)
			end).toThrow("unknown keyframe field")
			expect(function()
				Ops.setKeyframe(doc, moved, { value = { 1, 2 } })
			end).toThrow("transparency")
			expectValid(doc)
		end)

		T.it("removes keyframes and empty tracks", function()
			local doc = hierarchyDoc()
			local track = "child-rate"
			Ops.removeKeyframes(doc, { { component = "child", track = track, index = 2 } })
			expect(times(find(doc, "child").tracks[1])).toEqual({ 0 })
			Ops.removeKeyframes(doc, {
				{ component = "child", track = track, index = 1 },
				{ component = "child", track = track, index = 1 },
			})
			expect(find(doc, "child").tracks).toBeNil()
			expectValid(doc)
			expect(function()
				Ops.removeKeyframes(doc, { { component = "child", track = track, index = 1 } })
			end).toThrow("has no track")
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- Events and markers
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("Ops events", function()
		T.it("adds events with defaults, sorted by time", function()
			local doc = hierarchyDoc()
			local e1 = Ops.addEvent(doc, "child", "emit", 0.2)
			local e2 = Ops.addEvent(doc, "child", "fire", 0.1, { name = "Burst" })
			local e3 = Ops.addEvent(doc, "child", "fire", 0.3)
			local e4 = Ops.addEvent(doc, "child", "clear", 0.4, { count = 3, name = "Ignored" })
			expect({ e1, e2, e3, e4 }).toEqual({ "child-emit-2", "child-fire", "child-fire-2", "child-clear" })
			local events = find(doc, "child").events
			expect(ids(events)).toEqual({ "child-fire", "child-emit-2", "child-fire-2", "child-clear", "child-emit" })
			expect(events[2]).toEqual({
				id = "child-emit-2",
				time = 0.2,
				action = "emit",
				count = Ops.DEFAULT_EMIT_COUNT,
			})
			expect(events[3].name).toBe(Ops.DEFAULT_EVENT_NAME)
			expect(events[4]).toEqual({ id = "child-clear", time = 0.4, action = "clear" })
			expectValid(doc)
			expect(function()
				Ops.addEvent(doc, "other", "emit", 0)
			end).toThrow('part does not support the action "emit"')
			expect(function()
				Ops.addEvent(doc, "child", "fire", 0, { name = "bad name" })
			end).toThrow("event name")
			expect(function()
				Ops.addEvent(doc, "child", "emit", 0, { colour = 1 })
			end).toThrow("unknown event field")
			Ops.addEvent(doc, "child", "emit", 0, { count = 1e9 })
			expect(find(doc, "child").events[1].count).toBe(Constants.MAX_EMIT_COUNT)
		end)

		T.it("moves, edits and removes events", function()
			local doc = hierarchyDoc()
			Ops.addEvent(doc, "child", "fire", 0.25, { name = "A" })
			Ops.moveEvent(doc, { component = "child", event = "child-emit" }, -1)
			local events = find(doc, "child").events
			expect(ids(events)).toEqual({ "child-emit", "child-fire" })
			expect(events[1].time).toBe(0)
			Ops.setEvent(doc, { component = "child", event = "child-emit" }, { count = 7, time = 0.75 })
			expect(ids(events)).toEqual({ "child-fire", "child-emit" })
			expect(events[2].count).toBe(7)
			expect(function()
				Ops.setEvent(doc, { component = "child", event = "child-fire" }, { count = 3 })
			end).toThrow("has no count")
			Ops.removeEvents(doc, { { component = "child", event = "child-fire" } })
			expect(ids(find(doc, "child").events)).toEqual({ "child-emit" })
			Ops.removeEvents(doc, { { component = "child", event = "child-emit" } })
			expect(find(doc, "child").events).toBeNil()
			expect(function()
				Ops.removeEvents(doc, { { component = "child", event = "child-emit" } })
			end).toThrow('has no event "child-emit"')
			expectValid(doc)
		end)

		T.it("enforces the event limit", function()
			local doc = newDoc()
			Ops.addComponent(doc, "sound")
			for i = 1, Constants.MAX_EVENTS_PER_COMPONENT do
				Ops.addEvent(doc, "sound", "play", i / 1000)
			end
			expect(function()
				Ops.addEvent(doc, "sound", "play", 0)
			end).toThrow("limit")
		end)
	end)

	T.describe("Ops markers", function()
		T.it("adds sorted markers with label slugs", function()
			local doc = newDoc()
			local a = Ops.addMarker(doc, 1, "Impact", { phase = "impact", event = "Impact", color = "#f00" })
			local b = Ops.addMarker(doc, 0.5, "Impact")
			local c = Ops.addMarker(doc, -1, "Start!")
			expect({ a, b, c }).toEqual({ "impact", "impact-2", "start" })
			expect(ids(doc.markers)).toEqual({ "start", "impact-2", "impact" })
			expect(doc.markers[3]).toEqual({
				id = "impact",
				time = 1,
				label = "Impact",
				phase = "impact",
				event = "Impact",
				color = "#FF0000",
			})
			expectValid(doc)
			expect(function()
				Ops.addMarker(doc, 0, "")
			end).toThrow("label must not be empty")
			expect(function()
				Ops.addMarker(doc, 0, "X", { event = "not valid" })
			end).toThrow("event name")
			expect(function()
				Ops.addMarker(doc, 0, "X", { time = 1 })
			end).toThrow("unknown marker field")
			expect(function()
				Ops.addMarker(doc, 0, "X", { color = "$none" })
			end).toThrow("does not exist")
		end)

		T.it("sets fields, re-sorts and removes optional fields with Json.NULL", function()
			local doc = newDoc()
			Ops.addMarker(doc, 0.2, "A", { phase = "charge", event = "Go" })
			Ops.addMarker(doc, 0.4, "B")
			Ops.setMarker(doc, "a", { time = 1.5, label = "Late", phase = Json.NULL, event = "" })
			expect(ids(doc.markers)).toEqual({ "b", "a" })
			expect(doc.markers[2]).toEqual({ id = "a", time = 1.5, label = "Late" })
			expect(function()
				Ops.setMarker(doc, "zzz", {})
			end).toThrow("unknown marker id")
			expectValid(doc)
		end)

		T.it("removing a marker clears OnMarker references", function()
			local doc = newDoc()
			Ops.addMarker(doc, 0.5, "Hit")
			Ops.addNode(doc, "OnMarker", nil, { marker = "hit" })
			Ops.addNode(doc, "OnMarker", nil)
			local affected = Ops.removeMarker(doc, "hit")
			expect(affected).toEqual({ "onmarker" })
			expect(node(doc, "onmarker").params).toEqual({ marker = "" })
			expect(doc.markers).toBeNil()
			expectValid(doc)
			expect(function()
				Ops.removeMarker(doc, "hit")
			end).toThrow("unknown marker id")
		end)

		T.it("enforces the marker limit", function()
			local doc = newDoc()
			for i = 1, Constants.MAX_MARKERS do
				Ops.addMarker(doc, i / 100, "M")
			end
			expect(function()
				Ops.addMarker(doc, 0, "M")
			end).toThrow("at most " .. Constants.MAX_MARKERS .. " markers")
			expectValid(doc)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- Graph
	-- ─────────────────────────────────────────────────────────────────────────

	-- particles "sparks", beam "slash", markers "go"; nodes onplay, emit, delay, number, component
	local function graphDoc(): any
		local doc = newDoc()
		Ops.addComponent(doc, "particles", { name = "Sparks" })
		Ops.addComponent(doc, "beam", { name = "Slash" })
		Ops.addMarker(doc, 0.5, "Go")
		Ops.addNode(doc, "OnPlay", { 0, 0 })
		Ops.addNode(doc, "Emit", { 200, 0 }, { target = "sparks" })
		Ops.addNode(doc, "Delay", { 400, 0 })
		Ops.addNode(doc, "Number", { 0, 100 }, { value = 3 })
		Ops.addNode(doc, "Component", { 0, 200 }, { component = "sparks" })
		return doc
	end

	T.describe("Ops graph nodes", function()
		T.it("adds, moves and removes nodes", function()
			local doc = graphDoc()
			expect(ids(doc.graph.nodes)).toEqual({ "onplay", "emit", "delay", "number", "component" })
			expect(node(doc, "emit")).toEqual({
				id = "emit",
				type = "Emit",
				position = { 200, 0 },
				params = { target = "sparks" },
			})
			expect(Ops.addNode(doc, "Emit", nil)).toBe("emit-2")
			expect(node(doc, "emit-2").position).toBeNil()
			Ops.moveNodes(doc, { "emit", "emit-2", "emit" }, { 10, -5 })
			expect(node(doc, "emit").position).toEqual({ 210, -5 })
			expect(node(doc, "emit-2").position).toEqual({ 10, -5 })
			Ops.connect(doc, "onplay.out", "emit.in")
			Ops.connect(doc, "emit.out", "delay.in")
			Ops.removeNodes(doc, { "emit" })
			expect(links(doc)).toEqual({})
			expect(ids(doc.graph.nodes)).toEqual({ "onplay", "delay", "number", "component", "emit-2" })
			expectValid(doc)
			Ops.removeNodes(doc, { "onplay", "delay", "number", "component", "emit-2" })
			expect(doc.graph).toBeNil()
			expect(function()
				Ops.addNode(doc, "Teleport", nil)
			end).toThrow('unknown node type "Teleport"')
			expect(function()
				Ops.removeNodes(doc, { "nope" })
			end).toThrow("unknown node id")
			expect(function()
				Ops.addNode(doc, "Number", nil, { bogus = 1 })
			end).toThrow("has no param")
		end)

		T.it("validates params", function()
			local doc = graphDoc()
			Ops.setNodeParam(doc, "delay", "seconds", 999)
			expect(node(doc, "delay").params.seconds).toBe(Constants.MAX_DURATION)
			Ops.setNodeParam(doc, "delay", "seconds", nil)
			expect(node(doc, "delay").params).toBeNil()
			expect(function()
				Ops.setNodeParam(doc, "emit", "target", "slash")
			end).toThrow("is a beam, expected particles")
			expect(function()
				Ops.setNodeParam(doc, "emit", "target", "missing")
			end).toThrow("does not exist")
			expect(function()
				Ops.setNodeParam(doc, "delay", "nope", 1)
			end).toThrow("has no param")
			expect(function()
				Ops.setNodeParam(doc, "missing", "seconds", 1)
			end).toThrow("unknown node id")
			local onMarker = Ops.addNode(doc, "OnMarker", nil)
			expect(function()
				Ops.setNodeParam(doc, onMarker, "marker", "nope")
			end).toThrow('marker "nope" does not exist')
			Ops.setNodeParam(doc, onMarker, "marker", "go")
			local onEvent = Ops.addNode(doc, "OnEvent", nil)
			expect(function()
				Ops.setNodeParam(doc, onEvent, "name", "1bad")
			end).toThrow("not a valid event name")
			local tween =
				Ops.addNode(doc, "Tween", nil, { target = "slash", channel = "width0", value = 3, easing = "Quad.Out" })
			expect(node(doc, tween).params).toEqual({ target = "slash", channel = "width0", value = 3, easing = "Quad" })
			expect(function()
				Ops.setNodeParam(doc, tween, "channel", "rate")
			end).toThrow('beam has no channel "rate"')
			expect(function()
				Ops.setNodeParam(doc, tween, "value", "#FFFFFF")
			end).toThrow("param value")
			local color = Ops.addNode(doc, "Color", nil)
			expect(function()
				Ops.setNodeParam(doc, color, "value", "$nope")
			end).toThrow("does not exist")
			expectValid(doc)
		end)

		T.it("repairs knock-on effects: inactive variadic outputs, retargeted channels and values", function()
			local doc = graphDoc()
			local sequence = Ops.addNode(doc, "Sequence", nil, { count = 4 })
			local tween = Ops.addNode(doc, "Tween", nil, { target = "sparks", channel = "rate", value = 50 })
			local tween2 = Ops.addNode(doc, "Tween", nil, { channel = "rate" })
			Ops.connect(doc, "onplay.out", sequence .. ".in")
			Ops.connect(doc, sequence .. ".then1", "emit.in")
			Ops.connect(doc, sequence .. ".then3", tween .. ".in")
			Ops.connect(doc, sequence .. ".then4", tween2 .. ".in")
			Ops.connect(doc, "component.component", tween2 .. ".target")
			Ops.connect(doc, "number.value", tween2 .. ".value")
			expectValid(doc)
			-- lowering the count drops the links from then3/then4
			local affected = Ops.setNodeParam(doc, sequence, "count", 2)
			expect(affected).toEqual({ sequence, tween, tween2 })
			expect(links(doc)).toEqual({
				"onplay.out>" .. sequence .. ".in",
				sequence .. ".then1>emit.in",
				"component.component>" .. tween2 .. ".target",
				"number.value>" .. tween2 .. ".value",
			})
			-- retarget: the channel "rate" does not exist on a beam; without a channel any value kind is fine
			affected = Ops.setNodeParam(doc, tween, "target", "slash")
			expect(affected).toEqual({ tween })
			expect(node(doc, tween).params).toEqual({ target = "slash", value = 50 })
			-- a new channel of another kind: the value no longer fits and is reset
			Ops.setNodeParam(doc, tween, "channel", "width0")
			expect(node(doc, tween).params).toEqual({ target = "slash", channel = "width0", value = 50 })
			affected = Ops.setNodeParam(doc, tween, "channel", "tint")
			expect(affected).toEqual({ tween })
			expect(node(doc, tween).params).toEqual({ target = "slash", channel = "tint" })
			-- retargeting through the Component node: tween2 loses its channel; the number link stays (value is any)
			affected = Ops.setNodeParam(doc, "component", "component", "slash")
			expect(affected).toEqual({ tween2 })
			expect(node(doc, tween2).params).toBeNil()
			expectValid(doc)
		end)
	end)

	T.describe("Ops.repairGraph", function()
		T.it("removes erroneous links and resets erroneous params of a hand-edited graph", function()
			local doc = graphDoc()
			doc.graph.links = {
				{ from = "onplay.out", to = "emit.in" },
				{ from = "onplay.out", to = "delay.in" }, -- second link from one exec output
				{ from = "emit.nope", to = "delay.in" }, -- unknown pin
				{ from = "number.value", to = "emit.in" }, -- kind mismatch
				{ from = "number.value", to = "emit.count" },
			}
			node(doc, "emit").params = { target = "slash", count = 3 } -- wrong component type
			local tween = Ops.addNode(doc, "Tween", nil)
			node(doc, tween).params = { target = "sparks", channel = "warp", easing = "Nope" }
			expect(#errorLines(doc) > 0).toBe(true)
			local affected = Ops.repairGraph(doc)
			expect(affected).toEqual({ "onplay", "emit", "delay", "number", tween })
			expect(links(doc)).toEqual({ "onplay.out>emit.in", "number.value>emit.count" })
			expect(node(doc, "emit").params).toEqual({ count = 3 })
			expect(node(doc, tween).params).toEqual({ target = "sparks" })
			expectValid(doc)
			expect(Ops.repairGraph(doc)).toEqual({})
			expect(Ops.repairGraph(newDoc())).toEqual({})
		end)

		T.it("enforces the node limit", function()
			local doc = newDoc()
			for _ = 1, Constants.MAX_GRAPH_NODES do
				Ops.addNode(doc, "Number", nil)
			end
			expect(function()
				Ops.addNode(doc, "Number", nil)
			end).toThrow("at most " .. Constants.MAX_GRAPH_NODES .. " nodes")
			expectValid(doc)
		end)
	end)

	T.describe("Ops.connect / disconnect", function()
		T.it("connects valid links", function()
			local doc = graphDoc()
			expect(Ops.connect(doc, "onplay.out", "emit.in")).toBe(true)
			expect(Ops.connect(doc, "number.value", "emit.count")).toBe(true)
			expect(Ops.connect(doc, "component.component", "emit.target")).toBe(true)
			expect(links(doc)).toEqual({
				"onplay.out>emit.in",
				"number.value>emit.count",
				"component.component>emit.target",
			})
			expectValid(doc)
		end)

		T.it("returns Graph.canConnect's reason on rejection", function()
			local doc = graphDoc()
			Ops.connect(doc, "onplay.out", "emit.in")
			Ops.connect(doc, "number.value", "emit.count")
			local cases = {
				{ "number.value", "emit.in", "graph.link_kind", "cannot connect" },
				{ "emit.in", "onplay.out", "graph.link_direction", "reversed" },
				{ "onplay.out", "delay.in", "graph.output_multiple", "already connected" },
				{ "number.value", "emit.count", "graph.link_duplicate", "already connected" },
				{ "component.component", "emit.count", "graph.link_kind", "cannot connect" },
				{ "emit.out", "emit.in", "graph.cycle", "itself" },
				{ "onplay.nothing", "emit.in", "graph.link_pin", "no pin" },
			}
			for _, case in cases do
				local ok, reason, code = Ops.connect(doc, case[1], case[2])
				expect(ok).toBe(false)
				expect(code).toBe(case[3])
				expect(reason).toContain(case[4])
			end
			local number2 = Ops.addNode(doc, "Number", nil)
			local ok, reason, code = Ops.connect(doc, number2 .. ".value", "emit.count")
			expect(ok).toBe(false)
			expect(code).toBe("graph.input_multiple")
			expect(reason).toContain("already connected")
			-- cycle through two nodes
			Ops.connect(doc, "emit.out", "delay.in")
			ok, reason, code = Ops.connect(doc, "delay.out", "emit.in")
			expect(ok).toBe(false)
			expect(code).toBe("graph.cycle")
			expect(reason).toContain("cycle")
			-- a Component of the wrong type for Emit.target
			local beamNode = Ops.addNode(doc, "Component", nil, { component = "slash" })
			ok, reason, code = Ops.connect(doc, beamNode .. ".component", "emit.target")
			expect(ok).toBe(false)
			expect(code).toBe("graph.component_type")
			expect(reason).toContain("particles")
			expect(#links(doc)).toBe(3) -- nothing was added
			expectValid(doc)
		end)

		T.it("replaces an occupied input or exec output on request", function()
			local doc = graphDoc()
			Ops.connect(doc, "onplay.out", "emit.in")
			Ops.connect(doc, "number.value", "emit.count")
			local number2 = Ops.addNode(doc, "Number", nil)
			expect(Ops.connect(doc, number2 .. ".value", "emit.count", { replace = true })).toBe(true)
			expect(Ops.connect(doc, "onplay.out", "delay.in", { replace = true })).toBe(true)
			expect(links(doc)).toEqual({ number2 .. ".value>emit.count", "onplay.out>delay.in" })
			-- replace does not override other rejections
			local ok, _, code = Ops.connect(doc, "number.value", "emit.in", { replace = true })
			expect(ok).toBe(false)
			expect(code).toBe("graph.link_kind")
			expectValid(doc)
		end)

		T.it("treats malformed refs and unknown nodes as programmer errors", function()
			local doc = graphDoc()
			expect(function()
				Ops.connect(doc, "ghost.out", "emit.in")
			end).toThrow('Ops.connect: unknown node id "ghost"')
			expect(function()
				Ops.connect(doc, "onplay", "emit.in")
			end).toThrow('"nodeId.pinName"')
			expect(function()
				Ops.connect(newDoc(), "a.out", "b.in")
			end).toThrow("unknown node id")
			expect(function()
				Ops.disconnect(doc, nil, "ghost.in")
			end).toThrow("unknown node id")
		end)

		T.it("disconnects links into a pin", function()
			local doc = graphDoc()
			local onPlay2 = Ops.addNode(doc, "OnPlay", nil)
			Ops.connect(doc, "onplay.out", "emit.in")
			Ops.connect(doc, onPlay2 .. ".out", "emit.in")
			Ops.connect(doc, "number.value", "emit.count")
			expect(Ops.disconnect(doc, "onplay.out", "emit.in")).toBe(1)
			expect(links(doc)).toEqual({ onPlay2 .. ".out>emit.in", "number.value>emit.count" })
			expect(Ops.disconnect(doc, nil, "emit.in")).toBe(1)
			expect(Ops.disconnect(doc, nil, "emit.in")).toBe(0)
			expect(links(doc)).toEqual({ "number.value>emit.count" })
			expectValid(doc)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- Clipboard
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("Ops component clipboard", function()
		T.it("copies subtrees as plain JSON data with relative start times", function()
			local doc = hierarchyDoc()
			Ops.setTiming(doc, "root", 0.5, nil)
			Ops.setTiming(doc, "child", 0.75, nil)
			Ops.setTiming(doc, "grand", 1, nil)
			local payload = Ops.copyComponents(doc, { "child", "root" })
			expect(payload.kind).toBe("components")
			expect(payload.version).toBe(1)
			expect(payload.origin).toBe(0.5)
			expect(payload.roots).toEqual({ "root" })
			expect(ids(payload.components)).toEqual({ "root", "child", "grand" })
			expect(payload.components[1].startTime).toBe(0)
			expect(payload.components[2].startTime).toBe(0.25)
			expect(payload.components[1].parent).toBeNil()
			expect(roundTrip(payload)).toEqual(payload)
			-- the copy is detached from the document
			payload.components[1].name = "Changed"
			expect(find(doc, "root").name).toBe("Root")
		end)

		T.it("pastes with fresh ids into the same document", function()
			local doc = hierarchyDoc()
			local payload = roundTrip(Ops.copyComponents(doc, { "root" }))
			local roots = Ops.pasteComponents(doc, payload)
			expect(roots).toEqual({ "root-2" })
			expect(find(doc, "root-2").name).toBe("Root")
			expect(find(doc, "child-2").parent).toBe("root-2")
			expect(find(doc, "grand-2").parent).toBe("child-2")
			expect(Ops.pasteComponents(doc, payload, "")[1]).toBe("root-3")
			expect(find(doc, "root-3").parent).toBeNil()
			Ops.removeComponents(doc, { "root-3" })
			local again = Ops.pasteComponents(doc, payload, "other", { atTime = 1 })
			expect(again).toEqual({ "root-3" })
			expect(find(doc, "root-3").parent).toBe("other")
			expect(find(doc, "root-3").startTime).toBe(1)
			local seen = {}
			for id in Ids.collect(doc) do
				expect(seen[id]).toBeNil()
				seen[id] = true
			end
			expectValid(doc)
		end)

		T.it("pastes into another document, carrying palette colours and dropping dangling references", function()
			local source = Ops.newEffect("Source", { duration = 4 })
			Ops.setEffectField(source, "palette", { accent = "#123456", spare = "#FFFFFF" })
			Ops.addComponent(source, "group", { name = "Rig", startTime = 2 })
			Ops.addComponent(source, "part", {
				name = "Core",
				parent = "rig",
				startTime = 3,
				duration = 1,
				properties = { color = "$accent" },
			})
			Ops.addKeyframe(source, "core", "color", 0, "$accent")
			local payload = roundTrip(Ops.copyComponents(source, { "rig" }))
			expect(payload.palette).toEqual({ accent = "#123456" })
			local target = hierarchyDoc()
			Ops.addComponent(target, "group", { name = "Rig" }) -- id collision: pasted rig becomes rig-2
			local roots = Ops.pasteComponents(target, payload)
			expect(roots).toEqual({ "rig-2" })
			expect(find(target, "rig-2").startTime).toBe(2)
			expect(find(target, "core").startTime).toBe(3)
			expect(find(target, "core").parent).toBe("rig-2")
			expect(target.palette).toEqual({ accent = "#123456" })
			expectValid(target) -- the component ends after the shorter effect: a warning, not an error
			-- a document that already has the key keeps its own colour
			local other = Ops.newEffect("Other")
			Ops.setEffectField(other, "palette", { accent = "#FF0000" })
			Ops.pasteComponents(other, payload, nil, { atTime = 0 })
			expect(other.palette).toEqual({ accent = "#FF0000" })
			expect(find(other, "rig").startTime).toBe(0)
			expect(find(other, "core").startTime).toBe(1)
			expectValid(other)
			-- a payload without the colour cannot be pasted into a document lacking it
			payload.palette = nil
			expect(function()
				Ops.pasteComponents(Ops.newEffect("Bare"), payload)
			end).toThrow('"$accent" is neither in the document nor in the clipboard')
		end)

		T.it("rejects foreign payloads", function()
			local doc = hierarchyDoc()
			expect(function()
				Ops.pasteComponents(doc, { kind = "keyframes", version = 1 } :: any)
			end).toThrow("expected a components clipboard payload")
			expect(function()
				Ops.pasteComponents(doc, { kind = "components", version = 99, components = {} } :: any)
			end).toThrow("unsupported clipboard version")
			expect(function()
				Ops.pasteComponents(
					doc,
					{
						kind = "components",
						version = 1,
						origin = 0,
						components = { { id = "x", name = "X", type = "warp" } },
					} :: any
				)
			end).toThrow("unknown type")
			expect(function()
				Ops.pasteComponents(doc, Ops.copyComponents(doc, { "other" }), "missing")
			end).toThrow("unknown component id")
		end)
	end)

	T.describe("Ops keyframe clipboard", function()
		local function keyDoc(): any
			local doc = Ops.newEffect("Keys", { duration = 5 })
			Ops.addComponent(doc, "part", { name = "A", startTime = 1 })
			Ops.addComponent(doc, "part", { name = "B", startTime = 0 })
			Ops.addComponent(doc, "light", { name = "L" })
			Ops.addKeyframe(doc, "a", "transparency", 0.5, 0.2, "Quad.In") -- absolute 1.5
			Ops.addKeyframe(doc, "a", "transparency", 1, 0.8) -- absolute 2
			Ops.addKeyframe(doc, "b", "transparency", 2, 0.4) -- absolute 2
			Ops.addKeyframe(doc, "b", "color", 1, "#00FF00") -- absolute 1
			return doc
		end

		T.it("copies keyframes with times relative to the earliest absolute key", function()
			local doc = keyDoc()
			local payload = Ops.copyKeyframes(doc, {
				{ component = "a", track = "a-transparency", index = 2 },
				{ component = "a", track = "a-transparency", index = 1 },
				{ component = "b", track = "b-transparency", index = 1 },
				{ component = "b", track = "b-transparency", index = 1 },
			})
			expect(payload).toEqual({
				kind = "keyframes",
				version = 1,
				origin = 1.5,
				source = "keys",
				tracks = {
					{
						component = "a",
						channel = "transparency",
						kind = "number",
						keyframes = {
							{ time = 0, value = 0.2, easing = "Quad.In" } :: any,
							{ time = 0.5, value = 0.8 },
						},
					},
					{
						component = "b",
						channel = "transparency",
						kind = "number",
						keyframes = { { time = 0.5, value = 0.4 } },
					},
				},
			})
			expect(roundTrip(payload)).toEqual(payload)
		end)

		T.it("pastes back onto the source components at the playhead", function()
			local doc = keyDoc()
			local payload = roundTrip(Ops.copyKeyframes(doc, {
				{ component = "a", track = "a-transparency", index = 1 },
				{ component = "b", track = "b-transparency", index = 1 },
			}))
			local refs = Ops.pasteKeyframes(doc, payload, 3)
			-- a: absolute 3 -> local 2 ; b: absolute 3.5 -> local 3.5
			expect(refs).toEqual({
				{ component = "a", track = "a-transparency", index = 3 },
				{ component = "b", track = "b-transparency", index = 2 },
			})
			expect(times(find(doc, "a").tracks[1])).toEqual({ 0.5, 1, 2 })
			expect(find(doc, "a").tracks[1].keyframes[3]).toEqual({ time = 2, value = 0.2, easing = "Quad.In" })
			expect(times(find(doc, "b").tracks[1])).toEqual({ 2, 3.5 })
			-- before the component start: clamped to local time 0
			refs = Ops.pasteKeyframes(doc, payload, 0)
			expect(refs[1]).toEqual({ component = "a", track = "a-transparency", index = 1 })
			expect(find(doc, "a").tracks[1].keyframes[1].time).toBe(0)
			expectValid(doc)
		end)

		T.it("pastes onto a target component, merging tracks and skipping missing channels", function()
			local doc = keyDoc()
			local payload = Ops.copyKeyframes(doc, {
				{ component = "a", track = "a-transparency", index = 1 },
				{ component = "b", track = "b-color", index = 1 },
				{ component = "b", track = "b-transparency", index = 1 },
			})
			-- origin = 1 (b.color at absolute 1); a.transparency rel 0.5, b.transparency rel 1
			local refs = Ops.pasteKeyframes(doc, payload, 0, "b")
			expect(refs).toEqual({
				{ component = "b", track = "b-transparency", index = 1 },
				{ component = "b", track = "b-color", index = 1 },
				{ component = "b", track = "b-transparency", index = 2 },
			})
			expect(times(find(doc, "b").tracks[1])).toEqual({ 0.5, 1, 2 })
			-- the light has color but no transparency channel
			refs = Ops.pasteKeyframes(doc, payload, 0, "l")
			expect(refs).toEqual({ { component = "l", track = "l-color", index = 1 } })
			expect(#find(doc, "l").tracks).toBe(1)
			expectValid(doc)
			local onlyTransparency =
				Ops.copyKeyframes(doc, { { component = "a", track = "a-transparency", index = 1 } })
			expect(function()
				Ops.pasteKeyframes(doc, onlyTransparency, 0, "l")
			end).toThrow("none of the copied channels")
		end)

		T.it("pastes into another document with palette colours", function()
			local doc = keyDoc()
			Ops.setEffectField(doc, "palette", { glow = "#ABCDEF" })
			Ops.addKeyframe(doc, "b", "color", 1.5, "$glow")
			local payload = roundTrip(Ops.copyKeyframes(doc, { { component = "b", track = "b-color", index = 2 } }))
			expect(payload.palette).toEqual({ glow = "#ABCDEF" })
			local other = Ops.newEffect("Other")
			Ops.addComponent(other, "part", { name = "Target" })
			expect(function()
				Ops.pasteKeyframes(other, payload, 0)
			end).toThrow("unknown component id")
			local refs = Ops.pasteKeyframes(other, payload, 0.25, "target")
			expect(refs).toEqual({ { component = "target", track = "target-color", index = 1 } })
			expect(find(other, "target").tracks[1].keyframes[1]).toEqual({ time = 0.25, value = "$glow" })
			expect(other.palette).toEqual({ glow = "#ABCDEF" })
			expectValid(other)
			expect(function()
				Ops.pasteKeyframes(other, Ops.copyComponents(other, { "target" }), 0)
			end).toThrow("expected a keyframes clipboard payload")
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- Property-based: random op sequences keep the document valid
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("Ops random sequences", function()
		local SEED = 20261028
		local SEQUENCES = 200
		local STEPS = 30

		local EASINGS: { any } =
			{ "Linear", "Constant", "Quad", "Back.InOut", "Sine.In", "Bounce.Out", { bezier = { 0.2, 0, 0.8, 1 } } }
		local PHASES = Constants.PHASES
		local TYPES = Components.types()
		local NODE_TYPES = {}
		for _, nodeType in NodeTypes.list() do
			table.insert(NODE_TYPES, nodeType.type)
		end

		local function pick(rng: any, list: { any }): any
			return rng:pick(list)
		end

		local function hex(rng: any): string
			return string.format("#%02X%02X%02X", rng:int(0, 255), rng:int(0, 255), rng:int(0, 255))
		end

		local function paletteKeys(doc: any): { string }
			local keys = {}
			if type(doc.palette) == "table" then
				for key in pairs(doc.palette) do
					table.insert(keys, key)
				end
			end
			table.sort(keys)
			return keys
		end

		local function colour(rng: any, doc: any): string
			local keys = paletteKeys(doc)
			if #keys > 0 and rng:next() < 0.3 then
				return "$" .. pick(rng, keys)
			end
			return hex(rng)
		end

		local function number(rng: any, spec: any): number
			local lo = if spec and spec.min then spec.min else -10
			local hi = if spec and spec.max then spec.max else lo + 20
			if hi - lo > 100 then
				hi = lo + 100
			end
			return math.floor(rng:range(lo, hi) * 100 + 0.5) / 100
		end

		local function componentIds(doc: any, allowed: { string }?): { string }
			local out = {}
			for _, c in doc.components do
				if allowed == nil or table.find(allowed, c.type) then
					table.insert(out, c.id)
				end
			end
			return out
		end

		local function valueFor(rng: any, doc: any, kind: string, spec: any): any
			if kind == "number" then
				return number(rng, spec)
			elseif kind == "integer" then
				local lo = math.ceil(if spec and spec.min then spec.min else 0)
				local hi = math.floor(if spec and spec.max then spec.max else lo + 20)
				return rng:int(lo, math.min(hi, lo + 50))
			elseif kind == "boolean" then
				return rng:next() < 0.5
			elseif kind == "string" then
				return pick(rng, { "Linear", "Quad", "Quart.Out", "Back.InOut" })
			elseif kind == "enum" then
				return if spec.enum then pick(rng, spec.enum) else spec.default
			elseif kind == "color3" then
				return colour(rng, doc)
			elseif kind == "vector3" then
				return { number(rng, spec), number(rng, spec), number(rng, spec) }
			elseif kind == "vector2" then
				return { number(rng, spec), number(rng, spec) }
			elseif kind == "numberRange" then
				local a, b = number(rng, spec), number(rng, spec)
				return { math.min(a, b), math.max(a, b) }
			elseif kind == "numberSequence" then
				return { { 0, number(rng, spec) }, { 1, number(rng, spec) } }
			elseif kind == "colorSequence" then
				return { { 0, colour(rng, doc) } :: { any }, { 1, colour(rng, doc) } }
			elseif kind == "asset" then
				return pick(rng, { "", "rbxassetid://123", "rbxasset://textures/particles/sparkles_main.dds" })
			elseif kind == "componentRef" then
				local candidates = componentIds(doc, spec and spec.componentTypes)
				if #candidates == 0 or rng:next() < 0.2 then
					return ""
				end
				return pick(rng, candidates)
			end
			error("no generator for kind " .. kind)
		end

		local function randomComponent(rng: any, doc: any): any?
			if #doc.components == 0 then
				return nil
			end
			return pick(rng, doc.components)
		end

		local function allKeyRefs(doc: any): { any }
			local out = {}
			for _, c in doc.components do
				for _, track in c.tracks or {} do
					for i in track.keyframes do
						table.insert(out, { component = c.id, track = track.id, index = i })
					end
				end
			end
			return out
		end

		local function allEventRefs(doc: any): { any }
			local out = {}
			for _, c in doc.components do
				for _, event in c.events or {} do
					table.insert(out, { component = c.id, event = event.id })
				end
			end
			return out
		end

		local function sample(rng: any, list: { any }, max: number): { any }
			local out = {}
			if #list == 0 then
				return out
			end
			for _ = 1, rng:int(1, max) do
				table.insert(out, pick(rng, list))
			end
			return out
		end

		local function nodes(doc: any): { any }
			return if doc.graph then doc.graph.nodes else {}
		end

		local function randomName(rng: any): string
			local r = rng:next()
			if r < 0.1 then
				return string.rep("Long ", 30)
			elseif r < 0.2 then
				return "Ünïcødé ✦ " .. rng:int(1, 99)
			end
			return pick(rng, { "Core", "Sparks", "Glow", "Ring", "Slash", "Rig" }) .. " " .. rng:int(1, 9)
		end

		-- Value for a node param, following the node's current target / channel.
		local function paramValue(rng: any, doc: any, n: any, spec: any): any
			local nodeType = NodeTypes.get(n.type)
			local special = nodeType.special[spec.name]
			if special == "easing" then
				return pick(rng, EASINGS)
			elseif special == "marker" then
				local markers = {}
				for _, m in doc.markers or {} do
					table.insert(markers, m.id)
				end
				if #markers == 0 or rng:next() < 0.2 then
					return ""
				end
				return pick(rng, markers)
			elseif special == "eventName" then
				return pick(rng, { "", "Hit", "Shake", "Boom_2" })
			elseif special == "channel" then
				local targetId = n.params and n.params.target
				local target = if type(targetId) == "string" then Ops.find(doc, targetId) else nil
				local descriptor = if target then Components.get(target.type) else nil
				if descriptor == nil or rng:next() < 0.2 then
					return pick(rng, { "", "position", "transparency", "rate", "color" })
				end
				return pick(rng, descriptor.channels).name
			elseif special == "channelValue" then
				local resolved = Graph.resolveParamSpec(doc.graph, doc, n.id, spec.name)
				local kind = if resolved and resolved.default ~= nil
					then resolved.kind
					else pick(rng, { "number", "vector3", "color3", "boolean" })
				return valueFor(rng, doc, kind, resolved)
			end
			return valueFor(rng, doc, spec.kind, spec)
		end

		-- Extra weight for graph, marker and event ops (they need earlier ops to have something to work on).
		local REMAP: { [number]: number } = {
			[35] = 29,
			[36] = 29,
			[37] = 24,
			[38] = 24,
			[39] = 24,
			[40] = 29,
			[41] = 29,
			[42] = 29,
			[43] = 31,
			[44] = 22,
			[45] = 26,
			[46] = 20,
		}

		-- One random op: returns (label, fn(doc)) or nil when nothing applies.
		local function randomOp(rng: any, doc: any, state: any): (string?, ((any) -> ())?)
			local r = rng:int(1, 46)
			r = REMAP[r] or r
			local c = randomComponent(rng, doc)
			if r == 1 or r == 2 or c == nil then
				local componentType = pick(rng, TYPES)
				local options: any = {}
				if rng:next() < 0.5 then
					options.name = randomName(rng)
				end
				if c and rng:next() < 0.4 then
					options.parent = c.id
				end
				if rng:next() < 0.5 then
					options.startTime = number(rng, { min = -0.5, max = 3 })
				end
				if rng:next() < 0.3 then
					options.duration = number(rng, { min = -0.2, max = 3 })
				end
				local descriptor = Components.get(componentType)
				if rng:next() < 0.5 and #descriptor.properties > 0 then
					options.properties = {}
					for _ = 1, rng:int(1, 3) do
						local spec = pick(rng, descriptor.properties)
						options.properties[spec.name] = valueFor(rng, doc, spec.kind, spec)
					end
				end
				if rng:next() < 0.2 then
					options.index = rng:int(-1, #doc.components + 3)
				end
				return "addComponent " .. componentType,
					function(d: any)
						Ops.addComponent(d, componentType, options)
					end
			elseif r == 3 then
				local targets = sample(rng, componentIds(doc), 2)
				local keep = rng:next() < 0.3
				return "removeComponents",
					function(d: any)
						Ops.removeComponents(d, targets, { keepComponentNodes = keep })
					end
			elseif r == 4 then
				local targets = sample(rng, componentIds(doc), 2)
				return "duplicateComponents", function(d: any)
					Ops.duplicateComponents(d, targets)
				end
			elseif r == 5 then
				local name = randomName(rng)
				return "renameComponent", function(d: any)
					Ops.renameComponent(d, c.id, name)
				end
			elseif r == 6 then
				local targets = sample(rng, componentIds(doc), 2)
				local enabled = rng:next() < 0.5
				return "setEnabled", function(d: any)
					Ops.setEnabled(d, targets, enabled)
				end
			elseif r == 7 then
				local others = {}
				for _, other in doc.components do
					if other.id ~= c.id then
						table.insert(others, other.id)
					end
				end
				local parent = if #others == 0 or rng:next() < 0.25 then nil else pick(rng, others)
				return "setParent", function(d: any)
					Ops.setParent(d, c.id, parent)
				end
			elseif r == 8 then
				local index = rng:int(-1, #doc.components + 2)
				return "moveComponent", function(d: any)
					Ops.moveComponent(d, c.id, index)
				end
			elseif r == 9 then
				local s = if rng:next() < 0.7 then number(rng, { min = -0.5, max = 3 }) else nil
				local du = if rng:next() < 0.7 then number(rng, { min = -0.5, max = 3 }) else nil
				return "setTiming", function(d: any)
					Ops.setTiming(d, c.id, s, du)
				end
			elseif r == 10 then
				local field = pick(rng, { "position", "rotation", "scale" })
				local value: any = nil
				if rng:next() < 0.8 then
					value = if field == "scale"
						then number(rng, { min = -1, max = 3 })
						else valueFor(rng, doc, "vector3", nil)
				end
				return "setTransform " .. field, function(d: any)
					Ops.setTransform(d, c.id, field, value)
				end
			elseif r == 11 then
				local field = pick(rng, { "phase", "minQuality", "notes" })
				local value: any = nil
				if rng:next() < 0.8 then
					value = if field == "phase"
						then pick(rng, PHASES)
						elseif field == "minQuality" then pick(rng, Constants.QUALITY_LEVELS)
						else "note"
				end
				return "setComponentField " .. field,
					function(d: any)
						Ops.setComponentField(d, { c.id }, field, value)
					end
			elseif r == 12 or r == 13 then
				local descriptor = Components.get(c.type)
				if #descriptor.properties == 0 then
					return nil, nil
				end
				local spec = pick(rng, descriptor.properties)
				local sameType = {}
				for _, other in doc.components do
					if other.type == c.type and rng:next() < 0.3 then
						table.insert(sameType, other.id)
					end
				end
				table.insert(sameType, c.id)
				if rng:next() < 0.2 then
					return "resetProperty " .. spec.name,
						function(d: any)
							Ops.resetProperty(d, sameType, spec.name)
						end
				end
				local value = valueFor(rng, doc, spec.kind, spec)
				return "setProperty " .. c.type .. "." .. spec.name,
					function(d: any)
						Ops.setProperty(d, sameType, spec.name, value)
					end
			elseif r == 14 or r == 15 then
				local descriptor = Components.get(c.type)
				if #descriptor.channels == 0 then
					return nil, nil
				end
				local channel = pick(rng, descriptor.channels)
				local t = number(rng, { min = -0.3, max = 2.5 })
				local value = valueFor(rng, doc, channel.kind, channel)
				local easing = if rng:next() < 0.4 then pick(rng, EASINGS) else nil
				return "addKeyframe " .. c.type .. "." .. channel.name,
					function(d: any)
						Ops.addKeyframe(d, c.id, channel.name, t, value, easing)
					end
			elseif r == 16 then
				local refs = sample(rng, allKeyRefs(doc), 3)
				if #refs == 0 then
					return nil, nil
				end
				return "removeKeyframes", function(d: any)
					Ops.removeKeyframes(d, refs)
				end
			elseif r == 17 then
				local refs = sample(rng, allKeyRefs(doc), 3)
				if #refs == 0 then
					return nil, nil
				end
				local dt = number(rng, { min = -1.5, max = 1.5 })
				return "moveKeyframes",
					function(d: any)
						local out = Ops.moveKeyframes(d, refs, dt)
						assert(#out == #refs, "moveKeyframes returns one ref per input ref")
						for _, ref in out do
							local component = Ops.find(d, ref.component)
							local track
							for _, tr in component.tracks do
								if tr.id == ref.track then
									track = tr
								end
							end
							assert(track and track.keyframes[ref.index], "moveKeyframes returned a dangling ref")
						end
					end
			elseif r == 18 then
				local refs = allKeyRefs(doc)
				if #refs == 0 then
					return nil, nil
				end
				local ref = pick(rng, refs)
				local component = Ops.find(doc, ref.component)
				local channelName
				for _, track in component.tracks do
					if track.id == ref.track then
						channelName = track.channel
					end
				end
				local channel = Components.channelSpec(component.type, channelName)
				local fields: any = {}
				if rng:next() < 0.6 then
					fields.time = number(rng, { min = -0.5, max = 2.5 })
				end
				if rng:next() < 0.5 then
					fields.value = valueFor(rng, doc, channel.kind, channel)
				end
				if rng:next() < 0.3 then
					fields.easing = pick(rng, EASINGS)
				end
				return "setKeyframe", function(d: any)
					Ops.setKeyframe(d, ref, fields)
				end
			elseif r == 19 then
				local descriptor = Components.get(c.type)
				local actions = { "fire" }
				for _, e in descriptor.events do
					table.insert(actions, e.action)
				end
				local action = pick(rng, actions)
				local t = number(rng, { min = -0.2, max = 2 })
				local fields: any = {}
				if rng:next() < 0.5 then
					fields.count = rng:int(-5, 50)
				end
				if rng:next() < 0.5 then
					fields.name = pick(rng, { "Hit", "Boom", "Go_1" })
				end
				return "addEvent " .. c.type .. "." .. action,
					function(d: any)
						Ops.addEvent(d, c.id, action, t, fields)
					end
			elseif r == 20 then
				local refs = sample(rng, allEventRefs(doc), 2)
				if #refs == 0 then
					return nil, nil
				end
				if rng:next() < 0.5 then
					return "removeEvents", function(d: any)
						Ops.removeEvents(d, refs)
					end
				end
				local t = number(rng, { min = -0.5, max = 2.5 })
				return "moveEvent", function(d: any)
					Ops.moveEvent(d, refs[1], t)
				end
			elseif r == 21 then
				local t = number(rng, { min = -0.5, max = 3 })
				local fields: any = {}
				if rng:next() < 0.4 then
					fields.phase = pick(rng, PHASES)
				end
				if rng:next() < 0.4 then
					fields.event = pick(rng, { "", "Impact", "Go" })
				end
				if rng:next() < 0.3 then
					fields.color = colour(rng, doc)
				end
				local label = randomName(rng)
				return "addMarker", function(d: any)
					Ops.addMarker(d, t, label, fields)
				end
			elseif r == 22 then
				local markers = doc.markers or {}
				if #markers == 0 then
					return nil, nil
				end
				local marker = pick(rng, markers)
				if rng:next() < 0.4 then
					return "removeMarker", function(d: any)
						Ops.removeMarker(d, marker.id)
					end
				end
				local fields: any = {}
				if rng:next() < 0.5 then
					fields.time = number(rng, { min = -0.5, max = 3 })
				end
				if rng:next() < 0.3 then
					fields.label = randomName(rng)
				end
				if rng:next() < 0.3 then
					fields.phase = if rng:next() < 0.5 then Json.NULL else pick(rng, PHASES)
				end
				if rng:next() < 0.3 then
					fields.color = if rng:next() < 0.5 then Json.NULL else colour(rng, doc)
				end
				return "setMarker", function(d: any)
					Ops.setMarker(d, marker.id, fields)
				end
			elseif r == 23 then
				local field =
					pick(rng, { "name", "description", "duration", "loop", "seed", "timeScale", "tags", "palette" })
				local value: any
				if field == "name" then
					value = randomName(rng)
				elseif field == "description" then
					value = if rng:next() < 0.5 then nil else "about"
				elseif field == "duration" then
					value = number(rng, { min = 0.2, max = 4 })
				elseif field == "loop" then
					value = rng:next() < 0.5
				elseif field == "seed" then
					value = rng:int(-1000, 1000)
				elseif field == "timeScale" then
					value = number(rng, { min = -1, max = 12 })
				elseif field == "tags" then
					value = { "a", pick(rng, { "b", "c" }) }
				else
					value = {}
					for _, key in paletteKeys(doc) do
						if rng:next() < 0.8 then
							value[key] = hex(rng)
						end
					end
					if rng:next() < 0.6 then
						value[pick(rng, { "primary", "accent", "dark", "hot" })] = hex(rng)
					end
				end
				return "setEffectField " .. field, function(d: any)
					Ops.setEffectField(d, field, value)
				end
			elseif r == 24 then
				local nodeType = pick(rng, NODE_TYPES)
				local params: any = nil
				if rng:next() < 0.4 then
					local nt = NodeTypes.get(nodeType)
					if #nt.params > 0 then
						params = {}
						local spec = pick(rng, nt.params)
						if NodeTypes.get(nodeType).special[spec.name] == nil then
							params[spec.name] = valueFor(rng, doc, spec.kind, spec)
						end
					end
				end
				local position = if rng:next() < 0.8 then { rng:int(-500, 500), rng:int(-500, 500) } else nil
				return "addNode " .. nodeType, function(d: any)
					Ops.addNode(d, nodeType, position, params)
				end
			elseif r == 25 then
				local list = nodes(doc)
				if #list == 0 then
					return nil, nil
				end
				local targets = { pick(rng, list).id }
				if rng:next() < 0.5 then
					return "removeNodes", function(d: any)
						Ops.removeNodes(d, targets)
					end
				end
				local delta = { rng:int(-50, 50), rng:int(-50, 50) }
				return "moveNodes", function(d: any)
					Ops.moveNodes(d, targets, delta)
				end
			elseif r == 26 or r == 27 or r == 28 then
				local list = nodes(doc)
				if #list == 0 then
					return nil, nil
				end
				local n = pick(rng, list)
				local nodeType = NodeTypes.get(n.type)
				if #nodeType.params == 0 then
					return nil, nil
				end
				local spec = pick(rng, nodeType.params)
				local value = if rng:next() < 0.1 then nil else paramValue(rng, doc, n, spec)
				return "setNodeParam " .. n.type .. "." .. spec.name,
					function(d: any)
						Ops.setNodeParam(d, n.id, spec.name, value)
					end
			elseif r == 29 or r == 30 then
				local list = nodes(doc)
				if #list < 2 then
					return nil, nil
				end
				local a = pick(rng, list)
				local outputs = NodeTypes.outputs(NodeTypes.get(a.type), a.params)
				if #outputs == 0 then
					return nil, nil
				end
				local output = pick(rng, outputs)
				-- mostly pins of a matching kind (exec -> exec, data -> same kind or any), sometimes anything
				local candidates = {}
				for _, b in list do
					for _, pin in NodeTypes.get(b.type).inputs do
						local match = if output.kind == "exec"
							then pin.kind == "exec"
							else pin.kind ~= "exec"
								and (pin.kind == output.kind or pin.kind == "any" or output.kind == "any")
						if match or rng:next() < 0.1 then
							table.insert(candidates, b.id .. "." .. pin.name)
						end
					end
				end
				if #candidates == 0 then
					return nil, nil
				end
				local from = a.id .. "." .. output.name
				local to = pick(rng, candidates)
				local replace = rng:next() < 0.3
				return "connect " .. from .. " -> " .. to,
					function(d: any)
						local ok, reason = Ops.connect(d, from, to, { replace = replace })
						if ok then
							if state.stats then
								state.stats.connected += 1
							end
						else
							assert(type(reason) == "string" and #reason > 0, "a rejected connect returns a reason")
						end
					end
			elseif r == 31 then
				local linkList = if doc.graph then doc.graph.links else {}
				if #linkList == 0 then
					return nil, nil
				end
				local link = pick(rng, linkList)
				local from = if rng:next() < 0.5 then link.from else nil
				return "disconnect",
					function(d: any)
						assert(Ops.disconnect(d, from, link.to) >= 1, "disconnect removes the link")
					end
			elseif r == 32 then
				local targets = sample(rng, componentIds(doc), 2)
				local payload = Ops.copyComponents(doc, targets)
				if rng:next() < 0.5 then
					payload = roundTrip(payload)
				end
				local parent = if rng:next() < 0.3 then (randomComponent(rng, doc) :: any).id else nil
				local options = if rng:next() < 0.3 then { atTime = number(rng, { min = -1, max = 3 }) } else nil
				return "copy/pasteComponents",
					function(d: any)
						Ops.pasteComponents(d, payload, parent, options)
					end
			elseif r == 33 then
				-- paste from the other document of this sequence
				local payload = roundTrip(Ops.copyComponents(state.other, componentIds(state.other)))
				local parent = if rng:next() < 0.3 then c.id else nil
				return "pasteComponents (other document)",
					function(d: any)
						Ops.pasteComponents(d, payload, parent)
					end
			else
				local sourceDoc = if rng:next() < 0.3 then state.other else doc
				local refs = sample(rng, allKeyRefs(sourceDoc), 3)
				if #refs == 0 then
					return nil, nil
				end
				local payload = roundTrip(Ops.copyKeyframes(sourceDoc, refs))
				local at = number(rng, { min = -1, max = 3 })
				local target = if sourceDoc == state.other or rng:next() < 0.5 then c.id else nil
				return "copy/pasteKeyframes", function(d: any)
					Ops.pasteKeyframes(d, payload, at, target)
				end
			end
		end

		local function otherDocument(): any
			local other = Ops.newEffect("Other", { duration = 3 })
			Ops.setEffectField(other, "palette", { accent = "#336699" })
			Ops.addComponent(other, "group", { name = "Core" })
			Ops.addComponent(other, "part", { name = "Core", parent = "core", properties = { color = "$accent" } })
			Ops.addComponent(other, "particles", { name = "Sparks", startTime = 1 })
			Ops.addKeyframe(other, "core-2", "color", 0, "$accent")
			Ops.addKeyframe(other, "core-2", "transparency", 0.5, 0.5)
			Ops.addKeyframe(other, "sparks", "rate", 0.25, 30)
			Ops.addEvent(other, "sparks", "emit", 0.1)
			return other
		end

		-- Authoring invariants beyond Validation. Ids generated by ops are unique across the whole effect scope;
		-- `shared` lists ids a hand-written starting document already reuses across scopes (Validation allows it).
		local function invariantProblems(doc: any, shared: { [string]: boolean }?): { string }
			local problems = {}
			local seen = {}
			local function id(kind: string, value: string)
				if seen[value] and not (shared and shared[value]) then
					table.insert(problems, "duplicate id " .. value .. " (" .. kind .. " and " .. seen[value] .. ")")
				end
				seen[value] = kind
			end
			local function sorted(kind: string, list: { any }?)
				local previous = -math.huge
				for _, entry in (list or {}) :: { any } do
					if entry.time < previous then
						table.insert(problems, kind .. " not sorted")
						return
					end
					previous = entry.time
				end
			end
			for _, c in doc.components do
				id("component", c.id)
				for _, track in c.tracks or {} do
					id("track", track.id)
					sorted("keyframes of " .. track.id, track.keyframes)
				end
				for _, event in c.events or {} do
					id("event", event.id)
				end
				sorted("events of " .. c.id, c.events)
				for _, key in { "properties", "tracks", "events", "transform" } do
					if c[key] ~= nil and next(c[key]) == nil then
						table.insert(problems, c.id .. "." .. key .. " is an empty table")
					end
				end
			end
			for _, marker in doc.markers or {} do
				id("marker", marker.id)
			end
			sorted("markers", doc.markers)
			for _, n in nodes(doc) do
				id("node", n.id)
			end
			if doc.graph and #doc.graph.nodes == 0 then
				table.insert(problems, "empty graph left in the document")
			end
			return problems
		end

		local function fixtureDocument(): any
			local ok, raw = Json.decode(Fixtures.FULL_JSON)
			assert(ok, raw)
			local doc = Migration.migrate(raw)
			assert(doc, "fixture migrates")
			return doc
		end

		T.it("starts from a fixture without validation errors", function()
			expect(errorLines(fixtureDocument())).toEqual({})
		end)

		T.it("200 random op sequences keep Validation at zero errors", function()
			local master = Random.new(SEED)
			local applied, rejected, skipped = 0, 0, 0
			local opCounts: { [string]: number } = {}
			local stats = { connected = 0, linksAtEnd = 0 }
			for sequence = 1, SEQUENCES do
				local rng = Random.new(master:int(1, 2 ^ 31 - 1))
				-- every fourth sequence starts from the realistic fixture (palette, graph flows, overrides, ...)
				local fromFixture = sequence % 4 == 0
				local doc = if fromFixture
					then fixtureDocument()
					else Ops.newEffect("Random " .. sequence, { duration = 2 })
				local state = { other = otherDocument(), stats = stats }
				local shared: { [string]: boolean } = {}
				do
					local counts: { [string]: number } = {}
					local function count(entry: any)
						counts[entry.id] = (counts[entry.id] or 0) + 1
					end
					for _, c in doc.components do
						count(c)
						for _, track in c.tracks or {} do
							count(track)
						end
						for _, event in c.events or {} do
							count(event)
						end
					end
					for _, marker in doc.markers or {} do
						count(marker)
					end
					for _, n in nodes(doc) do
						count(n)
					end
					for value, n in counts do
						if n > 1 then
							shared[value] = true
						end
					end
				end
				local log: { string } = {}
				for step = 1, STEPS do
					local label, op = randomOp(rng, doc, state)
					for _ = 1, 3 do
						if op then
							break
						end
						label, op = randomOp(rng, doc, state)
					end
					if label == nil or op == nil then
						skipped += 1
						continue
					end
					local working = Ops.clone(doc)
					local ok, err = pcall(op :: any, working)
					if not ok then
						local text = tostring(err)
						if string.sub(text, 1, 4) ~= "Ops." then
							T.fail(
								string.format(
									"sequence %d step %d (%s) raised a non-Ops error: %s\nlog:\n  %s",
									sequence,
									step,
									label,
									text,
									table.concat(log, "\n  ")
								)
							)
						end
						rejected += 1
						table.insert(log, "x " .. label .. " -> " .. text)
						continue
					end
					applied += 1
					local kind = string.match(label, "^[%w/]+") or label
					opCounts[kind] = (opCounts[kind] or 0) + 1
					doc = working
					table.insert(log, label)
					-- strict: ops never write unknown fields (the fixture has a deliberate unknown property)
					local errors = errorLines(doc, not fromFixture)
					local problems = invariantProblems(doc, shared)
					if #errors > 0 or #problems > 0 then
						T.fail(
							string.format(
								"sequence %d step %d (%s):\n  %s\nlog:\n  %s\ndocument:\n%s",
								sequence,
								step,
								label,
								table.concat(errors, "\n  ") .. table.concat(problems, "\n  "),
								table.concat(log, "\n  "),
								Json.encode(doc)
							)
						)
					end
				end
				stats.linksAtEnd += if doc.graph then #doc.graph.links else 0
				-- The result survives a JSON round trip and compiles.
				local decoded = roundTrip(doc)
				expect(errorLines(decoded)).toEqual({})
				local compiled = Compiler.compile(decoded, { quality = "High" })
				expect(compiled.id).toBe(doc.id)
			end
			-- The generator must exercise the ops, not just get rejected.
			expect(applied).toBeGreaterThan(SEQUENCES * STEPS * 0.6)
			expect(rejected).toBeLessThan(applied / 4)
			for _, kind in
				{
					"addComponent",
					"removeComponents",
					"duplicateComponents",
					"setParent",
					"setProperty",
					"addKeyframe",
					"moveKeyframes",
					"setKeyframe",
					"removeKeyframes",
					"addEvent",
					"moveEvent",
					"addMarker",
					"removeMarker",
					"setMarker",
					"setEffectField",
					"addNode",
					"setNodeParam",
					"connect",
					"disconnect",
					"copy/pasteComponents",
					"pasteComponents",
					"copy/pasteKeyframes",
				}
			do
				if (opCounts[kind] or 0) < 20 then
					T.fail(kind .. " was applied only " .. tostring(opCounts[kind] or 0) .. " times")
				end
			end
			expect(skipped).toBeLessThan(SEQUENCES * STEPS * 0.05)
			expect(stats.connected).toBeGreaterThan(100)
			expect(stats.linksAtEnd).toBeGreaterThan(50)
		end)

		T.it("is deterministic (same seed, same documents)", function()
			local function run(): string
				local rng = Random.new(SEED)
				local doc = Ops.newEffect("Det")
				local state = { other = otherDocument() }
				for _ = 1, 60 do
					local _, op = randomOp(rng, doc, state)
					if op then
						local working = Ops.clone(doc)
						if pcall(op :: any, working) then
							doc = working
						end
					end
				end
				return Json.encode(doc)
			end
			expect(run()).toBe(run())
		end)
	end)

	-- Codec is used indirectly; keep a direct reference so a Codec rename shows up here too.
	T.it("canonical values match Codec.normalize", function()
		local doc = newDoc()
		Ops.addComponent(doc, "particles", { properties = { lifetime = { 2, 2 } } })
		expect(find(doc, "particles").properties.lifetime).toEqual(Codec.normalize("numberRange", { 2, 2 }))
	end)
end
