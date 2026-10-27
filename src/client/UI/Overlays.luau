-- các lớp UI nổi trên thành phố: dải thống kê, cột Cách chơi/phiếu sự kiện, toast, thẻ thông tin,
-- băng chúc mừng lúc bắt đầu, màn kết thúc

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("EconCity")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local CityLayout = require(Shared:WaitForChild("CityLayout"))
local CityEngine = require(Shared:WaitForChild("CityEngine"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local C = require(script.Parent:WaitForChild("Components"))
local Icons = require(script.Parent:WaitForChild("Icons"))
local Colors = Theme.Colors

local Overlays = {}

local function soft(c)
	return c:Lerp(Color3.new(1, 1, 1), 0.86)
end

local function clear(frame)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- Dải thống kê góc dưới trái -------------------------------------------------------------
-- chỉ hiện số thẻ thành phố chưa có: người muốn đến, chỗ làm có người, dịch vụ, hàng cho shop
-- màn hẹp thì ẩn cho sa bàn rộng
function Overlays.cityBar(gui)
	local CELL_W = 156
	local bar = C.new("Frame", {
		Name = "CityBar",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 62),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0, 12, 1, -12),
		AnchorPoint = Vector2.new(0, 1),
		Parent = gui,
	})
	C.list(Enum.FillDirection.Horizontal, 8, nil, Enum.VerticalAlignment.Center).Parent = bar

	local cards = {}
	local specs = {
		{ "population", "Moving in", "people", Colors.people },
		{ "jobs", "Jobs filled", "briefcase", Colors.jobs },
		{ "service", "Services", "heart", Colors.mood },
		{ "goods", "Shop goods", "box", Colors.amber },
	}
	for i, t in ipairs(specs) do
		local card = C.panel({ Name = "Card_" .. t[1], Size = UDim2.fromOffset(CELL_W, 62), Radius = Theme.Radius.lg, LayoutOrder = i, Parent = bar })
		Icons.badge(t[3], { Size = 32, IconSize = 17, Color = t[4], Soft = soft(t[4]), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = card })
		C.label({ Text = t[2], Font = Theme.FontBold, TextSize = 11, Color = Colors.textDim, Truncate = true, Size = UDim2.new(1, -56, 0, 14), Position = UDim2.fromOffset(50, 8), Parent = card })
		local value = C.label({ Name = "Value", Text = "-", Font = Theme.FontDisplay, TextSize = 17, Truncate = true, Size = UDim2.new(1, -56, 0, 20), Position = UDim2.fromOffset(50, 22), Parent = card })
		local sub = C.label({ Name = "Sub", Text = "", Font = Theme.FontMedium, TextSize = 11, Color = Colors.textMuted, Truncate = true, Size = UDim2.new(1, -56, 0, 13), Position = UDim2.fromOffset(50, 42), Parent = card })
		cards[t[1]] = { value = value, sub = sub, frame = card }
	end

	local obj = { frame = bar }
	function obj.setCompact(compact)
		bar.Visible = not compact
	end
	function obj.update(snap)
		local s = snap.session
		if not s or type(s.cells) ~= "table" then
			return
		end
		local d = CityEngine.compute(s, s.population)
		local target = CityEngine.targetPop(d.C, d.J, s.happiness)
		cards.population.value.Text = Util.formatInt(target)
		cards.population.sub.Text = "max " .. Util.formatInt(d.C) .. " homes"
		-- đếm số chỗ làm có người, không dùng %: đặt cạnh "Việc làm 100%" của dân nhìn như mâu thuẫn
		cards.jobs.value.Text = Util.formatInt(d.emp) .. " / " .. Util.formatInt(d.J)
		cards.jobs.sub.Text = "workers / jobs"
		cards.service.value.Text = s.population > 0 and tostring(Util.round(d.S)) or "—"
		cards.service.sub.Text = "serves " .. Util.formatInt(d.pts * Config.FORMULA.residentsPerPoint) .. " people"
		cards.goods.value.Text = d.slots.shop > 0 and string.format("%d%%", Util.round(d.G * 100)) or "—"
		cards.goods.value.TextColor3 = (d.slots.shop > 0 and d.G < Config.CRISIS.goodsBelow) and Colors.warn or Colors.text
		cards.goods.sub.Text = string.format("%d IND / %d COM jobs", d.slots.factory, d.slots.shop)
	end
	return obj
