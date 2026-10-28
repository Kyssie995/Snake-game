--!strict
--[[
	Layers — component recipes of Authoring/Generator. Every layer kind adds one or more components to the draft
	through the Composer's builder (`b:add(spec)`); the composer resolves which kinds an effect gets, the timeline
	and the context (`c`). docs/research/vfx-design-performance.md §2.1–2.7 holds the craft rules used here:

	  * phases: anticipation → charge → action → impact → secondary → dissipation; the "Impact" marker sits on the
	    impact moment c.times.impact, every impact layer starts there.
	  * impact flash: attack 0.03 s, hold 0.02 s, decay 0.2–0.35 s (R3; a 2–3 frame peak), bright core colour.
	  * shockwave: 0.4–0.8 s expansion with Quart.Out, fade with Quad.In (A6, R7).
	  * sparks: small, additive (LightEmission 1), stretched along their velocity, short lifetime (A20, A21, R1).
	  * smoke: lingers longest, 1–2 s fade (lifetime), lit by the environment (A19, A20, R8).
	  * colour: "$core" (bright focus) → "$mid" (saturated) → "$edge" (dark end, fades additively) (A13–A16, R9).
	  * restraint: particle counts and procedural part counts stay well inside Analyzer.BUDGETS.High; optional
	    layers carry minQuality = "Medium" (or "High") so Low keeps only the readable silhouette (B3, §4.2).

	Context `c` (Composer): S (size scale = intensity), N (count scale), T (time factor), I (intensity),
	times = { anticipation, charge, action, impact } (absolute starts), lens = { anticipation, charge, action,
	secondary, dissipation } (seconds), loop / D (loop duration), center (core position), target (impact
	position), ground (y of ground layers), E (element profile), A (archetype template), element, archetype,
	bright, forceSmoke, tilt (slash roll in degrees), rng (Core/Random, seeded).

	Spec for b:add: { name, type, phase, start, duration, parent?, position?, rotation?, properties,
	tracks? = { { channel, keys = { K(time, value, easing?) } } }, events? = { { action, time, count?, name? } },
	minQuality?, overrides? = { [level] = { property = value } }, notes? } → component id.
	Numbers are rounded and property / keyframe values are normalised by the builder.
]]

local Recipes = require(script.Parent.Recipes)

local Layers = {}

export type Key = { any }
export type TrackSpec = { channel: string, keys: { Key } }
export type EventSpec = { action: string, time: number, count: number?, name: string? }
export type LayerSpec = {
	name: string,
	type: string,
	phase: string,
	start: number,
	duration: number,
	parent: string?,
	position: { number }?,
	rotation: { number }?,
	properties: { [string]: any },
	tracks: { TrackSpec }?,
	events: { EventSpec }?,
	minQuality: string?,
	overrides: { [string]: { [string]: any } }?,
	notes: string?,
}
export type Builder = {
	add: (self: Builder, spec: LayerSpec) -> string,
}
export type Ctx = {
	S: number,
	N: number,
	T: number,
	I: number,
	times: { anticipation: number, charge: number, action: number, impact: number },
	lens: { anticipation: number, charge: number, action: number, secondary: number, dissipation: number },
	loop: boolean,
	D: number,
	center: { number },
	target: { number },
	ground: number,
	E: Recipes.ElementProfile,
	A: Recipes.ArchetypeTemplate,
	element: string,
	archetype: string,
	bright: boolean,
	forceSmoke: boolean,
	tilt: number,
	rng: any,
	explicit: { [string]: boolean },
}

local TX = Recipes.TEXTURES

-- Phase of every layer kind (sorting and markers).
Layers.PHASE = {
	glint = "anticipation",
	gather = "anticipation",
	telegraph = "anticipation",
	chargeSphere = "charge",
	chargeParticles = "charge",
	chargeArcs = "charge",
	portal = "charge",
	coreBurst = "action",
	orb = "action",
	arcs = "action",
	strikeAction = "action",
	beam = "action",
	slash = "action",
	swing = "action",
	pillar = "action",
	meteor = "action",
	auraBody = "action",
	circle = "action",
	flash = "impact",
	shockwave = "impact",
	sparks = "impact",
	rays = "impact",
	shake = "impact",
	screen = "impact",
	flameBurst = "impact",
	splash = "impact",
	pulse = "impact",
	skyBeam = "impact",
	embers = "secondary",
	debris = "secondary",
	elementDebris = "secondary",
	residualArcs = "secondary",
	orbit = "secondary",
	motes = "secondary",
	bubbles = "secondary",
	leaves = "secondary",
	dissipation = "dissipation",
} :: { [string]: string }

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

-- Keyframe { time, value, easing? } (mixed array; a helper keeps the type checker from inferring { number }).
local function K(time: number, value: any, easing: string?): Key
	return { time, value, easing }
end

-- Colour keypoint { time, "$key" }.
local function C(time: number, colour: string): { any }
	return { time, colour }
end

local function clamp(x: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, x))
end

local function add3(a: { number }, b: { number }): { number }
	return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
end

-- Position on the ground below `p`.
local function grounded(c: Ctx, p: { number }): { number }
	return { p[1], c.ground, p[3] }
end

-- Unit direction from yaw / pitch (radians); yaw 0 = −Z (forward).
local function direction(yaw: number, pitch: number): { number }
	return { -math.cos(pitch) * math.sin(yaw), math.sin(pitch), -math.cos(pitch) * math.cos(yaw) }
end

local function scaled(v: { number }, k: number): { number }
	return { v[1] * k, v[2] * k, v[3] * k }
end

local function fadeTrack(duration: number, hold: number): TrackSpec
	return { channel = "transparency", keys = { K(0, 0), K(duration * hold, 0, "Quad.In"), K(duration, 1) } }
end

-- Start and length of a one-shot post-impact layer, or the whole loop.
local function postImpact(c: Ctx, delay: number, length: number): (number, number)
	if c.loop then
		return 0, c.D
	end
	return c.times.impact + delay, length
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Anticipation
-- ─────────────────────────────────────────────────────────────────────────────

-- A short glint at the hit point: the eye goes there before the impact.
function Layers.glint(b: Builder, c: Ctx)
	local len = math.max(c.lens.anticipation, 0.05) + 0.05
	b:add({
		name = "Wind-up Glint",
		type = "particles",
		phase = "anticipation",
		start = 0,
		duration = len,
		position = c.center,
		properties = {
			texture = TX.sparkles,
			color = "$core",
			rate = 0,
			burst = 2,
			lifetime = { len, len + 0.03 },
			speed = 0,
			size = { { 0, 0 }, { 0.5, 2.4 * c.S }, { 1, 0 } },
			rotation = { 0, 90 },
			rotSpeed = { 120, 240 },
			lightEmission = 1,
			zOffset = 1,
		},
		notes = "Anticipation: a short glint marks the focus point before the hit.",
	})
end

-- Particles pulled inwards (implosion) before the release.
function Layers.gather(b: Builder, c: Ctx)
	local S = c.S
	local len = math.max(c.lens.anticipation, 0.1)
	if c.lens.charge > 0 then
		len = math.max(len, 0.12)
	end
	local name = if c.element == "shadow" then "Dark Vortex" else "Gathering Energy"
	b:add({
		name = name,
		type = "particles",
		phase = "anticipation",
		start = 0,
		duration = len,
		position = c.center,
		properties = {
			texture = c.E.spark,
			shape = "Sphere",
			shapeStyle = "Surface",
			shapeInOut = "Inward",
			emitterSize = { 6 * S, 6 * S, 6 * S },
			speed = { 9 * S, 11 * S },
			lifetime = { 0.25, 0.3 },
			rate = 90 * c.N,
			size = { { 0, 0.15 * S }, { 0.7, 0.4 * S }, { 1, 0 } },
			color = { C(0, "$mid"), C(1, "$core") },
			transparency = { { 0, 1 }, { 0.3, 0 }, { 1, 0 } },
			rotSpeed = if c.element == "shadow" then { -240, 240 } else nil,
			lightEmission = 1,
		},
		notes = "Anticipation: particles rush inwards (implosion) before the release.",
	})
