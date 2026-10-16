--!strict
--[[
	Tooltip — one shared tooltip, reachable from every input type.

		Tooltip.attach(scope, someButton, "Craft a Torch (2 Wood, 1 Resin)")

	  Mouse     hover for 0.35 s → show; leave → hide
	  Touch     long-press 0.45 s → show; lift finger → hide after 1.5 s
	            (the long-press also suppresses that tap's click; see `consumeLongPress`)
	  Gamepad   select the element → show after 0.35 s; move off → hide

	The tooltip sits above the target (or below if there's no room) and is
	clamped inside the safe area.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Layers = require(script.Parent.Layers)
local Motion = require(script.Parent.Motion)
local Responsive = require(script.Parent.Responsive)
local Types = require(script.Parent.Types)
local Decor = require(script.Parent.Components.Decor)
local Text = require(script.Parent.Components.Text)

local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

local GAP = 8
local EDGE_MARGIN = 8
local TOUCH_LINGER = 1.5
local LONG_PRESS_ATTRIBUTE = "LN_LongPressed"

local state = {
	text = nil :: Fusion.Value<string>?,
	shown = nil :: Fusion.Value<boolean>?,
	position = nil :: Fusion.Value<UDim2>?,
	anchor = nil :: Fusion.Value<Vector2>?,
	frame = nil :: Frame?,
	target = nil :: GuiObject?,
	-- Bumped on every show/hide, so a stale delayed show/hide does nothing.
	generation = 0,
}

local Tooltip = {}

local function reposition()
	local frame, target, position, anchor = state.frame, state.target, state.position, state.anchor
	if not (frame and target and position and anchor) then
		return
	end
	local root = Layers.get("Overlay")
	local scale = peek(Responsive.scale)
	local rootSize = root.AbsoluteSize / scale
	local size = frame.AbsoluteSize / scale
	local topLeft = Layers.toLocal("Overlay", target.AbsolutePosition)
	local targetSize = target.AbsoluteSize / scale

	local centerX = topLeft.X + targetSize.X / 2
	local x = math.clamp(centerX, EDGE_MARGIN + size.X / 2, rootSize.X - EDGE_MARGIN - size.X / 2)

	-- Prefer above the target; flip below when it would leave the safe area.
	if topLeft.Y - GAP - size.Y >= EDGE_MARGIN then
		anchor:set(Vector2.new(0.5, 1))
		position:set(UDim2.fromOffset(x, topLeft.Y - GAP))
	else
		anchor:set(Vector2.new(0.5, 0))
		position:set(UDim2.fromOffset(x, topLeft.Y + targetSize.Y + GAP))
	end
end

--- Shows `text` next to `target` immediately.
function Tooltip.show(target: GuiObject, text: string)
	local shown, textValue = state.shown, state.text
	if not (shown and textValue) or text == "" then
		return
	end
	state.generation += 1
	state.target = target
	textValue:set(text)
	shown:set(true)
	-- Size is known only after the text lays out; place again next frame.
	reposition()
	task.defer(reposition)
end

--- Hides the tooltip (optionally only if it's still showing `target`).
function Tooltip.hide(target: GuiObject?)
	if target and state.target ~= target then
		return
	end
	state.generation += 1
	state.target = nil
	if state.shown then
		state.shown:set(false)
	end
end

local function showAfter(delaySeconds: number, target: GuiObject, text: Types.UsedAs<string>)
	state.generation += 1
	local mine = state.generation
	task.delay(delaySeconds, function()
		if state.generation == mine and target.Parent then
			Tooltip.show(target, peek(text))
		end
	end)
end

--- True (once) if the last touch on `target` was a long-press that opened a
--- tooltip. Buttons call this in Activated to skip the click.
function Tooltip.consumeLongPress(target: GuiObject): boolean
	if target:GetAttribute(LONG_PRESS_ATTRIBUTE) then
		target:SetAttribute(LONG_PRESS_ATTRIBUTE, nil)
		return true
	end
	return false
end

--- Wires hover / long-press / selection tooltips onto an existing element.
function Tooltip.attach(scope: Types.Scope, target: GuiObject, text: Types.UsedAs<string>)
	local touchToken = 0

	scope:Hydrate(target)({
		[OnEvent("MouseEnter")] = function()
			if peek(Responsive.inputMode) == "KeyboardMouse" then
				showAfter(Theme.Motion.TooltipDelay, target, text)
			end
		end,
		[OnEvent("MouseLeave")] = function()
			if peek(Responsive.inputMode) == "KeyboardMouse" then
				Tooltip.hide(target)
			end
		end,
		[OnEvent("SelectionGained")] = function()
			showAfter(Theme.Motion.TooltipDelay, target, text)
		end,
		[OnEvent("SelectionLost")] = function()
			Tooltip.hide(target)
		end,
		[OnEvent("InputBegan")] = function(input: InputObject)
			if input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			touchToken += 1
			local mine = touchToken
			target:SetAttribute(LONG_PRESS_ATTRIBUTE, nil)
			task.delay(Theme.Motion.LongPress, function()
				if touchToken == mine and target.Parent then
					target:SetAttribute(LONG_PRESS_ATTRIBUTE, true)
					Tooltip.show(target, peek(text))
				end
			end)
		end,
		[OnEvent("InputEnded")] = function(input: InputObject)
			if input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			touchToken += 1
			if state.target == target then
				local generation = state.generation
				task.delay(TOUCH_LINGER, function()
					if state.generation == generation then
						Tooltip.hide(target)
					end
				end)
			end
		end,
	})

	table.insert(scope, function()
		Tooltip.hide(target)
	end)
end

--- Builds the shared tooltip in the Overlay layer. Called once by UIController.
function Tooltip.mount(scope: Types.Scope)
	local text = scope:Value("")
	local shown = scope:Value(false)
	local position = scope:Value(UDim2.new())
	local anchor = scope:Value(Vector2.new(0.5, 1))
	state.text, state.shown, state.position, state.anchor = text, shown, position, anchor

	local alpha = Motion.tween(
		scope,
		scope:Computed(function(use): number
			return if use(shown) then 0 else 1
		end),
		Theme.Motion.Fade
	)
	local pop = Motion.spring(
		scope,
		scope:Computed(function(use): number
			return if use(shown) then 1 else 0.9
		end),
		Theme.Motion.Spring.Bouncy
	)

	state.frame = scope:New("Frame")({
		Name = "Tooltip",
		Parent = Layers.get("Overlay"),
		AnchorPoint = anchor,
		Position = position,
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = Theme.Colors.SurfaceRaised,
		BackgroundTransparency = alpha,
		Visible = scope:Computed(function(use): boolean
			return use(alpha) < 0.99
		end),
		ZIndex = 100,

		[Children] = {
			scope:New("UIScale")({ Scale = pop }),
			Decor.corner(scope, "M"),
			Decor.stroke(scope, Theme.Colors.BorderStrong, Theme.Stroke.Base, alpha),
			Decor.padding(scope, "XS", "S"),
			Text(scope, {
				Text = text,
				Variant = "Caption",
				Color = Theme.Colors.TextPrimary,
				Transparency = alpha,
				Wrapped = true,
				AutomaticSize = Enum.AutomaticSize.XY,
				Size = UDim2.fromOffset(0, 0),
				-- Capping an auto-sized label's width makes it wrap instead of growing.
				[Children] = scope:New("UISizeConstraint")({
					MaxSize = Vector2.new(Theme.Size.TooltipMaxWidth - Theme.Spacing.S * 2, math.huge),
				}),
			}),
		},

		[OnEvent("InputBegan")] = function()
			Tooltip.hide()
		end,
	}) :: Frame

	-- Wrapped text changes size after layout; keep it on-screen.
	state.frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(reposition)
end

return Tooltip
