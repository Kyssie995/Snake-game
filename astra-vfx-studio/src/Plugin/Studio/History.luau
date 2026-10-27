--!strict
--[[
	History — thin wrapper around ChangeHistoryService (docs/PLUGIN_CONTRACTS.md §3).

	Every document change the editor makes is wrapped in exactly one recording, so Studio's own Undo/Redo
	(Ctrl+Z, Edit menu) steps through ASTRA edits. Facts (docs/research/api-studio-plugin.md §2.3):
	* TryBeginRecording returns nil when this plugin already has an open recording or during playtests.
	* FinishRecording(id, Commit|Cancel|Append); Cancel reverts the recorded changes.
	* Undo()/Redo() raise when there is nothing to undo/redo or a playtest runs → pcall.
	* OnUndo/OnRedo fire for user-triggered and programmatic undo/redo.
	* Recordings are not cancelled when a plugin reloads → cancelStale() on startup.

	The service is injectable so the module can be tested with a fake.
]]

local Signal = require(script.Parent.Parent.Parent.AstraVFX.Core.Signal)

local History = {}
History.__index = History

export type History = typeof(setmetatable(
	{} :: {
		service: any,
		undone: Signal.Signal,
		redone: Signal.Signal,
		_open: string?,
		_connections: { any },
		_staleAttribute: Instance?,
	},
	History
))

local STALE_ATTRIBUTE = "AstraOpenRecording"

function History.new(service: any?, staleHolder: Instance?): History
	local self = setmetatable({
		service = service or game:GetService("ChangeHistoryService"),
		undone = Signal.new(),
		redone = Signal.new(),
		_open = nil :: string?,
		_connections = {},
		_staleAttribute = staleHolder,
	}, History)
	local okUndo, undoSignal = pcall(function()
		return self.service.OnUndo
	end)
	if okUndo and undoSignal then
		table.insert(
			self._connections,
			undoSignal:Connect(function(name: string)
				self.undone:Fire(name)
			end)
		)
	end
	local okRedo, redoSignal = pcall(function()
		return self.service.OnRedo
	end)
	if okRedo and redoSignal then
		table.insert(
			self._connections,
			redoSignal:Connect(function(name: string)
				self.redone:Fire(name)
			end)
		)
	end
	return self
end

local function finish(self: History, id: string, operation: EnumItem)
	local ok, err = pcall(function()
		self.service:FinishRecording(id, operation)
	end)
	if not ok then
		warn("[AstraVFX] FinishRecording failed: " .. tostring(err))
	end
	self._open = nil
	if self._staleAttribute then
		self._staleAttribute:SetAttribute(STALE_ATTRIBUTE, nil)
	end
end

--[[
	Runs `fn` inside one recording. Returns (true) on success, (false, "no-recording") when the change happened
	but could not be recorded (it is then NOT undoable), or (false, errorMessage) when `fn` raised — in that case
	the recording is cancelled, which reverts the partial change.
]]
function History.record(self: History, label: string, fn: () -> ()): (boolean, string?)
	local okBegin, id = pcall(function()
		return self.service:TryBeginRecording("AstraVFX_" .. string.gsub(label, "[^%w_]", "_"), "ASTRA: " .. label)
	end)
	if not okBegin or type(id) ~= "string" then
		local ok, err = pcall(fn :: any)
		if not ok then
			return false, tostring(err)
		end
		return false, "no-recording"
	end
	self._open = id
	if self._staleAttribute then
		self._staleAttribute:SetAttribute(STALE_ATTRIBUTE, id)
	end
	local ok, err = pcall(fn :: any)
	if ok then
		finish(self, id, Enum.FinishRecordingOperation.Commit)
		return true, nil
	end
	finish(self, id, Enum.FinishRecordingOperation.Cancel)
	return false, tostring(err)
end

function History.undo(self: History): boolean
	local ok = pcall(function()
		self.service:Undo()
	end)
	return ok
end

function History.redo(self: History): boolean
	local ok = pcall(function()
		self.service:Redo()
	end)
	return ok
end

function History.canUndo(self: History): boolean
	local ok, can = pcall(function()
		return self.service:GetCanUndo()
	end)
	return ok and can == true
end

function History.canRedo(self: History): boolean
	local ok, can = pcall(function()
		return self.service:GetCanRedo()
	end)
	return ok and can == true
end

-- Cancels a recording left open by a previous session of this plugin (id stored as an attribute).
function History.cancelStale(self: History)
	local holder = self._staleAttribute
	if not holder then
		return
	end
	local id = holder:GetAttribute(STALE_ATTRIBUTE)
	if type(id) == "string" then
		pcall(function()
			if self.service:IsRecordingInProgress(id) then
				self.service:FinishRecording(id, Enum.FinishRecordingOperation.Cancel)
			end
		end)
		holder:SetAttribute(STALE_ATTRIBUTE, nil)
	end
end

function History.destroy(self: History)
	if self._open then
		finish(self, self._open, Enum.FinishRecordingOperation.Cancel)
	end
	for _, c in self._connections do
		c:Disconnect()
	end
	table.clear(self._connections)
	self.undone:DisconnectAll()
	self.redone:DisconnectAll()
end

return History
