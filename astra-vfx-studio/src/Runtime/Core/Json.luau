--!strict
--[[
	Json — canonical JSON encoder and strict RFC 8259 parser (pure Luau, no HttpService).

	The encoder produces byte-for-byte reproducible output (diff-friendly effect files, stable exports):
	object keys follow a fixed priority list (default Constants.KEY_ORDER) and then byte-wise alphabetical
	order, numbers are formatted with integer arithmetic only, and the pretty layout is fully specified.

	Interpretation notes (where docs/MODULE_CONTRACTS.md §5 leaves room):
	  * Numbers: |x| < 2^53 and integral → plain digits. Other finite numbers below 2^53 are rounded half away
	    from zero to 6 decimals (integer arithmetic, no printf %f, so every platform prints the same bytes) and
	    trailing zeros are stripped; a result of zero prints "0" (never "-0"). Every double with |x| >= 2^53 is an
	    integer; those use Luau's shortest round-trip form (tostring, e.g. 1152921504606847000 or 1e+21), which is
	    Luau's own platform-independent printer and decodes back to the same double.
	  * Strings must be valid UTF-8 (encode errors otherwise; decode reports an error) so that the round trip
	    holds. Escaped: '"', '\', U+0000..U+001F (\b \f \n \r \t, others \u00xx in lowercase hex) and DEL (\u007f).
	    '/' and non-ASCII characters are written as-is.
	  * Json.EMPTY_OBJECT and Json.NULL are frozen sentinel tables (compare by identity). decode("{}") — and an
	    object whose members are all null — returns Json.EMPTY_OBJECT, so encode(decode(s)) stays canonical.
	    decode("[]") returns a fresh empty table. A top-level `null` decodes to Json.NULL.
	  * nil cannot be encoded (use Json.NULL). Tables are classified by their raw keys (metatables ignored):
	    no keys → "[]"; keys exactly 1..n → array; only string keys → object; anything else → error.
	    Cyclic references and nesting deeper than 200 containers are errors, so everything encode() accepts can
	    be decoded again.
	  * Pretty layout: 2-space indent, `"key": value`, empty containers as [] / {}, arrays of at most 8 scalars
	    (string/number/boolean/null) on one line as `[1, 2, 3]`, every other non-empty array and object with one
	    element per line. No trailing newline (Exporter adds one).
	  * Decode is strict RFC 8259: no comments, trailing commas, single quotes, NaN/Infinity, leading zeros or
	    '+' signs; duplicate object keys are rejected; numbers that overflow to ±inf are rejected; a leading
	    UTF-8 BOM is skipped. Errors are "line L, column C: message" with 1-based line and column; columns count
	    Unicode code points (bytes if the line is not valid UTF-8); the BOM is not counted. decode never throws.
]]

local Constants = require(script.Parent.Constants)

-- Builtins as locals: Luau still compiles these never-reassigned aliases as builtin fast calls, and they avoid
-- per-call global lookups when the module runs in a custom environment (e.g. the Lune test loader).
local type, next, typeof, tostring, tonumber = type, next, typeof, tostring, tonumber
local error, pcall, setmetatable, getmetatable = error, pcall, setmetatable, getmetatable
local byte, char, find, sub, match = string.byte, string.char, string.find, string.sub, string.match
local format, gsub, pack = string.format, string.gsub, string.pack
local concat, sort, insert, create = table.concat, table.sort, table.insert, table.create
local floor, abs, HUGE = math.floor, math.abs, math.huge
local utf8len, utf8char, utf8codepoint = utf8.len, utf8.char, utf8.codepoint

local Json = {}

export type EncodeOptions = {
	pretty: boolean?, -- default true
	keyOrder: { string }?, -- default Constants.KEY_ORDER; keys not listed follow in byte-wise alphabetical order
}

local MAX_DEPTH = 200
local TWO_POW_53 = 2 ^ 53

-- Sentinels -----------------------------------------------------------------------------------------------------

