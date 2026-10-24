-- các khối UI dùng lại: thẻ, nhãn, nút, slider, nút +/-, tab, modal, ô nhập. màu/phông lấy từ Theme

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Colors = Theme.Colors

local C = {}

-- Gamepad ------------------------------------------------------
-- chỉ bật Selectable khi đang dùng gamepad. với bàn phím phải tắt,
-- vì phím \ rồi Enter của Roblox từng bấm nhầm nút (vd. nút đi dạo)
local selectables = setmetatable({}, { __mode = "k" })
local gamepadMode = false

local function isGamepadInput(inputType)
	local ok, name = pcall(function()
		return inputType.Name
	end)
	return ok and type(name) == "string" and name:sub(1, 7) == "Gamepad"
end

pcall(function()
	gamepadMode = isGamepadInput(UserInputService:GetLastInputType())
end)

function C.selectable(obj)
	selectables[obj] = true
	obj.Selectable = gamepadMode
	return obj
end

function C.isGamepadMode()
	return gamepadMode
end

function C.setGamepadMode(on)
	gamepadMode = on
	for obj in pairs(selectables) do
		if obj.Parent then
			obj.Selectable = on
		end
	end
	if not on then
		pcall(function()
			GuiService.SelectedObject = nil
		end)
	end
end

pcall(function()
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local on = isGamepadInput(inputType)
		if on ~= gamepadMode then
			C.setGamepadMode(on)
		end
	end)
end)

-- chọn sẵn nút khi mở bảng, chỉ khi đang dùng gamepad
function C.focus(obj)
	if gamepadMode and obj then
		pcall(function()
			GuiService.SelectedObject = obj
		end)
	end
end

-- cỡ chữ tối thiểu, tính theo đơn vị thiết kế. màn hẹp đặt 13 (khoảng 9px ở UIScale 0.72)
-- cỡ gốc lưu ở attribute BaseTextSize để trả lại khi màn rộng ra
local textFloor = 0
local texts = setmetatable({}, { __mode = "k" })

local function applyFloor(inst)
	local base = inst:GetAttribute("BaseTextSize") or inst.TextSize
	inst:SetAttribute("BaseTextSize", base)
	inst.TextSize = math.max(base, textFloor)
end

local function trackText(inst)
	texts[inst] = true
	applyFloor(inst)
	return inst
end

function C.setTextFloor(size)
	if size == textFloor then
		return
	end
	textFloor = size
	for inst in pairs(texts) do
		if inst.Parent then
			applyFloor(inst)
		end
	end
end

-- Parent gán sau cùng
function C.new(className, props, children)
	local inst = Instance.new(className)
	local parent = nil
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			inst[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- radius tính bằng px, mặc định 12
function C.corner(radius)
	return C.new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Radius.md) })
end

-- bo tròn hẳn 2 đầu (pill / tròn)
function C.round()
	return C.new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function C.stroke(color, thickness, transparency)
	return C.new("UIStroke", {
		Color = color or Colors.stroke,
		Thickness = thickness or Theme.LineThickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

-- viền mờ để thẻ trắng tách khỏi thành phố phía sau
function C.shadowStroke(thickness, transparency)
	local s = C.stroke(Colors.shadow, thickness or Theme.FrameThickness, transparency or 0.86)
	s.Name = "Shadow"
	return s
end

function C.padding(all, horizontal)
	local v = UDim.new(0, all)
	local h = UDim.new(0, horizontal or all)
	return C.new("UIPadding", { PaddingTop = v, PaddingBottom = v, PaddingLeft = h, PaddingRight = h })
end

function C.list(direction, spacing, hAlign, vAlign)
	return C.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, spacing or 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
	})
end

-- UIGradient nhân với màu nền, nền trắng thì ra đúng 2 màu này
-- rotation: 90 trên xuống dưới, 0 trái sang phải, 45 chéo
function C.gradient(from, to, rotation)
	return C.new("UIGradient", {
		Name = "Gradient",
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, from), ColorSequenceKeypoint.new(1, to) }),
		Rotation = rotation or 90,
	})
end

