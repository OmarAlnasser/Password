--!strict
--[[
	Format — number and time formatting shared by UI and server messages.

		Format.withCommas(12345)   --> "12,345"
		Format.compact(1530000)    --> "1.5M"
		Format.duration(125)       --> "2:05"
]]

local SUFFIXES = { "", "K", "M", "B", "T", "Qa" }

local Format = {}

function Format.withCommas(n: number): string
	local digits = tostring(math.floor(math.abs(n)))
	local formatted = (digits:reverse():gsub("(%d%d%d)", "%1,")):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return (if n < 0 then "-" else "") .. formatted
end

--- Short form for big numbers; below 10,000 it falls back to commas.
function Format.compact(n: number): string
	local abs = math.abs(n)
	if abs < 10000 then
		return Format.withCommas(n)
	end
	local tier = math.min(math.floor(math.log10(abs) / 3), #SUFFIXES - 1)
	local scaled = n / 10 ^ (tier * 3)
	local text = if math.abs(scaled) >= 100
		then string.format("%d", math.floor(scaled))
		else string.format("%.1f", scaled)
	return (text:gsub("%.0$", "")) .. SUFFIXES[tier + 1]
end

--- Seconds → "m:ss" (or "h:mm:ss" past an hour).
function Format.duration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h, m = s // 3600, (s % 3600) // 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s % 60)
	end
	return string.format("%d:%02d", m, s % 60)
end

return table.freeze(Format)
