-- The rules: one level's tiles, the two robots, the cubes and the portals, and
-- a fixed step that moves them. Nothing in here touches LÖVE, so the whole game
-- can be played headless (tests/) exactly as it plays on screen.
--
-- A level is 40x22 tiles of 8px, as rows of characters. They are designed in
-- LDtk (levels.ldtk) and spelled out in this alphabet by src/ldtk.lua, which
-- keeps the rules free of any editor format; tests build small rooms in it
-- directly.
--
--   .  air              #  white panel: solid, takes portals
--   X  metal: solid, never takes a portal
--   ~  goo: kills a robot, dissolves a cube
--   |  emancipation grill: walk through it and your portals are gone; a cube
--      carried or thrown through it fizzles back to its dropper
--   a-e  floor button of that channel (the plate sits at the bottom of the tile)
--   A-E  door of that channel: solid while shut, never takes a portal
--   o  cube dropper: where a cube appears, and reappears when lost
--   *  exit: both robots inside it at once finishes the level
--   1 2  where each robot starts (and comes back after a dip in the goo)
--
-- A door opens when ANY button of its channel is held, unless the level says
-- `need = { a = "all" }`: then every separate run of that button letter must be
-- held at once, which is how a level asks for both robots (or a robot and a
-- cube) to stand still together.
--
-- Portals: each robot owns a pair (slot 1 and slot 2) that leads only to each
-- other, but ANY body may use any pair -- your partner's portals are as good as
-- yours, and that is most of the co-op. A portal is two tiles long on one face
-- of a white panel; a body goes through when it crosses the face moving into
-- it with its middle inside the opening. Speed in is speed out.
--
-- Movement is resolved one axis at a time in steps of at most 3px, so nothing
-- tunnels through a 1-tile wall even at fling speed; before each axis is
-- resolved against the tiles the portals get first look, so the face of a
-- portal is never a wall to a body that fits it.

local D = require "src.defs"

local floor, ceil, abs, min, max, sqrt = math.floor, math.ceil, math.abs, math.min, math.max, math.sqrt
local T = D.TILE

local World = {}
World.__index = World

local function approach(v, target, step)
    if v < target then return min(v + step, target) end
    return max(v - step, target)
end

local function overlaps(ax, ay, aw, ah, bx, by, bw, bh)
    return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

local function isDoor(ch) return ch >= "A" and ch <= "E" end
local function isButton(ch) return ch >= "a" and ch <= "e" end

--- loading -------------------------------------------------------------------------------------

