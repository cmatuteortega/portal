-- Every sound, made at load from nothing: a few voices per sound (an
-- oscillator swept from one pitch to another under a decaying envelope),
-- rendered once into a SoundData and played from a small pool of sources so
-- the same sound can overlap itself. No sample files.

local Sfx = { on = true }

local RATE = 22050
local TAU = math.pi * 2
local sin, floor, random = math.sin, math.floor, math.random

local function render(voices)
    local total = 0
    for _, v in ipairs(voices) do total = math.max(total, (v.at or 0) + v.dur) end
    local n = floor(total * RATE) + 1
    local buf = {}
    for i = 1, n do buf[i] = 0 end
    for _, v in ipairs(voices) do
        local start = floor((v.at or 0) * RATE)
        local len = floor(v.dur * RATE)
        local f0, f1 = v.f0, v.f1 or v.f0
        local phase, held = 0, 0
        for i = 0, len - 1 do
            local x = i / len
            local f = f0 * (f1 / f0) ^ x
            phase = phase + f / RATE
            local s
            if v.wave == "square" then
                s = (phase % 1) < 0.5 and 1 or -1
            elseif v.wave == "tri" then
                local p = phase % 1
                s = p < 0.5 and (4 * p - 1) or (3 - 4 * p)
            elseif v.wave == "noise" then
                -- Noise held for a pitch's worth of samples: grit, not hiss.
                if floor(phase) ~= floor(phase - f / RATE) then held = random() * 2 - 1 end
                s = held
            else
                s = sin(TAU * phase)
            end
            local env = math.min(1, i / (0.004 * RATE)) * (1 - x) ^ (v.curve or 2)
            local k = start + i + 1
            buf[k] = buf[k] + s * env * (v.vol or 0.5)
        end
    end
    local data = love.sound.newSoundData(n, RATE, 16, 1)
    for i = 1, n do data:setSample(i - 1, math.max(-1, math.min(1, buf[i]))) end
    return data
end

local DEFS = {
    shoot1 = { { wave = "square", f0 = 900, f1 = 1800, dur = 0.09, vol = 0.18 } },
    shoot2 = { { wave = "square", f0 = 600, f1 = 1200, dur = 0.09, vol = 0.18 } },
    open = {
        { wave = "sine", f0 = 220, f1 = 660, dur = 0.25, vol = 0.35 },
        { wave = "noise", f0 = 4000, f1 = 1500, dur = 0.2, vol = 0.08 },
    },
    fail = { { wave = "square", f0 = 180, f1 = 90, dur = 0.16, vol = 0.18 } },
    close = { { wave = "sine", f0 = 600, f1 = 150, dur = 0.2, vol = 0.25 } },
    teleport = {
        { wave = "sine", f0 = 300, f1 = 1200, dur = 0.14, vol = 0.3 },
        { wave = "noise", f0 = 6000, f1 = 2000, dur = 0.12, vol = 0.07 },
    },
    jump = { { wave = "square", f0 = 300, f1 = 520, dur = 0.08, vol = 0.12 } },
    grab = { { wave = "tri", f0 = 500, f1 = 700, dur = 0.06, vol = 0.3 } },
    drop = { { wave = "tri", f0 = 400, f1 = 250, dur = 0.07, vol = 0.3 } },
    door = {
        { wave = "noise", f0 = 900, f1 = 400, dur = 0.3, vol = 0.12, curve = 1 },
        { wave = "square", f0 = 110, f1 = 90, dur = 0.3, vol = 0.08, curve = 1 },
    },
    button = { { wave = "square", f0 = 1200, dur = 0.03, vol = 0.12 }, { wave = "square", f0 = 1600, dur = 0.03, at = 0.04, vol = 0.12 } },
    die = {
        { wave = "noise", f0 = 3000, f1 = 300, dur = 0.5, vol = 0.25 },
        { wave = "square", f0 = 400, f1 = 60, dur = 0.4, vol = 0.12 },
    },
    fizzle = { { wave = "noise", f0 = 8000, f1 = 2000, dur = 0.3, vol = 0.18 } },
    grill = { { wave = "noise", f0 = 5000, f1 = 5000, dur = 0.15, vol = 0.1 }, { wave = "sine", f0 = 900, f1 = 300, dur = 0.15, vol = 0.2 } },
    spawn = { { wave = "tri", f0 = 300, f1 = 900, dur = 0.15, vol = 0.3 } },
    tick = { { wave = "square", f0 = 1000, dur = 0.025, vol = 0.1 } },
    ready = { { wave = "tri", f0 = 660, dur = 0.08, vol = 0.3 }, { wave = "tri", f0 = 880, dur = 0.12, at = 0.08, vol = 0.3 } },
    win = {
        { wave = "tri", f0 = 523, dur = 0.14, vol = 0.3 },
        { wave = "tri", f0 = 659, dur = 0.14, at = 0.12, vol = 0.3 },
        { wave = "tri", f0 = 784, dur = 0.14, at = 0.24, vol = 0.3 },
        { wave = "tri", f0 = 1047, dur = 0.4, at = 0.36, vol = 0.3 },
    },
}

local pools = {}

function Sfx.load()
    for name, voices in pairs(DEFS) do
        local data = render(voices)
        local pool = { i = 1 }
        for k = 1, 4 do pool[k] = love.audio.newSource(data, "static") end
        pools[name] = pool
    end
end

function Sfx.play(name, pitch)
    local pool = pools[name]
    if not Sfx.on or not pool then return end
    local s = pool[pool.i]
    pool.i = pool.i % #pool + 1
    s:stop()
    s:setPitch((pitch or 1) * (0.96 + random() * 0.08))
    s:play()
end

return Sfx