end

-- Cách chơi + phiếu cảnh báo/sự kiện, cột trái ------------------------
function Overlays.eventsColumn(gui)
	local column = C.new("Frame", {
		Name = "EventsColumn",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(300, 10),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(12, 126), -- dưới thẻ thành phố và nhãn vai trò/chế độ thử
		Parent = gui,
	})
	C.list(Enum.FillDirection.Vertical, 8).Parent = column

	-- Cách chơi chỉ hiện ở tháng 0 (đang xây, chưa bấm Bắt đầu), bước nào xong tự đánh dấu
	local guide = C.panel({ Name = "Guide", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Radius = Theme.Radius.xl, LayoutOrder = 0, Parent = column })
	guide.Visible = false
	C.padding(14, 16).Parent = guide
	C.list(Enum.FillDirection.Vertical, 8).Parent = guide
	local head = C.new("Frame", { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 0, Parent = guide })
	Icons.badge("map", { Size = 30, IconSize = 16, Color = Colors.accent, Soft = Colors.accentSoft, Square = true, Position = UDim2.new(0, 0, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = head })
	C.label({ Text = "How to play", Font = Theme.FontDisplay, TextSize = 16, Size = UDim2.new(1, -100, 1, 0), Position = UDim2.fromOffset(40, 0), Parent = head })
	local progress = C.pill({ Name = "Progress", Text = "0 / 5", TextSize = 11, Color = Colors.accentSoft, TextColor = Colors.accent, Height = 22, Position = UDim2.new(1, 0, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = head })
	local STEPS = {
		"Drag a road from the GATE into the grid",
		"Build homes next to the road",
		"Add jobs: an office, or a shop + factory",
		"Add a park, school or hospital",
		"Press START",
	}
	local steps = {}
	for i, text in ipairs(STEPS) do
		local row = C.new("Frame", { Name = "Step" .. i, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 + i, Parent = guide })
		local box = C.new("Frame", { Name = "Box", BackgroundColor3 = Colors.success, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromOffset(20, 20), Position = UDim2.fromOffset(0, 0), Parent = row })
		C.round().Parent = box
		local boxStroke = C.stroke(Colors.strokeStrong, 2)
		boxStroke.Parent = box
		local number = C.label({ Name = "Number", Text = tostring(i), Font = Theme.FontBold, TextSize = 11, Color = Colors.textDim, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = box })
		local check = Icons.draw("check", { Size = 12, Color = Colors.onAccent, Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = box })
		check.Visible = false
		local label = C.label({ Text = text, Font = Theme.FontMedium, TextSize = 13, Wrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, -30, 0, 0), Position = UDim2.fromOffset(30, 1), Parent = row })
		steps[i] = { box = box, stroke = boxStroke, label = label, number = number, check = check }
	end
	C.label({ Text = "Striped lots with a ! aren't connected to the GATE: no residents, no revenue, but they still pay upkeep.", TextSize = 12, Color = Colors.textMuted, Wrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 10, Parent = guide })

	local slips = C.new("Frame", { Name = "Slips", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = column })
	C.list(Enum.FillDirection.Vertical, 8).Parent = slips

	local compact = false
	-- màn hẹp thì phiếu chỉ còn tiêu đề
	local function slip(order, color, title, sub)
		local card = C.panel({ Name = "Slip", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Radius = Theme.Radius.lg, LayoutOrder = order, Parent = slips })
		card.BackgroundColor3 = soft(color):Lerp(Colors.panel, 0.4)
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
			stroke.Transparency = 0.55
		end
		C.padding(10, 12).Parent = card
		Icons.draw("alert", { Size = 22, Color = color, Parent = card })
		C.label({ Text = title, Font = Theme.FontBold, TextSize = 13, Wrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, -32, 0, 0), Position = UDim2.fromOffset(32, 2), Parent = card })
		if sub and sub ~= "" and not compact then
			C.label({ Text = sub, TextSize = 12, Color = Colors.textDim, Wrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, -32, 0, 0), Position = UDim2.fromOffset(32, 22), Parent = card })
		end
	end

	local obj = { frame = column }
	local lastSnap = nil
	function obj.setCompact(on)
		compact = on
		if lastSnap then
			obj.update(lastSnap)
		end
	end
	function obj.update(snap)
		lastSnap = snap
		local s = snap.session
		if not s then
			return
		end
		guide.Visible = s.month == 0 and s.status ~= "ENDED" and s.status ~= "FAILED" and type(s.cells) == "table"
		if guide.Visible then
			local d = CityEngine.compute(s, 0)
			local roads = 0
			for i, kind in ipairs(s.cells) do
				if kind == "road" and d.conn[i] and i ~= Config.GATE_INDEX then
					roads = roads + 1
				end
			end
			local done = { roads > 0, d.C > 0, d.J > 0, d.pts > 0, false }
			local count = 0
			for i, step in ipairs(steps) do
				if done[i] then
					count = count + 1
				end
				step.box.BackgroundTransparency = done[i] and 0 or 1
				step.stroke.Color = done[i] and Colors.success or Colors.strokeStrong
				step.number.Visible = not done[i]
				step.check.Visible = done[i]
				step.label.TextColor3 = done[i] and Colors.textMuted or Colors.text
			end
			progress.Text = string.format("%d / %d", count, #steps)
		end
		clear(slips)
		for i, key in ipairs(s.crises or {}) do
			local text = Config.CRISIS_LABELS[key] or key
			local title, sub = text:match("^(.-):%s*(.*)$")
			slip(i, Colors.bad, title or text, sub)
		end
		for i, sc in ipairs(s.scenarios or {}) do
			slip(10 + i, Colors.warn, string.format("Event: %s (months left: %d)", sc.name or sc.id, sc.monthsLeft or 0), sc.description)
		end
	end
	return obj
end

-- Toast ---------------------------------------------------------------------------------
function Overlays.toasts(gui)
	local holder = C.new("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(440, 10),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0.5, 0, 0, 96),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 40,
		Parent = gui,
	})
	C.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center).Parent = holder
	local counter = 0
	local live = {} -- toast đang hiện, cũ nhất ở đầu
	local MAX_TOASTS = 4
	local obj = {}
	function obj.show(text, kind)
		counter = counter + 1
		-- quá MAX_TOASTS thì bỏ cái cũ nhất, không để che kín màn hình
		while #live >= MAX_TOASTS do
			local oldest = table.remove(live, 1)
			if oldest.Parent then
				oldest:Destroy()
			end
		end
		local color = (kind == "error" and Colors.bad) or (kind == "good" and Colors.success) or Colors.accent
		local toast = C.panel({ Name = "Toast", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Radius = Theme.Radius.lg, StrokeTransparency = 0.8, LayoutOrder = counter, ZIndex = 40, Parent = holder })
		C.padding(11, 14).Parent = toast
		local badge = Icons.badge(kind == "error" and "alert" or (kind == "good" and "check" or "info"), { Size = 26, IconSize = kind == "good" and 14 or 26, Color = kind == "good" and Colors.onAccent or color, Soft = kind == "good" and color or Colors.panel, ZIndex = 41, Parent = toast })
		badge.Name = "Mark"
		C.label({ Text = text, TextSize = 13, Font = Theme.FontBold, Wrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, -36, 0, 0), Position = UDim2.fromOffset(36, 3), ZIndex = 41, Parent = toast })
		C.popIn(toast, 0.9, 0.25)
		table.insert(live, toast)
		task.delay(4, function()
			for i, t in ipairs(live) do
				if t == toast then
					table.remove(live, i)
					break
				end
			end
			if toast.Parent then
				C.fadeOut(toast, 0.35, function()
					if toast.Parent then
						toast:Destroy()
					end
				end)
			end
		end)
	end
	return obj
