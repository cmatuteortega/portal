-- The online format (src/wire.lua): a host's world survives the trip to the
-- joiner's copy, presses survive lost packets, and every chamber can still be
-- solved with Orange's input arriving the way it does online.

package.path = "./?.lua;" .. package.path
local World = require "src.world"
local Wire = require "src.wire"
local Levels = require "src.levels"
local Drive = require "tests.drive"

local function trip(msg) return Wire.decode(Wire.encode(msg)) end

local function near(a, b, what)
    assert(math.abs(a - b) <= 0.01, ("%s: %s, want %s"):format(what, a, b))
end

-- What the play screen and src/draw.lua read off a world, compared.
local function same(a, b)
    for i, p in ipairs(a.players) do
        local q = b.players[i]
        near(q.x, p.x, "robot x"); near(q.y, p.y, "robot y")
        assert(q.alive == p.alive and q.facing == p.facing and q.ground == p.ground, "robot state")
    end
    for i, c in ipairs(a.cubes) do
        local d = b.cubes[i]
        near(d.x, c.x, "cube x"); near(d.y, c.y, "cube y")
        assert(d.alive == c.alive, "cube alive")
        assert((d.holder and d.holder.id) == (c.holder and c.holder.id), "cube holder")
    end
    for pi = 1, 2 do
        for s = 1, 2 do
            local p, q = a.portals[pi][s], b.portals[pi][s]
            assert((p == nil) == (q == nil), ("portal %d/%d placed on one side only"):format(pi, s))
            if p then assert(p.cx == q.cx and p.cy == q.cy and p.nx == q.nx and p.ny == q.ny, "portal moved") end
        end
    end
    for _, ch in ipairs({ "a", "b", "c", "d", "e" }) do
        assert((a.open[ch] or false) == (b.open[ch] or false), "door " .. ch)
        for g, group in ipairs(a.buttons[ch] or {}) do assert(group.down == b.buttons[ch][g].down, "button " .. ch) end
    end
    assert(a.won == b.won, "won")
    near(b.exitTime, a.exitTime, "exit time")
end

local solutions = dofile("tests/levels_test.lua").solutions

local tests = {
    { "presses arrive once each, through lost packets", function()
        local sender, rc = Wire.sender(), Wire.receiver()
        -- Two jumps pressed on frames whose packets are lost: the counts in
        -- the next packet that gets through still carry them.
        Wire.pack(sender, { jump = true, move = 1 })
        Wire.pack(sender, { jump = true, move = 1 })
        Wire.receive(rc, trip(Wire.pack(sender, { move = 1, clear = true })))
        local a, b, c = Wire.step(rc), Wire.step(rc), Wire.step(rc)
        assert(a.jump and a.clear and a.move == 1, "first step")
        assert(b.jump and not b.clear, "second jump")
        assert(not c.jump and not c.clear and c.move == 1, "a press fired twice")
        -- A new chamber forgets what the last one was sent.
        Wire.receive(rc, trip(Wire.pack(sender, { grab = true })))
        Wire.forget(rc)
        assert(not Wire.step(rc).grab, "a press carried into the next chamber")
    end },
}

for i, level in ipairs(Levels) do
    if solutions[level.name] then
        tests[#tests + 1] = { ("chamber %d %s, Orange playing from another machine"):format(i, level.name), function()
            -- The joiner's copy is built from the level as sent, and shown
            -- each snapshot; it must look like the host's at every frame.
            local mirror = World.new(trip(level))
            local sender, rc = Wire.sender(), Wire.receiver()
            local function relay(inputs, w)
                Wire.receive(rc, trip(Wire.pack(sender, inputs[2] or {})))
                inputs[2] = Wire.step(rc)
                return inputs
            end
            local w = Drive.run(level, solutions[level.name](), {
                relay = relay,
                trace = function(w)
                    Wire.apply(mirror, trip(Wire.snapshot(w, 1)))
                    same(w, mirror)
                end,
            })
            assert(w.won, "not won")
        end }
    end
end

return tests
