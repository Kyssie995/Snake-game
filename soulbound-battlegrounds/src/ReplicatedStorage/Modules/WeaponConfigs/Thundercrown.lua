--!strict
-- Thundercrown — the Lightning Greatsword. Slow, massive damage, stuns.

return {
	id = "Thundercrown",
	displayName = "Thundercrown",
	spiritName = "Raivo, the Storm Sovereign",
	color = Color3.fromRGB(255, 220, 80),
	tokenCost = 40,
	m1SpeedMult = 0.85,
	m1DamageMult = 1.3,
	moves = {
		{
			name = "Thunder Cleave",
			slot = 1,
			unlockLevel = 1,
			cooldown = 7,
			damage = 14,
			range = 10,
			description = "A huge vertical bolt-slash with a small AoE shock on impact.",
		},
		{
			name = "Storm Leap",
			slot = 2,
			unlockLevel = 5,
			cooldown = 12,
			damage = 12,
			range = 30,
			description = "Leap and crash down, popping nearby enemies airborne.",
		},
		{
			name = "Static Field",
			slot = 3,
			unlockLevel = 15,
			cooldown = 16,
			damage = 4, -- per tick
			range = 12,
			description = "Charge the ground for 4s. Enemies inside are micro-stunned every second.",
		},
		{
			name = "Crown Breaker",
			slot = 4,
			unlockLevel = 25,
			cooldown = 20,
			damage = 24,
			range = 13,
			clashEligible = true,
			description = "The slowest, hardest swing in the game. Breaks block and ragdolls victims through weak walls.",
		},
	},
	ultimate = {
		name = "Tempest King Release",
		duration = 20,
		cooldown = 90,
		description = "A storm crown ignites. Every 3rd M1 calls a lightning strike. Storm Leap doubles in distance.",
	},
	echoHint = "The echo hums with distant thunder...",
}
