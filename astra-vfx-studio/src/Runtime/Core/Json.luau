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
for byte = 0, 31 do
	local char = string.char(byte)
	if ESCAPES[char] == nil then
		ESCAPES[char] = string.format("\\u%04x", byte)
	end
end
local ESCAPE_PATTERN = '[%z\1-\31"\\\127]'

local INDENTS: { string } = {}
local function indent(level: number): string
	local s = INDENTS[level]
	if s == nil then
		s = string.rep("  ", level)
		INDENTS[level] = s
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
	if x ~= x or x == math.huge or x == -math.huge then
		return nil
	end
	if x == 0 then
		return "0" -- also -0
	end
	local a = math.abs(x)
	if a >= TWO_POW_53 then
		return tostring(x) -- integral; Luau's shortest round-trip representation
	end
	local whole = math.floor(a)
	if whole == a then
		return string.format("%d", x)
	end
	-- a - whole is exact in binary floating point; round the fraction to 6 decimals (half away from zero).
	local micros = math.floor((a - whole) * 1e6 + 0.5)
	if micros >= 1000000 then
		whole += 1
		micros = 0
	end
	local sign = if x < 0 then "-" else ""
	if micros == 0 then
		if whole == 0 then
			return "0"
		end
		return sign .. string.format("%d", whole)
	end
	local digits = string.format("%06d", micros)
	digits = (string.gsub(digits, "0+$", ""))
	return sign .. string.format("%d", whole) .. "." .. digits
end

local function isIdentifier(key: string): boolean
	return string.find(key, "^[%a_][%w_]*$") ~= nil
end

local function formatPath(path: { any }, length: number): string
	if length == 0 then
		return "(root)"
	end
	local parts = table.create(length)
	for i = 1, length do
		local key = path[i]
		if type(key) == "number" then
			parts[i] = "[" .. tostring(key) .. "]"
		elseif isIdentifier(key) then
			parts[i] = if i == 1 then key else "." .. key
		else
			parts[i] = string.format("[%q]", key)
		end
	end
	return table.concat(parts)
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
	local quotedKeys: { [string]: string } = {}
	local colon = if pretty then ": " else ":"

	local function fail(message: string): never
		error("Json.encode: " .. message .. " at " .. formatPath(path, pathLength), 0)
	end

	local function quote(s: string): string
		if utf8.len(s) == nil then
			fail("string is not valid UTF-8")
		end
		if string.find(s, ESCAPE_PATTERN) then
			s = (string.gsub(s, ESCAPE_PATTERN, ESCAPES))
		end
		return '"' .. s .. '"'
	end

	local function compareKeys(a: string, b: string): boolean
		local ra, rb = rank[a], rank[b]
		if ra ~= nil then
			if rb ~= nil then
				return ra < rb
			end
			return true
		elseif rb ~= nil then
			return false
		end
		return a < b
	end

	local function isScalar(v: any): boolean
		local t = type(v)
		return t == "string" or t == "number" or t == "boolean" or v == NULL
	end

	local writeValue: (v: any, depth: number) -> ()

	local function writeTable(t: { [any]: any }, depth: number)
		if depth > MAX_DEPTH then
			fail("nesting deeper than " .. MAX_DEPTH .. " levels")
		end
		if visiting[t] then
			fail("cyclic table reference")
		end
		-- Classify by raw keys.
		local count, maxIndex = 0, 0
		local hasString, hasIndex = false, false
		for key in next, t do
			count += 1
			local kt = type(key)
			if kt == "string" then
				hasString = true
			elseif kt == "number" and key >= 1 and key % 1 == 0 then
				hasIndex = true
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
		if hasString and hasIndex then
			fail("mixed table (array indices and string keys)")
		end
		if hasIndex and maxIndex ~= count then
			fail("sparse array (" .. count .. " elements but highest index " .. maxIndex .. ")")
		end
		visiting[t] = true
		pathLength += 1
		local slot = pathLength
		if hasIndex then
			if not pretty then
				n += 1
				out[n] = "["
				for i = 1, count do
					if i > 1 then
						n += 1
						out[n] = ","
					end
					path[slot] = i
					writeValue(t[i], depth)
				end
				n += 1
				out[n] = "]"
			else
				local inline = count <= 8
				if inline then
					for i = 1, count do
						if not isScalar(t[i]) then
							inline = false
							break
						end
					end
				end
				if inline then
					n += 1
					out[n] = "["
					for i = 1, count do
						if i > 1 then
							n += 1
							out[n] = ", "
						end
						path[slot] = i
						writeValue(t[i], depth)
					end
					n += 1
					out[n] = "]"
				else
					local inner = "\n" .. indent(depth)
					n += 1
					out[n] = "["
					for i = 1, count do
						n += 1
						out[n] = if i > 1 then "," .. inner else inner
						path[slot] = i
						writeValue(t[i], depth)
					end
					n += 1
					out[n] = "\n" .. indent(depth - 1) .. "]"
				end
			end
		else
			local keys: { string } = table.create(count)
			for key in next, t do
				table.insert(keys, key)
			end
			table.sort(keys, compareKeys)
			local inner = if pretty then "\n" .. indent(depth) else ""
			n += 1
			out[n] = "{"
			for i, key in keys do
				path[slot] = key
				local quoted = quotedKeys[key]
				if quoted == nil then
					quoted = quote(key)
					quotedKeys[key] = quoted
				end
				n += 1
				out[n] = (if i > 1 then "," .. inner else inner) .. quoted .. colon
				writeValue(t[key], depth)
			end
			n += 1
			out[n] = if pretty then "\n" .. indent(depth - 1) .. "}" else "}"
		end
		pathLength -= 1
		visiting[t] = nil
	end

	writeValue = function(v: any, depth: number)
		local t = type(v)
		if t == "string" then
			n += 1
			out[n] = quote(v)
		elseif t == "number" then
			local s = formatNumber(v)
			if s == nil then
				fail("cannot encode non-finite number " .. tostring(v))
			end
			n += 1
			out[n] = s :: string
		elseif t == "boolean" then
			n += 1
			out[n] = if v then "true" else "false"
		elseif t == "table" then
			if v == NULL then
				n += 1
				out[n] = "null"
			elseif v == EMPTY_OBJECT then
				n += 1
				out[n] = "{}"
			else
				writeTable(v, depth + 1)
			end
		elseif t == "nil" then
			fail("cannot encode nil (use Json.NULL)")
		else
			fail("cannot encode a value of type " .. typeof(v))
		end
	end

	writeValue(value, 0)
	return table.concat(out, "", 1, n)
