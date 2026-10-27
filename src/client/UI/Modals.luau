-- modal Bảng xếp hạng và Lịch sử

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = require(ReplicatedStorage:WaitForChild("EconCity"):WaitForChild("Util"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local C = require(script.Parent:WaitForChild("Components"))
local Icons = require(script.Parent:WaitForChild("Icons"))
local Colors = Theme.Colors

local Modals = {}

local MEDALS = {
	[1] = { Theme.Colors.gold, Color3.fromRGB(120, 84, 0) },
	[2] = { Color3.fromRGB(196, 204, 216), Color3.fromRGB(70, 80, 96) },
	[3] = { Color3.fromRGB(222, 160, 110), Color3.fromRGB(110, 60, 20) },
}

-- Bảng xếp hạng -----------------------------------------------------------------------
-- ctx: { request(action, payload), getSnapshot() }
function Modals.leaderboard(gui, ctx)
	local scope = "global"
	local classIndex = 1
	local modal
	local loading = false

	local function classCodes()
		local snap = ctx.getSnapshot()
		local codes = {}
		if snap and snap.profile then
			for _, code in ipairs(snap.profile.classes or {}) do
				table.insert(codes, code)
			end
			for _, code in ipairs(snap.profile.teaching or {}) do
				table.insert(codes, code)
			end
		end
		return codes
	end

	-- top 3 có huy hiệu vàng/bạc/đồng
	local function row(parent, order, rank, name, score, highlight)
		local r = C.well({ Color = highlight and Colors.accentSoft or Colors.panelAlt, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = order, ZIndex = 53, Parent = parent })
		if highlight then
			C.stroke(Colors.accent, 1.5, 0.4).Parent = r
		end
		local medal = MEDALS[rank]
		local rankBadge = C.label({
			Name = "Rank",
			Text = "#" .. tostring(rank),
			Font = Theme.FontDisplay,
			TextSize = 13,
			Color = medal and medal[2] or Colors.textDim,
			XAlign = Enum.TextXAlignment.Center,
			Size = UDim2.fromOffset(40, 28),
			Position = UDim2.new(0, 8, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			ZIndex = 54,
			Parent = r,
		})
		rankBadge.BackgroundTransparency = 0
		rankBadge.BackgroundColor3 = medal and medal[1] or Colors.panel
		C.round().Parent = rankBadge
		C.label({ Text = name, Font = highlight and Theme.FontBold or Theme.FontMedium, TextSize = 14, Truncate = true, Size = UDim2.new(1, -170, 1, 0), Position = UDim2.fromOffset(60, 0), ZIndex = 54, Parent = r })
		C.label({ Text = Util.formatInt(score), Font = Theme.FontDisplay, TextSize = 16, XAlign = Enum.TextXAlignment.Right, Color = Colors.accent, Size = UDim2.fromOffset(100, 44), Position = UDim2.new(1, -112, 0, 0), ZIndex = 54, Parent = r })
	end

	local refresh

	local function renderHeader()
		local tabRow = C.row({ Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 0, ZIndex = 53, Parent = modal.body })
		local seg = C.well({ Name = "Segments", Size = UDim2.fromOffset(268, 40), LayoutOrder = 1, ZIndex = 53, Parent = tabRow })
		C.padding(4).Parent = seg
		C.list(Enum.FillDirection.Horizontal, 4).Parent = seg
		local function tab(name, text, key, order)
			local on = scope == key
			local b = C.button({ Name = name, Text = text, Variant = "white", Stroke = false, Lip = false, Transparency = on and 0 or 1, TextColor = on and Colors.text or Colors.textDim, Size = UDim2.fromOffset(128, 32), Radius = Theme.Radius.sm, ZIndex = 54, LayoutOrder = order, Parent = seg }, function()
				scope = key
				task.spawn(refresh)
			end)
			if on then
				C.shadowStroke(1, 0.88).Parent = b
			end
		end
		tab("TabGlobal", "Global", "global", 1)
		tab("TabClass", "My class", "class", 2)
		local codes = classCodes()
		if scope == "class" and #codes > 1 then
			if classIndex > #codes then
				classIndex = 1
			end
			C.button({ Text = "Class: " .. codes[classIndex] .. "  ›", Variant = "white", Size = UDim2.fromOffset(150, 36), ZIndex = 54, LayoutOrder = 3, Parent = tabRow }, function()
				classIndex = classIndex % #codes + 1
				task.spawn(refresh)
			end)
		end
	end

	local requestToken = 0
	refresh = function()
		requestToken = requestToken + 1
		local myToken = requestToken -- chỉ hiện kết quả của lần bấm mới nhất, bỏ response cũ về trễ
		modal.clear()
		renderHeader()
		local status = C.label({ Text = "Loading...", TextSize = 12, Color = Colors.textMuted, LayoutOrder = 1, ZIndex = 53, Parent = modal.body })
		local payload = { scope = scope }
		if scope == "class" then
			local codes = classCodes()
			if #codes == 0 then
				status.Text = "You're not in a class yet."
				return
			end
			payload.code = codes[math.min(classIndex, #codes)]
		end
		loading = true
		local response = ctx.request("getLeaderboard", payload)
		loading = false
		if myToken ~= requestToken or not modal.root.Visible then
			return
		end
		if not response.ok then
			status.Text = response.error or "Couldn't load the leaderboard"
			status.TextColor3 = Colors.bad
			return
		end
		local data = response.data or {}
		local rows = data.rows or {}
		status.Text = "Score = employed residents × happiness / 100 + budget / 100. Everyone keeps their best score. The board updates every 2 months."
		status.TextWrapped = true
		status.Size = UDim2.new(1, 0, 0, 34)
		local meShown = false
		for i, r in ipairs(rows) do
			row(modal.body, 10 + i, r.rank, r.name, r.score, r.isMe)
			meShown = meShown or r.isMe
		end
		if #rows == 0 then
			C.label({ Text = "No rankings yet.", TextSize = 13, Color = Colors.textDim, LayoutOrder = 5, ZIndex = 53, Parent = modal.body })
		end
		-- dòng "Bạn" luôn hiện ở cuối, chưa lọt top cũng hiện
		local me = data.me
		if me and not meShown then
			local text
			if me.ranked == false then
				text = "You (Studio test play, not ranked)"
			else
				text = "You (not in the top " .. tostring(#rows > 0 and #rows or 20) .. ")"
			end
			local best = math.max(me.bestScore or 0, me.currentScore or 0)
			local r = C.well({ Color = Colors.accentSoft, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 100, ZIndex = 53, Parent = modal.body })
			C.stroke(Colors.accent, 1.5, 0.4).Parent = r
			C.label({ Text = text, Font = Theme.FontBold, TextSize = 13, Truncate = true, Size = UDim2.new(1, -130, 1, 0), Position = UDim2.fromOffset(14, 0), ZIndex = 54, Parent = r })
			C.label({ Text = Util.formatInt(best), Font = Theme.FontDisplay, TextSize = 16, XAlign = Enum.TextXAlignment.Right, Color = Colors.accent, Size = UDim2.fromOffset(100, 44), Position = UDim2.new(1, -112, 0, 0), ZIndex = 54, Parent = r })
		end
	end

	modal = C.modal({ Name = "LeaderboardModal", Title = "Leaderboard", Size = UDim2.fromOffset(560, 500), Parent = gui, onOpen = function()
		scope = "global" -- mở lại luôn về bảng toàn cầu
		task.spawn(refresh)
	end })
	Icons.badge("podium", { Size = 30, IconSize = 15, Color = Colors.gold, Soft = Colors.goldSoft, Square = true, Position = UDim2.fromOffset(22, 14), ZIndex = 52, Parent = modal.card })
	modal.card:FindFirstChild("Title").Position = UDim2.fromOffset(62, 0)
	return modal
end

-- Lịch sử ------------------------------------------------------------------
-- months: số tháng của ván = số cột
local function barChart(parent, order, title, values, formatter, colorFn, months)
	local holder = C.well({ Size = UDim2.new(1, 0, 0, 160), Radius = Theme.Radius.lg, LayoutOrder = order, ZIndex = 53, Parent = parent })
	C.label({ Text = title, Font = Theme.FontDisplay, TextSize = 14, Size = UDim2.new(0.5, 0, 0, 22), Position = UDim2.fromOffset(14, 8), ZIndex = 54, Parent = holder })
	local plot = C.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -28, 1, -58), Position = UDim2.fromOffset(14, 36), ZIndex = 54, Parent = holder })
	if #values == 0 then
		C.label({ Text = "No data yet, wait for the first month to end.", TextSize = 12, Color = Colors.textDim, Size = UDim2.fromScale(1, 1), XAlign = Enum.TextXAlignment.Center, ZIndex = 55, Parent = plot })
		return
	end
	local maxV, minV = 0, 0
	for _, v in ipairs(values) do
		maxV = math.max(maxV, v)
		minV = math.min(minV, v)
	end
	local range = maxV - minV
	if range <= 0 then
		range = 1
	end
	local zeroFrac = maxV / range -- trục 0, tính từ trên xuống
	local axis = C.new("Frame", { BackgroundColor3 = Colors.strokeStrong, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromScale(0, zeroFrac), ZIndex = 55, Parent = plot })
	axis.Name = "Axis"
	local n = math.max(12, months or 12, #values)
	local slot = 1 / n
	local labelEvery = n > 12 and 3 or 1
	for i, v in ipairs(values) do
		local h = math.abs(v) / range
		local top = v >= 0 and (zeroFrac - h) or zeroFrac
		local bar = C.new("Frame", {
			BackgroundColor3 = colorFn(v),
			BorderSizePixel = 0,
			Size = UDim2.new(slot * 0.66, 0, h, 0),
			Position = UDim2.new(slot * (i - 1) + slot * 0.17, 0, top, 0),
			ZIndex = 56,
			Parent = plot,
		})
		C.corner(4).Parent = bar
		if i == #values then
			C.stroke(Colors.text, 1.5, 0.75).Parent = bar -- cột mới nhất
		end
		if i == 1 or i % labelEvery == 0 then
			C.label({ Text = "M" .. i, Font = Theme.FontMedium, TextSize = 10, Color = Colors.textMuted, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(slot, 0, 0, 14), Position = UDim2.new(slot * (i - 1), 0, 1, 4), ZIndex = 55, Parent = plot })
		end
	end
	local summary = C.pill({
		Text = "Highest " .. formatter(math.max(table.unpack(values))) .. "   |   Latest " .. formatter(values[#values]),
		Font = Theme.FontBold,
		TextSize = 11,
		Color = Colors.panel,
		TextColor = Colors.textDim,
		Height = 22,
		Position = UDim2.new(1, -12, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		ZIndex = 54,
		Parent = holder,
	})
	summary.Name = "Summary"
end

local function pastGamesList(parent, order, pastSessions)
	local holder = C.well({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Radius = Theme.Radius.lg, LayoutOrder = order, ZIndex = 53, Parent = parent })
	C.padding(12, 14).Parent = holder
	C.list(Enum.FillDirection.Vertical, 6).Parent = holder
	C.label({ Text = "Past games", Font = Theme.FontDisplay, TextSize = 14, LayoutOrder = 0, ZIndex = 54, Parent = holder })
	if #pastSessions == 0 then
		C.label({ Text = "No finished games yet.", TextSize = 12, Color = Colors.textDim, LayoutOrder = 1, ZIndex = 54, Parent = holder })
		return
	end
	for i, p in ipairs(pastSessions) do
		if i > 10 then
			break
		end
		local statusText = (p.status == "ENDED" and "Won") or (p.status == "FAILED" and "Failed") or "Abandoned"
		local color = (p.status == "ENDED" and Colors.good) or (p.status == "FAILED" and Colors.bad) or Colors.textDim
		C.label({
			Text = string.format("%s • month %d/%d • budget %s • population %s • happiness %d • score %s",
				statusText, p.month or 0, p.maxMonths or 24, Util.formatMoneyFull(p.budget or 0), Util.formatInt(p.population or 0),
				Util.round(p.happiness or 0), Util.formatInt(p.prosperityScore or 0)),
			Font = Theme.FontMedium,
			TextSize = 12,
			Color = color,
			Truncate = true,
			LayoutOrder = i,
			ZIndex = 54,
			Parent = holder,
		})
	end
end

-- ctx: { getSnapshot() }
function Modals.history(gui, ctx)
	local modal
	local function render()
		local scroll = modal.body.CanvasPosition
		modal.clear()
		local snap = ctx.getSnapshot()
		local s = snap and snap.session
		local history = (s and s.history) or {}
		local months = (s and s.maxMonths) or 24
		local budgets, revenue, happiness, employment, population = {}, {}, {}, {}, {}
		for _, h in ipairs(history) do
			table.insert(budgets, h.budget)
			table.insert(revenue, h.gdp or 0)
			table.insert(happiness, h.happiness)
			table.insert(employment, h.employment or 0)
			table.insert(population, h.population or 0)
		end
		barChart(modal.body, 1, "Budget", budgets, Util.formatMoneyFull, function(v)
			return v >= 0 and Colors.gold or Colors.bad
		end, months)
		barChart(modal.body, 2, "Business revenue", revenue, Util.formatMoneyK, function()
			return Colors.jobs
		end, months)
		barChart(modal.body, 3, "Happiness", happiness, function(v)
			return tostring(Util.round(v))
		end, function(v)
			return Theme.happinessColor(v)
		end, months)
		barChart(modal.body, 4, "Employment rate", employment, function(v)
			return string.format("%d%%", Util.round(v))
		end, function(v)
			return (v < 80 and Colors.amber) or Colors.success
		end, months)
		barChart(modal.body, 5, "Population", population, function(v)
			return Util.formatInt(v)
		end, function()
			return Colors.people
		end, months)
		C.label({
			Text = "City tax = revenue × tax rate. A higher rate brings in more from each dollar, but it makes residents unhappy, so fewer people move in to work. Compare revenue, happiness and population to see the trade-off.",
			TextSize = 12,
			Color = Colors.textDim,
			Wrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			LayoutOrder = 6,
			ZIndex = 53,
			Parent = modal.body,
		})
		pastGamesList(modal.body, 7, (snap and snap.profile and snap.profile.pastSessions) or {})
		modal.body.CanvasPosition = scroll -- giữ chỗ đang cuộn khi vẽ lại mỗi lượt
	end
	modal = C.modal({ Name = "HistoryModal", Title = "City history", Size = UDim2.fromOffset(580, 580), Parent = gui, onOpen = render })
	Icons.badge("chart", { Size = 30, IconSize = 15, Color = Colors.accent, Soft = Colors.accentSoft, Square = true, Position = UDim2.fromOffset(22, 14), ZIndex = 52, Parent = modal.card })
	modal.card:FindFirstChild("Title").Position = UDim2.fromOffset(62, 0)
	-- chỉ vẽ lại khi có data mới (tick, ván mới, init), không theo đồng hồ
	function modal.refreshIfOpen(reason)
		if modal.root.Visible and (reason == "tick" or reason == "newGame" or reason == "init") then
			render()
		end
	end
	return modal
end

return Modals
