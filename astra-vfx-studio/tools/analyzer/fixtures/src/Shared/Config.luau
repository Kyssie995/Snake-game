--!strict
local Types = require(script.Parent.Types)

export type Config = {
	Version: string,
	DefaultRate: number,
	Lifetime: NumberRange,
	Palette: Types.Palette,
	FadeTime: number,
}

local Config: Config = {
	Version = "0.1.0",
	DefaultRate = 25,
	Lifetime = NumberRange.new(0.4, 0.9),
	Palette = { Color3.fromRGB(255, 170, 0), Color3.new(1, 1, 1) },
	FadeTime = 0.35,
}

return Config
