-- chạy thử cả game (server + client) trên Roblox giả (mock_roblox). Chạy: texlua tests/e2e_sim.lua
package.path = "./tests/?.lua;" .. package.path
local M = require("mock_roblox")
local Enum, Vector3, Vector2 = M.Enum, M.Vector3, M.Vector2

local checks, failures = 0, {}
local function check(cond, msg)
	checks = checks + 1
	if cond then
		print("  ✓ " .. msg)
	else
		print("  ✗ " .. msg)
		table.insert(failures, msg)
	end
end

local game = M.boot(".")
local function find(root, predicate)
	for _, d in ipairs(root:GetDescendants()) do
		if predicate(d) then
			return d
		end
	end
	return nil
end
local function findText(root, text, class)
	return find(root, function(d)
		return (not class or rawget(d, "__class") == class) and type(d.Text) == "string" and d.Text:find(text, 1, true) ~= nil
	end)
end
local function click(button)
	assert(button, "không tìm thấy nút")
	button.Activated:Fire()
	M.runFor(0.6)
end

print("Khởi động server")
M.runScript(M.serverFolder.Main)
M.runFor(0.5)
check(game:GetService("ReplicatedStorage"):FindFirstChild("EconCityRemotes") ~= nil, "Server tạo Remotes")
check(game:GetService("Workspace"):FindFirstChild("EconCityWorld") ~= nil, "Server dựng mặt đất + spawn")

print("Người chơi 1 (Alice) vào game + chạy client")
local alice = M.addPlayer(1001, "Alice")
M.runFor(0.5)
M.runScript(M.clientFolder.Main)
M.runFor(2)
local pg = alice.PlayerGui
local ui = pg:FindFirstChild("EconCityUI")
check(ui ~= nil, "Client tạo ScreenGui")
local State = M.require(M.clientFolder.State)
check(State.snapshot ~= nil and State.snapshot.session ~= nil, "Client nhận ảnh chụp trạng thái")
check(State.snapshot.persistence == "memory", "Không có DataStore => chế độ bộ nhớ tạm")
local monthLabel = find(ui, function(d) return d.Name == "Month" end)
check(monthLabel and monthLabel.Text == "Month 0 / 24", "HUD hiển thị Tháng 0 / 24")
local city = game:GetService("Workspace"):FindFirstChild("EconCityClientCity")
check(city ~= nil and city:FindFirstChild("Grid") ~= nil and city:FindFirstChild("Gate") ~= nil, "Thành phố 3D có lưới và cổng")
check(city:FindFirstChild("Cell_" .. 138) ~= nil, "Ô cổng có mặt đường")
M.runFor(21)
check(State.snapshot.session.status == "PAUSED" and State.snapshot.session.month == 0, "Ván mới chờ người chơi xây rồi bấm Bắt đầu (không tự tính lượt)")
local pauseBtn = find(ui, function(d) return d.Name == "Pause" end)
check(pauseBtn.Text == "START", "Nút chính hiện 'BẮT ĐẦU'")
local guide = find(ui, function(d) return d.Name == "Guide" end)
local function stepDone(i)
	local row = find(guide, function(d) return d.Name == "Step" .. i end)
	local box = row and row:FindFirstChild("Box")
	return box ~= nil and box.BackgroundTransparency == 0
end
check(guide and guide.Visible and findText(guide, "Drag a road from the GATE") ~= nil and not stepDone(1), "Tháng 0: hiện Ghi chú cách chơi, chưa bước nào xong")
local houseSwatch = find(find(ui, function(d) return d.Name == "Tool_house" end), function(d) return d.Name == "Code" end)
check(houseSwatch and houseSwatch.Text == "RES", "Chú giải dùng mã đất (Ở) thay cho biểu tượng")

-- click chuột vào ô (col, row) trên bản đồ 3D
local Shared = game:GetService("ReplicatedStorage").EconCity
local CityLayout = M.require(Shared.CityLayout)
local UIS = game:GetService("UserInputService")
local function cellIndex(col, row)
	return (row - 1) * 12 + col
end
local function aim(col, row)
	local x, z = CityLayout.cellCenter(cellIndex(col, row))
	M.clickPoint = Vector3.new(x, 0.2, z)
end
local function clickCell(col, row)
	aim(col, row)
	UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector2.new(400, 300), KeyCode = Enum.KeyCode.Unknown }, false)
	M.runFor(0.5)
end
local Config = M.require(Shared.Config)
-- mẫu chuẩn thì bấm ô màu của loại đất (bấm lại là bỏ chọn), mẫu khác và Phá dỡ thì bấm dòng của nó
local function tool(kind)
	local def = Config.BUILDINGS[kind]
	local name = (def and def.kind == kind) and ("Cat_" .. kind) or ("Tool_" .. kind)
	click(find(ui, function(d) return d.Name == name end))
