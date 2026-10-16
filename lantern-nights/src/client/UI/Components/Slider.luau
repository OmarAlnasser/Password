--!strict
--[[
	Slider — a numeric setting (volume, UI scale, sensitivity).

		Slider(scope, {
			Label = "Music", Value = Preferences.musicVolume,
			Min = 0, Max = 1, Step = 0.05,
			Format = function(v) return `{math.round(v * 100)}%` end,
		})

	• Drag anywhere on the track (mouse or touch); the thumb grows while held.
	• − / + buttons step the value: precise on touch, and how gamepad players
	  change it (D-pad selects them).
	• `OnChanged` replaces the default write (e.g. Preferences.setUIScale).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Motion = require(script.Parent.Parent.Motion)
local Types = require(script.Parent.Parent.Types)
local UISound = require(script.Parent.Parent.UISound)
local Button = require(script.Parent.Button)
local Decor = require(script.Parent.Decor)
local Text = require(script.Parent.Text)

local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

local TRACK_HEIGHT = 12
local THUMB = 28
local STEP_BUTTON = Theme.Size.MinHitTarget

export type Props = Types.LayoutProps & {
	Label: Types.UsedAs<string>,
	Value: Types.Value<number>,
	Min: number,
	Max: number,
	Step: number?,
	Format: ((number) -> string)?,
	OnChanged: ((number) -> ())?,
}

local function Slider(scope: Types.Scope, props: Props): Frame
	local step = props.Step or (props.Max - props.Min) / 20
	local format = props.Format or function(v: number): string
		return string.format("%.2f", v)
	end
	local dragging = scope:Value(false)

	local function commit(raw: number)
		local snapped = math.clamp(math.round((raw - props.Min) / step) * step + props.Min, props.Min, props.Max)
		if math.abs(snapped - peek(props.Value)) < 1e-6 then
			return
		end
		UISound.play("Tick")
		if props.OnChanged then
			props.OnChanged(snapped)
		else
			props.Value:set(snapped)
		end
	end

	local ratio = scope:Computed(function(use): number
		return math.clamp((use(props.Value) - props.Min) / (props.Max - props.Min), 0, 1)
	end)
	local shownRatio = Motion.spring(scope, ratio, Theme.Motion.Spring.Snappy)
	local thumbScale = Motion.spring(
		scope,
		scope:Computed(function(use): number
			return if use(dragging) then 1.25 else 1
		end),
		Theme.Motion.Spring.Bouncy
	)

	local track: Frame? = nil
	local moveConnection: RBXScriptConnection? = nil
	local endConnection: RBXScriptConnection? = nil

	local function stopDrag()
		dragging:set(false)
		if moveConnection then
			moveConnection:Disconnect()
			moveConnection = nil
		end
		if endConnection then
			endConnection:Disconnect()
			endConnection = nil
		end
	end
	table.insert(scope, stopDrag)

	local function setFromScreenX(x: number)
		local t = track
		if not t or t.AbsoluteSize.X <= 0 then
			return
		end
		local alpha = math.clamp((x - t.AbsolutePosition.X) / t.AbsoluteSize.X, 0, 1)
		commit(props.Min + alpha * (props.Max - props.Min))
	end

	local function beginDrag(input: InputObject)
		local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
		if not isMouse and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		stopDrag()
		dragging:set(true)
		setFromScreenX(input.Position.X)
		moveConnection = UserInputService.InputChanged:Connect(function(changed)
			local relevant = if isMouse
				then changed.UserInputType == Enum.UserInputType.MouseMovement
				else changed == input
			if relevant then
				setFromScreenX(changed.Position.X)
			end
		end)
		endConnection = UserInputService.InputEnded:Connect(function(ended)
			if ended == input or (isMouse and ended.UserInputType == Enum.UserInputType.MouseButton1) then
				stopDrag()
			end
		end)
	end

	track = scope:New("Frame")({
		Name = "Track",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, STEP_BUTTON + Theme.Spacing.S, 0.5, 0),
		Size = UDim2.new(1, -2 * (STEP_BUTTON + Theme.Spacing.S), 0, TRACK_HEIGHT),
		BackgroundColor3 = Theme.Colors.SurfaceSunken,
		[Children] = {
			Decor.corner(scope, "Pill"),
			Decor.stroke(scope, Theme.Colors.TextOutline),
			-- Generous invisible hit area so the thin track is easy to grab on phones.
			scope:New("TextButton")({
				Name = "HitArea",
				Text = "",
				BackgroundTransparency = 1,
				Selectable = false,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.new(1, 0, 0, Theme.Size.MinHitTarget),
				[OnEvent("InputBegan")] = beginDrag,
			}),
			scope:New("Frame")({
				Name = "Fill",
				BackgroundColor3 = Theme.Colors.Primary,
				Size = scope:Computed(function(use): UDim2
					return UDim2.fromScale(use(shownRatio), 1)
				end),
				[Children] = { Decor.corner(scope, "Pill") },
			}),
			scope:New("Frame")({
				Name = "Thumb",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = scope:Computed(function(use): UDim2
					return UDim2.fromScale(use(shownRatio), 0.5)
				end),
				Size = UDim2.fromOffset(THUMB, THUMB),
				BackgroundColor3 = Theme.Colors.White,
				ZIndex = 2,
				[Children] = {
					scope:New("UIScale")({ Scale = thumbScale }),
					Decor.corner(scope, "Pill"),
					Decor.stroke(scope, Theme.Colors.TextOutline, Theme.Stroke.Bold),
				},
			}),
		},
	}) :: Frame

	return scope:New("Frame")({
		Name = props.Name or "Slider",
		BackgroundTransparency = 1,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Size = props.Size or UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible,

		[Children] = {
			Decor.list(scope, { Gap = "XXS" }),
			-- Label row: name on the left, live value on the right.
			scope:New("Frame")({
				Name = "Header",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 1,
				[Children] = {
					Text(scope, { Text = props.Label, Variant = "BodyBold" }),
					Text(scope, {
						Text = scope:Computed(function(use): string
							return format(use(props.Value))
						end),
						Variant = "Number",
						Color = Theme.Colors.PrimaryBright,
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.fromScale(1, 0),
						XAlignment = Enum.TextXAlignment.Right,
					}),
				},
			}),
			scope:New("Frame")({
				Name = "Controls",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, STEP_BUTTON),
				LayoutOrder = 2,
				[Children] = {
					Button(scope, {
						Name = "Decrease",
						Icon = "Minus",
						Variant = "Secondary",
						ButtonSize = "Small",
						ClickSound = false,
						Position = UDim2.fromScale(0, 0),
						OnActivated = function()
							commit(peek(props.Value) - step)
						end,
					}),
					track,
					Button(scope, {
						Name = "Increase",
						Icon = "Plus",
						Variant = "Secondary",
						ButtonSize = "Small",
						ClickSound = false,
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.fromScale(1, 0),
						OnActivated = function()
							commit(peek(props.Value) + step)
						end,
					}),
				},
			}),
		},
	}) :: Frame
end

return Slider
