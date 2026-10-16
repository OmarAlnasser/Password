--!strict
--[[
	Button — the tactile, chunky button used everywhere (PS99-style feel).

		Button(scope, {
			Text = "Craft",
			Icon = "Craft",
			Variant = "Primary",
			OnActivated = function() ... end,
		})

	Leave out `Text` for a square icon button.

	Feel:
	  • Hover → springs to 1.05 (mouse / gamepad selection only, never on touch)
	  • Press → springs to 0.95 and the face sinks onto its darker "lip"
	  • Click SFX with slight pitch variation
	  • Disabled + tapped → error shake + error sound (instead of silently ignoring)
	  • Hit target never smaller than 44×44 pt
	  • Gamepad: custom selection ring; A presses it like a tap
	  • Optional tooltip (hover / long-press / selection) and a red badge (e.g. "3")
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Icons = require(ReplicatedStorage.Shared.Theme.Icons)
local Motion = require(script.Parent.Parent.Motion)
local Responsive = require(script.Parent.Parent.Responsive)
local Tooltip = require(script.Parent.Parent.Tooltip)
local Types = require(script.Parent.Parent.Types)
local UISound = require(script.Parent.Parent.UISound)
local Decor = require(script.Parent.Decor)
local Icon = require(script.Parent.Icon)
local Text = require(script.Parent.Text)

local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

export type Props = Types.LayoutProps & {
	Text: Types.UsedAs<string>?,
	Icon: Types.UsedAs<Icons.IconName>?,
	Variant: Types.UsedAs<Theme.ButtonVariant>?,
	ButtonSize: Theme.ButtonSize?,
	-- Fixed width in points. Omit to size to the label.
	Width: number?,
	Disabled: Types.UsedAs<boolean>?,
	Tooltip: Types.UsedAs<string>?,
	-- Small counter pill on the top-right corner; nil/"" hides it.
	Badge: Types.UsedAs<string?>?,
	-- Override the icon's tint (defaults to the variant's text colour).
	IconColor: Types.UsedAs<Color3>?,
	OnActivated: (() -> ())?,
	OnDisabledActivated: (() -> ())?,
	-- Set false for buttons that play their own sound (e.g. toggles).
	ClickSound: boolean?,
}

local PRESS_INPUTS: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}

local function isPressInput(input: InputObject): boolean
	return PRESS_INPUTS[input.UserInputType] == true or input.KeyCode == Enum.KeyCode.ButtonA
end

