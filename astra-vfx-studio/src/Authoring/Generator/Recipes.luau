--!strict
--[[
	Recipes — design data of Authoring/Generator: element profiles, colour hues, archetype templates and the
	built-in textures (docs/COMPONENTS_SPEC.md §16, docs/research/vfx-design-performance.md §2.4, §2.7, §4.5).

	  Recipes.ELEMENTS[element]     ElementProfile (palette, textures, motion traits, layer names)
	  Recipes.ELEMENT_ORDER         element keys in a fixed order (docs, tests)
	  Recipes.COLORS[colour]        { hue, saturation?, value? } for colour words; white / black are special
	  Recipes.ARCHETYPES[archetype] ArchetypeTemplate (phase lengths, default layers, sizes)
	  Recipes.ARCHETYPE_ORDER       archetype keys in a fixed order
	  Recipes.TEXTURES              the built-in texture paths the generator uses (all from §16)
	  Recipes.palette(element, colour?, shade?) -> { core, mid, edge, smoke }   "#RRGGBB" strings
	  Recipes.hsv(h, s, v) -> "#RRGGBB"

	Palette convention (research A13–A16, R9): `core` is the bright, nearly white focus colour (never pure white),
	`mid` the saturated identity colour, `edge` the dark end colour (additive particles fade into it), `smoke` the
	dissipation colour (dark smoke, light mist or a tinted haze). Components reference them as "$core", "$mid",
	"$edge", "$smoke", so a game can recolour a generated effect with Play({ Palette = ... }).

	Archetype phase lengths are base seconds before the speed / intensity time factor T (Composer): anticipation,
	charge (only used when a charge is requested, or `chargeDefault`), action (until the impact moment),
	secondary and dissipation (after the impact). Looping archetypes use `loopDuration` instead.
	Layer kinds are resolved by Composer / Layers; a trailing "?" marks an optional layer (minQuality = Medium).
]]

local Recipes = {}

export type ElementProfile = {
	label: string, -- name word ("Lightning")
	palette: { core: string, mid: string, edge: string, smoke: string },
	spark: string, -- texture of sparks / motes
	glow: string, -- texture of soft glow particles
	flame: string, -- texture of flame-like body particles
	smokeTexture: string,
	sparkGravity: number, -- spark acceleration Y (studs/s², × size scale)
	emberRise: number, -- secondary particle acceleration Y
	dissipation: string, -- "smoke" | "dust" | "mist" | "cloud" | "shadow" | "motes"
	dissipationName: string,
	emberName: string,
	coreName: string,
	debris: boolean, -- explosions throw debris by default
	debrisName: string,
	debrisMaterial: string,
	debrisColor: string, -- "$edge" or "#RRGGBB"
	debrisShape: string,
	shockMaterial: string,
	shellMaterial: string,
	extras: { [string]: { string } }, -- archetype -> extra layer kinds ("*" = every burst archetype)
}

export type ArchetypeTemplate = {
	label: string, -- name noun ("Explosion")
	loop: boolean,
	loopDuration: number?,
	grounded: boolean, -- impact layers sit on the ground (y ≈ 0) instead of at the hit point
	burst: boolean, -- receives the element's "*" extras
	anticipation: number,
	charge: number, -- used when a charge is requested
	chargeDefault: boolean, -- the template always has a charge phase
	action: number,
	secondary: number,
	dissipation: number,
	coreHeight: number, -- y of the visual centre (× size scale)
	flashSize: number, -- impact flash diameter (× size scale)
	shockRadius: number, -- shockwave end radius (× size scale)
	coreRadius: number, -- core burst end radius (× size scale)
	layers: { string },
}

local P = "rbxasset://textures/particles/"

