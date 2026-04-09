extends CharacterBody3D

const WALK_SPEED: float = 6.0
const SPRINT_SPEED: float = 12.0
const JUMP_VELOCITY: float = 7.0
const MOUSE_SENSITIVITY: float = 0.003
const DEFAULT_FOV: float = 75.0
const AIM_FOV: float = 50.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _pitch: float = -0.2
var _in_car: bool = false
var _current_car = null

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var crosshair: Label = $CanvasLayer/Control/Crosshair

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera_pivot.rotation.x = _pitch

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _in_car:
			camera_pivot.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		else:
			rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_pitch = clamp(_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.2, 0.4)
		camera_pivot.rotation.x = _pitch

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _in_car:
			_shoot()

	if event.is_action_pressed("interact"):
		if _in_car:
			_exit_car()
		else:
			var car = _find_nearby_car()
			if car:
				_enter_car(car)

func _physics_process(delta: float) -> void:
	if _in_car:
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var speed: float = SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()

func _process(_delta: float) -> void:
	if camera.global_position.distance_squared_to(camera_pivot.global_position) > 0.0001:
		camera.look_at(camera_pivot.global_position, Vector3.UP)

	var aiming: bool = Input.is_action_pressed("aim") and not _in_car
	camera.fov = lerp(camera.fov, AIM_FOV if aiming else DEFAULT_FOV, 0.15)
	crosshair.modulate = Color(1, 0.2, 0.2) if aiming else Color(1, 1, 1)
	crosshair.visible = not _in_car

func _find_nearby_car() -> Node3D:
	for car in get_tree().get_nodes_in_group("cars"):
		if global_position.distance_to(car.global_position) < 4.0:
			return car
	return null

func _enter_car(car: Node3D) -> void:
	_in_car = true
	_current_car = car
	visible = false
	velocity = Vector3.ZERO
	car.enter(self)

func _exit_car() -> void:
	_in_car = false
	visible = true
	velocity = Vector3.ZERO
	camera_pivot.rotation.y = 0.0
	# step out to the side of the car
	global_position = _current_car.global_position + _current_car.transform.basis.x * 2.5
	global_position.y = _current_car.global_position.y + 1.0
	global_rotation.y = _current_car.global_rotation.y
	_current_car.exit()
	_current_car = null

func _shoot() -> void:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var screen_center: Vector2 = get_viewport().get_visible_rect().size / 2.0
	var ray_origin: Vector3 = camera.project_ray_origin(screen_center)
	var ray_end: Vector3 = ray_origin + camera.project_ray_normal(screen_center) * 100.0

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [get_rid()]
	var result: Dictionary = space_state.intersect_ray(query)

	if result and result.collider.has_method("take_hit"):
		var ray_dir: Vector3 = camera.project_ray_normal(screen_center)
		result.collider.take_hit(result.position, ray_dir)
