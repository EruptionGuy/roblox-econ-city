-- bảng Xây dựng bên phải: chọn loại đất/mẫu, thuế, bảng tính hạnh phúc (docs/luat-choi-moi.md mục 4)
-- số dự kiến tính luôn ở client bằng CityEngine, số thật vẫn do server tính mỗi tháng

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("EconCity")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local CityEngine = require(Shared:WaitForChild("CityEngine"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local C = require(script.Parent:WaitForChild("Components"))
local Icons = require(script.Parent:WaitForChild("Icons"))
local Colors = Theme.Colors

local BuildPanel = {}

local WIDTH = 340
local FULL_HEIGHT = 580
local TOP = 80 -- cách mép trên, chừa chỗ cho thanh điều khiển
local HEADER = 56
local CHIP_H = 36
local ROW_H = 54
local TAX_SEND_DELAY = 0.5 -- giây, ngừng kéo slider lâu vậy mới gửi thuế

-- số thập phân dùng dấu phẩy
local function fmt(x, decimals)
	return (string.format("%." .. decimals .. "f", x):gsub("%.", ","))
end

local function soft(c)
	return c:Lerp(Color3.new(1, 1, 1), 0.86)
end

-- số liệu chính, hiện cuối dòng mẫu
local function keyStat(def)
	if def.cap then
		return string.format("%d chỗ ở", def.cap)
	elseif def.rev then
		return string.format("%d việc × %s", def.jobs, Util.formatMoneyFull(def.rev))
	elseif def.pts then
		return string.format("+%d dịch vụ", def.pts)
	end
	return "kéo từ CỔNG"
end

-- công trình 2x2 thì chia thành 4 ô nhỏ
local function swatch(parent, id, size)
	local def = Config.BUILDINGS[id]
	local frame = C.new("Frame", {
		Name = "Swatch",
		BackgroundColor3 = def and Theme.land(id) or Colors.panel,
		BorderSizePixel = 0,
		Size = size,
		Position = UDim2.new(0, 9, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = parent,
	})
	C.corner(10).Parent = frame
	if not def then
		C.stroke(Colors.strokeStrong, 1.5).Parent = frame -- phá dỡ: ô trắng viền
	elseif def.size > 1 then
		C.new("Frame", { Name = "Split", BackgroundColor3 = Colors.panel, BorderSizePixel = 0, Size = UDim2.new(0, 2, 1, 0), Position = UDim2.new(0.5, -1, 0, 0), Parent = frame })
		C.new("Frame", { Name = "Split", BackgroundColor3 = Colors.panel, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 0.5, -1), Parent = frame })
	end
	C.label({ Name = "Code", Text = def and def.code or "PD", Font = Theme.FontDisplay, TextSize = 13, Color = def and Theme.landInk(id) or Colors.text, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = frame })
	return frame
end

local function sectionHeader(parent, title, order)
	local head = C.new("Frame", { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = order or 0, Parent = parent })
	C.label({ Name = "Heading", Text = title, Font = Theme.FontDisplay, TextSize = 15, Size = UDim2.new(0.62, 0, 1, 0), Parent = head })
	return head
end

-- ctx: { onSelectTool(tool), onInfo(id), onSetTax(tax) -> (ok, errorText), onDemoBuild() }
-- callback chạy trong thread riêng, yield được
function BuildPanel.new(gui, ctx)
	local obj = { tool = nil, category = "house" }
	local finished = false

	local panel = C.panel({
		Name = "BuildPanel",
		Size = UDim2.fromOffset(WIDTH, FULL_HEIGHT),
		Position = UDim2.new(1, -12, 0, TOP),
		AnchorPoint = Vector2.new(1, 0),
		Radius = Theme.Radius.xl,
		Parent = gui,
	})
	obj.frame = panel

	-- header: tiêu đề + pill tool đang chọn
	local header = C.new("Frame", { Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(1, -32, 0, 34), Position = UDim2.fromOffset(16, 12), Parent = panel })
	Icons.badge("grid", { Size = 30, IconSize = 15, Color = Colors.accent, Soft = Colors.accentSoft, Square = true, Position = UDim2.new(0, 0, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = header })
	C.label({ Name = "PanelTitle", Text = "Xây dựng", Font = Theme.FontDisplay, TextSize = 18, Size = UDim2.new(0, 120, 1, 0), Position = UDim2.fromOffset(40, 0), Parent = header })
	local toolLabel = C.pill({ Name = "ToolLabel", Text = "", TextSize = 11, Color = Colors.accentSoft, TextColor = Colors.accent, Height = 24, Position = UDim2.new(1, 0, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = header })
	toolLabel.Visible = false

	local content = C.new("ScrollingFrame", {
		Name = "Content",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -16, 0, FULL_HEIGHT - HEADER - 10),
		Position = UDim2.fromOffset(16, HEADER),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Colors.strokeStrong,
		Parent = panel,
	})
	C.selectable(content)
	C.list(Enum.FillDirection.Vertical, 10).Parent = content
	C.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = content })
	local inner = UDim2.new(1, 0, 0, 0)

	-- chỉ hiện trong Studio: bot xây thành phố mẫu theo đúng luật, để xem game chạy ra sao
	local demoButton = C.button({
		Name = "DemoBuild",
		Text = "Bot xây mẫu (Studio)",
		Variant = "violet",
		TextSize = 12,
		Size = UDim2.new(1, 0, 0, 36),
		PadLeft = 24,
		LayoutOrder = 0,
		Parent = content,
	}, function()
		if not finished then
			ctx.onDemoBuild()
		end
	end)
	Icons.draw("bot", { Size = 16, Color = Colors.onAccent, Position = UDim2.new(0, -12, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = demoButton })
	demoButton.Visible = false

	-- Loại đất + mẫu của loại đang mở ----------------------------------------
	local renderTools
	local chips = C.new("Frame", { Name = "Categories", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, CHIP_H + 4), LayoutOrder = 1, Parent = content })
	local chipGrid = Instance.new("UIGridLayout")
	local count = #Config.CATEGORY_ORDER + 1
	chipGrid.CellSize = UDim2.new(1 / count, -4, 0, CHIP_H)
	chipGrid.CellPadding = UDim2.fromOffset(4, 0)
	chipGrid.SortOrder = Enum.SortOrder.LayoutOrder
	chipGrid.VerticalAlignment = Enum.VerticalAlignment.Center
	chipGrid.Parent = chips
	local chipButtons = {}
	local function onChip(cat)
		if finished then
			return
		end
		if cat == "demolish" then
			ctx.onSelectTool("demolish")
			return
		end
		local current = obj.tool and Config.BUILDINGS[obj.tool]
		obj.category = cat
		-- bấm lại loại đang chọn thì bỏ chọn, loại khác thì mở ra và chọn sẵn mẫu chuẩn
		ctx.onSelectTool((current and current.kind == cat) and obj.tool or cat)
		renderTools(obj.session)
	end
	for order, cat in ipairs(Config.CATEGORY_ORDER) do
		local info = Config.CATEGORIES[cat]
		local chip = C.button({ Name = "Cat_" .. cat, Text = info.code, Font = Theme.FontDisplay, TextSize = 13, Color = Theme.land(cat), TextColor = Theme.landInk(cat), Size = UDim2.fromOffset(32, CHIP_H), Radius = 10, LayoutOrder = order, Parent = chips }, function()
			onChip(cat)
		end)
		C.stroke(Colors.text, 2.5, 1).Parent = chip
		chipButtons[cat] = chip
	end
	chipButtons.demolish = C.button({ Name = "Tool_demolish", Text = "PD", Font = Theme.FontDisplay, TextSize = 13, Variant = "white", Size = UDim2.fromOffset(32, CHIP_H), Radius = 10, LayoutOrder = count, Parent = chips }, function()
		onChip("demolish")
	end)
	local zoneLabel = C.label({ Name = "Zone", Text = "", Font = Theme.FontBold, TextSize = 12, Color = Colors.textDim, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 2, Parent = content })

	local variants = C.new("Frame", { Name = "Variants", BackgroundTransparency = 1, Size = inner, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, Parent = content })
	C.list(Enum.FillDirection.Vertical, 6).Parent = variants
	local rows = {}
	local order = 0
	for _, cat in ipairs(Config.CATEGORY_ORDER) do
		for _, id in ipairs(Config.VARIANTS[cat]) do
			order = order + 1
			local def = Config.BUILDINGS[id]
			local row = C.button({ Name = "Tool_" .. id, Text = "", Variant = "white", Lip = false, Size = UDim2.new(1, 0, 0, ROW_H), Radius = 14, LayoutOrder = order, Parent = variants }, function()
				if not finished then
					ctx.onSelectTool(id)
				end
			end)
			swatch(row, id, UDim2.fromOffset(38, 38))
			C.label({ Name = "Title", Text = def.label .. (def.size > 1 and string.format(" %dx%d", def.size, def.size) or ""), Font = Theme.FontBold, TextSize = 14, Truncate = true, Size = UDim2.new(1, -100, 0, 18), Position = UDim2.fromOffset(56, 8), Parent = row })
			C.label({ Name = "Price", Text = "", Font = Theme.FontBold, TextSize = 12, Color = Colors.textDim, Size = UDim2.new(0.4, -24, 0, 16), Position = UDim2.fromOffset(56, 28), Parent = row })
			C.label({ Name = "Stat", Text = keyStat(def), Font = Theme.FontMedium, TextSize = 12, Color = Colors.textDim, XAlign = Enum.TextXAlignment.Right, Truncate = true, Size = UDim2.new(0.6, -50, 0, 16), Position = UDim2.new(0.4, 6, 0, 28), Parent = row })
			-- nút "i" mở thẻ thông tin mẫu, ván kết thúc rồi vẫn xem được
			C.button({ Name = "Info_" .. id, Text = "i", Font = Theme.FontDisplay, TextSize = 14, Variant = "secondary", Lip = false, Size = UDim2.fromOffset(28, 28), Radius = 14, Position = UDim2.new(1, -36, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = row }, function()
				ctx.onInfo(id)
			end)
			rows[id] = row
		end
	end
	-- chú thích gạch sọc = lô chưa nối đường
	local hatchRow = C.new("Frame", { Name = "HatchLegend", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 4, Parent = content })
	local hatchSwatch = C.new("Frame", { BackgroundColor3 = Theme.land("house"), BorderSizePixel = 0, ClipsDescendants = true, Size = UDim2.fromOffset(32, 24), Position = UDim2.new(0, 2, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = hatchRow })
	C.corner(8).Parent = hatchSwatch
	for k = 0, 3 do
		C.new("Frame", { BackgroundColor3 = Colors.text, BackgroundTransparency = 0.55, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2), Position = UDim2.fromOffset(0, 4 + k * 5), Parent = hatchSwatch })
	end
	C.label({ Text = "Gạch sọc + dấu ! đỏ: chưa nối đường về CỔNG", TextSize = 12, Color = Colors.textDim, Size = UDim2.new(1, -44, 1, 0), Position = UDim2.fromOffset(42, 0), Parent = hatchRow })
	C.label({
		Text = "Chọn loại đất và mẫu rồi bấm vào ô (mẫu 2x2 thì ô bấm là góc trên bên trái). Bấm i để xem số liệu. Đường: giữ chuột và kéo từ CỔNG.",
		TextSize = 12,
		Color = Colors.textMuted,
		Wrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = inner,
		LayoutOrder = 5,
		Parent = content,
	})

	-- Thuế, slider 0-50% ----------------------------------------------------------
	local taxCard = C.well({ Name = "TaxCard", Size = inner, AutomaticSize = Enum.AutomaticSize.Y, Radius = 16, LayoutOrder = 7, Parent = content })
	C.padding(12, 14).Parent = taxCard
	C.list(Enum.FillDirection.Vertical, 6).Parent = taxCard
	local taxBlock = C.new("Frame", { Name = "Tax", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 92), LayoutOrder = 1, Parent = taxCard })
	C.label({ Text = "Thuế", Font = Theme.FontDisplay, TextSize = 15, Size = UDim2.new(0.6, 0, 0, 26), Parent = taxBlock })
	local taxValue = C.pill({ Name = "TaxValue", Text = "", Font = Theme.FontDisplay, TextSize = 15, Color = Colors.panel, TextColor = Colors.accent, Height = 26, Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = taxBlock })
	local pendingTax = nil
	local taxToken = 0
	local slider = C.slider({
		min = 0,
		max = Config.TAX_MAX,
		step = 1,
		ticks = 5,
		labelEvery = 10,
		value = Config.START_TAX,
		onChanged = function(v)
			taxValue.Text = string.format("%d%%", v)
			pendingTax = v
			taxToken = taxToken + 1
			local myToken = taxToken
			task.delay(TAX_SEND_DELAY, function()
				if myToken ~= taxToken then
					return -- vẫn đang kéo
				end
				local ok, err = ctx.onSetTax(v)
				if myToken == taxToken then
					pendingTax = nil
				end
				if not ok and err then
					taxValue.Text = err
				end
			end)
		end,
	})
	slider.frame.Position = UDim2.fromOffset(0, 32)
	slider.frame.Parent = taxBlock
	C.label({ Text = "Thấp: dân vui hơn", Font = Theme.FontMedium, TextSize = 11, Color = Colors.good, Size = UDim2.new(0.5, 0, 0, 14), Position = UDim2.fromOffset(0, 76), Parent = taxBlock })
	C.label({ Text = "Cao: dân bỏ đi", Font = Theme.FontMedium, TextSize = 11, Color = Colors.bad, XAlign = Enum.TextXAlignment.Right, Size = UDim2.new(0.5, 0, 0, 14), Position = UDim2.new(0.5, 0, 0, 76), Parent = taxBlock })

	local money = C.label({ Name = "Money", Text = "", Font = Theme.FontMedium, TextSize = 12, Color = Colors.textDim, Wrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2, Parent = taxCard })

	-- Bảng tính hạnh phúc ---------------------------------------------------------------------
	local why = C.well({ Name = "Why", Size = inner, AutomaticSize = Enum.AutomaticSize.Y, Radius = 16, LayoutOrder = 10, Parent = content })
	C.padding(12, 14).Parent = why
	C.list(Enum.FillDirection.Vertical, 0).Parent = why
	local head = sectionHeader(why, "Bảng tính hạnh phúc", 0)
	head:FindFirstChild("Heading").Name = "WhyTitle"
	local whyValue = C.pill({ Name = "WhyValue", Text = "", Font = Theme.FontDisplay, TextSize = 15, Color = Colors.panel, TextColor = Colors.good, Height = 26, Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = head })
	C.new("Frame", { Name = "Gap", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 6), LayoutOrder = 1, Parent = why })
	local whyRows = {}
	for i = 1, 5 do
		local total = i == 5
		local row = C.new("Frame", { Name = "Row" .. i, BackgroundColor3 = Colors.panel, BackgroundTransparency = total and 0 or 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, total and 30 or 24), LayoutOrder = i * 2, Parent = why })
		if total then
			C.corner(10).Parent = row
			C.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = row })
		end
		whyRows[i] = {
			frame = row,
			name = C.label({ Text = "", TextSize = 12, Font = total and Theme.FontBold or Theme.FontMedium, Size = UDim2.new(0, 72, 1, 0), Parent = row }),
			formula = C.label({ Text = "", TextSize = 11, Font = Theme.FontMedium, Color = Colors.textMuted, Truncate = true, Size = UDim2.new(1, -124, 1, 0), Position = UDim2.fromOffset(72, 0), Parent = row }),
			value = C.label({ Text = "", TextSize = 12, Font = Theme.FontBold, XAlign = Enum.TextXAlignment.Right, Size = UDim2.new(0, 50, 1, 0), Position = UDim2.new(1, -50, 0, 0), Parent = row }),
			line = C.new("Frame", { Name = "Rule", BackgroundColor3 = Colors.stroke, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1), LayoutOrder = i * 2 + 1, Visible = i < 4, Parent = why }),
		}
	end
	local capNote = C.label({ Text = "", TextSize = 11, Color = Colors.textMuted, Wrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 20, Parent = why })
	C.new("UIPadding", { PaddingTop = UDim.new(0, 6), Parent = capNote })

	local function setRow(i, name, formula, value)
		local r = whyRows[i]
		r.frame.Visible = name ~= nil
		r.line.Visible = name ~= nil and i < 4
		r.name.Text = name or ""
		r.formula.Text = formula or ""
		r.value.Text = value or ""
	end

	renderTools = function(session)
		for id, row in pairs(rows) do
			local def = Config.BUILDINGS[id]
			row.Visible = def.kind == obj.category
			local price = session and CityEngine.priceOf(session, id) or def.price
			local short = session ~= nil and session.budget < price
			-- thiếu tiền: hiện số còn thiếu, làm nhạt tên, ô màu đất giữ nguyên
			local priceLabel = row:FindFirstChild("Price")
			priceLabel.Text = short and ("thiếu " .. Util.formatMoneyFull(price - session.budget)) or Util.formatMoneyFull(price)
			priceLabel.TextColor3 = short and Colors.bad or Colors.warn
			row:FindFirstChild("Title").TextColor3 = short and Colors.textMuted or Colors.text
			local selected = obj.tool == id
			C.setButtonColor(row, selected and Colors.accentSoft or Colors.panel)
			local stroke = row:FindFirstChildOfClass("UIStroke")
			stroke.Color = selected and Colors.accent or Colors.stroke
			stroke.Thickness = selected and 2 or 1.5
			C.setEnabled(row, not finished)
		end
		for cat, chip in pairs(chipButtons) do
			-- ô đang mở (hoặc PD khi đang phá dỡ) có viền đậm
			local on = (obj.tool == "demolish") == (cat == "demolish") and (cat == "demolish" or cat == obj.category)
			local stroke = chip:FindFirstChildOfClass("UIStroke")
			stroke.Color = on and Colors.text or (cat == "demolish" and Colors.stroke or Colors.text)
			stroke.Thickness = on and 2.5 or 1.5
			stroke.Transparency = (on or cat == "demolish") and 0 or 1
			C.setEnabled(chip, not finished)
		end
		local info = Config.CATEGORIES[obj.category]
		zoneLabel.Text = string.format("%s - %s, %d mẫu", info.code, info.zone, #Config.VARIANTS[obj.category])
		local def = obj.tool and Config.BUILDINGS[obj.tool]
		if obj.tool == "demolish" then
			toolLabel.Text = "Đang chọn: Phá dỡ"
			toolLabel.BackgroundColor3 = soft(Colors.danger)
			toolLabel.TextColor3 = Colors.bad
		elseif def then
			toolLabel.Text = "Đang chọn: " .. def.label
			toolLabel.BackgroundColor3 = Colors.accentSoft
			toolLabel.TextColor3 = Colors.accent
		else
			toolLabel.Text = ""
		end
		toolLabel.Visible = toolLabel.Text ~= ""
	end

	function obj.setTool(tool)
		obj.tool = tool
		local def = tool and Config.BUILDINGS[tool]
		if def then
			obj.category = def.kind
		end
		renderTools(obj.session)
	end

	function obj.update(snap)
		local s = snap.session
		if not s or type(s.cells) ~= "table" then
			return
		end
		obj.session = s
		finished = s.status == "ENDED" or s.status == "FAILED"
		demoButton.Visible = snap.isStudio == true
		C.setEnabled(demoButton, not finished)
		renderTools(s)
		slider.setEnabled(not finished)
		if not pendingTax then
			slider.set(s.tax, true)
			taxValue.Text = string.format("%d%%", s.tax)
		end
		local t = slider.get()
		slider.setColor(t <= 20 and Colors.success or (t <= 35 and Colors.amber or Colors.danger))

		local d = CityEngine.compute(s, s.population)
		-- số ròng đã có ở thẻ thành phố, ở đây tách thu thuế và bảo trì ra để thấy thuế tác động ra sao
		money.Text = string.format("Mỗi tháng: thu thuế %s, bảo trì %s", Util.formatMoneyFull(d.taxIn), Util.formatMoneyFull(d.M))

		local F = Config.FORMULA
		local A = CityEngine.attraction(s.happiness)
		local target = CityEngine.targetPop(d.C, d.J, s.happiness)
		whyValue.Text = tostring(Util.round(d.H))
		whyValue.TextColor3 = Theme.happinessColor(d.H)
		setRow(1, "Việc làm", string.format("%s × %d", fmt(F.happinessEmploymentWeight, 2), Util.round(d.E)), fmt(d.parts.E, 1))
		setRow(2, "Thuế", string.format("%s × (100 - 2×%d)", fmt(F.happinessTaxWeight, 2), s.tax), fmt(d.parts.T, 1))
		setRow(3, "Dịch vụ", string.format("%s × %d", fmt(F.happinessServiceWeight, 2), Util.round(d.S)), fmt(d.parts.S, 1))
		if d.parts.event ~= 0 then
			setRow(4, "Sự kiện", "", fmt(d.parts.event, 0))
		else
			setRow(4, nil)
		end
		setRow(5, "Muốn đến", string.format("%s × %s việc", fmt(A, 2), Util.formatInt(d.J)), Util.formatInt(target))
		-- bị chặn bởi số chỗ ở thì ghi rõ, không thì phép nhân ở trên nhìn như tính sai
		if target < math.floor(d.J * A) then
			capNote.Text = string.format("Không quá số chỗ ở (%s). Tính theo hạnh phúc tháng trước: %d.", Util.formatInt(d.C), Util.round(s.happiness))
		else
			capNote.Text = string.format("Tính theo hạnh phúc tháng trước (%d), dưới 50 thì không ai đến.", Util.round(s.happiness))
		end
	end

	function obj.setVisible(visible)
		panel.Visible = visible
		if visible then
			C.popIn(panel, 0.96, 0.18)
		end
	end

	-- maxHeight theo đơn vị thiết kế, màn thấp thì nội dung cuộn
	function obj.setMaxHeight(maxHeight)
		local h = math.max(260, math.min(FULL_HEIGHT, maxHeight))
		panel.Size = UDim2.fromOffset(WIDTH, h)
		content.Size = UDim2.new(1, -16, 0, h - HEADER - 10)
	end

	renderTools(nil)
	return obj
end

BuildPanel.WIDTH = WIDTH
BuildPanel.FULL_HEIGHT = FULL_HEIGHT
BuildPanel.TOP = TOP
return BuildPanel
