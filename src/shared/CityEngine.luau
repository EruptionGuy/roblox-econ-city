-- Luật thành phố trên lưới (docs/luat-choi-moi.md mục 2-5). Hàm thuần, không gọi Roblox API: server, client (số dự kiến) và test đều dùng.
-- Bản JS: prototypes/luat-moi/engine.js. Phải tính đúng thứ tự như bên đó để ra cùng số, balance_sim so điểm 2 bên.
--
-- ô đánh số 1..N*N theo hàng: (hàng-1)*N + cột. session.cells[i] là:
--   Config.EMPTY   ô trống
--   "<id mẫu>"     ô góc trên-trái của công trình (Config.BUILDINGS[id]), hoặc "road"
--   "+<ô góc>"     ô phụ của công trình nhiều ô, vd "+37" là thuộc công trình có góc ở ô 37

local Config = require(script.Parent.Config)
local Util = require(script.Parent.Util)
local Scenarios = require(script.Parent.Scenarios)

local B = Config.BUILDINGS
local F = Config.FORMULA
local N = Config.GRID_SIZE
local EMPTY = Config.EMPTY

local CityEngine = {}

function CityEngine.newCells()
	local cells = {}
	for i = 1, N * N do
		cells[i] = EMPTY
	end
	cells[Config.GATE_INDEX] = "road"
	return cells
end

-- client gửi gì cũng có thể, nên check: số nguyên, nằm trong lưới
function CityEngine.isValidIndex(i)
	return type(i) == "number" and i == math.floor(i) and i >= 1 and i <= N * N
end

local function neighbours(i)
	local x = (i - 1) % N
	local out = {}
	if i > N then
		table.insert(out, i - N)
	end
	if i <= N * (N - 1) then
		table.insert(out, i + N)
	end
	if x > 0 then
		table.insert(out, i - 1)
	end
	if x < N - 1 then
		table.insert(out, i + 1)
	end
	return out
end
CityEngine.neighbours = neighbours

-- các ô công trình cạnh size chiếm khi góc trên-trái ở index, ô góc đứng đầu. Tràn lưới thì nil
function CityEngine.footprint(index, size)
	local col, row = (index - 1) % N + 1, math.floor((index - 1) / N) + 1
	if col + size - 1 > N or row + size - 1 > N then
		return nil
	end
	local out = {}
	for dy = 0, size - 1 do
		for dx = 0, size - 1 do
			table.insert(out, index + dy * N + dx)
		end
	end
	return out
end

-- ô góc của công trình chứa i. ô góc/đường/trống thì trả về chính i
function CityEngine.anchorOf(cells, i)
	local v = cells[i]
	if type(v) == "string" and string.sub(v, 1, 1) == "+" then
		return tonumber(string.sub(v, 2)) or i
	end
	return i
end

-- sửa lưới đọc từ DataStore, data cũ/hỏng không được làm sập game.
-- bỏ mã lạ, gắn lại ô "+góc", công trình không đủ chỗ thì bỏ. Sửa tại chỗ
function CityEngine.sanitizeCells(cells)
	local total = N * N
	for i = 1, total do
		local v = cells[i]
		if not B[v] then
			cells[i] = EMPTY
		end
	end
	for i = 1, total do
		local def = B[cells[i]]
		if def and def.size > 1 then
			local fp = CityEngine.footprint(i, def.size)
			local free = fp ~= nil
			for k = 2, fp and #fp or 0 do
				if cells[fp[k]] ~= EMPTY then
					free = false
				end
			end
			if free then
				for k = 2, #fp do
					cells[fp[k]] = "+" .. i
				end
			else
				cells[i] = EMPTY
			end
		end
	end
	return cells
end

-- (2) conn[i]: ô đường thông tới cổng, hoặc ô của công trình có ít nhất 1 ô kề đường đó
function CityEngine.connectivity(cells)
	local linked = { [Config.GATE_INDEX] = true }
	local stack = { Config.GATE_INDEX }
	while #stack > 0 do
		local i = table.remove(stack)
		for _, j in ipairs(neighbours(i)) do
			if not linked[j] and cells[j] == "road" then
				linked[j] = true
				table.insert(stack, j)
			end
		end
	end
	local conn = {}
	for i = 1, N * N do
		conn[i] = false
	end
	for i = 1, N * N do
		local t = cells[i]
		local def = B[t]
		if t == "road" then
			conn[i] = linked[i] == true
		elseif def then
			local fp = CityEngine.footprint(i, def.size) or { i }
			local ok = false
			for _, c in ipairs(fp) do
				for _, j in ipairs(neighbours(c)) do
					if linked[j] then
						ok = true
					end
				end
			end
			for _, c in ipairs(fp) do
				conn[c] = ok
			end
		end
	end
	return conn
