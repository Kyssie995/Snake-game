--!strict
--[[
	ComponentsRegistry — registry-level contract specs for every descriptor in Core/Components.

	The family specs (ComponentsNative / ComponentsGeometry / ComponentsProcedural) test each component in depth.
	This spec checks the contracts every descriptor shares, generically over the whole registry, so a new or changed
	descriptor cannot silently break one of them:

	  * the registry holds exactly the 17 types of docs/COMPONENTS_SPEC.md, one file per type (PascalCase name);
	  * an independent transcription of every property table (keys in order, kinds, defaults, ranges, scale /
	    quality / advanced flags, explicit enum lists), every channel list and every event list of the spec;
	  * PropertySpec / ChannelSpec / EventSpec well-formedness, Codec round trips of every default, channel ↔
	    baseProperty consistency, one shared Material list;
	  * build → lifecycle → destroy in runtime, preview and (when supportsViewport) viewport mode: tagging,
	    physics-free parts, invisible until active, visible once active, exact CostEstimate counts (also for
	    property variants), unknown channels/actions ignored, rest values change nothing, identical values cause no
	    property writes, parts only move through frame.moveParts, reset() restores the built state, determinism
	    across frame histories, nothing emitted or played while seeking, destroy leaves nothing behind.

	Lune has no renderer: "visible" means Transparency < 1 / Enabled = true on the built instances.

	Camera types (cameraShake, screenFlash — COMPONENTS_SPEC §17-18) draw through workspace.CurrentCamera instead of
	the container. Every test therefore runs against a fresh test Camera (Env.override("Workspace")), and in Lune as
	a client (Env.override("Players") with a LocalPlayer; render-step bindings through the fakes, stepped by
	`step()` below). "Owned" instances include tagged instances under that camera, snapshots include the camera
	CFrame and "visible" also counts an enabled ColorCorrectionEffect or a moved camera. In-depth camera specs
	(server no-op, envelopes, falloff, bindings): ComponentsCamera.spec.
]]

type Row = {
	name: string,
	kind: string,
	default: any,
	min: number?,
	max: number?,
	flags: string?, -- "L" length, "C" count, "S" segments, "A" advanced
	enum: { string }?,
	enumType: string?,
}

type TypeSpec = {
	category: string,
	properties: { Row },
	channels: { [string]: string },
	events: { string },
}

local function P(
	name: string,
	kind: string,
	default: any,
	min: number?,
	max: number?,
	flags: string?,
	enum: { string }?,
	enumType: string?
): Row
	return {
		name = name,
		kind = kind,
		default = default,
		min = min,
		max = max,
		flags = flags,
		enum = enum,
		enumType = enumType,
	}
end

local SPIN = P("spin", "vector3", { 0, 0, 0 })
local TRANSFORM = { position = "vector3", rotation = "vector3", scale = "number" }

local function with(base: { [string]: string }, extra: { [string]: string }): { [string]: string }
	local out = table.clone(base)
	for k, v in extra do
		out[k] = v
	end
	return out
end