end

-- Ground marker that fades in before the hit (telegraph).
function Layers.telegraph(b: Builder, c: Ctx)
	local S = c.S
	local dur = math.max(c.times.impact, 0.1)
	local radius = (if c.archetype == "meteor" then 5 else 3) * S
	local fadeIn = math.max(c.lens.anticipation * 0.8, 0.05)
	local tracks: { TrackSpec } = {
		{ channel = "transparency", keys = { K(0, 1, "Quad.Out"), K(math.min(fadeIn, dur), 0.35), K(dur, 0.2) } },
	}
	if c.archetype == "meteor" then
		table.insert(tracks, { channel = "radius", keys = { K(0, radius, "Quad.In"), K(dur, radius * 0.7) } })
	end
	b:add({
		name = "Target Telegraph",
		type = "ring",
		phase = "anticipation",
		start = 0,
		duration = dur,
		position = { c.target[1], c.ground + 0.04, c.target[3] },
		properties = {
			style = "ring",
			segments = 32,
			radius = radius,
			thickness = 0.18 * S,
			height = 0.06,
			color = "$mid",
			material = "Neon",
			transparency = 1,
		},
		tracks = tracks,
		notes = "Anticipation: telegraphs where the hit lands (fade in, then the impact replaces it).",
	})
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Charge
-- ─────────────────────────────────────────────────────────────────────────────

function Layers.chargeSphere(b: Builder, c: Ctx)
	local S = c.S
	local R = (if c.archetype == "beam" then 0.8 else 1.1) * S
	local props = {
		radius = R,
		coreColor = "$core",
		shellColor = "$mid",
		shellMaterial = c.E.shellMaterial,
		shellScale = 1.5,
		shellTransparency = 0.3,
		pulseAmplitude = 0.08,
		pulseFrequency = 7,
		light = true,
		lightBrightness = 4,
		lightRange = clamp(10 * S, 4, 60),
	}
	if c.loop then
		b:add({
			name = "Charge Sphere",
			type = "sphere",
			phase = "charge",
			start = 0,
			duration = c.D,
			position = c.center,
			properties = props,
			tracks = {
				{
					channel = "radius",
					keys = { K(0, 0.85 * R, "Sine.InOut"), K(c.D / 2, R, "Sine.InOut"), K(c.D, 0.85 * R) },
				},
			},
			overrides = { Low = { light = false } },
			notes = "Charge: a pulsing energy sphere at the centre.",
		})
		return
	end
	local cLen = c.lens.charge
	local aLen = c.lens.action
	b:add({
		name = "Charge Sphere",
		type = "sphere",
		phase = "charge",
		start = c.times.charge,
		duration = cLen + aLen + 0.02,
		position = if c.archetype == "beam" then { c.center[1], c.center[2], c.center[3] - S } else c.center,
		properties = props,
		tracks = {
			{
				channel = "radius",
				keys = { K(0, 0.15 * R, "Quad.In"), K(cLen, R, "Back.In"), K(cLen + aLen, 0.7 * R) },
			},
			{ channel = "lightBrightness", keys = { K(0, 0, "Quad.In"), K(cLen, 4), K(cLen + aLen, 6) } },
		},
		overrides = { Low = { light = false } },
		notes = "Charge: the sphere grows (Quad.In), squashes before the release (Back.In) and is replaced by the impact.",
	})
end

function Layers.chargeParticles(b: Builder, c: Ctx)
	local S = c.S
	local start, dur = c.times.charge, c.lens.charge + c.lens.action
	local tracks: { TrackSpec }? = nil
	if c.loop then
		start, dur = 0, c.D
	else
		tracks = {
			{ channel = "rate", keys = { K(0, 25 * c.N, "Quad.In"), K(c.lens.charge, 70 * c.N), K(dur, 70 * c.N) } },
		}
	end
	b:add({
		name = "Charge Particles",
		type = "particles",
		phase = "charge",
		start = start,
		duration = dur,
		position = if c.archetype == "beam" then { c.center[1], c.center[2], c.center[3] - S } else c.center,
		properties = {
			texture = c.E.spark,
			shape = "Sphere",
			shapeStyle = "Surface",
			shapeInOut = "Inward",
			emitterSize = { 7 * S, 7 * S, 7 * S },
			speed = { 8.5 * S, 9.5 * S },
			lifetime = { 0.38, 0.42 },
			rate = (if c.loop then 40 else 25) * c.N,
			size = { { 0, 0.1 * S }, { 0.6, 0.35 * S }, { 1, 0.05 * S } },
			color = { C(0, "$mid"), C(1, "$core") },
			transparency = { { 0, 1 }, { 0.25, 0 }, { 1, 0 } },
			lightEmission = 1,
		},
		tracks = tracks,
		notes = "Charge: energy streams into the centre; the rate ramps up towards the release.",
	})
end

-- Short crackling arcs around a charging sphere (lightning).
function Layers.chargeArcs(b: Builder, c: Ctx)
	if c.loop or c.lens.charge <= 0 then
		return
	end
	local S = c.S
	local start = c.times.charge + 0.3 * c.lens.charge
	local dur = math.max(c.times.action - 0.01 - start, 0.05)
	for i = 1, 2 do
		local yaw = (i - 1) * math.pi + c.rng:range(-0.6, 0.6)
		local dir = direction(yaw, c.rng:range(-0.5, 0.8))
		b:add({
			name = "Charge Arc " .. i,
			type = "lightning",
			phase = "charge",
			start = start,
			duration = dur,
			position = c.center,
			properties = {
				from = { 0, 0, 0 },
				to = scaled(dir, 2.6 * S),
				segments = 6,
				jitter = 0.35 * S,
				branches = 0,
				flickerRate = 24,
				thickness = 0.12 * S,
				color = "$core",
				brightness = 3,
				lightEmission = 1,
			},
			minQuality = if i == 1 then "Medium" else "High",
			notes = "Charge: crackling arcs around the charge (optional detail, Medium+).",
		})
	end
end

-- Teleport: a ground portal opens, a vortex pulls energy in.
function Layers.portal(b: Builder, c: Ctx)
	local S = c.S
	local start = c.times.charge
	local total = c.lens.charge + c.lens.action + 0.5 * c.lens.secondary
	local R = 3.2 * S
	local open = math.min(0.3 * c.T, 0.4 * total)
	local close = math.min(0.25 * c.T, 0.3 * total)
	local function radiusKeys(r: number): { Key }
		return { K(0, 0.1, "Back.Out"), K(open, r), K(total - close, r, "Back.In"), K(total, 0.1) }
	end
	local base = { c.target[1], c.ground + 0.04, c.target[3] }
	b:add({
		name = "Portal Ring",
		type = "ring",
		phase = "charge",
		start = start,
		duration = total,
		position = base,
		properties = {
			style = "ring",
			segments = 32,
			radius = R,
			thickness = 0.3 * S,
			height = 0.08,
			color = "$mid",
			material = "Neon",
			spin = { 0, 120, 0 },
		},
		tracks = { { channel = "radius", keys = radiusKeys(R) } },
		notes = "Charge: the portal ring opens (Back.Out) and closes again (Back.In).",
	})
	b:add({
		name = "Portal Runes",
		type = "ring",
		phase = "charge",
		start = start,
		duration = total,
		position = base,
		properties = {
			style = "star",
			points = 6,
			starStep = 2,
			radius = 0.75 * R,
			thickness = 0.14 * S,
			height = 0.06,
			color = "$core",
			material = "Neon",
			spin = { 0, -90, 0 },
		},
		tracks = { { channel = "radius", keys = radiusKeys(0.75 * R) } },
		minQuality = "Medium",
	})
	b:add({
		name = "Portal Vortex",
		type = "particles",
		phase = "charge",
		start = start,
		duration = c.times.impact - start,
		position = { c.target[1], c.ground + 0.6 * S, c.target[3] },
		properties = {
			texture = c.E.spark,
			shape = "Sphere",
			shapeStyle = "Surface",
			shapeInOut = "Inward",
			emitterSize = { 6.5 * S, 6.5 * S, 6.5 * S },
			speed = { 8 * S, 9 * S },
			lifetime = { 0.35, 0.4 },
			rate = 50 * c.N,
			rotation = { 0, 360 },
			rotSpeed = { -180, 180 },
			size = { { 0, 0.4 * S }, { 1, 0.1 * S } },
			color = { C(0, "$mid"), C(1, "$core") },
			transparency = { { 0, 1 }, { 0.3, 0 }, { 1, 0 } },
			lightEmission = 1,
		},
	})
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Action
-- ─────────────────────────────────────────────────────────────────────────────

