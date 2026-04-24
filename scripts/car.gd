extends CharacterBody3D

# ── Engine ──────────────────────────────────────────────────────────────────
@export var max_speed: float = 22.0
@export var reverse_speed_ratio: float = 0.45
@export var acceleration: float = 14.0
@export var engine_brake_ratio: float = 0.55
@export var torque_falloff_start: float = 0.55  # fraction of max_speed where torque begins dropping

# ── Steering ─────────────────────────────────────────────────────────────────
@export var steer_speed_low: float = 2.4         # max steer rate at low speed
@export var steer_speed_high: float = 0.9        # min steer rate at highway speed
@export var steer_falloff_start: float = 8.0     # speed (u/s) where reduction begins
@export var steer_falloff_end: float = 20.0      # speed (u/s) where reduction is maximum
@export var handbrake_steer_mult: float = 1.6    # steer boost during handbrake

# ── Grip ──────────────────────────────────────────────────────────────────────
@export var normal_grip: float = 0.85
@export var handbrake_grip: float = 0.20         # 0.20 = SA controllable slide
@export var grip_recovery_rate: float = 4.0      # grip units/s when releasing handbrake
@export var wheelspin_grip_mult: float = 0.55    # grip multiplier during launch wheelspin
@export var wheelspin_speed_threshold: float = 4.0

# ── Visuals ───────────────────────────────────────────────────────────────────
@export var body_roll_max_deg: float = 6.0
@export var body_roll_speed: float = 6.0
@export var wheel_steer_max_deg: float = 25.0

var speed: float = 0.0
var _driver = null
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_occupied: bool = false

var _drift_grip_t: float = 1.0      # 1.0 = normal grip, 0.0 = handbrake grip
var _wheelspin_active: bool = false
var _steer_input: float = 0.0       # written in _physics_process, read in _process
var _body_roll_current: float = 0.0

@onready var _car_body: Node3D = $CarBody
@onready var _wheel_fl: MeshInstance3D = $CarBody/WheelFL
@onready var _wheel_fr: MeshInstance3D = $CarBody/WheelFR

func _ready() -> void:
	add_to_group("cars")

# ── Pure helper functions (static = callable without instancing the scene) ────

static func torque_at_speed(spd: float, max_spd: float, accel: float, falloff_start: float) -> float:
	var abs_spd: float = abs(spd)
	var falloff_spd: float = falloff_start * max_spd
	if abs_spd <= falloff_spd:
		return accel
	var ratio: float = (abs_spd - falloff_spd) / (max_spd - falloff_spd)
	return accel * (1.0 - clamp(ratio, 0.0, 1.0))

static func effective_steer_speed(spd: float, low: float, high: float, start: float, end_spd: float) -> float:
	var t: float = clamp((abs(spd) - start) / (end_spd - start), 0.0, 1.0)
	return lerp(low, high, t)

static func compute_grip(drift_grip_t: float, norm_grip: float, drift_grip: float) -> float:
	return lerp(drift_grip, norm_grip, drift_grip_t)

# ── Physics (60 Hz) ───────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	# A — Gravity
	if not is_on_floor():
		velocity.y -= _gravity * delta

	# B — Unoccupied coast
	if not is_occupied:
		speed = move_toward(speed, 0.0, acceleration * delta)
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		move_and_slide()
		return

	# C — Throttle / torque curve (power tapers off near max_speed)
	var torque: float = torque_at_speed(speed, max_speed, acceleration, torque_falloff_start)
	if Input.is_action_pressed("move_forward"):
		speed = move_toward(speed, max_speed, torque * delta)
	elif Input.is_action_pressed("move_backward"):
		speed = move_toward(speed, -max_speed * reverse_speed_ratio, torque * delta)
	else:
		speed = move_toward(speed, 0.0, acceleration * engine_brake_ratio * delta)

	# D — Wheelspin: low-speed launch with throttle breaks traction
	var throttle_held: bool = Input.is_action_pressed("move_forward")
	var handbrake: bool = Input.is_action_pressed("jump")
	_wheelspin_active = throttle_held and abs(speed) < wheelspin_speed_threshold and not handbrake

	# E — Handbrake grip state machine: instant slide entry, gradual recovery
	if handbrake:
		_drift_grip_t = move_toward(_drift_grip_t, 0.0, grip_recovery_rate * 3.0 * delta)
	else:
		_drift_grip_t = move_toward(_drift_grip_t, 1.0, grip_recovery_rate * delta)

	# F — Speed-sensitive steering
	_steer_input = Input.get_axis("move_left", "move_right")
	var steer_mult: float = handbrake_steer_mult if handbrake else 1.0
	var eff_steer: float = effective_steer_speed(speed, steer_speed_low, steer_speed_high,
												  steer_falloff_start, steer_falloff_end)
	if abs(speed) > 0.5:
		rotate_y(-_steer_input * eff_steer * steer_mult * delta * sign(speed))

	# G — Lateral grip application
	var grip: float = compute_grip(_drift_grip_t, normal_grip, handbrake_grip)
	if _wheelspin_active:
		grip *= wheelspin_grip_mult
	var target_vel: Vector3 = -transform.basis.z * speed
	velocity.x = lerp(velocity.x, target_vel.x, grip)
	velocity.z = lerp(velocity.z, target_vel.z, grip)

	# H — Move and run-over detection
	move_and_slide()
	for i in get_slide_collision_count():
		var col = get_slide_collision(i)
		var collider = col.get_collider()
		if is_instance_valid(collider) and collider.has_method("get_run_over"):
			collider.get_run_over(abs(speed), velocity.normalized())

	# I — Keep driver glued to car
	if _driver:
		_driver.global_position = global_position
		_driver.global_rotation = global_rotation

# ── Visuals (render rate) ─────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Body roll — cosmetic tilt of CarBody only; collision capsule is unaffected
	var lateral_g: float = _steer_input * clamp(abs(speed) / max_speed, 0.0, 1.0)
	_body_roll_current = lerp(_body_roll_current, lateral_g * body_roll_max_deg, body_roll_speed * delta)
	_car_body.rotation_degrees.z = _body_roll_current

	# Front wheel steering animation
	var target_deg: float = -_steer_input * wheel_steer_max_deg
	_wheel_fl.rotation_degrees.y = lerp(_wheel_fl.rotation_degrees.y, target_deg, 12.0 * delta)
	_wheel_fr.rotation_degrees.y = lerp(_wheel_fr.rotation_degrees.y, target_deg, 12.0 * delta)

# ── Car entry / exit API (called by player.gd) ────────────────────────────────

func enter(player: Node3D) -> void:
	is_occupied = true
	_driver = player

func exit() -> void:
	is_occupied = false
	_driver = null
