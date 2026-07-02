--!strict
-- CombatService: the authoritative combat core.
-- Owns: damage pipeline, M1 combos, block, charged heavy, dash/perfect dodge,
-- Soul Energy, spawn protection, kill/assist credit, death events.
-- Other services bind INTO this one (clash eligibility, death listeners) so
-- the dependency graph stays one-directional.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Modules.Net)
local Constants = require(ReplicatedStorage.Modules.CombatConstants)
local Hitbox = require(ReplicatedStorage.Modules.HitboxModule)
local Cooldowns = require(ReplicatedStorage.Modules.CooldownManager)
local Stun = require(ReplicatedStorage.Modules.StunManager)
local Ragdoll = require(ReplicatedStorage.Modules.RagdollModule)
local StatusEffects = require(ReplicatedStorage.Modules.StatusEffects)
local WeaponConfigs = require(ReplicatedStorage.Modules.WeaponConfigs)

local DataService = require(script.Parent.DataService)
local ProgressionService = require(script.Parent.ProgressionService)

local CombatService = {}

--------------------------------------------------------------------------
-- Per-character combat state
--------------------------------------------------------------------------

type CombatState = {
	player: Player?, -- nil for dummies
	energy: number,
	blockHP: number,
	blocking: boolean,
	lastBlockTime: number,
	comboIndex: number,
	lastM1Time: number,
	lastCombatTime: number,
	spawnProtectedUntil: number,
	dashIFramesUntil: number,
	lastDashTime: number,
	heavyChargeStart: number?,
	recentAttackers: { [Player]: number }, -- player -> last damage time (assists)
	ultimateActiveUntil: number,
	ultimateMods: { [string]: any },
	counterWindow: { until_: number, callback: (attacker: Model) -> () }?,
}

local states: { [Model]: CombatState } = {}

local function getState(character: Model): CombatState?
	return states[character]
end
CombatService.GetState = getState

local function newState(character: Model, player: Player?): CombatState
	local s: CombatState = {
		player = player,
		energy = 0,
		blockHP = Constants.BLOCK.MAX_BLOCK_HP,
		blocking = false,
		lastBlockTime = 0,
		comboIndex = 0,
		lastM1Time = 0,
		lastCombatTime = 0,
		spawnProtectedUntil = os.clock() + Constants.SPAWN_PROTECTION_TIME,
		dashIFramesUntil = 0,
		lastDashTime = 0,
		heavyChargeStart = nil,
		recentAttackers = {},
		ultimateActiveUntil = 0,
		ultimateMods = {},
		counterWindow = nil,
	}
	states[character] = s
	return s
end

--------------------------------------------------------------------------
-- Broadcast helpers
--------------------------------------------------------------------------

local fxEvent: RemoteEvent
local hudEvent: RemoteEvent

local function broadcastFX(payload: { [string]: any })
	fxEvent:FireAllClients(payload)
end
CombatService.BroadcastFX = broadcastFX

local function pushEnergy(state: CombatState)
	if state.player then
		hudEvent:FireClient(state.player, { field = "Energy", value = state.energy })
	end
end

local function addEnergy(state: CombatState, amount: number)
	local before = state.energy
	state.energy = math.clamp(state.energy + amount, 0, Constants.ENERGY.MAX)
	if state.energy ~= before then
		pushEnergy(state)
	end
end
CombatService.AddEnergy = function(character: Model, amount: number)
	local s = getState(character)
	if s then
		addEnergy(s, amount)
	end
end

--------------------------------------------------------------------------
-- External bindings (SoulClash, death listeners, ultimate mods)
--------------------------------------------------------------------------

-- SoulClashService binds this; called when a clash-eligible hit is about to
-- land. Returning true means "a clash consumed this hit — don't apply damage".
local clashCheck: ((attacker: Model, victim: Model, damage: number) -> boolean)? = nil
function CombatService.BindClashCheck(fn: (attacker: Model, victim: Model, damage: number) -> boolean)
	clashCheck = fn
end

local deathListeners: { (victim: Model, killer: Player?) -> () } = {}
function CombatService.OnDeath(fn: (victim: Model, killer: Player?) -> ())
	table.insert(deathListeners, fn)
end

function CombatService.SetUltimateMods(character: Model, mods: { [string]: any }, duration: number)
	local s = getState(character)
	if s then
		s.ultimateMods = mods
		s.ultimateActiveUntil = os.clock() + duration
	end
