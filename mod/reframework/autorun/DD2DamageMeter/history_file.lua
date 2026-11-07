-- The optional history.json: the kept fights as JSON text and back. Pure Lua, no file access (the entry file reads and
-- writes the file); the text is made by this module's own encoder, so what is written does not depend on REFramework.
--
-- JSON written: a table whose keys are exactly 1..n is an array, any other table an object ({} for an empty one);
-- integers as %d, other numbers as %.10g with a decimal point, non-finite numbers as 0; strings escape " and \ and the
-- bytes 0-31 and 127 (\uXXXX), whatever the locale; UTF-8 passes as it is (a string that is not UTF-8 gets its high
-- bytes escaped too, so that one bad string cannot make the whole file unreadable); object keys are written as text;
-- functions and userdata are skipped (null in an array). The file is one array of fights, newest first, each an object
-- with "v": FORMAT beside the snapshot's own fields.
--
--   HistoryFile.FORMAT = 2
--   HistoryFile.MAX_BYTES = 4 MB                the most a written file holds
--   HistoryFile.encode(value) -> string
--   HistoryFile.encode_fight(snap) -> string    the snapshot plus "v": 2 in the text, the snapshot itself unchanged;
--                                               remembered per snapshot (a fight is encoded once, a snapshot is
--                                               never changed after it was taken)
--   HistoryFile.pack(snaps_newest_first, max_bytes) -> string, kept
--                                               the file's text and how many fights it holds; stops before the fight
--                                               that would pass max_bytes (MAX_BYTES when nil)
--   HistoryFile.unpack(decoded) -> { Snapshot }
--     the fights of a decoded file, newest first: tables with v == 2, table actors and enemies and a number duration;
--     anything else is dropped. Never raises; not an array, or not a table: {}.
local HistoryFile = {}

HistoryFile.FORMAT = 2
HistoryFile.MAX_BYTES = 4 * 1024 * 1024

local remembered = setmetatable({}, { __mode = "k" }) -- snapshot -> its text

local ESCAPE = { ['"'] = '\\"', ["\\"] = "\\\\" }
for byte = 0, 255 do
    local c = string.char(byte)
    if ESCAPE[c] == nil then ESCAPE[c] = string.format("\\u%04x", byte) end
end

-- The bytes to escape, spelled out rather than %c: %c follows the process's C locale, which something in the game may
-- have changed (Windows code pages count some UTF-8 continuation bytes as control characters).
local UNSAFE = '[\0-\31\127"\\]'
local UNSAFE_NOT_UTF8 = '[\0-\31\127"\\\128-\255]'

local function quote(s)
    local unsafe = utf8.len(s) and UNSAFE or UNSAFE_NOT_UTF8
    return '"' .. s:gsub(unsafe, ESCAPE) .. '"'
end

local function number_text(x)
    if math.type(x) == "integer" then return string.format("%d", x) end
    if x ~= x or x == math.huge or x == -math.huge then return "0" end
    -- %g writes the locale's decimal point and no comma of its own, so a comma is a decimal comma
    return (string.format("%.10g", x):gsub(",", "."))
end

local function key_text(k)
    if type(k) == "string" then return k end
    if type(k) == "number" then return number_text(k) end
    return nil
end

-- n when t's keys are exactly 1..n, else nil.
local function array_length(t)
    if t[1] == nil then return nil end
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    for i = 1, count do
        if t[i] == nil then return nil end
    end
    return count
end

local function skipped(v)
    local kind = type(v)
    return kind ~= "string" and kind ~= "number" and kind ~= "boolean" and kind ~= "table"
end

local put

-- `head`: the text of one more member, written first.
local function put_object(buf, n, t, head)
    n = n + 1
    buf[n] = "{"
    local first = true
    if head then
        n = n + 1
        buf[n] = head
        first = false
    end
    for k, v in pairs(t) do
        local key = key_text(k)
        if key ~= nil and not skipped(v) then
            n = n + 1
            buf[n] = (first and "" or ",") .. quote(key) .. ":"
            first = false
            n = put(buf, n, v)
        end
    end
    n = n + 1
    buf[n] = "}"
    return n
end

-- Appends the pieces of v's text to buf after buf[n]; gives the new n.
function put(buf, n, v)
    local kind = type(v)
    if kind == "table" then
        local length = array_length(v)
        if length == nil then return put_object(buf, n, v) end
        n = n + 1
        buf[n] = "["
        for i = 1, length do
            if i > 1 then
                n = n + 1
                buf[n] = ","
            end
            n = put(buf, n, v[i])
        end
        n = n + 1
        buf[n] = "]"
        return n
    end
    n = n + 1
    if kind == "string" then
        buf[n] = quote(v)
    elseif kind == "number" then
        buf[n] = number_text(v)
    elseif kind == "boolean" then
        buf[n] = v and "true" or "false"
    else
        buf[n] = "null"
    end
    return n
end

function HistoryFile.encode(value)
    local buf = {}
    put(buf, 0, value)
    return table.concat(buf)
end

function HistoryFile.encode_fight(snap)
    local text = remembered[snap]
    if text == nil then
        local buf = {}
        put_object(buf, 0, snap, '"v":' .. HistoryFile.FORMAT)
        text = table.concat(buf)
        remembered[snap] = text
    end
    return text
end

function HistoryFile.pack(snaps, max_bytes)
    max_bytes = max_bytes or HistoryFile.MAX_BYTES
    local parts, kept = {}, 0
    local size = 2 -- the brackets
    for _, snap in ipairs(snaps) do
        local text = HistoryFile.encode_fight(snap)
        local added = #text + (kept > 0 and 1 or 0) -- and the comma
        if size + added > max_bytes then break end
        kept = kept + 1
        parts[kept] = text
        size = size + added
    end
    return "[" .. table.concat(parts, ",") .. "]", kept
end

local function is_fight(item)
    return type(item) == "table" and item.v == HistoryFile.FORMAT and type(item.actors) == "table"
        and type(item.enemies) == "table" and type(item.duration) == "number"
end

-- A reader may give a whole number back as a float; the CharaID goes into the key of its kind ("c" .. id).
local function whole_chara_ids(snap)
    for _, group in ipairs({ snap.actors, snap.enemies }) do
        for _, entry in pairs(group) do
            local actor = type(entry) == "table" and entry.actor or nil
            if type(actor) == "table" and math.type(actor.chara_id) == "float" then
                actor.chara_id = math.tointeger(actor.chara_id) or actor.chara_id
            end
        end
    end
end

function HistoryFile.unpack(decoded)
    local out = {}
    if type(decoded) ~= "table" then return out end
    pcall(function()
        for i = 1, #decoded do
            local item = decoded[i]
            if is_fight(item) then
                item.v = nil -- a snapshot in memory has no version: encode_fight adds it
                whole_chara_ids(item)
                out[#out + 1] = item
            end
        end
    end)
    return out
end

return HistoryFile
