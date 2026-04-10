# CLAUDE.md — BloxyGTA

GTA-style freemode prototype built in Godot 4.6 (GL Compatibility renderer).
Blocky/Roblox-style visuals — everything is made from BoxMesh3D nodes stacked together.

---

## Project Layout

```
scenes/          # .tscn scene files
  main.tscn      # root level — floor, player, dummy, car, all props
  player.tscn    # red box player with third-person camera
  dummy.tscn     # black box enemy (patrol, 3-hit health, debris)
  car.tscn       # orange sports car (multi-mesh bloxy style)
  props/         # 15 static prop scenes (roads, buildings, trees, etc.)
scripts/         # .gd scripts
  player.gd      # movement, camera, shooting, car enter/exit
  dummy.gd       # patrol AI, take_hit(), get_run_over(), debris spawn
  car.gd         # driving, drift, player-glue, run-over detection
docs/
  game_design_doc.md       # game vision, features, story
  technical_design_doc.md  # architecture, systems, props, known issues
```

## Reference Docs

- **Game design**: `docs/game_design_doc.md` — vision, planned features, art style, story
- **Technical design**: `docs/technical_design_doc.md` — architecture, all systems deep-dive, props list, rendering, known issues

---

## Collision Layers (3D Physics)

| Layer | Name | Value | Who uses it |
|---|---|---|---|
| 1 | World | 1 | Floor, all props (StaticBody3D) |
| 2 | Player | 2 | player.tscn |
| 3 | Enemy | 4 | dummy.tscn |
| 4 | Car | 8 | car.tscn |

**collision_mask rules:**
- Player mask = 1 (collides with World only)
- Dummy mask = 1 (collides with World only)
- Car mask = 5 (1+4 = World + Enemy, so it can run over dummies)
- Props mask = 0 (static, nothing needs to collide with them)
- Debris mask = 0 (layer 0 too — invisible to everything, just falls via gravity)

---

## Input Map

| Action | Key |
|---|---|
| move_forward | W |
| move_backward | S |
| move_left | A |
| move_right | D |
| jump | Space (also drift when in car) |
| sprint | Shift |
| interact | E (enter/exit car) |
| aim | Right Mouse Button |
| shoot | Left Mouse Button |

---

## Key Conventions

### Scene files
- All props use `StaticBody3D`, `collision_layer = 1`, `collision_mask = 0`
- Mesh Y-offset = half the mesh height (so prop sits on the floor when placed at Y=0)
- Collision shape Y-offset matches mesh Y-offset
- Sub-resource IDs use short descriptive strings (e.g. `id="mesh_body"`, `id="mat_orange"`)

### Scripts
- `move_and_slide()` used for CharacterBody3D (player, dummy, car)
- Gravity: `ProjectSettings.get_setting("physics/3d/default_gravity")`
- Debris: spawn as `RigidBody3D` with `collision_layer = 0`, set `linear_velocity` directly (not `apply_central_impulse`)
- Groups: car adds itself to `"cars"` group so player can find it via `get_nodes_in_group`

### Camera (on foot)
- `CameraPivot` Node3D at local (0, 1.5, 0) on player
- `Camera3D` at local (0, 0, 5) inside CameraPivot
- `camera.look_at(camera_pivot.global_position)` called every `_process` frame
- Mouse horizontal → `rotate_y` on player body; mouse vertical → `camera_pivot.rotation.x`

### Camera (in car)
- Camera locked — no mouse input while driving
- `camera_pivot.position.y = 2.5`, `camera.position.z = 8.0`, `camera_pivot.rotation.x = -0.35`
- Restored to on-foot values on exit

### Car forward direction
- Car moves along `-transform.basis.z` (Godot's default forward is -Z)
- Headlights/front bumper at negative Z; taillights/rear at positive Z
- Wheels: front pair at Z = -1.4, rear pair at Z = +1.4

---

## Common Gotchas

- **Debris blocking car**: Always set `collision_layer = 0` on spawned RigidBody3D debris
- **Debris not moving**: Use `linear_velocity` directly, not `apply_central_impulse` (unreliable right after `add_child`)
- **Black screen**: Needs `WorldEnvironment` with `ProceduralSkyMaterial` + `ambient_light_energy > 0`
- **Car direction**: Car's -Z is forward. Front visuals go at negative Z, rear at positive Z