end

-- Thẻ thông tin. 2 kiểu: mẫu công trình (nút "i" ở bảng Xây dựng, có hình 3D)
-- và công trình trên sa bàn (bấm ô khi không cầm tool). kiểu sau tự đóng sau 8s, PHÁ DỠ phải bấm 2 lần.
-- bấm ô phụ của công trình 2x2 cũng mở thẻ của cả công trình
-- ctx: { previewModel(id) -> (model, span, top), onChoose(id), onDemolish(index) }
function Overlays.detailPanel(gui, ctx)
	local panel = C.panel({
		Name = "DetailPanel",
		Size = UDim2.fromOffset(310, 10),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0, 12, 1, -86),
		AnchorPoint = Vector2.new(0, 1),
		Radius = Theme.Radius.xl,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	C.padding(14).Parent = panel
	C.list(Enum.FillDirection.Vertical, 8).Parent = panel
	local header = C.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 0, Parent = panel })
	local swatch = C.new("Frame", { Name = "Swatch", BorderSizePixel = 0, Size = UDim2.fromOffset(36, 36), Parent = header })
	C.corner(10).Parent = swatch
	local swatchCode = C.label({ Text = "", Font = Theme.FontDisplay, TextSize = 13, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = swatch })
	local title = C.label({ Text = "", Font = Theme.FontDisplay, TextSize = 17, Truncate = true, Size = UDim2.new(1, -92, 1, 0), Position = UDim2.fromOffset(46, 0), Parent = header })
	-- hình 3D của mẫu, ViewportFrame riêng chứ không nằm trong thành phố
	local view = C.new("ViewportFrame", { Name = "Preview", BackgroundColor3 = Colors.panelAlt, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 140), LayoutOrder = 1, Visible = false, Parent = panel })
	C.corner(Theme.Radius.md).Parent = view
	local viewCamera = Instance.new("Camera")
	viewCamera.FieldOfView = 40
	viewCamera.Parent = view
	view.CurrentCamera = viewCamera
	local lines = C.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = panel })
	C.list(Enum.FillDirection.Vertical, 4).Parent = lines

	-- positions[kiểu] = { Position, AnchorPoint }, Main.client sửa lại theo layout màn hình
	local obj = {
		frame = panel,
		index = nil,
		variant = nil,
		positions = {
			placed = { panel.Position, panel.AnchorPoint },
			catalog = { panel.Position, panel.AnchorPoint },
		},
	}
	local function place(mode)
		panel.Position = obj.positions[mode][1]
		panel.AnchorPoint = obj.positions[mode][2]
	end
	local token = 0
	local armed = false -- đã bấm PHÁ DỠ 1 lần, chờ lần 2
	local previewId, previewModel = nil, nil
	local lastSnap = nil
	local render

	function obj.close()
		panel.Visible = false
		obj.index = nil
		obj.variant = nil
		token = token + 1
	end
	C.closeButton({ Name = "CloseDetail", Size = 30, Position = UDim2.new(1, 0, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = header }, obj.close)

	local action = C.button({ Name = "Action", Text = "", TextSize = 13, Variant = "primary", Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 3, Visible = false, Parent = panel }, function()
		if obj.variant then
			local id = obj.variant
			obj.close()
			ctx.onChoose(id)
		elseif obj.index and not armed then
			armed = true
			obj.scheduleClose()
			render(lastSnap)
		elseif obj.index then
			local anchor = obj.anchor
			obj.close()
			ctx.onDemolish(anchor)
		end
	end)

	local function addLine(i, text, color, font)
		C.label({ Text = text, Font = font or Theme.FontMedium, TextSize = 13, Color = color or Colors.text, Wrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = i, Parent = lines })
	end

	-- xanh: đang hoạt động, đỏ: chưa nối đường
	local function addStatus(i, text, color)
		local p = C.pill({ Text = text, TextSize = 12, Color = soft(color), TextColor = color, Height = 26, LayoutOrder = i, Parent = lines })
		p.TextWrapped = false
		return p
	end

	local function addRow(i, name, value, color)
		local row = C.new("Frame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = i, Parent = lines })
		C.label({ Text = name, Font = Theme.FontMedium, TextSize = 12, Color = Colors.textDim, Size = UDim2.new(0.4, 0, 1, 0), Parent = row })
		C.label({ Name = "Value", Text = value, Font = Theme.FontBold, TextSize = 12, Color = color or Colors.text, XAlign = Enum.TextXAlignment.Right, Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.fromScale(0.4, 0), Parent = row })
		C.new("Frame", { BackgroundColor3 = Colors.rule, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), Parent = row })
	end

	local function setHeader(id, text)
		swatch.BackgroundColor3 = Theme.land(id)
		swatchCode.Text = Config.BUILDINGS[id].code
		swatchCode.TextColor3 = Theme.landInk(id)
		title.Text = text
	end

	local function showPreview(id)
		if previewId == id then
			return
		end
		previewId = id
		if previewModel then
			previewModel:Destroy()
		end
		local model, span, top = ctx.previewModel(id)
		model.Parent = view
		previewModel = model
		-- nhìn chéo giống camera toàn cảnh. cầu bao bán kính R, FOV dọc 40 độ thì phải lùi >= R / sin 20 độ
		-- (khoảng 2.92R) mới lọt khung. khung rộng hơn cao nên chiều ngang luôn đủ
		local h = math.max(top, 4)
		local radius = math.sqrt(span * span / 2 + (h / 2) ^ 2)
		local center = Vector3.new(0, h / 2, 0)
		viewCamera.CFrame = CFrame.lookAt(center + Vector3.new(1, 0.9, 1).Unit * radius * 3.1, center)
	end

	local function sizeText(def)
		return def.size > 1 and string.format("%dx%d = %d tiles", def.size, def.size, def.size * def.size) or "1 tile"
	end

	local function renderVariant(s, id)
		local def = Config.BUILDINGS[id]
		setHeader(id, def.label)
		view.Visible = true
		showPreview(id)
		local price = s and CityEngine.priceOf(s, id) or def.price
		local short = s ~= nil and s.budget < price
		addRow(1, "Zone", string.format("%s (%s)", def.zone, def.code))
		addRow(2, "Price", short and string.format("%s, short %s", Util.formatMoneyFull(price), Util.formatMoneyFull(price - s.budget)) or Util.formatMoneyFull(price), short and Colors.bad or nil)
		addRow(3, "Size", sizeText(def))
		if def.cap then
			addRow(4, "Housing", string.format("%d residents", def.cap))
		end
		if def.jobs then
			addRow(5, "Jobs", string.format("%d workers", def.jobs))
		end
		if def.rev then
			addRow(6, "Revenue", Util.formatMoneyFull(def.rev) .. " / worker / month")
		end
		if def.pts then
			addRow(7, "Services", string.format("+%d points, enough for %d residents", def.pts, def.pts * Config.FORMULA.residentsPerPoint))
		end
		addRow(8, "Upkeep", Util.formatMoneyFull(def.maint) .. " / month")
		addRow(9, "Demolish refund", Util.formatMoneyFull(math.floor(def.price * Config.DEMOLISH_REFUND)))
		addLine(10, Config.BUILDING_NOTES[id] or "", Colors.textDim)
		local finished = s ~= nil and (s.status == "ENDED" or s.status == "FAILED")
		action.Visible = true
		action.Text = "SELECT TO BUILD"
		C.setButtonColor(action, Colors.accent)
		action.TextColor3 = Colors.onAccent
		C.setEnabled(action, not finished)
	end

	local function renderPlaced(s)
		local i = CityEngine.anchorOf(s.cells, obj.index)
		obj.anchor = i
		local kind = s.cells[i]
		local def = Config.BUILDINGS[kind]
		view.Visible = false
		action.Visible = false
		if not def then
			local col, row = CityLayout.cellXY(i)
			swatch.BackgroundColor3 = Colors.panelAlt
			swatchCode.Text = ""
			title.Text = string.format("Empty tile (column %d, row %d)", col, row)
			addLine(1, "Pick a zone in the Build panel, then click this tile to build.", Colors.textDim)
			return
		end
		setHeader(kind, i == Config.GATE_INDEX and "City gate" or (def.size > 1 and string.format("%s %dx%d", def.label, def.size, def.size) or def.label))
		local d = CityEngine.compute(s, s.population)
		if d.conn[i] then
			addStatus(1, kind == "road" and "Connected to the GATE" or "Working (connected by road)", Colors.good)
		else
			addStatus(1, kind == "road" and "Not connected to the GATE" or "No road to the GATE", Colors.bad)
			if kind ~= "road" then
				addLine(2, "No residents, no revenue, still pays upkeep.", Colors.bad)
			end
		end
		addLine(3, Config.BUILDING_NOTES[kind] or "", Colors.textDim)
		if def.cap then
			addRow(4, "Housing", string.format("%d residents", def.cap))
		elseif def.jobs and d.conn[i] then
			local workers = Util.round(def.jobs * d.f)
			local perMonth = (def.rev or 0) * def.jobs * d.f * (def.kind == "shop" and d.G or 1)
			addRow(4, "Workers", string.format("%d/%d", workers, def.jobs))
			addRow(5, "Revenue", Util.formatMoneyFull(perMonth) .. "/month")
		end
		addRow(6, "Upkeep", Util.formatMoneyFull(def.maint) .. "/month", Colors.textDim)
		local finished = s.status == "ENDED" or s.status == "FAILED"
		if i ~= Config.GATE_INDEX and not finished then
			local refund = Util.formatMoneyFull(math.floor(def.price * Config.DEMOLISH_REFUND))
			action.Visible = true
			action.Text = armed and ("PRESS AGAIN TO DEMOLISH (REFUND " .. refund .. ")") or ("Demolish, refund " .. refund)
			C.setButtonColor(action, armed and Colors.danger or Colors.panelAlt)
			action.TextColor3 = armed and Colors.onAccent or Colors.bad
			C.setEnabled(action, true)
		end
	end

	render = function(snap)
		lastSnap = snap
		local s = snap and snap.session
		if obj.variant then
			clear(lines)
			renderVariant(s, obj.variant)
		elseif obj.index and s and type(s.cells) == "table" then
			clear(lines)
			renderPlaced(s)
		end
	end

	function obj.scheduleClose()
		token = token + 1
		local myToken = token
		task.delay(8, function()
			if token == myToken then
				obj.close()
			end
		end)
	end

	-- công trình trên sa bàn
	function obj.open(index, snap)
		obj.variant = nil
		obj.index = index
		armed = false
		place("placed")
		panel.Visible = true
		C.popIn(panel, 0.95, 0.18)
		render(snap)
		obj.scheduleClose()
	end

	-- mẫu trong danh mục, không tự đóng vì người chơi đang đọc
	function obj.openVariant(id, snap)
		obj.index = nil
		obj.variant = id
		armed = false
		token = token + 1
		place("catalog")
		panel.Visible = true
		C.popIn(panel, 0.95, 0.18)
		render(snap)
	end

	function obj.update(snap)
		if panel.Visible then
			render(snap)
		end
	end

	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape and panel.Visible then
			obj.close()
		end
	end)
	return obj
