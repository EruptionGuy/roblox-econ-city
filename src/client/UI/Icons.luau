-- icon vẽ bằng Frame/viền/chữ, mỗi cái nằm trong ô vuông size x size.
-- chưa upload ảnh lên Roblox nên không dùng ảnh, emoji thì mỗi máy hiện một kiểu nên cũng bỏ

local Theme = require(script.Parent:WaitForChild("Theme"))
local C = require(script.Parent:WaitForChild("Components"))
local Colors = Theme.Colors

local Icons = {}

local function rect(parent, x, y, w, h, color, radius, props)
	local f = C.new("Frame", {
		Name = props and props.Name or "Shape",
		BackgroundColor3 = color,
		BackgroundTransparency = props and props.Transparency or 0,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(w, h),
		Position = UDim2.fromOffset(x, y),
		AnchorPoint = props and props.AnchorPoint or Vector2.new(0, 0),
		Rotation = props and props.Rotation or 0,
		ZIndex = parent.ZIndex,
		ClipsDescendants = props and props.Clip or false,
		Parent = parent,
	})
	if radius == "full" then
		C.round().Parent = f
	elseif radius and radius > 0 then
		C.corner(radius).Parent = f
	end
	return f
end

local function ring(parent, x, y, d, color, thickness)
	local f = rect(parent, x, y, d, d, color, "full", { Transparency = 1, Name = "Ring" })
	C.stroke(color, thickness).Parent = f
	return f
end

local function glyph(parent, text, color, size, s)
	return C.label({
		Name = "Glyph",
		Text = text,
		Font = Theme.FontDisplay,
		TextSize = size,
		Color = color,
		XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(s, s),
		ZIndex = parent.ZIndex,
		Parent = parent,
	})
end

-- tam giác trỏ phải ghép từ các cột thấp dần, không dùng xoay vì sẽ bị cắt méo
local function triangle(parent, x0, width, s, color, columns)
	local n = columns or 5
	local cw = width / n
	for k = 0, n - 1 do
		local h = s * 0.62 * (1 - k / n)
		rect(parent, math.floor(x0 + k * cw), math.floor((s - h) / 2), math.ceil(cw) + 1, math.max(2, math.floor(h)), color, 0)
	end
end

local function mouth(icon, mood)
	local old = icon:FindFirstChild("Mouth")
	if old then
		old:Destroy()
	end
	local s = icon:GetAttribute("IconSize") or 20
	local white = Colors.panel
	local t = math.max(1.5, s / 11)
	if mood == "happy" then
		-- miệng cười: nửa dưới vòng tròn
		local clip = rect(icon, math.floor(s * 0.26), math.floor(s * 0.5), math.ceil(s * 0.48), math.ceil(s * 0.3), white, 0, { Name = "Mouth", Transparency = 1, Clip = true })
		ring(clip, 0, -math.floor(s * 0.24), math.ceil(s * 0.48), white, t)
	elseif mood == "sad" then
		local clip = rect(icon, math.floor(s * 0.28), math.floor(s * 0.62), math.ceil(s * 0.44), math.ceil(s * 0.2), white, 0, { Name = "Mouth", Transparency = 1, Clip = true })
		ring(clip, 0, 2, math.ceil(s * 0.44), white, t)
	else
		rect(icon, math.floor(s * 0.3), math.floor(s * 0.64), math.ceil(s * 0.4), math.max(2, math.floor(t)), white, "full", { Name = "Mouth" })
	end
end

local DRAW = {}

DRAW.coin = function(f, s, color)
	rect(f, 0, 0, s, s, color, "full")
	ring(f, math.floor(s * 0.16), math.floor(s * 0.16), math.ceil(s * 0.68), Theme.darken(color, 0.18), 1.5)
	glyph(f, "$", Theme.darken(color, 0.45), math.floor(s * 0.56), s)
end

DRAW.people = function(f, s, color)
	-- người sau nhạt, người trước đậm
	rect(f, math.floor(s * 0.56), math.floor(s * 0.12), math.ceil(s * 0.3), math.ceil(s * 0.3), color, "full", { Transparency = 0.4 })
	rect(f, math.floor(s * 0.48), math.floor(s * 0.48), math.ceil(s * 0.48), math.ceil(s * 0.4), color, math.floor(s * 0.2), { Transparency = 0.4 })
	rect(f, math.floor(s * 0.14), math.floor(s * 0.06), math.ceil(s * 0.38), math.ceil(s * 0.38), color, "full")
	rect(f, math.floor(s * 0.02), math.floor(s * 0.5), math.ceil(s * 0.62), math.ceil(s * 0.44), color, math.floor(s * 0.22))
end

