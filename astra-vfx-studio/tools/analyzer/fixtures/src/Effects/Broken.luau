--!strict
-- ABSICHTLICH FEHLERHAFT: jede markierte Zeile muss genau den erwarteten Fehler liefern.
-- (run_fixtures.sh prueft Zeile + Fehlercode + Textfragment)
local TweenService = game:GetService("TweenService")
local Config = require(script.Parent.Parent.Shared.Config)
local Util = require(script.Parent.Parent.Shared.Util)
local Spark = require(script.Parent.Spark)

local emitter = Instance.new("ParticleEmitter")
emitter.Ratee = 20 -- EXPECT UnknownProperty: Tippfehler in Property-Name
emitter.Rate = "fast" -- EXPECT TypeMismatch: string statt number

local beam = Instance.new("Beam")
beam.Color = Color3.new(1, 0, 0) -- EXPECT TypeMismatch: Beam.Color ist ColorSequence

local label: string = Config.DefaultRate -- EXPECT TypeMismatch: modulübergreifend, number -> string
local missing = Config.DefaultRatee -- EXPECT UnknownProperty: Feld existiert im Config-Typ nicht
local seq = Util.fadeSequence("0", 1) -- EXPECT TypeMismatch: Argumenttyp einer Funktion aus anderem Modul
Spark.makeBeam(emitter, emitter) -- EXPECT TypeMismatch: ParticleEmitter ist kein Attachment

local part = workspace:FindFirstChild("Target")
part.Name = "x" -- EXPECT OptionalValueAccess: FindFirstChild kann nil liefern

local bad = Instance.new("PartcleEmitter") -- EXPECT GenericError: ungueltiger Klassenname
local mat = Enum.Material.Neonn -- EXPECT UnknownProperty: Enum-Item existiert nicht
local Nope = require(script.Parent.DoesNotExist) -- EXPECT UnknownRequire: Modul fehlt im Rojo-Baum
local svc = game:GetService("TweenServce") -- EXPECT GenericError: ungueltiger Service-Name

TweenService:Create(beam, TweenInfo.new(1), { Width0 = 2 }):Play()
print(label, missing, seq, bad, mat, Nope, svc)
