-- Roblox giả tối giản, chạy Main.server + Main.client ngoài Studio để bắt lỗi runtime (gọi nil, sai tên biến, sai luồng data).
-- không bắt được sai tên property Roblox, mock nhận hết

local M = {}
M.errors = {}
M.warnings = {}
M.now = 0

local function recordError(msg)
	table.insert(M.errors, msg)
	print("  !! " .. msg)
end

local function deepCopy(v, seen)
	if type(v) ~= "table" then
		return v
	end
	if rawget(v, "__class") then
		return v -- Instance: truyền nguyên tham chiếu
	end
	if getmetatable(v) and getmetatable(v).__datatype then
		return v
	end
	seen = seen or {}
	if seen[v] then
		error("bảng tuần hoàn không gửi qua Remote được")
	end
	seen[v] = true
	local out = {}
	for k, x in pairs(v) do
		if type(x) == "function" then
			error("không thể gửi function qua Remote (khoá " .. tostring(k) .. ")")
		end
		out[k] = deepCopy(x, seen)
	end
	seen[v] = nil
	return out
end
M.deepCopy = deepCopy

-- scheduler (task.*)
local queue = {}
local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		recordError(tostring(err) .. "\n" .. debug.traceback(co))
	end
end

local task = {}
function task.spawn(fn, ...)
	local co = type(fn) == "thread" and fn or coroutine.create(fn)
	resume(co, ...)
	return co
end
function task.defer(fn, ...)
	local co = coroutine.create(fn)
	table.insert(queue, { time = M.now, co = co, args = table.pack(...) })
	return co
end
function task.delay(t, fn, ...)
	local co = coroutine.create(fn)
	table.insert(queue, { time = M.now + (t or 0), co = co, args = table.pack(...) })
	return co
end
function task.wait(t)
	t = t or 0.03
	local co, isMain = coroutine.running()
	if isMain then
		error("task.wait gọi trên luồng chính")
	end
	table.insert(queue, { time = M.now + t, co = co, args = table.pack() })
	coroutine.yield()
	return t
end
M.task = task

local frameListeners = {}
function M.runFor(seconds)
	local target = M.now + seconds
	local nextFrame = M.now
	while true do
		table.sort(queue, function(a, b)
			return a.time < b.time
		end)
		local item = queue[1]
		local t = item and item.time or math.huge
		if nextFrame <= t and nextFrame <= target then
			M.now = nextFrame
			for _, fn in ipairs(frameListeners) do
				fn(0.1)
			end
			nextFrame = nextFrame + 0.1
		elseif item and item.time <= target then
			table.remove(queue, 1)
			M.now = math.max(M.now, item.time)
			if coroutine.status(item.co) == "suspended" then
				resume(item.co, table.unpack(item.args, 1, item.args.n))
			end
		else
			break
		end
	end
	M.now = target
end

-- datatype
local Vector3, Vector2, CFrame, Color3, UDim, UDim2 = {}, {}, {}, {}, {}, {}
local V3meta = { __datatype = "Vector3" }
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3meta)
end
V3meta.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return Vector3.new(v.X / m, v.Y / m, v.Z / m)
	end
	error("Vector3 không có trường " .. tostring(k))
end
V3meta.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3meta.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3meta.__mul = function(a, b)
	if type(a) == "number" then
		a, b = b, a
	end
	if type(b) == "number" then
		return Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3meta.__unm = function(a)
	return Vector3.new(-a.X, -a.Y, -a.Z)
end
V3meta.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end

local V2meta = { __datatype = "Vector2" }
function Vector2.new(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, V2meta)
end
V2meta.__index = function(_, k)
	error("Vector2 không có trường " .. tostring(k))
end

local CFmeta = { __datatype = "CFrame" }
function CFrame.new(x, y, z)
	if type(x) == "table" then
		return setmetatable({ Position = x }, CFmeta)
	end
	return setmetatable({ Position = Vector3.new(x or 0, y or 0, z or 0) }, CFmeta)
