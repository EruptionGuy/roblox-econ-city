-- test logic server: Session/Classroom/Leaderboard/AdminService, Persistence chạy bằng bộ nhớ
package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

-- game giả tối thiểu, chỉ cần ReplicatedStorage.EconCity trỏ về src/shared
H.extraGlobals.game = {
	GetService = function(_, name)
		return {
			WaitForChild = function(_, child)
				if child == "EconCity" then
					return H.node("src/shared")
				end
				error("không có " .. child)
			end,
		}
	end,
}

local Persistence = H.require("src/server/Persistence")
local SessionService = H.require("src/server/SessionService")
local ClassroomService = H.require("src/server/ClassroomService")
local LeaderboardService = H.require("src/server/LeaderboardService")
local AdminService = H.require("src/server/AdminService")
local Config = H.require("src/shared/Config")

local clock = 1000
local function now() return clock end
local rng = H.require("src/shared/Util").seededRandom(42)

local function newSessions(p, jobId)
	return SessionService.new({
		persistence = p, now = now, random = rng, jobId = jobId,
		wait = function(seconds) clock = clock + seconds end,
	})
end

local function setup(teachers)
	local p = Persistence.new({ forceMemory = true, log = function() end })
	local notices = {}
	local s = newSessions(p, "server-A")
	local c = ClassroomService.new({
		persistence = p, sessions = s, now = now, random = rng,
		isTeacher = function(id) return teachers[id] == true end,
		notify = function(id, text) table.insert(notices, { id = id, text = text }) end,
	})
	local lb = LeaderboardService.new({ persistence = p, getClass = function(code) return c:getClass(code) end, clock = now })
	return p, s, c, lb, notices
end

-- như người chơi thật vào game: load, báo client ready, ván mới thì bấm Bắt đầu
local function join(s, id, name)
	local profile = s:loadPlayer(id, name or ("P" .. id))
	s:clientReady(id)
	if profile.session.status == "PAUSED" and profile.session.month == 0 then
		s:togglePause(id)
	end
	return profile
end

-- 5 công viên không nối đường (chỉ tốn bảo trì $500/tháng), chạy tới khi phá sản
local function goBankrupt(s, id)
	for k = 1, 5 do
		assert(s:act(id, "build", "park", k))
	end
	for _ = 1, 40 do
		s:tickAll()
		if s:getProfile(id).session.status == "FAILED" then
			return s:getProfile(id).session.month
		end
	end
	error("không phá sản")
end

print("Server: phiên chơi, lớp học, xếp hạng, quản trị")

H.test("Phiên chỉ bắt đầu tính lượt khi client báo sẵn sàng", function()
	local p, s = setup({})
	local profile = s:loadPlayer(1, "Alice")
	H.eq(profile.session.status, "PAUSED")
	H.eq(profile.session.waitingForClient, true)
	s:tickAll()
	H.eq(profile.session.month, 0, "chưa sẵn sàng => không tick")
	H.truthy(s:clientReady(1))
	H.eq(profile.session.status, "PAUSED", "ván mới chờ người chơi xây rồi bấm Bắt đầu")
	s:tickAll()
	H.eq(profile.session.month, 0)
	s:togglePause(1)
	H.eq(profile.session.status, "ACTIVE")
	s:tickAll()
	H.eq(profile.session.month, 1)
end)

H.test("Rời game tự tạm dừng; quay lại chạy tiếp sau khi client sẵn sàng", function()
	local p, s = setup({})
	local profile = join(s, 1, "Alice")
	s:tickAll()
	H.eq(profile.session.month, 1)
	local removed = s:unloadPlayer(1)
	H.eq(removed, profile, "trả về hồ sơ đã gỡ")
	H.eq(s:getProfile(1), nil)
	s:tickAll() -- hồ sơ đã gỡ không bị tick nữa
	H.eq(profile.session.month, 1)
	local again = s:loadPlayer(1, "Alice")
	H.eq(again.session.month, 1, "giữ tiến độ")
	H.eq(again.session.status, "PAUSED")
	s:clientReady(1)
	H.eq(again.session.status, "ACTIVE", "tự chạy lại sau khi auto-pause")
	H.eq(again.lock ~= nil, true, "đang giữ khoá")
end)

H.test("Tạm dừng thủ công vẫn giữ tạm dừng khi quay lại", function()
	local p, s = setup({})
	join(s, 1, "A")
	local ok, st = s:togglePause(1)
	H.eq(st, "PAUSED")
	s:unloadPlayer(1)
	local again = s:loadPlayer(1, "A")
	s:clientReady(1)
	H.eq(again.session.status, "PAUSED")
end)

