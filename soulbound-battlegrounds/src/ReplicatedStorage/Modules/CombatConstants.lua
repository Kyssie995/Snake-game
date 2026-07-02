--!strict
-- CombatConstants: every tunable number in the game lives here.
-- Balance passes edit THIS file (and WeaponConfigs), nothing else.

return {
	-- Health / respawn
	MAX_HEALTH = 100,
	RESPAWN_TIME = 3.5,
	SPAWN_PROTECTION_TIME = 5,

	-- M1 combo
	M1 = {
		DAMAGE = { 4, 4, 5, 8 }, -- hits 1..4 (finisher last)
		COMBO_WINDOW = 0.9, -- seconds to continue the chain
		SWING_COOLDOWN = 0.32, -- min time between swings
		HITSTUN = 0.35,
		HITSTOP = 0.06, -- client freeze-frame on hit
		RANGE = 7, -- studs, hitbox depth
		HITBOX_SIZE = Vector3.new(5, 5, 7),
		FINISHER_KNOCKBACK = 55, -- studs/s impulse
		AIR_LAUNCH_VELOCITY = 65,
		DASH_CANCEL_AFTER_HIT = 2, -- victim may dash-cancel from hit #2 onward
	},

	-- Charged heavy (guard break + Soul Clash eligible)
	HEAVY = {
		CHARGE_TIME = 0.8,
		DAMAGE = 14,
		KNOCKBACK = 70,
		COOLDOWN = 6,
		HITBOX_SIZE = Vector3.new(6, 6, 8),
	},

	-- Block
	BLOCK = {
		MAX_BLOCK_HP = 60,
		M1_BLOCK_COST = 8,
		ABILITY_BLOCK_COST = 20,
		ABILITY_DAMAGE_THROUGH = 0.5, -- abilities deal 50% through block
		REGEN_PER_SECOND = 10,
		REGEN_DELAY = 2,
		GUARD_BREAK_STUN = 1.5,
		FRONT_ARC_DEGREES = 120, -- block only covers this frontal arc
	},

	-- Dash / perfect dodge
	DASH = {
		COOLDOWN = 2,
		DISTANCE = 22,
		DURATION = 0.22,
		IFRAME_TIME = 0.22,
		-- A dodged hit counts as "perfect" only if it arrives within this
		-- long of the dash START. Must be < IFRAME_TIME, otherwise every
		-- i-framed hit is perfect and the mechanic loses meaning.
		PERFECT_WINDOW = 0.12,
		VULNERABLE_TIME = 1.2, -- attacker marked vulnerable after perfect dodge
		VULNERABLE_MULT = 1.2,
	},

	-- Stun system
	STUN = {
		MAX_CONTINUOUS = 4.5, -- anti-infinite: total stun before resistance
		RESIST_TIME = 1.0,
		RAGDOLL_RECOVERY = 1.2,
	},

	-- Soul Energy
	ENERGY = {
		MAX = 100,
		PER_HIT_DEALT = 3,
		PER_HIT_TAKEN = 2,
		PER_SECOND_IN_COMBAT = 1,
		COMBAT_TIMEOUT = 8, -- seconds since last hit to count as "in combat"
		DEATH_PENALTY_MULT = 0.5,
		ECHO_ABSORB = 10,
	},

	-- Final Release (per-weapon duration/cooldown live in WeaponConfigs)
	ULTIMATE = {
		ACTIVATION_TIME = 1.5, -- cinematic lock, invulnerable
		END_SLOW_MULT = 0.9,
		END_SLOW_TIME = 2,
		REQUIRED_ENERGY = 100,
		UNLOCK_LEVEL = 35,
	},

	-- Soul Clash
	CLASH = {
		WINDOW = 0.25, -- both eligible attacks must land within this
		RANGE = 12,
		DURATION = 2.0,
		MASH_KEY = Enum.KeyCode.E,
		MAX_MASH_PER_SECOND = 12,
		WIN_MARGIN = 0.15, -- >=15% more presses to win
		WIN_KNOCKBACK = 40, -- studs of blast
		TIE_KNOCKBACK = 25,
		WIN_DAMAGE_MULT = 1.2,
		COOLDOWN = 20,
	},

	-- Spirit Echo
	ECHO = {
		LIFETIME = 10,
		ABSORB_HOLD_TIME = 1,
		XP_REWARD = 15,
		KILLER_BONUS_XP = 5,
	},

	-- Progression
	PROGRESSION = {
		MAX_LEVEL = 50,
		XP_PER_2_DAMAGE = 1,
		KILL_XP = 50,
		ASSIST_XP = 20,
		ASSIST_WINDOW = 10, -- damaged victim within N seconds of death
		DUMMY_XP_RATE = 0.25,
		DUMMY_DAILY_CAP = 500,
		MOVE_UNLOCK_LEVELS = { 1, 5, 15, 25 },
		ULTIMATE_LEVEL = 35,
		AURA_LEVELS = { 10, 20, 30, 40, 50 },
		XPToNext = function(level: number): number
			return 100 + math.floor(level ^ 1.8 * 12)
		end,
	},

	-- Spirit Tokens
	TOKENS = {
		MINUTES_PER_TOKEN = 10,
		KILL_BONUS_EVERY = 10, -- +1 token per 10 kills
	},

	-- Destruction
	DESTRUCTION = {
		DEBRIS_FADE_TIME = 8,
		WALL_RESPAWN_TIME = 60,
		MIN_IMPACT_SPEED = 30, -- ragdolled body speed to break a weak wall
	},

	-- Remote rate limits (calls per second per player)
	RATES = {
		CombatRequest = 12,
		AbilityRequest = 6,
		ClashInput = 15, -- slightly above cap; excess clamped by clash logic
	},
}
