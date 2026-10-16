--!strict
--[[
	Theme — the single source of design truth for Lantern Nights.

	Every screen, component and VFX colour reads from here. Sections:

	  Colors        semantic colour tokens (surface, text, border, status…)
	  Gradients     ColorSequences for faces, cards and bars
	  Fonts / Type  font faces + the type scale (sizes are *points at UI scale 1*)
	  Spacing       4-pt spacing scale
	  Radius        corner radii (UDim) for UICorner
	  Stroke        outline widths for UIStroke
	  Shadow        drop-shadow presets (offset + transparency)
	  Motion        durations, easings, spring presets, hover/press scales
	  Size          hit targets, control heights, icon sizes
	  Layer         ScreenGui DisplayOrder per UI layer
	  ButtonStyles  per-variant colours for the Button component
	  Vitals        colour + icon per survival stat
	  Rarity        colour + pip count + name per rarity (pips = colourblind-safe cue)

	Sizes are authored for a phone in landscape (≈390 pt tall viewport) at
	scale 1.0. `UI/Responsive` scales the whole UI up on tablets/desktop, and
	`Text` clamps text to ≥ 18 px on touch screens whatever the user's
	UI-scale setting.
]]

local Palette = require(script.Palette)
local Icons = require(script.Icons)

local Ink, Lantern, Ember, Moss, Frost, Violet, Sun =
	Palette.Ink, Palette.Lantern, Palette.Ember, Palette.Moss, Palette.Frost, Palette.Violet, Palette.Sun

-- ─────────────────────────────────────────────────────────────── Types ──

export type TextVariant =
	"Hero"
	| "Display"
	| "Title"
	| "Heading"
	| "BodyLarge"
	| "Body"
	| "BodyBold"
	| "Caption"
	| "Number"
	| "NumberLarge"

export type TypeStyle = {
	Font: Font,
	Size: number,
	-- Display styles get a dark outline so they read over busy 3D scenes.
	Outline: boolean,
}

export type SpacingToken = "None" | "XXS" | "XS" | "S" | "M" | "L" | "XL" | "XXL"
export type RadiusToken = "S" | "M" | "L" | "XL" | "Pill"
export type SurfaceVariant = "Surface" | "Raised" | "Sunken" | "Accent" | "Glass"
export type ButtonVariant = "Primary" | "Secondary" | "Ghost" | "Danger" | "Success" | "Premium"
export type ButtonSize = "Small" | "Medium" | "Large"
export type ToastKind = "Info" | "Success" | "Warning" | "Error" | "Reward"
export type Vital = "Health" | "Stamina" | "Hunger" | "Warmth"
export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type SpringPreset = { Speed: number, Damping: number }

export type ButtonStyle = {
	Top: Color3, -- gradient top of the face
	Bottom: Color3, -- gradient bottom of the face
	Lip: Color3, -- the darker "3D" base the face presses into
	Stroke: Color3,
	Text: Color3,
	TextOutline: Color3?,
}

export type SurfaceStyle = {
	Gradient: ColorSequence,
	Stroke: Color3,
	StrokeTransparency: number,
	BackgroundTransparency: number,
}

export type RarityStyle = {
	Color: Color3,
	Gradient: ColorSequence,
	Pips: number,
	Order: number,
}

export type ShadowStyle = { Offset: number, Transparency: number }

-- ──────────────────────────────────────────────────────────── Helpers ──

local function vertical(top: Color3, bottom: Color3): ColorSequence
	return ColorSequence.new(top, bottom)
end

local function freeze<T>(t: T): T
	return table.freeze(t :: any) :: any
end

-- ───────────────────────────────────────────────────────────── Colors ──

