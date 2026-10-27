-- Dựng và cập nhật thành phố 3D ở client, mỗi người chơi thấy thành phố của mình. Địa hình xung quanh là server dựng.
-- Công trình 2x2: 1 model giữa 4 ô, dựng ở ô góc, 3 ô phụ ("+góc") không có model.
-- BuildController raycast vào folder này rồi đổi điểm trúng ra số ô (CityLayout.cellAt).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("EconCity")
local Config = require(Shared:WaitForChild("Config"))
local CityLayout = require(Shared:WaitForChild("CityLayout"))
local CityEngine = require(Shared:WaitForChild("CityEngine"))
local CitySpecs = require(script.Parent:WaitForChild("CitySpecs"))

local CityRenderer = {}
CityRenderer.__index = CityRenderer

local N = Config.GRID_SIZE
local CELL = CityLayout.CELL
local GRID_TOP = 0.2 -- mặt trên của tấm lưới
local MORPH_TIME = 1.6
local BOARD = Color3.fromRGB(128, 186, 98) -- cỏ khu đất
local BOARD_LINE = Color3.fromRGB(158, 206, 128) -- vạch chia ô
local FRAME = Color3.fromRGB(206, 208, 204) -- vỉa hè quanh khu đất
local INK = Color3.fromRGB(27, 31, 36)
local STAMP = Color3.fromRGB(229, 72, 77) -- chỉ dùng cho dấu "!"
local ROAD_ON = Color3.fromRGB(74, 77, 83)
local ROAD_OFF = Color3.fromRGB(166, 170, 176) -- chưa nối về cổng: nhạt + gạch sọc

local function landColor(kind)
	local c = Config.BUILDINGS[kind].color
	return Color3.fromRGB(c[1], c[2], c[3])
end
-- màu đất pha nửa trắng, vẫn nhận ra loại đất mà đỡ chói
local function lotColor(kind)
	return Color3.new(1, 1, 1):Lerp(landColor(kind), 0.5)
end
local GHOST = {
	ok = Color3.fromRGB(80, 230, 120),
	warn = Color3.fromRGB(250, 204, 21),
	bad = Color3.fromRGB(240, 80, 70),
}
-- { dx, dz, bit } sang ô bên cạnh
local SIDES = { { 0, -1, 1 }, { 0, 1, 2 }, { -1, 0, 4 }, { 1, 0, 8 } }

local function newPart(props, className)
	local p = Instance.new(className or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

local LOT_TOP = GRID_TOP + 0.12 -- công trình đứng trên nền lát của ô

-- tâm vùng size x size, góc trên-trái ở ô index, mở về +cột/+hàng giống CityEngine.footprint
local function footprintCenter(index, size)
	local cx, cz = CityLayout.cellCenter(index)
	local offset = (size - 1) * CELL / 2
	return cx + offset, cz + offset
end

-- spec.label: SurfaceGui trên một mặt của part
local function addLabel(part, s)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label"
	gui.Face = Enum.NormalId[s.labelFace or "Back"]
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.BuilderSansExtraBold
	text.TextScaled = true
	text.Text = s.label
	text.TextColor3 = s.labelColor or Color3.new(1, 1, 1)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.14, 0)
	pad.PaddingBottom = UDim.new(0.14, 0)
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.Parent = text
	text.Parent = gui
	gui.Parent = part
end

-- công trình tâm (cx, cz), nền ở baseY, xoay facing độ. animate thì mọc từ mặt đất lên theo tween info
local function specPart(model, s, cx, cz, baseY, facing, animate, info)
	local size, cframe = CitySpecs.place(s, cx, cz, baseY, facing)
	local seedSize, seedCFrame
	if animate then
		seedSize, seedCFrame = CitySpecs.seed(s, cx, cz, baseY, facing)
	end
	local props = {
		Name = s.name,
		Size = animate and seedSize or size,
		CFrame = animate and seedCFrame or cframe,
		Material = s.material,
		Color = s.color,
		Transparency = s.transparency or 0,
		Reflectance = s.reflectance or 0,
		CastShadow = not s.noShadow,
	}
	if s.noCollide then
		props.CanCollide = false
		props.CanQuery = false
	end
	local part
	if s.shape == "Wedge" then
		part = newPart(props, "WedgePart")
	else
		props.Shape = (s.shape == "Cylinder" and Enum.PartType.Cylinder) or (s.shape == "Ball" and Enum.PartType.Ball) or Enum.PartType.Block
		part = newPart(props)
	end
	if s.effect == "smoke" then
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(236, 236, 240)
		smoke.Opacity = 0.12
		smoke.RiseVelocity = 3
		smoke.Size = 2.5
		smoke.Parent = part
	end
	if s.label then
		addLabel(part, s)
	end
	part.Parent = model
	if animate then
		TweenService:Create(part, info, { Size = size, CFrame = cframe }):Play()
	end
	return part