end

function CombatService.GetUltimateMod(character: Model, key: string): any
	local s = getState(character)
	if s and os.clock() < s.ultimateActiveUntil then
		return s.ultimateMods[key]
	end
	return nil
end

-- Abilities (Flame Counter) register a parry window through this.
function CombatService.SetCounterWindow(character: Model, duration: number, callback: (attacker: Model) -> ())
	local s = getState(character)
	if s then
		s.counterWindow = { until_ = os.clock() + duration, callback = callback }
	end
end

--------------------------------------------------------------------------
-- Damage pipeline
--------------------------------------------------------------------------

export type DamageInfo = {
	amount: number,
	attacker: Model?,
	attackerPlayer: Player?,
	isM1: boolean?,
	isHeavy: boolean?,
	clashEligible: boolean?,
	knockback: number?, -- studs/s; triggers ragdoll
	knockbackDirection: Vector3?,
	airLaunch: boolean?,
	hitstun: number?,
	bypassBlock: boolean?,
}

local function isBlockingAgainst(victimState: CombatState, victim: Model, attacker: Model?): boolean
	if not victimState.blocking or victimState.blockHP <= 0 then
		return false
	end
	if not attacker then
		return true
	end
	-- Directional block: only the frontal arc counts
	local vRoot = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
	local aRoot = attacker:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not vRoot or not aRoot then
		return true
	end
	local toAttacker = (aRoot.Position - vRoot.Position)
	if toAttacker.Magnitude < 0.001 then
		return true
	end
	local angle = math.deg(math.acos(math.clamp(vRoot.CFrame.LookVector:Dot(toAttacker.Unit), -1, 1)))
	return angle <= Constants.BLOCK.FRONT_ARC_DEGREES / 2
end

local function handleDeath(victim: Model, victimState: CombatState, killer: Player?)
	-- Kill + assist credit
	if killer then
		ProgressionService.AwardKill(killer)
	end
	local now = os.clock()
	for attacker, lastHit in victimState.recentAttackers do
		if attacker ~= killer and now - lastHit <= Constants.PROGRESSION.ASSIST_WINDOW and attacker.Parent then
			ProgressionService.AwardAssist(attacker)
		end
	end
	-- Death energy penalty
	victimState.energy = math.floor(victimState.energy * Constants.ENERGY.DEATH_PENALTY_MULT)
	pushEnergy(victimState)

	for _, listener in deathListeners do
		task.spawn(listener, victim, killer)
	end
end

