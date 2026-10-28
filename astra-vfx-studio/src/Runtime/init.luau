--!strict
--[[
	AstraVFX — public runtime API (ModuleScript "AstraVFX"; docs/ARCHITECTURE.md §5.3, docs/MODULE_CONTRACTS.md §19).

	  local AstraVFX = require(ReplicatedStorage.AstraVFX)
	  AstraVFX.Register(source) -> string | { string }   definition table, JSON text, ModuleScript returning one
	                                                     of those, StringValue with JSON text, or a Folder of them
	  AstraVFX.Unregister(name) -> boolean ; AstraVFX.IsRegistered(name) -> boolean ; AstraVFX.GetNames() -> { string }
	  AstraVFX.Play(name, options?) -> Handle            errors on unknown names / bad options
	  AstraVFX.TryPlay(name, options?) -> (Handle?, string?)
	  AstraVFX.Preload(name, options?) -> number         warms the pool (options: Count = 1, Quality, Scale, Seed,
	                                                     Palette)
	  AstraVFX.SetQuality(level) / GetQuality()          default quality of Play ("Auto" = Quality.detect() per Play)
	  AstraVFX.StopAll(immediate?) ; AstraVFX.ActiveCount() -> number
	  AstraVFX.SetUpdateEvent("Heartbeat" | "PreRender")   Core/Scheduler event (PreRender only on clients)
	  AstraVFX.Validate(definitionOrJson) -> (ValidationResult, EffectDefinition?)   migrate + validate, no register
	  AstraVFX.Version                                   Constants.VERSION
	  AstraVFX.Net                                       optional server -> client replication (Net.luau)

	Names: an effect is found by its id, its name, or (for instance sources) the instance name. Registering a
	definition with an id that already exists replaces it (its compiled cache and pooled copies are dropped).
	Registration migrates (Core/Migration) and validates (Core/Validation); a definition with errors raises an
	error with a readable diagnostic summary (warnings are accepted silently — use Validate to see them).

	Lazy auto-registration: children of `script.Effects` (ModuleScripts returning a definition table or JSON text,
	StringValues with JSON text, Folders of those) are registered the first time a name is looked up that is not
	registered yet; later misses register only children that were not seen before. A broken child is reported
	with warn() and skipped (one bad effect never breaks the others). Effect modules must not yield.

	PlayOptions (Types.PlayOptions; unknown keys are errors):
	  CFrame | Position     effect origin (default identity); with Attach this is the fallback while the target is
	                        missing (e.g. not streamed in)
	  Attach                BasePart | Attachment | Model to follow every frame; Offset applies on top of it
	  Offset                CFrame applied on top of Attach / CFrame
	  Parent                container parent (default Workspace via Core/Env). On clients keep effects under
	                        Workspace (or a client-created folder in it), never under server-owned instances that
	                        StreamingEnabled can remove (docs/ROBLOX_API_CONSTRAINTS.md ST-2/ST-3).
	  Scale                 > 0, clamped to Constants.MAX_SCALE (compile option)
	  Quality               "Low" | "Medium" | "High" | "Auto" (default: SetQuality, initially "Auto")
	  TimeScale             >= 0, clamped to Constants.MAX_TIME_SCALE (multiplies the definition's timeScale)
	  Seed                  finite number (compile option; a new seed compiles a new variant — leave it nil to hit
	                        the cache)
	  Loop                  boolean (default: the definition's loop)
	  Palette               { [name]: Color3 } palette overrides (compile option)
	  OnEvent               (name) -> () for marker / component / graph "fire" events
	  Autoplay              default true; false = built and posed at t = 0 but paused until handle:Resume()

	Play never yields: lookup (incl. lazy registration) -> compile (cached by Compiler.key with the content hash
	computed once per registration; at most 64 cached variants, the oldest is dropped together with its pooled
	copies) -> a pooled copy (Core/Pool, key = cache key) or Builder.build -> Player.new + start ->
	Scheduler.add. The copy goes back to the pool when the effect ends (finish, Stop, Destroy) as long as its cache
	entry still exists and its container is still parented (a container removed from the outside — cleared
	folder, destroyed parent — is never pooled); otherwise it is destroyed.

	Handle: Stop(fade?), Destroy(), Pause(), Resume(), SetTimeScale(n), SetCFrame(cf), SetLoop(b), Seek(t),
	Fire(name), GetTime(), GetState(), IsPlaying() (true until stopped / finished / destroyed, also while paused),
	Finished (Signal, fires once with "finished" | "destroyed"), Event (Signal(name)), Name, Id.
]]

local Builder = require(script.Core.Builder)
local Compiler = require(script.Core.Compiler)
local Constants = require(script.Core.Constants)
local Env = require(script.Core.Env)
local Migration = require(script.Core.Migration)
local Net = require(script.Net)
local Player = require(script.Core.Player)
local Pool = require(script.Core.Pool)
local Quality = require(script.Core.Quality)
local Scheduler = require(script.Core.Scheduler)
local Types = require(script.Core.Types)
local Validation = require(script.Core.Validation)

type EffectDefinition = Types.EffectDefinition
type CompiledEffect = Types.CompiledEffect
type Diagnostic = Types.Diagnostic
type ValidationResult = Types.ValidationResult
type PlayOptions = Types.PlayOptions
type QualityLevel = Types.QualityLevel
type PlayerState = Types.PlayerState
type Player = Player.Player
type BuiltEffect = Builder.BuiltEffect

type Entry = {
	id: string,
	name: string,
	def: EffectDefinition,
	hash: string,
	aliases: { string },
	keys: { [string]: boolean }, -- compile cache keys of this effect
}

type CacheEntry = { compiled: CompiledEffect, id: string }

local AstraVFX = {}

AstraVFX.Version = Constants.VERSION
AstraVFX.Net = Net

local MAX_CACHE = 64
local MAX_SUMMARY_LINES = 12
local INF = math.huge

local registry: { [string]: Entry } = {} -- by id
local aliases: { [string]: string } = {} -- name / instance name -> id
local seenSources: { [Instance]: boolean } = {}
local cache: { [string]: CacheEntry } = {}
local cacheOrder: { string } = {}
local defaultQuality: QualityLevel | "Auto" = "Auto"
local live: { [any]: boolean } = {} -- handles

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= INF and x ~= -INF
end

local function describe(v: any): string
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return typeof(v)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Diagnostics summary
-- ─────────────────────────────────────────────────────────────────────────────

local function formatDiagnostic(d: Diagnostic): string
	local path = if d.path ~= "" then d.path .. ": " else ""
	return d.severity .. " " .. d.code .. " " .. path .. d.message
end

local function summary(label: string, diagnostics: { Diagnostic }): string
	local errors: { Diagnostic } = {}
	for _, d in diagnostics do
		if d.severity == "error" then
			table.insert(errors, d)
		end
	end
	local lines = { label .. " (" .. #errors .. (if #errors == 1 then " error" else " errors") .. "):" }
	for i, d in errors do
		if i > MAX_SUMMARY_LINES then
			table.insert(lines, "  ... and " .. (#errors - MAX_SUMMARY_LINES) .. " more")
			break
		end
		table.insert(lines, "  " .. formatDiagnostic(d))
	end
	return table.concat(lines, "\n")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Registry
-- ─────────────────────────────────────────────────────────────────────────────

local function find(name: string): Entry?
	local entry = registry[name]
	if entry then
		return entry
	end
	local id = aliases[name]
	return if id then registry[id] else nil
end

local function dropCacheKey(key: string)
	if cache[key] == nil then
		return
	end
	cache[key] = nil
	local index = table.find(cacheOrder, key)
	if index then
		table.remove(cacheOrder, index)
	end
	Pool.clear(key)
end

local function dropEntry(entry: Entry)
	for key in entry.keys do
		dropCacheKey(key)
	end
	table.clear(entry.keys)
	for _, alias in entry.aliases do
		if aliases[alias] == entry.id then
			aliases[alias] = nil
		end
	end
	registry[entry.id] = nil
end

-- Migrates + validates `raw` (table or JSON text). Returns the definition or raises with a summary.
local function prepare(raw: any, label: string): EffectDefinition
	local def, migration = Migration.migrate(raw)
	if def == nil then
		error(summary("AstraVFX.Register: " .. label .. " is not an effect definition", migration), 0)
	end
	local result = Validation.validate(def)
	if not result.ok then
		local name = if type(def.name) == "string" then def.name else tostring(def.id)
		error(summary("AstraVFX.Register: effect " .. string.format("%q", name) .. " is invalid", result.errors), 0)
	end
	return def
end

local function addDefinition(raw: any, label: string, alias: string?): string
	local def = prepare(raw, label)
	local existing = registry[def.id]
	if existing then
		dropEntry(existing)
	end
	local entry: Entry = {
		id = def.id,
		name = def.name,
		def = def,
		hash = Compiler.contentHash(def),
		aliases = {},
		keys = {},
	}
	registry[def.id] = entry
	local function addAlias(name: string?)
		if type(name) == "string" and name ~= "" and name ~= def.id and aliases[name] ~= def.id then
			aliases[name] = def.id
			table.insert(entry.aliases, name)
		end
	end
	addAlias(def.name)
	addAlias(alias)
	return def.name
end

local function sortedChildren(folder: Instance): { Instance }
	local children = folder:GetChildren()
	table.sort(children, function(a: Instance, b: Instance): boolean
		return a.Name < b.Name
	end)
	return children
end

local registerInstance: (inst: Instance, out: { string }) -> ()

registerInstance = function(inst: Instance, out: { string })
	if inst:IsA("ModuleScript") then
		local value: any = (require :: any)(inst)
		if type(value) ~= "table" and type(value) ~= "string" then
			error(
				"AstraVFX.Register: "
					.. inst:GetFullName()
					.. " must return a definition table or JSON text, got "
					.. typeof(value),
				0
			)
		end
		table.insert(out, addDefinition(value, inst:GetFullName(), inst.Name))
	elseif inst:IsA("StringValue") then
		table.insert(out, addDefinition((inst :: StringValue).Value, inst:GetFullName(), inst.Name))
	elseif inst:IsA("Folder") or inst:IsA("Configuration") then
		for _, child in sortedChildren(inst) do
			registerInstance(child, out)
		end
	else
		error("AstraVFX.Register: cannot register a " .. inst.ClassName .. " (" .. inst:GetFullName() .. ")", 0)
	end
end

-- Registers every child of script.Effects not seen before. Returns true when something new was registered.
local function scanEffects(): boolean
	local folder = script:FindFirstChild("Effects")
	if folder == nil then
		return false
	end
	local added = false
	for _, child in sortedChildren(folder) do
		if not seenSources[child] then
			seenSources[child] = true
			local out: { string } = {}
			local ok, err = pcall(registerInstance :: any, child, out)
			if not ok then
				warn("[AstraVFX] skipped effect " .. child:GetFullName() .. ": " .. tostring(err))
			elseif #out > 0 then
				added = true
			end
		end
	end
	return added
end

local function lookup(name: any): Entry?
	if type(name) ~= "string" then
		return nil
	end
	local entry = find(name)
	if entry then
		return entry
	end
	if scanEffects() then
		return find(name)
	end
	return nil
end

-- Registers a definition (table / JSON text), a ModuleScript or StringValue holding one, or a Folder of those.
-- Returns the effect name (a list of names for folders). Invalid definitions raise an error with a summary.
function AstraVFX.Register(source: any): string | { string }
	if type(source) == "table" or type(source) == "string" then
		return addDefinition(source, "definition", nil)
	elseif typeof(source) == "Instance" then
		local out: { string } = {}
		registerInstance(source, out)
		if source:IsA("ModuleScript") or source:IsA("StringValue") then
			return out[1]
		end
		return out
	end
	error("AstraVFX.Register: expected a definition table, JSON text or Instance, got " .. typeof(source), 2)
end

-- Removes a registered effect (by id or name). Its cached compiles and pooled copies are dropped.
function AstraVFX.Unregister(name: string): boolean
	local entry = if type(name) == "string" then find(name) else nil
	if entry == nil then
		return false
	end
	dropEntry(entry)
	return true
end

-- True when `name` (id, name or instance name) is a registered effect (after lazy registration).
function AstraVFX.IsRegistered(name: string): boolean
	return lookup(name) ~= nil
end

-- Names of every registered effect, sorted.
function AstraVFX.GetNames(): { string }
	scanEffects()
	local out: { string } = {}
	for _, entry in registry do
		table.insert(out, entry.name)
	end
	table.sort(out)
	return out
end

-- Migrates and validates a definition without registering it. Returns (result, migrated definition or nil).
function AstraVFX.Validate(source: any): (ValidationResult, EffectDefinition?)
	local def, migration = Migration.migrate(source)
	if def == nil then
		local errors: { Diagnostic } = {}
		local infos: { Diagnostic } = {}
		local warnings: { Diagnostic } = {}
		for _, d in migration do
			if d.severity == "error" then
				table.insert(errors, d)
			elseif d.severity == "warning" then
				table.insert(warnings, d)
			else
				table.insert(infos, d)
			end
		end
		return { ok = false, errors = errors, warnings = warnings, infos = infos }, nil
	end
	local result = Validation.validate(def)
	for _, d in migration do
		if d.severity == "warning" then
			table.insert(result.warnings, d)
		elseif d.severity == "info" then
			table.insert(result.infos, d)
		end
	end
	return result, def
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Options + compile cache
-- ─────────────────────────────────────────────────────────────────────────────

local OPTION_KEYS: { [string]: boolean } = {
	CFrame = true,
	Position = true,
	Attach = true,
	Offset = true,
	Parent = true,
	Scale = true,
	Quality = true,
	TimeScale = true,
	Seed = true,
	Loop = true,
	Palette = true,
	OnEvent = true,
	Autoplay = true,
}

local QUALITY_NAMES: { [string]: boolean } = { Low = true, Medium = true, High = true, Auto = true }

local function optionError(fn: string, message: string): never
	error("AstraVFX." .. fn .. ": " .. message, 0)
end

local function checkPlayOptions(fn: string, options: any): PlayOptions
	if options == nil then
		return {}
	end
	if type(options) ~= "table" then
		optionError(fn, "options must be a table, got " .. typeof(options))
	end
	for key in options do
		if type(key) ~= "string" or not OPTION_KEYS[key] then
			optionError(fn, "unknown option " .. describe(key))
		end
	end
	local o: any = options
	if o.CFrame ~= nil and typeof(o.CFrame) ~= "CFrame" then
		optionError(fn, "CFrame must be a CFrame, got " .. describe(o.CFrame))
	end
	if o.Position ~= nil and typeof(o.Position) ~= "Vector3" then
		optionError(fn, "Position must be a Vector3, got " .. describe(o.Position))
	end
	if o.Offset ~= nil and typeof(o.Offset) ~= "CFrame" then
		optionError(fn, "Offset must be a CFrame, got " .. describe(o.Offset))
	end
	if o.Attach ~= nil then
		local attach = o.Attach
		if
			typeof(attach) ~= "Instance"
			or not (attach:IsA("BasePart") or attach:IsA("Attachment") or attach:IsA("PVInstance"))
		then
			optionError(fn, "Attach must be a BasePart, Attachment or Model, got " .. describe(attach))
		end
	end
	if o.Parent ~= nil and typeof(o.Parent) ~= "Instance" then
		optionError(fn, "Parent must be an Instance, got " .. describe(o.Parent))
	end
	if o.Scale ~= nil and not (isFinite(o.Scale) and o.Scale > 0) then
		optionError(fn, "Scale must be a finite number > 0, got " .. tostring(o.Scale))
	end
	if o.Quality ~= nil and not (type(o.Quality) == "string" and QUALITY_NAMES[o.Quality]) then
		optionError(fn, 'Quality must be "Low", "Medium", "High" or "Auto", got ' .. describe(o.Quality))
	end
	if o.TimeScale ~= nil and not (isFinite(o.TimeScale) and o.TimeScale >= 0) then
		optionError(fn, "TimeScale must be a finite number >= 0, got " .. tostring(o.TimeScale))
	end
	if o.Seed ~= nil and not isFinite(o.Seed) then
		optionError(fn, "Seed must be a finite number, got " .. tostring(o.Seed))
	end
	if o.Loop ~= nil and type(o.Loop) ~= "boolean" then
		optionError(fn, "Loop must be a boolean, got " .. describe(o.Loop))
	end
	if o.Palette ~= nil and type(o.Palette) ~= "table" then
		optionError(fn, "Palette must be a table of Color3 values, got " .. describe(o.Palette))
	end
	if o.OnEvent ~= nil and type(o.OnEvent) ~= "function" then
		optionError(fn, "OnEvent must be a function, got " .. describe(o.OnEvent))
	end
	if o.Autoplay ~= nil and type(o.Autoplay) ~= "boolean" then
		optionError(fn, "Autoplay must be a boolean, got " .. describe(o.Autoplay))
	end
	return o
end

local function resolveQuality(level: any): QualityLevel
	local chosen: any = if level ~= nil then level else defaultQuality
	if chosen == "Auto" then
		return Quality.detect()
	end
	return chosen
end

type Variant = { key: string, compiled: CompiledEffect }

-- Compiled effect for (entry, options), cached by Compiler.key.
local function variant(entry: Entry, o: any): Variant
	local compileOptions: Compiler.CompileOptions = {
		quality = resolveQuality(o.Quality),
		scale = if o.Scale ~= nil then math.min(o.Scale, Constants.MAX_SCALE) else nil,
		palette = o.Palette,
		seed = o.Seed,
	}
	local key = Compiler.key(entry.def, compileOptions, entry.hash)
	local hit = cache[key]
	if hit then
		return { key = key, compiled = hit.compiled }
	end
	local compiled = Compiler.compile(entry.def, compileOptions)
	cache[key] = { compiled = compiled, id = entry.id }
	table.insert(cacheOrder, key)
	entry.keys[key] = true
	while #cacheOrder > MAX_CACHE do
		local oldest = cacheOrder[1]
		local owner = registry[cache[oldest].id]
		if owner then
			owner.keys[oldest] = nil
		end
		dropCacheKey(oldest)
	end
	return { key = key, compiled = compiled }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Handle
-- ─────────────────────────────────────────────────────────────────────────────

local Handle = {}
Handle.__index = Handle

type HandleData = {
	Name: string,
	Id: string,
	Finished: any,
	Event: any,
	_player: Player,
}

export type Handle = typeof(setmetatable({} :: HandleData, Handle))

-- Graceful stop: emission stops, live particles finish, then the copy is cleaned up.
function Handle.Stop(self: Handle, fade: number?)
	self._player:stop(fade)
end

-- Immediate removal.
function Handle.Destroy(self: Handle)
	local player = self._player
	player:destroy()
	Scheduler.remove(player)
	live[self] = nil
end

function Handle.Pause(self: Handle)
	self._player:pause()
end

function Handle.Resume(self: Handle)
	self._player:resume()
end

function Handle.SetTimeScale(self: Handle, n: number)
	self._player:setTimeScale(n)
end

function Handle.SetCFrame(self: Handle, cf: CFrame)
	self._player:setCFrame(cf)
end

function Handle.SetLoop(self: Handle, loop: boolean)
	self._player:setLoop(loop)
end

function Handle.Seek(self: Handle, t: number)
	self._player:seek(t)
end

-- Triggers the graph's OnEvent(name) flows at the current effect time.
function Handle.Fire(self: Handle, name: string)
	self._player:fire(name)
end

function Handle.GetTime(self: Handle): number
	return self._player.time
end

function Handle.GetState(self: Handle): PlayerState
	return self._player.state
end

-- True until the effect is stopped, finished or destroyed (also while paused).
function Handle.IsPlaying(self: Handle): boolean
	local state = self._player.state
	return state == "playing" or state == "paused" or state == "idle"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Play
-- ─────────────────────────────────────────────────────────────────────────────

local function defaultParent(): Instance
	return Env.getService("Workspace")
end

-- False when the copy's container was removed from the outside while it played (a cleared folder, a destroyed
-- parent such as a respawned character — Roblox then locks Parent, so the pool could not reset / re-parent it):
-- such a copy is destroyed instead of pooled. pcall: Lune raises on destroyed Instances.
local function stillParented(built: BuiltEffect): boolean
	local ok, parent = pcall(function(): Instance?
		return built.container.Parent
	end)
	return ok and parent ~= nil
end

local function play(name: any, options: any): Handle
	local o = checkPlayOptions("Play", options)
	local entry = lookup(name)
	if entry == nil then
		error("AstraVFX.Play: unknown effect " .. describe(name), 0)
	end
	local v = variant(entry, o)
	local key = v.key
	local parent: Instance = o.Parent or defaultParent()
	local built: BuiltEffect? = Pool.acquire(key)
	if built then
		local copy = built :: BuiltEffect
		local ok = pcall(function()
			copy.container.Parent = parent
		end)
		if not ok then
			copy:destroy()
			built = nil
		end
	end
	if built == nil then
		built = Builder.build(v.compiled, { parent = parent })
	end
	local copy = built :: BuiltEffect
	local cframe: CFrame? = o.CFrame
	if cframe == nil and o.Position ~= nil then
		cframe = CFrame.new(o.Position)
	end
	local player = Player.new(copy.effect, copy, {
		cframe = cframe,
		attach = o.Attach,
		offset = o.Offset,
		timeScale = if o.TimeScale ~= nil then math.min(o.TimeScale, Constants.MAX_TIME_SCALE) else nil,
		loop = o.Loop,
		onEvent = o.OnEvent,
		release = function(b: BuiltEffect): boolean
			return cache[key] ~= nil and stillParented(b) and Pool.release(key, b)
		end,
	})
	local handle: Handle = setmetatable({
		Name = v.compiled.name,
		Id = v.compiled.id,
		Finished = player.finished,
		Event = player.event,
		_player = player,
	}, Handle)
	live[handle] = true
	player.finished:Connect(function()
		live[handle] = nil
		Scheduler.remove(player)
	end)
	player:start()
	if o.Autoplay == false then
		player:pause()
	end
	Scheduler.add(player)
	return handle
end

-- Plays a registered effect. Errors on unknown names and invalid options. Never yields.
function AstraVFX.Play(name: string, options: PlayOptions?): Handle
	return play(name, options)
end

-- Like Play, but returns (nil, message) instead of raising.
function AstraVFX.TryPlay(name: string, options: PlayOptions?): (Handle?, string?)
	local ok, result = pcall(play, name, options)
	if ok then
		return result, nil
	end
	return nil, tostring(result)
end

export type PreloadOptions = {
	Count: number?,
	Quality: (QualityLevel | "Auto")?,
	Scale: number?,
	Seed: number?,
	Palette: { [string]: Color3 }?,
}

-- Builds pooled copies of an effect variant ahead of time. Returns the number of copies built.
function AstraVFX.Preload(name: string, options: PreloadOptions?): number
	local o: any = options or {}
	if type(o) ~= "table" then
		error("AstraVFX.Preload: options must be a table, got " .. typeof(o), 2)
	end
	for key in o do
		if key ~= "Count" and key ~= "Quality" and key ~= "Scale" and key ~= "Seed" and key ~= "Palette" then
			error("AstraVFX.Preload: unknown option " .. describe(key), 2)
		end
	end
	local count: any = if o.Count == nil then 1 else o.Count
	if not isFinite(count) or count < 0 or count % 1 ~= 0 then
		error("AstraVFX.Preload: Count must be a whole number >= 0, got " .. tostring(count), 2)
	end
	checkPlayOptions("Preload", { Quality = o.Quality, Scale = o.Scale, Seed = o.Seed, Palette = o.Palette })
	local entry = lookup(name)
	if entry == nil then
		error("AstraVFX.Preload: unknown effect " .. describe(name), 2)
	end
	local v = variant(entry, o)
	return Pool.prewarm(v.key, function(): BuiltEffect
		return Builder.build(v.compiled)
	end, count)
end

-- Default quality for Play ("Auto" resolves with Quality.detect() on every Play).
function AstraVFX.SetQuality(level: QualityLevel | "Auto")
	if type(level) ~= "string" or not QUALITY_NAMES[level] then
		error('AstraVFX.SetQuality: expected "Low", "Medium", "High" or "Auto", got ' .. describe(level), 2)
	end
	defaultQuality = level
end

function AstraVFX.GetQuality(): QualityLevel | "Auto"
	return defaultQuality
end

-- Stops every effect started through Play (gracefully; immediately with `immediate = true`).
function AstraVFX.StopAll(immediate: boolean?)
	local handles: { Handle } = {}
	for handle in live do
		table.insert(handles, handle)
	end
	for _, handle in handles do
		if immediate then
			handle:Destroy()
		else
			handle:Stop()
		end
	end
end

-- Number of effects started through Play that have not ended yet.
function AstraVFX.ActiveCount(): number
	local n = 0
	for _ in live do
		n += 1
	end
	return n
end

-- Selects the Scheduler's RunService event ("Heartbeat" default; "PreRender" only on clients).
function AstraVFX.SetUpdateEvent(name: Scheduler.EventName)
	Scheduler.setEventName(name)
end

-- Test / plugin hook: destroys every running effect, empties the pool, the compile cache and the registry.
function AstraVFX._reset()
	AstraVFX.StopAll(true)
	for key in cache do
		Pool.clear(key)
	end
	table.clear(cache)
	table.clear(cacheOrder)
	table.clear(registry)
	table.clear(aliases)
	table.clear(seenSources)
	defaultQuality = "Auto"
end

-- Diagnostics: number of cached compiled variants.
function AstraVFX._cacheSize(): number
	return #cacheOrder
end

Net._bind(AstraVFX)

return AstraVFX
