-- Phố nền quanh khu đất + spawn. Thành phố 12x12 thì client tự dựng (mỗi người thấy thành phố của mình).
-- nhà thấp ở phía camera toàn cảnh (+X, +Z) và sát khu đất để không che, không đổ bóng lên lưới. Càng về -X, -Z càng cao
-- LCG seed cố định nên server nào cũng giống nhau. Nước dùng Terrain, ngoài Roblox (test) thì tấm kính xanh

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("EconCity")
local Config = require(Shared:WaitForChild("Config"))
local CityLayout = require(Shared:WaitForChild("CityLayout"))

local World = {}

local rgb = Color3.fromRGB
local M = Enum.Material

local ASPHALT = rgb(74, 77, 83) -- cùng màu đường đã nối trong thành phố
local CURB = rgb(214, 216, 212)
local MARK = rgb(242, 241, 234)
local GLASS = { rgb(104, 156, 204), rgb(84, 132, 176), rgb(140, 184, 214), rgb(112, 170, 186), rgb(160, 178, 198), rgb(70, 100, 140) }
local WALLS = { rgb(238, 234, 226), rgb(216, 208, 196), rgb(198, 202, 208), rgb(228, 216, 198), rgb(186, 146, 124), rgb(246, 244, 238), rgb(170, 176, 186) }
local RIBBONS = { rgb(84, 124, 168), rgb(64, 86, 112), rgb(112, 154, 182), rgb(96, 140, 150) }
local ACCENTS = { rgb(214, 64, 58), rgb(46, 107, 255), rgb(242, 184, 40), rgb(46, 158, 98), rgb(124, 92, 220) }
local LEAVES = { rgb(86, 160, 72), rgb(104, 176, 82), rgb(70, 138, 66), rgb(122, 182, 90) }
local CARS = { rgb(236, 236, 236), rgb(30, 32, 38), rgb(196, 40, 40), rgb(46, 107, 255), rgb(150, 154, 160), rgb(242, 184, 40), rgb(60, 70, 90) }

local function part(props, className)
	local p = Instance.new(className or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

-- trụ đứng: trục Cylinder của Roblox theo X nên xoay 90 độ
local function disc(props, x, y, z, height, diameter)
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.pi / 2)
	return part(props)
end

