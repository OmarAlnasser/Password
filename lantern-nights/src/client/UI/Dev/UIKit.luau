--!strict
--[[
	UIKit — Studio-only living style guide.

	Press F2 (or tap the "UI Kit" button on the right edge) during a Studio
	play-test to open a window that shows every design token and component
	live: type scale, button variants and states, the icon set, vitals bars,
	count-ups, toasts, tooltips, rarities, and the accessibility settings
	(UI scale, reduce motion, SFX volume) wired to the real Preferences.

	Never mounted in live servers (UIController checks RunService:IsStudio()).
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Icons = require(ReplicatedStorage.Shared.Theme.Icons)
local Format = require(ReplicatedStorage.Shared.Util.Format)

local UI = script.Parent.Parent
local Layers = require(UI.Layers)
local Preferences = require(UI.Preferences)
local Responsive = require(UI.Responsive)
local Toasts = require(UI.Toasts)
local Types = require(UI.Types)
local WindowManager = require(UI.WindowManager)
local Button = require(UI.Components.Button)
local Card = require(UI.Components.Card)
local CountUp = require(UI.Components.CountUp)
local Decor = require(UI.Components.Decor)
local Icon = require(UI.Components.Icon)
local ProgressBar = require(UI.Components.ProgressBar)
local Slider = require(UI.Components.Slider)
local Text = require(UI.Components.Text)
local Toggle = require(UI.Components.Toggle)
local Window = require(UI.Components.Window)

local Children, peek = Fusion.Children, Fusion.peek

local WINDOW_NAME = "UIKit"

local UIKit = {}

-- A titled section card.
local function Section(scope: Types.Scope, order: number, title: string, children: { Types.Child }): Frame
	return Card(scope, {
		Name = title,
		Variant = "Raised",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Shadow = "Small",
		LayoutOrder = order,
		[Children] = {
			Decor.list(scope, { Gap = "S" }),
			Text(scope, { Text = title, Variant = "Heading", Color = Theme.Colors.PrimaryBright, LayoutOrder = 0 }),
			children,
		},
	})
end

-- A wrapping horizontal row.
local function Row(scope: Types.Scope, order: number, children: { Types.Child }): Frame
	return scope:New("Frame")({
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		[Children] = {
			Decor.list(scope, {
				Direction = "Horizontal",
				Gap = "S",
				VAlign = Enum.VerticalAlignment.Center,
				Wraps = true,
			}),
			children,
		},
	}) :: Frame
end

local function build(scope: Types.Scope, isOpen: Types.StateObject<boolean>, close: () -> ()): Instance
	-- Demo state ---------------------------------------------------------------
	local health = scope:Value(100)
	local stamina = scope:Value(80)
	local hunger = scope:Value(60)
	local warmth = scope:Value(35)
	local embers = scope:Value(1250)
	local disabledDemo = scope:Value(true)

	local typeRows: { Types.Child } = {}
	local variants: { Theme.TextVariant } =
		{ "Hero", "Display", "Title", "Heading", "BodyLarge", "Body", "BodyBold", "Caption", "Number", "NumberLarge" }
	for i, variant in variants do
		table.insert(
			typeRows,
			Text(scope, {
				Text = `{variant} · {Theme.Type[variant].Size}pt · Lantern Nights 0123`,
				Variant = variant,
				LayoutOrder = i,
			})
		)
	end

	local buttonVariants: { Theme.ButtonVariant } = { "Primary", "Secondary", "Ghost", "Danger", "Success", "Premium" }
	local variantButtons: { Types.Child } = {}
	for i, variant in buttonVariants do
		table.insert(
			variantButtons,
			Button(scope, {
				Text = variant,
				Variant = variant,
				LayoutOrder = i,
				OnActivated = function()
					Toasts.show({ Kind = "Info", Message = `{variant} pressed` })
				end,
			})
		)
	end

	local iconCells: { Types.Child } = {}
	local tints = {
		Theme.Colors.TextPrimary,
		Theme.Colors.Primary,
		Theme.Colors.Danger,
		Theme.Colors.Success,
		Theme.Colors.Info,
		Theme.Colors.Premium,
	}
	for i, name in Icons.all() do
		table.insert(
			iconCells,
			Icon(scope, {
				Icon = name,
				Size = UDim2.fromOffset(Theme.Size.IconLarge, Theme.Size.IconLarge),
				Color = tints[(i - 1) % #tints + 1],
				LayoutOrder = i,
			})
		)
	end

	local rarityCards: { Types.Child } = {}
	for name, rarity in Theme.Rarity do
		local pips: { Types.Child } = {}
		for p = 1, rarity.Pips do
			table.insert(
				pips,
				scope:New("Frame")({
					Size = UDim2.fromOffset(8, 8),
					BackgroundColor3 = rarity.Color,
					LayoutOrder = p,
					[Children] = { Decor.corner(scope, "Pill"), Decor.stroke(scope, Theme.Colors.TextOutline, 1) },
				})
			)
		end
		table.insert(
			rarityCards,
			Card(scope, {
				Name = name,
				Variant = "Sunken",
				Size = UDim2.fromOffset(120, 96),
				StrokeColor = rarity.Color,
				Padding = "XS",
				Shadow = "None",
				LayoutOrder = rarity.Order,
				[Children] = {
					Decor.list(scope, { Gap = "XXS", HAlign = Enum.HorizontalAlignment.Center }),
					Icon(scope, { Icon = "Star", Color = rarity.Color, LayoutOrder = 1 }),
					Text(scope, { Text = name, Variant = "Caption", Color = rarity.Color, LayoutOrder = 2 }),
					scope:New("Frame")({
						BackgroundTransparency = 1,
						Size = UDim2.fromOffset(0, 8),
						AutomaticSize = Enum.AutomaticSize.X,
						LayoutOrder = 3,
						[Children] = { Decor.list(scope, { Direction = "Horizontal", Gap = "XXS" }), pips },
					}),
				},
			})
		)
	end

	return Window(scope, {
		Name = "UIKit",
		Title = "UI Kit",
		Icon = "Lantern",
		Open = isOpen,
		OnClose = close,
		HeaderActions = Text(scope, {
			Text = scope:Computed(function(use): string
				local scale = string.format("%.2f", use(Responsive.scale))
				return `{use(Responsive.device)} · {use(Responsive.inputMode)} · ×{scale}`
			end),
			Variant = "Caption",
			Color = Theme.Colors.TextMuted,
			LayoutOrder = 1,
		}),
		[Children] = {
			Section(scope, 1, "Accessibility", {
				Slider(scope, {
					Label = "UI scale",
					Value = Preferences.uiScale,
					Min = Theme.Accessibility.UIScaleMin,
					Max = Theme.Accessibility.UIScaleMax,
					Step = 0.05,
					Format = function(v)
						return `{math.round(v * 100)}%`
					end,
					OnChanged = Preferences.setUIScale,
					LayoutOrder = 1,
				}),
				Slider(scope, {
					Label = "SFX volume",
					Value = Preferences.sfxVolume,
					Min = 0,
					Max = 1,
					Step = 0.05,
					Format = function(v)
						return `{math.round(v * 100)}%`
					end,
					LayoutOrder = 2,
				}),
				Toggle(scope, {
					Label = "Reduce motion",
					Description = "Removes bounces, shakes and slides. Everything still works.",
					Value = Preferences.reduceMotion,
					OnChanged = Preferences.setReduceMotion,
					LayoutOrder = 3,
				}),
				Toggle(scope, {
					Label = "Camera shake",
					Value = Preferences.cameraShake,
					Tooltip = "Hover, long-press or select me: tooltips work on every input.",
					LayoutOrder = 4,
				}),
			}),

			Section(scope, 2, "Buttons", {
				Row(scope, 1, variantButtons),
				Row(scope, 2, {
					Button(scope, { Text = "Small", ButtonSize = "Small", Variant = "Secondary", LayoutOrder = 1 }),
					Button(scope, { Text = "Medium", ButtonSize = "Medium", Variant = "Secondary", LayoutOrder = 2 }),
					Button(scope, { Text = "Large", ButtonSize = "Large", Variant = "Secondary", LayoutOrder = 3 }),
					Button(scope, {
						Icon = "Backpack",
						Variant = "Primary",
						Badge = "3",
						Tooltip = "Inventory (B)",
						LayoutOrder = 4,
					}),
					Button(scope, { Icon = "Settings", Variant = "Ghost", Tooltip = "Settings", LayoutOrder = 5 }),
					Button(scope, { Text = "Craft", Icon = "Craft", Variant = "Success", LayoutOrder = 6 }),
				}),
				Row(scope, 3, {
					Button(scope, {
						Text = scope:Computed(function(use): string
							return if use(disabledDemo) then "Locked (tap me)" else "Unlocked"
						end),
						Icon = "Lock",
						Variant = "Primary",
						Disabled = disabledDemo,
						OnDisabledActivated = function()
							Toasts.show({ Kind = "Error", Message = "Not enough Embers" })
						end,
						LayoutOrder = 1,
					}),
					Button(scope, {
						Text = "Toggle lock",
						Variant = "Ghost",
						OnActivated = function()
							disabledDemo:set(not peek(disabledDemo))
						end,
						LayoutOrder = 2,
					}),
				}),
			}),

			Section(scope, 3, "Vitals", {
				ProgressBar(scope, {
					Value = health,
					Max = 100,
					Color = Theme.Vitals.Health.Color,
					LowColor = Theme.Vitals.Health.Low,
					Icon = "Health",
					ShowText = true,
					LayoutOrder = 1,
				}),
				ProgressBar(scope, {
					Value = stamina,
					Max = 100,
					Color = Theme.Vitals.Stamina.Color,
					Icon = "Stamina",
					LayoutOrder = 2,
				}),
				ProgressBar(
					scope,
					{ Value = hunger, Max = 100, Color = Theme.Vitals.Hunger.Color, Icon = "Hunger", LayoutOrder = 3 }
				),
				ProgressBar(scope, {
					Value = warmth,
					Max = 100,
					Color = Theme.Vitals.Warmth.Color,
					LowColor = Theme.Vitals.Warmth.Low,
					Icon = "Warmth",
					LayoutOrder = 4,
				}),
				Row(scope, 5, {
					Button(scope, {
						Text = "Hit −18",
						Icon = "Sword",
						Variant = "Danger",
						ButtonSize = "Small",
						LayoutOrder = 1,
						OnActivated = function()
							health:set(math.max(0, peek(health) - 18))
							stamina:set(math.max(0, peek(stamina) - 10))
							warmth:set(math.max(0, peek(warmth) - 7))
						end,
					}),
					Button(scope, {
						Text = "Heal",
						Icon = "Plus",
						Variant = "Success",
						ButtonSize = "Small",
						LayoutOrder = 2,
						OnActivated = function()
							health:set(100)
							stamina:set(100)
							hunger:set(100)
							warmth:set(100)
						end,
					}),
				}),
			}),

			Section(scope, 4, "Numbers & toasts", {
				Row(scope, 1, {
					Icon(scope, { Icon = "Embers", Color = Theme.Colors.Embers, LayoutOrder = 1 }),
					CountUp(
						scope,
						{ Value = embers, Variant = "NumberLarge", Color = Theme.Colors.Embers, LayoutOrder = 2 }
					),
					CountUp(scope, {
						Value = embers,
						Variant = "Number",
						Format = Format.compact,
						Color = Theme.Colors.TextMuted,
						PopOnIncrease = false,
						LayoutOrder = 3,
					}),
				}),
				Row(scope, 2, {
					Button(scope, {
						Text = "+25",
						ButtonSize = "Small",
						LayoutOrder = 1,
						OnActivated = function()
							embers:set(peek(embers) + 25)
						end,
					}),
					Button(scope, {
						Text = "+25,000",
						ButtonSize = "Small",
						Variant = "Premium",
						LayoutOrder = 2,
						OnActivated = function()
							embers:set(peek(embers) + 25000)
							Toasts.show({ Kind = "Reward", Title = "Treasure!", Message = "+25,000 Embers" })
						end,
					}),
				}),
				Row(scope, 3, {
					Button(scope, {
						Text = "Info",
						Variant = "Secondary",
						ButtonSize = "Small",
						LayoutOrder = 1,
						OnActivated = function()
							Toasts.show({ Kind = "Info", Message = "Night falls in 30 seconds." })
						end,
					}),
					Button(scope, {
						Text = "Success",
						Variant = "Success",
						ButtonSize = "Small",
						LayoutOrder = 2,
						OnActivated = function()
							Toasts.show({ Kind = "Success", Title = "Crafted!", Message = "Torch ×1" })
						end,
					}),
					Button(scope, {
						Text = "Warning",
						Variant = "Secondary",
						ButtonSize = "Small",
						LayoutOrder = 3,
						OnActivated = function()
							Toasts.show({ Kind = "Warning", Message = "You're getting cold. Find a fire." })
						end,
					}),
					Button(scope, {
						Text = "Error",
						Variant = "Danger",
						ButtonSize = "Small",
						LayoutOrder = 4,
						OnActivated = function()
							Toasts.show({ Kind = "Error", Message = "Inventory full" })
						end,
					}),
				}),
			}),

			Section(scope, 5, "Typography", typeRows),
			Section(scope, 6, "Icons", { Row(scope, 1, iconCells) }),
			Section(scope, 7, "Rarity", { Row(scope, 1, rarityCards) }),
		},
	})
end

function UIKit.mount()
	local scope = Fusion.scoped(Fusion)
	WindowManager.register(WINDOW_NAME, build)

	-- Launcher on the right edge, clear of the thumb zones.
	Button(scope, {
		Name = "UIKitLauncher",
		Text = "UI Kit",
		Icon = "Lantern",
		Variant = "Premium",
		ButtonSize = "Small",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -Theme.Spacing.M, 0.5, 0),
		OnActivated = function()
			WindowManager.toggle(WINDOW_NAME)
		end,
	}).Parent =
		Layers.get("HUD")

	ContextActionService:BindAction("LN_ToggleUIKit", function(_, state)
		if state == Enum.UserInputState.Begin then
			WindowManager.toggle(WINDOW_NAME)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.F2)
end

return UIKit
