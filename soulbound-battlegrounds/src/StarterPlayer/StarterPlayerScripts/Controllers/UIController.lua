--!strict
-- UIController: builds the alpha HUD programmatically (no StarterGui asset
-- dependency — everything spawns from code so the repo is one source of
-- truth). Replace with authored ScreenGuis during the month-3 UI pass.
-- Owns: HP bar, Soul Energy bar, hotbar cooldown radials, weapon level bar,
-- flash text, damage numbers, clash prompt, echo hints, weapon menu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Net = require(ReplicatedStorage.Modules.Net)
local Constants = require(ReplicatedStorage.Modules.CombatConstants)
local WeaponConfigs = require(ReplicatedStorage.Modules.WeaponConfigs)
local VFXUtil = require(ReplicatedStorage.Modules.VFXUtil)

local UIController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screen: ScreenGui
local hpFill: Frame
local energyFill: Frame
local levelFill: Frame
local levelLabel: TextLabel
local tokenLabel: TextLabel
local slotOverlays: { [number]: Frame } = {}
local flashLabel: TextLabel
local hintLabel: TextLabel
local clashFrame: Frame
local ultimateBar: Frame?

local FONT = Enum.Font.GothamBold
local BG = Color3.fromRGB(18, 20, 30)
local ACCENT = Color3.fromRGB(120, 200, 255)

local function makeFrame(parent: Instance, size: UDim2, position: UDim2, color: Color3?): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = color or BG
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

local function makeBar(parent: Instance, position: UDim2, size: UDim2, fillColor: Color3): (Frame, Frame)
	local back = makeFrame(parent, size, position)
	back.BackgroundTransparency = 0.35
	local fill = makeFrame(back, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), fillColor)
	return back, fill
end

local function buildHUD()
	screen = Instance.new("ScreenGui")
	screen.Name = "MainHUD"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Parent = playerGui

	-- HP bar (bottom-center-left)
	local _, hp = makeBar(screen, UDim2.new(0.5, -260, 1, -90), UDim2.fromOffset(250, 18), Color3.fromRGB(120, 255, 140))
	hpFill = hp

	-- Soul Energy bar (bottom-center-right)
	local _, en = makeBar(screen, UDim2.new(0.5, 10, 1, -90), UDim2.fromOffset(250, 18), ACCENT)
	energyFill = en
	energyFill.Size = UDim2.fromScale(0, 1)

	-- Hotbar: 4 ability slots + ultimate
	local hotbar = makeFrame(screen, UDim2.fromOffset(320, 56), UDim2.new(0.5, -160, 1, -62))
	hotbar.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = hotbar

	for slot = 1, 5 do
		local cell = makeFrame(hotbar, UDim2.fromOffset(52, 52), UDim2.new())
		cell.BackgroundTransparency = 0.25
		local keyLabel = Instance.new("TextLabel")
		keyLabel.Size = UDim2.fromScale(1, 1)
		keyLabel.BackgroundTransparency = 1
		keyLabel.Font = FONT
		keyLabel.TextSize = 18
		keyLabel.TextColor3 = Color3.new(1, 1, 1)
		keyLabel.Text = slot == 5 and "G" or tostring(slot)
		keyLabel.Parent = cell
		-- Cooldown overlay fills from bottom as a radial substitute (alpha)
		local overlay = makeFrame(cell, UDim2.fromScale(1, 0), UDim2.fromScale(0, 1), Color3.new(0, 0, 0))
		overlay.AnchorPoint = Vector2.new(0, 1)
		overlay.BackgroundTransparency = 0.4
		slotOverlays[slot == 5 and 0 or slot] = overlay
	end

	-- Weapon level bar (top-center)
	local levelBack, lf = makeBar(screen, UDim2.new(0.5, -150, 0, 16), UDim2.fromOffset(300, 10), Color3.fromRGB(255, 240, 150))
	levelFill = lf
	levelLabel = Instance.new("TextLabel")
	levelLabel.Size = UDim2.new(1, 0, 0, 16)
	levelLabel.Position = UDim2.new(0, 0, 1, 2)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Font = FONT
	levelLabel.TextSize = 14
	levelLabel.TextColor3 = Color3.new(1, 1, 1)
	levelLabel.Text = ""
	levelLabel.Parent = levelBack

	-- Spirit Tokens (top-right)
	tokenLabel = Instance.new("TextLabel")
	tokenLabel.Size = UDim2.fromOffset(160, 24)
	tokenLabel.Position = UDim2.new(1, -170, 0, 14)
	tokenLabel.BackgroundTransparency = 1
	tokenLabel.Font = FONT
	tokenLabel.TextSize = 16
	tokenLabel.TextXAlignment = Enum.TextXAlignment.Right
	tokenLabel.TextColor3 = ACCENT
	tokenLabel.Text = "Spirit Tokens: 0"
	tokenLabel.Parent = screen

	-- Center flash text (level ups, perfect dodge, ultimate names)
	flashLabel = Instance.new("TextLabel")
	flashLabel.Size = UDim2.new(1, 0, 0, 46)
	flashLabel.Position = UDim2.new(0, 0, 0.3, 0)
	flashLabel.BackgroundTransparency = 1
	flashLabel.Font = FONT
	flashLabel.TextSize = 36
	flashLabel.TextStrokeTransparency = 0.5
	flashLabel.TextTransparency = 1
	flashLabel.Text = ""
	flashLabel.Parent = screen

	-- Hint line (Spirit Echo whispers)
	hintLabel = Instance.new("TextLabel")
	hintLabel.Size = UDim2.new(1, 0, 0, 24)
	hintLabel.Position = UDim2.new(0, 0, 0.38, 0)
	hintLabel.BackgroundTransparency = 1
	hintLabel.Font = Enum.Font.GothamMedium
	hintLabel.TextSize = 18
	hintLabel.TextColor3 = Color3.fromRGB(190, 210, 255)
	hintLabel.TextTransparency = 1
	hintLabel.Text = ""
	hintLabel.Parent = screen

	-- Clash mash prompt (hidden until a clash)
	clashFrame = makeFrame(screen, UDim2.fromOffset(240, 80), UDim2.new(0.5, -120, 0.55, 0))
	clashFrame.BackgroundTransparency = 0.2
	clashFrame.Visible = false
	local clashText = Instance.new("TextLabel")
	clashText.Name = "Prompt"
	clashText.Size = UDim2.fromScale(1, 1)
	clashText.BackgroundTransparency = 1
	clashText.Font = FONT
	clashText.TextSize = 28
	clashText.TextColor3 = Color3.new(1, 1, 1)
	clashText.Text = "MASH [E]!"
	clashText.Parent = clashFrame