local seed = 20261022
local function rand()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local function pick(list)
	return list[math.floor(rand() * #list) + 1]
end

-- Lưới phố
local HALF = CityLayout.HALF_EXTENT -- 84: nửa cạnh khu đất của người chơi
local GATE_X = CityLayout.cellCenter(Config.GATE_INDEX)
local ROAD = 16 -- bề rộng mặt đường
local PITCH = 76 -- khoảng cách hai tim đường (khối phố 60 + đường 16)
local RING = HALF + 12 -- 96: tim đường vành đai (mép đường sát vỉa hè quanh khu đất)
local LINES = {} -- tim đường theo một trục: ±96, ±172, ±248, ±324, ±400, ±476, ±552
for k = 0, 6 do
	table.insert(LINES, -(RING + k * PITCH))
	table.insert(LINES, RING + k * PITCH)
end
table.sort(LINES)
local BANDS = {} -- dải đất giữa 2 tim đường liền nhau, rộng 60. Dải giữa rộng 176 là khu đất
for k = 1, #LINES - 1 do
	BANDS[k] = { LINES[k] + ROAD / 2, LINES[k + 1] - ROAD / 2 }
end
local LIMIT = RING + 5 * PITCH + ROAD / 2 -- 484: tường vô hình ở mép ngoài đường ±476
local AVENUE = { GATE_X - 10, GATE_X + 10 } -- đại lộ từ cổng thành phố chạy về phía +Z

-- sông chạy theo X, giữa 2 đường ven sông z = -324 và z = -248
local RIVER = { z0 = -(RING + 3 * PITCH) + ROAD / 2, z1 = -(RING + 2 * PITCH) - ROAD / 2 } -- -316 .. -256
local BRIDGES = {}
for _, k in ipairs({ 0, 2, 4 }) do
	BRIDGES[RING + k * PITCH] = true
	BRIDGES[-(RING + k * PITCH)] = true
end
local LANDMARK = { x = -(RING + PITCH + PITCH / 2), z = -(RING + PITCH + PITCH / 2) } -- (-210, -210)
local GROUND = 2048

local function onRiver(z)
	return z > RIVER.z0 - 0.5 and z < RIVER.z1 + 0.5
end

-- Đồ đường phố
local function tree(parent, x, z, s, y0)
	y0 = y0 or 0.4
	local m = Instance.new("Model")
	m.Name = "StreetTree"
	disc({ Name = "Trunk", Material = M.Wood, Color = rgb(112, 84, 60), Parent = m }, x, y0 + 1.6 * s, z, 3.2 * s, 0.7 * s)
	part({ Name = "Crown", Shape = Enum.PartType.Ball, Size = Vector3.new(4.4 * s, 4.4 * s, 4.4 * s), Position = Vector3.new(x, y0 + 4.4 * s, z), Material = M.Grass, Color = pick(LEAVES), CanCollide = false, Parent = m })
	part({ Name = "Top", Shape = Enum.PartType.Ball, Size = Vector3.new(3 * s, 3 * s, 3 * s), Position = Vector3.new(x + 0.5 * s, y0 + 6 * s, z - 0.3 * s), Material = M.Grass, Color = pick(LEAVES), CanCollide = false, CastShadow = false, Parent = m })
	m.Parent = parent
end

local function lamp(parent, x, z, y0)
	y0 = y0 or 0.4
	disc({ Name = "LampPole", Material = M.Metal, Color = rgb(64, 68, 76), CastShadow = false, Parent = parent }, x, y0 + 3.2, z, 6.4, 0.32)
	part({ Name = "LampHead", Size = Vector3.new(1.3, 0.35, 1.3), Position = Vector3.new(x, y0 + 6.5, z), Material = M.Neon, Color = rgb(255, 244, 214), CastShadow = false, Parent = parent })
end

local function car(parent, x, z, alongX)
	local function size(l, h, w)
		return alongX and Vector3.new(l, h, w) or Vector3.new(w, h, l)
	end
	local m = Instance.new("Model")
	m.Name = "Car"
	part({ Name = "Wheels", Size = size(3.6, 0.8, 2.3), Position = Vector3.new(x, 0.4, z), Material = M.SmoothPlastic, Color = rgb(30, 30, 34), Parent = m })
	part({ Name = "Body", Size = size(4.6, 1.1, 2.2), Position = Vector3.new(x, 1.15, z), Material = M.SmoothPlastic, Color = pick(CARS), Parent = m })
	part({ Name = "Cabin", Size = size(2.6, 0.9, 2), Position = Vector3.new(x, 2.15, z), Material = M.Glass, Color = rgb(44, 54, 70), Reflectance = 0.3, Parent = m })
	m.Parent = parent
end

-- cây/đèn xen kẽ dọc 4 mép vỉa hè của khối phố
local function dressEdges(parent, x0, x1, z0, z1)
	local inset = 1.8
	local edges = {
		{ x0 + inset, z0 + inset, x1 - inset, z0 + inset },
		{ x0 + inset, z1 - inset, x1 - inset, z1 - inset },
		{ x0 + inset, z0 + inset, x0 + inset, z1 - inset },
		{ x1 - inset, z0 + inset, x1 - inset, z1 - inset },
	}
	for e, edge in ipairs(edges) do
		local ax, az, bx, bz = edge[1], edge[2], edge[3], edge[4]
		local len = math.max(math.abs(bx - ax), math.abs(bz - az))
		local n = math.max(2, math.floor(len / 11))
		for k = 1, n - 1 do
			local t = k / n
			local px, pz = ax + (bx - ax) * t, az + (bz - az) * t
			if (k + e) % 2 == 0 then
				lamp(parent, px, pz)
			else
				tree(parent, px, pz, 0.75 + rand() * 0.2)
			end
		end
	end
end

-- Công trình
local function roofTop(m, x, z, w, d, h)
	local r = rand()
	if r < 0.45 then
		part({ Name = "AC", Size = Vector3.new(math.min(5, w * 0.3), 1.8, math.min(4, d * 0.25)), Position = Vector3.new(x - w * 0.2, h + 0.9, z - d * 0.2), Material = M.Metal, Color = rgb(196, 200, 206), Parent = m })
	elseif r < 0.7 then
		disc({ Name = "Tank", Material = M.Metal, Color = rgb(170, 176, 186), Parent = m }, x + w * 0.2, h + 1.6, z - d * 0.2, 3.2, math.min(4, w * 0.3))
	end
end

-- tháp kính: khối đế + thân kính có dải viền, đỉnh là helipad hoặc ăng-ten
local function tower(parent, x, z, w, d, h, detail)
	local m = Instance.new("Model")
	m.Name = "Tower"
	local podium = 8 + math.floor(rand() * 3) * 2
	local wall = pick(WALLS)
	part({ Name = "Podium", Size = Vector3.new(w, podium, d), Position = Vector3.new(x, podium / 2, z), Material = M.Concrete, Color = wall, Parent = m })
	part({ Name = "Storefront", Size = Vector3.new(w + 0.3, podium - 4, d + 0.3), Position = Vector3.new(x, podium / 2 - 0.5, z), Material = M.Glass, Color = rgb(130, 178, 214), Reflectance = 0.2, Parent = m })
	local tw, td = w * 0.76, d * 0.76
	local body = h - podium
	local glass = pick(GLASS)
	part({ Name = "Body", Size = Vector3.new(tw, body, td), Position = Vector3.new(x, podium + body / 2, z), Material = M.Glass, Color = glass, Reflectance = 0.22, Parent = m })
	local step = detail and (h > 110 and 10 or 7) or 14
	for y = podium + step, h - 3, step do
		part({ Name = "Band", Size = Vector3.new(tw + 0.3, detail and 0.7 or 1.2, td + 0.3), Position = Vector3.new(x, y, z), Material = M.SmoothPlastic, Color = rgb(236, 240, 245), CastShadow = false, Parent = m })
	end
	-- cột góc suốt thân, đặt ở góc camera nhìn thấy
	if detail then
		part({ Name = "Fin", Size = Vector3.new(0.8, body, 0.8), Position = Vector3.new(x + tw / 2, podium + body / 2, z + td / 2), Material = M.SmoothPlastic, Color = rgb(236, 240, 245), CastShadow = false, Parent = m })
	end
	part({ Name = "Crown", Size = Vector3.new(tw + 0.6, 2, td + 0.6), Position = Vector3.new(x, h + 1, z), Material = M.SmoothPlastic, Color = glass:Lerp(rgb(255, 255, 255), 0.55), Parent = m })
	if h > 120 and rand() < 0.5 then
		disc({ Name = "Antenna", Material = M.Metal, Color = rgb(220, 222, 226), CastShadow = false, Parent = m }, x, h + 14, z, 24, 0.8)
		part({ Name = "Beacon", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), Position = Vector3.new(x, h + 26.5, z), Material = M.Neon, Color = rgb(255, 72, 72), CastShadow = false, Parent = m })
	elseif h > 80 and math.min(tw, td) > 16 then
		disc({ Name = "HelipadRing", Material = M.SmoothPlastic, Color = rgb(242, 184, 40), Parent = m }, x, h + 2.1, z, 0.2, math.min(tw, td) * 0.8)
		disc({ Name = "Helipad", Material = M.Concrete, Color = rgb(70, 74, 82), Parent = m }, x, h + 2.2, z, 0.2, math.min(tw, td) * 0.8 - 1.2)
	else
		roofTop(m, x, z, tw, td, h + 2)
	end
	m.Parent = parent
end

local function midrise(parent, x, z, w, d, h, detail)
	local m = Instance.new("Model")
	m.Name = "Building"
	local wall = pick(WALLS)
	local ribbon = pick(RIBBONS)
	part({ Name = "Body", Size = Vector3.new(w, h, d), Position = Vector3.new(x, h / 2, z), Material = M.Concrete, Color = wall, Parent = m })
	local step = detail and 3.6 or 7.2
	for y = 2.8, h - 2.4, step do
		part({ Name = "Windows", Size = Vector3.new(w + 0.3, detail and 1.9 or 3.6, d + 0.3), Position = Vector3.new(x, y, z), Material = M.Glass, Color = ribbon, Reflectance = 0.15, CastShadow = false, Parent = m })
	end
	part({ Name = "Roof", Size = Vector3.new(w + 0.6, 0.8, d + 0.6), Position = Vector3.new(x, h + 0.4, z), Material = M.SmoothPlastic, Color = wall:Lerp(rgb(40, 40, 40), 0.25), Parent = m })
	if detail then
		roofTop(m, x, z, w, d, h + 0.8)
	end
	m.Parent = parent
end

local function shops(parent, x, z, w, d, h)
	local m = Instance.new("Model")
	m.Name = "Shops"
	local accent = pick(ACCENTS)
	part({ Name = "Body", Size = Vector3.new(w, h, d), Position = Vector3.new(x, h / 2, z), Material = M.Plaster, Color = pick(WALLS), Parent = m })
	part({ Name = "Storefront", Size = Vector3.new(w + 0.3, 3.2, d + 0.3), Position = Vector3.new(x, 2.2, z), Material = M.Glass, Color = rgb(150, 196, 230), Reflectance = 0.25, CastShadow = false, Parent = m })
	part({ Name = "Awning", Size = Vector3.new(w + 1.8, 0.4, d + 1.8), Position = Vector3.new(x, 4.3, z), Material = M.SmoothPlastic, Color = accent, Parent = m })
	part({ Name = "Sign", Size = Vector3.new(w + 0.4, 1.2, d + 0.4), Position = Vector3.new(x, h - 1.2, z), Material = M.SmoothPlastic, Color = accent:Lerp(rgb(255, 255, 255), 0.75), CastShadow = false, Parent = m })
	part({ Name = "Roof", Size = Vector3.new(w + 0.6, 0.6, d + 0.6), Position = Vector3.new(x, h + 0.3, z), Material = M.SmoothPlastic, Color = rgb(120, 124, 132), Parent = m })
	m.Parent = parent
end

-- tháp biểu tượng: 3 tầng nhỏ dần + chóp
local function landmark(parent, x, z)
	local m = Instance.new("Model")
	m.Name = "Landmark"
	part({ Name = "Plaza", Size = Vector3.new(54, 0.3, 54), Position = Vector3.new(x, 0.55, z), Material = M.Granite, Color = rgb(226, 224, 218), Parent = m })
	local tiers = { { 36, 110 }, { 28, 70 }, { 20, 50 } }
	local y = 0.7
	for i, t in ipairs(tiers) do
		local s, h = t[1], t[2]
		part({ Name = "Tier" .. i, Size = Vector3.new(s, h, s), Position = Vector3.new(x, y + h / 2, z), Material = M.Glass, Color = rgb(96, 146, 196), Reflectance = 0.25, Parent = m })
		for yy = y + 8, y + h - 2, 8 do
			part({ Name = "Band", Size = Vector3.new(s + 0.3, 0.6, s + 0.3), Position = Vector3.new(x, yy, z), Material = M.SmoothPlastic, Color = rgb(238, 242, 248), CastShadow = false, Parent = m })
		end
		part({ Name = "Ledge", Size = Vector3.new(s + 1.2, 1.2, s + 1.2), Position = Vector3.new(x, y + h + 0.6, z), Material = M.SmoothPlastic, Color = rgb(230, 234, 240), Parent = m })
		y = y + h + 1.2
	end
	disc({ Name = "Spire", Material = M.Metal, Color = rgb(226, 230, 236), Parent = m }, x, y + 20, z, 40, 2)
	part({ Name = "Beacon", Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.6, 2.6), Position = Vector3.new(x, y + 41, z), Material = M.Neon, Color = rgb(255, 72, 72), CastShadow = false, Parent = m })
	m.Parent = parent
