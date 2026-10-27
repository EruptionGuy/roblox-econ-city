-- Hồ sơ người chơi + phiên đang chạy trong server này. Chỉ tick người đang ở server (hết người là Roblox tắt server).
-- lock = { jobId, at }: server khác đang giữ thì chờ nó lưu xong mới nạp. Bị giành lock thì ngừng ghi, không đè data mới hơn.
-- Mỗi người chỉ 1 lần lưu chạy, yêu cầu lưu lúc đó thì gộp. Rời game/chuyển server: pause ngay, lưu lần cuối, nhả lock.
-- Phiên chỉ tính lượt sau khi client báo ready (máy yếu load chậm khỏi thua oan).
-- không gọi Roblox API trực tiếp, mọi thứ đi qua deps (để test chạy được ngoài Studio)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("EconCity")

local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local GameTick = require(Shared:WaitForChild("GameTick"))
local CityEngine = require(Shared:WaitForChild("CityEngine"))
local DemoBot = require(Shared:WaitForChild("DemoBot"))
local Scenarios = require(Shared:WaitForChild("Scenarios"))

local SessionService = {}
SessionService.__index = SessionService

local PROFILE_VERSION = 2
-- field chỉ có lúc chạy, không lưu DataStore
local RUNTIME_FIELDS = { "loadFailed", "lockLost", "teleporting" }

-- deps: persistence, now (giây), random ([0,1)), defer(fn) (task.spawn), wait (task.wait), jobId (game.JobId),
-- onTick(userId, profile, result) / onSessionFinished(userId, profile) tuỳ chọn
function SessionService.new(deps)
	local self = setmetatable({}, SessionService)
	self.persistence = deps.persistence
	self.now = deps.now or os.time
	self.random = deps.random or math.random
	self.onTick = deps.onTick
	self.onSessionFinished = deps.onSessionFinished
	self.defer = deps.defer or function(fn)
		fn()
	end
	self.wait = deps.wait or function() end
	self.jobId = (deps.jobId and deps.jobId ~= "") and deps.jobId or "local"
	self.profiles = {} -- [userId] = profile đang nạp
	self.saveState = {} -- [userId] = { running, again, final, profile }
	self.lastWriteAt = {} -- [userId] = lần ghi ok gần nhất, dùng để refresh lock
	self.tickCounter = 0
	self.nextTickAt = 0
	return self
end

local function newProfile(userId, name)
	return {
		version = PROFILE_VERSION,
		userId = userId,
		name = name,
		session = nil,
		pastSessions = {},
		classes = {}, -- lớp đã vào (HS)
		teaching = {}, -- lớp đang dạy (GV)
		scenarioSync = {}, -- [mã lớp] = mốc sự kiện lớp đã nhận
		gamesPlayed = 0,
		bestScore = 0,
	}
end

function SessionService:_key(userId)
	return "u_" .. tostring(userId)
end

function SessionService:_newSessionId(userId)
	return string.format("s_%s_%d_%04d", tostring(userId), self.now(), math.floor(self.random() * 10000))
end

function SessionService:_startNewSession(profile)
	profile.session = GameTick.newSession(profile.userId, self:_newSessionId(profile.userId), self.now())
	return profile.session
end

-- data cũ/thiếu field không được làm sập vòng tick.
-- false = phiên luật cũ (nhóm dân + chính sách, không có lưới), cho chơi ván mới
local function normalizeSession(session)
	local size = Config.GRID_SIZE * Config.GRID_SIZE
	if type(session) ~= "table" or type(session.cells) ~= "table" or #session.cells ~= size then
		return false
	end
	CityEngine.sanitizeCells(session.cells)
	session.cells[Config.GATE_INDEX] = "road"
	local tax = session.tax
	if type(tax) ~= "number" or tax ~= math.floor(tax) or tax < 0 or tax > Config.TAX_MAX then
		session.tax = Config.START_TAX
	end
	for _, key in ipairs({ "budget", "population", "employed", "employment", "gdp", "happiness", "prosperityScore" }) do
		if not Util.isFiniteNumber(session[key]) then
			session[key] = 0
		end
	end
	session.population = math.max(0, math.floor(session.population))
	session.scenarios = type(session.scenarios) == "table" and session.scenarios or {}
	session.history = type(session.history) == "table" and session.history or {}
	session.crises = type(session.crises) == "table" and session.crises or {}
	session.month = tonumber(session.month) or 0
	session.maxMonths = tonumber(session.maxMonths) or Config.GAME_DURATION_MONTHS
	return true
end

