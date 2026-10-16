--!strict
--[[
	Audio config. Every sound id the game uses lives in a config module like
	this, so live-ops can swap sounds without touching code.

	The UI defaults below are sounds that ship inside the Roblox client
	(`rbxasset://sounds/...`), so the UI is audible before you upload
	anything. Replace them with your own uploads ("rbxassetid://…") for the
	final mix. An empty string means "silent".
]]

export type UISoundName = "Click" | "Hover" | "Open" | "Close" | "Error" | "Success" | "Reward" | "Toggle" | "Tick"

export type UISoundDef = {
	Id: string,
	Volume: number,
	-- Random ± pitch spread so repeated clicks don't sound robotic.
	PitchJitter: number,
	-- Minimum seconds between plays (stops hover spam when sweeping a grid).
	Cooldown: number,
}

local UI: { [UISoundName]: UISoundDef } = {
	Click = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.55, PitchJitter = 0.06, Cooldown = 0.03 },
	Hover = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.12, PitchJitter = 0.04, Cooldown = 0.06 },
	Open = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.35, PitchJitter = 0.05, Cooldown = 0.1 },
	Close = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.25, PitchJitter = 0.05, Cooldown = 0.1 },
	Error = { Id = "rbxasset://sounds/button.wav", Volume = 0.5, PitchJitter = 0, Cooldown = 0.15 },
	Success = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.45, PitchJitter = 0.03, Cooldown = 0.1 },
	Reward = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, PitchJitter = 0, Cooldown = 0.1 },
	Toggle = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.4, PitchJitter = 0.02, Cooldown = 0.05 },
	Tick = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.15, PitchJitter = 0.08, Cooldown = 0.025 },
}

return table.freeze({
	UI = table.freeze(UI),
})
