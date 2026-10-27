--!strict
-- History (ChangeHistoryService wrapper) and Settings, tested against fakes.
return function(T: any, use: (string) -> any, ctx: any)
	local History = use("Plugin.Studio.History")
	local Settings = use("Plugin.Studio.Settings")
	local Signal = use("AstraVFX.Core.Signal")

	-- Fake ChangeHistoryService with the documented semantics (one open recording per plugin).
	local function fakeService()
		local svc: any = {
			open = nil :: string?,
			counter = 0,
			log = {} :: { string },
			OnUndo = Signal.new(),
			OnRedo = Signal.new(),
			undoable = 0,
			blocked = false,
		}
		function svc:TryBeginRecording(name: string, _display: string?)
			if self.open or self.blocked then
				return nil
			end
			self.counter += 1
			self.open = name .. "#" .. self.counter
			return self.open
		end
		function svc:FinishRecording(id: string, op: any)
			assert(id == self.open, "finishing unknown recording")
			table.insert(self.log, op.Name)
			if op == Enum.FinishRecordingOperation.Commit then
				self.undoable += 1
			end
			self.open = nil
		end
		function svc:IsRecordingInProgress(id: string?)
			return self.open ~= nil and (id == nil or id == self.open)
		end
		function svc:Undo()
			if self.undoable == 0 then
				error("nothing to undo")
			end
			self.undoable -= 1
			self.OnUndo:Fire("x")
		end
		function svc:Redo()
			error("nothing to redo")
		end
		function svc:GetCanUndo()
			return self.undoable > 0
		end
		function svc:GetCanRedo()
			return false
		end
		return svc
	end

	T.describe("History", function()
		T.it("wraps a change in one committed recording", function()
			local svc = fakeService()
			local h = History.new(svc)
			local ran = false
			local ok = h:record("Set Rate", function()
				ran = true
			end)
			T.expect(ok).toBe(true)
			T.expect(ran).toBe(true)
			T.expect(svc.log).toEqual({ "Commit" })
			T.expect(svc.open).toBeNil()
		end)
		T.it("cancels the recording when the change fails", function()
			local svc = fakeService()
			local h = History.new(svc)
			local ok, err = h:record("Broken", function()
				error("bad edit")
			end)
			T.expect(ok).toBe(false)
			T.expect(err).toContain("bad edit")
			T.expect(svc.log).toEqual({ "Cancel" })
		end)
		T.it("still applies the change when no recording can be opened", function()
			local svc = fakeService()
			svc.blocked = true
			local h = History.new(svc)
			local ran = false
			local ok, reason = h:record("Playtest edit", function()
				ran = true
			end)
			T.expect(ran).toBe(true)
			T.expect(ok).toBe(false)
			T.expect(reason).toBe("no-recording")
		end)
		T.it("undo/redo never throw and forward OnUndo", function()
			local svc = fakeService()
			local h = History.new(svc)
			local undone = 0
			h.undone:Connect(function()
				undone += 1
			end)
			T.expect(h:undo()).toBe(false)
			h:record("A", function() end)
			T.expect(h:canUndo()).toBe(true)
			T.expect(h:undo()).toBe(true)
			T.expect(undone).toBe(1)
			T.expect(h:redo()).toBe(false)
		end)
		T.it("cancels a stale recording recorded on the holder", function()
			local svc = fakeService()
			local holder = Instance.new("Folder")
			local id = svc:TryBeginRecording("Old")
			holder:SetAttribute("AstraOpenRecording", id)
			local h = History.new(svc, holder)
			h:cancelStale()
			T.expect(svc.open).toBeNil()
			T.expect(svc.log).toEqual({ "Cancel" })
			T.expect(holder:GetAttribute("AstraOpenRecording")).toBeNil()
		end)
	end)

	T.describe("Settings", function()
		T.itIf(ctx.environment == "lune", "round-trips values with safe keys", function()
			local plugin = ctx.plugin.newPlugin()
			local s = Settings.new(plugin)
			s:set("bridgeToken", 'a"b\\c')
			s:set("previewDistance", 40)
			s:set("recentDocuments", { "fire", "ice" })
			local fresh = Settings.new(plugin)
			T.expect(fresh:get("bridgeToken")).toBe('a"b\\c')
			T.expect(fresh:get("previewDistance")).toBe(40)
			T.expect(fresh:get("recentDocuments")).toEqual({ "fire", "ice" })
			T.expect(fresh:get("loop")).toBe(true) -- default
			for key, value in plugin.settings do
				T.expect(string.find(key, '[%."\\]')).toBeNil()
				if type(value) == "string" then
					T.expect(string.find(value, "\\", 1, true)).toBeNil()
				end
			end
		end)
		T.it("rejects unsafe keys", function()
			local s = Settings.new({})
			T.expect(function()
				s:get("bad.key")
			end).toThrow("invalid key")
		end)
	end)
end