end

-- (4) bước 2 và 4-9 của 1 tháng với dân số pop cho trước. Không sửa session
function CityEngine.compute(session, pop, eff)
	eff = eff or Scenarios.aggregate(session.scenarios)
	local cells = session.cells
	local conn = CityEngine.connectivity(cells)
	local slots = { shop = 0, factory = 0, office = 0 }
	local counts = {}
	local C, J, pts, M = 0, 0, 0, 0
	-- mỗi mẫu có lương/người riêng nên cộng dồn chỗ làm x lương theo loại đất
	local wages = { shop = 0, factory = 0, office = 0 }
	for i = 1, N * N do
		local b = B[cells[i]] -- chỉ ô góc (ô "+góc" không có trong B)
		if b then
			M = M + b.maint -- chưa nối vẫn tốn bảo trì
			counts[b.kind] = (counts[b.kind] or 0) + 1
			if conn[i] then
				C = C + (b.cap or 0)
				J = J + (b.jobs or 0)
				pts = pts + (b.pts or 0)
				if slots[b.kind] then
					slots[b.kind] = slots[b.kind] + b.jobs
					wages[b.kind] = wages[b.kind] + b.jobs * b.rev
				end
			end
		end
	end
	M = M * eff.maintenanceMultiplier
	local emp = math.min(pop, J)
	local f = J > 0 and emp / J or 0
	local E = pop > 0 and (emp / pop) * 100 or 100
	local G = slots.shop > 0 and math.min(1, (slots.factory * eff.goodsMultiplier) / slots.shop) or 1
	local R = f * (wages.shop * G + wages.factory + wages.office) * eff.revenueMultiplier
	local tax = session.tax
	local taxIn = (R * tax) / 100
	local S = pop > 0 and math.min(100, ((pts * F.residentsPerPoint) / pop) * 100) or 100
	local parts = {
		E = F.happinessEmploymentWeight * E,
		T = F.happinessTaxWeight * (100 - 2 * tax),
		S = F.happinessServiceWeight * S,
		event = eff.happinessPenalty,
	}
	local H = Util.clamp(parts.E + parts.T + parts.S + parts.event, 0, 100)
	return {
		conn = conn, counts = counts, slots = slots, C = C, J = J, pts = pts, emp = emp, f = f,
		E = E, G = G, R = R, taxIn = taxIn, M = M, net = taxIn - M, S = S, H = H, parts = parts,
	}
end

-- (4, bước 3) độ hấp dẫn A, dân mục tiêu P*
function CityEngine.attraction(H)
	return F.attractionMax * Util.clamp((H - F.attractionLow) / (F.attractionHigh - F.attractionLow), 0, 1)
end

function CityEngine.targetPop(C, J, H)
	return math.min(C, math.floor(J * CityEngine.attraction(H)))
end

-- H là của tháng trước, dân phản ứng trễ 1 tháng
function CityEngine.migrate(pop, C, J, H, leaveRate)
	pop = math.min(pop, C) -- nhà bị phá hoặc mất nối: dân đi ngay
	local diff = CityEngine.targetPop(C, J, H) - pop
	if diff > 0 then
		pop = pop + math.ceil(diff * F.moveRate)
	elseif diff < 0 then
		pop = pop - math.ceil(-diff * F.moveRate)
	end
	return pop - Util.round(pop * (leaveRate or 0))
end

-- mục 7
function CityEngine.crises(session, d)
	local c = Config.CRISIS
	local out = {}
	if session.budget < c.budgetBelow then
		table.insert(out, "BUDGET")
	end
	if d.H < c.happinessBelow then
		table.insert(out, "HAPPINESS")
	end
	if session.population > 0 and d.E < c.employmentBelow then
		table.insert(out, "UNEMPLOYMENT")
	end
	if d.slots.shop > 0 and d.G < c.goodsBelow then
		table.insert(out, "SHORTAGE")
	end
	return out
end

-- mục 6, điểm không âm
function CityEngine.score(employed, happiness, budget)
	return math.max(0, Util.round((employed * happiness) / 100 + budget / 100))
