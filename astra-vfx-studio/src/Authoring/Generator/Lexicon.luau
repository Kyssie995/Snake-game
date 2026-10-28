--!strict
--[[
	Lexicon — prompt tokenisation and keyword lookup for Authoring/Generator (English and German).

	  Lexicon.fold(text) -> string                  lower-case ASCII form ("Trümmer" -> "trummer", "groß" -> "gross")
	  Lexicon.tokenize(text) -> ({ string }, breaks) folded words ([a-z0-9]+), at most MAX_TOKENS; breaks[i] =
	                                                true when clause punctuation (, ; : . ! ?) precedes word i
	  Lexicon.lookup(word) -> (form?, { Tag }?)     direct entry, else the first stem that is an entry
	  Lexicon.match(tokens) -> ({ Match }, { string })   recognised keywords in token order + unknown words
	  Lexicon.ENTRIES                               folded keyword -> { Tag } (read-only by convention)

	Folding: ASCII letters are lower-cased; the German umlauts and ß are transliterated to the base letter
	(ä -> a, ö -> o, ü -> u, ß -> ss) and common accented Latin letters to theirs (é -> e, ...); every other byte
	(punctuation, digits stay, other non-ASCII characters, invalid UTF-8) separates words. Keywords are written
	in their natural spelling below and registered in two folded variants, the base-letter form ("trummer") and
	the "ae/oe/ue" form ("truemmer"), so either way of typing an umlaut matches.

	Stemming (lookup): the word itself, then the word without one of the endings "s", "es", "en", "e", "n", "er",
	"em", "ern" (plural s/es, German -en/-e/-n and adjective endings), as long as at least 3 characters remain.
	Only stems that are entries match, so stemming never invents a meaning ("runes" -> "rune", "kugeln" ->
	"kugel", "riesigen" -> "riesig", but "run" stays unknown).

	Compounds (match): a word that is no entry and has at least 6 characters is split into 2..3 known parts
	(each at least 3 characters, each looked up with stemming, so German linking letters such as the "n" of
	"Sonnenstrahl" are covered): "feuerexplosion" -> feuer + explosion, "eiskugel" -> eis + kugel,
	"thunderstorm" -> thunder + storm. The longest first part wins. Only complete decompositions count, which
	keeps "string" (st + ring) or "notice" (not + ice: negations and connectors are never parts) from matching.
	Explicit entries win over splitting ("blitzlicht" is a flash, not lightning + light; "lichtbogen" is an electric
	arc).

	Tags (Tag.kind / Tag.value):
	  element     fire | lightning | ice | water | poison | shadow | holy | energy | earth | wind | nature
	  archetype   explosion | strike | beam | slash | aura | magicCircle | teleport | meteor | impact
	  intensity   2 (massive) | 1.4 (big) | 0.6 (small)
	  speed       0.7 (quick) | 1.4 (slow)
	  component   charge | sphere | arcs | flash | shockwave | smoke | debris | sparks | beam | trail | pillar |
	              rays | shake | screen
	  color       red | orange | gold | yellow | green | cyan | blue | purple | pink | white | black
	  modifier    bright | glow | expand
	  negation    (no value) "no", "without", "ohne", "kein", ...: negates the next 3 words (up to a clause break)
	  connector   (no value) "with", "mit", ...: ends the head clause (archetype choice, see Generator)
	Stopwords ("a", "the", "create", "ein", "mit", ...) are recognised silently: they are neither matches nor
	unknown words.
]]

local Lexicon = {}

export type Tag = { kind: string, value: any }
export type Match = {
	word: string, -- the folded prompt word
	form: string, -- the lexicon entry that matched (stem or compound part)
	index: number, -- token index (1-based); compound parts share the index of their word
	tags: { Tag },
}

Lexicon.MAX_TOKENS = 400
Lexicon.MAX_COMPOUND_LENGTH = 32
Lexicon.MIN_PART = 3
Lexicon.SUFFIXES = { "s", "es", "en", "e", "n", "er", "em", "ern" }

