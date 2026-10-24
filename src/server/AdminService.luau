-- Bảng Quản trị, chỉ owner dùng: thêm/bớt GV (publish cho mọi server), ban/unban (BanAsync, cả experience),
-- xoá data theo yêu cầu Right to be Forgotten.
-- Kho Config.DATASTORE.admin:
--   "teachers" = { ["<userId>"] = { name, addedAt, addedBy } }
--   "bans"     = { ["<userId>"] = { name, reason, days, at } }   (chỉ để hiện list)
--   "log"      = { { at, by, action, target } ... }               (30 dòng gần nhất)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("EconCity")

local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local AdminService = {}
AdminService.__index = AdminService

local STORE = Config.DATASTORE.admin

-- deps: persistence, sessions, leaderboard, isOwner(userId), setExtraTeachers(map), now,
-- getUserIdFromName / getNameFromUserId, banUser(userId, seconds, reason) / unbanUser(userId) (Players:BanAsync/UnbanAsync),
-- isInServer(userId), publish(message) tuỳ chọn
function AdminService.new(deps)
	local self = setmetatable({}, AdminService)
	for k, v in pairs(deps) do
		self[k] = v
	end
	self.now = deps.now or os.time
	return self
end

-- load list GV owner thêm rồi đẩy sang Roles
function AdminService:refresh()
	local ok, teachers = self.persistence:get(STORE, "teachers")
	if ok and self.setExtraTeachers then
		self.setExtraTeachers(type(teachers) == "table" and teachers or {})
	end
	return ok
end

function AdminService:onMessage(message)
	if type(message) == "table" and message.kind == "teachersChanged" then
		self:refresh()
	end
end

function AdminService:_log(byId, action, target)
	self.persistence:update(STORE, "log", function(old)
		local log = type(old) == "table" and old or {}
		table.insert(log, 1, { at = self.now(), by = byId, action = action, target = target })
		while #log > 30 do
			table.remove(log)
		end
		return log
	end)
end

-- input: username hoặc UserId dạng chuỗi số. Trả (userId, name) hoặc (nil, err)
function AdminService:_resolve(input)
	if type(input) == "number" then
		input = tostring(math.floor(input))
	end
	if type(input) ~= "string" then
		return nil, "Hãy nhập tên đăng nhập hoặc UserId"
	end
	input = input:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^@", "")
	if #input == 0 or #input > 40 then
		return nil, "Hãy nhập tên đăng nhập hoặc UserId"
	end
	if input:match("^%d+$") then
		local userId = tonumber(input)
		local name = nil
		if self.getNameFromUserId then
			local ok, result = pcall(self.getNameFromUserId, userId)
			if ok and type(result) == "string" then
				name = result
			end
		end
		return userId, name or ("#" .. input)
	end
	if not input:match("^[%w_]+$") then
		return nil, "Tên đăng nhập chỉ gồm chữ, số và dấu _"
	end
	if not self.getUserIdFromName then
		return nil, "Không tra được tên đăng nhập ở môi trường này"
	end
	local ok, userId = pcall(self.getUserIdFromName, input)
	if not ok or type(userId) ~= "number" then
		return nil, "Không tìm thấy người dùng Roblox tên \"" .. input .. "\""
	end
	return userId, input
end

local function sortedList(map)
	local list = {}
	for key, value in pairs(type(map) == "table" and map or {}) do
		local row = Util.deepCopy(value)
		row.userId = tonumber(key) or key
		table.insert(list, row)
	end
	table.sort(list, function(a, b)
		return (a.at or a.addedAt or 0) > (b.at or b.addedAt or 0)
	end)
	return list
end

function AdminService:getState(ownerId)
	if not self.isOwner(ownerId) then
		return false, "Chỉ chủ game mới dùng được bảng quản trị"
	end
	local ok1, teachers = self.persistence:get(STORE, "teachers")
	local ok2, bans = self.persistence:get(STORE, "bans")
	local ok3, log = self.persistence:get(STORE, "log")
	if not (ok1 and ok2 and ok3) then
		return false, "Không tải được dữ liệu quản trị"
	end
	return true, {
		teachers = sortedList(teachers),
		bans = sortedList(bans),
		log = type(log) == "table" and log or {},
		persistence = self.persistence.mode,
	}
