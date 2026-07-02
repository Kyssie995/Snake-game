--!strict
-- Voidneedle — the Shadow Rapier. Speed, teleports, assassination (+25% backstab).

return {
	id = "Voidneedle",
	displayName = "Voidneedle",
	spiritName = "Nyx-Thorn, the Silent Point",
	color = Color3.fromRGB(150, 70, 255),
	tokenCost = 40,
	m1SpeedMult = 1.1,
	m1DamageMult = 0.85,
	moves = {
		{
			name = "Shadow Pierce",
			slot = 1,
			unlockLevel = 1,
			cooldown = 6,
			damage = 11,
			range = 14,
			description = "A lunging thrust that phases you through the target on hit.",
		},
		{
			name = "Vanish Step",
			slot = 2,
			unlockLevel = 5,
			cooldown = 12,
			damage = 0,
			range = 0,
			description = "Turn invisible for 2s. Your next M1 deals +8 bonus damage.",
		},
		{
			name = "Dark Thread",
			slot = 3,
			unlockLevel = 15,
			cooldown = 15,
			damage = 6,
			range = 28,
			description = "Tether a target. After 1s they are pulled to you unless they dash-cancel the thread.",
		},
		{
			name = "Backstab Rift",
			slot = 4,
			unlockLevel = 25,
			cooldown = 18,
			damage = 19,
			range = 25,
			clashEligible = true,
			description = "Teleport behind a target within 25 studs and deliver a heavy stab.",
		},
	},
	ultimate = {
		name = "Eclipse Release",
		duration = 15,
		cooldown = 90,
		description = "Darkness bleeds from the rapier. Ghost afterimages trail you, Vanish Step gains 2 charges, backstab bonus rises to +50%.",
	},
	echoHint = "The echo flickers like a dying shadow...",
}
