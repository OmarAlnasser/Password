--!strict
--[[
	Card — the rounded, outlined, softly-graded surface behind every panel.

		Card(scope, {
			Variant = "Raised",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			[Children] = { ... },
		})

	Structure:  Card (transparent holder, carries layout props)
	              ├ Shadow   offset, translucent copy of the shape
	              └ Surface  gradient + UICorner + 2-pt UIStroke + padding
	                  └ your children
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Types = require(script.Parent.Parent.Types)
local Decor = require(script.Parent.Decor)

local Children = Fusion.Children

export type Props = Types.LayoutProps & {
	Variant: Types.UsedAs<Theme.SurfaceVariant>?,
	Padding: Theme.SpacingToken?,
	Radius: Theme.RadiusToken?,
	Shadow: ("Small" | "Medium" | "Large" | "None")?,
	AutomaticSize: Enum.AutomaticSize?,
	-- Overrides the variant's outline colour (e.g. rarity colour on item cards).
	StrokeColor: Types.UsedAs<Color3>?,
	ClipsDescendants: boolean?,
	[typeof(Children)]: Types.Child?,
}

local function Card(scope: Types.Scope, props: Props): Frame
	local variant: Types.UsedAs<Theme.SurfaceVariant> = props.Variant or "Surface"
	local style = scope:Computed(function(use): Theme.SurfaceStyle
		return Theme.Surfaces[use(variant)]
	end)
	local radius = props.Radius or "L"
	local shadowName = props.Shadow or "Medium"
	local shadow = if shadowName ~= "None" then Theme.Shadow[shadowName] else nil
	local automaticSize = props.AutomaticSize or Enum.AutomaticSize.None

	return scope:New("Frame")({
		Name = props.Name or "Card",
		BackgroundTransparency = 1,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Size = props.Size or UDim2.fromScale(1, 1),
		AutomaticSize = automaticSize,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		Visible = props.Visible,

		[Children] = {
			if shadow
				then scope:New("Frame")({
					Name = "Shadow",
					ZIndex = 0,
					Position = UDim2.fromOffset(0, shadow.Offset),
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Theme.Colors.Black,
					BackgroundTransparency = shadow.Transparency,
					[Children] = { Decor.corner(scope, radius) },
				})
				else nil,

			scope:New("Frame")({
				Name = "Surface",
				ZIndex = 1,
				-- Fill the holder on any axis it doesn't auto-size; grow from content on the others.
				Size = UDim2.fromScale(
					if automaticSize == Enum.AutomaticSize.X or automaticSize == Enum.AutomaticSize.XY then 0 else 1,
					if automaticSize == Enum.AutomaticSize.Y or automaticSize == Enum.AutomaticSize.XY then 0 else 1
				),
				AutomaticSize = automaticSize,
				BackgroundColor3 = Theme.Colors.White,
				BackgroundTransparency = scope:Computed(function(use): number
					return use(style).BackgroundTransparency
				end),
				ClipsDescendants = props.ClipsDescendants or false,

				[Children] = {
					Decor.corner(scope, radius),
					Decor.gradient(
						scope,
						scope:Computed(function(use): ColorSequence
							return use(style).Gradient
						end)
					),
					Decor.stroke(
						scope,
						props.StrokeColor
							or scope:Computed(function(use): Color3
								return use(style).Stroke
							end),
						Theme.Stroke.Base,
						scope:Computed(function(use): number
							return use(style).StrokeTransparency
						end)
					),
					Decor.padding(scope, props.Padding or "M"),
					props[Children],
				},
			}),
		},
	}) :: Frame
end

return Card
