-- Entry phía server: nối các service với Roblox (remote, vòng tick, DataStore, MessagingService, teleport, admin)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local TeleportService = game:GetService("TeleportService")
local TextService = game:GetService("TextService")
local UserService = game:GetService("UserService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("EconCity")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local GameTick = require(Shared:WaitForChild("GameTick"))
local Scenarios = require(Shared:WaitForChild("Scenarios"))

local serverFolder = script.Parent
local Persistence = require(serverFolder:WaitForChild("Persistence"))
local SessionService = require(serverFolder:WaitForChild("SessionService"))
local ClassroomService = require(serverFolder:WaitForChild("ClassroomService"))
local LeaderboardService = require(serverFolder:WaitForChild("LeaderboardService"))
local AdminService = require(serverFolder:WaitForChild("AdminService"))
local Roles = require(serverFolder:WaitForChild("Roles"))
local World = require(serverFolder:WaitForChild("World"))

local IS_STUDIO = RunService:IsStudio()
-- phòng học riêng là reserved server, không có owner. Server riêng mua bằng Robux thì PrivateServerOwnerId ~= 0
local IN_CLASS_ROOM = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0

World.build()

-- Remotes
local remotes = Instance.new("Folder")
remotes.Name = Net.FOLDER
local stateEvent = Instance.new("RemoteEvent")
stateEvent.Name = Net.STATE_EVENT
stateEvent.Parent = remotes
local noticeEvent = Instance.new("RemoteEvent")
noticeEvent.Name = Net.NOTICE_EVENT
noticeEvent.Parent = remotes
local requestFunction = Instance.new("RemoteFunction")
requestFunction.Name = Net.REQUEST
requestFunction.Parent = remotes
remotes.Parent = ReplicatedStorage

-- Services
local persistence = Persistence.new({
	dataStoreService = DataStoreService,
	memoryStoreService = MemoryStoreService,
	wait = function(seconds)
		task.wait(seconds)
	end,
	log = warn,
	-- chỉ Studio mới được fallback sang bộ nhớ tạm, game thật thì không bao giờ
	allowMemoryFallback = IS_STUDIO,
	-- Studio ghi kho riêng, không lẫn data HS thật
	suffix = IS_STUDIO and Config.STUDIO_STORE_SUFFIX or "",
})

local function notify(userId, text)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		noticeEvent:FireClient(player, text)
	end
end

local sessions -- khai báo trước cho callback dùng
local classroom
local leaderboard
local admin
local pushState

sessions = SessionService.new({
	persistence = persistence,
	now = os.time,
	random = math.random,
	jobId = game.JobId,
	defer = function(fn)
		task.spawn(fn)
	end,
	wait = function(seconds)
		task.wait(seconds)
	end,
	onTick = function(userId, profile, result)
		local finished = GameTick.isFinished(profile.session)
		if finished or sessions.tickCounter % Config.LEADERBOARD_UPDATE_EVERY_TICKS == 0 then
			local score = profile.session.prosperityScore
			local classes = { table.unpack(profile.classes) }
			task.spawn(function()
				leaderboard:submit(userId, profile.name, score, classes)
			end)
		end
		for _, scenario in ipairs(result.finishedScenarios or {}) do
			local def = Scenarios.get(scenario.id)
			notify(userId, "Event ended: " .. ((def and def.name) or scenario.name or tostring(scenario.id)))
		end
	end,
	onSessionFinished = function(userId, profile)
		task.spawn(function()
			classroom:persistProgress(userId, profile)
		end)
		if profile.session.status == GameTick.STATUS.ENDED then
			notify(userId, string.format("Congratulations! You finished your %d-month term.", Config.GAME_DURATION_MONTHS))
		else
			notify(userId, "The city went bankrupt. Try again with a different layout and tax rate!")
		end
	end,
})

-- đặt mốc tick đầu luôn, người vào sớm nhận snapshot đã có đồng hồ đúng
sessions.nextTickAt = Workspace:GetServerTimeNow() + Config.TICK_SECONDS

local messagingReady = false
local function publish(message)
	if not messagingReady then
		return false
	end
	message.from = game.JobId -- server gửi cũng nhận lại message của chính nó, lúc nhận thì bỏ qua
	local ok = pcall(function()
		MessagingService:PublishAsync(Config.DATASTORE.messagingTopic, message)
	end)
	return ok
end

-- Roblox bắt buộc lọc chữ người chơi nhập trước khi người khác thấy
local function filterText(text, userId)
	local ok, result = pcall(function()
		local filterResult = TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PublicChat)
		return filterResult:GetNonChatStringForBroadcastAsync()
	end)
	if ok then
		return result
	end
	if IS_STUDIO then
		return text -- Studio có thể không lọc được, chỉ để test
	end
	error(result)
