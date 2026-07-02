--!strict
-- StatusEffects: server-side tickers for Burn, Chill, Vulnerable, Slow.
-- Effects are attribute-backed so clients can drive VFX from attribute changes
-- without any extra replication.

local StatusEffects = {}

type BurnEntry = { expiresAt: number, dps: number, source: Player? }
type ChillEntry = { stacks: number, expiresAt: number }
type TimedEntry = { expiresAt: number, magnitude: number }

local burns: { [Model]: BurnEntry } = {}
local chills: { [Model]: ChillEntry } = {}
local vulnerable: { [Model]: TimedEntry } = {}
local slows: { [Model]: TimedEntry } = {}

-- Damage callback is injected by CombatService to avoid circular requires.
local dealDamage: ((victim: Model, amount: number, source: Player?) -> ())? = nil
function StatusEffects.BindDamageCallback(fn: (victim: Model, amount: number, source: Player?) -> ())
	dealDamage = fn
end

local freezeCallback: ((victim: Model, duration: number) -> ())? = nil
function StatusEffects.BindFreezeCallback(fn: (victim: Model, duration: number) -> ())
	freezeCallback = fn
end

function StatusEffects.ApplyBurn(victim: Model, dps: number, duration: number, source: Player?)
	burns[victim] = { expiresAt = os.clock() + duration, dps = dps, source = source }
	victim:SetAttribute("Burning", true)
end

function StatusEffects.ApplyChill(victim: Model, stacks: number, duration: number)
	local entry = chills[victim]
	local newStacks = (entry and os.clock() < entry.expiresAt) and entry.stacks + stacks or stacks
	if newStacks >= 3 then
		chills[victim] = nil
		victim:SetAttribute("ChillStacks", 0)
		if freezeCallback then
			freezeCallback(victim, 1.0)
		end
	else
		chills[victim] = { stacks = newStacks, expiresAt = os.clock() + duration }
		victim:SetAttribute("ChillStacks", newStacks)
	end
end

function StatusEffects.ApplyVulnerable(victim: Model, mult: number, duration: number)
	vulnerable[victim] = { expiresAt = os.clock() + duration, magnitude = mult }
	victim:SetAttribute("Vulnerable", true)
end

function StatusEffects.GetDamageTakenMultiplier(victim: Model): number
	local v = vulnerable[victim]
	if v and os.clock() < v.expiresAt then
		return v.magnitude
	end
	return 1
end

function StatusEffects.ApplySlow(victim: Model, mult: number, duration: number)
	slows[victim] = { expiresAt = os.clock() + duration, magnitude = mult }
	local humanoid = victim:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 16 * mult
	end
end

-- Single heartbeat ticker for all effects
local accumulator = 0
game:GetService("RunService").Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.5 then
		return
	end
	local step = accumulator
	accumulator = 0
	local now = os.clock()

	for victim, burn in burns do
		if now >= burn.expiresAt or victim.Parent == nil then
			burns[victim] = nil
			victim:SetAttribute("Burning", false)
		elseif dealDamage then
			dealDamage(victim, burn.dps * step, burn.source)
		end
	end

	for victim, chill in chills do
		if now >= chill.expiresAt or victim.Parent == nil then
			chills[victim] = nil
			if victim.Parent then
				victim:SetAttribute("ChillStacks", 0)
			end
		end
	end

	for victim, v in vulnerable do
		if now >= v.expiresAt or victim.Parent == nil then
			vulnerable[victim] = nil
			if victim.Parent then
				victim:SetAttribute("Vulnerable", false)
			end
		end
	end

	for victim, s in slows do
		if now >= s.expiresAt or victim.Parent == nil then
			slows[victim] = nil
			local humanoid = victim.Parent and victim:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = 16
			end
		end
	end
end)

function StatusEffects.Cleanup(character: Model)
	burns[character] = nil
	chills[character] = nil
	vulnerable[character] = nil
	slows[character] = nil
end

return StatusEffects