DRAW.briefcase = function(f, s, color)
	local handle = rect(f, math.floor(s * 0.32), math.floor(s * 0.08), math.ceil(s * 0.36), math.ceil(s * 0.28), color, math.max(2, math.floor(s * 0.1)), { Transparency = 1 })
	C.stroke(color, math.max(1.5, s / 10)).Parent = handle
	rect(f, math.floor(s * 0.04), math.floor(s * 0.3), math.ceil(s * 0.92), math.ceil(s * 0.6), color, math.max(2, math.floor(s * 0.16)))
	rect(f, math.floor(s * 0.04), math.floor(s * 0.52), math.ceil(s * 0.92), math.max(1, math.floor(s * 0.08)), Colors.panel, 0, { Transparency = 0.45 })
end

DRAW.face = function(f, s, color, mood)
	rect(f, 0, 0, s, s, color, "full", { Name = "Face" })
	local e = math.max(2, math.floor(s * 0.13))
	rect(f, math.floor(s * 0.3), math.floor(s * 0.3), e, e, Colors.panel, "full")
	rect(f, math.floor(s * 0.57), math.floor(s * 0.3), e, e, Colors.panel, "full")
	f:SetAttribute("Mood", mood or "happy")
	mouth(f, mood or "happy")
end

DRAW.heart = function(f, s, color)
	local d = math.ceil(s * 0.5)
	rect(f, math.floor(s * 0.04), math.floor(s * 0.1), d, d, color, "full")
	rect(f, math.floor(s * 0.46), math.floor(s * 0.1), d, d, color, "full")
	rect(f, math.floor(s * 0.5), math.floor(s * 0.52), math.ceil(s * 0.52), math.ceil(s * 0.52), color, math.max(1, math.floor(s * 0.06)), { Rotation = 45, AnchorPoint = Vector2.new(0.5, 0.5) })
end

DRAW.box = function(f, s, color)
	rect(f, math.floor(s * 0.1), math.floor(s * 0.32), math.ceil(s * 0.8), math.ceil(s * 0.6), color, math.max(2, math.floor(s * 0.1)))
	rect(f, math.floor(s * 0.04), math.floor(s * 0.14), math.ceil(s * 0.92), math.ceil(s * 0.24), Theme.darken(color, 0.12), math.max(2, math.floor(s * 0.08)))
	rect(f, math.floor(s * 0.43), math.floor(s * 0.14), math.ceil(s * 0.14), math.ceil(s * 0.78), Colors.panel, 0, { Transparency = 0.5 })
end

DRAW.clock = function(f, s, color)
	ring(f, 1, 1, s - 2, color, math.max(1.5, s / 10))
	local t = math.max(2, math.floor(s * 0.12))
	rect(f, math.floor(s / 2 - t / 2), math.floor(s * 0.24), t, math.ceil(s * 0.3), color, "full")
	rect(f, math.floor(s / 2 - t / 2), math.floor(s / 2 - t / 2), math.ceil(s * 0.26), t, color, "full")
end

DRAW.chart = function(f, s, color)
	local w = math.ceil(s * 0.24)
	local heights = { 0.42, 0.68, 0.92 }
	for k, hf in ipairs(heights) do
		local h = math.ceil(s * hf)
		rect(f, math.floor(s * (0.04 + (k - 1) * 0.34)), s - h, w, h, color, math.max(1, math.floor(s * 0.08)))
	end
end

DRAW.podium = function(f, s, color)
	local w = math.ceil(s * 0.3)
	local spec = { { 0.02, 0.56, 0.45 }, { 0.35, 0.92, 0 }, { 0.68, 0.4, 0.45 } }
	for _, p in ipairs(spec) do
		local h = math.ceil(s * p[2])
		rect(f, math.floor(s * p[1]), s - h, w, h, color, math.max(1, math.floor(s * 0.08)), { Transparency = p[3] })
	end
end

DRAW.grid = function(f, s, color)
	local d = math.ceil(s * 0.42)
	local r = math.max(2, math.floor(s * 0.12))
	rect(f, 0, 0, d, d, color, r)
	rect(f, s - d, 0, d, d, color, r, { Transparency = 0.45 })
	rect(f, 0, s - d, d, d, color, r, { Transparency = 0.45 })
	rect(f, s - d, s - d, d, d, color, r)
end

DRAW.check = function(f, s, color)
	local t = math.max(2, math.floor(s * 0.16))
	rect(f, math.floor(s * 0.36), math.floor(s * 0.62), math.ceil(s * 0.34), t, color, "full", { Rotation = 45, AnchorPoint = Vector2.new(0.5, 0.5) })
	rect(f, math.floor(s * 0.6), math.floor(s * 0.48), math.ceil(s * 0.6), t, color, "full", { Rotation = -52, AnchorPoint = Vector2.new(0.5, 0.5) })
end

DRAW.play = function(f, s, color)
	triangle(f, s * 0.24, s * 0.6, s, color, 9)
end

DRAW.pause = function(f, s, color)
	local w = math.ceil(s * 0.2)
	local h = math.ceil(s * 0.62)
	local y = math.floor((s - h) / 2)
	rect(f, math.floor(s * 0.24), y, w, h, color, math.max(1, math.floor(w / 3)))
	rect(f, math.floor(s * 0.56), y, w, h, color, math.max(1, math.floor(w / 3)))
