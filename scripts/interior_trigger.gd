extends Area3D

@export var destination: Vector3 = Vector3.ZERO
@export var portal_color: Color = Color(0.15, 1.0, 0.4, 1)

var _player: CharacterBody3D = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_spawn_portal()

func _spawn_portal() -> void:
	# Glowing outer frame
	var frame := MeshInstance3D.new()
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(2.2, 3.2, 0.1)
	frame.mesh = frame_mesh
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = portal_color
	frame_mat.emission_enabled = true
	frame_mat.emission = portal_color
	frame_mat.emission_energy_multiplier = 3.0
	frame.set_surface_override_material(0, frame_mat)
	add_child(frame)

	# Semi-transparent inner fill
	var fill := MeshInstance3D.new()
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(1.85, 2.85, 0.05)
	fill.mesh = fill_mesh
	var fill_mat := StandardMaterial3D.new()
	fill_mat.albedo_color = Color(portal_color.r, portal_color.g, portal_color.b, 0.28)
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mat.emission_enabled = true
	fill_mat.emission = portal_color
	fill_mat.emission_energy_multiplier = 1.2
	fill.set_surface_override_material(0, fill_mat)
	add_child(fill)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player = null

func _process(_delta: float) -> void:
	if _player and not _player._in_car and Input.is_action_just_pressed("interact"):
		_player.global_position = destination
		_player.velocity = Vector3.ZERO
