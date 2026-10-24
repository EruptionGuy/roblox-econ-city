-- Camera nhìn chéo cố định xuống cả thành phố (có zoom), hoặc chế độ đi dạo dùng camera mặc định theo nhân vật.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CameraController = {}
CameraController.__index = CameraController

local DIRECTION = Vector3.new(1, 1.15, 1).Unit
-- điện thoại màn thấp: nhìn dốc hơn cho lọt cả thành phố
local DIRECTION_TOUCH = Vector3.new(1, 1.6, 1).Unit
local STUDS_PER_ZOOM = 9

function CameraController.new(focus)
	local self = setmetatable({}, CameraController)
	local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	self.focus = focus or Vector3.new(0, 0, 0)
	self.currentFocus = self.focus
	self.direction = touch and DIRECTION_TOUCH or DIRECTION
	-- zoom mặc định: đủ gần để thấy rõ nhà mà vẫn thấy hết lưới 12x12
	self.minZoom = touch and 12 or 9
	self.maxZoom = touch and 36 or 30
	self.zoom = touch and 25 or 22
	self.currentZoom = self.zoom
	self.mode = "overview"
	self._connections = {}

	table.insert(self._connections, UserInputService.InputChanged:Connect(function(input, processed)
		if processed or self.mode ~= "overview" then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			self:zoomBy(-input.Position.Z * 2)
		end
	end))
	local pinchStartZoom = self.zoom
	table.insert(self._connections, UserInputService.TouchPinch:Connect(function(_, scale, _, state, processed)
		if processed or self.mode ~= "overview" then
			return
		end
		if state == Enum.UserInputState.Begin then
			pinchStartZoom = self.zoom
		elseif state == Enum.UserInputState.Change and scale > 0 then
			-- scale tính từ lúc bắt đầu chụm. Chụm vào (scale < 1) thì lùi xa, mở ra thì lại gần
			self.zoom = math.clamp(pinchStartZoom / scale, self.minZoom, self.maxZoom)
		end
	end))
	-- phải chạy sau camera script mặc định của Roblox
	RunService:BindToRenderStep("EconCityCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		self:_update(dt)
	end)
	self:setMode("overview")
	return self
end

-- dời điểm nhìn (vd. né bảng Xây dựng bên phải), _update tự lerp tới
function CameraController:setFocus(focus)
	self.focus = focus
end

function CameraController:zoomBy(delta)
	self.zoom = math.clamp(self.zoom + delta, self.minZoom, self.maxZoom)
end

function CameraController:_update(dt)
	if self.mode ~= "overview" then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	local alpha = math.clamp(dt * 8, 0, 1)
	self.currentZoom = self.currentZoom + (self.zoom - self.currentZoom) * alpha
	self.currentFocus = self.currentFocus + (self.focus - self.currentFocus) * alpha
	local distance = self.currentZoom * STUDS_PER_ZOOM
	local position = self.currentFocus + self.direction * distance
	camera.CFrame = CFrame.lookAt(position, self.currentFocus)
	camera.Focus = CFrame.new(self.currentFocus) -- cho LOD / ánh sáng quanh chỗ nhìn
	camera.FieldOfView = 50
end

function CameraController:setMode(mode)
	self.mode = mode
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if mode == "overview" then
		camera.CameraType = Enum.CameraType.Scriptable
	else
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

function CameraController:toggleMode()
	self:setMode(self.mode == "overview" and "walk" or "overview")
	return self.mode
end

return CameraController