end

-- lô (hoặc mặt đường) + các part của công trình. Trả về part nền và độ cao đỉnh tính từ mặt lô
local function addParts(model, kind, index, cx, cz, animate, facing)
	local span = Config.BUILDINGS[kind].size * CELL
	local base
	if kind == "road" then
		base = newPart({ Name = "Road", Size = Vector3.new(CELL, 0.15, CELL), Position = Vector3.new(cx, GRID_TOP + 0.075, cz), Material = Enum.Material.Asphalt, Color = ROAD_OFF, Parent = model })
	else
		base = newPart({ Name = "Lot", Size = Vector3.new(span - 0.6, 0.12, span - 0.6), Position = Vector3.new(cx, GRID_TOP + 0.06, cz), Material = Enum.Material.Pavement, Color = lotColor(kind), Parent = model })
		-- viền màu đất đậm quanh lô
		for _, side in ipairs(SIDES) do
			local alongX = side[1] == 0
			newPart({
				Name = "LotEdge",
				Size = alongX and Vector3.new(span - 0.6, 0.14, 0.5) or Vector3.new(0.5, 0.14, span - 0.6),
				Position = Vector3.new(cx + side[1] * (span / 2 - 0.55), GRID_TOP + 0.07, cz + side[2] * (span / 2 - 0.55)),
				Material = Enum.Material.SmoothPlastic,
				Color = landColor(kind),
				CanQuery = false,
				CastShadow = false,
				Parent = model,
			})
		end
	end
	local info = TweenInfo.new(animate and MORPH_TIME or 0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local top = 0
	for _, s in ipairs(CitySpecs.forKind(kind, index)) do
		specPart(model, s, cx, cz, LOT_TOP, facing, animate, info)
		top = math.max(top, s.pos[2] + s.size[2])
	end
	return base, top
end

-- hướng mặt tiền (độ) của công trình góc ở ô i: quay ra ô đường kề, ưu tiên +Z, +X, -X rồi -Z
-- vì camera tổng quan nhìn từ phía +X, +Z. Không kề đường thì giữ +Z
local FACINGS = { { 0, 1, 0 }, { 1, 0, 90 }, { -1, 0, -90 }, { 0, -1, 180 } }
local function facingFor(cells, i, size)
	local col, row = CityLayout.cellXY(i)
	for _, f in ipairs(FACINGS) do
		for k = 0, size - 1 do
			local c, r
			if f[1] ~= 0 then
				c, r = f[1] > 0 and col + size or col - 1, row + k
			else
				c, r = col + k, f[2] > 0 and row + size or row - 1
			end
			if c >= 1 and c <= N and r >= 1 and r <= N and cells[(r - 1) * N + c] == "road" then
				return f[3]
			end
		end
	end
	return 0
end

function CityRenderer.new()
	local self = setmetatable({}, CityRenderer)
	local old = Workspace:FindFirstChild("EconCityClientCity")
	if old then
		old:Destroy()
	end
	self.folder = Instance.new("Folder")
	self.folder.Name = "EconCityClientCity"
	self.cells = {} -- [i] = { kind, model, connected, marker }
	self:_buildStatic()
	self.folder.Parent = Workspace
	return self
end

function CityRenderer:_buildStatic()
	local size = CELL * N
	newPart({
		Name = "Grid",
		-- kéo dày xuống dưới vì địa hình xung quanh thấp hơn khu đất 2 stud
		Size = Vector3.new(size + 4, GRID_TOP + 2.4, size + 4),
		Position = Vector3.new(CityLayout.ORIGIN.x, (GRID_TOP - 2.4) / 2, CityLayout.ORIGIN.z),
		Material = Enum.Material.Grass,
		Color = BOARD,
		Parent = self.folder,
	})
	-- vỉa hè quanh khu đất, chừa chỗ cổng ở mép +Z
	local gx, gz = CityLayout.cellCenter(Config.GATE_INDEX)
	local function frame(x0, x1, z0, z1)
		newPart({
			Name = "BoardFrame",
			Size = Vector3.new(x1 - x0, 2.9, z1 - z0),
			Position = Vector3.new(CityLayout.ORIGIN.x + (x0 + x1) / 2, 0.5 - 1.45, CityLayout.ORIGIN.z + (z0 + z1) / 2),
			Material = Enum.Material.Concrete,
			Color = FRAME,
			CanQuery = false,
			Parent = self.folder,
		})
	end
	local outer, inner = size / 2 + 4, size / 2 + 2
	frame(-outer, outer, -outer, -inner)
	frame(-outer, -inner, -inner, inner)
	frame(inner, outer, -inner, inner)
	frame(-outer, gx - CELL / 2, inner, outer)
	frame(gx + CELL / 2, outer, inner, outer)
	-- vạch chia ô, không chặn raycast
	local lines = Instance.new("Folder")
	lines.Name = "GridLines"
	lines.Parent = self.folder
	for k = 0, N do
		local offset = -size / 2 + k * CELL
		for _, horizontal in ipairs({ true, false }) do
			newPart({
				Name = "Line",
				Size = horizontal and Vector3.new(size, 0.02, 0.15) or Vector3.new(0.15, 0.02, size),
				Position = horizontal and Vector3.new(CityLayout.ORIGIN.x, GRID_TOP + 0.01, CityLayout.ORIGIN.z + offset)
					or Vector3.new(CityLayout.ORIGIN.x + offset, GRID_TOP + 0.01, CityLayout.ORIGIN.z),
				Material = Enum.Material.SmoothPlastic,
				Color = BOARD_LINE,
				Transparency = 0.35,
				CanCollide = false,
				CanQuery = false,
				CastShadow = false,
				Parent = lines,
			})
		end
	end

	-- cổng + đoạn đường dẫn ngoài lưới (mọi đường phải nối về đây). Vành đai, đại lộ bên ngoài là server dựng,
	-- ở đây chỉ nối từ cổng ra tới đó
	local edge = gz + CELL / 2
	local gate = Instance.new("Model")
	gate.Name = "Gate"
	newPart({ Name = "Highway", Size = Vector3.new(CELL, 2.4, 4), Position = Vector3.new(gx, 0.15 - 1.2, edge + 2), Material = Enum.Material.Asphalt, Color = ROAD_ON, Parent = gate })
	for _, side in ipairs({ -1, 1 }) do
		newPart({ Name = "Pillar", Size = Vector3.new(1.4, 9, 1.4), Position = Vector3.new(gx + side * 6.6, 4.5, edge + 1), Material = Enum.Material.Concrete, Color = Color3.fromRGB(240, 238, 232), Parent = gate })
		newPart({ Name = "PillarCap", Size = Vector3.new(2, 0.6, 2), Position = Vector3.new(gx + side * 6.6, 0.3, edge + 1), Material = Enum.Material.Concrete, Color = Color3.fromRGB(206, 208, 204), Parent = gate })
	end
	local beam = newPart({ Name = "Beam", Size = Vector3.new(15, 1.6, 1.6), Position = Vector3.new(gx, 9.6, edge + 1), Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(46, 107, 255), Parent = gate })
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(72, 24)
	billboard.StudsOffset = Vector3.new(0, 1.8, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 600
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 0
	text.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	text.TextColor3 = Color3.fromRGB(24, 34, 52)
	text.Font = Enum.Font.BuilderSansExtraBold
	text.TextSize = 13
	text.Size = UDim2.fromScale(1, 1)
	text.Text = "GATE"
	text.Parent = billboard
	local tagCorner = Instance.new("UICorner")
	tagCorner.CornerRadius = UDim.new(1, 0)
	tagCorner.Parent = text
	local tagStroke = Instance.new("UIStroke")
	tagStroke.Color = Color3.fromRGB(11, 18, 32)
	tagStroke.Thickness = 1.5
	tagStroke.Transparency = 0.8
	tagStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	tagStroke.Parent = text
	billboard.Parent = beam
	gate.Parent = self.folder

	-- ô xem trước + đoạn đường đang kéo
	self.ghost = newPart({ Name = "Ghost", Size = Vector3.new(CELL - 1, 0.8, CELL - 1), Material = Enum.Material.Neon, Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false, Parent = self.folder })
	self.pathParts = {}
	for k = 1, Config.MAX_ROAD_PATH do
		self.pathParts[k] = newPart({ Name = "PathPreview", Size = Vector3.new(CELL - 2, 0.6, CELL - 2), Material = Enum.Material.Neon, Color = GHOST.ok, Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false, Parent = self.folder })
	end
end

-- dấu "!" trên công trình chưa nối đường
local function marker(parent)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Unconnected"
	billboard.Size = UDim2.fromOffset(22, 22)
	billboard.StudsOffset = Vector3.new(0, 5, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 500
	local text = Instance.new("TextLabel")
	text.BackgroundColor3 = STAMP
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.Font = Enum.Font.BuilderSansExtraBold
	text.TextSize = 15
	text.Size = UDim2.fromScale(1, 1)
	text.Text = "!"
	text.Parent = billboard
	local markCorner = Instance.new("UICorner")
	markCorner.CornerRadius = UDim.new(1, 0)
	markCorner.Parent = text
	local markStroke = Instance.new("UIStroke")
	markStroke.Color = Color3.fromRGB(255, 255, 255)
	markStroke.Thickness = 2
	markStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	markStroke.Parent = text
	billboard.Parent = parent
	return billboard
end

-- sọc trên lô chưa nối đường. Thanh chạy dọc X nhưng camera nhìn chéo nên trông như gạch chéo
local function hatch(parent, cx, cz, top, span)
	local folder = Instance.new("Folder")
	folder.Name = "Hatch"
	local count = math.floor((span - 4) / 2.5) + 1 -- 1 ô: 5 thanh, 2x2: 10 thanh
	for k = 0, count - 1 do
		newPart({
			Name = "HatchBar",
			Size = Vector3.new(span - 1, 0.04, 0.7),
			Position = Vector3.new(cx, top, cz + (k - (count - 1) / 2) * 2.5),
			Material = Enum.Material.SmoothPlastic,
			Color = INK,
			Transparency = 0.45,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
			Parent = folder,
		})
	end
	folder.Parent = parent
	return folder
end

-- vạch, vỉa hè, đèn của ô đường theo mask (bit trong SIDES), xem CitySpecs.road
function CityRenderer:_drawRoadMarks(entry, cx, cz, mask, index)
	if entry.marks then
		entry.marks:Destroy()
	end
	local marks = Instance.new("Folder")
	marks.Name = "Marks"
	local arms = {}
	for _, side in ipairs(SIDES) do
		if mask % (side[3] * 2) >= side[3] then
			table.insert(arms, { side[1], side[2] })
		end
	end
	for _, s in ipairs(CitySpecs.road(arms, index)) do
		specPart(marks, s, cx, cz, GRID_TOP + 0.15, 0, false)
	end
	marks.Parent = entry.model
	entry.marks = marks
	entry.mask = mask
end

-- ô trống và ô phụ "+góc" không có model
function CityRenderer:_buildCell(i, kind, animate, facing)
	local entry = self.cells[i]
	if entry and entry.model then
		local oldModel = entry.model
		if animate then
			for _, part in ipairs(oldModel:GetChildren()) do
				if part:IsA("BasePart") then
					TweenService:Create(part, TweenInfo.new(MORPH_TIME * 0.5), { Transparency = 1 }):Play()
				end
			end
			task.delay(MORPH_TIME * 0.5, function()
				oldModel:Destroy()
			end)
		else
			oldModel:Destroy()
		end
	end
	entry = { kind = kind, connected = nil, facing = facing or 0 }
	self.cells[i] = entry
	local def = Config.BUILDINGS[kind]
	if not def then
		return entry
	end
	entry.span = def.size * CELL
	entry.cx, entry.cz = footprintCenter(i, def.size)
	local model = Instance.new("Model")
	model.Name = "Cell_" .. i
	model:SetAttribute("Cell", i)
	model:SetAttribute("Kind", kind)
	local base = addParts(model, kind, i, entry.cx, entry.cz, animate, entry.facing)
	if kind == "road" then
		entry.road = base
	else
		entry.lot = base -- dấu "!" gắn vào lô
	end
	model.Parent = self.folder
	entry.model = model
	return entry
end

-- model mẫu quanh gốc toạ độ cho khung xem 3D ở thẻ thông tin. Trả về model, cạnh lô (stud), độ cao đỉnh
function CityRenderer.previewModel(kind)
	local model = Instance.new("Model")
	model.Name = "Preview_" .. kind
	local _, top = addParts(model, kind, 1, 0, 0, false, 0)
	return model, Config.BUILDINGS[kind].size * CELL, top
end

-- animate = false lúc dựng lần đầu hoặc ván mới
function CityRenderer:update(session, animate)
	if not session or type(session.cells) ~= "table" then
		return
	end
	local cells = session.cells
	local conn = CityEngine.connectivity(cells)
	for i = 1, N * N do
		local kind = cells[i] or Config.EMPTY
		local entry = self.cells[i]
		local def = Config.BUILDINGS[kind]
		local facing = (def and kind ~= "road") and facingFor(cells, i, def.size) or 0
		if not entry or entry.kind ~= kind then
			entry = self:_buildCell(i, kind, animate, facing)
		elseif entry.model and not entry.road and entry.facing ~= facing then
			-- có đường mới kề bên thì quay mặt ra đường, dựng lại luôn, không animate
			entry = self:_buildCell(i, kind, false, facing)
		end
		if entry.model then
			local connected = conn[i] == true
			if entry.road then
				-- ô cổng có thêm nhánh +Z ra đường dẫn ngoài lưới
				local col, row = CityLayout.cellXY(i)
				local mask = i == Config.GATE_INDEX and 2 or 0
				for _, side in ipairs(SIDES) do
					local c, r = col + side[1], row + side[2]
					if c >= 1 and c <= N and r >= 1 and r <= N and cells[(r - 1) * N + c] == "road" then
						mask = mask + side[3]
					end
				end
				if entry.mask ~= mask then
					local cx, cz = CityLayout.cellCenter(i)
					self:_drawRoadMarks(entry, cx, cz, mask, i)
				end
			end
			if entry.connected ~= connected then
				entry.connected = connected
				if entry.road then
					entry.road.Color = connected and ROAD_ON or ROAD_OFF
				end
				if not connected and not entry.hatch then
					-- công viên: sọc nằm trên bãi cỏ, lô khác: sát mặt lô, dưới chân nhà
					local onLawn = Config.BUILDINGS[kind].kind == "park"
					entry.hatch = hatch(entry.model, entry.cx, entry.cz, GRID_TOP + (onLawn and 0.46 or kind == "road" and 0.19 or 0.16), entry.span)
				elseif connected and entry.hatch then
					entry.hatch:Destroy()
					entry.hatch = nil
				end
				if entry.lot and not connected and not entry.marker then
					entry.marker = marker(entry.lot)
				elseif connected and entry.marker then
					entry.marker:Destroy()
					entry.marker = nil
				end
			end
		end
	end
end

-- vùng size x size góc ở ô index (theo chuột hoặc con trỏ tay cầm). state: "ok" | "warn" | "bad", index = nil để ẩn
function CityRenderer:setGhost(index, state, size)
	if not index then
		self.ghost.Transparency = 1
		return
	end
	size = size or 1
	local cx, cz = footprintCenter(index, size)
	self.ghost.Size = Vector3.new(size * CELL - 1, 0.8, size * CELL - 1)
	self.ghost.Position = Vector3.new(cx, GRID_TOP + 0.4, cz)
	self.ghost.Color = GHOST[state] or GHOST.bad
	self.ghost.Transparency = 0.55
end

-- path = list ô đang kéo, nil để ẩn
function CityRenderer:setPath(path)
	for k, part in ipairs(self.pathParts) do
		local i = path and path[k]
		if i then
			local cx, cz = CityLayout.cellCenter(i)
			part.Position = Vector3.new(cx, GRID_TOP + 0.3, cz)
			part.Transparency = 0.45
		else
			part.Transparency = 1
		end
	end
end

return CityRenderer
