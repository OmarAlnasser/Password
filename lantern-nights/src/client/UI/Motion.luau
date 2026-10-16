--!strict
--[[
	Motion — every animation in the UI goes through these helpers, so
	"Reduce motion" is honoured in one place.

	  Motion.spring(scope, goal, preset?)  Fusion Spring; snaps instantly with Reduce motion
	  Motion.tween(scope, goal, info)      Fusion Tween;  zero-length with Reduce motion
	  Motion.shake(scope)                  -> (offset state, trigger)  error shake for invalid actions
	  Motion.pop(scope)                    -> (scale state, trigger)   one-shot "boing" for rewards / counters

	Presets live in Theme.Motion so the whole game shares one feel.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Preferences = require(script.Parent.Preferences)
local Types = require(script.Parent.Types)

local peek = Fusion.peek

local INSTANT = TweenInfo.new(0)
local SHAKE_SEQUENCE = { 10, -8, 6, -4, 2, 0 }
local SHAKE_STEP = 0.035

local Motion = {}

--- A spring towards `goal` using a Theme preset (default: Snappy).
function Motion.spring<T>(scope: Types.Scope, goal: Types.UsedAs<T>, preset: Theme.SpringPreset?): Fusion.Spring<T>
	local p = preset or Theme.Motion.Spring.Snappy
	local speed = scope:Computed(function(use): number
		return if use(Preferences.reduceMotion) then Theme.Motion.ReducedSpringSpeed else p.Speed
	end)
	local damping = scope:Computed(function(use): number
		return if use(Preferences.reduceMotion) then 1 else p.Damping
	end)
	return scope:Spring(goal, speed, damping)
end

--- A tween towards `goal`. `info` may itself be state (e.g. open vs close easing).
function Motion.tween<T>(scope: Types.Scope, goal: Types.UsedAs<T>, info: Types.UsedAs<TweenInfo>): Fusion.Tween<T>
	local tweenInfo = scope:Computed(function(use): TweenInfo
		return if use(Preferences.reduceMotion) then INSTANT else use(info)
	end)
	return scope:Tween(goal, tweenInfo)
end

--- Horizontal error shake. Bind the returned state to a Position X offset
--- and call `trigger()` on an invalid action. With Reduce motion on it does
--- nothing; callers also flash/sound, so the feedback isn't lost.
function Motion.shake(scope: Types.Scope): (Fusion.Spring<number>, () -> ())
	local target = scope:Value(0)
	local generation = 0
	-- Cancel any in-flight shake when the owning scope is cleaned up.
	table.insert(scope, function()
		generation += 1
	end)

	local function trigger()
		if peek(Preferences.reduceMotion) then
			return
		end
		generation += 1
		local mine = generation
		task.spawn(function()
			for _, x in SHAKE_SEQUENCE do
				if generation ~= mine then
					return
				end
				target:set(x)
				task.wait(SHAKE_STEP)
			end
		end)
	end

	return Motion.spring(scope, target, Theme.Motion.Spring.Shake), trigger
end

--- One-shot pop: scale jumps to `amount` then springs back to 1.
function Motion.pop(scope: Types.Scope, amount: number?): (Fusion.Spring<number>, () -> ())
	local target = scope:Value(1)
	local spring = Motion.spring(scope, target, Theme.Motion.Spring.Bouncy)
	local function trigger()
		if peek(Preferences.reduceMotion) then
			return
		end
		-- Kick the spring directly so it overshoots from the peak, then settle at 1.
		spring:setPosition(amount or 1.18)
		target:set(1)
	end
	return spring, trigger
end

return Motion