end

classroom = ClassroomService.new({
	persistence = persistence,
	sessions = sessions,
	isTeacher = Roles.isTeacherId,
	now = os.time,
	random = math.random,
	publish = publish,
	notify = notify,
	currentPrivateServerId = game.PrivateServerId,
	reserveServer = function()
		local accessCode, privateServerId = TeleportService:ReserveServerAsync(game.PlaceId)
		return accessCode, privateServerId
	end,
	teleportToRoom = function(userId, accessCode)
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			error("That player is no longer on this server")
		end
		-- lưu cuối + nhả lock trước khi teleport để server mới đọc được data mới nhất.
		-- tóm tắt lớp thì ghi 1 lần lúc thật sự rời server này
		sessions:beginTeleport(userId)
		local ok, err = pcall(function()
			local options = Instance.new("TeleportOptions")
			options.ReservedServerAccessCode = accessCode
			TeleportService:TeleportAsync(game.PlaceId, { player }, options)
		end)
		if not ok then
			sessions:teleportFailed(userId)
			if pushState then
				pushState(player, "teleportFailed")
			end
			error(err)
		end
	end,
	filterText = filterText,
})

leaderboard = LeaderboardService.new({
	persistence = persistence,
	clock = os.clock,
	resolveName = function(userId)
		return Players:GetNameFromUserIdAsync(userId)
	end,
	-- display name nhiều người trong 1 lần gọi
	resolveNames = function(userIds)
		local map = {}
		local infos = UserService:GetUserInfosByUserIdsAsync(userIds)
		for _, info in ipairs(infos) do
			map[info.Id] = info.DisplayName
		end
		return map
	end,
	getClass = function(code)
		return classroom:getClass(code)
	end,
})

admin = AdminService.new({
	persistence = persistence,
	sessions = sessions,
	leaderboard = leaderboard,
	now = os.time,
	publish = publish,
	setExtraTeachers = Roles.setExtraTeachers,
	isOwner = function(userId)
		local player = Players:GetPlayerByUserId(userId)
		return player ~= nil and Roles.isOwner(player)
	end,
	isInServer = function(userId)
		return Players:GetPlayerByUserId(userId) ~= nil
	end,
	getUserIdFromName = function(name)
		return Players:GetUserIdFromNameAsync(name)
	end,
	getNameFromUserId = function(userId)
		return Players:GetNameFromUserIdAsync(userId)
	end,
	banUser = function(userId, durationSeconds, reason)
		Players:BanAsync({
			UserIds = { userId },
			ApplyToUniverse = true,
			Duration = durationSeconds,
			DisplayReason = reason,
			PrivateReason = "EconCity admin panel",
			ExcludeAltAccounts = false,
		})
	end,
	unbanUser = function(userId)
		Players:UnbanAsync({ UserIds = { userId }, ApplyToUniverse = true })
	end,
})

task.spawn(function()
	-- list GV owner thêm: load lúc start, refresh mỗi 5 phút
	while true do
		admin:refresh()
		task.wait(300)
	end
end)

if persistence.mode == "datastore" then
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(Config.DATASTORE.messagingTopic, function(packet)
				local data = packet.Data
				if type(data) == "table" and game.JobId ~= "" and data.from == game.JobId then
					return -- đã xử lý tại chỗ lúc gửi
				end
				local okMsg, msgErr = pcall(function()
					classroom:onMessage(packet.Data)
					admin:onMessage(packet.Data)
				end)
				if not okMsg then
					warn("[EconCity] Message handling error: " .. tostring(msgErr))
				end
			end)
		end)
		messagingReady = ok
		if not ok then
			warn("[EconCity] MessagingService unavailable: " .. tostring(err))
		end
	end)
end

-- Gửi state
pushState = function(player, reason)
	local ok, err = pcall(function()
		local snap = sessions:snapshot(player.UserId, {
			reason = reason,
			isTeacher = Roles.isTeacher(player),
			isOwner = Roles.isOwner(player),
			isStudio = IS_STUDIO,
			inPrivateRoom = IN_CLASS_ROOM,
		})
		if snap then
			stateEvent:FireClient(player, snap)
		end
	end)
	if not ok then
		warn("[EconCity] Error sending state: " .. tostring(err))
	end