function CombatService.DealDamage(victim: Model, info: DamageInfo): boolean
	local humanoid = victim:FindFirstChildOfClass("Humanoid")
	local victimState = getState(victim)
	if not humanoid or humanoid.Health <= 0 or not victimState then
		return false
	end
	local now = os.clock()

	-- Spawn protection & i-frames
	if now < victimState.spawnProtectedUntil or now < victimState.dashIFramesUntil then
		-- Perfect dodge check: were these dash i-frames started just in time?
		if now < victimState.dashIFramesUntil
			and now - victimState.lastDashTime <= Constants.DASH.PERFECT_WINDOW then
			Cooldowns.Clear(victim, "Dash") -- refund
			if info.attacker then
				StatusEffects.ApplyVulnerable(info.attacker, Constants.DASH.VULNERABLE_MULT, Constants.DASH.VULNERABLE_TIME)
			end
			if victimState.player then
				fxEvent:FireClient(victimState.player, { fx = "PerfectDodge" })
			end
			broadcastFX({ fx = "PerfectDodgeFlash", character = victim })
		end
		return false
	end

	-- Attacker spawn protection ends the moment they attack
	if info.attacker then
		local attackerState = getState(info.attacker)
		if attackerState then
			attackerState.spawnProtectedUntil = 0
		end
	end

	-- Counter windows (e.g. Flame Counter) intercept the hit entirely
	if victimState.counterWindow and now < victimState.counterWindow.until_ and info.attacker then
		local cb = victimState.counterWindow.callback
		victimState.counterWindow = nil
		task.spawn(cb, info.attacker)
		return false
	end

	-- Soul Clash interception for eligible heavy-vs-heavy moments
	if info.clashEligible and info.attacker and clashCheck then
		if clashCheck(info.attacker, victim, info.amount) then
			return false
		end
	end

	local amount = info.amount

	-- Blocking
	if not info.bypassBlock and isBlockingAgainst(victimState, victim, info.attacker) then
		if info.isHeavy then
			-- Guard break!
			victimState.blocking = false
			victimState.blockHP = 0
			Stun.ApplyStun(victim, "GuardBreak", Constants.BLOCK.GUARD_BREAK_STUN)
			broadcastFX({ fx = "GuardBreak", character = victim })
		elseif info.isM1 then
			victimState.blockHP -= Constants.BLOCK.M1_BLOCK_COST
			victimState.lastBlockTime = now
			broadcastFX({ fx = "BlockHit", character = victim })
			if victimState.blockHP <= 0 then
				victimState.blocking = false
				Stun.ApplyStun(victim, "GuardBreak", Constants.BLOCK.GUARD_BREAK_STUN)
				broadcastFX({ fx = "GuardBreak", character = victim })
			end
			return false -- M1 fully blocked
		else
			victimState.blockHP -= Constants.BLOCK.ABILITY_BLOCK_COST
			victimState.lastBlockTime = now
			amount *= Constants.BLOCK.ABILITY_DAMAGE_THROUGH
			broadcastFX({ fx = "BlockHit", character = victim })
			if victimState.blockHP <= 0 then
				victimState.blocking = false
				Stun.ApplyStun(victim, "GuardBreak", Constants.BLOCK.GUARD_BREAK_STUN)
				broadcastFX({ fx = "GuardBreak", character = victim })
			end
		end
	end

	-- Vulnerability multiplier (perfect dodge punish)
	amount *= StatusEffects.GetDamageTakenMultiplier(victim)
	amount = math.floor(amount * 10 + 0.5) / 10

	-- Apply
	humanoid:TakeDamage(amount)
	victimState.lastCombatTime = now
	addEnergy(victimState, Constants.ENERGY.PER_HIT_TAKEN)

	if info.attackerPlayer then
		victimState.recentAttackers[info.attackerPlayer] = now
		local attackerState = info.attacker and getState(info.attacker)
		if attackerState then
			attackerState.lastCombatTime = now
			addEnergy(attackerState, Constants.ENERGY.PER_HIT_DEALT)
		end
		-- XP for damage (dummy detection via attribute)
		local isDummy = victim:GetAttribute("IsTrainingDummy") == true
		ProgressionService.AwardXP(info.attackerPlayer, math.floor(amount / 2), isDummy)
	end

	-- Hit reactions
	local root = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		broadcastFX({
			fx = "HitSpark",
			position = root.Position,
			weapon = info.attackerPlayer and select(1, CombatService.GetEquippedWeaponId(info.attackerPlayer)) or nil,
			damage = amount,
			victim = victim,
		})
	end

	if info.airLaunch then
		Ragdoll.AirLaunch(victim, Constants.M1.AIR_LAUNCH_VELOCITY)
		Stun.ApplyStun(victim, "Hitstun", 0.8)
	elseif info.knockback and info.knockback > 0 and root then
		local dir = info.knockbackDirection
		if not dir and info.attacker then
			local aRoot = info.attacker:FindFirstChild("HumanoidRootPart") :: BasePart?
			if aRoot then
				dir = (root.Position - aRoot.Position)
			end
		end
		if dir and dir.Magnitude > 0.001 and not Stun.HasResistance(victim) then
			if Stun.ApplyStun(victim, "Ragdoll", 1.0) then
				Ragdoll.Knockback(victim, dir.Unit, info.knockback)
			end
		end
	elseif info.hitstun then
		Stun.ApplyStun(victim, "Hitstun", info.hitstun)
	end

	if humanoid.Health <= 0 then
		handleDeath(victim, victimState, info.attackerPlayer)
	end
	return true
end

function CombatService.GetEquippedWeaponId(player: Player): string?
	return ProgressionService.GetEquippedWeapon(player)
end

--------------------------------------------------------------------------
-- Player intents: M1, heavy, block, dash
--------------------------------------------------------------------------