-- The bright core that compresses before the release and bursts with the impact (Quart.Out).
function Layers.coreBurst(b: Builder, c: Ctx)
	local S = c.S
	local aLen = c.lens.action
	local life = clamp(0.4 * c.T, 0.3, 0.6)
	local dur = aLen + life
	local R0 = 0.7 * S
	local R1 = c.A.coreRadius * S
	b:add({
		name = c.E.coreName,
		type = "sphere",
		phase = "action",
		start = c.times.action,
		duration = dur,
		position = c.center,
		properties = {
			radius = R0,
			coreColor = "$core",
			shellColor = "$mid",
			coreMaterial = "Neon",
			shellMaterial = c.E.shellMaterial,
			shellScale = 1.35,
			shellTransparency = 0.25,
			pulseAmplitude = 0,
			light = false,
		},
		tracks = {
			{ channel = "radius", keys = { K(0, R0, "Quad.In"), K(aLen, 0.75 * R0, "Quart.Out"), K(dur, R1) } },
			{ channel = "transparency", keys = { K(0, 0), K(aLen, 0, "Quad.In"), K(dur, 1) } },
		},
		notes = "Action/core: bright centre, expands with Quart.Out and fades with Quad.In (silhouette layer 1).",
	})
end

-- A floating orb for looping effects.
function Layers.orb(b: Builder, c: Ctx)
	local S = c.S
	local R = 0.8 * S
	b:add({
		name = "Floating Orb",
		type = "sphere",
		phase = "action",
		start = 0,
		duration = c.D,
		position = c.center,
		properties = {
			radius = R,
			coreColor = "$core",
			shellColor = "$mid",
			shellMaterial = c.E.shellMaterial,
			shellScale = 1.4,
			shellTransparency = 0.3,
			pulseAmplitude = 0.06,
			pulseFrequency = 2,
			light = false,
		},
		tracks = {
			{
				channel = "position",
				keys = {
					K(0, c.center, "Sine.InOut"),
					K(c.D / 2, add3(c.center, { 0, 0.4 * S, 0 }), "Sine.InOut"),
					K(c.D, c.center),
				},
			},
		},
	})
end

-- Electric arcs radiating from the centre.
function Layers.arcs(b: Builder, c: Ctx)
	local S = c.S
	local k = if c.I >= 1 then 3 else 2
	local start, dur = c.times.action, c.lens.action + clamp(0.45 * c.T, 0.35, 0.6)
	local length = 7 * S
	if c.loop then
		start, dur, length = 0, c.D, 3 * S
	end
	for i = 1, k do
		local yaw = (i - 1) / k * 2 * math.pi + c.rng:range(-0.35, 0.35)
		local pitch = c.rng:range(-0.15, 0.6)
		local dir = direction(yaw, pitch)
		local tracks: { TrackSpec }? = nil
		if not c.loop then
			tracks = {
				{ channel = "thickness", keys = { K(0, 0.28 * S, "Quad.In"), K(dur, 0.03 * S) } },
				fadeTrack(dur, 0.6),
			}
		end
		b:add({
			name = "Electric Arc " .. i,
			type = "lightning",
			phase = "action",
			start = start,
			duration = dur,
			position = c.center,
			properties = {
				from = { 0, 0, 0 },
				to = scaled(dir, length * c.rng:range(0.85, 1.15)),
				segments = 8,
				jitter = (if c.loop then 0.5 else 0.9) * S,
				branches = 0,
				flickerRate = 30,
				thickness = 0.22 * S,
				color = if i == 1 then "$core" else "$mid",
				brightness = 3,
				lightEmission = 1,
			},
			tracks = tracks,
			minQuality = if i == 2 then "Medium" elseif i == 3 then "High" else nil,
			notes = if i == 1
				then "Action: jagged electric arcs shoot out (thickness thins out, fade at the end)."
				else nil,
		})
	end
end

-- Lightning bolt from the sky into the target.
local function bolt(b: Builder, c: Ctx)
	local S = c.S
	local aLen = c.lens.action
	local dur = aLen + clamp(0.4 * c.T, 0.3, 0.55)
	b:add({
		name = "Lightning Bolt",
		type = "lightning",
		phase = "action",
		start = c.times.action,
		duration = dur,
		position = grounded(c, c.target),
		properties = {
			from = { c.rng:range(-4, 4) * S, 40 * S, c.rng:range(-4, 4) * S },
			to = { 0, 0, 0 },
			segments = 12,
			branches = 2,
			branchLength = 0.35,
			jitter = 2.2 * S,
			flickerRate = 18,
			thickness = 0.45 * S,
			color = "$core",
			brightness = 4,
			lightEmission = 1,
		},
		tracks = {
			{ channel = "thickness", keys = { K(0, 0.55 * S, "Quad.In"), K(dur, 0.05 * S) } },
			fadeTrack(dur, 0.7),
		},
		events = if aLen > 0.01 and aLen < dur then { { action = "regenerate", time = aLen } } else nil,
		notes = "Action: the bolt hits at the impact marker (a new shape at the moment of impact).",
	})
end

-- A vertical beam from the sky (strike without lightning).
local function strikeBeam(b: Builder, c: Ctx)
	local S = c.S
	local aLen = c.lens.action
	local dur = aLen + clamp(0.35 * c.T, 0.3, 0.6)
	local keys = { K(0, 0.1, "Quad.Out"), K(aLen, 1), K(dur * 0.7, 0.8, "Quad.In"), K(dur, 0) }
	local position = grounded(c, c.target)
	b:add({
		name = "Strike Beam",
		type = "beam",
		phase = "action",
		start = c.times.action,
		duration = dur,
		position = position,
		properties = {
			from = { 0, 45 * S, 0 },
			to = { 0, 0, 0 },
			width0 = 3 * S,
			width1 = 3 * S,
			color = { C(0, "$core"), C(1, "$mid") },
			transparency = { { 0, 0.5 }, { 1, 0.15 } },
			lightEmission = 1,
			brightness = 2,
		},
		tracks = { { channel = "scale", keys = keys } },
		notes = "Action: a column of energy slams down into the target.",
	})
	b:add({
		name = "Strike Core",
		type = "beam",
		phase = "action",
		start = c.times.action,
		duration = dur,
		position = position,
		properties = {
			from = { 0, 45 * S, 0 },
			to = { 0, 0, 0 },
			width0 = S,
			width1 = S,
			color = "$core",
			lightEmission = 1,
			brightness = 3,
		},
		tracks = { { channel = "scale", keys = keys } },
	})
end

