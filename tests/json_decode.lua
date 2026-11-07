-- A small JSON decoder for the tests' round trips (what REFramework's json.load_file gives back, as Lua values):
-- objects and arrays become tables, null is nil, a number without a fraction or exponent is an integer. Raises on
-- malformed text.
--
--   local decode = require("json_decode")
--   decode('{"a":[1,2.5,"x"]}') -> { a = { 1, 2.5, "x" } }

local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function decode(text)
    local pos = 1

    local function fail(what)
        error(string.format("json: %s at %d", what, pos), 0)
    end

    local function skip()
        pos = text:find("[^ \t\r\n]", pos) or #text + 1
    end

    local value

    local function hex4()
        local digits = text:match("^%x%x%x%x", pos)
        if not digits then fail("bad \\u escape") end
        pos = pos + 4
        return tonumber(digits, 16)
    end

    local function string_value()
        pos = pos + 1 -- the opening quote
        local out = {}
        while true do
            local stop = text:find('["\\]', pos)
            if not stop then fail("unterminated string") end
            out[#out + 1] = text:sub(pos, stop - 1)
            pos = stop + 1
            if text:sub(stop, stop) == '"' then return table.concat(out) end
            local c = text:sub(pos, pos)
            pos = pos + 1
            if c == "u" then
                local code = hex4()
                if code >= 0xD800 and code < 0xDC00 and text:sub(pos, pos + 1) == "\\u" then
                    pos = pos + 2
                    code = 0x10000 + (code - 0xD800) * 0x400 + (hex4() - 0xDC00)
                end
                out[#out + 1] = utf8.char(code)
            elseif ESCAPES[c] then
                out[#out + 1] = ESCAPES[c]
            else
                fail("bad escape")
            end
        end
    end

    local function number_value()
        local int = text:match("^-?%d+", pos)
        if not int then fail("bad number") end
        local last = pos + #int
        local frac = text:match("^%.%d+", last)
        if frac then last = last + #frac end
        local exp = text:match("^[eE][+-]?%d+", last)
        if exp then last = last + #exp end
        local literal = text:sub(pos, last - 1)
        pos = last
        if frac or exp then return tonumber(literal) end
        return math.tointeger(tonumber(literal)) or tonumber(literal)
    end

    local function array_value()
        pos = pos + 1
        local out = {}
        skip()
        if text:sub(pos, pos) == "]" then pos = pos + 1 return out end
        local n = 0
        while true do
            n = n + 1
            out[n] = value()
            skip()
            local c = text:sub(pos, pos)
            pos = pos + 1
            if c == "]" then return out end
            if c ~= "," then fail("expected , or ]") end
        end
    end

    local function object_value()
        pos = pos + 1
        local out = {}
        skip()
        if text:sub(pos, pos) == "}" then pos = pos + 1 return out end
        while true do
            skip()
            if text:sub(pos, pos) ~= '"' then fail("expected a key") end
            local key = string_value()
            skip()
            if text:sub(pos, pos) ~= ":" then fail("expected :") end
            pos = pos + 1
            out[key] = value()
            skip()
            local c = text:sub(pos, pos)
            pos = pos + 1
            if c == "}" then return out end
            if c ~= "," then fail("expected , or }") end
        end
    end

    function value()
        skip()
        local c = text:sub(pos, pos)
        if c == "{" then return object_value() end
        if c == "[" then return array_value() end
        if c == '"' then return string_value() end
        if text:sub(pos, pos + 3) == "true" then pos = pos + 4 return true end
        if text:sub(pos, pos + 4) == "false" then pos = pos + 5 return false end
        if text:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil end
        return number_value()
    end

    local result = value()
    skip()
    if pos <= #text then fail("trailing text") end
    return result
end

return decode
