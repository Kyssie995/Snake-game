--!strict
-- SpiritEchoService: defeated players leave a glowing echo for 10 seconds.
-- Other players hold E (ProximityPrompt) to absorb it for XP + energy + a
-- hint about the victim's Soul Weapon.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Modules.Net)
local Constants = require(ReplicatedStorage.Modules.CombatConstants)
local WeaponConfigs = require(ReplicatedStorage.Modules.WeaponConfigs)
local VFXUtil = require(ReplicatedStorage.Modules.VFXUtil)

local CombatService = require(script.Parent.CombatService)
local ProgressionService = require(script.Parent.ProgressionService)

local SpiritEchoService = {}

local E = Constants.ECHO

local function spawnEcho(victim: Model, killer: Player?)
	local root = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
	local victimPlayer = Players:GetPlayerFromCharacter(victim)
	if not root or not victimPlayer then
		return -- dummies don't leave echoes
	end
	local weaponId = victim:GetAttribute("EquippedWeapon")
	local config = typeof(weaponId) == "string" and WeaponConfigs.Get(weaponId) or nil
	local color = config and config.color or Color3.fromRGB(180, 220, 255)

	local echo = Instance.new("Part")
	echo.Name = "SpiritEcho"
	echo.Anchored = true
	echo.CanCollide = false
	echo.Material = Enum.Material.ForceField
	echo.Color = color
	echo.Size = Vector3.new(2.4, 4.2, 1.4)
	echo.CFrame = CFrame.new(root.Position) * CFrame.new(0, -0.5, 0)
	echo.Transparency = 0.35

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 12
	light.Brightness = 2
	light.Parent = echo

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Rate = 15
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(1, 3)
	emitter.Size = NumberSequence.new(0.35)
	emitter.Parent = echo

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Absorb Echo"
	prompt.ObjectText = "Spirit Echo"
	prompt.HoldDuration = E.ABSORB_HOLD_TIME
	prompt.MaxActivationDistance = 10
	prompt.Parent = echo

	local absorbed = false
	prompt.Triggered:Connect(function(absorber)
		if absorbed then
			return
		end
		if absorber == victimPlayer then
			return -- can't absorb your own echo
		end
		absorbed = true
		prompt.Enabled = false

		local xp = E.XP_REWARD + (absorber == killer and E.KILLER_BONUS_XP or 0)
		ProgressionService.AwardXP(absorber, xp)
		local absorberCharacter = absorber.Character
		if absorberCharacter then
			CombatService.AddEnergy(absorberCharacter, Constants.ENERGY.ECHO_ABSORB)
		end
		local hint = config and config.echoHint or "The echo fades silently..."
		Net.GetEvent("CombatFX"):FireClient(absorber, { fx = "EchoAbsorbed", hint = hint, xp = xp })
		VFXUtil.Shockwave(echo.Position, color, 8, 0.5)
		echo:Destroy()
	end)

	echo.Parent = Workspace
	task.delay(E.LIFETIME, function()
		if echo.Parent then
			echo:Destroy()
		end
	end)
end

function SpiritEchoService.Init()
	CombatService.OnDeath(spawnEcho)
end

return SpiritEchoService
