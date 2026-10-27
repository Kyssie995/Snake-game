--!strict
--[[
	sound — a positional Sound (docs/COMPONENTS_SPEC.md §8).

	Instances: Sound inside an Attachment on the effect Root (a Sound under an Attachment is positional: distance
	roll-off and panning from the attachment's world position). The Sound is the first entry of `instances`.

	Behaviour:
	  * playOnStart: plays when the component becomes active. `play` / `stop` events. Nothing starts while
	    frame.seeking (scrubbing is silent) or after release(). An empty soundId never plays.
	  * Deactivation (span end) and release() stop LOOPED sounds; one-shot sounds play out (like particles finish
	    their lifetime) unless a `stop` event cuts them. Destroying the effect always stops everything.
	  * Preview (ctx.isPreview): in Studio edit mode Sound:Play() / Sound.Playing do not produce audio, so the
	    preview plays through SoundService:PlayLocalSound(sound) inside pcall instead (falls back to Sound:Play()
	    if that call fails). PlayLocalSound plays a fire-and-forget copy: it cannot be stopped and ignores Looped.
	    Preview audio is therefore BEST EFFORT and unverified in current Studio builds (DevForum reports conflict;
	    docs/research/api-geometry-lighting-tween.md S5/S6).
	  * Channels: position, volume, playbackSpeed (each caches its last value).
]]

local Common = require(script.Parent.Common)
local Env = require(script.Parent.Parent.Env)
local Types = require(script.Parent.Parent.Types)

type FrameContext = Types.FrameContext
type CompiledComponent = Types.CompiledComponent

local prop = Common.prop
local channel = Common.channel

local descriptor: Types.ComponentDescriptor = {
	type = "sound",
	displayName = "Sound",
	category = "Audio",
	description = "Positional sound effect, started on activation or by play events. "
		.. "Editor preview audio is best effort (Studio edit mode does not play Sound:Play()).",
	icon = "♪",
	properties = {
		prop("soundId", "asset", "", "Audio asset id (rbxassetid://…).", { category = "Audio" }),
		prop("volume", "number", 0.5, "Volume (0..10).", { category = "Audio", min = 0, max = 10 }),
		prop(
			"playbackSpeed",
			"number",
			1,
			"Playback speed; also raises/lowers the pitch.",
			{ category = "Audio", min = 0.01, max = 10 }
		),
		prop(
			"rollOffMinDistance",
			"number",
			10,
			"Distance in studs up to which the sound plays at full volume.",
			{ category = "Audio", min = 0, max = 10000, scale = "length" }
		),
		prop(
			"rollOffMaxDistance",
			"number",
			100,
			"Distance in studs beyond which the sound is inaudible.",
			{ category = "Audio", min = 0, max = 10000, scale = "length" }
		),
		prop("looped", "boolean", false, "Repeat the sound until the component ends.", { category = "Audio" }),
		prop(
			"playOnStart",
			"boolean",
			true,
			"Play automatically when the component becomes active.",
			{ category = "Audio" }
		),
	},
	channels = {
		channel("position", "vector3", "Offset from the parent/effect origin in studs.", { scale = "length" }),
		channel("volume", "number", "Volume (0..10).", { min = 0, max = 10, baseProperty = "volume" }),
		channel("playbackSpeed", "number", "Playback speed (pitch).", {
			min = 0.01,
			max = 10,
			baseProperty = "playbackSpeed",
		}),
	},
	events = {
		{ action = "play", description = "Plays the sound from the start." },
		{ action = "stop", description = "Stops the sound." },
	},
	canParent = true,
	supportsViewport = false,
	build = function(ctx: Types.BuildContext, component: CompiledComponent): Types.ComponentInstance
		local props = component.props
		local soundId: string = props.soundId
		local baseVolume: number = props.volume
		local baseSpeed: number = props.playbackSpeed
		local looped: boolean = props.looped
		local playOnStart: boolean = props.playOnStart
		local isPreview = ctx.isPreview

		local sound = Instance.new("Sound")
		sound.Name = component.name
		sound.SoundId = soundId
		sound.Volume = baseVolume
		sound.PlaybackSpeed = baseSpeed
		sound.RollOffMinDistance = props.rollOffMinDistance
		sound.RollOffMaxDistance = props.rollOffMaxDistance
		sound.Looped = looped
		sound.PlayOnRemove = false
		ctx.tagInstance(sound, component.id)
		local attachment = Common.newAttachment(ctx, component.id, component.name)
		sound.Parent = attachment

		local active = false
		local released = false
		local started = false
		local volume = baseVolume
		local speed = baseSpeed
		local lastCFrame: CFrame? = nil

		local function play(frame: FrameContext?)
			if released or soundId == "" or (frame ~= nil and frame.seeking) then
				return
			end
			started = true
			if isPreview then
				local ok = pcall(function()
					local soundService: any = Env.getService("SoundService")
					soundService:PlayLocalSound(sound)
				end :: any)
				if ok then
					return
				end
			end
			sound:Play()
		end

		local function stop()
			if started then
				started = false
				sound:Stop()
			end
		end

		local controller = Common.controller(component, { sound, attachment })

		function controller.setActive(_self, isActive: boolean, frame: FrameContext)
			if isActive == active then
				return
			end
			active = isActive
			if isActive then
				if playOnStart then
					play(frame)
				end
			elseif looped then
				stop()
			end
		end

		function controller.apply(_self, name: string, value: any)
			if type(value) ~= "number" then
				return
			end
			if name == "volume" then
				local v = math.clamp(value, 0, 10)
				if v ~= volume then
					volume = v
					sound.Volume = v
				end
			elseif name == "playbackSpeed" then
				local v = math.clamp(value, 0.01, 10)
				if v ~= speed then
					speed = v
					sound.PlaybackSpeed = v
				end
			end
		end

		function controller.setTransform(_self, localCFrame: CFrame, _worldCFrame: CFrame, _frame: FrameContext)
			if localCFrame ~= lastCFrame then
				lastCFrame = localCFrame
				attachment.CFrame = localCFrame
			end
		end

		function controller.onAction(_self, action: Types.ScheduledAction, frame: FrameContext)
			if action.action == "play" then
				play(frame)
			elseif action.action == "stop" then
				stop()
			end
		end

		function controller.release(_self)
			released = true
			if looped then
				stop()
			end
		end

		function controller.reset(_self)
			active = false
			released = false
			stop()
			volume = baseVolume
			sound.Volume = baseVolume
			speed = baseSpeed
			sound.PlaybackSpeed = baseSpeed
			lastCFrame = nil
			attachment.CFrame = CFrame.new()
		end

		return controller
	end,
	estimateCost = function(component: CompiledComponent, _quality: Types.QualityProfile): Types.CostEstimate
		local cost = Common.cost()
		cost.instances = 2
		cost.attachments = 1
		cost.sounds = 1
		local moving = component.tracks.position ~= nil
		-- Heuristic: one write per volume/playbackSpeed track, plus the attachment CFrame write when moving.
		local updates = if moving then 1 else 0
		for name in component.tracks do
			if name ~= "position" then
				updates += 1
			end
		end
		cost.propertyUpdates = updates
		if component.props.soundId == "" then
			cost.notes = { "No soundId set: the component is silent." }
		end
		return cost
	end,
}

return descriptor
