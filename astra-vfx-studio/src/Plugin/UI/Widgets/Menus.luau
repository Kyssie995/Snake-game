--!strict
--[[
	Menus — cached Studio context menus (PluginMenu) built from plain item tables.

		local menus = Menus.new(plugin)
		task.spawn(function()                       -- ShowAsync yields: never call show() on a UI event thread
			local choice = menus:show("explorer_row", {
				{ id = "rename", text = "Umbenennen" },
				{ id = "duplicate", text = "Duplizieren" },
				{ separator = true },
				{ id = "add", text = "Hinzufügen", items = {           -- submenu
					{ id = "add_particles", text = "Partikel" },
				} },
				{ id = "delete", text = "Löschen", disabled = not canDelete }, -- disabled entries are left out
			})
			if choice == "rename" then ... end
		end)
		menus:open("explorer_row", items, function(choice) ... end)   -- same, spawned for you
		menus:destroy()                                                -- destroys all menus and actions

	One PluginMenu is created per menuId (plugin:CreatePluginMenu) and rebuilt with Clear/AddNewAction/AddMenu/
	AddSeparator only when the item list changed. Action ids must be unique per plugin, so they are
	"<menuId>/<itemId>"; ShowAsync's PluginAction is mapped back to the item id (nil when dismissed).
	Studio menus have no disabled or checked states (docs/research/api-studio-plugin.md T6): disabled items are
	omitted and `checked = true` prefixes "✓ ". Item `onActivate` callbacks run after the choice.
]]

local Menus = {}
Menus.__index = Menus

export type MenuItem = {
	id: string?,
	text: string?,
	icon: string?,
	items: { MenuItem }?, -- submenu
	separator: boolean?,
	disabled: boolean?,
	checked: boolean?,
	onActivate: (() -> ())?,
}

type CachedMenu = {
	menu: any, -- PluginMenu
	signature: string,
	actions: { [string]: MenuItem }, -- ActionId -> item
	created: { any }, -- actions and submenus created for the current build
}

type MenusData = {
	plugin: any,
	_menus: { [string]: CachedMenu },
	_showing: { [string]: boolean },
	_destroyed: boolean,
}

export type Menus = typeof(setmetatable({} :: MenusData, Menus))

function Menus.new(plugin: any): Menus
	assert(plugin ~= nil, "Menus.new: plugin is required")
	return setmetatable({
		plugin = plugin,
		_menus = {},
		_showing = {},
		_destroyed = false,
	}, Menus)
end

-- Stable text form of an item list (detects changes between show() calls).
local function signature(items: { MenuItem }): string
	local parts = {}
	for _, item in items do
		if item.separator then
			table.insert(parts, "|")
		elseif not item.disabled then
			local entry = string.format(
				"%s\0%s\0%s\0%s",
				item.id or "",
				item.text or "",
				item.icon or "",
				if item.checked then "1" else "0"
			)
			if item.items then
				entry ..= "\0[" .. signature(item.items :: { MenuItem }) .. "]"
			end
			table.insert(parts, entry)
		end
	end
	return table.concat(parts, "\1")
end
Menus.signature = signature

local function destroyObject(obj: any)
	pcall(function()
		obj:Destroy()
	end)
end

-- Drops trailing/leading/double separators that remain after leaving out disabled entries.
local function visibleItems(items: { MenuItem }): { MenuItem }
	local out: { MenuItem } = {}
	for _, item in items do
		if item.separator then
			if #out > 0 and not out[#out].separator then
				table.insert(out, item)
			end
		elseif not item.disabled then
			table.insert(out, item)
		end
	end
	while #out > 0 and out[#out].separator do
		table.remove(out)
	end
	return out
end

