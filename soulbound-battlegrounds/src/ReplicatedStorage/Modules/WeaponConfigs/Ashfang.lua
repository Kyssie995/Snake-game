--!strict
-- Ashfang — the Fire Wolf Blade. Aggressive melee pressure + Burn.

return {
	id = "Ashfang",
	displayName = "Ashfang",
	spiritName = "Kaen, the Ember Wolf",
	color = Color3.fromRGB(255, 120, 40),
	tokenCost = 0, -- starter weapon
	m1SpeedMult = 1.0,
	m1DamageMult = 1.0,
	moves = {
		{
			name = "Ember Slash",
			slot = 1,
			unlockLevel = 1,
			cooldown = 6,
			damage = 12,
			range = 9,
			description = "A fast 270° arc of burning steel. Applies Burn. Combo extender.",
		},
		{
			name = "Wolf Rush",
			slot = 2,
			unlockLevel = 5,
			cooldown = 10,
			damage = 15, -- 3 bites x3 + slash 6
			range = 24,
			description = "Dash forward as a flame-wolf. First target hit takes 3 bites and a knockback slash.",
		},
		{
			name = "Flame Counter",
			slot = 3,
			unlockLevel = 15,
			cooldown = 14,
			damage = 10,
			range = 8,
			description = "Hold a 0.6s parry stance. If struck, negate the hit and erupt, ragdolling the attacker.",
		},
		{
			name = "Burning Fang",
			slot = 4,
			unlockLevel = 25,
			cooldown = 18,
			damage = 20,
			range = 12,
			clashEligible = true,
			description = "Charged overhead slam leaving a cone of ground fire. Breaks block.",
		},
	},
	ultimate = {
		name = "Inferno Pack Release",
		duration = 20,
		cooldown = 90,
		description = "The blade splits into twin fangs. Two spectral wolves hunt at your side. M1 speed +20%, Wolf Rush cooldown halved.",
	},
	echoHint = "The echo smells of embers and wolf fur...",
}
