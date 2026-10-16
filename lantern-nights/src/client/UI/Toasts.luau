--!strict
--[[
	Toasts — short notifications that slide in from the right.

		Toasts.show({ Kind = "Success", Title = "Crafted!", Message = "Torch ×1" })
		Toasts.show({ Kind = "Error", Message = "Inventory full" })

	• Up to MAX_VISIBLE at once; extra toasts push the oldest out.
	• Each lives Theme.Motion.ToastLifetime seconds; tap to dismiss early.
	• Kind sets the accent colour *and* icon (never colour alone).
	• "Reward" plays the reward sound and pops in bigger.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Icons = require(ReplicatedStorage.Shared.Theme.Icons)
local Layers = require(script.Parent.Layers)
local Motion = require(script.Parent.Motion)
local Types = require(script.Parent.Types)
local UISound = require(script.Parent.UISound)
local Decor = require(script.Parent.Components.Decor)
local Icon = require(script.Parent.Components.Icon)
local Text = require(script.Parent.Components.Text)

local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

local MAX_VISIBLE = 3
local SLIDE_DISTANCE = Theme.Size.ToastWidth + 40
local EXIT_TIME = 0.25

export type ToastOptions = {
	Kind: Theme.ToastKind?,
	Title: string?,
	Message: string,
	Icon: Icons.IconName?,
	Duration: number?,
}

type Entry = {
	Id: number,
	Options: ToastOptions,
	Leaving: Fusion.Value<boolean>,
	Scope: Types.Scope,
}

local scope = Fusion.scoped(Fusion)
local entries = scope:Value({} :: { Entry })
local nextId = 0

local Toasts = {}

local function remove(id: number)
	local list = table.clone(peek(entries))
	for index, entry in list do
		if entry.Id == id then
			table.remove(list, index)
			entries:set(list)
			-- Let ForValues tear down the view first, then free the entry's state.
			task.defer(Fusion.doCleanup, entry.Scope)
			return
		end
	end
end

local function dismiss(entry: Entry)
	if peek(entry.Leaving) then
		return
	end
	entry.Leaving:set(true)
	task.delay(EXIT_TIME, remove, entry.Id)
end

function Toasts.show(options: ToastOptions)
	nextId += 1
	local entryScope = Fusion.scoped(Fusion)
	local entry: Entry = {
		Id = nextId,
		Options = options,
		Leaving = entryScope:Value(false),
		Scope = entryScope,
	}

	local list = table.clone(peek(entries))
	table.insert(list, entry)
	entries:set(list)

	-- Too many on screen: retire the oldest that isn't already leaving.
	local active = 0
	for _, e in list do
		if not peek(e.Leaving) then
			active += 1
		end
	end
	if active > MAX_VISIBLE then
		for _, e in list do
			if not peek(e.Leaving) then
				dismiss(e)
				break
			end
		end
	end

	local kind = options.Kind or "Info"
	if kind == "Reward" then
		UISound.play("Reward")
	elseif kind == "Error" then
		UISound.play("Error")
	elseif kind == "Success" then
		UISound.play("Success")
	end

	task.delay(options.Duration or Theme.Motion.ToastLifetime, dismiss, entry)
end

local function ToastView(viewScope: Types.Scope, entry: Entry): Instance
	local options = entry.Options
	local kind = options.Kind or "Info"
	local style = Theme.Toast[kind]
	local entered = viewScope:Value(false)
	task.defer(function()
		entered:set(true)
	end)

	local offset = Motion.spring(
		viewScope,
		viewScope:Computed(function(use): number
			return if use(entered) and not use(entry.Leaving) then 0 else SLIDE_DISTANCE
		end),
		if kind == "Reward" then Theme.Motion.Spring.Bouncy else Theme.Motion.Spring.Snappy
	)

	return viewScope:New("TextButton")({
		Name = `Toast{entry.Id}`,
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(Theme.Size.ToastWidth, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = entry.Id,
		[OnEvent("Activated")] = function()
			dismiss(entry)
		end,

		[Children] = {
			viewScope:New("Frame")({
				Name = "Panel",
				Position = viewScope:Computed(function(use): UDim2
					return UDim2.fromOffset(use(offset), 0)
				end),
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = Theme.Colors.White,
				[Children] = {
					Decor.corner(viewScope, "M"),
					Decor.gradient(viewScope, Theme.Gradients.Raised),
					Decor.stroke(viewScope, style.Color),
					Decor.padding(viewScope, "S"),
					viewScope:New("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, Theme.Spacing.S),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					Icon(viewScope, {
						Icon = options.Icon or style.Icon,
						Color = style.Color,
						Size = UDim2.fromOffset(Theme.Size.IconLarge, Theme.Size.IconLarge),
						LayoutOrder = 1,
					}),
					viewScope:New("Frame")({
						Name = "Copy",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, -(Theme.Size.IconLarge + Theme.Spacing.S), 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						LayoutOrder = 2,
						[Children] = {
							Decor.list(viewScope, { Gap = "None" }),
							if options.Title
								then Text(viewScope, {
									Text = options.Title,
									Variant = "Heading",
									Color = style.Color,
									LayoutOrder = 1,
								})
								else nil,
							Text(viewScope, {
								Text = options.Message,
								Variant = "Body",
								Wrapped = true,
								Size = UDim2.fromScale(1, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								LayoutOrder = 2,
							}),
						},
					}),
				},
			}),
		},
	})
end

--- Builds the toast stack in the Toasts layer. Called once by UIController.
function Toasts.mount()
	scope:New("Frame")({
		Name = "ToastStack",
		Parent = Layers.get("Toasts"),
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Theme.Spacing.M, 0, Theme.Spacing.M),
		Size = UDim2.fromOffset(Theme.Size.ToastWidth, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		[Children] = {
			Decor.list(scope, { Gap = "XS", HAlign = Enum.HorizontalAlignment.Right }),
			scope:ForValues(entries, function(_, viewScope: Types.Scope, entry: Entry)
				return ToastView(viewScope, entry)
			end),
		},
	})
end

return Toasts