-- A pillar of light (holy strike, teleport column, explicit "pillar").
function Layers.pillar(b: Builder, c: Ctx)
	local S = c.S
	local H = 26 * S
	local start, dur = c.times.action, c.lens.action + clamp(0.6 * c.T, 0.4, 0.9)
	if c.loop then
		start, dur = 0, c.D
	end
	local tracks: { TrackSpec }
	if c.loop then
		tracks = {
			{
				channel = "transparency",
				keys = { K(0, 0.35, "Sine.InOut"), K(c.D / 2, 0.15, "Sine.InOut"), K(c.D, 0.35) },
			},
		}
	else
		local peak = math.min(0.15 * c.T, 0.4 * dur)
		tracks = {
			{
				channel = "size",
				keys = {
					K(0, { H, 0.2 * S, 0.2 * S }, "Back.Out"),
					K(peak, { H, 3 * S, 3 * S }, "Sine.InOut"),
					K(dur * 0.7, { H, 2.2 * S, 2.2 * S }, "Quad.In"),
					K(dur, { H, 0.05, 0.05 }),
				},
			},
			{ channel = "transparency", keys = { K(0, 0.1), K(dur * 0.7, 0.15, "Quad.In"), K(dur, 1) } },
		}
	end
	b:add({
		name = "Light Pillar",
		type = "part",
		phase = "action",
		start = start,
		duration = dur,
		position = { c.target[1], c.ground + H / 2, c.target[3] },
		rotation = { 0, 0, 90 },
		properties = {
			shape = "Cylinder",
			size = { H, 2.4 * S, 2.4 * S },
			color = "$mid",
			material = "Neon",
			transparency = if c.loop then 0.35 else 0.1,
		},
		tracks = tracks,
		notes = "Action: a vertical column (cylinder axis turned up); widens with Back.Out, thins out at the end.",
	})
	b:add({
		name = "Pillar Sparkles",
		type = "particles",
		phase = "action",
		start = start,
		duration = dur,
		position = { c.target[1], c.ground + 0.45 * H, c.target[3] },
		properties = {
			texture = c.E.spark,
			shape = "Box",
			emitterSize = { 2 * S, 0.8 * H, 2 * S },
			emissionDirection = "Top",
			speed = { 6 * S, 12 * S },
			lifetime = { 0.5, 0.9 },
			rate = 40 * c.N,
			size = { { 0, 0.3 * S }, { 1, 0 } },
			color = "$core",
			lightEmission = 1,
		},
		minQuality = "Medium",
	})
end

-- Strike action by element: a bolt (lightning, energy, shadow), a pillar (holy) or a sky beam.
function Layers.strikeAction(b: Builder, c: Ctx)
	if c.element == "lightning" or c.element == "energy" or c.element == "shadow" then
		bolt(b, c)
	elseif c.element == "holy" then
		Layers.pillar(b, c)
	else
		strikeBeam(b, c)
	end
end

-- Laser / energy beam: a white core inside a saturated glow, plus a muzzle flash.
function Layers.beam(b: Builder, c: Ctx)
	local S = c.S
	local aLen = c.lens.action
	local sustain = c.lens.secondary
	local dur = aLen + sustain
	local fade = math.min(0.2 * c.T, 0.3)
	local muzzle = { c.center[1], c.center[2], c.center[3] - S }
	local L = 36 * S
	local keys = {
		K(0, 0, "Back.Out"),
		K(aLen, 1, "Sine.InOut"),
		K(aLen + sustain * 0.5, 1.12, "Sine.InOut"),
		K(dur - fade, 1, "Quad.In"),
		K(dur, 0),
	}
	b:add({
		name = "Beam Glow",
		type = "beam",
		phase = "action",
		start = c.times.action,
		duration = dur,
		position = muzzle,
		properties = {
			from = { 0, 0, 0 },
			to = { 0, 0, -L },
			width0 = 2.6 * S,
			width1 = 2.6 * S,
			color = { C(0, "$core"), C(1, "$mid") },
			transparency = { { 0, 0.15 }, { 1, 0.35 } },
			lightEmission = 1,
			brightness = 2,
		},
		tracks = { { channel = "scale", keys = keys } },
		notes = "Action: the beam opens with Back.Out, pulses while it sustains and closes with Quad.In.",
	})
	b:add({
		name = "Beam Core",
		type = "beam",
		phase = "action",
		start = c.times.action,
		duration = dur,
		position = muzzle,
		properties = {
			from = { 0, 0, 0 },
			to = { 0, 0, -L },
			width0 = 0.9 * S,
			width1 = 0.9 * S,
			color = "$core",
			lightEmission = 1,
			brightness = 3,
		},
		tracks = { { channel = "scale", keys = keys } },
	})
	b:add({
		name = "Muzzle Flash",
		type = "flash",
		phase = "action",
		start = c.times.action,
		duration = 0.32,
		position = muzzle,
		properties = {
			color = "$core",
			size = 3 * S,
			startSize = 0.5 * S,
			attack = 0.03,
			hold = 0.05,
			decay = 0.2,
			light = false,
		},
	})
end

-- An upward beam erupting from the centre (explicit "beam" in other archetypes).
function Layers.skyBeam(b: Builder, c: Ctx)
	local S = c.S
	local start, dur = c.times.impact, clamp(0.6 * c.T, 0.4, 0.9)
	local keys: { Key } = { K(0, 0, "Back.Out"), K(0.12, 1), K(dur * 0.7, 0.9, "Quad.In"), K(dur, 0) }
	if c.loop then
		start, dur = 0, c.D
		keys = { K(0, 0.85, "Sine.InOut"), K(c.D / 2, 1, "Sine.InOut"), K(c.D, 0.85) }
	end
	b:add({
		name = "Energy Beam",
		type = "beam",
		phase = "impact",
		start = start,
		duration = dur,
		position = c.center,
		properties = {
			from = { 0, 0, 0 },
			to = { 0, 30 * S, 0 },
			width0 = 2.4 * S,
			width1 = 1.2 * S,
			color = { C(0, "$core"), C(1, "$mid") },
			transparency = { { 0, 0.1 }, { 1, 0.6 } },
			lightEmission = 1,
			brightness = 2,
		},
		tracks = { { channel = "scale", keys = keys } },
	})
end

-- Curved slash ribbon (two beams: saturated arc + white core).
function Layers.slash(b: Builder, c: Ctx)
	local S = c.S
	local aLen = c.lens.action
	local dur = aLen + 0.18 * c.T
	local keys = { K(0, 0.2, "Quint.Out"), K(aLen, 1, "Quad.In"), K(dur, 0) }
	local base = {
		from = { -3.2 * S, 0, -1.2 * S },
		to = { 3.2 * S, 0, -1.2 * S },
		curveDirection = { 0, 0, -1 },
		curveSize0 = 2.4 * S,
		curveSize1 = 2.4 * S,
		segments = 24,
		lightEmission = 1,
	}
	local arc = table.clone(base)
	arc.width0 = 1.4 * S
	arc.width1 = 0.15 * S
	arc.color = { C(0, "$mid"), C(0.5, "$core"), C(1, "$mid") }
	arc.transparency = { { 0, 0.6 }, { 0.5, 0 }, { 1, 0.6 } }
	arc.brightness = 2
	b:add({
		name = "Slash Arc",
		type = "beam",
		phase = "action",
		start = c.times.action,
		duration = dur,
		position = c.center,
		rotation = { 0, 0, c.tilt },
		properties = arc,
		tracks = { { channel = "scale", keys = keys } },
		notes = "Action: the slash opens with Quint.Out and thins out with Quad.In; bent forward by curveSize.",
	})
	local core = table.clone(base)
	core.width0 = 0.45 * S
	core.width1 = 0.05 * S
	core.color = "$core"
	core.transparency = { { 0, 0.4 }, { 0.5, 0 }, { 1, 0.4 } }
	core.brightness = 3
	b:add({
		name = "Slash Core",
		type = "beam",
		phase = "action",
		start = c.times.action,
		duration = dur,
		position = c.center,
		rotation = { 0, 0, c.tilt },
		properties = core,
		tracks = { { channel = "scale", keys = keys } },
	})