-- docs/COMPONENTS_SPEC.md §1–§15 and §17–§18, transcribed independently of the descriptors. `enum` is given where
-- the spec lists the names explicitly; `enumType` where the spec names the Roblox Enum.
local SPEC: { [string]: TypeSpec } = {
	group = {
		category = "Structure",
		properties = { SPIN },
		channels = { position = "vector3", rotation = "vector3" },
		events = {},
	},
	particles = {
		category = "Particles",
		properties = {
			P("texture", "asset", "rbxasset://textures/particles/sparkles_main.dds"),
			P("color", "colorSequence", "#FFFFFF"),
			P("transparency", "numberSequence", 0, 0, 1),
			P("size", "numberSequence", 1, 0, 100, "L"),
			P("squash", "numberSequence", 0, -3, 3, "A"),
			P("lifetime", "numberRange", { 1, 2 }, 0, 20),
			P("rate", "number", 20, 0, 400, "C"),
			P("burst", "integer", 0, 0, 10000, "C"),
			P("speed", "numberRange", { 5, 5 }, -1000, 1000, "L"),
			P("spreadAngle", "vector2", { 0, 0 }, -360, 360),
			P("acceleration", "vector3", { 0, 0, 0 }, nil, nil, "L"),
			P("drag", "number", 0, 0, 100),
			P("rotation", "numberRange", { 0, 0 }, -360, 360),
			P("rotSpeed", "numberRange", { 0, 0 }, -3600, 3600),
			P("emissionDirection", "enum", "Top", nil, nil, nil, nil, "NormalId"),
			P("shape", "enum", "Point", nil, nil, nil, { "Point", "Box", "Sphere", "Cylinder", "Disc" }),
			P("emitterSize", "vector3", { 1, 1, 1 }, 0, 2048, "L"),
			P("shapeStyle", "enum", "Volume", nil, nil, nil, nil, "ParticleEmitterShapeStyle"),
			P("shapeInOut", "enum", "Outward", nil, nil, nil, nil, "ParticleEmitterShapeInOut"),
			P("shapePartial", "number", 1, 0, 1),
			P("orientation", "enum", "FacingCamera", nil, nil, nil, nil, "ParticleOrientation"),
			P("lightEmission", "number", 0, 0, 1),
			P("lightInfluence", "number", 0, 0, 1),
			P("brightness", "number", 1, 0, 100),
			P("zOffset", "number", 0, -100, 100),
			P("timeScale", "number", 1, 0, 1),
			P("lockedToPart", "boolean", false),
			P("velocityInheritance", "number", 0, 0, 1, "A"),
			P("windAffectsDrag", "boolean", false, nil, nil, "A"),
			P("flipbookLayout", "enum", "None", nil, nil, nil, nil, "ParticleFlipbookLayout"),
			P("flipbookMode", "enum", "Loop", nil, nil, nil, nil, "ParticleFlipbookMode"),
			P("flipbookFramerate", "numberRange", { 1, 1 }, 0, 30),
			P("flipbookStartRandom", "boolean", false),
			SPIN,
		},
		channels = with(TRANSFORM, {
			transparency = "number",
			tint = "color3",
			rate = "number",
			brightness = "number",
			lightEmission = "number",
			acceleration = "vector3",
			timeScale = "number",
		}),
		events = { "emit", "clear", "enable", "disable" },
	},
	beam = {
		category = "Beams & Trails",
		properties = {
			P("from", "vector3", { 0, 0, 0 }, nil, nil, "L"),
			P("to", "vector3", { 0, 0, -10 }, nil, nil, "L"),
			P("curveDirection", "vector3", { 0, 1, 0 }),
			P("roll", "number", 0, -360, 360),
			P("texture", "asset", ""),
			P("color", "colorSequence", "#FFFFFF"),
			P("transparency", "numberSequence", 0, 0, 1),
			P("width0", "number", 1, 0, 1000, "L"),
			P("width1", "number", 1, 0, 1000, "L"),
			P("curveSize0", "number", 0, -1000, 1000, "L"),
			P("curveSize1", "number", 0, -1000, 1000, "L"),
			P("segments", "integer", 10, 1, 1000, "S"),
			P("textureLength", "number", 1, 0.01, 1000, "L"),
			P("textureMode", "enum", "Stretch", nil, nil, nil, nil, "TextureMode"),
			P("textureSpeed", "number", 1, -100, 100),
			P("faceCamera", "boolean", true),
			P("lightEmission", "number", 0, 0, 1),
			P("lightInfluence", "number", 0, 0, 1),
			P("brightness", "number", 1, 0, 100),
			P("zOffset", "number", 0),
			SPIN,
		},
		channels = with(TRANSFORM, {
			transparency = "number",
			tint = "color3",
			width0 = "number",
			width1 = "number",
			curveSize0 = "number",
			curveSize1 = "number",
			from = "vector3",
			to = "vector3",
			brightness = "number",
			textureSpeed = "number",
		}),
		events = { "enable", "disable" },
	},
	trail = {
		category = "Beams & Trails",
		properties = {
			P("width", "number", 1, 0, 100, "L"),
			P("widthDirection", "vector3", { 0, 1, 0 }),
			P("lifetime", "number", 0.5, 0.01, 20),
			P("minLength", "number", 0.1, 0, 100, "L"),
			P("maxLength", "number", 0, 0, 10000, "L"),
			P("widthScale", "numberSequence", 1, 0, 1),
			P("color", "colorSequence", "#FFFFFF"),
			P("transparency", "numberSequence", 0, 0, 1),
			P("texture", "asset", ""),
			P("textureLength", "number", 1, nil, nil, "L"),
			P("textureMode", "enum", "Stretch", nil, nil, nil, nil, "TextureMode"),
			P("faceCamera", "boolean", false),
			P("lightEmission", "number", 0, 0, 1),
			P("lightInfluence", "number", 0, 0, 1),
			P("brightness", "number", 1, 0, 100),
			P("clearOnStart", "boolean", true),
			SPIN,
		},
		channels = with(TRANSFORM, {
			width = "number",
			transparency = "number",
			tint = "color3",
			brightness = "number",
		}),
		events = { "enable", "disable", "clear" },
	},
	part = {
		category = "Geometry",
		properties = {
			P(
				"shape",
				"enum",
				"Block",
				nil,
				nil,
				nil,
				{ "Block", "Ball", "Cylinder", "Wedge", "CornerWedge" },
				"PartType"
			),
			P("size", "vector3", { 1, 1, 1 }, 0.001, 2048, "L"),
			P("color", "color3", "#FFFFFF"),
			P("material", "enum", "Neon", nil, nil, nil, nil, "Material"),
			P("transparency", "number", 0, 0, 1),
			P("reflectance", "number", 0, 0, 1, "A"),
			P("castShadow", "boolean", false, nil, nil, "A"),
			SPIN,
		},
		channels = with(TRANSFORM, { size = "vector3", transparency = "number", color = "color3" }),
		events = {},
	},
	mesh = {
		category = "Geometry",
		properties = {
			P(
				"meshType",
				"enum",
				"Sphere",
				nil,
				nil,
				nil,
				{ "Sphere", "Cylinder", "Brick", "Wedge", "FileMesh" },
				"MeshType"
			),
			P("meshId", "asset", ""),
			P("textureId", "asset", ""),
			P("partSize", "vector3", { 1, 1, 1 }, nil, nil, "L"),
			P("meshScale", "vector3", { 1, 1, 1 }, 0, 10000),
			P("offset", "vector3", { 0, 0, 0 }, nil, nil, "L"),
			P("vertexColor", "color3", "#FFFFFF"),
			P("color", "color3", "#FFFFFF"),
			P("material", "enum", "SmoothPlastic", nil, nil, nil, nil, "Material"),
			P("transparency", "number", 0, 0, 1),
			SPIN,
		},
		channels = with(TRANSFORM, {
			meshScale = "vector3",
			offset = "vector3",
			transparency = "number",
			color = "color3",
			vertexColor = "color3",
		}),
		events = {},
	},
	light = {
		category = "Lighting",
		properties = {
			P("lightType", "enum", "Point", nil, nil, nil, { "Point", "Spot", "Surface" }),
			P("color", "color3", "#FFFFFF"),
			P("brightness", "number", 1, 0, 100),
			P("range", "number", 8, 0, 120, "L"),
			P("angle", "number", 90, 0, 180),
			P("face", "enum", "Front", nil, nil, nil, nil, "NormalId"),
			P("shadows", "boolean", false),
			P("surfaceSize", "vector3", { 4, 4, 0.2 }, nil, nil, "L"),
		},
		channels = {
			position = "vector3",
			rotation = "vector3",
			brightness = "number",
			range = "number",
			color = "color3",
			angle = "number",
		},
		events = { "enable", "disable" },
	},
	sound = {
		category = "Audio",
		properties = {
			P("soundId", "asset", ""),
			P("volume", "number", 0.5, 0, 10),
			P("playbackSpeed", "number", 1, 0.01, 10),
			P("rollOffMinDistance", "number", 10, 0, 10000, "L"),
			P("rollOffMaxDistance", "number", 100, 0, 10000, "L"),
			P("looped", "boolean", false),
			P("playOnStart", "boolean", true),
		},
		channels = { position = "vector3", volume = "number", playbackSpeed = "number" },
		events = { "play", "stop" },
	},
	sphere = {
		category = "Procedural",
		properties = {
			P("radius", "number", 1, 0.01, 500, "L"),
			P("coreColor", "color3", "#FFFFFF"),
			P("shellColor", "color3", "#8A5CFF"),
			P("coreMaterial", "enum", "Neon", nil, nil, nil, nil, "Material"),
			P("shellMaterial", "enum", "ForceField", nil, nil, nil, nil, "Material"),
			P("shellScale", "number", 1.4, 1, 10),
			P("coreTransparency", "number", 0, 0, 1),
			P("shellTransparency", "number", 0.3, 0, 1),
			P("pulseAmplitude", "number", 0.05, 0, 1),
			P("pulseFrequency", "number", 4, 0, 60),
			P("light", "boolean", true),
			P("lightBrightness", "number", 2, 0, 100),
			P("lightRange", "number", 8, 0, 120, "L"),
			SPIN,
		},
		channels = with(TRANSFORM, {
			radius = "number",
			transparency = "number",
			coreColor = "color3",
			shellColor = "color3",
			lightBrightness = "number",
		}),
		events = {},
	},
	flash = {
		category = "Procedural",
		properties = {
			P("color", "color3", "#FFFFFF"),
			P("size", "number", 6, 0, 500, "L"),
			P("startSize", "number", 1, 0, 500, "L"),
			P("attack", "number", 0.03, 0, 5),
			P("hold", "number", 0.02, 0, 5),
			P("decay", "number", 0.25, 0.01, 10),
			P("material", "enum", "Neon", nil, nil, nil, nil, "Material"),
			P("light", "boolean", true),
			P("peakBrightness", "number", 10, 0, 100),
			P("range", "number", 16, 0, 120, "L"),
		},
		channels = { position = "vector3", color = "color3" },
		events = {},
	},
	shockwave = {
		category = "Procedural",
		properties = {
			P("startRadius", "number", 0.5, 0, 2000, "L"),
			P("endRadius", "number", 12, 0, 2000, "L"),
			P("height", "number", 0.3, 0.01, 100, "L"),
			P("color", "color3", "#FFFFFF"),
			P("material", "enum", "ForceField", nil, nil, nil, nil, "Material"),
			P("startTransparency", "number", 0, 0, 1),
			P("expandEasing", "string", "Quart.Out"),
			P("fadeEasing", "string", "Quad.In"),
			P("layers", "integer", 1, 1, 4, "S"),
			P("layerDelay", "number", 0.05, 0, 2),
			P("layerThinning", "number", 0.6, 0.05, 1),
		},
		channels = { position = "vector3", rotation = "vector3", color = "color3" },
		events = {},
	},
	ring = {
		category = "Procedural",
		properties = {
			P("style", "enum", "ring", nil, nil, nil, { "ring", "polygon", "star", "spokes" }),
			P("segments", "integer", 24, 3, 128, "S"),
			P("points", "integer", 5, 3, 32),
			P("starStep", "integer", 2, 1, 15),
			P("radius", "number", 4, 0, 2000, "L"),
			P("innerRadius", "number", 0, 0, 2000, "L"),
			P("thickness", "number", 0.2, 0.001, 100, "L"),
			P("height", "number", 0.1, 0.001, 100, "L"),
			P("color", "color3", "#FFFFFF"),
			P("material", "enum", "Neon", nil, nil, nil, nil, "Material"),
			P("transparency", "number", 0, 0, 1),
			SPIN,
		},
		channels = with(TRANSFORM, {
			radius = "number",
			thickness = "number",
			transparency = "number",
			color = "color3",
		}),
		events = {},
	},
	radialBurst = {
		category = "Procedural",
		properties = {
			P("count", "integer", 12, 1, 256, "C"),
			P("distribution", "enum", "sphere", nil, nil, nil, { "sphere", "hemisphere", "ring", "cone" }),
			P("coneAngle", "number", 45, 0, 180),
			P("startRadius", "number", 0.5, 0, 2000, "L"),
			P("endRadius", "number", 10, 0, 2000, "L"),
			P("width", "number", 0.3, 0.001, 100, "L"),
			P("jitter", "number", 0.3, 0, 1),
			P("color", "color3", "#FFFFFF"),
			P("material", "enum", "Neon", nil, nil, nil, nil, "Material"),
			P("transparency", "number", 0, 0, 1),
		},
		channels = { position = "vector3", rotation = "vector3", transparency = "number", color = "color3" },
		events = {},
	},
	debris = {
		category = "Procedural",
		properties = {
			P("count", "integer", 12, 1, 200, "C"),
			P("shape", "enum", "Mixed", nil, nil, nil, { "Block", "Wedge", "Ball", "Mixed" }),
			P("size", "numberRange", { 0.3, 0.8 }, 0.01, 50, "L"),
			P("speed", "numberRange", { 20, 40 }, 0, 2000, "L"),
			P("direction", "vector3", { 0, 1, 0 }),
			P("spreadAngle", "number", 60, 0, 180),
			P("gravity", "vector3", { 0, -80, 0 }, nil, nil, "L"),
			P("drag", "number", 0, 0, 20),
			P("spinSpeed", "numberRange", { 90, 360 }, 0, 3600),
			P("color", "color3", "#6B5B4B"),
			P("colorVariance", "number", 0.15, 0, 1),
			P("material", "enum", "Slate", nil, nil, nil, nil, "Material"),
			P("transparency", "number", 0, 0, 1),
			P("fadeTime", "number", 0.3, 0, 10),
			P("floor", "boolean", false),
			P("floorHeight", "number", 0, nil, nil, "L"),
		},
		channels = { position = "vector3", rotation = "vector3", color = "color3", transparency = "number" },
		events = {},
	},
	lightning = {
		category = "Procedural",
		properties = {
			P("from", "vector3", { 0, 10, 0 }, nil, nil, "L"),
			P("to", "vector3", { 0, 0, 0 }, nil, nil, "L"),
			P("segments", "integer", 12, 2, 64, "S"),
			P("jitter", "number", 1.5, 0, 500, "L"),
			P("branches", "integer", 2, 0, 8, "C"),
			P("branchLength", "number", 0.35, 0, 1),
			P("flickerRate", "number", 20, 0, 120),
			P("thickness", "number", 0.3, 0.01, 50, "L"),
			P("color", "color3", "#A8DCFF"),
			P("render", "enum", "beam", nil, nil, nil, { "beam", "part" }),
			P("lightEmission", "number", 1, 0, 1),
			P("brightness", "number", 2, 0, 100),
			P("texture", "asset", ""),
			P("transparency", "number", 0, 0, 1),
			P("material", "enum", "Neon", nil, nil, nil, nil, "Material"),
		},
		channels = {
			position = "vector3",
			rotation = "vector3",
			from = "vector3",
			to = "vector3",
			thickness = "number",
			transparency = "number",
			color = "color3",
		},
		events = { "regenerate" },
	},
	cameraShake = {
		category = "Camera",
		properties = {
			P("amplitude", "number", 0.6, 0, 20),
			P("positionAmplitude", "number", 0.15, 0, 10, "L"),
			P("frequency", "number", 18, 0.1, 60),
			P("attack", "number", 0.02, 0, 5),
			P("decay", "number", 0.35, 0, 10),
			P("decayEasing", "string", "Quad.Out"),
			P("rotationWeights", "vector3", { 1, 0.6, 0.3 }, 0, 1),
			P("innerRadius", "number", 20, 0, 10000, "L"),
			P("outerRadius", "number", 120, 0, 10000, "L"),
			P("previewInStudio", "boolean", false),
		},
		channels = { position = "vector3", amplitude = "number" },
		events = {},
	},
	screenFlash = {
		category = "Camera",
		properties = {
			P("brightness", "number", 0.35, -1, 2),
			P("contrast", "number", 0.8, -1, 3),
			P("saturation", "number", -0.6, -1, 2),
			P("tint", "color3", "#FFFFFF"),
			P("attack", "number", 0.02, 0, 2),
			P("hold", "number", 0.05, 0, 2),
			P("decay", "number", 0.18, 0.01, 5),
			P("previewInStudio", "boolean", true),
		},
		channels = { tint = "color3" },
		events = {},
	},
}