local function getCharacterAndState(player: Player): (Model?, CombatState?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local s = getState(character)
	return character, s
end

local function weaponConfigFor(player: Player)
	local id = ProgressionService.GetEquippedWeapon(player)
	return id and WeaponConfigs.Get(id) or nil
end

local function doM1(player: Player, variant: string?)
	local character, s = getCharacterAndState(player)
	if not character or not s then
		return
	end
	if not Stun.IsActionable(character) or s.blocking then
		return
	end
	local config = weaponConfigFor(player)
	if not config then
		return
	end

	local now = os.clock()
	local speedMult = config.m1SpeedMult
	local ultSpeed = CombatService.GetUltimateMod(character, "m1SpeedMult")
	if ultSpeed then
		speedMult *= ultSpeed
	end
	if now - s.lastM1Time < Constants.M1.SWING_COOLDOWN / speedMult then
		return
	end
	if now - s.lastM1Time > Constants.M1.COMBO_WINDOW then
		s.comboIndex = 0
	end
	s.comboIndex += 1
	if s.comboIndex > #Constants.M1.DAMAGE then
		s.comboIndex = 1
	end
	s.lastM1Time = now

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local isFinisher = s.comboIndex == #Constants.M1.DAMAGE
	local damage = Constants.M1.DAMAGE[s.comboIndex] * config.m1DamageMult

	broadcastFX({ fx = "M1Swing", character = character, index = s.comboIndex, weapon = config.id })

	-- Small windup so animation and hit line up (also gives dodge a chance)
	task.delay(0.12 / speedMult, function()
		if not character.Parent or not Stun.IsActionable(character) then
			return
		end
		local hits = Hitbox.Sweep({
			attacker = character,
			cframe = root.CFrame * CFrame.new(0, 0, -Constants.M1.RANGE / 2),
			size = Constants.M1.HITBOX_SIZE,
		})
		for _, victim in hits do
			if not Hitbox.HasLineOfSight(character, victim) then
				continue
			end
			local info: DamageInfo = {
				amount = damage,
				attacker = character,
				attackerPlayer = player,
				isM1 = true,
				hitstun = Constants.M1.HITSTUN,
			}
			if isFinisher then
				if variant == "air" then
					info.airLaunch = true
				else
					info.knockback = Constants.M1.FINISHER_KNOCKBACK
					info.hitstun = nil
				end
			end
			-- Backstab bonus (Voidneedle identity, config-driven post-alpha)
			if config.id == "Voidneedle" then
				local vRoot = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
				if vRoot then
					local behind = vRoot.CFrame.LookVector:Dot((vRoot.Position - root.Position).Unit) > 0.3
					if behind then
						local bonus = CombatService.GetUltimateMod(character, "backstabMult") or 1.25
						info.amount *= bonus
					end
				end
			end
			CombatService.DealDamage(victim, info)
			-- Ultimate on-hit hooks (e.g. Tempest King 3rd-M1 lightning)
			local onHit = CombatService.GetUltimateMod(character, "onM1Hit")
			if onHit then
				task.spawn(onHit, character, victim, s.comboIndex)
			end
		end
	end)
end

local function doHeavy(player: Player)
	local character, s = getCharacterAndState(player)
	if not character or not s then
		return
	end
	if not Stun.IsActionable(character) or s.blocking then
		return
	end
	if not Cooldowns.IsReady(character, "Heavy") then
		return
	end
	Cooldowns.Start(character, "Heavy", Constants.HEAVY.COOLDOWN)
	local config = weaponConfigFor(player)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not config then
		return
	end

	broadcastFX({ fx = "HeavyCharge", character = character, weapon = config.id })
	task.delay(Constants.HEAVY.CHARGE_TIME, function()
		if not character.Parent or not Stun.IsActionable(character) then
			return -- interrupted (getting hit cancels the heavy)
		end
		broadcastFX({ fx = "HeavySwing", character = character, weapon = config.id })
		local hits = Hitbox.Sweep({
			attacker = character,
			cframe = root.CFrame * CFrame.new(0, 0, -Constants.HEAVY.HITBOX_SIZE.Z / 2),
			size = Constants.HEAVY.HITBOX_SIZE,
		})
		for _, victim in hits do
			if not Hitbox.HasLineOfSight(character, victim) then
				continue
			end
			CombatService.DealDamage(victim, {
				amount = Constants.HEAVY.DAMAGE * config.m1DamageMult,
				attacker = character,
				attackerPlayer = player,
				isHeavy = true,
				clashEligible = true,
				knockback = Constants.HEAVY.KNOCKBACK,
			})
		end
	end)
end

local function doBlock(player: Player, active: boolean)
	local character, s = getCharacterAndState(player)
	if not character or not s then
		return
	end
	if active and not Stun.IsActionable(character) then
		return
	end
	s.blocking = active and s.blockHP > 0
	character:SetAttribute("Blocking", s.blocking)
end

local function doDash(player: Player, direction: any)
	local character, s = getCharacterAndState(player)
	if not character or not s then
		return
	end
	local state = Stun.GetState(character)
	local canCancel = state == "Hitstun" and Stun.CanDashCancel(character)
	if state ~= "Idle" and not canCancel then
		return
	end
	if not Cooldowns.IsReady(character, "Dash") then
		return
	end
	local dir = Net.SafeVector3(direction, 2)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not dir or dir.Magnitude < 0.1 or not root then
		return
	end

	Cooldowns.Start(character, "Dash", Constants.DASH.COOLDOWN)
	if canCancel then
		Stun.ClearStun(character)
	end
	local now = os.clock()
	s.lastDashTime = now
	s.dashIFramesUntil = now + Constants.DASH.IFRAME_TIME
	s.blocking = false
	character:SetAttribute("Blocking", false)

	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.1 then
		flat = root.CFrame.LookVector
	end
	root.AssemblyLinearVelocity = flat.Unit * (Constants.DASH.DISTANCE / Constants.DASH.DURATION)
		+ Vector3.new(0, 2, 0)
	broadcastFX({ fx = "SoulDash", character = character })
end

--------------------------------------------------------------------------
-- Character lifecycle + tickers
--------------------------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.MaxHealth = Constants.MAX_HEALTH
	humanoid.Health = Constants.MAX_HEALTH
	humanoid.BreakJointsOnDeath = false
	newState(character, player)

	local weaponId = ProgressionService.GetEquippedWeapon(player)
	if weaponId then
		character:SetAttribute("EquippedWeapon", weaponId)
		local tier = ProgressionService.GetAuraTier(player, weaponId)
		character:SetAttribute("AuraTier", tier)
	end

	humanoid.Died:Connect(function()
		task.delay(Constants.RESPAWN_TIME, function()
			if player.Parent then
				player:LoadCharacter()
			end
		end)
	end)

	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			states[character] = nil
			Stun.Cleanup(character)
			Ragdoll.Cleanup(character)
			StatusEffects.Cleanup(character)
			Cooldowns.Clear(character)
		end
	end)
