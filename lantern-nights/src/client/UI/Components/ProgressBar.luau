--!strict
--[[
	ProgressBar — vitals, XP, boss health, crafting progress.

		ProgressBar(scope, {
			Value = health, Max = 100,
			Color = Theme.Vitals.Health.Color,
			Icon = "Health",
			ShowText = true,
		})

	• The fill springs to its new value.
	• A pale "ghost" segment trails behind on losses (shows how much you just
	  took), then drains after a short beat (fighting-game style).
	• Below `LowThreshold` the outline pulses and the fill turns `LowColor`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Icons = require(ReplicatedStorage.Shared.Theme.Icons)
local Motion = require(script.Parent.Parent.Motion)
local Preferences = require(script.Parent.Parent.Preferences)
local Types = require(script.Parent.Parent.Types)
local Decor = require(script.Parent.Decor)
local Icon = require(script.Parent.Icon)
local Text = require(script.Parent.Text)

local Children, peek = Fusion.Children, Fusion.peek

local GHOST_DELAY = 0.45

export type Props = Types.LayoutProps & {
	Value: Types.UsedAs<number>,
	Max: Types.UsedAs<number>,
	Color: Types.UsedAs<Color3>,
	LowColor: Types.UsedAs<Color3>?,
	LowThreshold: number?, -- 0..1, default 0.25
	Icon: Icons.IconName?,
	ShowText: boolean?,
	Height: number?,
}

local function ProgressBar(scope: Types.Scope, props: Props): Frame
	local height = props.Height or 22
	local lowThreshold = props.LowThreshold or 0.25

	local ratio = scope:Computed(function(use): number
		local max = use(props.Max)
		if max <= 0 then
			return 0
		end
		return math.clamp(use(props.Value) / max, 0, 1)
	end)
	local fill = Motion.spring(scope, ratio, Theme.Motion.Spring.Smooth)

	-- Ghost follows instantly on gains and after a delay on losses.
	local ghostTarget = scope:Value(peek(ratio))
	local ghostToken = 0
	scope:Observer(ratio):onChange(function()
		local now = peek(ratio)
		ghostToken += 1
		if now >= peek(ghostTarget) then
			ghostTarget:set(now)
		else
			local mine = ghostToken
			task.delay(GHOST_DELAY, function()
				if ghostToken == mine then
					ghostTarget:set(peek(ratio))
				end
			end)
		end
	end)
	table.insert(scope, function()
		ghostToken += 1
	end)
	local ghost = Motion.tween(scope, ghostTarget, Theme.Motion.Standard)

	local isLow = scope:Computed(function(use): boolean
		return use(ratio) <= lowThreshold
	end)

	local lowColor = props.LowColor
	local fillColor = scope:Computed(function(use): Color3
		if lowColor and use(isLow) then
			return use(lowColor)
		end
		return use(props.Color)
	end)

	-- Low-value pulse on the outline (0..1), driven only while low.
	local pulse = scope:Value(0)
	local pulseConnection: RBXScriptConnection? = nil
	local function updatePulse()
		local shouldPulse = peek(isLow) and not peek(Preferences.reduceMotion)
		if shouldPulse and not pulseConnection then
			pulseConnection = RunService.RenderStepped:Connect(function()
				pulse:set((math.sin(os.clock() * 8) + 1) / 2)
			end)
		elseif not shouldPulse and pulseConnection then
			pulseConnection:Disconnect()
			pulseConnection = nil
			pulse:set(0)
		end
	end
	scope:Observer(isLow):onBind(updatePulse)
	scope:Observer(Preferences.reduceMotion):onChange(updatePulse)
	table.insert(scope, function()
		if pulseConnection then
			pulseConnection:Disconnect()
		end
	end)

	local iconSize = height + 10

	return scope:New("Frame")({
		Name = props.Name or "ProgressBar",
		BackgroundTransparency = 1,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Size = props.Size or UDim2.new(1, 0, 0, iconSize),
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		Visible = props.Visible,

		[Children] = {
			scope:New("Frame")({
				Name = "Track",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				Size = UDim2.new(1, if props.Icon then -iconSize / 2 else 0, 0, height),
				BackgroundColor3 = Theme.Colors.SurfaceSunken,
				BackgroundTransparency = 0.15,
				ClipsDescendants = true,
				[Children] = {
					Decor.corner(scope, "Pill"),
					Decor.stroke(
						scope,
						scope:Computed(function(use): Color3
							return if use(isLow) then use(fillColor) else Theme.Colors.TextOutline
						end),
						Theme.Stroke.Base,
						scope:Computed(function(use): number
							return if use(isLow) then 0.6 * use(pulse) else 0
						end)
					),
					scope:New("Frame")({
						Name = "Ghost",
						BackgroundColor3 = Theme.Colors.White,
						BackgroundTransparency = 0.35,
						Size = scope:Computed(function(use): UDim2
							return UDim2.fromScale(math.max(use(ghost), use(fill)), 1)
						end),
						[Children] = { Decor.corner(scope, "Pill") },
					}),
					scope:New("Frame")({
						Name = "Fill",
						BackgroundColor3 = fillColor,
						Size = scope:Computed(function(use): UDim2
							return UDim2.fromScale(use(fill), 1)
						end),
						Visible = scope:Computed(function(use): boolean
							return use(fill) > 0.001
						end),
						[Children] = {
							Decor.corner(scope, "Pill"),
							Decor.gradient(scope, Theme.Gradients.Sheen),
							-- Top highlight for a glossy, rounded read.
							scope:New("Frame")({
								Name = "Shine",
								BackgroundColor3 = Theme.Colors.White,
								BackgroundTransparency = 0.7,
								Position = UDim2.new(0, 6, 0, 3),
								Size = UDim2.new(1, -12, 0.28, 0),
								[Children] = { Decor.corner(scope, "Pill") },
							}),
						},
					}),
					if props.ShowText
						then Text(scope, {
							Name = "Label",
							Text = scope:Computed(function(use): string
								return `{math.ceil(use(props.Value))}/{math.ceil(use(props.Max))}`
							end),
							Variant = "Caption",
							Outline = true,
							Color = Theme.Colors.White,
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.fromScale(0.5, 0.5),
							XAlignment = Enum.TextXAlignment.Center,
							ZIndex = 3,
						})
						else nil,
				},
			}),

			-- Icon disc overlapping the left end of the bar.
			if props.Icon
				then scope:New("Frame")({
					Name = "IconDisc",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromScale(0, 0.5),
					Size = UDim2.fromOffset(iconSize, iconSize),
					BackgroundColor3 = Theme.Colors.SurfaceRaised,
					ZIndex = 2,
					[Children] = {
						Decor.corner(scope, "Pill"),
						Decor.stroke(scope, Theme.Colors.TextOutline),
						Icon(scope, {
							Icon = props.Icon,
							Color = fillColor,
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.fromScale(0.5, 0.5),
							Size = UDim2.fromScale(0.72, 0.72),
						}),
					},
				})
				else nil,
		},
	}) :: Frame
end

return ProgressBar
