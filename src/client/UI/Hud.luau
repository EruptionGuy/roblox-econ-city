-- thẻ thành phố góc trên trái (tên, tháng, 4 ô chỉ số) và thanh điều khiển góc trên phải

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Util = require(ReplicatedStorage:WaitForChild("EconCity"):WaitForChild("Util"))
local Config = require(ReplicatedStorage:WaitForChild("EconCity"):WaitForChild("Config"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local C = require(script.Parent:WaitForChild("Components"))
local Icons = require(script.Parent:WaitForChild("Icons"))
local Colors = Theme.Colors

local Hud = {}

local BLOCK_H = 76
local LEFT_W = 186
local TILE_W, TILE_H, TILE_GAP = 112, 60, 6
local BAR_H = 60

local function soft(c)
	return c:Lerp(Color3.new(1, 1, 1), 0.86)
end

-- số nảy lên khi đổi giá trị, để thấy là đã sang tháng mới
local function bump(label)
	local scale = label:FindFirstChild("Bump") or C.new("UIScale", { Name = "Bump", Parent = label })
	scale.Scale = 1.14
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function setValue(label, text, animate)
	if label.Text ~= text then
		label.Text = text
		if animate then
			bump(label)
		end
	end
end

local function statTile(parent, x, spec)
	local tile = C.well({ Name = spec.name, Size = UDim2.fromOffset(TILE_W, TILE_H), Position = UDim2.fromOffset(x, 8), Parent = parent })
	local _, icon = Icons.badge(spec.icon, { Name = "Badge", Size = 22, IconSize = 13, Color = spec.color, Soft = soft(spec.color), Position = UDim2.fromOffset(8, 7), Parent = tile })
	C.label({ Name = "Title", Text = spec.title, Font = Theme.FontBold, TextSize = 11, Color = Colors.textDim, Truncate = true, Size = UDim2.new(1, -38, 0, 22), Position = UDim2.fromOffset(34, 7), Parent = tile })
	local value = C.label({ Name = "Value", Text = "-", Font = Theme.FontDisplay, TextSize = 20, Truncate = true, Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(9, 28), Parent = tile })
	local sub = C.label({ Name = "Sub", Text = "", Font = Theme.FontMedium, TextSize = 11, Color = Colors.textMuted, Truncate = true, Size = UDim2.new(1, -16, 0, 12), Position = UDim2.fromOffset(9, 47), Parent = tile })
	return value, sub, icon, tile
end

-- ctx: { onTogglePause, onNewGame, onHistory, onLeaderboard, onClass, onTickNow, onTogglePanel }
function Hud.new(gui, ctx)
	local obj = {}

	-- Thẻ thành phố ----------------------------------------------------------------------
	local blockW = LEFT_W + TILE_W * 4 + TILE_GAP * 3 + 8
	local stats = C.panel({ Name = "Stats", Size = UDim2.fromOffset(blockW, BLOCK_H), Position = UDim2.fromOffset(12, 10), Radius = Theme.Radius.xl, Parent = gui })
	-- logo: ô xanh gradient, hàng nhà trắng
	local logo = C.new("Frame", { Name = "Logo", BackgroundColor3 = Colors.panel, BorderSizePixel = 0, Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(14, 15), Parent = stats })
	C.corner(14).Parent = logo
	C.gradient(Colors.accent, Colors.violet, 45).Parent = logo
	local skyline = { { 7, 14 }, { 14, 24 }, { 22, 18 }, { 30, 28 } }
	for k, b in ipairs(skyline) do
		local bar = C.new("Frame", { Name = "Tower", BackgroundColor3 = Colors.panel, BackgroundTransparency = k % 2 == 0 and 0 or 0.25, BorderSizePixel = 0, Size = UDim2.fromOffset(7, b[2]), Position = UDim2.fromOffset(b[1], 38 - b[2]), Parent = logo })
		C.corner(2).Parent = bar
	end
	C.label({ Name = "Name", Text = "Econ City", Font = Theme.FontDisplay, TextSize = 20, Size = UDim2.fromOffset(LEFT_W - 76, 24), Position = UDim2.fromOffset(70, 11), Parent = stats })
	obj.month = C.label({ Name = "Month", Text = "Month 0 / 24", Font = Theme.FontMedium, TextSize = 12, Color = Colors.textDim, Size = UDim2.fromOffset(LEFT_W - 76, 16), Position = UDim2.fromOffset(70, 35), Parent = stats })
	local monthTrack = C.new("Frame", { Name = "MonthBar", BackgroundColor3 = Colors.track, BorderSizePixel = 0, Size = UDim2.fromOffset(LEFT_W - 82, 6), Position = UDim2.fromOffset(70, 56), Parent = stats })
	C.round().Parent = monthTrack
	obj.monthFill = C.new("Frame", { Name = "Fill", BackgroundColor3 = Colors.panel, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = monthTrack })
	C.round().Parent = obj.monthFill
	C.gradient(Colors.accent, Colors.violet, 0).Parent = obj.monthFill

	local specs = {
		{ name = "Stat_BUDGET", title = "Budget", icon = "coin", color = Colors.gold },
		{ name = "Stat_POPULATION", title = "Population", icon = "people", color = Colors.people },
		{ name = "Stat_EMPLOYMENT", title = "Employment", icon = "briefcase", color = Colors.jobs },
		{ name = "Stat_HAPPINESS", title = "Happiness", icon = "face", color = Colors.good },
	}
	local x = LEFT_W
	obj.budget, obj.budgetSub = statTile(stats, x, specs[1])
	x = x + TILE_W + TILE_GAP
	obj.population, obj.populationSub = statTile(stats, x, specs[2])
	x = x + TILE_W + TILE_GAP
	obj.employment, obj.employmentSub = statTile(stats, x, specs[3])
	x = x + TILE_W + TILE_GAP
	local happyTile
	obj.happiness, obj.happinessSub, obj.happyIcon, happyTile = statTile(stats, x, specs[4])
	obj.happyBadge = happyTile:FindFirstChild("Badge")
	obj.happinessSub.Text = "50+: people move in"

	-- nhãn vai trò giáo viên / cảnh báo lưu dữ liệu, học sinh thường không thấy
	obj.modeBadge = C.pill({ Name = "ModeBadge", Text = "", TextSize = 11, Color = Colors.goldSoft, TextColor = Colors.warn, Height = 24, Position = UDim2.fromOffset(14, BLOCK_H + 18), Parent = gui })
	-- màn hẹp thì ẩn các dòng phụ này. riêng thu chi/tháng của ngân sách luôn hiện (phản hồi chính khi chỉnh thuế)
	obj.subs = { obj.populationSub, obj.employmentSub, obj.happinessSub }

	-- Thanh điều khiển ---------------------------------------------------------------------
	local bar = C.panel({
		Name = "Controls",
		Size = UDim2.fromOffset(0, BAR_H),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(1, -12, 0, 10),
		AnchorPoint = Vector2.new(1, 0),
		Radius = Theme.Radius.xl,
		Parent = gui,
	})
	C.padding(8).Parent = bar
	C.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center).Parent = bar
	local order = 0
	local function nextOrder()
		order = order + 1
		return order
	end

	-- trạng thái + đếm ngược chung 1 ô
	local statusCell = C.well({ Name = "Status", Size = UDim2.fromOffset(118, 44), LayoutOrder = nextOrder(), Parent = bar })
	obj.statusDot = C.new("Frame", { Name = "Dot", BackgroundColor3 = Colors.good, BorderSizePixel = 0, Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(12, 10), Parent = statusCell })
	C.round().Parent = obj.statusDot
	obj.statusText = C.label({ Name = "StatusText", Text = "Loading", Font = Theme.FontBold, TextSize = 12, Truncate = true, Size = UDim2.new(1, -32, 0, 18), Position = UDim2.fromOffset(26, 5), Parent = statusCell })
	obj.countdown = C.label({ Name = "Countdown", Text = "", Font = Theme.FontMedium, TextSize = 11, Color = Colors.textDim, Size = UDim2.new(1, -24, 0, 16), Position = UDim2.fromOffset(12, 23), Parent = statusCell })
	obj.statusCell = statusCell

	obj.pauseButton = C.button({
		Name = "Pause",
		Text = "PAUSE",
		Variant = "success",
		Font = Theme.FontDisplay,
		TextSize = 15,
		Size = UDim2.fromOffset(136, 44),
		PadLeft = 24,
		LayoutOrder = nextOrder(),
		Parent = bar,
	}, function()
		if obj.finished then
			-- ván vừa kết thúc đúng lúc bấm Tạm dừng thì đừng mở ván mới ngoài ý muốn
			if os.clock() - (obj.finishedAt or 0) < 2 then
				return
			end
			ctx.onNewGame()
		else
			ctx.onTogglePause()
		end
	end)
	local pauseIcon = nil
	local function setPauseIcon(name)
		if pauseIcon and pauseIcon:GetAttribute("IconName") == name then
			return
		end
		if pauseIcon then
			pauseIcon:Destroy()
		end
		pauseIcon = Icons.draw(name, { Size = 18, Color = Colors.onAccent, Position = UDim2.new(0, -12, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = obj.pauseButton })
	end

	obj.tickNowButton = C.button({ Name = "TickNow", Text = "Tick now", Variant = "secondary", TextSize = 12, Size = UDim2.fromOffset(98, 44), PadLeft = 22, LayoutOrder = nextOrder(), Parent = bar }, ctx.onTickNow)
	Icons.draw("forward", { Size = 14, Color = Colors.accent, Position = UDim2.new(0, -8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = obj.tickNowButton })
	obj.tickNowButton.Visible = false

	C.new("Frame", { Name = "Divider", BackgroundColor3 = Colors.rule, BorderSizePixel = 0, Size = UDim2.fromOffset(1, 32), LayoutOrder = nextOrder(), Parent = bar })

	local navIcons = {}
	local function navButton(name, text, icon, onClick)
		local b = C.button({ Name = name, Text = text, Variant = "ghost", TextColor = Colors.textDim, TextSize = 11, YAlign = Enum.TextYAlignment.Bottom, Size = UDim2.fromOffset(64, 44), Radius = Theme.Radius.md, LayoutOrder = nextOrder(), Parent = bar }, onClick)
		b:FindFirstChild("Padding").PaddingBottom = UDim.new(0, 4)
		navIcons[b] = Icons.draw(icon, { Size = 18, Color = Colors.textDim, Position = UDim2.new(0.5, 0, 0, 4), AnchorPoint = Vector2.new(0.5, 0), Parent = b })
		return b
	end
	obj.historyButton = navButton("History", "History", "chart", ctx.onHistory)
	obj.leaderboardButton = navButton("Leaderboard", "Ranking", "podium", ctx.onLeaderboard)
	obj.classButton = navButton("Class", "Class", "people", ctx.onClass)
	obj.panelToggle = navButton("PanelToggle", "Hide", "grid", ctx.onTogglePanel)

	local lastMonth = nil
	function obj.update(snap)
		local s = snap.session
		if not s then
			return
		end
		local animate = lastMonth ~= nil and lastMonth ~= s.month
		lastMonth = s.month
		obj.month.Text = string.format("Month %d / %d", s.month, s.maxMonths)
		local progress = s.maxMonths > 0 and math.clamp(s.month / s.maxMonths, 0, 1) or 0
		TweenService:Create(obj.monthFill, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(progress, 1) }):Play()
		setValue(obj.budget, Util.formatMoneyFull(s.budget), animate)
		obj.budget.TextColor3 = s.budget < 0 and Colors.bad or Colors.text
		setValue(obj.population, Util.formatInt(s.population or 0), animate)
		local hasPeople = (s.population or 0) > 0
		setValue(obj.employment, hasPeople and string.format("%d%%", Util.round(s.employment or 0)) or "—", animate)
		obj.employment.TextColor3 = (hasPeople and (s.employment or 0) < 80) and Colors.warn or Colors.text
		setValue(obj.happiness, tostring(Util.round(s.happiness)), animate)
		local hColor = Theme.happinessColor(s.happiness)
		obj.happiness.TextColor3 = hColor
		Icons.setColor(obj.happyIcon, hColor)
		obj.happyBadge.BackgroundColor3 = soft(hColor)
		Icons.setMood(obj.happyIcon, s.happiness >= 65 and "happy" or (s.happiness >= 50 and "neutral" or "sad"))

		local finished = s.status == "ENDED" or s.status == "FAILED"
		if finished and not obj.finished then
			obj.finishedAt = os.clock()
		end
		obj.finished = finished
		obj.status = s.status
		obj.notStarted = s.status == "PAUSED" and s.month == 0
		obj.statusText.Text = obj.notStarted and "Not started" or (Theme.StatusTitle[s.status] or s.status)
		obj.statusDot.BackgroundColor3 = obj.notStarted and Colors.textMuted or Theme.statusColor(s.status)
		obj.renderPauseText()
		obj.tickNowButton.Visible = snap.isStudio == true and not obj.compact
		C.setEnabled(obj.tickNowButton, s.status == "ACTIVE")

		local role = (snap.isOwner and "Owner") or (snap.isTeacher and "Teacher") or nil
		local parts = { role }
		local color, bg = Colors.textDim, Colors.panel
		if snap.inPrivateRoom then
			table.insert(parts, "Private classroom")
		end
		if snap.saveDisabled then
			table.insert(parts, "Progress can't be saved, please leave and rejoin")
			color, bg = Colors.bad, soft(Colors.bad)
		elseif snap.persistence == "memory" then
			table.insert(parts, "Test mode: data is only kept on this server")
			color, bg = Colors.warn, Colors.goldSoft
		end
		obj.modeBadge.Text = table.concat(parts, " | ")
		obj.modeBadge.TextColor3 = color
		obj.modeBadge.BackgroundColor3 = bg
		obj.modeBadge.Visible = #parts > 0
	end

	-- net = thu chi dự kiến mỗi tháng, Main tính bằng CityEngine
	function obj.setNet(net, capacity, jobs)
		obj.budgetSub.Text = string.format("%s%s/mo", net >= 0 and "+" or "", Util.formatMoneyFull(net))
		obj.budgetSub.TextColor3 = net >= 0 and Colors.good or Colors.bad
		obj.populationSub.Text = "/ " .. Util.formatInt(capacity) .. " homes"
		obj.employmentSub.Text = Util.formatInt(jobs) .. " jobs"
	end

	function obj.renderPauseText()
		local text, variantColor, icon
		if obj.finished then
			text, variantColor, icon = "NEW GAME", Colors.accent, "play" -- đóng màn hình kết thúc rồi vẫn chơi lại được
		elseif obj.notStarted then
			text, variantColor, icon = "START", Colors.success, "play"
		elseif obj.status == "PAUSED" then
			text, variantColor, icon = "RESUME", Colors.success, "play"
		else
			text, variantColor, icon = "PAUSE", Colors.amber, "pause"
		end
		obj.pauseButton.Text = text
		if obj.pauseButton:GetAttribute("BaseColor") ~= variantColor then
			C.setButtonColor(obj.pauseButton, variantColor)
		end
		setPauseIcon(icon)
	end

	-- màn hẹp (điện thoại, tablet dọc): ô trạng thái chỉ còn đồng hồ, nhãn nút ngắn lại
	function obj.setCompact(compact)
		obj.compact = compact
		obj.statusText.Visible = not compact
		obj.statusCell.Size = UDim2.fromOffset(compact and 70 or 118, 44)
		obj.countdown.Position = compact and UDim2.fromOffset(8, 14) or UDim2.fromOffset(12, 23)
		obj.countdown.Size = compact and UDim2.new(1, -16, 0, 16) or UDim2.new(1, -24, 0, 16)
		obj.countdown.TextXAlignment = compact and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
		obj.statusDot.Visible = not compact
		obj.leaderboardButton.Text = compact and "Rank" or "Ranking"
		obj.classButton.Text = compact and "Class" or "Class"
		obj.panelToggle.Text = compact and "Build" or (obj.panelVisible and "Hide" or "Build")
		for _, sub in ipairs(obj.subs) do
			sub.Visible = not compact
		end
		obj.renderPauseText()
		if compact then
			obj.tickNowButton.Visible = false
		end
	end

	-- nút Xây dựng sáng lên khi bảng đang mở
	function obj.setPanelVisible(visible)
		obj.panelVisible = visible
		local b = obj.panelToggle
		b:SetAttribute("BaseTransparency", visible and 0 or 1)
		b.BackgroundTransparency = visible and 0 or 1
		C.setButtonColor(b, visible and Colors.accentSoft or Colors.panel)
		b.TextColor3 = visible and Colors.accent or Colors.textDim
		Icons.setColor(navIcons[b], visible and Colors.accent or Colors.textDim)
		if not obj.compact then
			b.Text = visible and "Hide" or "Build"
		end
	end

	function obj.updateCountdown(snap, serverNow)
		local s = snap and snap.session
		if s and (s.status == "ENDED" or s.status == "FAILED") then
			obj.countdown.Text = "Game over"
			return
		end
		if not s or s.status ~= "ACTIVE" then
			obj.countdown.Text = string.format("%ds / month", Config.TICK_SECONDS)
			return
		end
		local remaining = math.max(0, math.ceil((snap.nextTickAt or 0) - serverNow))
		obj.countdown.Text = string.format("%ds left", remaining)
	end

	setPauseIcon("play")
	return obj
end

Hud.BLOCK_H = BLOCK_H
return Hud
