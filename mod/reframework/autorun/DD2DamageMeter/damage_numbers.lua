-- The damage numbers' model (ui/damage_numbers.lua draws them): each hit on an enemy that the meter counted becomes a
-- number of the HP it counted (Fight:add_hit), at the hit's point (Hit.point, read by game/hits.lua while the
-- numbers are on), or adds to the live number of the same attacker, skill and enemy whose first hit is at most MERGE
-- seconds older: that number shows the sum and keeps its first hit's point and time. A number is a crit or a weak
-- point when any of its hits is (DamageNumbers.crit, DamageNumbers.weak). At most MAX numbers live; the oldest goes
-- first. Pure Lua: no game access, no drawing.
--
--   DamageNumbers.new() -> list;  list.items: the live numbers, oldest first
--   list:add(hit, amount, t, shade) -> number | nil   the number the hit made or joined at time t; nil for a hit on
--       anyone but an enemy, one without a point, or an amount not above 0. shade: which member of their vocation a
--       party attacker is (View.shades), for the colour; or shade(hit) -> that, asked only when a party member's hit
--       makes a new number
--   list:prune(t, life)   forgets the numbers whose first hit is more than `life` seconds before t
--   list:clear()
--   Number = { t, point, victim, who, skill, amount, crit, crit_t, weak, dot, kind, job, shade }
--     victim / who: the enemy's and the attacker's actor keys ("other" for nobody); skill: what hits are merged by
--     (the skill id, else "normal" for a normal attack, else the attack's name, else "status:<name>"); crit_t: when
--     the number became a crit; dot: a DoT tick's; kind: "player" | "pawn" | "ally" | "other" (nobody, an enemy, a
--     neutral character, an object), job and shade a party member's (nil for the others)
--   DamageNumbers.crit(hit) -> boolean   the crit rule
--   DamageNumbers.weak(hit) -> boolean   the weak-point rule
--   DamageNumbers.MAX (40), DamageNumbers.MERGE (0.3 s)
local DamageNumbers = {}
DamageNumbers.__index = DamageNumbers

local MAX = 40
local MERGE = 0.3
local EPS = 1e-9 -- times are sums of frame times: 10.3 - 10 is a little over 0.3
local RATE_DUST = 0.001 -- a DamageRate that rose by no more than this did not rise: float dust
DamageNumbers.MAX, DamageNumbers.MERGE = MAX, MERGE

local KIND = { player = "player", pawn = "pawn", ally = "ally" }
local PARTY = { player = true, pawn = true }

-- A crit: the enemy's defence step raised the hit's DamageRate (Hit.target_bonus), the game's bonus for the enemy's
-- state (a downed enemy); the attacker's buffs (the Trickster's incense, a jump attack) and a lowered rate are none.
function DamageNumbers.crit(hit)
    local bonus = hit.target_bonus
    return hit.status == nil and type(bonus) == "number" and bonus > RATE_DUST
end

-- A weak-point hit: the game's own IsWeakDamage.
function DamageNumbers.weak(hit)
    return hit.status == nil and hit.weak_damage == true
end

function DamageNumbers.new()
    return setmetatable({ items = {} }, DamageNumbers)
end

local function skill_of(hit)
    local ref = hit.skill or {}
    if ref.id then return ref.id end
    if ref.normal then return "normal" end
    if ref.attack then return ref.attack end
    return "status:" .. tostring(ref.status or hit.status)
end

local function positive(x)
    return type(x) == "number" and x > 0 and x ~= math.huge
end

function DamageNumbers:add(hit, amount, t, shade)
    if type(hit) ~= "table" or not hit.point or not positive(amount) or type(t) ~= "number" then return nil end
    local victim = hit.victim
    if type(victim) ~= "table" or victim.kind ~= "enemy" then return nil end
    local attacker = hit.attacker
    local who, skill = attacker and attacker.key or "other", skill_of(hit)
    local crit, weak = DamageNumbers.crit(hit), DamageNumbers.weak(hit)
    local items = self.items
    for i = #items, 1, -1 do
        local n = items[i]
        if t - n.t > MERGE + EPS then break end
        if n.victim == victim.key and n.who == who and n.skill == skill then
            n.amount = n.amount + amount
            if crit and not n.crit then n.crit, n.crit_t = true, t end
            n.weak = n.weak or weak
            return n
        end
    end
    local kind = attacker and KIND[attacker.kind] or "other"
    local party = PARTY[kind] == true
    if party and type(shade) == "function" then shade = shade(hit) end
    local n = {
        t = t, point = hit.point, victim = victim.key, who = who, skill = skill, amount = amount,
        crit = crit, crit_t = crit and t or nil, weak = weak, dot = hit.status ~= nil,
        kind = kind, job = party and attacker.job or nil, shade = party and shade or nil,
    }
    if #items >= MAX then table.remove(items, 1) end
    items[#items + 1] = n
    return n
end

function DamageNumbers:prune(t, life)
    local items = self.items
    while #items > 0 and t - items[1].t > life do table.remove(items, 1) end
end

function DamageNumbers:clear()
    self.items = {}
end

return DamageNumbers
