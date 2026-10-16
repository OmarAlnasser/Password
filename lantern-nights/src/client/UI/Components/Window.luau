--!strict
--[[
	Window — the modal panel every full screen uses (Inventory, Shop, Settings…).

		Window(scope, {
			Title = "Inventory",
			Icon = "Backpack",
			Open = isOpen,          -- Fusion state<boolean>
			OnClose = close,
			[Children] = { ... },   -- goes into the scrolling body
		})

	Open:  pops in with Back-out easing (0.28 s); close: Quint-in (0.2 s).
	Fits the safe area on phones (92% × 90%) and caps at Theme.Size.WindowMax
	on large screens. Normally created by WindowManager, which also draws the
	backdrop and handles "only one window at a time".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Icons = require(ReplicatedStorage.Shared.Theme.Icons)
local Motion = require(script.Parent.Parent.Motion)
local Types = require(script.Parent.Parent.Types)
local Button = require(script.Parent.Button)
local Card = require(script.Parent.Card)
local Decor = require(script.Parent.Decor)
local Icon = require(script.Parent.Icon)
local Text = require(script.Parent.Text)

local Children = Fusion.Children

local CLOSED_SCALE = 0.6
local HEADER_HEIGHT = 56

export type Props = {
	Name: string?,
	Title: Types.UsedAs<string>,
	Icon: Icons.IconName?,
	Open: Types.UsedAs<boolean>,
	OnClose: () -> (),
	Size: UDim2?,
	MaxSize: Vector2?,
	-- false for screens that manage their own scrolling (inventory grid, etc.)
	Scrolling: boolean?,
	-- Extra controls placed in the header next to the close button.
	HeaderActions: Types.Child?,
	[typeof(Children)]: Types.Child?,
}

local function Window(scope: Types.Scope, props: Props): Frame
	local scaleGoal = scope:Computed(function(use): number
		return if use(props.Open) then 1 else CLOSED_SCALE
	end)
	local tweenInfo = scope:Computed(function(use): TweenInfo
		return if use(props.Open) then Theme.Motion.Open else Theme.Motion.Close
	end)
	local scale = Motion.tween(scope, scaleGoal, tweenInfo)

	local visible = scope:Computed(function(use): boolean
		-- Stay visible while the close animation plays out.
		return use(props.Open) or use(scale) > CLOSED_SCALE + 0.01
	end)

	local bodyChildren: Types.Child = {
		Decor.list(scope, { Gap = "S" }),
		Decor.padding(scope, "XS", "XXS"),
		props[Children],
	}

	return scope:New("Frame")({
		Name = props.Name or "Window",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = props.Size or UDim2.fromScale(0.92, 0.9),
		Visible = visible,

		[Children] = {
			scope:New("UIScale")({ Scale = scale }),
			scope:New("UISizeConstraint")({ MaxSize = props.MaxSize or Theme.Size.WindowMax }),

			Card(scope, {
				Name = "Panel",
				Variant = "Surface",
				Radius = "XL",
				Shadow = "Large",
				Padding = "M",
				[Children] = {
					-- Header: icon badge, title, actions, close.
					scope:New("Frame")({
						Name = "Header",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
						[Children] = {
							-- Left: icon badge + title. (Absolute children, so the right group can pin to the edge.)
							scope:New("Frame")({
								Name = "LeftGroup",
								BackgroundTransparency = 1,
								Size = UDim2.fromScale(0, 1),
								AutomaticSize = Enum.AutomaticSize.X,
								[Children] = {
									Decor.list(scope, {
										Direction = "Horizontal",
										Gap = "S",
										VAlign = Enum.VerticalAlignment.Center,
									}),
									if props.Icon
										then Card(scope, {
											Name = "IconBadge",
											Variant = "Accent",
											Size = UDim2.fromOffset(48, 48),
											Radius = "M",
											Shadow = "Small",
											Padding = "XXS",
											LayoutOrder = 1,
											[Children] = Icon(scope, {
												Icon = props.Icon,
												Size = UDim2.fromScale(1, 1),
												Color = Theme.Colors.White,
											}),
										})
										else nil,
									Text(scope, {
										Text = props.Title,
										Variant = "Title",
										LayoutOrder = 2,
									}),
								},
							}),
							-- Push actions + close to the right edge.
							scope:New("Frame")({
								Name = "RightGroup",
								BackgroundTransparency = 1,
								AnchorPoint = Vector2.new(1, 0.5),
								Position = UDim2.fromScale(1, 0.5),
								Size = UDim2.fromScale(0, 1),
								AutomaticSize = Enum.AutomaticSize.X,
								[Children] = {
									Decor.list(scope, {
										Direction = "Horizontal",
										Gap = "XS",
										HAlign = Enum.HorizontalAlignment.Right,
										VAlign = Enum.VerticalAlignment.Center,
									}),
									props.HeaderActions,
									Button(scope, {
										Name = "Close",
										Icon = "Close",
										Variant = "Danger",
										ButtonSize = "Small",
										LayoutOrder = 100,
										OnActivated = props.OnClose,
									}),
								},
							}),
						},
					}),

					-- Body.
					if props.Scrolling == false
						then scope:New("Frame")({
							Name = "Body",
							BackgroundTransparency = 1,
							Position = UDim2.fromOffset(0, HEADER_HEIGHT + Theme.Spacing.S),
							Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + Theme.Spacing.S)),
							[Children] = props[Children],
						})
						else scope:New("ScrollingFrame")({
							Name = "Body",
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Position = UDim2.fromOffset(0, HEADER_HEIGHT + Theme.Spacing.S),
							Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + Theme.Spacing.S)),
							CanvasSize = UDim2.new(),
							AutomaticCanvasSize = Enum.AutomaticSize.Y,
							ScrollingDirection = Enum.ScrollingDirection.Y,
							ScrollBarThickness = Theme.Size.ScrollBar,
							ScrollBarImageColor3 = Theme.Colors.Primary,
							VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
							ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
							Selectable = false,
							[Children] = bodyChildren,
						}),
				},
			}),
		},
	}) :: Frame
end

return Window
