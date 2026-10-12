![Procedural Road World](docs/cover.jpg)

# Procedural Road World

Generate a road-connected open world from a seed, explore it on foot, and jump into a physics car.

A complete starter for exploration, driving, delivery, survival or open-world prototypes. Every visual is built from primitives and code, so it is easy to reskin.

## What's inside

- Seeded procedural terrain: by default 1152 x 1152 m in 36 chunks that render and collide on their own, up to 10 x 10 chunks or 2560 x 2560 m.
- A terrain-aware through road with four collision-backed T-junction branches, four level districts, 64 enterable house shells and four parkour spots.
- First- and third-person movement on foot with sprint, jump and mantle.
- An enterable four-wheel physics car with SPORT, CHILL or fully editable handling: mass, suspension, power, grip, drive split, traction control.
- Weather that cycles clear, overcast, rain and fog, with fog, sky and light changing together.
- Desktop controls plus a multi-touch Android layout, and a world settings panel to tweak and regenerate.

## Get started

1. [Download the ZIP](https://github.com/SummerEngine/template-3d-procedural-road-world/archive/refs/heads/codex/importable-template.zip) or clone the repo:
   `git clone https://github.com/SummerEngine/template-3d-procedural-road-world.git`
2. Open the folder in [Summer Engine](https://www.summerengine.com/download).
3. Press Play. Or run it from a terminal:

```bash
npx -y summer-engine@latest run .
```

At startup you pick a seed, world settings and a vehicle profile, then generate.

Summer's AI agent can extend it for you. Try asking:

- "Add delivery missions: pick up a package in one district and drop it off in another before a timer runs out."
- "Add simple AI traffic cars that follow the road network."
- "Add a day and night cycle with working car headlights."

## Controls

| Action | Input |
|---|---|
| Move or drive | W, A, S, D |
| Look around on foot | Mouse |
| Sprint | Shift |
| Jump on foot / handbrake and drift in the car | Space |
| Switch first/third person or cockpit/chase camera | V |
| Enter or exit the car | E |
| Reset the controlled actor | R |
| Show or hide the world parameter panel | F1 |
| Cycle clear, overcast, rain and fog | F2 |
| Pause menu (Resume, world settings, Quit) | Esc |
| Capture the mouse after closing menus | Left click |

On Android the game locks to landscape. On foot you get a left virtual stick, a right-side look drag and action buttons, all usable at the same time. In the car the stick becomes separate `BRAKE` / `GAS` buttons on the left and `LEFT` / `RIGHT` steering on the right. Android Back opens or closes the pause flow.

The world panel exposes seed, terrain feature scale, hill and mountain heights, mountain coverage, landmark scale, road width, maximum grade, earthwork width, branch count, plot size and decoration count. Press **Regenerate** to apply values or **Random Seed** for a new world.

## Customize it

- World generation: `scripts/world_generator.gd`
- Player movement and cameras: `scripts/movement_player.gd`
- Vehicle handling and appearance: `scripts/arcade_car.gd`
- Enter/exit flow and startup menus: `scripts/movement_lab.gd`
- Weather: `scripts/weather_system.gd`
- Desktop and mobile controls: `scripts/mobile_controls.gd`

The world is finite and regenerated from a seed. Persistence, traffic, missions, combat, interiors, streaming and multiplayer are left for the game you build on top.

## Verify

```bash
./scripts/verify.sh
```

The check covers deterministic regeneration, seed variation, shared chunk edges, road grades and collisions, terrain clearance, districts, parkour plots, the 64 house shells, the landmark mountain, decorations, weather, touch controls, movement and vehicle customization. Movement architecture, tuning and its own checklist are in [`MOVEMENT.md`](MOVEMENT.md).

## License

MIT. See [LICENSE](LICENSE). No external assets and no third-party runtime dependencies are included: terrain, roads, buildings, vegetation, player, car, UI and weather are all generated from Godot primitives and project code. See [`ASSETS.md`](ASSETS.md).
