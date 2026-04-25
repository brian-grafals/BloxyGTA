extends RigidBody3D

# ── Engine ───────────────────────────────────────────────────────────────────
@export var engine_force: float = 8000.0      # N — peak drive force
@export var brake_force_mult: float = 1.8     # braking force relative to engine
@export var max_reverse_ratio: float = 0.45   # reverse cap as fraction of max speed

# ── Suspension ───────────────────────────────────────────────────────────────
@export var rest_length: float = 0.15         # m — spring natural length
@export var resting_ratio: float = 0.5        # spring compressed to this fraction at rest
@export var damping_ratio: float = 0.45       # 0 = no damping, 1 = critical
@export var tire_radius: float = 0.3          # m

# ── Anti-Roll Bar ────────────────────────────────────────────────────────────
@export var arb_ratio: float = 0.15           # fraction of spring stiffness for ARB

# ── Steering ─────────────────────────────────────────────────────────────────
@export var max_steer_angle: float = 0.5      # rad (~28°)
@export var steer_rate: float = 3.0           # rad/s input rate
@export var steer_speed_decay: float = 0.04   # steer reduction per u/s
@export var steering_stiffness: float = 800.0 # N per (rad·m/s) — cornering force at front axle

# ── Grip (same 0–1 range as before) ──────────────────────────────────────────
@export var normal_grip: float = 0.85
@export var handbrake_grip: float = 0.20

# ── Inertia Override ──────────────────────────────────────────────────────────
@export var inertia_yaw_mult: float = 2.5     # GTA feel — higher = heavier rotation
@export var inertia_pitch_mult: float = 1.2
@export var inertia_roll_mult: float = 0.8

# ── Aerodynamics ─────────────────────────────────────────────────────────────
@export var drag_coeff: float = 0.35
@export var frontal_area: float = 2.0

# ── State ─────────────────────────────────────────────────────────────────────
var _speed: float = 0.0
var _steer_angle: float = 0.0
var _compression: Array[float] = [0.0, 0.0, 0.0, 0.0]  # FL FR RL RR
var _inertia_set: bool = false
var _drifting: bool = false
var _driver = null
var is_occupied: bool = false

const _FL := 0
const _FR := 1
const _RL := 2
const _RR := 3
const _AIR_DENSITY := 1.225

@onready var _wheels: Array = [$WheelFL, $WheelFR, $WheelRL, $WheelRR]
@onready var _mesh_fl: MeshInstance3D = $CarBody/WheelMeshFL
@onready var _mesh_fr: MeshInstance3D = $CarBody/WheelMeshFR

func _ready() -> void:
	add_to_group("cars")

# ── Static helpers (testable without instancing) ──────────────────────────────

static func spring_rate(car_mass: float, wheels: int, length: float, ratio: float) -> float:
	var weight_per_wheel := car_mass * 9.8 / wheels
	var target_comp := length * ratio
	return weight_per_wheel / target_comp  # N/m

static func damping_coeff(spring_k: float, mass_per_wheel: float, ratio: float) -> float:
	return ratio * 2.0 * sqrt(spring_k * mass_per_wheel)  # N/(m/s)

static func compute_drag(speed: float, air_density: float, area: float, cd: float) -> float:
	return 0.5 * air_density * speed * speed * area * cd  # N

# ── Physics (120 Hz) ──────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	_drifting = is_occupied and Input.is_action_pressed("jump")

	var local_vel: Vector3 = global_transform.basis.inverse() * linear_velocity
	_speed = -local_vel.z  # positive when moving forward

	_process_steering(delta)
	_process_suspension(delta)
	if is_occupied:
		_process_drive()
		_process_steering_force()
	_process_drag()

	if _driver:
		_driver.global_position = global_position
		_driver.rotation.y = rotation.y

# _integrate_forces runs after forces are integrated each tick.
# Used for the inertia override (first call) and lateral grip correction (every call).
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not _inertia_set:
		var inv := state.inverse_inertia
		if inv.is_finite() and inv != Vector3.ZERO:
			var base := Vector3(1.0 / inv.x, 1.0 / inv.y, 1.0 / inv.z)
			inertia = Vector3(
				base.x * inertia_pitch_mult,
				base.y * inertia_yaw_mult,
				base.z * inertia_roll_mult
			)
			_inertia_set = true

	# GTA-style lateral grip: correct lateral velocity directly after integration.
	# Same lerp feel as CharacterBody3D but on a real physics body.
	var local_vel := state.transform.basis.inverse() * state.linear_velocity
	var grip := handbrake_grip if _drifting else normal_grip
	local_vel.x *= (1.0 - grip)
	state.linear_velocity = state.transform.basis * local_vel

