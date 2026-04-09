extends CharacterBody3D

const MAX_SPEED: float = 22.0
const ACCELERATION: float = 14.0
const STEER_SPEED: float = 2.4
const NORMAL_GRIP: float = 0.85
const DRIFT_GRIP: float = 0.05

var speed: float = 0.0
var _driver = null
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var is_occupied: bool = false

func _ready() -> void:
	add_to_group("cars")

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if not is_occupied:
		speed = move_toward(speed, 0, ACCELERATION * delta)
		velocity.x = move_toward(velocity.x, 0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 10.0 * delta)
		move_and_slide()
		return

	# Accelerate / brake
	if Input.is_action_pressed("move_forward"):
		speed = move_toward(speed, MAX_SPEED, ACCELERATION * delta)
	elif Input.is_action_pressed("move_backward"):
		speed = move_toward(speed, -MAX_SPEED * 0.45, ACCELERATION * delta)
	else:
		speed = move_toward(speed, 0, ACCELERATION * 0.55 * delta)

	# Steering — only effective when moving
	var steer: float = Input.get_axis("move_left", "move_right")
	var drifting: bool = Input.is_action_pressed("jump")

	if abs(speed) > 0.5:
		var steer_mult: float = 1.6 if drifting else 1.0
		rotate_y(-steer * STEER_SPEED * steer_mult * delta * sign(speed))

	# Grip — drift = velocity lags behind car facing (sliding)
	var grip: float = DRIFT_GRIP if drifting else NORMAL_GRIP
	var target_x: float = -transform.basis.z.x * speed
	var target_z: float = -transform.basis.z.z * speed
	velocity.x = lerp(velocity.x, target_x, grip)
	velocity.z = lerp(velocity.z, target_z, grip)

	move_and_slide()

	# Check for things we ran into
	for i in get_slide_collision_count():
		var col = get_slide_collision(i)
		var collider = col.get_collider()
		if is_instance_valid(collider) and collider.has_method("get_run_over"):
			collider.get_run_over(abs(speed), velocity.normalized())

	# Keep driver glued to car
	if _driver:
		_driver.global_position = global_position
		_driver.global_rotation = global_rotation

func enter(player: Node3D) -> void:
	is_occupied = true
	_driver = player

func exit() -> void:
	is_occupied = false
	_driver = null