local Colors = freeze({
	-- Surfaces
	Backdrop = Ink[950], -- modal dimmer
	Background = Ink[900],
	Surface = Ink[800],
	SurfaceRaised = Ink[700],
	SurfaceSunken = Ink[950],
	SurfaceHover = Ink[600],

	-- Borders
	Border = Ink[500],
	BorderStrong = Ink[400],
	BorderFocus = Lantern[400],

	-- Text
	TextPrimary = Ink[50],
	TextSecondary = Ink[200],
	TextMuted = Ink[300],
	TextDisabled = Ink[400],
	TextOnPrimary = Lantern[900],
	TextOutline = Ink[950],

	-- Brand + status
	Primary = Lantern[500],
	PrimaryBright = Lantern[300],
	Danger = Ember[500],
	Success = Moss[500],
	Warning = Sun[500],
	Info = Frost[500],
	Premium = Violet[500],

	-- Currencies
	Embers = Lantern[400], -- soft currency (earned in runs)
	Moonstones = Frost[400], -- permanent currency
	Stardust = Violet[400], -- cosmetic-only currency (purchasable)

	White = Palette.White,
	Black = Palette.Black,
})

-- ────────────────────────────────────────────────────────── Gradients ──

local Gradients = freeze({
	Surface = vertical(Ink[700], Ink[800]),
	Raised = vertical(Ink[600], Ink[700]),
	Sunken = vertical(Ink[950], Ink[900]),
	Accent = vertical(Lantern[300], Lantern[500]),
	Premium = vertical(Violet[400], Violet[600]),
	-- Subtle white sheen used on bar fills (multiplied over the fill colour).
	Sheen = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(235, 235, 235)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200)),
	}),
})

local Surfaces: { [SurfaceVariant]: SurfaceStyle } = freeze({
	Surface = { Gradient = Gradients.Surface, Stroke = Ink[500], StrokeTransparency = 0, BackgroundTransparency = 0 },
	Raised = { Gradient = Gradients.Raised, Stroke = Ink[400], StrokeTransparency = 0, BackgroundTransparency = 0 },
	Sunken = { Gradient = Gradients.Sunken, Stroke = Ink[600], StrokeTransparency = 0, BackgroundTransparency = 0 },
	Accent = { Gradient = Gradients.Accent, Stroke = Lantern[700], StrokeTransparency = 0, BackgroundTransparency = 0 },
	-- Translucent card for the HUD: keeps the 3D world readable behind it.
	Glass = {
		Gradient = Gradients.Surface,
		Stroke = Ink[400],
		StrokeTransparency = 0.35,
		BackgroundTransparency = 0.25,
	},
})

-- ─────────────────────────────────────────────────────── Typography ──

-- Fredoka One: rounded, chunky display face for titles and numbers.
-- Builder Sans: Roblox's clean UI face for body copy (Latin + engine fallback for Arabic).
local DISPLAY_FAMILY = "rbxasset://fonts/families/FredokaOne.json"
local BODY_FAMILY = "rbxasset://fonts/families/BuilderSans.json"

local Fonts = freeze({
	Display = Font.new(DISPLAY_FAMILY, Enum.FontWeight.Regular),
	Body = Font.new(BODY_FAMILY, Enum.FontWeight.Medium),
	BodyBold = Font.new(BODY_FAMILY, Enum.FontWeight.Bold),
	BodyHeavy = Font.new(BODY_FAMILY, Enum.FontWeight.ExtraBold),
})

local Type: { [TextVariant]: TypeStyle } = freeze({
	Hero = { Font = Fonts.Display, Size = 64, Outline = true },
	Display = { Font = Fonts.Display, Size = 44, Outline = true },
	Title = { Font = Fonts.Display, Size = 32, Outline = true },
	Heading = { Font = Fonts.Display, Size = 26, Outline = false },
	BodyLarge = { Font = Fonts.Body, Size = 22, Outline = false },
	Body = { Font = Fonts.Body, Size = 20, Outline = false },
	BodyBold = { Font = Fonts.BodyBold, Size = 20, Outline = false },
	Caption = { Font = Fonts.BodyBold, Size = 18, Outline = false },
	Number = { Font = Fonts.Display, Size = 24, Outline = true },
	NumberLarge = { Font = Fonts.Display, Size = 36, Outline = true },
})

