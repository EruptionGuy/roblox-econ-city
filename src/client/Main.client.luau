-- entry phía client: dựng UI, thành phố 3D, camera, nối với server

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local root = script.Parent
local State = require(root:WaitForChild("State"))
local UIFolder = root:WaitForChild("UI")
local CityFolder = root:WaitForChild("City")

local Theme = require(UIFolder:WaitForChild("Theme"))
local C = require(UIFolder:WaitForChild("Components"))
local Hud = require(UIFolder:WaitForChild("Hud"))
local BuildPanel = require(UIFolder:WaitForChild("BuildPanel"))
local Overlays = require(UIFolder:WaitForChild("Overlays"))
local Modals = require(UIFolder:WaitForChild("Modals"))
local ClassPanel = require(UIFolder:WaitForChild("ClassPanel"))
local CityRenderer = require(CityFolder:WaitForChild("CityRenderer"))
local Mood = require(CityFolder:WaitForChild("Mood"))
local CameraController = require(CityFolder:WaitForChild("CameraController"))
local BuildController = require(CityFolder:WaitForChild("BuildController"))

local CityLayout = require(ReplicatedStorage:WaitForChild("EconCity"):WaitForChild("CityLayout"))
local Config = require(ReplicatedStorage:WaitForChild("EconCity"):WaitForChild("Config"))
local CityEngine = require(ReplicatedStorage:WaitForChild("EconCity"):WaitForChild("CityEngine"))
local Util = require(ReplicatedStorage:WaitForChild("EconCity"):WaitForChild("Util"))

-- UI mặc định này che bảng Xây dựng
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

-- ScreenGui ------------------------------------------------------------------------
local function makeScreenGui(name, order)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = order
	gui.Parent = playerGui
	return gui
end
local gui = makeScreenGui("EconCityUI", 1)
local modalGui = makeScreenGui("EconCityModals", 10)
local toastGui = makeScreenGui("EconCityToasts", 20) -- toast luôn nằm trên cùng

local camTouch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

local scales = {}
for _, g in ipairs({ gui, modalGui, toastGui }) do
	local s = Instance.new("UIScale")
	s.Parent = g
	table.insert(scales, s)
end
-- UI dựng theo khung 1366x768 rồi scale theo màn hình.
-- điện thoại không scale dưới 0.72 (chữ không đọc nổi), thay vào đó chuyển layout compact
local layout = { compact = false, designW = 1366, designH = 768 }
local layoutListeners = {}
local function rescale()
	local size = gui.AbsoluteSize -- đã trừ topbar Roblox
	if size.X <= 0 or size.Y <= 0 then
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		size = camera.ViewportSize
	end
	local scale = math.min(size.X / 1366, size.Y / 768)
	scale = math.clamp(scale, camTouch and 0.72 or 0.6, 1.15)
	for _, s in ipairs(scales) do
		s.Scale = scale
	end
	layout.designW = size.X / scale
	layout.designH = size.Y / scale
	layout.compact = layout.designW < 1250 or layout.designH < 700
	for _, fn in ipairs(layoutListeners) do
		local ok, err = pcall(fn, layout)
		if not ok then
			warn("[EconCity] Layout error: " .. tostring(err))
		end
	end
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)

-- Thế giới 3D -----------------------------------------------------------------------
local renderer = CityRenderer.new()
local mood = Mood.new(renderer)
local CITY_CENTER = Vector3.new(CityLayout.ORIGIN.x, 0, CityLayout.ORIGIN.z)
-- bảng Xây dựng che bên phải nên dời điểm nhìn sang phải, thành phố nằm giữa phần trống.
-- với góc camera này (1, 0, -1) trên mặt đất là bên phải màn hình
local PANEL_FOCUS_SHIFT = Vector3.new(12, 0, -12)
local PHONE_FOCUS_SHIFT = Vector3.new(-6, 0, -6)
local camera = CameraController.new(CITY_CENTER)

-- Giao diện -----------------------------------------------------------------------------
local toasts = Overlays.toasts(toastGui)

local function request(action, payload)
	local response = State.request(action, payload)
	return response
end

local function requestOrToast(action, payload)
	local response = request(action, payload)
	if not response.ok then
		toasts.show(response.error or "Couldn't do that", "error")
	end
	return response
