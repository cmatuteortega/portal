-- Paints a World into the canvas, in game pixels, map at (0, 0). Everything is
-- whole pixels: rectangles and ASCII sprites, lines plotted a pixel at a time
-- (`line` below) rather than LÖVE's smoothed ones, and no rotation -- a robot
-- facing left is its sprite mirrored.
--
-- Draw order, back to front: the void, the tiles, buttons and doors, the
-- exit, portals, cubes, robots, aim lines, shot traces and sparks, then the
-- level's lettering over the floor.

local D = require "src.defs"
local P = require "src.palette"
local Font = require "src.font"
local Sprites = require "src.sprites"

local floor, abs, max, sin = math.floor, math.abs, math.max, math.sin
local T = D.TILE
local rect = function(x, y, w, h) love.graphics.rectangle("fill", floor(x), floor(y), w, h) end

local Draw = {}

-- Bresenham, every `every`-th pixel (dashes), from (x0, y0) to (x1, y1).
local function line(x0, y0, x1, y1, every, phase)
    x0, y0, x1, y1 = floor(x0), floor(y0), floor(x1), floor(y1)
    local dx, dy = abs(x1 - x0), -abs(y1 - y0)
    local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
    local err = dx + dy
    local n = phase or 0
    every = every or 1
    while true do
        if n % every == 0 then rect(x0, y0, 1, 1) end
        n = n + 1
        if x0 == x1 and y0 == y1 then break end
        local e2 = 2 * err
        if e2 >= dy then err = err + dy; x0 = x0 + sx end
        if e2 <= dx then err = err + dx; y0 = y0 + sy end
    end
end
Draw.line = line

--- sparks --------------------------------------------------------------------------------------

local sparks = {}
local traces = {}

function Draw.reset()
    sparks, traces = {}, {}
end

function Draw.burst(x, y, key, n, speed, life)
    for _ = 1, n do
        local a = love.math.random() * math.pi * 2
        local s = (0.3 + love.math.random() * 0.7) * (speed or 60)
        sparks[#sparks + 1] = {
            x = x, y = y, vx = math.cos(a) * s, vy = math.sin(a) * s,
            life = (life or 0.4) * (0.5 + love.math.random() * 0.5), key = key,
        }
    end
end

