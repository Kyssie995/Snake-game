--!strict
--[[
	ComponentsProcedural — descriptor specs for the procedural components ring, radialBurst, debris and lightning
	(docs/COMPONENTS_SPEC.md §12-15).

	Components are built with tests/specs/Helpers/ComponentHarness.luau into real Lune instances (property names and
	value types are checked against the Roblox reflection database). Lune has no renderer: these specs prove
	instance structure, property values, write caching, CFrame batching, the documented formulas and determinism —
	not the visual result.

	Structure:
	  1. Spec fidelity per type: property keys/kinds/defaults/ranges/flags, channels, events, Codec round trip.
	  2. Generic controller contract per build variant (lightning: beam and part render): tagging, physics-free
	     parts, invisible until active, exact cost counts, channels change instances, moves only via
	     frame.moveParts, reset() = built state, release(), history independence (t = 0.7 after different
	     histories and when seeking), seed behaviour, no instances created per frame, destroy() leaves nothing.
	  3. Type-specific geometry and behaviour.
]]

return function(T: any, use: (string) -> any, ctx: any)
	local Harness = use("Tests.Specs.Helpers.ComponentHarness")
	local Components = use("AstraVFX.Core.Components")
	local Codec = use("AstraVFX.Core.Codec")
	local expect = T.expect
	local fakes = ctx.fakes

	local EPS = 1e-4
	local HIGH = {
		level = "High",
		countScale = 1,
		segmentScale = 1,
		sizeCompensation = 1,
		lightShadows = true,
		maxLights = math.huge,
	}
	local RED = Color3.new(1, 0, 0)
	local GREEN = Color3.new(0, 1, 0)

	local MATERIAL_LIST = {
		"Plastic",
		"SmoothPlastic",
		"Neon",
		"Wood",
		"WoodPlanks",
		"Marble",
		"Basalt",
		"Slate",
		"CrackedLava",
		"Concrete",
		"Limestone",
		"Granite",
		"Pavement",
		"Brick",
		"Pebble",
		"Cobblestone",
		"Rock",
		"Sandstone",
		"CorrodedMetal",
		"DiamondPlate",
		"Foil",
		"Metal",
		"Grass",
		"LeafyGrass",
		"Sand",
		"Fabric",
		"Snow",
		"Mud",
		"Ground",
		"Asphalt",
		"Salt",
		"Ice",
		"Glacier",
		"Glass",
		"ForceField",
		"Cardboard",
		"Carpet",
		"CeramicTiles",
		"ClayRoofTiles",
		"RoofShingles",
		"Leather",
		"Plaster",
		"Rubber",
	}

	-- ─────────────────────────────────────────────────────────────────────────
	-- docs/COMPONENTS_SPEC.md §12-15 transcribed
	-- ─────────────────────────────────────────────────────────────────────────

	type PropRow = {
		name: string,
		kind: string,
		default: any,
		min: number?,
		max: number?,
		scale: string?,
		quality: string?,
		advanced: boolean?,
		enumType: string?,
		enum: { string }?,
	}
	type ChannelRow = { name: string, kind: string, scale: string?, baseProperty: string? }
	type ExpectedType = { properties: { PropRow }, channels: { ChannelRow }, events: { string } }

	local POSITION: ChannelRow = { name = "position", kind = "vector3", scale = "length" }
	local ROTATION: ChannelRow = { name = "rotation", kind = "vector3" }
	local MATERIAL = function(default: string): PropRow
		return { name = "material", kind = "enum", default = default, enumType = "Material", enum = MATERIAL_LIST }
	end
	local TRANSPARENCY: PropRow = { name = "transparency", kind = "number", default = 0, min = 0, max = 1 }

	local EXPECTED: { [string]: ExpectedType } = {
		ring = {
			properties = {
				{ name = "style", kind = "enum", default = "ring", enum = { "ring", "polygon", "star", "spokes" } },
				{ name = "segments", kind = "integer", default = 24, min = 3, max = 128, quality = "segments" },
				{ name = "points", kind = "integer", default = 5, min = 3, max = 32 },
				{ name = "starStep", kind = "integer", default = 2, min = 1, max = 15 },
				{ name = "radius", kind = "number", default = 4, min = 0, max = 2000, scale = "length" },
				{ name = "innerRadius", kind = "number", default = 0, min = 0, max = 2000, scale = "length" },
				{ name = "thickness", kind = "number", default = 0.2, min = 0.001, max = 100, scale = "length" },
				{ name = "height", kind = "number", default = 0.1, min = 0.001, max = 100, scale = "length" },
				{ name = "color", kind = "color3", default = "#FFFFFF" },
				MATERIAL("Neon"),
				TRANSPARENCY,
				{ name = "spin", kind = "vector3", default = { 0, 0, 0 } },
			},
			channels = {
				POSITION,
				ROTATION,
				{ name = "scale", kind = "number" },
				{ name = "radius", kind = "number", scale = "length", baseProperty = "radius" },
				{ name = "thickness", kind = "number", scale = "length", baseProperty = "thickness" },
				{ name = "transparency", kind = "number", baseProperty = "transparency" },
				{ name = "color", kind = "color3", baseProperty = "color" },
			},
			events = {},
		},
		radialBurst = {
			properties = {
				{ name = "count", kind = "integer", default = 12, min = 1, max = 256, quality = "count" },
				{
					name = "distribution",
					kind = "enum",
					default = "sphere",
					enum = { "sphere", "hemisphere", "ring", "cone" },
				},
				{ name = "coneAngle", kind = "number", default = 45, min = 0, max = 180 },
				{ name = "startRadius", kind = "number", default = 0.5, min = 0, max = 2000, scale = "length" },
				{ name = "endRadius", kind = "number", default = 10, min = 0, max = 2000, scale = "length" },
				{ name = "width", kind = "number", default = 0.3, min = 0.001, max = 100, scale = "length" },
				{ name = "jitter", kind = "number", default = 0.3, min = 0, max = 1 },
				{ name = "color", kind = "color3", default = "#FFFFFF" },
				MATERIAL("Neon"),
				TRANSPARENCY,
			},
			channels = {
				POSITION,
				ROTATION,
				{ name = "transparency", kind = "number", baseProperty = "transparency" },
				{ name = "color", kind = "color3", baseProperty = "color" },
			},
			events = {},
		},
		debris = {
			properties = {
				{ name = "count", kind = "integer", default = 12, min = 1, max = 200, quality = "count" },
				{ name = "shape", kind = "enum", default = "Mixed", enum = { "Block", "Wedge", "Ball", "Mixed" } },
				{ name = "size", kind = "numberRange", default = { 0.3, 0.8 }, min = 0.01, max = 50, scale = "length" },
				{ name = "speed", kind = "numberRange", default = { 20, 40 }, min = 0, max = 2000, scale = "length" },
				{ name = "direction", kind = "vector3", default = { 0, 1, 0 } },
				{ name = "spreadAngle", kind = "number", default = 60, min = 0, max = 180 },
				{ name = "gravity", kind = "vector3", default = { 0, -80, 0 }, scale = "length" },
				{ name = "drag", kind = "number", default = 0, min = 0, max = 20 },
				{ name = "spinSpeed", kind = "numberRange", default = { 90, 360 }, min = 0, max = 3600 },
				{ name = "color", kind = "color3", default = "#6B5B4B" },
				{ name = "colorVariance", kind = "number", default = 0.15, min = 0, max = 1 },
				MATERIAL("Slate"),
				TRANSPARENCY,
				{ name = "fadeTime", kind = "number", default = 0.3, min = 0, max = 10 },
				{ name = "floor", kind = "boolean", default = false },
				{ name = "floorHeight", kind = "number", default = 0, scale = "length" },
			},
			channels = {
				POSITION,
				ROTATION,
				{ name = "color", kind = "color3", baseProperty = "color" },
				{ name = "transparency", kind = "number", baseProperty = "transparency" },
			},
			events = {},
		},
		lightning = {
			properties = {
				{ name = "from", kind = "vector3", default = { 0, 10, 0 }, scale = "length" },
				{ name = "to", kind = "vector3", default = { 0, 0, 0 }, scale = "length" },
				{ name = "segments", kind = "integer", default = 12, min = 2, max = 64, quality = "segments" },
				{ name = "jitter", kind = "number", default = 1.5, min = 0, max = 500, scale = "length" },
				{ name = "branches", kind = "integer", default = 2, min = 0, max = 8, quality = "count" },
				{ name = "branchLength", kind = "number", default = 0.35, min = 0, max = 1 },
				{ name = "flickerRate", kind = "number", default = 20, min = 0, max = 120 },
				{ name = "thickness", kind = "number", default = 0.3, min = 0.01, max = 50, scale = "length" },
				{ name = "color", kind = "color3", default = "#A8DCFF" },
				{ name = "render", kind = "enum", default = "beam", enum = { "beam", "part" } },
				{ name = "lightEmission", kind = "number", default = 1, min = 0, max = 1 },
				{ name = "brightness", kind = "number", default = 2, min = 0, max = 100 },
				{ name = "texture", kind = "asset", default = "" },
				TRANSPARENCY,
				MATERIAL("Neon"),
			},
			channels = {
				POSITION,
				ROTATION,
				{ name = "from", kind = "vector3", scale = "length", baseProperty = "from" },
				{ name = "to", kind = "vector3", scale = "length", baseProperty = "to" },
				{ name = "thickness", kind = "number", scale = "length", baseProperty = "thickness" },
				{ name = "transparency", kind = "number", baseProperty = "transparency" },
				{ name = "color", kind = "color3", baseProperty = "color" },
			},
			events = { "regenerate" },
		},
	}

	local TYPES = { "ring", "radialBurst", "debris", "lightning" }

	-- Build variants for the controller contract. `visibleAt`: a local time at which the default build shows.
	type Variant = {
		label: string,
		type: string,
		props: { [string]: any }?,
		visibleAt: number,
		seeded: boolean, -- shape depends on the component seed
		samples: { { any } }, -- channel values that differ from the defaults (decoded form)
	}
	local VARIANTS: { Variant } = {
		{
			label = "ring",
			type = "ring",
			visibleAt = 0,
			seeded = false,
			samples = {
				{ "scale", 2 },
				{ "radius", 6 },
				{ "thickness", 0.5 },
				{ "transparency", 0.5 },
				{ "color", RED },
			},
		},
		{
			label = "ring (star)",
			type = "ring",
			props = { style = "star", points = 7, starStep = 3 },
			visibleAt = 0,
			seeded = false,
			samples = { { "radius", 6 }, { "thickness", 0.5 }, { "transparency", 0.5 }, { "color", RED } },
		},
		{
			label = "ring (spokes)",
			type = "ring",
			props = { style = "spokes", points = 8, innerRadius = 1 },
			visibleAt = 0,
			seeded = false,
			samples = { { "scale", 0.5 }, { "radius", 6 }, { "thickness", 0.5 }, { "color", RED } },
		},
		{
			label = "radialBurst",
			type = "radialBurst",
			visibleAt = 0.3,
			seeded = true,
			samples = { { "transparency", 0.5 }, { "color", RED } },
		},
		{
			label = "debris",
			type = "debris",
			visibleAt = 0,
			seeded = true,
			samples = { { "color", RED }, { "transparency", 0.5 } },
		},
		{
			label = "debris (floor, drag)",
			type = "debris",
			props = { floor = true, floorHeight = -1, drag = 2, shape = "Ball" },
			visibleAt = 0,
			seeded = true,
			samples = { { "color", RED }, { "transparency", 0.5 } },
		},
		{
			label = "lightning (beam)",
			type = "lightning",
			visibleAt = 0,
			seeded = true,
			samples = {
				{ "from", Vector3.new(2, 8, 1) },
				{ "to", Vector3.new(-1, 0, 3) },
				{ "thickness", 0.8 },
				{ "transparency", 0.5 },
				{ "color", RED },
			},
		},
		{
			label = "lightning (part)",
			type = "lightning",
			props = { render = "part" },
			visibleAt = 0,
			seeded = true,
			samples = {
				{ "from", Vector3.new(2, 8, 1) },
				{ "to", Vector3.new(-1, 0, 3) },
				{ "thickness", 0.8 },
				{ "transparency", 0.5 },
				{ "color", RED },
			},
		},
	}

	-- ─────────────────────────────────────────────────────────────────────────
	-- Helpers
	-- ─────────────────────────────────────────────────────────────────────────

	-- Every harness created by a test is cleaned up after it (also when an expectation failed).
	local open: { any } = {}
	local function harness(): any
		local h = Harness.new(use)
		table.insert(open, h)
		return h
	end
	T.afterEach(function()
		for _, h in open do
			h:cleanup()
		end
		table.clear(open)
		if fakes then
			fakes:reset()
		end
	end)

	local function descriptorOf(typeName: string): any
		local d = Components.get(typeName)
		assert(d, "descriptor not registered: " .. typeName)
		return d
	end

	local function ofClass(h: any, id: string, className: string): { any }
		local out = {}
		for _, inst: any in h:instancesOf(id) do
			if inst:IsA(className) then
				table.insert(out, inst)
			end
		end
		return out
	end

	local function partsOf(h: any, id: string): { any }
		return ofClass(h, id, "BasePart")
	end

	local function beamsOf(h: any, id: string): { any }
		return ofClass(h, id, "Beam")
	end

	-- Instance of a component by name.
	local function find(h: any, id: string, name: string): any
		for _, inst: any in h:instancesOf(id) do
			if inst.Name == name then
				return inst
			end
		end
		error("instance not found: " .. name)
	end

	-- Named, ordered instances: prefix .. 1, prefix .. 2, ...
	local function sequence(h: any, id: string, prefix: string, count: number): { any }
		local out = {}
		for i = 1, count do
			out[i] = find(h, id, prefix .. i)
		end
		return out
	end

	local function countClasses(list: { any }): { [string]: number }
		local counts = {
			instances = #list,
			parts = 0,
			attachments = 0,
			lights = 0,
			emitters = 0,
			beams = 0,
			trails = 0,
			sounds = 0,
		}
		for _, inst: any in list do
			if inst:IsA("BasePart") then
				counts.parts += 1
			elseif inst:IsA("Attachment") then
				counts.attachments += 1
			elseif inst:IsA("Light") then
				counts.lights += 1
			elseif inst:IsA("ParticleEmitter") then
				counts.emitters += 1
			elseif inst:IsA("Beam") then
				counts.beams += 1
			elseif inst:IsA("Trail") then
				counts.trails += 1
			elseif inst:IsA("Sound") then
				counts.sounds += 1
			end
		end
		return counts
	end

	-- Every rendering-relevant property of a component's instances, keyed by "Class:Name".
	local function snapshot(h: any, id: string, withCFrame: boolean?): { [string]: any }
		local out = {}
		for _, inst: any in h:instancesOf(id) do
			local s: { [string]: any } = {}
			if inst:IsA("BasePart") then
				s = {
					Size = inst.Size,
					Transparency = inst.Transparency,
					Color = inst.Color,
					Material = inst.Material,
					Shape = inst.Shape,
				}
				if withCFrame then
					s.CFrame = inst.CFrame
				end
			elseif inst:IsA("Beam") then
				s = {
					Enabled = inst.Enabled,
					Width0 = inst.Width0,
					Width1 = inst.Width1,
					Transparency = inst.Transparency,
					Color = inst.Color,
					-- names, not references: snapshots are compared across harnesses
					Attachment0 = if inst.Attachment0 then inst.Attachment0.Name else "",
					Attachment1 = if inst.Attachment1 then inst.Attachment1.Name else "",
				}
			elseif inst:IsA("Attachment") then
				s = { CFrame = inst.CFrame }
			end
			out[inst.ClassName .. ":" .. inst.Name] = s
		end
		return out
	end

	-- One Player-like frame: setTransform → update → BulkMoveTo (flush).
	local function step(h: any, c: any, t: number, localCFrame: CFrame?, seeking: boolean?): any
		local f = h:frame(t, if seeking then 0 else 1 / 60, seeking)
		local cf = localCFrame or CFrame.new()
		c:setTransform(cf, h.root.CFrame * cf, f)
		if c.update then
			c:update(t, f)
		end
		h:flush(f)
		return f
	end

	local function activate(h: any, c: any, t: number?)
		c:setActive(true, h:frame(t or 0, 0))
	end

	local function allHidden(h: any, id: string): boolean
		for _, p in partsOf(h, id) do
			if p.Transparency < 1 then
				return false
			end
		end
		for _, b in beamsOf(h, id) do
			if b.Enabled then
				return false
			end
		end
		return true
	end

	local function visibleCount(h: any, id: string): number
		local n = 0
		for _, p in partsOf(h, id) do
			if p.Transparency < 1 then
				n += 1
			end
		end
		for _, b in beamsOf(h, id) do
			if b.Enabled then
				n += 1
			end
		end
		return n
	end

	local function contains(list: { any }, item: any): boolean
		return table.find(list, item) ~= nil
	end

	-- Deep comparison with tolerance (same rules as the toBeCloseTo matcher).
	local function closeTo(a: any, b: any, eps: number): boolean
		local t = typeof(a)
		if t ~= typeof(b) then
			return false
		end
		if t == "number" then
			return math.abs(a - b) <= eps
		elseif t == "Vector3" then
			return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps and math.abs(a.Z - b.Z) <= eps
		elseif t == "Color3" then
			return math.abs(a.R - b.R) <= eps and math.abs(a.G - b.G) <= eps and math.abs(a.B - b.B) <= eps
		elseif t == "CFrame" then
			local ca = { a:GetComponents() }
			local cb = { b:GetComponents() }
			for i = 1, 12 do
				if math.abs(ca[i] - cb[i]) > eps then
					return false
				end
			end
			return true
		elseif t == "table" then
			for k, v in a do
				if not closeTo(v, b[k], eps) then
					return false
				end
			end
			for k in b do
				if a[k] == nil then
					return false
				end
			end
			return true
		end
		return a == b
	end

	local function isFiniteCFrame(cf: CFrame): boolean
		for _, v in { cf:GetComponents() } do
			if v ~= v or v == math.huge or v == -math.huge then
				return false
			end
		end
		return true
	end

	-- Rotation angle (radians) of a rotation-only CFrame.
	local function rotationAngle(cf: CFrame): number
		local _, _, _, r00, _, _, _, r11, _, _, _, r22 = cf:GetComponents()
		return math.acos(math.clamp((r00 + r11 + r22 - 1) / 2, -1, 1))
	end

	local function angleBetween(a: Vector3, b: Vector3): number
		return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
	end

	-- Distance from point p to the segment a–b.
	local function distanceToSegment(p: Vector3, a: Vector3, b: Vector3): number
		local ab = b - a
		local len2 = ab:Dot(ab)
		local u = if len2 > 0 then math.clamp((p - a):Dot(ab) / len2, 0, 1) else 0
		return (p - (a + ab * u)).Magnitude
	end

	-- Lightning attachment world-free positions (CFrame relative to the Root part) of one polyline.
	local function polyline(h: any, id: string, line: number, count: number): { Vector3 }
		local out = {}
		for j = 1, count do
			out[j] = find(h, id, "lightning_P" .. line .. "_" .. j).CFrame.Position
		end
		return out
	end

	-- ─────────────────────────────────────────────────────────────────────────
	-- 1. Spec fidelity
	-- ─────────────────────────────────────────────────────────────────────────

	for _, typeName in TYPES do
		local expected = EXPECTED[typeName]
		T.describe("ComponentsProcedural " .. typeName .. " spec", function()
			T.it("is a registered procedural, viewport-capable descriptor", function()
				local d = descriptorOf(typeName)
				expect(d.type).toBe(typeName)
				expect(d.category).toBe("Procedural")
				expect(d.supportsViewport).toBe(true)
				expect(d.canParent).toBe(true)
				expect(d.tailTime).toBeNil()
				expect(type(d.displayName)).toBe("string")
				expect(type(d.description)).toBe("string")
				expect(type(d.build)).toBe("function")
				expect(type(d.estimateCost)).toBe("function")
				local actions = {}
				for _, e in d.events do
					table.insert(actions, e.action)
					expect(type(e.description)).toBe("string")
				end
				expect(actions).toEqual(expected.events)
			end)

			T.it("declares exactly the properties of docs/COMPONENTS_SPEC.md", function()
				local d = descriptorOf(typeName)
				local names = {}
				for _, spec in d.properties do
					table.insert(names, spec.name)
				end
				local expectedNames = {}
				for _, row in expected.properties do
					table.insert(expectedNames, row.name)
				end
				expect(names).toEqual(expectedNames)
				for _, row in expected.properties do
					local spec = Components.propertySpec(typeName, row.name)
					expect(spec).never.toBeNil()
					local actual: { any } = {
						spec.name,
						spec.kind,
						spec.min,
						spec.max,
						spec.scale,
						spec.quality,
						spec.advanced == true,
						spec.enumType,
					}
					local wanted: { any } = {
						row.name,
						row.kind,
						row.min,
						row.max,
						row.scale,
						row.quality,
						row.advanced == true,
						row.enumType,
					}
					expect(actual).toEqual(wanted)
					expect(spec.default).toEqual(row.default)
					expect(type(spec.description)).toBe("string")
					if row.enum then
						expect(spec.enum).toEqual(row.enum)
					end
				end
			end)

			T.it("declares exactly the channels of docs/COMPONENTS_SPEC.md", function()
				local d = descriptorOf(typeName)
				local names = {}
				for _, spec in d.channels do
					table.insert(names, spec.name)
				end
				local expectedNames = {}
				for _, row in expected.channels do
					table.insert(expectedNames, row.name)
				end
				expect(names).toEqual(expectedNames)
				for _, row in expected.channels do
					local spec = Components.channelSpec(typeName, row.name)
					local got: { any } = { spec.name, spec.kind, spec.scale, spec.baseProperty }
					local want: { any } = { row.name, row.kind, row.scale, row.baseProperty }
					expect(got).toEqual(want)
					expect(type(spec.description)).toBe("string")
					if spec.baseProperty then
						local base = Components.propertySpec(typeName, spec.baseProperty)
						expect(base).never.toBeNil()
					end
				end
			end)

			T.it("encodes every default in canonical JSON form that Codec checks and decodes", function()
				local d = descriptorOf(typeName)
				for _, spec in d.properties do
					local value = Codec.default(spec)
					local ok, problem = Codec.check(spec.kind, value, spec)
					if not ok then
						error(spec.name .. ": " .. tostring(problem))
					end
					expect(Codec.normalize(spec.kind, value, spec)).toEqual(spec.default)
					local decoded = Codec.decode(spec.kind, value, spec)
					expect(decoded).never.toBeNil()
					if spec.kind == "enum" then
						if spec.enumType then
							expect(typeof(decoded)).toBe("EnumItem")
							expect(decoded.Name).toBe(spec.default)
							for _, name in spec.enum do
								expect(typeof(Codec.decode("enum", name, spec))).toBe("EnumItem")
							end
						else
							expect(decoded).toBe(spec.default)
							expect(contains(spec.enum, spec.default)).toBe(true)
						end
					end
				end
			end)

			T.it("builds with every enum value", function()
				local d = descriptorOf(typeName)
				for _, spec in d.properties do
					if spec.kind == "enum" then
						for _, name in spec.enum do
							local h = harness()
							local c, component = h:build(typeName, { [spec.name] = name })
							expect(#c.instances).toBeGreaterThan(0)
							activate(h, c)
							step(h, c, 0.3)
							expect(visibleCount(h, component.id)).toBeGreaterThan(0)
						end
					end
				end
			end)
		end)
	end

	-- ─────────────────────────────────────────────────────────────────────────
	-- 2. Controller contract per build variant
	-- ─────────────────────────────────────────────────────────────────────────

	for _, variant in VARIANTS do
		local typeName = variant.type
		local props = variant.props
		local visibleAt = variant.visibleAt

		local function build(h: any, options: any?): (any, any)
			local c, component = h:build(typeName, props, options)
			return c, component
		end

		T.describe("ComponentsProcedural " .. variant.label .. " contract", function()
			T.it("builds with defaults, tags every instance and keeps parts physics-free", function()
				local h = harness()
				local c, component = build(h)
				expect(#c.instances).toBeGreaterThan(0)
				expect(c.component).toBe(component)
				local owned = h:instancesOf(component.id)
				expect(#owned).toBe(#c.instances)
				for _, inst: any in c.instances do
					expect(inst:GetAttribute("AstraComponent")).toBe(component.id)
					expect(inst:IsDescendantOf(h.container)).toBe(true)
					expect(contains(owned, inst)).toBe(true)
				end
				for _, p in partsOf(h, component.id) do
					expect(p.Anchored).toBe(true)
					expect(p.CanCollide).toBe(false)
					expect(p.CanQuery).toBe(false)
					expect(p.CanTouch).toBe(false)
					expect(p.CastShadow).toBe(false)
					expect(p.Massless).toBe(true)
					expect(p.Parent).toBe(h.container)
				end
				for _, inst in ofClass(h, component.id, "Attachment") do
					expect(inst.Parent).toBe(h.root)
				end
				for _, b in beamsOf(h, component.id) do
					expect(b.Parent).toBe(h.root)
				end
			end)

			T.it("is invisible until setActive(true) and hidden again by setActive(false)", function()
				local h = harness()
				local c, component = build(h)
				expect(allHidden(h, component.id)).toBe(true)
				step(h, c, visibleAt) -- frames while inactive reveal nothing
				expect(allHidden(h, component.id)).toBe(true)
				activate(h, c)
				step(h, c, visibleAt)
				expect(visibleCount(h, component.id)).toBeGreaterThan(0)
				c:setActive(false, h:frame(visibleAt, 0))
				expect(allHidden(h, component.id)).toBe(true)
				step(h, c, visibleAt + 0.1)
				expect(allHidden(h, component.id)).toBe(true)
				activate(h, c)
				step(h, c, visibleAt)
				expect(visibleCount(h, component.id)).toBeGreaterThan(0)
			end)

			T.it("reports exact built instance counts in estimateCost", function()
				local h = harness()
				local _, component = build(h)
				local counts = countClasses(h:instancesOf(component.id))
				local cost = descriptorOf(typeName).estimateCost(component, HIGH)
				for key, n in counts do
					local actualPair: { any } = { key, cost[key] }
					local expectedPair: { any } = { key, n }
					expect(actualPair).toEqual(expectedPair)
				end
				expect(cost.shadowLights).toBe(0)
				expect(cost.continuousRate).toBe(0)
				expect(cost.burstCount).toBe(0)
				expect(cost.maxLifetime).toBe(0)
				expect(cost.propertyUpdates).toBeGreaterThanOrEqual(0)
				expect(cost.movingParts).toBeLessThanOrEqual(counts.parts)
				expect(cost.transparentLayers).toBeLessThanOrEqual(counts.parts + counts.beams)
				expect(cost.overdrawWeight).toBeGreaterThanOrEqual(0)
			end)

			T.it("counts its parts as moving when a position track exists", function()
				local h = harness()
				local _, component = build(h, { tracks = { position = {} } })
				local cost = descriptorOf(typeName).estimateCost(component, HIGH)
				expect(cost.movingParts).toBe(#partsOf(h, component.id))
			end)

			T.it("applies every declared non-transform channel to the instances", function()
				local h = harness()
				local c, component = build(h)
				activate(h, c)
				step(h, c, visibleAt)
				for _, sample in variant.samples do
					local before = snapshot(h, component.id, true)
					c:apply(sample[1], sample[2])
					step(h, c, visibleAt)
					local after = snapshot(h, component.id, true)
					if closeTo(after, before, EPS) then
						error("channel " .. sample[1] .. " changed nothing")
					end
				end
			end)

			T.it("ignores unknown channels, mistyped values and unknown actions", function()
				local h = harness()
				local c, component = build(h)
				activate(h, c)
				step(h, c, visibleAt)
				local before = snapshot(h, component.id, true)
				local f = h:frame(visibleAt, 1 / 60)
				c:apply("bogus", 1)
				c:apply("position", Vector3.new(5, 5, 5)) -- transform channels are composed by the Player
				c:apply("rotation", Vector3.new(0, 90, 0))
				for _, sample in variant.samples do
					c:apply(sample[1], "not a value")
				end
				c:onAction({ time = 0.5, action = "emit", count = 10, source = "event", order = 1 }, f)
				c:onAction({ time = 0.5, action = "bogus", source = "event", order = 2 }, f)
				expect(#f.moveParts).toBe(0)
				expect(snapshot(h, component.id, true)).toBeCloseTo(before, EPS)
				if fakes then
					expect(fakes:totalEmitted()).toBe(0)
				end
			end)

			T.it("moves parts only through frame.moveParts and only when the CFrame changes", function()
				local h = harness()
				h.root.CFrame = CFrame.new(5, 0, 0)
				local c, component = build(h)
				activate(h, c)
				local parts = partsOf(h, component.id)
				local before: { [any]: CFrame } = {}
				for _, p in parts do
					before[p] = p.CFrame
				end
				local localCFrame = CFrame.new(1, 2, 3) * CFrame.Angles(0, 0.5, 0.25)
				local world = h.root.CFrame * localCFrame
				local f = h:frame(0, 1 / 60)
				c:setTransform(localCFrame, world, f)
				expect(#f.moveParts).toBe(#parts)
				expect(#f.moveCFrames).toBe(#parts)
				local seen = {}
				for _, p in f.moveParts do
					expect(contains(parts, p)).toBe(true)
					expect(seen[p]).toBeNil() -- every part queued once
					seen[p] = true
				end
				-- setTransform never writes BasePart.CFrame itself (the Player batches BulkMoveTo).
				for _, p in parts do
					expect(p.CFrame).toBeCloseTo(before[p], EPS)
				end
				-- update in the same frame (a later local time, so procedural parts move again) overwrites the
				-- queued slots instead of appending twice; the last queued CFrame is the evaluated one.
				local later = visibleAt + 0.05
				if c.update then
					c:update(later, f)
				end
				expect(#f.moveParts).toBe(#parts)
				local queued: { [any]: CFrame } = {}
				for i, p in f.moveParts do
					queued[p] = f.moveCFrames[i]
				end
				h:flush(f)
				for _, p in parts do
					expect(p.CFrame).toBeCloseTo(queued[p], 1e-4) -- Lune stores part CFrames at float32 precision
				end
				for _, inst in ofClass(h, component.id, "Attachment") do
					expect(inst.Parent).toBe(h.root)
				end
				-- Unchanged CFrame and time: nothing queued.
				local f2 = h:frame(later, 1 / 60)
				c:setTransform(localCFrame, world, f2)
				if c.update then
					c:update(later, f2)
				end
				expect(#f2.moveParts).toBe(0)
				-- New CFrame: queued again.
				local f3 = h:frame(later, 1 / 60)
				c:setTransform(CFrame.new(), h.root.CFrame, f3)
				expect(#f3.moveParts).toBe(#parts)
				h:flush(f3)
			end)

			T.it("positions its geometry relative to the world CFrame", function()
				local h = harness()
				local c, component = build(h)
				activate(h, c)
				step(h, c, visibleAt)
				local reference = snapshot(h, component.id, true)
				local offset = CFrame.new(3, -2, 7) * CFrame.Angles(0.3, 1.1, -0.4)
				h.root.CFrame = CFrame.new()
				step(h, c, visibleAt, offset)
				for key, props2 in snapshot(h, component.id, true) do
					local ref = reference[key]
					if props2.CFrame then
						-- Every part / attachment moved rigidly with the transform.
						expect(props2.CFrame).toBeCloseTo(offset * ref.CFrame, 1e-3)
					end
				end
			end)

			T.it("restores the freshly built state on reset", function()
				local h = harness()
				local c, component = build(h)
				local built = snapshot(h, component.id)
				activate(h, c)
				for _, sample in variant.samples do
					c:apply(sample[1], sample[2])
				end
				c:onAction({ time = 0.2, action = "regenerate", source = "event", order = 1 }, h:frame(0.2, 0))
				step(h, c, 0.7, CFrame.new(3, 1, 0) * CFrame.Angles(0.2, 0.4, 0))
				expect(snapshot(h, component.id)).never.toBeCloseTo(built, EPS)
				c:reset()
				expect(snapshot(h, component.id)).toBeCloseTo(built, EPS)
				-- After a reset the next transform is queued again even if it equals the previous one.
				local f = h:frame(0, 1 / 60)
				c:setTransform(CFrame.new(3, 1, 0), h.root.CFrame * CFrame.new(3, 1, 0), f)
				local f2 = h:frame(0, 1 / 60)
				c:reset()
				c:setTransform(CFrame.new(3, 1, 0), h.root.CFrame * CFrame.new(3, 1, 0), f2)
				expect(#f2.moveParts).toBe(#partsOf(h, component.id))
				-- And it replays: active again => visible again.
				activate(h, c)
				step(h, c, visibleAt)
				expect(visibleCount(h, component.id)).toBeGreaterThan(0)
			end)

			T.it("hides everything on release until reset", function()
				local h = harness()
				local c, component = build(h)
				activate(h, c)
				step(h, c, visibleAt)
				expect(visibleCount(h, component.id)).toBeGreaterThan(0)
				c:release()
				expect(allHidden(h, component.id)).toBe(true)
				step(h, c, visibleAt + 0.01)
				activate(h, c)
				step(h, c, visibleAt)
				expect(allHidden(h, component.id)).toBe(true)
				c:reset()
				activate(h, c)
				step(h, c, visibleAt)
				expect(visibleCount(h, component.id)).toBeGreaterThan(0)
			end)

			T.it("evaluates t = 0.7 identically after different histories and when seeking", function()
				local final = CFrame.new(2, 1, -3) * CFrame.Angles(0.1, 0.6, 0)
				local function evaluate(history: { number }, seeking: boolean): any
					local h = harness()
					local c, component = build(h)
					activate(h, c)
					for i, t in history do
						-- Arbitrary channel values along the way ...
						for _, sample in variant.samples do
							if i % 2 == 0 then
								c:apply(sample[1], sample[2])
							end
						end
						step(h, c, t, CFrame.new(t * 10, 0, 0), i % 3 == 0)
					end
					-- ... and the same channel values in the evaluated frame.
					for _, sample in variant.samples do
						c:apply(sample[1], sample[2])
					end
					step(h, c, 0.7, final, seeking)
					return snapshot(h, component.id, true)
				end
				local reference = evaluate({}, false)
				expect(evaluate({ 0.1, 0.2, 0.9, 1.5 }, false)).toBeCloseTo(reference, 1e-6)
				expect(evaluate({ 1.9, 0.3, 0.69, 0.71 }, false)).toBeCloseTo(reference, 1e-6)
				expect(evaluate({ 0.05, 1.2, 0.699 }, true)).toBeCloseTo(reference, 1e-6)
				expect(evaluate({ 0.7, 0.7, 0.7 }, true)).toBeCloseTo(reference, 1e-6)
				if fakes then
					expect(fakes:totalEmitted()).toBe(0)
				end
			end)

			T.it(
				if variant.seeded
					then "is deterministic per seed and differs between seeds"
					else "is seed-independent and deterministic",
				function()
					local function run(seed: number): any
						local h = harness()
						local c, component = build(h, { seed = seed })
						activate(h, c)
						for _, t in { 0, 0.1, 0.35, 0.7 } do
							step(h, c, t, CFrame.new(t, 0, 0))
						end
						return snapshot(h, component.id, true)
					end
					local a = run(1)
					expect(run(1)).toBeCloseTo(a, 1e-9)
					if variant.seeded then
						expect(run(987654)).never.toBeCloseTo(a, 1e-3)
					else
						expect(run(987654)).toBeCloseTo(a, 1e-9)
					end
				end
			)

			T.it("never creates or removes instances after build", function()
				local h = harness()
				local c = build(h)
				local count = #h.container:GetDescendants()
				activate(h, c)
				for i = 0, 40 do
					local t = i * 0.05
					if i % 7 == 0 then
						for _, sample in variant.samples do
							c:apply(sample[1], sample[2])
						end
						c:onAction({ time = t, action = "regenerate", source = "event", order = i }, h:frame(t, 0))
					end
					step(h, c, t, CFrame.new(0, t, 0), i % 5 == 0)
				end
				c:release()
				c:reset()
				expect(#h.container:GetDescendants()).toBe(count)
			end)

			T.it("builds into a viewport as parts only", function()
				local h = harness()
				local c, component = build(h, { viewport = true, isPreview = true })
				for _, inst: any in h:instancesOf(component.id) do
					expect(inst:IsA("BasePart")).toBe(true)
				end
				activate(h, c)
				step(h, c, visibleAt)
				expect(visibleCount(h, component.id)).toBeGreaterThan(0)
			end)

			T.it("removes every instance on destroy and tolerates calls afterwards", function()
				local h = harness()
				local c, component = build(h)
				activate(h, c)
				step(h, c, visibleAt)
				local owned = table.clone(c.instances)
				c:destroy()
				expect(#c.instances).toBe(0)
				expect(#h:instancesOf(component.id)).toBe(0)
				for _, inst: any in owned do
					expect(inst.Parent).toBeNil()
				end
				local f = h:frame(1, 1 / 60)
				c:setActive(true, f)
				for _, sample in variant.samples do
					c:apply(sample[1], sample[2])
				end
				c:setTransform(CFrame.new(1, 0, 0), CFrame.new(1, 0, 0), f)
				if c.update then
					c:update(1, f)
				end
				c:onAction({ time = 1, action = "regenerate", source = "event", order = 1 }, f)
				c:release()
				c:reset()
				c:destroy()
				expect(#f.moveParts).toBe(0)
			end)
		end)
	end

	-- ─────────────────────────────────────────────────────────────────────────
	-- 3a. ring
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("ComponentsProcedural ring", function()
		local TAU = 2 * math.pi

		local function vertex(r: number, i: number, n: number): Vector3
			local theta = -math.pi / 2 + TAU * (i - 1) / n
			return Vector3.new(math.cos(theta), 0, math.sin(theta)) * r
		end

		local function edges(h: any, c: any, component: any, count: number): { any }
			activate(h, c)
			step(h, c, 0)
			expect(#partsOf(h, component.id)).toBe(count)
			return sequence(h, component.id, "ring_Edge", count)
		end

		-- True when the world point lies inside the part's box (tolerance eps).
		local function inside(part: any, point: Vector3, eps: number): boolean
			local p = part.CFrame:PointToObjectSpace(point)
			local half = part.Size / 2
			return math.abs(p.X) <= half.X + eps and math.abs(p.Y) <= half.Y + eps and math.abs(p.Z) <= half.Z + eps
		end

		T.it("builds one Block per edge for every style", function()
			local cases: { { any } } = {
				{ { style = "ring" }, 24 },
				{ { style = "ring", segments = 3 }, 3 },
				{ { style = "ring", segments = 128 }, 128 },
				{ { style = "polygon", points = 6 }, 6 },
				{ { style = "star", points = 5, starStep = 2 }, 5 },
				{ { style = "star", points = 6, starStep = 2 }, 6 }, -- hexagram: two triangles
				{ { style = "star", points = 6, starStep = 3 }, 3 }, -- 2k = N: three diameters
				{ { style = "star", points = 5, starStep = 5 }, 5 }, -- k ≡ 0 → polygon
				{ { style = "star", points = 5, starStep = 13 }, 5 },
				{ { style = "spokes", points = 3 }, 3 },
				{ { style = "spokes", points = 32 }, 32 },
			}
			for _, case in cases do
				local h = harness()
				local c, component = h:build("ring", case[1])
				expect(#c.instances).toBe(case[2])
				local cost = descriptorOf("ring").estimateCost(component, HIGH)
				expect(cost.parts).toBe(case[2])
				expect(cost.instances).toBe(case[2])
				for _, p in partsOf(h, component.id) do
					expect(p.Shape).toBe(Enum.PartType.Block)
					expect(p.Material).toBe(Enum.Material.Neon)
				end
			end
		end)

		T.it("lies flat in the local XZ plane with Size = (length, height, thickness)", function()
			for _, style in { "ring", "polygon", "star", "spokes" } do
				local h = harness()
				local c, component = h:build("ring", { style = style, height = 0.3, thickness = 0.4 })
				activate(h, c)
				local tilt = CFrame.new(0, 5, 0) * CFrame.Angles(0.4, 0, 0.2)
				step(h, c, 0, tilt)
				for _, p in partsOf(h, component.id) do
					local relative = tilt:ToObjectSpace(p.CFrame)
					expect(relative.Position.Y).toBeCloseTo(0, EPS)
					expect(relative.UpVector).toBeCloseTo(Vector3.new(0, 1, 0), EPS)
					expect(p.Size.Y).toBeCloseTo(0.3, EPS)
					expect(p.Size.Z).toBeCloseTo(0.4, EPS)
				end
			end
		end)

		T.it("closes the ring: neighbouring chords meet at the outer mitre with a slight overlap", function()
			local cases: { { any } } = { { "ring", 24, 4, 0.2 }, { "ring", 8, 3, 0.5 }, { "polygon", 5, 4, 0.3 } }
			for _, case in cases do
				local style, n, r, w = case[1], case[2], case[3], case[4]
				local h = harness()
				local props = { style = style, radius = r, thickness = w, segments = n, points = n }
				local c, component = h:build("ring", props)
				local parts = edges(h, c, component, n)
				local phi = math.pi / n
				local chord = 2 * r * math.sin(phi)
				local apothem = r * math.cos(phi)
				for i = 1, n do
					local edge = parts[i]
					-- Documented length: chord + w·tan φ (mitre) + 0.05·w (overlap).
					expect(edge.Size.X).toBeCloseTo(chord + w * math.tan(phi) + 0.05 * w, 1e-4)
					-- Centre on the apothem, mid-angle of v_i → v_{i+1}.
					local mid = (vertex(r, i, n) + vertex(r, i + 1, n)) / 2
					expect(edge.CFrame.Position).toBeCloseTo(mid, 1e-4)
					expect(edge.CFrame.Position.Magnitude).toBeCloseTo(apothem, 1e-4)
					-- Both corners lie on the edge's centre line.
					expect(edge.CFrame.RightVector:Cross((vertex(r, i + 1, n) - vertex(r, i, n)).Unit).Magnitude).toBeCloseTo(
						0,
						1e-4
					)
					-- The outer mitre point of the joint at v_{i+1} is covered by both neighbours.
					local nextEdge = parts[i % n + 1]
					local mitre = vertex(r, i + 1, n).Unit * ((apothem + w / 2) / math.cos(phi))
					expect(inside(edge, mitre, 1e-3)).toBe(true)
					expect(inside(nextEdge, mitre, 1e-3)).toBe(true)
					-- ... with overlap: the mitre point is strictly inside along the edge.
					local along = math.abs(edge.CFrame:PointToObjectSpace(mitre).X)
					expect(edge.Size.X / 2 - along).toBeGreaterThan(0.02 * w)
				end
			end
		end)

		T.it("starts at vertex 1 pointing forward (−Z)", function()
			local h = harness()
			local c, component = h:build("ring", { style = "polygon", points = 4, radius = 2 })
			local parts = edges(h, c, component, 4)
			-- Edge 1 joins (0, 0, −2) and (2, 0, 0).
			expect(parts[1].CFrame.Position).toBeCloseTo(Vector3.new(1, 0, -1), 1e-4)
		end)

		T.it("draws {N/k} stars with chords between vertex i and i + k", function()
			local cases: { { number } } = { { 5, 2 }, { 7, 3 }, { 8, 3 }, { 6, 2 }, { 7, 5 } }
			for _, case in cases do
				local n, step0 = case[1], case[2]
				local k = if 2 * step0 > n then n - step0 else step0
				local r = 5
				local h = harness()
				local c, component = h:build("ring", { style = "star", points = n, starStep = step0, radius = r })
				local parts = edges(h, c, component, n)
				local chord = 2 * r * math.sin(math.pi * k / n)
				for i = 1, n do
					local a, b = vertex(r, i, n), vertex(r, i + k, n)
					local edge = parts[i]
					expect(edge.CFrame.Position).toBeCloseTo((a + b) / 2, 1e-4)
					local ends =
						{ edge.CFrame * Vector3.new(-chord / 2, 0, 0), edge.CFrame * Vector3.new(chord / 2, 0, 0) }
					local matches = ((ends[1] - a).Magnitude < 1e-3 and (ends[2] - b).Magnitude < 1e-3)
						or ((ends[1] - b).Magnitude < 1e-3 and (ends[2] - a).Magnitude < 1e-3)
					expect(matches).toBe(true)
					-- Length: chord + capped mitre + overlap.
					local mitre = math.min(math.tan(math.pi * k / n), 2)
					expect(edge.Size.X).toBeCloseTo(chord + 0.2 * mitre + 0.05 * 0.2, 1e-4)
				end
			end
		end)

		T.it("draws diameters without mitre when 2·starStep = points", function()
			local h = harness()
			local c, component = h:build("ring", { style = "star", points = 4, starStep = 2, radius = 3 })
			local parts = edges(h, c, component, 2)
			for _, p in parts do
				expect(p.CFrame.Position).toBeCloseTo(Vector3.zero, 1e-4)
				expect(p.Size.X).toBeCloseTo(6 + 0.05 * 0.2, 1e-4)
			end
		end)

		T.it("draws spokes from innerRadius to radius", function()
			local h = harness()
			local c, component = h:build("ring", { style = "spokes", points = 6, innerRadius = 1, radius = 4 })
			local parts = edges(h, c, component, 6)
			for i, p in parts do
				local dir = vertex(1, i, 6)
				expect(p.CFrame.Position).toBeCloseTo(dir * 2.5, 1e-4)
				expect(p.CFrame.RightVector).toBeCloseTo(dir, 1e-4)
				expect(p.Size.X).toBeCloseTo(3, 1e-4)
			end
		end)

		T.it("applies radius, thickness and scale to the geometry", function()
			local h = harness()
			local c, component = h:build("ring", { style = "polygon", points = 4, radius = 2 }, { scale = 2 })
			local parts = edges(h, c, component, 4)
			local function lengthFor(r: number, w: number): number
				return 2 * r * math.sin(math.pi / 4) + w * math.tan(math.pi / 4) + 0.05 * w
			end
			expect(parts[1].Size.X).toBeCloseTo(lengthFor(4, 0.4), 1e-4)
			expect(parts[1].Size.Z).toBeCloseTo(0.4, 1e-4)
			expect(parts[1].Size.Y).toBeCloseTo(0.2, 1e-4)
			c:apply("radius", 3)
			step(h, c, 0)
			expect(parts[1].Size.X).toBeCloseTo(lengthFor(6, 0.4), 1e-4)
			expect(parts[1].CFrame.Position.Magnitude).toBeCloseTo(6 * math.cos(math.pi / 4), 1e-4)
			c:apply("thickness", 0.5)
			step(h, c, 0)
			expect(parts[1].Size.Z).toBeCloseTo(1, 1e-4)
			c:apply("scale", 1)
			step(h, c, 0)
			expect(parts[1].Size.X).toBeCloseTo(lengthFor(3, 0.5), 1e-4)
			expect(parts[1].Size.Y).toBeCloseTo(0.1, 1e-4)
			c:apply("scale", 0)
			expect(parts[1].Size).toBeCloseTo(Vector3.new(0.001, 0.001, 0.001), 2e-5)
		end)

		T.it("recomputes geometry only when radius, thickness or scale change (dirty flag)", function()
			local h = harness()
			local c, component = h:build("ring", { segments = 8 })
			local parts = edges(h, c, component, 8)
			local marker = Vector3.new(9, 9, 9)
			parts[1].Size = marker -- external change; the controller's cache still holds the computed size
			c:apply("transparency", 0.3)
			c:apply("color", GREEN)
			c:apply("radius", 4) -- unchanged value
			c:apply("thickness", 0.2)
			c:apply("scale", 1)
			local f = h:frame(0.5, 1 / 60)
			c:setTransform(CFrame.new(), h.root.CFrame, f)
			c:update(0.5, f)
			expect(parts[1].Size).toBeCloseTo(marker, EPS)
			expect(#f.moveParts).toBe(0)
			-- A changed radius rewrites every Size and queues every part once.
			c:apply("radius", 5)
			expect(parts[1].Size).never.toBeCloseTo(marker, EPS)
			local f2 = h:frame(0.5, 1 / 60)
			c:setTransform(CFrame.new(), h.root.CFrame, f2)
			expect(#f2.moveParts).toBe(8)
			c:update(0.5, f2)
			expect(#f2.moveParts).toBe(8)
		end)

		T.it("flushes geometry changed after setTransform from update", function()
			local h = harness()
			local c, component = h:build("ring", { segments = 6 })
			local parts = edges(h, c, component, 6)
			local f = h:frame(0.1, 1 / 60)
			c:setTransform(CFrame.new(), h.root.CFrame, f)
			expect(#f.moveParts).toBe(0)
			c:apply("radius", 8)
			c:update(0.1, f)
			expect(#f.moveParts).toBe(6)
			h:flush(f)
			expect(parts[1].CFrame.Position.Magnitude).toBeCloseTo(8 * math.cos(math.pi / 6), 1e-4)
			-- Moved transform queued by setTransform, then a geometry change in the same frame: the queued slots
			-- are overwritten (one entry per part) and hold the final CFrames.
			local moved = CFrame.new(0, 3, 0)
			local f2 = h:frame(0.2, 1 / 60)
			c:setTransform(moved, h.root.CFrame * moved, f2)
			expect(#f2.moveParts).toBe(6)
			c:apply("radius", 2)
			c:update(0.2, f2)
			expect(#f2.moveParts).toBe(6)
			h:flush(f2)
			for _, p in parts do
				expect(p.CFrame.Position.Y).toBeCloseTo(3, 1e-4)
				expect((p.CFrame.Position - Vector3.new(0, 3, 0)).Magnitude).toBeCloseTo(
					2 * math.cos(math.pi / 6),
					1e-4
				)
			end
		end)

		T.it("writes transparency and colour channels while keeping inactive parts hidden", function()
			local h = harness()
			local c, component = h:build("ring", { transparency = 0.25, color = "#00FF00" })
			local parts = partsOf(h, component.id)
			c:apply("transparency", 0.4)
			for _, p in parts do
				expect(p.Transparency).toBe(1)
				expect(p.Color).toBeCloseTo(GREEN, EPS)
			end
			activate(h, c)
			for _, p in parts do
				expect(p.Transparency).toBeCloseTo(0.4, EPS)
			end
			c:apply("transparency", 1.5) -- easing overshoot is clamped
			expect(parts[1].Transparency).toBeCloseTo(1, EPS)
			c:apply("transparency", -0.5)
			expect(parts[1].Transparency).toBeCloseTo(0, EPS)
			c:apply("color", RED)
			for _, p in parts do
				expect(p.Color).toBeCloseTo(RED, EPS)
			end
			c:reset()
			activate(h, c)
			expect(parts[1].Transparency).toBeCloseTo(0.25, EPS)
		end)

		T.it("reports spin as moving parts and Size writes for animated geometry", function()
			local d = descriptorOf("ring")
			local h = harness()
			local _, spinning = h:build("ring", { spin = { 0, 90, 0 } })
			expect(d.estimateCost(spinning, HIGH).movingParts).toBe(24)
			local _, still = h:build("ring", nil, { id = "still" })
			local stillCost = d.estimateCost(still, HIGH)
			expect(stillCost.movingParts).toBe(0)
			expect(stillCost.propertyUpdates).toBe(0)
			expect(stillCost.transparentLayers).toBe(0)
			local _, animated = h:build("ring", nil, { tracks = { radius = {}, color = {} }, id = "animated" })
			local cost = d.estimateCost(animated, HIGH)
			expect(cost.propertyUpdates).toBe(48)
			expect(cost.notes).never.toBeNil()
			local _, glass = h:build("ring", { material = "Glass" }, { id = "glass" })
			local glassCost = d.estimateCost(glass, HIGH)
			expect(glassCost.transparentLayers).toBe(24)
			expect(glassCost.overdrawWeight).toBeGreaterThan(0)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- 3b. radialBurst
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("ComponentsProcedural radialBurst", function()
		local function spikes(h: any, component: any): { any }
			return sequence(h, component.id, "radialBurst_Spike", component.props.count)
		end

		local function directionsAt(props: { [string]: any }, seed: number?): { Vector3 }
			local h = harness()
			local c, component = h:build("radialBurst", props, { seed = seed })
			activate(h, c)
			step(h, c, 0.5)
			local out = {}
			for i, p in spikes(h, component) do
				out[i] = p.CFrame.LookVector
			end
			return out
		end

		local function cubicOut(u: number): number
			return 1 - (1 - u) ^ 3
		end

		local function cubicIn(u: number): number
			return u ^ 3
		end

		T.it("builds `count` Neon blocks", function()
			for _, n in { 1, 12, 256 } do
				local h = harness()
				local c, component = h:build("radialBurst", { count = n })
				expect(#c.instances).toBe(n)
				for _, p in spikes(h, component) do
					expect(p.Shape).toBe(Enum.PartType.Block)
					expect(p.Material).toBe(Enum.Material.Neon)
				end
			end
		end)

		T.it("animates head (Cubic.Out) and tail (Cubic.In) between start and end radius", function()
			local h = harness()
			local c, component = h:build(
				"radialBurst",
				{ count = 8, startRadius = 1, endRadius = 9, width = 0.4 },
				{ endTime = 2 }
			)
			activate(h, c)
			for _, t in { 0.2, 0.5, 1, 1.3, 1.8 } do
				step(h, c, t)
				local u = t / 2
				local head = 1 + 8 * cubicOut(u)
				local tail = 1 + 8 * cubicIn(u)
				local width = 0.4 * (1 - u)
				for _, p in spikes(h, component) do
					local look = p.CFrame.LookVector
					expect(p.CFrame.Position).toBeCloseTo(look * ((head + tail) / 2), 1e-3)
					expect(p.Size).toBeCloseTo(Vector3.new(width, width, head - tail), 1e-4)
					expect(p.Transparency).toBeCloseTo(0, EPS)
					-- Tip and tail of the spike are at the head / tail distances.
					expect((p.CFrame * Vector3.new(0, 0, -p.Size.Z / 2)).Magnitude).toBeCloseTo(head, 1e-3)
					expect((p.CFrame * Vector3.new(0, 0, p.Size.Z / 2)).Magnitude).toBeCloseTo(tail, 1e-3)
				end
			end
		end)

		T.it("hides degenerate spikes at the start and end of the span", function()
			local h = harness()
			local c, component = h:build("radialBurst", nil, { endTime = 1 })
			activate(h, c)
			step(h, c, 0)
			expect(allHidden(h, component.id)).toBe(true)
			step(h, c, 0.5)
			expect(visibleCount(h, component.id)).toBe(12)
			step(h, c, 1)
			expect(allHidden(h, component.id)).toBe(true)
			step(h, c, 3)
			expect(allHidden(h, component.id)).toBe(true)
		end)

		T.it("shrinks spikes back to zero length (implosion when endRadius < startRadius)", function()
			local h = harness()
			local c, component = h:build("radialBurst", { count = 3, startRadius = 10, endRadius = 2 })
			activate(h, c)
			step(h, c, 1) -- u = 0.5: head 10 − 8·0.875 = 3, tail 10 − 8·0.125 = 9
			for _, p in spikes(h, component) do
				expect(p.Size.Z).toBeCloseTo(6, 1e-4)
				expect(p.CFrame.Position.Magnitude).toBeCloseTo(6, 1e-3)
			end
		end)

		T.it("scales radii and width with the transform scale", function()
			local h = harness()
			local c, component = h:build("radialBurst", { count = 2 }, { scale = 2 })
			activate(h, c)
			step(h, c, 1)
			local head = 0.5 + 9.5 * 0.875
			local tail = 0.5 + 9.5 * 0.125
			for _, p in spikes(h, component) do
				expect(p.Size).toBeCloseTo(Vector3.new(0.3, 0.3, 2 * (head - tail)), 1e-4)
				expect(p.CFrame.Position.Magnitude).toBeCloseTo(head + tail, 1e-3)
			end
		end)

		T.it("uses regular Fibonacci directions without jitter (seed-independent)", function()
			local n = 10
			local a = directionsAt({ count = n, jitter = 0 }, 1)
			expect(directionsAt({ count = n, jitter = 0 }, 999)).toBeCloseTo(a, 1e-6)
			local ys = {}
			for _, d in a do
				expect(d.Magnitude).toBeCloseTo(1, 1e-4)
				table.insert(ys, d.Y)
			end
			table.sort(ys)
			for i = 0, n - 1 do
				expect(ys[n - i]).toBeCloseTo(1 - 2 * (i + 0.5) / n, 1e-4)
			end
			-- An even sphere pattern has (nearly) no net direction.
			local sum = Vector3.zero
			for _, d in a do
				sum += d
			end
			expect(sum.Magnitude / n).toBeLessThan(0.1)
		end)

		T.it("keeps every distribution inside its domain, with and without jitter", function()
			for _, jitter in { 0, 0.3, 1 } do
				for _, d in directionsAt({ count = 40, distribution = "hemisphere", jitter = jitter }) do
					expect(d.Y).toBeGreaterThanOrEqual(-1e-4)
				end
				for _, d in directionsAt({ count = 40, distribution = "ring", jitter = jitter }) do
					expect(d.Y).toBeCloseTo(0, 1e-4)
				end
				for _, angle in { 10, 45, 90 } do
					for _, d in directionsAt({ count = 40, distribution = "cone", coneAngle = angle, jitter = jitter }) do
						expect(angleBetween(d, Vector3.new(0, 1, 0))).toBeLessThanOrEqual(angle + 0.05)
					end
				end
			end
		end)

		T.it("spaces ring directions evenly without jitter, starting forward", function()
			local n = 8
			local dirs = directionsAt({ count = n, distribution = "ring", jitter = 0 })
			for i, d in dirs do
				local theta = -math.pi / 2 + 2 * math.pi * (i - 1) / n
				expect(d).toBeCloseTo(Vector3.new(math.cos(theta), 0, math.sin(theta)), 1e-4)
			end
		end)

		T.it("jitter blends towards random directions deterministically", function()
			local regular = directionsAt({ count = 20, jitter = 0 }, 7)
			local jittered = directionsAt({ count = 20, jitter = 0.5 }, 7)
			expect(directionsAt({ count = 20, jitter = 0.5 }, 7)).toBeCloseTo(jittered, 1e-9)
			expect(directionsAt({ count = 20, jitter = 0.5 }, 8)).never.toBeCloseTo(jittered, 1e-3)
			local moved = 0
			for i, d in jittered do
				if angleBetween(d, regular[i]) > 1 then
					moved += 1
				end
			end
			expect(moved).toBeGreaterThan(10)
		end)

		T.it("writes transparency and colour channels", function()
			local h = harness()
			local c, component = h:build("radialBurst", { transparency = 0.2 })
			activate(h, c)
			step(h, c, 0.5)
			local parts = spikes(h, component)
			expect(parts[1].Transparency).toBeCloseTo(0.2, EPS)
			c:apply("transparency", 0.6)
			c:apply("color", RED)
			for _, p in parts do
				expect(p.Transparency).toBeCloseTo(0.6, EPS)
				expect(p.Color).toBeCloseTo(RED, EPS)
			end
			c:apply("transparency", 2)
			expect(parts[1].Transparency).toBeCloseTo(1, EPS)
		end)

		T.it("reports every spike as moving and resizing", function()
			local h = harness()
			local _, component = h:build("radialBurst", { count = 20 })
			local cost = descriptorOf("radialBurst").estimateCost(component, HIGH)
			expect(cost.movingParts).toBe(20)
			expect(cost.propertyUpdates).toBe(20)
			expect(cost.transparentLayers).toBe(0)
			local _, faded = h:build("radialBurst", { count = 20, transparency = 0.5 }, { id = "faded" })
			local fadedCost = descriptorOf("radialBurst").estimateCost(faded, HIGH)
			expect(fadedCost.transparentLayers).toBe(20)
			expect(fadedCost.overdrawWeight).toBeGreaterThan(0)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- 3c. debris
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("ComponentsProcedural debris", function()
		local function pieces(h: any, component: any): { any }
			return sequence(h, component.id, "debris_Piece", component.props.count)
		end

		-- Straight up at 20 studs/s, no spread, constant size.
		local STRAIGHT = {
			count = 3,
			spreadAngle = 0,
			speed = 20,
			direction = { 0, 1, 0 },
			gravity = { 0, -80, 0 },
			fadeTime = 0,
		}

		local function with(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
			local out = table.clone(base)
			for k, v in extra do
				out[k] = v
			end
			return out
		end

		T.it("follows p(t) = v0·t + ½·g·t² without drag", function()
			local h = harness()
			local c, component = h:build("debris", STRAIGHT)
			activate(h, c)
			for _, t in { 0, 0.1, 0.25, 0.5, 0.7, 1.3 } do
				step(h, c, t)
				for _, p in pieces(h, component) do
					expect(p.CFrame.Position).toBeCloseTo(Vector3.new(0, 20 * t - 40 * t * t, 0), 1e-3)
				end
			end
		end)

		T.it("follows the exact linear-drag formula", function()
			for _, k in { 0.5, 2, 20 } do
				local h = harness()
				local c, component = h:build("debris", with(STRAIGHT, { drag = k, direction = { 1, 1, 0 } }))
				activate(h, c)
				local v0 = Vector3.new(1, 1, 0).Unit * 20
				local g = Vector3.new(0, -80, 0)
				for _, t in { 0.1, 0.4, 0.9, 1.7 } do
					step(h, c, t)
					local e = 1 - math.exp(-k * t)
					local expected = v0 * (e / k) + g * (t / k - e / (k * k))
					for _, p in pieces(h, component) do
						expect(p.CFrame.Position).toBeCloseTo(expected, 1e-3)
					end
				end
			end
		end)

		T.it("approaches the drag-free formula as k → 0", function()
			local h = harness()
			local c, component = h:build("debris", with(STRAIGHT, { drag = 1e-4 }))
			activate(h, c)
			step(h, c, 0.6)
			expect(pieces(h, component)[1].CFrame.Position).toBeCloseTo(Vector3.new(0, 12 - 14.4, 0), 2e-3)
		end)

		T.it("throws along `direction` within `spreadAngle`", function()
			local h = harness()
			local props = { count = 40, gravity = { 0, 0, 0 }, direction = { 1, 0, 0 }, spreadAngle = 25 }
			local c, component = h:build("debris", props)
			activate(h, c)
			step(h, c, 0.5)
			for _, p in pieces(h, component) do
				local pos = p.CFrame.Position
				expect(angleBetween(pos, Vector3.new(1, 0, 0))).toBeLessThanOrEqual(25.05)
				-- speed ∈ [20, 40) → distance ∈ [10, 20) after 0.5 s
				expect(pos.Magnitude).toBeGreaterThanOrEqual(10 - 1e-3)
				expect(pos.Magnitude).toBeLessThan(20 + 1e-3)
			end
		end)

		T.it("spins each piece at its own rate about a fixed axis", function()
			local h = harness()
			local c, component = h:build("debris", with(STRAIGHT, { spinSpeed = 90 }))
			activate(h, c)
			step(h, c, 0.2)
			local first = {}
			for i, p in pieces(h, component) do
				first[i] = p.CFrame.Rotation
			end
			step(h, c, 0.7)
			for i, p in pieces(h, component) do
				local delta = p.CFrame.Rotation * first[i]:Inverse()
				expect(rotationAngle(delta)).toBeCloseTo(math.rad(45), 1e-3)
			end
			-- spinSpeed 0: orientation constant.
			local h2 = harness()
			local c2, still = h2:build("debris", with(STRAIGHT, { spinSpeed = 0 }))
			activate(h2, c2)
			step(h2, c2, 0.1)
			local r = pieces(h2, still)[1].CFrame.Rotation
			step(h2, c2, 1.1)
			expect(pieces(h2, still)[1].CFrame.Rotation).toBeCloseTo(r, 1e-4)
		end)

		T.it("rests on the floor at the analytic landing time and stops spinning", function()
			local h = harness()
			local c, component = h:build("debris", with(STRAIGHT, { floor = true, floorHeight = -2 }))
			activate(h, c)
			local landing = (20 + math.sqrt(400 + 320)) / 80 -- 20t − 40t² = −2
			step(h, c, landing - 0.01)
			local y = 20 * (landing - 0.01) - 40 * (landing - 0.01) ^ 2
			expect(pieces(h, component)[1].CFrame.Position.Y).toBeCloseTo(y, 1e-3)
			expect(y).toBeGreaterThan(-2)
			step(h, c, landing + 0.05)
			local rest = {}
			for i, p in pieces(h, component) do
				expect(p.CFrame.Position).toBeCloseTo(Vector3.new(0, -2, 0), 1e-4)
				rest[i] = p.CFrame
			end
			step(h, c, 1.9)
			for i, p in pieces(h, component) do
				expect(p.CFrame).toBeCloseTo(rest[i], 1e-5)
			end
		end)

		T.it("never lets pieces sink below the floor (drag, spread, Mixed shapes)", function()
			local h = harness()
			local props = { count = 30, floor = true, floorHeight = -1.5, drag = 1.5, spreadAngle = 120, fadeTime = 0 }
			local c, component = h:build("debris", props)
			activate(h, c)
			local landed = {}
			for i = 0, 38 do
				local t = i * 0.05
				step(h, c, t)
				for j, p in pieces(h, component) do
					local y = p.CFrame.Position.Y
					expect(y).toBeGreaterThanOrEqual(-1.5 - 1e-4)
					if math.abs(y + 1.5) < 1e-6 then
						landed[j] = true
					end
				end
			end
			-- Every piece has landed by the end of the 2 s span and is frozen.
			local frozen = {}
			for j, p in pieces(h, component) do
				expect(landed[j]).toBe(true)
				frozen[j] = p.CFrame
			end
			step(h, c, 1.99)
			for j, p in pieces(h, component) do
				expect(p.CFrame).toBeCloseTo(frozen[j], 1e-5)
			end
		end)

		T.it("stops queueing moves for pieces resting on the floor", function()
			local h = harness()
			local props = with(STRAIGHT, { count = 6, spreadAngle = 30, floor = true, floorHeight = -1 })
			local c, component = h:build("debris", props)
			activate(h, c)
			step(h, c, 1.5) -- every piece has landed (flight time < 0.8 s)
			for _, p in pieces(h, component) do
				expect(p.CFrame.Position.Y).toBeCloseTo(-1, 1e-5)
			end
			local f = h:frame(1.6, 1 / 60)
			c:setTransform(CFrame.new(), h.root.CFrame, f)
			c:update(1.6, f)
			expect(#f.moveParts).toBe(0)
			-- A piece still in the air keeps moving: only it is queued.
			local h2 = harness()
			local c2, mixed = h2:build("debris", with(STRAIGHT, { count = 1, floor = true, floorHeight = -1 }))
			activate(h2, c2)
			step(h2, c2, 0.2)
			local f2 = h2:frame(0.3, 1 / 60)
			c2:setTransform(CFrame.new(), h2.root.CFrame, f2)
			c2:update(0.3, f2)
			expect(#f2.moveParts).toBe(1)
			expect(f2.moveParts[1]).toBe(pieces(h2, mixed)[1])
		end)

		T.it("clamps pieces that start below the floor", function()
			local h = harness()
			local c, component = h:build("debris", with(STRAIGHT, { floor = true, floorHeight = 3 }))
			activate(h, c)
			step(h, c, 0.4)
			for _, p in pieces(h, component) do
				expect(p.CFrame.Position).toBeCloseTo(Vector3.new(0, 3, 0), 1e-4)
			end
		end)

		T.it("fades and shrinks during the last fadeTime seconds of the span", function()
			local h = harness()
			local c, component = h:build("debris", with(STRAIGHT, { fadeTime = 0.5, size = 1 }), { endTime = 2 })
			activate(h, c)
			step(h, c, 1)
			local p = pieces(h, component)[1]
			local full = p.Size
			expect(p.Transparency).toBeCloseTo(0, EPS)
			step(h, c, 1.5)
			expect(p.Transparency).toBeCloseTo(0, EPS)
			expect(p.Size).toBeCloseTo(full, 1e-4)
			step(h, c, 1.75)
			expect(p.Transparency).toBeCloseTo(0.5, EPS)
			expect(p.Size).toBeCloseTo(full * 0.5, 1e-4)
			c:apply("transparency", 0.4) -- t' = 1 − (1 − 0.4)(1 − 0.5)
			expect(p.Transparency).toBeCloseTo(0.7, EPS)
			step(h, c, 2)
			expect(p.Transparency).toBeCloseTo(1, EPS)
		end)

		T.it("fades over the whole span when fadeTime exceeds it", function()
			local h = harness()
			local c, component = h:build("debris", with(STRAIGHT, { fadeTime = 5 }), { endTime = 2 })
			activate(h, c)
			step(h, c, 1)
			expect(pieces(h, component)[1].Transparency).toBeCloseTo(0.5, EPS)
		end)

		T.it("draws sizes from the size range, scaled by the transform scale", function()
			local h = harness()
			local c, component = h:build("debris", { count = 50, size = { 0.5, 2 }, fadeTime = 0 }, { scale = 3 })
			activate(h, c)
			step(h, c, 0.1)
			for _, p in pieces(h, component) do
				local largest = math.max(p.Size.X, p.Size.Y, p.Size.Z)
				expect(largest).toBeGreaterThanOrEqual(1.5 - 1e-4)
				expect(largest).toBeLessThan(6 + 1e-4)
				if p.Shape == Enum.PartType.Ball then
					expect(p.Size.X).toBeCloseTo(p.Size.Y, 1e-5)
					expect(p.Size.X).toBeCloseTo(p.Size.Z, 1e-5)
				end
			end
			-- Positions scale too.
			local h2 = harness()
			local c2, scaled = h2:build("debris", STRAIGHT, { scale = 2 })
			activate(h2, c2)
			step(h2, c2, 0.25)
			expect(pieces(h2, scaled)[1].CFrame.Position).toBeCloseTo(Vector3.new(0, 2 * (5 - 2.5), 0), 1e-3)
		end)

		T.it("uses the requested shape, Mixed picks several", function()
			for _, shape in { "Block", "Wedge", "Ball" } do
				local h = harness()
				local _, component = h:build("debris", { count = 10, shape = shape })
				for _, p in pieces(h, component) do
					expect(p.Shape).toBe((Enum.PartType :: any)[shape])
				end
			end
			local h = harness()
			local _, mixed = h:build("debris", { count = 30 })
			local seen = {}
			local kinds = 0
			for _, p in pieces(h, mixed) do
				if not seen[p.Shape] then
					seen[p.Shape] = true
					kinds += 1
				end
				expect(p.Material).toBe(Enum.Material.Slate)
			end
			expect(kinds).toBe(3)
		end)

		T.it("varies piece brightness by colorVariance and keeps the factors under the colour channel", function()
			local base = Color3.fromRGB(0x6B, 0x5B, 0x4B)
			local h = harness()
			local _, uniform = h:build("debris", { colorVariance = 0 })
			for _, p in pieces(h, uniform) do
				expect(p.Color).toBeCloseTo(base, 1e-4)
			end
			local h2 = harness()
			local c2, varied = h2:build("debris", { colorVariance = 0.5, count = 20 })
			local distinct = 0
			local factors = {}
			for i, p in pieces(h2, varied) do
				local f = p.Color.R / base.R
				factors[i] = f
				expect(f).toBeGreaterThanOrEqual(0.5 - 1e-3)
				expect(f).toBeLessThan(1.5 + 1e-3)
				expect(p.Color.G / base.G).toBeCloseTo(f, 1e-3) -- same factor on every channel
				if math.abs(f - 1) > 0.01 then
					distinct += 1
				end
			end
			expect(distinct).toBeGreaterThan(10)
			c2:apply("color", Color3.new(0.5, 0.5, 0))
			for i, p in pieces(h2, varied) do
				expect(p.Color).toBeCloseTo(Color3.new(0.5 * factors[i], 0.5 * factors[i], 0), 1e-3)
			end
		end)

		T.it("gives piece i the same motion at every count (quality subsets)", function()
			local function cframes(count: number): { CFrame }
				local h = harness()
				local c, component = h:build("debris", { count = count }, { seed = 42 })
				activate(h, c)
				step(h, c, 0.4)
				local out = {}
				for i, p in pieces(h, component) do
					out[i] = p.CFrame
				end
				return out
			end
			local few = cframes(5)
			local many = cframes(12)
			for i = 1, 5 do
				expect(few[i]).toBeCloseTo(many[i], 1e-6)
			end
		end)

		T.it("reports every piece as moving and the fade writes", function()
			local d = descriptorOf("debris")
			local h = harness()
			local _, component = h:build("debris", { count = 7 })
			local cost = d.estimateCost(component, HIGH)
			expect(cost.movingParts).toBe(7)
			expect(cost.propertyUpdates).toBe(14)
			expect(cost.transparentLayers).toBe(7)
			local _, opaque = h:build("debris", { count = 7, fadeTime = 0 }, { id = "opaque" })
			local opaqueCost = d.estimateCost(opaque, HIGH)
			expect(opaqueCost.propertyUpdates).toBe(0)
			expect(opaqueCost.transparentLayers).toBe(0)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- 3d. lightning
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("ComponentsProcedural lightning", function()
		local MAIN = 12
		local BRANCH_POINTS = 5 -- round(11 × 0.35) + 1

		local function mainLine(h: any, component: any): { Vector3 }
			return polyline(h, component.id, 1, component.props.segments)
		end

		local function shapeAt(props: { [string]: any }?, t: number, seed: number?, regenerations: number?): any
			local h = harness()
			local c, component = h:build("lightning", props, { seed = seed })
			activate(h, c)
			for i = 1, regenerations or 0 do
				c:onAction({ time = 0, action = "regenerate", source = "event", order = i }, h:frame(0, 0))
			end
			step(h, c, t)
			return snapshot(h, component.id, true)
		end

		T.it("builds attachments on the Root and one Beam per sub-segment (beam render)", function()
			local h = harness()
			local c, component = h:build("lightning")
			local beams = beamsOf(h, component.id)
			local attachments = ofClass(h, component.id, "Attachment")
			expect(#attachments).toBe(MAIN + 2 * BRANCH_POINTS)
			expect(#beams).toBe((MAIN - 1) + 2 * (BRANCH_POINTS - 1))
			expect(#c.instances).toBe(#attachments + #beams)
			expect(c.instances[1]:IsA("Beam")).toBe(true)
			for _, b in beams do
				expect(b.Parent).toBe(h.root)
				expect(b.FaceCamera).toBe(true)
				expect(b.Segments).toBe(1)
				expect(b.CurveSize0).toBe(0)
				expect(b.CurveSize1).toBe(0)
				expect(b.LightEmission).toBeCloseTo(1, EPS)
				expect(b.LightInfluence).toBeCloseTo(0, EPS)
				expect(b.Brightness).toBeCloseTo(2, EPS)
				expect(b.Texture).toBe("")
				expect(b.Enabled).toBe(false)
				expect(b.Transparency).toBe(NumberSequence.new(0))
				expect(b.Color).toBe(ColorSequence.new(Color3.fromRGB(0xA8, 0xDC, 0xFF)))
				expect(contains(attachments, b.Attachment0)).toBe(true)
				expect(contains(attachments, b.Attachment1)).toBe(true)
			end
			-- Main bolt beams connect consecutive attachments with the documented widths.
			for j = 1, MAIN - 1 do
				local b = find(h, component.id, "lightning_Bolt" .. j)
				expect(b.Attachment0).toBe(find(h, component.id, "lightning_P1_" .. j))
				expect(b.Attachment1).toBe(find(h, component.id, "lightning_P1_" .. (j + 1)))
				expect(b.Width0).toBeCloseTo(0.3, EPS)
				expect(b.Width1).toBeCloseTo(0.3, EPS)
			end
			for j = MAIN, #beams do
				local b = find(h, component.id, "lightning_Bolt" .. j)
				expect(b.Width0).toBeCloseTo(0.18, EPS)
				expect(b.Width1).toBeCloseTo(0.18, EPS)
			end
			activate(h, c)
			for _, b in beams do
				expect(b.Enabled).toBe(true)
			end
		end)

		T.it("maps texture, lightEmission and brightness to the beams", function()
			local h = harness()
			local _, component = h:build("lightning", {
				texture = "rbxasset://textures/particles/sparkles_main.dds",
				lightEmission = 0.25,
				brightness = 7,
			})
			for _, b in beamsOf(h, component.id) do
				expect(b.Texture).toBe("rbxasset://textures/particles/sparkles_main.dds")
				expect(b.LightEmission).toBeCloseTo(0.25, EPS)
				expect(b.Brightness).toBeCloseTo(7, EPS)
			end
		end)

		T.it("keeps the endpoints exact and the zig-zag inside the sin(π·u) envelope", function()
			for _, seed in { 1, 2, 3, 99 } do
				local h = harness()
				local from, to = Vector3.new(1, 10, -2), Vector3.new(-3, 0, 4)
				local c, component = h:build("lightning", {
					from = { 1, 10, -2 },
					to = { -3, 0, 4 },
					jitter = 2,
					segments = 16,
				}, { seed = seed })
				activate(h, c)
				step(h, c, 0)
				local points = mainLine(h, component)
				expect(points[1]).toBeCloseTo(from, 1e-5)
				expect(points[16]).toBeCloseTo(to, 1e-5)
				local axis = to - from
				local length = axis.Magnitude
				local d = axis / length
				local maxOffset = 0
				for j = 2, 15 do
					local u = (j - 1) / 15
					local rel = points[j] - from
					-- Evenly spaced along the bolt, offset only perpendicular to it.
					expect(rel:Dot(d) / length).toBeCloseTo(u, 1e-4)
					local offset = (rel - d * rel:Dot(d)).Magnitude
					expect(offset).toBeLessThanOrEqual(2 * math.sin(math.pi * u) + 1e-4)
					maxOffset = math.max(maxOffset, offset)
				end
				expect(maxOffset).toBeGreaterThan(0.2) -- it actually zig-zags
			end
		end)

		T.it("is a straight line without jitter", function()
			local h = harness()
			local c, component = h:build("lightning", { jitter = 0, branches = 0 })
			activate(h, c)
			step(h, c, 0)
			for j, p in mainLine(h, component) do
				expect(p).toBeCloseTo(Vector3.new(0, 10 - 10 * (j - 1) / 11, 0), 1e-4)
			end
		end)

		T.it("starts branches on the main bolt with branchLength × main length", function()
			for _, seed in { 5, 6, 7 } do
				local h = harness()
				local c, component = h:build("lightning", { branches = 3, branchLength = 0.5 }, { seed = seed })
				activate(h, c)
				step(h, c, 0)
				local main = mainLine(h, component)
				local m = math.floor(11 * 0.5 + 0.5) + 1
				for b = 1, 3 do
					local branch = polyline(h, component.id, b + 1, m)
					local start = branch[1]
					local best = math.huge
					for j = 1, MAIN - 1 do
						best = math.min(best, distanceToSegment(start, main[j], main[j + 1]))
					end
					expect(best).toBeLessThan(1e-3)
					local reach = branch[m] - start
					expect(reach.Magnitude).toBeCloseTo(0.5 * 10, 1e-3)
					local angle = angleBetween(reach, Vector3.new(0, -1, 0))
					expect(angle).toBeGreaterThanOrEqual(20 - 0.01)
					expect(angle).toBeLessThanOrEqual(45 + 0.01)
				end
			end
		end)

		T.it("builds no branch instances when branches = 0 or branchLength = 0", function()
			local cases: { { [string]: any } } = { { branches = 0 }, { branchLength = 0 } }
			for _, props in cases do
				local h = harness()
				local _, component = h:build("lightning", props)
				expect(#beamsOf(h, component.id)).toBe(MAIN - 1)
				expect(#ofClass(h, component.id, "Attachment")).toBe(MAIN)
				local cost = descriptorOf("lightning").estimateCost(component, HIGH)
				expect(cost.beams).toBe(MAIN - 1)
				expect(cost.attachments).toBe(MAIN)
			end
		end)

		T.it("flickers: one shape per 1/flickerRate seconds", function()
			local a = shapeAt(nil, 0.01, 3)
			expect(shapeAt(nil, 0.04, 3)).toBeCloseTo(a, 1e-9) -- same bucket (floor(t·20) = 0)
			expect(shapeAt(nil, 0.06, 3)).never.toBeCloseTo(a, 1e-3) -- next bucket
			expect(shapeAt(nil, 0.05, 3)).toBeCloseTo(shapeAt(nil, 0.0999, 3), 1e-9) -- bucket edge is exact
		end)

		T.it("keeps a static shape when flickerRate = 0", function()
			local a = shapeAt({ flickerRate = 0 }, 0, 3)
			expect(shapeAt({ flickerRate = 0 }, 0.5, 3)).toBeCloseTo(a, 1e-9)
			expect(shapeAt({ flickerRate = 0 }, 1.7, 3)).toBeCloseTo(a, 1e-9)
		end)

		T.it("regenerates a new shape on the regenerate event; reset restores the first shape", function()
			local original = shapeAt({ flickerRate = 0 }, 0.3, 11)
			local once = shapeAt({ flickerRate = 0 }, 0.3, 11, 1)
			local twice = shapeAt({ flickerRate = 0 }, 0.3, 11, 2)
			expect(once).never.toBeCloseTo(original, 1e-3)
			expect(twice).never.toBeCloseTo(once, 1e-3)
			expect(shapeAt({ flickerRate = 0 }, 0.3, 11, 1)).toBeCloseTo(once, 1e-9)
			-- The regeneration count and the time bucket both feed the shape seed.
			expect(shapeAt(nil, 0, 11, 1)).never.toBeCloseTo(shapeAt(nil, 0.06, 11, 0), 1e-3)

			local h = harness()
			local c, component = h:build("lightning", { flickerRate = 0 }, { seed = 11 })
			activate(h, c)
			step(h, c, 0.3)
			local before = snapshot(h, component.id, true)
			expect(before).toBeCloseTo(original, 1e-9)
			local f = h:frame(0.3, 0)
			c:onAction({ time = 0.3, action = "regenerate", source = "event", order = 1 }, f)
			-- Applied immediately (the action runs after update in the Player frame).
			expect(snapshot(h, component.id, true)).toBeCloseTo(once, 1e-9)
			c:reset()
			activate(h, c)
			step(h, c, 0.3)
			expect(snapshot(h, component.id, true)).toBeCloseTo(original, 1e-9)
		end)

		T.it("regenerate in part render re-queues the moved parts in the same frame", function()
			local h = harness()
			local c = h:build("lightning", { render = "part", flickerRate = 0 })
			activate(h, c)
			step(h, c, 0.2)
			local f = h:frame(0.3, 1 / 60)
			c:setTransform(CFrame.new(), h.root.CFrame, f)
			c:update(0.3, f)
			expect(#f.moveParts).toBe(0)
			c:onAction({ time = 0.3, action = "regenerate", source = "event", order = 1 }, f)
			expect(#f.moveParts).toBeGreaterThan(0)
			local seen = {}
			for _, p in f.moveParts do
				expect(seen[p]).toBeNil()
				seen[p] = true
			end
		end)

		T.it("moves the attachments with the transform (attachment CFrame = localCFrame × point)", function()
			local h = harness()
			local c, component = h:build("lightning", { jitter = 0, branches = 0 })
			activate(h, c)
			local localCFrame = CFrame.new(4, 0, 0) * CFrame.Angles(0, 0, math.pi / 2)
			local f = h:frame(0, 1 / 60)
			c:setTransform(localCFrame, h.root.CFrame * localCFrame, f)
			c:update(0, f)
			expect(#f.moveParts).toBe(0) -- beam render moves attachments, never parts
			expect(find(h, component.id, "lightning_P1_1").CFrame).toBeCloseTo(localCFrame * CFrame.new(0, 10, 0), 1e-4)
			expect(find(h, component.id, "lightning_P1_12").CFrame).toBeCloseTo(localCFrame, 1e-4)
		end)

		T.it("applies from / to / thickness / transparency / colour channels (beam render)", function()
			local h = harness()
			local c, component = h:build("lightning")
			activate(h, c)
			step(h, c, 0)
			c:apply("from", Vector3.new(5, 5, 5))
			c:apply("to", Vector3.new(-5, 1, 0))
			expect(find(h, component.id, "lightning_P1_1").CFrame.Position).toBeCloseTo(Vector3.new(5, 5, 5), 1e-5)
			expect(find(h, component.id, "lightning_P1_12").CFrame.Position).toBeCloseTo(Vector3.new(-5, 1, 0), 1e-5)
			c:apply("thickness", 1)
			c:apply("transparency", 0.4)
			c:apply("color", GREEN)
			for j, b in sequence(h, component.id, "lightning_Bolt", 19) do
				local w = if j < MAIN then 1 else 0.6
				expect(b.Width0).toBeCloseTo(w, EPS)
				expect(b.Width1).toBeCloseTo(w, EPS)
				expect(b.Transparency.Keypoints[1].Value).toBeCloseTo(0.4, EPS)
				expect(b.Transparency.Keypoints[#b.Transparency.Keypoints].Value).toBeCloseTo(0.4, EPS)
				expect(b.Color).toBe(ColorSequence.new(GREEN))
			end
		end)

		T.it("scales the bolt with the transform scale", function()
			local h = harness()
			local c, component = h:build("lightning", { jitter = 0 }, { scale = 2 })
			activate(h, c)
			step(h, c, 0)
			expect(find(h, component.id, "lightning_P1_1").CFrame.Position).toBeCloseTo(Vector3.new(0, 20, 0), 1e-4)
			expect(find(h, component.id, "lightning_Bolt1").Width0).toBeCloseTo(0.6, EPS)
		end)

		T.it("draws Neon blocks between consecutive points (part render)", function()
			local h = harness()
			local from, to = Vector3.new(0, 10, 0), Vector3.new(0, 0, 0)
			local c, component = h:build("lightning", { render = "part" })
			expect(#beamsOf(h, component.id)).toBe(0)
			expect(#ofClass(h, component.id, "Attachment")).toBe(0)
			local parts = sequence(h, component.id, "lightning_Segment", 19)
			expect(#partsOf(h, component.id)).toBe(19)
			activate(h, c)
			step(h, c, 0)
			local function ends(p: any): (Vector3, Vector3)
				local half = p.Size.Z / 2
				return p.CFrame * Vector3.new(0, 0, half), p.CFrame * Vector3.new(0, 0, -half)
			end
			for i, p in parts do
				expect(p.Shape).toBe(Enum.PartType.Block)
				expect(p.Material).toBe(Enum.Material.Neon)
				expect(p.Color).toBeCloseTo(Color3.fromRGB(0xA8, 0xDC, 0xFF), 1e-4)
				expect(isFiniteCFrame(p.CFrame)).toBe(true)
				local w = if i < MAIN then 0.3 else 0.18
				expect(p.Size.X).toBeCloseTo(w, 1e-4)
				expect(p.Size.Y).toBeCloseTo(w, 1e-4)
			end
			-- The main bolt is a connected chain from `from` to `to`; LookVector points from a to b.
			local first = ends(parts[1])
			expect(first).toBeCloseTo(from, 1e-3)
			for i = 1, MAIN - 2 do
				local _, b = ends(parts[i])
				local a = ends(parts[i + 1])
				expect(b).toBeCloseTo(a, 1e-3)
			end
			local _, last = ends(parts[MAIN - 1])
			expect(last).toBeCloseTo(to, 1e-3)
			-- Branches start on the main chain.
			for b = 0, 1 do
				local start = ends(parts[MAIN + b * (BRANCH_POINTS - 1)])
				local best = math.huge
				for i = 1, MAIN - 1 do
					local a, z = ends(parts[i])
					best = math.min(best, distanceToSegment(start, a, z))
				end
				expect(best).toBeLessThan(1e-3)
			end
		end)

		T.it("handles a vertical straight bolt without NaN (part render)", function()
			local h = harness()
			local c, component = h:build("lightning", { render = "part", jitter = 0, branches = 0 })
			activate(h, c)
			step(h, c, 0)
			for _, p in partsOf(h, component.id) do
				expect(isFiniteCFrame(p.CFrame)).toBe(true)
				expect(p.CFrame.LookVector).toBeCloseTo(Vector3.new(0, -1, 0), 1e-4)
				expect(p.Size.Z).toBeCloseTo(10 / 11, 1e-4)
			end
			-- Degenerate bolt (from = to) stays finite too.
			local h2 = harness()
			local c2, point = h2:build("lightning", { render = "part", from = { 1, 1, 1 }, to = { 1, 1, 1 } })
			activate(h2, c2)
			step(h2, c2, 0)
			for _, p in partsOf(h2, point.id) do
				expect(isFiniteCFrame(p.CFrame)).toBe(true)
			end
		end)

		T.it("applies thickness, transparency and colour channels (part render)", function()
			local h = harness()
			local c, component = h:build("lightning", { render = "part", material = "Glass" })
			activate(h, c)
			step(h, c, 0)
			c:apply("thickness", 1)
			c:apply("transparency", 0.4)
			c:apply("color", GREEN)
			for i, p in sequence(h, component.id, "lightning_Segment", 19) do
				local w = if i < MAIN then 1 else 0.6
				expect(p.Size.X).toBeCloseTo(w, 1e-4)
				expect(p.Transparency).toBeCloseTo(0.4, EPS)
				expect(p.Color).toBeCloseTo(GREEN, EPS)
				expect(p.Material).toBe(Enum.Material.Glass)
			end
		end)

		T.it("forces part render in a viewport", function()
			local h = harness()
			local c, component = h:build("lightning", nil, { viewport = true, isPreview = true })
			expect(#beamsOf(h, component.id)).toBe(0)
			expect(#ofClass(h, component.id, "Attachment")).toBe(0)
			expect(#partsOf(h, component.id)).toBe(19)
			activate(h, c)
			step(h, c, 0)
			expect(visibleCount(h, component.id)).toBe(19)
		end)

		T.it("reports exact counts for render modes, segment and branch counts", function()
			local d = descriptorOf("lightning")
			local cases: { { [string]: any } } = {
				{},
				{ render = "part" },
				{ segments = 2, branches = 8 },
				{ segments = 64, branches = 8, branchLength = 1 },
				{ render = "part", segments = 64, branches = 8, branchLength = 1 },
				{ render = "part", segments = 2, branches = 0 },
			}
			for _, props in cases do
				local h = harness()
				local _, component = h:build("lightning", props)
				local counts = countClasses(h:instancesOf(component.id))
				local cost = d.estimateCost(component, HIGH)
				expect({ cost.instances, cost.parts, cost.attachments, cost.beams }).toEqual({
					counts.instances,
					counts.parts,
					counts.attachments,
					counts.beams,
				})
			end
			local h = harness()
			local _, static = h:build("lightning", { flickerRate = 0, render = "part" })
			expect(d.estimateCost(static, HIGH).movingParts).toBe(0)
			local _, flicker = h:build("lightning", { render = "part" }, { id = "flicker" })
			expect(d.estimateCost(flicker, HIGH).movingParts).toBe(19)
			local _, beam = h:build("lightning", nil, { id = "beam" })
			local beamCost = d.estimateCost(beam, HIGH)
			expect(beamCost.transparentLayers).toBe(19)
			expect(beamCost.notes).never.toBeNil()
		end)
	end)
end