end

-- Vào / rời game
local function onPlayerAdded(player)
	local userId = player.UserId
	local profile = sessions:loadPlayer(userId, player.DisplayName)
	leaderboard:rememberName(userId, player.DisplayName)
	if not player.Parent then
		sessions:unloadPlayer(userId) -- rời lúc đang nạp
		return
	end
	-- sự kiện lớp gán lúc vắng
	local okSync, syncErr = pcall(function()
		classroom:syncPendingScenarios(userId, profile)
	end)
	if not okSync then
		warn("[EconCity] Class event sync error: " .. tostring(syncErr))
	end
	if not player.Parent then
		sessions:unloadPlayer(userId)
		return
	end
	if profile.loadFailed then
		noticeEvent:FireClient(player, "Saved data couldn't be loaded, so this game won't be saved.")
	end
	pushState(player, "init")
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(onPlayerAdded, player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

local lastRequestAt = {}
local lastActionAt = {}

Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	lastRequestAt[userId] = nil
	lastActionAt[userId] = nil
	-- ghi tóm tắt lớp song song với lần lưu cuối (unloadPlayer gỡ khỏi vòng tick ngay)
	local profile = sessions:getProfile(userId)
	if profile then
		task.spawn(function()
			classroom:persistProgress(userId, profile, true)
		end)
	end
	sessions:unloadPlayer(userId)
	classroom:forget(userId)
	Roles.forget(userId)
end)

-- teleport vào phòng riêng fail sau khi TeleportAsync đã return: chơi tiếp ở đây
TeleportService.TeleportInitFailed:Connect(function(player, result, message)
	if sessions:teleportFailed(player.UserId) then
		notify(player.UserId, "Couldn't join the private classroom (" .. tostring(message or result) .. "). You can keep playing here.")
		pushState(player, "teleportFailed")
	end
end)

game:BindToClose(function()
	-- tóm tắt lớp + hồ sơ lưu song song, Roblox cho tối đa 30s
	local started = os.clock()
	for userId, profile in pairs(sessions.profiles) do
		task.spawn(function()
			classroom:persistProgress(userId, profile, true)
		end)
	end
	sessions:saveAll()
	-- chờ hết các lần ghi tóm tắt lớp, kể cả của người vừa rời
	while classroom.pendingWrites > 0 and os.clock() - started < 27 do
		task.wait(0.25)
	end
end)

-- Vòng tick: 1 đồng hồ chung cả server, theo GetServerTimeNow để client đếm ngược khớp
task.spawn(function()
	while true do
		local remaining = sessions.nextTickAt - Workspace:GetServerTimeNow()
		if remaining > 0 then
			task.wait(remaining)
		end
		local okLoop, loopErr = pcall(function()
			sessions.nextTickAt = sessions.nextTickAt + Config.TICK_SECONDS
			-- server treo lâu thì bỏ các lượt đã lỡ, không tick dồn
			local now = Workspace:GetServerTimeNow()
			if sessions.nextTickAt < now then
				sessions.nextTickAt = now + Config.TICK_SECONDS
			end
			local results = sessions:tickAll()
			for _, player in ipairs(Players:GetPlayers()) do
				local profile = sessions:getProfile(player.UserId)
				if profile then
					pushState(player, results[player.UserId] and "tick" or "clock")
					-- tiến độ sống cho GV, cả lúc pause để biết ai online
					task.spawn(function()
						classroom:recordProgress(player.UserId, profile)
					end)
				end
			end
		end)
		if not okLoop then
			warn("[EconCity] Tick loop error: " .. tostring(loopErr))
			sessions.nextTickAt = Workspace:GetServerTimeNow() + Config.TICK_SECONDS
		end
	end
end)

-- Request từ client
local handlers = {}

local function requireTeacher(player)
	if not Roles.isTeacher(player) then
		return false, "Teachers only"
	end
	return true
end

local function requireOwner(player)
	if not Roles.isOwner(player) then
		return false, "Only the game owner can use this"
	end
	return true
end

