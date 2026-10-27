--!strict
--[[
	Settings — plugin settings with safe keys (docs/PLUGIN_CONTRACTS.md §5).

	plugin:SetSetting/GetSetting store JSON; keys must not contain '.', '"', '\' or newlines and values must not
	contain '\' (docs/research/api-studio-plugin.md §2.1). Keys are prefixed "astra_v1_" and restricted to
	[A-Za-z0-9_]. Strings that contain '\' or '"' are stored hex-encoded with a "hex:" prefix.
]]

local Settings = {}
Settings.__index = Settings

export type Settings = typeof(setmetatable({} :: { plugin: any, cache: { [string]: any } }, Settings))

local PREFIX = "astra_v1_"

Settings.DEFAULTS = {
	previewLocation = "camera",
	previewDistance = 24,
	previewCharacter = "none",
	previewQuality = "High",
	timeScale = 1,
	loop = true,
	snap = true,
	bridgeEnabled = false,
	bridgeUrl = "http://localhost:34873",
	bridgeToken = "",
	stashStudioSelection = true,
	recentDocuments = {},
} :: { [string]: any }

local function checkKey(key: string)
	assert(string.match(key, "^[A-Za-z0-9_]+$") ~= nil, "Settings: invalid key " .. key)
end

local function toHex(s: string): string
	return (string.gsub(s, ".", function(c)
		return string.format("%02x", string.byte(c))
	end))
end

local function fromHex(s: string): string
	return (string.gsub(s, "%x%x", function(h)
		return string.char(tonumber(h, 16) :: number)
	end))
end

local function encode(value: any): any
	if type(value) == "string" then
		if string.find(value, '[\\"]') or string.sub(value, 1, 4) == "hex:" then
			return "hex:" .. toHex(value)
		end
		return value
	elseif type(value) == "table" then
		local out = {}
		for k, v in pairs(value) do
			out[k] = encode(v)
		end
		return out
	end
	return value
end

local function decode(value: any): any
	if type(value) == "string" then
		if string.sub(value, 1, 4) == "hex:" then
			return fromHex(string.sub(value, 5))
		end
		return value
	elseif type(value) == "table" then
		local out = {}
		for k, v in pairs(value) do
			out[k] = decode(v)
		end
		return out
	end
	return value
end

function Settings.new(plugin: any): Settings
	return setmetatable({ plugin = plugin, cache = {} }, Settings)
end

function Settings.get(self: Settings, key: string, default: any?): any
	checkKey(key)
	local cached = self.cache[key]
	if cached ~= nil then
		return cached
	end
	local ok, raw = pcall(function()
		return self.plugin:GetSetting(PREFIX .. key)
	end)
	local value
	if ok and raw ~= nil then
		value = decode(raw)
	elseif default ~= nil then
		value = default
	else
		value = Settings.DEFAULTS[key]
	end
	self.cache[key] = value
	return value
end

function Settings.set(self: Settings, key: string, value: any)
	checkKey(key)
	self.cache[key] = value
	local ok, err = pcall(function()
		self.plugin:SetSetting(PREFIX .. key, encode(value))
	end)
	if not ok then
		warn("[AstraVFX] could not save setting " .. key .. ": " .. tostring(err))
	end
end

return Settings
