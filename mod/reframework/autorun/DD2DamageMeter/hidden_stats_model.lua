-- The hidden-stats panel's model: an augment's or a
-- ring's meaning (hidden_stats_data.lua) and the game's own numbers (game/hidden_stats.lua) as marked lines of text.
-- Pure Lua: no game access, no drawing (the panel's drawing reads Panel).
--
--   HiddenStatsModel.panel(entry, raw, base, total) -> Panel | nil
--     entry: HiddenStatsData.augment / .ring's Entry; raw: the game's AugmentRaw / RingRaw (nil when not read);
--     base: { who = "player" | "pawn", phys_defence, magic_defence, strength, magic } | nil, the numbers in brackets
--       on the status screen of the one whose augments or ring the screen shows (only who when they cannot be read)
--     total: { phys, magic, equipped, who } | nil, for the total lines: that one's defence and magick
--       defence as the status screen shows them before its floor (each nil when unknown); equipped: whether the
--       hovered augment or ring is on that one (true / false, else unknown); who: "player" | "pawn" as Hover's (else
--       unknown)
--   Panel = { lines = { { text, mark = "plain" | "approx" | "guess" | "none" } }, legend = boolean }
--     text carries its mark's prefix: none for plain, "≈ " for approx, "? " for guess; legend: whether a line
--     is approx or guess (the drawing adds the hs_legend line)
--     nil for a silent entry, no entry, or when no line is left. A none entry gives its one hs_none line, and so does
--     an or_none entry when none of its lines can be written (Везение unread).
--   Texts are the current I18n.lang()'s, else English.
--
-- A line (HiddenStatsData's Line) is written from its text's places: "{n}" is its nums[n]'s value, read from raw by
-- the dotted path src (a part that is a whole number is an index: "curve.steps.2.to") and converted by its `as`:
--   num: whole, grouped ("1 234")       signed: "+0,3" / "-5", up to 2 decimals    dec: I18n.dec ("1,5")
--   pct: a percent number, 30 -> "30%"  signed_pct: 30 -> "+30%"                    list: names joined by ", "
--   mult: a multiplier, 0.85 -> "-15%", 1.1 -> "+10%"                               add: 0.1 -> "+10%"
--   share: a share of a whole, unsigned, 0.3 -> "30%"
-- A value is missing when it is not a finite number (for list: not a table); it is 0 when it is 0 (an empty list).
--   - A line whose values are all missing or 0 is dropped: the game gave no number for it.
--   - A "[...]" part of the text is kept only when every value it shows is there and not 0 («и ещё 0» is never
--     written); a place outside such a part whose value is missing drops the line (no "nil", never half a line).
--   - A fallback line is written only when no line before it in its entry was (a curve's top, when its steps
--     cannot be read).
--   - A line with a base ends with that base as the status screen shows it (floored, through I18n.num) and
--     the personal number base_add + base[base] × base_pct / 100 through I18n.num: «(у тебя 380) — сейчас +159»
--     (hs_yours) or «(у пешки 375) — сейчас +158» (hs_pawns) by base.who, and its English "{whose}" is "your" or
--     "the pawn's" (hs_whose_yours / hs_whose_pawns); without that base number or a known who, the hint hs_base_hint
--     and "the" (hs_whose_none). base_add nil counts 0. A line with no_pawn (a bonus that holds only without pawns)
--     on a pawn's base (base.who "pawn") has neither: no ending, and "the".
--   - A line with a total that is written is followed by its total line, with the line's mark: «защита 1486 →
--     1645 (+11%)» (hs_total_phys / hs_total_magic), before → after, each floored as the status screen floors it
--     (not grouped), then (after / before − 1) × 100 with its sign, whole, or to one decimal below 1 in size
--     («+0,5%»). The bonus is the line's personal number, else total_add's value (a ring's field); equipped: before =
--     total − bonus, after = total; not: before = total, after = total + bonus. Left out when the total, the bonus or
--     whether it is equipped is unknown, or when before or after is not above 0: never guessed.
--   - Under a total line, the most damage taken it can cut, with the line's mark as the total line has it: «до -10%
--     физ. урона по тебе» (hs_damage_<phys|magic>_<yours|pawns> by total.who), −round((1 − before / after) × 100)
--     with its sign, the cut rounded as the total line's percent: whole, or to one decimal below 1 in size
--     («до -0,5%»). "Up to" («до»): the game's step is damage × C / (C + D), D the total defence, C about 113 against
--     the enemy measured (its attack, probably), and this is its C-free form, the cut's upper bound: for Стойкость's
--     −10 % the real cut is 7 to 10 %, by the enemy. Left out with the total line, and when who is not known.
local I18n = require("DD2DamageMeter/i18n")

local HiddenStatsModel = {}

local PREFIX = { plain = "", approx = "≈ ", guess = "? " }

local function finite(v)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

-- The value at the dotted path ("efficacy.rate", "curve.steps.1.y": a whole number is an index) of raw, or nil.
local function get(raw, path)
    local v = raw
    for key in tostring(path):gmatch("[^.]+") do
        if type(v) ~= "table" then return nil end
        local index = tonumber(key)
        v = v[index and math.tointeger(index) or key]
    end
    return v
end

-- "+" before a number that is not shown as 0 or with its own "-".
local function signed(text)
    if text == "0" or text:sub(1, 1) == "-" then return text end
    return "+" .. text
end

local CONV = {
    num = function(x) return I18n.num(x) end,
    signed = function(x) return signed(I18n.dec(x)) end,
    dec = function(x) return I18n.dec(x) end,
    pct = function(x) return I18n.dec(x) .. "%" end,
    signed_pct = function(x) return signed(I18n.dec(x)) .. "%" end,
    mult = function(x) return signed(I18n.dec((x - 1) * 100)) .. "%" end,
    add = function(x) return signed(I18n.dec(x * 100)) .. "%" end,
    share = function(x) return I18n.dec(x * 100) .. "%" end,
}

-- The num's shown text, or nil when its value is missing; and whether the value is 0.
local function value_of(num, raw)
    local v = get(raw, num.src)
    if num.as == "list" then
        if type(v) ~= "table" then return nil, false end
        local names = {}
        for _, name in ipairs(v) do
            if type(name) == "string" then names[#names + 1] = name end
        end
        return table.concat(names, ", "), #names == 0
    end
    v = finite(v)
    local conv = CONV[num.as]
    if v == nil or conv == nil then return nil, false end
    return conv(v), v == 0
end

-- Whose: the keys of the English word for whose base, of the base and personal number's ending, of the damage line.
local WHO = {
    player = { whose = "hs_whose_yours", ending = "hs_yours", damage = "yours" },
    pawn = { whose = "hs_whose_pawns", ending = "hs_pawns", damage = "pawns" },
}
local TOTAL_KEYS = { phys = "hs_total_phys", magic = "hs_total_magic" }

-- A number as the status screen shows it: floored, after a thousandth is added, so that a float's noise just under a
-- whole number (1485.9999 for 1486) does not take one off.
local function floored(x) return math.floor(x + 0.001) end

-- A whole number to the nearest, half up.
local function rounded(x) return math.floor(x + 0.5) end

-- A percent of the total and damage lines: whole, or to one decimal below 1 in size (its size rounded half up, its
-- sign kept), so that a small bonus on a big total is not shown as 0: 0.48 -> 0.5, 0.97 -> 1, 0.03 -> 0.
local function percent(x)
    if math.abs(x) >= 1 then return rounded(x) end
    local tenths = math.floor(math.abs(x) * 10 + 0.5)
    return (x < 0 and -tenths or tenths) / 10
end

-- The personal number of a line with a base, the base and whose (WHO's); nil when it cannot be made.
local function personal(line, raw, base)
    if type(base) ~= "table" then return nil end
    local stat, who = finite(base[line.base]), WHO[base.who]
    local add = line.base_add == nil and 0 or finite(get(raw, line.base_add))
    local pct = finite(get(raw, line.base_pct))
    if not (stat and who and add and pct) then return nil end
    return add + stat * pct / 100, stat, who
end

-- A line with a base's ending put to its text: the base in brackets and the personal number, else the hint;
-- with that number (nil with the hint). A no_pawn line seen on a pawn has no ending at all: a pawn on the screen
-- means a party with pawns, so the bonus never holds for it.
local function with_base(text, line, raw, base)
    if line.no_pawn and type(base) == "table" and base.who == "pawn" then
        return (text:gsub("{whose}", function() return I18n.t("hs_whose_none") end)), nil
    end
    local n, stat, who = personal(line, raw, base)
    local word = I18n.t(n and who.whose or "hs_whose_none")
    text = text:gsub("{whose}", function() return word end)
    if n == nil then return text .. " " .. I18n.t("hs_base_hint"), nil end
    return text .. " " .. I18n.t(who.ending, I18n.num(floored(stat)), signed(I18n.num(n))), n
end

-- The total line and the damage line under a written line with a total; each nil when it is left out.
-- `bonus`: the line's personal number (a line with a base).
local function total_lines(line, raw, bonus, total)
    local key = TOTAL_KEYS[line.total]
    if key == nil or type(total) ~= "table" or type(total.equipped) ~= "boolean" then return nil, nil end
    local now = finite(total[line.total])
    if line.base == nil then bonus = finite(get(raw, line.total_add)) end
    if not (now and bonus) then return nil, nil end
    local before, after = now, now + bonus
    if total.equipped then before, after = now - bonus, now end
    if not (before > 0 and after > 0) then return nil, nil end
    local function shown(x) return string.format("%.0f", floored(x)) end
    local text = I18n.t(key, shown(before), shown(after), signed(I18n.dec(percent((after / before - 1) * 100))) .. "%")
    local who = WHO[total.who]
    if who == nil then return text, nil end
    local cut = percent((1 - before / after) * 100)
    return text, I18n.t("hs_damage_" .. line.total .. "_" .. who.damage, signed(I18n.dec(-cut)) .. "%")
end

-- The line's text in the current language, or nil when it is dropped; and its personal number, when it has one.
local function write(line, raw, base)
    local text = line[I18n.lang()] or line.en
    if type(text) ~= "string" or type(line.nums) ~= "table" then return nil end
    local shown, zero, any = {}, {}, false
    for i, num in ipairs(line.nums) do
        shown[i], zero[i] = value_of(num, raw)
        if shown[i] ~= nil and not zero[i] then any = true end
    end
    if not any then return nil end
    text = text:gsub("%[(.-)%]", function(part)
        for n in part:gmatch("{(%d+)}") do
            local i = tonumber(n)
            if shown[i] == nil or zero[i] then return "" end
        end
        return part
    end)
    local missing = false
    text = text:gsub("{(%d+)}", function(n)
        local s = shown[tonumber(n)]
        if s == nil then missing = true return "" end
        return s
    end)
    if missing then return nil end
    if line.base ~= nil then return with_base(text, line, raw, base) end
    return text
end

-- The one hs_none line: a number should exist, none was found (or read).
local function none_panel() return { lines = { { text = I18n.t("hs_none"), mark = "none" } }, legend = false } end

function HiddenStatsModel.panel(entry, raw, base, total)
    if type(entry) ~= "table" or entry.silent then return nil end
    if entry.none then return none_panel() end
    local lines, legend, written = {}, false, false
    local function add(text, mark)
        lines[#lines + 1] = { text = PREFIX[mark] .. text, mark = mark }
        if mark ~= "plain" then legend = true end
    end
    for _, line in ipairs(entry.lines or {}) do
        local text, bonus = nil, nil
        if PREFIX[line.mark] and not (line.fallback and written) then text, bonus = write(line, raw, base) end
        if text then
            written = true
            add(text, line.mark)
            local sum, damage = total_lines(line, raw, bonus, total)
            if sum then add(sum, line.mark) end
            if damage then add(damage, line.mark) end
        end
    end
    if #lines == 0 then return entry.or_none and none_panel() or nil end
    return { lines = lines, legend = legend }
end

return HiddenStatsModel
