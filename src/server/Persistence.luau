-- Bọc DataStore / OrderedDataStore / MemoryStore. Hàm nào cũng có thể yield, chỉ gọi từ server.
-- Game thật: luôn dùng DataStore, probe lúc start lỗi cũng vậy. Lệnh nào lỗi thì báo người đó, không mất data cả server.
-- Studio chưa publish / chưa bật API access: dùng bộ nhớ tạm.
-- Studio có API thì tên kho thêm hậu tố (mặc định "_Studio") cho khỏi lẫn data thật

local Persistence = {}
Persistence.__index = Persistence

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = deepCopy(v)
	end
	return out
end

-- options: dataStoreService/memoryStoreService (nil thì chạy bộ nhớ), wait (task.wait), log,
-- forceMemory (test), allowMemoryFallback (chỉ Studio), suffix (hậu tố tên kho)
function Persistence.new(options)
	options = options or {}
	local self = setmetatable({}, Persistence)
	self._dss = options.dataStoreService
	self._mss = options.memoryStoreService
	self._wait = options.wait or function() end
	self._log = options.log or print
	self._suffix = options.suffix or ""
	self._stores = {}
	self._ordered = {}
	self._maps = {}
	self._memory = {} -- [storeName][key] = value
	self._memoryOrdered = {} -- [storeName][key] = number
	self._memoryLive = {} -- [mapName][key] = value
	self.mode = "memory"
	self.liveMode = "memory"
	self.degraded = false -- DataStore lỗi lúc start, vẫn retry từng lệnh

	if not options.forceMemory and self._dss then
		local lastErr
		local ok = false
		for attempt = 1, 4 do
			ok, lastErr = pcall(function()
				self._dss:GetDataStore("EconCity_Probe" .. self._suffix):GetAsync("probe")
			end)
			if ok then
				break
			end
			if options.allowMemoryFallback then
				break -- Studio: khỏi retry, sang bộ nhớ tạm luôn
			end
			self._wait(attempt * 2)
		end
		if ok then
			self.mode = "datastore"
		elseif options.allowMemoryFallback then
			self._log("[EconCity] (Studio) DataStore unavailable, using memory: " .. tostring(lastErr))
		else
			self.mode = "datastore"
			self.degraded = true
			self._log("[EconCity] DataStore failed at startup, will retry per call: " .. tostring(lastErr))
		end
	end
	if self.mode == "datastore" and self._mss then
		local ok = pcall(function()
			self._mss:GetHashMap("EconCity_Probe" .. self._suffix)
		end)
		if ok then
			self.liveMode = "memorystore"
		end
	end
	return self
end

function Persistence:_retry(fn)
	local lastErr
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		if attempt < 3 then
			self._wait(attempt)
		end
	end
	self._log("[EconCity] Storage error: " .. tostring(lastErr))
	return false, lastErr
end

function Persistence:_store(name)
	local full = name .. self._suffix
	local store = self._stores[full]
	if not store then
		store = self._dss:GetDataStore(full)
		self._stores[full] = store
	end
	return store
end

function Persistence:_orderedStore(name)
	local full = name .. self._suffix
	local store = self._ordered[full]
	if not store then
		store = self._dss:GetOrderedDataStore(full)
		self._ordered[full] = store
	end
	return store
end

function Persistence:_map(name)
	local full = name .. self._suffix
	local map = self._maps[full]
	if not map then
		map = self._mss:GetHashMap(full)
		self._maps[full] = map
	end
	return map
end

-- DataStore thường

function Persistence:get(storeName, key)
	if self.mode == "memory" then
		local bucket = self._memory[storeName]
		return true, bucket and deepCopy(bucket[key]) or nil
	end
	return self:_retry(function()
		return (self:_store(storeName):GetAsync(key))
	end)
end

function Persistence:set(storeName, key, value)
	if self.mode == "memory" then
		self._memory[storeName] = self._memory[storeName] or {}
		self._memory[storeName][key] = deepCopy(value)
		return true
	end
	return self:_retry(function()
		self:_store(storeName):SetAsync(key, value)
	end)