-- Built-in textures (docs/COMPONENTS_SPEC.md §16: present in the Studio 0.745 client manifest).
Recipes.TEXTURES = {
	sparkles = P .. "sparkles_main.dds",
	fireSparks = P .. "fire_sparks_main.dds",
	fire = P .. "fire_main.dds",
	smoke = P .. "smoke_main.dds",
	explosionSmoke = P .. "explosion01_smoke_main.dds",
	glow = P .. "forcefield_glow_main.dds",
	vortex = P .. "forcefield_vortex_main.dds",
	square = P .. "SquareParticle.png",
}
local TX = Recipes.TEXTURES

-- "#RRGGBB" of an HSV colour (h, s, v in 0..1).
function Recipes.hsv(h: number, s: number, v: number): string
	h = (h % 1) * 6
	s = math.clamp(s, 0, 1)
	v = math.clamp(v, 0, 1)
	local i = math.floor(h)
	local f = h - i
	local p = v * (1 - s)
	local q = v * (1 - s * f)
	local t = v * (1 - s * (1 - f))
	local r, g, b
	if i == 0 then
		r, g, b = v, t, p
	elseif i == 1 then
		r, g, b = q, v, p
	elseif i == 2 then
		r, g, b = p, v, t
	elseif i == 3 then
		r, g, b = p, q, v
	elseif i == 4 then
		r, g, b = t, p, v
	else
		r, g, b = v, p, q
	end
	return string.format(
		"#%02X%02X%02X",
		math.floor(r * 255 + 0.5),
		math.floor(g * 255 + 0.5),
		math.floor(b * 255 + 0.5)
	)
end

local function element(profile: ElementProfile): ElementProfile
	return profile
end

