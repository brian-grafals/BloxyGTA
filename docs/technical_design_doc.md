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

**Node type:** `RigidBody3D` (mass 1500 kg, custom CoM at (0, −0.3, 0))
**Collision:** layer 8 (Car), mask 5 (World + Enemy)
**Physics tick:** 120 Hz

### Scene Structure

```
Car (RigidBody3D)
├── CollisionShape3D (BoxShape3D 2.0×1.0×4.2, offset 0,0.35,0)
├── WheelFL (RayCast3D)   ← suspension spring + steering ray
├── WheelFR (RayCast3D)
├── WheelRL (RayCast3D)
├── WheelRR (RayCast3D)
└── CarBody (Node3D)      ← visual container, never rotated by script
    ├── Body, Cabin, BumperFront, BumperRear
    ├── WheelMeshFL, WheelMeshFR   ← Y-rotated for steering animation
    ├── WheelMeshRL, WheelMeshRR
    ├── HeadlightL/R, TaillightL/R
    └── Windshield, RearWindow
```

Each RayCast3D fires straight down from a wheel anchor point. Contact with the ground produces a Hooke spring + damper force applied **at the contact point** — off-center forces create pitch/roll torques that tilt the body with the terrain.

The BoxShape3D (raised 0.35 m above root) handles side/wall collisions. It does not rest on the ground — the spring forces keep the body suspended.

### Parameter Reference

| Parameter | Default | Units | Controls |
|---|---|---|---|
| `engine_force` | 8000 | N | Peak drive force at rear wheels |
| `brake_force_mult` | 1.8 | × | Braking force relative to engine |
| `max_reverse_ratio` | 0.45 | fraction | Reverse speed cap |
| `rest_length` | 0.15 | m | Spring natural length |
| `resting_ratio` | 0.5 | 0–1 | Spring compressed to this fraction at rest |
| `damping_ratio` | 0.45 | 0–1 | 0 = no damping, 1 = critical damping |
| `tire_radius` | 0.3 | m | Distance from spring contact to wheel center |
| `arb_ratio` | 0.15 | fraction | Anti-roll bar as fraction of spring stiffness |
| `max_steer_angle` | 0.5 | rad (~28°) | Maximum front wheel deflection |
| `steer_rate` | 3.0 | rad/s | Input rate limit |
| `steer_speed_decay` | 0.04 | per u/s | Steer reduction per unit of speed |
| `normal_grip` | 0.85 | 0–1 | Lateral velocity correction per tick |
| `handbrake_grip` | 0.20 | 0–1 | Lateral correction during handbrake |
| `inertia_yaw_mult` | 2.5 | × | GTA heavy-rotation feel (high = sluggish yaw) |
| `inertia_pitch_mult` | 1.2 | × | Pitch inertia scale |
| `inertia_roll_mult` | 0.8 | × | Roll inertia scale |
| `drag_coeff` | 0.35 | Cd | Aerodynamic drag coefficient |
| `frontal_area` | 2.0 | m² | Frontal cross-section for drag |

### Physics Architecture

Two callbacks run each tick:

**`_physics_process(delta)` — applies forces (120 Hz)**

1. Read `_drifting` from handbrake input
2. Compute `_speed` from local-Z velocity (`-local_vel.z` = positive forward)
3. `_process_steering` — rate-limit steer angle, rotate RayCast3D nodes for steering rays
4. `_process_suspension` — spring/damper forces + anti-roll bar per axle
5. `_process_drive` — engine force at rear wheel contact points (RWD); front+rear braking
6. `_process_drag` — aerodynamic drag via `apply_central_force()`
7. Driver glue — snap player position and yaw to car

**`_integrate_forces(state: PhysicsDirectBodyState3D)` — corrects velocity after integration**

- **Inertia override (first call only):** Reads `state.inverse_inertia`, computes base inertia, scales each axis by the pitch/yaw/roll multipliers. Must be deferred — `inverse_inertia` reports zero in `_ready()`.
- **Lateral grip (every call):** Directly corrects lateral velocity in car-local space:
  ```
  local_vel.x *= (1.0 - grip)   # 0 = full correction, 1 = free slide
  ```
  Same lerp feel as CharacterBody3D but applied on a real physics body after all forces are integrated.

### Suspension Formula

```
k  = (mass × 9.8 / wheels) / (rest_length × resting_ratio)   [N/m]
c  = damping_ratio × 2 × √(k × mass_per_wheel)                [N/(m/s)]
f  = max(0, k × compression + c × compression_velocity)       [N]
```

```
Compression diagram (side view):
  anchor ─────────────────────── (RayCast3D origin)
    │  ↕ spring_len = contact_distance − tire_radius
  contact ────────────────────── (raycast hit point, on ground)
  [tire radius below = wheel center]
```

At rest: `compression = rest_length × resting_ratio = 0.075 m`. Spring force equals weight per wheel (3675 N at 1500 kg). Force is applied at the contact point, not the center of mass, so unequal compressions (ramp, cornering, braking) create real pitch/roll torques.

**Anti-roll bar (per axle):**
```
arb_force = (comp_left − comp_right) × spring_rate × arb_ratio
```
Applied as opposing vertical forces at each wheel's contact point to resist body roll.

### Visual Systems (`_process`, render rate)

**Wheel steering:** `WheelMeshFL/FR.rotation.y` lerps toward `_steer_angle` at rate 15.0/s. Cosmetic smoothing — the RayCast3D nodes are set instantly in `_physics_process` for accurate physics.

**Body roll and pitch:** Real — the RigidBody3D tilts with the terrain via spring torques. No script-driven rotation needed or applied.

### Testable Pure Functions

Three `static func` helpers callable without instancing the scene:

- `spring_rate(car_mass, wheels, length, ratio)` — N/m
- `damping_coeff(spring_k, mass_per_wheel, ratio)` — N/(m/s)
- `compute_drag(speed, air_density, area, cd)` — N

Tests live in `test/unit/test_car_physics.gd` (GdUnit4) and `test/run_tests.gd` (standalone).

**Run standalone tests headlessly:**
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . test/run_tests.tscn
```

### Tuning Guide

| Feel | `normal_grip` | `handbrake_grip` | `inertia_yaw_mult` | `damping_ratio` |
|---|---|---|---|---|
| GTA 4 heavy | 0.80 | 0.15 | 3.5 | 0.35 |
| **GTA 5 default** | **0.85** | **0.20** | **2.5** | **0.45** |
| GTA 5 snappy | 0.92 | 0.30 | 1.8 | 0.55 |

**Forward direction:** Car moves along `-transform.basis.z`. Front visuals/bumper at negative Z, rear at positive Z. Rear wheels at Z = +1.4 drive the car (RWD).

### Known Issues

| Issue | Notes |
|---|---|
| No visual suspension travel | Wheel meshes don't move up/down with compression. Upgrade path: animate wheel mesh Y position using `_compression[i]` values each frame. |
| Run-over detection removed | RigidBody3D collision iteration differs from CharacterBody3D. Dummies are not currently run over by the car. Upgrade path: connect `body_entered` signal, check velocity magnitude. |

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
