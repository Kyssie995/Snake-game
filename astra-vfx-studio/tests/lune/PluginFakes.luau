--[[
	PluginFakes (Lune only)

	Minimal stand-ins for the Studio-only objects the plugin uses (Plugin, DockWidgetPluginGui, PluginToolbar,
	PluginAction, PluginMenu, ChangeHistoryService behaviour), so UI panels and plugin modules can be CONSTRUCTED and
	driven programmatically in tests. Real GUI instances (Frame, TextButton, ...) are genuine Lune Instances, so
	property names/values are still validated against the reflection database.

	What this does NOT prove: rendering, layout, real mouse/keyboard input, docking behaviour.
]]

local roblox = require("@lune/roblox")
local Fakes = require("./Fakes")

local Instance = roblox.Instance

local PluginFakes = {}

function PluginFakes.newWidget(id: string, title: string?)
	-- A ScreenGui is the closest creatable LayerCollector; panels parent their root frames into widget.gui.
	local gui = Instance.new("ScreenGui")
	gui.Name = id
	local widget = {
		Name = id,
		Title = title or id,
		Enabled = true,
		gui = gui,
		mouse = roblox.Vector2.new(0, 0),
		WindowFocused = Fakes.newSignal("WindowFocused"),
		WindowFocusReleased = Fakes.newSignal("WindowFocusReleased"),
		PluginDragEntered = Fakes.newSignal("PluginDragEntered"),
		PluginDragMoved = Fakes.newSignal("PluginDragMoved"),
		PluginDragLeft = Fakes.newSignal("PluginDragLeft"),
		PluginDragDropped = Fakes.newSignal("PluginDragDropped"),
		enabledChanged = Fakes.newSignal("Enabled"),
	}
	function widget:GetRelativeMousePosition()
		return self.mouse
	end
	function widget:BindToClose(_fn) end
	function widget:GetPropertyChangedSignal(prop: string)
		assert(prop == "Enabled", "fake widget only supports Enabled changes")
		return self.enabledChanged
	end
	function widget:Destroy()
		gui:Destroy()
	end
	return widget
end

local function newAction(id: string, text: string)
	return { ActionId = id, Text = text, Triggered = Fakes.newSignal("Triggered") }
end

local function newMenu(id: string, title: string?)
	local menu = { id = id, Title = title or "", items = {}, nextChoice = nil }
	function menu:AddNewAction(actionId: string, text: string, _icon: string?)
		local action = newAction(actionId, text)
		table.insert(self.items, { kind = "action", action = action })
		return action
	end
	function menu:AddAction(action)
		table.insert(self.items, { kind = "action", action = action })
	end
	function menu:AddMenu(sub)
		table.insert(self.items, { kind = "menu", menu = sub })
	end
	function menu:AddSeparator()
		table.insert(self.items, { kind = "separator" })
	end
	function menu:Clear()
		table.clear(self.items)
	end
	-- Tests set menu.nextChoice = "<actionId>" to simulate the user picking an entry.
	function menu:ShowAsync()
		local choice = self.nextChoice
		self.nextChoice = nil
		if choice == nil then
			return nil
		end
		local function find(m)
			for _, item in m.items do
				if item.kind == "action" and item.action.ActionId == choice then
					return item.action
				elseif item.kind == "menu" then
					local found = find(item.menu)
					if found then
						return found
					end
				end
			end
			return nil
		end
		return find(self)
	end
	function menu:Destroy() end
	return menu
end

function PluginFakes.newPlugin()
	local plugin = {
		settings = {},
		widgets = {},
		toolbars = {},
		actions = {},
		menus = {},
		Unloading = Fakes.newSignal("Unloading"),
		savedSelections = {},
		mouse = { Icon = "" },
	}
	function plugin:GetSetting(key: string)
		return self.settings[key]
	end
	function plugin:SetSetting(key: string, value: any)
		assert(not string.find(key, "[%.\"\\\n]"), "invalid plugin setting key: " .. key)
		self.settings[key] = value
	end
	function plugin:CreateToolbar(name: string)
		local toolbar = { Name = name, buttons = {} }
		function toolbar:CreateButton(id: string, tooltip: string, icon: string, text: string?)
			local button = {
				Name = id,
				Tooltip = tooltip,
				Icon = icon,
				Text = text or id,
				Enabled = true,
				ClickableWhenViewportHidden = false,
				active = false,
				Click = Fakes.newSignal("Click"),
			}
			function button:SetActive(active: boolean)
				self.active = active
			end
			self.buttons[id] = button
			return button
		end
		table.insert(self.toolbars, toolbar)
		return toolbar
	end
	function plugin:CreateDockWidgetPluginGuiAsync(id: string, _info)
		assert(self.widgets[id] == nil, "duplicate widget id " .. id)
		local widget = PluginFakes.newWidget(id)
		self.widgets[id] = widget
		return widget
	end
	function plugin:CreatePluginAction(id: string, text: string, _tip: string, _icon: string?, _allowBinding: boolean?)
		local action = newAction(id, text)
		self.actions[id] = action
		return action
	end
	function plugin:CreatePluginMenu(id: string, title: string?, _icon: string?)
		local menu = newMenu(id, title)
		self.menus[id] = menu
		return menu
	end
	function plugin:GetMouse()
		return self.mouse
	end
	function plugin:PromptForExistingAssetIdAsync(_assetType: string)
		return 0
	end
	function plugin:PromptSaveSelectionAsync(name: string?)
		table.insert(self.savedSelections, name or "")
		return true
	end
	return plugin
end

-- DockWidgetPluginGuiInfo.new stand-in (positional arguments kept for inspection).
PluginFakes.DockWidgetPluginGuiInfo = {
	new = function(...)
		return { args = table.pack(...) }
	end,
}

-- TweenInfo stand-in (UI code may build TweenInfos; TweenService itself is not faked).
PluginFakes.TweenInfo = {
	new = function(...)
		return { args = table.pack(...) }
	end,
}

return PluginFakes
