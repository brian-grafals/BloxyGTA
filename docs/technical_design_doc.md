# BloxyGTA — Technical Design Document

*Godot 4.6 — GL Compatibility renderer — Started April 2026*

---

## Architecture Overview

BloxyGTA is a single-scene 3D game. Everything lives in `scenes/main.tscn`. There is no scene switching yet — the player, dummies, car, and all props are instanced directly into Main.

```
Main (Node3D)
├── WorldEnvironment      — sky + ambient light
├── DirectionalLight3D    — sun
├── Floor (StaticBody3D)  — 150×1×150 gray plane
├── Player (CharacterBody3D)
├── Dummy (CharacterBody3D)
├── Car (CharacterBody3D)
└── Props × 20+           — StaticBody3D instances from scenes/props/
```

---

## Physics Layers

| Bit | Layer Name | Value | Used By |
|---|---|---|---|
| 1 | World | 1 | Floor, all props |
| 2 | Player | 2 | Player |
| 3 | Enemy | 4 | Dummy |
| 4 | Car | 8 | Car |

Debris RigidBody3D nodes use `collision_layer = 0` and `collision_mask = 0` so they pass through everything. They still fall due to gravity and auto-delete after 4 seconds via a Timer.

---

## Player (`scripts/player.gd`)

**Node type:** `CharacterBody3D`
**Collision:** layer 2, mask 1 (World only)

### Movement
- Walk speed: 6.0 u/s, Sprint: 12.0 u/s
- Jump velocity: 7.0 u/s (instant Y velocity set)
- `move_and_slide()` each physics frame
- Gravity applied manually when not on floor

### Camera
- `CameraPivot` Node3D sits at (0, 1.5, 0) local — follows player position
- `Camera3D` at (0, 0, 5) inside CameraPivot — 5 units behind pivot
- `camera.look_at(camera_pivot.global_position)` called every frame
- Mouse X → `player.rotate_y()` (full body turns)
- Mouse Y → `camera_pivot.rotation.x` clamped to [-1.2, 0.4] rad
- Right-click aim zooms FOV from 75° → 50°, turns crosshair red

### Shooting
- Raycast from screen center, 100 m range
- `PhysicsRayQueryParameters3D`, excludes player's own RID
- Calls `result.collider.take_hit(position, direction)` if the method exists

### Car Interaction
- Press E → searches for any node in group `"cars"` within 4 m
- On enter: player becomes invisible, camera shifts to car-follow position
- On exit: player reappears beside car (2.5 m to the side), rotation matches car

---

## Dummy (`scripts/dummy.gd`)

**Node type:** `CharacterBody3D`
**Collision:** layer 4 (Enemy), mask 1 (World only)

### Patrol AI
- Picks a random horizontal direction, walks 2.5 u/s for 2–4 seconds
- On hitting a wall (not on floor or slide collision), picks a new direction
- `_knockback` vector applied when shot or run over, decays each frame

### Taking Damage
- `take_hit(pos, dir)` — called by player raycast
  - Health -1, flash red for 0.15 s, apply knockback
  - Spawns 2–3 debris cubes at hit position
  - At 0 HP: spawns 10 debris cubes and calls `queue_free()`
- `get_run_over(speed, dir)` — called by car collision loop
  - Speed ≥ 7.0 u/s: instant kill, 10 debris cubes
  - Speed < 7.0 u/s: knockback proportional to car speed

### Debris
- Each piece is a `RigidBody3D`, `BoxMesh` 0.3×0.3×0.3, red
- `collision_layer = 0`, `collision_mask = 0` (invisible to all collision)
- 50% of pieces fly outward, 50% fall straight down
- Timer auto-deletes each piece after 4 seconds

---

## Car (`scripts/car.gd`)

**Node type:** `CharacterBody3D`
**Collision:** layer 8 (Car), mask 5 (World + Enemy)

### Driving
- W/S: accelerate/brake up to ±22 u/s (forward) or ±9.9 u/s (reverse)
- A/D: steering, only effective above 0.5 u/s
- Space: drift mode — grip drops from 0.85 → 0.05
- Velocity is lerped toward the car's facing direction each frame (grip system)
- When not occupied: car coasts to a stop

