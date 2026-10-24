-- Lớp học và mọi thứ GV làm với lớp: tiến độ HS, gán kịch bản, CSV, phòng học riêng.
-- Lớp: Config.DATASTORE.classes, key "c_<MÃ>":
--   { code, name, teacherId, teacherName, createdAt, nextSeq,
--     members = { ["<userId>"] = { name, joinedAt, summary } },
--     room = { accessCode, privateServerId, openedAt } | nil,
--     scenarioLog = { { seq, scenarioId, def?, at, by } ... } (mới nhất trước) }
-- Kịch bản tự tạo: Config.DATASTORE.scenarios, key "t_<teacherId>":
--   { nextId, list = { { id, name, description, severity, durationMonths, effects, createdAt } } }
-- Tiến độ sống: MemoryStore key "u_<userId>" (2 phút không refresh là hết hạn) + bộ nhớ server.
-- members[...].summary chỉ ghi lúc HS rời game / xong ván, tránh ghi dồn vào 1 key.
-- HS vắng lúc gán kịch bản thì nhận khi vào lại (profile.scenarioSync[mã lớp] = seq cuối đã nhận)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("EconCity")

local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local GameTick = require(Shared:WaitForChild("GameTick"))
local Scenarios = require(Shared:WaitForChild("Scenarios"))
local CityEngine = require(Shared:WaitForChild("CityEngine"))

local ClassroomService = {}
ClassroomService.__index = ClassroomService

local MAX_NAME_CHARS = 40
local MAX_DESCRIPTION_CHARS = 120
local MAX_SCENARIO_LOG = 20

-- deps: persistence, sessions, isTeacher(userId), now, random. Tuỳ chọn: publish(message) (MessagingService),
-- notify(userId, text), reserveServer() trả (accessCode, privateServerId), teleportToRoom(userId, accessCode).
-- currentPrivateServerId: "" nếu server thường
-- filterText(text, userId): bắt buộc cho chữ người chơi nhập mà người khác thấy
function ClassroomService.new(deps)
	local self = setmetatable({}, ClassroomService)
	self.persistence = deps.persistence
	self.sessions = deps.sessions
	self.isTeacher = deps.isTeacher or function()
		return false
	end
	self.now = deps.now or os.time
	self.random = deps.random or math.random
	self.publish = deps.publish
	self.notify = deps.notify
	self.reserveServer = deps.reserveServer
	self.teleportToRoom = deps.teleportToRoom
	self.currentPrivateServerId = deps.currentPrivateServerId or ""
	self.filterText = deps.filterText
	self.liveSummaries = {} -- [userId] = detail của người chơi trong server này
	self.pendingWrites = 0 -- số lần ghi tóm tắt lớp đang chạy, server chờ trước khi tắt
	return self
end

local function classKey(code)
	return "c_" .. code
end

local function scenarioStoreKey(teacherId)
	return "t_" .. tostring(teacherId)
end

local function liveKey(userId)
	return "u_" .. tostring(userId)
end
ClassroomService.liveKey = liveKey

-- history nén: mỗi tháng 1 mảng { tháng, ngân sách, doanh thu, hạnh phúc, % việc làm, dân số }, nhỏ đi ~2 lần
-- v = 2 là luật xây thành phố. Bản cũ cột 5 là lạm phát, đừng đọc thành việc làm
local PACK_VERSION = 2
local function packHistory(history)
	local out = {}
	for _, h in ipairs(history or {}) do
		table.insert(out, { h.month, h.budget, h.gdp, h.happiness, h.employment, h.population })
	end
	return out
end

local function unpackHistory(packed, current)
	local out = {}
	for _, row in ipairs(packed or {}) do
		if type(row) == "table" then
			if type(row[1]) == "number" then
				table.insert(out, { month = row[1], budget = row[2], gdp = row[3], happiness = row[4], employment = current and row[5] or nil, population = row[6] })
			else
				table.insert(out, row) -- dạng cũ
			end
		end
	end
	return out
end

local DETAIL_FIELDS = { "sessionId", "month", "maxMonths", "status", "budget", "gdp", "happiness", "employment", "population", "tax", "prosperityScore", "updatedAt", "finishedGame", "finishedAt" }

-- full: thêm city + sự kiện (bản sống). Không full: chỉ số liệu + history (bản lưu trong lớp)
local function packDetail(detail, full)
	local out = { h = packHistory(detail.history), v = PACK_VERSION }
	for _, key in ipairs(DETAIL_FIELDS) do
		out[key] = detail[key]
	end
	if full then
		out.city = detail.city
		out.scenarios = detail.scenarios
	end
	return out
