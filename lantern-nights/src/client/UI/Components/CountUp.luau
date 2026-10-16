--!strict
--[[
	CountUp — a number that rolls up (or down) to its new value and pops.

		CountUp(scope, { Value = embers, Variant = "NumberLarge", Format = Format.compact })

	Used for currencies, damage totals and results-screen stats. The roll and
	pop are skipped under Reduce motion (the number just changes).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Motion = require(script.Parent.Parent.Motion)
local Types = require(script.Parent.Parent.Types)
local Text = require(script.Parent.Text)

local Children, peek = Fusion.Children, Fusion.peek

export type Props = Types.LayoutProps & {
	Value: Types.UsedAs<number>,
	Variant: Types.UsedAs<Theme.TextVariant>?,
	Color: Types.UsedAs<Color3>?,
	Format: ((number) -> string)?,
	XAlignment: Types.UsedAs<Enum.TextXAlignment>?,
	-- Pop when the value goes up (default true).
	PopOnIncrease: boolean?,
}

local function CountUp(scope: Types.Scope, props: Props): TextLabel
	local format = props.Format or Format.withCommas
	local shown = Motion.tween(scope, props.Value, Theme.Motion.CountUp)
	local popScale, pop = Motion.pop(scope, 1.15)

	-- Only state can change; a constant number never needs the pop observer.
	if props.PopOnIncrease ~= false and typeof(props.Value) == "table" then
		local last = peek(props.Value)
		scope:Observer(props.Value):onChange(function()
			local now = peek(props.Value)
			if now > last then
				pop()
			end
			last = now
		end)
	end

	return Text(scope, {
		Name = props.Name or "CountUp",
		Text = scope:Computed(function(use): string
			return format(math.round(use(shown)))
		end),
		Variant = props.Variant or "Number",
		Color = props.Color,
		XAlignment = props.XAlignment,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Size = props.Size,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		Visible = props.Visible,
		[Children] = scope:New("UIScale")({ Scale = popScale }),
	})
end

return CountUp
