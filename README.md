# Portal Pals

A co-op 2D portal platformer for two robots, on one screen or two machines, in LÖVE. It's an MVP
in the spirit of Portal 2's co-op: each robot has its own pair of portals,
either robot can use either pair, and the six test chambers are built so the
two of you have to work together.

```sh
love .              # LÖVE 11.x
love . 5            # dev: straight into chamber 5
love . --shots      # dev: plays each chamber's scripted solution part way and
                    # writes screenshots to the save directory's shots/
love . --host       # play online as Blue, waiting for a partner
love . --join localhost   # ...and join it from a second window as Orange
luajit tests/run.lua    # the tests, no LÖVE needed
```

The chambers are drawn in [LDtk](https://ldtk.io): open `levels.ldtk`, edit,
save, and press **F5** in the game to reload them (see **Designing chambers**).

![Chamber 5, FLING](docs/fling.png)

## Controls

Both robots play on one keyboard, or with gamepads, or a mix; or one per machine
(see **Playing on two machines**).

| | Blue (left hand) | Orange (right hand) | Gamepad |
|---|---|---|---|
| move | A / D | ← / → | left stick, d-pad |
| aim | WASD (8 ways), or the mouse | arrows (8 ways) | right stick (or the left) |
| jump | Space | `/` (or numpad 0, right Ctrl) | A |
| portal 1 / 2 | Q / E, or left / right click | `,` / `.` (or numpad 1 / 2) | LB / RB (or triggers) |
| grab / drop a cube | F, or middle click | `;` (or numpad 3) | X or B |
| take down your portals | C | `'` (or numpad 4) | Y |

With one gamepad it plays Orange; with two, one each. **Tab** (or a pad's Back)
swaps which robot the two keyboard halves drive, so one person can play both
robots alone, slowly. **R** restarts the chamber, **Esc** goes back to the
chamber list, **F11** toggles fullscreen, **M** mutes, **F5** reloads the
chambers from `levels.ldtk`.

Taking down your portals removes both of your own (never your partner's), wherever
you are: the way out of a pair you've put somewhere that traps the chamber.

With no direction held, a robot aims the way it faces. The dashed line from
its gun shows where a shot will land, ending in a lit square if a portal fits
there and a grey X if it doesn't.

## Playing on two machines

One player hosts and plays **Blue**; the other joins and plays **Orange**. On the
title screen press **H** to host, or **J** to join and type the host's address
(a name or IP, `:port` if it isn't the usual 22122). Or from the command line:

```sh
love . --host               # host, on UDP port 22122
love . --host --port 23000  # another port
love . --join 192.168.1.20  # join (`--join` alone joins localhost)
```

Online, each machine has one robot and the whole of that machine's controls:
both keyboard halves, the mouse and every gamepad drive it (Tab does nothing).
The host picks the chambers and keeps the progress; the joiner follows along.
**R** on either machine restarts the chamber. **Esc** on the joiner leaves; on
the host it goes to the chamber list, and Esc there stops hosting. If either
side quits, the other is told within a couple of seconds and carries on alone.

**Testing on one machine:** run `love . --host` and, in a second terminal,
`love . --join localhost`. Each window drives its own robot from whichever has
the focus. Add `--mute` to one of them to hear one set of sounds.

Over the internet the host's UDP port 22122 has to be reachable (forwarded on
the router, or both on a VPN such as Tailscale); on a LAN it just works.

**How it works.** The host's game runs the rules exactly as on one machine.
The joiner's runs none: it sends its input every frame, and draws the
snapshots of the host's world that come back (60 a second) and plays the host's
events as its own sounds and sparks. So the two can never disagree about where
anything is, at the cost of the joiner's input being a round trip late, which
on a LAN is a frame or two. Presses are sent as running counts, so a lost packet
loses no jump. The host sends each chamber whole when it starts, so the two
machines needn't have the same `levels.ldtk`, and F5 on the host reloads both.
`src/wire.lua` is the format (and is tested headless); `src/net.lua` carries it
over ENet, which ships with LÖVE.

## How it plays

- **Portals** go on white panels only, two tiles long, with open air in front.
  Metal, doors and the edges of things refuse them. A robot's two portals lead
  only to each other; a pair works once both ends are placed. Blue's are blue
  and violet, Orange's orange and red.
- **Anything goes through any pair.** Robots and cubes both, and Orange can use
  Blue's portals as easily as its own. That's most of the co-op.
- **Speed in is speed out.** A body that falls 15 tiles into a floor portal
  comes out of a wall portal moving sideways at that speed. In the air you can
  steer up to a run, or against a fling, but nothing slows a fling you're going
  along with.
- **Robots are platforms.** Land on your partner's head and you ride it; jump
  from there and you reach a ledge one robot can't. A jump clears three tiles,
  not four. A four-tile step is the "boost me up" step.
- **Buttons** hold a door open while a robot or a cube stands on them. A door
  normally opens on any of its buttons; some want every button at once.
- **Cubes** are picked up, carried through portals, thrown (they keep the
  robot's speed), and set down on buttons.
- **Emancipation grills** wipe the portals of a robot that walks through them,
  and dissolve a carried cube, which comes back to its dropper.
- **Goo** kills a robot (it reappears where it started, portals intact) and
  dissolves a cube.
- **The exit** needs both robots inside it at once.

## The chambers

1. **PORTALS 101**: two white walls with goo between them. One portal on
   each wall and walk in.
2. **HOLD THE DOOR**: one robot holds the door for the other, which holds it
   back from the far side.
3. **BOOST**: a four-tile step. One robot climbs its partner's head, then
   stands on the button that opens the way round for it.
4. **CUBE**: carry the cube through a wall portal, out of the ceiling, onto
   the button.
5. **FLING**: four portals. Walk into Blue's pair, drop the height of the room
   from the ceiling into Orange's floor portal, and come out of the high wall
   flying across the goo.
6. **TOGETHER**: two buttons that must both be held, two cubes, and one of
   them up a step only a boost reaches.

Progress (the furthest chamber opened) is saved to `progress.txt` in LÖVE's
save directory, under `portal-coop/`.

## How it's built

The rules (`src/world.lua`) are plain Lua with no LÖVE calls in them, stepped at
a fixed 120Hz. That buys two things. A fling goes the same distance on every
machine whatever the frame rate. And the whole game runs headless, so
`tests/levels_test.lua` plays every chamber from spawn to exit with scripted
inputs. A change to the physics or to `levels.ldtk` that makes a chamber
unsolvable as designed fails a test rather than a playtest.

| File | What it is |
|---|---|
| `main.lua` | window, the low-res canvas, the whole-number zoom |
| `src/game.lua` | the screens (title, play, end), the fixed step, events → sounds and sparks, progress |
| `src/world.lua` | the rules: tiles, robots, cubes, portals, buttons, doors, the exit |
| `levels.ldtk` | the chambers, drawn in LDtk |
| `src/levels.lua`, `src/ldtk.lua` | the chamber list (and F5's reload); LDtk → the map the rules play |
| `lib/` | from buzo: `tilemapper.lua`, `json.lua`, `classic.lua`, unchanged |
| `src/defs.lua` | every number the rules use |
| `src/input.lua` | keyboard halves, mouse and gamepads → per-robot input |
| `src/net.lua`, `src/wire.lua` | online play: the ENet connection; what goes over it |
| `src/draw.lua` | paints a world, a whole pixel at a time |
| `src/sprites.lua` | the robots and the cube, as ASCII art |
| `src/palette.lua`, `src/font.lua` | the colours, and a 3x5 pixel face |
| `src/sfx.lua` | every sound, synthesised at load. No sample files |
| `src/shots.lua` | dev: `--shots` |
| `tests/` | `run.lua`, the mechanics tests, the chamber playthroughs (also with Orange online) and their driver |

### Rendering

Everything draws into a canvas of game pixels, scaled up by the largest whole
number that fits the 320x176 chamber in the window. Sprites are ASCII grids of
palette keys, lines are Bresenham-plotted, and nothing rotates. A robot facing
left is its sprite mirrored. These are the habits of the sibling Survive
School and Mycelio TD projects, carried over.

### Portals, exactly

A portal sits on one face of a tile: a normal pointing into the room, and a
tangent that is fixed per orientation (down for walls, right for floors and
ceilings) rather than turned with the normal. That choice means wall-to-wall
travel keeps which way is up and floor-to-floor keeps which way is forward,
which is what a player expects in 2D. A body teleports on the step where its
leading edge crosses a linked portal's face with its middle inside the
opening. Its speed into the face becomes speed out of the other (at least
`EXIT_MIN`, so nothing sits stuck in an opening), its sideways speed carries
over along the tangent, and it's placed just clear of the far face. If the far
side has no room, the portal behaves as a wall.

Movement resolves one axis at a time in steps of at most 3px, so nothing tunnels
through a one-tile wall even at fling speed, and the portals get first look
before each axis meets the tiles.

## Designing chambers

The chambers live in `levels.ldtk`, an [LDtk](https://ldtk.io) 1.5 project. It's
read with the `tilemapper` from buzo (`lib/tilemapper.lua`, vendored
unchanged, with its `json.lua` and `classic.lua`). `src/ldtk.lua` turns what
tilemapper gives back into the map `src/world.lua` plays, so nothing in the
rules knows about LDtk.

Open `levels.ldtk` in LDtk. Each level is one chamber, and they play in the
order of LDtk's level list (drag to reorder). A chamber is exactly one screen:
**320x176 px, 40x22 tiles of 8px**. Two layers:

**Tiles** (IntGrid). Paint what the chamber is made of. Empty is air.

| value | | |
|---|---|---|
| 1 `panel` | white | solid, **takes portals** |
| 2 `metal` | grey | solid, never takes a portal |
| 3 `goo` | green | kills a robot, dissolves a cube |
| 4 `grill` | cyan | wipes the portals of a robot walking through, dissolves a carried cube |

**Entities**. Place on the grid. Sizes are in whole tiles.

| entity | what to do |
|---|---|
| `Robot1`, `Robot2` | exactly one each: the tile Blue / Orange starts standing in (put it in the air tile just above a floor) |
| `Button` | in the air tile above a floor; stretch it sideways for a wider plate. `channel` a–e |
| `Door` | stretch it over the opening. `channel` a–e, the same letter as its buttons. Tick `needs_all` and it opens only while **every** button of that channel is held at once (two robots, or a robot and a cube); otherwise any one will do |
| `Cube` | a cube's dropper: where a cube appears, and reappears when it's lost |
| `Exit` | stretch it over the exit. Both robots inside at once finishes the chamber |
| `Hint` | `text` is painted on the back wall from that tile, in capitals |

Each level also has a `title` field (Level settings → Custom fields): the
chamber's name in game. Leave it empty and the level's identifier is used.

**The loop:** keep the game running (`love .`, or `love . 7` to go straight to
chamber 7), save in LDtk, press **F5**. The chamber restarts with your
changes. If the file has a mistake (no `Robot2`, a chamber the wrong size, a
channel that isn't a–e), the game keeps the chambers it had and prints what's
wrong along the bottom of the screen.

**Then a solution.** `luajit tests/run.lua` checks that every chamber loads.
A chamber with a scripted solution in `tests/levels_test.lua` (keyed by its
title) is also played to the exit on every push. Until it has one, the tests
pass with a note naming it. Add the script once the chamber settles: from then
on, a physics change that breaks the chamber fails CI instead of a playtest.
Renaming a chamber's `title` means renaming its solution too.

LDtk's own backups are switched off for this project, so git is the history.

## Not in the MVP

Prediction for the joiner's robot (it feels a round trip of lag), more than two players, chambers bigger than one screen, light bridges, lasers, gels, moving platforms,
and portals seen through portals.
