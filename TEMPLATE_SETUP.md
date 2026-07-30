# Template setup

The project is ready to run after import. `project.godot` already points to `res://main.tscn` and the game registers its required input actions in code.

Good first changes:

1. Rename the project in `project.godot`.
2. Tune the default world in `scripts/world_generator.gd`.
3. Change the car profiles and materials in `scripts/arcade_car.gd`.
4. Replace the procedural player placeholder in `scripts/movement_player.gd`.
5. Add one focused gameplay loop such as deliveries, races, exploration objectives, or survival.

Keep the finite seeded-world generator intact until the chosen gameplay loop has been verified. Infinite streaming and multiplayer are not part of this starter.
