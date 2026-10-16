--!strict
--[[
	Icon — draws a glyph from the custom icon set (Theme.Icons).

		Icon(scope, { Name = "Health", Size = UDim2.fromOffset(28, 28), Color = Theme.Vitals.Health.Color })

	The artwork is white with a dark outline, so `Color` tints the fill.
	If the icon hasn't been uploaded yet it falls back to a text glyph.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Icons = require(ReplicatedStorage.Shared.Theme.Icons)
local Types = require(script.Parent.Parent.Types)

local Children = Fusion.Children

export type Props = Types.LayoutProps & {
	Icon: Types.UsedAs<Icons.IconName>,
	Color: Types.UsedAs<Color3>?,
	Transparency: Types.UsedAs<number>?,
	Rotation: Types.UsedAs<number>?,
	[typeof(Children)]: Types.Child?,
}

local function Icon(scope: Types.Scope, props: Props): ImageLabel
	local image = scope:Computed(function(use): string
		return Icons.image(use(props.Icon))
	end)
	local color: Types.UsedAs<Color3> = props.Color or Theme.Colors.TextPrimary

	return scope:New("ImageLabel")({
		Name = props.Name or "Icon",
		BackgroundTransparency = 1,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Size = props.Size or UDim2.fromOffset(Theme.Size.IconMedium, Theme.Size.IconMedium),
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		Visible = props.Visible,
		Rotation = props.Rotation,

		Image = image,
		ImageColor3 = color,
		ImageTransparency = props.Transparency or 0,
		ScaleType = Enum.ScaleType.Fit,

		[Children] = {
			scope:New("UIAspectRatioConstraint")({ AspectRatio = 1 }),
			-- Glyph fallback, only while the PNG hasn't been uploaded.
			scope:New("TextLabel")({
				Name = "Glyph",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Visible = scope:Computed(function(use): boolean
					return use(image) == ""
				end),
				Text = scope:Computed(function(use): string
					return Icons.glyph(use(props.Icon))
				end),
				TextScaled = true,
				FontFace = Theme.Fonts.BodyHeavy,
				TextColor3 = color,
				TextTransparency = props.Transparency or 0,
				[Children] = {
					scope:New("UIStroke")({
						Color = Theme.Colors.TextOutline,
						Thickness = Theme.Stroke.Base,
						Transparency = props.Transparency or 0,
					}),
				},
			}),
			props[Children],
		},
	}) :: ImageLabel
end

return Icon
