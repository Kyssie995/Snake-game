--!strict
--[[
	Pool — idle BuiltEffect copies kept for reuse, per key (normally Compiler.key of the compiled effect). See
	docs/MODULE_CONTRACTS.md §18.

	  Pool.acquire(key) -> BuiltEffect?            an idle copy (container parented to nil; the caller parents it)
	  Pool.release(key, built) -> boolean          true: reset() + parented to nil + kept; false: not taken (pool full,
	                                               copy destroyed, already pooled, reset failed) — the caller then
	                                               destroys it. The pool never destroys what it did not take.
	  Pool.prewarm(key, factory, count) -> number  builds copies with factory() until `count` are idle; raises that
	                                               key's capacity to `count` if needed; returns how many it built
	  Pool.clear(key?)                             destroys the idle copies of one key (or all keys) and forgets
	                                               raised capacities
	  Pool.setCapacity(n, key?)                    idle copies kept per key (default 2; whole number >= 0); with a
	                                               key only that key. Excess idle copies are destroyed.
	  Pool.capacity(key?) / Pool.count(key?)       capacity / number of idle copies (all keys without a key)

	Copies are reset() when they are released (Builder: every controller restores its freshly-built state and
	clears particles), so acquire() is cheap and an acquired copy looks exactly like a fresh build. Released
	copies are parented to nil, so they neither render nor replicate (and are never streamed). acquire() is LIFO
	(the most recently released copy has the warmest caches) and skips copies destroyed while pooled.
]]

local Builder = require(script.Parent.Builder)

type BuiltEffect = Builder.BuiltEffect

local Pool = {}

local DEFAULT_CAPACITY = 2

local idle: { [string]: { BuiltEffect } } = {}
local pooled: { [BuiltEffect]: string } = {}
local keyCapacity: { [string]: number } = {}
local defaultCapacity = DEFAULT_CAPACITY

Pool.DEFAULT_CAPACITY = DEFAULT_CAPACITY

local function checkKey(fn: string, key: any)
	if type(key) ~= "string" then
		error("Pool." .. fn .. ": key must be a string, got " .. typeof(key), 3)
	end
end

local function capacityOf(key: string): number
	return keyCapacity[key] or defaultCapacity
end

local function destroyCopy(built: BuiltEffect)
	pooled[built] = nil
	local ok, err = pcall(built.destroy :: any, built)
	if not ok then
		warn("[AstraVFX] destroying a pooled effect copy failed: " .. tostring(err))
	end
end

local function trim(key: string)
	local list = idle[key]
	if list == nil then
		return
	end
	local limit = capacityOf(key)
	while #list > limit do
		destroyCopy(table.remove(list, 1) :: BuiltEffect)
	end
	if #list == 0 then
		idle[key] = nil
	end
end

-- Takes an idle copy for `key`, or nil.
function Pool.acquire(key: string): BuiltEffect?
	checkKey("acquire", key)
	local list = idle[key]
	if list == nil then
		return nil
	end
	while #list > 0 do
		local built = table.remove(list) :: BuiltEffect
		pooled[built] = nil
		if not built.destroyed then
			if #list == 0 then
				idle[key] = nil
			end
			return built
		end
	end
	idle[key] = nil
	return nil
end

-- Resets and keeps `built` for `key`; false when it was not taken (see header).
function Pool.release(key: string, built: BuiltEffect): boolean
	checkKey("release", key)
	if type(built) ~= "table" or type((built :: any).reset) ~= "function" then
		error("Pool.release: expected a BuiltEffect, got " .. typeof(built), 2)
	end
	if built.destroyed or pooled[built] ~= nil then
		return false
	end
	local list = idle[key]
	if #(list or {}) >= capacityOf(key) then
		return false
	end
	local ok, err = pcall(function()
		built:reset()
		built.container.Parent = nil
	end)
	if not ok then
		warn("[AstraVFX] resetting an effect copy for the pool failed: " .. tostring(err))
		return false
	end
	if list == nil then
		list = {}
		idle[key] = list
	end
	table.insert(list :: { BuiltEffect }, built)
	pooled[built] = key
	return true
end

-- Builds copies with `factory` until `count` are idle for `key`. Returns the number of copies built.
function Pool.prewarm(key: string, factory: () -> BuiltEffect, count: number): number
	checkKey("prewarm", key)
	if type(factory) ~= "function" then
		error("Pool.prewarm: factory must be a function, got " .. typeof(factory), 2)
	end
	if type(count) ~= "number" or count ~= count or count < 0 or count % 1 ~= 0 then
		error("Pool.prewarm: count must be a whole number >= 0, got " .. tostring(count), 2)
	end
	if count > capacityOf(key) then
		keyCapacity[key] = count
	end
	local built = 0
	local list = idle[key]
	while #(list or {}) < count do
		local copy = factory()
		if type(copy) ~= "table" or type((copy :: any).reset) ~= "function" then
			error("Pool.prewarm: factory must return a BuiltEffect, got " .. typeof(copy), 2)
		end
		copy.container.Parent = nil
		if list == nil then
			list = {}
			idle[key] = list
		end
		table.insert(list :: { BuiltEffect }, copy)
		pooled[copy] = key
		built += 1
	end
	return built
end

-- Destroys the idle copies of `key` (or of every key) and forgets raised capacities.
function Pool.clear(key: string?)
	if key ~= nil then
		checkKey("clear", key)
		local list = idle[key]
		idle[key] = nil
		keyCapacity[key] = nil
		if list then
			for _, built in list do
				destroyCopy(built)
			end
		end
		return
	end
	local all = idle
	idle = {}
	table.clear(keyCapacity)
	for _, list in all do
		for _, built in list do
			destroyCopy(built)
		end
	end
end

-- Idle copies kept per key (default 2), or for one key only.
function Pool.setCapacity(n: number, key: string?)
	if type(n) ~= "number" or n ~= n or n < 0 or n % 1 ~= 0 then
		error("Pool.setCapacity: capacity must be a whole number >= 0, got " .. tostring(n), 2)
	end
	if key ~= nil then
		checkKey("setCapacity", key)
		keyCapacity[key] = n
		trim(key)
		return
	end
	defaultCapacity = n
	local keys: { string } = {}
	for k in idle do
		table.insert(keys, k)
	end
	for _, k in keys do
		trim(k)
	end
end

function Pool.capacity(key: string?): number
	if key ~= nil then
		return capacityOf(key)
	end
	return defaultCapacity
end

-- Number of idle copies for `key` (or in total).
function Pool.count(key: string?): number
	if key ~= nil then
		local list = idle[key]
		return if list then #list else 0
	end
	local n = 0
	for _, list in idle do
		n += #list
	end
	return n
end

return Pool
