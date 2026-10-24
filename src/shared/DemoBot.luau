-- Bot xây thành phố, đi qua CityEngine như người chơi nên không ăn gian được.
-- Dùng cho nút "Bot xây mẫu" (Studio) và balance_sim. Dịch 1:1 từ prototypes/luat-moi/sim.js,
-- balance_sim so từng số với bản JS nên sửa cách bot chơi ở đây thì sửa luôn sim.js.
--
-- bố cục: trục đường dọc ở cột cổng + 4 hàng đường ngang, công trình sát đường (89 ô công trình, 55 ô đường)
-- SHOWCASE (nút Xây mẫu) = BALANCED + đủ tiền thì xây mẫu 2x2 trong dải 2 hàng giữa 2 hàng đường.
-- chiến thuật của balance_sim không bật big nên vẫn khớp bản JS

local Config = require(script.Parent.Config)
local CityEngine = require(script.Parent.CityEngine)

local B = Config.BUILDINGS
local N = Config.GRID_SIZE
local GX = (Config.GATE_INDEX - 1) % N -- cột cổng, đếm từ 0
local JOBS = { "shop", "factory", "office", "hospital", "school" }

local DemoBot = {}

-- mix: tỉ lệ chỗ làm theo loại, S: dịch vụ tối thiểu, houseRatio: chỗ ở / việc làm,
-- reserveMonths: số tháng tiền bảo trì phải chừa lại
DemoBot.BALANCED = {
	mix = { { "shop", 0.4 }, { "factory", 0.4 }, { "office", 0.2 } },
	S = 60,
	service = { "park", "hospital", "school" },
	houseRatio = 1.2,
	reserveMonths = 2,
}

local function with(over)
	local s = {}
	for k, v in pairs(DemoBot.BALANCED) do
		s[k] = v
	end
	for k, v in pairs(over) do
		s[k] = v
	end
	return s
end
DemoBot.SHOWCASE = with({ big = true })

-- mẫu 2x2 của từng loại đất, nếu có
local BIG = {}
for cat, ids in pairs(Config.VARIANTS) do
	for _, id in ipairs(ids) do
		if B[id].size == 2 then
			BIG[cat] = id
		end
	end
end

local ROAD_ROWS = { N - 2, N - 5, N - 8, N - 11 } -- hàng đường ngang, đếm từ 0
local function roadRowOf(y)
	for _, r in ipairs(ROAD_ROWS) do
		if math.abs(r - y) == 1 then
			return r
		end
	end
end
local function isRoadRow(y)
	for _, r in ipairs(ROAD_ROWS) do
		if r == y then
			return true
		end
	end
	return false
end

local SLOTS = {}
for y = 0, N - 1 do
	for x = 0, N - 1 do
		if not isRoadRow(y) and not (x == GX and y >= 1) then
			table.insert(SLOTS, { x = x, y = y, i = y * N + x + 1 })
		end
	end
end
-- giả sort ổn định của JS: hàng đường gần cổng trước, rồi gần trục, rồi theo thứ tự sinh ra
table.sort(SLOTS, function(a, b)
	local ra, rb = roadRowOf(a.y), roadRowOf(b.y)
	if ra ~= rb then
		return ra > rb
	end
	local da, db = math.abs(a.x - GX), math.abs(b.x - GX)
	if da ~= db then
		return da < db
	end
	return a.i < b.i
end)
DemoBot.SLOTS = SLOTS

-- ô đường còn thiếu để nối slot về cổng: trục dọc tới hàng đường của slot, rồi đi ngang tới cột
local function roadsFor(session, slot)
	local r, out = roadRowOf(slot.y), {}
	for y = r, N - 1 do
		table.insert(out, y * N + GX + 1)
	end
	for x = math.min(GX, slot.x), math.max(GX, slot.x) do
		table.insert(out, r * N + x + 1)
	end
	local todo = {}
	for _, i in ipairs(out) do
		if session.cells[i] ~= "road" then
			table.insert(todo, i)
		end
	end
	return todo
end

