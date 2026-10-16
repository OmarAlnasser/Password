--!strict
--[[
	UISound — non-positional interface sounds (clicks, opens, errors, rewards).

		UISound.play("Click")

	Sounds are created once, routed through a "UI" SoundGroup whose volume
	follows the player's SFX × Master sliders, and rate-limited per sound so
	sweeping a finger across a grid doesn't machine-gun hover ticks.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Audio = require(ReplicatedStorage.Shared.Config.Audio)
local Preferences = require(script.Parent.Preferences)

local scope = Fusion.scoped(Fusion)

local group = Instance.new("SoundGroup")
group.Name = "UI"
group.Parent = SoundService

scope:Hydrate(group)({
	Volume = scope:Computed(function(use): number
		return use(Preferences.sfxVolume) * use(Preferences.masterVolume)
	end),
})

local sounds: { [Audio.UISoundName]: Sound } = {}
local lastPlayed: { [Audio.UISoundName]: number } = {}
local random = Random.new()

local function getSound(name: Audio.UISoundName): Sound?
	local existing = sounds[name]
	if existing then
		return existing
	end
	local def = Audio.UI[name]
	if not def or def.Id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = def.Id
	sound.Volume = def.Volume
	sound.SoundGroup = group
	sound.Parent = group
	sounds[name] = sound
	return sound
end

local UISound = {}

function UISound.play(name: Audio.UISoundName)
	local def = Audio.UI[name]
	local sound = getSound(name)
	if not sound or not def then
		return
	end
	local now = os.clock()
	if now - (lastPlayed[name] or 0) < def.Cooldown then
		return
	end
	lastPlayed[name] = now
	sound.PlaybackSpeed = 1 + (random:NextNumber() * 2 - 1) * def.PitchJitter
	-- PlayLocalSound plays a fire-and-forget copy, so overlapping clicks don't cut each other off.
	SoundService:PlayLocalSound(sound)
end

--- Warm the cache so the first click isn't silent while the asset loads.
function UISound.preload()
	for name in Audio.UI do
		getSound(name)
	end
end

return UISound
