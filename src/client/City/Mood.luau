-- Đổi trời/ánh sáng theo hạnh phúc thành phố, chỉ local ở client này.
-- >= 65 HAPPY, 50-64 NEUTRAL, < 50 CRISIS. FAILED luôn là CRISIS, PAUSED thì ngả xám thêm.

local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Mood = {}
Mood.__index = Mood

local PRESETS = {
	HAPPY = {
		lighting = { ClockTime = 14, Brightness = 3, OutdoorAmbient = Color3.fromRGB(150, 145, 135), Ambient = Color3.fromRGB(90, 88, 84) },
		atmosphere = { Density = 0.25, Haze = 0, Glare = 0.2, Color = Color3.fromRGB(205, 220, 240), Decay = Color3.fromRGB(120, 140, 170) },
		correction = { Brightness = 0.03, Contrast = 0.08, Saturation = 0.12, TintColor = Color3.fromRGB(255, 248, 236) },
	},
	NEUTRAL = {
		lighting = { ClockTime = 16.4, Brightness = 2, OutdoorAmbient = Color3.fromRGB(128, 124, 116), Ambient = Color3.fromRGB(80, 78, 74) },
		atmosphere = { Density = 0.36, Haze = 1.4, Glare = 0, Color = Color3.fromRGB(210, 200, 170), Decay = Color3.fromRGB(150, 130, 100) },
		correction = { Brightness = 0, Contrast = 0.04, Saturation = -0.05, TintColor = Color3.fromRGB(250, 244, 228) },
	},
	CRISIS = {
		lighting = { ClockTime = 17.6, Brightness = 1.1, OutdoorAmbient = Color3.fromRGB(96, 98, 106), Ambient = Color3.fromRGB(62, 64, 70) },
		atmosphere = { Density = 0.5, Haze = 3, Glare = 0, Color = Color3.fromRGB(150, 152, 160), Decay = Color3.fromRGB(90, 92, 100) },
		correction = { Brightness = -0.04, Contrast = 0.02, Saturation = -0.3, TintColor = Color3.fromRGB(214, 218, 228) },
	},
}

function Mood.new(renderer)
	local self = setmetatable({}, Mood)
	self.renderer = renderer
	self.current = nil
	self.paused = nil

	self.atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not self.atmosphere then
		self.atmosphere = Instance.new("Atmosphere")
		self.atmosphere.Parent = Lighting
	end
	self.correction = Lighting:FindFirstChild("EconCityMood")
	if not self.correction then
		self.correction = Instance.new("ColorCorrectionEffect")
		self.correction.Name = "EconCityMood"
		self.correction.Parent = Lighting
	end
	self.pauseEffect = Lighting:FindFirstChild("EconCityPause")
	if not self.pauseEffect then
		self.pauseEffect = Instance.new("ColorCorrectionEffect")
		self.pauseEffect.Name = "EconCityPause"
		self.pauseEffect.Parent = Lighting
	end
	Lighting.GlobalShadows = true
	self.lightHaze = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	return self
end

function Mood.presetFor(happiness, status)
	if status == "FAILED" then
		return "CRISIS"
	end
	if happiness >= 65 then
		return "HAPPY"
	elseif happiness >= 50 then
		return "NEUTRAL"
	end
	return "CRISIS"
end

function Mood:apply(happiness, status, instant)
	local key = Mood.presetFor(happiness, status)
	local duration = instant and 0 or 2.5
	if key ~= self.current then
		self.current = key
		local preset = PRESETS[key]
		local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		TweenService:Create(Lighting, info, preset.lighting):Play()
		local atmosphere = preset.atmosphere
		if self.lightHaze then
			-- màn hình nhỏ: bớt sương cho đỡ che công trình
			local copy = {}
			for k, v in pairs(atmosphere) do
				copy[k] = v
			end
			atmosphere = copy
			atmosphere.Density = atmosphere.Density * 0.6
			atmosphere.Haze = atmosphere.Haze * 0.5
		end
		TweenService:Create(self.atmosphere, info, atmosphere):Play()
		TweenService:Create(self.correction, info, preset.correction):Play()
	end
	local paused = status == "PAUSED"
	if paused ~= self.paused then
		self.paused = paused
		TweenService:Create(self.pauseEffect, TweenInfo.new(instant and 0 or 0.4), { Saturation = paused and -0.35 or 0 }):Play()
	end
end

return Mood
