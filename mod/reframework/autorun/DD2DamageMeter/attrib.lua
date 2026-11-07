-- Credit for what the game does not name: a heal goes to the heal area that touched the
-- target in the same frames, a DoT tick to whoever last applied that status to the victim.
-- A heal on a party member or an ally that has no source at all is his own (own_heal): lifesteal when it is at
-- least lifesteal_min_hp and comes at most lifesteal_frames frames after a hit of his on an enemy began (struck), else
-- regeneration (measured in game: lifesteal heals of 30-507 HP, regeneration ticks of 1-4 HP).
-- The healing spot also goes on healing for about 4 s after its last touch (up to 4.8 s as
-- logged in game), so a heal with no touch near it goes to the latest toucher of that target
-- for linger_seconds, if it is a tick of at most linger_max_hp (spot ticks are under 3 HP; a
-- jump to full HP is not one); a new fight forgets those touches but the ones of the frames
-- just before it opened.
-- Entries live only as long as their window; prune drops the rest, so a long fight
-- keeps a handful of entries however many touches arrive.
local Attrib = {}
Attrib.__index = Attrib

local LINGER_MAX = 10  -- s; heals of other sources were seen from 19 s after the last touch

function Attrib.new(opts)
    opts = opts or {}
    return setmetatable({
        touch_frames = opts.touch_frames or 3,
        dot_seconds = opts.dot_seconds or 30,
        linger_seconds = math.min(opts.linger_seconds or 6, LINGER_MAX),
        linger_max_hp = opts.linger_max_hp or 50,
        lifesteal_frames = opts.lifesteal_frames or 3,
        lifesteal_min_hp = opts.lifesteal_min_hp or 10,
        touches = {}, -- target key -> list of { frame, healer, skill }
        latest = {},  -- target key -> { t, healer, skill }: the latest touch of that target
        applied = {}, -- victim key -> { last = entry, by_status = { status -> entry } }, entry = { t, applier }
        strikes = {}, -- party member's or ally's key -> the frame his latest hit on an enemy began in
    }, Attrib)
end

-- t: the touch's time in seconds; without it the touch counts only in its frames.
function Attrib:touch(frame, healer, target_key, skill_ref, t)
    local list = self.touches[target_key]
    if not list then
        list = {}
        self.touches[target_key] = list
    end
    list[#list + 1] = { frame = frame, healer = healer, skill = skill_ref }
    if t == nil then return end
    local latest = self.latest[target_key]
    if latest == nil then
        self.latest[target_key] = { t = t, healer = healer, skill = skill_ref }
    elseif t >= latest.t then
        latest.t, latest.healer, latest.skill = t, healer, skill_ref
    end
end

-- Nearest touch on the target within touch_frames either way; on a tie the one recorded first.
-- Else, given the heal's time t, the latest touch of the target if at most linger_seconds old,
-- unless the heal's HP (when given) is more than linger_max_hp.
function Attrib:healer_for(frame, target_key, t, hp)
    local list = self.touches[target_key]
    local best, best_distance = nil, self.touch_frames + 1
    for i = 1, list and #list or 0 do
        local touch = list[i]
        local distance = math.abs(touch.frame - frame)
        if distance < best_distance then
            best, best_distance = touch, distance
        end
    end
    if best then return best.healer, best.skill end
    if t == nil or (hp ~= nil and hp > self.linger_max_hp) then return nil, nil end
    local latest = self.latest[target_key]
    if latest and t - latest.t <= self.linger_seconds then return latest.healer, latest.skill end
    return nil, nil
end

-- A new fight opened in `frame`: heals in it no longer go to touches from before it, except where the
-- target was touched in the last touch_frames frames (the touch came just before the fight opened).
function Attrib:new_fight(frame)
    local oldest = frame - self.touch_frames
    for key in pairs(self.latest) do
        local list, recent = self.touches[key], false
        for i = 1, list and #list or 0 do
            if list[i].frame >= oldest then recent = true end
        end
        if not recent then self.latest[key] = nil end
    end
end

-- A new world: everything is forgotten.
function Attrib:reset()
    self.touches, self.latest, self.applied, self.strikes = {}, {}, {}, {}
end

-- A party member's or an ally's hit on an enemy began in `frame` (game/hits.lua: damageProc's start; counted or not).
function Attrib:struck(frame, attacker_key)
    local last = self.strikes[attacker_key]
    if last == nil or frame > last then self.strikes[attacker_key] = frame end
end

-- A heal of `hp` on a party member or an ally that has no source: "lifesteal" when hp is at least lifesteal_min_hp and
-- it comes 0..lifesteal_frames frames after a hit of his on an enemy began, else "regen".
function Attrib:own_heal(frame, target_key, hp)
    local last = self.strikes[target_key]
    if last and frame >= last and frame - last <= self.lifesteal_frames
        and type(hp) == "number" and hp >= self.lifesteal_min_hp then
        return "lifesteal"
    end
    return "regen"
end

function Attrib:status_applied(t, victim_key, status, applier)
    local v = self.applied[victim_key]
    if not v then
        v = { by_status = {} }
        self.applied[victim_key] = v
    end
    local entry = { t = t, applier = applier }
    v.last = entry
    if status then v.by_status[status] = entry end
end

-- Last applier of `status` (of any status when nil) on the victim, if not older than dot_seconds.
function Attrib:dot_source(t, victim_key, status)
    local v = self.applied[victim_key]
    if not v then return nil end
    local entry
    if status then entry = v.by_status[status] else entry = v.last end
    if not entry or t - entry.t > self.dot_seconds then return nil end
    return entry.applier
end

-- Drops what no query from this frame/time on can still use.
function Attrib:prune(frame, t)
    local oldest = frame - self.touch_frames
    for key, list in pairs(self.touches) do
        local len, kept = #list, 0
        for i = 1, len do
            local touch = list[i]
            if touch.frame >= oldest then
                kept = kept + 1
                list[kept] = touch
            end
        end
        for i = kept + 1, len do list[i] = nil end
        if kept == 0 then self.touches[key] = nil end
    end

    local linger = self.linger_seconds
    for key, latest in pairs(self.latest) do
        if t - latest.t > linger then self.latest[key] = nil end
    end

    local oldest_strike = frame - self.lifesteal_frames
    for key, last in pairs(self.strikes) do
        if last < oldest_strike then self.strikes[key] = nil end
    end

    local dot_seconds = self.dot_seconds
    for key, v in pairs(self.applied) do
        for status, entry in pairs(v.by_status) do
            if t - entry.t > dot_seconds then v.by_status[status] = nil end
        end
        if v.last and t - v.last.t > dot_seconds then v.last = nil end
        if not v.last and next(v.by_status) == nil then self.applied[key] = nil end
    end
end

return Attrib