end
function CFrame.Angles()
	return setmetatable({ Position = Vector3.new(0, 0, 0) }, CFmeta)
end
function CFrame.lookAt(a)
	return setmetatable({ Position = a }, CFmeta)
end
CFmeta.__mul = function(a, b)
	if getmetatable(b) == CFmeta then
		return setmetatable({ Position = a.Position + b.Position }, CFmeta)
	end
	return a.Position + b
end
CFmeta.__index = function(_, k)
	error("CFrame không có trường " .. tostring(k))
end

local C3meta = { __datatype = "Color3" }
function Color3.new(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3meta)
end
function Color3.fromRGB(r, g, b)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
C3meta.__index = function(c, k)
	if k == "Lerp" then
		return function(self, other, t)
			return Color3.new(self.R + (other.R - self.R) * t, self.G + (other.G - self.G) * t, self.B + (other.B - self.B) * t)
		end
	end
	error("Color3 không có trường " .. tostring(k))
end

local UDmeta = { __datatype = "UDim" }
function UDim.new(s, o)
	return setmetatable({ Scale = s or 0, Offset = o or 0 }, UDmeta)
end
local UD2meta = { __datatype = "UDim2" }
function UDim2.new(xs, xo, ys, yo)
	return setmetatable({ X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }, UD2meta)
end
function UDim2.fromOffset(x, y)
	return UDim2.new(0, x, 0, y)
end
function UDim2.fromScale(x, y)
	return UDim2.new(x, 0, y, 0)
end
UD2meta.__add = function(a, b)
	return UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end

-- ColorSequence/NumberSequence (UIGradient, UIStroke...): chỉ cần giữ data
local ColorSequenceKeypoint = {
	new = function(t, c)
		return { Time = t, Value = c }
	end,
}
local ColorSequence = {
	new = function(a, b)
		if type(a) == "table" and a.Time == nil and b == nil and a.R == nil then
			for i = 2, #a do
				assert(a[i].Time > a[i - 1].Time, "ColorSequence: thời điểm phải tăng dần")
			end
			return { Keypoints = a }
		end
		return { Keypoints = { { Time = 0, Value = a }, { Time = 1, Value = b or a } } }
	end,
}
local NumberSequenceKeypoint = {
	new = function(t, v)
		return { Time = t, Value = v }
	end,
}
local NumberSequence = {
	new = function(a, b)
		if type(a) == "table" then
			return { Keypoints = a }
		end
		return { Keypoints = { { Time = 0, Value = a }, { Time = 1, Value = b or a } } }
	end,
}

local TweenInfo = {
	new = function(t)
		return { Time = t or 1 }
	end,
}
local RaycastParams = {
	new = function()
		return {}
	end,
}