Recipes.ELEMENTS = {
	neutral = element({
		label = "",
		palette = { core = "#FFF4DC", mid = "#FFB547", edge = "#7A3A12", smoke = "#3B3633" },
		spark = TX.sparkles,
		glow = TX.glow,
		flame = TX.glow,
		smokeTexture = TX.smoke,
		sparkGravity = -30,
		emberRise = -6,
		dissipation = "smoke",
		dissipationName = "Smoke",
		emberName = "Lingering Sparks",
		coreName = "Core Glow",
		debris = true,
		debrisName = "Debris",
		debrisMaterial = "Slate",
		debrisColor = "#5E544A",
		debrisShape = "Mixed",
		shockMaterial = "ForceField",
		shellMaterial = "ForceField",
		extras = {},
	}),
	fire = element({
		label = "Fire",
		palette = { core = "#FFF1C2", mid = "#FF7A1A", edge = "#8C1C04", smoke = "#3A3431" },
		spark = TX.fireSparks,
		glow = TX.fire,
		flame = TX.fire,
		smokeTexture = TX.smoke,
		sparkGravity = -25,
		emberRise = 6,
		dissipation = "smoke",
		dissipationName = "Smoke",
		emberName = "Embers",
		coreName = "Fireball",
		debris = true,
		debrisName = "Charred Debris",
		debrisMaterial = "Basalt",
		debrisColor = "#3A2A22",
		debrisShape = "Mixed",
		shockMaterial = "Neon",
		shellMaterial = "Neon",
		extras = { ["*"] = { "flameBurst" } },
	}),
	lightning = element({
		label = "Lightning",
		palette = { core = "#E8F6FF", mid = "#4FC3FF", edge = "#1B3FA8", smoke = "#2E3440" },
		spark = TX.sparkles,
		glow = TX.glow,
		flame = TX.glow,
		smokeTexture = TX.smoke,
		sparkGravity = -10,
		emberRise = 0,
		dissipation = "motes",
		dissipationName = "Static Motes",
		emberName = "Static Sparks",
		coreName = "Plasma Core",
		debris = false,
		debrisName = "Debris",
		debrisMaterial = "Slate",
		debrisColor = "#4A4E58",
		debrisShape = "Mixed",
		shockMaterial = "Neon",
		shellMaterial = "ForceField",
		extras = {
			impact = { "arcs" },
			explosion = { "arcs" },
			meteor = { "arcs" },
			strike = { "residualArcs" },
			beam = { "chargeArcs" },
			slash = { "arcs" },
		},
	}),
	ice = element({
		label = "Ice",
		palette = { core = "#F2FCFF", mid = "#8FDFFF", edge = "#2F6FB0", smoke = "#C9E4F2" },
		spark = TX.sparkles,
		glow = TX.glow,
		flame = TX.glow,
		smokeTexture = TX.smoke,
		sparkGravity = -35,
		emberRise = -4,
		dissipation = "mist",
		dissipationName = "Frost Mist",
		emberName = "Frost Glitter",
		coreName = "Frost Core",
		debris = true,
		debrisName = "Ice Shards",
		debrisMaterial = "Ice",
		debrisColor = "#BFEAFF",
		debrisShape = "Wedge",
		shockMaterial = "ForceField",
		shellMaterial = "ForceField",
		extras = { ["*"] = { "debris" }, explosion = { "rays?" }, strike = { "rays?" } },
	}),
	water = element({
		label = "Water",
		palette = { core = "#E6FBFF", mid = "#2EA8FF", edge = "#0B3D91", smoke = "#A9CFE6" },
		spark = TX.sparkles,
		glow = TX.glow,
		flame = TX.smoke,
		smokeTexture = TX.smoke,
		sparkGravity = -60,
		emberRise = -20,
		dissipation = "mist",
		dissipationName = "Spray Mist",
		emberName = "Droplets",
		coreName = "Water Core",
		debris = false,
		debrisName = "Debris",
		debrisMaterial = "Glass",
		debrisColor = "#7FC8FF",
		debrisShape = "Ball",
		shockMaterial = "Glass",
		shellMaterial = "Glass",
		extras = { ["*"] = { "splash" } },
	}),
	poison = element({
		label = "Poison",
		palette = { core = "#F0FFD0", mid = "#7CFF3A", edge = "#2E6B0A", smoke = "#3E5A2A" },
		spark = TX.sparkles,
		glow = TX.glow,
		flame = TX.explosionSmoke,
		smokeTexture = TX.explosionSmoke,
		sparkGravity = -30,
		emberRise = 2,
		dissipation = "cloud",
		dissipationName = "Toxic Cloud",
		emberName = "Toxic Droplets",
		coreName = "Toxic Core",
		debris = false,
		debrisName = "Debris",
		debrisMaterial = "Slate",
		debrisColor = "#3A4A2A",
		debrisShape = "Mixed",
		shockMaterial = "Neon",
		shellMaterial = "ForceField",
		extras = { ["*"] = { "bubbles" } },
	}),
	shadow = element({
		label = "Shadow",
		palette = { core = "#D9C2FF", mid = "#7A2CFF", edge = "#1A0633", smoke = "#120A1C" },
		spark = TX.sparkles,
		glow = TX.vortex,
		flame = TX.smoke,
		smokeTexture = TX.smoke,
		sparkGravity = -8,
		emberRise = 1,
		dissipation = "shadow",
		dissipationName = "Shadow Smoke",
		emberName = "Shadow Wisps",
		coreName = "Void Core",
		debris = false,
		debrisName = "Debris",
		debrisMaterial = "Basalt",
		debrisColor = "#1E1726",
		debrisShape = "Mixed",
		shockMaterial = "ForceField",
		shellMaterial = "ForceField",
		extras = { impact = { "gather" }, strike = { "gather" } },
	}),
	holy = element({
		label = "Holy",
		palette = { core = "#FFFBEA", mid = "#FFD54A", edge = "#B87A0A", smoke = "#F5E6B8" },
		spark = TX.sparkles,
		glow = TX.glow,
		flame = TX.glow,
		smokeTexture = TX.smoke,
		sparkGravity = -6,
		emberRise = 3,
		dissipation = "motes",
		dissipationName = "Fading Motes",
		emberName = "Holy Sparkles",
		coreName = "Radiant Core",
		debris = false,
		debrisName = "Debris",
		debrisMaterial = "Marble",
		debrisColor = "#E8DFC8",
		debrisShape = "Mixed",
		shockMaterial = "Neon",
		shellMaterial = "ForceField",
		extras = { ["*"] = { "rays" } },
	}),
	energy = element({
		label = "Arcane",
		palette = { core = "#F3E8FF", mid = "#B05CFF", edge = "#3D1580", smoke = "#2A1F3D" },
		spark = TX.sparkles,
		glow = TX.glow,
		flame = TX.glow,
		smokeTexture = TX.smoke,
		sparkGravity = -10,
		emberRise = 2,
		dissipation = "motes",
		dissipationName = "Fading Motes",
		emberName = "Arcane Sparkles",
		coreName = "Energy Core",
		debris = false,
		debrisName = "Debris",
		debrisMaterial = "Slate",
		debrisColor = "#3A2F4A",
		debrisShape = "Mixed",
		shockMaterial = "ForceField",
		shellMaterial = "ForceField",
		extras = { explosion = { "rays?" } },
	}),
	earth = element({
		label = "Earth",
		palette = { core = "#FFE7B8", mid = "#C98A4A", edge = "#5A3A1E", smoke = "#6B5A48" },
		spark = TX.sparkles,
		glow = TX.smoke,
		flame = TX.smoke,
		smokeTexture = TX.smoke,
		sparkGravity = -60,
		emberRise = -12,
		dissipation = "dust",
		dissipationName = "Dust Cloud",
		emberName = "Grit",
		coreName = "Earth Core",
		debris = true,
		debrisName = "Rock Debris",
		debrisMaterial = "Slate",
		debrisColor = "#5A4632",
		debrisShape = "Mixed",
		shockMaterial = "Sand",
		shellMaterial = "Sand",
		extras = { ["*"] = { "debris" }, slash = { "debris" } },
	}),
	wind = element({
		label = "Wind",
		palette = { core = "#F4FFFB", mid = "#A8F0DC", edge = "#4E8C7E", smoke = "#D6E6E1" },
		spark = TX.sparkles,
		glow = TX.smoke,
		flame = TX.smoke,
		smokeTexture = TX.smoke,
		sparkGravity = -4,
		emberRise = 2,
		dissipation = "dust",
		dissipationName = "Dust Swirl",
		emberName = "Wind Motes",
		coreName = "Wind Core",
		debris = false,
		debrisName = "Debris",
		debrisMaterial = "Slate",
		debrisColor = "#8C9690",
		debrisShape = "Mixed",
		shockMaterial = "ForceField",
		shellMaterial = "ForceField",
		extras = { ["*"] = { "orbit" } },
	}),
	nature = element({
		label = "Nature",
		palette = { core = "#F2FFE0", mid = "#5FD35A", edge = "#1F6B2A", smoke = "#7A8F55" },
		spark = TX.sparkles,
		glow = TX.glow,
		flame = TX.glow,
		smokeTexture = TX.smoke,
		sparkGravity = -12,
		emberRise = 1,
		dissipation = "motes",
		dissipationName = "Pollen Motes",
		emberName = "Pollen",
		coreName = "Life Core",
		debris = false,
		debrisName = "Debris",
		debrisMaterial = "Grass",
		debrisColor = "#3E7A2E",
		debrisShape = "Mixed",
		shockMaterial = "Neon",
		shellMaterial = "ForceField",
		extras = { ["*"] = { "leaves" }, aura = { "leaves" } },
	}),
} :: { [string]: ElementProfile }

