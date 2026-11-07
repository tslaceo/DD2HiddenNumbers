-- UI texts and number formatting. Texts come from lang/<code>.lua; the current language is
-- module state, set once from the settings (the caller resolves "auto" to a code).
--   I18n.plural(n, lang?) -> "one" | "few" | "many" | "other"   the plural form of the count as I18n.num shows it:
--     Russian one / few / many, English (and any other language) one / other
--   I18n.tn(key, n) -> the text key_<form> of the count n with I18n.num(n) as its argument ("862 раза"); a counted
--     text has every form (one, few, many, other) in both lang files, each language uses its own
local I18n = {}

local LANGS = {
    en = require("DD2DamageMeter/lang/en"),
    ru = require("DD2DamageMeter/lang/ru"),
}
local DEFAULT = "en"

local current = DEFAULT

function I18n.set(lang)
    current = LANGS[lang] and lang or DEFAULT
end

function I18n.lang()
    return current
end

-- The text of `key` in the current language, else in English, else the key itself.
-- Arguments go through string.format; without arguments the text is returned as is.
function I18n.t(key, ...)
    local text = LANGS[current][key] or LANGS[DEFAULT][key]
    if text == nil then return tostring(key) end
    if select("#", ...) == 0 then return text end
    return string.format(text, ...)
end

-- Counters can reach the formatters as nil or NaN (an empty fight divides 0 by 0); show zero.
local function finite(n)
    if type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge then return n end
    return 0
end

-- 52898 -> "52 898"; rounded to a whole number.
function I18n.num(n)
    n = finite(n)
    local rounded = math.floor(math.abs(n) + 0.5)
    local digits = string.format("%.0f", rounded)
    local parts = {}
    local head = #digits % 3
    if head > 0 then parts[1] = digits:sub(1, head) end
    for i = head + 1, #digits, 3 do parts[#parts + 1] = digits:sub(i, i + 2) end
    local sign = (n < 0 and rounded > 0) and "-" or ""
    return sign .. table.concat(parts, " ")
end

function I18n.plural(n, lang)
    local whole = math.floor(math.abs(finite(n)) + 0.5)
    if (lang or current) ~= "ru" then return whole == 1 and "one" or "other" end
    local last, tens = whole % 10, whole % 100
    if last == 1 and tens ~= 11 then return "one" end
    if last >= 2 and last <= 4 and (tens < 12 or tens > 14) then return "few" end
    return "many"
end

function I18n.tn(key, n)
    return I18n.t(key .. "_" .. I18n.plural(n), I18n.num(n))
end

-- Seconds -> "5:18" (whole seconds; minutes keep counting past an hour).
function I18n.time(sec)
    local whole = math.max(0, math.floor(finite(sec)))
    return string.format("%d:%02d", whole // 60, whole % 60)
end

-- A share from 0 to 1 -> "43%".
function I18n.pct(x)
    return string.format("%d%%", math.floor(finite(x) * 100 + 0.5))
end

-- The text with its first letter a capital: Latin a-z, Cyrillic а-я and ё; any other first character (or a text that
-- is not one) as it is. Done on the UTF-8 bytes: string.upper follows the C locale, which the game may have changed.
function I18n.upper_first(text)
    if type(text) ~= "string" then return text end
    local b1, b2 = text:byte(1, 2)
    if b1 == nil then return text end
    if b1 >= 0x61 and b1 <= 0x7A then return string.char(b1 - 0x20) .. text:sub(2) end          -- a-z
    if b1 == 0xD0 and b2 and b2 >= 0xB0 and b2 <= 0xBF then                                      -- а-п: D0 B0..BF
        return "\xD0" .. string.char(b2 - 0x20) .. text:sub(3)                                   -- А-П: D0 90..9F
    end
    if b1 == 0xD1 and b2 and b2 >= 0x80 and b2 <= 0x8F then                                      -- р-я: D1 80..8F
        return "\xD0" .. string.char(b2 + 0x20) .. text:sub(3)                                   -- Р-Я: D0 A0..AF
    end
    if b1 == 0xD1 and b2 == 0x91 then return "\xD0\x81" .. text:sub(3) end                      -- ё -> Ё
    return text
end

-- A number -> "1,5" (ru) / "1.5" (en): rounded to 2 decimals, trailing zeros dropped ("62,7", "3"), the whole part
-- grouped as I18n.num groups it ("1 234,5"), "-" for minus; "" for nil or a non-finite value. Built from whole
-- numbers, so the C locale cannot change the decimal mark.
function I18n.dec(x)
    if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then return "" end
    local hundredths = math.floor(math.abs(x) * 100 + 0.5)
    local whole, frac = hundredths // 100, hundredths % 100
    local text = I18n.num(whole)
    if frac > 0 then
        local decimals = string.format("%02d", frac):gsub("0$", "")
        text = text .. I18n.t("decimal_sep") .. decimals
    end
    local sign = (x < 0 and hundredths > 0) and "-" or ""
    return sign .. text
end

-- A multiplier -> "×1,5" (ru) / "×1.5" (en): rounded to 2 decimals, at least 1 shown ("×1,0", "×0,75"); "" for nil
-- or a non-finite value. Built from whole numbers, so the C locale cannot change the decimal mark.
function I18n.mult(x)
    if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then return "" end
    local hundredths = math.floor(math.abs(x) * 100 + 0.5)
    local whole, frac = hundredths // 100, hundredths % 100
    local decimals = frac % 10 == 0 and string.format("%d", frac // 10) or string.format("%02d", frac)
    local sign = (x < 0 and hundredths > 0) and "-" or ""
    return "×" .. sign .. string.format("%.0f", whole) .. I18n.t("decimal_sep") .. decimals
end

return I18n