### Drift System
```
grip = DRIFT_GRIP (0.05) if Space held else NORMAL_GRIP (0.85)
velocity.x = lerp(velocity.x, target_x, grip)
velocity.z = lerp(velocity.z, target_z, grip)
```
Low grip causes velocity to lag behind facing direction — creates slide effect.

### Run-Over Detection
After `move_and_slide()`, iterates `get_slide_collision_count()` and calls `get_run_over(speed, dir)` on any collider that has that method.

### Visual Structure
Multi-mesh bloxy sports car (all BoxMesh3D):
- Orange body + cabin (cabin shifted toward rear = long hood look)
- Dark gray front/rear bumpers
- 4 black wheels (sticking out sides)
- Yellow emissive headlights (front, -Z)
- Red emissive taillights (rear, +Z)
- Blue semi-transparent windshield + rear window

**Forward direction:** Car moves along `-transform.basis.z`. All front visuals are at negative Z, rear at positive Z.

---

## Props System

All props live in `scenes/props/` as standalone `.tscn` scenes. They are all:
- `StaticBody3D` root
- `collision_layer = 1` (World)
- `collision_mask = 0` (static — nothing needs to collide with props)
- Y-offset applied so the prop sits flush on the floor when placed at Y=0

### Prop List

| Scene | Description | Approx Size (X×Y×Z) |
|---|---|---|
| `grass_tile.tscn` | Green ground tile | 8×0.1×10 |
| `sidewalk.tscn` | Light gray raised pavement | 2.5×0.2×10 |
| `road_straight.tscn` | 2-lane road with center + edge lines | 8×0.1×10 |
| `road_highway.tscn` | 4-lane highway with 5 lane lines | 14×0.1×10 |
| `road_intersection.tscn` | 4-way intersection with crosswalks | 14×0.1×14 |
| `bench.tscn` | Wood slat bench with metal legs | 2×1×0.6 |
| `tree.tscn` | Block trunk + 3 stacked leaf layers | 2.4×5×2.4 |
| `streetlight.tscn` | Pole + arm + emissive yellow bulb | 1.2×5.2×0.2 |
| `stoplight.tscn` | Pole + signal box + R/Y/G lights | 0.6×5.5×0.6 |
| `skyscraper.tscn` | Tall navy building, 18 windows, antenna | 6×21×6 |
| `skyscraper_short.tscn` | Medium dark building, 12 windows | 5×10.5×5 |
| `clothes_shop.tscn` | Pink shop, awning, "CLOTHES" sign | 7×4×6 |
| `gun_shop.tscn` | Green shop, red stripe, "GUN SHOP" sign | 6×4×5 |
| `police_station.tscn` | Navy station, R+B roof lights, "POLICE" sign | 9×6.5×8 |
| `hotel.tscn` | Tan hotel, 15 windows, canopy, "HOTEL" sign | 8×14.5×7 |

---

## Scene: main.tscn

- Floor: `StaticBody3D`, `BoxMesh` 150×1×150, gray, `collision_layer = 1`, `collision_mask = 0`
- Player spawn: (0, 1, 0)
- Dummy spawn: (0, 1, -8)
- Car spawn: (6, 0.5, -3)
- Props placed in a row at Z ≈ -30, spanning X = -58 to +70

---

## Rendering

- Sky: `ProceduralSkyMaterial` inside `Sky` inside `Environment`
- `background_mode = 2` (sky)
- `ambient_light_source = 2`, energy = 0.5 (prevents all-black scene)
- `DirectionalLight3D`: rotated 45° on X, `light_energy = 1.5`, shadows enabled
- All emissive materials (lights, windows) use `emission_enabled = true` + `emission_energy_multiplier`

---

## Known Issues / Limitations

| Issue | Notes |
|---|---|
| Road/sidewalk edge catching | Box colliders on player/car catch on prop edges. Capsule colliders are the right fix but need more testing. |
| No health bar UI | Player has infinite health currently |
| No respawn | Falling off the floor = stuck |
| No NPC spawning | Dummies are hand-placed in main.tscn |
| No wanted level | Police station is visual only |
| No audio | No sound effects or music yet |
