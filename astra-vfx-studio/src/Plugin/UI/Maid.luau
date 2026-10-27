--!strict
--[[
	Maid — collects cleanup tasks and runs them once.

	Accepted tasks: RBXScriptConnection / Signal connections (Disconnect), Instances (Destroy), functions,
	and objects with a `destroy` or `Destroy` method.
]]

local Maid = {}
Maid.__index = Maid

export type Maid = typeof(setmetatable({} :: { _tasks: { any }, _cleaning: boolean }, Maid))

function Maid.new(): Maid
	return setmetatable({ _tasks = {}, _cleaning = false }, Maid)
end

-- Adds a task and returns it (so `local c = maid:give(signal:Connect(...))` works).
function Maid.give<T>(self: Maid, task: T): T
	table.insert(self._tasks, task)
	return task
end

local function runTask(task: any)
	local kind = typeof(task)
	if kind == "function" then
		task()
	elseif kind == "RBXScriptConnection" then
		task:Disconnect()
	elseif kind == "Instance" then
		task:Destroy()
	elseif kind == "table" then
		if type(task.Disconnect) == "function" then
			task:Disconnect()
		elseif type(task.destroy) == "function" then
			task:destroy()
		elseif type(task.Destroy) == "function" then
			task:Destroy()
		end
	end
end

-- Runs all tasks in reverse order of registration. Errors in one task do not stop the others.
function Maid.clean(self: Maid)
	if self._cleaning then
		return
	end
	self._cleaning = true
	local tasks = self._tasks
	self._tasks = {}
	for i = #tasks, 1, -1 do
		local ok, err = pcall(runTask :: any, tasks[i])
		if not ok then
			warn("[AstraVFX] cleanup error: " .. tostring(err))
		end
	end
	self._cleaning = false
end

Maid.destroy = Maid.clean

return Maid