end

-- Dummies register through this so the same damage pipeline applies.
function CombatService.RegisterNPC(character: Model)
	newState(character, nil)
end

function CombatService.Init()
	fxEvent = Net.GetEvent("CombatFX")
	hudEvent = Net.GetEvent("HUDUpdate")

	StatusEffects.BindDamageCallback(function(victim, amount, source)
		local sourceCharacter = source and source.Character
		CombatService.DealDamage(victim, {
			amount = amount,
			attacker = sourceCharacter,
			attackerPlayer = source,
			bypassBlock = true,
		})
	end)
	StatusEffects.BindFreezeCallback(function(victim, duration)
		Stun.ApplyStun(victim, "GuardBreak", duration)
		broadcastFX({ fx = "Frozen", character = victim, duration = duration })
	end)

	Net.RegisterHandler("CombatRequest", Constants.RATES.CombatRequest, function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end
		local action = Net.SafeString(payload.action, 16)
		if action == "M1" then
			doM1(player, Net.SafeString(payload.variant, 8))
		elseif action == "Heavy" then
			doHeavy(player)
		elseif action == "BlockStart" then
			doBlock(player, true)
		elseif action == "BlockEnd" then
			doBlock(player, false)
		elseif action == "Dash" then
			doDash(player, payload.direction)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			-- Wait for profile before combat state (equipped weapon needed)
			task.spawn(function()
				DataService.WaitForProfile(player)
				onCharacterAdded(player, character)
			end)
		end)
	end)

	-- Block regen + in-combat energy ticker
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for character, s in states do
				if character.Parent == nil then
					states[character] = nil
					continue
				end
				if not s.blocking and now - s.lastBlockTime > Constants.BLOCK.REGEN_DELAY then
					s.blockHP = math.min(Constants.BLOCK.MAX_BLOCK_HP, s.blockHP + Constants.BLOCK.REGEN_PER_SECOND)
				end
				if now - s.lastCombatTime < Constants.ENERGY.COMBAT_TIMEOUT then
					addEnergy(s, Constants.ENERGY.PER_SECOND_IN_COMBAT)
				end
			end
		end
	end)
end

return CombatService