-- ─────────────────────────────────────────────────────────────────────────────
-- Folding
-- ─────────────────────────────────────────────────────────────────────────────

-- Two-byte UTF-8 sequences (C3 xx) folded to ASCII; "ae" mode spells umlauts as ae/oe/ue.
local LATIN_BASE: { [number]: string } = {
	[0x84] = "a", -- Ä
	[0xA4] = "a", -- ä
	[0x96] = "o", -- Ö
	[0xB6] = "o", -- ö
	[0x9C] = "u", -- Ü
	[0xBC] = "u", -- ü
	[0x9F] = "ss", -- ß
	[0x80] = "a", -- À
	[0x81] = "a", -- Á
	[0x82] = "a", -- Â
	[0xA0] = "a", -- à
	[0xA1] = "a", -- á
	[0xA2] = "a", -- â
	[0x87] = "c", -- Ç
	[0xA7] = "c", -- ç
	[0x88] = "e", -- È
	[0x89] = "e", -- É
	[0x8A] = "e", -- Ê
	[0xA8] = "e", -- è
	[0xA9] = "e", -- é
	[0xAA] = "e", -- ê
	[0xAB] = "e", -- ë
	[0x8E] = "i", -- Î
	[0xAE] = "i", -- î
	[0xAF] = "i", -- ï
	[0x94] = "o", -- Ô
	[0xB4] = "o", -- ô
	[0x9B] = "u", -- Û
	[0xBB] = "u", -- û
	[0x91] = "n", -- Ñ
	[0xB1] = "n", -- ñ
}
local UMLAUT_AE: { [number]: string } = {
	[0x84] = "ae",
	[0xA4] = "ae",
	[0x96] = "oe",
	[0xB6] = "oe",
	[0x9C] = "ue",
	[0xBC] = "ue",
}

-- Clause punctuation (, ; : . ! ?) — tokenize() records a break before the next word.
local BREAKS: { [number]: boolean } = { [44] = true, [59] = true, [58] = true, [46] = true, [33] = true, [63] = true }