end

-- Decoder ---------------------------------------------------------------------------------------------------------

-- Parser state (decode() is not re-entrant, which is fine: it never yields or calls user code).
local src = ""
local srcLength = 0

local ParseError = {}

local function parseFail(pos: number, message: string): never
	error(setmetatable({ pos = pos, message = message }, ParseError), 0)
end

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
	local c = string.byte(src, pos)
	if c == nil then
		return "end of input"
	elseif c >= 32 and c < 127 then
		return "'" .. string.char(c) .. "'"
	elseif c >= 0xC2 and c <= 0xF4 then
		-- Non-ASCII: show the code point too (makes invisible characters such as U+FEFF identifiable).
		local seq = string.match(src, "^[\xC2-\xF4][\x80-\xBF]*", pos)
		if seq and utf8.len(seq) == 1 then
			return string.format("character U+%04X '%s'", utf8.codepoint(seq), seq)
		end
	end
	return string.format("byte 0x%02X", c)
end

local function skipWhitespace(pos: number): number
	local c = string.byte(src, pos)
	if c == 32 or c == 10 or c == 13 or c == 9 then
		local _, last = string.find(src, "^[ \t\r\n]*", pos)
		return (last :: number) + 1
	end
	return pos
end

local function checkUtf8(chunk: string, chunkStart: number)
	local ok, badIndex = utf8.len(chunk)
	if ok == nil then
		parseFail(chunkStart + (badIndex :: number) - 1, "invalid UTF-8 in string")
	end
end

local function readHex4(pos: number): number?
	local hex = string.match(src, "^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]", pos)
	if hex == nil then
		return nil
	end
	return tonumber(hex, 16)
end

