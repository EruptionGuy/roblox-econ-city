-- snapshot state phía client, và hàm gọi server

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage:WaitForChild("EconCity"):WaitForChild("Net"))

local State = {}
State.snapshot = nil
State.previous = nil

local listeners = {}
local remotes = ReplicatedStorage:WaitForChild(Net.FOLDER)
local requestFunction = remotes:WaitForChild(Net.REQUEST)
State.stateEvent = remotes:WaitForChild(Net.STATE_EVENT)
State.noticeEvent = remotes:WaitForChild(Net.NOTICE_EVENT)

function State.subscribe(fn)
	table.insert(listeners, fn)
	if State.snapshot then
		task.spawn(fn, State.snapshot, nil)
	end
	return function()
		for i, f in ipairs(listeners) do
			if f == fn then
				table.remove(listeners, i)
				break
			end
		end
	end
end

function State.set(snapshot)
	if type(snapshot) ~= "table" then
		return
	end
	State.previous = State.snapshot
	State.snapshot = snapshot
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn, snapshot, State.previous)
		if not ok then
			warn("[EconCity] UI update error: " .. tostring(err))
		end
	end
end

function State.session()
	return State.snapshot and State.snapshot.session
end

function State.serverNow()
	return Workspace:GetServerTimeNow()
end

-- trả về { ok, data, error }
-- timeout mặc định 30s, không thì nút bấm treo mãi khi server chậm
function State.request(action, payload, timeout)
	timeout = timeout or 30
	local done, result = false, nil
	task.spawn(function()
		local ok, response = pcall(function()
			return requestFunction:InvokeServer(action, payload)
		end)
		if not ok then
			result = { ok = false, error = "Lost connection to the server" }
		elseif type(response) ~= "table" then
			result = { ok = false, error = "The server isn't responding" }
		else
			result = response
		end
		done = true
	end)
	local waited = 0
	while not done and waited < timeout do
		task.wait(0.1)
		waited = waited + 0.1
	end
	if not done then
		return { ok = false, error = "The server took too long, please try again" }
	end
	return result
end

return State