end

-- A trail on a spinning pivot sweeps the swing (~200°).
function Layers.swing(b: Builder, c: Ctx)
	local S = c.S
	local dur = c.lens.action + 0.08 * c.T
	local pivot = b:add({
		name = "Swing Pivot",
		type = "group",
		phase = "action",
		start = c.times.action,
		duration = dur,
		position = c.center,
		rotation = { 0, 100, c.tilt },
		properties = { spin = { 0, -200 / dur, 0 } },
	})
	b:add({
		name = "Swing Trail",
		type = "trail",
		phase = "action",
		parent = pivot,
		start = c.times.action,
		duration = dur,
		position = { 0, 0, -3 * S },
		properties = {
			width = 1.2 * S,
			widthDirection = { 0, 1, 0 },
			lifetime = 0.2,
			color = { C(0, "$core"), C(1, "$mid") },
			transparency = { { 0, 0.1 }, { 1, 1 } },
			widthScale = { { 0, 1 }, { 1, 0.2 } },
			lightEmission = 1,
			brightness = 2,
		},
		notes = "Action: the trail draws the swing while its pivot spins.",
	})
end

-- A meteor falls along a curve (Quad.In = accelerating) into the target.
function Layers.meteor(b: Builder, c: Ctx)
	local S = c.S
	local aLen = math.max(c.lens.action, 0.1)
	local start = c.times.action
	local from = { (-14 + c.rng:range(-3, 3)) * S, 48 * S, (-10 + c.rng:range(-3, 3)) * S }
	local to = { c.target[1], c.ground + c.A.coreHeight * S * 0.6, c.target[3] }
	local group = b:add({
		name = "Meteor",
		type = "group",
		phase = "action",
		start = start,
		duration = aLen,
		position = from,
		properties = {},
		tracks = { { channel = "position", keys = { K(0, from, "Quad.In"), K(aLen, to) } } },
		notes = "Action: falls with Quad.In; children (core, trail, flames) follow it.",
	})
	b:add({
		name = "Meteor Core",
		type = "sphere",
		phase = "action",
		parent = group,
		start = start,
		duration = aLen,
		properties = {
			radius = 1.4 * S,
			coreColor = "$core",
			shellColor = "$mid",
			shellMaterial = c.E.shellMaterial,
			shellScale = 1.4,
			shellTransparency = 0.2,
			pulseAmplitude = 0.06,
			pulseFrequency = 10,
			light = true,
			lightBrightness = 3,
			lightRange = clamp(14 * S, 4, 60),
		},
		overrides = { Low = { light = false } },
	})
	b:add({
		name = "Meteor Trail",
		type = "trail",
		phase = "action",
		parent = group,
		start = start,
		duration = aLen,
		properties = {
			width = 2.4 * S,
			widthDirection = { 1, 0, 0 },
			lifetime = 0.35,
			color = { C(0, "$core"), C(0.4, "$mid"), C(1, "$edge") },
			transparency = { { 0, 0 }, { 1, 1 } },
			widthScale = { { 0, 1 }, { 1, 0 } },
			lightEmission = 1,
			brightness = 2,
			faceCamera = true,
		},
	})
	b:add({
		name = "Meteor Flames",
		type = "particles",
		phase = "action",
		parent = group,
		start = start,
		duration = aLen,
		properties = {
			texture = c.E.flame,
			rate = 60 * c.N,
			lifetime = { 0.25, 0.45 },
			speed = { 2 * S, 4 * S },
			spreadAngle = { 25, 25 },
			size = { { 0, 1.8 * S }, { 1, 0.2 * S } },
			color = { C(0, "$core"), C(0.4, "$mid"), C(1, "$edge") },
			transparency = { { 0, 0.1 }, { 1, 1 } },
			rotation = { 0, 360 },
			lightEmission = 1,
		},
	})
end

-- Looping aura: rising particles, a pulsing ground ring and a soft light.
function Layers.auraBody(b: Builder, c: Ctx)
	local S = c.S
	local D = c.D
	local isFire = c.element == "fire"
	b:add({
		name = if isFire then "Aura Flames" else "Aura Particles",
		type = "particles",
		phase = "action",
		start = 0,
		duration = D,
		position = { 0, c.ground + 0.15, 0 },
		properties = {
			texture = c.E.flame,
			shape = "Box",
			emitterSize = { 3 * S, 0.3, 3 * S },
			emissionDirection = "Top",
			spreadAngle = { 10, 10 },
			speed = { 3 * S, 6 * S },
			acceleration = { 0, 4 * S, 0 },
			lifetime = { 0.6, 1.0 },
			rate = 36 * c.N,
			size = { { 0, 0.9 * S }, { 0.5, 0.6 * S }, { 1, 0 } },
			transparency = { { 0, 0.3 }, { 0.2, 0 }, { 1, 1 } },
			color = { C(0, "$core"), C(0.5, "$mid"), C(1, "$edge") },
			rotation = { 0, 360 },
			rotSpeed = { -60, 60 },
			lightEmission = 1,
		},
		notes = "Loop: particles rise around the body for the whole cycle.",
	})
	b:add({
		name = "Ground Ring",
		type = "ring",
		phase = "action",
		start = 0,
		duration = D,
		position = { 0, c.ground + 0.03, 0 },
		properties = {
			style = "ring",
			segments = 32,
			radius = 2.6 * S,
			thickness = 0.14 * S,
			height = 0.05,
			color = "$mid",
			material = "Neon",
			transparency = 0.45,
		},
		tracks = {
			{
				channel = "transparency",
				keys = { K(0, 0.45, "Sine.InOut"), K(D / 2, 0.1, "Sine.InOut"), K(D, 0.45) },
			},
		},
		notes = "Loop: the ring breathes (Sine.InOut, seamless: same value at 0 and at the cycle end).",
	})
	b:add({
		name = "Aura Light",
		type = "light",
		phase = "action",
		start = 0,
		duration = D,
		position = { 0, c.ground + 2 * S, 0 },
		properties = { color = "$mid", brightness = 1.2, range = clamp(12 * S, 4, 60) },
		tracks = {
			{ channel = "brightness", keys = { K(0, 1.2, "Sine.InOut"), K(D / 2, 2.2, "Sine.InOut"), K(D, 1.2) } },
		},
	})
end

