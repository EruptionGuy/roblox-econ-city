-- Ai là giáo viên / chủ game, theo UserId.
-- GV: owner experience (cũng là admin, mở được bảng Quản trị), có trong TEACHER_USER_IDS/ADMIN_USER_IDS,
-- rank >= TEACHER_GROUP_MIN_RANK trong TEACHER_GROUP_ID, owner thêm ở bảng Quản trị (AdminService),
-- hoặc trong Studio khi STUDIO_EVERYONE_IS_TEACHER = true (chỉ để test)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("EconCity"):WaitForChild("Config"))

local Roles = {}
local cache = {} -- [userId] = { teacher, owner }, chỉ cache khi tra không lỗi
local extraTeachers = {} -- [userId] = true, owner thêm

local function inList(list, userId)
	for _, id in ipairs(list or {}) do
		if id == userId then
			return true
		end
	end
	return false
end

-- (isTeacher, isOwner, reliable). reliable = false khi gọi mạng lỗi, lúc đó không cache
local function compute(player)
	local userId = player.UserId
	local reliable = true
	local owner = false
	if RunService:IsStudio() and Config.STUDIO_EVERYONE_IS_TEACHER then
		return true, true, true
	end
	if inList(Config.ADMIN_USER_IDS, userId) then
		owner = true
	elseif game.CreatorType == Enum.CreatorType.User and game.CreatorId == userId then
		owner = true
	elseif game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(function()
			return player:GetRankInGroup(game.CreatorId)
		end)
		if ok then
			owner = rank >= 255
		else
			reliable = false
		end
	end
	if owner then
		return true, true, true
	end
	if inList(Config.TEACHER_USER_IDS, userId) or extraTeachers[userId] then
		return true, false, reliable
	end
	if Config.TEACHER_GROUP_ID and Config.TEACHER_GROUP_ID > 0 then
		local ok, rank = pcall(function()
			return player:GetRankInGroup(Config.TEACHER_GROUP_ID)
		end)
		if ok then
			if rank >= Config.TEACHER_GROUP_MIN_RANK then
				return true, false, reliable
			end
		else
			reliable = false
		end
	end
	return false, false, reliable
end

local function lookup(player)
	if not player then
		return { teacher = false, owner = false }
	end
	local cached = cache[player.UserId]
	if cached then
		return cached
	end
	local teacher, owner, reliable = compute(player)
	local result = { teacher = teacher, owner = owner }
	if reliable then
		cache[player.UserId] = result
	end
	return result
end

function Roles.isTeacher(player)
	return lookup(player).teacher
end

function Roles.isOwner(player)
	return lookup(player).owner
end

function Roles.isTeacherId(userId)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return Roles.isTeacher(player)
	end
	-- không ở server này: chỉ check list cố định + list owner thêm
	return inList(Config.TEACHER_USER_IDS, userId) or inList(Config.ADMIN_USER_IDS, userId) or extraTeachers[userId] == true
end

-- map { ["<userId>"] = {...} } hoặc { [userId] = true }
function Roles.setExtraTeachers(map)
	extraTeachers = {}
	for key in pairs(map or {}) do
		local id = tonumber(key)
		if id then
			extraTeachers[id] = true
		end
	end
	cache = {} -- vai trò có thể đã đổi
end

function Roles.forget(userId)
	cache[userId] = nil
end

return Roles
