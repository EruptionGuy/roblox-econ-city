-- Vòng đời phiên chơi và 1 lượt tính (1 tháng), docs/luat-choi-moi.md mục 4-6.
-- session là bảng Lua thuần, lưu thẳng vào DataStore được

local Config = require(script.Parent.Config)
local Util = require(script.Parent.Util)
local Scenarios = require(script.Parent.Scenarios)
local CityEngine = require(script.Parent.CityEngine)

local GameTick = {}

GameTick.STATUS = {
	ACTIVE = "ACTIVE",
	PAUSED = "PAUSED",
	ENDED = "ENDED",
	FAILED = "FAILED",
}

-- ván mới: tháng 0, PAUSED (người chơi xây trước rồi bấm Bắt đầu), lưới trống trừ ô cổng
function GameTick.newSession(userId, sessionId, now)
	local session = {
		id = sessionId,
		userId = userId,
		createdAt = now or 0,
		month = 0,
		maxMonths = Config.GAME_DURATION_MONTHS,
		status = GameTick.STATUS.PAUSED,
		budget = Config.START_BUDGET,
		tax = Config.START_TAX,
		population = 0,
		employed = 0,
		employment = 100,
		gdp = 0, -- thật ra là doanh thu R tháng gần nhất, giữ tên gdp cho báo cáo lớp/CSV
		happiness = 0,
		prosperityScore = 0,
		cells = CityEngine.newCells(),
		scenarios = {},
		crises = {},
		history = {},
		autoPaused = false,
	}
	session.happiness = CityEngine.compute(session, 0).H -- = 82 với thuế 20%
	return session
end

function GameTick.isFinished(session)
	return session.status == GameTick.STATUS.ENDED or session.status == GameTick.STATUS.FAILED
end

-- mục 6
function GameTick.prosperityScore(session)
	return CityEngine.score(session.employed or 0, session.happiness or 0, session.budget or 0)
end

-- false nếu sự kiện không tồn tại hoặc đang chạy.
-- customDef (tuỳ chọn, kịch bản giáo viên tự tạo): { name, description, severity, durationMonths, effects }
function GameTick.addScenario(session, scenarioId, meta, customDef)
	if not Scenarios.get(scenarioId) and type(customDef) ~= "table" then
		return false, "Kịch bản không tồn tại"
	end
	if GameTick.isFinished(session) then
		return false, "Ván đã kết thúc"
	end
	for _, s in ipairs(session.scenarios) do
		if s.id == scenarioId then
			return false, "Kịch bản đang diễn ra"
		end
	end
	local entry = { id = scenarioId, monthsActive = 0 }
	if not Scenarios.get(scenarioId) then
		entry.custom = true
		entry.name = customDef.name
		entry.description = customDef.description
		entry.severity = customDef.severity
		entry.durationMonths = customDef.durationMonths
		entry.effects = Util.deepCopy(customDef.effects)
	end
	if meta then
		for k, v in pairs(meta) do
			entry[k] = v
		end
	end
	table.insert(session.scenarios, entry)
	return true
end

-- 1 lượt = 1 tháng. Sửa session tại chỗ, trả về tóm tắt lượt.
-- thứ tự (mục 4): dân đến/đi theo H tháng trước, việc làm, hàng hoá, doanh thu, ngân sách,
-- dịch vụ, hạnh phúc, cảnh báo, thắng/thua
function GameTick.processTick(session)
	if session.status ~= GameTick.STATUS.ACTIVE then
		return nil
	end
	local effects = Scenarios.aggregate(session.scenarios)
	local before = CityEngine.compute(session, session.population, effects)
	session.population = CityEngine.migrate(session.population, before.C, before.J, session.happiness, effects.leaveRate)
	local d = CityEngine.compute(session, session.population, effects)

	session.month = session.month + 1
	session.budget = Util.clamp(session.budget + d.net, Config.BUDGET_CLAMP[1], Config.BUDGET_CLAMP[2])
	session.happiness = d.H
	session.employment = d.E
	session.employed = d.emp
	session.gdp = d.R

	local kept, finishedScenarios = Scenarios.advance(session.scenarios)
	session.scenarios = kept
	session.crises = CityEngine.crises(session, d)
	session.prosperityScore = GameTick.prosperityScore(session)

	if session.budget < Config.FAIL_BUDGET then
		session.status = GameTick.STATUS.FAILED
	elseif session.month >= session.maxMonths then
		session.status = GameTick.STATUS.ENDED
	end

	table.insert(session.history, {
		month = session.month,
		budget = Util.roundTo(session.budget, 2),
		gdp = Util.roundTo(d.R, 2),
		happiness = Util.roundTo(d.H, 2),
		employment = Util.roundTo(d.E, 1),
		population = session.population,
	})

	return {
		month = session.month,
		revenue = d.R,
		taxIn = d.taxIn,
		maintenance = d.M,
		budgetDelta = d.net,
		population = session.population,
		finishedScenarios = finishedScenarios,
		status = session.status,
	}
end

-- tóm tắt gọn cho giáo viên xem / lưu vào lớp.
-- withHistory: kèm lịch sử từng tháng (xuất CSV, chi tiết học sinh)
function GameTick.summary(session, withHistory)
	local history = nil
	if withHistory then
		history = {}
		for _, h in ipairs(session.history or {}) do
			table.insert(history, {
				month = h.month,
				budget = Util.roundTo(h.budget or 0, 0),
				gdp = Util.roundTo(h.gdp or 0, 0),
				happiness = Util.roundTo(h.happiness or 0, 1),
				employment = Util.roundTo(h.employment or 0, 1),
				population = h.population,
			})
		end
	end
	return {
		history = history,
		sessionId = session.id,
		month = session.month,
		maxMonths = session.maxMonths,
		status = session.status,
		budget = Util.roundTo(session.budget, 0),
		gdp = Util.roundTo(session.gdp or 0, 0),
		happiness = Util.roundTo(session.happiness, 1),
		employment = Util.roundTo(session.employment or 0, 1),
		population = session.population,
		prosperityScore = session.prosperityScore,
	}
end

return GameTick
