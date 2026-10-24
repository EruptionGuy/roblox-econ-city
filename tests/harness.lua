-- Nạp module cho test chạy ngoài Roblox (texlua, Lua 5.3).
-- giả script.Parent.X, :WaitForChild("X") và require(...) để ModuleScript trong src/ chạy nguyên văn

local H = {}

local ROOT = (os.getenv("ECONCITY_ROOT") or ".")
H.ROOT = ROOT

local loaded = {}
local nodeMeta

local function dirname(path)
	return (path:match("^(.*)/[^/]+$")) or "."
end

local function node(path)
	return setmetatable({ __path = path }, nodeMeta)
end

nodeMeta = {
	__index = function(self, key)
		if key == "Parent" then
			return node(dirname(rawget(self, "__path")))
		elseif key == "WaitForChild" or key == "FindFirstChild" then
			return function(this, name)
				return node(rawget(this, "__path") .. "/" .. name)
			end
		elseif key == "Name" then
			return (rawget(self, "__path"):match("([^/]+)$"))
		end
		return node(rawget(self, "__path") .. "/" .. key)
	end,
	__tostring = function(self)
		return "Node(" .. rawget(self, "__path") .. ")"
	end,
}

H.node = node

local function fileExists(p)
	local f = io.open(p, "r")
	if f then
		f:close()
		return true
	end
	return false
end

-- file nguồn của node: X.luau, X/init.luau hoặc X.lua
local function resolve(path)
	for _, candidate in ipairs({ path .. ".luau", path .. "/init.luau", path .. ".lua" }) do
		if fileExists(candidate) then
			return candidate
		end
	end
	return nil
end

H.extraGlobals = {}

function H.loadFile(file, modulePath)
	local env = setmetatable({}, { __index = function(_, k)
		local v = H.extraGlobals[k]
		if v ~= nil then
			return v
		end
		return _G[k]
	end })
	env.script = node(modulePath)
	env.require = function(ref)
		if type(ref) == "table" and rawget(ref, "__path") then
			return H.require(rawget(ref, "__path"))
		end
		if type(ref) == "table" and ref.__mockPath then
			return H.require(ref.__mockPath)
		end
		error("require() nhận đối tượng không hợp lệ: " .. tostring(ref))
	end
	local chunk, err = loadfile(file, "t", env)
	if not chunk then
		error(err)
	end
	return chunk()
end

function H.require(modulePath)
	if loaded[modulePath] ~= nil then
		return loaded[modulePath]
	end
	local file = resolve(modulePath)
	if not file then
		error("Không tìm thấy module: " .. modulePath)
	end
	local result = H.loadFile(file, modulePath)
	loaded[modulePath] = result
	return result
end

function H.reset()
	loaded = {}
end

-- mini test framework
local passed, failed = 0, 0
local failures = {}

function H.test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
		print("  ✓ " .. name)
	else
		failed = failed + 1
		table.insert(failures, name .. ": " .. tostring(err))
		print("  ✗ " .. name .. "\n      " .. tostring(err))
	end
end

function H.eq(actual, expected, msg)
	if actual ~= expected then
		error((msg or "") .. " mong đợi " .. tostring(expected) .. " nhưng nhận " .. tostring(actual), 2)
	end
end

function H.near(actual, expected, tol, msg)
	tol = tol or 1e-6
	if math.abs(actual - expected) > tol then
		error((msg or "") .. " mong đợi ~" .. tostring(expected) .. " nhưng nhận " .. tostring(actual), 2)
	end
end

function H.truthy(v, msg)
	if not v then
		error(msg or "mong đợi giá trị đúng", 2)
	end
end

function H.summary()
	print(string.format("\n%d passed, %d failed", passed, failed))
	return failed == 0
end

return H