-- §17-18: camera types render through the current camera (never into the container or a viewport).
local CAMERA_TYPES = { cameraShake = true, screenFlash = true }

-- §0: only geometry types render in a ViewportFrame (lightning switches to part render there).
local VIEWPORT_TYPES = {
	group = true,
	part = true,
	mesh = true,
	sphere = true,
	flash = true,
	shockwave = true,
	ring = true,
	radialBurst = true,
	debris = true,
	lightning = true,
}

-- Defaults the spec writes as `[n, n]`; Codec's canonical form of an equal-ended NumberRange is the plain number.
local NON_CANONICAL_DEFAULTS = {
	["particles.speed"] = 5,
	["particles.rotation"] = 0,
	["particles.rotSpeed"] = 0,
	["particles.flipbookFramerate"] = 1,
}

-- Class of controller.instances[1] (the "main" instance) in a runtime build with defaults. Camera types build
-- nothing up front (screenFlash creates its effect only while it shows).
local MAIN_CLASS = {
	particles = "ParticleEmitter",
	beam = "Beam",
	trail = "Trail",
	light = "PointLight",
	sound = "Sound",
	part = "Part",
	mesh = "Part",
	sphere = "Part",
	flash = "Part",
	shockwave = "Part",
	ring = "Part",
	radialBurst = "Part",
	debris = "Part",
	lightning = "Beam",
}

-- Local time at which a default build is visibly active (flash fades out after 0.3 s, screenFlash after 0.25 s,
-- radialBurst is degenerate at u = 0 and u = 1).
local VISIBLE_AT: { [string]: number } = { flash = 0.04, screenFlash = 0.04 }

-- Property variants whose instance structure differs from the defaults (cost counts must still be exact).
local VARIANTS: { [string]: { { [string]: any } } } = {
	particles = { { shape = "Box" }, { shape = "Sphere", emitterSize = { 4, 4, 4 } } },
	light = { { lightType = "Spot" }, { lightType = "Surface", shadows = true } },
	sphere = { { light = false } },
	flash = { { light = false } },
	shockwave = { { layers = 3 } },
	ring = { { style = "star", points = 6, starStep = 3 }, { style = "spokes", points = 7 }, { style = "polygon" } },
	radialBurst = { { count = 3, distribution = "cone" } },
	debris = { { count = 5, floor = true } },
	lightning = { { render = "part" }, { branchLength = 0 }, { branches = 0, segments = 2 } },
	mesh = { { meshType = "FileMesh" } },
	sound = { { soundId = "rbxassetid://1" } },
	cameraShake = { { previewInStudio = true, innerRadius = 0, outerRadius = 50 } },
	screenFlash = { { tint = "#FF2040", attack = 0 } },
}

-- Properties that make a default build show something in every mode (sound needs an id; the camera shake's
-- Studio preview is opt-in).
local SHOW_PROPS: { [string]: { [string]: any } } = {
	sound = { soundId = "rbxassetid://1" },
	cameraShake = { previewInStudio = true },
}