end

function AdminService:_teachersChanged()
	self:refresh()
	if self.publish then
		self.publish({ kind = "teachersChanged" })
	end
end

function AdminService:addTeacher(ownerId, input)
	if not self.isOwner(ownerId) then
		return false, "Chỉ chủ game mới thêm được giáo viên"
	end
	local userId, nameOrErr = self:_resolve(input)
	if not userId then
		return false, nameOrErr
	end
	local ok = self.persistence:update(STORE, "teachers", function(old)
		local map = type(old) == "table" and old or {}
		map[tostring(userId)] = { name = nameOrErr, addedAt = self.now(), addedBy = ownerId }
		return map
	end)
	if not ok then
		return false, "Lỗi lưu trữ, hãy thử lại"
	end
	self:_log(ownerId, "addTeacher", nameOrErr .. " (" .. userId .. ")")
	self:_teachersChanged()
	return true, { userId = userId, name = nameOrErr }
end

function AdminService:removeTeacher(ownerId, userId)
	if not self.isOwner(ownerId) then
		return false, "Chỉ chủ game mới bớt được giáo viên"
	end
	userId = tonumber(userId)
	if not userId then
		return false, "UserId không hợp lệ"
	end
	local removed = false
	local ok = self.persistence:update(STORE, "teachers", function(old)
		removed = false
		if type(old) ~= "table" or not old[tostring(userId)] then
			return nil
		end
		old[tostring(userId)] = nil
		removed = true
		return old
	end)
	if not ok then
		return false, "Lỗi lưu trữ, hãy thử lại"
	end
	if not removed then
		return false, "Người này không có trong danh sách giáo viên"
	end
	self:_log(ownerId, "removeTeacher", tostring(userId))
	self:_teachersChanged()
	return true
end

-- days 0/nil = cấm vĩnh viễn
function AdminService:ban(ownerId, input, days, reason)
	if not self.isOwner(ownerId) then
		return false, "Chỉ chủ game mới cấm được người chơi"
	end
	local userId, nameOrErr = self:_resolve(input)
	if not userId then
		return false, nameOrErr
	end
	if userId == ownerId then
		return false, "Không thể tự cấm chính mình"
	end
	days = math.floor(tonumber(days) or 0)
	if days < 0 or days > 3650 then
		return false, "Số ngày không hợp lệ"
	end
	reason = Util.cleanUserText(reason, 100, 300) or "Vi phạm nội quy lớp học"
	if not self.banUser then
		return false, "Chức năng cấm chỉ chạy khi game đã publish"
	end
	local ok, err = pcall(self.banUser, userId, days > 0 and days * 86400 or -1, reason)
	if not ok then
		return false, "Roblox từ chối lệnh cấm: " .. tostring(err)
	end
	self.persistence:update(STORE, "bans", function(old)
		local map = type(old) == "table" and old or {}
		map[tostring(userId)] = { name = nameOrErr, reason = reason, days = days, at = self.now() }
		return map
	end)
	self:_log(ownerId, "ban", nameOrErr .. " (" .. userId .. ")")
	return true, { userId = userId, name = nameOrErr }
end

function AdminService:unban(ownerId, userId)
	if not self.isOwner(ownerId) then
		return false, "Chỉ chủ game mới bỏ cấm được"
	end
	userId = tonumber(userId)
	if not userId then
		return false, "UserId không hợp lệ"
	end
	if not self.unbanUser then
		return false, "Chức năng này chỉ chạy khi game đã publish"
	end
	local ok, err = pcall(self.unbanUser, userId)
	if not ok then
		return false, "Roblox từ chối lệnh bỏ cấm: " .. tostring(err)
	end
	self.persistence:update(STORE, "bans", function(old)
		if type(old) ~= "table" or not old[tostring(userId)] then
			return nil
		end
		old[tostring(userId)] = nil
		return old
	end)
	self:_log(ownerId, "unban", tostring(userId))
	return true