func _process_steering(delta: float) -> void:
	var input := Input.get_axis("move_left", "move_right") if is_occupied else 0.0
	var speed_factor: float = 1.0 / (1.0 + abs(_speed) * steer_speed_decay)
	var target: float = input * max_steer_angle * speed_factor
	_steer_angle = move_toward(_steer_angle, target, steer_rate * delta)
	$WheelFL.rotation.y = _steer_angle
	$WheelFR.rotation.y = _steer_angle

func _process_suspension(delta: float) -> void:
	var k := spring_rate(mass, 4, rest_length, resting_ratio)
	var c := damping_coeff(k, mass / 4.0, damping_ratio)
	var arb_k := k * arb_ratio
	var compressions: Array[float] = [0.0, 0.0, 0.0, 0.0]

	for i in 4:
		var w: RayCast3D = _wheels[i]
		w.force_raycast_update()
		if not w.is_colliding():
			_compression[i] = 0.0
			continue

		var contact := w.get_collision_point()
		var normal := w.get_collision_normal()
		var spring_len := contact.distance_to(w.global_position) - tire_radius
		var comp := maxf(0.0, rest_length - spring_len)
		compressions[i] = comp

		var comp_vel: float = (comp - _compression[i]) / delta
		_compression[i] = comp

		# Spring force (Hooke) + damping. Applied at the contact point so the
		# resulting torque naturally pitches and rolls the body on terrain.
		var f := maxf(0.0, k * comp + c * comp_vel)
		apply_force(normal * f, contact - global_position)

	_apply_arb(_FL, _FR, compressions, arb_k)
	_apply_arb(_RL, _RR, compressions, arb_k)

func _apply_arb(left: int, right: int, compressions: Array[float], arb_k: float) -> void:
	var wl: RayCast3D = _wheels[left]
	var wr: RayCast3D = _wheels[right]
	if not wl.is_colliding() or not wr.is_colliding():
		return
	var diff: float = compressions[left] - compressions[right]
	var f: float = diff * arb_k
	apply_force(-global_transform.basis.y * f, wl.get_collision_point() - global_position)
	apply_force(global_transform.basis.y * f, wr.get_collision_point() - global_position)

func _process_drive() -> void:
	var throttle := Input.get_action_strength("move_forward")
	var reverse := Input.get_action_strength("move_backward")
	var fwd := -global_transform.basis.z

	# RWD: engine force at rear wheel contact points
	for i in [_RL, _RR]:
		var w: RayCast3D = _wheels[i]
		if not w.is_colliding():
			continue
		var offset := w.get_collision_point() - global_position
		if throttle > 0.0:
			apply_force(fwd * (engine_force * throttle * 0.5), offset)
		elif reverse > 0.0:
			if _speed > 0.5:  # braking while moving forward
				apply_force(-linear_velocity.normalized() * (engine_force * brake_force_mult * reverse * 0.5), offset)
			else:             # reversing
				apply_force(-fwd * (engine_force * max_reverse_ratio * reverse * 0.5), offset)

	# Front braking
	if reverse > 0.0 and _speed > 0.5:
		for i in [_FL, _FR]:
			var w: RayCast3D = _wheels[i]
			if not w.is_colliding():
				continue
			apply_force(
				-linear_velocity.normalized() * (engine_force * brake_force_mult * reverse * 0.5),
				w.get_collision_point() - global_position
			)

func _process_steering_force() -> void:
	if abs(_steer_angle) < 0.001:
		return
	var lat := global_transform.basis.x
	var front_offset := -global_transform.basis.z * 1.4  # front axle centre
	apply_force(lat * (_steer_angle * abs(_speed) * steering_stiffness), front_offset)

func _process_drag() -> void:
	if linear_velocity.is_zero_approx():
		return
	var f := compute_drag(linear_velocity.length(), _AIR_DENSITY, frontal_area, drag_coeff)
	apply_central_force(-linear_velocity.normalized() * f)

# ── Visuals (render rate) ─────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Smooth visual wheel steering at render rate
	_mesh_fl.rotation.y = lerp(_mesh_fl.rotation.y, _steer_angle, 15.0 * delta)
	_mesh_fr.rotation.y = lerp(_mesh_fr.rotation.y, _steer_angle, 15.0 * delta)

# ── Public API (called by player.gd) ─────────────────────────────────────────

func enter(player: Node3D) -> void:
	is_occupied = true
	_driver = player

func exit() -> void:
	is_occupied = false
	_driver = null
