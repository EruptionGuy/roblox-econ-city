-- Bản vẽ khối cho từng loại công trình. Hàm thuần, trả list spec, toạ độ tính từ tâm công trình.
-- spec: name, shape, size {x,y,z}, pos {x,y,z}, color, material; tuỳ chọn: rot (độ, quanh trục đứng), transparency,
-- reflectance, noShadow, noCollide, effect ("smoke"), label, labelColor, labelFace (tên mặt Roblox, "Back" = +Z, "Right" = +X).
-- pos y = đáy khối so với mặt lô. Cylinder: x = z = đường kính. Wedge: cao ở đầu +Z (trục riêng, trước khi xoay rot).
-- Mặt tiền là +Z, renderer xoay cả công trình ra phía ô đường kề. 1x1 nằm trong ±6.2, 2x2 trong ±13.2 (ô 14 stud).

local CitySpecs = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("EconCity"):WaitForChild("Config"))

local FLOOR = 3
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local M = Enum.Material

local PLASTIC = M.SmoothPlastic
local PLASTER = M.Plaster
local BRICK = M.Brick
local CONCRETE = M.Concrete
local GLASSMAT = M.Glass
local METAL = M.Metal
local TILES = M.ClayRoofTiles
local SHINGLES = M.RoofShingles
local WOODMAT = M.WoodPlanks
local GRASSMAT = M.Grass
local PAVE = M.Pavement

local WALLS = { rgb(247, 241, 230), rgb(242, 236, 222), rgb(236, 240, 244), rgb(248, 233, 214), rgb(232, 236, 228) }
local GLASS = rgb(150, 196, 230)
local GLASS_DARK = rgb(86, 128, 168)
local FRAME = rgb(250, 250, 248)
local WOOD = rgb(128, 90, 60)
local DECK = rgb(186, 146, 104)
local TRUNK = rgb(112, 82, 58)
local STONE = rgb(214, 210, 200)
local PAVING = rgb(226, 223, 214)
local LAWN = rgb(124, 186, 96)
local ASPHALT = rgb(84, 88, 96)
local DARK = rgb(62, 66, 74)
local STEEL = rgb(200, 204, 210)
local BRICK_RED = rgb(190, 108, 82)
local SIDEWALK = rgb(214, 216, 210)
local WATER = rgb(90, 170, 230)
local LEAVES = { rgb(86, 164, 74), rgb(104, 178, 84), rgb(70, 142, 68), rgb(124, 186, 78), rgb(94, 156, 92) }
local FLOWERS = { rgb(244, 114, 146), rgb(250, 204, 72), rgb(255, 255, 255), rgb(196, 120, 230), rgb(250, 140, 70) }
local CARS = { rgb(230, 70, 70), rgb(70, 130, 230), rgb(250, 250, 250), rgb(250, 196, 60), rgb(60, 60, 70), rgb(80, 190, 150), rgb(160, 164, 172) }
local CLOTHES = { rgb(46, 107, 255), rgb(208, 52, 52), rgb(60, 157, 74), rgb(242, 184, 40), rgb(124, 92, 220), rgb(240, 138, 36), rgb(250, 250, 250) }
local SKIN = { rgb(255, 214, 170), rgb(224, 172, 128), rgb(176, 120, 84), rgb(250, 226, 196) }
local PANTS = rgb(52, 60, 84)

-- mặt: 1 = +Z (tiền), 2 = +X, 3 = -Z (sau), 4 = -X
local FACE = { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }
local LABEL_FACE = { "Back", "Right", "Front", "Left" }

-- màu đất của loại công trình (mái, biển... dùng màu này để nhìn xa vẫn biết loại đất). t < 1 pha trắng, dark > 0 làm sẫm
local function land(kind, t, dark)
	local c = Config.BUILDINGS[kind].color
	local col = rgb(c[1], c[2], c[3])
	if t and t < 1 then
		col = WHITE:Lerp(col, t)
	end
	if dark and dark > 0 then
		col = col:Lerp(BLACK, dark)
	end
	return col
end

local function spec(name, shape, sx, sy, sz, px, py, pz, color, material, extra)
	local s = {
		name = name,
		shape = shape,
		size = { sx, sy, sz },
		pos = { px, py, pz },
		color = color,
		material = material or PLASTIC,
	}
	for k, v in pairs(extra or {}) do
		s[k] = v
	end
	return s
end

local function add(out, s)
	table.insert(out, s)
	return s
end

-- 0..1 theo index ô, để nhà cùng loại không giống hệt nhau
local function variant(index)
	return (index * 7919) % 97 / 97
end

