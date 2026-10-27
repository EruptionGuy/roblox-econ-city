-- bảng Lớp học. học sinh vào lớp bằng mã mời, giáo viên quản lý lớp/kịch bản/CSV/phòng riêng,
-- chủ game có thêm trang Quản trị

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("EconCity")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Scenarios = require(Shared:WaitForChild("Scenarios"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local C = require(script.Parent:WaitForChild("Components"))
local Icons = require(script.Parent:WaitForChild("Icons"))
local Colors = Theme.Colors

local ClassPanel = {}

local Z = 53

local function sectionTitle(parent, order, text)
	return C.label({ Text = text, Font = Theme.FontDisplay, TextSize = 15, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = order, ZIndex = Z, Parent = parent })
end

local function note(parent, order, text, color)
	return C.label({
		Text = text,
		TextSize = 12,
		Color = color or Colors.textDim,
		Wrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = order,
		ZIndex = Z,
		Parent = parent,
	})
end

local function card(parent, order)
	local frame = C.well({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Radius = Theme.Radius.lg, LayoutOrder = order, ZIndex = Z, Parent = parent })
	C.padding(12, 14).Parent = frame
	C.list(Enum.FillDirection.Vertical, 6).Parent = frame
	return frame
end

local function listFrame(parent, order, spacing)
	local frame = C.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, ZIndex = Z, Parent = parent })
	C.list(Enum.FillDirection.Vertical, spacing or 6).Parent = frame
	return frame
end

-- primary: nền xanh chữ trắng, không thì nút trắng viền mảnh
local function btn(parent, order, text, width, onClick, primary)
	return C.button({
		Text = text,
		Size = UDim2.fromOffset(width, 34),
		ZIndex = Z,
		LayoutOrder = order,
		Variant = primary and "primary" or "white",
		Parent = parent,
	}, onClick)
end

local function formatEffect(field, value)
	if field.kind == "percent" then
		return string.format("%s%%", tostring(Util.roundTo(value * 100, 1)))
	elseif field.kind == "multiplier" then
		return string.format("×%.2f", value)
	end
	return tostring(value)
end

-- stepper -/+ bước tuỳ ý, cho form kịch bản tuỳ chỉnh
local function numberStepper(parent, order, label, opts)
	local row = C.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = order, ZIndex = Z, Parent = parent })
	C.label({ Text = label, TextSize = 12, Size = UDim2.new(1, -170, 1, 0), ZIndex = Z, Parent = row })
	local value = opts.value
	local valueLabel
	local function set(v)
		v = math.clamp(v, opts.min, opts.max)
		v = math.floor(v / opts.step + 0.5) * opts.step
		v = Util.roundTo(v, 4)
		value = v
		valueLabel.Text = opts.format(v)
		valueLabel.TextColor3 = (v ~= opts.default) and Colors.warn or Colors.text
		if opts.onChanged then
			opts.onChanged(v)
		end
	end
	C.button({ Text = "−", Size = UDim2.fromOffset(30, 30), Radius = 15, Lip = false, Position = UDim2.new(1, -166, 0, 0), ZIndex = Z, Parent = row }, function()
		set(value - opts.step)
	end)
	valueLabel = C.label({ Text = "", Font = Theme.FontBold, TextSize = 13, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(96, 30), Position = UDim2.new(1, -134, 0, 0), ZIndex = Z, Parent = row })
	C.button({ Text = "+", Size = UDim2.fromOffset(30, 30), Radius = 15, Lip = false, Position = UDim2.new(1, -34, 0, 0), ZIndex = Z, Parent = row }, function()
		set(value + opts.step)
	end)
	set(value)
	return function()
		return value
	end
end

local function multilineBox(parent, order, text)
	local box = C.new("TextBox", {
		Name = "CsvBox",
		BackgroundColor3 = Colors.panelAlt,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = Colors.text,
		Font = Theme.FontNumber,
		TextSize = 12,
		ClearTextOnFocus = false,
		MultiLine = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = order,
		ZIndex = Z,
		Parent = parent,
	})
	C.corner(10).Parent = box
	C.stroke(Colors.stroke, 1.5).Parent = box
	C.padding(8, 10).Parent = box
	return box