end

local historyModal, leaderboardModal, classModal, buildPanel, builder, approvalStamp, detail
local positionCamBox

local panelVisible = true
if camTouch and Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize.X < 1000 then
	panelVisible = false
end

local function startNewGame()
	local response = requestOrToast("newGame")
	if response.ok then
		toasts.show("New game: build homes, jobs and services, then press START.", "good")
	end
end

local hud = Hud.new(gui, {
	onTogglePause = function()
		local s = State.session()
		local starting = s ~= nil and s.status == "PAUSED" and s.month == 0
		local response = requestOrToast("togglePause")
		if response.ok and starting then
			approvalStamp.show("City is open!", string.format("Your %d-month term begins", s.maxMonths or 24))
		end
	end,
	onNewGame = startNewGame,
	onHistory = function()
		historyModal.open()
	end,
	onLeaderboard = function()
		leaderboardModal.open()
	end,
	onClass = function()
		classModal.open()
	end,
	onTickNow = function()
		requestOrToast("tickNow")
	end,
	onTogglePanel = function()
		panelVisible = not panelVisible
		buildPanel.setVisible(panelVisible)
		hud.setPanelVisible(panelVisible)
		positionCamBox()
	end,
})

buildPanel = BuildPanel.new(gui, {
	onSelectTool = function(tool)
		builder:setTool(tool)
	end,
	onInfo = function(id)
		detail.openVariant(id, State.snapshot)
	end,
	onSetTax = function(tax)
		local response = requestOrToast("setTax", { tax = tax })
		return response.ok, response.error
	end,
	onDemoBuild = function()
		local response = requestOrToast("demoBuild")
		if not response.ok then
			return
		end
		local built = response.data and response.data.built or 0
		if built > 0 then
			local s = State.session()
			local hint = (s and s.month == 0) and " Press START to watch the city run." or " Press again in a few months to build more."
			toasts.show(string.format("Buildings added by the bot: %d (roads to the gate, homes, jobs, services).%s", built, hint), "good")
		else
			toasts.show("Bot couldn't build more: not enough money (it keeps 2 months of upkeep) or no space left.")
		end
	end,
})
buildPanel.setVisible(panelVisible)

local cityBar = Overlays.cityBar(gui)
approvalStamp = Overlays.stamp(gui)
local events = Overlays.eventsColumn(gui)
detail = Overlays.detailPanel(gui, {
	previewModel = CityRenderer.previewModel,
	onChoose = function(id)
		if builder.tool ~= id then
			builder:setTool(id)
		end
	end,
	onDemolish = function(index)
		task.spawn(function()
			local response = requestOrToast("demolish", { index = index })
			if response.ok then
				toasts.show("Demolished, refunded " .. Util.formatMoneyFull(response.data and response.data.refund or 0))
			end
		end)
	end,
})
local endScreen = Overlays.endScreen(gui, {
	onNewGame = startNewGame,
	onHistory = function()
		historyModal.open()
	end,
})

local getSnapshot = function()
	return State.snapshot
end
leaderboardModal = Modals.leaderboard(modalGui, { request = request, getSnapshot = getSnapshot })
historyModal = Modals.history(modalGui, { getSnapshot = getSnapshot })
classModal = ClassPanel.new(modalGui, { request = request, getSnapshot = getSnapshot, toast = toasts.show })

-- chế độ toàn cảnh thì tắt điều khiển nhân vật: WASD không kéo nhân vật chạy ra ngoài khung hình,
-- joystick trên điện thoại cũng không che UI
local characterControls = nil
local cameraMode = "overview"
local function applyControlMode()
	if characterControls then
		pcall(function()
			if cameraMode == "overview" then
				characterControls:Disable()
			else
				characterControls:Enable()
			end
		end)
	end
end
task.spawn(function()
	local ok, controls = pcall(function()
		local scripts = player:WaitForChild("PlayerScripts", 10)
		local module = scripts and scripts:WaitForChild("PlayerModule", 10)
		return module and require(module):GetControls()
	end)
	if ok and controls then
		-- phải chờ có character, tắt sớm Roblox báo "Player:Move called..."
		if not player.Character then
			player.CharacterAdded:Wait()
		end
		characterControls = controls
		applyControlMode()
	end
end)