end
local function cells()
	return State.snapshot.session.cells
end

print("Xây bằng chuột: nhà, kéo đường, văn phòng, công viên")
tool("house")
check(findText(ui, "Selected: House") ~= nil, "Bảng Xây dựng hiện công cụ đang chọn")
clickCell(5, 12)
check(cells()[cellIndex(5, 12)] == "house", "Xây nhà cạnh cổng")
check(State.snapshot.session.budget == 9400, "Trừ $600 tiền xây nhà")
check(city:FindFirstChild("Cell_" .. cellIndex(5, 12)) ~= nil, "Nhà xuất hiện trên bản đồ 3D")
tool("road")
aim(6, 11) -- nhấn, kéo lên 2 ô, thả
UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector2.new(400, 300), KeyCode = Enum.KeyCode.Unknown }, false)
M.mouseDown = true
for _, row in ipairs({ 10, 9 }) do
	aim(6, row)
	UIS.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseMovement, Position = Vector2.new(400, 300) }, false)
end
local preview = 0
for _, d in ipairs(city:GetChildren()) do
	if d.Name == "PathPreview" and d.Transparency < 1 then
		preview = preview + 1
	end
end
check(preview == 3, "Kéo đường hiện trước 3 ô (" .. preview .. ")")
M.mouseDown = false
UIS.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
M.runFor(0.5)
check(cells()[cellIndex(6, 11)] == "road" and cells()[cellIndex(6, 10)] == "road" and cells()[cellIndex(6, 9)] == "road", "Kéo đường 3 ô bằng một lần thả chuột")
check(State.snapshot.session.budget == 9400 - 150, "Trừ $50 mỗi ô đường")
check(stepDone(1) and stepDone(2) and not stepDone(5), "Ghi chú tự đánh dấu bước đã xong")
local roadModel = city:FindFirstChild("Cell_" .. cellIndex(6, 10))
check(roadModel and roadModel:FindFirstChild("Marks") ~= nil, "Đường có vạch kẻ nối sang ô bên cạnh")
tool("office")
clickCell(7, 12)
tool("park")
clickCell(5, 11)
check(cells()[cellIndex(7, 12)] == "office" and cells()[cellIndex(5, 11)] == "park", "Xây văn phòng và công viên")
-- vẫn đang cầm công cụ Công viên
local ghost = city:FindFirstChild("Ghost")
local function hover(col, row)
	aim(col, row)
	UIS.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseMovement, Position = Vector2.new(400, 300) }, false)
end
hover(7, 11)
check(ghost.Transparency < 1 and ghost.Color.G > ghost.Color.R, "Rê chuột lên ô trống: ô xem trước màu xanh")
hover(2, 2)
check(ghost.Color.R > 0.9 and ghost.Color.G > 0.7 and ghost.Color.B < 0.3, "Ô trống chưa có đường nối: ô xem trước màu vàng")
hover(7, 12)
check(ghost.Color.R > ghost.Color.G, "Rê chuột lên ô đã có văn phòng: ô xem trước màu đỏ")
clickCell(7, 12)
check(findText(pg:FindFirstChild("EconCityToasts"), "already taken") ~= nil, "Server từ chối xây đè và báo lỗi")

print("Công trình chưa nối đường, phá dỡ, xem thông tin ô")
tool("house")
clickCell(1, 1)
local far = city:FindFirstChild("Cell_1")
check(far ~= nil and find(far, function(d) return d.Name == "Unconnected" end) ~= nil, "Nhà chưa nối đường có biển cảnh báo")
check(findText(pg:FindFirstChild("EconCityToasts"), "Not connected to the GATE") ~= nil, "Xây chỗ chưa nối đường: báo ngay cho người chơi")
tool("demolish")
clickCell(1, 1)
check(cells()[1] == "", "Phá dỡ")
check(findText(pg:FindFirstChild("EconCityToasts"), "refunded $300") ~= nil, "Báo số tiền được hoàn")
tool("demolish") -- bấm lại để bỏ chọn
clickCell(7, 12)
local detail = find(ui, function(d) return d.Name == "DetailPanel" end)
check(detail and detail.Visible == true and findText(detail, "Office") ~= nil, "Không chọn công cụ: bấm vào ô để xem thông tin")
check(findText(detail, "Working") ~= nil, "Thông tin ô: đã nối đường")
M.runFor(9)
check(detail.Visible == false, "Bảng thông tin tự đóng sau 8 giây")

print("Mẫu công trình: thẻ thông tin, công trình 2×2, phá dỡ trong thẻ, vạch qua đường")
local function byName(root, name)
	return find(root, function(d) return d.Name == name end)
