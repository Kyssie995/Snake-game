--!strict
--[[
	EffectFixtures — realistic effect definitions (JSON text) shared by the Compiler and Builder specs.

	EffectFixtures.FULL_JSON uses every registered component type at least once, a palette with "$name"
	references, markers (one with an event), tracks (incl. a disabled one), component events, qualityOverrides,
	minQuality, a disabled group with a child, nested transforms and a node graph with OnPlay / OnMarker / OnEvent
	flows (RandomNumber -> Emit, FireEvent -> Delay -> Tween -> SetEnabled, Regenerate).

	Expected schedule (High, cycle 0; times absolute):
	  0     emit sparks (graph, count = round(RandomNumber 5..15))
	  0.5   regenerate bolt (event) · fire "Impact" (marker) · fire "Shake" (graph)
	  0.75  emit sparks 30 (event "pop") · tween core.transparency -> 1 over 0.25 s (graph)
	  1     emit sparks 1 (event "tiny") · play boom (event "again") · disable ultra (graph, Tween done; ultra only
	        exists at High)
	  1.25  emit sparks 4 (event "four")
]]

local EffectFixtures = {}

EffectFixtures.FULL_JSON = [=[
{
  "schemaVersion": 1,
  "id": "violetImpact",
  "name": "Violet Impact",
  "duration": 2,
  "seed": 42,
  "palette": { "primary": "#8A5CFF", "hot": "#FFFFFF", "dark": "#200040" },
  "markers": [
    { "id": "impact", "time": 0.5, "label": "Impact", "phase": "impact", "event": "Impact" },
    { "id": "fade", "time": 1.5, "label": "Fade" }
  ],
  "components": [
    { "id": "pivot", "name": "Pivot", "type": "group",
      "transform": { "position": [0, 2, 0], "rotation": [0, 45, 0] },
      "properties": { "spin": [0, 90, 0] } },
    { "id": "sparks", "name": "Sparks", "type": "particles", "parent": "pivot", "startTime": 0.5, "duration": 1,
      "properties": {
        "rate": 40, "burst": 25, "color": [[0, "$primary"], [1, "$hot"]], "size": [[0, 1], [1, 0.5, 0.25]],
        "speed": [10, 20], "lifetime": [0.5, 1.5], "acceleration": [0, -10, 0], "emitterSize": [2, 2, 2],
        "shape": "Sphere", "lightEmission": 1, "unknownProp": 5
      },
      "tracks": [
        { "id": "rateTrack", "channel": "rate", "keyframes": [
          { "time": 0, "value": 40 }, { "time": 1, "value": 0, "easing": "Quad.In" } ] }
      ],
      "events": [
        { "id": "pop", "time": 0.25, "action": "emit", "count": 30 },
        { "id": "tiny", "time": 0.5, "action": "emit", "count": 1 },
        { "id": "four", "time": 0.75, "action": "emit", "count": 4 }
      ],
      "qualityOverrides": { "Low": { "lifetime": [0.4, 0.8] } } },
    { "id": "slash", "name": "Slash", "type": "beam",
      "properties": { "from": [-4, 0, 0], "to": [4, 0, 0], "width0": 2, "width1": 0.5, "curveSize0": 3,
        "curveSize1": 3, "segments": 20, "color": "$primary", "transparency": [[0, 0], [1, 1]] },
      "tracks": [
        { "id": "w", "channel": "width0", "keyframes": [
          { "time": 0, "value": 0 }, { "time": 0.2, "value": 2, "easing": "Back.Out" } ] }
      ] },
    { "id": "swoosh", "name": "Swoosh", "type": "trail", "parent": "pivot",
      "transform": { "position": [3, 0, 0] },
      "properties": { "width": 1.5, "lifetime": 0.4, "minLength": 0.2, "color": "$primary" } },
    { "id": "core", "name": "Core", "type": "part",
      "properties": { "shape": "Ball", "size": [2, 2, 2], "color": "$hot", "transparency": 0.2 },
      "tracks": [
        { "id": "grow", "channel": "size", "keyframes": [
          { "time": 0, "value": [1, 1, 1] }, { "time": 0.5, "value": [3, 3, 3], "easing": "Quart.Out" } ] },
        { "id": "off", "channel": "transparency", "enabled": false, "keyframes": [ { "time": 0, "value": 1 } ] }
      ] },
    { "id": "orb", "name": "Orb", "type": "mesh", "transform": { "scale": 1.5 },
      "properties": { "meshType": "Sphere", "partSize": [2, 2, 2], "meshScale": [1, 1, 1], "offset": [0, 1, 0],
        "color": "$primary" } },
    { "id": "glow", "name": "Glow", "type": "light", "parent": "pivot",
      "properties": { "color": "$primary", "brightness": 5, "range": 16, "shadows": true } },
    { "id": "boom", "name": "Boom", "type": "sound",
      "properties": { "soundId": "rbxassetid://12345", "volume": 0.8, "rollOffMinDistance": 5,
        "rollOffMaxDistance": 80 },
      "events": [ { "id": "again", "time": 1, "action": "play" } ] },
    { "id": "energy", "name": "Energy", "type": "sphere", "startTime": 0, "duration": 0.6,
      "properties": { "radius": 1.5, "shellColor": "$primary", "lightRange": 10 } },
    { "id": "flash", "name": "Flash", "type": "flash", "startTime": 0.5, "duration": 0.4,
      "properties": { "size": 8, "startSize": 2, "range": 20, "color": "$hot" } },
    { "id": "wave", "name": "Wave", "type": "shockwave", "startTime": 0.5,
      "properties": { "startRadius": 1, "endRadius": 14, "height": 0.4, "layers": 3, "color": "$primary" } },
    { "id": "circle", "name": "Circle", "type": "ring", "parent": "pivot", "minQuality": "Medium",
      "properties": { "style": "ring", "segments": 32, "radius": 5, "thickness": 0.3, "height": 0.1 } },
    { "id": "spikes", "name": "Spikes", "type": "radialBurst", "startTime": 0.5, "duration": 0.5,
      "properties": { "count": 16, "startRadius": 1, "endRadius": 12, "width": 0.4 } },
    { "id": "rocks", "name": "Rocks", "type": "debris", "startTime": 0.5,
      "properties": { "count": 20, "size": [0.4, 1], "speed": [20, 40], "gravity": [0, -60, 0],
        "floorHeight": -1 } },
    { "id": "bolt", "name": "Bolt", "type": "lightning",
      "properties": { "from": [0, 12, 0], "to": [0, 0, 0], "segments": 16, "branches": 3, "jitter": 2,
        "thickness": 0.4 },
      "events": [ { "id": "regen", "time": 0.5, "action": "regenerate" } ] },
    { "id": "hidden", "name": "Hidden", "type": "group", "enabled": false },
    { "id": "hiddenChild", "name": "Hidden Child", "type": "part", "parent": "hidden" },
    { "id": "ultra", "name": "Ultra Glow", "type": "light", "minQuality": "High" },
    { "id": "shake", "name": "Shake", "type": "cameraShake", "startTime": 0.5, "duration": 0.6,
      "properties": { "amplitude": 1.2, "frequency": 22, "decay": 0.4, "outerRadius": 150 },
      "tracks": [
        { "id": "calm", "channel": "amplitude", "keyframes": [
          { "time": 0, "value": 1.2 }, { "time": 0.6, "value": 0.3, "easing": "Quad.Out" } ] }
      ] },
    { "id": "impactFrame", "name": "Impact Frame", "type": "screenFlash", "startTime": 0.5, "duration": 0.3,
      "properties": { "contrast": 1.2, "saturation": -1, "tint": "$hot" } }
  ],
  "graph": {
    "nodes": [
      { "id": "play", "type": "OnPlay" },
      { "id": "rnd", "type": "RandomNumber", "params": { "min": 5, "max": 15 } },
      { "id": "burst", "type": "Emit", "params": { "target": "sparks", "count": 10 } },
      { "id": "onImpact", "type": "OnMarker", "params": { "marker": "impact" } },
      { "id": "shake", "type": "FireEvent", "params": { "name": "Shake" } },
      { "id": "wait", "type": "Delay", "params": { "seconds": 0.25 } },
      { "id": "fadeCore", "type": "Tween",
        "params": { "target": "core", "channel": "transparency", "value": 1, "duration": 0.25, "easing": "Quad.In" } },
      { "id": "offUltra", "type": "SetEnabled", "params": { "target": "ultra", "enabled": false } },
      { "id": "onDetonate", "type": "OnEvent", "params": { "name": "Detonate" } },
      { "id": "regen", "type": "Regenerate", "params": { "target": "bolt" } }
    ],
    "links": [
      { "from": "play.out", "to": "burst.in" },
      { "from": "rnd.value", "to": "burst.count" },
      { "from": "onImpact.out", "to": "shake.in" },
      { "from": "shake.out", "to": "wait.in" },
      { "from": "wait.out", "to": "fadeCore.in" },
      { "from": "fadeCore.done", "to": "offUltra.in" },
      { "from": "onDetonate.out", "to": "regen.in" }
    ]
  }
}
]=]

-- Decodes FULL_JSON (fresh tables every call).
function EffectFixtures.full(Json: any): any
	local ok, def = Json.decode(EffectFixtures.FULL_JSON)
	assert(ok, "EffectFixtures.FULL_JSON: " .. tostring(def))
	return def
end

return EffectFixtures