-- Enum
local enumCache = {}
local Enum = setmetatable({}, {
	__index = function(_, enumType)
		enumCache[enumType] = enumCache[enumType] or setmetatable({}, {
			__index = function(t, name)
				local token = setmetatable({ Name = name, EnumType = enumType, Value = (#name * 7) % 100 + (name == "Camera" and 200 or 0) }, {
					__tostring = function()
						return "Enum." .. enumType .. "." .. name
					end,
				})
				rawset(t, name, token)
				return token
			end,
		})
		return enumCache[enumType]
	end,
})

-- Signal
local function newSignal()
	local s = { handlers = {} }
	function s:Connect(fn)
		local entry = { fn = fn, connected = true }
		table.insert(self.handlers, entry)
		return {
			Disconnect = function()
				entry.connected = false
			end,
			Connected = true,
		}
	end
	function s:Once(fn)
		local conn
		conn = self:Connect(function(...)
			conn.Disconnect()
			fn(...)
		end)
		return conn
	end
	function s:Fire(...)
		local list = {}
		for _, h in ipairs(self.handlers) do
			if h.connected then
				table.insert(list, h.fn)
			end
		end
		for _, fn in ipairs(list) do
			task.spawn(fn, ...)
		end
	end
	function s:Wait()
		error("Signal:Wait chưa hỗ trợ trong mock")
	end
	return s
end
M.newSignal = newSignal

-- Instance
local EVENTS = {
	MouseButton1Click = true, Activated = true, MouseEnter = true, MouseLeave = true, InputBegan = true,
	InputChanged = true, InputEnded = true, TouchPinch = true, Completed = true, OnClientEvent = true,
	OnServerEvent = true, PlayerAdded = true, PlayerRemoving = true, Heartbeat = true, RenderStepped = true,
	Changed = true, FocusLost = true, Focused = true, MouseButton1Down = true, MouseButton1Up = true, CharacterAdded = true, Stepped = true, TeleportInitFailed = true, LastInputTypeChanged = true,
}
local GUI_CLASSES = { Frame = true, TextLabel = true, TextButton = true, TextBox = true, ScrollingFrame = true, ImageLabel = true, ImageButton = true }
local PART_CLASSES = { Part = true, SpawnLocation = true, MeshPart = true, WedgePart = true }

local instMeta = {}
local methods = {}

local function isA(self, cls)
	local c = rawget(self, "__class")
	if cls == c or cls == "Instance" then
		return true
	end
	if cls == "GuiObject" then
		return GUI_CLASSES[c] == true
	end
	if cls == "GuiButton" then
		return c == "TextButton" or c == "ImageButton"
	end
	if cls == "BasePart" then
		return PART_CLASSES[c] == true
	end
	if cls == "LuaSourceContainer" or cls == "BaseScript" then
		return c == "Script" or c == "LocalScript" or c == "ModuleScript"
	end
	return false
end

local function newInstance(className, name)
	local self = setmetatable({
		__class = className,
		__props = { Name = name or className, ClassName = className },
		__children = {},
		__signals = {},
		__attrs = {},
	}, instMeta)
	return self
end
M.newInstance = newInstance

local function children(self)
	return rawget(self, "__children")
end

function methods.FindFirstChild(self, name)
	for _, c in ipairs(children(self)) do
		if c.Name == name then
			return c
		end
	end
	return nil
end
function methods.WaitForChild(self, name, timeout)
	local found = methods.FindFirstChild(self, name)
	local waited = 0
	while not found do
		local co, isMain = coroutine.running()
		if isMain then
			break
		end
		task.wait(0.05)
		waited = waited + 0.05
		found = methods.FindFirstChild(self, name)
		if waited > (timeout or 10) then
			break
		end
	end
	if not found and not timeout then
		error("WaitForChild: không thấy '" .. tostring(name) .. "' trong " .. tostring(self.Name))
	end
	return found
end
function methods.GetChildren(self)
	local out = {}
	for i, c in ipairs(children(self)) do
		out[i] = c
	end
	return out
end
function methods.GetDescendants(self)
	local out = {}
	local function walk(node)
		for _, c in ipairs(children(node)) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods.IsA(self, cls)
	return isA(self, cls)
end
function methods.FindFirstChildOfClass(self, cls)
	for _, c in ipairs(children(self)) do
		if rawget(c, "__class") == cls then
			return c
		end
	end
	return nil
end
function methods.FindFirstChildWhichIsA(self, cls)
	for _, c in ipairs(children(self)) do
		if isA(c, cls) then
			return c
		end
	end
	return nil
end
function methods.FindFirstAncestorWhichIsA(self, cls)
	local p = self.Parent
	while p do
		if isA(p, cls) then
			return p
		end
		p = p.Parent
	end
	return nil
end
function methods.Destroy(self)
	self.Parent = nil
	rawset(self, "__destroyed", true)
	for _, c in ipairs(methods.GetChildren(self)) do
		methods.Destroy(c)
	end
end
function methods.ClearAllChildren(self)
	for _, c in ipairs(methods.GetChildren(self)) do
		methods.Destroy(c)
	end
end
function methods.SetAttribute(self, k, v)
	rawget(self, "__attrs")[k] = v
end
function methods.GetAttribute(self, k)
	return rawget(self, "__attrs")[k]
end
function methods.GetPropertyChangedSignal(self, prop)
	local signals = rawget(self, "__signals")
	signals["prop:" .. prop] = signals["prop:" .. prop] or newSignal()
	return signals["prop:" .. prop]
end
function methods.GetFullName(self)
	local names = {}
	local node = self
	while node do
		table.insert(names, 1, node.Name)
		node = node.Parent
	end
	return table.concat(names, ".")
end

-- method riêng theo class, __index tra theo __class
local classMethods = {}
classMethods.RemoteEvent = {
	FireClient = function(self, player, ...)
		if player ~= M.localPlayer then
			return -- chỉ giả máy của localPlayer
		end
		local args = table.pack(...)
		for i = 1, args.n do
			args[i] = deepCopy(args[i])
		end
		self.OnClientEvent:Fire(table.unpack(args, 1, args.n))
	end,
	FireAllClients = function(self, ...)
		self.OnClientEvent:Fire(...)
	end,
	FireServer = function(self, ...)
		self.OnServerEvent:Fire(M.localPlayer, ...)
	end,
}
classMethods.RemoteFunction = {
	InvokeServer = function(self, ...)
		local handler = rawget(self, "__props").OnServerInvoke
		if not handler then
			error("RemoteFunction chưa có OnServerInvoke")
		end
		local args = table.pack(...)
		for i = 1, args.n do
			args[i] = deepCopy(args[i])
		end
		return deepCopy(handler(M.localPlayer, table.unpack(args, 1, args.n)))
	end,
}
classMethods.Camera = {
	ScreenPointToRay = function(_, x, y)
		return { Origin = Vector3.new(150, 150, 150), Direction = Vector3.new(-1, -1, -1).Unit }
	end,
	ViewportPointToRay = function(_, x, y)
		return { Origin = Vector3.new(150, 150, 150), Direction = Vector3.new(-1, -1, -1).Unit }
	end,
}
classMethods.Player = {
	GetRankInGroup = function()
		return 0
	end,
}

instMeta.__index = function(self, key)
	local props = rawget(self, "__props")
	local v = props[key]
	if v ~= nil then
		return v
	end
	local cm = classMethods[rawget(self, "__class")]
	if cm and cm[key] then
		return cm[key]
	end
	if methods[key] then
		return methods[key]
	end
	if EVENTS[key] then
		local signals = rawget(self, "__signals")
		signals[key] = signals[key] or newSignal()
		return signals[key]
	end
	for _, c in ipairs(rawget(self, "__children")) do
		if c.Name == key then
			return c
		end
	end
	-- giá trị mặc định khi chưa gán
	if key == "Active" then
		return rawget(self, "__class") == "TextButton" or rawget(self, "__class") == "TextBox"
	elseif key == "Visible" or key == "Enabled" then
		return true
	elseif key == "AbsoluteSize" then
		if rawget(self, "__class") == "ScreenGui" then
			return Vector2.new(1366, 732) -- màn hình laptop, đã trừ thanh công cụ Roblox
		end
		return Vector2.new(300, 20)
	elseif key == "AbsolutePosition" then
		return Vector2.new(100, 100)
	elseif key == "ViewportSize" then
		return Vector2.new(1366, 768)
	elseif key == "Text" then
		return ""
	elseif key == "Transparency" or key == "BackgroundTransparency" or key == "TextTransparency" then
		return 0
	elseif key == "Size" and PART_CLASSES[rawget(self, "__class")] then
		return Vector3.new(4, 1, 2)
	elseif key == "Position" and PART_CLASSES[rawget(self, "__class")] then
		return Vector3.new(0, 0, 0)
	elseif key == "Shape" then
		return Enum.PartType.Block
	end
	return nil
end

instMeta.__newindex = function(self, key, value)
	local props = rawget(self, "__props")
	if key == "Parent" then
		local old = props.Parent
		if old then
			local list = rawget(old, "__children")
			for i = #list, 1, -1 do
				if list[i] == self then
					table.remove(list, i)
				end
			end
		end
		props.Parent = value
		if value then
			if rawget(value, "__destroyed") then
				error("gán Parent vào Instance đã bị Destroy")
			end
			table.insert(rawget(value, "__children"), self)
		end
		return
	end
	if PART_CLASSES[rawget(self, "__class")] then
		if key == "CFrame" then
			props.Position = value.Position
		elseif key == "Position" then
			props.CFrame = CFrame.new(value)
		end
	end
	if key == "Shape" or key == "Material" or key == "Font" then
		if type(value) ~= "table" or not value.EnumType then
			error("Gán " .. key .. " phải là Enum, nhận " .. tostring(value))
		end
	end
	-- Roblox thật không cho script ghi property này (cần quyền Plugin)
	if key == "FallenPartsDestroyHeight" then
		error("The current thread cannot set 'FallenPartsDestroyHeight' (lacking capability Plugin)")
	end
	props[key] = value
	local signals = rawget(self, "__signals")
	if signals["prop:" .. key] then
		signals["prop:" .. key]:Fire()
	end
end
instMeta.__tostring = function(self)
	return rawget(self, "__props").Name
end

local Instance = {
	new = function(className, parent)
		local inst = newInstance(className)
		if parent then
			inst.Parent = parent
		end
		return inst
	end,
}

-- nạp script
local moduleCache = {}
local makeEnv

local function requireInstance(inst)
	if type(inst) ~= "table" or not rawget(inst, "__class") then
		error("require() cần ModuleScript, nhận " .. tostring(inst))
	end
	if rawget(inst, "__class") ~= "ModuleScript" then
		error("require() cần ModuleScript, nhận " .. rawget(inst, "__class"))
	end
	if moduleCache[inst] ~= nil then
		return moduleCache[inst]
	end
	local file = rawget(inst, "__file")
	local chunk = assert(loadfile(file, "t", makeEnv(inst)))
	local result = chunk()
	if result == nil then
		error("ModuleScript " .. file .. " không trả về giá trị")
	end
	moduleCache[inst] = result
	return result
end

local luauMath = setmetatable({
	clamp = function(x, lo, hi)
		if lo > hi then
			error("math.clamp: min > max")
		end
		return math.max(lo, math.min(hi, x))
	end,
	round = function(x)
		if x >= 0 then
			return math.floor(x + 0.5)
		end
		return -math.floor(-x + 0.5)
	end,
	sign = function(x)
		return x > 0 and 1 or (x < 0 and -1 or 0)
	end,
}, { __index = math })

makeEnv = function(scriptInst)
	local env = {
		script = scriptInst,
		game = M.game,
		workspace = M.workspace,
		Instance = Instance,
		Enum = Enum,
		Vector3 = Vector3,
		Vector2 = Vector2,
		CFrame = CFrame,
		Color3 = Color3,
		UDim = UDim,
		UDim2 = UDim2,
		TweenInfo = TweenInfo,
		RaycastParams = RaycastParams,
		ColorSequence = ColorSequence,
		ColorSequenceKeypoint = ColorSequenceKeypoint,
		NumberSequence = NumberSequence,
		NumberSequenceKeypoint = NumberSequenceKeypoint,
		task = task,
		require = requireInstance,
		math = luauMath,
		warn = function(...)
			local parts = {}
			for i, v in ipairs({ ... }) do
				parts[i] = tostring(v)
			end
			local msg = table.concat(parts, " ")
			table.insert(M.warnings, msg)
			print("  [warn] " .. msg)
		end,
		print = function(...)
			print("  [print]", ...)
		end,
		typeof = function(v)
			if type(v) == "table" and rawget(v, "__class") then
				return "Instance"
			end
			return type(v)
		end,
		os = { time = function() return 1790000000 + math.floor(M.now) end, clock = function() return M.now end },
	}
	return setmetatable(env, { __index = _G })
end

local function buildTree(dir, parent)
	-- ls -1p thêm "/" sau tên thư mục, chạy được cả macOS lẫn Linux
	local p = io.popen('ls -1p "' .. dir .. '"')
	for entry in p:lines() do
		if entry:sub(-1) == "/" then
			local name = entry:sub(1, -2)
			local folder = newInstance("Folder", name)
			folder.Parent = parent
			buildTree(dir .. "/" .. name, folder)
		elseif entry:match("%.luau$") then
			local full = dir .. "/" .. entry
			local cls, name = "ModuleScript", entry:gsub("%.luau$", "")
			if entry:match("%.server%.luau$") then
				cls, name = "Script", entry:gsub("%.server%.luau$", "")
			elseif entry:match("%.client%.luau$") then
				cls, name = "LocalScript", entry:gsub("%.client%.luau$", "")
			end
			local inst = newInstance(cls, name)
			rawset(inst, "__file", full)
			inst.Parent = parent
		end
	end
	p:close()
end

M.require = function(inst)
	return requireInstance(inst)
end

function M.runScript(inst)
	local chunk = assert(loadfile(rawget(inst, "__file"), "t", makeEnv(inst)))
	task.spawn(chunk)
end

-- dựng game
function M.boot(root)
	local game = newInstance("DataModel", "Game")
	M.game = game
	local services = {}
	local function service(name)
		local s = services[name]
		if not s then
			s = newInstance(name, name)
			s.Parent = game
			services[name] = s
		end
		return s
	end
	rawget(game, "__props").GetService = function(_, name)
		return service(name)
	end
	rawget(game, "__props").BindToClose = function(_, fn)
		M.bindToClose = fn
	end
	rawget(game, "__props").PlaceId = 12345
	rawget(game, "__props").CreatorId = 1
	rawget(game, "__props").CreatorType = Enum.CreatorType.User
	rawget(game, "__props").JobId = "" -- Studio
	rawget(game, "__props").PrivateServerId = ""
	rawget(game, "__props").PrivateServerOwnerId = 0

	local ws = service("Workspace")
	M.workspace = ws
	local camera = newInstance("Camera", "Camera")
	camera.Parent = ws
	rawget(ws, "__props").CurrentCamera = camera
	rawget(ws, "__props").GetServerTimeNow = function()
		return 1790000000 + M.now
	end
	-- raycast luôn trúng M.clickPoint (điểm trên mặt lưới, test đặt trước khi bấm)
	rawget(ws, "__props").Raycast = function(_, origin, direction, params)
		M.lastRaycast = params
		local folder = params.FilterDescendantsInstances and params.FilterDescendantsInstances[1]
		if not folder or not M.clickPoint then
			return nil
		end
		return { Instance = folder:FindFirstChild("Grid") or folder, Position = M.clickPoint }
	end

	local players = service("Players")
	rawget(players, "__props").GetPlayers = function(self)
		local out = {}
		for _, c in ipairs(children(self)) do
			if rawget(c, "__class") == "Player" then
				table.insert(out, c)
			end
		end
		return out
	end
	rawget(players, "__props").GetPlayerByUserId = function(self, id)
		for _, c in ipairs(children(self)) do
			if rawget(c, "__class") == "Player" and c.UserId == id then
				return c
			end
		end
		return nil
	end
	rawget(players, "__props").GetNameFromUserIdAsync = function(_, id)
		return "User" .. tostring(id)
	end
	M.nameToId = { cogiao_lan = 555 }
	rawget(players, "__props").GetUserIdFromNameAsync = function(_, name)
		local id = M.nameToId[name]
		if not id then
			error("Players:GetUserIdFromNameAsync() failed because HTTP 400 (Bad Request)")
		end
		return id
	end
	M.bans = {}
	rawget(players, "__props").BanAsync = function(_, config)
		for _, id in ipairs(config.UserIds) do
			M.bans[id] = config
		end
	end
	rawget(players, "__props").UnbanAsync = function(_, config)
		for _, id in ipairs(config.UserIds) do
			M.bans[id] = nil
		end
	end

	local runService = service("RunService")
	rawget(runService, "__props").IsStudio = function()
		return true
	end
	rawget(runService, "__props").IsServer = function()
		return true
	end
	rawget(runService, "__props").IsClient = function()
		return true
	end
	M.renderSteps = {}
	rawget(runService, "__props").BindToRenderStep = function(_, name, priority, fn)
		if type(priority) ~= "number" then
			error("BindToRenderStep: priority phải là số")
		end
		M.renderSteps[name] = fn
	end
	table.insert(frameListeners, function(dt)
		runService.Heartbeat:Fire(dt)
		runService.RenderStepped:Fire(dt)
		for _, fn in pairs(M.renderSteps) do
			task.spawn(fn, dt)
		end
	end)

	local dss = service("DataStoreService")
	rawget(dss, "__props").GetDataStore = function()
		error("You must publish this place to the web to access DataStore.")
	end
	rawget(dss, "__props").GetOrderedDataStore = rawget(dss, "__props").GetDataStore
	local mss = service("MemoryStoreService")
	rawget(mss, "__props").GetHashMap = function()
		error("MemoryStore không khả dụng")
	end
	local ms = service("MessagingService")
	rawget(ms, "__props").SubscribeAsync = function()
		error("MessagingService không khả dụng trong Studio")
	end
	rawget(ms, "__props").PublishAsync = rawget(ms, "__props").SubscribeAsync
	local tp = service("TeleportService")
	rawget(tp, "__props").ReserveServer = function()
		error("ReserveServer không chạy trong Studio")
	end
	rawget(tp, "__props").ReserveServerAsync = function()
		error("ReserveServerAsync không chạy trong Studio")
	end
	rawget(tp, "__props").TeleportAsync = function()
		error("Teleport không chạy trong Studio")
	end

	local tween = service("TweenService")
	rawget(tween, "__props").Create = function(_, inst, info, props)
		if type(info) ~= "table" or not info.Time then
			error("TweenService:Create cần TweenInfo")
		end
		local t = { Completed = newSignal() }
		function t:Play()
			for k, v in pairs(props) do
				inst[k] = v
			end
			self.Completed:Fire(Enum.PlaybackState.Completed)
		end
		function t:Cancel() end
		function t:Pause() end
		return t
	end

	local uis = service("UserInputService")
	rawget(uis, "__props").TouchEnabled = false
	rawget(uis, "__props").MouseEnabled = true
	rawget(uis, "__props").GetMouseLocation = function()
		return Vector2.new(500, 300)
	end
	rawget(uis, "__props").IsMouseButtonPressed = function()
		return M.mouseDown == true
	end

	local sg = service("StarterGui")
	rawget(sg, "__props").SetCoreGuiEnabled = function() end
	rawget(sg, "__props").SetCore = function() end

	service("Lighting")
	service("ReplicatedStorage")
	service("ServerScriptService")
	local sp = service("StarterPlayer")
	local sps = newInstance("StarterPlayerScripts", "StarterPlayerScripts")
	sps.Parent = sp

	-- source trong src/
	local shared = newInstance("Folder", "EconCity")
	buildTree(root .. "/src/shared", shared)
	shared.Parent = service("ReplicatedStorage")
	local server = newInstance("Folder", "EconCityServer")
	buildTree(root .. "/src/server", server)
	server.Parent = service("ServerScriptService")
	local client = newInstance("Folder", "EconCityClient")
	buildTree(root .. "/src/client", client)
	client.Parent = sps
	M.serverFolder = server
	M.clientFolder = client
	return game
end

function M.addPlayer(userId, name)
	local players = M.game:GetService("Players")
	local player = newInstance("Player", name)
	rawget(player, "__props").UserId = userId
	rawget(player, "__props").DisplayName = name
	local pg = newInstance("PlayerGui", "PlayerGui")
	pg.Parent = player
	player.Parent = players
	M.localPlayer = M.localPlayer or player
	rawget(players, "__props").LocalPlayer = M.localPlayer
	players.PlayerAdded:Fire(player)
	return player
end

function M.removePlayer(player)
	local players = M.game:GetService("Players")
	players.PlayerRemoving:Fire(player)
	player.Parent = nil
end

M.Enum = Enum
M.Vector3 = Vector3
M.Vector2 = Vector2

return M
