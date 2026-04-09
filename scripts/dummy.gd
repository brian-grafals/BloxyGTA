extends CharacterBody3D

var health: int = 3
var _speed: float = 2.5
var _move_dir: Vector3 = Vector3.ZERO
var _dir_timer: float = 0.0
var _knockback: Vector3 = Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _mesh: MeshInstance3D = $MeshInstance3D

var _body_mat := StandardMaterial3D.new()
var _hit_mat := StandardMaterial3D.new()
var _debris_mesh := BoxMesh.new()
var _debris_mat := StandardMaterial3D.new()
var _col_shape := BoxShape3D.new()

func _ready() -> void:
	_body_mat.albedo_color = Color(0, 0, 0)
	_hit_mat.albedo_color = Color(1, 0.1, 0.1)
	_mesh.set_surface_override_material(0, _body_mat)

	_debris_mesh.size = Vector3(0.4, 0.4, 0.4)
	_debris_mat.albedo_color = Color(1, 0.1, 0.1)
	_col_shape.size = Vector3(0.4, 0.4, 0.4)

	_pick_new_direction()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	_dir_timer -= delta
	if _dir_timer <= 0.0:
		_pick_new_direction()

	_knockback = _knockback.lerp(Vector3.ZERO, 8.0 * delta)

	velocity.x = _move_dir.x * _speed + _knockback.x
	velocity.z = _move_dir.z * _speed + _knockback.z

	move_and_slide()

func _pick_new_direction() -> void:
	var angle: float = randf() * TAU
	_move_dir = Vector3(cos(angle), 0, sin(angle))
	_dir_timer = randf_range(1.5, 3.0)

func get_run_over(car_speed: float, direction: Vector3) -> void:
	if car_speed >= 7.0:
		# fast enough — instant kill, skip health
		_spawn_debris(global_position + Vector3(0, 1, 0), 10, true)
		queue_free()
	else:
		# slow bump — just get shoved
		_knockback = Vector3(direction.x, 0, direction.z).normalized() * car_speed * 3.0

func take_hit(hit_pos: Vector3, hit_dir: Vector3) -> void:
	health -= 1
	_flash_red()

	var knockback_dir := Vector3(hit_dir.x, 0.0, hit_dir.z).normalized()
	_knockback = knockback_dir * 10.0

	_spawn_debris(hit_pos, randi_range(2, 3), false)
	if health <= 0:
		_spawn_debris(global_position + Vector3(0, 1, 0), 10, true)
		queue_free()

func _flash_red() -> void:
	_mesh.set_surface_override_material(0, _hit_mat)
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(self):
		_mesh.set_surface_override_material(0, _body_mat)

func _spawn_debris(origin: Vector3, count: int, explode: bool) -> void:
	for i in count:
		var piece := RigidBody3D.new()
		piece.collision_layer = 4
		piece.collision_mask = 1

		var mesh_inst := MeshInstance3D.new()
		mesh_inst.mesh = _debris_mesh
		mesh_inst.set_surface_override_material(0, _debris_mat)
		piece.add_child(mesh_inst)

		var col := CollisionShape3D.new()
		col.shape = _col_shape
		piece.add_child(col)

		get_tree().current_scene.add_child(piece)
		piece.global_position = origin + Vector3(
			randf_range(-0.2, 0.2),
			randf_range(-0.2, 0.2),
			randf_range(-0.2, 0.2)
		)

		if explode or randf() < 0.5:
			piece.linear_velocity = Vector3(
				randf_range(-6.0, 6.0),
				randf_range(3.0, 8.0),
				randf_range(-6.0, 6.0)
			)

		var timer := Timer.new()
		timer.wait_time = 4.0
		timer.one_shot = true
		timer.timeout.connect(piece.queue_free)
		piece.add_child(timer)
		timer.start()