end
tool("house")
check(byName(ui, "Tool_apartment").Visible and not byName(ui, "Tool_office").Visible, "Bấm ô màu Ở: hiện các mẫu đất ở, ẩn mẫu loại khác")
check(findText(ui, "Selected: House") ~= nil and byName(ui, "Zone").Text:find("3 types", 1, true) ~= nil, "Ô màu chọn sẵn mẫu chuẩn; ghi số mẫu của loại")
check(byName(byName(ui, "Tool_apartment"), "Split") ~= nil and byName(byName(ui, "Tool_house"), "Split") == nil, "Ô màu của mẫu 2×2 vẽ thành 4 ô nhỏ")
click(byName(ui, "Info_apartment"))
local view = byName(detail, "Preview")
check(detail.Visible and findText(detail, "Apartments") ~= nil and findText(detail, "200 residents") ~= nil and findText(detail, "2x2 = 4 tiles") ~= nil, "Nút i: thẻ số liệu của mẫu (chỗ ở, diện tích)")
check(view and view.Visible and view:FindFirstChild("Preview_apartment") ~= nil and view.CurrentCamera ~= nil, "Thẻ mẫu có hình 3D (ViewportFrame + camera)")
M.runFor(9)
check(detail.Visible, "Thẻ mẫu không tự đóng khi đang đọc")
click(findText(detail, "SELECT TO BUILD"))
check(not detail.Visible and findText(ui, "Selected: Apartments") ~= nil, "CHỌN ĐỂ XÂY: chọn mẫu làm công cụ")
hover(12, 1)
check(ghost.Color.R > ghost.Color.G, "Mẫu 2×2 tràn mép lưới: ô xem trước màu đỏ")
hover(1, 1)
check(ghost.Size.X == 27 and ghost.Color.R > 0.9 and ghost.Color.G > 0.7, "Ô xem trước phủ cả 4 ô (vàng: chưa nối đường)")
tool("house") -- đang chọn Chung cư (loại Ở), bấm lại ô Ở là bỏ chọn
check(findText(ui, "Selected:") == nil, "Bấm lại ô màu của loại đang chọn: bỏ chọn")

print("Thanh thuế")
local taxBlock = find(ui, function(d) return d.Name == "Tax" end)
local hit = find(taxBlock, function(d) return d.Name == "Hit" end)
hit.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector2.new(250, 0) })
UIS.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
M.runFor(1)
check(State.snapshot.session.tax == 25, "Kéo thanh thuế: server lưu thuế 25% (" .. tostring(State.snapshot.session.tax) .. ")")
local taxValue = find(taxBlock, function(d) return d.Name == "TaxValue" end)
local before = taxValue.Text
local touch = { UserInputType = Enum.UserInputType.Touch, Position = Vector2.new(120, 300) }
hit.InputBegan:Fire(touch)
touch.Position = Vector2.new(122, 340)
UIS.InputChanged:Fire(touch)
UIS.InputEnded:Fire(touch)
M.runFor(1)
check(taxValue.Text == before, "Cảm ứng: vuốt dọc để cuộn bảng không đổi thuế")
local why = find(ui, function(d) return d.Name == "Why" end)
check(findText(why, "How happiness is calculated") ~= nil and findText(why, "Moving in") ~= nil, "Có bảng tính hạnh phúc")
local priceRuleOk, budgetNow = true, State.snapshot.session.budget
for _, kind in ipairs({ "house", "shop", "factory", "office", "hospital", "school", "park", "road" }) do
	local price = find(find(ui, function(d) return d.Name == "Tool_" .. kind end), function(d) return d.Name == "Price" end)
	local struck = price.Text:find("short", 1, true) ~= nil
	local cost = ({ house = 600, shop = 1600, factory = 1200, office = 3000, hospital = 2400, school = 2000, park = 1800, road = 50 })[kind]
	priceRuleOk = priceRuleOk and (struck == (budgetNow < cost))
end
check(priceRuleOk, "Chú giải ghi 'thiếu $...' đúng ở những ô vượt ngân sách ($" .. math.floor(budgetNow) .. ")")
local budgetSub = find(find(ui, function(d) return d.Name == "Stat_BUDGET" end), function(d) return d.Name == "Sub" end)
check(budgetSub and budgetSub.Text:find("/mo", 1, true) ~= nil, "Khung tên: dòng thu - chi dưới ngân sách")

