-- Just enough of LÖVE for the rules and the level loader to run under plain
-- LuaJIT: reading a file from the game's folder (tilemapper reads levels.ldtk
-- through love.filesystem).

love = love or {}
love.filesystem = love.filesystem or {
    read = function(path)
        local f = assert(io.open(path, "rb"))
        local data = f:read("*a")
        f:close()
        return data
    end,
}