local EMPTY_OBJECT = table.freeze(setmetatable({}, {
	__tostring = function()
		return "Json.EMPTY_OBJECT"
	end,
}))

local NULL = table.freeze(setmetatable({}, {
	__tostring = function()
		return "Json.NULL"
	end,
}))

-- Encodes as `{}` (a plain empty table encodes as `[]`). Frozen; compare by identity.
Json.EMPTY_OBJECT = EMPTY_OBJECT :: any
-- Encodes as `null`. decode() yields it for null array elements (and a top-level null); null members are omitted.
Json.NULL = NULL :: any
-- Maximum container nesting accepted by encode and decode.
Json.MAX_DEPTH = MAX_DEPTH

-- Helpers ---------------------------------------------------------------------------------------------------------

local ESCAPES: { [string]: string } = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\b"] = "\\b",
	["\f"] = "\\f",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
	["\127"] = "\\u007f",
}
for code = 0, 31 do
	local c = char(code)
	if ESCAPES[c] == nil then
		ESCAPES[c] = format("\\u%04x", code)
	end
end
local ESCAPE_PATTERN = '[%z\1-\31"\\\127]'

-- Bytes that need a closer look: control characters, '"', '\', DEL and every non-ASCII byte.
local NON_PLAIN_PATTERN = '[%z\1-\31"\\\127-\255]'

-- "\n" .. indentation and ",\n" .. indentation per nesting level (pretty layout, 2 spaces per level).
local LINE_INDENTS: { [number]: string } = {}
local COMMA_LINE_INDENTS: { [number]: string } = {}
local function lineIndent(level: number): string
	local s = LINE_INDENTS[level]
	if s == nil then
		s = "\n" .. string.rep("  ", level)
		LINE_INDENTS[level] = s
	end
	return s
end
local function commaLineIndent(level: number): string
	local s = COMMA_LINE_INDENTS[level]
	if s == nil then
		s = ",\n" .. string.rep("  ", level)
		COMMA_LINE_INDENTS[level] = s
	end
	return s
end

local function buildRank(order: { string }): { [string]: number }
	local rank: { [string]: number } = {}
	for i, key in order do
		if type(key) ~= "string" then
			error("Json.encode: options.keyOrder must contain only strings", 3)
		end
		if rank[key] == nil then
			rank[key] = i
		end
	end
	return rank
end

local DEFAULT_RANK = buildRank(Constants.KEY_ORDER)

-- Formats a number canonically, or returns nil for NaN / ±inf.
local function formatNumber(x: number): string?
	if x ~= x or x == HUGE or x == -HUGE then
		return nil
	end
	if x == 0 then
		return "0" -- also -0
	end
	local a = abs(x)
	if a >= TWO_POW_53 then
		return tostring(x) -- integral; Luau's shortest round-trip representation
	end
	local whole = floor(a)
	if whole == a then
		return format("%d", x)
	end
	-- a - whole is exact in binary floating point; round the fraction to 6 decimals (half away from zero).
	local micros = floor((a - whole) * 1e6 + 0.5)
	if micros >= 1000000 then
		whole += 1
		micros = 0
	end
	local sign = if x < 0 then "-" else ""
	if micros == 0 then
		if whole == 0 then
			return "0"
		end
		return sign .. format("%d", whole)
	end
	local digits = format("%06d", micros)
	digits = (gsub(digits, "0+$", ""))
	return sign .. format("%d", whole) .. "." .. digits
end

local function isIdentifier(key: string): boolean
	return find(key, "^[%a_][%w_]*$") ~= nil
end

local function formatPath(path: { any }, length: number): string
	if length == 0 then
		return "(root)"
	end
	local parts = create(length)
	for i = 1, length do
		local key = path[i]
		if type(key) == "number" then
			parts[i] = "[" .. tostring(key) .. "]"
		elseif isIdentifier(key) then
			parts[i] = if i == 1 then key else "." .. key
		else
			parts[i] = format("[%q]", key)
		end
	end
	return concat(parts)