end

DRAW.forward = function(f, s, color)
	triangle(f, s * 0.1, s * 0.4, s, color, 4)
	triangle(f, s * 0.5, s * 0.4, s, color, 4)
end

DRAW.alert = function(f, s, color)
	rect(f, 0, 0, s, s, color, "full")
	glyph(f, "!", Colors.panel, math.floor(s * 0.68), s)
end

DRAW.info = function(f, s, color)
	rect(f, 0, 0, s, s, color, "full")
	glyph(f, "i", Colors.panel, math.floor(s * 0.66), s)
end

DRAW.trophy = function(f, s, color)
	rect(f, math.floor(s * 0.2), math.floor(s * 0.06), math.ceil(s * 0.6), math.ceil(s * 0.46), color, math.max(2, math.floor(s * 0.2)))
	rect(f, math.floor(s * 0.44), math.floor(s * 0.48), math.ceil(s * 0.12), math.ceil(s * 0.24), color, 0)
	rect(f, math.floor(s * 0.26), math.floor(s * 0.72), math.ceil(s * 0.48), math.ceil(s * 0.16), color, math.max(1, math.floor(s * 0.06)))
	ring(f, math.floor(s * 0.04), math.floor(s * 0.12), math.ceil(s * 0.3), color, math.max(1.5, s / 14))
	ring(f, math.floor(s * 0.66), math.floor(s * 0.12), math.ceil(s * 0.3), color, math.max(1.5, s / 14))
end

DRAW.bot = function(f, s, color)
	rect(f, math.floor(s * 0.46), 0, math.ceil(s * 0.08), math.ceil(s * 0.2), color, 0)
	rect(f, math.floor(s * 0.4), 0, math.ceil(s * 0.2), math.ceil(s * 0.14), color, "full")
	rect(f, math.floor(s * 0.08), math.floor(s * 0.18), math.ceil(s * 0.84), math.ceil(s * 0.7), color, math.max(2, math.floor(s * 0.2)))
	local e = math.max(2, math.floor(s * 0.16))
	rect(f, math.floor(s * 0.26), math.floor(s * 0.42), e, e, Colors.panel, "full")
	rect(f, math.floor(s * 0.58), math.floor(s * 0.42), e, e, Colors.panel, "full")
end

DRAW.map = function(f, s, color)
	-- bản đồ gấp 3 nếp
	local w = math.ceil(s * 0.3)
	rect(f, math.floor(s * 0.04), math.floor(s * 0.1), w, math.ceil(s * 0.8), color, math.max(1, math.floor(s * 0.06)))
	rect(f, math.floor(s * 0.35), math.floor(s * 0.04), w, math.ceil(s * 0.8), color, math.max(1, math.floor(s * 0.06)), { Transparency = 0.4 })
	rect(f, math.floor(s * 0.66), math.floor(s * 0.1), w, math.ceil(s * 0.8), color, math.max(1, math.floor(s * 0.06)))
end

function Icons.draw(name, props)
	props = props or {}
	local s = props.Size or 20
	local f = C.new("Frame", {
		Name = props.Name or ("Icon_" .. name),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(s, s),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		ZIndex = props.ZIndex or 1,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	f:SetAttribute("IconSize", s)
	f:SetAttribute("IconName", name)
	local fn = DRAW[name]
	if fn then
		fn(f, s, props.Color or Colors.text, props.Mood)
	end
	return f
end

-- icon trên nền tròn nhạt, trả về holder, icon
function Icons.badge(name, props)
	props = props or {}
	local size = props.Size or 32
	local holder = C.new("Frame", {
		Name = props.Name or "Badge",
		BackgroundColor3 = props.Soft or Colors.panelAlt,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		ZIndex = props.ZIndex or 1,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	if props.Square then
		C.corner(math.floor(size * 0.3)).Parent = holder
	else
		C.round().Parent = holder
	end
	local iconSize = props.IconSize or math.floor(size * 0.56)
	local icon = Icons.draw(name, {
		Name = "Icon",
		Size = iconSize,
		Color = props.Color,
		Mood = props.Mood,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = holder.ZIndex,
		Parent = holder,
	})
	return holder, icon
end

-- mood: "happy" | "neutral" | "sad"
function Icons.setMood(icon, mood)
	if icon:GetAttribute("Mood") == mood then
		return
	end
	icon:SetAttribute("Mood", mood)
	mouth(icon, mood)
end

-- giữ nguyên phần trắng
function Icons.setColor(icon, color)
	for _, d in ipairs(icon:GetDescendants()) do
		if d:IsA("Frame") and d.Name ~= "Mouth" and d.BackgroundColor3 ~= Colors.panel then
			d.BackgroundColor3 = color
		elseif d:IsA("UIStroke") and d.Parent and d.Parent.Name == "Ring" and d.Parent.Parent ~= nil and d.Parent.Parent.Name ~= "Mouth" then
			d.Color = color
		end
	end
end

return Icons
