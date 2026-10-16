--!strict
--[[
	Preferences — reactive, client-side player settings the UI reacts to.

	Each field is a Fusion Value, so any component that `use`s one updates
	the moment the player moves a slider. The Settings screen (later module)
	writes these and the DataStore module persists them. On first join they
	start from sensible defaults and the OS accessibility settings.

		local reduce = Preferences.reduceMotion   -- Fusion.Value<boolean>
		Preferences.uiScale:set(1.1)
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(ReplicatedStorage.Shared.Theme)

export type GraphicsQuality = "Auto" | "Low" | "Medium" | "High"

-- Lives for the whole session; never cleaned up.
local scope = Fusion.scoped(Fusion)

-- Respect the player's Roblox-level "Reduce Motion" setting when available.
local function systemReducedMotion(): boolean
	local ok, value = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end

local Preferences = {
	-- Multiplier on top of the automatic device scale (Theme.Accessibility range).
	uiScale = scope:Value(1) :: Fusion.Value<number>,
	reduceMotion = scope:Value(systemReducedMotion()) :: Fusion.Value<boolean>,
	cameraShake = scope:Value(true) :: Fusion.Value<boolean>,
	particles = scope:Value(true) :: Fusion.Value<boolean>,
	subtitles = scope:Value(true) :: Fusion.Value<boolean>,
	graphics = scope:Value("Auto" :: GraphicsQuality) :: Fusion.Value<GraphicsQuality>,

	-- 0..1 volume sliders.
	masterVolume = scope:Value(1) :: Fusion.Value<number>,
	musicVolume = scope:Value(0.7) :: Fusion.Value<number>,
	sfxVolume = scope:Value(0.8) :: Fusion.Value<number>,
	ambienceVolume = scope:Value(0.7) :: Fusion.Value<number>,
}

--- Clamps and applies a UI scale multiplier.
function Preferences.setUIScale(value: number)
	local a = Theme.Accessibility
	Preferences.uiScale:set(math.clamp(value, a.UIScaleMin, a.UIScaleMax))
end

-- Set once the player picks a value in Settings; after that the OS setting
-- no longer overrides theirs.
local reduceMotionOverridden = false

--- Sets "Reduce motion" from the in-game Settings screen.
function Preferences.setReduceMotion(value: boolean)
	reduceMotionOverridden = true
	Preferences.reduceMotion:set(value)
end

-- Follow OS-level changes until the player has chosen in-game.
pcall(function()
	GuiService:GetPropertyChangedSignal("ReducedMotionEnabled" :: any):Connect(function()
		if not reduceMotionOverridden then
			Preferences.reduceMotion:set(systemReducedMotion())
		end
	end)
end)

return Preferences