handlers.getState = function(player)
	return true, sessions:snapshot(player.UserId, {
		isTeacher = Roles.isTeacher(player),
		isOwner = Roles.isOwner(player),
		isStudio = IS_STUDIO,
		inPrivateRoom = IN_CLASS_ROOM,
	})
end

handlers.clientReady = function(player)
	local ok, err = sessions:clientReady(player.UserId)
	if ok then
		pushState(player, "ready")
	end
	return ok, err
end

-- xây / kéo đường / phá / thuế: CityEngine (qua SessionService) validate mọi giá trị client gửi
local function cityAction(action, read)
	return function(player, payload)
		payload = payload or {}
		local a, b = read(payload)
		local ok, data = sessions:act(player.UserId, action, a, b)
		if ok then
			pushState(player, "city")
		end
		return ok, data
	end
end
handlers.build = cityAction("build", function(p)
	return p.kind, p.index
end)
handlers.buildRoad = cityAction("buildRoad", function(p)
	return p.path
end)
handlers.demolish = cityAction("demolish", function(p)
	return p.index
end)
handlers.setTax = cityAction("setTax", function(p)
	return p.tax
end)

handlers.togglePause = function(player)
	local ok, statusOrErr = sessions:togglePause(player.UserId)
	if ok then
		pushState(player, "pause")
		return true, statusOrErr
	end
	return false, statusOrErr
end

handlers.newGame = function(player)
	local ok, err = sessions:newGame(player.UserId)
	if ok then
		pushState(player, "newGame")
	end
	return ok, err
end

handlers.tickNow = function(player)
	if not IS_STUDIO then
		return false, "Only available in Roblox Studio"
	end
	local result = sessions:tickOne(player.UserId)
	pushState(player, result and "tick" or "clock")
	if not result then
		return false, "The game isn't running"
	end
	return true
end

handlers.demoBuild = function(player)
	if not IS_STUDIO then
		return false, "Only available in Roblox Studio"
	end
	local ok, data = sessions:demoBuild(player.UserId)
	if ok then
		pushState(player, "city")
	end
	return ok, data
end

handlers.getLeaderboard = function(player, payload)
	payload = payload or {}
	local ok, data = leaderboard:top(payload.scope == "class" and "class" or "global", payload.code, player.UserId)
	if ok then
		local profile = sessions:getProfile(player.UserId)
		data.me = {
			bestScore = profile and profile.bestScore or 0,
			currentScore = profile and profile.session and profile.session.prosperityScore or 0,
			ranked = player.UserId > 0,
		}
	end
	return ok, data
end

handlers.joinClass = function(player, payload)
	local ok, result = classroom:joinClass(player.UserId, player.DisplayName, payload and payload.code)
	if ok then
		pushState(player, "class")
	end
	return ok, result
end

handlers.leaveClass = function(player, payload)
	local ok, result = classroom:leaveClass(player.UserId, payload and payload.code)
	if ok then
		pushState(player, "class")
	end
	return ok, result
end

handlers.getMyClasses = function(player)
	return classroom:getMyClasses(player.UserId)
end

handlers.createClass = function(player, payload)
	local ok, result = classroom:createClass(player.UserId, player.DisplayName, payload and payload.name)
	if ok then
		pushState(player, "class")
	end
	return ok, result
end

handlers.getTeacherClasses = function(player)
	local allowed, err = requireTeacher(player)
	if not allowed then
		return false, err
	end
	return classroom:getTeacherClasses(player.UserId)
end

handlers.getClassRoster = function(player, payload)
	return classroom:getRoster(player.UserId, payload and payload.code)
end

handlers.getStudentDetail = function(player, payload)
	payload = payload or {}
	return classroom:getStudentDetail(player.UserId, payload.code, payload.userId)
end

handlers.exportClassCsv = function(player, payload)
	return classroom:exportClassCsv(player.UserId, payload and payload.code)
end

handlers.assignScenario = function(player, payload)
	payload = payload or {}
	return classroom:assignScenario(player.UserId, payload.code, payload.scenarioId)
end

handlers.listScenarios = function(player)
	return classroom:listScenarios(player.UserId)
end

handlers.createScenario = function(player, payload)
	return classroom:createScenario(player.UserId, payload)
end

handlers.deleteScenario = function(player, payload)
	return classroom:deleteScenario(player.UserId, payload and payload.id)
end

handlers.openClassRoom = function(player, payload)
	return classroom:openRoom(player.UserId, payload and payload.code)
end