-- Properties read from built instances for snapshots and the "no redundant writes" check.
local WATCHED: { { any } } = {
	{ "BasePart", { "Size", "CFrame", "Transparency", "Color", "Reflectance", "CastShadow" } },
	{ "Attachment", { "CFrame", "Visible" } },
	{
		"ParticleEmitter",
		{
			"Enabled",
			"Rate",
			"Size",
			"Transparency",
			"Color",
			"Brightness",
			"LightEmission",
			"Acceleration",
			"TimeScale",
		},
	},
	{
		"Beam",
		{
			"Enabled",
			"Width0",
			"Width1",
			"CurveSize0",
			"CurveSize1",
			"Transparency",
			"Color",
			"Brightness",
			"TextureSpeed",
			"Segments",
		},
	},
	{ "Trail", { "Enabled", "Transparency", "Color", "Brightness" } },
	{ "Light", { "Enabled", "Brightness", "Color", "Shadows" } },
	{ "PointLight", { "Range" } },
	{ "SpotLight", { "Range", "Angle" } },
	{ "SurfaceLight", { "Range", "Angle" } },
	{ "Sound", { "Volume", "PlaybackSpeed", "Looped" } },
	{ "SpecialMesh", { "Scale", "Offset", "VertexColor" } },
	{ "ColorCorrectionEffect", { "Enabled", "Brightness", "Contrast", "Saturation", "TintColor" } },
}

