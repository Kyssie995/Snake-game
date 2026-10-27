--!nonstrict
-- Nonstrict-Datei: unannotierte Locals sind hier `any`, daher meldet der Standardlauf nichts.
-- Mit --force-strict wird die Datei strict geprueft und Zeile 5 ist ein Fehler (UnknownProperty).
local target = workspace
target.Gravityy = 50

return {}
