--!strict
--[[
	Responsive — device class, input mode and UI scale as reactive state.

	  Responsive.viewport   Value<Vector2>     camera viewport in points
	  Responsive.inputMode  Value<InputMode>   last used input: Touch / KeyboardMouse / Gamepad
	  Responsive.device     Computed<DeviceClass>
	  Responsive.isTouch    Computed<boolean>  touch is the active input
	  Responsive.scale      Computed<number>   device scale × player UI-scale setting

	Layout is authored at scale 1.0 for a phone in landscape (≈390 pt short
	side). The automatic scale grows the UI on tablets and desktops so it never
	looks tiny on a 1080p monitor, and the player's UI-scale slider multiplies
	on top. The input mode switches on the fly (a player can pick up a
	controller mid-session), and prompts and hover behaviour follow it.
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Preferences = require(script.Parent.Preferences)

export type DeviceClass = "Phone" | "Tablet" | "Desktop" | "Console"
export type InputMode = "Touch" | "KeyboardMouse" | "Gamepad"

local scope = Fusion.scoped(Fusion)

-- Short-side (points) → automatic scale. Linear between stops, clamped at ends.
local SCALE_STOPS: { { number } } = {
	{ 320, 0.88 }, -- small phones
	{ 390, 1.0 }, -- reference phone (landscape)
	{ 768, 1.15 }, -- tablets
	{ 1080, 1.3 }, -- 1080p desktop
	{ 1440, 1.55 }, -- 1440p / 4K with OS scaling
}

local function interpolateScale(shortSide: number): number
	local first, last = SCALE_STOPS[1], SCALE_STOPS[#SCALE_STOPS]
	if shortSide <= first[1] then
		return first[2]
	elseif shortSide >= last[1] then
		return last[2]
	end
	for i = 1, #SCALE_STOPS - 1 do
		local a, b = SCALE_STOPS[i], SCALE_STOPS[i + 1]
		if shortSide <= b[1] then
			local t = (shortSide - a[1]) / (b[1] - a[1])
			return a[2] + (b[2] - a[2]) * t
		end
	end
	return last[2]
end

local function inputModeFor(inputType: Enum.UserInputType): InputMode?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif inputType.Name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	elseif
		inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseWheel
	then
		return "KeyboardMouse"
	end
	return nil
end

local function initialInputMode(): InputMode
	local fromLast = inputModeFor(UserInputService:GetLastInputType())
	if fromLast then
		return fromLast
	elseif GuiService:IsTenFootInterface() then
		return "Gamepad"
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	return "KeyboardMouse"
end

local viewport = scope:Value(Vector2.new(1280, 720))
local inputMode = scope:Value(initialInputMode())

local device = scope:Computed(function(use): DeviceClass
	if GuiService:IsTenFootInterface() then
		return "Console"
	end
	local size = use(viewport)
	local shortSide = math.min(size.X, size.Y)
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return if shortSide < 600 then "Phone" else "Tablet"
	end
	return "Desktop"
end)

local isTouch = scope:Computed(function(use): boolean
	return use(inputMode) == "Touch"
end)

local deviceScale = scope:Computed(function(use): number
	local size = use(viewport)
	local base = interpolateScale(math.min(size.X, size.Y))
	-- Consoles are viewed from the couch: bump everything up a notch.
	if use(device) == "Console" then
		base *= 1.15
	end
	return base
end)

local totalScale = scope:Computed(function(use): number
	return use(deviceScale) * use(Preferences.uiScale)
end)

-- Keep the viewport in sync, including when CurrentCamera is replaced.
local cameraConnection: RBXScriptConnection? = nil
local function bindCamera()
	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	viewport:set(camera.ViewportSize)
	cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		viewport:set(camera.ViewportSize)
	end)
end
bindCamera()
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)

UserInputService.LastInputTypeChanged:Connect(function(inputType)
	local mode = inputModeFor(inputType)
	if mode then
		inputMode:set(mode)
	end
end)

local Responsive = {
	viewport = viewport,
	inputMode = inputMode,
	device = device,
	isTouch = isTouch,
	deviceScale = deviceScale,
	scale = totalScale,
}

return Responsive