function World.new(level)
    local w = setmetatable({}, World)
    w.level = level
    w.rows = {}
    assert(#level.map == D.ROWS, ("%s: %d rows, want %d"):format(level.name, #level.map, D.ROWS))
    for y, row in ipairs(level.map) do
        assert(#row == D.COLS, ("%s row %d: %d columns, want %d"):format(level.name, y - 1, #row, D.COLS))
        w.rows[y - 1] = row
    end
    w.need = level.need or {}
    w.open = {}
    w.pressed = {}
    w.buttons = {}     -- channel -> list of groups; group = list of {tx, ty}
    w.doors = {}       -- list of {tx, ty, ch}
    w.droppers = {}
    w.spawns = {}
    w.portals = { {}, {} }
    w.players = {}
    w.cubes = {}
    w.events = {}
    w.time = 0
    w.exitTime = 0
    w.won = false

    for ty = 0, D.ROWS - 1 do
        local row = w.rows[ty]
        local tx = 0
        while tx < D.COLS do
            local ch = row:sub(tx + 1, tx + 1)
            if isButton(ch) then
                -- One group per horizontal run of the same letter.
                local group = {}
                while tx < D.COLS and row:sub(tx + 1, tx + 1) == ch do
                    group[#group + 1] = { tx, ty }
                    tx = tx + 1
                end
                w.buttons[ch] = w.buttons[ch] or {}
                table.insert(w.buttons[ch], group)
                tx = tx - 1
            elseif isDoor(ch) then
                w.doors[#w.doors + 1] = { tx = tx, ty = ty, ch = ch:lower() }
            elseif ch == "o" then
                w.droppers[#w.droppers + 1] = { tx = tx, ty = ty }
            elseif ch == "1" or ch == "2" then
                w.spawns[tonumber(ch)] = { tx = tx, ty = ty }
            end
            tx = tx + 1
        end
    end
    assert(w.spawns[1] and w.spawns[2], level.name .. ": needs spawns 1 and 2")

    for i = 1, 2 do
        local p = {
            kind = "player", id = i, w = D.PLAYER_W, h = D.PLAYER_H,
            vx = 0, vy = 0, facing = 1, alive = true, deadTime = 0,
            coyote = 0, buffer = 0, cooldown = 0, aimx = 1, aimy = 0, lastDx = 0,
        }
        w:spawnPlayer(p)
        w.players[i] = p
    end
    for i, d in ipairs(w.droppers) do
        local c = { kind = "cube", id = i, w = D.CUBE, h = D.CUBE, vx = 0, vy = 0, dropper = d, alive = true, lastDx = 0 }
        w:spawnCube(c)
        w.cubes[i] = c
    end
    w:updateDoors()
    return w
end

function World:spawnPlayer(p)
    local s = self.spawns[p.id]
    p.x = s.tx * T + (T - p.w) / 2
    p.y = (s.ty + 1) * T - p.h
    p.vx, p.vy = 0, 0
    p.alive = true
    p.ground = false
    p.standOn = nil
    p.holding = nil
    p.facing = (s.tx < D.COLS / 2) and 1 or -1
end

function World:spawnCube(c)
    c.x = c.dropper.tx * T
    c.y = c.dropper.ty * T
    c.vx, c.vy = 0, 0
    c.alive = true
    c.respawn = nil
    c.holder = nil
    c.ground = false
end

function World:emit(name, x, y, extra)
    local e = extra or {}
    e.name, e.x, e.y = name, x, y
    self.events[#self.events + 1] = e
end

--- tiles ---------------------------------------------------------------------------------------

function World:tile(tx, ty)
    if tx < 0 or ty < 0 or tx >= D.COLS or ty >= D.ROWS then return "X" end
    local ch = self.rows[ty]:sub(tx + 1, tx + 1)
    return ch
end

function World:solid(tx, ty)
    local ch = self:tile(tx, ty)
    if ch == "#" or ch == "X" then return true end
    if isDoor(ch) then return not self.open[ch:lower()] end
    return false
end

function World:portalable(tx, ty)
    return self:tile(tx, ty) == "#"
end

-- Any solid tile under a rectangle.
function World:rectSolid(x, y, w, h)
    local tx0, tx1 = floor(x / T), floor((x + w - 1e-6) / T)
    local ty0, ty1 = floor(y / T), floor((y + h - 1e-6) / T)
    for ty = ty0, ty1 do
        for tx = tx0, tx1 do
            if self:solid(tx, ty) then return true end
        end
    end
    return false
end

function World:rectHas(x, y, w, h, ch)
    local tx0, tx1 = floor(x / T), floor((x + w - 1e-6) / T)
    local ty0, ty1 = floor(y / T), floor((y + h - 1e-6) / T)
    for ty = ty0, ty1 do
        for tx = tx0, tx1 do
            if self:tile(tx, ty) == ch then return true end
        end
    end
    return false
end

--- buttons and doors ---------------------------------------------------------------------------

-- Bodies that weigh on a button: robots on their feet and cubes nobody holds.
function World:eachWeight(fn)
    for _, p in ipairs(self.players) do
        if p.alive then fn(p) end
    end
    for _, c in ipairs(self.cubes) do
        if c.alive and not c.holder then fn(c) end
    end
end

function World:updateDoors()
    local pressed = {}
    for ch, groups in pairs(self.buttons) do
        local held, all = 0, #groups
        for _, group in ipairs(groups) do
            local down = false
            for _, t in ipairs(group) do
                local bx, by = t[1] * T, t[2] * T + 5
                self:eachWeight(function(b)
                    if overlaps(b.x, b.y, b.w, b.h, bx, by, T, 3) then down = true end
                end)
            end
            group.down = down
            if down then held = held + 1 end
        end
        if self.need[ch] == "all" then pressed[ch] = held == all else pressed[ch] = held > 0 end
    end

    for ch, want in pairs(pressed) do
        if want ~= (self.open[ch] or false) then
            if want then
                self.open[ch] = true
                self:emit("door_open", 0, 0, { ch = ch })
            else
                -- Never shut on someone: a door waits until its tiles are clear.
                local blocked = false
                for _, d in ipairs(self.doors) do
                    if d.ch == ch then
                        local dx, dy = d.tx * T, d.ty * T
                        self:eachWeight(function(b)
                            if overlaps(b.x, b.y, b.w, b.h, dx, dy, T, T) then blocked = true end
                        end)
                        for _, p in ipairs(self.players) do
                            local c = p.holding
                            if c and overlaps(c.x, c.y, c.w, c.h, dx, dy, T, T) then blocked = true end
                        end
                    end
                end
                if not blocked then
                    self.open[ch] = false
                    self:emit("door_shut", 0, 0, { ch = ch })
                end
            end
        end
    end
    self.pressed = pressed
end

--- portals -------------------------------------------------------------------------------------

-- Walk the grid along a ray (Amanatides & Woo) to the first solid tile. Returns
-- the tile, the normal of the face the ray came in through, and the point.
function World:raycast(ox, oy, dx, dy, maxDist)
    maxDist = maxDist or D.RAY_MAX
    local len = sqrt(dx * dx + dy * dy)
    if len == 0 then return nil end
    dx, dy = dx / len, dy / len
    local tx, ty = floor(ox / T), floor(oy / T)
    if self:solid(tx, ty) then return nil end
    local stepX = dx > 0 and 1 or -1
    local stepY = dy > 0 and 1 or -1
    local tMaxX, tMaxY = math.huge, math.huge
    local tDeltaX, tDeltaY = math.huge, math.huge
    if dx ~= 0 then
        local edge = dx > 0 and (tx + 1) * T or tx * T
        tMaxX = (edge - ox) / dx
        tDeltaX = T / abs(dx)
    end
    if dy ~= 0 then
        local edge = dy > 0 and (ty + 1) * T or ty * T
        tMaxY = (edge - oy) / dy
        tDeltaY = T / abs(dy)
    end
    while true do
        local t, nx, ny
        if tMaxX < tMaxY then
            t = tMaxX
            tx = tx + stepX
            tMaxX = tMaxX + tDeltaX
            nx, ny = -stepX, 0
        else
            t = tMaxY
            ty = ty + stepY
            tMaxY = tMaxY + tDeltaY
            nx, ny = 0, -stepY
        end
        if t > maxDist then return nil, ox + dx * maxDist, oy + dy * maxDist end
        if self:solid(tx, ty) then
            return { tx = tx, ty = ty, nx = nx, ny = ny, x = ox + dx * t, y = oy + dy * t }
        end
    end
end

-- The opening of a portal on its face: centre, normal and tangent. The tangent
-- is fixed per orientation -- down for a wall, right for a floor or ceiling --
-- rather than turned with the normal, so going wall-to-same-facing-wall keeps
-- which way is up, and floor-to-floor keeps which way is forward.
local function frame(p)
    if p.nx ~= 0 then
        local fx = p.nx > 0 and (p.tx + 1) * T or p.tx * T
        p.cx, p.cy, p.fx = fx, (p.ty + 1) * T, fx
        p.tanx, p.tany = 0, 1
    else
        local fy = p.ny > 0 and (p.ty + 1) * T or p.ty * T
        p.cx, p.cy, p.fy = (p.tx + 1) * T, fy, fy
        p.tanx, p.tany = 1, 0
    end
    return p
end

-- The two tiles a portal would cover, starting at (tx, ty), are both white
-- panel with open air in front, and no other portal shares that face.
function World:portalFits(tx, ty, nx, ny, owner, slot)
    local ax, ay = ny ~= 0 and 1 or 0, nx ~= 0 and 1 or 0
    for k = 0, 1 do
        local x, y = tx + ax * k, ty + ay * k
        if not self:portalable(x, y) then return false end
        if self:solid(x + nx, y + ny) then return false end
    end
    for pi = 1, 2 do
        for s = 1, 2 do
            local q = self.portals[pi][s]
            if q and not (pi == owner and s == slot) and q.nx == nx and q.ny == ny then
                if nx ~= 0 and q.tx == tx and abs(q.ty - ty) < 2 then return false end
                if ny ~= 0 and q.ty == ty and abs(q.tx - tx) < 2 then return false end
            end
        end
    end
    return true
end

-- Where a shot along (dx, dy) from (ox, oy) would put `slot` of robot `pi`.
-- The two-tile opening goes on whichever side of the tile that was hit is
-- nearer the point of impact, and on the other side if that one does not fit.
-- Returns the hit (or nil, and where the ray gave up) and the portal's base
-- tile if one fits. The aim line (src/draw.lua) asks this every frame.
function World:aim(pi, slot, ox, oy, dx, dy)
    local hit, ex, ey = self:raycast(ox, oy, dx, dy)
    if not hit then return nil, nil, ex or ox, ey or oy end
    local options
    if hit.nx ~= 0 then
        local frac = hit.y / T - hit.ty
        options = frac < 0.5 and { { hit.tx, hit.ty - 1 }, { hit.tx, hit.ty } } or { { hit.tx, hit.ty }, { hit.tx, hit.ty - 1 } }
    else
        local frac = hit.x / T - hit.tx
        options = frac < 0.5 and { { hit.tx - 1, hit.ty }, { hit.tx, hit.ty } } or { { hit.tx, hit.ty }, { hit.tx - 1, hit.ty } }
    end
    for _, o in ipairs(options) do
        if self:portalFits(o[1], o[2], hit.nx, hit.ny, pi, slot) then return hit, o end
    end
    return hit, nil
end

-- Fire `slot` of robot `pi`.
function World:fire(pi, slot, ox, oy, dx, dy)
    local hit, o, ex, ey = self:aim(pi, slot, ox, oy, dx, dy)
    if not hit then
        self:emit("shot", ox, oy, { x1 = ex, y1 = ey, owner = pi, slot = slot, ok = false })
        return false
    end
    if o then
        local p = frame({ tx = o[1], ty = o[2], nx = hit.nx, ny = hit.ny, owner = pi, slot = slot, born = self.time })
        self.portals[pi][slot] = p
        self:emit("shot", ox, oy, { x1 = hit.x, y1 = hit.y, owner = pi, slot = slot, ok = true })
        self:emit("portal_open", p.cx, p.cy, { owner = pi, slot = slot, nx = p.nx, ny = p.ny })
        return true
    end
    self:emit("shot", ox, oy, { x1 = hit.x, y1 = hit.y, owner = pi, slot = slot, ok = false })
    self:emit("portal_fail", hit.x, hit.y, { owner = pi, slot = slot })
    return false
end

function World:clearPortals(pi)
    local had = self.portals[pi][1] or self.portals[pi][2]
    for s = 1, 2 do
        local p = self.portals[pi][s]
        if p then self:emit("portal_close", p.cx, p.cy, { owner = pi, slot = s }) end
    end
    self.portals[pi] = {}
    return had
end

-- Send body b in through portal p and out of q. Returns false (and leaves the
-- body where it is, to meet the wall) if there is no room on the far side.
function World:teleport(b, p, q)
    local speedIn = -(b.vx * p.nx + b.vy * p.ny)
    local tv = b.vx * p.tanx + b.vy * p.tany
    local cx, cy = b.x + b.w / 2, b.y + b.h / 2
    local off = (cx - p.cx) * p.tanx + (cy - p.cy) * p.tany
    local out = max(speedIn, D.EXIT_MIN)

    local hn, ht
    if q.nx ~= 0 then hn, ht = b.w / 2, b.h / 2 else hn, ht = b.h / 2, b.w / 2 end
    local room = D.PORTAL_LEN / 2 - ht
    off = room > 0 and max(-room, min(room, off)) or 0

    local function place(o)
        local ncx = q.cx + q.nx * (hn + 0.05) + q.tanx * o
        local ncy = q.cy + q.ny * (hn + 0.05) + q.tany * o
        return ncx - b.w / 2, ncy - b.h / 2
    end
    local nx, ny = place(off)
    if self:rectSolid(nx, ny, b.w, b.h) then
        nx, ny = place(0)
        if self:rectSolid(nx, ny, b.w, b.h) then return false end
    end

    self:emit("teleport", cx, cy, { x1 = nx + b.w / 2, y1 = ny + b.h / 2, kind = b.kind })
    b.x, b.y = nx, ny
    b.vx = q.nx * out + q.tanx * tv
    b.vy = q.ny * out + q.tany * tv
    b.standOn = nil
    b.ground = false
    b.jumping = false
    if b.kind == "player" and q.nx ~= 0 then b.facing = q.nx end
    b.teleported = true
    return true
end

-- Has this axis move (d pixels) carried b into a linked portal's face?
function World:tryPortals(b, axis, d)
    if d == 0 then return false end
    for pi = 1, 2 do
        local pair = self.portals[pi]
        for s = 1, 2 do
            local p, q = pair[s], pair[3 - s]
            if p and q then
                local hit = false
                if axis == "x" and p.nx ~= 0 and d * p.nx < 0 then
                    local edge = p.nx < 0 and (b.x + b.w) or b.x
                    local pen = (edge - p.fx) * -p.nx
                    local cy = b.y + b.h / 2
                    hit = pen > 0 and pen - abs(d) <= 1e-3 and cy > p.cy - 7 and cy < p.cy + 7
                elseif axis == "y" and p.ny ~= 0 and d * p.ny < 0 then
                    local edge = p.ny < 0 and (b.y + b.h) or b.y
                    local pen = (edge - p.fy) * -p.ny
                    local cx = b.x + b.w / 2
                    hit = pen > 0 and pen - abs(d) <= 1e-3 and cx > p.cx - 7 and cx < p.cx + 7
                end
                if hit and self:teleport(b, p, q) then return true end
            end
        end
    end
    return false
end

--- moving bodies -------------------------------------------------------------------------------

local function moveX(self, b, dx)
    b.x = b.x + dx
    if self:tryPortals(b, "x", dx) then return true end
    local tx0, tx1 = floor(b.x / T), floor((b.x + b.w - 1e-6) / T)
    local ty0, ty1 = floor(b.y / T), floor((b.y + b.h - 1e-6) / T)
    if dx > 0 then
        for ty = ty0, ty1 do
            if self:solid(tx1, ty) then
                b.x = tx1 * T - b.w
                b.vx = 0
                return false
            end
        end
    elseif dx < 0 then
        for ty = ty0, ty1 do
            if self:solid(tx0, ty) then
                b.x = (tx0 + 1) * T
                b.vx = 0
                return false
            end
        end
    end
    return false
end

-- Robots and cubes are one-way floors to each other: you land on a head or a
-- cube from above and walk through them sideways. That is the whole of the
-- stacking rule, and it is what "boost me up" is made of.
local function moveY(self, b, dy, platforms)
    local oldBottom = b.y + b.h
    b.y = b.y + dy
    if self:tryPortals(b, "y", dy) then return true end
    local tx0, tx1 = floor(b.x / T), floor((b.x + b.w - 1e-6) / T)
    local ty0, ty1 = floor(b.y / T), floor((b.y + b.h - 1e-6) / T)
    if dy > 0 then
        for tx = tx0, tx1 do
            if self:solid(tx, ty1) then
                b.y = ty1 * T - b.h
                b.vy = 0
                b.ground = true
                return false
            end
        end
        for _, o in ipairs(platforms) do
            if o ~= b and overlaps(b.x, 0, b.w, 1, o.x, 0, o.w, 1)
                and oldBottom <= o.y + 0.01 and b.y + b.h > o.y then
                b.y = o.y - b.h
                b.vy = 0
                b.ground = true
                b.standOn = o
                return false
            end
        end
    elseif dy < 0 then
        for tx = tx0, tx1 do
            if self:solid(tx, ty0) then
                b.y = (ty0 + 1) * T
                b.vy = 0
                return false
            end
        end
    end
    return false
end

function World:platformsFor(b)
    local list = {}
    for _, p in ipairs(self.players) do
        if p ~= b and p.alive then list[#list + 1] = p end
    end
    for _, c in ipairs(self.cubes) do
        if c ~= b and c.alive and not c.holder then list[#list + 1] = c end
    end
    return list
end

function World:moveBody(b, dt)
    local x0 = b.x
    b.teleported = false
    -- Riding: whatever you stand on carries you with it.
    local under = b.standOn
    if under and under.alive and not under.teleported and under.lastDx ~= 0
        and overlaps(b.x, b.y + b.h, b.w, 1, under.x, under.y, under.w, 1) then
        moveX(self, b, under.lastDx)
    end
    b.ground = false
    b.standOn = nil
    local platforms = self:platformsFor(b)
    local dist = max(abs(b.vx), abs(b.vy)) * dt
    local steps = max(1, ceil(dist / 3))
    local h = dt / steps
    for _ = 1, steps do
        -- A trip through a portal ends this step's move: the speed it was
        -- taken at no longer applies.
        if not moveX(self, b, b.vx * h) then moveY(self, b, b.vy * h, platforms) end
    end
    -- Resting on something: say so even when gravity's nudge was too small to
    -- register a landing this step (a body at rest on a head, say).
    if not b.ground and b.vy >= 0 then
        if self:rectSolid(b.x, b.y + b.h, b.w, 0.5) then
            b.ground = true
        else
            for _, o in ipairs(platforms) do
                if overlaps(b.x, 0, b.w, 1, o.x, 0, o.w, 1) and abs(b.y + b.h - o.y) < 0.5 then
                    b.ground, b.standOn = true, o
                    break
                end
            end
        end
    end
    b.lastDx = b.teleported and 0 or (b.x - x0)
end

--- robots --------------------------------------------------------------------------------------

function World:kill(p)
    if not p.alive then return end
    p.alive = false
    p.deadTime = 0
    self:emit("die", p.x + p.w / 2, p.y + p.h / 2, { id = p.id })
    if p.holding then self:fizzleCube(p.holding) end
    p.holding = nil
end

function World:fizzleCube(c)
    if not c.alive then return end
    if c.holder then c.holder.holding = nil end
    c.holder = nil
    c.alive = false
    c.respawn = D.CUBE_RESPAWN
    self:emit("fizzle", c.x + c.w / 2, c.y + c.h / 2)
end

-- Where a carried cube rides: out in front at chest height.
local function holdSpot(p, c)
    return p.x + p.w / 2 - c.w / 2 + p.facing * 7, p.y + 1
end

function World:grab(p)
    if p.holding then
        local c = p.holding
        p.holding = nil
        c.holder = nil
        -- Put it down where it is if there is room, else at the robot's feet.
        if self:rectSolid(c.x, c.y, c.w, c.h) then
            c.x = p.x + p.w / 2 - c.w / 2
            c.y = p.y + p.h - c.h
            if self:rectSolid(c.x, c.y, c.w, c.h) then c.y = p.y end
        end
        c.vx, c.vy = p.vx, min(p.vy, 0)
        self:emit("drop", c.x + c.w / 2, c.y + c.h / 2)
        return
    end
    local pcx, pcy = p.x + p.w / 2, p.y + p.h / 2
    local best, bestD
    for _, c in ipairs(self.cubes) do
        if c.alive and not c.holder then
            local ddx, ddy = c.x + c.w / 2 - pcx, c.y + c.h / 2 - pcy
            local d2 = ddx * ddx + ddy * ddy
            if abs(ddx) <= D.REACH and abs(ddy) <= D.REACH and (not bestD or d2 < bestD) then
                best, bestD = c, d2
            end
        end
    end
    -- Not the cube you are standing on, and not one your partner holds.
    if best and p.standOn ~= best then
        p.holding = best
        best.holder = p
        best.vx, best.vy = 0, 0
        self:emit("grab", pcx, pcy)
    end
end

function World:updatePlayer(p, input, dt)
    if not p.alive then
        p.deadTime = p.deadTime + dt
        if p.deadTime >= D.RESPAWN then
            self:spawnPlayer(p)
            self:emit("respawn", p.x + p.w / 2, p.y + p.h / 2, { id = p.id })
        end
        return
    end
    input = input or {}
    local move = input.move or 0

    if move ~= 0 then p.facing = move > 0 and 1 or -1 end
    local target = move * D.RUN
    if p.ground then
        p.vx = approach(p.vx, target, (move ~= 0 and D.ACC_GROUND or D.FRICTION) * dt)
    elseif move ~= 0 then
        -- In the air you can steer up to a run, and against a fling, but never
        -- shave a fling you are going along with: momentum is the point.
        if p.vx * move < D.RUN then p.vx = approach(p.vx, target, D.ACC_AIR * dt) end
    else
        p.vx = approach(p.vx, 0, D.AIR_DRAG * dt)
    end

    p.coyote = p.ground and D.COYOTE or max(0, p.coyote - dt)
    p.buffer = input.jump and D.BUFFER or max(0, p.buffer - dt)
    if p.buffer > 0 and p.coyote > 0 then
        p.vy = -D.JUMP
        p.buffer, p.coyote = 0, 0
        p.jumping = true
        p.ground = false
        self:emit("jump", p.x + p.w / 2, p.y + p.h)
    end
    if p.jumping and (p.vy >= 0) then p.jumping = false end
    if p.jumping and not input.jumpHeld then
        p.vy = p.vy * D.JUMP_CUT
        p.jumping = false
    end
    p.vy = min(p.vy + D.GRAV * dt, D.MAXFALL)

    self:moveBody(p, dt)

    -- Aim: the stick or keys if held, else straight ahead.
    local ax, ay = input.aimx or 0, input.aimy or 0
    if ax == 0 and ay == 0 then ax = p.facing end
    local al = sqrt(ax * ax + ay * ay)
    p.aimx, p.aimy = ax / al, ay / al
    if input.aimx and input.aimx ~= 0 and move == 0 then p.facing = input.aimx > 0 and 1 or -1 end

    -- A shot pressed while the gun is still cooling is kept, not dropped: it
    -- goes off the moment it can (aimed wherever the robot aims by then).
    p.cooldown = max(0, p.cooldown - dt)
    if input.fire1 or input.fire2 then p.queued, p.queuedFor = input.fire1 and 1 or 2, D.FIRE_COOLDOWN end
    if p.queued then
        if p.cooldown == 0 then
            local gx, gy = self:gun(p)
            self:fire(p.id, p.queued, gx, gy, p.aimx, p.aimy)
            p.cooldown = D.FIRE_COOLDOWN
            p.queued = nil
        else
            p.queuedFor = p.queuedFor - dt
            if p.queuedFor <= 0 then p.queued = nil end
        end
    end

    if input.grab then self:grab(p) end
    if p.holding then
        local c = p.holding
        c.x, c.y = holdSpot(p, c)
        c.vx, c.vy = p.vx, p.vy
    end

    -- The goo and the grill.
    if self:rectHas(p.x, p.y + 2, p.w, p.h - 2, "~") then
        self:kill(p)
        return
    end
    if self:rectHas(p.x, p.y, p.w, p.h, "|") then
        if self:clearPortals(p.id) then self:emit("grill", p.x + p.w / 2, p.y + p.h / 2) end
        if p.holding then self:fizzleCube(p.holding) end
    end
end

-- Where shots leave from: the middle of the robot, a little above centre.
function World:gun(p)
    return p.x + p.w / 2, p.y + 5
end

function World:updateCube(c, dt)
    if not c.alive then
        c.respawn = c.respawn - dt
        if c.respawn <= 0 then
            self:spawnCube(c)
            self:emit("cube_spawn", c.x + c.w / 2, c.y + c.h / 2)
        end
        return
    end
    if c.holder then
        -- A carried cube is wherever its robot holds it, out in front: it can
        -- reach into a grill the robot itself has not touched yet.
        if self:rectHas(c.x, c.y, c.w, c.h, "|") then self:fizzleCube(c) end
        return
    end
    if c.ground then c.vx = approach(c.vx, 0, D.FRICTION * dt) end
    c.vy = min(c.vy + D.GRAV * dt, D.MAXFALL)
    self:moveBody(c, dt)
    if self:rectHas(c.x, c.y, c.w, c.h, "~") or self:rectHas(c.x, c.y, c.w, c.h, "|") then
        self:fizzleCube(c)
    end
end

--- the step ------------------------------------------------------------------------------------

-- inputs[i] is what robot i is doing this step:
--   move (-1..1), jump (pressed this step), jumpHeld, aimx, aimy,
--   fire1, fire2 (pressed this step), grab (pressed this step)
function World:update(dt, inputs)
    self.time = self.time + dt
    for i, p in ipairs(self.players) do self:updatePlayer(p, inputs[i], dt) end
    for _, c in ipairs(self.cubes) do self:updateCube(c, dt) end
    self:updateDoors()

    local inExit = 0
    for _, p in ipairs(self.players) do
        if p.alive then
            local cx, cy = p.x + p.w / 2, p.y + p.h / 2
            if self:tile(floor(cx / T), floor(cy / T)) == "*" then inExit = inExit + 1 end
        end
    end
    if inExit == #self.players then
        if self.exitTime == 0 then self:emit("exit_ready", 0, 0) end
        self.exitTime = self.exitTime + dt
        if self.exitTime >= D.EXIT_HOLD and not self.won then
            self.won = true
            self:emit("win", 0, 0)
        end
    else
        self.exitTime = 0
    end
end

function World:drainEvents()
    local e = self.events
    self.events = {}
    return e
end

return World
