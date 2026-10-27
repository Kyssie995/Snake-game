// astra-analyze - minimaler JSON-Parser (fuer Rojo-Projektdateien)
// SPDX-License-Identifier: MIT
//
// Unterstuetzt Objekte (Schluesselreihenfolge bleibt erhalten), Arrays, Strings (inkl. \uXXXX),
// Zahlen, true/false/null. Grosszuegig: //- und /* */-Kommentare sowie abschliessende Kommas werden akzeptiert.
#pragma once

#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace astra
{

struct JsonValue
{
    enum class Type
    {
        Null,
        Bool,
        Number,
        String,
        Array,
        Object,
    };

    Type type = Type::Null;
    bool boolean = false;
    double number = 0;
    std::string string;
    std::vector<JsonValue> array;
    std::vector<std::pair<std::string, JsonValue>> object;

    bool isObject() const
    {
        return type == Type::Object;
    }
    bool isString() const
    {
        return type == Type::String;
    }

    const JsonValue* find(const std::string& key) const
    {
        if (type != Type::Object)
            return nullptr;
        for (const auto& [k, v] : object)
            if (k == key)
                return &v;
        return nullptr;
    }
};

class JsonParser
{
public:
    explicit JsonParser(const std::string& text)
        : s(text)
    {
    }

    std::optional<JsonValue> parse(std::string& error)
    {
        JsonValue v;
        skipWs();
        if (!parseValue(v, 0))
        {
            error = err;
            return std::nullopt;
        }
        skipWs();
        if (pos != s.size())
        {
            error = at("unexpected trailing characters");
            return std::nullopt;
        }
        return v;
    }

private:
    const std::string& s;
    size_t pos = 0;
    std::string err;

    std::string at(const std::string& msg) const
    {
        size_t line = 1, col = 1;
        for (size_t i = 0; i < pos && i < s.size(); ++i)
        {
            if (s[i] == '\n')
            {
                ++line;
                col = 1;
            }
            else
                ++col;
        }
        return "line " + std::to_string(line) + ", column " + std::to_string(col) + ": " + msg;
    }

    bool fail(const std::string& msg)
    {
        if (err.empty())
            err = at(msg);
        return false;
    }

    void skipWs()
    {
        while (pos < s.size())
        {
            char c = s[pos];
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r')
                ++pos;
            else if (c == '/' && pos + 1 < s.size() && s[pos + 1] == '/')
            {
                while (pos < s.size() && s[pos] != '\n')
                    ++pos;
            }
            else if (c == '/' && pos + 1 < s.size() && s[pos + 1] == '*')
            {
                size_t end = s.find("*/", pos + 2);
                pos = end == std::string::npos ? s.size() : end + 2;
            }
            else
                break;
        }
    }

    bool literal(const char* word)
    {
        size_t n = std::char_traits<char>::length(word);
        if (s.compare(pos, n, word) == 0)
        {
            pos += n;
            return true;
        }
        return false;
    }

    static void appendUtf8(std::string& out, unsigned cp)
    {
        if (cp < 0x80)
            out += char(cp);
        else if (cp < 0x800)
        {
            out += char(0xC0 | (cp >> 6));
            out += char(0x80 | (cp & 0x3F));
        }
        else if (cp < 0x10000)
        {
            out += char(0xE0 | (cp >> 12));
            out += char(0x80 | ((cp >> 6) & 0x3F));
            out += char(0x80 | (cp & 0x3F));
        }
        else
        {
            out += char(0xF0 | (cp >> 18));
            out += char(0x80 | ((cp >> 12) & 0x3F));
            out += char(0x80 | ((cp >> 6) & 0x3F));
            out += char(0x80 | (cp & 0x3F));
        }
    }

    bool parseHex4(unsigned& out)
    {
        if (pos + 4 > s.size())
            return fail("truncated \\u escape");
        out = 0;
        for (int i = 0; i < 4; ++i)
        {
            char c = s[pos++];
            out <<= 4;
            if (c >= '0' && c <= '9')
                out |= unsigned(c - '0');
            else if (c >= 'a' && c <= 'f')
                out |= unsigned(c - 'a' + 10);
            else if (c >= 'A' && c <= 'F')
                out |= unsigned(c - 'A' + 10);
            else
                return fail("invalid \\u escape");
        }
        return true;
    }

    bool parseString(std::string& out)
    {
        if (s[pos] != '"')
            return fail("expected string");
        ++pos;
        while (pos < s.size())
        {
            char c = s[pos++];
            if (c == '"')
                return true;
            if (c != '\\')
            {
                out += c;
                continue;
            }
            if (pos >= s.size())
                break;
            char e = s[pos++];
            switch (e)
            {
            case '"':
            case '\\':
            case '/':
                out += e;
                break;
            case 'b':
                out += '\b';
                break;
            case 'f':
                out += '\f';
                break;
            case 'n':
                out += '\n';
                break;
            case 'r':
                out += '\r';
                break;
            case 't':
                out += '\t';
                break;
            case 'u':
            {
                unsigned cp;
                if (!parseHex4(cp))
                    return false;
                if (cp >= 0xD800 && cp <= 0xDBFF && pos + 6 <= s.size() && s[pos] == '\\' && s[pos + 1] == 'u')
                {
                    pos += 2;
                    unsigned lo;
                    if (!parseHex4(lo))
                        return false;
                    cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                }
                appendUtf8(out, cp);
                break;
            }
            default:
                return fail("invalid escape sequence");
            }
        }
        return fail("unterminated string");
    }

    bool parseValue(JsonValue& v, int depth)
    {
        if (depth > 256)
            return fail("nesting too deep");
        skipWs();
        if (pos >= s.size())
            return fail("unexpected end of input");

        char c = s[pos];
        if (c == '{')
        {
            ++pos;
            v.type = JsonValue::Type::Object;
            skipWs();
            if (pos < s.size() && s[pos] == '}')
            {
                ++pos;
                return true;
            }
            while (true)
            {
                skipWs();
                if (pos < s.size() && s[pos] == '}') // abschliessendes Komma
                {
                    ++pos;
                    return true;
                }
                std::string key;
                if (pos >= s.size() || !parseString(key))
                    return fail("expected object key");
                skipWs();
                if (pos >= s.size() || s[pos] != ':')
                    return fail("expected ':'");
                ++pos;
                JsonValue child;
                if (!parseValue(child, depth + 1))
                    return false;
                v.object.emplace_back(std::move(key), std::move(child));
                skipWs();
                if (pos < s.size() && s[pos] == ',')
                {
                    ++pos;
                    continue;
                }
                if (pos < s.size() && s[pos] == '}')
                {
                    ++pos;
                    return true;
                }
                return fail("expected ',' or '}'");
            }
        }
        if (c == '[')
        {
            ++pos;
            v.type = JsonValue::Type::Array;
            while (true)
            {
                skipWs();
                if (pos < s.size() && s[pos] == ']')
                {
                    ++pos;
                    return true;
                }
                JsonValue child;
                if (!parseValue(child, depth + 1))
                    return false;
                v.array.push_back(std::move(child));
                skipWs();
                if (pos < s.size() && s[pos] == ',')
                {
                    ++pos;
                    continue;
                }
                if (pos < s.size() && s[pos] == ']')
                {
                    ++pos;
                    return true;
                }
                return fail("expected ',' or ']'");
            }
        }
        if (c == '"')
        {
            v.type = JsonValue::Type::String;
            return parseString(v.string);
        }
        if (literal("true"))
        {
            v.type = JsonValue::Type::Bool;
            v.boolean = true;
            return true;
        }
        if (literal("false"))
        {
            v.type = JsonValue::Type::Bool;
            return true;
        }
        if (literal("null"))
            return true;
        if (c == '-' || (c >= '0' && c <= '9'))
        {
            size_t start = pos;
            ++pos;
            while (pos < s.size() && (isdigitc(s[pos]) || s[pos] == '.' || s[pos] == 'e' || s[pos] == 'E' || s[pos] == '+' || s[pos] == '-'))
                ++pos;
            v.type = JsonValue::Type::Number;
            try
            {
                v.number = std::stod(s.substr(start, pos - start));
            }
            catch (...)
            {
                return fail("invalid number");
            }
            return true;
        }
        return fail(std::string("unexpected character '") + c + "'");
    }

    static bool isdigitc(char c)
    {
        return c >= '0' && c <= '9';
    }
};

} // namespace astra
