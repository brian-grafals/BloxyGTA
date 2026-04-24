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

### Scene Structure

```
Car (CharacterBody3D)
├── CollisionShape3D (CapsuleShape3D, horizontal) ← untouched by body roll
└── CarBody (Node3D)                              ← rotated by script for body roll
    ├── Body, Cabin, BumperFront, BumperRear
    ├── WheelFL, WheelFR                          ← Y-rotated for steering animation
    ├── WheelRL, WheelRR
    ├── HeadlightL/R, TaillightL/R
    └── Windshield, RearWindow
```

`CarBody` exists solely to separate visual rotation from physics. `_car_body.rotation_degrees.z` produces body roll without tilting the capsule collider.

### Parameter Reference

| Parameter | Default | Controls |
|---|---|---|
| `max_speed` | 22.0 u/s | Forward speed cap |
| `reverse_speed_ratio` | 0.45 | Reverse cap = max_speed × ratio |
| `acceleration` | 14.0 u/s² | Base drive force (peak torque) |
| `engine_brake_ratio` | 0.55 | Coast decel = accel × ratio |
| `torque_falloff_start` | 0.55 | Fraction of max_speed where torque begins dropping |
| `steer_speed_low` | 2.4 rad/s | Steering rate at low speed |
| `steer_speed_high` | 0.9 rad/s | Steering rate at highway speed |
| `steer_falloff_start` | 8.0 u/s | Speed where steering reduction begins |
| `steer_falloff_end` | 20.0 u/s | Speed where steering reduction is maximum |
| `handbrake_steer_mult` | 1.6× | Steer rate boost during handbrake |
| `normal_grip` | 0.85 | Lateral damping at normal driving |
| `handbrake_grip` | 0.20 | Lateral damping during handbrake slide |
| `grip_recovery_rate` | 4.0 /s | How fast grip returns after releasing handbrake |
| `wheelspin_grip_mult` | 0.55× | Grip multiplier during launch wheelspin |
| `wheelspin_speed_threshold` | 4.0 u/s | Exit wheelspin below this speed |
| `body_roll_max_deg` | 6.0° | Peak visual body roll angle |
| `body_roll_speed` | 6.0 | Body roll lerp rate |
| `wheel_steer_max_deg` | 25.0° | Max front wheel visual turn angle |

### Physics Loop (60 Hz)

**A — Gravity:** `velocity.y -= gravity * delta` when airborne.

**B — Unoccupied coast:** Speed and velocity lerp toward 0.

**C — Throttle / torque curve:** `torque_at_speed()` returns full acceleration up to `torque_falloff_start × max_speed`, then linearly decays to 0 at `max_speed`.

```
Torque
 14 |████████████\
    |             \
  0 |______________\___
    0            12.1  22.0   speed (u/s)
    (falloff_start=0.55 × 22 = 12.1)
```

**D — Wheelspin:** When throttle held at `abs(speed) < 4.0 u/s`, grip drops to `wheelspin_grip_mult × normal_grip` — rear breaks loose at standing launch.

**E — Handbrake grip state machine:** `_drift_grip_t` (0→1) blends between `handbrake_grip` and `normal_grip`. Drops 3× faster on press than recovery on release — instant slide entry, gradual catch.

```
_drift_grip_t: 1.0 ──── (handbrake press) ──▶ 0.0   (rate × 3)
               0.0 ──── (handbrake release) ─▶ 1.0   (rate × 1)
effective grip = lerp(handbrake_grip=0.20, normal_grip=0.85, _drift_grip_t)
```

**F — Speed-sensitive steering:**

| Speed | Steer rate |
|---|---|
| 0–8 u/s | 2.4 rad/s |
| 14 u/s | 1.65 rad/s |
| 20 u/s | 0.9 rad/s |

**G — Lateral grip:** `velocity.xz` lerped toward car-forward direction at rate `compute_grip()`.

**H — `move_and_slide()` and run-over detection:** After slide, iterates collisions and calls `get_run_over(speed, dir)` on valid colliders.

**I — Driver glue:** Player position/rotation snapped to car each frame.

### Visual Systems (`_process`, render rate)

**Body roll:** `_car_body.rotation_degrees.z` lerps toward `steer_input × speed_fraction × body_roll_max_deg`. Cosmetic only — collision capsule does not tilt.

**Wheel steering:** `WheelFL` and `WheelFR` `rotation_degrees.y` lerps toward `−steer_input × wheel_steer_max_deg` at rate 12.0/s.

### Testable Pure Functions

Three `static func` helpers can be called without instantiating the scene:

- `torque_at_speed(spd, max_spd, accel, falloff_start)` — torque curve
- `effective_steer_speed(spd, low, high, start, end_spd)` — steering rate
- `compute_grip(drift_grip_t, normal_grip, handbrake_grip)` — effective grip

Tests live in `test/unit/test_car_physics.gd` (GdUnit4) and `test/run_tests.gd` (standalone).

**Run standalone tests headlessly:**
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . test/run_tests.tscn
```

### Tuning Presets

| Feel | `normal_grip` | `handbrake_grip` | `steer_speed_low` | `torque_falloff_start` |
|---|---|---|---|---|
| GTA 3 floaty | 0.70 | 0.05 | 2.8 | 0.35 |
| **GTA SA (default)** | **0.85** | **0.20** | **2.4** | **0.55** |
| GTA 5 sticky | 0.93 | 0.35 | 2.0 | 0.70 |

**Forward direction:** Car moves along `-transform.basis.z`. Front visuals are at negative Z, rear at positive Z.

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
| No suspension simulation | Body roll is cosmetic only. Upgrade path: RigidBody3D + RayCast3D at 120 Hz physics tick |
