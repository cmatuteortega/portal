-- The rules one at a time, on small made-up rooms.

package.path = "./?.lua;" .. package.path
local World = require "src.world"
local D = require "src.defs"

local DT = 1 / 120

-- A 40x22 room of metal walls around air, with rows patched in from `patch`
-- (row index -> { col, text }).
local function room(patch, extra)
    local rows = {}
    for y = 0, D.ROWS - 1 do
        local r
        if y == 0 or y >= 19 then r = ("X"):rep(D.COLS) else r = "X" .. ("."):rep(D.COLS - 2) .. "X" end
        rows[y + 1] = r
    end
    for y, list in pairs(patch) do
        for _, p in ipairs(list) do
            local col, text = p[1], p[2]
            local r = rows[y + 1]
            rows[y + 1] = r:sub(1, col) .. text .. r:sub(col + #text + 1)
        end
    end
    local level = { name = "test", map = rows }
    for k, v in pairs(extra or {}) do level[k] = v end
    return World.new(level)
end

local function run(w, secs, inputs)
    for _ = 1, math.floor(secs / DT) do w:update(DT, inputs or {}) end
end

local function near(a, b, eps, what)
    assert(math.abs(a - b) <= (eps or 0.5), ("%s: %s, want %s"):format(what or "value", a, b))
end

return {
    { "a portal needs white panel, two tiles of it, with air in front", function()
        local patch = { [18] = { { 3, "1" }, { 10, "2" } } }
        for y = 16, 18 do patch[y] = patch[y] or {}; table.insert(patch[y], { 39, "#" }) end
        local w = room(patch)
        assert(not w:fire(1, 1, 30, 140, -1, 0), "metal took a portal")
        assert(w:fire(1, 1, 30, 140, 1, 0), "white wall refused one")
        local p = w.portals[1][1]
        assert(p.nx == -1 and p.tx == 39, "on the wrong face")
        -- Robot 2 cannot open one over robot 1's.
        assert(not w:fire(2, 1, 30, 140, 1, 0), "portals overlapped")
    end },

    { "clear takes down your own portals and not your partner's", function()
        local patch = { [18] = { { 3, "1" }, { 10, "2" } } }
        for y = 13, 18 do
            patch[y] = patch[y] or {}
            table.insert(patch[y], 1, { 0, "#" })
            table.insert(patch[y], { 39, "#" })
        end
        local w = room(patch)
        assert(w:fire(1, 1, 30, 143, -1, 0) and w:fire(1, 2, 30, 143, 1, 0))
        assert(w:fire(2, 1, 30, 120, -1, 0))
        w:update(DT, { { clear = true } })
        assert(not w.portals[1][1] and not w.portals[1][2], "robot 1's portals survived its clear")
        assert(w.portals[2][1], "robot 1's clear took robot 2's portal")
    end },

    { "speed in is speed out, wall to wall", function()
        local patch = { [18] = { { 5, "1" }, { 20, "2" } } }
        for y = 13, 18 do
            patch[y] = patch[y] or {}
            table.insert(patch[y], 1, { 0, "#" })
            table.insert(patch[y], { 39, "#" })
        end
        local w = room(patch)
        assert(w:fire(1, 1, 30, 143, -1, 0))
        assert(w:fire(1, 2, 30, 143, 1, 0))
        local p = w.players[1]
        p.x, p.vx = 9, -200
        for _ = 1, 24 do
            w:update(DT, {})
            if p.x > 250 then break end
        end
        assert(p.x > 250, "did not come out the far wall: x=" .. p.x)
        -- (Less what the floor's friction took on the way in.)
        assert(p.vx < -180, "lost its speed: vx=" .. p.vx)
    end },

    { "a fall into the floor comes out of a wall sideways", function()
        local patch = { [18] = { { 2, "1" }, { 3, "2" } }, [19] = { { 20, "##" } } }
        for y = 5, 6 do patch[y] = { { 0, "#" } } end
        local w = room(patch)
        assert(w:fire(1, 1, 168, 100, 0, 1), "floor portal")
        assert(w:fire(1, 2, 30, 48, -1, 0), "wall portal")
        local p = w.players[1]
        p.x, p.y, p.vx, p.vy = 165, 40, 0, 300
        run(w, 0.25, {})
        assert(p.vx > 250, "not flung: vx=" .. p.vx)
    end },

    { "the grill takes your portals", function()
        local patch = { [18] = { { 3, "1" }, { 30, "2" } } }
        for y = 1, 18 do patch[y] = patch[y] or {}; table.insert(patch[y], { 10, "|" }) end
        for y = 16, 18 do table.insert(patch[y], 1, { 0, "#" }) end
        local w = room(patch)
        assert(w:fire(1, 1, 30, 143, -1, 0))
        run(w, 1.2, { { move = 1 } })
        assert(w.players[1].x > 90, "did not walk through")
        assert(not w.portals[1][1], "portal survived the grill")
    end },

    { "goo kills, and the robot comes back where it started", function()
        local w = room({ [18] = { { 3, "1" }, { 30, "2" } }, [19] = { { 8, "~~~~" } } })
        local p = w.players[1]
        local x0 = p.x
        run(w, 0.8, { { move = 1 } })
        assert(not p.alive or p.x ~= x0, "never reached the goo")
        run(w, 0.05, {})
        assert(not p.alive, "goo did not kill")
        run(w, D.RESPAWN + 0.1, {})
        assert(p.alive, "no respawn")
        near(p.x, x0, 0.01, "respawn x")
    end },

    { "a door that needs all its buttons waits for both", function()
        local w = room({ [18] = { { 3, "1a" }, { 20, "A" }, { 30, "a2" } } }, { need = { a = "all" } })
        local p1, p2 = w.players[1], w.players[2]
        p1.x = 4 * 8 + 1
        p2.x = 40 * 8
        run(w, 0.1, {})
        assert(not w.open.a, "opened on one button")
        p2.x = 30 * 8 + 1
        run(w, 0.1, {})
        assert(w.open.a, "both held and still shut")
    end },

    { "a robot lands on its partner's head and rides it", function()
        local w = room({ [18] = { { 5, "2" }, { 20, "1" } } })
        local p1, p2 = w.players[1], w.players[2]
        run(w, 0.1, {})
        p1.x, p1.y = p2.x, p2.y - 30
        run(w, 0.5, {})
        assert(p1.standOn == p2, "did not land on the head")
        local before = p1.x
        run(w, 0.3, { nil, { move = 1 } })
        assert(p1.x - before > 10, "was not carried along")
        assert(p1.standOn == p2, "fell off")
    end },

    { "a cube carried through a grill fizzles back to its dropper", function()
        local patch = { [18] = { { 3, "1" }, { 4, "o" }, { 30, "2" } } }
        for y = 1, 18 do patch[y] = patch[y] or {}; table.insert(patch[y], { 12, "|" }) end
        local w = room(patch)
        run(w, 0.2, {})
        w:grab(w.players[1])
        assert(w.players[1].holding, "could not pick the cube up")
        run(w, 1.5, { { move = 1 } })
        assert(not w.players[1].holding, "still holding it past the grill")
        run(w, D.CUBE_RESPAWN + 0.2, {})
        assert(w.cubes[1].alive and w.cubes[1].x < 40, "cube did not come back to its dropper")
    end },
}