local function foldWith(text: string, ae: boolean, breaks: boolean?): string
	local out = table.create(#text)
	local i = 1
	local n = #text
	while i <= n do
		local b = string.byte(text, i)
		if breaks and BREAKS[b] then
			table.insert(out, " | ")
			i += 1
		elseif b >= 65 and b <= 90 then
			table.insert(out, string.char(b + 32))
			i += 1
		elseif (b >= 97 and b <= 122) or (b >= 48 and b <= 57) then
			table.insert(out, string.char(b))
			i += 1
		else
			local c = if b == 0xC3 and i < n then string.byte(text, i + 1) else nil
			if c and c >= 0x80 and c <= 0xBF then
				local mapped = (if ae then UMLAUT_AE[c] else nil) or LATIN_BASE[c]
				table.insert(out, mapped or " ")
				i += 2
			else
				-- Other ASCII punctuation and any other non-ASCII byte (valid or not) separate words.
				table.insert(out, " ")
				i += 1
			end
		end
	end
	return table.concat(out)
end

-- Lower-case ASCII form of `text` (umlauts -> base letters, other characters -> spaces).
function Lexicon.fold(text: string): string
	return foldWith(text, false)
end

-- Folded words of `text` (at most MAX_TOKENS) and the token indices preceded by clause punctuation.
function Lexicon.tokenize(text: string): ({ string }, { [number]: boolean })
	local tokens: { string } = {}
	local breaks: { [number]: boolean } = {}
	local pending = false
	for word in string.gmatch(foldWith(text, false, true), "[a-z0-9|]+") do
		if word == "|" then
			pending = true
		else
			table.insert(tokens, word)
			if pending then
				breaks[#tokens] = true
				pending = false
			end
			if #tokens >= Lexicon.MAX_TOKENS then
				break
			end
		end
	end
	return tokens, breaks
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Vocabulary (natural spelling; folded when registered)
-- ─────────────────────────────────────────────────────────────────────────────

local ELEMENT_WORDS: { [string]: { string } } = {
	fire = {
		"fire",
		"flame",
		"flames",
		"flaming",
		"fiery",
		"blaze",
		"blazing",
		"burn",
		"burning",
		"inferno",
		"lava",
		"magma",
		"heat",
		"pyro",
		"firework",
		"feuer",
		"feurig",
		"flamme",
		"brennend",
		"lodernd",
		"hitze",
		"glut",
	},
	lightning = {
		"lightning",
		"electric",
		"electrical",
		"electricity",
		"electrified",
		"electrifying",
		"electro",
		"thunder",
		"thunderbolt",
		"shock",
		"volt",
		"voltage",
		"static",
		"tesla",
		"plasma",
		"zap",
		"blitz",
		"strom",
		"elektrisch",
		"elektro",
		"elektrizität",
		"donner",
		"gewitter",
		"spannung",
	},
	ice = {
		"ice",
		"icy",
		"frost",
		"frosty",
		"frozen",
		"freeze",
		"freezing",
		"cold",
		"snow",
		"glacier",
		"crystal",
		"blizzard",
		"cryo",
		"eis",
		"eisig",
		"gefroren",
		"kalt",
		"kälte",
		"schnee",
		"kristall",
		"gletscher",
	},
	water = {
		"water",
		"aqua",
		"aquatic",
		"splash",
		"ocean",
		"sea",
		"tidal",
		"tide",
		"rain",
		"liquid",
		"hydro",
		"wasser",
		"flut",
		"meer",
		"regen",
		"nass",
	},
	poison = {
		"poison",
		"poisonous",
		"toxic",
		"venom",
		"venomous",
		"acid",
		"acidic",
		"plague",
		"corrosive",
		"gift",
		"giftig",
		"säure",
		"toxisch",
		"pest",
		"ätzend",
	},
	shadow = {
		"shadow",
		"shadows",
		"dark",
		"darkness",
		"void",
		"abyss",
		"abyssal",
		"night",
		"evil",
		"curse",
		"cursed",
		"demonic",
		"necrotic",
		"umbral",
		"demon",
		"schatten",
		"dunkel",
		"dunkle",
		"dunkelheit",
		"finsternis",
		"leere",
		"abgrund",
		"fluch",
		"verflucht",
		"dämonisch",
	},
	holy = {
		"holy",
		"light",
		"divine",
		"heaven",
		"heavenly",
		"sacred",
		"angelic",
		"radiant",
		"celestial",
		"sun",
		"solar",
		"blessing",
		"blessed",
		"smite",
		"licht",
		"heilig",
		"göttlich",
		"himmlisch",
		"sonne",
		"strahlend",
		"segen",
		"gesegnet",
	},
	energy = {
		"energy",
		"magic",
		"magical",
		"arcane",
		"mana",
		"mystic",
		"mystical",
		"spell",
		"psychic",
		"cosmic",
		"ki",
		"chakra",
		"energie",
		"magie",
		"magisch",
		"arkan",
		"mystisch",
		"zauber",
		"kosmisch",
	},
	earth = {
		"earth",
		"earthen",
		"rock",
		"rocky",
		"stone",
		"boulder",
		"sand",
		"mud",
		"terra",
		"granite",
		"erde",
		"erd",
		"fels",
		"felsen",
		"stein",
		"lehm",
	},
	wind = {
		"wind",
		"windy",
		"air",
		"gust",
		"tornado",
		"whirlwind",
		"cyclone",
		"breeze",
		"storm",
		"hurricane",
		"aero",
		"vortex",
		"luft",
		"sturm",
		"böe",
		"wirbel",
		"wirbelwind",
		"orkan",
	},
	nature = {
		"nature",
		"natural",
		"leaf",
		"leaves",
		"plant",
		"vine",
		"flower",
		"forest",
		"grass",
		"petal",
		"thorn",
		"life",
		"heal",
		"healing",
		"druid",
		"natur",
		"blatt",
		"blätter",
		"pflanze",
		"ranke",
		"blume",
		"wald",
		"blüte",
		"dorn",
		"leben",
		"heilung",
	},
}

local ARCHETYPE_WORDS: { [string]: { string } } = {
	explosion = {
		"explosion",
		"explode",
		"explodes",
		"exploding",
		"explosive",
		"exploded",
		"blast",
		"burst",
		"detonation",
		"detonate",
		"boom",
		"nova",
		"explodieren",
		"explodiert",
		"explodierend",
		"explosiv",
	},
	strike = {
		"strike",
		"bolt",
		"thunderbolt",
		"smite",
		"einschlag",
		"schlag",
	},
	beam = { "beam", "laser", "ray", "kamehameha", "strahl" },
	slash = {
		"slash",
		"swing",
		"cut",
		"slice",
		"sword",
		"blade",
		"cleave",
		"swipe",
		"schnitt",
		"hieb",
		"schwung",
		"klinge",
		"schwert",
	},
	aura = { "aura", "buff", "mantle", "cloak", "emanation", "ausstrahlung" },
	magicCircle = {
		"circle",
		"rune",
		"sigil",
		"glyph",
		"seal",
		"pentagram",
		"summoning",
		"kreis",
		"siegel",
		"bannkreis",
	},
	teleport = {
		"teleport",
		"teleportation",
		"portal",
		"warp",
		"blink",
		"vanish",
		"verschwinden",
	},
	meteor = { "meteor", "meteorite", "comet", "asteroid", "meteorit", "komet" },
	impact = {
		"impact",
		"hit",
		"punch",
		"smash",
		"slam",
		"crash",
		"collision",
		"aufprall",
		"treffer",
		"aufschlag",
		"wucht",
		"stoß",
	},
}

local INTENSITY_WORDS: { [number]: { string } } = {
	[2] = {
		"massive",
		"huge",
		"giant",
		"gigantic",
		"enormous",
		"colossal",
		"epic",
		"ultimate",
		"mega",
		"titanic",
		"gewaltig",
		"riesig",
		"gigantisch",
		"enorm",
		"ultimativ",
		"episch",
	},
	[1.4] = {
		"big",
		"bigger",
		"large",
		"larger",
		"strong",
		"powerful",
		"heavy",
		"intense",
		"groß",
		"stark",
		"kräftig",
		"heftig",
		"mächtig",
		"wuchtig",
	},
	[0.6] = {
		"small",
		"smaller",
		"tiny",
		"little",
		"mini",
		"minor",
		"subtle",
		"weak",
		"klein",
		"winzig",
		"schwach",
		"dezent",
	},
}

local SPEED_WORDS: { [number]: { string } } = {
	[0.7] = { "quick", "quickly", "fast", "faster", "rapid", "swift", "instant", "snappy", "schnell", "rasch", "flink" },
	[1.4] = {
		"slow",
		"slowly",
		"slower",
		"lingering",
		"gradual",
		"langsam",
		"träge",
		"gemächlich",
	},
}

local COMPONENT_WORDS: { [string]: { string } } = {
	charge = {
		"charge",
		"charging",
		"charged",
		"chargeup",
		"buildup",
		"gather",
		"gathering",
		"aufladen",
		"aufladung",
		"aufladend",
		"auflädt",
		"lädt",
		"aufgeladen",
		"laden",
		"ladend",
		"geladen",
	},
	sphere = { "sphere", "orb", "core", "ball", "globe", "kugel", "kern" },
	arcs = { "arc", "arcs", "lightning", "tendril", "crackle", "crackling", "bogen", "bögen", "lichtbogen" },
	flash = { "flash", "flare", "blitzlicht", "lichtblitz", "aufblitzen" },
	shockwave = {
		"shockwave",
		"ring",
		"ripple",
		"wave",
		"druckwelle",
		"schockwelle",
		"welle",
	},
	smoke = { "smoke", "smoky", "fumes", "cloud", "haze", "rauch", "qualm", "wolke", "dunst" },
	debris = {
		"debris",
		"rocks",
		"rubble",
		"fragment",
		"shard",
		"chunk",
		"pieces",
		"boulders",
		"shatter",
		"shattered",
		"shattering",
		"trümmer",
		"splitter",
		"brocken",
		"geröll",
		"schutt",
	},
	sparks = {
		"spark",
		"sparkle",
		"ember",
		"embers",
		"glitter",
		"sparkling",
		"particles",
		"funken",
		"funke",
		"glitzer",
		"partikel",
	},
	beam = { "beam", "strahl", "laserstrahl" },
	trail = { "trail", "streak", "tail", "streamer", "spur", "schweif", "streifen" },
	pillar = { "pillar", "column", "tower", "geyser", "säule", "pfeiler", "lichtsäule" },
	rays = { "rays", "spikes", "spokes", "radial", "strahlen", "spitzen", "stacheln" },
	shake = {
		"shake",
		"shaking",
		"quake",
		"earthquake",
		"rumble",
		"tremor",
		"beben",
		"erdbeben",
		"wackeln",
		"erschütterung",
	},
	screen = { "screen", "impactframe", "bildschirm" },
}

local COLOR_WORDS: { [string]: { string } } = {
	red = { "red", "crimson", "scarlet", "ruby", "rot", "blutrot" },
	orange = { "orange" },
	gold = { "gold", "golden" },
	yellow = { "yellow", "gelb" },
	green = { "green", "emerald", "lime", "grün", "smaragd" },
	cyan = { "cyan", "teal", "turquoise", "türkis" },
	blue = { "blue", "azure", "sapphire", "cobalt", "navy", "blau", "saphir" },
	purple = { "purple", "violet", "lila", "violett", "purpur", "amethyst" },
	pink = { "pink", "magenta", "rosa" },
	white = { "white", "weiß" },
	black = { "black", "schwarz" },
}

local MODIFIER_WORDS: { [string]: { string } } = {
	bright = {
		"bright",
		"brilliant",
		"blinding",
		"dazzling",
		"vivid",
		"hell",
		"grell",
		"gleißend",
		"leuchtend",
	},
	glow = { "glow", "glowing", "glühen", "glühend", "leuchten" },
	expand = { "expanding", "expand", "expands", "growing", "spreading", "expandierend", "wachsend", "ausbreitend" },
}

local NEGATION_WORDS = { "no", "not", "without", "none", "ohne", "kein", "keine", "keinen", "keinem", "keiner" }
local CONNECTOR_WORDS = {
	"with",
	"featuring",
	"including",
	"containing",
	"having",
	"plus",
	"that",
	"which",
	"mit",
	"samt",
	"inklusive",
	"welche",
	"welcher",
}

local STOPWORDS = {
	"a",
	"an",
	"the",
	"of",
	"and",
	"or",
	"to",
	"in",
	"on",
	"at",
	"for",
	"from",
	"by",
	"into",
	"onto",
	"is",
	"are",
	"be",
	"it",
	"its",
	"this",
	"some",
	"very",
	"really",
	"super",
	"so",
	"like",
	"as",
	"then",
	"also",
	"more",
	"much",
	"many",
	"lots",
	"around",
	"above",
	"below",
	"over",
	"under",
	"up",
	"down",
	"out",
	"off",
	"after",
	"before",
	"while",
	"during",
	"through",
	"create",
	"make",
	"generate",
	"build",
	"design",
	"give",
	"me",
	"my",
	"i",
	"want",
	"need",
	"please",
	"effect",
	"effects",
	"vfx",
	"visual",
	"one",
	"two",
	"three",
	"ein",
	"eine",
	"einen",
	"einem",
	"einer",
	"eines",
	"der",
	"die",
	"das",
	"den",
	"dem",
	"des",
	"und",
	"oder",
	"von",
	"vom",
	"zu",
	"zum",
	"zur",
	"im",
	"an",
	"am",
	"auf",
	"aus",
	"für",
	"bei",
	"nach",
	"vor",
	"über",
	"unter",
	"durch",
	"ist",
	"sind",
	"sein",
	"erstelle",
	"erstellen",
	"erzeuge",
	"erzeugen",
	"mache",
	"machen",
	"generiere",
	"baue",
	"bitte",
	"effekt",
	"effekte",
	"ich",
	"mir",
	"mein",
	"will",
	"möchte",
	"brauche",
	"sehr",
	"ganz",
	"wie",
	"dann",
	"auch",
	"mehr",
	"viel",
	"viele",
	"sich",
	"dass",
	"einem",
	"um",
	"herum",
	"sowie",
	"ground",
	"boden",
	"camera",
	"kamera",
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Registry
-- ─────────────────────────────────────────────────────────────────────────────

local ENTRIES: { [string]: { Tag } } = {}
local STOP: { [string]: boolean } = {}

local function register(word: string, tag: Tag)
	local seen: { [string]: boolean } = {}
	for _, form in { foldWith(word, false), foldWith(word, true) } do
		form = string.gsub(form, "%s+", "")
		if form ~= "" and not seen[form] then
			seen[form] = true
			local list = ENTRIES[form]
			if not list then
				list = {}
				ENTRIES[form] = list
			end
			local duplicate = false
			for _, existing in list do
				if existing.kind == tag.kind and existing.value == tag.value then
					duplicate = true
					break
				end
			end
			if not duplicate then
				table.insert(list, tag)
			end
		end
	end
end

-- Registers groups in sorted key order so the tag order of shared words is deterministic.
local function registerGroups(kind: string, groups: { [any]: { string } })
	local keys = {}
	for key in groups do
		table.insert(keys, key)
	end
	table.sort(keys, function(a: any, b: any)
		return tostring(a) < tostring(b)
	end)
	for _, key in keys do
		for _, word in groups[key] do
			register(word, { kind = kind, value = key })
		end
	end
end

registerGroups("element", ELEMENT_WORDS)
registerGroups("archetype", ARCHETYPE_WORDS)
registerGroups("intensity", INTENSITY_WORDS)
registerGroups("speed", SPEED_WORDS)
registerGroups("component", COMPONENT_WORDS)
registerGroups("color", COLOR_WORDS)
registerGroups("modifier", MODIFIER_WORDS)
for _, word in NEGATION_WORDS do
	register(word, { kind = "negation", value = true })
end
for _, word in CONNECTOR_WORDS do
	register(word, { kind = "connector", value = true })
end
-- Words with two meanings
register("rocks", { kind = "element", value = "earth" })
register("lichtbogen", { kind = "element", value = "lightning" })
register("thunderbolt", { kind = "element", value = "lightning" })
register("earthquake", { kind = "element", value = "earth" })
register("erdbeben", { kind = "element", value = "earth" })
register("lichtsäule", { kind = "element", value = "holy" })
register("laserstrahl", { kind = "archetype", value = "beam" })
register("firework", { kind = "archetype", value = "explosion" })
register("splash", { kind = "component", value = "sparks" })
register("impactframe", { kind = "archetype", value = "impact" })

for _, word in STOPWORDS do
	for _, form in { foldWith(word, false), foldWith(word, true) } do
		if not ENTRIES[form] then
			STOP[form] = true
		end
	end
end

Lexicon.ENTRIES = ENTRIES

-- True when `word` (folded) is a stopword.
function Lexicon.isStopword(word: string): boolean
	return STOP[word] == true
end

-- The entry for `word` (folded): the word itself, else the first stem that is an entry.
function Lexicon.lookup(word: string): (string?, { Tag }?)
	local tags = ENTRIES[word]
	if tags then
		return word, tags
	end
	for _, suffix in Lexicon.SUFFIXES do
		local cut = #word - #suffix
		if cut >= Lexicon.MIN_PART and string.sub(word, cut + 1) == suffix then
			local stem = string.sub(word, 1, cut)
			tags = ENTRIES[stem]
			if tags then
				return stem, tags
			end
		end
	end
	return nil, nil
end

-- A compound part must carry a meaning (negations and connectors never do: "notice" is not "not" + "ice").
local function partForm(text: string): string?
	local form, tags = Lexicon.lookup(text)
	if form and tags then
		for _, tag in tags do
			if tag.kind ~= "negation" and tag.kind ~= "connector" then
				return form
			end
		end
	end
	return nil
end

-- Splits `word` into 2..3 known parts (longest first part first); nil when no full decomposition exists.
local function split(word: string, depth: number): { string }?
	local n = #word
	local minPart = Lexicon.MIN_PART
	for i = n - minPart, minPart, -1 do
		local head = string.sub(word, 1, i)
		local headForm = partForm(head)
		if headForm then
			local tail = string.sub(word, i + 1)
			local tailForm = partForm(tail)
			if tailForm then
				return { headForm, tailForm }
			end
			if depth < 2 and #tail >= 2 * minPart then
				local rest = split(tail, depth + 1)
				if rest then
					table.insert(rest, 1, headForm)
					return rest
				end
			end
		end
	end
	return nil
end

-- Two-word phrases read as one keyword (first word, second word -> entry).
local BIGRAMS: { [string]: { [string]: string } } = {
	shock = { wave = "shockwave", waves = "shockwave" },
	camera = { shake = "shake", shakes = "shake", shaking = "shake" },
	kamera = { wackeln = "shake", beben = "shake" },
	impact = { frame = "impactframe", frames = "impactframe" },
	screen = { flash = "screen", shake = "shake" },
}
-- Shade words (entry forms): before a colour they modify the colour instead of naming an element ("light blue",
-- "dunkelblau").
local SHADES: { [string]: string } =
	{ light = "light", hell = "light", dark = "dark", dunkel = "dark", dunkle = "dark" }

local function hasColor(form: string?): boolean
	local tags = if form then ENTRIES[form] else nil
	if tags then
		for _, tag in tags do
			if tag.kind == "color" then
				return true
			end
		end
	end
	return false
end

-- Appends the matches of consecutive entry forms of one prompt word (a shade before a colour becomes a modifier).
local function addForms(matches: { Match }, word: string, index: number, forms: { string }, nextForm: string?)
	for i, form in forms do
		local following = if i < #forms then forms[i + 1] else nextForm
		local shade = SHADES[form]
		if shade and hasColor(following) then
			table.insert(
				matches,
				{ word = word, form = form, index = index, tags = { { kind = "modifier", value = shade } } }
			)
		else
			table.insert(matches, { word = word, form = form, index = index, tags = ENTRIES[form] })
		end
	end
end

-- Recognised keywords of `tokens` in order, and the words that are neither keywords nor stopwords.
function Lexicon.match(tokens: { string }): ({ Match }, { string })
	local matches: { Match } = {}
	local unknown: { string } = {}
	local skip = 0
	for index, word in tokens do
		if index <= skip then
			continue
		end
		local nextWord = tokens[index + 1]
		local bigram = BIGRAMS[word]
		local joined = if bigram and nextWord then bigram[nextWord] else nil
		local form = Lexicon.lookup(word)
		if joined and ENTRIES[joined] then
			table.insert(
				matches,
				{ word = word .. " " .. nextWord, form = joined, index = index, tags = ENTRIES[joined] }
			)
			skip = index + 1
		elseif form then
			addForms(matches, word, index, { form }, if nextWord then Lexicon.lookup(nextWord) else nil)
		elseif STOP[word] or string.match(word, "^%d+$") then
			continue
		else
			local parts = if #word >= 2 * Lexicon.MIN_PART and #word <= Lexicon.MAX_COMPOUND_LENGTH
				then split(word, 1)
				else nil
			if parts then
				addForms(matches, word, index, parts, nil)
			else
				table.insert(unknown, word)
			end
		end
	end
	return matches, unknown
end

return Lexicon
