-- Hằng số của game. Luật: docs/luat-choi-moi.md.
-- Số cân bằng đã chạy thử bằng prototypes/luat-moi/sim.js và tests/balance_sim.lua, 2 bên phải ra cùng điểm.
-- sửa số xong thì chạy `lua tests/balance_sim.lua` xem điểm theo từng mức thuế

local Config = {}

Config.VERSION = "0.2.2"

-- Nhịp
-- 1 lượt = 1 tháng, đổi số giây không làm lệch cân bằng
Config.TICK_SECONDS = 20
Config.GAME_DURATION_MONTHS = 24

-- Ngân sách, thắng/thua (mục 6)
Config.START_BUDGET = 10000
Config.FAIL_BUDGET = -5000 -- dưới mức này là thua
Config.BUDGET_CLAMP = { -10000000, 1000000000 }

-- Lưới, đường (mục 2)
Config.GRID_SIZE = 12
-- ô cổng: cột 6, hàng 12 (hàng gần camera). Ô đánh số 1..144 theo hàng: (hàng-1)*12 + cột
Config.GATE_INDEX = (12 - 1) * 12 + 6
Config.EMPTY = "" -- ô trống. Không dùng nil vì DataStore không lưu được mảng có lỗ

-- Thuế, thao tác (mục 5)
Config.START_TAX = 20
Config.TAX_MAX = 50
Config.DEMOLISH_REFUND = 0.5
Config.MAX_ROAD_PATH = 24 -- số ô tối đa mỗi lần kéo đường

-- Công trình (mục 3)
-- 8 loại đất. code + color (RGB) dùng chung cho ô chú giải, nền lô và màu nhà trên sa bàn.
-- inkLight: chữ trắng trên ô màu. Thứ tự = thứ tự trên bảng Chú giải
Config.CATEGORY_ORDER = { "house", "shop", "factory", "office", "hospital", "school", "park", "road" }
Config.BUILDING_ORDER = Config.CATEGORY_ORDER -- tên cũ
Config.CATEGORIES = {
	house = { code = "Ở", zone = "Đất ở", color = { 242, 194, 48 } },
	shop = { code = "TM", zone = "Thương mại", color = { 208, 52, 52 }, inkLight = true },
	factory = { code = "CN", zone = "Công nghiệp", color = { 126, 79, 181 }, inkLight = true },
	office = { code = "VP", zone = "Văn phòng", color = { 47, 111, 208 }, inkLight = true },
	hospital = { code = "YT", zone = "Y tế", color = { 192, 58, 124 }, inkLight = true },
	school = { code = "GD", zone = "Giáo dục", color = { 240, 138, 36 } },
	park = { code = "CX", zone = "Cây xanh", color = { 60, 157, 74 } },
	road = { code = "GT", zone = "Giao thông", color = { 107, 112, 120 }, inkLight = true },
}

-- mẫu chuẩn: id trùng tên loại, số đã cân bằng (bot, balance_sim và bản JS dùng mẫu này).
-- mẫu nhỏ 1x1 rẻ, lãi/ô thấp hơn. mẫu lớn 2x2 đắt, lãi/ô cao hơn ~15-25%, đáng xây khi lưới đã chật.
-- size = cạnh (ô), công trình 2x2 lấy ô bấm làm góc trên-trái
Config.BUILDINGS = {
	house = { kind = "house", label = "Nhà", price = 600, maint = 10, cap = 40 },
	house_small = { kind = "house", label = "Nhà nhỏ", price = 350, maint = 6, cap = 20 },
	apartment = { kind = "house", label = "Chung cư", size = 2, price = 3000, maint = 60, cap = 200 },

	shop = { kind = "shop", label = "Shop", price = 1600, maint = 60, jobs = 20, rev = 105 },
	cafe = { kind = "shop", label = "Quán cà phê", price = 900, maint = 35, jobs = 10, rev = 100 },
	supermarket = { kind = "shop", label = "Siêu thị", size = 2, price = 7000, maint = 260, jobs = 90, rev = 110 },

	factory = { kind = "factory", label = "Nhà máy", price = 1200, maint = 80, jobs = 30, rev = 55 },
	workshop = { kind = "factory", label = "Xưởng nhỏ", price = 700, maint = 45, jobs = 15, rev = 55 },
	plant = { kind = "factory", label = "Nhà máy lớn", size = 2, price = 5000, maint = 320, jobs = 130, rev = 58 },

	office = { kind = "office", label = "Văn phòng", price = 3000, maint = 100, jobs = 20, rev = 160 },
	office_small = { kind = "office", label = "Văn phòng nhỏ", price = 1500, maint = 55, jobs = 10, rev = 155 },
	tower = { kind = "office", label = "Tháp văn phòng", size = 2, price = 14000, maint = 420, jobs = 90, rev = 170 },

	hospital = { kind = "hospital", label = "Bệnh viện", price = 2400, maint = 120, jobs = 20, pts = 10 },
	clinic = { kind = "hospital", label = "Trạm y tế", price = 1200, maint = 60, jobs = 8, pts = 5 },

	school = { kind = "school", label = "Trường học", price = 2000, maint = 100, jobs = 20, pts = 10 },
	school_big = { kind = "school", label = "Trường lớn", size = 2, price = 7000, maint = 350, jobs = 80, pts = 40 },

	park = { kind = "park", label = "Công viên", price = 1800, maint = 100, pts = 5 },
	park_big = { kind = "park", label = "Công viên lớn", size = 2, price = 6000, maint = 360, pts = 22 },

	road = { kind = "road", label = "Đường", price = 50, maint = 0 },
}
-- thứ tự hiện trên Chú giải, mẫu chuẩn đứng đầu
Config.VARIANTS = {
	house = { "house", "house_small", "apartment" },
	shop = { "shop", "cafe", "supermarket" },
	factory = { "factory", "workshop", "plant" },
	office = { "office", "office_small", "tower" },
	hospital = { "hospital", "clinic" },
	school = { "school", "school_big" },
	park = { "park", "park_big" },
	road = { "road" },
}
-- chép code/zone/color của loại đất vào từng mẫu, UI và sa bàn đọc thẳng từ mẫu
for id, def in pairs(Config.BUILDINGS) do
	local cat = Config.CATEGORIES[def.kind]
	def.id = id
	def.size = def.size or 1
	def.code, def.zone, def.color, def.inkLight = cat.code, cat.zone, cat.color, cat.inkLight
