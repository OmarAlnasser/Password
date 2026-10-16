--!strict
--[[
	WindowManager — opens and closes full-screen windows, one at a time.

		WindowManager.register("Inventory", function(scope, isOpen, close)
			return Window(scope, { Title = "Inventory", Icon = "Backpack", Open = isOpen, OnClose = close, ... })
		end)
		WindowManager.open("Inventory")
		WindowManager.toggle("Inventory")
		WindowManager.current      -- Value<string?> (HUD hides non-essentials while a window is open)

	• Windows are built lazily on first open, then kept (re-opening is instant).
	• Opening one window closes the current one.
	• Tapping the dimmed backdrop or pressing B (gamepad) closes it.
	• The first button in a window is selected for gamepad players.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Layers = require(script.Parent.Layers)
local Motion = require(script.Parent.Motion)
local Responsive = require(script.Parent.Responsive)
local Types = require(script.Parent.Types)
local UISound = require(script.Parent.UISound)

local OnEvent, peek = Fusion.OnEvent, Fusion.peek

export type Builder = (scope: Types.Scope, isOpen: Types.StateObject<boolean>, close: () -> ()) -> Instance

local CLOSE_ACTION = "LN_CloseWindow"
local BACKDROP_TRANSPARENCY = 0.45

local scope = Fusion.scoped(Fusion)
local builders: { [string]: Builder } = {}
local built: { [string]: Instance } = {}

local current = scope:Value(nil :: string?)

local WindowManager = {
	current = current,
	anyOpen = scope:Computed(function(use): boolean
		return use(current) ~= nil
	end),
}

function WindowManager.register(name: string, builder: Builder)
	assert(builders[name] == nil, `window "{name}" registered twice`)
	builders[name] = builder
end

function WindowManager.isOpen(name: string): Types.StateObject<boolean>
	return scope:Computed(function(use): boolean
		return use(current) == name
	end)
end

local function selectFirstButton(root: Instance)
	if peek(Responsive.inputMode) ~= "Gamepad" then
		return
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("GuiButton") and descendant.Selectable and descendant.Name ~= "Close" then
			GuiService.SelectedObject = descendant
			return
		end
	end
end

local function ensureBuilt(name: string): Instance?
	local existing = built[name]
	if existing then
		return existing
	end
	local builder = builders[name]
	if not builder then
		warn(`[WindowManager] no window registered as "{name}"`)
		return nil
	end
	local instance = builder(scope, WindowManager.isOpen(name), function()
		WindowManager.close(name)
	end)
	instance.Parent = Layers.get("Menus")
	built[name] = instance
	return instance
end

function WindowManager.open(name: string)
	if peek(current) == name then
		return
	end
	local instance = ensureBuilt(name)
	if not instance then
		return
	end
	current:set(name)
	UISound.play("Open")
	task.defer(selectFirstButton, instance)
end

--- Closes `name` (or whichever window is open when `name` is nil).
function WindowManager.close(name: string?)
	local open = peek(current)
	if open == nil or (name ~= nil and open ~= name) then
		return
	end
	current:set(nil)
	UISound.play("Close")
	GuiService.SelectedObject = nil
end

function WindowManager.toggle(name: string)
	if peek(current) == name then
		WindowManager.close(name)
	else
		WindowManager.open(name)
	end
end

--- Builds the shared backdrop and binds the gamepad close action. Called once by UIController.
function WindowManager.mount()
	local transparency = Motion.tween(
		scope,
		scope:Computed(function(use): number
			return if use(current) ~= nil then BACKDROP_TRANSPARENCY else 1
		end),
		Theme.Motion.Fade
	)

	scope:New("TextButton")({
		Name = "Backdrop",
		Parent = Layers.get("ModalBackdrop"),
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Backdrop,
		BackgroundTransparency = transparency,
		Visible = scope:Computed(function(use): boolean
			return use(transparency) < 0.99
		end),
		-- Blocks clicks/taps from reaching the world or HUD behind the window.
		Active = true,
		[OnEvent("Activated")] = function()
			WindowManager.close()
		end,
	})

	scope:Observer(current):onChange(function()
		if peek(current) ~= nil then
			ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, inputState)
				if inputState == Enum.UserInputState.Begin then
					WindowManager.close()
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
		else
			ContextActionService:UnbindAction(CLOSE_ACTION)
		end
	end)
end

return WindowManager