end

local function park(parent, x0, x1, z0, z1)
	local m = Instance.new("Model")
	m.Name = "Park"
	local w, d = x1 - x0, z1 - z0
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	part({ Name = "Lawn", Size = Vector3.new(w - 4, 0.5, d - 4), Position = Vector3.new(cx, 0.45, cz), Material = M.Grass, Color = rgb(112, 178, 86), Parent = m })
	part({ Name = "PathX", Size = Vector3.new(w - 4, 0.1, 3.2), Position = Vector3.new(cx, 0.72, cz), Material = M.Pavement, Color = rgb(226, 222, 210), Parent = m })
	part({ Name = "PathZ", Size = Vector3.new(3.2, 0.1, d - 4), Position = Vector3.new(cx, 0.72, cz), Material = M.Pavement, Color = rgb(226, 222, 210), Parent = m })
	disc({ Name = "Basin", Material = M.Concrete, Color = rgb(224, 226, 230), Parent = m }, cx, 1.1, cz, 1, 14)
	disc({ Name = "Water", Material = M.Glass, Color = rgb(80, 170, 220), Transparency = 0.15, Reflectance = 0.3, Parent = m }, cx, 1.62, cz, 0.1, 12.4)
	disc({ Name = "Jet", Material = M.Glass, Color = rgb(200, 236, 255), Transparency = 0.3, CastShadow = false, Parent = m }, cx, 3, cz, 4, 1.4)
	local count = math.floor(w * d / 260)
	for _ = 1, count do
		local px = x0 + 5 + rand() * (w - 10)
		local pz = z0 + 5 + rand() * (d - 10)
		if math.abs(px - cx) > 4 and math.abs(pz - cz) > 4 and (px - cx) ^ 2 + (pz - cz) ^ 2 > 120 then
			tree(m, px, pz, 0.9 + rand() * 0.6, 0.7)
		end
	end
	m.Parent = parent
