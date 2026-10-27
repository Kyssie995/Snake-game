--!strict
local Config = require(script.Parent.Shared.Config)
local Util = require(script.Parent.Shared.Util)
local Types = require(script.Parent.Shared.Types)
local Spark = require(script.Spark)
local Data = require(script.Parent.Data)

local Effects = {}

function Effects.spawnSparks(target: BasePart, rate: number): Types.EffectHandle
	local emitter = Spark.makeEmitter(target, rate)
	emitter.Transparency = Util.fadeSequence(0, 1)
	emitter.Lifetime = Config.Lifetime
	local _anything = Data.whatever.deep -- JSON-Module sind `any`
	return {
		emitter = emitter,
		beam = nil,
		stop = function()
			emitter.Enabled = false
		end,
	}
end

return Effects
