-- Mô phỏng cân bằng: DemoBot (cũng là bot nút Xây mẫu) chơi bằng chính code Luau của game,
-- 12 chiến thuật x 11 mức thuế, dịch 1:1 từ prototypes/luat-moi/sim.js.
-- điểm cuối ván phải khớp từng số với bảng của bản JS, lệch là Luau tính khác bản thử (docs/luat-choi-moi.md mục 10)
-- chạy: lua tests/balance_sim.lua
-- đổi số trong Config thì bảng JS dưới đây hết đúng: chạy với --no-compare để in bảng mới, rồi chạy lại sim.js cập nhật
package.path = "./tests/?.lua;" .. package.path
local H = require("harness")
local Config = H.require("src/shared/Config")
local GameTick = H.require("src/shared/GameTick")
local CityEngine = H.require("src/shared/CityEngine")

local DemoBot = H.require("src/shared/DemoBot")
local N = Config.GRID_SIZE
local COMPARE = not (arg and arg[1] == "--no-compare")

local function run(st, tax)
	local s = GameTick.newSession(1, "sim", 0)
	CityEngine.setTax(s, tax)
	s.status = GameTick.STATUS.ACTIVE
	while not GameTick.isFinished(s) do
		DemoBot.act(s, st)
		GameTick.processTick(s)
	end
	return s
end

local function strat(over)
	local s = {}
	for k, v in pairs(DemoBot.BALANCED) do
		s[k] = v
	end
	for k, v in pairs(over or {}) do
		s[k] = v
	end
	return s
end
local STRATS = {
	{ "cân bằng", strat(), "F17 68 157 371 905 1789 2155 2078 1582 412 76" },
	{ "chỉ văn phòng", strat({ mix = { { "office", 1 } } }), "F19 42 116 303 738 1558 2373 2236 1131 347 67" },
	{ "shop + nhà máy", strat({ mix = { { "shop", 0.5 }, { "factory", 0.5 } } }), "F21 57 171 396 943 1811 2043 1963 1535 410 76" },
	{ "chỉ shop (không nhà máy)", strat({ mix = { { "shop", 1 } } }), "F24 F24 F24 F24 F24 F24 F24 F24 F24 F24 F24" },
	{ "chỉ nhà máy", strat({ mix = { { "factory", 1 } } }), "F15 92 162 335 739 1244 1412 1330 983 333 70" },
	{ "không dịch vụ công", strat({ S = 0 }), "F17 96 204 247 182 99 25 20 9 0 0" },
	{ "dịch vụ cao (S ≥ 90)", strat({ S = 90 }), "F17 68 153 336 798 1659 2576 2277 1254 360 66" },
	{ "chỉ công viên", strat({ service = { "park" } }), "F17 68 157 363 891 1658 1983 1923 1567 411 82" },
	{ "chỉ bệnh viện", strat({ service = { "hospital" } }), "24 65 116 307 793 1599 2066 1961 1334 351 93" },
	{ "thừa nhà (×2)", strat({ houseRatio = 2 }), "16 58 135 277 614 1245 1517 1423 981 279 55" },
	{ "thiếu nhà (×0,7)", strat({ houseRatio = 0.7 }), "F17 68 151 245 397 676 1128 1679 1476 571 96" },
	{ "liều (không dự trữ)", strat({ reserveMonths = 0 }), "F15 59 162 413 1079 2055 2372 2408 1909 440 67" },
	-- 2 dòng này chỉ Luau có (JS không có mẫu công trình): không so với JS, check riêng ở cuối file
	{ "nút Xây mẫu (2×2, chỉ Luau)", DemoBot.SHOWCASE, nil },
	{ "mẫu nhỏ 1×1 (chỉ Luau)", strat({ variants = { house = "house_small", shop = "cafe", factory = "workshop", office = "office_small", hospital = "clinic" } }), nil },
}

local TAXES = { 0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50 }
local header = string.rep(" ", 28)
for _, t in ipairs(TAXES) do
	header = header .. string.format("%6s", t .. "%")
end
print(string.format("Bố cục bot: %d ô công trình, %d ô đường (kể cả cổng)", #DemoBot.SLOTS, N * N - #DemoBot.SLOTS))
print("Điểm cuối ván theo thuế (F<tháng> = phá sản):")
print(header)
local mismatches = 0
local bestTax, bestScore = {}, {}
for _, row in ipairs(STRATS) do
	local cells, line = {}, ""
	local best, bestAt = -1, nil
	for _, tax in ipairs(TAXES) do
		local s = run(row[2], tax)
		local cell = s.status == "FAILED" and ("F" .. s.month) or tostring(s.prosperityScore)
		table.insert(cells, cell)
		line = line .. string.format("%6s", cell)
		if s.status ~= "FAILED" and s.prosperityScore > best then
			best, bestAt = s.prosperityScore, tax
		end
	end
	bestTax[row[1]] = bestAt
	bestScore[row[1]] = best
	local name = row[1] .. string.rep(" ", math.max(0, 28 - utf8.len(row[1])))
	local got = table.concat(cells, " ")
	local mark = ""
	if COMPARE and row[3] and got ~= row[3] then
		mismatches = mismatches + 1
		mark = "   ✗ bản JS: " .. row[3]
	end
	print(name .. line .. mark)
end

if COMPARE then
	if mismatches > 0 then
		print(string.format("\n✗ %d chiến thuật khác bản JS (prototypes/luat-moi/sim.js)", mismatches))
		os.exit(1)
	end
	print("\n✓ Khớp từng con số với bản JS (prototypes/luat-moi/sim.js)")
end
local t = bestTax["cân bằng"]
local ok = t and t >= 25 and t <= 35
print(string.format("%s Thuế tối ưu của chiến thuật cân bằng: %s%%", ok and "✓" or "✗", tostring(t)))
local small, base = bestScore["mẫu nhỏ 1×1 (chỉ Luau)"], bestScore["cân bằng"]
local okSmall = small < base
print(string.format("%s Mẫu nhỏ không áp đảo: %d điểm so với %d của mẫu chuẩn", okSmall and "✓" or "✗", small, base))
-- 2x2 lãi/ô hơn 10-30%: bot Xây mẫu phải chơi được (không phá sản ở thuế tối ưu) nhưng không bỏ xa mẫu chuẩn
local show = bestScore["nút Xây mẫu (2×2, chỉ Luau)"]
local okShow = show > base * 0.8 and show < base * 1.6
print(string.format("%s Bot nút Xây mẫu (có 2×2) chơi được, không áp đảo: %d điểm so với %d", okShow and "✓" or "✗", show, base))
os.exit((ok and okSmall and okShow) and 0 or 1)
