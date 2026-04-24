# GTA Driving Physics — Research Notes

Reference for reimplementing car feel in BloxyGTA. Target feel: GTA 3 / San Andreas (arcade, slidey, fun).

---

## GTA Era Comparison

| Attribute | GTA 3 / VC | GTA SA | GTA 4 | GTA 5 |
|---|---|---|---|---|
| Physics base | RenderWare custom | Custom improved | RAGE + Bullet | RAGE evolved |
| Traction model | Single multiplier | Same + traction bias | Curve max/min | Full curve + spring |
| Inertia / yaw | Very low (snappy) | Low + turnMass | High (sluggish) | Low (snappy again) |
| Suspension | Underdamped, bouncy | + high-speed damp | Soft, exaggerated roll | Stiffer, critically damped |
| Weight transfer | Minimal | Moderate | Strong + nonlinear | Present but tighter |
| Downforce | None | None | None | Yes |
| Anti-roll | Implicit | Implicit | Moderate | Strong |
| Net feel | Floaty, snappy slides | Controlled drift | Heavy, delayed, emergent | Accessible, stable |

---

## GTA 3 / Vice City / San Andreas

No published postmortems. All knowledge comes from the modding community's reverse engineering of `handling.cfg`.

### What made cars floaty and slidey

**High center of mass Z** (`CentreOfMass.z`): Set higher than realistic, making cars roll easily and flip with minimal input. GTA 3 was the worst offender — cars could flip with almost zero effort.

**Traction — three interacting values:**
- `fTractionMultiplier` — overall grip multiplier. Paradoxically high values made slides snap in/out quickly rather than being stable.
- `fTractionLoss` — grip remaining under acceleration/braking. Set 0.05–0.15 below the multiplier, causing wheelspin on acceleration and lockup on braking.
- `fTractionBias` — front/rear grip split (0 = pure RWD, 1 = pure FWD). Stock GTA cars were rear-biased, making power oversteer trivial to trigger.

**Underdamped suspension** (`fSuspensionDampingLevel`): Low damping = springs kept bouncing, producing the characteristic "boat on water" secondary motion. SA added `fSuspensionHighSpdComDamp` to stiffen at speed.

**Low `fTurnMass`** (SA only): Rotational inertia around the vertical axis. Low values let the car spin quickly — enabling snap oversteer with minimal steering input.

**High `fSteeringLock`**: Maximum wheel angle in degrees. Combined with loose traction loss = easy drift initiation.

**No downforce model**: Cars got lighter at speed, not heavier.

### San Andreas improvements

SA added `fTurnMass`, better high-speed suspension damping, and `fEngineInertia` for smoother torque. The handbrake drop + weight transfer combo worked physically, which is why SA is the best stunt driving game in the series.

---

## GTA 4 — The Simulation Swing

RAGE engine + Bullet physics. Vehicle dynamics were a custom layer on top of Bullet's rigid body solver. Key design: parameters tuned with stronger non-linear responses than the 3D era.

### Why cars felt heavy

**Nonlinear traction curve**: GTA 4 introduced separate `m_fTractionCurveMax` (peak grip) and `m_fTractionCurveMin` (grip after traction loss). Once you exceeded the peak slip angle, grip dropped sharply — snap oversteer that was hard to catch at real-time speed.

**High yaw inertia**: The car resisted changes in direction. Inputs had a delay before the car started rotating — the defining "heavy" feel of GTA 4.

**Strong weight transfer**: Pronounced nose-dive under braking reduced rear grip on RWD cars, making them tail-happy. Load shift was a direct consequence of `vecCentreOfMassOffset.z` interacting with the spring-damper system.

**Soft, underdamped suspension**: SUVs leaned visibly during cornering. Secondary bounce was prominent.

**Effective braking**: Brake force was tuned to use all available traction — dramatic nose-dive, fast stops.

**Different cars actually felt different**: RWD, FWD, AWD, weight distribution all produced distinct handling characters. This was largely absent in the 3D era.

---

## GTA 5 — Tuned Back to Arcade

Evolved RAGE engine. Config file is now `handling.meta` (XML). Modding community documentation is the best publicly available window into Rockstar's vehicle model.

### Key parameters

**`vecInertiaMultiplier` (X, Y, Z)**: The single most important arcade-vs-simulation dial. Z axis controls yaw response. Values below 2.0 create arcade-like steering. GTA 5 sports cars: ~1.0–1.5. This is the primary reason GTA 5 feels snappier than GTA 4.

