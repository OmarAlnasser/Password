--!strict
--[[
	Text — the only way text is drawn in Lantern Nights.

		Text(scope, { Text = "Night 7", Variant = "Title" })

	• Font, size and outline come from Theme.Type[Variant].
	• On touch screens the rendered size never drops below
	  Theme.Accessibility.MinTouchTextPx (18 px), whatever the UI scale.
	• Auto-sizes by default; pass Size + Wrapped for paragraphs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Responsive = require(script.Parent.Parent.Responsive)
local Types = require(script.Parent.Parent.Types)

local Children = Fusion.Children

export type Props = Types.LayoutProps & {
	Text: Types.UsedAs<string>,
	Variant: Types.UsedAs<Theme.TextVariant>?,
	Color: Types.UsedAs<Color3>?,
	Transparency: Types.UsedAs<number>?,
	-- Override the variant's outline (e.g. force an outline on body text over 3D).
	Outline: Types.UsedAs<boolean>?,
	OutlineColor: Types.UsedAs<Color3>?,
	XAlignment: Types.UsedAs<Enum.TextXAlignment>?,
	YAlignment: Types.UsedAs<Enum.TextYAlignment>?,
	Wrapped: boolean?,
	RichText: boolean?,
	AutomaticSize: Enum.AutomaticSize?,
	Truncate: boolean?,
	MaxVisibleGraphemes: Types.UsedAs<number>?,
	[typeof(Children)]: Types.Child?,
}

local function Text(scope: Types.Scope, props: Props): TextLabel
	local variant: Types.UsedAs<Theme.TextVariant> = props.Variant or "Body"

	local style = scope:Computed(function(use): Theme.TypeStyle
		return Theme.Type[use(variant)]
	end)

	local textSize = scope:Computed(function(use): number
		local size = use(style).Size
		if use(Responsive.isTouch) then
			-- Rendered px = TextSize × scale, so divide to keep ≥ the minimum.
			size = math.max(size, Theme.Accessibility.MinTouchTextPx / use(Responsive.scale))
		end
		return math.round(size)
	end)

	local outlineOverride = props.Outline
	local outlined = scope:Computed(function(use): boolean
		if outlineOverride ~= nil then
			return use(outlineOverride)
		end
		return use(style).Outline
	end)

	return scope:New("TextLabel")({
		Name = props.Name or "Text",
		BackgroundTransparency = 1,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Size = props.Size or UDim2.new(),
		AutomaticSize = props.AutomaticSize or (if props.Size then Enum.AutomaticSize.None else Enum.AutomaticSize.XY),
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		Visible = props.Visible,

		Text = props.Text,
		RichText = props.RichText or false,
		TextWrapped = props.Wrapped or false,
		TextTruncate = if props.Truncate then Enum.TextTruncate.AtEnd else Enum.TextTruncate.None,
		MaxVisibleGraphemes = props.MaxVisibleGraphemes or -1,
		FontFace = scope:Computed(function(use): Font
			return use(style).Font
		end),
		TextSize = textSize,
		TextColor3 = props.Color or Theme.Colors.TextPrimary,
		TextTransparency = props.Transparency or 0,
		TextXAlignment = props.XAlignment or Enum.TextXAlignment.Left,
		TextYAlignment = props.YAlignment or Enum.TextYAlignment.Center,

		[Children] = {
			scope:New("UIStroke")({
				ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
				Color = props.OutlineColor or Theme.Colors.TextOutline,
				Thickness = Theme.Stroke.Text,
				Transparency = props.Transparency or 0,
				Enabled = outlined,
			}),
			props[Children],
		},
	}) :: TextLabel
end

return Text
