-- Tên các remote + whitelist action client được gọi.

local Net = {}

Net.FOLDER = "EconCityRemotes"
Net.STATE_EVENT = "State" -- server gửi xuống: snapshot trạng thái
Net.NOTICE_EVENT = "Notice" -- server gửi xuống: toast
Net.REQUEST = "Request" -- client gọi lên: RemoteFunction(action, payload)

Net.ACTIONS = {
	getState = true,
	build = true, -- { kind, index }
	buildRoad = true, -- { path = { index... } }
	demolish = true, -- { index }
	setTax = true, -- { tax }
	togglePause = true,
	newGame = true,
	tickNow = true, -- chỉ Studio
	demoBuild = true, -- nút "Bot xây mẫu", chỉ Studio
	getLeaderboard = true,
	joinClass = true,
	leaveClass = true,
	getMyClasses = true,
	createClass = true,
	getTeacherClasses = true,
	getClassRoster = true,
	assignScenario = true,
	openClassRoom = true,
	enterClassRoom = true,
	clientReady = true, -- client dựng xong UI thì mới bắt đầu tính lượt
	exportClassCsv = true,
	getStudentDetail = true,
	listScenarios = true,
	createScenario = true,
	deleteScenario = true,
	closeClassRoom = true,
	adminGetState = true,
	adminAddTeacher = true,
	adminRemoveTeacher = true,
	adminBan = true,
	adminUnban = true,
	adminDeleteUserData = true,
}

return Net