-- gờ nổi dưới đáy nút: dải sẫm cao depth px (UIGradient nhân màu nền), chữ dịch lên cho nằm giữa mặt nút
local WHITE = Color3.new(1, 1, 1)
function C.lip(button, depth, shade)
	local h = button.Size.Y.Offset
	if h <= 0 then
		h = 36
	end
	local edge = math.clamp(1 - depth / h, 0.5, 0.96)
	local dark = Color3.new(shade or 0.78, shade or 0.78, (shade or 0.78) + 0.02)
	local g = C.new("UIGradient", {
		Name = "Lip",
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, WHITE),
			ColorSequenceKeypoint.new(edge, WHITE),
			ColorSequenceKeypoint.new(math.min(edge + 0.01, 0.999), dark),
			ColorSequenceKeypoint.new(1, dark),
		}),
	})
	g.Parent = button
	return g
end

function C.panel(props)
	props = props or {}
	local frame = C.new("Frame", {
		Name = props.Name or "Panel",
		BackgroundColor3 = props.Color or Colors.panel,
		BackgroundTransparency = props.Transparency or Theme.PanelTransparency,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromOffset(200, 100),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.None,
		LayoutOrder = props.LayoutOrder or 0,
		Visible = props.Visible ~= false,
		ZIndex = props.ZIndex or 1,
		-- Active để click vào nền bảng không xuyên xuống thành phố
		Active = props.Active ~= false,
		Parent = props.Parent,
	})
	C.corner(props.Radius or Theme.Radius.lg).Parent = frame
	if props.Stroke ~= false then
		C.shadowStroke(props.StrokeThickness, props.StrokeTransparency).Parent = frame
	end
	return frame
end

