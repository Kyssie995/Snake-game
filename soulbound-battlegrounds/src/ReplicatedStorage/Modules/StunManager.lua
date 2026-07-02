--!strict
-- StunManager: authoritative combat-state machine per character.
-- States: Idle | Hitstun | GuardBreak | Ragdoll | Clash | UltimateLock
-- Also tracks continuous-stun accumulation for the anti-infinite rule.

local Constants = require(script.Parent.CombatConstants)

local StunManager = {}

export type StunState = "Idle" | "Hitstun" | "GuardBreak" | "Ragdoll" | "Clash" | "UltimateLock"

type Entry = {
	state: StunState,
	expiresAt: number,
	stunAccumulated: number, -- continuous stun seconds
	lastStunEnd: number,
	resistUntil: number, -- knockback/stun resistance window
	hitCountInCombo: number,
}

local entries: { [Model]: Entry } = {}

local function getEntry(character: Model): Entry
	local e = entries[character]
	if not e then
		e = {
			state = "Idle",
			expiresAt = 0,
			stunAccumulated = 0,
			lastStunEnd = 0,
			resistUntil = 0,
			hitCountInCombo = 0,
		}
		entries[character] = e
	end
	return e
end

local function refresh(e: Entry)
	local now = os.clock()
	if e.state ~= "Idle" and now >= e.expiresAt then
		e.state = "Idle"
		e.lastStunEnd = now
	end
	-- Combo dropped: reset accumulation after a gap
	if e.state == "Idle" and now - e.lastStunEnd > 1.5 then
		e.stunAccumulated = 0
		e.hitCountInCombo = 0
	end
end

function StunManager.GetState(character: Model): StunState
	local e = getEntry(character)
	refresh(e)
	return e.state
end

function StunManager.IsActionable(character: Model): boolean
	return StunManager.GetState(character) == "Idle"
end

function StunManager.HasResistance(character: Model): boolean
	return os.clock() < getEntry(character).resistUntil
end

-- Apply a stun. Returns false if resisted (anti-infinite kicked in).
function StunManager.ApplyStun(character: Model, state: StunState, duration: number): boolean
	local e = getEntry(character)
	refresh(e)
	local now = os.clock()

	if now < e.resistUntil and (state == "Hitstun" or state == "Ragdoll") then
		return false
	end

	-- Anti-infinite: too much continuous stun -> grant resistance instead
	if e.stunAccumulated + duration > Constants.STUN.MAX_CONTINUOUS
		and (state == "Hitstun" or state == "Ragdoll") then
		e.resistUntil = now + Constants.STUN.RESIST_TIME
		e.stunAccumulated = 0
		return false
	end

	-- Clash and UltimateLock override everything; otherwise longer stun wins
	local override = state == "Clash" or state == "UltimateLock"
	if override or e.state == "Idle" or now + duration > e.expiresAt then
		e.state = state
		e.expiresAt = now + duration
		if state == "Hitstun" or state == "Ragdoll" or state == "GuardBreak" then
			e.stunAccumulated += duration
			e.hitCountInCombo += 1
		end
	end
	return true
end

function StunManager.ClearStun(character: Model)
	local e = getEntry(character)
	e.state = "Idle"
	e.expiresAt = 0
	e.lastStunEnd = os.clock()
end

-- Victims may dash-cancel hitstun from M1 hit #N onward (spends their dash).
function StunManager.CanDashCancel(character: Model): boolean
	local e = getEntry(character)
	refresh(e)
	return e.state == "Hitstun"
		and e.hitCountInCombo >= Constants.M1.DASH_CANCEL_AFTER_HIT
end

function StunManager.Cleanup(character: Model)
	entries[character] = nil
end

return StunManager
