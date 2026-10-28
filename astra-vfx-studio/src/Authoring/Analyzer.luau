--!strict
--[[
	Analyzer — heuristic performance analysis of an effect definition (docs/MODULE_CONTRACTS.md §20,
	docs/research/vfx-design-performance.md §4.1).

	  Analyzer.analyze(def, options?) -> AnalysisReport
	  Analyzer.compareQualities(def, options?) -> { Low: AnalysisReport, Medium: AnalysisReport, High: AnalysisReport }
	  Analyzer.BUDGETS   per-level budget table (plain table: callers may change it; options.budgets overrides it
	                     per call)
	  Analyzer.NOTICE    "Heuristische Schätzung – keine FPS-Messung" — every UI showing a report must show it

	options = { quality: QualityLevel? (default "High" — the authored values), sampleRate: number? (default 30,
	            samples per effect second, capped at MAX_SAMPLE_RATE), scale: number? (effect scale, default 1),
	            budgets: { [metric]: number }? (partial override of BUDGETS[quality]) }

	Everything here is a HEURISTIC model of the engine's work. It never measures and never outputs frame rates
	(report.heuristic = true, report.notice). The definition must be migrated + validated (Core/Compiler raises on
	invalid property values); compiler warnings are passed through into report.diagnostics.

	Model (all times are effect seconds):
	  1. compiled = Compiler.compile(def, { quality, scale }). Only built components are analysed (minQuality,
	     enabled = false and lights beyond quality.maxLights are gone already); report.totals.omitted counts the rest.
	  2. Cost per component = descriptor.estimateCost(component, quality). A component whose ancestor moves every
	     frame (position / rotation track or a non-zero spin on any ancestor) is moved by the Player every frame as
	     well, so it is estimated as moving: with a synthetic position track (component.inheritedMotion = true).
	  3. Activity: active while Timeline.isActive (start <= t < end). A scheduled "disable" (component event or
	     graph SetEnabled) switches a component off until the next "enable": types that declare the events keep
	     their per-frame work but stop rendering / emitting; other types are switched off entirely (as the Player
	     does). Emitters and trails stay visible after their span: emitters while particles live, trails for
	     tailTime (= trail lifetime) after the end.
	  4. Particles of an emitting component (cost.emitters > 0), L = cost.maxLifetime (lifetime.Max): every
	     particle is assumed to live exactly L (upper bound). Alive at t = particles emitted in [lower, t] with
	     lower = max(t − L, the last "clear" at or before t):
	       continuous  ∫ rate over the emitting intervals (span ∩ enabled) inside [lower, t]. With a constant rate
	                   this is rate × min(t − start, L) while active, decaying linearly to 0 over L after the end.
	                   A `rate` track is integrated numerically (trapezoids, RATE_STEP). Rates are clamped to
	                   Constants.MAX_PARTICLE_RATE like the controller does. Graph tween/set on `rate` is ignored.
	       bursts      the `burst` property at activation + every scheduled "emit" (component events and graph
	                   Emit; a count-less event uses the descriptor's default count), each alive on the closed
	                   interval [t_emit, t_emit + L].
	     The burst-at-activation and default emit counts are read through estimateCost (events removed / one
	     count-less emit added), so the Analyzer does not duplicate descriptor constants.
	  5. Sampling: t = i / sampleRate over the window [0, duration + maxTail], plus the window end and every
	     breakpoint of the piecewise-linear model (span starts/ends, start + L, end + tail, emit times and
	     emit + L, clear and enable/disable times), so peaks of short bursts are not missed. Looping effects are
	     analysed in steady state: the window is [0, duration] and particles / trail tails of earlier cycles
	     (t + k × duration, k = 1..ceil(maxTail / duration)) are added (the cycle-0 schedule is used for every
	     cycle).
	  6. Per sample: live particles, active components, visible emitters / beams / trails / lights / shadow
	     lights, per-frame movingParts and propertyUpdates (active components), transparentLayers and
	     overdrawWeight. Particle overdraw = (largest sprite size × component scale × sizeCompensation)² × live
	     particles (the per-particle form of Particles.estimateCost); every other component adds its static
	     cost.overdrawWeight / transparentLayers while visible. report.peaks holds the maximum of every series and
	     the first sample time reaching it.
	  7. Totals: sums of the cost estimates over the built components plus OVERHEAD (the Builder's container
	     Folder and Root part); animated = components with tracks or a non-zero spin; procedural = descriptor
	     category "Procedural".
	  8. Budgets (BUDGETS[quality], heuristic): liveParticles, emitters, beams, trails, lights, shadowLights,
	     movingParts, propertyUpdates (peaks) and instances (total). status = "ok" (value <= WARN_RATIO × budget),
	     "warn" (above that, up to the budget), "over" (above the budget); a budget of 0 is "over" for any
	     value > 0 (ratio nil). Non-ok metrics become Diagnostics "perf.<metric>" (over: warning, warn: info) at the
	     component that contributes most at the peak (most instances for `instances`), with a hint such as
	     "reduce rate or lifetime on 'Sparks'" or "set minQuality = Medium for 'Glow Light'". Notes of the cost
	     estimates become "perf.note" infos.
	  9. report.components: per-component breakdown sorted by score (descending, then compiled order), score =
	     Σ over the budget metrics of contribution / budget (budget 0 counts as 1): own peak live particles,
	     static counts and per-frame numbers (0 for an empty span).

	Not modelled (documented limits): the effect timeScale and ParticleEmitter.TimeScale (effect time is used as
	real time), engine LOD (it is platform specific and not readable, research §4.2 item 1), parts moved because
	the whole effect is attached to a moving target, graph tween/set overrides, per-cycle graph randomness.
]]

local Common = require(script.Parent.Parent.AstraVFX.Core.Components.Common)
local Compiler = require(script.Parent.Parent.AstraVFX.Core.Compiler)
local Components = require(script.Parent.Parent.AstraVFX.Core.Components)
local Constants = require(script.Parent.Parent.AstraVFX.Core.Constants)
local Curves = require(script.Parent.Parent.AstraVFX.Core.Curves)
local Quality = require(script.Parent.Parent.AstraVFX.Core.Quality)
local Timeline = require(script.Parent.Parent.AstraVFX.Core.Timeline)
local Types = require(script.Parent.Parent.AstraVFX.Core.Types)

type EffectDefinition = Types.EffectDefinition
type CompiledEffect = Types.CompiledEffect
type CompiledComponent = Types.CompiledComponent
type CompiledTrack = Types.CompiledTrack
type ComponentDescriptor = Types.ComponentDescriptor
type CostEstimate = Types.CostEstimate
type Diagnostic = Types.Diagnostic
type QualityLevel = Types.QualityLevel
type QualityProfile = Types.QualityProfile

export type BudgetStatus = "ok" | "warn" | "over"

-- Budget per metric (keys of Analyzer.METRICS).
export type Budget = {
	liveParticles: number,
	emitters: number,
	beams: number,
	trails: number,
	lights: number,
	shadowLights: number,
	movingParts: number,
	propertyUpdates: number,
	instances: number,
}

export type AnalyzeOptions = {
	quality: QualityLevel?,
	sampleRate: number?,
	scale: number?,
	budgets: { [string]: number }?,
}

-- Maximum of one series and the first sample time reaching it.
export type Peak = { value: number, time: number }

export type Peaks = {
	liveParticles: Peak,
	activeComponents: Peak,
	emitters: Peak,
	beams: Peak,
	trails: Peak,
	lights: Peak,
	shadowLights: Peak,
	movingParts: Peak,
	propertyUpdates: Peak,
	transparentLayers: Peak,
	overdrawWeight: Peak,
}

export type Totals = {
	components: number, -- built components
	omitted: number, -- definition components that are not built at this quality (disabled, minQuality, maxLights)
	instances: number, -- including OVERHEAD.instances
	parts: number, -- including OVERHEAD.parts
	attachments: number,
	emitters: number,
	beams: number,
	trails: number,
	lights: number,
	shadowLights: number,
	sounds: number,
	animated: number, -- components with tracks or a non-zero spin
	procedural: number, -- descriptor category "Procedural"
}

export type MetricResult = {
	key: string,
	label: string, -- German UI label
	value: number,
	budget: number,
	ratio: number?, -- value / budget; nil when the budget is 0
	status: BudgetStatus,
	time: number?, -- peak time (nil for totals)
	componentId: string?, -- largest contributor at the peak (nil when the value is 0)
}

export type ComponentReport = {
	id: string,
	name: string,
	type: string,
	category: string,
	index: number, -- 1-based index in def.components
	order: number, -- position in the compiled (topological) order
	startTime: number,
	endTime: number,
	tail: number, -- descriptor tailTime
	cost: CostEstimate, -- at the analysed quality (inherited motion applied)
	inheritedMotion: boolean,
	animated: boolean,
	procedural: boolean,
	peakParticles: number, -- own peak live particles
	shares: { [string]: number }, -- metric -> contribution / budget (non-zero entries only)
	score: number, -- Σ shares
	notes: { string },
}

-- One value per sample (series.time); the same keys as Peaks.
export type Series = {
	time: { number },
	liveParticles: { number },
	activeComponents: { number },
	emitters: { number },
	beams: { number },
	trails: { number },
	lights: { number },
	shadowLights: { number },
	movingParts: { number },
	propertyUpdates: { number },
	transparentLayers: { number },
	overdrawWeight: { number },
}

export type AnalysisReport = {
	effectId: string,
	effectName: string,
	quality: QualityLevel,
	sampleRate: number,
	scale: number,
	heuristic: boolean, -- always true
	notice: string, -- Analyzer.NOTICE; the UI must show it
	loop: boolean,
	duration: number,
	maxTail: number,
	window: number, -- sampled seconds: duration + maxTail (duration for looping effects)
	sampleCount: number,
	status: BudgetStatus, -- worst metric status
	peaks: Peaks,
	totals: Totals,
	budget: Budget,
	metrics: { MetricResult }, -- in Analyzer.METRICS order
	components: { ComponentReport }, -- sorted by score
	diagnostics: { Diagnostic },
	series: Series,
}

export type QualityComparison = { Low: AnalysisReport, Medium: AnalysisReport, High: AnalysisReport }

local Analyzer = {}

local INF = math.huge
local DEFAULT_QUALITY: QualityLevel = "High"
local LEVELS: { QualityLevel } = { "Low", "Medium", "High" }
local EPS = 1e-9

Analyzer.NOTICE = "Heuristische Schätzung – keine FPS-Messung"
Analyzer.DEFAULT_QUALITY = DEFAULT_QUALITY
Analyzer.DEFAULT_SAMPLE_RATE = 30
Analyzer.MAX_SAMPLE_RATE = 240
Analyzer.WARN_RATIO = 0.8 -- above this share of a budget the status is "warn"
Analyzer.RATE_STEP = 1 / 240 -- integration step (seconds) for animated particle rates
-- Instances the Builder creates per effect copy besides the components: the container Folder and the Root part.
Analyzer.OVERHEAD = { instances = 2, parts = 1 }

-- Heuristic per-level budgets (not engine limits). Plain tables, so a game can tune them.
Analyzer.BUDGETS = {
	Low = {
		liveParticles = 300,
		emitters = 8,
		beams = 8,
		trails = 4,
		lights = 2,
		shadowLights = 0,
		movingParts = 40,
		propertyUpdates = 150,
		instances = 150,
	},
	Medium = {
		liveParticles = 800,
		emitters = 16,
		beams = 16,
		trails = 8,
		lights = 4,
		shadowLights = 0,
		movingParts = 100,
		propertyUpdates = 400,
		instances = 300,
	},
	High = {
		liveParticles = 2000,
		emitters = 32,
		beams = 32,
		trails = 16,
		lights = 8,
		shadowLights = 2,
		movingParts = 250,
		propertyUpdates = 1000,
		instances = 600,
	},
} :: { [string]: Budget }

type MetricInfo = { key: string, label: string, code: string, noun: string, total: boolean }

-- Budget metrics in report order. `total` metrics compare report.totals, the others report.peaks.
local METRICS: { MetricInfo } = {
	{
		key = "liveParticles",
		label = "Lebende Partikel",
		code = "perf.live_particles",
		noun = "live particles",
		total = false,
	},
	{ key = "emitters", label = "Emitter", code = "perf.emitters", noun = "active emitters", total = false },
	{ key = "beams", label = "Beams", code = "perf.beams", noun = "active beams", total = false },
	{ key = "trails", label = "Trails", code = "perf.trails", noun = "active trails", total = false },
	{ key = "lights", label = "Lichter", code = "perf.lights", noun = "active lights", total = false },
	{
		key = "shadowLights",
		label = "Schattenwerfende Lichter",
		code = "perf.shadow_lights",
		noun = "shadow-casting lights",
		total = false,
	},
	{
		key = "movingParts",
		label = "Bewegte Parts pro Frame",
		code = "perf.moving_parts",
		noun = "moving parts per frame",
		total = false,
	},
	{
		key = "propertyUpdates",
		label = "Property-Writes pro Frame",
		code = "perf.property_updates",
		noun = "property writes per frame",
		total = false,
	},
	{ key = "instances", label = "Instanzen", code = "perf.instances", noun = "instances", total = true },
}
Analyzer.METRICS = METRICS

local SERIES_KEYS: { string } = {
	"liveParticles",
	"activeComponents",
	"emitters",
	"beams",
	"trails",
	"lights",
	"shadowLights",
	"movingParts",
	"propertyUpdates",
	"transparentLayers",
	"overdrawWeight",
}

local NEXT_LEVEL: { [string]: QualityLevel } = { Low = "Medium", Medium = "High" }

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= INF and x ~= -INF
end

-- Rounds away float noise (199.99999999997 -> 200) in reported numbers.
local function clean(x: number): number
	local r = math.floor(x * 1e6 + 0.5) / 1e6
	if r == 0 then
		return 0 -- also -0
	end
	return r
end

local function formatNumber(x: number): string
	if x == math.floor(x) then
		return string.format("%d", x)
	end
	local s = string.format("%.2f", x)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s
end

local function linear(alpha: number): number
	return alpha
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Sorted-list helpers
-- ─────────────────────────────────────────────────────────────────────────────

-- Number of entries of the ascending list with value <= x (strict = false) or < x (strict = true).
local function countBelow(list: { number }, x: number, strict: boolean): number
	local lo, hi = 1, #list
	local n = 0
	while lo <= hi do
		local mid = (lo + hi) // 2
		local v = list[mid]
		if (strict and v < x) or (not strict and v <= x) then
			n = mid
			lo = mid + 1
		else
			hi = mid - 1
		end
	end
	return n
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Component model
-- ─────────────────────────────────────────────────────────────────────────────

type Model = {
	c: CompiledComponent,
	descriptor: ComponentDescriptor,
	index: number,
	order: number,
	cost: CostEstimate,
	inheritedMotion: boolean,
	start: number,
	finish: number,
	nonEmpty: boolean,
	tail: number,
	hardOff: boolean, -- "disable" switches the whole component off (the type does not declare the event)
	toggleTimes: { number },
	toggleOn: { boolean },
	-- particles
	emitting: boolean,
	lifetime: number,
	rate: number,
	rateTable: { number }?,
	rateStep: number,
	intervals: { { number } }, -- emission intervals { a, b } (span ∩ enabled, half-open)
	emitTimes: { number },
	emitPrefix: { number }, -- emitPrefix[i] = Σ counts of emitTimes[1..i]
	clearTimes: { number },
	spriteArea: number?, -- (sprite size)² per live particle; nil = static cost.overdrawWeight
	-- results
	peakLive: number,
}

local function movesItself(c: CompiledComponent): boolean
	local tracks = c.tracks
	if tracks.position or tracks.rotation then
		return true
	end
	local spin = c.props.spin
	return typeof(spin) == "Vector3" and (spin :: Vector3).Magnitude > 0
end

local function isAnimated(c: CompiledComponent): boolean
	if next(c.tracks) ~= nil then
		return true
	end
	local spin = c.props.spin
	return typeof(spin) == "Vector3" and (spin :: Vector3).Magnitude > 0
end

-- The component as estimateCost should see it: with a synthetic position track when an ancestor moves it.
local function costInput(c: CompiledComponent, inherited: boolean): CompiledComponent
	if not inherited or Common.isMoving(c) then
		return c
	end
	local copy = table.clone(c)
	local tracks = table.clone(c.tracks)
	tracks.position = {
		id = "analyzer-inherited-motion",
		channel = "position",
		kind = "vector3",
		keys = { { time = 0, value = c.position, ease = linear, constant = false } },
	}
	copy.tracks = tracks
	return copy
end

local function maxSequenceValue(sequence: NumberSequence): number
	local m = 0
	for _, k in sequence.Keypoints do
		m = math.max(m, k.Value + k.Envelope)
	end
	return m
end

-- Cumulative integral table of a clamped rate track over [start, finish] (trapezoids).
local function rateTable(track: CompiledTrack, start: number, finish: number): ({ number }, number)
	local span = finish - start
	local n = math.max(1, math.ceil(span / Analyzer.RATE_STEP - EPS))
	local h = span / n
	local function rateAt(localTime: number): number
		local v = Curves.evaluate(track, localTime)
		if not isFinite(v) then
			return 0
		end
		return math.clamp(v, 0, Constants.MAX_PARTICLE_RATE)
	end
	local out = table.create(n + 1, 0)
	local previous = rateAt(0)
	for i = 1, n do
		local current = rateAt(i * h)
		out[i + 1] = out[i] + h * (previous + current) / 2
		previous = current
	end
	return out, h
end

-- ∫ rate from model.start to x (x clamped to the span).
local function rateIntegral(m: Model, x: number): number
	local tableValues = m.rateTable :: { number }
	local u = math.clamp((x - m.start) / m.rateStep, 0, #tableValues - 1)
	local i = math.floor(u)
	if i >= #tableValues - 1 then
		return tableValues[#tableValues]
	end
	local a = tableValues[i + 1]
	return a + (tableValues[i + 2] - a) * (u - i)
end

local function enabledAt(m: Model, t: number): boolean
	local n = countBelow(m.toggleTimes, t, false)
	if n == 0 then
		return true
	end
	return m.toggleOn[n]
end

local function activeAt(m: Model, t: number): boolean
	if not (t >= m.start and t < m.finish) then
		return false
	end
	return not m.hardOff or enabledAt(m, t)
end

-- Particles alive at t were emitted in [lower, t]: lower = max(t − L, last clear at or before t).
local function windowStart(m: Model, t: number): number
	local lower = t - m.lifetime
	local clears = countBelow(m.clearTimes, t, false)
	if clears > 0 then
		lower = math.max(lower, m.clearTimes[clears])
	end
	return lower
end

-- Live particles from continuous emission (one cycle, single-cycle time t).
local function continuousSingle(m: Model, t: number): number
	if not m.emitting then
		return 0
	end
	local lower = windowStart(m, t)
	local total = 0
	for _, interval in m.intervals do
		local x = math.max(interval[1], lower)
		local y = math.min(interval[2], t)
		if y > x then
			if m.rateTable then
				total += rateIntegral(m, y) - rateIntegral(m, x)
			else
				total += m.rate * (y - x)
			end
		end
	end
	return total
end

-- Live particles from bursts and emit actions (one cycle, single-cycle time t).
local function burstSingle(m: Model, t: number): number
	if not m.emitting then
		return 0
	end
	local upto = countBelow(m.emitTimes, t, false)
	local before = countBelow(m.emitTimes, windowStart(m, t), true)
	if upto <= before then
		return 0
	end
	return m.emitPrefix[upto] - (if before > 0 then m.emitPrefix[before] else 0)
end

-- Trail segments (or any other tail) still fading after the span, at single-cycle time t.
local function tailVisibleSingle(m: Model, t: number): boolean
	return m.nonEmpty and m.tail > 0 and t >= m.finish and t <= m.finish + m.tail
end

-- Σ fn over the current and the earlier loop cycles still in their tail (t + k × duration, k = 0..cycles).
local function overCycles(fn: (Model, number) -> number, m: Model, t: number, cycles: number, duration: number): number
	local total = 0
	for k = 0, cycles do
		total += fn(m, t + k * duration)
	end
	return total
end

local function liveAt(m: Model, t: number, cycles: number, duration: number): number
	if not m.emitting then
		return 0
	end
	return overCycles(continuousSingle, m, t, cycles, duration) + overCycles(burstSingle, m, t, cycles, duration)
end

local function tailVisibleAt(m: Model, t: number, cycles: number, duration: number): boolean
	if m.tail <= 0 then
		return false
	end
	for k = 0, cycles do
		if tailVisibleSingle(m, t + k * duration) then
			return true
		end
	end
	return false
end

-- Emission intervals: [start, finish) split at the enable/disable times, keeping the enabled pieces.
local function emissionIntervals(m: Model): { { number } }
	local cuts: { number } = { m.start }
	for _, time in m.toggleTimes do
		if time > m.start and time < m.finish and time > cuts[#cuts] then
			table.insert(cuts, time)
		end
	end
	table.insert(cuts, m.finish)
	local out: { { number } } = {}
	for i = 1, #cuts - 1 do
		local a, b = cuts[i], cuts[i + 1]
		if b > a and enabledAt(m, a) then
			local last = out[#out]
			if last and last[2] == a then
				last[2] = b
			else
				table.insert(out, { a, b })
			end
		end
	end
	return out
end

local function buildModel(
	compiled: CompiledEffect,
	c: CompiledComponent,
	order: number,
	index: number,
	inherited: boolean
): Model
	local descriptor = Components.get(c.type) :: ComponentDescriptor
	local quality = compiled.quality
	local input = costInput(c, inherited)
	local cost = descriptor.estimateCost(input, quality)
	local tailTime = descriptor.tailTime
	local tail = if tailTime then tailTime(c) else 0
	if not isFinite(tail) or tail < 0 then
		tail = 0
	end
	local declaresToggle = Components.eventSpec(c.type, "disable") ~= nil
	local m: Model = {
		c = c,
		descriptor = descriptor,
		index = index,
		order = order,
		cost = cost,
		inheritedMotion = inherited and not Common.isMoving(c),
		start = c.startTime,
		finish = c.endTime,
		nonEmpty = c.endTime > c.startTime,
		tail = tail,
		hardOff = not declaresToggle,
		toggleTimes = {},
		toggleOn = {},
		emitting = false,
		lifetime = 0,
		rate = 0,
		rateTable = nil,
		rateStep = 0,
		intervals = {},
		emitTimes = {},
		emitPrefix = {},
		clearTimes = {},
		spriteArea = nil,
		peakLive = 0,
	}

	local emits: { { number } } = {}
	for _, action in compiled.schedule do
		if action.componentId ~= c.id or not isFinite(action.time) then
			continue
		end
		local kind = action.action
		if kind == "enable" or kind == "disable" then
			table.insert(m.toggleTimes, action.time)
			table.insert(m.toggleOn, kind == "enable")
		elseif kind == "clear" then
			table.insert(m.clearTimes, action.time)
		elseif kind == "emit" then
			table.insert(emits, { action.time, action.count or -1 })
		end
	end

	local lifetime = cost.maxLifetime
	if cost.emitters > 0 and isFinite(lifetime) and lifetime > 0 then
		m.emitting = true
		m.lifetime = lifetime
		m.rate = if isFinite(cost.continuousRate)
			then math.clamp(cost.continuousRate, 0, Constants.MAX_PARTICLE_RATE)
			else 0
		local rateTrack = c.tracks.rate
		if rateTrack and m.nonEmpty and Components.channelSpec(c.type, "rate") ~= nil then
			m.rateTable, m.rateStep = rateTable(rateTrack, m.start, m.finish)
		end
		m.intervals = emissionIntervals(m)
		-- Burst on activation and the default count of a count-less emit, read through the descriptor.
		local probe = table.clone(input)
		probe.events = {}
		local activationBurst = descriptor.estimateCost(probe, quality).burstCount
		probe.events = { { id = "analyzer-probe", time = 0, action = "emit" } }
		local defaultEmit = descriptor.estimateCost(probe, quality).burstCount - activationBurst
		local list: { { number } } = {}
		if m.nonEmpty and activationBurst > 0 then
			table.insert(list, { m.start, activationBurst })
		end
		for _, e in emits do
			local count = if e[2] < 0 then defaultEmit else e[2]
			count = math.clamp(math.floor(count + 0.5), 0, Constants.MAX_EMIT_COUNT)
			if count > 0 then
				table.insert(list, e)
				e[2] = count
			end
		end
		table.sort(list, function(a, b)
			return a[1] < b[1]
		end)
		local sum = 0
		for i, e in list do
			m.emitTimes[i] = e[1]
			sum += e[2]
			m.emitPrefix[i] = sum
		end
		local size: any = c.props.size
		if typeof(size) == "NumberSequence" then
			local s = maxSequenceValue(size :: NumberSequence) * c.scale * quality.sizeCompensation
			m.spriteArea = s * s
		end
	end
	return m
end

-- Times where the piecewise-linear model can peak (single-cycle time).
local function breakpoints(m: Model, out: { number })
	table.insert(out, m.start)
	table.insert(out, m.finish)
	if m.tail > 0 then
		table.insert(out, m.finish + m.tail)
	end
	for _, time in m.toggleTimes do
		table.insert(out, time)
	end
	if m.emitting then
		local L = m.lifetime
		table.insert(out, m.start + L)
		for _, interval in m.intervals do
			table.insert(out, interval[1] + L)
			table.insert(out, interval[2])
			table.insert(out, interval[2] + L)
		end
		for _, time in m.emitTimes do
			table.insert(out, time)
			table.insert(out, time + L)
		end
		for _, time in m.clearTimes do
			table.insert(out, time)
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Options
-- ─────────────────────────────────────────────────────────────────────────────

local function resolveLevel(value: any): QualityLevel
	if value == nil then
		return DEFAULT_QUALITY
	end
	if not Quality.isLevel(value) then
		error("Analyzer: options.quality must be Low, Medium or High, got " .. tostring(value), 3)
	end
	return value :: QualityLevel
end

local function resolveSampleRate(value: any): number
	if value == nil then
		return Analyzer.DEFAULT_SAMPLE_RATE
	end
	if not isFinite(value) or value <= 0 then
		error("Analyzer: options.sampleRate must be a finite number > 0, got " .. tostring(value), 3)
	end
	return math.min(value, Analyzer.MAX_SAMPLE_RATE)
end

local function resolveBudget(level: QualityLevel, overrides: any): Budget
	local base: any = Analyzer.BUDGETS[level]
	if type(base) ~= "table" then
		error("Analyzer: Analyzer.BUDGETS." .. level .. " is missing", 3)
	end
	local budget: { [string]: number } = {}
	for _, metric in METRICS do
		local v = base[metric.key]
		budget[metric.key] = if isFinite(v) and v >= 0 then v else INF
	end
	if overrides ~= nil then
		if type(overrides) ~= "table" then
			error("Analyzer: options.budgets must be a table, got " .. typeof(overrides), 3)
		end
		for key, v in overrides do
			if budget[key] == nil then
				error("Analyzer: options.budgets has no metric " .. tostring(key), 3)
			end
			if not isFinite(v) or v < 0 then
				error("Analyzer: options.budgets." .. tostring(key) .. " must be a finite number >= 0", 3)
			end
			budget[key] = v
		end
	end
	for key, v in budget do
		if v == INF then
			error("Analyzer: Analyzer.BUDGETS." .. level .. "." .. key .. " must be a finite number >= 0", 3)
		end
	end
	return (budget :: any) :: Budget
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Status, hints, diagnostics
-- ─────────────────────────────────────────────────────────────────────────────

local function statusOf(value: number, budget: number): (BudgetStatus, number?)
	if budget <= 0 then
		if value > 0 then
			return "over", nil
		end
		return "ok", nil
	end
	local ratio = value / budget
	if ratio > 1 then
		return "over", ratio
	elseif ratio > Analyzer.WARN_RATIO then
		return "warn", ratio
	end
	return "ok", ratio
end

local STATUS_RANK: { [string]: number } = { ok = 0, warn = 1, over = 2 }

local function quoted(c: CompiledComponent): string
	return "'" .. c.name .. "'"
end

local function hintFor(metric: string, m: Model, level: QualityLevel, continuousShare: boolean): string
	local name = quoted(m.c)
	local nextLevel = NEXT_LEVEL[level]
	local minQuality = if nextLevel then "set minQuality = " .. nextLevel .. " for " .. name else nil
	local c = m.c
	if metric == "liveParticles" then
		local text = if continuousShare
			then "reduce rate or lifetime on " .. name
			else "reduce burst/emit counts or lifetime on " .. name
		if level ~= "High" then
			text ..= " (qualityOverrides." .. level .. " changes this level only)"
		end
		return text
	elseif metric == "shadowLights" then
		return "set shadows = false on " .. name
	elseif metric == "lights" then
		if c.type ~= "light" then
			local own = "set light = false on " .. name
			return if minQuality then own .. " or " .. minQuality else own
		end
		return if minQuality then minQuality .. " or merge lights" else "remove or merge lights, e.g. " .. name
	end
	local primary: string
	if metric == "emitters" then
		primary = "merge emitters or shorten overlapping spans, e.g. " .. name
	elseif metric == "beams" then
		primary = if c.type == "lightning"
			then "reduce segments or branches on " .. name
			else "merge or shorten beams, e.g. " .. name
	elseif metric == "trails" then
		primary = "shorten the span or lifetime of " .. name
	elseif metric == "movingParts" then
		primary = "reduce counts/segments or stop moving " .. name .. " every frame"
	elseif metric == "propertyUpdates" then
		primary = "reduce animated tracks or counts on " .. name
	else
		primary = "reduce counts or segments on " .. name
	end
	return if minQuality then primary .. " or " .. minQuality else primary
end

-- ─────────────────────────────────────────────────────────────────────────────
-- analyze
-- ─────────────────────────────────────────────────────────────────────────────

local function definitionIndex(def: EffectDefinition): { [string]: number }
	local out: { [string]: number } = {}
	local list: any = def.components
	if type(list) == "table" then
		for i, c in list do
			if type(c) == "table" and type(c.id) == "string" and out[c.id] == nil then
				out[c.id] = i
			end
		end
	end
	return out
end

-- Analyses one quality level (see the header for the model).
function Analyzer.analyze(def: EffectDefinition, options: AnalyzeOptions?): AnalysisReport
	if type(def) ~= "table" then
		error("Analyzer.analyze: definition must be a table, got " .. typeof(def), 2)
	end
	local o: AnalyzeOptions = options or {}
	if type(o) ~= "table" then
		error("Analyzer.analyze: options must be a table, got " .. typeof(o), 2)
	end
	local level: QualityLevel = resolveLevel(o.quality)
	local sampleRate = resolveSampleRate(o.sampleRate)
	local budget = resolveBudget(level, o.budgets)
	local compileOptions: Compiler.CompileOptions = { quality = level, scale = o.scale }
	local compiled, compilerDiagnostics = Compiler.compile(def, compileOptions)
	local quality: QualityProfile = compiled.quality

	-- Models in compiled (topological) order.
	local indexOf = definitionIndex(def)
	local models: { Model } = {}
	local movesById: { [string]: boolean } = {} -- the component's world CFrame changes every frame
	for order, c in compiled.components do
		local parentId = c.parentId
		local inherited = parentId ~= nil and movesById[parentId] == true
		movesById[c.id] = inherited or movesItself(c)
		table.insert(models, buildModel(compiled, c, order, indexOf[c.id] or order, inherited))
	end

	-- Sample window and times.
	local duration = compiled.duration
	local loop = compiled.loop and duration > 0
	local window = if loop then duration else duration + compiled.maxTail
	local cycles = if loop then math.ceil(compiled.maxTail / duration - EPS) else 0
	local times: { number } = {}
	local steps = math.floor(window * sampleRate + EPS)
	for i = 0, steps do
		table.insert(times, i / sampleRate)
	end
	table.insert(times, window)
	local points: { number } = {}
	for _, m in models do
		breakpoints(m, points)
	end
	for _, p in points do
		if isFinite(p) then
			for k = 0, cycles do
				local t = p - k * duration
				if t >= 0 and t <= window then
					table.insert(times, t)
				end
			end
		end
	end
	table.sort(times)
	local samples: { number } = {}
	for _, t in times do
		local last = samples[#samples]
		if last == nil or t - last > EPS then
			table.insert(samples, t)
		end
	end

	-- Series.
	local values: { [string]: { number } } = {}
	for _, key in SERIES_KEYS do
		values[key] = table.create(#samples, 0)
	end
	for si, t in samples do
		local particles, activeCount, emitters, beams, trails, lights, shadows = 0, 0, 0, 0, 0, 0, 0
		local moving, updates, layers, overdraw = 0, 0, 0, 0
		for _, m in models do
			local cost = m.cost
			local n = liveAt(m, t, cycles, duration)
			local tailVisible = tailVisibleAt(m, t, cycles, duration)
			if n > m.peakLive then
				m.peakLive = n
			end
			particles += n
			local active = activeAt(m, t)
			local visible = active and enabledAt(m, t)
			if active then
				activeCount += 1
				moving += cost.movingParts
				updates += cost.propertyUpdates
			end
			if visible then
				beams += cost.beams
				lights += cost.lights
				shadows += cost.shadowLights
			end
			if visible or n > 0 then
				emitters += cost.emitters
			end
			if visible or tailVisible then
				trails += cost.trails
			end
			if m.emitting and m.spriteArea ~= nil then
				if n > 0 then
					layers += cost.transparentLayers
					overdraw += (m.spriteArea :: number) * n
				end
			elseif visible or tailVisible or n > 0 then
				layers += cost.transparentLayers
				overdraw += cost.overdrawWeight
			end
		end
		values.liveParticles[si] = particles
		values.activeComponents[si] = activeCount
		values.emitters[si] = emitters
		values.beams[si] = beams
		values.trails[si] = trails
		values.lights[si] = lights
		values.shadowLights[si] = shadows
		values.movingParts[si] = moving
		values.propertyUpdates[si] = updates
		values.transparentLayers[si] = layers
		values.overdrawWeight[si] = overdraw
	end

	local peaks: { [string]: Peak } = {}
	for _, key in SERIES_KEYS do
		local best, at = -INF, 0
		for si, v in values[key] do
			local r = clean(v)
			values[key][si] = r
			if r > best then
				best, at = r, samples[si]
			end
		end
		peaks[key] = { value = if best == -INF then 0 else best, time = clean(at) }
	end

	-- Totals.
	local totals: Totals = {
		components = #models,
		omitted = math.max(0, (if type(def.components) == "table" then #def.components else 0) - #models),
		instances = Analyzer.OVERHEAD.instances,
		parts = Analyzer.OVERHEAD.parts,
		attachments = 0,
		emitters = 0,
		beams = 0,
		trails = 0,
		lights = 0,
		shadowLights = 0,
		sounds = 0,
		animated = 0,
		procedural = 0,
	}
	for _, m in models do
		local cost = m.cost
		totals.instances += cost.instances
		totals.parts += cost.parts
		totals.attachments += cost.attachments
		totals.emitters += cost.emitters
		totals.beams += cost.beams
		totals.trails += cost.trails
		totals.lights += cost.lights
		totals.shadowLights += cost.shadowLights
		totals.sounds += cost.sounds
		if isAnimated(m.c) then
			totals.animated += 1
		end
		if m.descriptor.category == "Procedural" then
			totals.procedural += 1
		end
	end

	-- Contribution of a model to a budget metric at time t (nil: the per-component value of the breakdown).
	local function contribution(metric: string, m: Model, t: number?): number
		local cost: any = m.cost
		if metric == "liveParticles" then
			return if t == nil then m.peakLive else liveAt(m, t, cycles, duration)
		elseif metric == "instances" then
			return cost.instances
		end
		if t == nil then
			return if m.nonEmpty then cost[metric] else 0
		end
		local active = activeAt(m, t)
		local visible = active and enabledAt(m, t)
		if metric == "movingParts" or metric == "propertyUpdates" then
			return if active then cost[metric] else 0
		elseif metric == "emitters" then
			return if visible or liveAt(m, t, cycles, duration) > 0 then cost.emitters else 0
		elseif metric == "trails" then
			return if visible or tailVisibleAt(m, t, cycles, duration) then cost.trails else 0
		end
		return if visible then cost[metric] else 0
	end

	-- Metrics + diagnostics.
	local diagnostics: { Diagnostic } = {}
	for _, d in compilerDiagnostics do
		table.insert(diagnostics, d)
	end
	local metrics: { MetricResult } = {}
	local worst: BudgetStatus = "ok"
	for _, info in METRICS do
		local key = info.key
		local limit = (budget :: any)[key] :: number
		local value: number
		local time: number? = nil
		if info.total then
			value = (totals :: any)[key]
		else
			value = peaks[key].value
			time = peaks[key].time
		end
		local status: BudgetStatus, ratio: number? = statusOf(value, limit)
		local top: Model? = nil
		local topValue = 0
		if value > 0 then
			for _, m in models do
				local v = contribution(key, m, time)
				if v > topValue then
					top, topValue = m, v
				end
			end
		end
		local result: MetricResult = {
			key = key,
			label = info.label,
			value = value,
			budget = limit,
			ratio = if ratio then clean(ratio) else nil,
			status = status,
			time = time,
			componentId = if top then top.c.id else nil,
		}
		table.insert(metrics, result)
		if STATUS_RANK[status] > STATUS_RANK[worst] then
			worst = status
		end
		if status ~= "ok" then
			local at = if time then " at " .. Timeline.format(time) else ""
			local message: string
			if status == "over" then
				message = string.format(
					"%s%s: %s exceed the %s budget of %s (heuristic).",
					info.noun,
					at,
					formatNumber(value),
					level,
					formatNumber(limit)
				)
			else
				message = string.format(
					"%s%s: %s are at %d%% of the %s budget of %s (heuristic).",
					info.noun,
					at,
					formatNumber(value),
					math.floor((ratio :: number) * 100 + 0.5),
					level,
					formatNumber(limit)
				)
			end
			message = string.upper(string.sub(message, 1, 1)) .. string.sub(message, 2)
			local hint: string? = nil
			local path = ""
			local componentId: string? = nil
			if top then
				-- Which part dominates the top emitter's particles at the peak decides the advice.
				local continuous = time ~= nil
					and overCycles(continuousSingle, top, time, cycles, duration)
						>= overCycles(burstSingle, top, time, cycles, duration)
				hint = hintFor(key, top, level, continuous)
				path = "components[" .. top.index .. "]"
				componentId = top.c.id
			end
			local severity: Types.Severity = "info"
			if status == "over" then
				severity = "warning"
			end
			table.insert(diagnostics, {
				severity = severity,
				code = info.code,
				path = path,
				message = message,
				hint = hint,
				componentId = componentId,
			})
		end
	end

	-- Per-component breakdown.
	local reports: { ComponentReport } = {}
	for _, m in models do
		local shares: { [string]: number } = {}
		local score = 0
		for _, info in METRICS do
			local v = contribution(info.key, m, nil)
			if v > 0 then
				local limit = (budget :: any)[info.key] :: number
				local share = v / (if limit > 0 then limit else 1)
				shares[info.key] = clean(share)
				score += share
			end
		end
		local notes: { string } = {}
		local costNotes: { string } = m.cost.notes or {}
		for _, note in costNotes do
			table.insert(notes, note)
			table.insert(diagnostics, {
				severity = "info",
				code = "perf.note",
				path = "components[" .. m.index .. "]",
				message = quoted(m.c) .. ": " .. note,
				componentId = m.c.id,
			})
		end
		table.insert(reports, {
			id = m.c.id,
			name = m.c.name,
			type = m.c.type,
			category = m.descriptor.category,
			index = m.index,
			order = m.order,
			startTime = m.start,
			endTime = m.finish,
			tail = m.tail,
			cost = m.cost,
			inheritedMotion = m.inheritedMotion,
			animated = isAnimated(m.c),
			procedural = m.descriptor.category == "Procedural",
			peakParticles = clean(m.peakLive),
			shares = shares,
			score = clean(score),
			notes = notes,
		})
	end
	table.sort(reports, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.order < b.order
	end)

	for i, t in samples do
		samples[i] = clean(t)
	end
	local seriesTable: { [string]: { number } } = table.clone(values)
	seriesTable.time = samples
	local series = (seriesTable :: any) :: Series

	return {
		effectId = compiled.id,
		effectName = compiled.name,
		quality = quality.level,
		sampleRate = sampleRate,
		scale = compiled.scale,
		heuristic = true,
		notice = Analyzer.NOTICE,
		loop = loop,
		duration = duration,
		maxTail = clean(compiled.maxTail), -- NumberRange stores float32 (0.8 -> 0.800000011920929)
		window = clean(window),
		sampleCount = #samples,
		status = worst,
		peaks = (peaks :: any) :: Peaks,
		totals = totals,
		budget = budget,
		metrics = metrics,
		components = reports,
		diagnostics = diagnostics,
		series = series,
	}
end

-- Reports for Low, Medium and High (same options otherwise; options.quality is ignored).
function Analyzer.compareQualities(def: EffectDefinition, options: AnalyzeOptions?): QualityComparison
	local o: AnalyzeOptions = options or {}
	if type(o) ~= "table" then
		error("Analyzer.compareQualities: options must be a table, got " .. typeof(o), 2)
	end
	local out: { [string]: AnalysisReport } = {}
	for _, level: QualityLevel in LEVELS do
		local levelOptions: AnalyzeOptions = table.clone(o)
		levelOptions.quality = level
		out[level] = Analyzer.analyze(def, levelOptions)
	end
	return (out :: any) :: QualityComparison
end

return Analyzer