-- ─────────────────────────────────────────────── Spacing / shape ──

local Spacing: { [SpacingToken]: number } = freeze({
	None = 0,
	XXS = 4,
	XS = 8,
	S = 12,
	M = 16,
	L = 24,
	XL = 32,
	XXL = 48,
})

local Radius: { [RadiusToken]: UDim } = freeze({
	S = UDim.new(0, 8),
	M = UDim.new(0, 12),
	L = UDim.new(0, 18),
	XL = UDim.new(0, 24),
	Pill = UDim.new(0.5, 0),
})

local Stroke = freeze({
	Hairline = 1,
	Base = 2, -- the house style: 2-pt outlines on cards, buttons and bars
	Bold = 3,
	Text = 2, -- outline on display text
})

local Shadow: { [string]: ShadowStyle } = freeze({
	Small = { Offset = 2, Transparency = 0.55 },
	Medium = { Offset = 4, Transparency = 0.45 },
	Large = { Offset = 8, Transparency = 0.4 },
})

-- ──────────────────────────────────────────────────────────── Motion ──

local Motion = freeze({
	Duration = freeze({
		Fast = 0.12,
		Base = 0.22,
		Open = 0.28, -- window / popup open (spec: 0.2–0.3 s)
		Close = 0.2,
		CountUp = 0.6,
	}),

	-- Open/close: Back-out pop on open, Quint-in on close (spec).
	Open = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Close = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
	Standard = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Fade = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	CountUp = TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),

	Spring = freeze({
		Snappy = { Speed = 30, Damping = 0.8 } :: SpringPreset, -- presses, toggles
		Bouncy = { Speed = 24, Damping = 0.5 } :: SpringPreset, -- hover pops, rewards
		Smooth = { Speed = 16, Damping = 1 } :: SpringPreset, -- bars, panels
		Shake = { Speed = 45, Damping = 0.35 } :: SpringPreset, -- error shake
	}),

	Scale = freeze({ Hover = 1.05, Press = 0.95 }),

	ToastLifetime = 3.2,
	TooltipDelay = 0.35,
	LongPress = 0.45,
	-- With "Reduce motion" on, springs use this speed (visually instant, no overshoot).
	ReducedSpringSpeed = 120,
})

-- ────────────────────────────────────────────────────────────── Size ──

local Size = freeze({
	MinHitTarget = 44, -- Apple HIG / Material minimum, enforced on every button
	ButtonHeight = freeze({ Small = 44, Medium = 52, Large = 64 }) :: { [ButtonSize]: number },
	ButtonLip = 4, -- depth of the 3D press
	IconSmall = 20,
	IconMedium = 28,
	IconLarge = 40,
	ScrollBar = 6,
	ToastWidth = 320,
	TooltipMaxWidth = 280,
	WindowMax = Vector2.new(920, 640),
})

-- ───────────────────────────────────────────────────── Layers / order ──

local Layer = freeze({
	HUD = 10,
	ModalBackdrop = 19,
	Menus = 20,
	Toasts = 40,
	Overlay = 50, -- tooltips, drag ghosts
	Loading = 100,
})

-- ─────────────────────────────────────────────────── Button styles ──

