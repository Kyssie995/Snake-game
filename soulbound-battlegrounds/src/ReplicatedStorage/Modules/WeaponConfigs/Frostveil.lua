--!strict
-- Frostveil — the Ice Mirror Katana. Zoning, control, Chill stacks (3 = freeze).

return {
	id = "Frostveil",
	displayName = "Frostveil",
	spiritName = "Yuiri, the Mirror Maiden",
	color = Color3.fromRGB(140, 225, 255),
	tokenCost = 25,
	m1SpeedMult = 1.0,
	m1DamageMult = 0.95,
	moves = {
		{
			name = "Ice Cut",
			slot = 1,
			unlockLevel = 1,
			cooldown = 7,
			damage = 10,
			range = 30,
			description = "Send a crescent ice wave forward. Applies 1 Chill stack.",
		},
		{
			name = "Frozen Step",
			slot = 2,
			unlockLevel = 5,
			cooldown = 11,
			damage = 6,
			range = 20,
			description = "Dash that leaves a freezing trail for 3s. Enemies touching it gain Chill.",
		},
		{
			name = "Mirror Trap",
			slot = 3,
			unlockLevel = 15,
			cooldown = 16,
			damage = 8,
			range = 15,
			description = "Place an invisible mirror. The first enemy to touch it is frozen for 1.5s.",
		},
		{
			name = "Crystal Burst",
			slot = 4,
			unlockLevel = 25,
			cooldown = 18,
			damage = 18,
			range = 14,
			clashEligible = true,
			description = "Erupt in a ring of ice spikes. Breaks block and applies 2 Chill stacks.",
		},
	},
	ultimate = {
		name = "Winter Domain Release",
		duration = 18,
		cooldown = 90,
		description = "A 30-stud snow dome slows enemies 25%. Your Chill applies double stacks. Mirror clones flicker at the edge.",
	},
	echoHint = "The echo breathes cold mist into the air...",
}
