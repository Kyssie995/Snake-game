--!strict
--[[
	Constants — limits, identifiers and canonical orderings shared by every layer.
	Engine limits are documented with sources in docs/ROBLOX_API_CONSTRAINTS.md.
]]

local Constants = {}

Constants.VERSION = "0.1.0"
Constants.SCHEMA_VERSION = 1

-- Effect limits (ASTRA's own, chosen to keep effects bounded and validators fast)
Constants.MAX_DURATION = 60 -- seconds
Constants.MAX_COMPONENTS = 256
Constants.MAX_TRACKS_PER_COMPONENT = 32
Constants.MAX_KEYFRAMES_PER_TRACK = 256
Constants.MAX_EVENTS_PER_COMPONENT = 256
Constants.MAX_MARKERS = 128
Constants.MAX_EMIT_COUNT = 10000
Constants.MAX_GRAPH_NODES = 256
Constants.MAX_GRAPH_LINKS = 1024
Constants.MAX_GRAPH_ACTIONS = 10000 -- per trigger
Constants.MAX_LOOP_ITERATIONS = 100
Constants.MAX_TIME_SCALE = 10
Constants.MAX_SCALE = 50

-- Engine limits (see docs/ROBLOX_API_CONSTRAINTS.md)
Constants.MAX_SEQUENCE_KEYPOINTS = 20 -- NumberSequence / ColorSequence
Constants.MAX_PARTICLE_LIFETIME = 20 -- seconds (engine cap)
Constants.MAX_PARTICLE_RATE = 400 -- particles/second per emitter (engine cap; mobile lower)
Constants.MAX_FLIPBOOK_FRAMERATE = 30
Constants.MAX_LIGHT_RANGE = 120
Constants.MAX_SPOTLIGHT_ANGLE = 180
Constants.MAX_TRAIL_LIFETIME = 20

-- Identifiers
Constants.ID_PATTERN = "^[A-Za-z0-9_%-]+$"
Constants.ID_MAX_LENGTH = 64
Constants.NAME_MAX_LENGTH = 100
Constants.EVENT_NAME_PATTERN = "^[A-Za-z_][A-Za-z0-9_%-]*$"

-- Attributes / names on built instances
Constants.ATTR_EFFECT = "AstraEffect" -- on every built container (effect name)
Constants.ATTR_COMPONENT = "AstraComponent" -- on every built instance (component id)
Constants.ATTR_PREVIEW = "AstraPreview" -- on preview-only instances (editor)
Constants.PREVIEW_FOLDER = "AstraVFX_Preview"
Constants.CONTAINER_PREFIX = "AstraVFX_"

Constants.QUALITY_LEVELS = { "Low", "Medium", "High" }
Constants.PHASES = { "anticipation", "charge", "action", "impact", "secondary", "dissipation" }

-- Canonical JSON key order. Keys not listed are sorted alphabetically after these.
Constants.KEY_ORDER = {
	"schemaVersion",
	"id",
	"name",
	"type",
	"description",
	"tags",
	"duration",
	"loop",
	"seed",
	"timeScale",
	"palette",
	"parent",
	"enabled",
	"startTime",
	"phase",
	"minQuality",
	"transform",
	"position",
	"rotation",
	"scale",
	"properties",
	"tracks",
	"channel",
	"keyframes",
	"time",
	"value",
	"easing",
	"events",
	"action",
	"count",
	"markers",
	"label",
	"event",
	"components",
	"graph",
	"nodes",
	"links",
	"from",
	"to",
	"params",
	"quality",
	"qualityOverrides",
	"notes",
	"metadata",
}

return Constants