H.test("Phiên thua: không cho xây / đặt thuế / tạm dừng; vào lại được phiên mới", function()
	local p, s = setup({})
	local profile = join(s, 1, "A")
	goBankrupt(s, 1)
	H.eq(profile.session.status, "FAILED")
	H.eq((s:act(1, "setTax", 30)), false)
	H.eq((s:act(1, "build", "house", 20)), false)
	H.eq((s:togglePause(1)), false)
	H.eq(profile.gamesPlayed, 1)
	H.eq(#profile.pastSessions, 1)
	H.truthy(s:newGame(1))
	H.eq(profile.session.status, "PAUSED", "ván mới chờ người chơi bấm Bắt đầu")
	H.eq(profile.session.month, 0)
	H.eq(profile.gamesPlayed, 1, "không lưu trùng")
end)

H.test("Thao tác thành phố kiểm tra dữ liệu client", function()
	local p, s = setup({})
	local profile = join(s, 1, "A")
	H.eq((s:act(1, "build", "castle", 5)), false)
	H.eq((s:act(1, "build", "house", 0)), false)
	H.eq((s:act(1, "build", "house", "5")), false)
	H.eq((s:act(1, "buildRoad", "hack")), false)
	H.eq((s:act(1, "setTax", 99)), false)
	H.eq((s:act(1, "applyPolicy", {})), false, "hành động lạ")
	H.eq((s:act(2, "build", "house", 5)), false, "chưa nạp hồ sơ")
	H.eq(profile.session.budget, 10000, "không trừ tiền khi bị từ chối")
	local ok, r = s:act(1, "build", "house", Config.GATE_INDEX - 1)
	H.truthy(ok)
	H.eq(r.cost, 600)
	H.truthy(s:act(1, "setTax", 25))
	H.eq(profile.session.tax, 25)
end)

H.test("Mẫu công trình qua server: xây 2×2, phá từ ô phụ, chi tiết lớp đếm mỗi công trình một lần", function()
	local p, s, c = setup({ [99] = true })
	join(s, 99, "T")
	local _, cls = c:createClass(99, "T", "Lop")
	local profile = join(s, 1, "A")
	c:joinClass(1, "A", cls.code)
	profile.session.budget = 50000
	H.truthy(s:act(1, "build", "supermarket", 1))
	H.eq((s:act(1, "build", "supermarket", 12)), false, "tràn mép phải")
	H.eq((s:act(1, "build", "unicorn", 30)), false)
	local ok, r = s:act(1, "demolish", 14) -- ô phụ dưới-phải của siêu thị
	H.truthy(ok)
	H.eq(r.refund, 3500)
	H.eq(profile.session.cells[1], Config.EMPTY)
	H.truthy(s:act(1, "build", "tower", 1)) -- chưa nối đường
	s:tickAll()
	c:recordProgress(1, profile)
	local _, detail = c:getStudentDetail(99, cls.code, 1)
	H.eq(detail.detail.city.counts.office, 1)
	H.eq(detail.detail.city.unconnected, 1, "tháp 2×2 tính là 1 công trình chưa nối")
	-- nạp lại từ DataStore: ô phụ giữ nguyên
	s:unloadPlayer(1)
	local again = s:loadPlayer(1, "A")
	H.eq(again.session.cells[2], "+1")
	H.eq(again.session.cells[14], "+1")
end)

H.test("Xây được cả khi tạm dừng; tác dụng ở lượt tính kế tiếp; ván tháng 0 làm lại được từ đầu", function()
	local p, s = setup({})
	local profile = s:loadPlayer(1, "A")
	s:clientReady(1)
	local gate = Config.GATE_INDEX
	H.truthy(s:act(1, "build", "house", gate - 1))
	H.truthy(s:act(1, "build", "office", gate + 1))
	H.eq(profile.session.population, 0)
	s:togglePause(1)
	s:tickAll()
	H.truthy(profile.session.population > 0, "dân đến sau lượt tính")
	H.truthy(s:newGame(1))
	H.eq(#profile.pastSessions, 1, "ván đã qua tháng 1 được lưu lịch sử")
	s:act(1, "build", "house", gate - 1)
	H.truthy(s:newGame(1))
	H.eq(#profile.pastSessions, 1, "ván tháng 0 không lưu lịch sử")
	H.eq(profile.session.cells[gate - 1], Config.EMPTY, "làm lại từ lưới trống")
end)

H.test("Xây mẫu: bot xây theo luật, không chạy khi ván đã kết thúc", function()
	local p, s = setup({})
	local profile = s:loadPlayer(1, "A")
	s:clientReady(1)
	local ok, r = s:demoBuild(1)
	H.truthy(ok)
	H.truthy(r.built > 0)
	H.truthy(profile.session.budget < 10000 and profile.session.budget >= 0)
	H.eq((s:demoBuild(2)), false, "chưa nạp hồ sơ")
	profile.session.status = "ENDED"
	H.eq((s:demoBuild(1)), false)
end)

H.test("Snapshot gửi client có tên kịch bản và số tháng còn lại", function()
	local p, s = setup({})
	join(s, 1, "A")
	s:addScenario(1, "pandemic")
	local snap = s:snapshot(1, { isTeacher = false })
	H.eq(snap.session.scenarios[1].name, "Đại dịch")
	H.eq(snap.session.scenarios[1].monthsLeft, 6)
	H.eq(snap.persistence, "memory")
	H.eq(snap.isTeacher, false)
	H.eq(snap.saveDisabled, false)
end)

H.test("Khoá phiên: server thứ hai chờ, và server cũ bị giành khoá thì ngừng ghi", function()
	local p = Persistence.new({ forceMemory = true, log = function() end })
	local a = newSessions(p, "A")
	local b = newSessions(p, "B")
	local pa = join(a, 1, "X")
	a:tickAll()
	H.eq(pa.session.month, 1)
	-- A rời game: lưu lần cuối, nhả lock. B load ngay, thấy tiến độ mới nhất
	a:unloadPlayer(1)
	local startClock = clock
	local pb = b:loadPlayer(1, "X")
	H.eq(clock, startClock, "không phải chờ khi khoá đã nhả")
	H.eq(pb.session.month, 1)
	-- A (server treo) load lại lúc B đang giữ lock: A phải chờ, hết lượt chờ thì giành lock
	local pa2 = a:loadPlayer(1, "X")
	H.truthy(clock > startClock, "đã chờ server kia")
	H.eq(pa2.loadFailed, nil)
	-- B mất lock nên lần ghi sau bị chặn, không ghi đè
	b:clientReady(1)
	b:tickAll()
	H.eq(b:getProfile(1).lockLost, true)
	H.eq(b:snapshot(1).saveDisabled, true)
	local ok, stored = p:get(Config.DATASTORE.profiles, "u_1")
	H.eq(stored.lock.jobId, "A")
end)

H.test("Chuyển server thất bại: lấy lại khoá và chạy tiếp", function()
	local p, s = setup({})
	local profile = join(s, 1, "A")
	H.truthy(s:beginTeleport(1))
	H.eq(profile.session.status, "PAUSED")
	s:tickAll()
	H.eq(profile.session.month, 0, "không tick khi đang chuyển")
	local _, stored = p:get(Config.DATASTORE.profiles, "u_1")
	H.eq(stored.lock, nil, "đã nhả khoá trước khi chuyển")
	H.truthy(s:teleportFailed(1))
	H.eq(profile.session.status, "ACTIVE")
	s:tickAll()
	H.eq(profile.session.month, 1)
end)

H.test("Học sinh không tạo được lớp; giáo viên tạo được mã 6 ký tự không nguyên âm", function()
	local p, s, c = setup({ [99] = true })
	join(s, 1, "Student")
	join(s, 99, "Teacher")
	H.eq((c:createClass(1, "Student", "10A1")), false)
	H.eq((c:createClass(99, "Teacher", "   ")), false)
	local ok, cls = c:createClass(99, "Teacher", "10A1")
	H.truthy(ok)
	H.eq(#cls.code, 6)
	H.eq(cls.code:find("[AEIOU01]"), nil, "không có nguyên âm / 0 / 1")
	local ok2, list = c:getTeacherClasses(99)
	H.eq(#list, 1)
	H.eq(list[1].memberCount, 0)
end)

H.test("Tham gia lớp: không phân biệt hoa thường, không trùng, mã sai báo lỗi, giới hạn số lớp", function()
	local p, s, c = setup({ [99] = true })
	join(s, 1, "Alice")
	join(s, 99, "T")
	local _, cls = c:createClass(99, "T", "10A1")
	local ok, joined = c:joinClass(1, "Alice", string.lower(cls.code))
	H.truthy(ok)
	H.eq(joined.name, "10A1")
	H.eq((c:joinClass(1, "Alice", cls.code)), false, "đã ở trong lớp")
	H.eq(#s:getProfile(1).classes, 1)
	H.eq((c:joinClass(1, "Alice", "ZZZZZZ")), false)
	H.eq((c:joinClass(99, "T", cls.code)), false, "giáo viên không tự vào lớp mình")
	H.eq((c:leaveClass(1, "QQQQQQ")), false, "không ở trong lớp đó")
	-- lớp lưu trong profile nên vào lại vẫn còn
	s:unloadPlayer(1)
	local ok3, mine = c:getMyClasses((s:loadPlayer(1, "Alice")).userId)
	H.eq(#mine, 1)
	-- giới hạn số lớp mỗi học sinh
	local profile = s:getProfile(1)
	for i = 2, Config.MAX_CLASSES_PER_STUDENT do
		table.insert(profile.classes, "FAKE" .. i)
	end
	local _, cls2 = c:createClass(99, "T", "10A2")
	local okLimit, errLimit = c:joinClass(1, "Alice", cls2.code)
	H.eq(okLimit, false)
	H.truthy(errLimit:find("tối đa"))
end)

H.test("Gán kịch bản: đếm đúng số học sinh nhận được, chỉ chủ lớp được gán", function()
	local p, s, c, lb, notices = setup({ [99] = true, [98] = true })
	join(s, 99, "T"); join(s, 98, "T2")
	local _, cls = c:createClass(99, "T", "Lop")
	for id = 1, 3 do
		join(s, id, "HS" .. id)
		c:joinClass(id, "HS" .. id, cls.code)
	end
	join(s, 4, "Ngoai lop")
	local ok, result = c:assignScenario(99, cls.code, "recession")
	H.truthy(ok)
	H.eq(result.appliedHere, 3)
	H.eq(result.memberCount, 3)
	H.eq(#s:getProfile(4).session.scenarios, 0)
	H.eq(#notices, 3)
	H.eq((c:assignScenario(98, cls.code, "recession")), false)
	H.eq((c:assignScenario(99, cls.code, "khongco")), false)
	-- gán lại cùng kịch bản thì không cộng dồn
	local _, again = c:assignScenario(99, cls.code, "recession")
	H.eq(again.appliedHere, 0)
end)

H.test("Học sinh vắng mặt nhận sự kiện khi vào game; học sinh mới vào lớp không nhận sự kiện cũ", function()
	local p, s, c, lb, notices = setup({ [99] = true })
	join(s, 99, "T")
	local _, cls = c:createClass(99, "T", "Lop")
	join(s, 1, "Vang")
	c:joinClass(1, "Vang", cls.code)
	s:unloadPlayer(1)
	local _, r = c:assignScenario(99, cls.code, "supply")
	H.eq(r.appliedHere, 0)
	-- quay lại game
	local profile = s:loadPlayer(1, "Vang")
	H.eq(c:syncPendingScenarios(1, profile), 1)
	H.eq(profile.session.scenarios[1].id, "supply")
	H.eq(c:syncPendingScenarios(1, profile), 0, "không áp lại lần hai")
	-- học sinh mới
	join(s, 2, "Moi")
	c:joinClass(2, "Moi", cls.code)
	H.eq(c:syncPendingScenarios(2, s:getProfile(2)), 0)
	-- sự kiện quá cũ (hơn 7 ngày) không áp
	s:unloadPlayer(2)
	c:assignScenario(99, cls.code, "prices")
	clock = clock + Config.SCENARIO_SYNC_MAX_AGE + 10
	local p2 = s:loadPlayer(2, "Moi")
	H.eq(c:syncPendingScenarios(2, p2), 0)
end)

H.test("Thông điệp từ server khác áp kịch bản đúng một lần", function()
	local p, s, c = setup({ [99] = true })
	join(s, 99, "T")
	local _, cls = c:createClass(99, "T", "Lop")
	join(s, 1, "A")
	c:joinClass(1, "A", cls.code)
	local entry = { seq = 1, scenarioId = "supply", at = clock, by = 99 }
	c:onMessage({ kind = "assignScenario", code = cls.code, entry = entry })
	H.eq(s:getProfile(1).session.scenarios[1].id, "supply")
	c:onMessage({ kind = "assignScenario", code = cls.code, entry = entry })
	H.eq(#s:getProfile(1).session.scenarios, 1)
	c:onMessage({ kind = "assignScenario", code = cls.code, entry = { seq = "x" } }) -- rác: bỏ qua
end)

H.test("Thông điệp gọn {mã lớp, số thứ tự}: server nhận tự đọc sự kiện từ hồ sơ lớp", function()
	local p = Persistence.new({ forceMemory = true, log = function() end })
	-- server A (giáo viên) và server B (học sinh) dùng chung kho dữ liệu
	local sa, sb = newSessions(p, "A"), newSessions(p, "B")
	local sent = {}
	local ca = ClassroomService.new({ persistence = p, sessions = sa, now = now, random = rng,
		isTeacher = function() return true end, publish = function(m) table.insert(sent, m) return true end })
	local cb = ClassroomService.new({ persistence = p, sessions = sb, now = now, random = rng, isTeacher = function() return false end })
	join(sa, 99, "T")
	local _, cls = ca:createClass(99, "T", "Lop")
	join(sb, 1, "HS")
	cb:joinClass(1, "HS", cls.code)
	local okDef, def = ca:createScenario(99, { name = "Bão", effects = { revenueMultiplier = 0.8 } })
	local ok, r = ca:assignScenario(99, cls.code, def.id)
	H.eq(r.appliedHere, 0)
	H.eq(r.broadcast, true)
	H.eq(sent[1].entry, nil, "không gửi kèm chi tiết")
	cb:onMessage(sent[1])
	local sc = sb:getProfile(1).session.scenarios[1]
	H.eq(sc and sc.name, "Bão")
end)

H.test("Kịch bản tuỳ chỉnh: tạo, kiểm tra dữ liệu, gán và có tác dụng", function()
	local p, s, c = setup({ [99] = true })
	join(s, 99, "T")
	join(s, 1, "HS")
	H.eq((c:createScenario(1, { name = "X", effects = { revenueMultiplier = 0.5 } })), false, "học sinh không tạo được")
	H.eq((c:createScenario(99, { name = "Rỗng", effects = {} })), false, "cần ít nhất một hiệu ứng")
	H.eq((c:createScenario(99, { name = "   ", effects = { revenueMultiplier = 0.5 } })), false, "cần tên")
	local ok, def = c:createScenario(99, {
		name = "Bão lớn", description = "Mưa bão", severity = 99, durationMonths = 2,
		effects = { revenueMultiplier = 0.1, happinessPenalty = -12.4, hack = 5 },
	})
	H.truthy(ok)
	H.eq(def.severity, 10, "kẹp mức độ")
	H.eq(def.effects.revenueMultiplier, 0.5, "kẹp về giới hạn an toàn")
	H.eq(def.effects.happinessPenalty, -12)
	H.eq(def.effects.hack, nil, "hiệu ứng lạ bị bỏ")
	local okList, list = c:listScenarios(99)
	H.eq(#list.custom, 1)
	H.eq(#list.catalog, 4)
	local _, cls = c:createClass(99, "T", "Lop")
	c:joinClass(1, "HS", cls.code)
	local okAssign, res = c:assignScenario(99, cls.code, def.id)
	H.truthy(okAssign)
	H.eq(res.appliedHere, 1)
	local session = s:getProfile(1).session
	H.eq(session.scenarios[1].custom, true)
	H.eq(session.scenarios[1].name, "Bão lớn")
	local snap = s:snapshot(1)
	H.eq(snap.session.scenarios[1].monthsLeft, 2)
	s:tickAll()
	H.eq(session.scenarios[1].monthsActive, 1)
	s:tickAll()
	H.eq(#session.scenarios, 0, "hết hạn sau 2 tháng")
	H.truthy(c:deleteScenario(99, def.id))
	H.eq((c:deleteScenario(99, def.id)), false)
end)

H.test("Bão giá vật liệu: xây đắt gấp 1,5 trong lúc sự kiện diễn ra", function()
	local p, s = setup({})
	local profile = join(s, 1, "A")
	s:addScenario(1, "prices")
	local _, r = s:act(1, "build", "house", 1)
	H.eq(r.cost, 900)
	H.eq(profile.session.budget, 10000 - 900)
end)

H.test("Bảng tiến độ, chi tiết học sinh và xuất CSV", function()
	local p, s, c = setup({ [99] = true })
	join(s, 99, "T")
	local _, cls = c:createClass(99, "T", "Lop")
	join(s, 1, "Alice, \"A\"")
	c:joinClass(1, "Alice, \"A\"", cls.code)
	s:act(1, "build", "house", Config.GATE_INDEX - 1)
	s:act(1, "build", "office", 1) -- chưa nối đường
	s:tickAll(); s:tickAll()
	c:recordProgress(1, s:getProfile(1))
	local ok, roster = c:getRoster(99, cls.code)
	H.truthy(ok)
	H.eq(#roster.members, 1)
	H.eq(roster.members[1].summary.month, 2)
	H.eq(roster.members[1].online, true)
	H.eq((c:getRoster(1, cls.code)), false, "học sinh không xem được")
	local okD, detail = c:getStudentDetail(99, cls.code, 1)
	H.truthy(okD)
	H.eq(#detail.detail.history, 2)
	H.eq(detail.detail.city.counts.house, 1)
	H.eq(detail.detail.city.unconnected, 1)
	H.eq(detail.detail.tax, 20)
	H.eq((c:getStudentDetail(99, cls.code, 12345)), false)
	local okCsv, csv = c:exportClassCsv(99, cls.code)
	H.truthy(okCsv)
	H.eq(csv.rows, 2)
	local lines = {}
	for line in csv.csv:gmatch("[^\n]+") do
		table.insert(lines, line)
	end
	H.eq(#lines, 3)
	H.truthy(lines[1]:find("^student_name,user_id"))
	H.truthy(lines[2]:find('^"Alice, ""A""",1,ACTIVE,1,'), "tên có dấu phẩy/ngoặc kép được bọc đúng: " .. lines[2])
	H.eq((c:exportClassCsv(1, cls.code)), false)
	-- rời game: tóm tắt được lưu vào lớp, vẫn xem được khi offline
	local removed = s:unloadPlayer(1)
	c:persistProgress(1, removed)
	c:forget(1)
	clock = clock + 3600
	local _, roster2 = c:getRoster(99, cls.code)
	H.eq(roster2.members[1].online, false)
	H.eq(roster2.members[1].summary.month, 2)
end)

H.test("Bảng xếp hạng giữ điểm cao nhất mỗi người, kiểm tra thành viên lớp, bỏ người chơi thử", function()
	local p, s, c, lb = setup({ [99] = true })
	join(s, 99, "T")
	local _, cls = c:createClass(99, "T", "Lop")
	join(s, 1, "A"); c:joinClass(1, "A", cls.code)
	join(s, 2, "B"); c:joinClass(2, "B", cls.code)
	join(s, 3, "C")
	lb:submit(1, "A", 120.5, { cls.code })
	lb:submit(1, "A", 80, { cls.code }) -- thấp hơn, bỏ qua
	lb:submit(2, "B", 300, { cls.code })
	lb:submit(3, "C", 200, {})
	lb:submit(-1, "Player1", 999, {}) -- người chơi thử trong Studio
	local ok, data = lb:top("global", nil, 1)
	local rows = data.rows
	H.eq(#rows, 3)
	H.eq(rows[1].name, "B")
	H.eq(rows[3].score, 120.5)
	H.eq(rows[3].isMe, true)
	local ok2, classData = lb:top("class", cls.code, 2)
	H.eq(#classData.rows, 2)
	H.eq((lb:top("class", cls.code, 3)), false, "người ngoài lớp bị chặn")
	H.eq((lb:top("class", "NOPE00", 1)), false)
	-- cache: điểm mới chỉ hiện khi cache hết hạn
	lb:submit(3, "C", 500, {})
	local _, cached = lb:top("global", nil, 1)
	H.eq(cached.rows[1].name, "B", "vẫn dùng bản đệm")
	clock = clock + Config.LEADERBOARD_CACHE_SECONDS + 1
	local _, fresh = lb:top("global", nil, 1)
	H.eq(fresh.rows[1].name, "C")
end)

H.test("Bảng xếp hạng: tra tên lỗi không gọi lại liên tục", function()
	local p, s, c, lb = setup({})
	local calls = 0
	lb.resolveName = function() calls = calls + 1 error("web down") end
	lb:submit(7, nil, 50, {})
	lb.names = {}
	local _, d1 = lb:top("global", nil, 1)
	H.eq(d1.rows[1].name, "Người chơi 7")
	clock = clock + Config.LEADERBOARD_CACHE_SECONDS + 1
	lb:top("global", nil, 1)
	H.eq(calls, 1)
end)

H.test("Phòng học riêng: báo lỗi khi chưa publish, dùng lại phòng cũ, không vào lại phòng đang ở", function()
	local p, s, c = setup({ [99] = true })
	join(s, 99, "T")
	local _, cls = c:createClass(99, "T", "Lop")
	c.reserveServer = function() error("not in Studio") end
	local ok, err = c:openRoom(99, cls.code)
	H.eq(ok, false)
	H.truthy(err:find("publish"))
	local reserved = 0
	c.reserveServer = function() reserved = reserved + 1 return "ACCESS", "PSID-1" end
	H.truthy(c:openRoom(99, cls.code))
	local _, again = c:openRoom(99, cls.code)
	H.eq(again.reused, true)
	H.eq(reserved, 1)
	local teleported = nil
	c.teleportToRoom = function(userId, code) teleported = code end
	H.truthy(c:enterRoom(99, cls.code))
	H.eq(teleported, "ACCESS")
	c.currentPrivateServerId = "PSID-1"
	H.eq((c:enterRoom(99, cls.code)), false, "đang ở trong phòng")
	H.truthy(c:closeRoom(99, cls.code))
	H.eq((c:enterRoom(99, cls.code)), false, "phòng đã đóng")
end)

H.test("Tên lớp tiếng Việt dài được cắt theo ký tự và qua bộ lọc; lọc lỗi => tên mặc định", function()
	local p, s, c = setup({ [99] = true })
	join(s, 99, "T")
	local filtered = {}
	c.filterText = function(text) table.insert(filtered, text) return text end
	local long = string.rep("Lớp Kinh tế học ", 5)
	local ok, cls = c:createClass(99, "T", long)
	H.truthy(ok)
	H.truthy(utf8.len(cls.name) ~= nil, "UTF-8 hợp lệ")
	H.truthy(utf8.len(cls.name) <= 40, "tối đa 40 ký tự")
	H.eq(#filtered, 1, "đã gọi bộ lọc")
	H.eq(ClassroomService.trimName("\xff\xfe"), nil, "chuỗi UTF-8 hỏng bị từ chối")
	H.eq(ClassroomService.trimName(string.rep("a", 5000)):len(), 40, "chuỗi rất dài bị cắt trước khi xử lý")
	c.filterText = function() error("filter down") end
	local ok2, cls2 = c:createClass(99, "T", "Lop B")
	H.truthy(ok2)
	H.eq(cls2.name, "Lớp " .. cls2.code, "lọc lỗi => dùng tên mặc định")
	H.eq(cls2.renamed, true)
end)

H.test("Quản trị: thêm/bớt giáo viên, cấm, xoá dữ liệu theo yêu cầu", function()
	local p, s, c, lb = setup({ [99] = true })
	local extra, banned = nil, {}
	local a = AdminService.new({
		persistence = p, sessions = s, leaderboard = lb, now = now,
		isOwner = function(id) return id == 1000 end,
		setExtraTeachers = function(map) extra = map end,
		getUserIdFromName = function(name)
			if name == "cogiao_lan" then return 555 end
			error("not found")
		end,
		getNameFromUserId = function(id) return "user" .. id end,
		banUser = function(id, duration, reason) banned[id] = { duration = duration, reason = reason } end,
		unbanUser = function(id) banned[id] = nil end,
		isInServer = function(id) return s:getProfile(id) ~= nil end,
	})
	H.eq((a:addTeacher(1, "cogiao_lan")), false, "không phải chủ game")
	H.eq((a:addTeacher(1000, "không hợp lệ!")), false)
	H.eq((a:addTeacher(1000, "khongtontai")), false)
	local ok, t = a:addTeacher(1000, "@cogiao_lan")
	H.truthy(ok)
	H.eq(t.userId, 555)
	H.truthy(extra["555"] ~= nil, "Roles được cập nhật")
	local okState, state = a:getState(1000)
	H.eq(#state.teachers, 1)
	H.truthy(a:removeTeacher(1000, 555))
	H.eq(extra["555"], nil)
	-- cấm
	H.truthy(a:ban(1000, "777", 3, "Spam"))
	H.eq(banned[777].duration, 3 * 86400)
	H.eq((a:ban(1000, "1000", 0, "")), false, "không tự cấm")
	local _, st2 = a:getState(1000)
	H.eq(#st2.bans, 1)
	H.truthy(a:unban(1000, 777))
	H.eq(banned[777], nil)
	-- xoá dữ liệu: học sinh 5 có hồ sơ, ở trong lớp, có điểm
	join(s, 99, "T")
	local _, cls = c:createClass(99, "T", "Lop")
	join(s, 5, "Xoa")
	c:joinClass(5, "Xoa", cls.code)
	lb:submit(5, "Xoa", 100, { cls.code })
	-- điểm còn sót trong bảng xếp hạng của luật cũ (v1) cũng phải bị xoá
	local legacy = Config.LEGACY_LEADERBOARDS[1]
	p:orderedSetMax(legacy.global, "5", 47290)
	p:orderedSetMax(legacy.classPrefix .. cls.code, "5", 47290)
	H.eq((a:deleteUserData(1000, "5")), false, "đang trong server")
	s:unloadPlayer(5)
	local okDel, report = a:deleteUserData(1000, "5")
	H.truthy(okDel)
	H.eq(report.classesLeft, 1)
	local _, profile = p:get(Config.DATASTORE.profiles, "u_5")
	H.eq(profile, nil, "hồ sơ đã xoá")
	H.eq(c:getClass(cls.code).members["5"], nil, "đã rút khỏi lớp")
	clock = clock + Config.LEADERBOARD_CACHE_SECONDS + 1
	local _, top = lb:top("global", nil, 99)
	H.eq(#top.rows, 0, "đã xoá khỏi bảng xếp hạng")
	local _, legacyTop = p:orderedTop(legacy.global, 10)
	local _, legacyClassTop = p:orderedTop(legacy.classPrefix .. cls.code, 10)
	H.eq(#legacyTop + #legacyClassTop, 0, "đã xoá khỏi bảng xếp hạng của luật cũ")
	-- xoá giáo viên thì xoá luôn lớp của họ
	s:unloadPlayer(99)
	local _, r2 = a:deleteUserData(1000, "99")
	H.eq(r2.classesDeleted, 1)
	H.eq(c:getClass(cls.code), nil)
end)

H.test("Lưu song song khi tắt server và nhả khoá", function()
	local p, s = setup({})
	join(s, 1, "A"); join(s, 2, "B")
	s:tickAll()
	s:saveAll()
	for _, id in ipairs({ 1, 2 }) do
		local _, stored = p:get(Config.DATASTORE.profiles, "u_" .. id)
		H.eq(stored.lock, nil)
		H.eq(stored.session.month, 1)
		H.eq(stored.session.autoPaused, true)
	end
end)


H.test("Học sinh mở ván mới (tháng 0) không làm mất kết quả ván vừa xong trong bảng của giáo viên", function()
	local p, s, c = setup({ [99] = true })
	join(s, 99, "T")
	local _, cls = c:createClass(99, "T", "Lop")
	local profile = join(s, 1, "A")
	c:joinClass(1, "A", cls.code)
	local failMonth = goBankrupt(s, 1)
	H.eq(profile.session.status, "FAILED")
	local removed = s:unloadPlayer(1)
	c:persistProgress(1, removed, true)
	c:forget(1)
	local again = s:loadPlayer(1, "A") -- phiên đã thua nên mở ván mới tháng 0
	H.eq(again.session.month, 0)
	c:recordProgress(1, again)
	local _, roster = c:getRoster(99, cls.code)
	H.eq(roster.members[1].summary.month, failMonth, "vẫn báo kết quả ván vừa xong")
	H.eq(roster.members[1].summary.status, "FAILED")
	local _, csv = c:exportClassCsv(99, cls.code)
	H.eq(csv.rows, failMonth, "CSV vẫn có đủ các tháng của ván vừa xong")
	-- bản lưu trong lớp dạng gọn (không có city), có field phiên bản v
	local record = c:getClass(cls.code)
	local stored = record.members["1"].summary
	H.truthy(stored.h ~= nil and stored.city == nil)
	H.eq(stored.v, 2)
	local _, detail = c:getStudentDetail(99, cls.code, 1)
	H.truthy(detail.detail.history[1].employment ~= nil, "đọc được tỉ lệ việc làm từ lịch sử nén")
end)

H.test("Không hồi sinh hồ sơ đã bị xoá; không ghi khi đang chuyển server; làm mới khoá khi tạm dừng", function()
	local p, s = setup({})
	local profile = join(s, 1, "A")
	p:remove(Config.DATASTORE.profiles, "u_1") -- chủ game xoá dữ liệu
	s:tickAll()
	local _, stored = p:get(Config.DATASTORE.profiles, "u_1")
	H.eq(stored, nil, "không tạo lại hồ sơ đã xoá")
	H.eq(profile.lockLost, true)
	-- chuyển server
	join(s, 2, "B")
	s:beginTeleport(2)
	s:requestSave(2, false)
	local _, st2 = p:get(Config.DATASTORE.profiles, "u_2")
	H.eq(st2.lock, nil, "không giành lại khoá sau khi đã nhả để chuyển server")
	-- tạm dừng lâu: khoá vẫn được làm mới
	join(s, 3, "C")
	s:togglePause(3)
	local _, before = p:get(Config.DATASTORE.profiles, "u_3")
	clock = clock + Config.LOCK_REFRESH_SECONDS + 1
	s:tickAll()
	local _, after = p:get(Config.DATASTORE.profiles, "u_3")
	H.truthy(after.lock.at > before.lock.at, "khoá được làm mới")
end)

os.exit(H.summary() and 0 or 1)