handlers.closeClassRoom = function(player, payload)
	return classroom:closeRoom(player.UserId, payload and payload.code)
end

handlers.enterClassRoom = function(player, payload)
	return classroom:enterRoom(player.UserId, payload and payload.code)
end

-- Quản trị, chỉ owner
handlers.adminGetState = function(player)
	local allowed, err = requireOwner(player)
	if not allowed then
		return false, err
	end
	return admin:getState(player.UserId)
end

handlers.adminAddTeacher = function(player, payload)
	local allowed, err = requireOwner(player)
	if not allowed then
		return false, err
	end
	return admin:addTeacher(player.UserId, payload and payload.target)
end

handlers.adminRemoveTeacher = function(player, payload)
	local allowed, err = requireOwner(player)
	if not allowed then
		return false, err
	end
	return admin:removeTeacher(player.UserId, payload and payload.userId)
end

handlers.adminBan = function(player, payload)
	local allowed, err = requireOwner(player)
	if not allowed then
		return false, err
	end
	payload = payload or {}
	return admin:ban(player.UserId, payload.target, payload.days, payload.reason)
end

handlers.adminUnban = function(player, payload)
	local allowed, err = requireOwner(player)
	if not allowed then
		return false, err
	end
	return admin:unban(player.UserId, payload and payload.userId)
end

handlers.adminDeleteUserData = function(player, payload)
	local allowed, err = requireOwner(player)
	if not allowed then
		return false, err
	end
	return admin:deleteUserData(player.UserId, payload and payload.target)
end

requestFunction.OnServerInvoke = function(player, action, payload)
	if type(action) ~= "string" or not Net.ACTIONS[action] or not handlers[action] then
		return { ok = false, error = "Invalid action" }
	end
	if payload ~= nil and type(payload) ~= "table" then
		return { ok = false, error = "Invalid data" }
	end
	local userId = player.UserId
	-- rate limit kiểu token bucket: cho burst vài request (mở bảng gọi 2-3 API cùng lúc), chặn spam liên tục
	local now = os.clock()
	local bucket = lastRequestAt[userId]
	if not bucket then
		bucket = { tokens = Config.REQUEST_BURST, at = now }
		lastRequestAt[userId] = bucket
	end
	bucket.tokens = math.min(Config.REQUEST_BURST, bucket.tokens + (now - bucket.at) * Config.REQUEST_REFILL_PER_SECOND)
	bucket.at = now
	if bucket.tokens < 1 then
		return { ok = false, error = "You're going too fast" }
	end
	bucket.tokens = bucket.tokens - 1
	if not sessions:getProfile(userId) then
		return { ok = false, error = "Still loading data, try again in a moment" }
	end
	-- cooldown riêng cho action tốn tài nguyên (DataStore, lọc chữ, teleport).
	-- đánh dấu trước khi xử lý, không thì request gửi cùng lúc lách được cooldown
	local cooldown = Config.ACTION_COOLDOWNS[action]
	local previous = nil
	if cooldown then
		local marks = lastActionAt[userId] or {}
		lastActionAt[userId] = marks
		if marks["busy:" .. action] then
			return { ok = false, error = "Still working on your last request, please wait" }
		end
		local last = marks[action]
		if last and now - last < cooldown then
			return { ok = false, error = string.format("Please wait %ds and try again", math.ceil(cooldown - (now - last))) }
		end
		previous = last
		marks[action] = now
		marks["busy:" .. action] = true
	end
	local success, ok, data = pcall(handlers[action], player, payload)
	local marks = lastActionAt[userId]
	if cooldown and marks then
		marks["busy:" .. action] = nil
		-- fail (gõ sai tên, lỗi mạng) thì cho thử lại ngay. Riêng joinClass vẫn tính cooldown, chống dò mã
		if (not success or not ok) and action ~= "joinClass" then
			marks[action] = previous
		end
	end
	if not success then
		warn("[EconCity] Error handling " .. action .. ": " .. tostring(ok))
		return { ok = false, error = "Server error, try again later" }
	end
	if ok then
		return { ok = true, data = data }
	end
	return { ok = false, error = data or "Couldn't do that" }
end

print(string.format(
	"[EconCity] Server v%s ready, storage: %s%s, tick %ds",
	Config.VERSION,
	persistence.mode,
	persistence.degraded and " (failing, retrying per call)" or "",
	Config.TICK_SECONDS
))