print("Tay cầm: chọn công cụ rồi D-pad + A để xây")
UIS.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)
M.runFor(0.1)
tool("house")
local gs = game:GetService("GuiService")
check(gs.SelectedObject == nil, "Chọn công cụ bằng tay cầm: thả nút giao diện để điều khiển ô")
UIS.InputBegan:Fire({ KeyCode = Enum.KeyCode.DPadRight, UserInputType = Enum.UserInputType.Gamepad1 }, false)
UIS.InputBegan:Fire({ KeyCode = Enum.KeyCode.ButtonA, UserInputType = Enum.UserInputType.Gamepad1 }, false)
M.runFor(0.5)
check(cells()[cellIndex(7, 11)] == "house", "D-pad phải + A: xây nhà ở ô bên phải trục đường")
UIS.InputBegan:Fire({ KeyCode = Enum.KeyCode.ButtonB, UserInputType = Enum.UserInputType.Gamepad1 }, false)
M.runFor(0.1)
check(findText(ui, "Selected:") == nil, "Nút B bỏ công cụ")
UIS.LastInputTypeChanged:Fire(Enum.UserInputType.MouseMovement)
M.runFor(0.1)

print("Nút Xây mẫu (chỉ trong Studio)")
local demoButton = find(ui, function(d) return d.Name == "DemoBuild" end)
check(demoButton ~= nil and demoButton.Visible, "Trong Studio có nút Xây mẫu")
local function countBuilt()
	local n = 0
	for _, kind in ipairs(cells()) do
		if kind ~= "" and kind ~= "road" then
			n = n + 1
		end
	end
	return n
end
local beforeDemo = countBuilt()
click(demoButton)
M.runFor(0.5)
check(countBuilt() > beforeDemo, "Bot xây thêm công trình (" .. beforeDemo .. " -> " .. countBuilt() .. ")")
check(State.snapshot.session.budget >= 0, "Bot không tiêu quá số tiền đang có")
check(findText(pg:FindFirstChild("EconCityToasts"), "Buildings added by the bot") ~= nil, "Báo bot đã xây gì")

print("Bắt đầu, tạm dừng, tick ngay")
click(pauseBtn)
check(State.snapshot.session.status == "ACTIVE", "Bấm Bắt đầu")
local stamp = find(ui, function(d) return d.Name == "ApprovalStamp" end)
check(stamp and stamp.Visible and findText(stamp, "is open") ~= nil, "Bắt đầu: băng chúc mừng thành phố mở cửa")
M.runFor(21)
check(State.snapshot.session.month == 1, "Sang tháng 1")
check(guide.Visible == false, "Đã qua tháng 0: ẩn thẻ Cách chơi")
check(monthLabel.Text == "Month 1 / 24", "HUD cập nhật Tháng 1 / 24")
check(State.snapshot.session.population > 0, "Có dân chuyển đến (" .. State.snapshot.session.population .. ")")
local popTile = find(ui, function(d) return d.Name == "Value" and d.Parent and d.Parent.Name == "Stat_POPULATION" end)
check(popTile and popTile.Text == tostring(State.snapshot.session.population), "HUD hiện dân số")
local cityBar = find(ui, function(d) return d.Name == "CityBar" end)
check(cityBar ~= nil and findText(cityBar, "homes") ~= nil and findText(cityBar, "Moving in") ~= nil, "Dải thống kê chỉ có số khung tên chưa có")
click(pauseBtn)
check(State.snapshot.session.status == "PAUSED", "Tạm dừng")
local monthBefore = State.snapshot.session.month
M.runFor(21)
check(State.snapshot.session.month == monthBefore, "Không tick khi tạm dừng")
click(pauseBtn)
check(State.snapshot.session.status == "ACTIVE", "Tiếp tục")
click(find(ui, function(d) return d.Name == "TickNow" end))
check(State.snapshot.session.month == monthBefore + 1, "Nút Tick ngay (Studio) hoạt động")

print("Công trình 2×2 trên sa bàn, phá dỡ trong thẻ, vạch qua đường")
click(pauseBtn) -- tạm dừng để số tiền không đổi giữa các bước
for _ = 1, 8 do
	if State.snapshot.session.budget >= 3200 then
		break
	end
	click(pauseBtn)
	click(find(ui, function(d) return d.Name == "TickNow" end))
	click(pauseBtn)
end
check(State.snapshot.session.status == "PAUSED" and State.snapshot.session.budget >= 3200, "(đủ tiền xây chung cư: $" .. math.floor(State.snapshot.session.budget) .. ")")
tool("apartment")
local budgetBefore = State.snapshot.session.budget
clickCell(1, 1)
check(cells()[1] == "apartment" and cells()[2] == "+1" and cells()[13] == "+1" and cells()[14] == "+1", "Xây chung cư 2×2: ô góc + 3 ô phụ")
check(State.snapshot.session.budget == budgetBefore - 3000, "Trừ $3.000")
local apt = city:FindFirstChild("Cell_1")
check(apt and byName(apt, "Lot").Size.X > 27 and city:FindFirstChild("Cell_2") == nil and city:FindFirstChild("Cell_14") == nil, "Bản đồ 3D: một mô hình phủ 4 ô, ô phụ không có mô hình riêng")
local bars = 0
for _, d in ipairs(apt:GetDescendants()) do
	if d.Name == "HatchBar" then
		bars = bars + 1
	end
