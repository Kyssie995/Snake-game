--!strict
-- WeaponConfigs index: loads and validates every weapon config.
-- Adding a new weapon = drop a new ModuleScript in this folder. Nothing else.

export type MoveConfig = {
	name: string,
	slot: number, -- 1..4 hotbar key
	unlockLevel: number,
	cooldown: number,
	damage: number,
	range: number,
	clashEligible: boolean?,
	description: string,
}

export type WeaponConfig = {
	id: string,
	displayName: string,
	spiritName: string, -- the weapon spirit's name (flavor)
	color: Color3,
	tokenCost: number, -- 0 = starter weapon
	m1SpeedMult: number,
	m1DamageMult: number,
	moves: { MoveConfig },
	ultimate: {
		name: string,
		duration: number,
		cooldown: number,
		description: string,
	},
	echoHint: string, -- Spirit Echo whisper line
}

local configs: { [string]: WeaponConfig } = {}

for _, child in script:GetChildren() do
	if child:IsA("ModuleScript") then
		local config = require(child) :: WeaponConfig
		assert(config.id == child.Name, "Weapon config id must match module name: " .. child.Name)
		assert(#config.moves == 4, config.id .. " must define exactly 4 moves")
		for i, move in config.moves do
			assert(move.slot == i, config.id .. " move slots must be ordered 1..4")
		end
		configs[config.id] = config
	end
end

local WeaponConfigs = {}

function WeaponConfigs.Get(id: string): WeaponConfig?
	return configs[id]
end

function WeaponConfigs.GetAll(): { [string]: WeaponConfig }
	return configs
end

WeaponConfigs.STARTER_WEAPON = "Ashfang"

return WeaponConfigs