-- ô lót nhạt trong thẻ, không có viền bóng
function C.well(props)
	props = props or {}
	local frame = C.new("Frame", {
		Name = props.Name or "Well",
		BackgroundColor3 = props.Color or Colors.panelAlt,
		BackgroundTransparency = props.Transparency or 0,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.new(1, 0, 0, 0),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.None,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	C.corner(props.Radius or Theme.Radius.md).Parent = frame
	return frame
end

function C.label(props)
	props = props or {}
	return trackText(C.new("TextLabel", {
		Name = props.Name or "Label",
		BackgroundTransparency = 1,
		Text = props.Text or "",
		TextColor3 = props.Color or Colors.text,
		Font = props.Font or Theme.Font,
		TextSize = props.TextSize or 14,
		TextXAlignment = props.XAlign or Enum.TextXAlignment.Left,
		TextYAlignment = props.YAlign or Enum.TextYAlignment.Center,
		TextWrapped = props.Wrapped or false,
		RichText = props.RichText or false,
		Size = props.Size or UDim2.new(1, 0, 0, (props.TextSize or 14) + 6),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.None,
		LayoutOrder = props.LayoutOrder or 0,
		TextTruncate = props.Truncate and Enum.TextTruncate.AtEnd or Enum.TextTruncate.None,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	}))
end

-- tự giãn theo chữ
function C.pill(props)
	local label = C.label({
		Name = props.Name or "Pill",
		Text = props.Text or "",
		Font = props.Font or Theme.FontBold,
		TextSize = props.TextSize or 12,
		Color = props.TextColor or Colors.text,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, props.Height or 24),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		Parent = props.Parent,
	})
	label.BackgroundTransparency = 0
	label.BackgroundColor3 = props.Color or Colors.panelAlt
	C.round().Parent = label
	C.new("UIPadding", { PaddingLeft = UDim.new(0, props.PadX or 10), PaddingRight = UDim.new(0, props.PadX or 10) }).Parent = label
	return label
end

-- { màu nền, màu chữ }
local VARIANTS = {
	primary = { Colors.accent, Colors.onAccent },
	success = { Colors.success, Colors.onAccent },
	warning = { Colors.amber, Colors.onAccent },
	danger = { Colors.danger, Colors.onAccent },
	violet = { Colors.violet, Colors.onAccent },
	secondary = { Colors.panelAlt, Colors.text },
	white = { Colors.panel, Colors.text },
	ghost = { Colors.panel, Colors.textDim },
}

local function luminance(c)
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

-- tween màu hover đang chạy của từng nút, để C.setButtonColor huỷ được (không thì tween đè lên màu mới)
local hoverTweens = setmetatable({}, { __mode = "k" })

-- hover: nút đậm thì sáng lên, nút nhạt thì ngả sang accent
local function hoverOf(base)
	if luminance(base) < 0.75 then
		return base:Lerp(WHITE, 0.12)
	end
	return base:Lerp(Colors.accent, 0.08)
end

-- onClick(button) chạy cho cả chuột, chạm, gamepad
-- props: Variant (key trong VARIANTS) hoặc Color/TextColor, Stroke = true thêm viền, Lip = false bỏ gờ, Radius
function C.button(props, onClick)
	props = props or {}
	local variant = VARIANTS[props.Variant or ""] or (not props.Color and VARIANTS.secondary) or nil
	local base = props.Color or variant[1]
	local textColor = props.TextColor or (variant and variant[2]) or (luminance(base) < 0.6 and Colors.onAccent or Colors.text)
	local size = props.Size or UDim2.fromOffset(120, 36)
	local button = C.new("TextButton", {
		Name = props.Name or "Button",
		AutoButtonColor = false,
		BackgroundColor3 = base,
		BackgroundTransparency = props.Transparency or (props.Variant == "ghost" and 1 or 0),
		BorderSizePixel = 0,
		Text = props.Text or "",
		TextColor3 = textColor,
		Font = props.Font or Theme.FontBold,
		TextSize = props.TextSize or 13,
		TextXAlignment = props.XAlign or Enum.TextXAlignment.Center,
		TextYAlignment = props.YAlign or Enum.TextYAlignment.Center,
		TextWrapped = props.Wrapped or false,
		Size = size,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.None,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Visible = props.Visible ~= false,
		Parent = props.Parent,
	})
	C.selectable(button)
	trackText(button)
	button:SetAttribute("BaseTransparency", button.BackgroundTransparency)
	local h = size.Y.Offset > 0 and size.Y.Offset or 36
	C.corner(props.Radius or math.min(Theme.Radius.md, math.floor(h / 2))).Parent = button
	-- nút trắng luôn có viền, nút khác phải truyền Stroke = true
	if props.Stroke == true or (props.Stroke ~= false and props.Variant == "white") then
		C.stroke(Colors.stroke, 1.5).Parent = button
	end
	-- gờ: nút đậm sẫm rõ, nút nhạt sẫm nhẹ. nút trong suốt hoặc thấp hơn 24 thì bỏ
	local depth = 0
	if props.Lip ~= false and props.Variant ~= "ghost" and (props.Transparency or 0) < 0.5 and h >= 24 then
		depth = h >= 40 and 4 or 3
		C.lip(button, depth, luminance(base) < 0.75 and 0.76 or 0.9)
	end
	local pad = C.new("UIPadding", {
		Name = "Padding",
		PaddingBottom = UDim.new(0, depth),
		PaddingLeft = UDim.new(0, props.PadLeft or ((props.AutomaticSize and props.AutomaticSize ~= Enum.AutomaticSize.None) and 14 or 0)),
		PaddingRight = UDim.new(0, props.PadRight or ((props.AutomaticSize and props.AutomaticSize ~= Enum.AutomaticSize.None) and 14 or 0)),
	})
	pad.Parent = button

	local press = C.new("UIScale", { Name = "PressScale", Scale = 1, Parent = button })
	local function setPressed(on)
		TweenService:Create(press, TweenInfo.new(on and 0.06 or 0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = on and 0.95 or 1 }):Play()
	end
	button.InputBegan:Connect(function(input)
		if button:GetAttribute("Disabled") ~= true and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			setPressed(true)
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			setPressed(false)
		end
	end)

	button:SetAttribute("BaseColor", base)
	local ghost = props.Variant == "ghost"
	button.MouseEnter:Connect(function()
		if button:GetAttribute("Disabled") ~= true then
			local now = button:GetAttribute("BaseColor") or base
			local goal = ghost and { BackgroundTransparency = 0, BackgroundColor3 = Colors.panelAlt } or { BackgroundColor3 = hoverOf(now) }
			hoverTweens[button] = TweenService:Create(button, TweenInfo.new(0.12), goal)
			hoverTweens[button]:Play()
		end
	end)
	button.MouseLeave:Connect(function()
		setPressed(false)
		local goal = { BackgroundColor3 = button:GetAttribute("BaseColor") or base }
		if ghost then
			goal.BackgroundTransparency = button:GetAttribute("BaseTransparency") or 1
		end
		hoverTweens[button] = TweenService:Create(button, TweenInfo.new(0.12), goal)
		hoverTweens[button]:Play()
	end)
	if onClick then
		button.Activated:Connect(function()
			if button:GetAttribute("Disabled") ~= true then
				onClick(button)
			end
		end)
	end
	return button
end

-- đổi màu gốc (BaseColor) để hover tính lại đúng, dùng cho tab đang chọn...
function C.setButtonColor(button, color)
	if hoverTweens[button] then
		hoverTweens[button]:Cancel()
		hoverTweens[button] = nil
	end
	button:SetAttribute("BaseColor", color)
	button.BackgroundColor3 = color
end

-- không đụng .Active (nút vẫn phải nuốt click, không cho xuyên xuống thành phố), dùng attribute Disabled
function C.setEnabled(button, enabled)
	button:SetAttribute("Disabled", not enabled)
	button.AutoButtonColor = false
	button.TextTransparency = enabled and 0 or 0.45
	if button:GetAttribute("BaseTransparency") == nil then
		button:SetAttribute("BaseTransparency", button.BackgroundTransparency)
	end
	local baseT = button:GetAttribute("BaseTransparency")
	button.BackgroundTransparency = enabled and baseT or math.max(baseT, 0.45)
end

-- fade cả cụm UI rồi gọi done(). transparency gốc được lưu lại để C.restoreFade(root) trả về như cũ
-- (cho phần tử hiện lại nhiều lần)
local function fadeItems(root)
	local items = { root }
	for _, d in ipairs(root:GetDescendants()) do
		table.insert(items, d)
	end
	return items
end

function C.fadeOut(root, duration, done)
	local info = TweenInfo.new(duration or 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, d in ipairs(fadeItems(root)) do
		if d:IsA("GuiObject") then
			if d:GetAttribute("FadeBg") == nil then
				d:SetAttribute("FadeBg", d.BackgroundTransparency)
			end
			local goal = { BackgroundTransparency = 1 }
			if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
				if d:GetAttribute("FadeText") == nil then
					d:SetAttribute("FadeText", d.TextTransparency)
				end
				goal.TextTransparency = 1
			end
			TweenService:Create(d, info, goal):Play()
		elseif d:IsA("UIStroke") then
			if d:GetAttribute("FadeStroke") == nil then
				d:SetAttribute("FadeStroke", d.Transparency)
			end
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		end
	end
	if done then
		task.delay(duration or 0.35, done)
	end
end

function C.restoreFade(root)
	for _, d in ipairs(fadeItems(root)) do
		local bg, text, stroke = d:GetAttribute("FadeBg"), d:GetAttribute("FadeText"), d:GetAttribute("FadeStroke")
		if bg ~= nil then
			d.BackgroundTransparency = bg
		end
		if text ~= nil then
			d.TextTransparency = text
		end
		if stroke ~= nil then
			d.Transparency = stroke
		end
	end
end

-- hiện ra kiểu pop (scale từ nhỏ lên), dùng cho thẻ, toast, modal
function C.popIn(frame, from, duration)
	local scale = frame:FindFirstChild("PopScale") or C.new("UIScale", { Name = "PopScale", Parent = frame })
	scale.Scale = from or 0.9
	TweenService:Create(scale, TweenInfo.new(duration or 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- slider. opts: min, max, step, value, onChanged(value)
-- tuỳ chọn: ticks = bước vạch, labelEvery = bước vạch có số, fill = 2 màu gradient cho phần đã chọn
-- trả về { frame, set(value), get() }
function C.slider(opts)
	local minV, maxV, step = opts.min, opts.max, opts.step
	local value = opts.value or minV
	local frame = C.new("Frame", {
		Name = "Slider",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, opts.ticks and 40 or 26),
		LayoutOrder = opts.LayoutOrder or 0,
		Parent = opts.Parent,
	})
	local track = C.new("Frame", {
		Name = "Track",
		BackgroundColor3 = Colors.track,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -22, 0, 8),
		Position = UDim2.new(0, 11, 0, 13),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = frame,
	})
	C.round().Parent = track
	if opts.ticks then
		for v = minV, maxV, opts.ticks do
			local alpha = (v - minV) / (maxV - minV)
			local major = opts.labelEvery and (v - minV) % opts.labelEvery == 0
			if major then
				C.new("Frame", { Name = "Tick", BackgroundColor3 = Colors.strokeStrong, BorderSizePixel = 0, Size = UDim2.fromOffset(2, 5), Position = UDim2.new(alpha, -1, 1, 4), Parent = track })
				C.label({ Text = tostring(v), Font = Theme.FontMedium, TextSize = 10, Color = Colors.textMuted, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(24, 12), Position = UDim2.new(alpha, -12, 1, 10), Parent = track })
			end
		end
	end
	local fill = C.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = opts.color or Colors.accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		Parent = track,
	})
	C.round().Parent = fill
	if opts.fill then
		-- gradient gắn lên phần đã chọn nên co giãn theo độ dài fill
		C.new("UIGradient", { Name = "FillGradient", Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, opts.fill[1]), ColorSequenceKeypoint.new(1, opts.fill[2]) }), Parent = fill })
	end
	local knob = C.new("Frame", {
		Name = "Knob",
		BackgroundColor3 = Colors.panel,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(22, 22),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		ZIndex = 3,
		Parent = track,
	})
	C.round().Parent = knob
	local knobRing = C.stroke(opts.color or Colors.accent, 4)
	knobRing.Parent = knob
	-- vùng bắt input to hơn thanh, cho dễ kéo trên điện thoại
	local hit = C.new("TextButton", {
		Name = "Hit",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 32),
		Position = UDim2.new(0, 0, 0, -3),
		ZIndex = 4,
		Parent = frame,
	})

	C.selectable(hit)
	local obj = { frame = frame }

	local function render()
		local alpha = (maxV > minV) and (value - minV) / (maxV - minV) or 0
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)
	end

	function obj.set(v, silent)
		v = math.clamp(v, minV, maxV)
		v = minV + math.floor((v - minV) / step + 0.5) * step
		v = math.clamp(v, minV, maxV)
		local changed = math.abs(v - value) > 1e-9
		value = v
		render()
		if changed and not silent and opts.onChanged then
			opts.onChanged(value)
		end
	end

	function obj.get()
		return value
	end

	function obj.setColor(color)
		knobRing.Color = color
		if not opts.fill then
			fill.BackgroundColor3 = color
		end
	end

	local enabled = true
	local dragInput = nil -- chuột: MouseButton1, chạm: đúng ngón đã chạm vào thanh
	-- touch: chưa biết là kéo thanh (ngang) hay cuộn bảng (dọc) cho tới khi ngón tay di chuyển
	local touchStart = nil
	local touchDecided = false
	local function updateFromX(x)
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local alpha = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		obj.set(minV + alpha * (maxV - minV))
	end

	function obj.setEnabled(on)
		enabled = on
		dragInput = nil
		knob.BackgroundTransparency = on and 0 or 0.5
		knobRing.Transparency = on and 0 or 0.6
	end

	-- gamepad: chọn slider rồi LB/RB để giảm/tăng
	UserInputService.InputBegan:Connect(function(input)
		if not enabled or not gamepadMode then
			return
		end
		local selected = nil
		pcall(function()
			selected = GuiService.SelectedObject
		end)
		if selected ~= hit then
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonL1 then
			obj.set(value - step)
		elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
			obj.set(value + step)
		end
	end)

	hit.InputBegan:Connect(function(input)
		if not enabled then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragInput = input
			updateFromX(input.Position.X)
		elseif input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
			touchStart = input.Position
			touchDecided = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragInput then
			return
		end
		if dragInput.UserInputType == Enum.UserInputType.Touch then
			if input ~= dragInput then
				return
			end
			if not touchDecided and touchStart then
				local dx = math.abs(input.Position.X - touchStart.X)
				local dy = math.abs(input.Position.Y - touchStart.Y)
				if dy > 8 and dy >= dx then
					dragInput = nil -- vuốt dọc thì nhường cho bảng cuộn
					return
				elseif dx > 8 then
					touchDecided = true
				else
					return
				end
			end
			updateFromX(input.Position.X)
		elseif input.UserInputType == Enum.UserInputType.MouseMovement then
			-- nhả chuột ngoài cửa sổ có khi không ra InputEnded, nên check lại nút chuột
			if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
				dragInput = nil
				return
			end
			updateFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not dragInput then
			return
		end
		if input == dragInput or (dragInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then
			-- tap không kéo: lấy giá trị tại chỗ chạm
			if dragInput.UserInputType == Enum.UserInputType.Touch and not touchDecided then
				updateFromX(input.Position.X)
			end
			dragInput = nil
		end
	end)

	render()
	return obj
end

-- nút -/+ chỉnh cấp. opts: min, max, value, onChanged(value)
function C.stepper(opts)
	local value = opts.value or opts.min
	local frame = C.new("Frame", {
		Name = "Stepper",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(112, 32),
		LayoutOrder = opts.LayoutOrder or 0,
		Parent = opts.Parent,
	})
	local obj = { frame = frame }
	local valueLabel
	local minus = C.button({ Text = "−", Size = UDim2.fromOffset(32, 32), TextSize = 18, Radius = 16, Parent = frame }, function()
		obj.set(value - 1)
	end)
	minus.Name = "Minus"
	valueLabel = C.label({
		Text = tostring(value),
		Size = UDim2.fromOffset(48, 32),
		Position = UDim2.fromOffset(32, 0),
		XAlign = Enum.TextXAlignment.Center,
		Font = Theme.FontDisplay,
		TextSize = 16,
		Parent = frame,
	})
	local plus = C.button({ Text = "+", Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(80, 0), TextSize = 18, Radius = 16, Parent = frame }, function()
		obj.set(value + 1)
	end)
	plus.Name = "Plus"

	function obj.set(v, silent)
		v = math.clamp(math.floor(v + 0.5), opts.min, opts.max)
		local changed = v ~= value
		value = v
		valueLabel.Text = tostring(value)
		if changed and not silent and opts.onChanged then
			opts.onChanged(value)
		end
	end
	function obj.get()
		return value
	end
	function obj.setEnabled(enabled)
		C.setEnabled(minus, enabled)
		C.setEnabled(plus, enabled)
	end
	return obj
end

-- segmented control. tabs = { { key, text } }, onSelect(key)
function C.tabs(opts)
	local frame = C.new("Frame", {
		Name = "Tabs",
		BackgroundColor3 = Colors.panelAlt,
		BorderSizePixel = 0,
		Size = opts.Size or UDim2.new(1, 0, 0, 38),
		LayoutOrder = opts.LayoutOrder or 0,
		ZIndex = opts.ZIndex or 1,
		Parent = opts.Parent,
	})
	C.corner(Theme.Radius.md).Parent = frame
	C.padding(4).Parent = frame
	local layout = C.list(Enum.FillDirection.Horizontal, 4)
	layout.Parent = frame
	local buttons = {}
	local obj = { frame = frame, selected = nil }
	local count = #opts.tabs
	function obj.select(key, silent)
		obj.selected = key
		for k, b in pairs(buttons) do
			local on = k == key
			C.setButtonColor(b, Colors.panel)
			b.BackgroundTransparency = on and 0 or 1
			b:SetAttribute("BaseTransparency", b.BackgroundTransparency)
			b.TextColor3 = on and Colors.text or Colors.textDim
			local s = b:FindFirstChild("Shadow")
			if s then
				s.Transparency = on and 0.88 or 1
			end
		end
		if not silent and opts.onSelect then
			opts.onSelect(key)
		end
	end
	for i, tab in ipairs(opts.tabs) do
		local b = C.button({
			Name = "Tab_" .. tab.key,
			Text = tab.text,
			Variant = "white",
			Stroke = false,
			Lip = false,
			Size = UDim2.new(1 / count, -4 * (count - 1) / count, 1, 0),
			TextSize = 13,
			Radius = Theme.Radius.sm,
			LayoutOrder = i,
			ZIndex = opts.ZIndex,
			Parent = frame,
		}, function()
			obj.select(tab.key)
		end)
		C.shadowStroke(1, 0.88).Parent = b
		buttons[tab.key] = b
	end
	obj.buttons = buttons
	return obj
end

local modals = {} -- giữ lại để co cho vừa màn nhỏ
local openStack = {} -- modal đang mở, mới nhất ở cuối. nút B gamepad đóng cái trên cùng

pcall(function()
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.ButtonB and #openStack > 0 then
			openStack[#openStack].close()
		end
	end)
end)
local viewDesign = { w = 1366, h = 768 }

local function fitCard(entry)
	local w = math.min(entry.w, viewDesign.w - 24)
	local h = math.min(entry.h, viewDesign.h - 24)
	entry.card.Size = UDim2.fromOffset(w, h)
end

-- kích thước theo đơn vị thiết kế (đã chia UIScale)
function C.fitModals(designWidth, designHeight)
	viewDesign.w, viewDesign.h = designWidth, designHeight
	for _, entry in ipairs(modals) do
		fitCard(entry)
	end
end

function C.closeButton(props, onClick)
	return C.button({
		Name = props.Name or "Close",
		Text = "×",
		Font = Theme.FontBold,
		TextSize = 22,
		Size = UDim2.fromOffset(props.Size or 34, props.Size or 34),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Radius = math.floor((props.Size or 34) / 2),
		Lip = false,
		ZIndex = props.ZIndex,
		Parent = props.Parent,
	}, onClick)
end

-- trả về { root, body, open(), close(), setTitle() }
function C.modal(opts)
	local root = C.new("Frame", {
		Name = opts.Name or "Modal",
		BackgroundColor3 = Colors.overlay,
		BackgroundTransparency = 0.5,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 50,
		Active = true,
		Parent = opts.Parent,
	})
	local card = C.panel({
		Name = "Card",
		Size = opts.Size or UDim2.fromOffset(560, 440),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Radius = Theme.Radius.xl,
		StrokeTransparency = 0.8,
		ZIndex = 51,
		Parent = root,
	})
	local title = C.label({
		Name = "Title",
		Text = opts.Title or "",
		Font = Theme.FontDisplay,
		TextSize = 21,
		Truncate = true,
		Size = UDim2.new(1, -80, 0, 58),
		Position = UDim2.fromOffset(22, 0),
		ZIndex = 52,
		Parent = card,
	})
	local obj = { root = root, card = card }
	local closeButton = C.closeButton({ Position = UDim2.new(1, -16, 0, 12), AnchorPoint = Vector2.new(1, 0), ZIndex = 52, Parent = card }, function()
		obj.close()
	end)
	C.new("Frame", { Name = "HeaderRule", BackgroundColor3 = Colors.rule, BorderSizePixel = 0, Size = UDim2.new(1, -44, 0, 1), Position = UDim2.fromOffset(22, 58), ZIndex = 52, Parent = card })
	local size = opts.Size or UDim2.fromOffset(560, 440)
	local entry = { card = card, w = size.X.Offset, h = size.Y.Offset }
	table.insert(modals, entry)
	fitCard(entry)
	local body = C.new("ScrollingFrame", {
		Name = "Body",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -28, 1, -74),
		Position = UDim2.fromOffset(14, 66),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Colors.strokeStrong,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 52,
		Parent = card,
	})
	C.selectable(body)
	C.list(Enum.FillDirection.Vertical, 10).Parent = body
	C.padding(4, 8).Parent = body
	obj.body = body
	function obj.open()
		body.CanvasPosition = Vector2.new(0, 0)
		root.Visible = true
		C.popIn(card, 0.94, 0.22)
		table.insert(openStack, obj)
		if opts.onOpen then
			opts.onOpen()
		end
		C.focus(closeButton)
	end
	function obj.close()
		root.Visible = false
		for i = #openStack, 1, -1 do
			if openStack[i] == obj then
				table.remove(openStack, i)
			end
		end
		if gamepadMode then
			pcall(function()
				GuiService.SelectedObject = nil
			end)
		end
		if opts.onClose then
			opts.onClose()
		end
	end
	function obj.setTitle(text)
		title.Text = text
	end
	function obj.clear()
		for _, child in ipairs(body:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end
	return obj
end

function C.textbox(props)
	local box = C.new("TextBox", {
		Name = props.Name or "Input",
		BackgroundColor3 = Colors.panelAlt,
		BorderSizePixel = 0,
		Text = props.Text or "",
		PlaceholderText = props.Placeholder or "",
		PlaceholderColor3 = Colors.textMuted,
		TextColor3 = Colors.text,
		Font = Theme.FontMedium,
		TextSize = props.TextSize or 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Size = props.Size or UDim2.fromOffset(180, 38),
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	C.corner(Theme.Radius.md).Parent = box
	local stroke = C.stroke(Colors.stroke, 1.5)
	stroke.Parent = box
	C.padding(4, 12).Parent = box
	box.Focused:Connect(function()
		stroke.Color = Colors.accent
	end)
	box.FocusLost:Connect(function()
		stroke.Color = Colors.stroke
	end)
	return trackText(box)
end

function C.row(props)
	local frame = C.new("Frame", {
		Name = props.Name or "Row",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.new(1, 0, 0, 36),
		AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.None,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	C.list(Enum.FillDirection.Horizontal, props.Spacing or 8, nil, Enum.VerticalAlignment.Center).Parent = frame
	return frame
end

-- ZIndex cho cả cây con, dùng cho modal nằm trên cùng
function C.setZ(root, z)
	if root:IsA("GuiObject") then
		root.ZIndex = z
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("GuiObject") then
			d.ZIndex = z
		end
	end
end

return C