local function Button(scope: Types.Scope, props: Props): TextButton
	local buttonSize = props.ButtonSize or "Medium"
	local height = Theme.Size.ButtonHeight[buttonSize]
	local lip = Theme.Size.ButtonLip
	local hasText = props.Text ~= nil
	local iconSize = math.floor(height * (if hasText then 0.5 else 0.62))
	local textVariant: Theme.TextVariant = if buttonSize == "Large" then "Heading" else "BodyBold"

	local variant: Types.UsedAs<Theme.ButtonVariant> = props.Variant or "Primary"
	local disabledProp: Types.UsedAs<boolean> = props.Disabled or false

	local hovered = scope:Value(false)
	local pressed = scope:Value(false)

	local disabled = scope:Computed(function(use): boolean
		return use(disabledProp)
	end)

	local style = scope:Computed(function(use): Theme.ButtonStyle
		if use(disabled) then
			return Theme.ButtonStyles.Disabled
		end
		return Theme.ButtonStyles[use(variant)]
	end)

	-- Motion ----------------------------------------------------------------
	local scale = Motion.spring(
		scope,
		scope:Computed(function(use): number
			if use(disabled) then
				return 1
			elseif use(pressed) then
				return Theme.Motion.Scale.Press
			elseif use(hovered) then
				return Theme.Motion.Scale.Hover
			end
			return 1
		end),
		Theme.Motion.Spring.Bouncy
	)
	local sink = Motion.spring(
		scope,
		scope:Computed(function(use): number
			return if use(pressed) and not use(disabled) then lip else 0
		end),
		Theme.Motion.Spring.Snappy
	)
	local shakeX, shake = Motion.shake(scope)

	local textColor = scope:Computed(function(use): Color3
		return use(style).Text
	end)

	-- Content (icon + label), shared by the visible face and the invisible measurer.
	local function content(visible: boolean): { Instance }
		local items: { Instance } = {
			Decor.list(scope, {
				Direction = "Horizontal",
				Gap = "XS",
				HAlign = Enum.HorizontalAlignment.Center,
				VAlign = Enum.VerticalAlignment.Center,
			}),
		}
		if props.Icon then
			table.insert(
				items,
				Icon(scope, {
					Icon = props.Icon,
					Size = UDim2.fromOffset(iconSize, iconSize),
					Color = props.IconColor or textColor,
					Transparency = if visible then 0 else 1,
					LayoutOrder = 1,
				})
			)
		end
		if props.Text then
			table.insert(
				items,
				Text(scope, {
					Text = props.Text,
					Variant = textVariant,
					Color = textColor,
					Outline = scope:Computed(function(use): boolean
						return visible and use(style).TextOutline ~= nil
					end),
					OutlineColor = scope:Computed(function(use): Color3
						return use(style).TextOutline or Theme.Colors.TextOutline
					end),
					Transparency = if visible then 0 else 1,
					LayoutOrder = 2,
				})
			)
		end
		return items
	end

	local horizontalPad = if hasText then Theme.Spacing.L else 0
	local width = props.Width or (if hasText then nil else height)
	local hitbox: TextButton? = nil

	hitbox = scope:New("TextButton")({
		Name = props.Name or "Button",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Selectable = true,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		Visible = props.Visible,
		Size = props.Size or UDim2.fromOffset(width or 0, height),
		AutomaticSize = if props.Size or width then Enum.AutomaticSize.None else Enum.AutomaticSize.X,

		SelectionImageObject = scope:New("Frame")({
			Name = "SelectionRing",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 8, 1, 8),
			Position = UDim2.fromOffset(-4, -4),
			[Children] = {
				Decor.corner(scope, "L"),
				Decor.stroke(scope, Theme.Colors.BorderFocus, Theme.Stroke.Bold),
			},
		}),

		[OnEvent("MouseEnter")] = function()
			if peek(Responsive.inputMode) == "KeyboardMouse" and not peek(disabled) then
				hovered:set(true)
				UISound.play("Hover")
			end
		end,
		[OnEvent("MouseLeave")] = function()
			hovered:set(false)
			pressed:set(false)
		end,
		[OnEvent("SelectionGained")] = function()
			hovered:set(true)
			UISound.play("Hover")
		end,
		[OnEvent("SelectionLost")] = function()
			hovered:set(false)
			pressed:set(false)
		end,
		[OnEvent("InputBegan")] = function(input: InputObject)
			if isPressInput(input) then
				pressed:set(true)
			end
		end,
		[OnEvent("InputEnded")] = function(input: InputObject)
			if isPressInput(input) then
				pressed:set(false)
			end
		end,
		[OnEvent("Activated")] = function()
			local button = hitbox
			if button and Tooltip.consumeLongPress(button) then
				return -- the touch was a long-press to read the tooltip
			end
			if peek(disabled) then
				shake()
				UISound.play("Error")
				if props.OnDisabledActivated then
					props.OnDisabledActivated()
				end
				return
			end
			if props.ClickSound ~= false then
				UISound.play("Click")
			end
			if props.OnActivated then
				props.OnActivated()
			end
		end,

		[Children] = {
			scope:New("UISizeConstraint")({
				MinSize = Vector2.new(Theme.Size.MinHitTarget, Theme.Size.MinHitTarget),
			}),

			-- Invisible copy of the content: drives auto-width.
			if width == nil and props.Size == nil
				then scope:New("Frame")({
					Name = "Measure",
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(0, 1),
					AutomaticSize = Enum.AutomaticSize.X,
					[Children] = {
						scope:New("UIPadding")({
							PaddingLeft = UDim.new(0, horizontalPad),
							PaddingRight = UDim.new(0, horizontalPad),
						}),
						content(false),
					},
				})
				else nil,

			-- Everything visible lives in Body so it scales around its centre.
			scope:New("Frame")({
				Name = "Body",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = scope:Computed(function(use): UDim2
					return UDim2.new(0.5, use(shakeX), 0.5, 0)
				end),
				Size = UDim2.fromScale(1, 1),

				[Children] = {
					scope:New("UIScale")({ Scale = scale }),

					scope:New("Frame")({
						Name = "Lip",
						Position = UDim2.fromOffset(0, lip),
						Size = UDim2.new(1, 0, 1, -lip),
						BackgroundColor3 = scope:Computed(function(use): Color3
							return use(style).Lip
						end),
						[Children] = {
							Decor.corner(scope, "M"),
							Decor.stroke(
								scope,
								scope:Computed(function(use): Color3
									return use(style).Stroke
								end)
							),
						},
					}),

					scope:New("Frame")({
						Name = "Face",
						Position = scope:Computed(function(use): UDim2
							return UDim2.fromOffset(0, use(sink))
						end),
						Size = UDim2.new(1, 0, 1, -lip),
						BackgroundColor3 = Theme.Colors.White,
						[Children] = {
							Decor.corner(scope, "M"),
							Decor.gradient(
								scope,
								scope:Computed(function(use): ColorSequence
									local s = use(style)
									return ColorSequence.new(s.Top, s.Bottom)
								end)
							),
							Decor.stroke(
								scope,
								scope:Computed(function(use): Color3
									return use(style).Stroke
								end)
							),
							-- Glossy top highlight.
							scope:New("Frame")({
								Name = "Shine",
								BackgroundColor3 = Theme.Colors.White,
								BackgroundTransparency = 0.82,
								Position = UDim2.fromOffset(4, 3),
								Size = UDim2.new(1, -8, 0.38, 0),
								[Children] = { Decor.corner(scope, "S") },
							}),
							scope:New("Frame")({
								Name = "Content",
								BackgroundTransparency = 1,
								Size = UDim2.fromScale(1, 1),
								[Children] = {
									scope:New("UIPadding")({
										PaddingLeft = UDim.new(0, horizontalPad),
										PaddingRight = UDim.new(0, horizontalPad),
									}),
									content(true),
								},
							}),
						},
					}),

					-- Notification badge.
					if props.Badge
						then scope:New("Frame")({
							Name = "Badge",
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.new(1, -4, 0, 4),
							Size = UDim2.fromOffset(0, 22),
							AutomaticSize = Enum.AutomaticSize.X,
							BackgroundColor3 = Theme.Colors.Danger,
							ZIndex = 5,
							Visible = scope:Computed(function(use): boolean
								local badge = use(props.Badge :: Types.UsedAs<string?>)
								return badge ~= nil and badge ~= ""
							end),
							[Children] = {
								Decor.corner(scope, "Pill"),
								Decor.stroke(scope, Theme.Colors.TextOutline),
								scope:New("UISizeConstraint")({ MinSize = Vector2.new(22, 22) }),
								scope:New("UIPadding")({
									PaddingLeft = UDim.new(0, 6),
									PaddingRight = UDim.new(0, 6),
								}),
								Text(scope, {
									Text = scope:Computed(function(use): string
										return use(props.Badge :: Types.UsedAs<string?>) or ""
									end),
									Variant = "Caption",
									Color = Theme.Colors.White,
									Outline = true,
									Size = UDim2.fromScale(1, 1),
									AutomaticSize = Enum.AutomaticSize.X,
									XAlignment = Enum.TextXAlignment.Center,
								}),
							},
						})
						else nil,
				},
			}),
		},
	}) :: TextButton

	if props.Tooltip and hitbox then
		Tooltip.attach(scope, hitbox, props.Tooltip)
	end

	return hitbox :: TextButton
end

return Button
