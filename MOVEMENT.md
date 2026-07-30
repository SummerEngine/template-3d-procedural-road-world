# Movement Lab — candidate notes

Owner: Velizard  
Acceptance: candidate until the user confirms that on-foot movement, cameras, mantle, and driving feel good and have no known bugs.

This movement layer uses the existing procedural terrain and road as its test world. It does not change the terrain generator's ownership or mix movement guidance into the world-generation documentation.

## Playable slice

- One `CharacterBody3D` controller with first-person and over-the-shoulder cameras.
- Fast acceleration and braking, sprint FOV response, asymmetric fall gravity, coyote time, jump buffering, jump cut, air control, floor snap, and automatic low-ledge mantle.
- One custom four-wheel `RigidBody3D` car with enter/exit, cockpit/chase cameras, acceleration/braking/drag, per-wheel raycast suspension with a vertical fallback probe and bounded spring load, a shared longitudinal/lateral friction budget, progressive grip loss/recovery, and slip-driven skid marks.
- Four seed-driven roadside parkour locations built as scaffold runs, ruins, and cargo yards. The world planner reserves and flattens each terrain footprint before placement; a thin collision-backed slab sits 18 cm above that level surface, and raised decks have visible supports.
- A startup generation menu and a real Esc pause menu with Resume, world settings, and Quit to Desktop.
- Primitive-only presentation; no external or generated assets.

## Controls

| Input | On foot | In car |
| --- | --- | --- |
| `WASD` | Move | Throttle/brake/steer |
| Mouse | Look | — |
| `Shift` | Sprint | — |
| `Space` | Jump | Handbrake / reduced lateral grip |
| `V` | First/third-person camera | Cockpit/chase camera |
| `E` | Enter nearby car | Exit car |
| `R` | Reset player | Reset car |
| `F1` | Toggle world panel | Toggle world panel |
| `F2` | Cycle weather | Cycle weather |
| `Esc` | Pause / generation settings / quit | Pause / generation settings / quit |

## Implementation boundaries

- `scripts/movement_player.gd` owns character physics, camera switching, and mantle detection.
- `scripts/arcade_car.gd` owns the rigid chassis, four suspension/tire contact points, and vehicle cameras.
- `scripts/movement_lab.gd` places actors and obstacles on the generated road and owns startup/pause menus, enter/exit, input routing, and the movement HUD.
- `scripts/world_generator.gd` remains the source of terrain height, collision, road points, and reserved level parkour/district footprints.
- `scripts/weather_system.gd` owns camera-following rain, fog/sky/light presets, and the F2 weather status.

The car is deliberately not a Forza-scale tire simulation. Four suspension raycasts measure independent spring travel, with a world-down fallback when chassis tilt would otherwise miss a surface; spring and damping forces are capped before they are applied to the rigid chassis at each contact point. The road ribbons now own matching collision, so the tire contact and visible asphalt share a surface. The two front tire directions follow the steering angle, and lateral tire forces at those contact points turn the chassis. There is no direct `rotate_y()` steering. Steering pivots rotate around local Y while separate roll pivots spin around local X, so visible wheel steering and rolling cannot overwrite each other.

High-speed steering is limited by the lateral acceleration the tires can reasonably request: `atan(wheelbase * target_lateral_acceleration / speed²)`, capped by the low-speed steering angle. A bounded yaw-rate assist closes the gap between the bicycle-model target and the rigid chassis without rotating it directly or lowering tire grip. Ordinary cornering still saturates the instantaneous friction budget when necessary, but it no longer lowers the persistent grip state; braking slip and the deliberate handbrake drift remain the two ways to reduce and progressively recover grip. This avoids both the previous positive feedback where any sustained fast turn became an uncontrollable slide and the over-correction where a stable car barely changed course.

`MovementLab` must process while paused so its menus can receive Resume/Quit input. The player and car therefore override the inherited mode with `PROCESS_MODE_PAUSABLE`; otherwise their physics would inherit `ALWAYS` from the menu owner and continue under the Esc overlay.

Longitudinal drive/brake demand and lateral cornering demand now share one per-wheel friction budget. Grip loss begins only after demand exceeds that budget, while a deliberate handbrake drift can still lower rear grip; releasing the handbrake does not restore it in one frame. Hard braking while steering can therefore slide and mark the road without the drift key. Skid ribbons are emitted from measured slip, bounded to `max_skid_segments`, and lifted by a configurable `skid_surface_lift` because the current visual road is 18 cm above its terrain collision.

Godot documents limitations in its built-in `VehicleBody3D` and recommends custom `CharacterBody3D` or `RigidBody3D` vehicle physics for more advanced behavior. The custom rigid-body route was chosen so suspension, center of mass, tire grip, and force application remain explicit and testable.

## Feel controls

On foot, start with `walk_speed = 9`, `sprint_speed = 14`, `ground_acceleration = 72`, `jump_velocity = 9`, and `gravity = 28`. The target is immediate, aggressive traversal rather than realistic human locomotion. Mantle duration is `0.52 s`; it was increased from `0.24 s` so the movement remains readable.

For the car, tune `vehicle_mass` and `center_of_mass_drop` first, then `suspension_stiffness` / `suspension_damping`, then tire stiffness/friction, and only then engine and braking forces. These values affect the actual rigid body; mass is not a display-only statistic. `max_steering_angle` gives the low-speed wheel angle while high-speed steering is reduced automatically. Lower `drift_rear_stiffness` or `drift_rear_friction`, or increase `grip_recovery_seconds`, for a longer slide.