end

-- pháo giấy màu đất, chỉ trang trí nên không chặn click (attribute Decor)
local function confetti(gui, origin, count)
	local palette = {}
	for _, cat in ipairs(Config.CATEGORY_ORDER) do
		table.insert(palette, Theme.land(cat))
	end
	for k = 1, count do
		local angle = (k / count) * math.pi * 2 + math.random() * 0.4
		local dist = 140 + math.random() * 160
		local piece = C.new("Frame", {
			Name = "Confetti",
			BackgroundColor3 = palette[(k % #palette) + 1],
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(8 + math.random(0, 6), 5 + math.random(0, 4)),
			Position = origin,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = math.random(0, 180),
			ZIndex = 29,
			Parent = gui,
		})
		piece:SetAttribute("Decor", true)
		C.corner(2).Parent = piece
		local target = origin + UDim2.fromOffset(math.cos(angle) * dist, math.sin(angle) * dist * 0.7 + 80)
		TweenService:Create(piece, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target, Rotation = piece.Rotation + math.random(-240, 240) }):Play()
		TweenService:Create(piece, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.7), { BackgroundTransparency = 1 }):Play()
		task.delay(1.3, function()
			piece:Destroy()
		end)
	end
end

-- Băng chúc mừng lúc bắt đầu ván ---------------
function Overlays.stamp(gui)
	local banner = C.panel({
		Name = "ApprovalStamp",
		Size = UDim2.fromOffset(400, 104),
		Position = UDim2.fromScale(0.42, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Radius = 26,
		StrokeTransparency = 0.75,
		ZIndex = 30,
		Parent = gui,
	})
	banner.Visible = false
	C.gradient(Colors.success, Colors.jobs, 20).Parent = banner
	local badge = Icons.badge("play", { Size = 56, IconSize = 26, Color = Colors.success, Soft = Colors.panel, Position = UDim2.new(0, 24, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 31, Parent = banner })
	badge.Name = "Seal"
	local titleLabel = C.label({ Name = "StampTitle", Text = "", Font = Theme.FontDisplay, TextSize = 26, Color = Colors.onAccent, Size = UDim2.new(1, -110, 0, 32), Position = UDim2.fromOffset(96, 22), ZIndex = 31, Parent = banner })
	local subLabel = C.label({ Name = "StampSub", Text = "", Font = Theme.FontBold, TextSize = 14, Color = Colors.onAccent, Size = UDim2.new(1, -110, 0, 20), Position = UDim2.fromOffset(96, 56), ZIndex = 31, Parent = banner })
	local scale = Instance.new("UIScale")
	scale.Parent = banner
	local token = 0
	local obj = { frame = banner }
	function obj.show(title, sub)
		token = token + 1
		local myToken = token
		titleLabel.Text = title
		subLabel.Text = sub or ""
		C.restoreFade(banner)
		scale.Scale = 0.6
		banner.Visible = true
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		confetti(gui, banner.Position, 26)
		task.delay(1.6, function()
			if myToken ~= token then
				return
			end
			TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.85 }):Play()
			C.fadeOut(banner, 0.35, function()
				if myToken == token then
					banner.Visible = false
					C.restoreFade(banner)
				end
			end)
		end)
	end
	return obj
