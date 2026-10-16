--!strict
--[[
	Decor — tiny helpers for the house style's modifier instances, so every
	corner, outline and padding in the game comes from Theme tokens.

		[Children] = {
			Decor.corner(scope, "M"),
			Decor.stroke(scope, Theme.Colors.Border),
			Decor.padding(scope, "M"),
		}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local Types = require(script.Parent.Parent.Types)

local Decor = {}

function Decor.corner(scope: Types.Scope, radius: Theme.RadiusToken?): UICorner
	return scope:New("UICorner")({
		CornerRadius = Theme.Radius[radius or "M"],
	}) :: UICorner
end

function Decor.stroke(
	scope: Types.Scope,
	color: Types.UsedAs<Color3>?,
	thickness: Types.UsedAs<number>?,
	transparency: Types.UsedAs<number>?
): UIStroke
	return scope:New("UIStroke")({
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Color = color or Theme.Colors.Border,
		Thickness = thickness or Theme.Stroke.Base,
		Transparency = transparency or 0,
	}) :: UIStroke
end

function Decor.padding(scope: Types.Scope, all: Theme.SpacingToken, horizontal: Theme.SpacingToken?): UIPadding
	local v = UDim.new(0, Theme.Spacing[all])
	local h = UDim.new(0, Theme.Spacing[horizontal or all])
	return scope:New("UIPadding")({
		PaddingTop = v,
		PaddingBottom = v,
		PaddingLeft = h,
		PaddingRight = h,
	}) :: UIPadding
end

function Decor.gradient(scope: Types.Scope, color: Types.UsedAs<ColorSequence>, rotation: number?): UIGradient
	return scope:New("UIGradient")({
		Color = color,
		Rotation = rotation or 90, -- top → bottom
	}) :: UIGradient
end

export type ListOptions = {
	Direction: ("Vertical" | "Horizontal")?,
	Gap: Theme.SpacingToken?,
	HAlign: Enum.HorizontalAlignment?,
	VAlign: Enum.VerticalAlignment?,
	Wraps: boolean?,
}

function Decor.list(scope: Types.Scope, options: ListOptions?): UIListLayout
	local o: ListOptions = options or {}
	return scope:New("UIListLayout")({
		FillDirection = if o.Direction == "Horizontal"
			then Enum.FillDirection.Horizontal
			else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, Theme.Spacing[o.Gap or "S"]),
		HorizontalAlignment = o.HAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = o.VAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Wraps = o.Wraps or false,
	}) :: UIListLayout
end

return Decor