**Traction curve:**
- `fTractionCurveMax` — peak grip before sliding. Higher = more grip before traction loss.
- `fTractionCurveMin` — grip while sliding. Higher relative to Max = more controlled slides rather than total loss.
- `fTractionCurveLateral` — shape of the lateral curve. Higher values = more forgiving grip loss. GTA 5 runs higher than GTA 4.
- `fTractionSpringDeltaMax` — max lateral sidewall travel. Creates a restoring spring force pulling the tire back toward straight — essentially self-centering. Higher = more stability.
- `fCamberStiffnesss` [Rockstar typo] — force pushing car toward its roll direction during cornering. 0–1 = realistic; outside that range = arcade-exaggerated.
- `fTractionBiasFront` — drivetrain split: 0.01 = pure RWD, 0.5 = AWD.
- `fLowSpeedTractionLossMult` — burnout at low speed. 1.0 default; lower = less wheelspin at launch.

**`vecCentreOfMassOffset`**: GTA 5 vehicles have lower Z offsets than GTA 4 — less body roll, more stability. COM shifted rearward = understeer tendency; forward = oversteer tendency.

**`fDownForceModifier`**: Velocity-squared downforce. Increases grip at high speed. First introduced in the series.

**`fAntiRollBarForce`**: Spring force transmitted to opposite wheel during compression. High values reduce body roll. GTA 5 runs higher than GTA 4 — flatter, more planted cornering.

**Suspension**: Higher `fSuspensionCompDamp` and `fSuspensionReboundDamp` vs GTA 4. Critically damped — no secondary bounce.

### The GTA 5 arcade recipe

- Low `vecInertiaMultiplier.z` (~1.0–1.5) → snappy yaw response
- High `fTractionCurveLateral` → forgiving grip loss
- High `fTractionCurveMin` relative to Max → controlled slides
- Low COM Z offset → minimal body roll
- High anti-roll bar force → flat cornering
- High suspension damping → no secondary bounce
- High `fTractionSpringDeltaMax` → self-correcting lateral

---

## Core Implementation Techniques

### The lateral damping trick (arcade shortcut)

The simplest path to GTA-style sliding. Instead of full slip angle math, damp the lateral velocity component each frame. This is the conceptual foundation of what the 3D era was doing:

```gdscript
# In _physics_process — applied to CharacterBody3D or RigidBody3D
var grip: float = 0.85  # tune this value:
                         # 0.6–0.75 = GTA 3 floaty
                         # 0.80–0.88 = GTA SA controlled
                         # 0.90–0.95 = GTA 5 sticky
velocity = velocity.lerp(-transform.basis.z * velocity.length(), grip)
```

For `RigidBody3D`, apply it as a force instead:

```gdscript
var lateral_dir = -transform.basis.x
var lateral_vel = linear_velocity.dot(lateral_dir)
apply_central_force(lateral_dir * -lateral_vel * grip_factor * mass)
```

Handbrake drift: temporarily drop grip to ~0.45–0.55 and allow free yaw rotation.

### Weight transfer

Load shifts between axles during acceleration/braking:

```
Wf = (c/L)*W - (h/L)*M*a   # front axle load
Wr = (b/L)*W + (h/L)*M*a   # rear axle load
```

- `c`, `b` = CG distances to rear/front axle
- `h` = CG height
- `L` = wheelbase
- `a` = longitudinal acceleration

Higher `h` amplifies transfer. Reduces grip on the unloaded axle — produces natural oversteer-under-power and understeer-under-braking.

### Friction circle

Total tire force cannot exceed: `sqrt(Fx² + Fy²) ≤ μ × Fz`

If exceeded, scale both forces proportionally down. This models the tradeoff: maximum traction while accelerating means minimum lateral grip — what makes drifting physically correct.

### Simplified Pacejka lateral curve

For more realistic grip falloff than a flat multiplier:

```
F = D × sin(C × atan(B × slip_angle))
```

- `B` (stiffness) — controls peak location
- `C` (shape) — controls curve width
- `D` (peak) — maximum force

Arcade use: skip this and use lateral damping unless you want the nonlinear falloff that defines GTA 4 feel.

### Suspension (raycast method)

Cast a ray downward from each wheel position. Measure compression vs rest length:

