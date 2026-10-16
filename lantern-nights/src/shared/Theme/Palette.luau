--!strict
--[[
	Palette — raw colour ramps for Lantern Nights.

	UI code should never read these directly. Read the semantic tokens in
	`Theme.Colors`, so re-skinning the game (or shipping a seasonal palette)
	means editing one mapping, not hunting through screens.

	Art direction: warm lantern light pushing back a cool indigo night.
	The accent hues (Lantern, Ember, Moss, Frost, Violet) are tuned from the
	Okabe–Ito colourblind-safe set. They stay tellable apart under protanopia,
	deuteranopia and tritanopia, and are always paired with an icon or shape
	(never colour alone).
]]

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

export type Ramp = { [number]: Color3 }

local Palette = {
	-- Night neutrals. Backgrounds, surfaces, borders, text.
	Ink = table.freeze({
		[950] = hex("#080913"),
		[900] = hex("#0E0F1F"),
		[800] = hex("#16182E"),
		[700] = hex("#1F2240"),
		[600] = hex("#2A2E55"),
		[500] = hex("#3A3F70"),
		[400] = hex("#5A5F94"),
		[300] = hex("#8A8FBF"),
		[200] = hex("#BFC3E6"),
		[100] = hex("#E6E8F7"),
		[50] = hex("#F7F8FF"),
	}) :: Ramp,

	-- Primary brand: lantern amber (Okabe–Ito orange family).
	Lantern = table.freeze({
		[50] = hex("#FFF6DD"),
		[200] = hex("#FFE09A"),
		[300] = hex("#FFD06B"),
		[400] = hex("#FFB940"),
		[500] = hex("#FF9F1C"),
		[600] = hex("#E07E00"),
		[700] = hex("#A85A00"),
		[900] = hex("#3A1F00"),
	}) :: Ramp,

	-- Danger / health: warm coral, kept clearly apart from Lantern in luminance.
	Ember = table.freeze({
		[300] = hex("#FF9E92"),
		[400] = hex("#FF7A6B"),
		[500] = hex("#F2545B"),
		[600] = hex("#C93A43"),
		[700] = hex("#8E2530"),
	}) :: Ramp,

	-- Success / hunger: bluish green (Okabe–Ito #009E73 family).
	Moss = table.freeze({
		[300] = hex("#8CF0CF"),
		[400] = hex("#4FDDB0"),
		[500] = hex("#1FBF92"),
		[600] = hex("#0F9470"),
		[700] = hex("#0A6450"),
	}) :: Ramp,

	-- Info / cold: sky blue (Okabe–Ito #56B4E9 / #0072B2 family).
	Frost = table.freeze({
		[300] = hex("#A9DBFF"),
		[400] = hex("#6CC1F5"),
		[500] = hex("#3A9BE0"),
		[600] = hex("#1F6FB8"),
		[700] = hex("#164C80"),
	}) :: Ramp,

	-- Premium / epic: violet (Okabe–Ito reddish-purple shifted cooler).
	Violet = table.freeze({
		[300] = hex("#D9C2FF"),
		[400] = hex("#B98CFF"),
		[500] = hex("#9A63F2"),
		[600] = hex("#7442C8"),
		[700] = hex("#4E2A8C"),
	}) :: Ramp,

	-- Stamina / currency: bright yellow (Okabe–Ito #F0E442 family).
	Sun = table.freeze({
		[300] = hex("#FFF3A1"),
		[400] = hex("#FBE45B"),
		[500] = hex("#F2CF2E"),
		[600] = hex("#C9A40F"),
		[700] = hex("#7F6806"),
	}) :: Ramp,

	White = hex("#FFFFFF"),
	Black = hex("#000000"),
}

return table.freeze(Palette)
