-- Màu, phông, bo góc dùng chung cho UI.
-- Màu đất chỉ lấy từ Config.BUILDINGS[...].color (ô chọn loại đất, lô đất, nhà trên sa bàn), đừng khai báo lại ở đây.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("EconCity"):WaitForChild("Config"))

local Theme = {}

-- Builder Sans có sẵn trong Roblox, đủ dấu tiếng Việt. số dùng Bold, không cần monospace
Theme.Font = Enum.Font.BuilderSans
Theme.FontMedium = Enum.Font.BuilderSansMedium
Theme.FontBold = Enum.Font.BuilderSansBold
Theme.FontDisplay = Enum.Font.BuilderSansExtraBold
Theme.FontNumber = Enum.Font.BuilderSansBold

local rgb = Color3.fromRGB

Theme.Colors = {
	panel = rgb(255, 255, 255),
	panelAlt = rgb(242, 245, 250), -- ô lót trong thẻ, nút phụ
	panelHover = rgb(232, 238, 247),
	stroke = rgb(219, 226, 236), -- viền, đường kẻ mảnh
	strokeStrong = rgb(196, 206, 220),
	rule = rgb(231, 236, 243),
	shadow = rgb(11, 18, 32), -- viền bóng quanh thẻ, đi với transparency cao
	overlay = rgb(12, 20, 36), -- nền che sau modal

	text = rgb(24, 34, 52),
	textDim = rgb(84, 98, 120),
	textMuted = rgb(103, 117, 138), -- contrast >= 4.5:1 trên nền trắng
	onAccent = rgb(255, 255, 255),

	-- accent: ô đang chọn, tab, slider
	accent = rgb(46, 107, 255),
	accentDark = rgb(29, 79, 216),
	accentSoft = rgb(229, 237, 255),

	success = rgb(34, 179, 94), -- nút Bắt đầu / Chạy tiếp / Chơi ván mới
	successDark = rgb(22, 135, 69),
	amber = rgb(245, 165, 36), -- Tạm dừng
	amberDark = rgb(199, 124, 14),
	danger = rgb(229, 72, 77),
	dangerDark = rgb(184, 42, 48),
	violet = rgb(124, 92, 255), -- nút bot xây mẫu, chỉ có trong Studio
	violetDark = rgb(93, 64, 214),

	good = rgb(26, 158, 85),
	warn = rgb(196, 120, 0),
	bad = rgb(224, 54, 74),
	info = rgb(46, 107, 255),
	stamp = rgb(229, 72, 77), -- ô "!" và viền phá sản (tên cũ)
	highlight = rgb(229, 237, 255), -- dòng "Bạn" trên bảng xếp hạng
	track = rgb(227, 232, 240),

	-- màu icon của từng chỉ số
	gold = rgb(245, 179, 1),
	goldSoft = rgb(255, 245, 214),
	people = rgb(124, 92, 255),
	peopleSoft = rgb(238, 234, 255),
	jobs = rgb(20, 160, 200),
	jobsSoft = rgb(223, 244, 250),
	mood = rgb(240, 80, 122),
	moodSoft = rgb(253, 231, 238),
}

Theme.Radius = { sm = 8, md = 12, lg = 16, xl = 20 }
Theme.PanelTransparency = 0
Theme.FrameThickness = 1.5 -- viền bóng quanh thẻ
Theme.LineThickness = 1

-- t < 1 thì pha với trắng (nhà trên sa bàn dùng màu nhạt)
function Theme.land(kind, t)
	local def = Config.BUILDINGS[kind]
	local c = def and rgb(def.color[1], def.color[2], def.color[3]) or Theme.Colors.textMuted
	if t and t < 1 then
		return Color3.new(1, 1, 1):Lerp(c, t)
	end
	return c
end

-- màu chữ đặt trên ô màu đất
function Theme.landInk(kind)
	local def = Config.BUILDINGS[kind]
	return (def and def.inkLight) and rgb(255, 255, 255) or Theme.Colors.text
end

-- dùng cho gờ nổi dưới nút
function Theme.darken(c, amount)
	return c:Lerp(Color3.new(0, 0, 0), amount or 0.22)
end

-- h: 0-100. dưới 50 là đỏ vì không ai chuyển đến nữa (docs/luat-choi-moi.md mục 4)
function Theme.happinessColor(h)
	if h >= 65 then
		return Theme.Colors.good
	elseif h >= 50 then
		return Theme.Colors.warn
	end
	return Theme.Colors.bad
end

Theme.StatusText = {
	ACTIVE = "Đang chạy",
	PAUSED = "Tạm dừng",
	ENDED = "Đã kết thúc",
	FAILED = "Phá sản",
}

-- chữ trên thanh điều khiển, viết kiểu câu như phần còn lại của UI
Theme.StatusTitle = {
	ACTIVE = "Đang chạy",
	PAUSED = "Tạm dừng",
	ENDED = "Đã kết thúc",
	FAILED = "Phá sản",
}

function Theme.statusColor(status)
	if status == "ACTIVE" then
		return Theme.Colors.good
	elseif status == "PAUSED" then
		return Theme.Colors.amber
	elseif status == "ENDED" then
		return Theme.Colors.info
	end
	return Theme.Colors.bad
end

return Theme
