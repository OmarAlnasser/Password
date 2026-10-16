--!strict
--[[
	Toggle — an on/off setting row. The whole row is the hit target.

		Toggle(scope, { Label = "Camera shake", Value = Preferences.cameraShake })

	`Value` is a Fusion Value<boolean> that the toggle writes. Pass
	`OnChanged` instead to route the write elsewhere (e.g. Preferences.setReduceMotion).
	Besides colour, the state is shown by knob position and an ON/OFF word,
	so it reads without colour vision.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Motion = require(script.Parent.Parent.Motion)
local Tooltip = require(script.Parent.Parent.Tooltip)
local Types = require(script.Parent.Parent.Types)
local UISound = require(script.Parent.Parent.UISound)
local Decor = require(script.Parent.Decor)
local Text = require(script.Parent.Text)

local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

local TRACK = Vector2.new(64, 34)
local KNOB = 26

export type Props = Types.LayoutProps & {
	Label: Types.UsedAs<string>,
	Value: Types.Value<boolean>,
	OnChanged: ((boolean) -> ())?,
	Description: Types.UsedAs<string>?,
	Tooltip: Types.UsedAs<string>?,
}

local function Toggle(scope: Types.Scope, props: Props): TextButton
	local on = props.Value
	local knobX = Motion.spring(
		scope,
		scope:Computed(function(use): number
			return if use(on) then TRACK.X - KNOB - 4 else 4
		end),
		Theme.Motion.Spring.Bouncy
	)
	local trackColor = Motion.spring(
		scope,
		scope:Computed(function(use): Color3
			return if use(on) then Theme.Colors.Success else Theme.Colors.SurfaceSunken
		end),
		Theme.Motion.Spring.Smooth
	)

	local row = scope:New("TextButton")({
		Name = props.Name or "Toggle",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Size = props.Size or UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible,

		[OnEvent("Activated")] = function()
			local nextValue = not peek(on)
			UISound.play("Toggle")
			if props.OnChanged then
				props.OnChanged(nextValue)
			else
				on:set(nextValue)
			end
		end,

		[Children] = {
			scope:New("UISizeConstraint")({
				MinSize = Vector2.new(0, Theme.Size.MinHitTarget),
			}),
			Decor.padding(scope, "XXS", "None"),

			-- Label (+ optional description), leaving room for the switch.
			scope:New("Frame")({
				Name = "Labels",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.new(1, -(TRACK.X + Theme.Spacing.M), 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				[Children] = {
					Decor.list(scope, { Gap = "None" }),
					Text(scope, { Text = props.Label, Variant = "BodyBold", LayoutOrder = 1 }),
					if props.Description
						then Text(scope, {
							Text = props.Description,
							Variant = "Caption",
							Color = Theme.Colors.TextMuted,
							Wrapped = true,
							Size = UDim2.fromScale(1, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							LayoutOrder = 2,
						})
						else nil,
				},
			}),

			-- Switch.
			scope:New("Frame")({
				Name = "Track",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				Size = UDim2.fromOffset(TRACK.X, TRACK.Y),
				BackgroundColor3 = trackColor,
				[Children] = {
					Decor.corner(scope, "Pill"),
					Decor.stroke(scope, Theme.Colors.TextOutline),
					Text(scope, {
						Name = "State",
						Text = scope:Computed(function(use): string
							return if use(on) then "ON" else "OFF"
						end),
						Variant = "Caption",
						Color = Theme.Colors.White,
						Outline = true,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = scope:Computed(function(use): UDim2
							-- Sits on the side the knob isn't on.
							return if use(on) then UDim2.new(0.36, 0, 0.5, 0) else UDim2.new(0.66, 0, 0.5, 0)
						end),
					}),
					scope:New("Frame")({
						Name = "Knob",
						AnchorPoint = Vector2.new(0, 0.5),
						Position = scope:Computed(function(use): UDim2
							return UDim2.new(0, use(knobX), 0.5, 0)
						end),
						Size = UDim2.fromOffset(KNOB, KNOB),
						BackgroundColor3 = Theme.Colors.White,
						ZIndex = 2,
						[Children] = {
							Decor.corner(scope, "Pill"),
							Decor.stroke(scope, Theme.Colors.TextOutline),
						},
					}),
				},
			}),
		},
	}) :: TextButton

	if props.Tooltip then
		Tooltip.attach(scope, row, props.Tooltip)
	end
	return row
end

return Toggle