return function(T: any, use: (string) -> any, ctx: any)
	local Harness = use("Tests.Specs.Helpers.ComponentHarness")
	local Components = use("AstraVFX.Core.Components")
	local Codec = use("AstraVFX.Core.Codec")
	local Env = use("AstraVFX.Core.Env")
	local expect = T.expect
	local isLune = ctx.environment == "lune"
	local fakes = ctx.fakes

	local EXPECTED_TYPES = {}
	for name in SPEC do
		table.insert(EXPECTED_TYPES, name)
	end
	table.sort(EXPECTED_TYPES)

	local HIGH = {
		level = "High",
		countScale = 1,
		segmentScale = 1,
		sizeCompensation = 1,
		lightShadows = true,
		maxLights = math.huge,
	}
	local LOW = {
		level = "Low",
		countScale = 0.35,
		segmentScale = 0.5,
		sizeCompensation = 1.12,
		lightShadows = false,
		maxLights = 2,
	}

	local open: { any } = {}
	local function harness(): any
		local h = Harness.new(use)
		table.insert(open, h)
		return h
	end

	-- Test camera for the camera types (see header); Lune also simulates a client. `cameraHome` is the CFrame the
	-- camera holds after the assignment (Lune's property storage rounds CFrames on the first write).
	local CAMERA_START = CFrame.new(0, 5, 20) * CFrame.Angles(-0.2, 0, 0)
	local camera: Camera? = nil
	local cameraHome = CAMERA_START

	T.beforeEach(function()
		local cam = Instance.new("Camera")
		cam.Name = "RegistryTestCamera"
		cam.CFrame = CAMERA_START
		cameraHome = cam.CFrame
		camera = cam
		Env.override("Workspace", { CurrentCamera = cam })
		if isLune then
			Env.override("Players", { LocalPlayer = { Name = "RegistryTestPlayer" } })
		end
	end)

	T.afterEach(function()
		for _, h in open do
			h:cleanup()
		end
		table.clear(open)
		if fakes then
			fakes:reset()
		end
		Env.override("Workspace", nil)
		Env.override("Players", nil)
		if camera then
			camera:Destroy()
			camera = nil
		end
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- Helpers
	-- ─────────────────────────────────────────────────────────────────────────

	local function mode(name: string): any
		if name == "preview" then
			return { isPreview = true }
		elseif name == "viewport" then
			return { isPreview = true, viewport = true }
		end
		return {}
	end

	local function modesOf(descriptor: any): { string }
		local out = { "runtime", "preview" }
		if descriptor.supportsViewport then
			table.insert(out, "viewport")
		end
		return out
	end

	local function merge(a: { [string]: any }?, b: { [string]: any }?): { [string]: any }
		local first: { [string]: any } = a or {}
		local second: { [string]: any } = b or {}
		local out = table.clone(first)
		for k, v in second do
			out[k] = v
		end
		return out
	end

	-- Instances of a component: tagged ones below the container plus (camera types) below the test camera.
	local function owned(h: any, componentId: string): { Instance }
		local out = h:instancesOf(componentId)
		if camera then
			for _, inst in camera:GetDescendants() do
				if inst:GetAttribute("AstraComponent") == componentId then
					table.insert(out, inst)
				end
			end
		end
		return out
	end

	-- Rows of "Class Name.Property=value" for every watched property of the component's instances, plus the test
	-- camera's CFrame (only camera types ever change it).
	local function snapshot(h: any, componentId: string, skip: { [string]: boolean }?): string
		local rows = {}
		if camera then
			table.insert(rows, "Camera.CFrame=" .. tostring(camera.CFrame))
		end
		for _, inst: any in owned(h, componentId) do
			for _, entry in WATCHED do
				local class: string, props: { string } = entry[1], entry[2]
				if inst:IsA(class) then
					for _, prop in props do
						if not (skip and skip[class .. "." .. prop]) then
							table.insert(
								rows,
								inst.ClassName .. " " .. inst.Name .. "." .. prop .. "=" .. tostring(inst[prop])
							)
						end
					end
				end
			end
		end
		table.sort(rows)
		return table.concat(rows, "\n")
	end

	local function frameAt(h: any, localTime: number, seeking: boolean?): any
		return h:frame(localTime, if seeking then 0 else 1 / 60, seeking)
	end

	-- One Player frame (setTransform → update → flush, then the render-step bindings in Lune) at `localTime` with
	-- the component at `cf`.
	local function step(h: any, c: any, localTime: number, cf: CFrame?, seeking: boolean?): any
		local f = frameAt(h, localTime, seeking)
		local local_ = cf or CFrame.new()
		c:setTransform(local_, h.root.CFrame * local_, f)
		if c.update then
			c:update(localTime, f)
		end
		h:flush(f)
		if fakes then
			fakes:renderStep(f.dt)
		end
		return f
	end

	-- Rest value of a channel (what it shows without a track), or nil for transform channels.
	local function restValue(spec: any, component: any): any
		if spec.baseProperty then
			return component.props[spec.baseProperty]
		elseif spec.name == "transparency" then
			return 0
		elseif spec.name == "tint" then
			return Color3.new(1, 1, 1)
		elseif spec.name == "scale" then
			return component.scale
		end
		return nil
	end

	-- A valid value different from the rest value (transform channels position/rotation are composed by the
	-- Player into setTransform and never applied).
	local function sampleValue(spec: any): any
		if spec.name == "position" or spec.name == "rotation" then
			return nil
		end
		if spec.kind == "number" then
			if spec.name == "transparency" then
				return 0.4
			elseif spec.name == "scale" then
				return 1.5
			elseif spec.min ~= nil and spec.max ~= nil then
				return spec.min + (spec.max - spec.min) * 0.37
			elseif spec.min ~= nil then
				return spec.min + 1.7
			end
			return 1.7
		elseif spec.kind == "vector3" then
			return Vector3.new(1.5, 2.5, 3.5)
		elseif spec.kind == "color3" then
			return Color3.new(0.2, 0.4, 0.6)
		elseif spec.kind == "boolean" then
			return true
		end
		return nil
	end

	local function eventAction(event: any, order: number, localTime: number): any
		return {
			time = localTime,
			action = event.action,
			count = if event.usesCount then 3 else nil,
			source = "event",
			order = order,
		}
	end

	local function counts(h: any, componentId: string): any
		local n = {
			instances = 0,
			parts = 0,
			attachments = 0,
			emitters = 0,
			beams = 0,
			trails = 0,
			lights = 0,
			shadowLights = 0,
			sounds = 0,
		}
		for _, inst: any in owned(h, componentId) do
			n.instances += 1
			if inst:IsA("BasePart") then
				n.parts += 1
			elseif inst:IsA("Attachment") then
				n.attachments += 1
			elseif inst:IsA("ParticleEmitter") then
				n.emitters += 1
			elseif inst:IsA("Beam") then
				n.beams += 1
			elseif inst:IsA("Trail") then
				n.trails += 1
			elseif inst:IsA("Light") then
				n.lights += 1
				if inst.Shadows then
					n.shadowLights += 1
				end
			elseif inst:IsA("Sound") then
				n.sounds += 1
			end
		end
		return n
	end

	local function visibleCount(h: any, componentId: string): number
		local n = 0
		for _, inst: any in owned(h, componentId) do
			if inst:IsA("BasePart") then
				if inst.Transparency < 1 then
					n += 1
				end
			elseif
				inst:IsA("ParticleEmitter")
				or inst:IsA("Beam")
				or inst:IsA("Trail")
				or inst:IsA("Light")
				or inst:IsA("PostEffect")
			then
				if inst.Enabled then
					n += 1
				end
			end
		end
		-- a shaken camera
		if camera and camera.CFrame ~= cameraHome then
			n += 1
		end
		return n
	end

	local function soundActions(): number
		return if fakes then #fakes.sounds else 0
	end

	-- ─────────────────────────────────────────────────────────────────────────
	-- 1. Registry contents
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("registry", function()
		T.it("contains exactly the 17 component types of docs/COMPONENTS_SPEC.md, sorted by type", function()
			expect(#EXPECTED_TYPES).toBe(17)
			expect(Components.types()).toEqual(EXPECTED_TYPES)
			local listed = {}
			for _, d in Components.list() do
				table.insert(listed, d.type)
			end
			expect(listed).toEqual(EXPECTED_TYPES)
		end)

		T.it("lookups return the descriptor's own spec tables and nil for unknown names", function()
			for _, d in Components.list() do
				expect(Components.get(d.type)).toBe(d)
				for _, p in d.properties do
					expect(Components.propertySpec(d.type, p.name)).toBe(p)
				end
				for _, c in d.channels do
					expect(Components.channelSpec(d.type, c.name)).toBe(c)
				end
				for _, e in d.events do
					expect(Components.eventSpec(d.type, e.action)).toBe(e)
				end
				expect(Components.propertySpec(d.type, "noSuchProperty")).toBeNil()
				expect(Components.channelSpec(d.type, "noSuchChannel")).toBeNil()
				expect(Components.eventSpec(d.type, "noSuchAction")).toBeNil()
			end
			expect(Components.get("noSuchType")).toBeNil()
		end)

		T.itIf(
			isLune and ctx.loader ~= nil,
			"has one PascalCase descriptor module per type and no other module besides Common",
			function()
				local folder = ctx.loader:resolve("AstraVFX.Core.Components")
				local names = {}
				for _, child: any in folder:GetChildren() do
					if child:IsA("ModuleScript") and child.Name ~= "Common" then
						table.insert(names, child.Name)
					end
				end
				table.sort(names)
				local expected = {}
				for _, t in EXPECTED_TYPES do
					table.insert(expected, string.upper(string.sub(t, 1, 1)) .. string.sub(t, 2))
				end
				table.sort(expected)
				expect(names).toEqual(expected)
			end
		)

		T.it("supportsViewport is true exactly for the geometry types of COMPONENTS_SPEC §0", function()
			for _, d in Components.list() do
				expect(d.supportsViewport).toBe(VIEWPORT_TYPES[d.type] == true)
			end
		end)

		T.it("every Material-valued enum offers the same list: Enum.Material without Air and Water", function()
			local browsable = {}
			for _, item: any in Enum.Material:GetEnumItems() do
				if item.Name ~= "Air" and item.Name ~= "Water" then
					browsable[item.Name] = true
				end
			end
			local found = 0
			for _, d in Components.list() do
				for _, p in d.properties do
					if p.enumType == "Material" then
						found += 1
						local listed = {}
						for _, name in p.enum or {} do
							expect(listed[name]).toBeNil()
							listed[name] = true
						end
						expect(listed).toEqual(browsable)
					end
				end
			end
			-- part, mesh, sphere (core + shell), flash, shockwave, ring, radialBurst, debris, lightning
			expect(found).toBe(10)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- 2. Per-type spec contracts
	-- ─────────────────────────────────────────────────────────────────────────

	for _, typeName in EXPECTED_TYPES do
		local expected = SPEC[typeName]
		local descriptor = Components.get(typeName)

		T.describe("descriptor " .. typeName, function()
			T.it("exists with type, display name, description, spec category and functions", function()
				expect(descriptor).toBeTruthy()
				expect(descriptor.type).toBe(typeName)
				expect(descriptor.type).toMatch("^[a-z][A-Za-z0-9]*$")
				expect(type(descriptor.displayName) == "string" and #descriptor.displayName > 0).toBe(true)
				expect(type(descriptor.description) == "string" and #descriptor.description > 0).toBe(true)
				expect(descriptor.category).toBe(expected.category)
				expect(type(descriptor.build)).toBe("function")
				expect(type(descriptor.estimateCost)).toBe("function")
				expect(type(descriptor.canParent)).toBe("boolean")
				expect(type(descriptor.supportsViewport)).toBe("boolean")
			end)

			T.it("property table matches COMPONENTS_SPEC (keys in order, kinds, defaults, ranges, flags)", function()
				local names, expectedNames = {}, {}
				for _, p in descriptor.properties do
					table.insert(names, p.name)
				end
				for _, row in expected.properties do
					table.insert(expectedNames, row.name)
				end
				expect(names).toEqual(expectedNames)
				for i, row in expected.properties do
					local p = descriptor.properties[i]
					local where = typeName .. "." .. row.name
					expect(where .. ":" .. p.kind).toBe(where .. ":" .. row.kind)
					expect(p.default).toEqual(row.default)
					expect(p.min).toBe(row.min)
					expect(p.max).toBe(row.max)
					local flags = row.flags or ""
					expect(where .. ":scale=" .. tostring(p.scale)).toBe(
						where .. ":scale=" .. (if string.find(flags, "L", 1, true) then "length" else "nil")
					)
					local quality = if string.find(flags, "C", 1, true)
						then "count"
						elseif string.find(flags, "S", 1, true) then "segments"
						else "nil"
					expect(where .. ":quality=" .. tostring(p.quality)).toBe(where .. ":quality=" .. quality)
					expect(where .. ":advanced=" .. tostring(p.advanced == true)).toBe(
						where .. ":advanced=" .. tostring(string.find(flags, "A", 1, true) ~= nil)
					)
					if row.enum then
						expect(p.enum).toEqual(row.enum)
					end
					if row.enumType then
						expect(p.enumType).toBe(row.enumType)
					end
				end
			end)

			T.it("channel list matches COMPONENTS_SPEC (names and kinds)", function()
				local channels = {}
				for _, c in descriptor.channels do
					channels[c.name] = c.kind
				end
				expect(channels).toEqual(expected.channels)
			end)

			T.it("event list matches COMPONENTS_SPEC", function()
				local actions = {}
				for _, e in descriptor.events do
					table.insert(actions, e.action)
				end
				expect(actions).toEqual(expected.events)
			end)

			T.it("property specs are well-formed", function()
				local seen = {}
				for _, p in descriptor.properties do
					local where = typeName .. "." .. tostring(p.name)
					expect(type(p.name)).toBe("string")
					expect(p.name).toMatch("^[a-z][A-Za-z0-9]*$")
					expect(seen[p.name]).toBeNil()
					seen[p.name] = true
					expect(table.find(Codec.KINDS, p.kind) ~= nil).toBe(true)
					expect(where .. ":" .. tostring(type(p.description) == "string" and #p.description > 0)).toBe(
						where .. ":true"
					)
					expect(where .. ":" .. tostring(type(p.category) == "string" and #p.category > 0)).toBe(
						where .. ":true"
					)
					if p.min ~= nil and p.max ~= nil then
						expect(p.min).toBeLessThanOrEqual(p.max)
					end
					if p.scale ~= nil then
						expect(p.scale).toBe("length")
						local scalable = {
							number = true,
							integer = true,
							vector3 = true,
							vector2 = true,
							numberRange = true,
							numberSequence = true,
						}
						expect(where .. ":" .. tostring(scalable[p.kind] == true)).toBe(where .. ":true")
					end
					if p.quality ~= nil then
						expect(p.quality == "count" or p.quality == "segments").toBe(true)
						expect(p.kind == "integer" or p.kind == "number").toBe(true)
					end
					if p.kind == "numberSequence" or p.kind == "colorSequence" then
						expect(p.maxKeypoints).toBe(20)
					else
						expect(p.maxKeypoints).toBeNil()
					end
					if p.kind == "enum" then
						expect(type(p.enum) == "table" and #p.enum > 0).toBe(true)
						local names = {}
						for _, name in p.enum do
							expect(names[name]).toBeNil()
							names[name] = true
						end
						expect(names[p.default]).toBe(true)
					else
						expect(p.enum).toBeNil()
						expect(p.enumType).toBeNil()
					end
				end
			end)

			T.it("every enumType name is a real Roblox Enum item (Codec.decode yields an EnumItem)", function()
				for _, p in descriptor.properties do
					if p.kind == "enum" and p.enumType then
						for _, name in p.enum do
							local item = Codec.decode("enum", name, p)
							expect(typeof(item)).toBe("EnumItem")
							expect(item.Name).toBe(name)
							expect(item.EnumType).toBe((Enum :: any)[p.enumType])
						end
					end
				end
			end)

			T.it("every default passes Codec.check, decodes and round-trips through encode", function()
				for _, p in descriptor.properties do
					local where = typeName .. "." .. p.name
					local ok, message = Codec.check(p.kind, p.default, p)
					expect(where .. ":" .. tostring(ok) .. ":" .. tostring(message)).toBe(where .. ":true:nil")
					local decoded = Codec.decode(p.kind, Codec.default(p), p)
					expect(decoded ~= nil).toBe(true)
					local normalized = Codec.normalize(p.kind, p.default, p)
					expect(Codec.encode(p.kind, decoded, p)).toEqual(normalized)
					local canonical = NON_CANONICAL_DEFAULTS[where]
					if canonical ~= nil then
						expect(normalized).toEqual(canonical)
					else
						expect(normalized).toEqual(p.default)
					end
				end
			end)

			T.it("channel specs are well-formed and consistent with their base properties", function()
				local props = {}
				for _, p in descriptor.properties do
					props[p.name] = p
				end
				local seen = {}
				for _, c in descriptor.channels do
					local where = typeName .. ":" .. tostring(c.name)
					expect(c.name).toMatch("^[a-z][A-Za-z0-9]*$")
					expect(seen[c.name]).toBeNil()
					seen[c.name] = true
					expect(table.find(Codec.CHANNEL_KINDS, c.kind) ~= nil).toBe(true)
					expect(type(c.description) == "string" and #c.description > 0).toBe(true)
					if c.min ~= nil and c.max ~= nil then
						expect(c.min).toBeLessThanOrEqual(c.max)
					end
					if c.scale ~= nil then
						expect(c.scale).toBe("length")
					end
					if c.name == "position" then
						expect(where .. ":" .. c.kind .. ":" .. tostring(c.scale)).toBe(where .. ":vector3:length")
					elseif c.name == "rotation" then
						expect(where .. ":" .. c.kind .. ":" .. tostring(c.scale)).toBe(where .. ":vector3:nil")
					elseif c.name == "scale" then
						expect(where .. ":" .. c.kind .. ":" .. tostring(c.min)).toBe(where .. ":number:0")
						expect(c.baseProperty).toBeNil()
					elseif c.name == "transparency" then
						expect(where .. ":" .. tostring(c.min) .. ".." .. tostring(c.max)).toBe(where .. ":0..1")
					elseif c.name == "tint" or c.name == "color" then
						expect(c.kind).toBe("color3")
					end
					if c.baseProperty ~= nil then
						local base = props[c.baseProperty]
						expect(where .. " base " .. tostring(base ~= nil)).toBe(where .. " base true")
						local compatible = c.kind == base.kind or (c.kind == "number" and base.kind == "integer")
						expect(where .. " kind " .. tostring(compatible)).toBe(where .. " kind true")
						-- The Compiler scales both or neither: a mismatch would make tracks jump against the rest value.
						expect(where .. " scale " .. tostring(c.scale)).toBe(where .. " scale " .. tostring(base.scale))
						expect(Codec.check(c.kind, base.default, c)).toBe(true)
					end
				end
			end)

			T.it("channel semantics follow COMPONENTS_SPEC §0 (part-like vs sequence-based types)", function()
				local props = {}
				for _, p in descriptor.properties do
					props[p.name] = p
				end
				local transparency = Components.channelSpec(typeName, "transparency")
				if transparency then
					local sequence = props.transparency ~= nil and props.transparency.kind == "numberSequence"
					if sequence or typeName == "sphere" then
						-- Fade channel (sequence types; sphere fades both layers): rest value 0, no base property.
						expect(transparency.baseProperty).toBeNil()
					else
						expect(transparency.baseProperty).toBe("transparency")
					end
				end
				local color = Components.channelSpec(typeName, "color")
				if color then
					expect(color.baseProperty).toBe("color")
					expect(props.color.kind).toBe("color3")
				end
				local tint = Components.channelSpec(typeName, "tint")
				if tint and CAMERA_TYPES[typeName] then
					-- screenFlash: the channel is the TintColor itself; its rest value is the `tint` property.
					expect(tint.baseProperty).toBe("tint")
					expect(props.tint.kind).toBe("color3")
				elseif tint then
					expect(props.color.kind).toBe("colorSequence")
					expect(tint.baseProperty).toBeNil()
				end
			end)

			T.it("event specs are well-formed", function()
				local known = {
					emit = true,
					clear = true,
					enable = true,
					disable = true,
					play = true,
					stop = true,
					regenerate = true,
				}
				local seen = {}
				for _, e in descriptor.events do
					expect(known[e.action]).toBe(true)
					expect(seen[e.action]).toBeNil()
					seen[e.action] = true
					expect(type(e.description) == "string" and #e.description > 0).toBe(true)
					expect(e.usesCount == true).toBe(e.action == "emit")
					expect(e.usesName).toBeNil()
				end
			end)

			T.it("tailTime is declared for particles (lifetime.Max) and trail (lifetime) only", function()
				local h = harness()
				local _, component = h:build(typeName)
				if typeName == "particles" then
					expect(descriptor.tailTime(component)).toBe(2)
				elseif typeName == "trail" then
					expect(descriptor.tailTime(component)).toBeCloseTo(0.5, 1e-9)
				else
					expect(descriptor.tailTime).toBeNil()
				end
			end)
		end)
	end

	-- ─────────────────────────────────────────────────────────────────────────
	-- 3. Build / lifecycle contracts (generic over the registry)
	-- ─────────────────────────────────────────────────────────────────────────

	for _, typeName in EXPECTED_TYPES do
		local descriptor = Components.get(typeName)
		local visibleAt = VISIBLE_AT[typeName] or 0.5

		T.describe("build " .. typeName, function()
			for _, modeName in modesOf(descriptor) do
				T.it(
					modeName .. ": builds with defaults; every instance is tagged and listed by the controller",
					function()
						local h = harness()
						local c, component = h:build(typeName, nil, mode(modeName))
						local tagged = {}
						for _, inst in owned(h, component.id) do
							tagged[inst] = true
						end
						local listed = {}
						for _, inst in c.instances do
							listed[inst] = true
						end
						expect(listed).toEqual(tagged)
						expect(c.component).toBe(component)
						expect(c.anchor).toBeNil()
						if CAMERA_TYPES[typeName] then
							expect(#c.instances).toBe(0)
						elseif typeName ~= "group" and modeName == "runtime" then
							expect(c.instances[1].ClassName).toBe(MAIN_CLASS[typeName])
						end
						-- Nothing outside the container, nothing under the container except tagged instances + Root.
						for _, inst: any in h.container:GetDescendants() do
							if inst ~= h.root then
								expect(tagged[inst]).toBe(true)
							end
						end
					end
				)

				T.it(modeName .. ": parts are anchored and physics-free", function()
					local h = harness()
					local _, component = h:build(typeName, nil, mode(modeName))
					for _, inst: any in owned(h, component.id) do
						if inst:IsA("BasePart") then
							expect(inst.Anchored).toBe(true)
							expect(inst.CanCollide).toBe(false)
							expect(inst.CanQuery).toBe(false)
							expect(inst.CanTouch).toBe(false)
						end
					end
				end)

				T.itIf(isLune, modeName .. ": invisible / disabled / silent until setActive(true)", function()
					local h = harness()
					local c, component = h:build(typeName, SHOW_PROPS[typeName], mode(modeName))
					step(h, c, visibleAt)
					expect(fakes:renderBindingCount()).toBe(0)
					for _, inst: any in owned(h, component.id) do
						if inst:IsA("BasePart") then
							expect(inst.Transparency).toBe(1)
						elseif
							inst:IsA("ParticleEmitter")
							or inst:IsA("Beam")
							or inst:IsA("Trail")
							or inst:IsA("Light")
						then
							expect(inst.Enabled).toBe(false)
						elseif inst:IsA("Attachment") and typeName ~= "group" then
							expect(inst.Visible).toBe(false)
						end
					end
					expect(visibleCount(h, component.id)).toBe(0)
					expect(#fakes.emits).toBe(0)
					expect(soundActions()).toBe(0)
				end)

				T.itIf(isLune, modeName .. ": shows (or plays) something once active", function()
					local h = harness()
					local c, component = h:build(typeName, SHOW_PROPS[typeName], mode(modeName))
					c:setActive(true, frameAt(h, visibleAt))
					step(h, c, visibleAt)
					if typeName == "group" then
						expect(visibleCount(h, component.id)).toBe(0)
					elseif typeName == "sound" then
						expect(soundActions()).toBeGreaterThan(0)
					else
						expect(visibleCount(h, component.id)).toBeGreaterThan(0)
					end
					c:setActive(false, frameAt(h, visibleAt))
					step(h, c, visibleAt)
					expect(visibleCount(h, component.id)).toBe(0)
					expect(fakes:renderBindingCount()).toBe(0)
				end)

				if modeName == "viewport" then
					T.it(
						"viewport: builds no particles, beams, trails, lights or sounds (they do not render there)",
						function()
							local h = harness()
							local _, component = h:build(typeName, nil, mode(modeName))
							local n = counts(h, component.id)
							expect(n.emitters + n.beams + n.trails + n.lights + n.sounds).toBe(0)
						end
					)
				end

				-- Camera types are counted while they show (screenFlash's effect exists only then); at runtime that
				-- needs the simulated client (Lune).
				local countable = not CAMERA_TYPES[typeName] or modeName == "preview" or isLune
				if modeName ~= "viewport" and not (typeName == "group" and modeName == "preview") then
					T.itIf(
						countable,
						modeName .. ": estimateCost counts match the built instances exactly (defaults and variants)",
						function()
							local variants: { { [string]: any } } = { {} }
							local extra: { { [string]: any } } = VARIANTS[typeName] or {}
							for _, v in extra do
								table.insert(variants, v)
							end
							for _, props in variants do
								for _, quality in { HIGH, LOW } do
									local h = harness()
									local options = merge(mode(modeName), { quality = quality })
									local c, component = h:build(typeName, props, options)
									if CAMERA_TYPES[typeName] then
										c:setActive(true, frameAt(h, visibleAt))
										step(h, c, visibleAt)
									end
									local cost = descriptor.estimateCost(component, quality)
									local actual = counts(h, component.id)
									for key, value in actual do
										expect(typeName .. "." .. key .. "=" .. tostring(cost[key])).toBe(
											typeName .. "." .. key .. "=" .. tostring(value)
										)
									end
									-- builds of one test share the test camera: leave it to the next variant
									c:destroy()
								end
							end
						end
					)
				end

				T.itIf(isLune, modeName .. ": full lifecycle runs without errors and destroy leaves nothing", function()
					local h = harness()
					local c, component = h:build(typeName, nil, mode(modeName))
					local f0 = frameAt(h, 0)
					c:setActive(true, f0)
					for _, spec in descriptor.channels do
						local v = sampleValue(spec)
						if v ~= nil then
							c:apply(spec.name, v)
						end
					end
					step(h, c, 0.25, CFrame.new(1, 2, 3))
					for i, event in descriptor.events do
						local f = frameAt(h, 0.3)
						c:onAction(eventAction(event, i, 0.3), f)
						h:flush(f)
					end
					step(h, c, 0.6, CFrame.new(-1, 0, 2) * CFrame.Angles(0.2, 0.4, 0))
					c:release()
					step(h, c, 0.9)
					c:reset()
					c:setActive(false, frameAt(h, 1))
					c:destroy()
					expect(#c.instances).toBe(0)
					expect(#owned(h, component.id)).toBe(0)
					expect(#h.container:GetChildren()).toBe(1) -- only the Root part is left
					-- camera types: nothing left under the camera, camera restored, no render-step binding leaked
					expect(#(camera :: Camera):GetChildren()).toBe(0)
					expect((camera :: Camera).CFrame).toBe(cameraHome)
					expect(fakes:renderBindingCount()).toBe(0)
					c:destroy() -- a second destroy is harmless
				end)
			end

			T.it("ignores unknown channels and unknown actions silently", function()
				local h = harness()
				local c, component = h:build(typeName)
				c:setActive(true, frameAt(h, visibleAt))
				step(h, c, visibleAt)
				local before = snapshot(h, component.id)
				c:apply("noSuchChannel", 1)
				c:apply("noSuchChannel", Vector3.new(1, 2, 3))
				c:onAction({ time = 0, action = "noSuchAction", source = "event", order = 1 }, frameAt(h, visibleAt))
				-- Wrong value types for real channels are ignored as well.
				for _, spec in descriptor.channels do
					c:apply(spec.name, if spec.kind == "number" then "not a number" else 12345)
				end
				step(h, c, visibleAt)
				expect(snapshot(h, component.id)).toBe(before)
			end)

			T.it("applying every channel's rest value changes nothing (High and Low quality, scale 1 and 2)", function()
				for _, quality in { HIGH, LOW } do
					for _, scale in { 1, 2 } do
						local h = harness()
						local c, component = h:build(typeName, nil, { quality = quality, scale = scale })
						c:setActive(true, frameAt(h, visibleAt))
						step(h, c, visibleAt)
						local before = snapshot(h, component.id)
						for _, spec in descriptor.channels do
							local v = restValue(spec, component)
							if v ~= nil then
								c:apply(spec.name, v)
							end
						end
						step(h, c, visibleAt)
						expect(snapshot(h, component.id)).toBe(before)
						c:destroy() -- the builds share the test camera
					end
				end
			end)

			for _, modeName in { "runtime", "preview" } do
				-- group's preview gizmo (Group.luau, the reference descriptor) rewrites Attachment.CFrame every frame.
				local skipped = typeName == "group" and modeName == "preview"
				T.itIf(
					isLune and not skipped,
					modeName .. ": identical values, transforms and times cause no property writes",
					function()
						local h = harness()
						local c, component = h:build(typeName, nil, mode(modeName))
						local cf = CFrame.new(2, 1, -3) * CFrame.Angles(0.3, 0.1, 0)
						c:setActive(true, frameAt(h, visibleAt))
						local function frame(): any
							for _, spec in descriptor.channels do
								local v = sampleValue(spec)
								if v ~= nil then
									c:apply(spec.name, v)
								end
							end
							local f = frameAt(h, visibleAt)
							c:setTransform(cf, h.root.CFrame * cf, f)
							if c.update then
								c:update(visibleAt, f)
							end
							return f
						end
						h:flush(frame())
						-- Overwrite every watched property with a sentinel: a redundant write would restore the real value.
						local sentinels = {}
						for _, inst: any in owned(h, component.id) do
							for _, entry in WATCHED do
								local class: string, props: { string } = entry[1], entry[2]
								if inst:IsA(class) then
									for _, prop in props do
										local v = inst[prop]
										local t = typeof(v)
										local s: any = nil
										if t == "number" then
											s = v + 1
										elseif t == "boolean" then
											s = not v
										elseif t == "Vector3" then
											s = v + Vector3.new(1, 1, 1)
										elseif t == "Color3" then
											s = Color3.new(0.123, 0.456, 0.789)
										elseif t == "CFrame" then
											s = v * CFrame.new(1, 1, 1)
										elseif t == "NumberSequence" then
											s = NumberSequence.new(0.123)
										elseif t == "ColorSequence" then
											s = ColorSequence.new(Color3.new(0.123, 0.456, 0.789))
										end
										if s ~= nil then
											inst[prop] = s
											table.insert(sentinels, { inst, prop, tostring(inst[prop]) })
										end
									end
								end
							end
						end
						local f = frame()
						expect(#f.moveParts).toBe(0)
						h:flush(f)
						for _, entry in sentinels do
							local inst: any, prop: string, value: string = entry[1], entry[2], entry[3]
							expect(inst.Name .. "." .. prop .. "=" .. tostring(inst[prop])).toBe(
								inst.Name .. "." .. prop .. "=" .. value
							)
						end
					end
				)
			end

			T.it("moves parts only through frame.moveParts (no direct CFrame writes in setTransform/update)", function()
				local h = harness()
				local c, component = h:build(typeName)
				c:setActive(true, frameAt(h, visibleAt))
				step(h, c, visibleAt)
				local before = {}
				for _, inst: any in owned(h, component.id) do
					if inst:IsA("BasePart") then
						before[inst] = inst.CFrame
					end
				end
				local cf = CFrame.new(10, 4, -6) * CFrame.Angles(0, 0.7, 0)
				local f = frameAt(h, visibleAt + 0.1)
				c:setTransform(cf, h.root.CFrame * cf, f)
				if c.update then
					c:update(visibleAt + 0.1, f)
				end
				for part, cframe in before do
					expect(part.CFrame).toEqual(cframe)
				end
				for _, part in f.moveParts do
					expect(before[part] ~= nil).toBe(true)
				end
				expect(#f.moveParts).toBe(#f.moveCFrames)
				h:flush(f)
			end)

			T.it("reset() restores the freshly built state after channels, events, moves and release", function()
				local h = harness()
				local c, component = h:build(typeName)
				-- BasePart CFrames are not part of the built state: moved parts stay where they are and are
				-- re-queued by the next setTransform (the pool re-parents the container).
				local skip = { ["BasePart.CFrame"] = true }
				local built = snapshot(h, component.id, skip)
				c:setActive(true, frameAt(h, 0))
				for _, spec in descriptor.channels do
					local v = sampleValue(spec)
					if v ~= nil then
						c:apply(spec.name, v)
					end
				end
				step(h, c, 0.4, CFrame.new(3, 3, 3))
				for i, event in descriptor.events do
					c:onAction(eventAction(event, i, 0.4), frameAt(h, 0.4))
				end
				step(h, c, 0.8, CFrame.new(-3, 1, 0))
				c:release()
				c:reset()
				expect(snapshot(h, component.id, skip)).toBe(built)
			end)

			T.it("is deterministic: the state at t = 0.7 does not depend on the frame history", function()
				local function run(history: { { any } }, seed: number): string
					local h = harness()
					local c, component = h:build(typeName, nil, { seed = seed })
					local cf = CFrame.new(1, 2, 3) * CFrame.Angles(0.1, 0.2, 0.3)
					for _, entry in history do
						local t: number, command: string? = entry[1], entry[2]
						local f = frameAt(h, t, entry[3] == true)
						if command == "reset" then
							c:reset()
						elseif command == "release" then
							c:release()
						elseif command == "on" then
							c:setActive(true, f)
						elseif command == "off" then
							c:setActive(false, f)
						elseif command == "samples" then
							for _, spec in descriptor.channels do
								local v = sampleValue(spec)
								if v ~= nil then
									c:apply(spec.name, v)
								end
							end
						elseif command == "rest" then
							for _, spec in descriptor.channels do
								local v = restValue(spec, component)
								if v ~= nil then
									c:apply(spec.name, v)
								end
							end
						end
						step(h, c, t, if entry[4] then CFrame.new(9, 9, 9) else cf, entry[3] == true)
					end
					local state = snapshot(h, component.id)
					c:destroy() -- the runs share the test camera
					return state
				end
				local direct: { { any } } = { { 0.7, "on" } }
				local winding: { { any } } = {
					{ 0, "on" },
					{ 0.1, nil, false, true },
					{ 1.5, "samples" },
					{ 0.3, "off" },
					{ 0.2, "release" },
					{ 0.25, "reset" },
					{ 1.9, "on", true },
					{ 0.4, "samples", true },
					{ 0.5, "rest" },
					{ 0.7 },
				}
				expect(run(winding, 4242)).toBe(run(direct, 4242))
				-- Same seed, same result; the procedural types with randomness depend on the seed (the camera shake's
				-- noise phases too — visible here when it runs as the simulated Lune client).
				expect(run(direct, 4242)).toBe(run(direct, 4242))
				local seeded = typeName == "radialBurst" or typeName == "debris" or typeName == "lightning"
				if seeded or (typeName == "cameraShake" and isLune) then
					expect(run(direct, 4242)).never.toBe(run(direct, 77))
				else
					expect(run(direct, 4242)).toBe(run(direct, 77))
				end
			end)

			T.itIf(isLune, "emits nothing, plays nothing and keeps emitters off while seeking", function()
				local h = harness()
				local props = if typeName == "sound"
					then { soundId = "rbxassetid://1" }
					elseif typeName == "particles" then { burst = 25 }
					else nil
				local c, component = h:build(typeName, props)
				c:setActive(true, frameAt(h, visibleAt, true))
				step(h, c, visibleAt, CFrame.new(5, 0, 0), true)
				for i, event in descriptor.events do
					c:onAction(eventAction(event, i, visibleAt), frameAt(h, visibleAt, true))
				end
				step(h, c, visibleAt, CFrame.new(6, 0, 0), true)
				expect(#fakes.emits).toBe(0)
				local plays = 0
				for _, s in fakes.sounds do
					if s.action == "Play" then
						plays += 1
					end
				end
				expect(plays).toBe(0)
				for _, inst: any in owned(h, component.id) do
					if inst:IsA("ParticleEmitter") then
						expect(inst.Enabled).toBe(false)
					end
				end
			end)
		end)
	end
end