end

--------------------------------------------------------------------------
-- Public API used by CombatClient and server HUD pushes
--------------------------------------------------------------------------

function UIController.Flash(text: string, color: Color3)
	flashLabel.Text = text
	flashLabel.TextColor3 = color
	flashLabel.TextTransparency = 0
	flashLabel.TextSize = 44
	TweenService:Create(flashLabel, TweenInfo.new(1.2, Enum.EasingStyle.Quad), {
		TextTransparency = 1,
		TextSize = 36,
	}):Play()
end

function UIController.ShowHint(text: string)
	hintLabel.Text = text
	hintLabel.TextTransparency = 0
	TweenService:Create(hintLabel, TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
	}):Play()
end

function UIController.ShowDamageNumber(worldPosition: Vector3, amount: number)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Position = worldPosition + Vector3.new(math.random(-2, 2), 3, math.random(-2, 2))
	part.Parent = workspace
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(80, 30)
	billboard.AlwaysOnTop = true
	billboard.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextSize = 20
	label.TextColor3 = Color3.fromRGB(255, 230, 160)
	label.TextStrokeTransparency = 0.4
	label.Text = tostring(math.floor(amount * 10 + 0.5) / 10)
	label.Parent = billboard
	TweenService:Create(part, TweenInfo.new(0.8), { Position = part.Position + Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(part, 0.9)
end

function UIController.ShowClashPrompt(keyName: string, duration: number)
	local prompt = clashFrame:FindFirstChild("Prompt") :: TextLabel
	prompt.Text = ("MASH [%s]!"):format(keyName)
	clashFrame.Visible = true
	task.delay(duration + 0.5, function()
		clashFrame.Visible = false
	end)
end

function UIController.HideClashPrompt()
	clashFrame.Visible = false
end

function UIController.StartUltimateTimer(duration: number)
	if ultimateBar then
		ultimateBar:Destroy()
	end
	local back, fill = makeBar(screen, UDim2.new(0.5, -100, 1, -120), UDim2.fromOffset(200, 8), Color3.fromRGB(255, 160, 60))
	ultimateBar = back
	TweenService:Create(fill, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Size = UDim2.fromScale(0, 1),
	}):Play()
	task.delay(duration, function()
		if ultimateBar == back then
			back:Destroy()
			ultimateBar = nil
		end
	end)
end

local function startCooldownOverlay(slot: number, duration: number)
	local overlay = slotOverlays[slot]
	if not overlay then
		return
	end
	overlay.Size = UDim2.fromScale(1, 1)
	TweenService:Create(overlay, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Size = UDim2.fromScale(1, 0),
	}):Play()
