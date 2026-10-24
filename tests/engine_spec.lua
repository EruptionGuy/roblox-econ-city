-- test engine (luật trong docs/luat-choi-moi.md). Chạy từ thư mục gốc: lua tests/engine_spec.lua
package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

local Config = H.require("src/shared/Config")
local GameTick = H.require("src/shared/GameTick")
local Scenarios = H.require("src/shared/Scenarios")
local CityEngine = H.require("src/shared/CityEngine")
local CityLayout = H.require("src/shared/CityLayout")
local Util = H.require("src/shared/Util")
local DemoBot = H.require("src/shared/DemoBot")

local N = Config.GRID_SIZE
local GATE = Config.GATE_INDEX
local gx, gy = CityLayout.cellXY(GATE)
local function at(x, y) -- 1-based
	return (y - 1) * N + x
end
local function new(budget)
	local s = GameTick.newSession(1, "s_test", 0)
	if budget then
		s.budget = budget
	end
	return s
end
local function run(s)
	s.status = GameTick.STATUS.ACTIVE
	return s
end

print("Bộ máy mô phỏng: thành phố trên lưới")

H.test("Ván mới: $10.000, thuế 20%, tạm dừng, ô cổng là đường, H = 35 + 27 + 20 = 82", function()
	local s = new()
	H.eq(s.budget, 10000)
	H.eq(s.tax, 20)
	H.eq(s.status, "PAUSED")
	H.eq(s.cells[GATE], "road")
	H.eq(#s.cells, N * N)
	H.near(s.happiness, 82)
	H.eq(gx, 6)
	H.eq(gy, 12)
	H.eq(GameTick.processTick(s), nil, "tạm dừng thì không tính lượt")
end)

H.test("Nối đường: nhà kề cổng thì nối; nhà xa không nối nhưng vẫn tốn bảo trì", function()
	local s = new()
	H.truthy(CityEngine.build(s, "house", at(gx - 1, gy)))
	H.truthy(CityEngine.build(s, "house", at(1, 1)))
	local d = CityEngine.compute(s, 0)
	H.eq(d.C, 40, "chỉ nhà đã nối mới có chỗ ở")
	H.eq(d.M, 20, "nhà chưa nối vẫn tốn bảo trì")
	H.truthy(CityEngine.buildRoad(s, { at(gx, gy - 1), at(gx, gy - 2) }))
	H.truthy(CityEngine.build(s, "office", at(gx + 1, gy - 2)))
	H.eq(CityEngine.compute(s, 0).J, 20, "văn phòng cạnh đường nối về cổng")
	-- đường lẻ không thông về cổng: công trình cạnh nó không chạy
	H.truthy(CityEngine.buildRoad(s, { at(2, 1) }))
	H.eq(CityEngine.compute(s, 0).C, 40, "đường lẻ không nối cổng")
end)

H.test("Kéo đường: bỏ qua ô đã là đường, từ chối cả đoạn khi gặp công trình hoặc thiếu tiền", function()
	local s = new()
	CityEngine.build(s, "house", at(gx - 1, gy))
	local before = s.budget
	H.eq((CityEngine.buildRoad(s, { at(gx - 2, gy), at(gx - 1, gy) })), false)
	H.eq(s.budget, before)
	H.eq(s.cells[at(gx - 2, gy)], Config.EMPTY)
	local ok, r = CityEngine.buildRoad(s, { GATE, at(gx, gy - 1), at(gx, gy - 1) })
	H.truthy(ok)
	H.eq(r.built, 1, "ô cổng và ô lặp không tính tiền")
	H.eq(s.budget, before - 50)
	local long = {}
	for i = 1, Config.MAX_ROAD_PATH + 1 do
		long[i] = i
	end
	H.eq((CityEngine.buildRoad(s, long)), false, "quá 24 ô")
	s.budget = 100
	H.eq((CityEngine.buildRoad(s, { at(1, 1), at(2, 1), at(3, 1) })), false, "thiếu tiền cho cả đoạn")
	H.eq(s.cells[at(1, 1)], Config.EMPTY)
end)

H.test("Dữ liệu xấu từ client bị từ chối", function()
	local s = new()
	for _, bad in ipairs({ 0, 145, 1.5, -3, 0 / 0, math.huge, "5", {} }) do
		H.eq((CityEngine.build(s, "house", bad)), false, "ô " .. tostring(bad))
	end
	H.eq((CityEngine.build(s, "castle", 1)), false)
	H.eq((CityEngine.build(s, nil, 1)), false)
	H.eq((CityEngine.buildRoad(s, "x")), false)
	H.eq((CityEngine.buildRoad(s, { 1, "2" })), false)
	H.eq((CityEngine.setTax(s, 51)), false)
	H.eq((CityEngine.setTax(s, 12.5)), false)
	H.eq((CityEngine.setTax(s, 0 / 0)), false)
	H.truthy(CityEngine.setTax(s, 30))
	H.eq(s.tax, 30)
	H.eq(s.budget, 10000, "không trừ tiền khi bị từ chối")
	H.eq((CityEngine.build(s, "house", GATE)), false, "ô cổng đã có đường")
end)

H.test("Phá dỡ hoàn 50% giá xây, không phá được ô cổng", function()
	local s = new()
	CityEngine.build(s, "house", at(1, 1))
	local ok, r = CityEngine.demolish(s, at(1, 1))
	H.truthy(ok)
	H.eq(r.refund, 300)
	H.eq(s.budget, 10000 - 600 + 300)
	H.eq((CityEngine.demolish(s, GATE)), false)
	H.eq((CityEngine.demolish(s, at(1, 1))), false, "ô trống")
end)

H.test("Hàng hoá: shop không có nhà máy thì không bán được gì", function()
	local s = new(1e6)
	CityEngine.buildRoad(s, { at(gx, gy - 1), at(gx, gy - 2) })
	CityEngine.build(s, "shop", at(gx - 1, gy - 1))
	local d = CityEngine.compute(s, 20)
	H.eq(d.G, 0)
	H.eq(d.R, 0)
	CityEngine.build(s, "factory", at(gx + 1, gy - 1)) -- 30 chỗ nhà máy >= 20 chỗ shop
	d = CityEngine.compute(s, 50)
	H.eq(d.G, 1)
	H.near(d.R, 20 * 105 + 30 * 55)
	d = CityEngine.compute(s, 25) -- thiếu người: mọi nơi thiếu như nhau
	H.near(d.f, 0.5)
	H.near(d.R, 0.5 * (20 * 105 + 30 * 55))
end)

H.test("Công thức H và ví dụ đường cong Laffer trong tài liệu", function()
	local s = new(1e6)
	CityEngine.buildRoad(s, { at(gx, gy - 1) })
	CityEngine.build(s, "house", at(gx - 1, gy))
	CityEngine.build(s, "office", at(gx + 1, gy))
	CityEngine.build(s, "office", at(gx - 1, gy - 1))
	CityEngine.build(s, "park", at(gx + 1, gy - 1)) -- 5 điểm, đủ cho 100 người
	CityEngine.setTax(s, 30)
	local d = CityEngine.compute(s, 40)
	H.near(d.E, 100)
	H.near(d.S, 100)
	H.near(d.H, 35 + 18 + 20, 1e-9, "E=100, S=100, thuế 30%")
	H.near(CityEngine.attraction(68), 0.864, 1e-9)
	H.near(CityEngine.attraction(59), 0.432, 1e-9)
	H.eq(CityEngine.attraction(50), 0)
	H.near(CityEngine.attraction(90), 1.2)
	H.truthy(CityEngine.build(s, "hospital", at(gx, gy - 2)))
	d = CityEngine.compute(s, 400) -- 400 dân, bệnh viện + công viên = 15 điểm, đủ cho 300 người nên S = 75
	H.near(d.S, 75)
end)

H.test("Dân đi dần tới mục tiêu min(chỗ ở, floor(việc làm × A)) rồi đứng yên", function()
	local s = new(1e6)
	CityEngine.buildRoad(s, { at(gx, gy - 1) })
	CityEngine.build(s, "house", at(gx - 1, gy))
	CityEngine.build(s, "office", at(gx + 1, gy))
	CityEngine.build(s, "park", at(gx - 1, gy - 1))
	run(s)
	local first = GameTick.processTick(s)
	H.eq(first.month, 1)
	H.eq(s.population, 12, "tháng 1: đi nửa quãng tới mục tiêu 24 (20 việc × 1,2)")
	for _ = 1, 9 do
		GameTick.processTick(s)
	end
	local d = CityEngine.compute(s, s.population)
	H.eq(s.population, CityEngine.targetPop(d.C, d.J, s.happiness))
	H.truthy(s.population > 0 and s.population <= 40)
	-- phá nhà: dân phải đi ngay
	CityEngine.demolish(s, at(gx - 1, gy))
	GameTick.processTick(s)
	H.eq(s.population, 0)
end)

H.test("Hết 24 tháng thì thắng; ngân sách < −$5.000 thì thua; điểm theo công thức", function()
	local s = run(new())
	for _ = 1, 24 do
		GameTick.processTick(s)
	end
	H.eq(s.status, "ENDED")
	H.eq(#s.history, 24)
	H.eq((CityEngine.build(s, "house", 1)), false, "không xây sau khi hết ván")
	H.eq((CityEngine.setTax(s, 10)), false)
	H.eq(s.prosperityScore, CityEngine.score(s.employed, s.happiness, s.budget))

	local f = new()
	for k = 1, 5 do
		H.truthy(CityEngine.build(f, "park", at(k, 1))) -- chưa nối: chỉ tốn $500/tháng
	end
	run(f)
	repeat
		GameTick.processTick(f)
	until GameTick.isFinished(f)
	H.eq(f.status, "FAILED")
	H.truthy(f.budget < Config.FAIL_BUDGET)
	H.eq(f.prosperityScore, 0, "điểm không âm")
end)

H.test("Cảnh báo: ngân sách âm, H < 50, thất nghiệp, shop thiếu hàng", function()
	local s = new(1e6)
	CityEngine.buildRoad(s, { at(gx, gy - 1) })
	CityEngine.build(s, "house", at(gx - 1, gy))
	CityEngine.build(s, "shop", at(gx + 1, gy))
	CityEngine.setTax(s, 50)
	s.budget = -10
	s.population = 40
	local d = CityEngine.compute(s, 40)
	local set = {}
	for _, c in ipairs(CityEngine.crises(s, d)) do
		set[c] = true
	end
	H.truthy(set.BUDGET and set.HAPPINESS and set.UNEMPLOYMENT and set.SHORTAGE)
end)

H.test("Sự kiện: bão giá làm giá xây ×1,5 rồi hết sau 5 tháng; không gán trùng", function()
	local s = new()
	H.truthy(GameTick.addScenario(s, "prices"))
	H.eq(CityEngine.priceOf(s, "house"), 900)
	H.eq((GameTick.addScenario(s, "prices")), false)
	H.eq((GameTick.addScenario(s, "food")), false, "sự kiện của luật cũ không còn")
	run(s)
	for _ = 1, 5 do
		GameTick.processTick(s)
	end
	H.eq(#s.scenarios, 0)
	H.eq(CityEngine.priceOf(s, "house"), 600)
end)

H.test("Sự kiện: suy thoái giảm doanh thu, đại dịch làm dân bỏ đi và giảm hạnh phúc", function()
	local s = new(1e6)
	CityEngine.buildRoad(s, { at(gx, gy - 1) })
	CityEngine.build(s, "house", at(gx - 1, gy))
	CityEngine.build(s, "office", at(gx + 1, gy))
	s.population = 20
	local base = CityEngine.compute(s, 20)
	GameTick.addScenario(s, "recession")
	GameTick.addScenario(s, "pandemic")
	local eff = Scenarios.aggregate(s.scenarios)
	local d = CityEngine.compute(s, 20, eff)
	H.near(d.R, base.R * 0.7)
	H.near(d.H, base.H - 10)
	H.eq(CityEngine.migrate(100, 200, 200, 90, eff.leaveRate), 100 + 50 - 3, "đi nửa quãng rồi 2% bỏ đi")
end)

H.test("Kịch bản tuỳ chỉnh: kẹp giới hạn, bỏ hiệu ứng lạ, cần ít nhất một hiệu ứng", function()
	local clean = Scenarios.sanitizeCustom({ severity = 30, durationMonths = 0, effects = { revenueMultiplier = 0.1, happinessPenalty = -12.4, hack = 5 } })
	H.eq(clean.effects.revenueMultiplier, 0.5)
	H.eq(clean.effects.happinessPenalty, -12)
	H.eq(clean.effects.hack, nil)
	H.eq(clean.severity, 10)
	H.eq(clean.durationMonths, 1)
	H.eq((Scenarios.sanitizeCustom({ effects = {} })), nil)
	local s = new()
	H.truthy(GameTick.addScenario(s, "c_9_1", nil, { name = "Bão", durationMonths = 2, effects = clean.effects }))
	H.near(Scenarios.aggregate(s.scenarios).revenueMultiplier, 0.5)
end)

H.test("Phiên chỉ chứa dữ liệu lưu được vào DataStore (không NaN/inf, không hàm, không lỗ nil)", function()
	local s = new(1e6)
	CityEngine.buildRoad(s, { at(gx, gy - 1) })
	CityEngine.build(s, "house", at(gx - 1, gy))
	CityEngine.build(s, "shop", at(gx + 1, gy))
	GameTick.addScenario(s, "pandemic", { assignedBy = 1 })
	run(s)
	for _ = 1, 3 do
		GameTick.processTick(s)
	end
	local function check(v, path)
		local t = type(v)
		if t == "table" then
			local n = #v
			for k, child in pairs(v) do
				if type(k) == "number" then
					H.truthy(k >= 1 and k <= n and k == math.floor(k), "mảng có lỗ tại " .. path)
				end
				check(child, path .. "." .. tostring(k))
			end
		elseif t == "number" then
			H.truthy(Util.isFiniteNumber(v), "số không hữu hạn tại " .. path)
		else
			H.truthy(t == "string" or t == "boolean", "kiểu " .. t .. " tại " .. path)
		end
	end
	check(s, "session")
end)

H.test("CityLayout: tâm ô và tìm ô theo toạ độ khớp nhau", function()
	for _, i in ipairs({ 1, 12, GATE, 144, 73 }) do
		local x, z = CityLayout.cellCenter(i)
		H.eq(CityLayout.cellAt(x, z), i)
		H.eq(CityLayout.cellAt(x + 6.9, z - 6.9), i)
	end
	H.eq(CityLayout.cellAt(1000, 0), nil)
	local _, zGate = CityLayout.cellCenter(GATE)
	H.truthy(zGate > 0 and CityLayout.SPAWN.z > zGate, "cổng ở phía +Z, điểm spawn ngay trước cổng")
end)

H.test("Bot xây mẫu: mọi công trình đều nối đường, giữ tiền dự trữ, không ăn gian", function()
	local s = new()
	local built = DemoBot.act(s)
	H.truthy(built >= 3, "xây được vài công trình với $10.000: " .. built)
	local d = CityEngine.compute(s, 0)
	for i, kind in ipairs(s.cells) do
		if kind ~= Config.EMPTY then
			H.truthy(d.conn[i], "ô " .. i .. " (" .. kind .. ") chưa nối đường")
		end
	end
	H.truthy(d.C > 0 and d.J > 0 and d.pts > 0, "có nhà, chỗ làm và dịch vụ")
	H.truthy(s.budget >= 2 * d.M, "giữ lại 2 tháng tiền bảo trì")
	H.eq(DemoBot.act(s), 0, "hết tiền thì không xây thêm")
	run(s)
	for _ = 1, 3 do
		GameTick.processTick(s)
	end
	H.truthy(s.population > 0, "thành phố mẫu có dân")
end)

H.test("Bot xây mẫu: né công trình người chơi đặt chắn đường, dừng khi ván đã kết thúc", function()
	local s = new()
	-- chắn cả hàng đường gần cổng (hàng 11) bên trái và bên phải trục
	CityEngine.build(s, "park", at(gx - 1, gy - 1))
	CityEngine.build(s, "park", at(gx + 1, gy - 1))
	local built = DemoBot.act(s)
	H.truthy(built > 0, "vẫn xây được ở hàng đường khác")
	H.eq(s.cells[at(gx - 1, gy - 1)], "park", "không phá công trình của người chơi")
	local f = new()
	f.status = "ENDED"
	H.eq(DemoBot.act(f), 0)
end)

H.test("Mẫu công trình: mẫu chuẩn giữ nguyên số liệu đã cân bằng, mọi mẫu thuộc một loại đất", function()
	local B = Config.BUILDINGS
	H.eq(B.house.price, 600)
	H.eq(B.house.cap, 40)
	H.eq(B.shop.rev, 105)
	H.eq(B.office.price, 3000)
	H.eq(B.park.pts, 5)
	for id, def in pairs(B) do
		H.truthy(Config.CATEGORIES[def.kind], id .. ": loại đất")
		H.truthy(def.size == 1 or def.size == 2, id .. ": kích thước")
		H.eq(def.code, Config.CATEGORIES[def.kind].code, id .. ": mã chữ")
	end
	for kind, list in pairs(Config.VARIANTS) do
		H.eq(list[1], kind, "mẫu chuẩn đứng đầu " .. kind)
		for _, id in ipairs(list) do
			H.eq(B[id].kind, kind)
		end
	end
end)

H.test("Mẫu lớn 2×2: lãi mỗi ô hơn mẫu chuẩn 10-30%, không áp đảo", function()
	-- lãi tháng mỗi ô khi đủ người, thuế 30%, đủ hàng
	local function perTile(def)
		local net = (def.jobs or 0) * (def.rev or 0) * 0.30 - def.maint
		return net / (def.size * def.size)
	end
	for _, id in ipairs({ "supermarket", "plant", "tower" }) do
		local def = Config.BUILDINGS[id]
		local ratio = perTile(def) / perTile(Config.BUILDINGS[def.kind])
		H.truthy(ratio >= 1.1 and ratio <= 1.3, id .. ": lãi/ô gấp " .. ratio)
	end
	local apt, house = Config.BUILDINGS.apartment, Config.BUILDINGS.house
	local capRatio = (apt.cap / 4) / house.cap
	H.truthy(capRatio > 1 and capRatio <= 1.3, "chung cư: chỗ ở/ô gấp " .. capRatio)
	for _, id in ipairs({ "school_big", "park_big" }) do
		local def = Config.BUILDINGS[id]
		local base = Config.BUILDINGS[def.kind]
		local ratio = (def.pts / def.maint) / (base.pts / base.maint)
		H.truthy(ratio >= 1 and ratio <= 1.3, id .. ": dịch vụ/bảo trì gấp " .. ratio)
	end
end)

H.test("Công trình 2×2: chiếm 4 ô, nối đường qua bất kỳ ô nào, phá ở ô nào cũng phá cả công trình", function()
	local s = new(1e6)
	local a = at(2, 9)
	H.truthy(CityEngine.build(s, "supermarket", a))
	H.eq(s.cells[a], "supermarket")
	H.eq(s.cells[at(3, 9)], "+" .. a)
	H.eq(s.cells[at(2, 10)], "+" .. a)
	H.eq(s.cells[at(3, 10)], "+" .. a)
	H.eq(CityEngine.anchorOf(s.cells, at(3, 10)), a)
	H.eq(s.budget, 1e6 - 7000)
	-- chồng lên, tràn lưới, xây đè ô phụ: bị từ chối
	H.eq((CityEngine.build(s, "tower", at(3, 10))), false)
	H.eq((CityEngine.build(s, "house", at(3, 9))), false)
	H.eq((CityEngine.build(s, "apartment", at(12, 5))), false, "tràn mép phải")
	H.eq((CityEngine.build(s, "apartment", at(5, 12))), false, "tràn mép dưới")
	H.eq((CityEngine.buildRoad(s, { at(3, 10) })), false, "đường không đi qua công trình")
	-- chưa nối; kéo đường chạm vào ô dưới-phải là đủ
	local d = CityEngine.compute(s, 0)
	H.eq(d.conn[a], false)
	H.truthy(CityEngine.buildRoad(s, { at(4, 10), at(4, 11), at(4, 12), at(5, 12) }))
	d = CityEngine.compute(s, 0)
	H.eq(d.conn[a], true)
	H.eq(d.conn[at(3, 10)], true)
	H.eq(d.J, 90, "đếm chỗ làm một lần")
	H.eq(d.counts.shop, 1)
	H.eq(d.slots.shop, 90)
	-- doanh thu tính theo lương của chính mẫu: 90 người x $110, cần đủ hàng
	CityEngine.build(s, "plant", at(6, 9))
	CityEngine.buildRoad(s, { at(6, 11) })
	d = CityEngine.compute(s, 1000)
	H.near(d.G, 1)
	H.near(d.R, 90 * 110 + 130 * 58)
	local before = s.budget
	local ok, r = CityEngine.demolish(s, at(3, 10))
	H.truthy(ok)
	H.eq(r.anchor, a)
	H.eq(r.refund, 3500)
	H.eq(s.budget, before + 3500)
	for _, c in ipairs({ a, at(3, 9), at(2, 10), at(3, 10) }) do
		H.eq(s.cells[c], Config.EMPTY)
	end
end)

H.test("Sửa lưới hỏng/cũ khi nạp: bỏ mã lạ, gắn lại ô phụ, bỏ công trình không đủ chỗ", function()
	local cells = CityEngine.newCells()
	cells[1] = "apartment" -- thiếu ô phụ: gắn lại
	cells[20] = "+999" -- ô phụ mồ côi
	cells[30] = "castle"
	cells[40] = "tower"
	cells[41] = "house" -- chắn ô phụ của tháp nên tháp bị bỏ
	cells[N] = "plant" -- góc ở mép phải, tràn lưới, bỏ
	CityEngine.sanitizeCells(cells)
	H.eq(cells[2], "+1")
	H.eq(cells[13], "+1")
	H.eq(cells[14], "+1")
	H.eq(cells[20], Config.EMPTY)
	H.eq(cells[30], Config.EMPTY)
	H.eq(cells[40], Config.EMPTY)
	H.eq(cells[41], "house")
	H.eq(cells[N], Config.EMPTY)
	H.eq(cells[Config.GATE_INDEX], "road")
end)

H.test("Util.formatMoney", function()
	H.eq(Util.formatMoney(10000), "$10.0k")
	H.eq(Util.formatMoney(3725), "$3,725")
	H.eq(Util.formatMoney(-6837.5), "-$6,838")
	H.eq(Util.formatMoney(173694.02), "$174k")
end)

H.test("Bot nút Xây mẫu: đầu ván chỉ xây mẫu chuẩn, có tiền dư thì xây 2×2 đúng luật, mọi công trình nối đường", function()
	local s = new()
	CityEngine.setTax(s, 30)
	DemoBot.act(s, DemoBot.SHOWCASE)
	for _, c in ipairs(s.cells) do
		H.truthy(c == Config.EMPTY or c == "road" or Config.BUILDINGS[c].size == 1, "tháng 0 chưa có dân: không xây mẫu lớn")
	end
	s.status = GameTick.STATUS.ACTIVE
	while not GameTick.isFinished(s) do
		DemoBot.act(s, DemoBot.SHOWCASE)
		GameTick.processTick(s)
	end
	H.eq(s.status, "ENDED")
	local d, big = CityEngine.compute(s, s.population), 0
	for i, c in ipairs(s.cells) do
		local def = Config.BUILDINGS[c]
		if def and def.size == 2 then
			big = big + 1
			local fp = CityEngine.footprint(i, 2)
			for k = 2, 4 do
				H.eq(s.cells[fp[k]], "+" .. i)
			end
		end
		if def and c ~= "road" then
			H.truthy(d.conn[i], "công trình ở ô " .. i .. " nối đường")
		end
	end
	H.truthy(big >= 1, "có ít nhất một công trình 2×2 (" .. big .. ")")
end)

os.exit(H.summary() and 0 or 1)