local function pick(list, v)
	return list[math.floor(v * #list) % #list + 1]
end

local function box(out, name, w, h, d, x, y, z, color, material, extra)
	return add(out, spec(name, "Block", w, h, d, x, y, z, color, material, extra))
end

local function cyl(out, name, dia, h, x, y, z, color, material, extra)
	return add(out, spec(name, "Cylinder", dia, h, dia, x, y, z, color, material, extra))
end

local function ball(out, name, dia, x, y, z, color, material, extra)
	return add(out, spec(name, "Ball", dia, dia, dia, x, y, z, color, material, extra))
end

-- vạch sơn, mảng phẳng sát đất: không collide, không đổ bóng
local function flat(out, name, w, d, x, y, z, color, material, extra)
	local e = { noShadow = true, noCollide = true }
	for k, v in pairs(extra or {}) do
		e[k] = v
	end
	return box(out, name, w, 0.05, d, x, y, z, color, material or PLASTIC, e)
end

-- mái 2 dốc trên khối w x d, nóc chạy theo axis "x" hoặc "z"
local function gable(out, name, w, d, h, x, y, z, color, axis, material)
	material = material or TILES
	if axis == "z" then
		add(out, spec(name .. "L", "Wedge", d, h, w / 2, x - w / 4, y, z, color, material, { rot = 90 }))
		add(out, spec(name .. "R", "Wedge", d, h, w / 2, x + w / 4, y, z, color, material, { rot = -90 }))
	else
		add(out, spec(name .. "B", "Wedge", w, h, d / 2, x, y, z - d / 4, color, material))
		add(out, spec(name .. "F", "Wedge", w, h, d / 2, x, y, z + d / 4, color, material, { rot = 180 }))
	end
end

-- mái răng cưa: n dốc dọc trục X, mặt đứng mỗi răng (phía +X) là dải kính
local function sawtooth(out, name, w, d, h, x, y, z, n, colorA, colorB)
	local step = w / n
	for k = 1, n do
		local px = x - w / 2 + step * (k - 0.5)
		add(out, spec(name .. k, "Wedge", d, h, step, px, y, z, k % 2 == 0 and colorB or colorA, METAL, { rot = 90 }))
		box(out, name .. "Light" .. k, 0.12, h * 0.75, d - 0.8, px + step / 2 + 0.02, y + 0.1, z, GLASS_DARK, GLASSMAT, { reflectance = 0.2, noShadow = true })
	end
end

-- điểm trên mặt face của khối w x d tâm (x, z): t dọc mặt, off nhô ra ngoài
local function onFace(face, x, z, w, d, t, off)
	local dir = FACE[face]
	if dir[1] == 0 then
		return x + t, z + dir[2] * (d / 2 + off)
	end
	return x + dir[1] * (w / 2 + off), z + t
end

-- a dọc mặt, b cao, c dày
local function faceSize(face, a, b, c)
	if FACE[face][1] == 0 then
		return a, b, c
	end
	return c, b, a
end

local function faceLength(face, w, d)
	return FACE[face][1] == 0 and w or d
end

-- tấm áp lên mặt face (cửa, biển, ô kính): rộng pw, cao ph, dày thick, đáy ở y
local function panel(out, name, face, w, d, x, z, t, y, pw, ph, color, material, off, thick, extra)
	thick = thick or 0.14
	local px, pz = onFace(face, x, z, w, d, t, (off or 0) + thick / 2)
	local sx, sy, sz = faceSize(face, pw, ph, thick)
	local e = { noShadow = true }
	for k, v in pairs(extra or {}) do
		e[k] = v
	end
	return box(out, name, sx, sy, sz, px, y, pz, color, material or PLASTIC, e)
end

local function sign(out, name, text, face, w, d, x, z, t, y, pw, ph, bg, fg, off)
	return panel(out, name, face, w, d, x, z, t, y, pw, ph, bg, PLASTIC, off or 0, 0.3, { label = text, labelColor = fg or WHITE, labelFace = LABEL_FACE[face] })
end

-- cửa sổ 4 mặt, tầng đầu từ y0. counts = số cửa mỗi tầng {tiền, +X, sau, -X}
-- opts: ww, wh (cỡ kính), floorH, sill (tính từ sàn), glass, frame (false = bỏ khung), shutter (màu chớp),
-- positions[face] = {t...} nếu muốn đặt tay, skip(face, f, k) trả true để bỏ ô đó
local function windowsAll(out, name, w, d, x, z, y0, floors, counts, opts)
	opts = opts or {}
	local ww, wh = opts.ww or 1.2, opts.wh or 1.4
	local fh = opts.floorH or FLOOR
	local glass = opts.glass or GLASS
	local frame = opts.frame
	if frame == nil then
		frame = FRAME
	end
	for f = 0, floors - 1 do
		local y = y0 + f * fh + (opts.sill or 0.8)
		for face = 1, 4 do
			local ts = opts.positions and opts.positions[face]
			local n = ts and #ts or (counts[face] or 0)
			local length = faceLength(face, w, d)
			for k = 1, n do
				if not (opts.skip and opts.skip(face, f, k)) then
					local t = ts and ts[k] or (-length / 2 + length * (k - 0.5) / n)
					local id = name .. face .. "_" .. f .. "_" .. k
					if frame then
						panel(out, id .. "F", face, w, d, x, z, t, y - 0.17, ww + 0.34, wh + 0.34, frame, PLASTIC, 0, 0.1)
					end
					panel(out, id, face, w, d, x, z, t, y, ww, wh, glass, GLASSMAT, frame and 0.06 or 0, 0.1, { reflectance = 0.25 })
					if opts.shutter then
						for _, sgn in ipairs({ -1, 1 }) do
							panel(out, id .. "S" .. sgn, face, w, d, x, z, t + sgn * (ww / 2 + 0.42), y - 0.05, 0.42, wh + 0.1, opts.shutter, PLASTIC, 0, 0.1)
						end
					end
				end
			end
		end
	end
end

-- mỗi tầng 1 dải kính quanh 4 mặt (1 khối bọc ngoài thân nhà)
local function ribbons(out, name, w, d, x, z, y0, floors, h, color, fh, extra)
	fh = fh or FLOOR
	local e = { reflectance = 0.22, noShadow = true }
	for k, v in pairs(extra or {}) do
		e[k] = v
	end
	for f = 0, floors - 1 do
		box(out, name .. f, w + 0.24, h, d + 0.24, x, y0 + f * fh + (fh - h) / 2, z, color, GLASSMAT, e)
	end
end

-- thanh đứng chia kính, n thanh mỗi mặt
local function mullions(out, name, w, d, x, z, y0, height, n, color)
	for face = 1, 4 do
		local length = faceLength(face, w, d)
		for k = 1, n do
			local t = -length / 2 + length * k / (n + 1)
			panel(out, name .. face .. k, face, w, d, x, z, t, y0, 0.24, height, color or FRAME, PLASTIC, 0.12, 0.2)
		end
	end
end

local function door(out, name, face, w, d, x, z, t, color, wide, high)
	wide, high = wide or 1.2, high or 2.2
	panel(out, name .. "Frame", face, w, d, x, z, t, 0, wide + 0.36, high + 0.18, FRAME, PLASTIC, 0, 0.1)
	panel(out, name, face, w, d, x, z, t, 0, wide, high, color or WOOD, (color == GLASS_DARK or color == GLASS) and GLASSMAT or WOODMAT, 0.06, 0.1)
end

local function tree(out, name, x, z, scale, y, v)
	scale = scale or 1
	y = y or 0
	v = v or ((x * 13 + z * 7) % 10) / 10
	cyl(out, name .. "Trunk", 0.6 * scale, 2.6 * scale, x, y, z, TRUNK, WOODMAT)
	ball(out, name .. "Crown", 4 * scale, x, y + 1.9 * scale, z, pick(LEAVES, v), GRASSMAT)
	ball(out, name .. "Top", 2.8 * scale, x + 0.5 * scale, y + 3.8 * scale, z - 0.3 * scale, pick(LEAVES, v + 0.3), GRASSMAT)
end

-- cây thông
local function pine(out, name, x, z, scale, y)
	scale = scale or 1
	y = y or 0
	cyl(out, name .. "Trunk", 0.5 * scale, 1.6 * scale, x, y, z, TRUNK, WOODMAT)
	cyl(out, name .. "Low", 3 * scale, 1.4 * scale, x, y + 1.4 * scale, z, rgb(58, 128, 72), GRASSMAT)
	cyl(out, name .. "Mid", 2.2 * scale, 1.3 * scale, x, y + 2.6 * scale, z, rgb(66, 140, 78), GRASSMAT)
	cyl(out, name .. "Top", 1.3 * scale, 1.2 * scale, x, y + 3.7 * scale, z, rgb(76, 152, 84), GRASSMAT)
end

local function bush(out, name, x, z, scale, y)
	scale = scale or 1
	ball(out, name, 1.6 * scale, x, y or 0, z, pick(LEAVES, (x * 3 + z) % 1), GRASSMAT)
end

-- bồn cây bê tông
local function planter(out, name, x, z, size, y)
	y = y or 0
	box(out, name, size, 0.7, size, x, y, z, STONE, CONCRETE)
	ball(out, name .. "Bush", size * 0.95, x, y + 0.35, z, pick(LEAVES, (x + z * 2) % 1), GRASSMAT)
end

-- hàng rào cây xén
local function hedge(out, name, w, d, x, z, y)
	box(out, name, w, 0.9, d, x, y or 0, z, rgb(72, 140, 70), GRASSMAT)
end

-- luống hoa, dọc trục X
local function flowers(out, name, x, z, w, d, y)
	y = y or 0
	box(out, name .. "Bed", w, 0.35, d, x, y, z, rgb(122, 92, 66), M.Ground)
	local n = math.max(2, math.floor(w / 0.8))
	for k = 1, n do
		local px = x - w / 2 + w * (k - 0.5) / n
		ball(out, name .. k, 0.7, px, y + 0.25, z + ((k % 2 == 0) and d * 0.2 or -d * 0.2), FLOWERS[(k % #FLOWERS) + 1], PLASTIC, { noShadow = true })
	end
end

-- rào gỗ từ (x0, z0) tới (x1, z1), chỉ đi thẳng theo X hoặc Z
local function fence(out, name, x0, z0, x1, z1, y, color, step)
	y = y or 0
	color = color or WHITE
	step = step or 1.3
	local alongX = z0 == z1
	local length = alongX and math.abs(x1 - x0) or math.abs(z1 - z0)
	local n = math.max(1, math.floor(length / step + 0.5))
	for k = 0, n do
		local t = k / n
		box(out, name .. "Post" .. k, 0.22, 1.1, 0.22, x0 + (x1 - x0) * t, y, z0 + (z1 - z0) * t, color, WOODMAT, { noShadow = true })
	end
	for r, ry in ipairs({ 0.3, 0.75 }) do
		box(out, name .. "Rail" .. r, alongX and length or 0.12, 0.16, alongX and 0.12 or length, (x0 + x1) / 2, y + ry, (z0 + z1) / 2, color, WOODMAT, { noShadow = true })
	end
end

local function car(out, name, x, z, color, alongX, y)
	y = y or 0
	local function s(a, c)
		if alongX then
			return a, c
		end
		return c, a
	end
	local wx, wz = s(0.75, 1.9)
	local fx, fz = s(1.15, 0)
	box(out, name .. "WheelF", wx, 0.75, wz, x + fx, y, z + fz, DARK, PLASTIC)
	box(out, name .. "WheelB", wx, 0.75, wz, x - fx, y, z - fz, DARK, PLASTIC)
	local bx, bz = s(3.6, 1.8)
	box(out, name .. "Body", bx, 0.8, bz, x, y + 0.35, z, color, PLASTIC)
	local cx, cz = s(2, 1.6)
	box(out, name .. "Cabin", cx, 0.62, cz, x, y + 1.15, z, GLASS_DARK, GLASSMAT, { reflectance = 0.25, noShadow = true })
	local rx, rz = s(1.8, 1.65)
	box(out, name .. "Roof", rx, 0.14, rz, x, y + 1.77, z, color, PLASTIC)
end

local function person(out, name, x, z, v, y)
	y = y or 0
	box(out, name .. "Legs", 0.55, 0.85, 0.32, x, y, z, PANTS, PLASTIC, { noShadow = true })
	box(out, name .. "Shirt", 0.72, 0.85, 0.4, x, y + 0.85, z, pick(CLOTHES, v), PLASTIC, { noShadow = true })
	ball(out, name .. "Head", 0.56, x, y + 1.7, z, pick(SKIN, v * 1.7), PLASTIC, { noShadow = true })
end

-- tựa lưng ở phía -Z nếu alongX, không thì -X
local function bench(out, name, x, z, alongX, y)
	y = y or 0
	box(out, name, alongX and 2.4 or 0.8, 0.55, alongX and 0.8 or 2.4, x, y, z, WOOD, WOODMAT)
	box(out, name .. "Back", alongX and 2.4 or 0.16, 0.7, alongX and 0.16 or 2.4, x - (alongX and 0 or 0.34), y + 0.55, z - (alongX and 0.34 or 0), WOOD, WOODMAT, { noShadow = true })
end

local function lamp(out, name, x, z, y, height)
	y = y or 0
	height = height or 4.2
	cyl(out, name .. "Pole", 0.24, height, x, y, z, rgb(70, 74, 82), METAL, { noShadow = true })
	ball(out, name .. "Light", 0.7, x, y + height - 0.1, z, rgb(255, 240, 200), M.Neon, { noShadow = true })
end

-- cục nóng điều hoà
local function acUnit(out, name, x, y, z)
	box(out, name, 1.6, 0.9, 1.2, x, y, z, STEEL, METAL)
	cyl(out, name .. "Fan", 0.8, 0.06, x, y + 0.9, z, DARK, METAL, { noShadow = true })
end

local function solar(out, name, x, y, z, w, d)
	box(out, name .. "Stand", w * 0.8, 0.3, d * 0.6, x, y, z, STEEL, METAL)
	box(out, name, w, 0.12, d, x, y + 0.3, z, rgb(38, 58, 108), GLASSMAT, { reflectance = 0.3 })
end

-- mái hiên sọc nhô ra +Z, z là mép sát tường
local function awning(out, name, w, x, y, z, color, n)
	n = n or 6
	local step = w / n
	for k = 1, n do
		add(out, spec(name .. k, "Wedge", step, 0.9, 2.2, x - w / 2 + step * (k - 0.5), y, z + 1.1, k % 2 == 1 and color or WHITE, PLASTIC, { rot = 180, noShadow = true }))
	end
end

local function umbrella(out, name, x, z, color, y)
	y = y or 0
	cyl(out, name .. "Pole", 0.16, 2.6, x, y, z, WHITE, METAL, { noShadow = true })
	cyl(out, name, 3, 0.25, x, y + 2.5, z, color, PLASTIC)
	ball(out, name .. "Top", 0.4, x, y + 2.7, z, color, PLASTIC, { noShadow = true })
end

-- bàn + 2 ghế
local function tableSet(out, name, x, z, y)
	y = y or 0
	cyl(out, name, 1.3, 1, x, y, z, WHITE, PLASTIC)
	box(out, name .. "ChairA", 0.6, 0.9, 0.6, x - 1, y, z, DARK, METAL)
	box(out, name .. "ChairB", 0.6, 0.9, 0.6, x + 1, y, z, DARK, METAL)
end

-- cờ đỏ sao vàng
local function flagpole(out, name, x, z, height, y)
	y = y or 0
	cyl(out, name .. "Pole", 0.28, height, x, y, z, WHITE, METAL, { noShadow = true })
	box(out, name .. "Flag", 2.6, 1.6, 0.12, x + 1.4, y + height - 1.8, z, rgb(218, 37, 29), PLASTIC, { noShadow = true })
	box(out, name .. "Star", 0.7, 0.7, 0.16, x + 1.4, y + height - 1.35, z, rgb(255, 222, 0), PLASTIC, { noShadow = true })
end

local function fountain(out, name, x, z, dia, y)
	y = y or 0
	cyl(out, name .. "Basin", dia, 0.7, x, y, z, STONE, M.Cobblestone)
	cyl(out, name .. "Water", dia - 0.7, 0.74, x, y, z, WATER, GLASSMAT, { transparency = 0.1, reflectance = 0.35 })
	cyl(out, name .. "Column", dia * 0.16, 1.6, x, y + 0.7, z, STONE, CONCRETE)
	cyl(out, name .. "Bowl", dia * 0.42, 0.3, x, y + 2.2, z, STONE, CONCRETE)
	cyl(out, name .. "Jet", dia * 0.08, 1.4, x, y + 2.5, z, rgb(214, 238, 255), GLASSMAT, { transparency = 0.35, noShadow = true })
	ball(out, name .. "Spray", dia * 0.22, x, y + 3.6, z, rgb(214, 238, 255), GLASSMAT, { transparency = 0.45, noShadow = true })
end

-- xe tải dọc trục Z, đầu xe phía +Z
local function truck(out, name, x, z, cabColor, y, length)
	y = y or 0
	length = length or 5.5
	box(out, name .. "Wheels", 2.5, 0.8, length + 1.4, x, y, z + 0.6, DARK, PLASTIC)
	box(out, name .. "Box", 2.5, 2.8, length, x, y + 0.6, z - 0.2, WHITE, METAL)
	box(out, name .. "Cab", 2.4, 2.2, 1.9, x, y + 0.6, z + length / 2 + 0.8, cabColor, PLASTIC)
	box(out, name .. "Windshield", 2.1, 0.8, 0.1, x, y + 1.9, z + length / 2 + 1.76, GLASS_DARK, GLASSMAT, { noShadow = true })
end

local BUILDERS = {}

-- nhà 2 tầng có ga-ra
BUILDERS.house = function(v)
	local out = {}
	local wall = pick(WALLS, v)
	local roof = land("house", 1, 0.3)
	box(out, "lawn", 12.4, 0.1, 12.4, 0, 0, 0, LAWN, GRASSMAT)
	local bx, bz, bw, bd = -1.6, -1.6, 7.2, 6.4
	box(out, "plinth", bw + 0.2, 0.6, bd + 0.2, bx, 0, bz, STONE, M.Slate)
	box(out, "body", bw, 2 * FLOOR, bd, bx, 0, bz, wall, PLASTER)
	box(out, "trim", bw + 0.16, 0.25, bd + 0.16, bx, FLOOR - 0.1, bz, FRAME, PLASTIC, { noShadow = true })
	gable(out, "roof", bw + 1, bd + 1, 2.8, bx, 2 * FLOOR, bz, roof, "x")
	windowsAll(out, "win", bw, bd, bx, bz, 0, 2, { 2, 2, 2, 2 }, {
		skip = function(face, f, k)
			return f == 0 and ((face == 1 and k == 2) or face == 2)
		end,
	})
	door(out, "door", 1, bw, bd, bx, bz, 1.8, rgb(150, 74, 56), 1.2, 2.3)
	box(out, "doorRoof", 2, 0.22, 1.1, bx + 1.8, 2.65, bz + bd / 2 + 0.55, roof, PLASTIC)
	box(out, "step", 1.7, 0.3, 0.8, bx + 1.8, 0, bz + bd / 2 + 0.4, STONE, CONCRETE)
	box(out, "path", 1.2, 0.14, 3.8, bx + 1.8, 0, 4.3, STONE, PAVE)
	box(out, "chimney", 1, 3.6, 1, bx - 2.4, 2 * FLOOR, bz - 2, BRICK_RED, BRICK)
	box(out, "chimneyCap", 1.3, 0.3, 1.3, bx - 2.4, 2 * FLOOR + 3.6, bz - 2, DARK, CONCRETE)
	-- ga-ra mái bằng bên phải
	box(out, "garage", 3.6, 2.9, 5.2, 4.2, 0, -2.2, wall, PLASTER)
	box(out, "garageRoof", 3.9, 0.3, 5.6, 4.2, 2.9, -2.2, roof, PLASTIC)
	box(out, "garageDoor", 2.8, 2.3, 0.12, 4.2, 0, 0.46, STEEL, METAL, { noShadow = true })
	for k = 1, 2 do
		box(out, "garageLine" .. k, 2.8, 0.08, 0.16, 4.2, 0.75 * k, 0.48, rgb(160, 164, 172), PLASTIC, { noShadow = true })
	end
	box(out, "driveway", 3.2, 0.14, 5.8, 4.2, 0, 3.3, PAVING, PAVE)
	if v > 0.3 then
		car(out, "car", 4.2, 3.4, pick(CARS, v), false, 0.14)
	end
	flowers(out, "flowers", bx - 1.4, bz + bd / 2 + 0.7, 3.4, 0.8, 0.1)
	fence(out, "fence", -6, 5.95, -0.6, 5.95, 0.1)
	tree(out, "tree", -4.4, 4, 0.8, 0.1, v)
	cyl(out, "mailPost", 0.18, 1.1, 1.3, 0.1, 5.7, WOOD, WOODMAT, { noShadow = true })
	box(out, "mailbox", 0.5, 0.45, 0.8, 1.3, 1.2, 5.7, rgb(46, 107, 255), PLASTIC, { noShadow = true })
	bush(out, "bushA", -5.4, -5.5, 0.8, 0.1)
	bush(out, "bushB", 1.4, -5.6, 0.7, 0.1)
	return out
end

-- nhà 1 tầng có hiên
BUILDERS.house_small = function(v)
	local out = {}
	local wall = pick(WALLS, v + 0.4)
	local roof = land("house", 1, 0.4)
	box(out, "lawn", 12.4, 0.1, 12.4, 0, 0, 0, LAWN, GRASSMAT)
	local bx, bz, bw, bd = -1.2, -1.6, 6.4, 5.2
	box(out, "plinth", bw + 0.2, 0.5, bd + 0.2, bx, 0, bz, STONE, M.Slate)
	box(out, "cottage", bw, 3.4, bd, bx, 0, bz, wall, PLASTER)
	gable(out, "roof", bw + 0.9, bd + 1.2, 2.6, bx, 3.4, bz, roof, "x", SHINGLES)
	windowsAll(out, "win", bw, bd, bx, bz, 0, 1, { 2, 1, 2, 1 }, { shutter = rgb(78, 116, 98), sill = 0.9, ww = 1, positions = { [1] = { -2, 2 } } })
	for k, t in ipairs({ -2, 2 }) do
		box(out, "flowerBox" .. k, 1.4, 0.35, 0.45, bx + t, 0.5, bz + bd / 2 + 0.25, WOOD, WOODMAT)
		ball(out, "flowerA" .. k, 0.6, bx + t - 0.35, 0.75, bz + bd / 2 + 0.25, FLOWERS[k], PLASTIC, { noShadow = true })
		ball(out, "flowerB" .. k, 0.6, bx + t + 0.35, 0.75, bz + bd / 2 + 0.25, FLOWERS[k + 2], PLASTIC, { noShadow = true })
	end
	door(out, "door", 1, bw, bd, bx, bz, 0, rgb(60, 110, 150), 1.1, 2.2)
	-- hiên gỗ
	box(out, "porch", 4.6, 0.3, 2, bx, 0, bz + bd / 2 + 1, DECK, WOODMAT)
	for k, px in ipairs({ bx - 2.1, bx + 2.1 }) do
		cyl(out, "porchPost" .. k, 0.3, 2.6, px, 0.3, bz + bd / 2 + 1.8, WHITE, WOODMAT)
	end
	box(out, "porchRoof", 5, 0.25, 2.3, bx, 2.9, bz + bd / 2 + 1.05, roof, PLASTIC)
	for k, sz in ipairs({ 3.7, 4.6, 5.4 }) do
		cyl(out, "stone" .. k, 1, 0.14, bx, 0.1, sz, STONE, M.Slate)
	end
	fence(out, "fenceL", -6, 5.95, -2.2, 5.95, 0.1)
	fence(out, "fenceR", -0.2, 5.95, 6, 5.95, 0.1)
	-- kho vườn
	box(out, "shed", 2.6, 2.2, 2.4, 4.2, 0.1, -4.4, rgb(150, 110, 80), WOODMAT)
	add(out, spec("shedRoof", "Wedge", 3, 0.8, 2.8, 4.2, 2.3, -4.4, roof, SHINGLES))
	box(out, "shedDoor", 1, 1.7, 0.1, 4.2, 0.1, -3.15, rgb(120, 86, 62), WOODMAT, { noShadow = true })
	tree(out, "tree", 4.2, 2.6, 0.9, 0.1, v)
	bush(out, "bush", 4.8, -1.2, 1, 0.1)
	flowers(out, "flowers", -4.2, 5.1, 3, 0.7, 0.1)
	return out
end

-- chung cư 2x2, 2 khối xếp chữ L
BUILDERS.apartment = function(v)
	local out = {}
	local floors = 6 + math.floor(v * 3)
	local h = floors * FLOOR
	local wall = pick(WALLS, v + 0.2)
	local accent = land("house", 1, 0.1)
	box(out, "court", 26.2, 0.1, 26.2, 0, 0, 0, PAVING, PAVE)
	-- khối A dọc phía sau
	local ax, az, aw, ad = -1.5, -8.5, 22, 7.6
	box(out, "slabA", aw, h, ad, ax, 0, az, wall, PLASTER)
	ribbons(out, "winA", aw, ad, ax, az, 0, floors, 1.5, GLASS)
	box(out, "roofA", aw + 0.4, 0.8, ad + 0.4, ax, h, az, accent, PLASTIC)
	for f = 1, floors - 1 do
		for k = 0, 3 do
			local px = -9.4 + k * 5.2
			box(out, "balA" .. f .. k, 3.6, 0.25, 1.3, px, f * FLOOR - 0.05, az + ad / 2 + 0.65, FRAME, PLASTIC)
			box(out, "railA" .. f .. k, 3.6, 0.9, 0.1, px, f * FLOOR + 0.2, az + ad / 2 + 1.25, rgb(200, 226, 240), GLASSMAT, { transparency = 0.35, noShadow = true })
		end
	end
	for k, px in ipairs({ ax - aw / 2 + 0.6, ax + aw / 2 - 0.6 }) do
		box(out, "stripeA" .. k, 1.2, h, 0.3, px, 0, az + ad / 2 + 0.15, accent, PLASTIC, { noShadow = true })
	end
	box(out, "entrance", 3.4, 2.4, 0.12, -1.5, 0, az + ad / 2 + 0.1, GLASS_DARK, GLASSMAT, { noShadow = true })
	box(out, "canopy", 4.4, 0.3, 2, -1.5, 2.55, az + ad / 2 + 1, accent, PLASTIC)
	box(out, "nameSign", 7, 1.4, 0.3, ax, h + 0.8, az + ad / 2 - 0.4, accent, PLASTIC, { label = "CHUNG CƯ", labelColor = WHITE, labelFace = "Back", noShadow = true })
	cyl(out, "tank", 2.4, 2, 6, h + 0.8, -10.4, STEEL, METAL)
	box(out, "liftRoom", 2.8, 2.2, 2.8, -9, h + 0.8, -10, wall, CONCRETE)
	for k = 0, 2 do
		solar(out, "solarA" .. k, -3 + k * 3.2, h + 0.8, -10.4, 2.8, 1.6)
	end
	-- khối B dọc bên trái
	local fb = floors - 2
	local hb = fb * FLOOR
	local bx, bz, bw, bd = -8.8, 4.2, 7.5, 12.4
	box(out, "slabB", bw, hb, bd, bx, 0, bz, wall, PLASTER)
	ribbons(out, "winB", bw, bd, bx, bz, 0, fb, 1.5, GLASS)
	box(out, "roofB", bw + 0.4, 0.8, bd + 0.4, bx, hb, bz, accent, PLASTIC)
	for f = 1, fb - 1 do
		for k = 0, 2 do
			local pz = bz - 4.4 + k * 4.4
			box(out, "balB" .. f .. k, 1.3, 0.25, 3.4, bx + bw / 2 + 0.65, f * FLOOR - 0.05, pz, FRAME, PLASTIC)
			box(out, "railB" .. f .. k, 0.1, 0.9, 3.4, bx + bw / 2 + 1.25, f * FLOOR + 0.2, pz, rgb(200, 226, 240), GLASSMAT, { transparency = 0.35, noShadow = true })
		end
	end
	box(out, "stripeB", 0.3, hb, 1.2, bx + bw / 2 + 0.15, 0, bz + bd / 2 - 0.6, accent, PLASTIC, { noShadow = true })
	acUnit(out, "acB", bx, hb + 0.8, bz + 3)
	-- sân trong
	box(out, "lawn", 7, 0.12, 5.6, 1.4, 0.1, 1.2, LAWN, GRASSMAT)
	tree(out, "treeA", -0.6, 0.8, 1, 0.22, v)
	tree(out, "treeB", 3.4, 2.2, 0.85, 0.22, v + 0.3)
	bench(out, "bench", 1.4, 4.6, true, 0.1)
	box(out, "playground", 6, 0.15, 6, 8.6, 0.1, 2.6, rgb(240, 120, 80), M.Rubber)
	box(out, "slideTower", 1.4, 1.8, 1.4, 6.8, 0.25, 1, rgb(250, 196, 60), PLASTIC)
	add(out, spec("slide", "Wedge", 1, 1.8, 2.6, 6.8, 0.25, 3, rgb(80, 160, 230), PLASTIC, { rot = 180 }))
	for k, px in ipairs({ 9.4, 11.4 }) do
		cyl(out, "swingPost" .. k, 0.2, 2.6, px, 0.25, 4.4, rgb(250, 196, 60), METAL, { noShadow = true })
	end
	box(out, "swingBar", 2.2, 0.2, 0.2, 10.4, 2.75, 4.4, rgb(250, 196, 60), METAL, { noShadow = true })
	box(out, "swingSeat", 0.8, 0.12, 0.5, 10.4, 1, 4.4, rgb(208, 52, 52), PLASTIC, { noShadow = true })
	person(out, "kidA", 8.4, 4.8, v, 0.25)
	person(out, "kidB", 5.2, 4.6, v + 0.5, 0.1)
	-- bãi đỗ xe phía trước
	box(out, "parking", 16.8, 0.12, 3.9, 4.2, 0.1, 10.9, ASPHALT, M.Asphalt)
	for k = 0, 5 do
		flat(out, "bay" .. k, 0.2, 3.4, -3.3 + k * 3, 0.22, 10.9, WHITE)
	end
	for k, slot in ipairs({ 0, 1, 3, 4 }) do
		car(out, "car" .. k, -1.8 + slot * 3, 10.9, pick(CARS, v + k * 0.21), false, 0.22)
	end
	tree(out, "treeC", -2.8, 7.4, 0.9, 0.1, v + 0.6)
	tree(out, "treeD", 11.2, 7.4, 0.9, 0.1, v + 0.8)
	lamp(out, "lampA", 0.2, 7.6, 0.1)
	lamp(out, "lampB", 8.2, 7.6, 0.1)
	return out
end

-- cửa hàng 2 tầng
BUILDERS.shop = function(v)
	local out = {}
	local wall = pick(WALLS, v + 0.6)
	local red = land("shop", 1)
	local w, d, x, z = 11, 8, 0, -2
	local fz = z + d / 2
	box(out, "forecourt", 12.4, 0.1, 4.1, 0, 0, 4.1, PAVING, PAVE)
	box(out, "base", w + 0.2, 0.5, d + 0.2, x, 0, z, rgb(110, 114, 122), CONCRETE)
	box(out, "store", w, 8.5, d, x, 0, z, wall, PLASTER)
	-- tủ kính trưng bày
	box(out, "bayBase", 7.6, 0.6, 1.1, -1.5, 0, fz + 0.55, DARK, CONCRETE)
	box(out, "bayTop", 7.6, 0.35, 1.1, -1.5, 3.2, fz + 0.55, red, PLASTIC)
	local goods = { rgb(250, 204, 72), rgb(70, 130, 230), rgb(244, 114, 146), rgb(120, 200, 140) }
	for k = 1, 4 do
		box(out, "goods" .. k, 1.2, 0.8 + (k % 2) * 0.6, 0.6, -6.3 + k * 1.9, 0.6, fz + 0.45, goods[k], PLASTIC, { noShadow = true })
	end
	box(out, "bayGlass", 7.4, 2.6, 0.1, -1.5, 0.6, fz + 1.05, rgb(196, 226, 244), GLASSMAT, { transparency = 0.45, reflectance = 0.2, noShadow = true })
	for k = -1, 1, 2 do
		box(out, "bayMullion" .. k, 0.16, 2.6, 0.16, -1.5 + k * 1.25, 0.6, fz + 1.05, DARK, METAL, { noShadow = true })
	end
	door(out, "door", 1, w, d, x, z, 3.9, GLASS_DARK, 1.4, 2.6)
	awning(out, "awning", 11, 0, 3.55, fz, red, 7)
	sign(out, "sign", "SHOP", 1, w, d, x, z, 0, 4.6, 9, 1.3, red, WHITE)
	windowsAll(out, "winUp", w, d, x, z, 5.35, 1, { 3, 2, 3, 2 })
	windowsAll(out, "winSide", w, d, x, z, 0.2, 1, { 0, 2, 0, 0 }, { wh = 1.8 })
	box(out, "cornice", w + 0.4, 0.5, d + 0.4, x, 8.5, z, land("shop", 1, 0.25), PLASTIC)
	box(out, "blade", 0.25, 2.2, 1.4, w / 2 + 0.15, 3.6, fz - 0.9, rgb(250, 196, 60), PLASTIC, { label = "SALE", labelColor = red, labelFace = "Right", noShadow = true })
	acUnit(out, "acA", -3, 9, -3.8)
	acUnit(out, "acB", 0.4, 9, -3.8)
	planter(out, "planterA", -5.2, 3.9, 1.2, 0.1)
	planter(out, "planterB", 5.3, 4.6, 1.2, 0.1)
	bench(out, "bench", -2.8, 5.2, true, 0.1)
	person(out, "shopperA", 1.6, 4.4, v, 0.1)
	person(out, "shopperB", -0.4, 5.3, v + 0.4, 0.1)
	return out
end

-- quán cà phê
BUILDERS.cafe = function(v)
	local out = {}
	local red = land("shop", 1)
	local bx, bz, bw, bd = -1.8, -2.9, 8, 6.6
	box(out, "cafe", bw, 4.4, bd, bx, 0, bz, rgb(176, 98, 74), BRICK)
	gable(out, "roof", bw + 0.6, bd + 0.6, 1.8, bx, 4.4, bz, land("shop", 1, 0.35), "x", SHINGLES)
	panel(out, "windowFrame", 1, bw, bd, bx, bz, -1.4, 0.5, 4.6, 2.5, FRAME, PLASTIC, 0, 0.1)
	panel(out, "window", 1, bw, bd, bx, bz, -1.4, 0.65, 4.3, 2.2, GLASS, GLASSMAT, 0.06, 0.1, { reflectance = 0.25 })
	door(out, "door", 1, bw, bd, bx, bz, 2.6, GLASS_DARK, 1.2, 2.3)
	awning(out, "awning", bw, bx, 2.75, bz + bd / 2, red, 5)
	sign(out, "sign", "CÀ PHÊ", 1, bw, bd, bx, bz, 0, 3.7, 5, 0.7, rgb(250, 240, 220), land("shop", 1, 0.3))
	windowsAll(out, "winSide", bw, bd, bx, bz, 0.2, 1, { 0, 2, 2, 1 }, { wh = 1.6 })
	cyl(out, "flue", 0.5, 1.6, bx - 2.6, 5.2, bz - 1.6, STEEL, METAL)
	-- sàn gỗ ngoài trời
	box(out, "deck", 11.6, 0.2, 5.2, 0, 0, 3.4, DECK, WOODMAT)
	hedge(out, "hedgeL", 2.6, 0.6, -4.5, 5.7, 0.2)
	hedge(out, "hedgeR", 2.6, 0.6, 4.5, 5.7, 0.2)
	for k, p in ipairs({ { -3.6, 4 }, { 0.4, 4.1 }, { 3.9, 2.6 } }) do
		tableSet(out, "table" .. k, p[1], p[2], 0.2)
		umbrella(out, "umbrella" .. k, p[1], p[2], k % 2 == 1 and red or WHITE, 0.2)
	end
	person(out, "guestA", -2.2, 2.2, v, 0.2)
	person(out, "guestB", 2.5, 4.9, v + 0.5, 0.2)
	-- biển hình cốc
	cyl(out, "cupPole", 0.3, 4.6, 5, 0, -4.8, DARK, METAL)
	cyl(out, "saucer", 2.2, 0.15, 5, 4.55, -4.8, WHITE, PLASTIC)
	cyl(out, "cup", 1.6, 1.3, 5, 4.7, -4.8, WHITE, PLASTIC)
	cyl(out, "coffee", 1.35, 0.06, 5, 6, -4.8, rgb(96, 60, 40), PLASTIC, { noShadow = true })
	box(out, "cupHandle", 0.3, 0.8, 0.3, 6, 5, -4.8, WHITE, PLASTIC)
	return out
end

-- siêu thị 2x2
BUILDERS.supermarket = function(v)
	local out = {}
	local red = land("shop", 1)
	local sx, sz, sw, sd = 0, -6.6, 24, 12.5
	box(out, "store", sw, 7, sd, sx, 0, sz, pick(WALLS, v), PLASTER)
	box(out, "base", sw + 0.2, 0.6, sd + 0.2, sx, 0, sz, rgb(110, 114, 122), CONCRETE)
	box(out, "band", sw + 0.3, 1.2, sd + 0.3, sx, 5.6, sz, red, PLASTIC)
	box(out, "parapet", sw + 0.4, 0.4, sd + 0.4, sx, 7, sz, land("shop", 1, 0.3), PLASTIC)
	panel(out, "frontFrame", 1, sw, sd, sx, sz, -4, 0.3, 10.4, 4, DARK, METAL, 0, 0.1)
	panel(out, "front", 1, sw, sd, sx, sz, -4, 0.5, 10, 3.6, GLASS, GLASSMAT, 0.06, 0.1, { reflectance = 0.25 })
	for k = -2, 2 do
		panel(out, "frontMullion" .. k, 1, sw, sd, sx, sz, -4 + k * 2, 0.5, 0.18, 3.6, DARK, METAL, 0.12, 0.12)
	end
	sign(out, "sign", "SIÊU THỊ", 1, sw, sd, sx, sz, 4.5, 4.4, 9, 2.4, WHITE, red, 0.15)
	box(out, "canopy", 12, 0.35, 3, -4, 4.4, 1.15, red, PLASTIC)
	for k, px in ipairs({ -9.5, 1.5 }) do
		cyl(out, "canopyPost" .. k, 0.35, 4.4, px, 0, 2.3, WHITE, METAL)
	end
	windowsAll(out, "winSide", sw, sd, sx, sz, 2.2, 1, { 0, 3, 0, 3 }, { ww = 2.4, wh = 1.6, frame = DARK })
	-- chỗ để xe đẩy
	box(out, "cartRail", 3.6, 0.9, 0.12, 6.6, 0, 0.4, STEEL, METAL, { noShadow = true })
	for k = 0, 2 do
		box(out, "cart" .. k, 0.9, 0.8, 1.3, 5.6 + k * 1, 0.1, 1.2, rgb(208, 52, 52), METAL, { noShadow = true })
	end
	for k = 0, 3 do
		acUnit(out, "ac" .. k, -9 + k * 5, 7.4, -9.5)
	end
	for k = 0, 1 do
		box(out, "skylight" .. k, 3, 0.6, 2, -2 + k * 7, 7.4, -5.2, rgb(200, 226, 240), GLASSMAT, { reflectance = 0.3 })
	end
	-- vỉa hè trước cửa + bãi đỗ xe
	box(out, "walk", 26.2, 0.14, 2.6, 0, 0, 0.9, PAVING, PAVE)
	box(out, "parking", 26.2, 0.12, 10.8, 0, 0, 7.7, ASPHALT, M.Asphalt)
	for row, rz in ipairs({ 5, 11 }) do
		for k = 0, 7 do
			flat(out, "bay" .. row .. k, 0.2, 3.6, -12 + k * 3, 0.12, rz, WHITE)
		end
		for k, slot in ipairs(row == 1 and { 0, 1, 3, 5 } or { 1, 2, 4 }) do
			car(out, "car" .. row .. k, -10.5 + slot * 3, rz, pick(CARS, v + slot * 0.17 + row * 0.3), false, 0.12)
		end
		box(out, "island" .. row, 2.6, 0.3, 3.6, 11.4, 0.12, rz, LAWN, GRASSMAT)
		tree(out, "islandTree" .. row, 11.4, rz, 0.85, 0.42, v + row * 0.3)
	end
	flat(out, "aisleArrow", 0.4, 2, -1, 0.12, 8, WHITE)
	lamp(out, "lampA", -6, 8, 0.12, 5)
	lamp(out, "lampB", 6, 8, 0.12, 5)
	person(out, "shopperA", 3.6, 2.4, v, 0.14)
	person(out, "shopperB", -7, 1.6, v + 0.3, 0.14)
	box(out, "shopperCart", 0.9, 0.8, 1.3, 3.6, 0.14, 3.4, rgb(208, 52, 52), METAL, { noShadow = true })
	return out
end

-- nhà máy
BUILDERS.factory = function(v)
	local out = {}
	local purple = land("factory", 1)
	local hx, hz, hw, hd = -1.6, -1.8, 8.8, 8.4
	box(out, "apron", 12.4, 0.1, 3.8, 0, 0, 4.3, rgb(200, 202, 204), CONCRETE)
	box(out, "hall", hw, 5.2, hd, hx, 0, hz, rgb(220, 222, 228), METAL)
	box(out, "hallBase", hw + 0.2, 1.2, hd + 0.2, hx, 0, hz, rgb(170, 172, 176), CONCRETE)
	ribbons(out, "hallWin", hw, hd, hx, hz, 3.4, 1, 0.9, GLASS_DARK, 1.2)
	sawtooth(out, "roof", hw, hd, 2, hx, 5.2, hz, 3, purple, land("factory", 1, 0.2))
	for k, t in ipairs({ -2.4, 1.2 }) do
		panel(out, "doorFrame" .. k, 1, hw, hd, hx, hz, t, 0, 3.2, 3.4, DARK, METAL, 0, 0.1)
		panel(out, "rollDoor" .. k, 1, hw, hd, hx, hz, t, 0, 2.8, 3.1, STEEL, METAL, 0.06, 0.1)
		panel(out, "doorLine" .. k, 1, hw, hd, hx, hz, t, 1.6, 2.8, 0.1, rgb(150, 154, 162), PLASTIC, 0.12, 0.08)
	end
	-- nhà văn phòng bên phải
	local ox, oz, ow, od = 4.5, -0.1, 3, 5
	box(out, "office", ow, 6, od, ox, 0, oz, rgb(246, 246, 244), PLASTER)
	windowsAll(out, "officeWin", ow, od, ox, oz, 0, 2, { 1, 2, 0, 0 }, { ww = 1.4, wh = 1.3, frame = purple })
	box(out, "officeRoof", ow + 0.3, 0.4, od + 0.3, ox, 6, oz, purple, PLASTIC)
	box(out, "officeSign", 3.2, 0.9, 0.25, ox, 6.4, oz + od / 2 - 0.2, purple, PLASTIC, { label = "NHÀ MÁY", labelColor = WHITE, labelFace = "Back", noShadow = true })
	-- ống khói
	cyl(out, "chimney", 2, 15, 4.4, 0, -4.6, rgb(200, 196, 190), BRICK)
	cyl(out, "chimneyBandA", 2.15, 0.9, 4.4, 10.5, -4.6, purple, PLASTIC)
	cyl(out, "chimneyBandB", 2.15, 0.9, 4.4, 12.6, -4.6, WHITE, PLASTIC)
	cyl(out, "chimneyTop", 2.4, 0.7, 4.4, 15, -4.6, DARK, METAL, { effect = "smoke" })
	-- bồn, hàng, xe nâng
	cyl(out, "tank", 2.6, 3.2, -4.6, 0.1, 4.4, rgb(226, 228, 232), METAL)
	ball(out, "tankDome", 2.6, -4.6, 2, 4.4, rgb(226, 228, 232), METAL)
	box(out, "pipe", 0.4, 0.4, 1.8, -4.6, 2.4, 2.4, purple, METAL)
	box(out, "pallet", 1.8, 0.25, 1.8, 0.6, 0.1, 4.6, WOOD, WOODMAT)
	box(out, "crateA", 1.6, 1.3, 1.6, 0.6, 0.35, 4.6, rgb(196, 150, 96), WOODMAT)
	box(out, "crateB", 1.2, 1, 1.2, 0.7, 1.65, 4.5, rgb(176, 132, 84), WOODMAT)
	box(out, "forklift", 1.2, 1, 1.8, 3.4, 0.35, 4.4, rgb(242, 184, 40), PLASTIC)
	box(out, "forkliftWheels", 1.3, 0.5, 1.4, 3.4, 0.1, 4.4, DARK, PLASTIC)
	box(out, "forkliftRoof", 1.2, 0.15, 1.1, 3.4, 2.4, 4.5, DARK, METAL)
	box(out, "forkliftMast", 1, 2.3, 0.15, 3.4, 0.1, 3.4, DARK, METAL)
	person(out, "worker", 2, 3.2, v, 0.1)
	return out
end

-- xưởng nhỏ
BUILDERS.workshop = function(v)
	local out = {}
	local purple = land("factory", 1)
	local hx, hz, hw, hd = -1.6, -2.3, 8.4, 7.4
	box(out, "apron", 12.4, 0.1, 4.8, 0, 0, 3.8, rgb(200, 202, 204), CONCRETE)
	box(out, "shed", hw, 4.2, hd, hx, 0, hz, rgb(222, 220, 226), METAL)
	box(out, "shedBase", hw + 0.2, 1, hd + 0.2, hx, 0, hz, rgb(170, 172, 176), CONCRETE)
	sawtooth(out, "roof", hw, hd, 1.6, hx, 4.2, hz, 2, purple, land("factory", 1, 0.2))
	panel(out, "doorFrame", 1, hw, hd, hx, hz, -1.6, 0, 3.4, 3.2, DARK, METAL, 0, 0.1)
	panel(out, "rollDoor", 1, hw, hd, hx, hz, -1.6, 0, 3, 2.9, STEEL, METAL, 0.06, 0.1)
	door(out, "sideDoor", 1, hw, hd, hx, hz, 2.4, rgb(90, 96, 110), 1.1, 2.2)
	sign(out, "sign", "XƯỞNG", 1, hw, hd, hx, hz, 2.4, 2.7, 2.6, 0.8, purple, WHITE)
	windowsAll(out, "win", hw, hd, hx, hz, 0.6, 1, { 0, 2, 2, 2 }, { wh = 1.2, frame = purple })
	cyl(out, "chimney", 1.2, 7.5, 4.6, 0, -4.8, rgb(200, 196, 190), BRICK)
	cyl(out, "chimneyTop", 1.4, 0.5, 4.6, 7.5, -4.8, DARK, METAL, { effect = "smoke" })
	for k, p in ipairs({ { -5.2, 2.4 }, { -4.2, 2.6 }, { -5, 3.5 } }) do
		cyl(out, "barrel" .. k, 0.9, 1.2, p[1], 0.1, p[2], rgb(46, 107, 255), METAL)
	end
	box(out, "crateA", 1.4, 1.2, 1.4, -1.6, 0.1, 3.6, rgb(196, 150, 96), WOODMAT)
	box(out, "crateB", 1, 0.9, 1, -1.5, 1.3, 3.6, rgb(176, 132, 84), WOODMAT)
	box(out, "workbench", 2.2, 1, 0.8, 1.2, 0.1, 2.2, WOOD, WOODMAT)
	truck(out, "van", 4.5, 2.6, purple, 0.1, 3)
	person(out, "worker", 0.2, 3.6, v, 0.1)
	return out
end

-- khu nhà máy 2x2
BUILDERS.plant = function(v)
	local out = {}
	local purple = land("factory", 1)
	local hx, hz, hw, hd = -3.3, -7, 18.6, 11.6
	box(out, "yard", 26.2, 0.1, 13, 0, 0, 6.4, rgb(200, 202, 204), CONCRETE)
	box(out, "hall", hw, 7.5, hd, hx, 0, hz, rgb(220, 222, 228), METAL)
	box(out, "hallBase", hw + 0.2, 1.4, hd + 0.2, hx, 0, hz, rgb(170, 172, 176), CONCRETE)
	ribbons(out, "hallWin", hw, hd, hx, hz, 5, 1, 1.2, GLASS_DARK, 1.6)
	sawtooth(out, "roof", hw, hd, 2.4, hx, 7.5, hz, 4, purple, land("factory", 1, 0.2))
	for k, t in ipairs({ -6, -1, 4 }) do
		panel(out, "doorFrame" .. k, 1, hw, hd, hx, hz, t, 0, 3.8, 4.3, DARK, METAL, 0, 0.1)
		panel(out, "rollDoor" .. k, 1, hw, hd, hx, hz, t, 0, 3.4, 4, STEEL, METAL, 0.06, 0.1)
	end
	-- nhà văn phòng 3 tầng
	local ox, oz, ow, od = 9.7, -2.9, 6.2, 6.2
	box(out, "office", ow, 9, od, ox, 0, oz, rgb(246, 246, 244), PLASTER)
	ribbons(out, "officeWin", ow, od, ox, oz, 0, 3, 1.6, GLASS)
	box(out, "officeRoof", ow + 0.3, 0.5, od + 0.3, ox, 9, oz, purple, PLASTIC)
	box(out, "officeSign", 5.4, 1.2, 0.3, ox, 9.5, oz + od / 2 - 0.3, purple, PLASTIC, { label = "NHÀ MÁY", labelColor = WHITE, labelFace = "Back", noShadow = true })
	door(out, "officeDoor", 1, ow, od, ox, oz, 0, GLASS_DARK, 1.8, 2.3)
	-- ống khói
	for k, p in ipairs({ { 8.4, -10.4, 22 }, { 11.6, -9, 18 } }) do
		cyl(out, "chimney" .. k, 2.6, p[3], p[1], 0, p[2], rgb(200, 196, 190), BRICK)
		cyl(out, "chimneyBand" .. k, 2.8, 1.2, p[1], p[3] - 3, p[2], purple, PLASTIC)
		cyl(out, "chimneyTop" .. k, 3, 0.8, p[1], p[3], p[2], DARK, METAL, { effect = "smoke" })
	end
	-- bồn chứa nối ống vào xưởng
	local front = hz + hd / 2
	for k, p in ipairs({ { -9, 6, 5, 5.5 }, { -3.5, 7.6, 4, 4.5 } }) do
		cyl(out, "tank" .. k, p[3], p[4], p[1], 0.1, p[2], rgb(226, 228, 232), METAL)
		ball(out, "tankDome" .. k, p[3], p[1], 0.1 + p[4] - p[3] / 2, p[2], rgb(226, 228, 232), METAL)
		cyl(out, "tankBand" .. k, p[3] + 0.1, 0.5, p[1], 0.1 + p[4] * 0.6, p[2], purple, PLASTIC)
		local back = p[2] - p[3] / 2
		box(out, "pipe" .. k, 0.5, 0.5, back - front, p[1], 3.6, (back + front) / 2, rgb(170, 172, 180), METAL)
	end
	box(out, "pipeRack", 6, 0.5, 0.5, -6.25, 3.6, 0.6, rgb(170, 172, 180), METAL)
	-- công-te-nơ, xe tải
	local containers = { rgb(46, 107, 255), rgb(208, 52, 52), rgb(60, 157, 74) }
	for k = 1, 3 do
		box(out, "container" .. k, 5.6, 2.4, 2.4, 3.4, k == 3 and 2.5 or 0.1, k == 3 and 5.9 or 4.7 + (k - 1) * 2.5, containers[k], METAL)
	end
	truck(out, "truck", 10.4, 6.6, purple, 0.1, 5.5)
	-- hàng rào phía trước, chừa cổng
	fence(out, "fenceL", -13, 12.9, 4, 12.9, 0.1, rgb(150, 154, 162), 2)
	fence(out, "fenceR", 8.4, 12.9, 13, 12.9, 0.1, rgb(150, 154, 162), 2)
	person(out, "workerA", 0, 2.2, v, 0.1)
	person(out, "workerB", 6.8, 9.8, v + 0.5, 0.1)
	return out
end

-- văn phòng, tháp đặt trên sảnh
BUILDERS.office = function(v)
	local out = {}
	local floors = 6 + math.floor(v * 4)
	local blue = land("office", 1)
	box(out, "plaza", 12.4, 0.1, 12.4, 0, 0, 0, PAVING, PAVE)
	local px, pz, pw, pd = -0.5, -1.6, 9, 8.4
	box(out, "lobby", pw, 4, pd, px, 0, pz, FRAME, CONCRETE)
	box(out, "lobbyGlass", pw + 0.2, 3, pd + 0.2, px, 0.2, pz, rgb(150, 200, 226), GLASSMAT, { reflectance = 0.25, noShadow = true })
	box(out, "lobbyCap", pw + 0.4, 0.6, pd + 0.4, px, 3.6, pz, FRAME, CONCRETE)
	local tx, tz, tw, td = -1, -2.2, 7, 7
	local ty = 4.2
	local th = floors * FLOOR
	box(out, "tower", tw, th, td, tx, ty, tz, FRAME, CONCRETE)
	ribbons(out, "win", tw, td, tx, tz, ty, floors, 2.2, land("office", 0.55))
	mullions(out, "mull", tw, td, tx, tz, ty, th, 2, FRAME)
	box(out, "fin", 0.6, th + 1, 0.6, tx + tw / 2, ty, tz + td / 2, blue, PLASTIC)
	local top = ty + th
	box(out, "crownGlass", 5.4, 2.4, 5.4, tx, top, tz, land("office", 0.8), GLASSMAT, { reflectance = 0.25 })
	box(out, "crownBand", 7.4, 0.6, 7.4, tx, top - 0.3, tz, blue, PLASTIC)
	box(out, "roofGarden", 5.8, 0.25, 5.8, tx, top + 2.4, tz, LAWN, GRASSMAT)
	bush(out, "roofBushA", tx - 1.6, tz - 1.4, 1, top + 2.6)
	bush(out, "roofBushB", tx + 1.4, tz + 1.2, 0.9, top + 2.6)
	cyl(out, "antenna", 0.3, 5, tx + 2, top + 2.6, tz - 2, WHITE, METAL, { noShadow = true })
	ball(out, "beacon", 0.6, tx + 2, top + 7.4, tz - 2, rgb(255, 80, 80), M.Neon, { noShadow = true })
	box(out, "sign", 5, 0.9, 0.25, px, 4.2, pz + pd / 2 - 0.35, blue, PLASTIC, { label = "VĂN PHÒNG", labelColor = WHITE, labelFace = "Back", noShadow = true })
	box(out, "canopy", 3.6, 0.25, 1.8, px, 3, pz + pd / 2 + 0.9, blue, PLASTIC)
	cyl(out, "revolvingDoor", 1.7, 2.5, px, 0, pz + pd / 2 + 0.2, rgb(150, 200, 226), GLASSMAT, { transparency = 0.2, reflectance = 0.3 })
	planter(out, "planterA", -5.2, 4.7, 1.4, 0.1)
	tree(out, "treeA", -5.2, 4.7, 0.6, 0.8, v)
	planter(out, "planterB", 4.6, 4.9, 1.4, 0.1)
	tree(out, "treeB", 4.6, 4.9, 0.6, 0.8, v + 0.4)
	bench(out, "bench", 1.6, 5.4, true, 0.1)
	person(out, "workerA", -2.4, 4.4, v, 0.1)
	person(out, "workerB", 2.8, 3.8, v + 0.6, 0.1)
	return out
end

-- văn phòng nhỏ 3-4 tầng
BUILDERS.office_small = function(v)
	local out = {}
	local floors = 3 + math.floor(v * 2)
	local blue = land("office", 1)
	local bx, bz, bw, bd = -0.8, -1.9, 8.4, 7.8
	local h = floors * FLOOR
	box(out, "plaza", 12.4, 0.1, 4, 0, 0, 4.2, PAVING, PAVE)
	box(out, "block", bw, h, bd, bx, 0, bz, rgb(176, 108, 86), BRICK)
	windowsAll(out, "win", bw, bd, bx, bz, 0, floors, { 3, 2, 3, 2 }, {
		ww = 1.5,
		wh = 1.6,
		frame = rgb(56, 60, 68),
		glass = land("office", 0.55),
		skip = function(face, f, k)
			return face == 1 and f == 0 and k == 2
		end,
	})
	door(out, "door", 1, bw, bd, bx, bz, 0, GLASS_DARK, 1.6, 2.3)
	box(out, "canopy", 3.6, 0.6, 1.8, bx, 2.5, bz + bd / 2 + 0.9, blue, PLASTIC, { label = "VĂN PHÒNG", labelColor = WHITE, labelFace = "Back" })
	box(out, "stripe", 0.9, h + 0.6, 0.9, bx + bw / 2, 0, bz + bd / 2, blue, PLASTIC)
	box(out, "cornice", bw + 0.4, 0.6, bd + 0.4, bx, h, bz, rgb(70, 74, 82), CONCRETE)
	solar(out, "solarA", bx - 1.8, h + 0.6, bz - 1, 3, 1.8)
	solar(out, "solarB", bx + 1.6, h + 0.6, bz - 1, 3, 1.8)
	acUnit(out, "ac", bx, h + 0.6, bz + 2.2)
	tree(out, "tree", 4.6, 4.6, 0.8, 0.1, v)
	car(out, "car", -3.4, 4.9, pick(CARS, v + 0.3), true, 0.1)
	for k = 0, 2 do
		box(out, "bikeRack" .. k, 0.12, 0.8, 1, 1.4 + k * 0.6, 0.1, 4.6, DARK, METAL, { noShadow = true })
	end
	person(out, "worker", 0.6, 3.4, v, 0.1)
	return out
end

-- tháp văn phòng 2x2
BUILDERS.tower = function(v)
	local out = {}
	local floors = 14 + math.floor(v * 4)
	local blue = land("office", 1)
	box(out, "plaza", 26.2, 0.1, 26.2, 0, 0, 0, PAVING, PAVE)
	-- khối đế
	box(out, "podium", 24, 5, 16, 0, 0, -4, FRAME, CONCRETE)
	box(out, "podiumGlass", 24.2, 3.6, 16.2, 0, 0.4, -4, rgb(150, 200, 226), GLASSMAT, { reflectance = 0.25, noShadow = true })
	box(out, "podiumCap", 24.4, 0.8, 16.4, 0, 4.6, -4, FRAME, CONCRETE)
	box(out, "podiumGarden", 7, 0.25, 5, 7.6, 5.4, 0.6, LAWN, GRASSMAT)
	bush(out, "podiumBushA", 6, 0.2, 1.2, 5.6)
	bush(out, "podiumBushB", 9.2, 1.4, 1, 5.6)
	local tx, tz, tw, td = -3, -5.8, 12.5, 12
	local ty = 5.4
	local th = floors * FLOOR
	box(out, "tower", tw, th, td, tx, ty, tz, FRAME, CONCRETE)
	ribbons(out, "win", tw, td, tx, tz, ty, floors, 2.2, land("office", 0.5))
	mullions(out, "mull", tw, td, tx, tz, ty, th, 3, FRAME)
	for k, c in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
		box(out, "fin" .. k, 0.7, th + 1.2, 0.7, tx + c[1] * tw / 2, ty, tz + c[2] * td / 2, blue, PLASTIC)
	end
	local top = ty + th
	box(out, "setback", 9, 6, 9, tx, top, tz, land("office", 0.7), GLASSMAT, { reflectance = 0.25 })
	mullions(out, "setMull", 9, 9, tx, tz, top, 6, 2, FRAME)
	box(out, "crownBand", 9.6, 0.8, 9.6, tx, top + 6, tz, blue, PLASTIC)
	box(out, "crown", 6, 3, 6, tx, top + 6.8, tz, FRAME, CONCRETE)
	cyl(out, "spire", 0.6, 10, tx, top + 9.8, tz, WHITE, METAL, { noShadow = true })
	ball(out, "beacon", 0.9, tx, top + 19.6, tz, rgb(255, 80, 80), M.Neon, { noShadow = true })
	box(out, "sign", 12, 1.6, 0.3, 0, 5.4, 3.7, blue, PLASTIC, { label = "ECON TOWER", labelColor = WHITE, labelFace = "Back", noShadow = true })
	box(out, "canopy", 8, 0.4, 3, -3, 3.4, 5.5, blue, PLASTIC)
	for k, px in ipairs({ -6.6, 0.6 }) do
		cyl(out, "canopyPost" .. k, 0.4, 3.4, px, 0, 6.6, WHITE, METAL)
	end
	cyl(out, "revolvingDoor", 2.2, 2.8, -3, 0, 4.1, rgb(150, 200, 226), GLASSMAT, { transparency = 0.2, reflectance = 0.3 })
	-- quảng trường
	fountain(out, "fountain", 6, 8.8, 5.4, 0.1)
	for k, p in ipairs({ { -10, 9 }, { -4.5, 11.6 }, { 11.4, 11.6 } }) do
		cyl(out, "treeRing" .. k, 2.6, 0.5, p[1], 0.1, p[2], STONE, CONCRETE)
		tree(out, "tree" .. k, p[1], p[2], 0.9, 0.6, v + k * 0.3)
	end
	bench(out, "benchA", 1, 10.6, true, 0.1)
	bench(out, "benchB", 11.6, 6.4, false, 0.1)
	local flags = { blue, rgb(208, 52, 52), rgb(60, 157, 74) }
	for k = 0, 2 do
		local fx = 9.6 + k * 1.4
		cyl(out, "flagPole" .. k, 0.2, 7, fx, 0.1, 4.6, WHITE, METAL, { noShadow = true })
		box(out, "flag" .. k, 0.1, 1, 1.6, fx, 5.9, 5.45, flags[k + 1], PLASTIC, { noShadow = true })
	end
	lamp(out, "lampA", -8, 6.6, 0.1, 5)
	lamp(out, "lampB", 3, 12.4, 0.1, 5)
	person(out, "walkerA", -1, 8, v, 0.1)
	person(out, "walkerB", 3.4, 7, v + 0.3, 0.1)
	person(out, "walkerC", -7, 11, v + 0.6, 0.1)
	return out
end

-- bệnh viện 4 tầng
BUILDERS.hospital = function(v)
	local out = {}
	local accent = land("hospital", 1)
	local h = 4 * FLOOR
	local mx, mz, mw, md = 0, -2.4, 11.6, 7.6
	local front = mz + md / 2
	box(out, "plaza", 12.4, 0.1, 4.6, 0, 0, 3.9, PAVING, PAVE)
	box(out, "main", mw, h, md, mx, 0, mz, rgb(246, 248, 250), PLASTER)
	ribbons(out, "win", mw, md, mx, mz, 0, 4, 1.4, rgb(176, 214, 236))
	box(out, "stripe", 1.6, h, 0.3, mx - mw / 2 + 0.8, 0, front + 0.15, accent, PLASTIC, { noShadow = true })
	box(out, "parapet", mw + 0.3, 0.8, md + 0.3, mx, h, mz, accent, PLASTIC)
	box(out, "sign", 7, 1.2, 0.3, 0.6, h + 0.8, front - 0.3, accent, PLASTIC, { label = "BỆNH VIỆN", labelColor = WHITE, labelFace = "Back", noShadow = true })
	-- chữ thập trên mặt tiền
	box(out, "crossBoard", 3, 3, 0.25, 3.8, 6.6, front + 0.25, WHITE, PLASTIC, { noShadow = true })
	box(out, "crossV", 0.9, 2.4, 0.2, 3.8, 6.9, front + 0.45, accent, PLASTIC, { noShadow = true })
	box(out, "crossH", 2.4, 0.9, 0.2, 3.8, 7.65, front + 0.45, accent, PLASTIC, { noShadow = true })
	-- sân đỗ trực thăng
	cyl(out, "helipad", 6, 0.2, -1.5, h + 0.8, -2.8, rgb(90, 94, 102), CONCRETE)
	cyl(out, "helipadRing", 5.2, 0.05, -1.5, h + 1, -2.8, WHITE, PLASTIC, { noShadow = true })
	cyl(out, "helipadInner", 4.6, 0.06, -1.5, h + 1, -2.8, rgb(90, 94, 102), CONCRETE, { noShadow = true })
	box(out, "heliH1", 0.5, 0.08, 2.6, -2.5, h + 1, -2.8, WHITE, PLASTIC, { noShadow = true })
	box(out, "heliH2", 0.5, 0.08, 2.6, -0.5, h + 1, -2.8, WHITE, PLASTIC, { noShadow = true })
	box(out, "heliH3", 1.8, 0.08, 0.5, -1.5, h + 1, -2.8, WHITE, PLASTIC, { noShadow = true })
	acUnit(out, "acA", 3.6, h + 0.8, -4.4)
	acUnit(out, "acB", 3.6, h + 0.8, -2.2)
	-- lối vào cấp cứu
	box(out, "canopy", 5, 0.6, 2.8, -2.4, 3, front + 1.4, accent, PLASTIC, { label = "CẤP CỨU", labelColor = WHITE, labelFace = "Back" })
	for k, px in ipairs({ -4.6, -0.2 }) do
		cyl(out, "canopyPost" .. k, 0.3, 3, px, 0, front + 2.5, WHITE, METAL)
	end
	box(out, "entrance", 3, 2.4, 0.12, -2.4, 0, front + 0.06, GLASS_DARK, GLASSMAT, { noShadow = true })
	-- xe cứu thương
	box(out, "ambulanceWheels", 1.95, 0.7, 3.2, 3.6, 0.1, 4, DARK, PLASTIC)
	box(out, "ambulance", 1.9, 1.7, 3.8, 3.6, 0.5, 4, WHITE, PLASTIC)
	box(out, "ambulanceStripe", 1.95, 0.35, 3.85, 3.6, 1.1, 4, accent, PLASTIC, { noShadow = true })
	box(out, "ambulanceGlass", 1.6, 0.6, 0.1, 3.6, 1.4, 5.92, GLASS_DARK, GLASSMAT, { noShadow = true })
	box(out, "ambulanceCrossV", 0.1, 0.8, 0.3, 4.58, 1.5, 3.4, accent, PLASTIC, { noShadow = true })
	box(out, "ambulanceCrossH", 0.1, 0.3, 0.8, 4.58, 1.75, 3.4, accent, PLASTIC, { noShadow = true })
	ball(out, "sirenBlue", 0.4, 3.2, 2.2, 5.2, rgb(70, 140, 255), M.Neon, { noShadow = true })
	ball(out, "sirenRed", 0.4, 4, 2.2, 5.2, rgb(255, 70, 70), M.Neon, { noShadow = true })
	-- vườn
	tree(out, "tree", -5.1, 4.8, 0.7, 0.1, v)
	bench(out, "bench", -2.6, 5.4, true, 0.1)
	person(out, "doctor", -0.6, 4.2, 0.9, 0.1)
	person(out, "visitor", -2.8, 4.6, v, 0.1)
	return out
end

-- trạm y tế
BUILDERS.clinic = function(v)
	local out = {}
	local accent = land("hospital", 1)
	local h = 2 * FLOOR
	local bx, bz, bw, bd = -1, -2.6, 8.4, 6.4
	box(out, "plaza", 12.4, 0.1, 5.6, 0, 0, 3.4, PAVING, PAVE)
	box(out, "clinic", bw, h, bd, bx, 0, bz, rgb(246, 248, 250), PLASTER)
	windowsAll(out, "win", bw, bd, bx, bz, 0, 2, { 3, 2, 3, 2 }, {
		frame = land("hospital", 0.35),
		skip = function(face, f, k)
			return face == 1 and f == 0 and k == 2
		end,
	})
	box(out, "trim", bw + 0.3, 0.6, bd + 0.3, bx, h, bz, accent, PLASTIC)
	box(out, "crossV", 0.8, 2.6, 0.4, bx, h + 0.6, bz + bd / 2 - 0.6, accent, PLASTIC)
	box(out, "crossH", 2.6, 0.8, 0.4, bx, h + 1.5, bz + bd / 2 - 0.6, accent, PLASTIC)
	door(out, "door", 1, bw, bd, bx, bz, 0, GLASS_DARK, 1.6, 2.3)
	box(out, "canopy", 3.8, 0.6, 1.6, bx, 2.55, bz + bd / 2 + 0.8, accent, PLASTIC, { label = "TRẠM Y TẾ", labelColor = WHITE, labelFace = "Back" })
	box(out, "step", 2, 0.3, 0.8, bx, 0.1, bz + bd / 2 + 0.4, STONE, CONCRETE)
	add(out, spec("ramp", "Wedge", 1.2, 0.4, 2.6, bx + 2.1, 0.1, bz + bd / 2 + 1.3, STONE, CONCRETE, { rot = 180 }))
	bench(out, "bench", 3.8, 4.6, true, 0.1)
	tree(out, "tree", -4.6, 4.4, 0.8, 0.1, v)
	flowers(out, "flowers", 1.4, 5.4, 2.6, 0.8, 0.1)
	acUnit(out, "ac", bx - 2, h + 0.6, bz - 1.4)
	person(out, "nurse", 2.6, 2.8, 0.9, 0.1)
	person(out, "patient", 3.2, 5.6, v, 0.1)
	return out
end

-- trường học 2 tầng
BUILDERS.school = function(v)
	local out = {}
	local orange = land("school", 1)
	local fh = 3.3
	local h = 2 * fh + 0.4
	local bx, bz, bw, bd = 0, -3.2, 12, 5.6
	local front = bz + bd / 2
	box(out, "yard", 12.4, 0.1, 6.6, 0, 0, 2.9, rgb(206, 208, 210), PAVE)
	box(out, "school", bw, h, bd, bx, 0, bz, rgb(206, 120, 88), BRICK)
	box(out, "plinth", bw + 0.2, 0.5, bd + 0.2, bx, 0, bz, STONE, CONCRETE)
	box(out, "floorTrim", bw + 0.16, 0.25, bd + 0.16, bx, fh + 0.2, bz, FRAME, PLASTIC, { noShadow = true })
	gable(out, "roof", bw + 0.4, bd + 1, 2.2, bx, h, bz, land("school", 1, 0.2), "x")
	windowsAll(out, "win", bw, bd, bx, bz, 0.4, 2, { 4, 1, 4, 1 }, {
		ww = 1,
		wh = 1.6,
		floorH = fh,
		glass = rgb(220, 236, 248),
		skip = function(face, f, k)
			return face == 1 and f == 0 and (k == 2 or k == 3)
		end,
	})
	door(out, "door", 1, bw, bd, bx, bz, 0, WOOD, 1.8, 2.5)
	box(out, "porch", 3.6, 0.6, 1.8, bx, 3, front + 0.9, orange, PLASTIC, { label = "TRƯỜNG HỌC", labelColor = WHITE, labelFace = "Back" })
	for k, px in ipairs({ -1.5, 1.5 }) do
		cyl(out, "column" .. k, 0.4, 3, px, 0, front + 1.5, WHITE, CONCRETE)
	end
	box(out, "steps", 3, 0.3, 1.4, bx, 0, front + 0.7, STONE, CONCRETE)
	-- tháp đồng hồ trên nóc
	box(out, "clockTower", 1.8, 3.6, 1.8, bx, h, bz, rgb(246, 240, 228), PLASTER)
	box(out, "clockFrame", 1.4, 1.4, 0.12, bx, h + 1.9, bz + 0.96, DARK, PLASTIC, { noShadow = true })
	box(out, "clockFace", 1.2, 1.2, 0.12, bx, h + 2, bz + 1.02, WHITE, PLASTIC, { noShadow = true })
	box(out, "clockHandA", 0.1, 0.5, 0.06, bx, h + 2.6, bz + 1.1, DARK, PLASTIC, { noShadow = true })
	box(out, "clockHandB", 0.4, 0.1, 0.06, bx + 0.2, h + 2.55, bz + 1.1, DARK, PLASTIC, { noShadow = true })
	gable(out, "clockRoof", 2.2, 2.2, 1.2, bx, h + 3.6, bz, land("school", 1, 0.2), "x")
	-- sân bóng rổ
	box(out, "court", 6.2, 0.12, 4.4, 2.8, 0.1, 3.4, land("school", 0.6), M.Rubber)
	flat(out, "courtLine", 0.15, 4.4, 2.8, 0.22, 3.4, WHITE)
	cyl(out, "courtCircle", 1.6, 0.06, 2.8, 0.2, 3.4, WHITE, PLASTIC, { noShadow = true, noCollide = true })
	cyl(out, "courtCircleIn", 1.3, 0.07, 2.8, 0.2, 3.4, land("school", 0.6), M.Rubber, { noShadow = true, noCollide = true })
	cyl(out, "hoopPole", 0.25, 3.2, 6, 0.1, 3.4, DARK, METAL, { noShadow = true })
	box(out, "backboard", 0.15, 1.1, 1.7, 5.75, 2.8, 3.4, WHITE, PLASTIC)
	box(out, "rim", 0.6, 0.08, 0.6, 5.35, 2.95, 3.4, rgb(240, 120, 40), METAL, { noShadow = true })
	flagpole(out, "flag", -5.5, 5.4, 7, 0.1)
	tree(out, "tree", -3.8, 2.4, 0.8, 0.1, v)
	person(out, "kidA", 1.2, 2.6, v, 0.1)
	person(out, "kidB", 4, 4.6, v + 0.3, 0.1)
	person(out, "kidC", -1.8, 4.8, v + 0.6, 0.1)
	return out
end

-- trường lớn 2x2
BUILDERS.school_big = function(v)
	local out = {}
	local orange = land("school", 1)
	local brick = rgb(206, 120, 88)
	local fh = 3.3
	local mx, mz, mw, md = 0, -9.6, 25.6, 6.6
	local mh = 3 * fh
	local front = mz + md / 2
	box(out, "yard", 26.2, 0.1, 19.4, 0, 0, 3.5, rgb(206, 208, 210), PAVE)
	box(out, "main", mw, mh, md, mx, 0, mz, brick, BRICK)
	box(out, "mainPlinth", mw + 0.2, 0.5, md + 0.2, mx, 0, mz, STONE, CONCRETE)
	gable(out, "roofMain", mw + 0.8, md + 1, 2.6, mx, mh, mz, land("school", 1, 0.2), "x")
	windowsAll(out, "winMain", mw, md, mx, mz, 0.4, 3, { 8, 0, 0, 0 }, {
		ww = 1.1,
		wh = 1.6,
		floorH = fh,
		glass = rgb(220, 236, 248),
		skip = function(face, f, k)
			return f == 0 and k == 6
		end,
	})
	windowsAll(out, "winMainBack", mw, md, mx, mz, 0.4, 3, { 0, 2, 6, 2 }, { wh = 1.6, floorH = fh, frame = false, glass = rgb(200, 222, 240) })
	door(out, "door", 1, mw, md, mx, mz, 4.8, WOOD, 2.2, 2.6)
	box(out, "porch", 4.6, 0.7, 2, 4.8, 3.1, front + 1, orange, PLASTIC, { label = "TRƯỜNG HỌC", labelColor = WHITE, labelFace = "Back" })
	for k, px in ipairs({ 3, 6.6 }) do
		cyl(out, "column" .. k, 0.4, 3.1, px, 0, front + 1.7, WHITE, CONCRETE)
	end
	box(out, "clockTower", 2.4, 4.2, 2.4, mx, mh, mz, rgb(246, 240, 228), PLASTER)
	box(out, "clockFrame", 1.8, 1.8, 0.12, mx, mh + 2.1, mz + 1.26, DARK, PLASTIC, { noShadow = true })
	box(out, "clockFace", 1.5, 1.5, 0.12, mx, mh + 2.25, mz + 1.32, WHITE, PLASTIC, { noShadow = true })
	box(out, "clockHand", 0.12, 0.6, 0.06, mx, mh + 3, mz + 1.4, DARK, PLASTIC, { noShadow = true })
	gable(out, "clockRoof", 2.8, 2.8, 1.4, mx, mh + 4.2, mz, land("school", 1, 0.2), "x")
	-- cánh nhà bên trái
	local wx, wz, ww, wd = -9.3, -0.8, 6.6, 11.2
	box(out, "wing", ww, 2 * fh, wd, wx, 0, wz, brick, BRICK)
	gable(out, "roofWing", ww + 0.8, wd + 0.6, 2.2, wx, 2 * fh, wz, land("school", 1, 0.3), "z")
	windowsAll(out, "winWing", ww, wd, wx, wz, 0.4, 2, { 2, 4, 0, 0 }, { ww = 1.1, wh = 1.6, floorH = fh, glass = rgb(220, 236, 248) })
	-- sân bóng + đường chạy
	local fx, fz = 4.4, 3.2
	box(out, "track", 16.4, 0.12, 14, fx, 0.1, fz, rgb(214, 96, 72), M.Rubber)
	box(out, "field", 13.6, 0.14, 11.2, fx, 0.12, fz, rgb(112, 178, 92), GRASSMAT)
	flat(out, "midLine", 0.2, 11.2, fx, 0.27, fz, WHITE)
	cyl(out, "centerCircle", 3.2, 0.05, fx, 0.26, fz, WHITE, PLASTIC, { noShadow = true, noCollide = true })
	cyl(out, "centerCircleIn", 2.8, 0.06, fx, 0.26, fz, rgb(112, 178, 92), GRASSMAT, { noShadow = true, noCollide = true })
	for k, gx in ipairs({ fx - 6.4, fx + 6.4 }) do
		box(out, "goal" .. k, 0.3, 1.6, 3, gx, 0.26, fz, WHITE, METAL)
	end
	-- khán đài
	for k = 0, 2 do
		box(out, "bleacher" .. k, 10, 0.5 + k * 0.5, 2.2 - k * 0.7, fx, 0.1, 11.6 + k * 0.35, k % 2 == 0 and rgb(200, 204, 210) or land("school", 0.6), CONCRETE)
	end
	person(out, "fanA", fx - 2, 11.2, v, 0.6)
	person(out, "fanB", fx + 1.5, 11.6, v + 0.4, 1.1)
	person(out, "playerA", fx - 2.6, 2, v + 0.2, 0.26)
	person(out, "playerB", fx + 2.4, 4.6, v + 0.7, 0.26)
	-- xe buýt trường
	box(out, "busWheels", 7.6, 0.8, 2.3, -8.4, 0.1, 9.6, DARK, PLASTIC)
	box(out, "bus", 7.6, 2.4, 2.4, -8.4, 0.6, 9.6, rgb(250, 196, 40), PLASTIC)
	box(out, "busWindows", 6.4, 0.8, 2.5, -8.6, 1.9, 9.6, GLASS_DARK, GLASSMAT, { noShadow = true })
	box(out, "busStripe", 7.7, 0.2, 2.5, -8.4, 1.3, 9.6, DARK, PLASTIC, { noShadow = true })
	flagpole(out, "flag", -12, 12.2, 9, 0.1)
	tree(out, "treeA", -11.4, 6.4, 0.9, 0.1, v)
	tree(out, "treeB", 11.2, -4.6, 0.9, 0.1, v + 0.5)
	return out
end

-- công viên
BUILDERS.park = function(v)
	local out = {}
	box(out, "lawn", 12.4, 0.3, 12.4, 0, 0, 0, rgb(116, 184, 92), GRASSMAT)
	for k, r in ipairs({ 45, -45 }) do
		box(out, "path" .. k, 15.4, 0.06, 1.6, 0, 0.3, 0, STONE, PAVE, { rot = r, noShadow = true })
	end
	cyl(out, "plaza", 4.4, 0.08, 0, 0.3, 0, STONE, PAVE, { noShadow = true })
	fountain(out, "fountain", 0, 0, 3.2, 0.38)
	cyl(out, "pondEdge", 3.6, 0.3, 0, 0.3, -4.1, STONE, M.Cobblestone)
	cyl(out, "pond", 3, 0.32, 0, 0.3, -4.1, WATER, GLASSMAT, { transparency = 0.1, reflectance = 0.35 })
	cyl(out, "lilyA", 0.7, 0.04, -0.6, 0.62, -4.4, rgb(84, 160, 72), PLASTIC, { noShadow = true })
	cyl(out, "lilyB", 0.6, 0.04, 0.6, 0.62, -3.7, rgb(84, 160, 72), PLASTIC, { noShadow = true })
	tree(out, "treeA", 4.2, 0, 0.95, 0.3, v)
	tree(out, "treeB", -4.2, 1.4, 0.9, 0.3, v + 0.3)
	pine(out, "pine", -4.4, -2.2, 0.9, 0.3)
	flowers(out, "flowersA", 0, 4.4, 2.8, 0.8, 0.3)
	flowers(out, "flowersB", 5, -2.6, 1.6, 0.7, 0.3)
	bench(out, "benchA", 0, 2.8, true, 0.3)
	bench(out, "benchB", -2.8, 0, false, 0.3)
	lamp(out, "lampA", 2.9, 1.4, 0.3)
	lamp(out, "lampB", 1.6, -2.9, 0.3)
	person(out, "walkerA", 1.6, 4.4, v, 0.3)
	person(out, "walkerB", -1.6, -2.4, v + 0.5, 0.3)
	return out
end

-- công viên lớn 2x2
BUILDERS.park_big = function(v)
	local out = {}
	local green = land("park", 1, 0.25)
	box(out, "lawn", 26.4, 0.3, 26.4, 0, 0, 0, rgb(116, 184, 92), GRASSMAT)
	box(out, "pathX", 26.4, 0.06, 2, 0, 0.3, 0, STONE, PAVE, { noShadow = true })
	box(out, "pathZ", 2, 0.06, 26.4, 0, 0.3, 0, STONE, PAVE, { noShadow = true })
	cyl(out, "plaza", 8.4, 0.08, 0, 0.3, 0, STONE, PAVE, { noShadow = true })
	fountain(out, "fountain", 0, 0, 5.2, 0.38)
	for k, p in ipairs({ { 3.4, 3.4 }, { -3.4, 3.4 }, { 3.4, -3.4 }, { -3.4, -3.4 } }) do
		flowers(out, "flowers" .. k, p[1], p[2], 2.6, 0.9, 0.3)
	end
	-- hồ
	cyl(out, "lakeEdge", 10.5, 0.3, -6.6, 0.3, -6.6, rgb(222, 206, 160), M.Sand)
	cyl(out, "lake", 9.4, 0.32, -6.6, 0.3, -6.6, WATER, GLASSMAT, { transparency = 0.1, reflectance = 0.35 })
	box(out, "bridge", 1.8, 0.4, 9.6, -6.6, 0.6, -6.6, DECK, WOODMAT)
	for k, s in ipairs({ -1, 1 }) do
		box(out, "bridgeRail" .. k, 0.15, 0.7, 9.6, -6.6 + s * 0.85, 1, -6.6, WOOD, WOODMAT, { noShadow = true })
	end
	for k, p in ipairs({ { -9, -5.2 }, { -4.4, -8.8 } }) do
		ball(out, "duck" .. k, 0.6, p[1], 0.55, p[2], WHITE, PLASTIC, { noShadow = true })
		ball(out, "duckHead" .. k, 0.35, p[1] + 0.3, 0.95, p[2], WHITE, PLASTIC, { noShadow = true })
		box(out, "duckBeak" .. k, 0.2, 0.1, 0.12, p[1] + 0.52, 1.05, p[2], rgb(250, 170, 40), PLASTIC, { noShadow = true })
	end
	-- chòi nghỉ
	local gx, gz = 7, -7
	cyl(out, "gazeboFloor", 5, 0.4, gx, 0.3, gz, DECK, WOODMAT)
	for k, c in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
		cyl(out, "gazeboPost" .. k, 0.3, 2.8, gx + c[1] * 1.6, 0.7, gz + c[2] * 1.6, WHITE, WOODMAT)
	end
	cyl(out, "gazeboRoofA", 5.8, 0.4, gx, 3.5, gz, green, PLASTIC)
	cyl(out, "gazeboRoofB", 4, 0.5, gx, 3.9, gz, green, PLASTIC)
	cyl(out, "gazeboRoofC", 2.2, 0.5, gx, 4.4, gz, green, PLASTIC)
	ball(out, "gazeboTop", 0.6, gx, 4.8, gz, WHITE, PLASTIC)
	-- sân chơi
	local px, pz = 7.5, 7.5
	box(out, "playground", 7, 0.2, 7, px, 0.3, pz, rgb(240, 120, 80), M.Rubber)
	box(out, "slideTower", 1.6, 2.2, 1.6, px - 2, 0.5, pz - 2, rgb(250, 196, 60), PLASTIC)
	box(out, "slideRoof", 2, 0.3, 2, px - 2, 3.4, pz - 2, rgb(46, 107, 255), PLASTIC)
	for k, c in ipairs({ { 1, 1 }, { -1, -1 } }) do
		cyl(out, "slidePost" .. k, 0.18, 1, px - 2 + c[1] * 0.8, 2.7, pz - 2 + c[2] * 0.8, rgb(250, 196, 60), METAL, { noShadow = true })
	end
	add(out, spec("slide", "Wedge", 1, 2.2, 3, px - 2, 0.5, pz + 0.3, rgb(80, 160, 230), PLASTIC, { rot = 180 }))
	for k, sx in ipairs({ px + 1, px + 3.4 }) do
		cyl(out, "swingPost" .. k, 0.22, 2.8, sx, 0.5, pz - 1.6, rgb(250, 196, 60), METAL, { noShadow = true })
	end
	box(out, "swingBar", 2.6, 0.22, 0.22, px + 2.2, 3.2, pz - 1.6, rgb(250, 196, 60), METAL, { noShadow = true })
	for k, sx in ipairs({ px + 1.6, px + 2.8 }) do
		box(out, "swingSeat" .. k, 0.7, 0.12, 0.5, sx, 1.2, pz - 1.6, rgb(208, 52, 52), PLASTIC, { noShadow = true })
		box(out, "swingRope" .. k, 0.06, 2, 0.06, sx, 1.3, pz - 1.6, DARK, PLASTIC, { noShadow = true })
	end
	box(out, "sandbox", 2.8, 0.4, 2.8, px + 2, 0.5, pz + 2, WOOD, WOODMAT)
	box(out, "sand", 2.4, 0.42, 2.4, px + 2, 0.5, pz + 2, rgb(236, 214, 160), M.Sand)
	person(out, "kidA", px - 0.4, pz + 1, v, 0.5)
	person(out, "kidB", px + 2.2, pz - 0.6, v + 0.4, 0.5)
	-- khu dã ngoại
	for k, p in ipairs({ { -8.6, 6.4 }, { -5, 9.4 } }) do
		box(out, "picnicTop" .. k, 2.6, 0.2, 1.4, p[1], 1.1, p[2], DECK, WOODMAT)
		box(out, "picnicLeg" .. k, 2.2, 0.8, 0.3, p[1], 0.3, p[2], WOOD, WOODMAT)
		box(out, "picnicSeatA" .. k, 2.6, 0.2, 0.5, p[1], 0.7, p[2] - 1, DECK, WOODMAT)
		box(out, "picnicSeatB" .. k, 2.6, 0.2, 0.5, p[1], 0.7, p[2] + 1, DECK, WOODMAT)
	end
	box(out, "blanket", 2.4, 0.06, 2, -9.4, 0.3, 10.4, rgb(208, 52, 52), PLASTIC, { noShadow = true })
	person(out, "picnicA", -8.6, 4.8, v + 0.2, 0.3)
	person(out, "picnicB", -5, 11, v + 0.7, 0.3)
	-- cây quanh rìa
	local trees = { { -3, -11, 1 }, { 3.2, -11, 1 }, { 11, -2.8, 1.1 }, { 11, 3.2, 1 }, { 3, 11, 1.1 }, { -3.2, 11, 1 }, { -11, 2.8, 1.1 }, { -11.2, -11.2, 0.9 }, { 11.2, 11.2, 0.9 } }
	for k, p in ipairs(trees) do
		if k % 3 == 0 then
			pine(out, "tree" .. k, p[1], p[2], p[3], 0.3)
		else
			tree(out, "tree" .. k, p[1], p[2], p[3], 0.3, v + k * 0.13)
		end
	end
	hedge(out, "hedgeL", 10.6, 0.8, -7.4, 12.7, 0.3)
	hedge(out, "hedgeR", 10.6, 0.8, 7.4, 12.7, 0.3)
	for k, p in ipairs({ { 2.6, 5.4, false }, { 2.6, -5.4, false }, { 5.4, -2.4, true }, { -5.4, 2.4, true } }) do
		bench(out, "bench" .. k, p[1], p[2], p[3], 0.3)
	end
	for k, p in ipairs({ { 2, -2 }, { -2, 2 }, { 2, 9 }, { -9.4, -1.8 } }) do
		lamp(out, "lamp" .. k, p[1], p[2], 0.3)
	end
	person(out, "walkerA", 1.6, -6, v + 0.9, 0.3)
	person(out, "walkerB", -1.4, 7.4, v + 0.1, 0.3)
	return out
end

-- Ô đường. arms = list {dx, dz} các phía có đường nối sang. Toạ độ tính từ tâm ô, y tính từ mặt đường.
local SW = 2.4 -- bề rộng vỉa hè
local CURB_H = 0.18

local function trafficLight(out, name, x, z, facing)
	cyl(out, name .. "Pole", 0.2, 3.4, x, 0, z, DARK, METAL, { noShadow = true })
	box(out, name .. "Head", 0.5, 1.4, 0.5, x, 3.2, z, DARK, METAL, { noShadow = true })
	local ox, oz = facing[1] * 0.27, facing[2] * 0.27
	ball(out, name .. "Red", 0.32, x + ox, 4.1, z + oz, rgb(255, 70, 60), M.Neon, { noShadow = true })
	ball(out, name .. "Amber", 0.32, x + ox, 3.7, z + oz, rgb(255, 196, 60), M.Neon, { noShadow = true, transparency = 0.5 })
	ball(out, name .. "Green", 0.32, x + ox, 3.3, z + oz, rgb(80, 230, 120), M.Neon, { noShadow = true, transparency = 0.5 })
end

function CitySpecs.road(arms, index)
	local out = {}
	local half = 7
	local inner = half - SW / 2
	local has, count = {}, 0
	for _, a in ipairs(arms) do
		has[a[1] .. "," .. a[2]] = true
		count = count + 1
	end
	local function arm(dx, dz)
		return has[dx .. "," .. dz] == true
	end
	-- vỉa hè
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		box(out, "SidewalkCorner", SW, CURB_H, SW, c[1] * inner, 0, c[2] * inner, SIDEWALK, PAVE)
	end
	local len = 2 * half - 2 * SW
	for _, d in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
		if not arm(d[1], d[2]) then
			if d[1] == 0 then
				box(out, "Sidewalk", len, CURB_H, SW, 0, 0, d[2] * inner, SIDEWALK, PAVE)
			else
				box(out, "Sidewalk", SW, CURB_H, len, d[1] * inner, 0, 0, SIDEWALK, PAVE)
			end
		end
	end
	-- vạch kẻ
	if count >= 3 then
		for _, a in ipairs(arms) do
			for k = -2, 2 do
				if a[1] == 0 then
					flat(out, "Crosswalk", 1, 2, k * 1.8, 0.01, a[2] * inner, WHITE)
				else
					flat(out, "Crosswalk", 2, 1, a[1] * inner, 0.01, k * 1.8, WHITE)
				end
			end
		end
		-- đèn giao thông ở hai góc chéo
		trafficLight(out, "TrafficA", -inner, -inner, { 1, 1 })
		trafficLight(out, "TrafficB", inner, inner, { -1, -1 })
	elseif count == 0 then
		flat(out, "Dot", 1, 1, 0, 0.01, 0, WHITE)
	else
		for _, a in ipairs(arms) do
			for _, dist in ipairs({ 1.9, 5.1 }) do
				if a[1] == 0 then
					flat(out, "Mark", 0.4, 1.8, 0, 0.01, a[2] * dist, WHITE)
				else
					flat(out, "Mark", 1.8, 0.4, a[1] * dist, 0.01, 0, WHITE)
				end
			end
		end
	end
	-- đèn đường và cây vỉa hè
	local side = (index or 0) % 2 == 0 and 1 or -1
	if count == 2 and arm(0, -1) and arm(0, 1) then
		lamp(out, "StreetLamp", side * inner, 0, CURB_H, 4.6)
		tree(out, "StreetTree", -side * inner, 0, 0.55, CURB_H)
	elseif count == 2 and arm(-1, 0) and arm(1, 0) then
		lamp(out, "StreetLamp", 0, side * inner, CURB_H, 4.6)
		tree(out, "StreetTree", 0, -side * inner, 0.55, CURB_H)
	elseif count == 2 then
		-- khúc cua: đèn ở góc ngoài
		local ox, oz = 0, 0
		for _, a in ipairs(arms) do
			ox, oz = ox - a[1], oz - a[2]
		end
		lamp(out, "StreetLamp", ox * inner, oz * inner, CURB_H, 4.6)
	elseif count == 1 then
		-- đường cụt: cây trên vỉa hè đối diện nhánh
		local a = arms[1]
		tree(out, "StreetTree", -a[1] * inner, -a[2] * inner, 0.55, CURB_H)
	end
	return out
end

local function yaw(s)
	return CFrame.Angles(0, math.rad(s.rot or 0), 0)
end

-- tâm khối trong world: công trình tâm (cx, cz), mặt lô ở baseY, xoay facing độ
local function worldCenter(s, cx, cz, baseY, facing, dy)
	local turn = math.rad(facing or 0)
	local c, sn = math.cos(turn), math.sin(turn)
	local px, pz = s.pos[1], s.pos[3]
	return Vector3.new(cx + px * c + pz * sn, baseY + s.pos[2] + dy, cz - px * sn + pz * c), CFrame.Angles(0, turn, 0)
end

-- Size + CFrame cho part
function CitySpecs.place(s, cx, cz, baseY, facing)
	local sx, sy, sz = s.size[1], s.size[2], s.size[3]
	local center, turn = worldCenter(s, cx, cz, baseY, facing, sy / 2)
	if s.shape == "Cylinder" then
		return Vector3.new(sy, sx, sz), CFrame.new(center) * turn * yaw(s) * CFrame.Angles(0, 0, math.pi / 2)
	end
	return Vector3.new(sx, sy, sz), CFrame.new(center) * turn * yaw(s)
end

-- dạng lúc bắt đầu mọc lên: dẹt sát đất
function CitySpecs.seed(s, cx, cz, baseY, facing)
	local sx, sz = s.size[1], s.size[3]
	local center, turn = worldCenter(s, cx, cz, baseY, facing, 0.05)
	if s.shape == "Cylinder" then
		return Vector3.new(0.1, sx, sz), CFrame.new(center) * turn * yaw(s) * CFrame.Angles(0, 0, math.pi / 2)
	elseif s.shape == "Ball" then
		return Vector3.new(0.2, 0.2, 0.2), CFrame.new(center)
	end
	return Vector3.new(sx, 0.1, sz), CFrame.new(center) * turn * yaw(s)
end

-- list spec cho một loại công trình. Đường thì dùng CitySpecs.road
function CitySpecs.forKind(kind, index)
	local builder = BUILDERS[kind]
	if not builder then
		return {}
	end
	return builder(variant(index or 1))
end

return CitySpecs