end

--------------------------------------------------------------------------
-- Weapon menu (M to toggle): list, level, buy, equip
--------------------------------------------------------------------------

local menuFrame: Frame? = nil

local function buildWeaponMenu()
	if menuFrame then
		menuFrame:Destroy()
		menuFrame = nil
		return
	end
	local frame = makeFrame(screen, UDim2.fromOffset(340, 300), UDim2.new(0.5, -170, 0.5, -150))
	frame.BackgroundTransparency = 0.1
	menuFrame = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 36)
	title.BackgroundTransparency = 1
	title.Font = FONT
	title.TextSize = 22
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = "SOUL WEAPONS  (M to close)"
	title.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	title.LayoutOrder = 0

	local shop = Net.GetFunction("ShopRequest")
	local order = 1
	for weaponId, config in WeaponConfigs.GetAll() do
		local row = Instance.new("TextButton")
		row.Size = UDim2.new(1, -16, 0, 48)
		row.LayoutOrder = order
		order += 1
		row.BackgroundColor3 = BG
		row.BackgroundTransparency = 0.2
		row.Font = FONT
		row.TextSize = 16
		row.TextColor3 = config.color
		row.Text = ("%s  —  %s"):format(config.displayName,
			config.tokenCost > 0 and (config.tokenCost .. " tokens") or "starter")
		local corner = Instance.new("UICorner")
		corner.Parent = row
		row.Parent = frame

		row.Activated:Connect(function()
			-- Try equip first; if not owned, try buy
			local result = shop:InvokeServer({ action = "Equip", weapon = weaponId })
			if typeof(result) == "table" and not result.ok and result.err == "not owned" then
				result = shop:InvokeServer({ action = "Buy", weapon = weaponId })
				if typeof(result) == "table" and result.ok then
					UIController.Flash(config.displayName .. " UNLOCKED", config.color)
					shop:InvokeServer({ action = "Equip", weapon = weaponId })
				elseif typeof(result) == "table" then
					UIController.Flash(tostring(result.err):upper(), Color3.fromRGB(255, 100, 100))
				end
			elseif typeof(result) == "table" and result.ok then
				UIController.Flash(config.displayName .. " EQUIPPED", config.color)
			end
		end)
	end
end

--------------------------------------------------------------------------

function UIController.Init()
	buildHUD()

	-- HP tracking from the local humanoid
	local function watchCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		local function update()
			hpFill.Size = UDim2.fromScale(math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1), 1)
		end
		humanoid.HealthChanged:Connect(update)
		update()
	end
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)

	-- Server HUD pushes
	Net.GetEvent("HUDUpdate").OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		if payload.field == "Energy" and typeof(payload.value) == "number" then
			local fraction = payload.value / Constants.ENERGY.MAX
			energyFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			energyFill.BackgroundColor3 = fraction >= 1 and Color3.fromRGB(255, 200, 80) or ACCENT
		elseif payload.field == "Cooldown" and typeof(payload.value) == "table" then
			startCooldownOverlay(payload.value.slot, payload.value.duration)
		elseif payload.field == "Tokens" then
			tokenLabel.Text = "Spirit Tokens: " .. tostring(payload.value)
		elseif payload.field == "WeaponXP" and typeof(payload.value) == "table" then
			local v = payload.value
			levelFill.Size = UDim2.fromScale(math.clamp(v.xp / math.max(v.toNext, 1), 0, 1), 1)
			levelLabel.Text = ("%s  ·  Lv %d"):format(tostring(v.weapon), v.level)
		end
	end)

	-- M toggles the weapon menu
	game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.M then
			buildWeaponMenu()
		end
	end)
end

return UIController