local function normalizeProfile(profile, userId, name)
	profile.version = PROFILE_VERSION
	profile.userId = userId
	profile.name = name or profile.name
	profile.pastSessions = type(profile.pastSessions) == "table" and profile.pastSessions or {}
	profile.classes = type(profile.classes) == "table" and profile.classes or {}
	profile.teaching = type(profile.teaching) == "table" and profile.teaching or {}
	profile.scenarioSync = type(profile.scenarioSync) == "table" and profile.scenarioSync or {}
	profile.gamesPlayed = tonumber(profile.gamesPlayed) or 0
	profile.bestScore = tonumber(profile.bestScore) or 0
end

-- đọc hồ sơ + giữ lock. Trả (profile, ok)
function SessionService:_acquire(userId, name)
	local key = self:_key(userId)
	for attempt = 1, 6 do
		local loaded, lockedByOther = nil, false
		local force = attempt == 6 -- lần cuối: coi lock cũ là bỏ rơi
		local ok = self.persistence:update(Config.DATASTORE.profiles, key, function(old)
			loaded, lockedByOther = nil, false
			local now = self.now()
			if not force and type(old) == "table" and type(old.lock) == "table" and old.lock.jobId ~= self.jobId
				and (now - (tonumber(old.lock.at) or 0)) < Config.SESSION_LOCK_STALE_SECONDS then
				lockedByOther = true
				return nil
			end
			local profile = type(old) == "table" and old or newProfile(userId, name)
			profile.lock = { jobId = self.jobId, at = now }
			loaded = profile
			return profile
		end)
		if not ok then
			return nil, false
		end
		if loaded then
			return Util.deepCopy(loaded), true
		end
		if not lockedByOther then
			return nil, false
		end
		self.wait(3) -- server cũ còn đang lưu lần cuối
	end
	return nil, false
end

-- tiếp phiên dở hoặc tạo mới. Phiên chờ client (không tính lượt) tới khi gọi clientReady
function SessionService:loadPlayer(userId, name)
	-- vừa rời rồi vào lại: lần lưu cuối còn chạy thì chờ xong mới đọc
	for _ = 1, 100 do
		local st = self.saveState[userId]
		if not st or not st.running then
			break
		end
		self.wait(0.2)
	end
	local profile, ok = self:_acquire(userId, name)
	if not profile then
		profile = newProfile(userId, name)
	end
	normalizeProfile(profile, userId, name)
	profile.loadFailed = not ok or nil

	local session = profile.session
	if not normalizeSession(session) or GameTick.isFinished(session) then
		session = self:_startNewSession(profile)
		session.status = GameTick.STATUS.PAUSED
		session.waitingForClient = true
	elseif session.status == GameTick.STATUS.ACTIVE or session.autoPaused then
		-- đang chạy dở (server cũ sập) hoặc auto pause lúc rời game: chờ client rồi chạy tiếp
		session.status = GameTick.STATUS.PAUSED
		session.autoPaused = false
		session.waitingForClient = true
	end
	self.profiles[userId] = profile
	return profile
end

-- client dựng xong UI
function SessionService:clientReady(userId)
	local profile = self.profiles[userId]
	if not profile or not profile.session then
		return false, "Data is still loading, try again in a moment"
	end
	local session = profile.session
	if session.waitingForClient then
		session.waitingForClient = false
		-- ván dở thì chạy tiếp. Ván mới (tháng 0) chờ người chơi xây xong tự bấm Bắt đầu
		if not GameTick.isFinished(session) and session.month > 0 then
			session.status = GameTick.STATUS.ACTIVE
		end
	end
	return true
end

function SessionService:getProfile(userId)
	return self.profiles[userId]
end

-- UpdateAsync có check lock. final = true thì nhả lock cho server khác nạp ngay
function SessionService:_write(userId, profile, final)
	if profile.loadFailed or profile.lockLost then
		return false
	end
	local copy = Util.deepCopy(profile)
	for _, field in ipairs(RUNTIME_FIELDS) do
		copy[field] = nil
	end
	if copy.session then
		copy.session.waitingForClient = nil
	end
	local lost = false
	local ok = self.persistence:update(Config.DATASTORE.profiles, self:_key(userId), function(old)
		lost = false
		local now = self.now()
		if old == nil then
			-- hồ sơ bị xoá (yêu cầu xoá data) lúc người chơi còn ở đây: không tạo lại
			lost = true
			return nil
		end
		if type(old) == "table" and type(old.lock) == "table" and old.lock.jobId ~= self.jobId
			and (now - (tonumber(old.lock.at) or 0)) < Config.SESSION_LOCK_STALE_SECONDS then
			lost = true -- server khác đang giữ lock, không ghi đè
			return nil
		end
		if final then
			copy.lock = nil
		else
			copy.lock = { jobId = self.jobId, at = now }
		end
		return copy
	end)
	if lost then
		profile.lockLost = true
	elseif ok then
		self.lastWriteAt[userId] = self.now()
	end
	return ok and not lost
end