end
check(bars == 10, "Gạch sọc chưa nối đường trải cả vùng 2×2 (" .. bars .. " thanh)")
tool("apartment") -- bấm lại mẫu đang chọn để bỏ chọn
clickCell(2, 2)
check(detail.Visible and findText(detail, "Apartments 2x2") ~= nil, "Bấm ô phụ: thẻ của cả công trình 2×2")
local action = byName(detail, "Action")
check(action.Visible and action.Text:find("Demolish, refund $1", 1, true) ~= nil, "Thẻ công trình có nút PHÁ DỠ kèm số tiền hoàn")
click(action)
check(cells()[1] == "apartment" and action.Text:find("PRESS AGAIN", 1, true) ~= nil, "Bấm PHÁ DỠ lần đầu: chỉ hỏi lại")
click(action)
M.runFor(1) -- model fade xong mới bị xoá
check(cells()[1] == "" and cells()[14] == "" and city:FindFirstChild("Cell_1") == nil, "Bấm lần hai: phá cả 4 ô")
check(State.snapshot.session.budget >= budgetBefore - 1500, "Hoàn 50% ($1.500)")
tool("road")
aim(5, 10)
UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector2.new(400, 300), KeyCode = Enum.KeyCode.Unknown }, false)
UIS.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
M.runFor(0.5)
tool("road")
local junction = city:FindFirstChild("Cell_" .. cellIndex(6, 10))
check(cells()[cellIndex(5, 10)] == "road" and junction and byName(junction, "Crosswalk") ~= nil, "Ngã ba có vạch qua đường")
check(byName(city:FindFirstChild("Cell_" .. cellIndex(6, 9)), "Crosswalk") == nil, "Đoạn đường thẳng không có vạch qua đường")

click(pauseBtn)
check(State.snapshot.session.status == "ACTIVE", "Chạy tiếp")

print("Zoom + chế độ đi dạo")
UIS.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseWheel, Position = Vector3.new(0, 0, 1) }, false)
M.runFor(0.3)
click(find(ui, function(d) return d.Name == "Walk" end))
tool("house_small")
check(cells()[cellIndex(12, 1)] == "", "(ô góc xa còn trống)")
clickCell(12, 1)
check(cells()[cellIndex(12, 1)] == "house_small", "Đi dạo: vẫn xây được bằng chuột")
tool("road")
local function touchAt(col, row, moveBy)
	aim(col, row)
	local t = { UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(300, 200, 0), KeyCode = Enum.KeyCode.Unknown }
	UIS.InputBegan:Fire(t, false)
	t.Position = Vector3.new(300 + moveBy, 200, 0)
	UIS.InputEnded:Fire(t)
	M.runFor(0.5)
end
touchAt(12, 3, 80)
check(cells()[cellIndex(12, 3)] == "", "Đi dạo trên cảm ứng: vuốt (xoay camera) không xây")
touchAt(12, 2, 3)
check(cells()[cellIndex(12, 2)] == "road", "Đi dạo trên cảm ứng: chạm nhẹ thì xây")
tool("road")
click(find(ui, function(d) return d.Name == "Walk" end))
click(find(ui, function(d) return d.Name == "ZoomIn" end))

