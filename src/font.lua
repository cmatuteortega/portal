-- A 3x5 pixel face, built at load into a LÖVE ImageFont: LÖVE's own vector font
-- would smear across a 320x180 canvas. Glyphs are white and tinted with
-- setColor. Lower case is drawn as upper case: there is only the one case.

local Font = {}

local G = {
    A = { ".#.", "#.#", "###", "#.#", "#.#" }, B = { "##.", "#.#", "##.", "#.#", "##." },
    C = { ".##", "#..", "#..", "#..", ".##" }, D = { "##.", "#.#", "#.#", "#.#", "##." },
    E = { "###", "#..", "##.", "#..", "###" }, F = { "###", "#..", "##.", "#..", "#.." },
    G = { ".##", "#..", "#.#", "#.#", ".##" }, H = { "#.#", "#.#", "###", "#.#", "#.#" },
    I = { "###", ".#.", ".#.", ".#.", "###" }, J = { "..#", "..#", "..#", "#.#", ".#." },
    K = { "#.#", "##.", "#..", "##.", "#.#" }, L = { "#..", "#..", "#..", "#..", "###" },
    M = { "#.#", "###", "###", "#.#", "#.#" }, N = { "##.", "#.#", "#.#", "#.#", "#.#" },
    O = { ".#.", "#.#", "#.#", "#.#", ".#." }, P = { "##.", "#.#", "##.", "#..", "#.." },
    Q = { ".#.", "#.#", "#.#", "##.", ".##" }, R = { "##.", "#.#", "##.", "#.#", "#.#" },
    S = { ".##", "#..", ".#.", "..#", "##." }, T = { "###", ".#.", ".#.", ".#.", ".#." },
    U = { "#.#", "#.#", "#.#", "#.#", "###" }, V = { "#.#", "#.#", "#.#", "#.#", ".#." },
    W = { "#.#", "#.#", "###", "###", "#.#" }, X = { "#.#", "#.#", ".#.", "#.#", "#.#" },
    Y = { "#.#", "#.#", ".#.", ".#.", ".#." }, Z = { "###", "..#", ".#.", "#..", "###" },
    ["0"] = { "###", "#.#", "#.#", "#.#", "###" }, ["1"] = { ".#.", "##.", ".#.", ".#.", "###" },
    ["2"] = { "##.", "..#", ".#.", "#..", "###" }, ["3"] = { "##.", "..#", ".#.", "..#", "##." },
    ["4"] = { "#.#", "#.#", "###", "..#", "..#" }, ["5"] = { "###", "#..", "##.", "..#", "##." },
    ["6"] = { ".##", "#..", "###", "#.#", "###" }, ["7"] = { "###", "..#", ".#.", ".#.", ".#." },
    ["8"] = { "###", "#.#", "###", "#.#", "###" }, ["9"] = { "###", "#.#", "###", "..#", "##." },
    [":"] = { "...", ".#.", "...", ".#.", "..." }, ["."] = { "...", "...", "...", "...", ".#." },
    [","] = { "...", "...", "...", ".#.", "#.." }, [";"] = { "...", ".#.", "...", ".#.", "#.." },
    ["-"] = { "...", "...", "###", "...", "..." }, ["+"] = { "...", ".#.", "###", ".#.", "..." },
    ["/"] = { "..#", "..#", ".#.", "#..", "#.." }, ["!"] = { ".#.", ".#.", ".#.", "...", ".#." },
    ["?"] = { "##.", "..#", ".#.", "...", ".#." }, ["'"] = { ".#.", ".#.", "...", "...", "..." },
    ["("] = { "..#", ".#.", ".#.", ".#.", "..#" }, [")"] = { "#..", ".#.", ".#.", ".#.", "#.." },
    ["<"] = { "..#", ".#.", "#..", ".#.", "..#" }, [">"] = { "#..", ".#.", "..#", ".#.", "#.." },
    ["="] = { "...", "###", "...", "###", "..." }, ["_"] = { "...", "...", "...", "...", "###" },
    ["*"] = { "...", "#.#", ".#.", "#.#", "..." }, ["#"] = { "#.#", "###", "#.#", "###", "#.#" },
    [" "] = { "...", "...", "...", "...", "..." },
}

Font.HEIGHT = 5
Font.ADVANCE = 4

function Font.load()
    local order = {}
    for ch in pairs(G) do order[#order + 1] = ch end
    table.sort(order)
    -- ImageFont layout: a separator column, then each glyph followed by one.
    local width = 1 + #order * 4
    local data = love.image.newImageData(width, 5)
    data:mapPixel(function(x)
        if x % 4 == 0 then return 1, 0, 1, 1 end
        return 0, 0, 0, 0
    end)
    for i, ch in ipairs(order) do
        local x0 = 1 + (i - 1) * 4
        for y, row in ipairs(G[ch]) do
            for x = 1, 3 do
                if row:sub(x, x) == "#" then data:setPixel(x0 + x - 1, y - 1, 1, 1, 1, 1) end
            end
        end
    end
    Font.font = love.graphics.newImageFont(data, table.concat(order), 1)
    Font.font:setFilter("nearest", "nearest")
    love.graphics.setFont(Font.font)
end

function Font.width(text)
    return #text * Font.ADVANCE - 1
end

function Font.print(text, x, y)
    love.graphics.print(text:upper(), math.floor(x), math.floor(y))
end

function Font.center(text, cx, y)
    Font.print(text, cx - Font.width(text) / 2, y)
end

-- A word in a colour, with a dark pixel of shadow under it so it reads on
-- anything.
function Font.shadow(text, x, y, key, P)
    P.set("k")
    Font.print(text, x + 1, y + 1)
    P.set(key)
    Font.print(text, x, y)
end

return Font