-- ô góc vùng 2x2 trống chứa slot, gọn giữa 2 hàng đường, không đè trục dọc. Không có thì nil
local function bigAnchor(session, slot)
	for _, dy in ipairs({ 0, 1 }) do
		for _, dx in ipairs({ 0, 1 }) do
			local x, y = slot.x - dx, slot.y - dy
			local fp = x >= 0 and y >= 0 and CityEngine.footprint(y * N + x + 1, 2)
			if fp and not isRoadRow(y) and not isRoadRow(y + 1) and not (x <= GX and GX <= x + 1) then
				local free = true
				for _, c in ipairs(fp) do
					free = free and session.cells[c] == Config.EMPTY
				end
				if free then
					return fp[1]
				end
			end
		end
	end
	return nil
end

-- đếm theo loại đất (gộp mọi mẫu): số công trình, chỗ ở, chỗ làm.
-- lưới chỉ có mẫu chuẩn thì ra y như bản JS (count x số mẫu chuẩn)
local function tally(session)
	local n, cap, jobs = {}, 0, {}
	for _, c in ipairs(session.cells) do
		local def = B[c]
		if def then
			n[def.kind] = (n[def.kind] or 0) + 1
			cap = cap + (def.cap or 0)
			jobs[def.kind] = (jobs[def.kind] or 0) + (def.jobs or 0)
		end
	end
	return n, cap, jobs
end

local function choose(session, st)
	local n, C, jobs = tally(session)
	local function count(kind)
		return n[kind] or 0
	end
	local J = 0
	for _, t in ipairs(JOBS) do
		J = J + (jobs[t] or 0)
	end
	local d = CityEngine.compute(session, math.max(1, math.min(C, J)))
	if C < J * st.houseRatio or (C == 0 and J == 0) then
		return "house", d
	elseif d.S < st.S then
		local built = count("hospital") + count("school") + count("park")
		return st.service[built % #st.service + 1], d
	end
	local total = 1
	for _, m in ipairs(st.mix) do
		total = total + (jobs[m[1]] or 0)
	end
	local best
	for _, m in ipairs(st.mix) do
		local gap = (jobs[m[1]] or 0) / total - m[2]
		if not best or gap < best.gap then
			best = { kind = m[1], gap = gap }
		end
	end
	return best.kind, d
end

-- xây bằng tiền đang có, chừa reserveMonths tháng bảo trì. Trả về số công trình đã xây (không tính đường)
-- slot bị công trình của người chơi chắn đường thì bỏ qua
function DemoBot.act(session, st)
	st = st or DemoBot.BALANCED
	local built, blocked = 0, {}
	while true do
		local slot
		for _, p in ipairs(SLOTS) do
			if not blocked[p.i] and session.cells[p.i] == Config.EMPTY then
				slot = p
				break
			end
		end
		if not slot then
			return built
		end
		local pick, d = choose(session, st)
		local roads = roadsFor(session, slot)
		local roadCost = #roads * CityEngine.priceOf(session, "road")
		local at = slot.i
		-- st.big: chỉ xây 2x2 phủ lên slot khi đã có dân, có chỗ, và mua xong vẫn còn >= giá mẫu lớn + dự trữ.
		-- mua sớm hơn là chôn tiền vào chỗ thừa (200 chỗ ở khi mới cần 40) hoặc hết tiền trước khi có chỗ làm.
		-- balance_sim check bot này vẫn chơi ngang mẫu chuẩn
		local anchor = st.big and BIG[pick] and (session.population or 0) > 0 and bigAnchor(session, slot)
		if anchor and session.budget - 2 * CityEngine.priceOf(session, BIG[pick]) - roadCost >= st.reserveMonths * d.M then
			pick, at = BIG[pick], anchor
		else
			-- st.variants (tuỳ chọn): thay mẫu chuẩn bằng mẫu 1x1 khác, vd { house = "house_small" }
			pick = (st.variants and st.variants[pick]) or pick
		end
		local clear = true
		for _, i in ipairs(roads) do
			if session.cells[i] ~= Config.EMPTY then
				clear = false
			end
		end
		if not clear then
			blocked[slot.i] = true
		else
			local cost = CityEngine.priceOf(session, pick) + roadCost
			if session.budget < cost or session.budget - cost < st.reserveMonths * d.M then
				return built
			end
			local ok = #roads == 0 or CityEngine.buildRoad(session, roads)
			if not (ok and CityEngine.build(session, pick, at)) then
				return built -- ván xong hoặc data lạ: dừng luôn, kẻo lặp mãi
			end
			built = built + 1
		end
	end
end

return DemoBot
