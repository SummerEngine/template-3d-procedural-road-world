# Procedural Road World

A complete Summer Engine / Godot starter project for a generated open world with terrain-aware roads, an on-foot controller, and an enterable physics car. It is intended as a clean base for GTA-like exploration, driving, delivery, survival, or open-world prototypes.

At startup, the candidate chooses a fresh random seed and lets you edit world generation settings plus a SPORT, CHILL, or fully editable vehicle profile before generating. Vehicle settings include real rigid-body mass, suspension, speed/power, grip/recovery, drive split, traction control, and unoccupied parking. The default world is 1152 × 1152 m with 36 independently rendered/collidable chunks, while the menu can generate up to 10 × 10 chunks or 2560 × 2560 m at the largest chunk size. The resolution selector automatically respects the previous maximum terrain-cell budget when the chunk count grows. The world contains a through road with four collision-backed T-junction branches, four separated 112 × 112 m level districts, 64 simple enterable house shells, four terrain-level procedural parkour locations, dense terrain-anchored trees and rocks, mostly rolling lowlands, and one dominant mountain landmark.

Weather starts in rain mode and can cycle through fog, clear, and overcast states. The rain emitter follows the active camera instead of filling the whole square-kilometre world, while each atmospheric state adjusts fog, sky color, ambient light, and directional-light energy together.

## Run

Open the project in Summer Engine and press Play, or run:

```bash
npx -y summer-engine@latest run .
```

## Controls

- `WASD` — move or drive
- Mouse — look around on foot
- `Shift` — sprint
- `Space` — jump on foot; handbrake/drift in the car
- `V` — switch first/third-person or cockpit/chase camera
- `E` — enter or exit the car
- `R` — reset the controlled actor
- `F1` — show/hide the world parameter panel
- `F2` — cycle clear, overcast, rain, and fog
- `Esc` — pause menu with Resume, world settings, and Quit to Desktop
- left click — capture the mouse after closing menus

On Android, the game is locked to sensor-aware landscape orientation. On foot, every finger is tracked independently, so the left virtual stick, right-side look drag, and action buttons can be held together. In the car, the stick is replaced by separate `BRAKE` and `GAS` buttons on the left and `LEFT` and `RIGHT` steering buttons on the right; throttle and steering therefore remain full-strength independent touches. The remaining buttons cover jump/drift, sprint, enter/exit, camera, reset, weather, and pause. Android Back also opens or closes the pause flow instead of quitting immediately.

The scrollable panel exposes seed, terrain feature scale, macro/hill/mountain/detail heights, mountain coverage, landmark scale, road width, maximum grade, earthwork width, branch count, buildable-plot dimensions and edge blend, and decoration count. Press **Regenerate** to apply values or **Random Seed** for a new world.

## Verify

```bash
./scripts/verify.sh
```

The check verifies deterministic regeneration, different-seed variation, exact shared chunk-edge vertices and normals, road grades and collisions, terrain clearance, separated level districts, parkour plots, 64 settlement shells, the landmark mountain, decorations, weather transitions, touch controls, movement, and vehicle customization.

Movement architecture, tuning, sources, and its separate test checklist are in [`MOVEMENT.md`](MOVEMENT.md).

## Customize this template

- World generation: `scripts/world_generator.gd`
- Player movement and cameras: `scripts/movement_player.gd`
- Vehicle handling and appearance: `scripts/arcade_car.gd`
- Enter/exit flow and startup menus: `scripts/movement_lab.gd`
- Weather: `scripts/weather_system.gd`
- Desktop/mobile controls: `scripts/mobile_controls.gd`

The current world is finite and regenerated from a seed. Persistence, traffic, missions, combat, interiors, streaming, and multiplayer are intentionally left for the game built on top.

## Licensing

No external or generated assets and no third-party runtime dependencies are included. The terrain, roads, buildings, vegetation, player placeholder, car, UI, and weather are generated from Godot primitives and project code. See [`ASSETS.md`](ASSETS.md).