end

-- Public API ------------------------------------------------------------------------------------------------------

-- True for tables whose raw keys are exactly 1..n (n >= 0, so a plain empty table counts); false for
-- Json.EMPTY_OBJECT, Json.NULL, objects, sparse/mixed tables and non-tables.
function Json.isArray(t: any): boolean
	if type(t) ~= "table" or t == EMPTY_OBJECT or t == NULL then
		return false
	end
	local count, maxIndex = 0, 0
	for key in next, t do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false
		end
		count += 1
		if key > maxIndex then
			maxIndex = key
		end
	end
	return count == maxIndex
end

-- Encodes a value as canonical JSON. Errors (with the path of the offending value) on unsupported input.
function Json.encode(value: any, options: EncodeOptions?): string
	if options ~= nil and type(options) ~= "table" then
		error("Json.encode: options must be a table or nil", 2)
	end
	local o: EncodeOptions = options or {}
	local pretty: boolean = true
	if o.pretty ~= nil then
		if type(o.pretty) ~= "boolean" then
			error("Json.encode: options.pretty must be a boolean", 2)
		end
		pretty = o.pretty
	end
	local rank = DEFAULT_RANK
	if o.keyOrder ~= nil then
		if type(o.keyOrder) ~= "table" then
			error("Json.encode: options.keyOrder must be an array of strings", 2)
		end
		rank = buildRank(o.keyOrder)
	end

	local out: { string } = {}
	local n = 0
	local path: { any } = {}
	local pathLength = 0
	local visiting: { [any]: boolean } = {}
	-- Per-call caches: effect documents repeat the same keys, strings and numbers many times.
	local quotedStrings: { [string]: string } = {}
	local formattedNumbers: { [number]: string } = {}
	local memberPrefixes: { [string]: string } = {}
	local sortKeyOf: { [string]: string } = {}
	local keyOfSortKey: { [string]: string } = {}
	local colon = if pretty then ": " else ":"

	-- Cast to a never-returning type: the old type solver cannot infer that error() does not return.
	local fail: (message: string) -> never = function(message: string)
		error("Json.encode: " .. message .. " at " .. formatPath(path, pathLength), 0)
	end :: any

	local function quote(s: string): string
		local quoted = quotedStrings[s]
		if quoted ~= nil then
			return quoted
		end
		if find(s, NON_PLAIN_PATTERN) == nil then
			quoted = '"' .. s .. '"' -- printable ASCII only: nothing to validate or escape
		else
			if utf8len(s) == nil then
				fail("string is not valid UTF-8")
			end
			quoted = '"' .. (gsub(s, ESCAPE_PATTERN, ESCAPES)) .. '"'
		end
		quotedStrings[s] = quoted
		return quoted
	end

	local function number(x: number): string
		local formatted = formatNumber(x)
		if formatted == nil then
			fail("cannot encode non-finite number " .. tostring(x))
		end
		formattedNumbers[x] = formatted :: string
		return formatted :: string
	end

	-- Byte-wise sortable key: ranked keys sort by rank, before all others, which sort by their own bytes.
	local function sortKey(key: string): string
		local sk = sortKeyOf[key]
		if sk == nil then
			local r = rank[key]
			sk = if r ~= nil then "\0" .. pack(">I4", r) else "\1" .. key
			sortKeyOf[key] = sk
			keyOfSortKey[sk] = key
		end
		return sk
	end

	local function memberPrefix(key: string): string
		local prefix = quote(key) .. colon
		memberPrefixes[key] = prefix
		return prefix
	end

	local writeTable: (t: { [any]: any }, depth: number) -> ()

	local function writeValue(v: any, depth: number)
		local vt = type(v)
		if vt == "string" then
			n += 1
			out[n] = quotedStrings[v] or quote(v)
		elseif vt == "number" then
			n += 1
			out[n] = formattedNumbers[v] or number(v)
		elseif vt == "boolean" then
			n += 1
			out[n] = if v then "true" else "false"
		elseif v == NULL then
			n += 1
			out[n] = "null"
		elseif v == EMPTY_OBJECT then
			-- `{}` is a container level too (decode counts it), so the depth limit applies to it.
			if depth + 1 > MAX_DEPTH then
				fail("nesting deeper than " .. MAX_DEPTH .. " levels")
			end
			n += 1
			out[n] = "{}"
		elseif vt == "table" then
			writeTable(v, depth + 1)
		elseif vt == "nil" then
			fail("cannot encode nil (use Json.NULL)")
		else
			fail("cannot encode a value of type " .. typeof(v))
		end
	end

	writeTable = function(t: { [any]: any }, depth: number)
		if depth > MAX_DEPTH then
			fail("nesting deeper than " .. MAX_DEPTH .. " levels")
		end
		if visiting[t] then
			fail("cyclic table reference")
		end
		-- Classify by raw keys (collecting sortable object keys on the way).
		local count, maxIndex = 0, 0
		local sortKeys: { string }? = nil
		for key in next, t do
			count += 1
			local kt = type(key)
			if kt == "string" then
				local sk = sortKeyOf[key] or sortKey(key)
				if sortKeys == nil then
					sortKeys = { sk }
				else
					sortKeys[#sortKeys + 1] = sk
				end
			elseif kt == "number" and key >= 1 and key % 1 == 0 then
				if key > maxIndex then
					maxIndex = key
				end
			else
				fail("invalid table key " .. tostring(key) .. " (" .. typeof(key) .. "); object keys must be strings")
			end
		end
		if count == 0 then
			n += 1
			out[n] = "[]"
			return
		end
		if sortKeys ~= nil and maxIndex > 0 then
			fail("mixed table (array indices and string keys)")
		end
		if sortKeys == nil and maxIndex ~= count then
			fail("sparse array (" .. count .. " elements but highest index " .. maxIndex .. ")")
		end
		visiting[t] = true
		pathLength += 1
		local slot = pathLength
		if sortKeys == nil then
			local inline = not pretty
			if pretty and count <= 8 then
				inline = true
				for i = 1, count do
					local v = t[i]
					local vt = type(v)
					if vt ~= "string" and vt ~= "number" and vt ~= "boolean" and v ~= NULL then
						inline = false
						break
					end
				end
			end
			local first, separator, close
			if inline then
				first, separator, close = "[", if pretty then ", " else ",", "]"
			else
				first, separator, close = "[" .. lineIndent(depth), commaLineIndent(depth), lineIndent(depth - 1) .. "]"
			end
			for i = 1, count do
				path[slot] = i
				n += 1
				out[n] = if i == 1 then first else separator
				writeValue(t[i], depth)
			end
			n += 1
			out[n] = close
		else
			local keys: { string } = sortKeys
			if count > 1 then
				sort(keys)
			end
			local first, separator, close
			if pretty then
				first, separator, close = "{" .. lineIndent(depth), commaLineIndent(depth), lineIndent(depth - 1) .. "}"
			else
				first, separator, close = "{", ",", "}"
			end
			for i = 1, count do
				local key = keyOfSortKey[keys[i]]
				path[slot] = key
				n += 2
				out[n - 1] = if i == 1 then first else separator
				out[n] = memberPrefixes[key] or memberPrefix(key)
				writeValue(t[key], depth)
			end
			n += 1
			out[n] = close
		end
		pathLength -= 1
		visiting[t] = nil
	end

	writeValue(value, 0)
	return concat(out, "", 1, n)
end

-- Decoder ---------------------------------------------------------------------------------------------------------

-- Parser state (decode() is not re-entrant, which is fine: it never yields or calls user code).
local src = ""
local srcLength = 0

local ParseError = {}

-- Cast to a never-returning type: the old type solver cannot infer that error() does not return.
local parseFail: (pos: number, message: string) -> never = function(pos: number, message: string)
	error(setmetatable({ pos = pos, message = message }, ParseError), 0)
end :: any

local SIMPLE_ESCAPES: { [number]: string } = {
	[34] = '"', -- \"
	[92] = "\\", -- \\
	[47] = "/", -- \/
	[98] = "\b", -- \b
	[102] = "\f", -- \f
	[110] = "\n", -- \n
	[114] = "\r", -- \r
	[116] = "\t", -- \t
}

local function describeAt(pos: number): string
	local c = byte(src, pos)
	if c == nil then
		return "end of input"
	elseif c >= 32 and c < 127 then
		return "'" .. char(c) .. "'"
	elseif c >= 0xC2 and c <= 0xF4 then
		-- Non-ASCII: show the code point too (makes invisible characters such as U+FEFF identifiable).
		local seq = match(src, "^[\194-\244][\128-\191]*", pos)
		if seq and utf8len(seq) == 1 then
			return format("character U+%04X '%s'", utf8codepoint(seq), seq)
		end
	end
	return format("byte 0x%02X", c)
end

local function skipWhitespace(pos: number): number
	local c = byte(src, pos)
	if c == 32 or c == 10 or c == 13 or c == 9 then
		local _, last = find(src, "^[ \t\r\n]*", pos)
		return (last :: number) + 1
	end
	return pos
end

local function checkUtf8(chunk: string, chunkStart: number)
	local ok, badIndex = utf8len(chunk)
	if ok == nil then
		parseFail(chunkStart + (badIndex :: number) - 1, "invalid UTF-8 in string")
	end
end

local function readHex4(pos: number): number?
	local hex = match(src, "^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]", pos)
	if hex == nil then
		return nil
	end
	return tonumber(hex, 16)
end

-- pos is at the opening quote; returns (string, position after the closing quote).
local function parseString(pos: number): (string, number)
	-- Fast path: printable ASCII without escapes (most keys and values) needs no UTF-8 validation.
	local _, last, plain = find(src, '^"([^"\\%z\1-\31\127-\255]*)"', pos)
	if plain ~= nil then
		return plain, (last :: number) + 1
	end
	local p = pos + 1
	local parts: { string }? = nil
	while true do
		local special = find(src, '[%z\1-\31"\\]', p)
		if special == nil then
			parseFail(srcLength + 1, "unterminated string (missing closing '\"')")
		end
		local s = special :: number
		local c = byte(src, s)
		local chunk = sub(src, p, s - 1)
		checkUtf8(chunk, p)
		if c == 34 then
			if parts == nil then
				return chunk, s + 1
			end
			insert(parts, chunk)
			return concat(parts), s + 1
		elseif c == 92 then
			local list: { string } = parts or {}
			parts = list
			insert(list, chunk)
			local e = byte(src, s + 1)
			if e == 117 then -- \uXXXX
				local code = readHex4(s + 2)
				if code == nil then
					parseFail(s, "invalid \\u escape (expected 4 hex digits)")
				end
				local cp = code :: number
				p = s + 6
				if cp >= 0xD800 and cp <= 0xDBFF then
					if sub(src, p, p + 1) ~= "\\u" then
						parseFail(s, "unpaired high surrogate \\u" .. format("%04X", cp))
					end
					local low = readHex4(p + 2)
					if low == nil then
						parseFail(p, "invalid \\u escape (expected 4 hex digits)")
					end
					local lo = low :: number
					if lo < 0xDC00 or lo > 0xDFFF then
						parseFail(p, "expected low surrogate after \\u" .. format("%04X", cp))
					end
					cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
					p += 6
				elseif cp >= 0xDC00 and cp <= 0xDFFF then
					parseFail(s, "unpaired low surrogate \\u" .. format("%04X", cp))
				end
				insert(list, utf8char(cp))
			else
				local replacement = if e == nil then nil else SIMPLE_ESCAPES[e]
				if replacement == nil then
					if e == nil then
						parseFail(srcLength + 1, "unterminated string (missing closing '\"')")
					end
					parseFail(s, "invalid escape sequence \\" .. char(e :: number))
				end
				insert(list, replacement :: string)
				p = s + 2
			end
		else
			parseFail(s, format("unescaped control character U+%04X in string", c :: number))
		end
	end
end

local function parseNumber(pos: number): (number, number)
	local p = pos
	if byte(src, p) == 45 then -- '-'
		p += 1
	end
	local c = byte(src, p)
	if c == 48 then -- '0'
		p += 1
		local nextChar = byte(src, p)
		if nextChar and nextChar >= 48 and nextChar <= 57 then
			parseFail(pos, "invalid number (leading zeros are not allowed)")
		end
	elseif c and c >= 49 and c <= 57 then
		local _, last = find(src, "^[0-9]+", p)
		p = (last :: number) + 1
	else
		parseFail(p, "invalid number (expected a digit, got " .. describeAt(p) .. ")")
	end
	if byte(src, p) == 46 then -- '.'
		local _, last = find(src, "^[0-9]+", p + 1)
		if last == nil then
			parseFail(p + 1, "invalid number (expected a digit after '.', got " .. describeAt(p + 1) .. ")")
		end
		p = (last :: number) + 1
	end
	c = byte(src, p)
	if c == 101 or c == 69 then -- 'e' / 'E'
		p += 1
		c = byte(src, p)
		if c == 43 or c == 45 then
			p += 1
		end
		local _, last = find(src, "^[0-9]+", p)
		if last == nil then
			parseFail(p, "invalid number (expected a digit in the exponent, got " .. describeAt(p) .. ")")
		end
		p = (last :: number) + 1
	end
	local value = tonumber(sub(src, pos, p - 1))
	if value == nil or value ~= value or value == HUGE or value == -HUGE then
		parseFail(pos, "number out of range")
	end
	return value :: number, p
end

local function expectLiteral(pos: number, literal: string)
	if sub(src, pos, pos + #literal - 1) ~= literal then
		parseFail(pos, "invalid literal (expected '" .. literal .. "')")
	end
end

local parseValue: (pos: number, depth: number) -> (any, number)

local function parseArray(pos: number, depth: number): ({ any }, number)
	if depth > MAX_DEPTH then
		parseFail(pos, "maximum nesting depth of " .. MAX_DEPTH .. " exceeded")
	end
	local array: { any } = {}
	local count = 0
	local p = skipWhitespace(pos + 1)
	if byte(src, p) == 93 then -- ']'
		return array, p + 1
	end
	while true do
		local value
		value, p = parseValue(p, depth)
		count += 1
		array[count] = value
		p = skipWhitespace(p)
		local c = byte(src, p)
		if c == 44 then -- ','
			p = skipWhitespace(p + 1)
			if byte(src, p) == 93 then
				parseFail(p, "trailing comma in array")
			end
		elseif c == 93 then
			return array, p + 1
		elseif c == nil then
			parseFail(p, "unterminated array (expected ',' or ']')")
		else
			parseFail(p, "expected ',' or ']' in array, got " .. describeAt(p))
		end
	end
end

local function parseObject(pos: number, depth: number): (any, number)
	if depth > MAX_DEPTH then
		parseFail(pos, "maximum nesting depth of " .. MAX_DEPTH .. " exceeded")
	end
	local object: { [string]: any } = {}
	local nullKeys: { [string]: boolean }? = nil
	local hasMember = false
	local p = skipWhitespace(pos + 1)
	if byte(src, p) == 125 then -- '}'
		return EMPTY_OBJECT, p + 1
	end
	while true do
		local c = byte(src, p)
		if c ~= 34 then
			if c == 125 then
				parseFail(p, "trailing comma in object")
			elseif c == nil then
				parseFail(p, "unterminated object (expected a string key)")
			end
			parseFail(p, "expected a string key in object, got " .. describeAt(p))
		end
		local keyPos = p
		local key
		key, p = parseString(p)
		if object[key] ~= nil or (nullKeys ~= nil and nullKeys[key]) then
			parseFail(keyPos, format("duplicate key %q", key))
		end
		p = skipWhitespace(p)
		if byte(src, p) ~= 58 then -- ':'
			parseFail(p, "expected ':' after object key, got " .. describeAt(p))
		end
		p = skipWhitespace(p + 1)
		local value
		value, p = parseValue(p, depth)
		if value == NULL then
			local set: { [string]: boolean } = nullKeys or {}
			nullKeys = set
			set[key] = true
		else
			object[key] = value
			hasMember = true
		end
		p = skipWhitespace(p)
		c = byte(src, p)
		if c == 44 then
			p = skipWhitespace(p + 1)
		elseif c == 125 then
			return (if hasMember then object else EMPTY_OBJECT), p + 1
		elseif c == nil then
			parseFail(p, "unterminated object (expected ',' or '}')")
		else
			parseFail(p, "expected ',' or '}' in object, got " .. describeAt(p))
		end
	end
end

parseValue = function(pos: number, depth: number): (any, number)
	local c = byte(src, pos)
	if c == 34 then -- '"'
		return parseString(pos)
	elseif c == 123 then -- '{'
		return parseObject(pos, depth + 1)
	elseif c == 91 then -- '['
		return parseArray(pos, depth + 1)
	elseif c == 45 or (c ~= nil and c >= 48 and c <= 57) then
		return parseNumber(pos)
	elseif c == 116 then
		expectLiteral(pos, "true")
		return true, pos + 4
	elseif c == 102 then
		expectLiteral(pos, "false")
		return false, pos + 5
	elseif c == 110 then
		expectLiteral(pos, "null")
		return NULL, pos + 4
	elseif c == nil then
		return parseFail(pos, "unexpected end of input (expected a value)")
	end
	return parseFail(pos, "unexpected " .. describeAt(pos) .. " (expected a value)")
end

-- 1-based (line, column) of byte position `pos`; lines end at "\n", "\r\n" or a lone "\r".
local function lineColumn(bodyStart: number, pos: number): (number, number)
	local line, lineStart = 1, bodyStart
	local i = bodyStart
	local stop = math.min(pos, srcLength + 1)
	while i < stop do
		local c = byte(src, i)
		-- "\r\n" counts once (at the "\n"); a lone "\r" is a line break of its own.
		if c == 10 or (c == 13 and byte(src, i + 1) ~= 10) then
			line += 1
			lineStart = i + 1
		end
		i += 1
	end
	local segment = sub(src, lineStart, stop - 1)
	local column = (utf8len(segment) or #segment) + 1
	return line, column
end

-- Parses JSON text. Returns (true, value) or (false, "line L, column C: message"). Never throws.
function Json.decode(text: string): (boolean, any)
	if type(text) ~= "string" then
		return false, "line 1, column 1: expected JSON text as a string, got " .. typeof(text)
	end
	src = text
	srcLength = #text
	local bodyStart = if sub(text, 1, 3) == "\239\187\191" then 4 else 1
	local ok, result = pcall(function(): any
		local p = skipWhitespace(bodyStart)
		local value
		value, p = parseValue(p, 0)
		p = skipWhitespace(p)
		if p <= srcLength then
			parseFail(p, "unexpected " .. describeAt(p) .. " after the JSON value")
		end
		return value
	end)
	local message: string? = nil
	if not ok then
		if type(result) == "table" and getmetatable(result) == ParseError then
			local line, column = lineColumn(bodyStart, result.pos)
			message = format("line %d, column %d: %s", line, column, result.message)
		else
			src = ""
			srcLength = 0
			error(result, 0) -- internal bug: do not hide it
		end
	end
	src = ""
	srcLength = 0
	if message ~= nil then
		return false, message
	end
	return true, result
end

return Json
