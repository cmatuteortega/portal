-- Every number the rules run on, in one place. Distances are game pixels (a
-- tile is 8), speeds pixels a second, times seconds.
--
-- The jump is sized against the tiles on purpose: JUMP clears three tiles
-- (28px peak) but not four, and a robot standing on its partner's head (14px
-- up) clears five. So a four-tile step is the "boost me" step, and the levels
-- lean on that. The fall speed cap is high so a fling keeps what it earned:
-- how far a fling carries is 2 * sqrt(fall * drop), whatever gravity is, as
-- long as nothing clips the speed on the way down.

return {
    TILE = 8,
    COLS = 40,
    ROWS = 22,

    PLAYER_W = 6,
    PLAYER_H = 14,
    CUBE = 8,

    GRAV = 900,
    RUN = 75,
    ACC_GROUND = 1000,
    FRICTION = 900,
    ACC_AIR = 450,
    AIR_DRAG = 40,
    JUMP = 232,
    JUMP_CUT = 0.45,
    MAXFALL = 640,
    COYOTE = 0.09,
    BUFFER = 0.12,

    PORTAL_LEN = 16,
    -- Least speed a body leaves a portal with: enough to be clear of the
    -- opening rather than sitting in it. Walking into a portal on a floor
    -- (from one on a wall) pops you out with a little hop.
    EXIT_MIN = 110,
    RAY_MAX = 480,
    FIRE_COOLDOWN = 0.15,

    REACH = 13,        -- how close a cube must be to pick up
    RESPAWN = 0.9,
    CUBE_RESPAWN = 0.7,
    EXIT_HOLD = 0.6,   -- both robots in the exit this long ends the level
}
