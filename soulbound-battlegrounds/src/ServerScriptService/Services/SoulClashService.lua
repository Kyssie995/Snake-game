--!strict
-- SoulClashService: the signature mechanic.
-- When two clash-eligible attacks connect with each other's owners within
-- CLASH.WINDOW seconds and CLASH.RANGE studs, both players lock into a 2s
-- mash duel. Winner blasts the loser away; ties explode both.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Modules.Net)
local Constants = require(ReplicatedStorage.Modules.CombatConstants)
local Stun = require(ReplicatedStorage.Modules.StunManager)
local Ragdoll = require(ReplicatedStorage.Modules.RagdollModule)
local Cooldowns = require(ReplicatedStorage.Modules.CooldownManager)

local CombatService = require(script.Parent.CombatService)

local SoulClashService = {}

local C = Constants.CLASH

-- Pending eligible hit: attacker character -> {victim, damage, at}
type PendingHit = { victim: Model, damage: number, at: number }
local pending: { [Model]: PendingHit } = {}

type ActiveClash = {
	a: Model,
	b: Model,
	pressesA: number,
	pressesB: number,
	lastPressA: number,
	lastPressB: number,
	damage: number,
	endsAt: number,
}
local activeByCharacter: { [Model]: ActiveClash } = {}

local clashStateEvent: RemoteEvent

local function playerOf(character: Model): Player?
	return Players:GetPlayerFromCharacter(character)
end

local function faceEachOther(a: Model, b: Model)
	local ra = a:FindFirstChild("HumanoidRootPart") :: BasePart?
	local rb = b:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not ra or not rb then
		return
	end
	local flatA = Vector3.new(rb.Position.X, ra.Position.Y, rb.Position.Z)
	local flatB = Vector3.new(ra.Position.X, rb.Position.Y, ra.Position.Z)
	ra.CFrame = CFrame.lookAt(ra.Position, flatA)
	rb.CFrame = CFrame.lookAt(rb.Position, flatB)
	ra.Anchored = true
	rb.Anchored = true
end

