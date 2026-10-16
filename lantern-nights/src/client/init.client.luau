--!strict
--[[
	Client entry point. Runs every controller in ./Controllers through the
	Init → Start lifecycle (see Shared/Util/Loader).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader = require(ReplicatedStorage.Shared.Util.Loader)

Loader.run(script:WaitForChild("Controllers"), "Client")