Recipes.ELEMENT_ORDER = {
	"neutral",
	"fire",
	"lightning",
	"ice",
	"water",
	"poison",
	"shadow",
	"holy",
	"energy",
	"earth",
	"wind",
	"nature",
}

-- Colour words: hue (0..1) of the identity colour; white / black use fixed palettes.
Recipes.COLORS = {
	red = { hue = 0.0 },
	orange = { hue = 0.07 },
	gold = { hue = 0.12 },
	yellow = { hue = 0.15 },
	green = { hue = 0.33 },
	cyan = { hue = 0.5 },
	blue = { hue = 0.6 },
	purple = { hue = 0.77 },
	pink = { hue = 0.9 },
	white = { hue = 0.6 },
	black = { hue = 0.75 },
} :: { [string]: { hue: number } }

local WHITE = { core = "#FFFFFF", mid = "#E6EEFF", edge = "#8C96B4", smoke = "#C8CCD6" }
local BLACK = { core = "#B8B0C8", mid = "#3A2F4A", edge = "#0E0B12", smoke = "#141018" }

-- Palette of an element, recoloured by a colour word (hue) and a shade ("light" / "dark").
function Recipes.palette(
	elementKey: string,
	colour: string?,
	shade: string?
): { core: string, mid: string, edge: string, smoke: string }
	local profile = Recipes.ELEMENTS[elementKey] or Recipes.ELEMENTS.neutral
	local base = profile.palette
	local out = { core = base.core, mid = base.mid, edge = base.edge, smoke = base.smoke }
	if colour == "white" then
		out = table.clone(WHITE)
	elseif colour == "black" then
		out = table.clone(BLACK)
	elseif colour and Recipes.COLORS[colour] then
		local h = Recipes.COLORS[colour].hue
		out.core = Recipes.hsv(h, 0.12, 1)
		out.mid = Recipes.hsv(h, 0.85, 1)
		out.edge = Recipes.hsv(h, 0.9, 0.42)
		-- Light dissipation styles (mist, motes) keep a light tint, smoke stays dark.
		local light = profile.dissipation == "mist" or profile.dissipation == "motes"
		out.smoke = if light then Recipes.hsv(h, 0.2, 0.85) else Recipes.hsv(h, 0.25, 0.22)
	end
	local hue: number? = if colour
			and colour ~= "white"
			and colour ~= "black"
			and Recipes.COLORS[colour]
		then Recipes.COLORS[colour].hue
		else nil
	if hue and shade == "light" then
		out.mid = Recipes.hsv(hue, 0.55, 1)
		out.edge = Recipes.hsv(hue, 0.7, 0.6)
	elseif hue and shade == "dark" then
		out.core = Recipes.hsv(hue, 0.35, 0.95)
		out.mid = Recipes.hsv(hue, 0.95, 0.7)
		out.edge = Recipes.hsv(hue, 1, 0.25)
	end
	return out
