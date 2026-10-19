-- What goes over the network between two machines playing one chamber, as
-- plain tables (src/net.lua carries them; this file never touches a socket, so
-- the tests run it under plain LuaJIT).
--
-- The host's machine runs the rules; the other machine runs none. It sends
-- what its player is doing, and draws snapshots of the host's world. That
-- costs the joining player a round trip of input lag, but the two can never
-- disagree about where a cube is, which a pair of machines each running their
-- own copy of the rules would sooner or later do on a fling.
--
-- Messages are tables with a type `t`, sent as JSON:
--
--   joiner -> host   hello {v}          the first thing sent; v is VERSION
--                    in {...}           input, every frame (Wire.pack)
--                    restart {}         R
--   host -> joiner   welcome {}         you are Orange
--                    start {i, run, level}  a chamber starts: its number and
--                                       the whole level, so the two machines
--                                       need not have the same levels.ldtk
--                    screen {s}         the host went to "title" or "end"
--                    snap {run, ...}    the world, up to 60 times a second
--                    ev {run, list}     World.events, for sounds and sparks
--                    bye {why}          go away (an old version, say)
--
-- `run` counts chamber starts on the host. Snapshots and input travel
-- unreliably and events reliably, and ENet keeps no order between the two, so
-- a snapshot of the last chamber can land after the next one has started: the
-- run says which chamber a message belongs to.

local json = require "lib.json"

local floor = math.floor

local Wire = {}

Wire.VERSION = 1

-- The presses a step can carry (see World:update), in the order `in` sends
-- their counts.
Wire.EDGES = { "jump", "fire1", "fire2", "grab", "clear" }

local CHANNELS = { "a", "b", "c", "d", "e" }

-- Two decimals is a hundredth of a game pixel: more than drawing needs, and
-- it keeps a snapshot well under a packet.
local function r2(v) return floor(v * 100 + 0.5) / 100 end
local function r3(v) return floor(v * 1000 + 0.5) / 1000 end

function Wire.encode(msg) return json.encode(msg) end
function Wire.decode(data) return json.decode(data) end

--- the world -----------------------------------------------------------------------------------

-- Everything src/draw.lua and the play screen read off a world, and nothing
-- else: the joiner's copy is only ever drawn, never stepped.
function Wire.snapshot(w, run)
    local s = { t = "snap", run = run, time = w.time, exit = w.exitTime, won = w.won, p = {}, c = {}, q = {} }
    local open, down = {}, {}
    for _, ch in ipairs(CHANNELS) do
        if w.open[ch] then open[#open + 1] = ch end
        for _, g in ipairs(w.buttons[ch] or {}) do down[#down + 1] = g.down and "1" or "0" end
    end
    s.open, s.down = table.concat(open), table.concat(down)
    for i, p in ipairs(w.players) do
        s.p[i] = { r2(p.x), r2(p.y), r2(p.vx), r2(p.vy), p.facing, p.alive and 1 or 0, p.ground and 1 or 0, r3(p.aimx), r3(p.aimy) }
    end
    for i, c in ipairs(w.cubes) do
        s.c[i] = { r2(c.x), r2(c.y), c.alive and 1 or 0, c.holder and c.holder.id or 0 }
    end
    for pi = 1, 2 do
        for slot = 1, 2 do
            local q = w.portals[pi][slot]
            if q then s.q[#s.q + 1] = { pi, slot, q.tx, q.ty, q.nx, q.ny, q.born } end
        end
    end
    return s
end

-- Make w (built from the same level) look like the world snapshot s was taken of.
function Wire.apply(w, s)
    w.time, w.exitTime, w.won = s.time, s.exit, s.won
    w.open = {}
    for ch in s.open:gmatch(".") do w.open[ch] = true end
    local k = 0
    for _, ch in ipairs(CHANNELS) do
        for _, g in ipairs(w.buttons[ch] or {}) do
            k = k + 1
            g.down = s.down:sub(k, k) == "1"
        end
    end
    for i, p in ipairs(w.players) do
        local v = s.p[i]
        if v then
            p.x, p.y, p.vx, p.vy, p.facing = v[1], v[2], v[3], v[4], v[5]
            p.alive, p.ground = v[6] == 1, v[7] == 1
            p.aimx, p.aimy = v[8], v[9]
        end
        p.holding = nil
    end
    for i, c in ipairs(w.cubes) do
        local v = s.c[i]
        if v then
            c.x, c.y, c.alive = v[1], v[2], v[3] == 1
            c.holder = w.players[v[4]]
            if c.holder then c.holder.holding = c end
        end
    end
    w.portals = { {}, {} }
    for _, q in ipairs(s.q) do w:placePortal(q[1], q[2], q[3], q[4], q[5], q[6], q[7]) end
end

--- input ---------------------------------------------------------------------------------------

-- Input goes unreliably, the latest packet winning, so a lost packet costs a
-- frame of stick and nothing more. Presses can't be sent as "pressed this
-- frame" that way, or a lost packet would lose a jump: each kind of press is
-- sent as a running count instead, and the host fires one press for every
-- step the count is ahead of what it has used.

function Wire.sender() return { counts = {} } end

-- `input` is what Input.collect made for the joiner's robot this frame.
function Wire.pack(sender, input)
    local n = {}
    for i, name in ipairs(Wire.EDGES) do
        if input[name] then sender.counts[i] = (sender.counts[i] or 0) + 1 end
        n[i] = sender.counts[i] or 0
    end
    return {
        t = "in", move = input.move or 0, ax = r3(input.aimx or 0), ay = r3(input.aimy or 0),
        hold = input.jumpHeld and 1 or 0, n = n,
    }
end

function Wire.receiver() return { seen = { 0, 0, 0, 0, 0 } } end

function Wire.receive(rc, msg) rc.last = msg end

-- A chamber starting: presses already counted belong to the last one.
function Wire.forget(rc)
    if rc.last then
        for i = 1, #Wire.EDGES do rc.seen[i] = rc.last.n[i] or 0 end
    end
end

-- The input for one step of the host's world, spending at most one of each
-- kind of press.
function Wire.step(rc)
    local m = rc.last
    if not m then return {} end
    local o = { move = m.move, aimx = m.ax, aimy = m.ay, jumpHeld = m.hold == 1 }
    for i, name in ipairs(Wire.EDGES) do
        if (m.n[i] or 0) > rc.seen[i] then
            o[name] = true
            rc.seen[i] = rc.seen[i] + 1
        end
    end
    return o
end

return Wire
