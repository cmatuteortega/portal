-- The LDtk side: levels.ldtk reads through tilemapper into chambers, and a
-- chamber drawn wrong fails with a message that says which and why.

local Ldtk = require "src.ldtk"
local Levels = require "src.levels"
local D = require "src.defs"

-- A tilemapper-shaped level: an empty room with the two robots, plus `extra`.
local function level(extra)
    local lv = {
        width = D.COLS * D.TILE, height = D.ROWS * D.TILE,
        Tiles = { tiles = { { x = 0, y = 0, v = 2 }, { x = 8, y = 0, v = 1 } } },
        Entities = {
            Robot1 = { { x = 16, y = 144, w = 8, h = 8 } },
            Robot2 = { { x = 32, y = 144, w = 8, h = 8 } },
        },
    }
    for k, v in pairs(extra or {}) do
        if k == "title" then lv.title = v else lv.Entities[k] = v end
    end
    return lv
end

local function fails(fn, pattern)
    local ok, err = pcall(fn)
    assert(not ok, "did not fail")
    assert(tostring(err):find(pattern, 1, true), "wrong message: " .. tostring(err))
end

return {
    { "levels.ldtk has chambers, in its own order", function()
        assert(#Levels >= 1, "no chambers")
        assert(Levels[1].name == "PORTALS 101", "first chamber is " .. Levels[1].name)
    end },

    { "tiles and entities land on the map", function()
        local l = Ldtk.convert(level({
            title = "Test",
            Button = { { x = 40, y = 144, w = 16, h = 8, channel = "b" } },
            Door = { { x = 80, y = 128, w = 8, h = 24, channel = "b", needs_all = true } },
            Exit = { { x = 280, y = 136, w = 24, h = 16 } },
            Cube = { { x = 56, y = 64, w = 8, h = 8 } },
            Hint = { { x = 16, y = 32, w = 8, h = 8, text = "hello" } },
        }), "Test_Level")
        assert(l.name == "Test")
        assert(l.map[1]:sub(1, 2) == "X#", "tiles: " .. l.map[1]:sub(1, 2))
        assert(l.map[19]:sub(3, 3) == "1" and l.map[19]:sub(5, 5) == "2", "robots")
        assert(l.map[19]:sub(6, 7) == "bb", "button")
        assert(l.map[17]:sub(11, 11) == "B" and l.map[19]:sub(11, 11) == "B", "door")
        assert(l.need.b == "all", "needs_all")
        assert(l.map[18]:sub(36, 38) == "***", "exit")
        assert(l.map[9]:sub(8, 8) == "o", "cube")
        assert(l.hints[1][3] == "HELLO", "hint")
    end },

    { "no title falls back to the identifier", function()
        assert(Ldtk.convert(level(), "Chamber_7").name == "CHAMBER 7")
    end },

    { "a chamber the wrong size says so", function()
        local lv = level()
        lv.width = 480
        fails(function() Ldtk.convert(lv, "Wide") end, "Wide: a chamber is 320x176")
    end },

    { "a missing robot says so", function()
        local lv = level()
        lv.Entities.Robot2 = nil
        fails(function() Ldtk.convert(lv, "Lonely") end, "needs exactly one Robot2")
    end },

    { "a bad channel says so", function()
        fails(function()
            Ldtk.convert(level({ Button = { { x = 40, y = 144, w = 8, h = 8, channel = "z" } } }), "Odd")
        end, "channel must be a letter a to e")
    end },
}