The startup/pause settings expose `SPORT`, `CHILL`, and editable `CUSTOM` handling. Runtime controls include mass, center-of-mass drop, suspension stiffness/damping, top speed, engine/brake force, base/sliding/drift grip, recovery time, front drive share, traction control, and whether an unoccupied car is frozen in place. Every lower-level value remains an exported property in `arcade_car.gd`; the presets are candidate starting points, not claims of universal correctness.

## Verification

Automated movement check:

```bash
/Applications/Summer.app/Contents/MacOS/Summer --headless \
  --path /Users/velizard/Projects/summer-knowledge-lab/games/procedural-road-world \
  --script res://tests/verify_movement.gd
```

The automated check covers startup generation, level and visibly raised procedural parkour foundations, procedural rebuilding, FPS/TPS movement, jump and mantle limits, vehicle entry/exit, active-car pause immobility, no direct stationary yaw, acceleration, four-wheel contact, unequal suspension travel, real chassis tilt, moving steering, drift, both vehicle cameras, high-speed steering stability, and rebuilding after regeneration. The dedicated steering regression holds full steering for 1.5 seconds after accelerating past 80 km/h; the current sample changed course by `30.43°` at `108.5 km/h`, retained `1.00` rear grip, and kept body slip at `7.25°`.

Vehicle customization regression:

```bash
/Applications/Summer.app/Contents/MacOS/Summer --headless \
  --path /Users/velizard/Projects/summer-knowledge-lab/games/procedural-road-world \
  --script res://tests/verify_vehicle_customization.gd
```

It verifies separate steering-Y and rolling-X axes, a manually selected 1475 kg real rigid-body mass, the 1150 kg SPORT preset, stationary unoccupied parking without frozen-force accumulation, more than 80 km/h after three seconds in SPORT, braking/cornering slip, skid emission without the drift key, non-instant drift recovery, and progressive grip restoration. The latest stable-acceleration sample reached `100.4 km/h` with four wheel contacts and rear grip at `1.00`; the braking and deliberate-drift stages still produce and recover from measured slip.

Human checks still required before acceptance:

1. Sprint, stop, strafe, and change direction in both camera modes.
2. Tap jump just before landing and just after leaving an edge.
3. Run through several roadside scaffold/ruin/cargo locations; mantle the low access step, chain jumps across supported decks, and confirm the tall wall is rejected.
4. Enter the car, accelerate, brake, reverse, hit slalom blocks, and switch both cameras.
5. Drive slowly on a bend and confirm the car cannot rotate in place or turn with a constant yaw rate.
6. Cross a slope and watch that individual wheels compress while the chassis pitches/rolls instead of staying parallel to the horizon.
7. Hold `Space` while steering above roughly 25 km/h and judge drift control, recovery, and perceived weight.
8. Press `Esc` while the occupied car is moving, release all driving input, wait several seconds, and confirm the chassis remains exactly still; Resume must not launch it.
9. Regenerate the world from `F1`, then repeat entry, reset, and collision checks.
10. Compare SPORT and CHILL, then change mass/center of mass/grip separately and confirm each produces a distinct, understandable effect.

## Sources used for this candidate

- [Godot `CharacterBody3D`](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html) — velocity, `move_and_slide()`, floor detection, floor snap, and collision queries.
- [Godot 3D player movement](https://docs.godotengine.org/en/stable/getting_started/first_3d_game/03.player_movement_code.html) — physics-step movement and gravity baseline.
- [Godot `SpringArm3D`](https://docs.godotengine.org/en/stable/classes/class_springarm3d.html) — collision-aware third-person camera boom.
- [Godot `RigidBody3D`](https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html) — applying forces at contact offsets, center-of-mass control, damping, and continuous collision detection.
- [Godot ray casting](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html) — direct-space wheel contact queries during physics updates.
- [Godot `VehicleBody3D`](https://docs.godotengine.org/en/stable/classes/class_vehiclebody3d.html) — documented built-in limitations that motivated the custom four-ray rigid-body implementation.
- [Godot `Input`](https://docs.godotengine.org/en/stable/classes/class_input.html) — analog action strengths used by the virtual stick and force-driven steering.
- [Godot `InputEventScreenTouch`](https://docs.godotengine.org/en/stable/classes/class_inputeventscreentouch.html) — stable per-finger indices used by the multitouch ownership map.
- [Godot `ImmediateMesh`](https://docs.godotengine.org/en/stable/classes/class_immediatemesh.html) — small dynamic triangle ribbons used for bounded skid marks.
- [Godot `GPUParticles3D`](https://docs.godotengine.org/en/stable/classes/class_gpuparticles3d.html) — bounded camera-following rain emission and particle draw meshes.
- [Godot `Environment`](https://docs.godotengine.org/en/stable/classes/class_environment.html) — fog density, fog color, sky, and ambient-light settings used by weather modes.
- [DOOM design interview with Marty Stratton and Hugo Martin](https://www.gamedeveloper.com/design/-make-me-think-make-me-move-new-i-doom-i-s-deceptively-simple-design) — fast movement and continuous repositioning as core goals.
- [Forza Motorsport tire-physics overview](https://forza.net/news/forza-motorsport-drivatars-tire-physics) — acceleration/cornering/braking fidelity and the full-simulation reference that this prototype intentionally simplifies.