-- Looping magic circle: a spinning pivot with rings, a rune star and spokes, plus a glow light.
function Layers.circle(b: Builder, c: Ctx)
	local S = c.S
	local D = c.D
	local pivot = b:add({
		name = "Circle Pivot",
		type = "group",
		phase = "action",
		start = 0,
		duration = D,
		position = { 0, c.ground + 0.04, 0 },
		properties = { spin = { 0, 24, 0 } },
		notes = "Loop: everything below spins slowly with this pivot.",
	})
	local pulse = { K(0, 0.25, "Sine.InOut"), K(D / 2, 0.05, "Sine.InOut"), K(D, 0.25) }
	b:add({
		name = "Outer Ring",
		type = "ring",
		phase = "action",
		parent = pivot,
		start = 0,
		duration = D,
		properties = {
			style = "ring",
			segments = 40,
			radius = 6 * S,
			thickness = 0.28 * S,
			height = 0.08,
			color = "$mid",
			material = "Neon",
			transparency = 0.25,
		},
		tracks = { { channel = "transparency", keys = pulse } },
	})
	b:add({
		name = "Inner Ring",
		type = "ring",
		phase = "action",
		parent = pivot,
		start = 0,
		duration = D,
		properties = {
			style = "ring",
			segments = 32,
			radius = 4.7 * S,
			thickness = 0.16 * S,
			height = 0.06,
			color = "$mid",
			material = "Neon",
			transparency = 0.2,
		},
		minQuality = "Medium",
	})
	b:add({
		name = "Rune Star",
		type = "ring",
		phase = "action",
		parent = pivot,
		start = 0,
		duration = D,
		properties = {
			style = "star",
			points = 6,
			starStep = 2,
			radius = 4.5 * S,
			thickness = 0.16 * S,
			height = 0.06,
			color = "$core",
			material = "Neon",
			spin = { 0, -48, 0 },
		},
	})
	b:add({
		name = "Rune Marks",
		type = "ring",
		phase = "action",
		parent = pivot,
		start = 0,
		duration = D,
		properties = {
			style = "spokes",
			points = 12,
			innerRadius = 4.9 * S,
			radius = 5.7 * S,
			thickness = 0.12 * S,
			height = 0.06,
			color = "$mid",
			material = "Neon",
		},
		minQuality = "Medium",
	})
	b:add({
		name = "Circle Glow",
		type = "light",
		phase = "action",
		start = 0,
		duration = D,
		position = { 0, c.ground + 1.5, 0 },
		properties = { color = "$mid", brightness = 1.5, range = clamp(14 * S, 4, 60) },
		tracks = {
			{ channel = "brightness", keys = { K(0, 1.5, "Sine.InOut"), K(D / 2, 2.5, "Sine.InOut"), K(D, 1.5) } },
		},
	})
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Impact
-- ─────────────────────────────────────────────────────────────────────────────

-- Impact flash: 0.03 s attack, 0.02 s hold, 0.2–0.35 s decay (a 2–3 frame peak).
function Layers.flash(b: Builder, c: Ctx)
	local S = c.S
	local decay = clamp(0.25 * c.T, 0.2, 0.35)
	local size = c.A.flashSize * S * (if c.bright then 1.2 else 1)
	local start = if c.loop then c.D / 2 else c.times.impact
	b:add({
		name = if c.archetype == "teleport" then "Teleport Flash" else "Impact Flash",
		type = "flash",
		phase = "impact",
		start = start,
		duration = 0.03 + 0.02 + decay + 0.02,
		position = c.target,
		properties = {
			color = "$core",
			size = size,
			startSize = 0.3 * size,
			attack = 0.03,
			hold = 0.02,
			decay = decay,
			peakBrightness = if c.bright then 14 else 10,
			range = clamp(18 * S, 8, 60),
			light = true,
		},
		notes = string.format(
			"Impact: 0.03 s attack, 0.02 s hold, %.2f s decay; the brightest value sits on the impact marker.",
			decay
		),
	})
end

-- Expanding shockwave: 0.4–0.8 s, Quart.Out expansion, Quad.In fade.
function Layers.shockwave(b: Builder, c: Ctx)
	local S = c.S
	local dur = clamp(0.55 * c.T, 0.4, 0.8)
	local position = if c.A.grounded then { c.target[1], c.ground + 0.1, c.target[3] } else c.target
	b:add({
		name = "Shockwave",
		type = "shockwave",
		phase = "impact",
		start = c.times.impact,
		duration = dur,
		position = position,
		rotation = if c.archetype == "beam" then { 90, 0, 0 } else nil,
		properties = {
			startRadius = 0.6 * S,
			endRadius = c.A.shockRadius * S,
			height = 0.35 * S,
			color = "$mid",
			material = c.E.shockMaterial,
			startTransparency = 0.15,
			expandEasing = "Quart.Out",
			fadeEasing = "Quad.In",
			layers = if c.I >= 1.4 then 2 else 1,
			layerDelay = 0.06,
		},
		notes = string.format("Impact: expands over %.2f s with Quart.Out and fades with Quad.In.", dur),
	})
end

-- Looping pulse wave in the middle of the cycle.
function Layers.pulse(b: Builder, c: Ctx)
	local S = c.S
	local dur = math.min(clamp(0.5 * c.T, 0.4, 0.8), c.D / 2)
	b:add({
		name = "Pulse Wave",
		type = "shockwave",
		phase = "impact",
		start = c.D / 2,
		duration = dur,
		position = { 0, c.ground + 0.08, 0 },
		properties = {
			startRadius = S,
			endRadius = c.A.shockRadius * S,
			height = 0.15 * S,
			color = "$mid",
			material = "Neon",
			startTransparency = 0.4,
			expandEasing = "Quart.Out",
			fadeEasing = "Quad.In",
			layers = 1,
		},
		notes = "Loop: one pulse per cycle at the Impact marker.",
	})
end

-- Spark burst: small, additive, stretched along the velocity, short-lived.
function Layers.sparks(b: Builder, c: Ctx)
	local S = c.S
	local life = clamp(c.T, 0.8, 1.3)
	local props: { [string]: any } = {
		texture = c.E.spark,
		rate = 0,
		burst = math.floor(42 * c.N + 0.5),
		lifetime = { 0.25 * life, 0.6 * life },
		speed = { 28 * S, 55 * S },
		drag = 4,
		spreadAngle = { 180, 180 },
		acceleration = { 0, c.E.sparkGravity * S, 0 },
		size = { { 0, 0.32 * S }, { 1, 0 } },
		squash = { { 0, -1 }, { 1, -0.5 } },
		orientation = "VelocityParallel",
		color = { C(0, "$core"), C(0.35, "$mid"), C(1, "$edge") },
		transparency = { { 0, 0 }, { 0.75, 0.15 }, { 1, 1 } },
		lightEmission = 1,
	}
	local start, dur = c.times.impact, 0.12
	if c.archetype == "slash" then
		props.emissionDirection = "Front"
		props.spreadAngle = { 40, 40 }
	elseif c.archetype == "beam" then
		-- The beam keeps hitting: a continuous stream while it sustains.
		props.burst = math.floor(20 * c.N + 0.5)
		props.rate = 40 * c.N
		dur = math.max(c.lens.secondary, 0.12)
	end
	b:add({
		name = "Impact Sparks",
		type = "particles",
		phase = "impact",
		start = start,
		duration = dur,
		position = c.target,
		properties = props,
		notes = "Impact: one spark burst (additive, VelocityParallel + squash = stretched streaks).",
	})
end

-- Radial rays / spikes.
function Layers.rays(b: Builder, c: Ctx)
	local S = c.S
	local isIce = c.element == "ice"
	local start = if c.loop then c.D / 2 else c.times.impact
	b:add({
		name = if isIce then "Ice Spikes" elseif c.element == "holy" then "Light Rays" else "Impact Rays",
		type = "radialBurst",
		phase = "impact",
		start = start,
		duration = clamp(0.4 * c.T, 0.3, 0.55),
		position = c.target,
		properties = {
			count = math.floor(12 * math.min(c.N, 1.25) + 0.5),
			distribution = if c.A.grounded then "hemisphere" else "sphere",
			startRadius = 0.8 * S,
			endRadius = (if isIce then 6 else 10) * S,
			width = (if isIce then 0.5 else 0.28) * S,
			jitter = 0.3,
			color = if isIce then "$mid" else "$core",
			material = if isIce then "Ice" else "Neon",
		},
		notes = "Impact: radial lines sell the force of the hit.",
	})
end

function Layers.shake(b: Builder, c: Ctx)
	local dur = clamp(0.5 * c.T, 0.35, 0.9)
	local start = if c.loop then c.D / 2 else c.times.impact
	b:add({
		name = "Camera Shake",
		type = "cameraShake",
		phase = "impact",
		start = start,
		duration = dur,
		position = c.target,
		properties = {
			amplitude = math.min(0.35 + 0.45 * c.I, 1.6),
			positionAmplitude = math.min(0.12 * c.S, 0.4),
			frequency = 16,
			attack = 0.02,
			decay = dur - 0.05,
			innerRadius = 25 * c.S,
			outerRadius = 140 * c.S,
		},
		notes = "Impact: short camera shake with distance falloff (clients only).",
	})