end

-- Màn kết thúc + viền đỏ khi phá sản -------------------
function Overlays.endScreen(gui, ctx)
	local vignette = C.new("Frame", {
		Name = "FailVignette",
		BackgroundTransparency = 1,
		-- UIStroke vẽ ra ngoài khung nên thu khung lại cho viền nằm trong màn hình
		Size = UDim2.new(1, -28, 1, -28),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	})
	vignette:SetAttribute("Decor", true)
	C.corner(28).Parent = vignette
	local vStroke = C.new("UIStroke", { Color = Colors.danger, Thickness = 14, Transparency = 0.4, Parent = vignette })

	local card = C.panel({
		Name = "EndCard",
		Size = UDim2.fromOffset(480, 10),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromScale(0.42, 0.48),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Radius = 26,
		StrokeTransparency = 0.78,
		Visible = false,
		ZIndex = 45,
		Parent = gui,
	})
	C.padding(22, 24).Parent = card
	C.list(Enum.FillDirection.Vertical, 12, Enum.HorizontalAlignment.Center).Parent = card

	-- huy chương: vàng là hoàn thành, đỏ là phá sản, số tháng ở giữa
	local medal = C.new("Frame", { Name = "Seal", BackgroundColor3 = Colors.panel, BorderSizePixel = 0, Size = UDim2.fromOffset(88, 88), LayoutOrder = 1, ZIndex = 46, Parent = card })
	C.round().Parent = medal
	local medalGradient = C.gradient(Colors.gold, Colors.amber, 45)
	medalGradient.Parent = medal
	local medalRing = C.new("Frame", { Name = "Ring", BackgroundTransparency = 1, Size = UDim2.new(1, -14, 1, -14), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 46, Parent = medal })
	C.round().Parent = medalRing
	C.stroke(Colors.panel, 3, 0.15).Parent = medalRing
	local medalNumber = C.label({ Name = "StampTitle", Text = "", Font = Theme.FontDisplay, TextSize = 30, Color = Colors.onAccent, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 18), ZIndex = 47, Parent = medal })
	local medalSub = C.label({ Name = "StampSub", Text = "", Font = Theme.FontBold, TextSize = 11, Color = Colors.onAccent, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 52), ZIndex = 47, Parent = medal })

	local title = C.label({ Text = "", Font = Theme.FontDisplay, TextSize = 28, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 2, ZIndex = 46, Parent = card })
	local reasonLabel = C.label({ Text = "", Font = Theme.FontMedium, TextSize = 13, Color = Colors.bad, XAlign = Enum.TextXAlignment.Center, Wrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 3, ZIndex = 46, Parent = card })
	local recordPill = C.pill({ Name = "Record", Text = "New record!", TextSize = 12, Color = Colors.goldSoft, TextColor = Colors.warn, Height = 26, LayoutOrder = 4, ZIndex = 46, Parent = card })

	-- lưới số liệu 3x2
	local grid = C.new("Frame", { Name = "Table", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 132), LayoutOrder = 5, ZIndex = 46, Parent = card })
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(1 / 3, -6, 0, 62)
	gridLayout.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	local cellValues = {}
	local LABELS = { { "MONTHS", "Month" }, { "SCORE", "Score" }, { "RECORD", "Record" }, { "POPULATION", "Population" }, { "HAPPINESS", "Happiness" }, { "BUDGET", "Budget" } }
	for k, l in ipairs(LABELS) do
		local cell = C.well({ Name = "Cell_" .. l[1], Size = UDim2.fromOffset(100, 62), LayoutOrder = k, ZIndex = 46, Parent = grid })
		C.label({ Text = l[2], Font = Theme.FontBold, TextSize = 11, Color = Colors.textDim, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, -12, 0, 14), Position = UDim2.fromOffset(6, 10), ZIndex = 47, Parent = cell })
		cellValues[l[1]] = C.label({ Text = "", Font = Theme.FontDisplay, TextSize = 19, XAlign = Enum.TextXAlignment.Center, Truncate = true, Size = UDim2.new(1, -12, 0, 24), Position = UDim2.fromOffset(6, 28), ZIndex = 47, Parent = cell })
	end

	local buttons = C.new("Frame", { Name = "Buttons", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 6, ZIndex = 46, Parent = card })
	C.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center).Parent = buttons
	C.button({ Text = "PLAY AGAIN", Variant = "success", Font = Theme.FontDisplay, TextSize = 14, Size = UDim2.fromOffset(150, 44), LayoutOrder = 1, ZIndex = 46, Parent = buttons }, function()
		ctx.onNewGame()
	end)
	C.button({ Text = "View history", Variant = "secondary", Size = UDim2.fromOffset(130, 44), LayoutOrder = 2, ZIndex = 46, Parent = buttons }, function()
		ctx.onHistory()
	end)
	C.button({ Text = "View city", Variant = "white", Size = UDim2.fromOffset(140, 44), LayoutOrder = 3, ZIndex = 46, Parent = buttons }, function()
		card.Visible = false
	end)

	local shownFor = nil
	local pulse = nil
	local obj = {}
	function obj.update(snap)
		local s = snap.session
		if not s then
			return
		end
		local failed = s.status == "FAILED"
		local ended = s.status == "ENDED"
		vignette.Visible = failed
		if failed and not pulse then
			pulse = TweenService:Create(vStroke, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.85 })
			pulse:Play()
		elseif not failed and pulse then
			pulse:Cancel()
			pulse = nil
		end
		if (failed or ended) and shownFor ~= s.id then
			shownFor = s.id
			title.Text = ended and "Term complete!" or "City went bankrupt"
			title.TextColor3 = ended and Colors.text or Colors.bad
			reasonLabel.Text = failed and string.format("The deficit went over %s.", Util.formatMoneyFull(-Config.FAIL_BUDGET)) or ""
			reasonLabel.Visible = failed
			local score = s.prosperityScore or 0
			local best = (snap.profile and snap.profile.bestScore) or 0
			cellValues["MONTHS"].Text = string.format("%d / %d", s.month, s.maxMonths)
			cellValues["SCORE"].Text = Util.formatInt(score)
			cellValues["POPULATION"].Text = Util.formatInt(s.population or 0)
			cellValues["HAPPINESS"].Text = tostring(Util.round(s.happiness))
			cellValues["HAPPINESS"].TextColor3 = Theme.happinessColor(s.happiness)
			cellValues["BUDGET"].Text = Util.formatMoneyFull(s.budget)
			cellValues["BUDGET"].TextColor3 = s.budget < 0 and Colors.bad or Colors.text
			cellValues["RECORD"].Text = Util.formatInt(best)
			-- kỷ lục mới khi điểm ván này chính là điểm cao nhất
			recordPill.Visible = ended and score > 0 and score >= best
			medalGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, ended and Colors.gold or Colors.danger),
				ColorSequenceKeypoint.new(1, ended and Colors.amber or Colors.dangerDark),
			})
			medalNumber.Text = tostring(s.month)
			medalSub.Text = ended and "MONTHS" or "BANKRUPT"
			card.Visible = true
			C.popIn(card, 0.85, 0.35)
			if ended then
				confetti(gui, card.Position, 34)
			end
		elseif not failed and not ended then
			card.Visible = false
		end
	end
	return obj
end

return Overlays