```
F_suspension = spring_stiffness × compression + damping_coeff × compression_rate
```

Apply force upward at each wheel position — the resulting torques produce body roll and pitch naturally.

### Ackermann steering

Inner wheel turns more sharply than outer. For arcade purposes, a simplified bicycle model (single front wheel, single rear wheel) is sufficient. Matters at low speeds to eliminate scrub; irrelevant at drift speeds.

---

## Godot 4 Implementation Options

### Node approach comparison

| Approach | Best for | Notes |
|---|---|---|
| CharacterBody3D + lateral lerp | GTA 3/SA feel, current setup | Fastest to iterate, fully manual |
| RigidBody3D + 4× RayCast3D | GTA 4/5 feel, real weight | Full force control, no physics-tick sensitivity |
| VehicleBody3D | Quick prototype only | Limited tunability, Bullet-inherited quirks |

### Physics tick

Minimum 120 Hz for any suspension-based vehicle. 240 Hz recommended for Pacejka/brush tire models. Set in Project Settings → Physics → Common → Physics Ticks Per Second.

Godot 4.4+ includes Jolt Physics (more stable rigid body simulation). VehicleBody3D works with Jolt.

### CharacterBody3D approach (GTA 3/SA target)

Stay on the current setup and add:
1. Lateral velocity lerp (grip factor) each `_physics_process`
2. Handbrake drops grip temporarily and allows free yaw
3. Visual body roll tilt on the car mesh (cosmetic only, proportional to turn input × speed)
4. Forward force curve — torque falloff at high speed via an `AnimationCurve` or a simple `max_force / (1 + velocity_ratio)` expression

### RigidBody3D approach (GTA 4/5 target)

1. Set physics tick to 120+
2. Four `RayCast3D` nodes at wheel positions, cast downward
3. Each wheel: compute suspension compression, apply spring+damping force upward via `apply_force(position, force)`
4. Drive: `apply_force(rear_axle_pos, -transform.basis.z * engine_force)`
5. Lateral grip: `apply_central_force(transform.basis.x * -lateral_vel * grip_factor * mass / delta)`
6. Tune `grip_factor` 0.3–0.5 for drifty, 0.7–0.95 for sticky
7. Override `inertia` tensor: lower Y component for snappier yaw (GTA 5 low `vecInertiaMultiplier.z` equivalent)

---

## Reference Repos

- [DAShoe1/Godot-Easy-Vehicle-Physics](https://github.com/DAShoe1/Godot-Easy-Vehicle-Physics) — RigidBody3D + RayCast3D, arcade demo, Jolt-compatible, all params in one script
- [Dechode/Godot-Simple-Vehicle](https://github.com/Dechode/Godot-Simple-Vehicle) — lighter raycast vehicle
- [Dechode/Godot-Advanced-Vehicle](https://github.com/Dechode/Godot-Advanced-Vehicle) — Pacejka + brush tire model, RWD/FWD/AWD, LSD, manual clutch (requires 240 Hz physics)
- [SergeyMakeev/ArcadeCarPhysics](https://github.com/SergeyMakeev/ArcadeCarPhysics) — Unity, but Ackermann + normalized lateral friction + stabilizer bars + speed curve
- [kidscancode sphere car](https://kidscancode.org/godot_recipes/4.x/3d/sphere_car/) — minimal RigidBody3D sphere driving example

## Reference Articles

- [Car Physics for Games — Marco Monster](https://www.asawicki.info/Mirror/Car%20Physics%20for%20Games/Car%20Physics%20for%20Games.html) — canonical simple implementation guide
- [Programming Vehicles in Games — wassimulator.com](https://wassimulator.com/blog/programming/programming_vehicles_in_games.html) — Pacejka, friction circle, torque chain
- [handling.cfg — GTAMods Wiki](https://gtamods.com/wiki/Handling.cfg)
- [handling.meta in GTA V — GTA Wiki](https://gta.fandom.com/wiki/Handling.meta_in_GTA_V)
- [handling.dat — GTAMods Wiki](https://gtamods.com/wiki/Handling.dat)
- [GTA 4 vehicle physics deep dive — Traxion](https://traxion.gg/how-grand-theft-auto-iv-broke-the-open-world-mould-for-vehicle-physics/)
- [GDC: It IS Rocket Science — Rocket League Physics](https://www.gdcvault.com/play/1024972/It-IS-Rocket-Science-The)