end

function Layers.screen(b: Builder, c: Ctx)
	local start = if c.loop then c.D / 2 else c.times.impact
	b:add({
		name = "Impact Frame",
		type = "screenFlash",
		phase = "impact",
		start = start,
		duration = 0.26,
		properties = {
			brightness = 0.22,
			contrast = 0.45,
			saturation = -0.35,
			tint = "$core",
			attack = 0.02,
			hold = 0.03,
			decay = 0.18,
		},
		minQuality = "Medium",
		notes = "Impact: a subtle full-screen impact frame (Medium+, clients only).",
	})
end

-- Fire: a burst of flame sprites (rising) on the impact.
function Layers.flameBurst(b: Builder, c: Ctx)
	local S = c.S
	b:add({
		name = "Flame Burst",
		type = "particles",
		phase = "impact",
		start = c.times.impact,
		duration = 0.12,
		position = c.target,
		properties = {
			texture = c.E.flame,
			rate = 0,
			burst = math.floor(18 * c.N + 0.5),
			lifetime = { 0.45, 0.8 },
			speed = { 8 * S, 18 * S },
			drag = 3,
			spreadAngle = { 180, 180 },
			acceleration = { 0, 10 * S, 0 },
			size = { { 0, 2.2 * S }, { 0.4, 2.6 * S }, { 1, 0.6 * S } },
			transparency = { { 0, 0.1 }, { 0.6, 0.3 }, { 1, 1 } },
			color = { C(0, "$core"), C(0.3, "$mid"), C(1, "$edge") },
			rotation = { 0, 360 },
			rotSpeed = { -90, 90 },
			lightEmission = 0.8,
		},
		notes = "Impact: flame body of the blast; rises while it burns out.",
	})
end

-- Water: droplets thrown up and falling back.
function Layers.splash(b: Builder, c: Ctx)
	local S = c.S
	b:add({
		name = "Water Splash",
		type = "particles",
		phase = "impact",
		start = c.times.impact,
		duration = 0.12,
		position = c.target,
		properties = {
			texture = c.E.spark,
			rate = 0,
			burst = math.floor(30 * c.N + 0.5),
			lifetime = { 0.5, 0.9 },
			speed = { 18 * S, 32 * S },
			emissionDirection = "Top",
			spreadAngle = { 35, 35 },
			acceleration = { 0, -60 * S, 0 },
			size = { { 0, 0.45 * S }, { 1, 0.15 * S } },
			color = { C(0, "$core"), C(1, "$mid") },
			transparency = { { 0, 0.1 }, { 1, 1 } },
			lightEmission = 0.3,
		},
	})
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Secondary
-- ─────────────────────────────────────────────────────────────────────────────

-- Lingering secondary particles (embers, static sparks, glitter, ...).
function Layers.embers(b: Builder, c: Ctx)
	local S = c.S
	local start, dur = postImpact(c, 0.04 * c.T, math.max(c.lens.secondary, 0.3))
	b:add({
		name = c.E.emberName,
		type = "particles",
		phase = "secondary",
		start = start,
		duration = dur,
		position = c.target,
		properties = {
			texture = c.E.spark,
			shape = "Sphere",
			emitterSize = { 3 * S, 3 * S, 3 * S },
			rate = 28 * c.N,
			lifetime = { 0.6, 1.1 },
			speed = { 3 * S, 9 * S },
			spreadAngle = { 180, 180 },
			drag = 1.5,
			acceleration = { 0, c.E.emberRise * S, 0 },
			size = { { 0, 0.22 * S }, { 1, 0 } },
			color = { C(0, "$core"), C(1, "$mid") },
			transparency = { { 0, 0 }, { 0.8, 0.3 }, { 1, 1 } },
			lightEmission = 1,
		},
		tracks = { { channel = "rate", keys = { K(0, 28 * c.N, "Quad.Out"), K(dur, 0) } } },
		notes = "Secondary: slower particles linger after the hit; the rate ramps down (Quad.Out).",
	})
end

-- Kinematic debris thrown out of the impact.
function Layers.debris(b: Builder, c: Ctx)
	if c.loop then
		return
	end
	local S = c.S
	local onGround = c.A.grounded
	b:add({
		name = c.E.debrisName,
		type = "debris",
		phase = "secondary",
		start = c.times.impact,
		duration = math.max(0.9, 1.2 * c.T),
		position = if onGround then { c.target[1], c.ground, c.target[3] } else c.target,
		properties = {
			count = math.floor(12 * c.N + 0.5),
			shape = c.E.debrisShape,
			size = { 0.3 * S, 0.8 * S },
			speed = { 20 * S, 38 * S },
			spreadAngle = if onGround then 55 else 90,
			gravity = { 0, (if onGround then -90 else -60) * S, 0 },
			drag = 0.5,
			color = c.E.debrisColor,
			colorVariance = 0.15,
			material = c.E.debrisMaterial,
			fadeTime = 0.35,
			floor = onGround,
			floorHeight = 0,
		},
		notes = "Secondary: deterministic ballistic fragments (no physics); they land and fade.",
	})
end

-- Explosion debris only for elements that throw any (fire, earth, ice, neutral).
function Layers.elementDebris(b: Builder, c: Ctx)
	if c.E.debris or c.explicit.debris then
		Layers.debris(b, c)
	end
end

-- Lightning strike: small ground arcs after the bolt.
function Layers.residualArcs(b: Builder, c: Ctx)
	local S = c.S
	local boltEnd = c.times.action + c.lens.action + clamp(0.4 * c.T, 0.3, 0.55)
	local start = if c.loop then 0 else boltEnd
	local dur = if c.loop then c.D else clamp(0.45 * c.T, 0.3, 0.6)
	local count = if c.explicit.arcs then 2 else 1
	for i = 1, count do
		local dir = direction((i - 1) * math.pi + c.rng:range(-0.8, 0.8), 0)
		b:add({
			name = "Ground Arc " .. i,
			type = "lightning",
			phase = "secondary",
			start = start,
			duration = dur,
			position = { c.target[1], c.ground + 0.2, c.target[3] },
			properties = {
				from = { 0, 0, 0 },
				to = scaled(dir, 5 * S),
				segments = 6,
				jitter = 0.7 * S,
				branches = 0,
				flickerRate = 30,
				thickness = 0.15 * S,
				color = "$mid",
				brightness = 3,
				lightEmission = 1,
			},
			tracks = if c.loop then nil else { fadeTrack(dur, 0.5) },
			minQuality = if i == 1 then "Medium" else "High",
			notes = if i == 1 then "Secondary: residual charge crackles over the ground." else nil,
		})
	end
end

-- Trails on a spinning pivot (swirl / orbit).
function Layers.orbit(b: Builder, c: Ctx)
	local S = c.S
	local start, dur = postImpact(c, 0, math.max(c.lens.secondary, 0.4))
	local height = if c.loop then c.ground + 1 * S else c.target[2] + 0.5 * S
	local tracks: { TrackSpec }? = nil
	if not c.loop and c.element == "wind" then
		tracks = {
			{
				channel = "position",
				keys = {
					K(0, { c.target[1], height, c.target[3] }, "Quad.Out"),
					K(dur, { c.target[1], height + 3 * S, c.target[3] }),
				},
			},
		}
	end
	local pivot = b:add({
		name = "Swirl Pivot",
		type = "group",
		phase = "secondary",
		start = start,
		duration = dur,
		position = { c.target[1], height, c.target[3] },
		properties = { spin = { 0, (if c.loop then 240 else 400) / c.T, 0 } },
		tracks = tracks,
	})
	for i = 1, 2 do
		b:add({
			name = "Swirl Trail " .. i,
			type = "trail",
			phase = "secondary",
			parent = pivot,
			start = start,
			duration = dur,
			position = { (if i == 1 then 2.6 else -2.6) * S, (i - 1) * 0.6 * S, 0 },
			properties = {
				width = 0.5 * S,
				widthDirection = { 0, 1, 0 },
				lifetime = 0.35,
				color = { C(0, "$core"), C(1, "$mid") },
				transparency = { { 0, 0.2 }, { 1, 1 } },
				widthScale = { { 0, 1 }, { 1, 0 } },
				lightEmission = 1,
			},
			minQuality = if i == 2 then "Medium" else nil,
			notes = if i == 1 then "Secondary: trails circle the centre on a spinning pivot." else nil,
		})
	end