end

local function unpackDetail(packed)
	if type(packed) ~= "table" then
		return nil
	end
	local out = {}
	for k, v in pairs(packed) do
		out[k] = v
	end
	out.history = packed.history or unpackHistory(packed.h, packed.v == PACK_VERSION)
	out.h = nil
	return out
end
ClassroomService.packDetail = packDetail
ClassroomService.unpackDetail = unpackDetail

local function normalizeCode(code)
	if type(code) ~= "string" or #code > 40 then
		return nil
	end
	code = string.upper((code:gsub("%s+", "")))
	if #code < 3 or #code > 12 or code:find("[^%w]") then
		return nil
	end
	return code
end
ClassroomService.normalizeCode = normalizeCode

-- cắt theo ký tự, không theo byte, không thì vỡ chữ có dấu (DataStore từ chối UTF-8 hỏng)
local function trimName(name)
	return Util.cleanUserText(name, MAX_NAME_CHARS, Config.MAX_TEXT_BYTES)
end
ClassroomService.trimName = trimName

local function countMembers(record)
	local count = 0
	for _ in pairs(record.members or {}) do
		count = count + 1
	end
	return count
end

local function contains(list, value)
	for _, v in ipairs(list or {}) do
		if v == value then
			return true
		end
	end
	return false
end