end

-- kiểu nhà + chiều cao theo vị trí lô. s > 0 là phía camera toàn cảnh
local function plan(lx, lz)
	local dist = math.max(math.abs(lx), math.abs(lz))
	local s = (lx + lz) / 2
	local r = rand()
	if dist < 170 then
		-- vòng sát khu đất: thấp để không che, không đổ bóng lên lưới
		if s > 60 then
			return r < 0.5 and "shops" or "mid", 8 + rand() * 6
		end
		return r < 0.3 and "shops" or "mid", 12 + rand() * 16
	end
	local reach = math.clamp((dist - 170) / 300, 0, 1)
	if s > 90 then
		return "mid", 10 + rand() * (10 + 18 * reach)
	end
	local depth = math.clamp(-s / 300, 0, 1)
	if r < 0.3 + 0.5 * depth then
		return "tower", 45 + (40 + 120 * math.max(depth, reach * 0.6)) * (0.55 + rand() * 0.6)
	end
	return "mid", 18 + rand() * (20 + 30 * reach)
end

-- khối phố [x0, x1] x [z0, z1]: nền vỉa hè rồi chia lô
local function block(parent, x0, x1, z0, z1)
	local w, d = x1 - x0, z1 - z0
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local dist = math.max(math.abs(cx), math.abs(cz))
	local near = dist < 170
	local detail = dist < 330
	part({ Name = "Sidewalk", Size = Vector3.new(w, 0.4, d), Position = Vector3.new(cx, 0.2, cz), Material = M.Pavement, Color = CURB, Parent = parent })
	if near then
		dressEdges(parent, x0, x1, z0, z1)
	end
	local lotSize = detail and 30 or 60
	local nx = math.max(1, math.floor(w / lotSize + 0.5))
	local nz = math.max(1, math.floor(d / lotSize + 0.5))
	local lw, ld = w / nx, d / nz
	local margin = near and 8 or 6
	for i = 1, nx do
		for j = 1, nz do
			local lx, lz = x0 + lw * (i - 0.5), z0 + ld * (j - 0.5)
			local bw, bd = lw - margin - rand() * 4, ld - margin - rand() * 4
			local kind, h = plan(lx, lz)
			if kind == "tower" then
				bw, bd = math.min(bw, 30 + rand() * 8), math.min(bd, 30 + rand() * 8)
				tower(parent, lx, lz, bw, bd, h, detail or h > 130)
			elseif kind == "shops" then
				shops(parent, lx, lz, bw, bd, h)
			else
				bw, bd = math.min(bw, 46), math.min(bd, 46)
				midrise(parent, lx, lz, bw, bd, h, detail)
			end
		end
	end
