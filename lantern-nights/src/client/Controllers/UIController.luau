--!strict
--[[
	UIController — boots the UI framework on the client.

	Init:  hides the default Roblox health bar and backpack (we draw our own),
	       mounts the layer stack, tooltip, toasts and window backdrop.
	Start: in Studio, adds the UI Kit gallery (F2 or the "UI Kit" button) for
	       checking every component, token and animation in one place.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Fusion = require(ReplicatedStorage.Packages.Fusion)

local UI = script.Parent.Parent.UI
local Layers = require(UI.Layers)
local Toasts = require(UI.Toasts)
local Tooltip = require(UI.Tooltip)
local UISound = require(UI.UISound)
local WindowManager = require(UI.WindowManager)

local UIController = {
	Priority = 100, -- before any controller that mounts screens
}

local scope = Fusion.scoped(Fusion)

function UIController:Init()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

	Layers.mount(scope)
	Tooltip.mount(scope)
	Toasts.mount()
	WindowManager.mount()
	UISound.preload()
end

function UIController:Start()
	-- Set the "DevUIKit" attribute on ReplicatedStorage to false to hide it in Studio.
	if RunService:IsStudio() and ReplicatedStorage:GetAttribute("DevUIKit") ~= false then
		local UIKit = require(UI.Dev.UIKit)
		UIKit.mount()
	end
end

return UIController
