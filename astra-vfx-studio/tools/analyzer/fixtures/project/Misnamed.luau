--!strict
-- Verwendet den Verzeichnisnamen statt des Instanznamens aus der Projektdatei.
local Config = require(script.Parent.Parent.src.Shared.Config) -- EXPECT UnknownRequire

print(Config)
return {}