-- không chặn. Đang có lần lưu chạy thì gộp vào
function SessionService:requestSave(userId, final)
	local profile = self.profiles[userId]
	local st = self.saveState[userId]
	if not st then
		st = { running = false, again = false, final = false }
		self.saveState[userId] = st
	end
	if profile then
		st.profile = profile
	end
	if not st.profile then
		return
	end
	-- đang teleport: đã lưu cuối + nhả lock, ghi nữa là giành lại lock
	if st.profile.teleporting and not final then
		return
	end
	st.final = st.final or final or false
	if st.running then
		st.again = true
		return
	end
	st.running = true
	self.defer(function()
		repeat
			st.again = false
			local ok, err = pcall(function()
				self:_write(userId, st.profile, st.final)
			end)
			if not ok then
				print("[EconCity] Error saving profile " .. tostring(userId) .. ": " .. tostring(err))
			end
		until not st.again
		st.running = false
		if st.final then
			self.saveState[userId] = nil
		end
	end)
end

-- chờ lần lưu đang chạy xong, tối đa timeout giây
function SessionService:flush(userId, timeout)
	local waited = 0
	while self.saveState[userId] and self.saveState[userId].running and waited < (timeout or 20) do
		self.wait(0.2)
		waited = waited + 0.2
	end
end

-- tên cũ, cho chỗ gọi đơn giản
function SessionService:save(userId)
	self:requestSave(userId, false)
	return true
end

local function pauseForLeave(session)
	if session and session.status == GameTick.STATUS.ACTIVE then
		session.status = GameTick.STATUS.PAUSED
		session.autoPaused = true
	elseif session and session.waitingForClient then
		session.autoPaused = true
	end
end

-- rời game: gỡ ngay (hết bị tick), pause, lưu cuối, nhả lock. Trả hồ sơ để ghi tóm tắt lớp
function SessionService:unloadPlayer(userId)
	local profile = self.profiles[userId]
	if not profile then
		return nil
	end
	self.profiles[userId] = nil
	pauseForLeave(profile.session)
	if profile.teleporting then
		return profile -- đã lưu cuối trước khi teleport
	end
	local st = self.saveState[userId]
	if st then
		st.profile = profile
	end
	self.saveState[userId] = st
	if not st then
		self.saveState[userId] = { running = false, again = false, final = false, profile = profile }
	end
	self:requestSave(userId, true)
	self:flush(userId, 25)
	return profile
end

-- trước khi teleport (phòng học riêng): pause, lưu cuối, nhả lock
function SessionService:beginTeleport(userId)
	local profile = self.profiles[userId]
	if not profile then
		return false
	end
	pauseForLeave(profile.session)
	self:requestSave(userId, true)
	self:flush(userId, 20)
	profile.teleporting = true
	return true
end

-- teleport lỗi: lấy lại lock, chạy tiếp
function SessionService:teleportFailed(userId)
	local profile = self.profiles[userId]
	if not profile or not profile.teleporting then
		return false
	end
	profile.teleporting = nil
	local session = profile.session
	if session and session.autoPaused and not GameTick.isFinished(session) then
		session.autoPaused = false
		session.status = GameTick.STATUS.ACTIVE
	end
	self:requestSave(userId, false)
	return true
end

-- tắt server: lưu song song mọi hồ sơ (nhả lock), chờ tối đa ~25s
function SessionService:saveAll()
	local ids = {}
	for userId in pairs(self.profiles) do
		table.insert(ids, userId)
	end
	for _, userId in ipairs(ids) do
		local profile = self.profiles[userId]
		if profile then
			pauseForLeave(profile.session)
			self:requestSave(userId, true)
		end
	end
	local waited = 0
	while waited < 25 do
		local busy = false
		for _, st in pairs(self.saveState) do
			if st.running then
				busy = true
			end
		end
		if not busy then
			break
		end
		self.wait(0.25)
		waited = waited + 0.25
	end
end

-- hành động người chơi

-- CityEngine tự validate mọi thứ client gửi (loại, ô, tiền, ván đã xong)
local CITY_ACTIONS = {
	build = CityEngine.build, -- (kind, index)
	buildRoad = CityEngine.buildRoad, -- (path)
	demolish = CityEngine.demolish, -- (index)
	setTax = CityEngine.setTax, -- (tax)
}

function SessionService:act(userId, action, a, b)
	local profile = self.profiles[userId]
	if not profile or not profile.session then
		return false, "No game in progress"
	end
	local fn = CITY_ACTIONS[action]
	if not fn then
		return false, "Invalid action"
	end
	return fn(profile.session, a, b)
end

-- nút "Xây mẫu" (chỉ Studio): bot xây tiếp bằng tiền đang có, đúng luật
function SessionService:demoBuild(userId)
	local profile = self.profiles[userId]
	if not profile or not profile.session then
		return false, "No game in progress"
	end
	if GameTick.isFinished(profile.session) then
		return false, "This game has ended, start a new one"
	end
	return true, { built = DemoBot.act(profile.session, DemoBot.SHOWCASE) }