end

-- transform(old) trả giá trị mới, nil = không ghi. Atomic giữa các server.
-- transform có thể chạy nhiều lần: biến ngoài nào nó ghi thì phải reset ở đầu transform
function Persistence:update(storeName, key, transform)
	if self.mode == "memory" then
		self._memory[storeName] = self._memory[storeName] or {}
		local newValue = transform(deepCopy(self._memory[storeName][key]))
		if newValue ~= nil then
			self._memory[storeName][key] = deepCopy(newValue)
		end
		return true, deepCopy(newValue)
	end
	return self:_retry(function()
		return (self:_store(storeName):UpdateAsync(key, function(old)
			return transform(old)
		end))
	end)
end

function Persistence:remove(storeName, key)
	if self.mode == "memory" then
		if self._memory[storeName] then
			self._memory[storeName][key] = nil
		end
		return true
	end
	return self:_retry(function()
		self:_store(storeName):RemoveAsync(key)
	end)
end

-- OrderedDataStore, chỉ lưu số nguyên

-- chỉ ghi nếu lớn hơn giá trị cũ. true = lệnh ok, kể cả khi không cần ghi
function Persistence:orderedSetMax(storeName, key, value)
	value = math.floor(value + 0.5)
	if self.mode == "memory" then
		self._memoryOrdered[storeName] = self._memoryOrdered[storeName] or {}
		local old = self._memoryOrdered[storeName][key]
		if old == nil or value > old then
			self._memoryOrdered[storeName][key] = value
		end
		return true
	end
	local ok = self:_retry(function()
		self:_orderedStore(storeName):UpdateAsync(key, function(old)
			if old == nil or value > old then
				return value
			end
			return nil
		end)
	end)
	return ok
end

function Persistence:orderedRemove(storeName, key)
	if self.mode == "memory" then
		if self._memoryOrdered[storeName] then
			self._memoryOrdered[storeName][key] = nil
		end
		return true
	end
	return self:_retry(function()
		self:_orderedStore(storeName):RemoveAsync(key)
	end)
end

-- mảng { key = string, value = number }, giảm dần
function Persistence:orderedTop(storeName, count)
	if self.mode == "memory" then
		local list = {}
		for k, v in pairs(self._memoryOrdered[storeName] or {}) do
			table.insert(list, { key = k, value = v })
		end
		table.sort(list, function(a, b)
			if a.value == b.value then
				return a.key < b.key
			end
			return a.value > b.value
		end)
		while #list > count do
			table.remove(list)
		end
		return true, list
	end
	return self:_retry(function()
		local pages = self:_orderedStore(storeName):GetSortedAsync(false, count)
		local out = {}
		for _, entry in ipairs(pages:GetCurrentPage()) do
			table.insert(out, { key = entry.key, value = entry.value })
		end
		return out
	end)
end

-- data "sống" đọc/ghi liên tục (MemoryStore HashMap)

function Persistence:liveSet(mapName, key, value, ttlSeconds)
	if self.liveMode == "memory" then
		self._memoryLive[mapName] = self._memoryLive[mapName] or {}
		self._memoryLive[mapName][key] = deepCopy(value)
		return true
	end
	local ok, err = pcall(function()
		self:_map(mapName):SetAsync(key, value, ttlSeconds or 3600)
	end)
	return ok, err
end

function Persistence:liveGet(mapName, key)
	if self.liveMode == "memory" then
		local bucket = self._memoryLive[mapName]
		return true, bucket and deepCopy(bucket[key]) or nil
	end
	local ok, result = pcall(function()
		return (self:_map(mapName):GetAsync(key))
	end)
	return ok, result
end

function Persistence:liveRemove(mapName, key)
	if self.liveMode == "memory" then
		if self._memoryLive[mapName] then
			self._memoryLive[mapName][key] = nil
		end
		return true
	end
	return pcall(function()
		self:_map(mapName):RemoveAsync(key)
	end)
end

return Persistence