function ClassroomService:_generateCode()
	local alphabet = Config.CLASS_CODE_ALPHABET
	local chars = {}
	for i = 1, Config.CLASS_CODE_LENGTH do
		local idx = math.floor(self.random() * #alphabet) + 1
		chars[i] = alphabet:sub(idx, idx)
	end
	return table.concat(chars)
end

-- lọc qua TextService, lỗi thì nil
function ClassroomService:_filter(text, userId)
	if not self.filterText then
		return text
	end
	local ok, filtered = pcall(self.filterText, text, userId)
	if ok and type(filtered) == "string" and #filtered > 0 then
		return filtered
	end
	return nil
end

function ClassroomService:getClass(code)
	code = normalizeCode(code)
	if not code then
		return nil
	end
	local ok, record = self.persistence:get(Config.DATASTORE.classes, classKey(code))
	if ok and type(record) == "table" then
		return record
	end
	return nil
end

function ClassroomService:_isMemberRecord(record, userId)
	return (record.members or {})[tostring(userId)] ~= nil
end

function ClassroomService:_inThisRoom(record)
	return record.room ~= nil and self.currentPrivateServerId ~= ""
		and record.room.privateServerId == self.currentPrivateServerId
end

-- Giáo viên

function ClassroomService:createClass(teacherId, teacherName, className)
	if not self.isTeacher(teacherId) then
		return false, "Chỉ giáo viên mới tạo được lớp"
	end
	local profile = self.sessions:getProfile(teacherId)
	if not profile then
		return false, "Dữ liệu chưa tải xong, thử lại sau giây lát"
	end
	className = trimName(className)
	if not className then
		return false, "Hãy nhập tên lớp"
	end
	if #profile.teaching >= Config.MAX_CLASSES_PER_TEACHER then
		return false, "Đã đạt số lớp tối đa (" .. Config.MAX_CLASSES_PER_TEACHER .. ")"
	end
	-- tên lớp hiện cho HS nên phải lọc. Lọc lỗi thì dùng "Lớp <mã>"
	local filteredName = self:_filter(className, teacherId)
	for _ = 1, 8 do
		local code = self:_generateCode()
		local finalName = filteredName or ("Lớp " .. code)
		local created = nil
		local ok = self.persistence:update(Config.DATASTORE.classes, classKey(code), function(old)
			created = nil
			if old ~= nil then
				return nil -- trùng mã, thử mã khác
			end
			created = {
				code = code,
				name = finalName,
				teacherId = teacherId,
				teacherName = teacherName,
				createdAt = self.now(),
				nextSeq = 1,
				members = {},
				scenarioLog = {},
			}
			return created
		end)
		if ok and created then
			table.insert(profile.teaching, 1, code)
			self.sessions:requestSave(teacherId, false)
			return true, { code = code, name = finalName, renamed = filteredName == nil }
		end
		if not ok then
			return false, "Lỗi lưu trữ, hãy thử lại"
		end
	end
	return false, "Không tạo được mã lớp, hãy thử lại"
end

function ClassroomService:getTeacherClasses(teacherId)
	local profile = self.sessions:getProfile(teacherId)
	if not profile then
		return false, "Dữ liệu chưa tải xong, thử lại sau giây lát"
	end
	local out = {}
	for _, code in ipairs(profile.teaching) do
		local record = self:getClass(code)
		if record and record.teacherId == teacherId then
			table.insert(out, {
				code = record.code,
				name = record.name,
				memberCount = countMembers(record),
				roomOpen = record.room ~= nil,
				inRoom = self:_inThisRoom(record),
			})
		end
	end
	return true, out
end

function ClassroomService:_assertOwner(teacherId, code)
	local record = self:getClass(code)
	if not record then
		return nil, "Không tìm thấy lớp"
	end
	if record.teacherId ~= teacherId then
		return nil, "Bạn không phải giáo viên của lớp này"
	end
	return record
end

-- lấy theo thứ tự: server này, MemoryStore (server khác), bản lưu trong lớp
function ClassroomService:_memberProgress(record, userId, member)
	local detail = self.liveSummaries[userId]
	local inThisServer = self.sessions:getProfile(userId) ~= nil
	if not detail then
		local ok, live = self.persistence:liveGet(Config.DATASTORE.classLiveMap, liveKey(userId))
		if ok and type(live) == "table" then
			detail = unpackDetail(live)
		end
	end
	detail = detail or unpackDetail(member.summary)
	local online = inThisServer
	if not online and type(detail) == "table" and tonumber(detail.updatedAt) then
		online = (self.now() - detail.updatedAt) <= Config.ONLINE_WINDOW_SECONDS
	end
	return detail, online
end

local function shortSummary(detail)
	if type(detail) ~= "table" then
		return nil
	end
	return {
		month = detail.month,
		maxMonths = detail.maxMonths,
		status = detail.status,
		budget = detail.budget,
		gdp = detail.gdp,
		happiness = detail.happiness,
		prosperityScore = detail.prosperityScore,
		updatedAt = detail.updatedAt,
	}
end

function ClassroomService:_scenarioName(entry)
	if entry.def and entry.def.name then
		return entry.def.name
	end
	local def = Scenarios.get(entry.scenarioId)
	return def and def.name or tostring(entry.scenarioId)
end

-- roster + tiến độ. Online lấy bản sống, offline lấy bản lưu gần nhất
function ClassroomService:getRoster(teacherId, code)
	local record, err = self:_assertOwner(teacherId, code)
	if not record then
		return false, err
	end
	local rows = {}
	for userIdText, member in pairs(record.members or {}) do
		local userId = tonumber(userIdText) or userIdText
		local detail, online = self:_memberProgress(record, userId, member)
		table.insert(rows, {
			userId = userId,
			name = member.name,
			online = online,
			summary = shortSummary(detail),
		})
	end
	table.sort(rows, function(a, b)
		return tostring(a.name) < tostring(b.name)
	end)
	local log = {}
	for i, entry in ipairs(record.scenarioLog or {}) do
		if i > 5 then
			break
		end
		table.insert(log, { name = self:_scenarioName(entry), at = entry.at })
	end
	return true, {
		code = record.code,
		name = record.name,
		members = rows,
		roomOpen = record.room ~= nil,
		inRoom = self:_inThisRoom(record),
		scenarioLog = log,
	}
end

-- history từng tháng, công trình, sự kiện đang chạy
function ClassroomService:getStudentDetail(teacherId, code, studentId)
	local record, err = self:_assertOwner(teacherId, code)
	if not record then
		return false, err
	end
	studentId = tonumber(studentId)
	local member = studentId and (record.members or {})[tostring(studentId)]
	if not member then
		return false, "Học sinh không thuộc lớp này"
	end
	local detail, online = self:_memberProgress(record, studentId, member)
	return true, {
		userId = studentId,
		name = member.name,
		joinedAt = member.joinedAt,
		online = online,
		detail = detail,
	}
end

local function csvField(value)
	local s = tostring(value == nil and "" or value)
	if s:find('[,"\r\n]') then
		s = '"' .. s:gsub('"', '""') .. '"'
	end
	return s
end

-- mỗi dòng = 1 HS x 1 tháng của ván gần nhất
function ClassroomService:exportClassCsv(teacherId, code)
	local record, err = self:_assertOwner(teacherId, code)
	if not record then
		return false, err
	end
	local lines = {
		"student_name,user_id,session_status,month,budget,revenue,happiness,employment_pct,population,prosperity_score",
	}
	local members = {}
	for userIdText, member in pairs(record.members or {}) do
		table.insert(members, { id = tonumber(userIdText) or userIdText, member = member })
	end
	table.sort(members, function(a, b)
		return tostring(a.member.name) < tostring(b.member.name)
	end)
	local rows = 0
	for _, m in ipairs(members) do
		local detail = self:_memberProgress(record, m.id, m.member)
		local name = csvField(m.member.name)
		if type(detail) == "table" and type(detail.history) == "table" and #detail.history > 0 then
			for _, h in ipairs(detail.history) do
				table.insert(lines, table.concat({
					name,
					tostring(m.id),
					csvField(detail.status),
					tostring(h.month),
					tostring(h.budget),
					tostring(h.gdp),
					tostring(h.happiness),
					h.employment and string.format("%.1f", h.employment) or "",
					tostring(h.population or ""),
					h.month == detail.month and tostring(detail.prosperityScore or "") or "",
				}, ","))
				rows = rows + 1
			end
		else
			table.insert(lines, table.concat({ name, tostring(m.id), "NO_DATA", "0", "", "", "", "", "", "" }, ","))
			rows = rows + 1
		end
	end
	return true, { csv = table.concat(lines, "\n"), rows = rows, code = record.code, name = record.name }
end

-- Kịch bản

function ClassroomService:_loadCustomScenarios(teacherId)
	local ok, data = self.persistence:get(Config.DATASTORE.scenarios, scenarioStoreKey(teacherId))
	if not ok then
		return nil
	end
	if type(data) ~= "table" or type(data.list) ~= "table" then
		return { nextId = 1, list = {} }
	end
	return data
end

function ClassroomService:listScenarios(teacherId)
	if not self.isTeacher(teacherId) then
		return false, "Chỉ dành cho giáo viên"
	end
	local catalog = {}
	for _, s in ipairs(Scenarios.CATALOG) do
		table.insert(catalog, {
			id = s.id,
			name = s.name,
			description = s.description,
			severity = s.severity,
			durationMonths = s.durationMonths,
		})
	end
	local data = self:_loadCustomScenarios(teacherId)
	if not data then
		return false, "Không tải được kịch bản tuỳ chỉnh"
	end
	return true, { catalog = catalog, custom = data.list, max = Config.MAX_CUSTOM_SCENARIOS }
end

-- payload: { name, description, severity, durationMonths, effects }
function ClassroomService:createScenario(teacherId, payload)
	if not self.isTeacher(teacherId) then
		return false, "Chỉ giáo viên mới tạo được kịch bản"
	end
	if type(payload) ~= "table" then
		return false, "Dữ liệu không hợp lệ"
	end
	local name = trimName(payload.name)
	if not name then
		return false, "Hãy đặt tên cho kịch bản"
	end
	local description = Util.cleanUserText(payload.description, MAX_DESCRIPTION_CHARS, 400) or ""
	local clean, err = Scenarios.sanitizeCustom(payload)
	if not clean then
		return false, err
	end
	-- tên/mô tả hiện cho HS, lọc trước khi lưu
	local filteredName = self:_filter(name, teacherId)
	if not filteredName then
		return false, "Chưa kiểm duyệt được tên kịch bản, hãy thử lại sau"
	end
	local filteredDescription = ""
	if description ~= "" then
		filteredDescription = self:_filter(description, teacherId)
		if not filteredDescription then
			return false, "Chưa kiểm duyệt được mô tả, hãy thử lại sau"
		end
	end
	local created, reason = nil, nil
	local ok = self.persistence:update(Config.DATASTORE.scenarios, scenarioStoreKey(teacherId), function(old)
		created, reason = nil, nil
		local data = (type(old) == "table" and type(old.list) == "table") and old or { nextId = 1, list = {} }
		if #data.list >= Config.MAX_CUSTOM_SCENARIOS then
			reason = "Đã đạt số kịch bản tối đa (" .. Config.MAX_CUSTOM_SCENARIOS .. ")"
			return nil
		end
		local n = tonumber(data.nextId) or (#data.list + 1)
		data.nextId = n + 1
		created = {
			id = "c_" .. tostring(teacherId) .. "_" .. tostring(n),
			name = filteredName,
			description = filteredDescription,
			severity = clean.severity,
			durationMonths = clean.durationMonths,
			effects = clean.effects,
			createdAt = self.now(),
		}
		table.insert(data.list, created)
		return data
	end)
	if not ok then
		return false, "Lỗi lưu trữ, hãy thử lại"
	end
	if not created then
		return false, reason or "Không tạo được kịch bản"
	end
	return true, created
end

function ClassroomService:deleteScenario(teacherId, scenarioId)
	if not self.isTeacher(teacherId) then
		return false, "Chỉ dành cho giáo viên"
	end
	if type(scenarioId) ~= "string" then
		return false, "Kịch bản không hợp lệ"
	end
	local removed = false
	local ok = self.persistence:update(Config.DATASTORE.scenarios, scenarioStoreKey(teacherId), function(old)
		removed = false
		if type(old) ~= "table" or type(old.list) ~= "table" then
			return nil
		end
		for i = #old.list, 1, -1 do
			if old.list[i].id == scenarioId then
				table.remove(old.list, i)
				removed = true
			end
		end
		if not removed then
			return nil
		end
		return old
	end)
	if not ok then
		return false, "Lỗi lưu trữ, hãy thử lại"
	end
	if not removed then
		return false, "Không tìm thấy kịch bản"
	end
	return true
end

-- áp sự kiện lớp vào hồ sơ đang nạp nếu chưa nhận. true = đã thêm vào phiên
function ClassroomService:_applyEntry(userId, profile, code, entry, silent)
	if not contains(profile.classes, code) then
		return false
	end
	profile.scenarioSync = profile.scenarioSync or {}
	local synced = tonumber(profile.scenarioSync[code]) or 0
	if (tonumber(entry.seq) or 0) <= synced then
		return false -- nhận rồi, server khác phát lại thì bỏ qua
	end
	profile.scenarioSync[code] = entry.seq
	local session = profile.session
	if not session or GameTick.isFinished(session) then
		return false
	end
	local added = GameTick.addScenario(session, entry.scenarioId, { classCode = code, assignedBy = entry.by }, entry.def)
	if added and self.notify and not silent then
		self.notify(userId, "Giáo viên vừa gán sự kiện: " .. self:_scenarioName(entry))
	end
	return added and true or false
end

-- chỉ HS của lớp đang ở server này
function ClassroomService:applyEntryLocally(code, entry)
	local applied = 0
	for userId, profile in pairs(self.sessions.profiles) do
		-- đang teleport sang phòng riêng: hồ sơ đã lưu cuối, nhận bù ở server mới
		if not profile.teleporting and self:_applyEntry(userId, profile, code, entry, false) then
			applied = applied + 1
			self.sessions:requestSave(userId, false)
		end
	end
	return applied
end

function ClassroomService:assignScenario(teacherId, code, scenarioId)
	local record, err = self:_assertOwner(teacherId, code)
	if not record then
		return false, err
	end
	if type(scenarioId) ~= "string" then
		return false, "Kịch bản không tồn tại"
	end
	local def = nil
	if not Scenarios.get(scenarioId) then
		local data = self:_loadCustomScenarios(teacherId)
		if not data then
			return false, "Không tải được kịch bản tuỳ chỉnh"
		end
		for _, s in ipairs(data.list) do
			if s.id == scenarioId then
				def = {
					name = s.name,
					description = s.description,
					severity = s.severity,
					durationMonths = s.durationMonths,
					effects = s.effects,
				}
			end
		end
		if not def then
			return false, "Kịch bản không tồn tại"
		end
	end
	-- ghi log lớp trước (HS vắng nhận sau), rồi mới áp cho người đang chơi
	local entry = nil
	local ok = self.persistence:update(Config.DATASTORE.classes, classKey(record.code), function(old)
		entry = nil
		if type(old) ~= "table" then
			return nil
		end
		old.scenarioLog = old.scenarioLog or {}
		local seq = tonumber(old.nextSeq) or 1
		for _, e in ipairs(old.scenarioLog) do
			seq = math.max(seq, (tonumber(e.seq) or 0) + 1)
		end
		old.nextSeq = seq + 1
		entry = { seq = seq, scenarioId = scenarioId, def = def, at = self.now(), by = teacherId }
		table.insert(old.scenarioLog, 1, entry)
		while #old.scenarioLog > MAX_SCENARIO_LOG do
			table.remove(old.scenarioLog)
		end
		return old
	end)
	if not ok or not entry then
		return false, "Lỗi lưu trữ, hãy thử lại"
	end
	local appliedHere = self:applyEntryLocally(record.code, entry)
	local broadcast = false
	if self.publish then
		-- chỉ gửi mã lớp + seq cho luôn < 1 KB, server nhận tự đọc entry từ hồ sơ lớp
		broadcast = self.publish({ kind = "assignScenario", code = record.code, seq = entry.seq }) and true or false
	end
	return true, {
		appliedHere = appliedHere,
		memberCount = countMembers(record),
		broadcast = broadcast,
		name = self:_scenarioName(entry),
	}
end

-- HS vừa vào game: nhận sự kiện gán lúc vắng, chỉ trong 7 ngày gần nhất (SCENARIO_SYNC_MAX_AGE)
function ClassroomService:syncPendingScenarios(userId, profile)
	if not profile or not profile.session then
		return 0
	end
	local applied = 0
	local now = self.now()
	for _, code in ipairs(profile.classes or {}) do
		local record = self:getClass(code)
		if record and self:_isMemberRecord(record, userId) then
			local log = record.scenarioLog or {}
			-- log mới nhất đứng đầu nên duyệt ngược, cũ tới mới
			for i = #log, 1, -1 do
				local entry = log[i]
				if type(entry) == "table" and tonumber(entry.seq) then
					if (now - (tonumber(entry.at) or 0)) <= Config.SCENARIO_SYNC_MAX_AGE then
						if self:_applyEntry(userId, profile, code, entry, true) then
							applied = applied + 1
						end
					else
						-- quá cũ: đánh dấu đã nhận, không áp nữa
						profile.scenarioSync = profile.scenarioSync or {}
						if (tonumber(profile.scenarioSync[code]) or 0) < entry.seq then
							profile.scenarioSync[code] = entry.seq
						end
					end
				end
			end
		end
	end
	if applied > 0 and self.notify then
		self.notify(userId, "Trong lúc bạn vắng mặt, giáo viên đã gán " .. applied .. " sự kiện mới.")
	end
	return applied
end

-- message từ server khác (MessagingService)
function ClassroomService:onMessage(message)
	if type(message) ~= "table" then
		return
	end
	local code = normalizeCode(message.code)
	if not code then
		return
	end
	if message.kind == "assignScenario" and tonumber(message.seq) and not message.entry then
		-- server này không có HS lớp đó thì khỏi đọc DataStore
		local anyMember = false
		for _, profile in pairs(self.sessions.profiles) do
			if contains(profile.classes, code) and not profile.teleporting then
				anyMember = true
				break
			end
		end
		if not anyMember then
			return
		end
		local record = self:getClass(code)
		if not record then
			return
		end
		for _, entry in ipairs(record.scenarioLog or {}) do
			if tonumber(entry.seq) == tonumber(message.seq) then
				self:applyEntryLocally(code, entry)
				return
			end
		end
	elseif message.kind == "assignScenario" and type(message.entry) == "table" then
		-- dạng cũ: server bản cũ gửi kèm nguyên sự kiện
		local entry = message.entry
		if type(entry.scenarioId) ~= "string" or not tonumber(entry.seq) then
			return
		end
		if not Scenarios.get(entry.scenarioId) then
			if type(entry.def) ~= "table" then
				return
			end
			-- data từ server khác vẫn sanitize lại
			local clean = Scenarios.sanitizeCustom(entry.def)
			if not clean then
				return
			end
			entry.def = {
				name = Util.cleanUserText(entry.def.name, MAX_NAME_CHARS, Config.MAX_TEXT_BYTES) or "Sự kiện của giáo viên",
				description = Util.cleanUserText(entry.def.description, MAX_DESCRIPTION_CHARS, 400) or "",
				severity = clean.severity,
				durationMonths = clean.durationMonths,
				effects = clean.effects,
			}
		end
		self:applyEntryLocally(code, entry)
	elseif message.kind == "roomOpened" then
		self:_notifyMembersHere(code, "Giáo viên đã mở phòng học riêng cho lớp " .. code .. ". Mở mục Lớp học để vào phòng.")
	end
end

function ClassroomService:_notifyMembersHere(code, text)
	if not self.notify then
		return
	end
	for userId, profile in pairs(self.sessions.profiles) do
		if contains(profile.classes, code) then
			self.notify(userId, text)
		end
	end
end

-- Phòng học riêng

-- reserved server cho lớp. Đã có phòng thì dùng lại
function ClassroomService:openRoom(teacherId, code)
	local record, err = self:_assertOwner(teacherId, code)
	if not record then
		return false, err
	end
	if record.room and record.room.accessCode then
		return true, { code = record.code, reused = true }
	end
	if not self.reserveServer then
		return false, "Phòng học riêng chỉ chạy khi game đã publish"
	end
	local okReserve, accessCode, privateServerId = pcall(self.reserveServer)
	if not okReserve or type(accessCode) ~= "string" then
		return false, "Phòng học riêng chỉ chạy khi game đã publish, trong Studio thì không"
	end
	local saved = false
	local ok = self.persistence:update(Config.DATASTORE.classes, classKey(record.code), function(old)
		saved = false
		if type(old) ~= "table" then
			return nil
		end
		if old.room and old.room.accessCode then
			saved = true -- server khác vừa mở trước, giữ phòng đó
			return nil
		end
		old.room = { accessCode = accessCode, privateServerId = privateServerId, openedAt = self.now() }
		saved = true
		return old
	end)
	if not ok or not saved then
		return false, "Không lưu được phòng học, hãy thử lại"
	end
	self:_notifyMembersHere(record.code, "Giáo viên đã mở phòng học riêng cho lớp " .. record.code .. ". Mở mục Lớp học để vào phòng.")
	if self.publish then
		self.publish({ kind = "roomOpened", code = record.code })
	end
	return true, { code = record.code, reused = false }
end

function ClassroomService:closeRoom(teacherId, code)
	local record, err = self:_assertOwner(teacherId, code)
	if not record then
		return false, err
	end
	local ok = self.persistence:update(Config.DATASTORE.classes, classKey(record.code), function(old)
		if type(old) ~= "table" then
			return nil
		end
		old.room = nil
		return old
	end)
	if not ok then
		return false, "Lỗi lưu trữ, hãy thử lại"
	end
	return true
end

function ClassroomService:enterRoom(userId, code)
	local record = self:getClass(code)
	if not record then
		return false, "Không tìm thấy lớp"
	end
	local isMember = record.teacherId == userId or self:_isMemberRecord(record, userId)
	if not isMember then
		return false, "Bạn chưa tham gia lớp này"
	end
	if not record.room or not record.room.accessCode then
		return false, "Lớp chưa mở phòng học riêng"
	end
	if self:_inThisRoom(record) then
		return false, "Bạn đang ở trong phòng học riêng của lớp này rồi"
	end
	if not self.teleportToRoom then
		return false, "Phòng học riêng chỉ chạy khi game đã publish"
	end
	local ok, err = pcall(self.teleportToRoom, userId, record.room.accessCode)
	if not ok then
		return false, "Không chuyển được vào phòng: " .. tostring(err)
	end
	return true
end

-- Học sinh

function ClassroomService:joinClass(userId, name, code)
	code = normalizeCode(code)
	if not code then
		return false, "Mã lớp không hợp lệ"
	end
	local profile = self.sessions:getProfile(userId)
	if not profile then
		return false, "Dữ liệu chưa tải xong, thử lại sau giây lát"
	end
	if contains(profile.classes, code) then
		return false, "Bạn đã ở trong lớp này rồi"
	end
	if #profile.classes >= Config.MAX_CLASSES_PER_STUDENT then
		return false, "Bạn đã tham gia tối đa " .. Config.MAX_CLASSES_PER_STUDENT .. " lớp"
	end
	local joined, reason, lastSeq = nil, nil, 0
	local ok = self.persistence:update(Config.DATASTORE.classes, classKey(code), function(old)
		joined, reason, lastSeq = nil, nil, 0
		if type(old) ~= "table" then
			reason = "Không tìm thấy lớp với mã " .. code
			return nil
		end
		if old.teacherId == userId then
			reason = "Bạn là giáo viên của lớp này"
			return nil
		end
		old.members = old.members or {}
		local key = tostring(userId)
		if not old.members[key] then
			if countMembers(old) >= Config.MAX_CLASS_MEMBERS then
				reason = "Lớp đã đủ học sinh"
				return nil
			end
			old.members[key] = { name = name, joinedAt = self.now() }
		end
		for _, e in ipairs(old.scenarioLog or {}) do
			lastSeq = math.max(lastSeq, tonumber(e.seq) or 0)
		end
		joined = { code = old.code, name = old.name, teacherName = old.teacherName }
		return old
	end)
	if not ok then
		return false, "Lỗi lưu trữ, hãy thử lại"
	end
	if not joined then
		return false, reason or "Không tham gia được lớp"
	end
	table.insert(profile.classes, code)
	-- sự kiện gán trước lúc vào lớp thì không áp cho HS mới
	profile.scenarioSync = profile.scenarioSync or {}
	profile.scenarioSync[code] = lastSeq
	self.sessions:requestSave(userId, false)
	self:recordProgress(userId, profile)
	return true, joined
end

function ClassroomService:leaveClass(userId, code)
	code = normalizeCode(code)
	local profile = self.sessions:getProfile(userId)
	if not code or not profile then
		return false, "Mã lớp không hợp lệ"
	end
	if not contains(profile.classes, code) then
		return false, "Bạn không ở trong lớp này"
	end
	local ok = self.persistence:update(Config.DATASTORE.classes, classKey(code), function(old)
		if type(old) ~= "table" or not old.members or not old.members[tostring(userId)] then
			return nil
		end
		old.members[tostring(userId)] = nil
		return old
	end)
	if not ok then
		return false, "Lỗi lưu trữ, hãy thử lại"
	end
	for i = #profile.classes, 1, -1 do
		if profile.classes[i] == code then
			table.remove(profile.classes, i)
		end
	end
	if profile.scenarioSync then
		profile.scenarioSync[code] = nil
	end
	self.sessions:requestSave(userId, false)
	return true
end

function ClassroomService:getMyClasses(userId)
	local profile = self.sessions:getProfile(userId)
	if not profile then
		return false, "Dữ liệu chưa tải xong, thử lại sau giây lát"
	end
	local out = {}
	for _, code in ipairs(profile.classes) do
		local record = self:getClass(code)
		if record then
			table.insert(out, {
				code = record.code,
				name = record.name,
				teacherName = record.teacherName,
				roomOpen = record.room ~= nil,
				inRoom = self:_inThisRoom(record),
			})
		end
	end
	return true, out
end

-- Tiến độ

-- cho bảng tiến độ, getStudentDetail, CSV
function ClassroomService:detailOf(session)
	local detail = GameTick.summary(session, true)
	detail.updatedAt = self.now()
	detail.tax = session.tax
	-- số công trình từng loại + số cái chưa nối đường
	local d = CityEngine.compute(session, session.population or 0)
	local unconnected = 0
	for i, kind in ipairs(session.cells or {}) do
		-- chỉ đếm ô góc (mỗi công trình 1 lần), bỏ đường
		if Config.BUILDINGS[kind] and kind ~= "road" and not d.conn[i] then
			unconnected = unconnected + 1
		end
	end
	detail.city = { counts = d.counts, unconnected = unconnected }
	detail.scenarios = {}
	for _, s in ipairs(session.scenarios or {}) do
		local def = Scenarios.get(s.id)
		table.insert(detail.scenarios, { name = (def and def.name) or s.name or s.id, monthsLeft = Scenarios.monthsLeft(s) })
	end
	return detail
end

-- HS vừa xong ván, ván mới chưa qua tháng nào: vẫn báo kết quả ván cũ, không để "Tháng 0" đè lên
function ClassroomService:detailForProfile(profile, leaving)
	local session = profile.session
	local detail
	if (not session or (session.month or 0) == 0) and type(profile.lastFinished) == "table" then
		detail = Util.deepCopy(profile.lastFinished)
		detail.updatedAt = self.now()
		detail.finishedGame = true
	elseif session then
		detail = self:detailOf(session)
	else
		return nil
	end
	if leaving and detail.status == GameTick.STATUS.ACTIVE then
		detail.status = GameTick.STATUS.PAUSED -- rời game thì phiên tự pause
	end
	return detail
end

-- gọi mỗi lượt cho mọi người chơi trong server, kể cả đang pause (để biết ai online)
function ClassroomService:recordProgress(userId, profile)
	if not profile then
		return
	end
	local detail = self:detailForProfile(profile, false)
	if not detail then
		return
	end
	self.liveSummaries[userId] = detail
	if #(profile.classes or {}) > 0 then
		self.persistence:liveSet(Config.DATASTORE.classLiveMap, liveKey(userId), packDetail(detail, true), Config.LIVE_SUMMARY_TTL)
	end
end

-- ghi summary vào hồ sơ lớp, chỉ lúc xong ván / rời game
function ClassroomService:persistProgress(userId, profile, leaving)
	if not profile then
		return
	end
	local detail = self:detailForProfile(profile, leaving)
	if not detail then
		return
	end
	local stored = packDetail(detail, false)
	local classes = { table.unpack(profile.classes or {}) }
	self.pendingWrites = self.pendingWrites + 1
	local ok, err = pcall(function()
		for _, code in ipairs(classes) do
			self.persistence:update(Config.DATASTORE.classes, classKey(code), function(old)
				if type(old) ~= "table" or not old.members then
					return nil
				end
				local member = old.members[tostring(userId)]
				if not member then
					return nil
				end
				member.summary = stored
				return old
			end)
		end
	end)
	self.pendingWrites = self.pendingWrites - 1
	if not ok then
		print("[EconCity] Lỗi lưu tiến độ lớp: " .. tostring(err))
	end
end

-- rời server: xoá bản sống để roster lấy bản lưu, hiện offline ngay
function ClassroomService:forget(userId)
	self.liveSummaries[userId] = nil
	self.persistence:liveRemove(Config.DATASTORE.classLiveMap, liveKey(userId))
end

return ClassroomService
