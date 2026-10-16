--!strict
--[[
	BootService — server-wide setup that has to happen before anything else.

	For now it creates the Remotes folder that later modules register their
	(rate-limited) RemoteEvents in. Highest priority so it runs first.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BootService = {
	Priority = 1000,
}

function BootService:Init()
	if not ReplicatedStorage:FindFirstChild("Remotes") then
		local remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end
end

return BootService
