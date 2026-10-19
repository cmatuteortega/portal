# CLAUDE.md

Guidance for Claude Code when working in this repository.

Portal Pals: a co-op 2D portal platformer in LÖVE 11.x (LuaJIT / Lua 5.1:
`unpack` is a global). `README.md` is the design document: the controls, the
rules, the six chambers and why the numbers are what they are. Read it before
a behavioural change and update it when behaviour changes.

## Running

```sh
love .                  # the game
love . 3                # straight into chamber 3 (F5 in game reloads levels.ldtk)
love . --shots          # screenshots of every chamber mid-solution (save dir, shots/)
love . --host           # online: host as Blue (UDP 22122; --port N for another)
love . --join localhost # online: join as Orange, in a second window to test locally
luajit tests/run.lua    # the tests: mechanics + every chamber played to the exit
for f in main.lua conf.lua lib/*.lua src/*.lua tests/*.lua; do luac5.1 -p "$f" || echo "FAILED $f"; done
```

Headless screenshots in a container: `xvfb-run -a love . --shots --mute`.

## Rules that hold everywhere

- **`src/world.lua` never calls LÖVE.** The rules run under plain LuaJIT in the
  tests; anything that needs LÖVE (sound, drawing, input) reacts to
  `World.events` from `src/game.lua` instead.
- **The rules step at a fixed 120Hz** (`Game.update`). Never feed the world a
  frame's `dt`.
- **Chambers are designed in LDtk** (`levels.ldtk`; README **Designing
  chambers** has the layers and entities). Don't hand-edit the JSON for design
  changes: the user designs there. A new entity or tile kind is a row in the
  project's defs, a case in `src/ldtk.lua`, and a character in
  `src/world.lua`'s alphabet. `lib/` (tilemapper, json, classic) is vendored
  from buzo unchanged: keep it that way so it can be re-synced.
- **Chambers with a scripted solution** in `tests/levels_test.lua` (keyed by
  title) are played to the exit on every push; a physics change that breaks one
  is a regression unless the chamber is redesigned on purpose. A chamber
  without one only has to load (the tests print a note). Write one once a
  chamber settles.
- **Online, the host runs the rules and the joiner only draws.** The joiner's
  world is filled from `Wire.snapshot`, so anything new that the drawing or the
  play screen reads off a world must go into the snapshot (and `Wire.apply`),
  and a new press into `Wire.EDGES`. `tests/wire_test.lua` plays every chamber
  with Orange's input through the wire and checks the joiner's copy each frame.
- **Whole pixels only**: everything renders into the low-res canvas scaled by a
  whole number (`main.lua`). No `love.graphics.line`/`circle`, no rotation
  (mirroring is fine): use `Draw.line` and rectangles.
- **Colours come from `src/palette.lua`** by key. Sprites are ASCII in
  `src/sprites.lua`.
- **Numbers live in `src/defs.lua`.** Several encode level design: `JUMP` clears
  three tiles but not four, and a boost off a partner's head (14px) clears
  five. Don't nudge them without re-running the chamber tests.

## Where things live

`main.lua` (canvas, zoom), `src/game.lua` (screens, step, events → sound and
sparks, progress, F5 reload), `src/world.lua` (the rules and the map legend),
`levels.ldtk` + `src/ldtk.lua` + `src/levels.lua` (the chambers), `src/input.lua` (keyboard halves, mouse, pads), `src/net.lua` (ENet
connection) + `src/wire.lua` (messages, snapshots, input), `src/draw.lua`,
`src/sprites.lua`, `src/palette.lua`, `src/font.lua`, `src/sfx.lua` (synthesised
sounds), `src/shots.lua` (dev). CI: `.github/workflows/test.yml` (syntax +
tests) and `build.yml` (game.love + a fused Windows build; Releases on `v*`).
Anything the game reads at run time (`levels.ldtk`, `lib/`) must be in
`build.yml`'s zip.

## Style

Comments explain why (the trade-off, the feel, the bug avoided) rather than
restating code, and modules open with a paragraph saying what they are. Match it.