print("Lớp học: tạo lớp (giáo viên trong Studio)")
local modals = pg:FindFirstChild("EconCityModals")
click(find(ui, function(d) return d.Name == "Class" end))
M.runFor(1)
local classModal = modals:FindFirstChild("ClassModal")
check(classModal.Visible, "Mở bảng Lớp học")
local nameBox = find(classModal, function(d) return rawget(d, "__class") == "TextBox" and d.PlaceholderText:find("class name") end)
nameBox.Text = "10A1"
click(findText(classModal, "Create class", "TextButton"))
M.runFor(1)
local titleLabel = find(classModal, function(d) return d.Name == "Title" and d.Text:find("Class ", 1, true) ~= nil end)
local code = titleLabel and titleLabel.Text:match("Class (%w+)$")
check(code and #code == 6, "Tạo lớp xong mở ngay trang của lớp, mã mời 6 ký tự: " .. tostring(code))
check(code and not code:find("[AEIOU01]"), "Mã mời không có nguyên âm / 0 / 1")

print("Người chơi 2 (Bob, không có client) tham gia lớp qua server")
local bob = M.addPlayer(1002, "Bob")
M.runFor(1)
local rf = game:GetService("ReplicatedStorage").EconCityRemotes.Request
local handler = rawget(rf, "__props").OnServerInvoke
local r = handler(bob, "joinClass", { code = string.lower(code) })
check(r.ok, "Bob tham gia lớp bằng mã chữ thường")
M.runFor(0.5)
local r2 = handler(bob, "joinClass", { code = "SAIMA1" })
check(not r2.ok, "Mã sai bị từ chối: " .. tostring(r2.error))
local bobState = handler(bob, "getState")
check(bobState.data.session.status == "PAUSED", "Bob chưa có client => phiên chưa chạy (không mất lượt khi tải chậm)")

print("Giáo viên xem tiến độ, chi tiết học sinh, CSV, gán kịch bản")
click(findText(classModal, "Reload", "TextButton"))
M.runFor(1)
check(findText(classModal, "Bob") ~= nil, "Bảng tiến độ có Bob")
click(findText(classModal, "Assign to class", "TextButton"))
M.runFor(1)
check(findText(classModal, "who got it: 1") ~= nil, "Báo đã áp dụng cho 1 học sinh đang chơi")
click(findText(classModal, "Open private classroom", "TextButton"))
M.runFor(1)
check(findText(pg:FindFirstChild("EconCityToasts"), "publish") ~= nil, "Mở phòng riêng trong Studio báo lỗi rõ ràng")
local bobRow = find(classModal, function(d)
	return rawget(d, "__class") == "TextButton" and find(d, function(x) return type(x.Text) == "string" and x.Text:find("Bob", 1, true) ~= nil end) ~= nil
end)
click(bobRow)
M.runFor(1)
check(findText(classModal, "Student details") ~= nil and findText(classModal, "Buildings") ~= nil, "Xem chi tiết học sinh (công trình)")
click(findText(classModal, "‹ Class", "TextButton"))
M.runFor(1)
click(findText(classModal, "Export CSV", "TextButton"))
M.runFor(1)
local csvBox = find(classModal, function(d) return d.Name == "CsvBox" end)
check(csvBox ~= nil and csvBox.Text:find("^student_name,user_id") ~= nil and csvBox.Text:find("Bob", 1, true) ~= nil, "Xuất CSV có tiêu đề và dòng của Bob")
check(csvBox.Text:find("revenue", 1, true) ~= nil and csvBox.Text:find("employment_pct", 1, true) ~= nil, "CSV có cột doanh thu và tỉ lệ việc làm")
click(findText(classModal, "‹ Class", "TextButton"))
M.runFor(1)
click(findText(classModal, "Back", "TextButton"))
M.runFor(1)

print("Học sinh vắng mặt nhận sự kiện khi quay lại")
M.removePlayer(bob)
M.runFor(1)
click(findText(classModal, "Progress & scenarios", "TextButton"))
M.runFor(3.5)
-- chọn sự kiện thứ 2 (Đứt gãy chuỗi cung ứng), gán lúc Bob vắng
click(findText(classModal, "›", "TextButton"))
click(findText(classModal, "Assign to class", "TextButton"))
M.runFor(1)
check(findText(classModal, "who got it: 0") ~= nil, "Bob vắng mặt => 0 học sinh nhận ngay")
bob = M.addPlayer(1002, "Bob")
M.runFor(1)
local back = handler(bob, "getState")
local names = {}
for _, sc in ipairs(back.data.session.scenarios or {}) do
	names[sc.id] = true
end
check(names.recession and names.supply, "Bob vào lại có cả 2 sự kiện lớp (nhận bù sự kiện lúc vắng mặt)")
click(findText(classModal, "Back", "TextButton"))
M.runFor(1)

print("Kịch bản tuỳ chỉnh")
click(findText(classModal, "Custom scenarios", "TextButton"))
M.runFor(1)
local scName = find(classModal, function(d) return rawget(d, "__class") == "TextBox" and d.PlaceholderText:find("Scenario name", 1, true) end)
scName.Text = "Big storm"
local revenueRowLabel = findText(classModal, "Revenue multiplier")
local minus = find(revenueRowLabel.Parent, function(d) return rawget(d, "__class") == "TextButton" and d.Text == "−" end)
click(minus)
click(minus)
check(findText(revenueRowLabel.Parent, "×0.90") ~= nil, "Chỉnh hiệu ứng bằng nút −/+ (doanh thu ×0.90)")
click(findText(classModal, "Create scenario", "TextButton"))
M.runFor(1)
check(findText(classModal, "Big storm (custom") ~= nil, "Kịch bản tuỳ chỉnh xuất hiện trong danh sách")
click(findText(classModal, "Back", "TextButton"))
M.runFor(1)

print("Quản trị (chủ game)")
click(findText(classModal, "Admin", "TextButton"))
M.runFor(1)
local teacherInput = find(classModal, function(d) return rawget(d, "__class") == "TextBox" and d.PlaceholderText:find("Username or UserId", 1, true) end)
check(teacherInput ~= nil, "Mở bảng Quản trị")
teacherInput.Text = "cogiao_lan"
click(findText(classModal, "Add teacher", "TextButton"))
M.runFor(1)
check(findText(classModal, "cogiao_lan (UserId 555)") ~= nil, "Thêm giáo viên theo tên đăng nhập")
click(findText(classModal, "Back", "TextButton"))
M.runFor(1)
click(find(classModal, function(d) return d.Name == "Close" end))

print("Giáo viên không tự tham gia lớp của mình; Bob bắt đầu chơi")
click(find(ui, function(d) return d.Name == "Class" end))
M.runFor(1)
local codeBox = find(classModal, function(d) return rawget(d, "__class") == "TextBox" and d.PlaceholderText:find("invite code") end)
codeBox.Text = code
click(findText(classModal, "Join", "TextButton"))
M.runFor(1)
check(findText(pg:FindFirstChild("EconCityToasts"), "teacher of this class") ~= nil, "Giáo viên không tự vào lớp mình")
check(#State.snapshot.profile.classes == 0 and #State.snapshot.profile.teaching == 1, "Hồ sơ Alice: dạy 1 lớp, không học lớp nào")
click(find(classModal, function(d) return d.Name == "Close" end))
check(handler(bob, "clientReady").ok, "Bob báo client sẵn sàng")
M.runFor(0.5)
check(handler(bob, "build", { kind = "house", index = 137 }).ok, "Bob xây nhà qua server")
M.runFor(0.5)
check(handler(bob, "togglePause").ok, "Bob bấm Bắt đầu")

print("Bảng xếp hạng & lịch sử")
M.runFor(41) -- 2 lượt bảng xếp hạng mới ghi điểm
click(find(ui, function(d) return d.Name == "Leaderboard" end))
M.runFor(1)
local lbModal = modals:FindFirstChild("LeaderboardModal")
check(lbModal.Visible and findText(lbModal, "#1") ~= nil, "Bảng xếp hạng toàn cầu có dữ liệu")
click(findText(lbModal, "My class", "TextButton"))
M.runFor(1)
check(findText(lbModal, "#1") ~= nil, "Bảng xếp hạng lớp có dữ liệu")
click(find(lbModal, function(d) return d.Name == "Close" end))
click(find(ui, function(d) return d.Name == "History" end))
local histModal = modals:FindFirstChild("HistoryModal")
check(histModal.Visible and findText(histModal, "Budget") ~= nil and findText(histModal, "Employment rate") ~= nil, "Lịch sử hiển thị biểu đồ")
click(find(histModal, function(d) return d.Name == "Close" end))

print("Bố cục điện thoại (màn hình 844x390)")
ui.AbsoluteSize = Vector2.new(844, 354)
M.runFor(0.2)
local lbButton = find(ui, function(d) return d.Name == "Leaderboard" end)
check(lbButton.Text == "Rank", "Màn hình hẹp: nhãn nút ngắn lại")
check(cityBar.Visible == false, "Màn hình hẹp: ẩn dải thống kê, nhường chỗ cho sa bàn")
local netSub = find(find(ui, function(d) return d.Name == "Stat_BUDGET" end), function(d) return d.Name == "Sub" end)
check(netSub.Visible ~= false and netSub.Text:find("/mo", 1, true) ~= nil, "Màn hình hẹp: vẫn thấy thu - chi mỗi tháng dưới ngân sách")
local smallest = 99
for _, d in ipairs(ui:GetDescendants()) do
	local cls = rawget(d, "__class")
	if (cls == "TextLabel" or cls == "TextButton") and type(d.TextSize) == "number" and d.TextSize < smallest then
		smallest = d.TextSize
	end
end
check(smallest >= 13, "Màn hình hẹp: không chữ nào nhỏ hơn 13 đơn vị thiết kế (nhỏ nhất " .. smallest .. ")")
local scaleObj = ui:FindFirstChildOfClass("UIScale")
check(math.abs(scaleObj.Scale - 0.6) < 1e-6, "Không thu nhỏ chữ quá mức (chuột: tối thiểu 0.6)")
local panelFrame = find(ui, function(d) return d.Name == "BuildPanel" end)
check(panelFrame.Size.Y.Offset <= 354 / scaleObj.Scale - 68 + 0.5, "Bảng Xây dựng vừa chiều cao màn hình")
ui.AbsoluteSize = Vector2.new(844, 250) -- màn hình rất thấp
M.runFor(0.2)
check(panelFrame.Size.Y.Offset < 504, "Màn hình thấp: bảng Xây dựng thu ngắn (phần nội dung cuộn)")
ui.AbsoluteSize = Vector2.new(1366, 732)
M.runFor(0.2)
check(lbButton.Text == "Ranking" and cityBar.Visible == true, "Trở lại bố cục đầy đủ")

print("Tay cầm (console): chọn nút, đóng bảng")
UIS.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)
M.runFor(0.1)
check(pauseBtn.Selectable == true, "Dùng tay cầm: nút chọn được")
click(find(ui, function(d) return d.Name == "History" end))
local hm = modals:FindFirstChild("HistoryModal")
check(gs.SelectedObject ~= nil and gs.SelectedObject.Name == "Close", "Mở bảng bằng tay cầm: chọn sẵn nút đóng")
UIS.InputBegan:Fire({ KeyCode = Enum.KeyCode.ButtonB, UserInputType = Enum.UserInputType.Gamepad1 }, true)
M.runFor(0.1)
check(hm.Visible == false, "Nút B đóng bảng")
UIS.LastInputTypeChanged:Fire(Enum.UserInputType.MouseMovement)
M.runFor(0.1)
check(pauseBtn.Selectable == false, "Quay lại chuột: tắt chọn bằng tay cầm")

print("Chơi tới hết ván")
print("    (trạng thái hiện tại: " .. State.snapshot.session.status .. ", tháng " .. State.snapshot.session.month .. ")")
for _ = 1, 30 do
	M.runFor(20)
	local st = State.snapshot.session.status
	if st == "ENDED" or st == "FAILED" then
		break
	end
end
local status = State.snapshot.session.status
check(status == "ENDED", "Hết nhiệm kỳ 24 tháng: " .. status)
local endCard = find(ui, function(d) return d.Name == "EndCard" end)
check(endCard.Visible and findText(endCard, "Term complete") ~= nil, "Hiện màn hình kết thúc")
local medal = find(endCard, function(d) return d.Name == "Seal" end)
check(medal ~= nil and findText(medal, "MONTHS") ~= nil and findText(medal, "24") ~= nil, "Màn kết thúc có huy chương 24 tháng")
local houseTool = find(ui, function(d) return d.Name == "Tool_house" end)
check(houseTool:GetAttribute("Disabled") == true, "Nút xây bị khoá khi ván kết thúc")
local r3 = handler(alice, "togglePause", nil)
check(not r3.ok, "Không 'hồi sinh' phiên đã kết thúc bằng nút tạm dừng")
M.runFor(0.5)
click(findText(endCard, "PLAY AGAIN", "TextButton"))
M.runFor(1)
check(State.snapshot.session.month == 0 and State.snapshot.session.status == "PAUSED", "Ván mới ở tháng 0, chờ bấm Bắt đầu")
check(State.snapshot.profile.gamesPlayed == 1, "Đếm 1 ván đã chơi")
check(city:FindFirstChild("Cell_" .. cellIndex(5, 12)) == nil, "Bản đồ 3D trở lại lưới trống")

print("Bảo mật: dữ liệu xấu từ client")
M.runFor(0.5)
check(not handler(alice, "build", { kind = "house", index = 999 }).ok, "Ô ngoài lưới bị từ chối")
M.runFor(0.5)
check(not handler(alice, "build", { kind = "castle", index = 1 }).ok, "Loại công trình lạ bị từ chối")
M.runFor(0.5)
check(not handler(alice, "setTax", { tax = 99 }).ok, "Thuế ngoài 0-50% bị từ chối")
M.runFor(0.5)
check(not handler(alice, "buildRoad", { path = "x" }).ok, "Đoạn đường sai kiểu bị từ chối")
M.runFor(0.5)
check(State.snapshot.session.budget == 10000, "Không trừ tiền khi bị từ chối")
check(not handler(alice, "applyPolicy", { policy = {} }).ok, "Hành động của luật cũ không còn")
M.runFor(0.5)
check(not handler(alice, "hack", {}).ok, "Hành động lạ bị từ chối")
M.runFor(0.5)
check(not handler(alice, "build", "x").ok, "Payload sai kiểu bị từ chối")

print("Rời game")
M.removePlayer(bob)
M.runFor(1)
if M.bindToClose then
	M.task.spawn(M.bindToClose)
end
M.runFor(1)

print(string.format("\n%d kiểm tra, %d thất bại, %d lỗi runtime, %d cảnh báo", checks, #failures, #M.errors, #M.warnings))
for _, w in ipairs(M.warnings) do
	print("  cảnh báo: " .. w)
end
for _, e in ipairs(M.errors) do
	print("  lỗi: " .. tostring(e))
end
os.exit((#failures == 0 and #M.errors == 0) and 0 or 1)
