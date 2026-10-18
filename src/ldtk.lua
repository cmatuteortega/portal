-- The chambers come from levels.ldtk, drawn in LDtk (https://ldtk.io), read by
-- buzo's tilemapper (lib/tilemapper.lua, vendored unchanged) and turned here
-- into the plain level tables src/world.lua takes: 40x22 rows of characters in
-- the alphabet at the top of world.lua, a name, `need`, and hints. The rules
-- never see LDtk, so the scripted chamber tests stay what they were.
--
-- The project, as LDtk shows it:
--
--   Tiles     IntGrid, 8px: 1 panel (white, takes portals), 2 metal, 3 goo,
--             4 grill. Empty is air. Nothing is drawn from a tileset: the game
--             paints every tile itself (src/draw.lua), so the editor colours
--             are only there to tell them apart.
--   Entities  Robot1, Robot2   the tile each robot starts standing in
--             Cube             a cube's dropper
--             Button           stretch it sideways; `channel` a..e
--             Door             stretch it to the opening; `channel`, and
--                              `needs_all` for every button of the channel at
--                              once rather than any one
--             Exit             stretch it over the exit
--             Hint             `text`, painted on the back wall from its tile
--   Level     `title`, the name shown in game (else the level's identifier)
--
-- A chamber is one screen, 320x176 (40x22 tiles); the chambers play in the
-- order of LDtk's level list. tilemapper only builds images for tile and auto
-- layers, which this project has none of, so all of this runs headless too.

Class = Class or require "lib.classic"
local json = require "lib.json"
local Tilemapper = require "lib.tilemapper"
local D = require "src.defs"

local T = D.TILE
local TILE_CHAR = { [1] = "#", [2] = "X", [3] = "~", [4] = "|" }

local Ldtk = {}

local function tilesOf(ent)
    local tx, ty = math.floor(ent.x / T + 0.5), math.floor(ent.y / T + 0.5)
    local tw = math.max(1, math.floor(ent.w / T + 0.5))
    local th = math.max(1, math.floor(ent.h / T + 0.5))
    return tx, ty, tw, th
end

-- One tilemapper level -> one World level table. Errors name the chamber and
-- what is wrong with it, since they are what a designer sees after a save.
function Ldtk.convert(lv, name)
    local where = name
    assert(lv.width == D.COLS * T and lv.height == D.ROWS * T,
        ("%s: a chamber is %dx%d px, this one is %dx%d"):format(where, D.COLS * T, D.ROWS * T, lv.width, lv.height))
    local grid = {}
    for y = 0, D.ROWS - 1 do
        grid[y] = {}
        for x = 0, D.COLS - 1 do grid[y][x] = "." end
    end
    local function put(x, y, ch)
        if x >= 0 and y >= 0 and x < D.COLS and y < D.ROWS then grid[y][x] = ch end
    end

    local tiles = assert(lv.Tiles, where .. ": no Tiles layer")
    for _, t in ipairs(tiles.tiles) do
        put(math.floor(t.x / T), math.floor(t.y / T), TILE_CHAR[t.v] or ".")
    end

    local ents = assert(lv.Entities, where .. ": no Entities layer")
    local need, hints = {}, {}
    local function each(kind, fn)
        for _, e in ipairs(ents[kind] or {}) do fn(e, tilesOf(e)) end
    end
    local function channel(e, kind)
        local ch = (e.channel or "a"):lower()
        assert(ch:match("^[a-e]$"), ("%s: a %s's channel must be a letter a to e, not %q"):format(where, kind, tostring(e.channel)))
        return ch
    end

    each("Exit", function(_, tx, ty, tw, th)
        for y = ty, ty + th - 1 do for x = tx, tx + tw - 1 do put(x, y, "*") end end
    end)
    each("Door", function(e, tx, ty, tw, th)
        local ch = channel(e, "door")
        if e.needs_all then need[ch] = "all" end
        for y = ty, ty + th - 1 do for x = tx, tx + tw - 1 do put(x, y, ch:upper()) end end
    end)
    each("Button", function(e, tx, ty, tw)
        local ch = channel(e, "button")
        for x = tx, tx + tw - 1 do put(x, ty, ch) end
    end)
    each("Cube", function(_, tx, ty) put(tx, ty, "o") end)
    for i = 1, 2 do
        local list = ents["Robot" .. i] or {}
        assert(#list == 1, ("%s: needs exactly one Robot%d, has %d"):format(where, i, #list))
        local tx, ty = tilesOf(list[1])
        put(tx, ty, tostring(i))
    end
    each("Hint", function(e, tx, ty)
        if e.text and e.text ~= "" then hints[#hints + 1] = { tx, ty, e.text:upper() } end
    end)

    local map = {}
    for y = 0, D.ROWS - 1 do
        local row = {}
        for x = 0, D.COLS - 1 do row[#row + 1] = grid[y][x] end
        map[#map + 1] = table.concat(row)
    end
    local title = lv.title
    if not title or title == "" then title = name:gsub("_", " "):upper() end
    return { name = title, id = name, need = need, hints = hints, map = map }
end

-- Every chamber in levels.ldtk (or `path`), in the order of LDtk's level list.
function Ldtk.load(path)
    path = path or "levels.ldtk"
    local map = Tilemapper(path, { collisions = { true, true, true, true } })
    -- tilemapper keys levels by name; the order is the project's own list.
    local raw = json.decode(love.filesystem.read(path))
    local levels = {}
    for _, l in ipairs(raw.levels) do
        levels[#levels + 1] = Ldtk.convert(map.levels[l.identifier], l.identifier)
    end
    return levels
end

return Ldtk