end

-- mặt đường, vạch kẻ, cầu
local function streets(parent)
	local south = GROUND / 2 - RIVER.z1
	local north = RIVER.z0 + GROUND / 2
	part({ Name = "Asphalt", Size = Vector3.new(GROUND, 2, south), Position = Vector3.new(0, -1, RIVER.z1 + south / 2), Material = M.Asphalt, Color = ASPHALT, Parent = parent })
	part({ Name = "AsphaltFar", Size = Vector3.new(GROUND, 2, north), Position = Vector3.new(0, -1, RIVER.z0 - north / 2), Material = M.Asphalt, Color = ASPHALT, Parent = parent })

	local marks = Instance.new("Folder")
	marks.Name = "RoadMarks"
	marks.Parent = parent
	local function line(x, z, sx, sz)
		part({ Name = "Mark", Size = Vector3.new(sx, 0.05, sz), Position = Vector3.new(x, 0.025, z), Material = M.SmoothPlastic, Color = MARK, CanCollide = false, CanQuery = false, CastShadow = false, Parent = marks })
	end
	-- vạch tim đường, từng đoạn giữa 2 ngã tư
	for _, L in ipairs(LINES) do
		for _, band in ipairs(BANDS) do
			local a, b = band[1], band[2]
			local mid, len = (a + b) / 2, b - a
			-- đường chạy theo X (z = L)
			line(mid, L, len, 0.45)
			-- đường chạy theo Z (x = L): bỏ đoạn qua sông nếu không có cầu
			if not (onRiver(mid) and not BRIDGES[L]) then
				line(L, mid, 0.45, len)
			end
		end
	end
	-- vạch tim đại lộ
	line(GATE_X, (RING + ROAD / 2 + LINES[#LINES]) / 2, 0.45, LINES[#LINES] - RING - ROAD / 2)
	-- vạch sang đường quanh các ngã tư gần khu đất
	local nearLines = { -(RING + PITCH), -RING, RING, RING + PITCH }
	for _, ix in ipairs(nearLines) do
		for _, iz in ipairs(nearLines) do
			for _, side in ipairs({ -1, 1 }) do
				for k = -2, 2 do
					line(ix + side * (ROAD / 2 + 3), iz + k * 3, 4, 1.4)
					line(ix + k * 3, iz + side * (ROAD / 2 + 3), 1.4, 4)
				end
			end
		end
	end
	local len = RIVER.z1 - RIVER.z0
	local zc = (RIVER.z0 + RIVER.z1) / 2
	for x in pairs(BRIDGES) do
		local bridge = Instance.new("Model")
		bridge.Name = "Bridge"
		part({ Name = "Deck", Size = Vector3.new(ROAD + 4, 1.6, len + 2), Position = Vector3.new(x, -0.8, zc), Material = M.Concrete, Color = rgb(200, 202, 206), Parent = bridge })
		part({ Name = "Road", Size = Vector3.new(ROAD, 0.1, len + 2), Position = Vector3.new(x, 0.05, zc), Material = M.Asphalt, Color = ASPHALT, Parent = bridge })
		for _, side in ipairs({ -1, 1 }) do
			part({ Name = "Rail", Size = Vector3.new(0.6, 1.6, len + 2), Position = Vector3.new(x + side * (ROAD / 2 + 1.7), 0.8, zc), Material = M.Metal, Color = rgb(46, 107, 255), Parent = bridge })
		end
		for k = 1, 3 do
			part({ Name = "Pier", Size = Vector3.new(ROAD, 12, 3), Position = Vector3.new(x, -7.6, RIVER.z0 + len * k / 4), Material = M.Concrete, Color = rgb(182, 184, 190), Parent = bridge })
		end
		bridge.Parent = parent
	end
end

-- sông: kè 2 bờ + lan can, đáy, nước (Terrain nếu có)
local function river(parent)
	local len = RIVER.z1 - RIVER.z0
	local zc = (RIVER.z0 + RIVER.z1) / 2
	-- lan can ngắt chỗ có cầu
	local gaps = {}
	for x in pairs(BRIDGES) do
		table.insert(gaps, x)
	end
	table.sort(gaps)
	local spans, from = {}, -GROUND / 2
	for _, x in ipairs(gaps) do
		table.insert(spans, { from, x - ROAD / 2 - 2.2 })
		from = x + ROAD / 2 + 2.2
	end
	table.insert(spans, { from, GROUND / 2 })
	for _, z in ipairs({ RIVER.z0, RIVER.z1 }) do
		local inward = z == RIVER.z0 and 1 or -1
		part({ Name = "Embankment", Size = Vector3.new(GROUND, 15, 2), Position = Vector3.new(0, -7.5, z + inward), Material = M.Concrete, Color = rgb(190, 192, 196), Parent = parent })
		for _, span in ipairs(spans) do
			local a, b = span[1], span[2]
			part({ Name = "Railing", Size = Vector3.new(b - a, 1.2, 0.3), Position = Vector3.new((a + b) / 2, 0.6, z + inward * 1.6), Material = M.Metal, Color = rgb(90, 96, 108), CastShadow = false, Parent = parent })
		end
	end
	part({ Name = "RiverBed", Size = Vector3.new(GROUND, 2, len), Position = Vector3.new(0, -15, zc), Material = M.Slate, Color = rgb(72, 84, 88), Parent = parent })
	local ok = false
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		ok = pcall(function()
			terrain.WaterColor = rgb(48, 136, 180)
			terrain.WaterTransparency = 0.45
			terrain.WaterReflectance = 0.7
			terrain.WaterWaveSize = 0.08
			terrain.WaterWaveSpeed = 6
			-- voxel terrain chia mốc ở y = -6, -2, 2... nên mặt nước nằm quanh y = -2
			terrain:FillBlock(CFrame.new(0, -8, zc), Vector3.new(GROUND, 12, len - 4), M.Water)
		end)
	end
	if not ok then
		part({ Name = "Water", Size = Vector3.new(GROUND, 1, len - 4), Position = Vector3.new(0, -2.5, zc), Material = M.Glass, Color = rgb(48, 136, 180), Transparency = 0.2, Reflectance = 0.3, CanCollide = false, Parent = parent })
	end
end

-- đèn trên vỉa hè quanh khu đất. Vỉa hè do client vẽ, mặt trên y = 0.5
local function plotLamps(parent)
	local edge = HALF + 3
	for t = -HALF + 6, HALF - 6, 24 do
		for _, p in ipairs({ { t, -edge }, { t, edge }, { -edge, t }, { edge, t } }) do
			if not (p[2] == edge and math.abs(p[1] - GATE_X) < 12) then
				lamp(parent, p[1], p[2], 0.5)
			end
		end
	end
end

-- xe đỗ dọc các làn gần khu đất
local function traffic(parent)
	local cars = Instance.new("Folder")
	cars.Name = "Traffic"
	cars.Parent = parent
	local function clear(x, z)
		for _, L in ipairs(LINES) do
			if math.abs(x - L) < ROAD / 2 + 6 and math.abs(z - L) < ROAD / 2 + 6 then
				return false
			end
		end
		if math.abs(x - GATE_X) < 14 and math.abs(z - (RING + 8)) < 16 then
			return false -- chừa chỗ spawn
		end
		return true
	end
	local function crossing(v)
		for _, L in ipairs(LINES) do
			if math.abs(v - L) < ROAD / 2 + 6 then
				return true
			end
		end
		return false
	end
	local near = { -(RING + 2 * PITCH), -(RING + PITCH), -RING, RING, RING + PITCH, RING + 2 * PITCH }
	for _, L in ipairs(near) do
		for _ = 1, 4 do
			local lane = rand() < 0.5 and -4 or 4
			local t = -260 + rand() * 520
			if not crossing(t) and clear(t, L) then
				car(cars, t, L + lane, true)
			end
			t = -260 + rand() * 520
			if not crossing(t) and not onRiver(t) and clear(L, t) then
				car(cars, L + lane, t, false)
			end
		end
	end
	for _ = 1, 6 do
		local z = RING + ROAD + rand() * 300
		if not crossing(z) then
			car(cars, GATE_X + (rand() < 0.5 and -4 or 4), z, false)
		end
	end
end

local function cityscape(folder)
	local city = Instance.new("Folder")
	city.Name = "Cityscape"
	streets(city)
	river(city)
	for _, bx in ipairs(BANDS) do
		for _, bz in ipairs(BANDS) do
			local centerX = bx[1] < 0 and bx[2] > 0
			local centerZ = bz[1] < 0 and bz[2] > 0
			local cx, cz = (bx[1] + bx[2]) / 2, (bz[1] + bz[2]) / 2
			if (centerX and centerZ) or onRiver(cz) then
				-- khu đất của người chơi / lòng sông: để trống
			elseif cx == LANDMARK.x and cz == LANDMARK.z then
				part({ Name = "Sidewalk", Size = Vector3.new(bx[2] - bx[1], 0.4, bz[2] - bz[1]), Position = Vector3.new(cx, 0.2, cz), Material = M.Pavement, Color = CURB, Parent = city })
				landmark(city, cx, cz)
			elseif (cx == -cz and math.abs(cx) == RING + PITCH / 2) or rand() < 0.05 then
				-- 2 công viên ở 2 góc chéo sát khu đất + vài cái rải rác
				part({ Name = "Sidewalk", Size = Vector3.new(bx[2] - bx[1], 0.4, bz[2] - bz[1]), Position = Vector3.new(cx, 0.2, cz), Material = M.Pavement, Color = CURB, Parent = city })
				park(city, bx[1], bx[2], bz[1], bz[2])
				if math.max(math.abs(cx), math.abs(cz)) < 170 then
					dressEdges(city, bx[1], bx[2], bz[1], bz[2])
				end
			elseif centerX and bz[1] > 0 then
				-- dải phía +Z bị đại lộ dẫn vào cổng chia đôi
				block(city, bx[1], AVENUE[1], bz[1], bz[2])
				block(city, AVENUE[2], bx[2], bz[1], bz[2])
			else
				block(city, bx[1], bx[2], bz[1], bz[2])
			end
		end
	end
	plotLamps(city)
	traffic(city)
	pcall(function()
		local terrain = Workspace:FindFirstChildOfClass("Terrain")
		if terrain then
			local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
			clouds.Cover = 0.45
			clouds.Density = 0.55
			clouds.Color = rgb(255, 255, 255)
			clouds.Parent = terrain
		end
	end)
	city.Parent = folder
end

function World.build()
	if Workspace:FindFirstChild("EconCityWorld") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "EconCityWorld"

	local ok, err = pcall(cityscape, folder)
	if not ok then
		warn("[EconCity] Couldn't build the city backdrop: " .. tostring(err))
		part({ Name = "Ground", Size = Vector3.new(1000, 2, 1000), Position = Vector3.new(0, -1, 0), Material = M.Asphalt, Color = ASPHALT, Parent = folder })
	end

	local spawnPos = CityLayout.SPAWN
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CitySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	-- trên đường vành đai trước cổng, cùng màu mặt đường cho khỏi lộ ở góc nhìn toàn cảnh
	spawn.Size = Vector3.new(10, 0.2, 10)
	spawn.Position = Vector3.new(spawnPos.x, spawnPos.y + 0.1, spawnPos.z)
	spawn.Material = M.Asphalt
	spawn.Color = ASPHALT
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = folder

	-- tường vô hình, không cho nhân vật ra khỏi lưới phố
	local half, height, thick = LIMIT, 300, 4
	local walls = {
		{ Vector3.new(0, height / 2, half + thick / 2), Vector3.new(half * 2 + thick * 2, height, thick) },
		{ Vector3.new(0, height / 2, -half - thick / 2), Vector3.new(half * 2 + thick * 2, height, thick) },
		{ Vector3.new(half + thick / 2, height / 2, 0), Vector3.new(thick, height, half * 2) },
		{ Vector3.new(-half - thick / 2, height / 2, 0), Vector3.new(thick, height, half * 2) },
	}
	for i, w in ipairs(walls) do
		part({
			Name = "Boundary" .. i,
			Position = w[1],
			Size = w[2],
			Transparency = 1,
			CanCollide = true,
			CastShadow = false,
			Parent = folder,
		})
	end

	folder.Parent = Workspace
end

return World