local function unanchor(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.Anchored = false
	end
end

local function resolve(clash: ActiveClash)
	activeByCharacter[clash.a] = nil
	activeByCharacter[clash.b] = nil
	unanchor(clash.a)
	unanchor(clash.b)
	Stun.ClearStun(clash.a)
	Stun.ClearStun(clash.b)

	local pa, pb = clash.pressesA, clash.pressesB
	local winner: Model? = nil
	local loser: Model? = nil
	if pa >= pb * (1 + C.WIN_MARGIN) and pa > 0 then
		winner, loser = clash.a, clash.b
	elseif pb >= pa * (1 + C.WIN_MARGIN) and pb > 0 then
		winner, loser = clash.b, clash.a
	end

	local ra = clash.a:FindFirstChild("HumanoidRootPart") :: BasePart?
	local rb = clash.b:FindFirstChild("HumanoidRootPart") :: BasePart?

	if winner and loser then
		local wRoot = (winner == clash.a and ra or rb)
		local lRoot = (loser == clash.a and ra or rb)
		clashStateEvent:FireAllClients({ phase = "Resolve", winner = winner, loser = loser })
		if wRoot and lRoot then
			local dir = (lRoot.Position - wRoot.Position)
			CombatService.DealDamage(loser, {
				amount = clash.damage * C.WIN_DAMAGE_MULT,
				attacker = winner,
				attackerPlayer = playerOf(winner),
				bypassBlock = true,
				knockback = C.WIN_KNOCKBACK * 1.5,
				knockbackDirection = dir.Magnitude > 0.001 and dir.Unit or Vector3.zAxis,
			})
		end
	else
		clashStateEvent:FireAllClients({ phase = "Tie", a = clash.a, b = clash.b })
		if ra and rb then
			local dir = (ra.Position - rb.Position)
			local u = dir.Magnitude > 0.001 and dir.Unit or Vector3.zAxis
			if Stun.ApplyStun(clash.a, "Ragdoll", 1.0) then
				Ragdoll.Knockback(clash.a, u, C.TIE_KNOCKBACK * 2)
			end
			if Stun.ApplyStun(clash.b, "Ragdoll", 1.0) then
				Ragdoll.Knockback(clash.b, -u, C.TIE_KNOCKBACK * 2)
			end
		end
	end

	for _, character in { clash.a, clash.b } do
		Cooldowns.Start(character, "SoulClash", C.COOLDOWN)
	end
end

local function abort(clash: ActiveClash)
	activeByCharacter[clash.a] = nil
	activeByCharacter[clash.b] = nil
	for _, character in { clash.a, clash.b } do
		if character.Parent then
			unanchor(character)
			Stun.ClearStun(character)
		end
	end
	clashStateEvent:FireAllClients({ phase = "Abort", a = clash.a, b = clash.b })
end

local function startClash(a: Model, b: Model, damage: number)
	local clash: ActiveClash = {
		a = a,
		b = b,
		pressesA = 0,
		pressesB = 0,
		lastPressA = 0,
		lastPressB = 0,
		damage = damage,
		endsAt = os.clock() + C.DURATION,
	}
	activeByCharacter[a] = clash
	activeByCharacter[b] = clash

	Stun.ApplyStun(a, "Clash", C.DURATION + 0.5)
	Stun.ApplyStun(b, "Clash", C.DURATION + 0.5)
	faceEachOther(a, b)

	clashStateEvent:FireAllClients({
		phase = "Start",
		a = a,
		b = b,
		duration = C.DURATION,
		mashKey = C.MASH_KEY.Name,
	})

	task.delay(C.DURATION, function()
		if activeByCharacter[a] == clash then
			if a.Parent and b.Parent then
				resolve(clash)
			else
				abort(clash)
			end
		end
	end)
end

-- Bound into CombatService.DealDamage. Returns true if the hit was consumed
-- by a clash (either starting one or registering the first half).
local function onClashEligibleHit(attacker: Model, victim: Model, damage: number): boolean
	local now = os.clock()

	if activeByCharacter[attacker] or activeByCharacter[victim] then
		return false -- already clashing; let normal rules handle it
	end
	if not Cooldowns.IsReady(attacker, "SoulClash") or not Cooldowns.IsReady(victim, "SoulClash") then
		return false
	end

	-- Did the victim ALSO land an eligible hit on the attacker just now?
	local reverse = pending[victim]
	if reverse and reverse.victim == attacker and now - reverse.at <= C.WINDOW then
		pending[victim] = nil
		pending[attacker] = nil
		local ra = attacker:FindFirstChild("HumanoidRootPart") :: BasePart?
		local rb = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
		if ra and rb and (ra.Position - rb.Position).Magnitude <= C.RANGE then
			startClash(attacker, victim, math.max(damage, reverse.damage))
			return true
		end
		return false
	end

	-- Register this hit and give the victim the window to answer.
	pending[attacker] = { victim = victim, damage = damage, at = now }
	task.delay(C.WINDOW + 0.05, function()
		local p = pending[attacker]
		if p and os.clock() - p.at > C.WINDOW then
			pending[attacker] = nil
		end
	end)
	return false -- hit still lands normally if no clash forms
end

function SoulClashService.Init()
	clashStateEvent = Net.GetEvent("ClashState")
	CombatService.BindClashCheck(onClashEligibleHit)

	Net.RegisterHandler("ClashInput", Constants.RATES.ClashInput, function(player)
		local character = player.Character
		if not character then
			return
		end
		local clash = activeByCharacter[character]
		if not clash or os.clock() > clash.endsAt then
			return
		end
		local now = os.clock()
		local minGap = 1 / C.MAX_MASH_PER_SECOND
		if character == clash.a then
			if now - clash.lastPressA >= minGap then
				clash.lastPressA = now
				clash.pressesA += 1
			end
		elseif character == clash.b then
			if now - clash.lastPressB >= minGap then
				clash.lastPressB = now
				clash.pressesB += 1
			end
		end
	end)

	-- Safety: abort clashes whose participants died or left
	Players.PlayerRemoving:Connect(function(player)
		local character = player.Character
		local clash = character and activeByCharacter[character]
		if clash then
			abort(clash)
		end
	end)
end

return SoulClashService