local ButtonStyles: { [ButtonVariant | "Disabled"]: ButtonStyle } = freeze({
	Primary = {
		Top = Lantern[300],
		Bottom = Lantern[500],
		Lip = Lantern[700],
		Stroke = Lantern[900],
		Text = Lantern[900],
		TextOutline = nil,
	},
	Secondary = {
		Top = Ink[500],
		Bottom = Ink[600],
		Lip = Ink[800],
		Stroke = Ink[950],
		Text = Ink[50],
		TextOutline = Ink[950],
	},
	Ghost = {
		Top = Ink[700],
		Bottom = Ink[700],
		Lip = Ink[900],
		Stroke = Ink[500],
		Text = Ink[100],
		TextOutline = nil,
	},
	Danger = {
		Top = Ember[400],
		Bottom = Ember[500],
		Lip = Ember[700],
		Stroke = Ink[950],
		Text = Palette.White,
		TextOutline = Ember[700],
	},
	Success = {
		Top = Moss[400],
		Bottom = Moss[500],
		Lip = Moss[700],
		Stroke = Ink[950],
		Text = Palette.White,
		TextOutline = Moss[700],
	},
	Premium = {
		Top = Violet[400],
		Bottom = Violet[500],
		Lip = Violet[700],
		Stroke = Ink[950],
		Text = Palette.White,
		TextOutline = Violet[700],
	},
	Disabled = {
		Top = Ink[600],
		Bottom = Ink[600],
		Lip = Ink[800],
		Stroke = Ink[700],
		Text = Ink[300],
		TextOutline = nil,
	},
})

-- ──────────────────────────────────────────────── Toasts / vitals ──

local Toast: { [ToastKind]: { Color: Color3, Icon: Icons.IconName } } = freeze({
	Info = { Color = Frost[400], Icon = "Info" },
	Success = { Color = Moss[400], Icon = "Check" },
	Warning = { Color = Sun[400], Icon = "Alert" },
	Error = { Color = Ember[400], Icon = "Close" },
	Reward = { Color = Lantern[400], Icon = "Gift" },
})

-- Each vital has its own colour *and* icon and a fixed screen position, so
-- colour is never the only cue.
local Vitals: { [Vital]: { Color: Color3, Low: Color3, Icon: Icons.IconName } } = freeze({
	Health = { Color = Ember[400], Low = Ember[600], Icon = "Health" },
	Stamina = { Color = Sun[400], Low = Sun[600], Icon = "Stamina" },
	Hunger = { Color = Moss[400], Low = Moss[600], Icon = "Hunger" },
	-- Warmth drains to a frosty blue as you get colder.
	Warmth = { Color = Lantern[400], Low = Frost[400], Icon = "Warmth" },
})

-- ─────────────────────────────────────────────────────────── Rarity ──

local Rarity: { [Rarity]: RarityStyle } = freeze({
	Common = { Color = Ink[200], Gradient = vertical(Ink[200], Ink[400]), Pips = 1, Order = 1 },
	Uncommon = { Color = Moss[400], Gradient = vertical(Moss[300], Moss[600]), Pips = 2, Order = 2 },
	Rare = { Color = Frost[400], Gradient = vertical(Frost[300], Frost[600]), Pips = 3, Order = 3 },
	Epic = { Color = Violet[400], Gradient = vertical(Violet[300], Violet[600]), Pips = 4, Order = 4 },
	Legendary = { Color = Lantern[400], Gradient = vertical(Lantern[200], Lantern[600]), Pips = 5, Order = 5 },
	Mythic = {
		Color = Ember[400],
		Gradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Ember[300]),
			ColorSequenceKeypoint.new(0.5, Violet[400]),
			ColorSequenceKeypoint.new(1, Frost[400]),
		}),
		Pips = 6,
		Order = 6,
	},
})

-- ─────────────────────────────────────────────────────────── Export ──

local Theme = {
	Palette = Palette,
	Icons = Icons,
	Colors = Colors,
	Gradients = Gradients,
	Surfaces = Surfaces,
	Fonts = Fonts,
	Type = Type,
	Spacing = Spacing,
	Radius = Radius,
	Stroke = Stroke,
	Shadow = Shadow,
	Motion = Motion,
	Size = Size,
	Layer = Layer,
	ButtonStyles = ButtonStyles,
	Toast = Toast,
	Vitals = Vitals,
	Rarity = Rarity,

	Accessibility = freeze({
		MinTouchTextPx = 18, -- text never renders smaller than this on phones
		UIScaleMin = 0.85,
		UIScaleMax = 1.35,
	}),
}

return table.freeze(Theme)