end

-- 1 dòng ghi chú trên thẻ thông tin
Config.BUILDING_NOTES = {
	house = "Dân chỉ đến khi có việc làm.",
	house_small = "Rẻ nhất để có dân, nhưng ít chỗ ở trên mỗi ô.",
	apartment = "Nhiều chỗ ở nhất trên mỗi ô, khi lưới đã chật.",
	shop = "Cần hàng từ nhà máy.",
	cafe = "Rẻ, ít người làm. Vẫn cần hàng từ nhà máy.",
	supermarket = "Lãi mỗi ô cao nhất trong thương mại. Cần nhiều hàng.",
	factory = "Cấp hàng cho shop: 1 công nhân đủ hàng cho 1 nhân viên shop.",
	workshop = "Rẻ, ít người làm. Cấp hàng cho shop.",
	plant = "Nhiều chỗ làm, cấp nhiều hàng cho shop.",
	office = "Lương cao, không cần hàng.",
	office_small = "Rẻ hơn, ít chỗ làm. Không cần hàng.",
	tower = "Lãi mỗi ô cao nhất, rất đắt.",
	hospital = "Dân vui hơn.",
	clinic = "Rẻ, phục vụ ít dân hơn.",
	school = "Dân vui hơn.",
	school_big = "Phục vụ nhiều dân, rẻ hơn 4 trường nhỏ.",
	park = "Không cần người làm.",
	park_big = "Phục vụ nhiều dân hơn 4 công viên nhỏ.",
	road = "Mọi công trình phải nối đường về CỔNG.",
}

-- Công thức (mục 4)
Config.FORMULA = {
	-- H = wE*E + wT*(100 - 2T) + wS*S
	happinessEmploymentWeight = 0.35,
	happinessTaxWeight = 0.45,
	happinessServiceWeight = 0.20,
	-- độ hấp dẫn A = aMax * clamp((H - hLo) / (hHi - hLo), 0, 1), dân mục tiêu = min(chỗ ở, floor(việc làm * A))
	attractionLow = 50,
	attractionHigh = 75,
	attractionMax = 1.2,
	moveRate = 0.5, -- mỗi tháng đi nửa quãng tới mục tiêu
	residentsPerPoint = 20, -- 1 điểm dịch vụ phục vụ 20 dân
}

-- Cảnh báo (mục 7), chỉ báo, không làm thua
Config.CRISIS = {
	budgetBelow = 0,
	happinessBelow = 50,
	employmentBelow = 80,
	goodsBelow = 0.7,
}

-- dạng "tiêu đề: giải thích". UI in đậm phần trước dấu hai chấm, phần sau thành dòng phụ
Config.CRISIS_LABELS = {
	BUDGET = "Ngân sách âm: đang lỗ, chưa xây được gì",
	HAPPINESS = "Hạnh phúc dưới 50: không ai muốn chuyển đến",
	UNEMPLOYMENT = "Việc làm dưới 80%: thiếu chỗ làm",
	SHORTAGE = "Shop thiếu hàng: cần thêm nhà máy",
}

