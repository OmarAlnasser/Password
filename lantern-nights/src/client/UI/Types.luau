--!strict
--[[
	Shared type aliases for the UI layer, so every component signature reads
	the same way:

		local function Card(scope: Types.Scope, props: Card.Props): Frame
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage.Packages.Fusion)

export type Scope = Fusion.Scope<typeof(Fusion)>
export type UsedAs<T> = Fusion.UsedAs<T>
export type Child = Fusion.Child
export type Value<T> = Fusion.Value<T>
export type StateObject<T> = Fusion.StateObject<T>

-- Placement props every visual component accepts and forwards to its root.
export type LayoutProps = {
	Name: string?,
	Position: UsedAs<UDim2>?,
	AnchorPoint: UsedAs<Vector2>?,
	Size: UsedAs<UDim2>?,
	LayoutOrder: UsedAs<number>?,
	ZIndex: UsedAs<number>?,
	Visible: UsedAs<boolean>?,
}

return {}