end

-- ctx: { request(action, payload), getSnapshot(), toast(text, kind) }
function ClassPanel.new(gui, ctx)
	local modal
	local view = { mode = "home", code = nil, scenarioIndex = 1, lastResult = nil, studentId = nil, scenarioList = nil }
	local busy = false

	local render

	local function go(mode, extra)
		view.mode = mode
		for k, v in pairs(extra or {}) do
			view[k] = v
		end
		render()
	end

	local function run(action, payload, okMessage)
		if busy then
			return nil
		end
		busy = true
		local response = ctx.request(action, payload)
		busy = false
		if response.ok then
			if okMessage then
				ctx.toast(okMessage, "good")
			end
			return response
		end
		ctx.toast(response.error or "Couldn't do that", "error")
		return nil
	end

	-- load async, nếu trong lúc chờ màn đã vẽ lại thì bỏ kết quả
	local function load(parent, action, payload, onData)
		local loading = note(parent, 0, "Loading...")
		task.spawn(function()
			local response = ctx.request(action, payload)
			if not loading.Parent then
				return
			end
			loading:Destroy()
			if not response.ok then
				note(parent, 1, response.error or "Couldn't load", Colors.bad)
				return
			end
			onData(response.data)
		end)
	end

	-- Trang chính ------------------------------------------------------------------------
	local function renderHome()
		local snap = ctx.getSnapshot()
		local isTeacher = snap and snap.isTeacher
		local isOwner = snap and snap.isOwner
		modal.setTitle("Classes")
		local body = modal.body

		sectionTitle(body, 1, "Join a class")
		local joinRow = C.row({ Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 2, ZIndex = Z, Parent = body })
		local codeBox = C.textbox({ Placeholder = "Enter invite code (e.g. QZ7K2M)", Size = UDim2.fromOffset(240, 38), ZIndex = Z, LayoutOrder = 1, Parent = joinRow })
		C.button({ Text = "Join", Variant = "primary", Size = UDim2.fromOffset(110, 38), ZIndex = Z, LayoutOrder = 2, Parent = joinRow }, function()
			local code = codeBox.Text
			if #code:gsub("%s", "") < 3 then
				ctx.toast("Class codes have at least 3 characters", "error")
				return
			end
			local response = run("joinClass", { code = code })
			if response then
				ctx.toast("Joined class " .. (response.data and response.data.name or code), "good")
				render()
			end
		end)

		sectionTitle(body, 3, "My classes")
		local myList = listFrame(body, 4)
		load(myList, "getMyClasses", nil, function(classes)
			if #classes == 0 then
				note(myList, 1, "You haven't joined a class yet.")
				return
			end
			for i, cls in ipairs(classes) do
				local c = card(myList, i)
				C.label({ Text = string.format("%s  •  Code %s", cls.name, cls.code), Font = Theme.FontBold, TextSize = 14, Truncate = true, LayoutOrder = 1, ZIndex = Z, Parent = c })
				note(c, 2, "Teacher: " .. tostring(cls.teacherName or "?"))
				local actions = C.row({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 3, ZIndex = Z, Parent = c })
				if cls.inRoom then
					note(c, 4, "You're in this class's private classroom.", Colors.good)
				elseif cls.roomOpen then
					btn(actions, 1, "Join classroom", 130, function()
						run("enterClassRoom", { code = cls.code }, "Moving to the classroom...")
					end, true)
				end
				btn(actions, 2, "Leave class", 90, function()
					if run("leaveClass", { code = cls.code }, "Left class " .. cls.name) then
						render()
					end
				end)
			end
		end)

		if not isTeacher then
			note(body, 9, "Only teachers can create classes. Ask the game owner to add you to the teacher list (Admin section).", Colors.textMuted)
			return
		end

		sectionTitle(body, 10, "Classes I teach")
		local createRow = C.row({ Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 11, ZIndex = Z, Parent = body })
		local nameBox = C.textbox({ Placeholder = "New class name (e.g. Period 3)", Size = UDim2.fromOffset(240, 38), ZIndex = Z, LayoutOrder = 1, Parent = createRow })
		C.button({ Text = "Create class", Variant = "primary", Size = UDim2.fromOffset(120, 38), ZIndex = Z, LayoutOrder = 2, Parent = createRow }, function()
			local name = nameBox.Text
			if #name:gsub("%s", "") == 0 then
				ctx.toast("Enter a class name", "error")
				return
			end
			local response = run("createClass", { name = name })
			if response then
				local d = response.data
				ctx.toast(string.format("Created class %s. Invite code: %s", d.name, d.code), "good")
				if d.renamed then
					ctx.toast("Couldn't check the class name, using the temporary name \"" .. d.name .. "\"", "error")
				end
				go("roster", { code = d.code, lastResult = nil, scenarioList = nil })
			end
		end)
		note(body, 12, "Students see the class name, and Roblox filters it. Don't use real names or school names. You can create 1 class per minute.", Colors.textMuted)

		local teachList = listFrame(body, 13)
		load(teachList, "getTeacherClasses", nil, function(classes)
			if #classes == 0 then
				note(teachList, 1, "No classes yet. Create one to get a 6-character invite code for students.")
				return
			end
			for i, cls in ipairs(classes) do
				local c = card(teachList, i)
				C.label({ Text = string.format("%s  •  INVITE CODE: %s", cls.name, cls.code), Font = Theme.FontBold, TextSize = 14, Truncate = true, LayoutOrder = 1, ZIndex = Z, Parent = c })
				note(c, 2, string.format("Students: %d%s", cls.memberCount or 0, cls.roomOpen and " • Private classroom open" or ""))
				btn(c, 3, "Progress & scenarios  ›", 240, function()
					go("roster", { code = cls.code, lastResult = nil, scenarioList = nil })
				end)
			end
		end)

		local extra = C.row({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 20, ZIndex = Z, Parent = body })
		btn(extra, 1, "Custom scenarios", 180, function()
			go("scenarios")
		end)
		if isOwner then
			btn(extra, 2, "Admin", 120, function()
				go("admin")
			end)
		end
	end

	-- kịch bản có sẵn + kịch bản tuỳ chỉnh, mỗi lần mở lớp chỉ tải 1 lần
	local function scenarioChoices()
		local list = {}
		for _, s in ipairs(Scenarios.CATALOG) do
			table.insert(list, { id = s.id, name = s.name, description = s.description, severity = s.severity, durationMonths = s.durationMonths })
		end
		for _, s in ipairs(view.scenarioList or {}) do
			table.insert(list, { id = s.id, name = s.name, description = s.description, severity = s.severity, durationMonths = s.durationMonths, custom = true, effects = s.effects })
		end
		return list
	end

	local function effectsText(effects)
		local parts = {}
		for _, field in ipairs(Scenarios.CUSTOM_EFFECTS) do
			local v = effects and effects[field.key]
			if v ~= nil then
				table.insert(parts, field.label .. " " .. formatEffect(field, v))
			end
		end
		return table.concat(parts, " • ")
	end

	-- Trang tiến độ lớp (giáo viên) ------------------------------------------------------------
	local function renderRoster()
		local body = modal.body
		modal.setTitle("Class " .. tostring(view.code))
		local top = C.row({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 1, ZIndex = Z, Parent = body })
		btn(top, 1, "‹ Back", 96, function()
			go("home")
		end)
		btn(top, 2, "Reload", 76, function()
			view.scenarioList = nil
			render()
		end)
		btn(top, 3, "Export CSV", 90, function()
			go("csv")
		end)
		local roomRow = C.row({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 2, ZIndex = Z, Parent = body })

		sectionTitle(body, 3, "Assign a crisis event to the whole class")
		local pickerHolder = listFrame(body, 4)
		local function drawPicker()
			for _, child in ipairs(pickerHolder:GetChildren()) do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			local choices = scenarioChoices()
			if view.scenarioIndex > #choices then
				view.scenarioIndex = 1
			end
			local current = choices[view.scenarioIndex]
			local picker = C.row({ Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 1, ZIndex = Z, Parent = pickerHolder })
			C.button({ Text = "‹", Variant = "white", Size = UDim2.fromOffset(34, 34), Radius = 17, ZIndex = Z, LayoutOrder = 1, Parent = picker }, function()
				view.scenarioIndex = (view.scenarioIndex - 2) % #choices + 1
				drawPicker()
			end)
			C.label({
				Text = string.format("%s%s (level %d/10, months: %d)  %d/%d", "", current.name .. (current.custom and " (custom)" or ""), current.severity or 5, current.durationMonths or 1, view.scenarioIndex, #choices),
				Font = Theme.FontBold,
				TextSize = 13,
				Truncate = true,
				XAlign = Enum.TextXAlignment.Center,
				Size = UDim2.fromOffset(380, 32),
				ZIndex = Z,
				LayoutOrder = 2,
				Parent = picker,
			})
			C.button({ Text = "›", Variant = "white", Size = UDim2.fromOffset(34, 34), Radius = 17, ZIndex = Z, LayoutOrder = 3, Parent = picker }, function()
				view.scenarioIndex = view.scenarioIndex % #choices + 1
				drawPicker()
			end)
			local desc = current.description ~= "" and current.description or "(no description)"
			if current.custom then
				desc = desc .. "\nEffects: " .. effectsText(current.effects)
			end
			note(pickerHolder, 2, desc)
			btn(pickerHolder, 3, "Assign to class", 140, function()
				local response = run("assignScenario", { code = view.code, scenarioId = current.id })
				if response then
					local d = response.data
					view.lastResult = string.format(
						"Assigned \"%s\". Students on this server who got it: %d%s. Offline students get it next time they join (within 7 days).",
						d.name or current.name,
						d.appliedHere or 0,
						d.broadcast and "; sent to students on other servers" or ""
					)
					render()
				end
			end, true)
			if view.lastResult then
				note(pickerHolder, 4, view.lastResult, Colors.good)
			end
		end
		drawPicker()
		if view.scenarioList == nil then
			task.spawn(function()
				local response = ctx.request("listScenarios")
				if response.ok and pickerHolder.Parent then
					view.scenarioList = response.data.custom or {}
					drawPicker()
				end
			end)
		end

		sectionTitle(body, 7, "Student progress (click a name for details)")
		local header = C.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 8, ZIndex = Z, Parent = body })
		local columns = { { "STUDENT", 0, 0.34 }, { "PROGRESS", 0.34, 0.16 }, { "REVENUE", 0.5, 0.16 }, { "HAPPINESS", 0.66, 0.16 }, { "STATUS", 0.82, 0.18 } }
		for _, col in ipairs(columns) do
			C.label({ Text = col[1], TextSize = 10, Font = Theme.FontBold, Color = Colors.textMuted, Size = UDim2.new(col[3], 0, 1, 0), Position = UDim2.fromScale(col[2], 0), ZIndex = Z, Parent = header })
		end
		local list = listFrame(body, 9, 4)
		local logHolder = listFrame(body, 10, 4)
		load(list, "getClassRoster", { code = view.code }, function(data)
			-- nút phòng riêng tuỳ phòng đang mở hay đóng
			if data.roomOpen then
				if data.inRoom then
					note(roomRow, 1, "You're in this class's private classroom.", Colors.good).Size = UDim2.fromOffset(300, 30)
				else
					btn(roomRow, 1, "Join private classroom", 170, function()
						run("enterClassRoom", { code = view.code }, "Moving to the classroom...")
					end, true)
				end
				btn(roomRow, 2, "Close classroom", 110, function()
					if run("closeClassRoom", { code = view.code }, "Private classroom closed") then
						render()
					end
				end)
			else
				btn(roomRow, 1, "Open private classroom", 170, function()
					if run("openClassRoom", { code = view.code }, "Private classroom open. Students press \"Join classroom\" to enter") then
						render()
					end
				end)
			end
			local members = data.members or {}
			if #members == 0 then
				note(list, 1, "No students have joined yet. Send the invite code " .. tostring(view.code) .. " to your students.")
			end
			for i, m in ipairs(members) do
				local r = C.new("TextButton", {
					Text = "",
					AutoButtonColor = false,
					BackgroundColor3 = Colors.panelAlt,
					BackgroundTransparency = 0,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 36),
					LayoutOrder = i,
					ZIndex = Z,
					Parent = list,
				})
				C.corner(10).Parent = r
				C.selectable(r)
				r.Activated:Connect(function()
					go("student", { studentId = m.userId })
				end)
				local s = m.summary
				local statusText, statusColor = "Not played", Colors.textMuted
				if s then
					statusText = Theme.StatusText[s.status] or s.status
					statusColor = Theme.statusColor(s.status)
				end
				local cells = {
					{ tostring(m.name) .. (m.online and " (playing)" or ""), 0, 0.34, m.online and Colors.good or Colors.text },
					{ s and string.format("Month %d/%d", s.month or 0, s.maxMonths or 12) or "Not started", 0.34, 0.16, Colors.text },
					{ s and Util.formatMoneyK(s.gdp or 0) or "$0k", 0.5, 0.16, Colors.text },
					{ s and tostring(Util.round(s.happiness or 0)) or "-", 0.66, 0.16, s and Theme.happinessColor(s.happiness or 0) or Colors.text },
					{ statusText, 0.82, 0.18, statusColor },
				}
				for _, cell in ipairs(cells) do
					C.label({ Text = cell[1], TextSize = 12, Color = cell[4], Truncate = true, Size = UDim2.new(cell[3], -6, 1, 0), Position = UDim2.new(cell[2], 6, 0, 0), ZIndex = Z, Parent = r })
				end
			end
			note(list, 900, "Green names are in the game now. Others show their last saved data.", Colors.textMuted)
			local log = data.scenarioLog or {}
			if #log > 0 then
				sectionTitle(logHolder, 1, "Recently assigned events")
				for i, e in ipairs(log) do
					note(logHolder, 1 + i, "• " .. tostring(e.name), Colors.textDim)
				end
			end
		end)
	end

	-- Chi tiết một học sinh ------------------------------------------------------------------
	local function renderStudent()
		local body = modal.body
		modal.setTitle("Student details")
		local top = C.row({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 1, ZIndex = Z, Parent = body })
		btn(top, 1, "‹ Class " .. tostring(view.code), 130, function()
			go("roster")
		end)
		local holder = listFrame(body, 2, 6)
		load(holder, "getStudentDetail", { code = view.code, userId = view.studentId }, function(data)
			sectionTitle(holder, 1, string.format("%s (%s)", tostring(data.name), data.online and "playing" or "offline"))
			local d = data.detail
			if type(d) ~= "table" then
				note(holder, 2, "This student has no game data yet.")
				return
			end
			note(holder, 2, string.format(
				"%s • Month %d/%d • Budget %s • Revenue %s/month • Happiness %d • Employment %s • Population %s • Tax %s • Score %s",
				Theme.StatusText[d.status] or tostring(d.status),
				d.month or 0,
				d.maxMonths or 24,
				Util.formatMoneyFull(d.budget or 0),
				Util.formatMoneyK(d.gdp or 0),
				Util.round(d.happiness or 0),
				d.employment and string.format("%d%%", Util.round(d.employment)) or "—",
				Util.formatInt(d.population or 0),
				d.tax and (tostring(d.tax) .. "%") or "—",
				Util.formatInt(d.prosperityScore or 0)
			), Colors.text)
			if type(d.city) == "table" and type(d.city.counts) == "table" then
				local g = card(holder, 3)
				C.label({ Text = "Buildings", Font = Theme.FontBold, TextSize = 13, LayoutOrder = 0, ZIndex = Z, Parent = g })
				local parts = {}
				for _, kind in ipairs(Config.BUILDING_ORDER) do
					local n = d.city.counts[kind]
					if n and n > 0 then
						table.insert(parts, string.format("%s %s: %d", Config.CATEGORIES[kind].code, Config.CATEGORIES[kind].zone, n))
					end
				end
				note(g, 1, #parts > 0 and table.concat(parts, " • ") or "Nothing built yet.")
				if (d.city.unconnected or 0) > 0 then
					note(g, 2, string.format("Buildings not connected by road: %d (not working, still paying upkeep)", d.city.unconnected), Colors.warn)
				end
			end
			if type(d.scenarios) == "table" and #d.scenarios > 0 then
				local names = {}
				for _, sc in ipairs(d.scenarios) do
					table.insert(names, string.format("%s (months left: %d)", tostring(sc.name), sc.monthsLeft or 0))
				end
				note(holder, 5, "Active events: " .. table.concat(names, ", "), Colors.warn)
			end
			if type(d.history) == "table" and #d.history > 0 then
				local h = card(holder, 6)
				C.label({ Text = "By month (month • budget • revenue • happiness • employment • population)", Font = Theme.FontBold, TextSize = 12, Wrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 0, ZIndex = Z, Parent = h })
				for i, row in ipairs(d.history) do
					note(h, i, string.format("T%d • %s • %s • %d • %s • %s", row.month or i, Util.formatMoneyFull(row.budget or 0),
						Util.formatMoneyK(row.gdp or 0), Util.round(row.happiness or 0), row.employment and string.format("%d%%", Util.round(row.employment)) or "—", Util.formatInt(row.population or 0)), Colors.text)
				end
			end
		end)
	end

	-- Xuất CSV ---------------------------------------------------------------------------------
	local function renderCsv()
		local body = modal.body
		modal.setTitle("Export CSV for class " .. tostring(view.code))
		local top = C.row({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 1, ZIndex = Z, Parent = body })
		btn(top, 1, "‹ Class " .. tostring(view.code), 130, function()
			go("roster")
		end)
		note(body, 2, "Click the box below, press Ctrl+A then Ctrl+C (Mac: ⌘A, ⌘C) to copy, then paste into Excel or Google Sheets. Each row is one student × one month of their latest game.")
		local holder = listFrame(body, 3, 8)
		load(holder, "exportClassCsv", { code = view.code }, function(data)
			local lines = {}
			for line in (data.csv .. "\n"):gmatch("([^\n]*)\n") do
				table.insert(lines, line)
			end
			-- chia ra nhiều ô, mỗi ô tối đa chunkSize dòng. text quá lớn thì Roblox render chậm
			local header = lines[1] or ""
			local chunkSize = 150
			local chunks = {}
			for i = 2, #lines, chunkSize do
				local part = { header }
				for j = i, math.min(#lines, i + chunkSize - 1) do
					table.insert(part, lines[j])
				end
				table.insert(chunks, table.concat(part, "\n"))
			end
			if #chunks == 0 then
				chunks = { header }
			end
			note(holder, 1, string.format("Data rows: %d%s", data.rows or 0, #chunks > 1 and (", split into " .. #chunks .. " parts, each with a header row") or ""), Colors.good)
			for i, chunk in ipairs(chunks) do
				if #chunks > 1 then
					note(holder, i * 2, "Part " .. i .. "/" .. #chunks, Colors.textDim)
				end
				multilineBox(holder, i * 2 + 1, chunk)
			end
		end)
	end

	-- Kịch bản tuỳ chỉnh ----------------------------------------------------------------------
	local function renderScenarios()
		local body = modal.body
		modal.setTitle("Custom scenarios")
		local top = C.row({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 1, ZIndex = Z, Parent = body })
		btn(top, 1, "‹ Back", 96, function()
			go("home")
		end)

		sectionTitle(body, 2, "My scenarios")
		local list = listFrame(body, 3)
		load(list, "listScenarios", nil, function(data)
			view.scenarioList = data.custom or {}
			if #data.custom == 0 then
				note(list, 1, "No custom scenarios yet.")
			end
			for i, s in ipairs(data.custom) do
				local c = card(list, i)
				C.label({ Text = string.format("%s (custom, level %d/10, months: %d)", s.name, s.severity, s.durationMonths), Font = Theme.FontBold, TextSize = 13, Truncate = true, LayoutOrder = 1, ZIndex = Z, Parent = c })
				if s.description and s.description ~= "" then
					note(c, 2, s.description)
				end
				note(c, 3, effectsText(s.effects), Colors.warn)
				btn(c, 4, "Delete", 70, function()
					if run("deleteScenario", { id = s.id }, "Scenario deleted") then
						view.scenarioList = nil
						render()
					end
				end)
			end
			note(list, 99, string.format("Up to %d scenarios. They appear under \"Assign\" in every class you teach (marked \"custom\").", data.max or Config.MAX_CUSTOM_SCENARIOS), Colors.textMuted)
		end)

		sectionTitle(body, 4, "New scenario")
		local form = card(body, 5)
		local nameBox = C.textbox({ Placeholder = "Scenario name (e.g. Big storm)", Size = UDim2.new(1, 0, 0, 34), ZIndex = Z, LayoutOrder = 1, Parent = form })
		local descBox = C.textbox({ Placeholder = "Short description for students (optional)", Size = UDim2.new(1, 0, 0, 34), ZIndex = Z, LayoutOrder = 2, Parent = form })
		local getSeverity = numberStepper(form, 3, "Severity (1-10)", { min = 1, max = 10, step = 1, value = 5, default = 5, format = tostring })
		local getDuration = numberStepper(form, 4, "Duration (months)", { min = 1, max = 12, step = 1, value = 3, default = 3, format = function(v)
			return v .. " mo"
		end })
		local getters = {}
		for i, field in ipairs(Scenarios.CUSTOM_EFFECTS) do
			local f = field
			getters[field.key] = numberStepper(form, 10 + i, field.label, {
				min = field.min,
				max = field.max,
				step = field.step,
				value = field.default,
				default = field.default,
				format = function(v)
					return formatEffect(f, v)
				end,
			})
		end
		note(form, 30, "Roblox filters names and descriptions before students see them. You can create 1 scenario per minute.", Colors.textMuted)
		btn(form, 31, "Create scenario", 140, function()
			local effects = {}
			for key, getter in pairs(getters) do
				effects[key] = getter()
			end
			local response = run("createScenario", {
				name = nameBox.Text,
				description = descBox.Text,
				severity = getSeverity(),
				durationMonths = getDuration(),
				effects = effects,
			})
			if response then
				ctx.toast("Created scenario \"" .. tostring(response.data.name) .. "\"", "good")
				view.scenarioList = nil
				render()
			end
		end, true)
	end

	-- Quản trị (chủ game) -------------------------------------------------------------------------
	local function renderAdmin()
		local body = modal.body
		modal.setTitle("Admin")
		local top = C.row({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 1, ZIndex = Z, Parent = body })
		btn(top, 1, "‹ Back", 96, function()
			go("home")
		end)
		btn(top, 2, "Reload", 76, function()
			render()
		end)
		local holder = listFrame(body, 2, 8)
		load(holder, "adminGetState", nil, function(data)
			sectionTitle(holder, 1, "Teachers")
			note(holder, 2, "Enter a Roblox username (not the display name) or UserId. The game owner and UserIds in Config are always teachers.", Colors.textMuted)
			local addRow = C.row({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 3, ZIndex = Z, Parent = holder })
			local teacherBox = C.textbox({ Placeholder = "Username or UserId", Size = UDim2.fromOffset(240, 34), ZIndex = Z, LayoutOrder = 1, Parent = addRow })
			btn(addRow, 2, "Add teacher", 140, function()
				local response = run("adminAddTeacher", { target = teacherBox.Text })
				if response then
					ctx.toast("Added teacher " .. tostring(response.data.name), "good")
					render()
				end
			end, true)
			local teachers = listFrame(holder, 4, 4)
			if #data.teachers == 0 then
				note(teachers, 1, "No teachers added yet.")
			end
			for i, t in ipairs(data.teachers) do
				local r = C.row({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = i, ZIndex = Z, Parent = teachers })
				C.label({ Text = string.format("%s (UserId %s)", tostring(t.name), tostring(t.userId)), TextSize = 12, Truncate = true, Size = UDim2.fromOffset(360, 30), LayoutOrder = 1, ZIndex = Z, Parent = r })
				btn(r, 2, "Remove", 60, function()
					if run("adminRemoveTeacher", { userId = t.userId }, "Teacher access removed") then
						render()
					end
				end)
			end

			sectionTitle(holder, 10, "Ban players")
			local banForm = C.row({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 11, ZIndex = Z, Parent = holder })
			local banTarget = C.textbox({ Placeholder = "Username / UserId", Size = UDim2.fromOffset(180, 34), ZIndex = Z, LayoutOrder = 1, Parent = banForm })
			local banDays = C.textbox({ Placeholder = "Days (0 = permanent)", Size = UDim2.fromOffset(170, 34), ZIndex = Z, LayoutOrder = 2, Parent = banForm })
			local banReason = C.textbox({ Placeholder = "Reason shown to the banned player", Size = UDim2.new(1, 0, 0, 34), ZIndex = Z, LayoutOrder = 12, Parent = holder })
			btn(holder, 13, "Ban", 90, function()
				local response = run("adminBan", { target = banTarget.Text, days = tonumber(banDays.Text) or 0, reason = banReason.Text })
				if response then
					ctx.toast("Banned " .. tostring(response.data.name), "good")
					render()
				end
			end, true)
			local bans = listFrame(holder, 14, 4)
			for i, b in ipairs(data.bans) do
				local r = C.row({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = i, ZIndex = Z, Parent = bans })
				C.label({ Text = string.format("%s • %s • %s", tostring(b.name), (b.days or 0) > 0 and (b.days .. " day(s)") or "permanent", tostring(b.reason or "")), TextSize = 12, Truncate = true, Size = UDim2.fromOffset(360, 30), LayoutOrder = 1, ZIndex = Z, Parent = r })
				btn(r, 2, "Unban", 80, function()
					if run("adminUnban", { userId = b.userId }, "Unbanned") then
						render()
					end
				end)
			end

			-- Xoá dữ liệu
			sectionTitle(holder, 20, "Delete data on request (Right to Erasure)")
			note(holder, 21, "When Roblox sends a data deletion request with a UserId, enter that UserId and press Delete twice. This deletes the profile, removes them from classes, and deletes the classes they teach, their leaderboard scores and custom scenarios. It can't be undone.", Colors.textMuted)
			local delRow = C.row({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 22, ZIndex = Z, Parent = holder })
			local delBox = C.textbox({ Placeholder = "UserId", Size = UDim2.fromOffset(180, 34), ZIndex = Z, LayoutOrder = 1, Parent = delRow })
			local armed = nil
			local delButton
			delButton = btn(delRow, 2, "Delete all data", 180, function()
				local target = delBox.Text
				if armed ~= target then
					armed = target
					delButton.Text = "Press again to confirm"
					task.delay(5, function()
						if delButton.Parent and armed == target then
							armed = nil
							delButton.Text = "Delete all data"
						end
					end)
					return
				end
				armed = nil
				delButton.Text = "Delete all data"
				local response = run("adminDeleteUserData", { target = target })
				if response then
					local d = response.data
					ctx.toast(string.format("Data deleted. Profile: %s. Removed from classes: %d. Classes deleted: %d", d.profile and "found" or "not found", d.classesLeft or 0, d.classesDeleted or 0), "good")
					render()
				end
			end)

			if #data.log > 0 then
				sectionTitle(holder, 30, "Recent log")
				for i, row in ipairs(data.log) do
					if i > 10 then
						break
					end
					note(holder, 30 + i, string.format("%s • %s", tostring(row.action), tostring(row.target or "")), Colors.textDim)
				end
			end
			if data.persistence == "memory" then
				note(holder, 50, "Test mode (DataStore off): lists are only kept on this server.", Colors.warn)
			end
		end)
	end

	render = function()
		modal.clear()
		modal.body.CanvasPosition = Vector2.new(0, 0)
		local mode = view.mode
		if mode == "roster" and view.code then
			renderRoster()
		elseif mode == "student" and view.code and view.studentId then
			renderStudent()
		elseif mode == "csv" and view.code then
			renderCsv()
		elseif mode == "scenarios" then
			renderScenarios()
		elseif mode == "admin" then
			renderAdmin()
		else
			renderHome()
		end
	end

	modal = C.modal({ Name = "ClassModal", Title = "Classes", Size = UDim2.fromOffset(640, 560), Parent = gui, onOpen = function()
		view.mode = "home"
		render()
	end })
	Icons.badge("people", { Size = 30, IconSize = 16, Color = Colors.people, Soft = Colors.peopleSoft, Square = true, Position = UDim2.fromOffset(22, 14), ZIndex = 52, Parent = modal.card })
	modal.card:FindFirstChild("Title").Position = UDim2.fromOffset(62, 0)
	return modal
end

return ClassPanel