end

-- xoá hết data của 1 UserId (Roblox gửi yêu cầu Right to be Forgotten qua tin nhắn)
function AdminService:deleteUserData(ownerId, input)
	if not self.isOwner(ownerId) then
		return false, "Chỉ chủ game mới xoá được dữ liệu"
	end
	local userId, nameOrErr = self:_resolve(input)
	if not userId then
		return false, nameOrErr
	end
	if self.isInServer and self.isInServer(userId) then
		return false, "Người này đang ở trong server, hãy xoá sau khi họ rời game"
	end
	local key = "u_" .. tostring(userId)
	local okRead, profile = self.persistence:get(Config.DATASTORE.profiles, key)
	if not okRead then
		return false, "Không đọc được dữ liệu, hãy thử lại"
	end
	if type(profile) == "table" and type(profile.lock) == "table"
		and (self.now() - (tonumber(profile.lock.at) or 0)) < Config.SESSION_LOCK_STALE_SECONDS then
		return false, "Người này đang chơi ở server khác, thử lại sau vài phút"
	end
	local report = { profile = profile ~= nil, classesLeft = 0, classesDeleted = 0 }
	local classes = type(profile) == "table" and type(profile.classes) == "table" and profile.classes or {}
	local teaching = type(profile) == "table" and type(profile.teaching) == "table" and profile.teaching or {}

	-- 1. rút khỏi các lớp đã vào
	for _, code in ipairs(classes) do
		if type(code) == "string" then
			self.persistence:update(Config.DATASTORE.classes, "c_" .. code, function(old)
				if type(old) ~= "table" or not old.members or not old.members[tostring(userId)] then
					return nil
				end
				old.members[tostring(userId)] = nil
				return old
			end)
			report.classesLeft = report.classesLeft + 1
		end
	end
	-- 2. lớp người này dạy có tên họ trong đó, xoá luôn hồ sơ lớp
	for _, code in ipairs(teaching) do
		if type(code) == "string" then
			local okGet, record = self.persistence:get(Config.DATASTORE.classes, "c_" .. code)
			if okGet and type(record) == "table" and record.teacherId == userId then
				self.persistence:remove(Config.DATASTORE.classes, "c_" .. code)
				report.classesDeleted = report.classesDeleted + 1
			end
		end
	end
	self.persistence:liveRemove(Config.DATASTORE.classLiveMap, "u_" .. tostring(userId))
	-- 3. BXH, kịch bản tự tạo, list quản trị
	if self.leaderboard then
		self.leaderboard:removeUser(userId, classes)
	end
	self.persistence:remove(Config.DATASTORE.scenarios, "t_" .. tostring(userId))
	-- log quản trị: bỏ mọi dòng dính tới người này
	self.persistence:update(STORE, "log", function(old)
		if type(old) ~= "table" then
			return nil
		end
		local kept = {}
		for _, row in ipairs(old) do
			if not tostring(row.target or ""):find(tostring(userId), 1, true) and row.by ~= userId then
				table.insert(kept, row)
			end
		end
		return kept
	end)
	for _, listKey in ipairs({ "teachers", "bans" }) do
		self.persistence:update(STORE, listKey, function(old)
			if type(old) ~= "table" or not old[tostring(userId)] then
				return nil
			end
			old[tostring(userId)] = nil
			return old
		end)
	end
	-- 4. profile xoá cuối: bước trước lỗi thì chạy lại vẫn còn list lớp để dọn
	local okRemove = self.persistence:remove(Config.DATASTORE.profiles, key)
	if not okRemove then
		return false, "Xoá hồ sơ thất bại, hãy chạy lại lệnh"
	end
	self:_log(ownerId, "deleteUserData", "(đã ẩn)")
	self:_teachersChanged()
	return true, report
end

return AdminService