-- Lớp học, vai trò
-- UserId giáo viên (xem README). Chủ game luôn là giáo viên
Config.TEACHER_USER_IDS = {
	-- 123456789,
}
-- admin mở được bảng Quản trị (thêm/bớt giáo viên, cấm, xoá dữ liệu). Chủ game luôn là admin
Config.ADMIN_USER_IDS = {
	-- 123456789,
}
-- tuỳ chọn: ai trong Group này có rank >= MIN_RANK là giáo viên
Config.TEACHER_GROUP_ID = 0
Config.TEACHER_GROUP_MIN_RANK = 200
-- trong Studio ai cũng là giáo viên, cho dễ test
Config.STUDIO_EVERYONE_IS_TEACHER = true

-- tắt chat mặc định: đè lên bảng chỉ số, mà lớp học cũng không cần chat
Config.SHOW_CHAT_WINDOW = false

Config.CLASS_CODE_LENGTH = 6
-- bỏ nguyên âm (khỏi ghép ra từ nhạy cảm) và 0/1 dễ nhầm, Roblox khuyến nghị vậy
Config.CLASS_CODE_ALPHABET = "BCDFGHJKLMNPQRSTVWXZ23456789"
Config.MAX_CLASSES_PER_TEACHER = 20
Config.MAX_CLASSES_PER_STUDENT = 10
Config.MAX_CLASS_MEMBERS = 60
Config.MAX_CUSTOM_SCENARIOS = 20
Config.MAX_TEXT_BYTES = 200 -- chặn chuỗi dài trước mọi xử lý
-- sự kiện gán lúc học sinh vắng: vào game vẫn nhận nếu chưa cũ hơn mức này
Config.SCENARIO_SYNC_MAX_AGE = 7 * 24 * 3600

-- Lưu trữ
Config.DATASTORE = {
	profiles = "EconCity_Profiles_v1",
	classes = "EconCity_Classes_v1",
	scenarios = "EconCity_Scenarios_v1",
	admin = "EconCity_Admin_v1",
	-- v2: điểm luật xây thành phố không so được với điểm luật cũ nên tách bảng mới
	leaderboardGlobal = "EconCity_LB_Global_v2",
	leaderboardClassPrefix = "EconCity_LB_Class_v2_",
	classLiveMap = "EconCity_ClassLive_v1",
	messagingTopic = "EconCity_Class_v1",
}
-- bảng xếp hạng luật cũ: không ghi nữa nhưng vẫn phải xoá khi có yêu cầu xoá dữ liệu (Right to be Forgotten)
Config.LEGACY_LEADERBOARDS = {
	{ global = "EconCity_LB_Global_v1", classPrefix = "EconCity_LB_Class_v1_" },
}
-- Studio có bật API thì ghi vào kho có hậu tố này, khỏi lẫn với game thật
Config.STUDIO_STORE_SUFFIX = "_Studio"
Config.MAX_PAST_SESSIONS = 20
Config.LEADERBOARD_UPDATE_EVERY_TICKS = 2 -- 2 lượt mới ghi 1 lần, cho khỏi vượt hạn mức
Config.LEADERBOARD_SIZE = 20
Config.LEADERBOARD_CACHE_SECONDS = 30
Config.LIVE_SUMMARY_TTL = 120 -- giây, tiến độ live trong MemoryStore. mỗi lượt (20s) làm mới
Config.ONLINE_WINDOW_SECONDS = 60 -- cập nhật trong khoảng này thì coi là "đang chơi"
Config.SESSION_LOCK_STALE_SECONDS = 90 -- lock của server khác quá khoảng này thì coi như bị bỏ
Config.LOCK_REFRESH_SECONDS = 60 -- profile đang mở được ghi lại ít nhất mỗi khoảng này để làm mới lock

-- chống spam request từ client
Config.REQUEST_BURST = 8 -- số request gửi dồn được
Config.REQUEST_REFILL_PER_SECOND = 4
-- cooldown (giây) giữa 2 lần gọi cùng 1 action, tính theo người chơi.
-- chữ tự nhập mà người khác thấy (tên lớp, tên kịch bản): Roblox quy định tối thiểu 60s
Config.ACTION_COOLDOWNS = {
	joinClass = 2,
	leaveClass = 2,
	createClass = 60,
	createScenario = 60,
	openClassRoom = 10,
	enterClassRoom = 5,
	assignScenario = 3,
	getLeaderboard = 1,
	exportClassCsv = 5,
	getStudentDetail = 1,
	listScenarios = 2,
	deleteScenario = 2,
	closeClassRoom = 5,
	newGame = 2,
	adminAddTeacher = 2,
	adminRemoveTeacher = 2,
	adminBan = 2,
	adminUnban = 2,
	adminDeleteUserData = 5,
}

return Config
