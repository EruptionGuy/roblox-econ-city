-- Sự kiện giáo viên gán cho lớp + gộp hiệu ứng các sự kiện đang chạy (docs/luat-choi-moi.md mục 8).
-- 4 sự kiện có sẵn đã chạy thử: điểm bot giảm 8-28%, không bot nào phá sản

local Scenarios = {}

Scenarios.CATALOG = {
	{
		id = "recession",
		name = "Recession",
		kind = "recession",
		severity = 6,
		durationMonths = 4,
		description = "People tighten their belts: revenue at every shop, factory and office drops to 70%.",
		effects = { revenueMultiplier = 0.7 },
	},
	{
		id = "supply",
		name = "Supply chain breakdown",
		kind = "supply",
		severity = 5,
		durationMonths = 4,
		description = "Factories deliver only half their goods: shops run short of things to sell.",
		effects = { goodsMultiplier = 0.5 },
	},
	{
		id = "pandemic",
		name = "Pandemic",
		kind = "pandemic",
		severity = 8,
		durationMonths = 6,
		description = "A disease spreads: 2% of residents leave each month and happiness drops 10 points.",
		effects = { leaveRate = 0.02, happinessPenalty = -10 },
	},
	{
		id = "prices",
		name = "Material price shock",
		kind = "prices",
		severity = 5,
		durationMonths = 5,
		description = "Material prices soar: new buildings cost 1.5 times as much and upkeep rises 30%.",
		effects = { priceMultiplier = 1.5, maintenanceMultiplier = 1.3 },
	},
}

local byId = {}
for _, s in ipairs(Scenarios.CATALOG) do
	byId[s.id] = s
end

function Scenarios.get(id)
	return byId[id]
end

-- nhiều sự kiện cùng chạy thì gộp: max lấy lớn nhất, sum cộng dồn, product nhân
Scenarios.EFFECT_RULES = {
	revenueMultiplier = { rule = "product", default = 1 },
	maintenanceMultiplier = { rule = "product", default = 1 },
	priceMultiplier = { rule = "product", default = 1 },
	goodsMultiplier = { rule = "product", default = 1 },
	happinessPenalty = { rule = "sum", default = 0 },
	leaveRate = { rule = "max", default = 0 },
}

-- kịch bản giáo viên tự tạo: cùng 6 hiệu ứng, kẹp trong khoảng an toàn
Scenarios.CUSTOM_EFFECTS = {
	{ key = "revenueMultiplier", label = "Revenue multiplier", min = 0.5, max = 1, step = 0.05, default = 1, kind = "multiplier" },
	{ key = "maintenanceMultiplier", label = "Upkeep multiplier", min = 1, max = 2, step = 0.1, default = 1, kind = "multiplier" },
	{ key = "priceMultiplier", label = "Build price multiplier", min = 1, max = 2, step = 0.1, default = 1, kind = "multiplier" },
	{ key = "goodsMultiplier", label = "Shop goods multiplier", min = 0.2, max = 1, step = 0.1, default = 1, kind = "multiplier" },
	{ key = "happinessPenalty", label = "Happiness change (points)", min = -30, max = 0, step = 1, default = 0, kind = "number" },
	{ key = "leaveRate", label = "Residents leaving per month", min = 0, max = 0.05, step = 0.005, default = 0, kind = "percent" },
}

local function clampStep(value, field)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return field.default
	end
	value = math.max(field.min, math.min(field.max, value))
	local steps = math.floor((value - field.min) / field.step + 0.5)
	return math.floor((field.min + steps * field.step) * 10000 + 0.5) / 10000
end

-- chuẩn hoá kịch bản client gửi lên. tên/mô tả thì server lọc riêng
function Scenarios.sanitizeCustom(input)
	if type(input) ~= "table" then
		return nil, "Invalid scenario data"
	end
	local severity = tonumber(input.severity) or 5
	local duration = tonumber(input.durationMonths) or 3
	local effects = {}
	local any = false
	local rawEffects = type(input.effects) == "table" and input.effects or {}
	for _, field in ipairs(Scenarios.CUSTOM_EFFECTS) do
		local v = clampStep(rawEffects[field.key], field)
		if v ~= field.default then
			effects[field.key] = v
			any = true
		end
	end
	if not any then
		return nil, "A scenario needs at least one effect"
	end
	return {
		severity = math.max(1, math.min(10, math.floor(severity + 0.5))),
		durationMonths = math.max(1, math.min(12, math.floor(duration + 0.5))),
		effects = effects,
	}
end

-- activeList: mảng { id = "recession", monthsActive = n, ... } trong session.
-- key không có trong EFFECT_RULES thì bỏ qua, nên kịch bản tự tạo lưu từ luật cũ không có tác dụng
function Scenarios.aggregate(activeList)
	local out = {}
	for key, spec in pairs(Scenarios.EFFECT_RULES) do
		out[key] = spec.default
	end
	for _, active in ipairs(activeList or {}) do
		local def = byId[active.id]
		local effects = (def and def.effects) or active.effects or {}
		for key, value in pairs(effects) do
			local spec = Scenarios.EFFECT_RULES[key]
			if spec and type(value) == "number" then
				if spec.rule == "max" then
					out[key] = math.max(out[key], value)
				elseif spec.rule == "sum" then
					out[key] = out[key] + value
				elseif spec.rule == "product" then
					out[key] = out[key] * value
				end
			end
		end
	end
	return out
end

-- tăng monthsActive, bỏ sự kiện hết hạn. Trả về (còn chạy, vừa kết thúc)
function Scenarios.advance(activeList)
	local kept, finished = {}, {}
	for _, active in ipairs(activeList or {}) do
		active.monthsActive = (active.monthsActive or 0) + 1
		local def = byId[active.id]
		local duration = (def and def.durationMonths) or active.durationMonths or 1
		if active.monthsActive >= duration then
			table.insert(finished, active)
		else
			table.insert(kept, active)
		end
	end
	return kept, finished
end

function Scenarios.monthsLeft(active)
	local def = byId[active.id]
	local duration = (def and def.durationMonths) or active.durationMonths or 1
	return math.max(0, duration - (active.monthsActive or 0))
end

return Scenarios
