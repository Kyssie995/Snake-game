--!strict
-- Nur im --project-Modus sinnvoll: "Lib" ist der Instanzname des Verzeichnisses src/ (init.luau),
-- "Tools" ein reiner $className-Folder, "Settings" eine JSON-Datei (Typ any).
-- Erwartung: keine Fehler.
local Lib = require(script.Parent.Parent.Lib)
local Config = require(script.Parent.Parent.Lib.Shared.Config)
local Settings = require(script.Parent.Settings)

local version: string = Lib.version()
local rate: number = Config.DefaultRate
local anything = Settings.whatever.you.like

print(version, rate, anything)
return {}
