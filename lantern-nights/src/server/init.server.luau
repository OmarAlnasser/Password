--!strict
--[[
	Server entry point. Runs every service in ./Services through the
	Init → Start lifecycle (see Shared/Util/Loader).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader = require(ReplicatedStorage.Shared.Util.Loader)

Loader.run(script:WaitForChild("Services"), "Server")
