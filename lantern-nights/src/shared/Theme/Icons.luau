--!strict
--[[
	Icons — the custom Lantern Nights icon set.

	Source art lives in `assets/icons/svg` (hand-authored, 128×128). The
	rendered `assets/icons/png` files are white glyphs with a dark outline, so
	`ImageColor3` tints the fill while the outline stays dark (the chunky
	sticker look).

	Workflow (see docs/SETUP.md, "Icons"):
	  1. Studio → Asset Manager → Bulk Import → select assets/icons/png/*.png
	  2. Paste each resulting rbxassetid into `AssetIds` below.

	Until an id is filled in, the `Icon` component draws `Glyphs[name]`, so
	the UI stays readable before any upload.
]]

export type IconName =
	"Health"
	| "Stamina"
	| "Hunger"
	| "Warmth"
	| "Embers"
	| "Moonstones"
	| "Stardust"
	| "Backpack"
	| "Craft"
	| "Build"
	| "Pets"
	| "Book"
	| "Quests"
	| "Gift"
	| "Crown"
	| "Trade"
	| "Settings"
	| "Close"
	| "Lock"
	| "Star"
	| "Home"
	| "Shop"
	| "Check"
	| "Plus"
	| "Minus"
	| "Sword"
	| "Shield"
	| "Moon"
	| "Sun"
	| "Travel"
	| "Trophy"
	| "Info"
	| "Alert"
	| "Party"
	| "Emote"
	| "Lantern"

-- Fill these in after Bulk Import ("rbxassetid://123…"). Empty = glyph fallback.
local AssetIds: { [IconName]: string } = {
	Health = "",
	Stamina = "",
	Hunger = "",
	Warmth = "",
	Embers = "",
	Moonstones = "",
	Stardust = "",
	Backpack = "",
	Craft = "",
	Build = "",
	Pets = "",
	Book = "",
	Quests = "",
	Gift = "",
	Crown = "",
	Trade = "",
	Settings = "",
	Close = "",
	Lock = "",
	Star = "",
	Home = "",
	Shop = "",
	Check = "",
	Plus = "",
	Minus = "",
	Sword = "",
	Shield = "",
	Moon = "",
	Sun = "",
	Travel = "",
	Trophy = "",
	Info = "",
	Alert = "",
	Party = "",
	Emote = "",
	Lantern = "",
}

-- Text fallbacks that render in Roblox's default font chain.
local Glyphs: { [IconName]: string } = {
	Health = "♥",
	Stamina = "ϟ",
	Hunger = "●",
	Warmth = "▲",
	Embers = "◉",
	Moonstones = "◆",
	Stardust = "✦",
	Backpack = "▣",
	Craft = "⚒",
	Build = "▦",
	Pets = "❖",
	Book = "▤",
	Quests = "!",
	Gift = "✚",
	Crown = "♛",
	Trade = "⇄",
	Settings = "⚙",
	Close = "✕",
	Lock = "■",
	Star = "★",
	Home = "⌂",
	Shop = "$",
	Check = "✓",
	Plus = "+",
	Minus = "−",
	Sword = "†",
	Shield = "⛨",
	Moon = "☾",
	Sun = "☀",
	Travel = "➤",
	Trophy = "♚",
	Info = "i",
	Alert = "!",
	Party = "☺",
	Emote = "☻",
	Lantern = "♨",
}

local Icons = {}

--- Returns the uploaded image for `name`, or "" if it hasn't been uploaded yet.
function Icons.image(name: IconName): string
	return AssetIds[name] or ""
end

--- Text fallback for `name` (used while `image(name)` is empty).
function Icons.glyph(name: IconName): string
	return Glyphs[name] or "?"
end

--- Every icon name, in a stable order (used by the UI Kit gallery and tests).
function Icons.all(): { IconName }
	local names: { IconName } = {}
	for name in AssetIds do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

return table.freeze(Icons)