-- nút camera
local camBox = C.new("Frame", {
	Name = "CameraControls",
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(104, 150),
	Position = UDim2.new(1, -12, 1, -12),
	AnchorPoint = Vector2.new(1, 1),
	Parent = gui,
})
C.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom).Parent = camBox
local zoomIn = C.button({ Name = "ZoomIn", Text = "+", Font = Theme.FontDisplay, TextSize = 22, Variant = "white", Size = UDim2.fromOffset(42, 42), Radius = 21, LayoutOrder = 1, Parent = camBox }, function()
	camera:zoomBy(-2)
end)
local zoomOut = C.button({ Name = "ZoomOut", Text = "−", Font = Theme.FontDisplay, TextSize = 22, Variant = "white", Size = UDim2.fromOffset(42, 42), Radius = 21, LayoutOrder = 2, Parent = camBox }, function()
	camera:zoomBy(2)
end)
local walkButton
walkButton = C.button({ Name = "Walk", Text = "Walk", TextSize = 12, Variant = "white", Size = UDim2.fromOffset(104, 40), Radius = 20, LayoutOrder = 3, Parent = camBox }, function()
	local mode = camera:toggleMode()
	cameraMode = mode
	applyControlMode()
	walkButton.Text = mode == "overview" and "Walk" or "Overview"
	zoomIn.Visible = mode == "overview"
	zoomOut.Visible = mode == "overview"
	toasts.show(mode == "overview" and "Overview mode" or "Walk mode: move with WASD or a controller. To build, pick a building and click a tile.")
end)

-- không cho nút camera đè bảng Xây dựng, thanh chỉ số, joystick, nút nhảy
positionCamBox = function()
	local panelHeight = math.min(BuildPanel.FULL_HEIGHT, layout.designH - (BuildPanel.TOP + 12))
	local roomBelowPanel = layout.designH >= BuildPanel.TOP + panelHeight + 12 + 150 + 12
	local besidePanel = panelVisible and not roomBelowPanel
	if camTouch then
		-- điện thoại: giữa cạnh phải, góc dưới phải là nút nhảy lúc đi dạo
		camBox.AnchorPoint = Vector2.new(1, 0.5)
		camBox.Position = UDim2.new(1, panelVisible and -(BuildPanel.WIDTH + 24) or -12, 0.62, 0)
	else
		camBox.AnchorPoint = Vector2.new(1, 1)
		camBox.Position = UDim2.new(1, besidePanel and -(BuildPanel.WIDTH + 24) or -12, 1, -12)
	end
	if camTouch then
		-- dời điểm nhìn ra xa cho sa bàn nằm dưới khung tên và hàng nút
		camera:setFocus(CITY_CENTER + PHONE_FOCUS_SHIFT)
	else
		camera:setFocus(panelVisible and CITY_CENTER + PANEL_FOCUS_SHIFT or CITY_CENTER)
	end
end

if camTouch then
	local top = { UDim2.new(0.5, 0, 0, 96), Vector2.new(0.5, 0) }
	detail.positions.placed = top
	detail.positions.catalog = top
else
	-- thẻ mẫu (nút "i") sát trái bảng Xây dựng, ngang đầu bảng
	detail.positions.catalog = { UDim2.new(1, -(BuildPanel.WIDTH + 24), 0, BuildPanel.TOP), Vector2.new(1, 0) }
end

table.insert(layoutListeners, function(l)
	-- màn hẹp: chữ tối thiểu 13 (khoảng 9px ở UIScale 0.72), layout gọn lại cho sa bàn rộng hơn
	C.setTextFloor(l.compact and 13 or 0)
	hud.setCompact(l.compact)
	cityBar.setCompact(l.compact)
	events.setCompact(l.compact)
	buildPanel.setMaxHeight(l.designH - (BuildPanel.TOP + 12))
	C.fitModals(l.designW, l.designH)
	positionCamBox()
end)
rescale()

-- chat mặc định ở góc trên trái, đè bảng chỉ số. game học tập nên ẩn luôn (Roblox cũng bắt kiểm tra tuổi mới cho chat)
-- muốn bật lại: Config.SHOW_CHAT_WINDOW = true
if not Config.SHOW_CHAT_WINDOW then
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
	end)
	pcall(function()
		local TextChatService = game:GetService("TextChatService")
		local window = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
		if window then
			window.Enabled = false
		end
		local inputBar = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
		if inputBar then
			inputBar.Enabled = false
		end
	end)
