--[[
	ObbyConfig.lua
	--------------------------------------------------------------------
	WHERE THIS GOES:  ReplicatedStorage > Modules > ObbyConfig (ModuleScript)

	One central place for every tunable number, colour and sound ID used
	by the Volcanic Arena Obby.  Both the server and the client read
	from this module, so keep it in ReplicatedStorage.

	SOUND IDS:
	Roblox audio permissions mean marketplace sounds only play if your
	experience owns them (or they are Roblox-created "Creator Store"
	audio).  The rbxasset:// entries below are built into every Roblox
	install and always work.  For the big boom / ambience, search the
	Creator Store (Toolbox > Audio > filter "Roblox created") for
	"cartoon explosion" / "volcano rumble" and paste the IDs here.
--------------------------------------------------------------------]]

local ObbyConfig = {}

-------------------------------------------------- MAP -----------------
ObbyConfig.Map = {
	LavaHeight        = -24,     -- Y position of the lava ocean surface
	LavaSize          = 2048,    -- lava ocean is LavaSize x LavaSize studs
	IslandBaseHeight  = 12,      -- Y of the first island's walking surface
	IslandRise        = 6,       -- each island is this much higher than the last
	JumpGap           = 12,      -- horizontal gap between island edges (studs)
	MovingPlatformSpeed = 6,     -- studs per second for moving platforms
}

-------------------------------------------------- COLOURS -------------
ObbyConfig.Colors = {
	Rock        = Color3.fromRGB(64, 58, 56),
	RockDark    = Color3.fromRGB(43, 38, 36),
	Lava        = Color3.fromRGB(255, 89, 0),
	LavaHot     = Color3.fromRGB(255, 170, 30),
	Checkpoint  = Color3.fromRGB(90, 200, 255),
	CheckpointOn= Color3.fromRGB(80, 255, 120),
	Treasure    = Color3.fromRGB(255, 200, 40),
	SplatRed    = Color3.fromRGB(214, 25, 32),   -- stylized paint red
	SplatRed2   = Color3.fromRGB(255, 70, 60),   -- lighter comic red
	PoofWhite   = Color3.fromRGB(255, 245, 230),
}

-------------------------------------------------- DEATH ANIMATION -----
ObbyConfig.Death = {
	FreezeTime       = 0.35,  -- (1) frozen stiff before anything happens
	ShakeTime        = 1.0,   -- (2) pressure build-up shake duration
	ShakeIntensity   = 0.9,   -- max stud offset while shaking
	InflateScale     = 1.35,  -- R15 characters puff up to this scale
	SplatCount       = 10,    -- (3) red splat MeshParts spawned around character
	ChunkCount       = 16,    -- (4) red chunks that fly out in the burst
	StarCount        = 6,     -- white comic "poof" stars in the burst
	GroundSplatCount = 5,     -- flat paint puddles left on the floor
	EffectLifetime   = 2.5,   -- seconds before burst debris is cleaned up
	RespawnDelay     = 2.2,   -- seconds from BOOM until respawn at checkpoint
	CameraShakeTime  = 0.7,   -- client-side camera shake duration
	CameraShakeMag   = 1.6,   -- client-side camera shake magnitude
}

-------------------------------------------------- SOUNDS --------------
ObbyConfig.Sounds = {
	-- Always-available built-in sounds (ship with the Roblox client):
	Splat      = "rbxasset://sounds/splat.wav",          -- cartoon splat
	Pop        = "rbxasset://sounds/short spring sound.wav",
	Checkpoint = "rbxasset://sounds/electronicpingshort.wav",

	-- Paste Creator-Store IDs you own here (leave "" to skip):
	Boom         = "",   -- e.g. "rbxassetid://YOUR_CARTOON_EXPLOSION_ID"
	VolcanoLoop  = "",   -- e.g. "rbxassetid://YOUR_RUMBLE_LOOP_ID"
	Victory      = "",   -- e.g. "rbxassetid://YOUR_FANFARE_ID"
}

-------------------------------------------------- REMOTES -------------
-- Names of the RemoteEvents the system creates inside
-- ReplicatedStorage > Remotes.  Referenced by server AND client.
ObbyConfig.Remotes = {
	Folder          = "Remotes",
	PlayDeathFX     = "PlayDeathFX",     -- server -> clients : camera shake / local boom
	RequestReset    = "RequestReset",    -- client -> server  : custom reset button
	CheckpointReached = "CheckpointReached", -- server -> client : UI ping
}

return ObbyConfig
