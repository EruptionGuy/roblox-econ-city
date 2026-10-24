-- Hàm tiện ích thuần, không dùng Roblox API. server, client, test dùng chung.
-- chỉ viết cú pháp chung Lua/Luau để test chạy được ngoài Studio

local Util = {}

function Util.clamp(x, lo, hi)
	if x ~= x then
		return lo -- NaN
	end
	if x < lo then
		return lo
	end
	if x > hi then
		return hi
	end
	return x
end

-- giống Math.round của JS: .5 làm tròn về phía +vô cực
function Util.round(x)
	return math.floor(x + 0.5)
end

function Util.roundTo(x, decimals)
	local m = 10 ^ decimals
	return math.floor(x * m + 0.5) / m
end

function Util.deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = Util.deepCopy(v)
	end
	return out
end

function Util.isFiniteNumber(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- phân cách nghìn, 12345.6 thành "12,346"
function Util.formatInt(n)
	local negative = n < 0
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	if negative then
		return "-" .. formatted
	end
	return formatted
end

-- "$12.3k", "-$6,837"
function Util.formatMoney(n)
	local sign = ""
	if n < 0 then
		sign = "-"
	end
	local a = math.abs(n)
	if a >= 1000000 then
		return sign .. "$" .. string.format("%.2fM", a / 1000000)
	elseif a >= 100000 then
		return sign .. "$" .. string.format("%.0fk", a / 1000)
	elseif a >= 10000 then
		return sign .. "$" .. string.format("%.1fk", a / 1000)
	end
	return sign .. "$" .. Util.formatInt(a)
end

-- "$10,000", "-$6,838": ngân sách hiện đủ số như bản web
function Util.formatMoneyFull(n)
	local sign = n < 0 and "-" or ""
	return sign .. "$" .. Util.formatInt(math.abs(n))
end

-- "$0k", "$102k", "$1.25M": GDP hiện theo nghìn như bản web
function Util.formatMoneyK(n)
	local sign = n < 0 and "-" or ""
	local a = math.abs(n)
	if a >= 1000000 then
		return sign .. "$" .. string.format("%.2fM", a / 1000000)
	end
	return sign .. "$" .. string.format("%.0fk", a / 1000)
end

-- cắt theo số ký tự UTF-8, không cắt đôi chữ có dấu
function Util.utf8Truncate(text, maxChars)
	if utf8.len(text) == nil then
		return nil
	end
	if utf8.len(text) <= maxChars then
		return text
	end
	return text:sub(1, utf8.offset(text, maxChars + 1) - 1)
end

-- làm sạch text người dùng nhập. Cắt theo byte trước tiên, rồi check UTF-8, gộp + trim khoảng trắng.
-- rỗng hoặc hỏng thì nil
function Util.cleanUserText(text, maxChars, maxBytes)
	if type(text) ~= "string" then
		return nil
	end
	maxBytes = maxBytes or 200
	if #text > maxBytes then
		text = text:sub(1, maxBytes)
		-- lỡ cắt giữa ký tự nhiều byte thì bỏ vài byte cuối
		local guard = 0
		while utf8.len(text) == nil and #text > 0 and guard < 4 do
			text = text:sub(1, -2)
			guard = guard + 1
		end
	end
	if utf8.len(text) == nil then
		return nil
	end
	text = text:gsub("[%c]", " "):gsub("%s+", " ")
	text = text:match("^%s*(.-)%s*$")
	if text == nil or #text == 0 then
		return nil
	end
	return Util.utf8Truncate(text, maxChars)
end

function Util.formatPercent(x, decimals)
	return string.format("%." .. tostring(decimals or 0) .. "f%%", x * 100)
end

function Util.indexOf(list, value)
	for i, v in ipairs(list) do
		if v == value then
			return i
		end
	end
	return nil
end

-- random có seed, để lần vẽ nào thành phố cũng ra giống nhau
function Util.seededRandom(seed)
	local state = seed % 2147483647
	if state <= 0 then
		state = state + 2147483646
	end
	return function()
		state = (state * 16807) % 2147483647
		return (state - 1) / 2147483646
	end
end

return Util