end

-- Cập nhật theo trạng thái -------------------------------------------------------------
local firstRender = true
local lastSessionId = nil
local readySent = false

-- server chỉ bắt đầu tính lượt sau clientReady, máy yếu tải chậm không bị mất lượt
local function sendClientReady()
	for _ = 1, 10 do
		local response = request("clientReady")
		if response.ok then
			return
		end
		task.wait(1)
	end
end

State.subscribe(function(snap, previous)
	local s = snap.session
	if not s then
		return
	end
	hud.update(snap)
	local d = CityEngine.compute(s, s.population or 0)
	hud.setNet(d.net, d.C, d.J)
	buildPanel.update(snap)
	cityBar.update(snap)
	events.update(snap)
	detail.update(snap)
	endScreen.update(snap)
	historyModal.refreshIfOpen(snap.reason)

	local sameSession = lastSessionId == s.id
	local animate = not firstRender and sameSession
	if not sameSession and builder then
		builder:setTool(nil) -- ván mới thì bỏ tool đang chọn
	end
	renderer:update(s, animate)
	mood:apply(s.happiness, s.status, firstRender)
	lastSessionId = s.id
	firstRender = false
	if not readySent then
		readySent = true
		task.spawn(sendClientReady)
	end

	-- toast các khủng hoảng mới xuất hiện ở tháng này
	if previous and previous.session and sameSession and snap.reason == "tick" then
		local before = {}
		for _, key in ipairs(previous.session.crises or {}) do
			before[key] = true
		end
		for _, key in ipairs(s.crises or {}) do
			if not before[key] then
				toasts.show(Config.CRISIS_LABELS[key] or key, "error")
			end
		end
	end
end)

State.stateEvent.OnClientEvent:Connect(State.set)
State.noticeEvent.OnClientEvent:Connect(function(text)
	toasts.show(tostring(text))
end)

-- tự lấy state lần đầu, phòng khi gói "init" tới trước lúc script chạy xong
task.spawn(function()
	-- server có thể phải chờ server cũ nhả lock hồ sơ (tới khoảng 20s), nên chờ đủ lâu rồi mới báo lỗi
	for _ = 1, 45 do
		if State.snapshot then
			return
		end
		local response = request("getState")
		if response.ok and response.data and response.data.session then
			State.set(response.data)
			return
		end
		task.wait(1)
	end
	if not State.snapshot then
		toasts.show("Couldn't reach the game server. Please rejoin.", "error")
	end
end)

-- Đồng hồ đếm ngược ---------------------------------------------------------------------
local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	local snap = State.snapshot
	accumulator = accumulator + dt
	if accumulator >= 0.2 then
		accumulator = 0
		hud.updateCountdown(snap, State.serverNow())
	end
end)

-- Xây dựng trên bản đồ ----------------------------------------------------------------------
-- có UI của game dưới con trỏ thì chặn click xuyên xuống thành phố
local function pointerOverUi(position)
	local ok, objects = pcall(function()
		return playerGui:GetGuiObjectsAtPosition(position.X, position.Y)
	end)
	if not ok then
		return false
	end
	for _, object in ipairs(objects) do
		local ours = object:IsDescendantOf(gui) or object:IsDescendantOf(modalGui) or object:IsDescendantOf(toastGui)
		-- đồ trang trí (pháo giấy, viền phá sản...) không chặn click
		local decor = object:GetAttribute("Decor") == true
		if ours and not decor and object.Visible and (object:IsA("GuiButton") or object.BackgroundTransparency < 0.95) then
			return true
		end
	end
	return false
end

builder = BuildController.new({
	renderer = renderer,
	getSession = State.session,
	isOverview = function()
		return cameraMode == "overview"
	end,
	request = request,
	toast = toasts.show,
	inspect = function(index)
		detail.open(index, State.snapshot)
	end,
	pointerOverUi = pointerOverUi,
	onToolChanged = function(tool)
		buildPanel.setTool(tool)
	end,
	isGamepad = C.isGamepadMode,
})

print("[EconCity] Client ready: " .. Theme.StatusText.ACTIVE)