end

function SessionService:togglePause(userId)
	local profile = self.profiles[userId]
	if not profile or not profile.session then
		return false, "No game in progress"
	end
	local session = profile.session
	if GameTick.isFinished(session) then
		-- không cho "hồi sinh" phiên đã xong bằng nút pause
		return false, "This game has ended"
	end
	if session.status == GameTick.STATUS.ACTIVE then
		session.status = GameTick.STATUS.PAUSED
	else
		session.status = GameTick.STATUS.ACTIVE
	end
	session.autoPaused = false
	session.waitingForClient = false
	return true, session.status
end

function SessionService:_archive(profile)
	local session = profile.session
	if not session or session.archived then
		return
	end
	session.archived = true
	profile.gamesPlayed = (profile.gamesPlayed or 0) + 1
	profile.bestScore = math.max(profile.bestScore or 0, session.prosperityScore or 0)
	local summary = GameTick.summary(session)
	summary.finishedAt = self.now()
	table.insert(profile.pastSessions, 1, summary)
	-- giữ kết quả ván vừa xong (kèm lịch sử tháng) để GV vẫn xem được khi HS mở ván mới
	profile.lastFinished = GameTick.summary(session, true)
	profile.lastFinished.finishedAt = summary.finishedAt
	while #profile.pastSessions > Config.MAX_PAST_SESSIONS do
		table.remove(profile.pastSessions)
	end
end

-- người chơi đang ở trong game nên chạy ngay
function SessionService:newGame(userId)
	local profile = self.profiles[userId]
	if not profile then
		return false, "Data is still loading, try again in a moment"
	end
	local old = profile.session
	-- ván chưa qua tháng nào thì không vào lịch sử
	if old and not old.archived and old.month > 0 then
		self:_archive(profile)
	end
	self:_startNewSession(profile)
	self:requestSave(userId, false)
	return true
end

function SessionService:addScenario(userId, scenarioId, meta, customDef)
	local profile = self.profiles[userId]
	if not profile or not profile.session then
		return false, "No game in progress"
	end
	return GameTick.addScenario(profile.session, scenarioId, meta, customDef)
end

-- Tick

function SessionService:tickOne(userId)
	local profile = self.profiles[userId]
	if not profile or not profile.session or profile.teleporting or profile.lockLost then
		return nil
	end
	local session = profile.session
	local result = GameTick.processTick(session)
	if not result then
		return nil
	end
	if GameTick.isFinished(session) then
		self:_archive(profile)
		if self.onSessionFinished then
			self.onSessionFinished(userId, profile)
		end
	end
	if self.onTick then
		self.onTick(userId, profile, result)
	end
	self:requestSave(userId, false)
	return result
end

-- trả { [userId] = result }
function SessionService:tickAll()
	self.tickCounter = self.tickCounter + 1
	local results = {}
	local ids = {}
	for userId in pairs(self.profiles) do
		table.insert(ids, userId)
	end
	local now = self.now()
	for _, userId in ipairs(ids) do
		local ok, result = pcall(function()
			return self:tickOne(userId)
		end)
		if ok then
			if result then
				results[userId] = result
			elseif now - (self.lastWriteAt[userId] or 0) >= Config.LOCK_REFRESH_SECONDS then
				-- phiên đang pause/đã xong vẫn refresh lock để server khác biết hồ sơ đang dùng
				self:requestSave(userId, false)
			end
		else
			print("[EconCity] Error ticking player " .. tostring(userId) .. ": " .. tostring(result))
		end
	end
	return results
end

-- snapshot gửi client

function SessionService:snapshot(userId, extra)
	local profile = self.profiles[userId]
	if not profile then
		return nil
	end
	local session = Util.deepCopy(profile.session)
	if session then
		for _, s in ipairs(session.scenarios or {}) do
			local def = Scenarios.get(s.id)
			if def then
				s.name = def.name
				s.description = def.description
				s.severity = def.severity
			end
			s.monthsLeft = Scenarios.monthsLeft(s)
		end
	end
	local snap = {
		session = session,
		nextTickAt = self.nextTickAt,
		tickSeconds = Config.TICK_SECONDS,
		profile = {
			name = profile.name,
			classes = Util.deepCopy(profile.classes),
			teaching = Util.deepCopy(profile.teaching),
			gamesPlayed = profile.gamesPlayed or 0,
			bestScore = profile.bestScore or 0,
			pastSessions = Util.deepCopy(profile.pastSessions),
		},
		persistence = self.persistence.mode,
		saveDisabled = (profile.loadFailed or profile.lockLost) and true or false,
	}
	if extra then
		for k, v in pairs(extra) do
			snap[k] = v
		end
	end
	return snap
end

return SessionService
