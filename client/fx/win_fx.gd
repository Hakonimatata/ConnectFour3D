class_name WinFx
extends RefCounted
## «Heftig» effekt ved fire på rad: gnistregn langs linjen, et smell i midten,
## kamerarist, sakte film og vibrasjon. Kalles fra spillskjermen.


static func play(board: BoardView, camera: CameraRig, line: Array, color: Color) -> void:
	for p in line:
		_burst(board, board.grid_to_world(p) + Vector3(0, BoardView.LAYER * 0.5, 0), color, 60, 4.5)
	_burst(board, board.center_of(line), Color(color.lerp(Color.WHITE, 0.5), 1.0), 160, 8.0)
	camera.add_trauma(0.95)
	Settings.vibrate(250)
	Sfx.play("boom")

	# Kort sakte film, så tilbake til normal fart.
	Engine.time_scale = 0.25
	var t := board.get_tree().create_tween().set_ignore_time_scale(true)
	t.tween_interval(0.12)
	t.tween_property(Engine, "time_scale", 1.0, 0.7).set_trans(Tween.TRANS_SINE)


static func _burst(parent: Node3D, at: Vector3, color: Color, amount: int, speed: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = 1.8
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -7.0, 0)
	p.damping_min = 1.0
	p.damping_max = 2.5
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve

	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r * 2.2, color.g * 2.2, color.b * 2.2)   # > 1 gir bloom
	mesh.material = mat
	p.mesh = mesh

	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
