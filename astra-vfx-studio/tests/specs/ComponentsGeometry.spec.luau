--!strict
--[[
	Specs for the geometry component descriptors (Core/Components): part, mesh, sphere, flash, shockwave.

	Components are built with tests/specs/Helpers/ComponentHarness.luau into real Lune instances (property names and
	value types are checked against the Roblox reflection database). Lune has no renderer: these specs prove
	instance structure, property values, write caching, CFrame batching and determinism — not the visual result.
]]

return function(T: any, use: (string) -> any, ctx: any)
	local Harness = use("Tests.Specs.Helpers.ComponentHarness")
	local Components = use("AstraVFX.Core.Components")
	local Codec = use("AstraVFX.Core.Codec")
	local Easing = use("AstraVFX.Core.Easing")
	local expect = T.expect

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
	local BLUE = Color3.new(0, 0, 1)
	local CYLINDER_AXIS = CFrame.Angles(0, 0, math.pi / 2)

	local TYPES = { "part", "mesh", "sphere", "flash", "shockwave" }

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

	-- docs/COMPONENTS_SPEC.md §5, §6, §9, §10, §11 transcribed. `enum` lists are checked when given.
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
	type ExpectedType = { properties: { PropRow }, channels: { [string]: string } }
	local SPIN: PropRow = { name = "spin", kind = "vector3", default = { 0, 0, 0 } }
	local EXPECTED: { [string]: ExpectedType } = {
		part = {
			properties = {
				{
					name = "shape",
					kind = "enum",
					default = "Block",
					enumType = "PartType",
					enum = { "Block", "Ball", "Cylinder", "Wedge", "CornerWedge" },
				},
				{ name = "size", kind = "vector3", default = { 1, 1, 1 }, min = 0.001, max = 2048, scale = "length" },
				{ name = "color", kind = "color3", default = "#FFFFFF" },
				{ name = "material", kind = "enum", default = "Neon", enumType = "Material", enum = MATERIAL_LIST },
				{ name = "transparency", kind = "number", default = 0, min = 0, max = 1 },
				{ name = "reflectance", kind = "number", default = 0, min = 0, max = 1, advanced = true },
				{ name = "castShadow", kind = "boolean", default = false, advanced = true },
				SPIN,
			},
			channels = {
				position = "vector3",
				rotation = "vector3",
				scale = "number",
				size = "vector3",
				transparency = "number",
				color = "color3",
			},
		},
		mesh = {
			properties = {
				{
					name = "meshType",
					kind = "enum",
					default = "Sphere",
					enumType = "MeshType",
					enum = { "Sphere", "Cylinder", "Brick", "Wedge", "FileMesh" },
				},
				{ name = "meshId", kind = "asset", default = "" },
				{ name = "textureId", kind = "asset", default = "" },
				{ name = "partSize", kind = "vector3", default = { 1, 1, 1 }, scale = "length" },
				{ name = "meshScale", kind = "vector3", default = { 1, 1, 1 }, min = 0, max = 10000 },
				{ name = "offset", kind = "vector3", default = { 0, 0, 0 }, scale = "length" },
				{ name = "vertexColor", kind = "color3", default = "#FFFFFF" },
				{ name = "color", kind = "color3", default = "#FFFFFF" },
				{
					name = "material",
					kind = "enum",
					default = "SmoothPlastic",
					enumType = "Material",
					enum = MATERIAL_LIST,
				},
				{ name = "transparency", kind = "number", default = 0, min = 0, max = 1 },
				SPIN,
			},
			channels = {
				position = "vector3",
				rotation = "vector3",
				scale = "number",
				meshScale = "vector3",
				offset = "vector3",
				transparency = "number",
				color = "color3",
				vertexColor = "color3",
			},
		},
		sphere = {
			properties = {
				{ name = "radius", kind = "number", default = 1, min = 0.01, max = 500, scale = "length" },
				{ name = "coreColor", kind = "color3", default = "#FFFFFF" },
				{ name = "shellColor", kind = "color3", default = "#8A5CFF" },
				{ name = "coreMaterial", kind = "enum", default = "Neon", enumType = "Material", enum = MATERIAL_LIST },
				{
					name = "shellMaterial",
					kind = "enum",
					default = "ForceField",
					enumType = "Material",
					enum = MATERIAL_LIST,
				},
				{ name = "shellScale", kind = "number", default = 1.4, min = 1, max = 10 },
				{ name = "coreTransparency", kind = "number", default = 0, min = 0, max = 1 },
				{ name = "shellTransparency", kind = "number", default = 0.3, min = 0, max = 1 },
				{ name = "pulseAmplitude", kind = "number", default = 0.05, min = 0, max = 1 },
				{ name = "pulseFrequency", kind = "number", default = 4, min = 0, max = 60 },
				{ name = "light", kind = "boolean", default = true },
				{ name = "lightBrightness", kind = "number", default = 2, min = 0, max = 100 },
				{ name = "lightRange", kind = "number", default = 8, min = 0, max = 120, scale = "length" },
				SPIN,
			},
			channels = {
				position = "vector3",
				rotation = "vector3",
				scale = "number",
				radius = "number",
				transparency = "number",
				coreColor = "color3",
				shellColor = "color3",
				lightBrightness = "number",
			},
		},
		flash = {
			properties = {
				{ name = "color", kind = "color3", default = "#FFFFFF" },
				{ name = "size", kind = "number", default = 6, min = 0, max = 500, scale = "length" },
				{ name = "startSize", kind = "number", default = 1, min = 0, max = 500, scale = "length" },
				{ name = "attack", kind = "number", default = 0.03, min = 0, max = 5 },
				{ name = "hold", kind = "number", default = 0.02, min = 0, max = 5 },
				{ name = "decay", kind = "number", default = 0.25, min = 0.01, max = 10 },
				{ name = "material", kind = "enum", default = "Neon", enumType = "Material", enum = MATERIAL_LIST },
				{ name = "light", kind = "boolean", default = true },
				{ name = "peakBrightness", kind = "number", default = 10, min = 0, max = 100 },
				{ name = "range", kind = "number", default = 16, min = 0, max = 120, scale = "length" },
			},
			channels = { position = "vector3", color = "color3" },
		},
		shockwave = {
			properties = {
				{ name = "startRadius", kind = "number", default = 0.5, min = 0, max = 2000, scale = "length" },
				{ name = "endRadius", kind = "number", default = 12, min = 0, max = 2000, scale = "length" },
				{ name = "height", kind = "number", default = 0.3, min = 0.01, max = 100, scale = "length" },
				{ name = "color", kind = "color3", default = "#FFFFFF" },
				{
					name = "material",
					kind = "enum",
					default = "ForceField",
					enumType = "Material",
					enum = MATERIAL_LIST,
				},
				{ name = "startTransparency", kind = "number", default = 0, min = 0, max = 1 },
				{ name = "expandEasing", kind = "string", default = "Quart.Out" },
				{ name = "fadeEasing", kind = "string", default = "Quad.In" },
				{ name = "layers", kind = "integer", default = 1, min = 1, max = 4, quality = "segments" },
				{ name = "layerDelay", kind = "number", default = 0.05, min = 0, max = 2 },
				{ name = "layerThinning", kind = "number", default = 0.6, min = 0.05, max = 1 },
			},
			channels = { position = "vector3", rotation = "vector3", color = "color3" },
		},
	}

	-- Channel values that differ from every default (decoded form), per type.
	local SAMPLES: { [string]: { { any } } } = {
		part = {
			{ "size", Vector3.new(2, 3, 4) },
			{ "scale", 2 },
			{ "transparency", 0.5 },
			{ "color", RED },
		},
		mesh = {
			{ "scale", 2 },
			{ "meshScale", Vector3.new(2, 3, 4) },
			{ "offset", Vector3.new(0, 1, 0) },
			{ "transparency", 0.5 },
			{ "color", RED },
			{ "vertexColor", GREEN },
		},
		sphere = {
			{ "scale", 2 },
			{ "radius", 3 },
			{ "transparency", 0.5 },
			{ "coreColor", RED },
			{ "shellColor", GREEN },
			{ "lightBrightness", 7 },
		},
		flash = { { "color", RED } },
		shockwave = { { "color", RED } },
	}

	-- Local time at which the default build is visible (flash: inside the hold phase).
	local VISIBLE_AT: { [string]: number } = { part = 0, mesh = 0, sphere = 0, flash = 0.04, shockwave = 0 }

	-- Builds that must report exact instance counts.
	local COST_VARIANTS: { [string]: { { [string]: any } } } = {
		part = { {}, { shape = "Ball" } },
		mesh = { {}, { meshType = "FileMesh" } },
		sphere = { {}, { light = false } },
		flash = { {}, { light = false } },
		shockwave = { {}, { layers = 3 }, { layers = 4 } },
	}

	-- ─────────────────────────────────────────────────────────────────────────
	-- Helpers
	-- ─────────────────────────────────────────────────────────────────────────

	local function descriptorOf(typeName: string): any
		local d = Components.get(typeName)
		assert(d, "descriptor not registered: " .. typeName)
		return d
	end

	local function partsOf(h: any, id: string): { any }
		local out = {}
		for _, inst: any in h:instancesOf(id) do
			if inst:IsA("BasePart") then
				table.insert(out, inst)
			end
		end
		return out
	end

	local function lightsOf(h: any, id: string): { any }
		local out = {}
		for _, inst: any in h:instancesOf(id) do
			if inst:IsA("Light") then
				table.insert(out, inst)
			end
		end
		return out
	end

	local function find(h: any, id: string, name: string): any
		for _, inst: any in h:instancesOf(id) do
			if inst.Name == name then
				return inst
			end
		end
		error("instance not found: " .. name)
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
					Reflectance = inst.Reflectance,
					CastShadow = inst.CastShadow,
				}
				if inst:IsA("Part") then
					s.Shape = inst.Shape
				end
				if withCFrame then
					s.CFrame = inst.CFrame
				end
			elseif inst:IsA("SpecialMesh") then
				s = {
					MeshType = inst.MeshType,
					Scale = inst.Scale,
					Offset = inst.Offset,
					VertexColor = inst.VertexColor,
					MeshId = inst.MeshId,
					TextureId = inst.TextureId,
				}
			elseif inst:IsA("PointLight") then
				s = {
					Enabled = inst.Enabled,
					Brightness = inst.Brightness,
					Range = inst.Range,
					Color = inst.Color,
					Shadows = inst.Shadows,
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
		for _, l in lightsOf(h, id) do
			if l.Enabled then
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
		return n
	end

	local function contains(list: { any }, item: any): boolean
		return table.find(list, item) ~= nil
	end

	-- ─────────────────────────────────────────────────────────────────────────
	-- Contract tests shared by every geometry type
	-- ─────────────────────────────────────────────────────────────────────────

	for _, typeName in TYPES do
		local expected = EXPECTED[typeName]

		T.describe("ComponentsGeometry " .. typeName .. " contract", function()
			T.it("is a registered, viewport-capable geometry descriptor without events", function()
				local d = descriptorOf(typeName)
				expect(d.type).toBe(typeName)
				expect(d.supportsViewport).toBe(true)
				expect(d.canParent).toBe(true)
				expect(#d.events).toBe(0)
				expect(d.tailTime).toBeNil()
				expect(type(d.displayName)).toBe("string")
				expect(type(d.description)).toBe("string")
				expect(contains({ "Geometry", "Procedural" }, d.category)).toBe(true)
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
					expect(spec.kind).toBe(row.kind)
					expect(spec.default).toEqual(row.default)
					expect(spec.min).toBe(row.min)
					expect(spec.max).toBe(row.max)
					expect(spec.scale).toBe(row.scale)
					expect(spec.quality).toBe(row.quality)
					expect(spec.advanced == true).toBe(row.advanced == true)
					expect(type(spec.description)).toBe("string")
					if row.enumType then
						expect(spec.enumType).toBe(row.enumType)
						expect(spec.enum).toEqual(row.enum)
					end
				end
			end)

			T.it("declares exactly the channels of docs/COMPONENTS_SPEC.md", function()
				local d = descriptorOf(typeName)
				local count = 0
				for name, kind in expected.channels do
					count += 1
					local spec = Components.channelSpec(typeName, name)
					expect(spec).never.toBeNil()
					expect(spec.kind).toBe(kind)
					if spec.baseProperty then
						expect(Components.propertySpec(typeName, spec.baseProperty)).never.toBeNil()
					end
				end
				expect(#d.channels).toBe(count)
				local position = Components.channelSpec(typeName, "position")
				expect(position.scale).toBe("length")
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
						expect(typeof(decoded)).toBe("EnumItem")
						expect(decoded.Name).toBe(spec.default)
						for _, name in spec.enum do
							expect(typeof(Codec.decode("enum", name, spec))).toBe("EnumItem")
						end
					end
				end
			end)

			T.it("builds with defaults, tags every instance and keeps parts physics-free", function()
				local h = Harness.new(use)
				local c, component = h:build(typeName)
				expect(#c.instances).toBeGreaterThan(0)
				expect(c.component).toBe(component)
				local owned = h:instancesOf(component.id)
				expect(#owned).toBe(#c.instances)
				for _, inst: any in c.instances do
					expect(inst:GetAttribute("AstraComponent")).toBe(component.id)
					expect(inst:IsDescendantOf(h.container)).toBe(true)
				end
				local parts = partsOf(h, component.id)
				expect(#parts).toBeGreaterThan(0)
				for _, p in parts do
					expect(p.Anchored).toBe(true)
					expect(p.CanCollide).toBe(false)
					expect(p.CanQuery).toBe(false)
					expect(p.CanTouch).toBe(false)
					expect(p.CastShadow).toBe(false)
					expect(p.Massless).toBe(true)
				end
				h:cleanup()
			end)

			T.it("is invisible until setActive(true) and hidden again by setActive(false)", function()
				local h = Harness.new(use)
				local c, component = h:build(typeName)
				expect(allHidden(h, component.id)).toBe(true)
				-- Frames while inactive must not reveal anything either.
				step(h, c, VISIBLE_AT[typeName])
				expect(allHidden(h, component.id)).toBe(true)
				activate(h, c)
				step(h, c, VISIBLE_AT[typeName])
				expect(visibleCount(h, component.id)).toBeGreaterThan(0)
				for _, l in lightsOf(h, component.id) do
					expect(l.Enabled).toBe(true)
				end
				c:setActive(false, h:frame(0.1, 0))
				expect(allHidden(h, component.id)).toBe(true)
				activate(h, c)
				expect(visibleCount(h, component.id)).toBeGreaterThan(0)
				h:cleanup()
			end)

			T.it("reports exact built instance counts in estimateCost", function()
				local d = descriptorOf(typeName)
				for _, props in COST_VARIANTS[typeName] do
					local h = Harness.new(use)
					local _, component = h:build(typeName, props)
					local counts = countClasses(h:instancesOf(component.id))
					local cost = d.estimateCost(component, HIGH)
					for key, n in counts do
						local actualPair: { any } = { key, cost[key] }
						local expectedPair: { any } = { key, n }
						expect(actualPair).toEqual(expectedPair)
					end
					expect(cost.shadowLights).toBe(0)
					expect(cost.continuousRate).toBe(0)
					expect(cost.burstCount).toBe(0)
					expect(cost.movingParts).toBe(0) -- no transform tracks, no spin
					expect(cost.propertyUpdates).toBeGreaterThanOrEqual(0)
					expect(cost.transparentLayers).toBeLessThanOrEqual(counts.parts)
					h:cleanup()
				end
			end)

			T.it("counts every part as moving when a position track exists", function()
				local d = descriptorOf(typeName)
				local h = Harness.new(use)
				local _, component = h:build(typeName, nil, { tracks = { position = {} } })
				local cost = d.estimateCost(component, HIGH)
				expect(cost.movingParts).toBe(#partsOf(h, component.id))
				h:cleanup()
			end)

			T.it("applies every declared non-transform channel to the instances", function()
				local h = Harness.new(use)
				local c, component = h:build(typeName)
				activate(h, c)
				step(h, c, VISIBLE_AT[typeName])
				for _, sample in SAMPLES[typeName] do
					local before = snapshot(h, component.id)
					c:apply(sample[1], sample[2])
					local after = snapshot(h, component.id)
					local changed = false
					for key, props in after do
						for prop, value in props do
							if before[key][prop] ~= value then
								changed = true
							end
						end
					end
					if not changed then
						error("channel " .. sample[1] .. " changed nothing")
					end
				end
				h:cleanup()
			end)

			T.it("ignores unknown channels, mistyped values and actions", function()
				local h = Harness.new(use)
				local c, component = h:build(typeName)
				activate(h, c)
				step(h, c, VISIBLE_AT[typeName])
				local before = snapshot(h, component.id, true)
				c:apply("bogus", 1)
				c:apply("position", Vector3.new(5, 5, 5)) -- transform channels are composed by the Player
				c:apply("rotation", Vector3.new(0, 90, 0))
				for _, sample in SAMPLES[typeName] do
					c:apply(sample[1], "not a value")
				end
				local f = h:frame(0.5, 1 / 60)
				c:onAction({ time = 0.5, action = "emit", count = 10, source = "event", order = 1 }, f)
				expect(#f.moveParts).toBe(0)
				expect(snapshot(h, component.id, true)).toBeCloseTo(before, EPS)
				if ctx.fakes then
					expect(ctx.fakes:totalEmitted()).toBe(0)
				end
				h:cleanup()
			end)

			T.it("moves parts only through frame.moveParts and only when the CFrame changes", function()
				local h = Harness.new(use)
				h.root.CFrame = CFrame.new(5, 0, 0)
				local c, component = h:build(typeName)
				activate(h, c)
				local parts = partsOf(h, component.id)
				local initial = parts[1].CFrame
				local localCFrame = CFrame.new(1, 2, 3) * CFrame.Angles(0, 0.5, 0.25)
				local world = h.root.CFrame * localCFrame
				local f = h:frame(0, 1 / 60)
				c:setTransform(localCFrame, world, f)
				expect(#f.moveParts).toBe(#parts)
				expect(#f.moveCFrames).toBe(#parts)
				local expectedCFrame = if typeName == "shockwave" then world * CYLINDER_AXIS else world
				for i, p in f.moveParts do
					expect(contains(parts, p)).toBe(true)
					expect(f.moveCFrames[i]).toBeCloseTo(expectedCFrame, EPS)
				end
				-- setTransform never writes BasePart.CFrame itself (the Player batches BulkMoveTo).
				expect(parts[1].CFrame).toBeCloseTo(initial, EPS)
				h:flush(f)
				for _, p in parts do
					expect(p.CFrame).toBeCloseTo(expectedCFrame, EPS)
				end
				for _, inst: any in h:instancesOf(component.id) do
					if inst:IsA("Attachment") then
						expect(inst.Parent).toBe(h.root)
						expect(inst.CFrame).toBeCloseTo(localCFrame, EPS)
					end
				end
				-- Unchanged CFrame: nothing queued.
				local f2 = h:frame(1 / 60, 1 / 60)
				c:setTransform(localCFrame, world, f2)
				expect(#f2.moveParts).toBe(0)
				-- New CFrame: queued again.
				local f3 = h:frame(2 / 60, 1 / 60)
				c:setTransform(CFrame.new(), h.root.CFrame, f3)
				expect(#f3.moveParts).toBe(#parts)
				h:flush(f3)
				h:cleanup()
			end)

			T.it("restores the freshly built state on reset", function()
				local h = Harness.new(use)
				local c, component = h:build(typeName)
				local built = snapshot(h, component.id)
				activate(h, c)
				for _, sample in SAMPLES[typeName] do
					c:apply(sample[1], sample[2])
				end
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
				step(h, c, VISIBLE_AT[typeName])
				expect(visibleCount(h, component.id)).toBeGreaterThan(0)
				h:cleanup()
			end)

			T.it("hides everything on release until reset", function()
				local h = Harness.new(use)
				local c, component = h:build(typeName)
				activate(h, c)
				step(h, c, VISIBLE_AT[typeName])
				expect(visibleCount(h, component.id)).toBeGreaterThan(0)
				c:release()
				expect(allHidden(h, component.id)).toBe(true)
				step(h, c, VISIBLE_AT[typeName] + 0.01)
				activate(h, c)
				step(h, c, VISIBLE_AT[typeName])
				expect(allHidden(h, component.id)).toBe(true)
				c:reset()
				activate(h, c)
				step(h, c, VISIBLE_AT[typeName])
				expect(visibleCount(h, component.id)).toBeGreaterThan(0)
				h:cleanup()
			end)

			T.it("builds into a viewport without lights", function()
				local h = Harness.new(use)
				local c, component = h:build(typeName, nil, { viewport = true, isPreview = true })
				expect(#lightsOf(h, component.id)).toBe(0)
				for _, inst: any in h:instancesOf(component.id) do
					expect(inst:IsA("BasePart") or inst:IsA("SpecialMesh")).toBe(true)
				end
				activate(h, c)
				step(h, c, VISIBLE_AT[typeName])
				expect(visibleCount(h, component.id)).toBeGreaterThan(0)
				h:cleanup()
			end)

			T.it("is seed-independent and deterministic (no random element)", function()
				local function run(seed: number): any
					local h = Harness.new(use)
					local c, component = h:build(typeName, nil, { seed = seed })
					activate(h, c)
					for _, t in { 0, 0.1, 0.35, 0.7 } do
						step(h, c, t, CFrame.new(t, 0, 0))
					end
					local s = snapshot(h, component.id, true)
					h:cleanup()
					return s
				end
				local a = run(1)
				expect(run(1)).toBeCloseTo(a, 1e-9)
				expect(run(987654)).toBeCloseTo(a, 1e-9)
			end)

			T.it("removes every instance on destroy and tolerates calls afterwards", function()
				local h = Harness.new(use)
				local c, component = h:build(typeName)
				activate(h, c)
				step(h, c, VISIBLE_AT[typeName])
				local owned = table.clone(c.instances)
				c:destroy()
				expect(#c.instances).toBe(0)
				expect(#h:instancesOf(component.id)).toBe(0)
				for _, inst: any in owned do
					expect(inst.Parent).toBeNil()
				end
				local f = h:frame(1, 1 / 60)
				c:setActive(true, f)
				for _, sample in SAMPLES[typeName] do
					c:apply(sample[1], sample[2])
				end
				c:setTransform(CFrame.new(1, 0, 0), CFrame.new(1, 0, 0), f)
				if c.update then
					c:update(1, f)
				end
				c:release()
				c:reset()
				c:destroy()
				expect(#f.moveParts).toBe(0)
				h:cleanup()
			end)
		end)
	end

	-- Procedural types: update(localTime) is a pure function of (localTime, props, channel values).
	for _, typeName in { "sphere", "flash", "shockwave" } do
		T.describe("ComponentsGeometry " .. typeName .. " determinism", function()
			T.it("evaluates t = 0.7 identically after different histories and when seeking", function()
				local final = CFrame.new(2, 1, -3) * CFrame.Angles(0.1, 0.6, 0)
				local function evaluate(history: { number }, seeking: boolean): any
					local h = Harness.new(use)
					local c, component = h:build(typeName)
					activate(h, c)
					for i, t in history do
						-- Arbitrary channel values along the way ...
						for _, sample in SAMPLES[typeName] do
							if i % 2 == 0 then
								c:apply(sample[1], sample[2])
							end
						end
						step(h, c, t, CFrame.new(t * 10, 0, 0))
					end
					-- ... and the same channel values in the evaluated frame.
					for _, sample in SAMPLES[typeName] do
						c:apply(sample[1], sample[2])
					end
					step(h, c, 0.7, final, seeking)
					local s = snapshot(h, component.id, true)
					h:cleanup()
					return s
				end
				local reference = evaluate({}, false)
				expect(evaluate({ 0.1, 0.2, 0.9, 1.5 }, false)).toBeCloseTo(reference, 1e-6)
				expect(evaluate({ 1.9, 0.3, 0.69, 0.71 }, false)).toBeCloseTo(reference, 1e-6)
				expect(evaluate({ 0.05, 1.2 }, true)).toBeCloseTo(reference, 1e-6)
				if ctx.fakes then
					expect(ctx.fakes:totalEmitted()).toBe(0)
				end
			end)
		end)
	end

	-- ─────────────────────────────────────────────────────────────────────────
	-- part
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("ComponentsGeometry part", function()
		T.it("maps every shape to Enum.PartType", function()
			for _, shape in { "Block", "Ball", "Cylinder", "Wedge", "CornerWedge" } do
				local h = Harness.new(use)
				local c = h:build("part", { shape = shape })
				expect(c.instances[1].ClassName).toBe("Part")
				expect(c.instances[1].Shape).toBe((Enum.PartType :: any)[shape])
				h:cleanup()
			end
		end)

		T.it("defaults to a Neon 1×1×1 white opaque block", function()
			local h = Harness.new(use)
			local c = h:build("part")
			local p = c.instances[1]
			activate(h, c)
			expect(p.Shape).toBe(Enum.PartType.Block)
			expect(p.Material).toBe(Enum.Material.Neon)
			expect(p.Size).toBeCloseTo(Vector3.new(1, 1, 1), EPS)
			expect(p.Color).toBeCloseTo(Color3.new(1, 1, 1), EPS)
			expect(p.Transparency).toBeCloseTo(0, EPS)
			expect(p.Reflectance).toBeCloseTo(0, EPS)
			expect(p.CastShadow).toBe(false)
			expect(c.update).toBeNil()
			h:cleanup()
		end)

		T.it("maps material, colour, transparency, reflectance and castShadow", function()
			local h = Harness.new(use)
			local c = h:build("part", {
				material = "Glass",
				color = "#FF0000",
				transparency = 0.25,
				reflectance = 0.5,
				castShadow = true,
			})
			local p = c.instances[1]
			expect(p.Transparency).toBe(1)
			activate(h, c)
			expect(p.Material).toBe(Enum.Material.Glass)
			expect(p.Color).toBeCloseTo(RED, EPS)
			expect(p.Transparency).toBeCloseTo(0.25, EPS)
			expect(p.Reflectance).toBeCloseTo(0.5, EPS)
			expect(p.CastShadow).toBe(true)
			h:cleanup()
		end)

		T.it("multiplies size by the component scale (rest value and channel)", function()
			local h = Harness.new(use)
			local c = h:build("part", { size = { 2, 3, 4 } }, { scale = 2 })
			local p = c.instances[1]
			expect(p.Size).toBeCloseTo(Vector3.new(4, 6, 8), EPS)
			c:apply("scale", 0.5)
			expect(p.Size).toBeCloseTo(Vector3.new(1, 1.5, 2), EPS)
			c:apply("size", Vector3.new(10, 1, 1)) -- absolute size, still × scale
			expect(p.Size).toBeCloseTo(Vector3.new(5, 0.5, 0.5), EPS)
			c:apply("scale", 0)
			expect(p.Size).toBeCloseTo(Vector3.new(0.001, 0.001, 0.001), 2e-5) -- Lune stores tiny sizes imprecisely
			h:cleanup()
		end)

		T.it("clamps sizes to the engine range 0.001..2048", function()
			local h = Harness.new(use)
			local c = h:build("part")
			c:apply("size", Vector3.new(5000, 0, -3))
			expect(c.instances[1].Size).toBeCloseTo(Vector3.new(2048, 0.001, 0.001), 2e-5)
			h:cleanup()
		end)

		T.it("writes transparency and colour channels while keeping inactive parts hidden", function()
			local h = Harness.new(use)
			local c = h:build("part")
			local p = c.instances[1]
			c:apply("transparency", 0.4)
			expect(p.Transparency).toBe(1)
			activate(h, c)
			expect(p.Transparency).toBeCloseTo(0.4, EPS)
			c:apply("transparency", 1.5) -- easing overshoot is clamped
			expect(p.Transparency).toBeCloseTo(1, EPS)
			c:apply("transparency", -0.5)
			expect(p.Transparency).toBeCloseTo(0, EPS)
			c:apply("color", BLUE)
			expect(p.Color).toBeCloseTo(BLUE, EPS)
			h:cleanup()
		end)

		T.it("skips writes of unchanged values", function()
			local h = Harness.new(use)
			local c = h:build("part")
			local p = c.instances[1]
			activate(h, c)
			c:apply("color", RED)
			p.Color = BLUE -- external change; the controller's cache still says RED
			c:apply("color", RED)
			expect(p.Color).toBeCloseTo(BLUE, EPS)
			c:apply("color", GREEN)
			expect(p.Color).toBeCloseTo(GREEN, EPS)
			c:apply("size", Vector3.new(2, 2, 2))
			p.Size = Vector3.new(9, 9, 9)
			c:apply("size", Vector3.new(2, 2, 2))
			expect(p.Size).toBeCloseTo(Vector3.new(9, 9, 9), EPS)
			h:cleanup()
		end)

		T.it("reports moving parts for spin and Size writes for size tracks", function()
			local d = descriptorOf("part")
			local h = Harness.new(use)
			local _, spinning = h:build("part", { spin = { 0, 90, 0 } })
			expect(d.estimateCost(spinning, HIGH).movingParts).toBe(1)
			local _, sized = h:build("part", nil, { tracks = { size = {}, color = {} }, id = "sized" })
			local cost = d.estimateCost(sized, HIGH)
			expect(cost.propertyUpdates).toBe(2)
			expect(cost.notes).never.toBeNil()
			local _, glass = h:build("part", { material = "Glass", size = { 2, 4, 2 } }, { id = "glass" })
			local glassCost = d.estimateCost(glass, HIGH)
			expect(glassCost.transparentLayers).toBe(1)
			expect(glassCost.overdrawWeight).toBeCloseTo(16, EPS)
			h:cleanup()
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- mesh
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("ComponentsGeometry mesh", function()
		T.it("builds a Part with an explicit SpecialMesh type (never the Head default)", function()
			local h = Harness.new(use)
			local c, component = h:build("mesh")
			local part = c.instances[1]
			local mesh = c.instances[2]
			expect(part.ClassName).toBe("Part")
			expect(mesh.ClassName).toBe("SpecialMesh")
			expect(mesh.Parent).toBe(part)
			expect(mesh.MeshType).toBe(Enum.MeshType.Sphere)
			expect(mesh.MeshId).toBe("")
			expect(mesh.TextureId).toBe("")
			expect(part.Size).toBeCloseTo(Vector3.new(1, 1, 1), EPS)
			expect(part.Material).toBe(Enum.Material.SmoothPlastic)
			expect(mesh.Scale).toBeCloseTo(Vector3.new(1, 1, 1), EPS)
			expect(mesh.Offset).toBeCloseTo(Vector3.zero, EPS)
			expect(mesh.VertexColor).toBeCloseTo(Vector3.new(1, 1, 1), EPS)
			expect(find(h, component.id, "Mesh")).toBe(mesh)
			expect(c.update).toBeNil()
			h:cleanup()
		end)

		T.it("maps every meshType to Enum.MeshType", function()
			for _, meshType in { "Sphere", "Cylinder", "Brick", "Wedge", "FileMesh" } do
				local h = Harness.new(use)
				local c = h:build("mesh", { meshType = meshType })
				expect(c.instances[2].MeshType).toBe((Enum.MeshType :: any)[meshType])
				h:cleanup()
			end
		end)

		T.it("builds an empty FileMesh without meshId and flags it in the cost notes", function()
			local h = Harness.new(use)
			local c, component = h:build("mesh", { meshType = "FileMesh" })
			expect(c.instances[2].MeshType).toBe(Enum.MeshType.FileMesh)
			expect(c.instances[2].MeshId).toBe("")
			local cost = descriptorOf("mesh").estimateCost(component, HIGH)
			expect(cost.notes).never.toBeNil()
			local found = false
			for _, note in cost.notes do
				if string.find(note, "meshId", 1, true) then
					found = true
				end
			end
			expect(found).toBe(true)
			h:cleanup()
		end)

		T.it("writes meshId and textureId to the SpecialMesh", function()
			local h = Harness.new(use)
			local c = h:build("mesh", {
				meshType = "FileMesh",
				meshId = "rbxassetid://123",
				textureId = 456,
			})
			expect(c.instances[2].MeshId).toBe("rbxassetid://123")
			expect(c.instances[2].TextureId).toBe("rbxassetid://456")
			h:cleanup()
		end)

		T.it("animates SpecialMesh.Scale = meshScale × scale and keeps Part.Size constant", function()
			local h = Harness.new(use)
			local c = h:build("mesh", { meshScale = { 2, 1, 3 }, partSize = { 4, 4, 4 } }, { scale = 2 })
			local part, mesh = c.instances[1], c.instances[2]
			expect(mesh.Scale).toBeCloseTo(Vector3.new(4, 2, 6), EPS)
			expect(part.Size).toBeCloseTo(Vector3.new(4, 4, 4), EPS)
			c:apply("scale", 0.5)
			expect(mesh.Scale).toBeCloseTo(Vector3.new(1, 0.5, 1.5), EPS)
			c:apply("meshScale", Vector3.new(4, 4, 4))
			expect(mesh.Scale).toBeCloseTo(Vector3.new(2, 2, 2), EPS)
			c:apply("meshScale", Vector3.new(-1, 1, 1)) -- negative scale is clamped to 0
			expect(mesh.Scale).toBeCloseTo(Vector3.new(0, 0.5, 0.5), EPS)
			expect(part.Size).toBeCloseTo(Vector3.new(4, 4, 4), EPS)
			h:cleanup()
		end)

		T.it("scales the offset with the mesh", function()
			local h = Harness.new(use)
			local c = h:build("mesh", { offset = { 0, 1, 0 } }, { scale = 2 })
			local mesh = c.instances[2]
			expect(mesh.Offset).toBeCloseTo(Vector3.new(0, 2, 0), EPS)
			c:apply("offset", Vector3.new(1, 0, -1))
			expect(mesh.Offset).toBeCloseTo(Vector3.new(2, 0, -2), EPS)
			h:cleanup()
		end)

		T.it("writes vertexColor as a Vector3 and colour/transparency to the Part", function()
			local h = Harness.new(use)
			local c = h:build("mesh", { vertexColor = "#FF8000", transparency = 0.2 })
			local part, mesh = c.instances[1], c.instances[2]
			expect(mesh.VertexColor).toBeCloseTo(Vector3.new(1, 128 / 255, 0), EPS)
			c:apply("vertexColor", Color3.new(0, 0.5, 1))
			expect(mesh.VertexColor).toBeCloseTo(Vector3.new(0, 0.5, 1), EPS)
			activate(h, c)
			expect(part.Transparency).toBeCloseTo(0.2, EPS)
			c:apply("transparency", 0.6)
			expect(part.Transparency).toBeCloseTo(0.6, EPS)
			c:apply("color", RED)
			expect(part.Color).toBeCloseTo(RED, EPS)
			h:cleanup()
		end)

		T.it("applies the effect scale to FileMesh scale only", function()
			local d = descriptorOf("mesh")
			local cases: { { any } } = { { "FileMesh", 6 }, { "Sphere", 2 } }
			for _, case in cases do
				local h = Harness.new(use)
				local component = h:compile("mesh", { meshType = case[1], meshScale = { 2, 2, 2 } })
				local buildContext = h:context({ [component.id] = component })
				buildContext.effect.scale = 3
				local c = d.build(buildContext, component)
				table.insert(h.controllers, c)
				expect(c.instances[2].Scale).toBeCloseTo(Vector3.new(case[2], case[2], case[2]), EPS)
				h:cleanup()
			end
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- sphere
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("ComponentsGeometry sphere", function()
		T.it("builds a core and a shell Ball plus a PointLight on an Attachment", function()
			local h = Harness.new(use)
			local c, component = h:build("sphere")
			local core = find(h, component.id, "sphere_Core")
			local shell = find(h, component.id, "sphere_Shell")
			local attachment = find(h, component.id, "sphere_Light")
			local light = find(h, component.id, "Light")
			expect(core.Shape).toBe(Enum.PartType.Ball)
			expect(shell.Shape).toBe(Enum.PartType.Ball)
			expect(core.Material).toBe(Enum.Material.Neon)
			expect(shell.Material).toBe(Enum.Material.ForceField)
			expect(attachment.ClassName).toBe("Attachment")
			expect(attachment.Parent).toBe(h.root)
			expect(light.ClassName).toBe("PointLight")
			expect(light.Parent).toBe(attachment)
			expect(light.Enabled).toBe(false)
			expect(light.Shadows).toBe(false)
			activate(h, c)
			step(h, c, 0)
			expect(core.Size).toBeCloseTo(Vector3.new(2, 2, 2), EPS)
			expect(shell.Size).toBeCloseTo(Vector3.new(2.8, 2.8, 2.8), EPS)
			expect(core.Transparency).toBeCloseTo(0, EPS)
			expect(shell.Transparency).toBeCloseTo(0.3, EPS)
			expect(core.Color).toBeCloseTo(Color3.new(1, 1, 1), EPS)
			expect(shell.Color).toBeCloseTo(Color3.fromRGB(0x8A, 0x5C, 0xFF), EPS)
			expect(light.Enabled).toBe(true)
			expect(light.Brightness).toBeCloseTo(2, EPS)
			expect(light.Range).toBeCloseTo(8, EPS)
			expect(light.Color).toBeCloseTo(Color3.fromRGB(0x8A, 0x5C, 0xFF), EPS)
			h:cleanup()
		end)

		T.it("pulses the radius: radius × (1 + amplitude × sin(2π·f·t))", function()
			local h = Harness.new(use)
			local c, component = h:build("sphere", { radius = 2, pulseAmplitude = 0.1, pulseFrequency = 4 })
			local core = find(h, component.id, "sphere_Core")
			local shell = find(h, component.id, "sphere_Shell")
			activate(h, c)
			for _, t in { 0, 1 / 16, 3 / 16, 0.1, 0.7, 1.33 } do
				step(h, c, t)
				local r = 2 * (1 + 0.1 * math.sin(2 * math.pi * 4 * t))
				expect(core.Size).toBeCloseTo(Vector3.new(2 * r, 2 * r, 2 * r), EPS)
				expect(shell.Size.X).toBeCloseTo(2 * r * 1.4, EPS)
			end
			step(h, c, 1 / 16)
			expect(core.Size.X).toBeCloseTo(4.4, EPS) -- peak of the sine
			step(h, c, 3 / 16)
			expect(core.Size.X).toBeCloseTo(3.6, EPS) -- trough
			h:cleanup()
		end)

		T.it("does not pulse when the amplitude or frequency is 0", function()
			local variants: { { [string]: any } } = { { pulseAmplitude = 0 }, { pulseFrequency = 0 } }
			for _, props in variants do
				local h = Harness.new(use)
				local c, component = h:build("sphere", props)
				activate(h, c)
				step(h, c, 1 / 16)
				expect(find(h, component.id, "sphere_Core").Size.X).toBeCloseTo(2, EPS)
				h:cleanup()
			end
		end)

		T.it("applies the radius and scale channels to both layers and the light range", function()
			local h = Harness.new(use)
			local c, component = h:build("sphere", { pulseAmplitude = 0, shellScale = 2 }, { scale = 2 })
			local core = find(h, component.id, "sphere_Core")
			local shell = find(h, component.id, "sphere_Shell")
			local light = find(h, component.id, "Light")
			expect(core.Size.X).toBeCloseTo(4, EPS)
			expect(light.Range).toBeCloseTo(16, EPS)
			c:apply("radius", 3)
			expect(core.Size.X).toBeCloseTo(12, EPS)
			expect(shell.Size.X).toBeCloseTo(24, EPS)
			c:apply("scale", 0.5)
			expect(core.Size.X).toBeCloseTo(3, EPS)
			expect(light.Range).toBeCloseTo(4, EPS)
			c:apply("scale", 100)
			expect(light.Range).toBeCloseTo(120, EPS) -- engine maximum
			expect(core.Size.X).toBeCloseTo(600, EPS)
			h:cleanup()
		end)

		T.it("fades both layers with t' = 1 − (1 − t)(1 − v) and dims the light", function()
			local h = Harness.new(use)
			local c, component = h:build("sphere", { coreTransparency = 0.2, shellTransparency = 0.4 })
			local core = find(h, component.id, "sphere_Core")
			local shell = find(h, component.id, "sphere_Shell")
			local light = find(h, component.id, "Light")
			activate(h, c)
			c:apply("transparency", 0.5)
			expect(core.Transparency).toBeCloseTo(1 - 0.8 * 0.5, EPS)
			expect(shell.Transparency).toBeCloseTo(1 - 0.6 * 0.5, EPS)
			expect(light.Brightness).toBeCloseTo(1, EPS)
			c:apply("transparency", 1)
			expect(core.Transparency).toBeCloseTo(1, EPS)
			expect(shell.Transparency).toBeCloseTo(1, EPS)
			expect(light.Brightness).toBeCloseTo(0, EPS)
			c:apply("transparency", 0)
			expect(core.Transparency).toBeCloseTo(0.2, EPS)
			h:cleanup()
		end)

		T.it("applies colour and light brightness channels", function()
			local h = Harness.new(use)
			local c, component = h:build("sphere")
			local core = find(h, component.id, "sphere_Core")
			local shell = find(h, component.id, "sphere_Shell")
			local light = find(h, component.id, "Light")
			activate(h, c)
			c:apply("coreColor", RED)
			c:apply("shellColor", GREEN)
			c:apply("lightBrightness", 7)
			expect(core.Color).toBeCloseTo(RED, EPS)
			expect(shell.Color).toBeCloseTo(GREEN, EPS)
			expect(light.Color).toBeCloseTo(GREEN, EPS)
			expect(light.Brightness).toBeCloseTo(7, EPS)
			h:cleanup()
		end)

		T.it("builds no light when light = false", function()
			local h = Harness.new(use)
			local c, component = h:build("sphere", { light = false })
			expect(#c.instances).toBe(2)
			expect(#lightsOf(h, component.id)).toBe(0)
			activate(h, c)
			c:apply("lightBrightness", 5)
			step(h, c, 0.2, CFrame.new(1, 0, 0))
			expect(visibleCount(h, component.id)).toBe(2)
			h:cleanup()
		end)

		T.it("estimates pulse Size writes and translucent layers", function()
			local d = descriptorOf("sphere")
			local h = Harness.new(use)
			local _, pulsing = h:build("sphere")
			local cost = d.estimateCost(pulsing, HIGH)
			expect(cost.propertyUpdates).toBe(2)
			expect(cost.transparentLayers).toBe(1) -- ForceField shell (opaque Neon core)
			local _, still = h:build("sphere", { pulseAmplitude = 0 }, { id = "still" })
			expect(d.estimateCost(still, HIGH).propertyUpdates).toBe(0)
			h:cleanup()
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- flash
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("ComponentsGeometry flash", function()
		T.it("builds a Neon Ball and a PointLight on an Attachment", function()
			local h = Harness.new(use)
			local _, component = h:build("flash")
			local ball = find(h, component.id, "flash")
			local light = find(h, component.id, "Light")
			expect(ball.Shape).toBe(Enum.PartType.Ball)
			expect(ball.Material).toBe(Enum.Material.Neon)
			expect(light.Parent).toBe(find(h, component.id, "flash_Light"))
			expect(light.Parent.Parent).toBe(h.root)
			expect(light.Range).toBeCloseTo(16, EPS)
			expect(light.Enabled).toBe(false)
			h:cleanup()
		end)

		T.it("follows the attack → hold → decay envelope", function()
			local h = Harness.new(use)
			local c, component = h:build("flash")
			local ball = find(h, component.id, "flash")
			local light = find(h, component.id, "Light")
			activate(h, c)
			-- { localTime, envelope }; A = 0.03, H = 0.02, D = 0.25
			local samples = {
				{ 0, 0 },
				{ 0.015, 0.5 },
				{ 0.03, 1 },
				{ 0.04, 1 },
				{ 0.05, 1 },
				{ 0.175, 0.5 },
				{ 0.2375, 0.25 },
				{ 0.3, 0 },
				{ 1, 0 },
			}
			for _, s in samples do
				step(h, c, s[1])
				expect({ s[1], ball.Transparency }).toBeCloseTo({ s[1], 1 - s[2] }, EPS)
				expect({ s[1], light.Brightness }).toBeCloseTo({ s[1], 10 * s[2] }, EPS)
				local enabled: { any } = { s[1], light.Enabled }
				local expectedEnabled: { any } = { s[1], s[2] > 0 }
				expect(enabled).toEqual(expectedEnabled)
			end
			h:cleanup()
		end)

		T.it("grows from startSize to size (Cubic.Out over the envelope)", function()
			local h = Harness.new(use)
			local c, component = h:build("flash", { startSize = 2, size = 10 })
			local ball = find(h, component.id, "flash")
			activate(h, c)
			step(h, c, 0)
			expect(ball.Size).toBeCloseTo(Vector3.new(2, 2, 2), EPS)
			step(h, c, 0.15) -- half of attack + hold + decay
			expect(ball.Size.X).toBeCloseTo(2 + 8 * (1 - 0.5 ^ 3), EPS)
			step(h, c, 0.3)
			expect(ball.Size).toBeCloseTo(Vector3.new(10, 10, 10), EPS)
			step(h, c, 2)
			expect(ball.Size.X).toBeCloseTo(10, EPS)
			local previous = 0
			for i = 0, 30 do
				step(h, c, i / 100)
				expect(ball.Size.X).toBeGreaterThanOrEqual(previous)
				previous = ball.Size.X
			end
			h:cleanup()
		end)

		T.it("peaks immediately when attack is 0", function()
			local h = Harness.new(use)
			local c, component = h:build("flash", { attack = 0 })
			activate(h, c)
			step(h, c, 0)
			expect(find(h, component.id, "flash").Transparency).toBeCloseTo(0, EPS)
			expect(find(h, component.id, "Light").Brightness).toBeCloseTo(10, EPS)
			h:cleanup()
		end)

		T.it("scales sizes and the light range by transform.scale (range ≤ 120)", function()
			local h = Harness.new(use)
			local c, component = h:build("flash", nil, { scale = 2 })
			local ball = find(h, component.id, "flash")
			activate(h, c)
			step(h, c, 0.3)
			expect(ball.Size.X).toBeCloseTo(12, EPS)
			expect(find(h, component.id, "Light").Range).toBeCloseTo(32, EPS)
			c:apply("scale", 5) -- not a flash channel: ignored
			step(h, c, 0.3)
			expect(ball.Size.X).toBeCloseTo(12, EPS)
			local h2 = Harness.new(use)
			local _, big = h2:build("flash", { range = 100 }, { scale = 2 })
			expect(find(h2, big.id, "Light").Range).toBeCloseTo(120, EPS)
			h:cleanup()
			h2:cleanup()
		end)

		T.it("applies the colour channel to the ball and the light", function()
			local h = Harness.new(use)
			local c, component = h:build("flash", { color = "#00FF00" })
			expect(find(h, component.id, "flash").Color).toBeCloseTo(GREEN, EPS)
			expect(find(h, component.id, "Light").Color).toBeCloseTo(GREEN, EPS)
			c:apply("color", RED)
			expect(find(h, component.id, "flash").Color).toBeCloseTo(RED, EPS)
			expect(find(h, component.id, "Light").Color).toBeCloseTo(RED, EPS)
			h:cleanup()
		end)

		T.it("builds no light when light = false", function()
			local h = Harness.new(use)
			local c, component = h:build("flash", { light = false })
			expect(#c.instances).toBe(1)
			activate(h, c)
			step(h, c, 0.04)
			expect(visibleCount(h, component.id)).toBe(1)
			h:cleanup()
		end)

		T.it("notes a span shorter than the envelope", function()
			local d = descriptorOf("flash")
			local h = Harness.new(use)
			local _, short = h:build("flash", nil, { endTime = 0.1 })
			expect(d.estimateCost(short, HIGH).notes).never.toBeNil()
			local _, long = h:build("flash", nil, { id = "long" })
			expect(d.estimateCost(long, HIGH).notes).toBeNil()
			h:cleanup()
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- shockwave
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("ComponentsGeometry shockwave", function()
		local quartOut = Easing.get("Quart", "Out")
		local quadIn = Easing.get("Quad", "In")

		T.it("builds one ForceField cylinder whose axis is the component's local Y", function()
			local h = Harness.new(use)
			local c, component = h:build("shockwave")
			local parts = partsOf(h, component.id)
			expect(#parts).toBe(1)
			local layer = parts[1]
			expect(layer.Name).toBe("shockwave_Layer1")
			expect(layer.Shape).toBe(Enum.PartType.Cylinder)
			expect(layer.Material).toBe(Enum.Material.ForceField)
			activate(h, c)
			h.root.CFrame = CFrame.new(0, 5, 0)
			local localCFrame = CFrame.new(1, 2, 3) * CFrame.Angles(0.3, 0.5, 0.1)
			step(h, c, 0, localCFrame)
			local world = h.root.CFrame * localCFrame
			expect(layer.CFrame.Position).toBeCloseTo(world.Position, EPS)
			expect(layer.CFrame.RightVector).toBeCloseTo(world.UpVector, EPS) -- cylinder axis = part X
			expect(layer.Size).toBeCloseTo(Vector3.new(0.3, 1, 1), EPS) -- (height, 2r, 2r)
			expect(layer.Transparency).toBeCloseTo(0, EPS)
			h:cleanup()
		end)

		T.it("expands with expandEasing and fades with fadeEasing over the span", function()
			local h = Harness.new(use)
			local c, component = h:build("shockwave")
			local layer = partsOf(h, component.id)[1]
			activate(h, c)
			for _, t in { 0, 0.25, 1, 1.5, 2 } do
				step(h, c, t)
				local u = t / 2
				local d = 2 * (0.5 + 11.5 * quartOut(u))
				local size: { any } = { t, layer.Size }
				local expectedSize: { any } = { t, Vector3.new(0.3, d, d) }
				expect(size).toBeCloseTo(expectedSize, EPS)
				expect({ t, layer.Transparency }).toBeCloseTo({ t, quadIn(u) }, EPS)
			end
			step(h, c, 1)
			expect(layer.Size.Y).toBeCloseTo(2 * (0.5 + 11.5 * 0.9375), EPS) -- Quart.Out(0.5) = 0.9375
			expect(layer.Transparency).toBeCloseTo(0.25, EPS) -- Quad.In(0.5)
			step(h, c, 2)
			expect(layer.Size.Y).toBeCloseTo(24, EPS)
			expect(layer.Transparency).toBeCloseTo(1, EPS)
			h:cleanup()
		end)

		T.it("fades from startTransparency to 1", function()
			local h = Harness.new(use)
			local c, component = h:build("shockwave", { startTransparency = 0.4 })
			local layer = partsOf(h, component.id)[1]
			activate(h, c)
			step(h, c, 0)
			expect(layer.Transparency).toBeCloseTo(0.4, EPS)
			step(h, c, 1)
			expect(layer.Transparency).toBeCloseTo(0.4 + 0.6 * 0.25, EPS)
			h:cleanup()
		end)

		T.it("delays and thins every further layer", function()
			local h = Harness.new(use)
			local c, component = h:build("shockwave", { layers = 3, layerDelay = 0.1, layerThinning = 0.5 })
			local l1 = find(h, component.id, "shockwave_Layer1")
			local l2 = find(h, component.id, "shockwave_Layer2")
			local l3 = find(h, component.id, "shockwave_Layer3")
			activate(h, c)
			step(h, c, 0.05)
			expect(l1.Transparency).toBeLessThan(1)
			expect(l2.Transparency).toBe(1) -- not started yet
			expect(l3.Transparency).toBe(1)
			expect(l1.Size.X).toBeCloseTo(0.3, EPS)
			expect(l2.Size.X).toBeCloseTo(0.15, EPS)
			expect(l3.Size.X).toBeCloseTo(0.075, EPS)
			step(h, c, 0.1)
			expect(l2.Transparency).toBeCloseTo(0, EPS) -- started: startTransparency
			-- Every layer runs the same animation, shifted by i × layerDelay.
			step(h, c, 0.5)
			local d1, t1 = l1.Size.Y, l1.Transparency
			step(h, c, 0.6)
			expect(l2.Size.Y).toBeCloseTo(d1, EPS)
			expect(l2.Transparency).toBeCloseTo(t1, EPS)
			step(h, c, 0.7)
			expect(l3.Size.Y).toBeCloseTo(d1, EPS)
			expect(l3.Transparency).toBeCloseTo(t1, EPS)
			-- The last layer finishes exactly at the end of the span (span 2 − 2 × 0.1 = 1.8 per layer).
			step(h, c, 1.8)
			expect(l1.Transparency).toBeCloseTo(1, EPS)
			expect(l3.Transparency).toBeLessThan(1)
			step(h, c, 2)
			for _, l in { l1, l2, l3 } do
				expect(l.Transparency).toBeCloseTo(1, EPS)
				expect(l.Size.Y).toBeCloseTo(24, EPS)
			end
			h:cleanup()
		end)

		T.it("falls back to Linear for invalid easing strings", function()
			local function sizesAt(props: { [string]: any }, t: number): any
				local h = Harness.new(use)
				local c, component = h:build("shockwave", props)
				activate(h, c)
				step(h, c, t)
				local s = snapshot(h, component.id)
				h:cleanup()
				return s
			end
			local linear = sizesAt({ expandEasing = "Linear", fadeEasing = "Linear" }, 1)
			local layer = linear["Part:shockwave_Layer1"]
			expect(layer.Size.Y).toBeCloseTo(2 * (0.5 + 11.5 * 0.5), EPS)
			expect(layer.Transparency).toBeCloseTo(0.5, EPS)
			expect(sizesAt({ expandEasing = "NotAnEasing", fadeEasing = "quad.in" }, 1)).toBeCloseTo(linear, EPS)
			expect(sizesAt({ expandEasing = "", fadeEasing = "Quad.Sideways" }, 1)).toBeCloseTo(linear, EPS)
		end)

		T.it("supports step easings (Constant)", function()
			local h = Harness.new(use)
			local c, component = h:build("shockwave", { fadeEasing = "Constant", startTransparency = 0.2 })
			local layer = partsOf(h, component.id)[1]
			activate(h, c)
			step(h, c, 1.9)
			expect(layer.Transparency).toBeCloseTo(0.2, EPS)
			step(h, c, 2)
			expect(layer.Transparency).toBeCloseTo(1, EPS)
			h:cleanup()
		end)

		T.it("scales radius and height by transform.scale", function()
			local h = Harness.new(use)
			local c, component = h:build("shockwave", nil, { scale = 2 })
			local layer = partsOf(h, component.id)[1]
			activate(h, c)
			step(h, c, 2)
			expect(layer.Size).toBeCloseTo(Vector3.new(0.6, 48, 48), EPS)
			h:cleanup()
		end)

		T.it("applies the colour channel to every layer", function()
			local h = Harness.new(use)
			local c, component = h:build("shockwave", { layers = 4, color = "#0000FF" })
			for _, p in partsOf(h, component.id) do
				expect(p.Color).toBeCloseTo(BLUE, EPS)
			end
			c:apply("color", RED)
			local parts = partsOf(h, component.id)
			expect(#parts).toBe(4)
			for _, p in parts do
				expect(p.Color).toBeCloseTo(RED, EPS)
			end
			h:cleanup()
		end)

		T.it("estimates per-layer writes and overdraw", function()
			local d = descriptorOf("shockwave")
			local h = Harness.new(use)
			local _, component = h:build("shockwave", { layers = 2 })
			local cost = d.estimateCost(component, HIGH)
			expect(cost.propertyUpdates).toBe(4)
			expect(cost.transparentLayers).toBe(2)
			expect(cost.overdrawWeight).toBeCloseTo(2 * 24 * 24, EPS)
			h:cleanup()
		end)
	end)
end
