-- BXH toàn cầu + theo lớp, tính theo "điểm thịnh vượng". Mỗi người chỉ giữ điểm cao nhất (1 dòng/người).
-- OrderedDataStore chỉ lưu số nguyên nên điểm x100.
-- cache kết quả đọc LEADERBOARD_CACHE_SECONDS giây cho khỏi vượt quota DataStore

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("EconCity")

local Config = require(Shared:WaitForChild("Config"))

local LeaderboardService = {}
LeaderboardService.__index = LeaderboardService

local SCALE = 100
local NAME_RETRY_SECONDS = 300

-- deps: persistence, resolveName(userId), getClass(code) (record hoặc nil),
--   resolveNames({userId...}) trả { [userId] = tên } (tuỳ chọn, tra gộp 1 lần), clock (os.clock, để hết hạn cache)
function LeaderboardService.new(deps)
	local self = setmetatable({}, LeaderboardService)
	self.persistence = deps.persistence
	self.resolveNames = deps.resolveNames
	self.resolveName = deps.resolveName
	self.getClass = deps.getClass
	self.clock = deps.clock or os.clock
	self.names = {}
	self.nameFailedAt = {} -- [userId] = lúc tra tên lỗi, để không retry liên tục
	self.lastSubmitted = {} -- [storeName|userId] = điểm đã ghi ok, tránh ghi thừa
	self.cache = {} -- [storeName] = { at, entries }
	return self
end

local function classStore(code)
	return Config.DATASTORE.leaderboardClassPrefix .. code
end
LeaderboardService.classStore = classStore

local function validUser(userId)
	-- Player1, Player2... trong Studio có UserId <= 0, không đưa lên bảng
	return type(userId) == "number" and userId > 0
end

function LeaderboardService:rememberName(userId, name)
	if name then
		self.names[userId] = name
	end
end

function LeaderboardService:_submitTo(storeName, userId, score)
	local cacheKey = storeName .. "|" .. tostring(userId)
	local last = self.lastSubmitted[cacheKey]
	if last and score <= last then
		return
	end
	local ok = self.persistence:orderedSetMax(storeName, tostring(userId), score * SCALE)
	if ok then
		self.lastSubmitted[cacheKey] = score
	end
end

-- chỉ ghi nếu cao hơn điểm đã có
function LeaderboardService:submit(userId, name, score, classCodes)
	if not validUser(userId) or type(score) ~= "number" or score <= 0 then
		return
	end
	self:rememberName(userId, name)
	self:_submitTo(Config.DATASTORE.leaderboardGlobal, userId, score)
	for _, code in ipairs(classCodes or {}) do
		self:_submitTo(classStore(code), userId, score)
	end
end

-- dùng khi xoá data theo yêu cầu. Xoá cả ở bảng luật cũ (LEGACY_LEADERBOARDS) dù giờ không ghi nữa
function LeaderboardService:removeUser(userId, classCodes)
	local id = tostring(userId)
	self.persistence:orderedRemove(Config.DATASTORE.leaderboardGlobal, id)
	for _, code in ipairs(classCodes or {}) do
		self.persistence:orderedRemove(classStore(code), id)
	end
	for _, legacy in ipairs(Config.LEGACY_LEADERBOARDS) do
		self.persistence:orderedRemove(legacy.global, id)
		for _, code in ipairs(classCodes or {}) do
			self.persistence:orderedRemove(legacy.classPrefix .. code, id)
		end
	end
	for key in pairs(self.lastSubmitted) do
		if key:sub(-#tostring(userId) - 1) == "|" .. tostring(userId) then
			self.lastSubmitted[key] = nil
		end
	end
	self.cache = {}
	self.names[userId] = nil
end

function LeaderboardService:_nameOf(userId)
	local cached = self.names[userId]
	if cached then
		return cached
	end
	local fallback = "Player " .. tostring(userId)
	local failedAt = self.nameFailedAt[userId]
	if not self.resolveName or (failedAt and self.clock() - failedAt < NAME_RETRY_SECONDS) then
		return fallback
	end
	local ok, name = pcall(self.resolveName, userId)
	if ok and type(name) == "string" then
		self.names[userId] = name
		return name
	end
	self.nameFailedAt[userId] = self.clock()
	return fallback
end

function LeaderboardService:_entries(storeName)
	local cached = self.cache[storeName]
	if cached and self.clock() - cached.at < Config.LEADERBOARD_CACHE_SECONDS then
		return true, cached.entries
	end
	local ok, entries = self.persistence:orderedTop(storeName, Config.LEADERBOARD_SIZE)
	if not ok then
		if cached then
			return true, cached.entries -- lỗi mạng: dùng tạm bản cũ
		end
		return false
	end
	self.cache[storeName] = { at = self.clock(), entries = entries }
	return true, entries
end

-- scope "global" | "class". Trả { scope, code, rows = { rank, userId, name, score, isMe } }
function LeaderboardService:top(scope, code, viewerId)
	local storeName
	if scope == "class" then
		if type(code) ~= "string" or code == "" then
			return false, "No class selected"
		end
		if not self.getClass then
			return false, "Class leaderboard isn't available"
		end
		local record = self.getClass(code)
		if not record then
			return false, "Class not found"
		end
		local isMember = record.teacherId == viewerId or (record.members or {})[tostring(viewerId)] ~= nil
		if not isMember then
			return false, "You're not in this class"
		end
		storeName = classStore(record.code)
		code = record.code
	else
		scope = "global"
		code = nil
		storeName = Config.DATASTORE.leaderboardGlobal
	end
	local ok, entries = self:_entries(storeName)
	if not ok then
		return false, "Couldn't load the leaderboard"
	end
	if self.resolveNames then
		local missing = {}
		for _, entry in ipairs(entries) do
			local id = tonumber(entry.key)
			local failedAt = id and self.nameFailedAt[id]
			if id and id > 0 and not self.names[id] and not (failedAt and self.clock() - failedAt < NAME_RETRY_SECONDS) then
				table.insert(missing, id)
			end
		end
		if #missing > 0 then
			local okNames, map = pcall(self.resolveNames, missing)
			if okNames and type(map) == "table" then
				for id, name in pairs(map) do
					self.names[id] = name
				end
			end
			for _, id in ipairs(missing) do
				if not self.names[id] then
					self.nameFailedAt[id] = self.clock()
				end
			end
		end
	end
	local rows = {}
	for i, entry in ipairs(entries) do
		local userId = tonumber(entry.key) or entry.key
		table.insert(rows, {
			rank = i,
			userId = userId,
			name = self:_nameOf(userId),
			score = entry.value / SCALE,
			isMe = userId == viewerId,
		})
	end
	return true, { scope = scope, code = code, rows = rows }
end

return LeaderboardService
