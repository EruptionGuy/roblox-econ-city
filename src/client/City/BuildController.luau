-- Xây/phá trên thành phố 3D bằng công cụ đang chọn, không có công cụ thì bấm ô để xem thông tin.
-- Đường: giữ và kéo theo hàng/cột. Tay cầm: D-pad dời ô, A xây/phá, B bỏ công cụ. 2x2: ô bấm là góc trên-trái.
-- Server kiểm tra lại hết (CityEngine), ở đây chỉ để hiện trước.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("EconCity")
local Config = require(Shared:WaitForChild("Config"))
local CityLayout = require(Shared:WaitForChild("CityLayout"))
local CityEngine = require(Shared:WaitForChild("CityEngine"))
local Util = require(Shared:WaitForChild("Util"))

local N = Config.GRID_SIZE

local BuildController = {}
BuildController.__index = BuildController

-- deps: renderer (CityRenderer), getSession(), isOverview(): bool (false = đang đi dạo),
--   request(action, payload): { ok, data, error } (gọi trong task riêng), toast(text, kind), inspect(index),
--   pointerOverUi(position): bool, isGamepad(): bool, onToolChanged(tool) tuỳ chọn
function BuildController.new(deps)
	local self = setmetatable({}, BuildController)
	self.deps = deps
	self.renderer = deps.renderer
	self.tool = nil
	self.path = nil
	self.dragInput = nil
	self.hover = nil
	self.cursor = Config.GATE_INDEX - N -- ô ngay trên cổng
	self:_connect()
	return self
end

-- đoán trước để tô màu: "ok" | "warn" (được nhưng chưa nối đường về cổng) | "bad"
function BuildController:preview(index)
	local session = self.deps.getSession()
	if not session or not index or not session.cells or not self.tool then
		return "bad"
	end
	if session.status == "ENDED" or session.status == "FAILED" then
		return "bad"
	end
	local cells = session.cells
	if self.tool == "demolish" then
		local anchor = CityEngine.anchorOf(cells, index)
		return (cells[anchor] ~= Config.EMPTY and anchor ~= Config.GATE_INDEX) and "ok" or "bad"
	end
	local fp = CityEngine.footprint(index, Config.BUILDINGS[self.tool].size)
	if not fp or session.budget < CityEngine.priceOf(session, self.tool) then
		return "bad"
	end
	for _, c in ipairs(fp) do
		if cells[c] ~= Config.EMPTY then
			return "bad"
		end
	end
	-- có ô đường đã nối cổng nằm sát vùng xây không
	local conn = CityEngine.connectivity(cells)
	for _, c in ipairs(fp) do
		for _, j in ipairs(CityEngine.neighbours(c)) do
			if cells[j] == "road" and conn[j] then
				return "ok"
			end
		end
	end
	return "warn"
end

-- index = nil để ẩn. Phá dỡ thì tô cả công trình sẽ bị phá
function BuildController:showGhost(index)
	if not index or not self.tool then
		self.renderer:setGhost(nil)
		return
	end
	local anchor, size = index, Config.BUILDINGS[self.tool] and Config.BUILDINGS[self.tool].size or 1
	local session = self.deps.getSession()
	if self.tool == "demolish" and session and session.cells then
		anchor = CityEngine.anchorOf(session.cells, index)
		local def = Config.BUILDINGS[session.cells[anchor]]
		size = def and def.size or 1
	end
	self.renderer:setGhost(anchor, self:preview(index), size)
end

function BuildController:setTool(tool)
	if tool == self.tool then
		tool = nil -- bấm lại công cụ đang chọn = bỏ chọn
	end
	self.tool = tool
	self.path = nil
	self.dragInput = nil
	self.renderer:setPath(nil)
	if tool and self.deps.isGamepad and self.deps.isGamepad() then
		-- bỏ chọn nút UI để D-pad điều khiển ô trên bản đồ
		pcall(function()
			GuiService.SelectedObject = nil
		end)
		self:showGhost(self.cursor)
	else
		self:showGhost(nil)
	end
	if self.deps.onToolChanged then
		self.deps.onToolChanged(tool)
	end
end

local function send(self, action, payload, okText)
	task.spawn(function()
		local response = self.deps.request(action, payload)
		if not response.ok then
			self.deps.toast(response.error or "Không thực hiện được", "error")
		elseif okText then
			self.deps.toast(okText(response.data or {}))
		end
	end)
end

function BuildController:apply(index)
	local tool = self.tool
	if not tool then
		self.deps.inspect(index)
	elseif tool == "demolish" then
		send(self, "demolish", { index = index }, function(data)
			return "Đã phá dỡ, hoàn " .. Util.formatMoneyFull(data.refund or 0)
		end)
	elseif tool == "road" then
		send(self, "buildRoad", { path = { index } })
	else
		local unconnected = self:preview(index) == "warn"
		send(self, "build", { kind = tool, index = index }, unconnected and function()
			return "Chưa nối đường về CỔNG nên công trình này chưa hoạt động. Hãy kéo đường tới nó."
		end or nil)
	end