end

local function archetype(template: ArchetypeTemplate): ArchetypeTemplate
	return template
end

Recipes.ARCHETYPES = {
	impact = archetype({
		label = "Impact",
		loop = false,
		grounded = false,
		burst = true,
		anticipation = 0.06,
		charge = 0.8,
		chargeDefault = false,
		action = 0.06,
		secondary = 0.6,
		dissipation = 1.0,
		coreHeight = 0,
		flashSize = 6,
		shockRadius = 8,
		coreRadius = 2,
		layers = { "glint", "coreBurst", "flash", "shockwave", "sparks", "embers?", "dissipation" },
	}),
	explosion = archetype({
		label = "Explosion",
		loop = false,
		grounded = true,
		burst = true,
		anticipation = 0.15,
		charge = 0.8,
		chargeDefault = false,
		action = 0.1,
		secondary = 0.8,
		dissipation = 1.4,
		coreHeight = 1.5,
		flashSize = 9,
		shockRadius = 13,
		coreRadius = 3.2,
		layers = {
			"gather",
			"coreBurst",
			"flash",
			"shockwave",
			"sparks",
			"shake",
			"elementDebris",
			"embers",
			"dissipation",
		},
	}),
	strike = archetype({
		label = "Strike",
		loop = false,
		grounded = true,
		burst = true,
		anticipation = 0.25,
		charge = 0.8,
		chargeDefault = false,
		action = 0.06,
		secondary = 0.6,
		dissipation = 1.0,
		coreHeight = 1,
		flashSize = 7,
		shockRadius = 10,
		coreRadius = 2,
		layers = { "telegraph", "strikeAction", "flash", "shockwave", "sparks", "shake", "embers?", "dissipation" },
	}),
	beam = archetype({
		label = "Beam",
		loop = false,
		grounded = false,
		burst = false,
		anticipation = 0.1,
		charge = 0.5,
		chargeDefault = true,
		action = 0.12,
		secondary = 0.7,
		dissipation = 0.8,
		coreHeight = 0,
		flashSize = 5,
		shockRadius = 5,
		coreRadius = 1.5,
		layers = {
			"glint",
			"chargeSphere",
			"chargeParticles",
			"beam",
			"flash",
			"sparks",
			"shockwave",
			"embers?",
			"dissipation",
		},
	}),
	slash = archetype({
		label = "Slash",
		loop = false,
		grounded = false,
		burst = false,
		anticipation = 0.05,
		charge = 0.6,
		chargeDefault = false,
		action = 0.14,
		secondary = 0.35,
		dissipation = 0.6,
		coreHeight = 0,
		flashSize = 4,
		shockRadius = 5,
		coreRadius = 1.2,
		layers = { "glint", "slash", "swing", "flash", "sparks", "embers?", "dissipation" },
	}),
	meteor = archetype({
		label = "Meteor",
		loop = false,
		grounded = true,
		burst = true,
		anticipation = 0.3,
		charge = 0.8,
		chargeDefault = false,
		action = 0.7,
		secondary = 0.8,
		dissipation = 1.6,
		coreHeight = 1,
		flashSize = 10,
		shockRadius = 16,
		coreRadius = 3.5,
		layers = {
			"telegraph",
			"meteor",
			"flash",
			"shockwave",
			"sparks",
			"shake",
			"debris",
			"embers",
			"dissipation",
		},
	}),
	teleport = archetype({
		label = "Teleport",
		loop = false,
		grounded = true,
		burst = false,
		anticipation = 0.25,
		charge = 0.5,
		chargeDefault = true,
		action = 0.25,
		secondary = 0.4,
		dissipation = 0.7,
		coreHeight = 1.5,
		flashSize = 6,
		shockRadius = 7,
		coreRadius = 1.5,
		layers = { "gather", "portal", "pillar", "flash", "sparks", "motes", "dissipation" },
	}),
	aura = archetype({
		label = "Aura",
		loop = true,
		loopDuration = 2,
		grounded = true,
		burst = false,
		anticipation = 0,
		charge = 0,
		chargeDefault = false,
		action = 0,
		secondary = 0,
		dissipation = 0,
		coreHeight = 2,
		flashSize = 4,
		shockRadius = 4.5,
		coreRadius = 1,
		layers = { "auraBody", "pulse", "orbit", "motes?" },
	}),
	magicCircle = archetype({
		label = "Magic Circle",
		loop = true,
		loopDuration = 3,
		grounded = true,
		burst = false,
		anticipation = 0,
		charge = 0,
		chargeDefault = false,
		action = 0,
		secondary = 0,
		dissipation = 0,
		coreHeight = 1.5,
		flashSize = 4,
		shockRadius = 7.5,
		coreRadius = 1,
		layers = { "circle", "pulse", "motes?" },
	}),
} :: { [string]: ArchetypeTemplate }

Recipes.ARCHETYPE_ORDER = {
	"impact",
	"explosion",
	"strike",
	"beam",
	"slash",
	"meteor",
	"teleport",
	"aura",
	"magicCircle",
}

return Recipes