end

-- (5) Thao tác người chơi, trả về (true, data) hoặc (false, lỗi).
-- server validate mọi thứ client gửi lên qua mấy hàm này. client cũng gọi priceOf để hiện giá

local function finished(session)
	return session.status == "ENDED" or session.status == "FAILED"
end
local FINISHED_TEXT = "Ván đã kết thúc, hãy bắt đầu ván mới"

function CityEngine.priceOf(session, kind)
	return Util.round(B[kind].price * Scenarios.aggregate(session.scenarios).priceMultiplier)
end

function CityEngine.build(session, kind, index)
	if finished(session) then
		return false, FINISHED_TEXT
	end
	if type(kind) ~= "string" or not B[kind] then
		return false, "Loại công trình không hợp lệ"
	end
	if not CityEngine.isValidIndex(index) then
		return false, "Ô không hợp lệ"
	end
	local size = B[kind].size
	local fp = CityEngine.footprint(index, size)
	if not fp then
		return false, string.format("%s cần %dx%d ô, tràn ra ngoài lưới", B[kind].label, size, size)
	end
	for _, c in ipairs(fp) do
		if session.cells[c] ~= EMPTY then
			return false, size > 1 and string.format("%s cần %dx%d ô trống", B[kind].label, size, size) or "Ô này đã có công trình"
		end
	end
	local cost = CityEngine.priceOf(session, kind)
	if session.budget < cost then
		return false, "Không đủ tiền: cần " .. Util.formatMoneyFull(cost)
	end
	session.budget = session.budget - cost
	session.cells[index] = kind
	for k = 2, #fp do
		session.cells[fp[k]] = "+" .. index
	end
	return true, { cost = cost }
end

-- 1 lần kéo đường. Ô đã là đường thì bỏ qua, gặp công trình hoặc thiếu tiền thì từ chối cả đoạn
function CityEngine.buildRoad(session, path)
	if finished(session) then
		return false, FINISHED_TEXT
	end
	if type(path) ~= "table" then
		return false, "Đoạn đường không hợp lệ"
	end
	local n = #path
	if n == 0 or n > Config.MAX_ROAD_PATH then
		return false, string.format("Mỗi lần kéo tối đa %d ô", Config.MAX_ROAD_PATH)
	end
	local todo, seen = {}, {}
	for k = 1, n do
		local i = path[k]
		if not CityEngine.isValidIndex(i) then
			return false, "Ô không hợp lệ"
		end
		if not seen[i] and session.cells[i] ~= "road" then
			if session.cells[i] ~= EMPTY then
				return false, "Đoạn đường đi qua ô đã có công trình"
			end
			table.insert(todo, i)
		end
		seen[i] = true
	end
	local cost = #todo * CityEngine.priceOf(session, "road")
	if session.budget < cost then
		return false, string.format("Không đủ tiền: cần %s cho %d ô đường", Util.formatMoneyFull(cost), #todo)
	end
	session.budget = session.budget - cost
	for _, i in ipairs(todo) do
		session.cells[i] = "road"
	end
	return true, { cost = cost, built = #todo }
end

function CityEngine.demolish(session, index)
	if finished(session) then
		return false, FINISHED_TEXT
	end
	if not CityEngine.isValidIndex(index) then
		return false, "Ô trống"
	end
	-- bấm ô nào của công trình nhiều ô cũng phá cả công trình
	local anchor = CityEngine.anchorOf(session.cells, index)
	local def = CityEngine.isValidIndex(anchor) and B[session.cells[anchor]]
	if not def then
		return false, "Ô trống"
	end
	if anchor == Config.GATE_INDEX then
		return false, "Không phá được ô cổng"
	end
	local refund = math.floor(def.price * Config.DEMOLISH_REFUND)
	session.budget = session.budget + refund
	for _, c in ipairs(CityEngine.footprint(anchor, def.size) or { anchor }) do
		session.cells[c] = EMPTY
	end
	return true, { refund = refund, anchor = anchor }
end

function CityEngine.setTax(session, tax)
	if finished(session) then
		return false, FINISHED_TEXT
	end
	if type(tax) ~= "number" or tax ~= math.floor(tax) or tax < 0 or tax > Config.TAX_MAX then
		return false, string.format("Thuế từ 0 đến %d%%", Config.TAX_MAX)
	end
	session.tax = tax
	return true, { tax = tax }
end

return CityEngine