end

-- chỉ nhận ô cùng hàng/cột với ô cuối, tự lấp ô ở giữa
function BuildController.extendPath(path, j)
	local last = path[#path]
	for _, i in ipairs(path) do
		if i == j then
			return
		end
	end
	local lx, ly = CityLayout.cellXY(last)
	local jx, jy = CityLayout.cellXY(j)
	if lx ~= jx and ly ~= jy then
		return
	end
	local step = (lx == jx) and (jy > ly and N or -N) or (jx > lx and 1 or -1)
	local k = last + step
	while #path < Config.MAX_ROAD_PATH do
		local seen = false
		for _, i in ipairs(path) do
			if i == k then
				seen = true
			end
		end
		if not seen then
			table.insert(path, k)
		end
		if k == j then
			break
		end
		k = k + step
	end
end

function BuildController:cellAtScreen(position)
	local cam = Workspace.CurrentCamera
	if not cam then
		return nil
	end
	local ray = cam:ScreenPointToRay(position.X, position.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { self.renderer.folder }
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
	if not result then
		return nil
	end
	return CityLayout.cellAt(result.Position.X, result.Position.Z)
end

function BuildController:_finishDrag()
	local path = self.path
	self.path = nil
	self.dragInput = nil
	self.renderer:setPath(nil)
	if path and #path > 0 then
		send(self, "buildRoad", { path = path })
	end
end

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local GAMEPAD_MOVES = {
	[Enum.KeyCode.DPadUp] = { 0, -1 },
	[Enum.KeyCode.DPadDown] = { 0, 1 },
	[Enum.KeyCode.DPadLeft] = { -1, 0 },
	[Enum.KeyCode.DPadRight] = { 1, 0 },
}

function BuildController:_connect()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		-- tay cầm, chỉ khi không có nút UI nào đang được chọn
		local move = GAMEPAD_MOVES[input.KeyCode]
		local guiSelected = false
		pcall(function()
			guiSelected = GuiService.SelectedObject ~= nil
		end)
		if self.tool and not guiSelected and (move or input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.ButtonB) then
			if move then
				local x, y = CityLayout.cellXY(self.cursor)
				x = math.clamp(x + move[1], 1, N)
				y = math.clamp(y + move[2], 1, N)
				self.cursor = (y - 1) * N + x
				self:showGhost(self.cursor)
			elseif input.KeyCode == Enum.KeyCode.ButtonA then
				self:apply(self.cursor)
			else
				self:setTool(nil)
			end
			return
		end
		if not isPointer(input) or self.deps.pointerOverUi(input.Position) then
			return
		end
		-- đi dạo trên cảm ứng: vuốt là xoay camera nên chỉ xây khi chạm nhẹ
		if input.UserInputType == Enum.UserInputType.Touch and not self.deps.isOverview() then
			self.tap = { input = input, x = input.Position.X, y = input.Position.Y } -- xử lý lúc nhấc tay
			return
		end
		local index = self:cellAtScreen(input.Position)
		if not index then
			return
		end
		if self.tool == "road" then
			self.path = { index }
			self.dragInput = input
			self.renderer:setGhost(nil)
			self.renderer:setPath(self.path)
		else
			self:apply(index)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not self.tool then
			return
		end
		local dragging = self.path ~= nil
		local isMouse = input.UserInputType == Enum.UserInputType.MouseMovement
		if dragging then
			local follow = (isMouse and self.dragInput.UserInputType == Enum.UserInputType.MouseButton1) or input == self.dragInput
			if not follow then
				return
			end
			-- nhả chuột ngoài cửa sổ có thể không có InputEnded
			if isMouse and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
				self:_finishDrag()
				return
			end
			local index = self:cellAtScreen(input.Position)
			if index then
				BuildController.extendPath(self.path, index)
				self.renderer:setPath(self.path)
			end
		elseif isMouse then
			local index = self:cellAtScreen(input.Position)
			if index ~= self.hover then
				self.hover = index
				self:showGhost(index)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		local tap = self.tap
		if tap and input == tap.input then
			self.tap = nil
			if math.abs(input.Position.X - tap.x) + math.abs(input.Position.Y - tap.y) < 16 then
				local index = self:cellAtScreen(input.Position)
				if index then
					self:apply(index)
				end
			end
			return
		end
		if not self.path then
			return
		end
		if input == self.dragInput or (self.dragInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then
			self:_finishDrag()
		end
	end)
end

return BuildController