-- pos is at the opening quote; returns (string, position after the closing quote).
local function parseString(pos: number): (string, number)
	local p = pos + 1
	local parts: { string }? = nil
	while true do
		local special = string.find(src, '[%z\1-\31"\\]', p)
		if special == nil then
			parseFail(srcLength + 1, "unterminated string (missing closing '\"')")
		end
		local s = special :: number
		local c = string.byte(src, s)
		local chunk = string.sub(src, p, s - 1)
		checkUtf8(chunk, p)
		if c == 34 then
			if parts == nil then
				return chunk, s + 1
			end
			table.insert(parts, chunk)
			return table.concat(parts), s + 1
		elseif c == 92 then
			local list: { string } = parts or {}
			parts = list
			table.insert(list, chunk)
			local e = string.byte(src, s + 1)
			if e == 117 then -- \uXXXX
				local code = readHex4(s + 2)
				if code == nil then
					parseFail(s, "invalid \\u escape (expected 4 hex digits)")
				end
				local cp = code :: number
				p = s + 6
				if cp >= 0xD800 and cp <= 0xDBFF then
					if string.sub(src, p, p + 1) ~= "\\u" then
						parseFail(s, "unpaired high surrogate \\u" .. string.format("%04X", cp))
					end
					local low = readHex4(p + 2)
					if low == nil then
						parseFail(p, "invalid \\u escape (expected 4 hex digits)")
					end
					local lo = low :: number
					if lo < 0xDC00 or lo > 0xDFFF then
						parseFail(p, "expected low surrogate after \\u" .. string.format("%04X", cp))
					end
					cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
					p += 6
				elseif cp >= 0xDC00 and cp <= 0xDFFF then
					parseFail(s, "unpaired low surrogate \\u" .. string.format("%04X", cp))
				end
				table.insert(list, utf8.char(cp))
			else
				local replacement = if e == nil then nil else SIMPLE_ESCAPES[e]
				if replacement == nil then
					if e == nil then
						parseFail(srcLength + 1, "unterminated string (missing closing '\"')")
					end
					parseFail(s, "invalid escape sequence \\" .. string.char(e :: number))
				end
				table.insert(list, replacement :: string)
				p = s + 2
			end
		else
			parseFail(s, string.format("unescaped control character U+%04X in string", c :: number))
		end
	end
end

local function parseNumber(pos: number): (number, number)
	local p = pos
	if string.byte(src, p) == 45 then -- '-'
		p += 1
	end
	local c = string.byte(src, p)
	if c == 48 then -- '0'
		p += 1
		local nextChar = string.byte(src, p)
		if nextChar and nextChar >= 48 and nextChar <= 57 then
			parseFail(pos, "invalid number (leading zeros are not allowed)")
		end
	elseif c and c >= 49 and c <= 57 then
		local _, last = string.find(src, "^[0-9]+", p)
		p = (last :: number) + 1
	else
		parseFail(p, "invalid number (expected a digit, got " .. describeAt(p) .. ")")
	end
	if string.byte(src, p) == 46 then -- '.'
		local _, last = string.find(src, "^[0-9]+", p + 1)
		if last == nil then
			parseFail(p + 1, "invalid number (expected a digit after '.', got " .. describeAt(p + 1) .. ")")
		end
		p = (last :: number) + 1
	end
	c = string.byte(src, p)
	if c == 101 or c == 69 then -- 'e' / 'E'
		p += 1
		c = string.byte(src, p)
		if c == 43 or c == 45 then
			p += 1
		end
		local _, last = string.find(src, "^[0-9]+", p)
		if last == nil then
			parseFail(p, "invalid number (expected a digit in the exponent, got " .. describeAt(p) .. ")")
		end
		p = (last :: number) + 1
	end
	local value = tonumber(string.sub(src, pos, p - 1))
	if value == nil or value ~= value or value == math.huge or value == -math.huge then
		parseFail(pos, "number out of range")
	end
	return value :: number, p
end

local function expectLiteral(pos: number, literal: string)
	if string.sub(src, pos, pos + #literal - 1) ~= literal then
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
	if string.byte(src, p) == 93 then -- ']'
		return array, p + 1
	end
	while true do
		local value
		value, p = parseValue(p, depth)
		count += 1
		array[count] = value
		p = skipWhitespace(p)
		local c = string.byte(src, p)
		if c == 44 then -- ','
			p = skipWhitespace(p + 1)
			if string.byte(src, p) == 93 then
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
	if string.byte(src, p) == 125 then -- '}'
		return EMPTY_OBJECT, p + 1
	end
	while true do
		local c = string.byte(src, p)
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
			parseFail(keyPos, string.format("duplicate key %q", key))
		end
		p = skipWhitespace(p)
		if string.byte(src, p) ~= 58 then -- ':'
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
		c = string.byte(src, p)
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
	local c = string.byte(src, pos)
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
		local c = string.byte(src, i)
		-- "\r\n" counts once (at the "\n"); a lone "\r" is a line break of its own.
		if c == 10 or (c == 13 and string.byte(src, i + 1) ~= 10) then
			line += 1
			lineStart = i + 1
		end
		i += 1
	end
	local segment = string.sub(src, lineStart, stop - 1)
	local column = (utf8.len(segment) or #segment) + 1
	return line, column
end

-- Parses JSON text. Returns (true, value) or (false, "line L, column C: message"). Never throws.
function Json.decode(text: string): (boolean, any)
	if type(text) ~= "string" then
		return false, "line 1, column 1: expected JSON text as a string, got " .. typeof(text)
	end
	src = text
	srcLength = #text
	local bodyStart = if string.sub(text, 1, 3) == "\239\187\191" then 4 else 1
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
			message = string.format("line %d, column %d: %s", line, column, result.message)
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