end

-- Slowly rising motes (loops, teleport afterglow).
function Layers.motes(b: Builder, c: Ctx)
	local S = c.S
	local start, dur = postImpact(c, 0.05, math.max(c.lens.secondary, 0.4))
	local width = (if c.archetype == "magicCircle" then 9 else 4) * S
	b:add({
		name = "Rising Motes",
		type = "particles",
		phase = "secondary",
		start = start,
		duration = dur,
		position = { c.target[1], c.ground + 0.2, c.target[3] },
		properties = {
			texture = c.E.spark,
			shape = "Box",
			emitterSize = { width, 0.2, width },
			emissionDirection = "Top",
			speed = { 1.5 * S, 3.5 * S },
			lifetime = { 1.0, 1.6 },
			rate = 12 * c.N,
			size = { { 0, 0 }, { 0.3, 0.3 * S }, { 1, 0 } },
			color = "$core",
			lightEmission = 1,
		},
	})
end

-- Poison: bubbles rising out of the hit area.
function Layers.bubbles(b: Builder, c: Ctx)
	local S = c.S
	local start, dur = postImpact(c, 0.05, math.max(c.lens.secondary, 0.4))
	b:add({
		name = "Toxic Bubbles",
		type = "particles",
		phase = "secondary",
		start = start,
		duration = dur,
		position = c.target,
		properties = {
			texture = TX.glow,
			shape = "Sphere",
			emitterSize = { 3 * S, S, 3 * S },
			rate = 14 * c.N,
			lifetime = { 0.8, 1.4 },
			speed = { S, 3 * S },
			acceleration = { 0, 2 * S, 0 },
			size = { { 0, 0.2 * S }, { 0.8, 0.45 * S }, { 1, 0.6 * S } },
			transparency = { { 0, 0.2 }, { 0.85, 0.3 }, { 1, 1 } },
			color = "$mid",
			lightEmission = 0.5,
		},
	})
end

-- Nature: tumbling leaves.
function Layers.leaves(b: Builder, c: Ctx)
	local S = c.S
	local start, dur = postImpact(c, 0, 0.12)
	local props: { [string]: any } = {
		texture = TX.square,
		rate = 0,
		burst = math.floor(16 * c.N + 0.5),
		lifetime = { 1.0, 1.6 },
		speed = { 8 * S, 16 * S },
		emissionDirection = "Top",
		spreadAngle = { 70, 70 },
		acceleration = { 0, -8 * S, 0 },
		drag = 2.5,
		rotation = { 0, 360 },
		rotSpeed = { -240, 240 },
		size = { { 0, 0.35 * S }, { 1, 0.25 * S } },
		color = { C(0, "$mid"), C(1, "$edge") },
		transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } },
		lightInfluence = 0.5,
	}
	if c.loop then
		props.burst = 0
		props.rate = 6 * c.N
		props.speed = { 2 * S, 4 * S }
	end
	b:add({
		name = "Leaves",
		type = "particles",
		phase = "secondary",
		start = start,
		duration = dur,
		position = c.target,
		properties = props,
	})
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Dissipation
-- ─────────────────────────────────────────────────────────────────────────────

type DissipationStyle = {
	texture: string,
	color: any,
	rise: number,
	size: { number },
	transparency: number,
	lightEmission: number,
	lightInfluence: number,
	rate: number,
	speed: { number },
	spread: number,
	fadeScale: number,
	sparkle: boolean,
}

local function dissipationStyle(c: Ctx): (DissipationStyle, string)
	local style = if c.forceSmoke then "smoke" else c.E.dissipation
	local E = c.E
	local name = if c.forceSmoke and E.dissipation ~= "smoke" then "Smoke" else E.dissipationName
	local base: DissipationStyle = {
		texture = E.smokeTexture,
		color = "$smoke",
		rise = 3,
		size = { 1.6, 5.5 },
		transparency = 0.55,
		lightEmission = 0,
		lightInfluence = 1,
		rate = 22,
		speed = { 3, 7 },
		spread = 70,
		fadeScale = 1.4,
		sparkle = false,
	}
	if style == "dust" then
		base.rise = 1
		base.size = { 2, 6 }
		base.speed = { 6, 12 }
		base.spread = 85
	elseif style == "mist" then
		base.rise = 0.5
		base.transparency = 0.6
		base.lightEmission = 0.2
		base.lightInfluence = 0.5
		base.rate = 18
	elseif style == "cloud" then
		base.color = { C(0, "$mid"), C(1, "$smoke") }
		base.rise = 1
		base.size = { 2, 6.5 }
		base.transparency = 0.5
		base.lightEmission = 0.3
		base.lightInfluence = 0.6
		base.fadeScale = 1.8
	elseif style == "shadow" then
		base.rise = 0.5
		base.transparency = 0.4
		base.lightInfluence = 0.4
	elseif style == "motes" then
		base.texture = E.spark
		base.color = { C(0, "$core"), C(1, "$mid") }
		base.rise = 1
		base.size = { 0.25, 0 }
		base.transparency = 0
		base.lightEmission = 1
		base.lightInfluence = 0
		base.rate = 18
		base.speed = { 1, 3 }
		base.spread = 180
		base.sparkle = true
	end
	return base, name
end

-- Dissipation: the slowest layer, 1–2 s fade (smoke, dust, mist, cloud or fading motes by element).
function Layers.dissipation(b: Builder, c: Ctx)
	local S = c.S
	local style, name = dissipationStyle(c)
	local fade = clamp(style.fadeScale * c.T, 1, 2)
	local start, dur = postImpact(c, 0.06 * c.T, math.max(0.6 * c.lens.dissipation, 0.3))
	local rate = style.rate * c.N
	local position = if c.A.grounded then { c.target[1], c.ground + 0.5 * S, c.target[3] } else c.target
	local props: { [string]: any } = {
		texture = style.texture,
		shape = "Sphere",
		emitterSize = { 3 * S, 1.5 * S, 3 * S },
		rate = rate,
		lifetime = { 0.75 * fade, fade },
		speed = { style.speed[1] * S, style.speed[2] * S },
		emissionDirection = "Top",
		spreadAngle = { style.spread, style.spread },
		drag = 1.5,
		acceleration = { 0, style.rise * S, 0 },
		size = { { 0, style.size[1] * S }, { 1, style.size[2] * S } },
		color = style.color,
		lightEmission = style.lightEmission,
		lightInfluence = style.lightInfluence,
	}
	if style.sparkle then
		props.transparency = { { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } }
	else
		props.transparency = { { 0, style.transparency }, { 0.25, style.transparency * 0.65 }, { 1, 1 } }
		props.rotation = { 0, 360 }
		props.rotSpeed = { -30, 30 }
	end
	b:add({
		name = name,
		type = "particles",
		phase = "dissipation",
		start = start,
		duration = dur,
		position = position,
		properties = props,
		tracks = if c.loop then nil else { { channel = "rate", keys = { K(0, rate, "Quad.Out"), K(dur, 0) } } },
		notes = string.format("Dissipation: lingers longest and fades over %.1f s (particle lifetime).", fade),
	})
end

return Layers