function Menus._fill(self: Menus, cached: CachedMenu, menu: any, items: { MenuItem }, prefix: string)
	for _, item in visibleItems(items) do
		if item.separator then
			menu:AddSeparator()
		elseif item.items then
			local subId = prefix .. "/" .. (item.id or item.text or "sub")
			local sub = self.plugin:CreatePluginMenu(subId, item.text or "", item.icon or "")
			table.insert(cached.created, sub)
			self:_fill(cached, sub, item.items :: { MenuItem }, subId)
			menu:AddMenu(sub)
		else
			assert(item.id, "Menus: menu items need an id (or separator = true)")
			local actionId = prefix .. "/" .. (item.id :: string)
			local text = item.text or (item.id :: string)
			if item.checked then
				text = "✓ " .. text
			end
			local action = menu:AddNewAction(actionId, text, item.icon or "")
			table.insert(cached.created, action)
			cached.actions[actionId] = item
		end
	end
end

-- Points the cached ActionIds at the current item tables (their onActivate closures may be new).
local function remap(cached: CachedMenu, items: { MenuItem }, prefix: string)
	for _, item in visibleItems(items) do
		if item.items then
			remap(cached, item.items :: { MenuItem }, prefix .. "/" .. (item.id or item.text or "sub"))
		elseif not item.separator and item.id then
			cached.actions[prefix .. "/" .. (item.id :: string)] = item
		end
	end
end

-- Returns the cached PluginMenu for menuId, (re)built for `items`.
function Menus.build(self: Menus, menuId: string, items: { MenuItem }): any
	assert(not self._destroyed, "Menus: used after destroy()")
	local sig = signature(items)
	local existing = self._menus[menuId]
	if existing and existing.signature == sig then
		remap(existing, items, menuId)
		return existing.menu
	end
	local c: CachedMenu
	if existing then
		c = existing
	else
		c = {
			menu = self.plugin:CreatePluginMenu(menuId, "", ""),
			signature = "",
			actions = {},
			created = {},
		}
		self._menus[menuId] = c
	end
	c.menu:Clear()
	for i = #c.created, 1, -1 do
		destroyObject(c.created[i])
	end
	table.clear(c.created)
	table.clear(c.actions)
	self:_fill(c, c.menu, items, menuId)
	c.signature = sig
	return c.menu
end

-- Shows the menu at the mouse and returns the chosen item id (nil when dismissed). YIELDS (ShowAsync): call it
-- from task.spawn. A second show() of the same menu while it is open returns nil immediately.
function Menus.show(self: Menus, menuId: string, items: { MenuItem }): string?
	if self._destroyed or self._showing[menuId] then
		return nil
	end
	local menu = self:build(menuId, items)
	local cached = self._menus[menuId]
	self._showing[menuId] = true
	local ok, action = pcall(function()
		return menu:ShowAsync()
	end)
	self._showing[menuId] = nil
	if not ok then
		warn("[AstraVFX] menu " .. menuId .. " failed: " .. tostring(action))
		return nil
	end
	if action == nil or self._destroyed then
		return nil
	end
	local actionId = (action :: any).ActionId
	local item = if cached then cached.actions[actionId] else nil
	if item == nil then
		return nil
	end
	if item.onActivate then
		(item.onActivate :: () -> ())()
	end
	return item.id
end

-- Non-blocking show(): runs in task.spawn and calls onChoose(id) when an entry was picked.
function Menus.open(self: Menus, menuId: string, items: { MenuItem }, onChoose: ((id: string) -> ())?)
	task.spawn(function()
		local choice = self:show(menuId, items)
		if choice ~= nil and onChoose then
			onChoose(choice)
		end
	end)
end

function Menus.isShowing(self: Menus, menuId: string): boolean
	return self._showing[menuId] == true
end

-- Destroys every menu and action created so far.
function Menus.destroy(self: Menus)
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, cached in self._menus do
		pcall(function()
			cached.menu:Clear()
		end)
		for i = #cached.created, 1, -1 do
			destroyObject(cached.created[i])
		end
		destroyObject(cached.menu)
	end
	table.clear(self._menus)
end

return Menus