function Draw.trace(x0, y0, x1, y1, key)
    traces[#traces + 1] = { x0 = x0, y0 = y0, x1 = x1, y1 = y1, key = key, life = 0.12 }
end

function Draw.update(dt)
    for i = #sparks, 1, -1 do
        local s = sparks[i]
        s.life = s.life - dt
        s.vy = s.vy + 200 * dt
        s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
        if s.life <= 0 then table.remove(sparks, i) end
    end
    for i = #traces, 1, -1 do
        traces[i].life = traces[i].life - dt
        if traces[i].life <= 0 then table.remove(traces, i) end
    end
end

--- tiles ---------------------------------------------------------------------------------------

local function isSolidCh(ch) return ch == "#" or ch == "X" end

local function drawVoid(w)
    P.set("k")
    rect(0, 0, D.COLS * T, D.ROWS * T)
    -- The chamber's far wall: a grid of dots, far behind everything.
    P.set("n")
    for y = 0, D.ROWS * T - 1, 8 do
        for x = 0, D.COLS * T - 1, 8 do rect(x + 4, y + 4, 1, 1) end
    end
end

local function drawPanel(w, tx, ty)
    local x, y = tx * T, ty * T
    P.set("w")
    rect(x, y, T, T)
    -- Seams every two tiles: the white panels read as 16px squares.
    P.set("m")
    if tx % 2 == 0 then rect(x, y, 1, T) end
    if ty % 2 == 0 then rect(x, y, T, 1) end
end

local function drawMetal(w, tx, ty)
    local x, y = tx * T, ty * T
    P.set("d")
    rect(x, y, T, T)
    -- A lit edge wherever the metal meets the room, so walls have a face.
    P.set("s")
    if not w:solid(tx, ty - 1) then rect(x, y, T, 1) end
    if not w:solid(tx - 1, ty) then rect(x, y, 1, T) end
    if not w:solid(tx + 1, ty) then rect(x + T - 1, y, 1, T) end
    if (tx + ty) % 3 == 0 then
        P.set("k")
        rect(x + 3, y + 3, 1, 1)
    end
end

local function drawGoo(w, tx, ty, time)
    local x, y = tx * T, ty * T
    P.set("t")
    rect(x, y + 2, T, T - 2)
    P.set("g")
    for i = 0, T - 1 do
        local h = floor(1.5 + sin(time * 4 + (x + i) * 0.5))
        rect(x + i, y + 2 - h, 1, 1)
    end
end

local function drawGrill(w, tx, ty, time)
    local x, y = tx * T, ty * T
    P.set("b")
    for i = 0, T - 1 do
        if (i + floor(time * 20)) % 3 ~= 0 then rect(x + 3, y + i, 1, 1) end
        if (i + floor(time * 14)) % 4 == 0 then rect(x + 4, y + i, 1, 1) end
    end
    P.set("s")
    if w:solid(tx, ty - 1) then rect(x + 2, y, 4, 2) end
    if w:solid(tx, ty + 1) then rect(x + 2, y + T - 2, 4, 2) end
end

local function drawDoor(w, tx, ty, ch)
    local x, y = tx * T, ty * T
    if w.open[ch:lower()] then
        P.set("d")
        rect(x, y, 1, T)
        rect(x + T - 1, y, 1, T)
        return
    end
    P.set("r")
    rect(x + 1, y, T - 2, T)
    P.set("d")
    rect(x, y, 1, T)
    rect(x + T - 1, y, 1, T)
    rect(x + 3, y, 2, T)
end

local function drawButton(w, tx, ty, ch)
    local x, y = tx * T, ty * T
    local down = false
    for _, g in ipairs(w.buttons[ch] or {}) do
        for _, t in ipairs(g) do
            if t[1] == tx and t[2] == ty then down = g.down end
        end
    end
    P.set("s")
    rect(x, y + T - 1, T, 1)
    P.set(down and "g" or "r")
    if down then rect(x + 1, y + T - 2, T - 2, 1) else rect(x + 1, y + T - 3, T - 2, 2) end
end

local function drawDropper(w, tx, ty)
    -- A chute from the ceiling, if there is one above; else a little hatch.
    local x, y = tx * T, ty * T
    local top = ty
    while top > 0 and not w:solid(tx, top - 1) do top = top - 1 end
    P.set("d")
    rect(x + 1, top * T, T - 2, 3)
    P.set("s")
    rect(x, top * T + 3, T, 1)
end

function Draw.tiles(w, time)
    drawVoid(w)
    for ty = 0, D.ROWS - 1 do
        for tx = 0, D.COLS - 1 do
            local ch = w:tile(tx, ty)
            if ch == "#" then drawPanel(w, tx, ty)
            elseif ch == "X" then drawMetal(w, tx, ty)
            elseif ch == "~" then drawGoo(w, tx, ty, time)
            elseif ch == "|" then drawGrill(w, tx, ty, time)
            elseif ch >= "A" and ch <= "E" then drawDoor(w, tx, ty, ch)
            elseif ch >= "a" and ch <= "e" then drawButton(w, tx, ty, ch)
            elseif ch == "o" then drawDropper(w, tx, ty)
            end
        end
    end
end

-- The exit: its outline, dashed and crawling, lit while both robots are in.
function Draw.exit(w, time)
    local lit = w.exitTime > 0
    P.set(lit and "g" or "t")
    local phase = floor(time * 10)
    for ty = 0, D.ROWS - 1 do
        for tx = 0, D.COLS - 1 do
            if w:tile(tx, ty) == "*" then
                local x, y = tx * T, ty * T
                for i = 0, T - 1 do
                    local on = (i + phase) % 3 ~= 0
                    if on then
                        if w:tile(tx, ty - 1) ~= "*" then rect(x + i, y, 1, 1) end
                        if w:tile(tx, ty + 1) ~= "*" and not isSolidCh(w:tile(tx, ty + 1)) then rect(x + i, y + T - 1, 1, 1) end
                        if w:tile(tx - 1, ty) ~= "*" then rect(x, y + i, 1, 1) end
                        if w:tile(tx + 1, ty) ~= "*" then rect(x + T - 1, y + i, 1, 1) end
                    end
                end
                if w:tile(tx, ty - 1) ~= "*" and w:tile(tx - 1, ty) ~= "*" then
                    Font.print("EXIT", x + 1, y - 7)
                end
            end
        end
    end
end

--- portals -------------------------------------------------------------------------------------

-- How deep the oval stands out of its wall at each of its 16 pixels.
local DEPTH = { 1, 2, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 3, 3, 2, 1 }

function Draw.portal(w, p, time)
    local look = P.robots[p.owner]
    local key = look.portal[p.slot]
    local linked = w.portals[p.owner][3 - p.slot] ~= nil
    local age = w.time - (p.born or 0)
    -- Opens from the middle out over a tenth of a second.
    local half = math.min(8, floor(age * 160) + 1)
    for i = 8 - half, 7 + half do
        local depth = DEPTH[i + 1]
        for k = 0, depth - 1 do
            local edge = k == depth - 1 or i == 8 - half or i == 7 + half
            local c
            if edge then
                c = key
            elseif linked then
                c = ((i + k + floor(time * 12)) % 4 == 0) and "w" or key
                if (i + floor(time * 12)) % 5 == 0 then c = look.light end
            else
                c = "k"
            end
            P.set(c)
            if p.nx ~= 0 then
                local x = p.nx > 0 and (p.fx + k) or (p.fx - 1 - k)
                rect(x, p.cy - 8 + i, 1, 1)
            else
                local y = p.ny > 0 and (p.fy + k) or (p.fy - 1 - k)
                rect(p.cx - 8 + i, y, 1, 1)
            end
        end
    end
end

--- bodies --------------------------------------------------------------------------------------

function Draw.cube(c)
    if not c.alive then return end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(Sprites.cube, floor(c.x + 0.5), floor(c.y + 0.5))
end

function Draw.robot(w, p, time)
    if not p.alive then return end
    local frames = Sprites.robot[p.id]
    local img
    if not p.ground then
        img = frames.air
    elseif abs(p.vx) > 5 then
        img = (floor(time * 10) % 2 == 0) and frames.walk1 or frames.walk2
    else
        img = frames.stand
    end
    love.graphics.setColor(1, 1, 1)
    local x, y = floor(p.x + 0.5), floor(p.y + 0.5)
    if p.facing < 0 then
        love.graphics.draw(img, x + p.w, y, 0, -1, 1)
    else
        love.graphics.draw(img, x, y)
    end
end

-- The aim line: dashes from the gun to where a shot would land, ending in a
-- mark of the colour of whichever portal would open there -- or a grey X where
-- neither would.
function Draw.aim(w, p, time)
    if not p.alive then return end
    local gx, gy = w:gun(p)
    local hit, o, ex, ey = w:aim(p.id, 1, gx, gy, p.aimx, p.aimy)
    local x1, y1 = hit and hit.x or ex, hit and hit.y or ey
    local look = P.robots[p.id]
    P.set(look.body)
    line(gx + p.aimx * 6, gy + p.aimy * 6, x1, y1, 4, floor(time * 16) % 4)
    if hit then
        if o then
            P.set(look.light)
            rect(x1 - 1, y1 - 1, 3, 3)
        else
            P.set("s")
            rect(x1 - 1, y1 - 1, 1, 1); rect(x1 + 1, y1 - 1, 1, 1)
            rect(x1, y1, 1, 1)
            rect(x1 - 1, y1 + 1, 1, 1); rect(x1 + 1, y1 + 1, 1, 1)
        end
    end
end

function Draw.effects()
    for _, t in ipairs(traces) do
        P.set(t.key)
        line(t.x0, t.y0, t.x1, t.y1, 2)
    end
    for _, s in ipairs(sparks) do
        P.set(s.key)
        rect(s.x, s.y, 1, 1)
    end
end

function Draw.hints(w)
    for _, h in ipairs(w.level.hints or {}) do
        Font.shadow(h[3], h[1] * T, h[2] * T, "m", P)
    end
end

function Draw.world(w, time, showAim)
    Draw.tiles(w, time)
    Draw.hints(w)
    Draw.exit(w, time)
    for pi = 1, 2 do
        for s = 1, 2 do
            local p = w.portals[pi][s]
            if p then Draw.portal(w, p, time) end
        end
    end
    for _, c in ipairs(w.cubes) do
        if not c.holder then Draw.cube(c) end
    end
    for _, p in ipairs(w.players) do Draw.robot(w, p, time) end
    for _, c in ipairs(w.cubes) do
        if c.holder then Draw.cube(c) end
    end
    if showAim then
        for _, p in ipairs(w.players) do Draw.aim(w, p, time) end
    end
    Draw.effects()
end

return Draw
