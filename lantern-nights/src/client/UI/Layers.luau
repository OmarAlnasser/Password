--!strict
--[[
	Layers — the stack of ScreenGuis every screen mounts into.

	  HUD            vitals, hotbar, objective              safe area
	  ModalBackdrop  full-bleed dimmer behind windows       full screen
	  Menus          windows (inventory, shop, settings…)   safe area
	  Toasts         notifications, pickup feed             safe area
	  Overlay        tooltips, drag ghosts                  safe area
	  Loading        loading screen                         full screen

	Safe-area layers use ScreenInsets.CoreUISafeInsets, so nothing ever sits
	under Roblox's top bar, a notch or the home indicator.

	Each layer has a single "Root" frame that applies the reactive UI scale.
	The root is sized at 1/scale and scaled back up by a UIScale, so children
	lay out in *design points* while still filling the screen exactly:

		Layers.get("Menus")  -- Frame to parent windows to
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Responsive = require(script.Parent.Responsive)
local Types = require(script.Parent.Types)

local Children = Fusion.Children

export type LayerName = "HUD" | "ModalBackdrop" | "Menus" | "Toasts" | "Overlay" | "Loading"

local SAFE: { [LayerName]: boolean } = {
	HUD = true,
	ModalBackdrop = false,
	Menus = true,
	Toasts = true,
	Overlay = true,
	Loading = false,
}

local roots: { [LayerName]: Frame } = {}

local Layers = {}

local function mountLayer(scope: Types.Scope, name: LayerName, parent: Instance): Frame
	local safe = SAFE[name]
	local root = scope:New("Frame")({
		Name = "Root",
		BackgroundTransparency = 1,
		Size = scope:Computed(function(use): UDim2
			local s = use(Responsive.scale)
			return UDim2.fromScale(1 / s, 1 / s)
		end),

		[Children] = {
			scope:New("UIScale")({
				Scale = Responsive.scale,
			}),
		},
	}) :: Frame

	scope:New("ScreenGui")({
		Name = "LN_" .. name,
		DisplayOrder = Theme.Layer[name],
		ResetOnSpawn = false,
		IgnoreGuiInset = not safe,
		ScreenInsets = if safe then Enum.ScreenInsets.CoreUISafeInsets else Enum.ScreenInsets.None,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = parent,

		[Children] = { root },
	})

	return root
end

--- Creates every layer under PlayerGui. Called once by UIController.
function Layers.mount(scope: Types.Scope)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for name in SAFE do
		roots[name] = mountLayer(scope, name, playerGui)
	end
end

--- The scaled root frame of a layer. Errors if called before `mount`.
function Layers.get(name: LayerName): Frame
	local root = roots[name]
	assert(root, `Layers.get("{name}") called before Layers.mount`)
	return root
end

--- Converts a screen-space AbsolutePosition into design points inside `layer`
--- (for positioning tooltips / drag ghosts next to an element in another layer).
function Layers.toLocal(name: LayerName, absolute: Vector2): Vector2
	local root = Layers.get(name)
	local scale = Fusion.peek(Responsive.scale)
	return (absolute - root.AbsolutePosition) / scale
end

return Layers
