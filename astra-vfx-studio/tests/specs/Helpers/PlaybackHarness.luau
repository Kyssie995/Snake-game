--!strict
--[[
	PlaybackHarness — shared helpers for the Player / Scheduler / Pool / Runtime / Net specs.

	  local H = use("Tests.Specs.Helpers.PlaybackHarness").new(use, ctx)
	  local compiled = H:compile(def, { quality = "High" })     -- Validation must pass (raises with the errors)
	  local p = H:player(def, compileOptions?, playerOptions?)  -- { player, built, compiled, parent }
	  H:steps(p.player, n, dt)                                 -- n frames; returns the list of times
	  H:snapshot(container)                                    -- property values of every descendant
	  H:cleanup()                                              -- destroys everything created by the harness
	                                                           -- and restores the shared fake logs

	Definitions are plain Luau tables (or JSON text decoded with Core/Json) in schema version 1. The emit / clear /
	sound logs of ctx.fakes are shared by every spec (some specs assert global totals), so cleanup() truncates
	them back to the length they had when the harness was created.
]]

local Harness = {}
Harness.__index = Harness

-- Properties captured by snapshot(), per class (checked with IsA, first match wins).
local SNAPSHOT_PROPS: { { any } } = {
	{ "BasePart", { "CFrame", "Size", "Transparency", "Color", "Material" } },
	{ "Attachment", { "CFrame" } },
	{
		"ParticleEmitter",
		{
			"Enabled",
			"Rate",
			"Transparency",
			"Color",
			"Size",
			"Acceleration",
			"Brightness",
			"LightEmission",
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
	{ "Light", { "Enabled", "Brightness", "Range", "Color", "Shadows" } },
	{ "Sound", { "Volume", "PlaybackSpeed" } },
	{ "SpecialMesh", { "Scale", "Offset", "VertexColor" } },
}

function Harness.new(use: (string) -> any, ctx: any)
	local self = setmetatable({}, Harness) :: any
	self.ctx = ctx
	self.Json = use("AstraVFX.Core.Json")
	self.Validation = use("AstraVFX.Core.Validation")
	self.Compiler = use("AstraVFX.Core.Compiler")
	self.Builder = use("AstraVFX.Core.Builder")
	self.Player = use("AstraVFX.Core.Player")
	self.created = {} :: { any }
	self.players = {} :: { any }
	local fakes = ctx.fakes
	self.marks = if fakes then { emits = #fakes.emits, clears = #fakes.clears, sounds = #fakes.sounds } else nil
	return self
end

-- Decodes JSON text with Core/Json (raises on syntax errors).
function Harness.decode(self: any, text: string): any
	local ok, value = self.Json.decode(text)
	assert(ok, "JSON: " .. tostring(value))
	return value
end

-- Validates (must pass) and compiles a definition.
function Harness.compile(self: any, def: any, options: any?): any
	local result = self.Validation.validate(def)
	if not result.ok then
		local lines = {}
		for _, d in result.errors do
			table.insert(lines, d.code .. " " .. d.path .. ": " .. d.message)
		end
		error("test definition is invalid:\n" .. table.concat(lines, "\n"), 2)
	end
	local compiled = self.Compiler.compile(def, options or { quality = "High" })
	return compiled
end

-- A fresh Folder that cleanup() destroys (parented under `parent` when given).
function Harness.folder(self: any, name: string?, parent: Instance?): Folder
	local folder = Instance.new("Folder")
	folder.Name = name or "PlaybackHarness"
	folder.Parent = parent
	table.insert(self.created, folder)
	return folder
end

-- Compiles, builds (into a fresh folder unless buildOptions.parent is given) and creates a Player.
function Harness.player(self: any, def: any, compileOptions: any?, playerOptions: any?, buildOptions: any?): any
	local compiled = self:compile(def, compileOptions)
	local bo: any = buildOptions or {}
	local parent = bo.parent or self:folder("PlayerParent")
	local built = self.Builder.build(compiled, { parent = parent, isPreview = bo.isPreview, viewport = bo.viewport })
	local player = self.Player.new(compiled, built, playerOptions)
	table.insert(self.players, player)
	return { player = player, built = built, compiled = compiled, parent = parent }
end

-- Steps `n` frames of `dt`; returns the player time after every frame.
function Harness.steps(_self: any, player: any, n: number, dt: number): { number }
	local times = {}
	for _ = 1, n do
		player:step(dt)
		table.insert(times, player.time)
	end
	return times
end

-- Emit log entries recorded since `mark` (an index into ctx.fakes.emits), optionally for one instance.
function Harness.emitsSince(self: any, mark: number, instance: any?): { number }
	local out = {}
	local emits = self.ctx.fakes.emits
	for i = mark + 1, #emits do
		local e = emits[i]
		if instance == nil or e.instance == instance then
			table.insert(out, e.count)
		end
	end
	return out
end

function Harness.emitMark(self: any): number
	return #self.ctx.fakes.emits
end

-- Property values of every descendant of `container`, keyed by "<index>:<class>:<name>" (creation order).
function Harness.snapshot(_self: any, container: Instance): { [string]: { [string]: any } }
	local out: { [string]: { [string]: any } } = {}
	for i, inst in container:GetDescendants() do
		local props: { [string]: any } = {}
		for _, entry in SNAPSHOT_PROPS do
			if inst:IsA(entry[1]) then
				for _, name in entry[2] do
					local ok, value = pcall(function()
						return (inst :: any)[name]
					end)
					if ok then
						props[name] = value
					end
				end
				break
			end
		end
		out[i .. ":" .. inst.ClassName .. ":" .. inst.Name] = props
	end
	return out
end

-- Instances below `container` tagged with a component id (Builder attribute AstraComponent).
function Harness.owned(_self: any, container: Instance, id: string): { Instance }
	local out = {}
	for _, inst in container:GetDescendants() do
		if inst:GetAttribute("AstraComponent") == id then
			table.insert(out, inst)
		end
	end
	return out
end

function Harness.cleanup(self: any)
	for _, player in self.players do
		pcall(function()
			player:destroy()
		end)
	end
	table.clear(self.players)
	for i = #self.created, 1, -1 do
		pcall(function()
			self.created[i]:Destroy()
		end)
	end
	table.clear(self.created)
	local fakes = self.ctx.fakes
	local marks = self.marks
	if fakes and marks then
		while #fakes.emits > marks.emits do
			table.remove(fakes.emits)
		end
		while #fakes.clears > marks.clears do
			table.remove(fakes.clears)
		end
		while #fakes.sounds > marks.sounds do
			table.remove(fakes.sounds)
		end
	end
end

return Harness
