--!strict
--[[
	Loader — tiny lifecycle for services (server) and controllers (client).

	Every ModuleScript in the folder may export:
	  Priority: number?        higher runs first (default 0)
	  Init(self)               synchronous setup; don't yield, don't call other modules' APIs that need Start
	  Start(self)              runs after *every* Init has finished, each in its own thread

	An error in one module is reported with its name and doesn't stop the others.
]]

export type Module = {
	Priority: number?,
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
}

type Loaded = { name: string, module: Module }

local Loader = {}

function Loader.run(folder: Instance, label: string)
	local loaded: { Loaded } = {}

	for _, child in folder:GetChildren() do
		if not child:IsA("ModuleScript") then
			continue
		end
		local ok, result = pcall(require, child)
		if not ok then
			warn(`[{label}] failed to require {child.Name}: {result}`)
		elseif type(result) == "table" then
			table.insert(loaded, { name = child.Name, module = result :: Module })
		end
	end

	table.sort(loaded, function(a, b)
		local pa, pb = a.module.Priority or 0, b.module.Priority or 0
		if pa ~= pb then
			return pa > pb
		end
		return a.name < b.name
	end)

	for _, entry in loaded do
		local init = entry.module.Init
		if init then
			local ok, err = pcall(init, entry.module)
			if not ok then
				warn(`[{label}] {entry.name}.Init failed: {err}`)
			end
		end
	end

	for _, entry in loaded do
		local start = entry.module.Start
		if start then
			task.spawn(function()
				local ok, err = xpcall(start, debug.traceback, entry.module)
				if not ok then
					warn(`[{label}] {entry.name}.Start failed: {err}`)
				end
			end)
		end
	end
end

return Loader
