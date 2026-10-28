class_name WinFx
extends RefCounted
## Seiersanimasjoner ved fire på rad. Vinneren velger selv (Innstillinger → Seiersanimasjon):
##   classic    gnistregn langs linjen og et smell i midten
##   fireworks  raketter skytes opp fra brikkene og eksploderer
##   confetti   konfetti regner over brettet
##   shockwave  sjokkbølge over brettet, og de andre brikkene hopper
##   lightning  lyn slår ned i de fire brikkene
##   supernova  linjen trekkes sammen, så et blendende lysglimt og en kraftig utblåsning
##   glitter    gull- og sølvdryss som daler stille over brettet
##   chaos      en kjempebrikke faller ned og spretter, alle brikkene kastes opp, det regner
##              brikker i alle farger, og kameraet rister som aldri før
## Alle har kamerarist, kort sakte film og vibrasjon.
##
## Ytelse (det hakket på telefon når partiet var slutt): shaderne kompileres første gang noe tegnes,
## så prewarm() tegner de samme materialene usynlig når partiet starter. Gnistnettene gjenbrukes,
## og på telefon brukes halvparten så mange partikler.

static var _spark_cache := {}   ## "farge:radius" -> SphereMesh


static func play(board: BoardView, camera: CameraRig, line: Array, color: Color, style := "classic") -> void:
	match style:
		"fireworks": _fireworks(board, camera, line, color)
		"confetti": _confetti(board, camera, line, color)
		"shockwave": _shockwave(board, camera, line, color)
		"lightning": _lightning(board, camera, line, color)
		"supernova": _supernova(board, camera, line, color)
		"glitter": _glitter(board, camera, line, color)
		"chaos": _chaos(board, camera, line, color)
		_: _classic(board, camera, line, color)
	Settings.vibrate(250)
	_slow_motion(board)


static func _slow_motion(board: Node) -> void:
	Engine.time_scale = 0.4
	var t := board.get_tree().create_tween().set_ignore_time_scale(true)
	t.tween_interval(0.12)
	t.tween_property(Engine, "time_scale", 1.0, 0.7).set_trans(Tween.TRANS_SINE)


static func _top_of(board: BoardView, p: Vector3i) -> Vector3:
	return board.grid_to_world(p) + Vector3(0, BoardView.LAYER * 0.5, 0)


# ---------------------------------------------------------------- Klassisk

static func _classic(board: BoardView, camera: CameraRig, line: Array, color: Color) -> void:
	for p in line:
		burst(board, _top_of(board, p), color, 60, 4.5)
	burst(board, board.center_of(line), Color(color.lerp(Color.WHITE, 0.5), 1.0), 160, 8.0)
	camera.add_trauma(0.95)
	Sfx.play("boom")


# ---------------------------------------------------------------- Fyrverkeri

static func _fireworks(board: BoardView, camera: CameraRig, line: Array, color: Color) -> void:
	camera.add_trauma(0.35)
	var top_y := board.size * BoardView.LAYER + 1.8
	for i in line.size():
		var start := _top_of(board, line[i])
		var rocket := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.07
		sphere.height = 0.14
		rocket.mesh = sphere
		rocket.material_override = _glow_material(color.lerp(Color.WHITE, 0.4), 2.5)
		board.add_child(rocket)
		rocket.global_position = start
		var trail := _trail(color)
		rocket.add_child(trail)
		var apex := start + Vector3(randf_range(-0.6, 0.6), top_y - start.y + randf_range(0.0, 0.8), randf_range(-0.6, 0.6))
		var hue_shift := Color.from_hsv(fposmod(color.h + 0.08 * i, 1.0), clampf(color.s, 0.5, 1.0), 1.0)
		var t := rocket.create_tween()
		t.tween_interval(0.12 * i)
		t.tween_property(rocket, "global_position", apex, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_callback(func() -> void:
			burst(board, rocket.global_position, hue_shift, 90, 5.5, 2.2)
			burst(board, rocket.global_position, Color.WHITE, 30, 3.0, 1.2)
			camera.add_trauma(0.3)
			Sfx.play("boom", randf_range(1.1, 1.5))
			rocket.queue_free()
		)


static func _trail(color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.45
	p.local_coords = false
	p.direction = Vector3.DOWN
	p.spread = 15.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0, -2.0, 0)
	p.scale_amount_curve = _fade_curve()
	p.mesh = _spark_mesh(color, 0.035)
	return p


# ---------------------------------------------------------------- Konfetti

static func _confetti(board: BoardView, camera: CameraRig, line: Array, color: Color) -> void:
	var width := board.size * BoardView.SPACING
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.75
	p.amount = particles(260)
	p.lifetime = 3.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(width * 0.6, 0.2, width * 0.6)
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -2.2, 0)
	p.damping_min = 0.8
	p.damping_max = 1.6
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	var colors := Gradient.new()
	colors.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	colors.colors = PackedColorArray([color, Color("ffd23a"), Color("ff4f9a"), Color("4fd1ff"), Color("8bd92a"), color.lerp(Color.WHITE, 0.5)])
	p.color_initial_ramp = colors
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.05)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	p.mesh = quad
	board.add_child(p)
	p.global_position = Vector3(0, board.size * BoardView.LAYER + 0.4, 0)
	p.emitting = true
	p.finished.connect(p.queue_free)
	for pos in line:
		burst(board, _top_of(board, pos), color, 30, 3.5)
	camera.add_trauma(0.6)
	Sfx.play("win", 1.2)


# ---------------------------------------------------------------- Sjokkbølge

static func _shockwave(board: BoardView, camera: CameraRig, line: Array, color: Color) -> void:
	var center := board.center_of(line)
	var floor_center := Vector3(center.x, 0.03, center.z)
	for i in 2:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.9
		torus.outer_radius = 1.0
		torus.rings = 64
		ring.mesh = torus
		var mat := _glow_material(color.lerp(Color.WHITE, 0.3), 2.0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.material_override = mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		board.add_child(ring)
		ring.global_position = floor_center + Vector3(0, i * 0.02, 0)
		ring.scale = Vector3(0.1, 0.05, 0.1)
		var reach := board.size * BoardView.SPACING * 1.1
		var t := ring.create_tween().set_parallel()
		t.tween_property(ring, "scale", Vector3(reach, 0.05, reach), 0.9).set_delay(0.15 * i) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(mat, "albedo_color:a", 0.0, 0.9).set_delay(0.15 * i)
		t.chain().tween_callback(ring.queue_free)
	board.hop_pieces(floor_center, line)
	burst(board, center, color, 120, 6.0)
	camera.add_trauma(1.0)
	Sfx.play("boom", 0.7)


# ---------------------------------------------------------------- Lyn

static func _lightning(board: BoardView, camera: CameraRig, line: Array, color: Color) -> void:
	var sky_y := board.size * BoardView.LAYER + 4.0
	for i in line.size():
		var target := _top_of(board, line[i]) + Vector3(0, BoardView.LAYER * 0.4, 0)
		var timer := board.get_tree().create_timer(0.09 * i, true, false, true)
		timer.timeout.connect(func() -> void:
			if not is_instance_valid(board):
				return
			var bolt := _bolt(Vector3(target.x + randf_range(-0.8, 0.8), sky_y, target.z + randf_range(-0.8, 0.8)), target)
			board.add_child(bolt)
			var t := bolt.create_tween()
			for k in 3:
				t.tween_property(bolt, "visible", false, 0.04)
				t.tween_property(bolt, "visible", true, 0.04)
			t.tween_interval(0.08)
			t.tween_callback(bolt.queue_free)
			burst(board, target, Color(0.8, 0.9, 1.0), 40, 4.0, 1.0)
			burst(board, target, color, 25, 2.5, 1.2)
			camera.add_trauma(0.35)
			Sfx.play("zap", randf_range(0.9, 1.2))
		)


## Et takkete lyn fra a til b, bygget av tynne bokser.
static func _bolt(from: Vector3, to: Vector3) -> Node3D:
	var root := Node3D.new()
	var mat := _glow_material(Color(0.75, 0.88, 1.0), 3.0)
	var points: Array[Vector3] = [from]
	var segments := 9
	for s in range(1, segments):
		var p := from.lerp(to, float(s) / segments)
		p += Vector3(randf_range(-0.22, 0.22), 0, randf_range(-0.22, 0.22))
		points.append(p)
	points.append(to)
	for s in segments:
		var a := points[s]
		var b := points[s + 1]
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.035, 0.035, a.distance_to(b))
		seg.mesh = box
		seg.material_override = mat
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var dir := (b - a).normalized()
		var up := Vector3.RIGHT if absf(dir.y) > 0.9 else Vector3.UP
		seg.transform = Transform3D(Basis.looking_at(dir, up), (a + b) / 2.0)
		root.add_child(seg)
	return root


# ---------------------------------------------------------------- Supernova

static func _supernova(board: BoardView, camera: CameraRig, line: Array, color: Color) -> void:
	var center := board.center_of(line)
	# 1) Lyskule som vokser i midten
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	core.mesh = sphere
	var mat := _glow_material(color.lerp(Color.WHITE, 0.6), 3.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core.material_override = mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board.add_child(core)
	core.global_position = center
	core.scale = Vector3.ONE * 0.05
	var t := core.create_tween()
	t.tween_property(core, "scale", Vector3.ONE * 0.35, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		# 2) Smell: kula blåser ut, gnister i alle retninger og en ring langs bakken
		burst(board, center, Color.WHITE, 120, 9.0, 1.4)
		burst(board, center, color, 160, 6.0, 2.0)
		camera.add_trauma(1.0)
		Sfx.play("boom", 0.6)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.92
		torus.outer_radius = 1.0
		torus.rings = 64
		ring.mesh = torus
		var ring_mat := _glow_material(color.lerp(Color.WHITE, 0.4), 2.2)
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.material_override = ring_mat
		board.add_child(ring)
		ring.global_position = Vector3(center.x, center.y, center.z)
		ring.scale = Vector3(0.2, 0.04, 0.2)
		var reach := board.size * BoardView.SPACING * 1.6
		var rt := ring.create_tween().set_parallel()
		rt.tween_property(ring, "scale", Vector3(reach, 0.04, reach), 0.7).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		rt.tween_property(ring_mat, "albedo_color:a", 0.0, 0.7)
		rt.chain().tween_callback(ring.queue_free)
	)
	t.tween_property(core, "scale", Vector3.ONE * 2.6, 0.18).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.35)
	t.tween_callback(core.queue_free)
	camera.add_trauma(0.25)


# ---------------------------------------------------------------- Glitter

static func _glitter(board: BoardView, camera: CameraRig, line: Array, color: Color) -> void:
	var width := board.size * BoardView.SPACING
	for i in 2:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.explosiveness = 0.35
		p.amount = particles(140)
		p.lifetime = 3.2
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(width * 0.65, 0.3, width * 0.65)
		p.direction = Vector3.DOWN
		p.spread = 20.0
		p.initial_velocity_min = 0.2
		p.initial_velocity_max = 0.6
		p.gravity = Vector3(0, -0.8, 0)
		p.scale_amount_min = 0.4
		p.scale_amount_max = 1.0
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 0.0))
		curve.add_point(Vector2(0.15, 1.0))
		curve.add_point(Vector2(0.7, 0.8))
		curve.add_point(Vector2(1.0, 0.0))
		p.scale_amount_curve = curve
		var tint := Color("ffd76a") if i == 0 else Color("eef3ff")
		p.mesh = _spark_mesh(tint, 0.035)
		board.add_child(p)
		p.global_position = Vector3(0, board.size * BoardView.LAYER + 1.6, 0)
		p.emitting = true
		p.finished.connect(p.queue_free)
	for pos in line:
		burst(board, _top_of(board, pos), color.lerp(Color("ffd76a"), 0.5), 24, 2.0, 1.6)
	camera.add_trauma(0.3)
	Sfx.play("win", 1.25)


# ---------------------------------------------------------------- Felles

## Et smell av gnister. Brukes også av andre effekter.
# ---------------------------------------------------------------- Kaos

static func _chaos(board: BoardView, camera: CameraRig, line: Array, color: Color) -> void:
	# Kameraet rister ekstra hardt i flere sekunder
	camera.shake_boost = 2.8
	var shake := camera.create_tween()
	for i in 24:
		shake.tween_callback(camera.add_trauma.bind(0.55))
		shake.tween_interval(0.12)
	shake.tween_property(camera, "shake_boost", 1.0, 0.9)

	# En kjempebrikke i vinnerens drakt faller fra himmelen og spretter tre ganger
	var giant := MeshInstance3D.new()
	giant.mesh = board._piece_mesh
	var src: MeshInstance3D = board._pieces.get(line[0])
	giant.material_override = src.material_override.duplicate() if src else _glow_material(color, 1.0)
	var big := BoardView.PIECE_SCALE * 6.0
	giant.scale = Vector3.ONE * big
	board.add_child(giant)
	var land := Vector3(0, BoardView.LAYER * 0.2, 0)
	giant.position = land + Vector3(0, 30, 0)
	giant.rotation = Vector3(0.7, 0.0, 0.5)
	var t := giant.create_tween()
	t.tween_property(giant, "position", land, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(giant, "rotation", Vector3.ZERO, 0.6)
	var heights := [6.0, 3.0, 0.0]
	for i in 3:
		t.tween_callback(_impact.bind(board, camera, land, i))
		t.tween_property(giant, "scale", Vector3(big * 1.4, big * 0.55, big * 1.4), 0.07)
		t.tween_property(giant, "scale", Vector3.ONE * big, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if heights[i] > 0.0:
			t.tween_property(giant, "position", land + Vector3(0, heights[i], 0), 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			t.tween_property(giant, "position", land, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(giant, "rotation:y", TAU * 2.0, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_property(giant, "scale", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(giant.queue_free)


## Et nedslag fra kjempebrikken: smell, regnbuegnister, og (første gang) alt kastes opp.
static func _impact(board: BoardView, camera: CameraRig, at: Vector3, n: int) -> void:
	camera.add_trauma(1.0)
	Sfx.play("boom", 0.6 + n * 0.2)
	Settings.vibrate(150)
	for k in 7:
		var off := Vector3(randf_range(-2.5, 2.5), 0.4, randf_range(-2.5, 2.5))
		burst(board, at + off, Color.from_hsv(randf(), 0.8, 1.0), 36, 10.0 - n * 2.0)
	if n == 0:
		_launch_pieces(board)
		_piece_rain(board)


## Alle brikkene på brettet kastes opp i lufta, snurrer, og lander der de sto.
static func _launch_pieces(board: BoardView) -> void:
	for piece: MeshInstance3D in board._pieces.values():
		var root := piece.get_parent() as Node3D
		if root == null:
			continue
		var start := root.position
		var up := Vector3(randf_range(-0.8, 0.8), randf_range(2.5, 6.0), randf_range(-0.8, 0.8))
		var t := root.create_tween()
		t.tween_interval(randf() * 0.15)
		t.tween_property(root, "position", start + up, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(root, "position", start, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		var spin := piece.create_tween()
		spin.tween_property(piece, "rotation", Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9)), 0.55)
		spin.tween_property(piece, "rotation", Vector3.ZERO, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Små brikker i alle regnbuens farger regner ned over brettet.
static func _piece_rain(board: BoardView) -> void:
	var half := board.size * BoardView.SPACING * 0.5 + 1.5
	for i in particles(50):
		var m := MeshInstance3D.new()
		m.mesh = board._piece_mesh
		m.material_override = _glow_material(Color.from_hsv(randf(), 0.75, 1.0), 1.0)
		m.scale = Vector3.ONE * BoardView.PIECE_SCALE * randf_range(0.35, 0.75)
		board.add_child(m)
		m.position = Vector3(randf_range(-half, half), 10.0 + randf() * 8.0, randf_range(-half, half))
		m.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var t := m.create_tween()
		t.tween_interval(randf() * 1.2)
		t.tween_property(m, "position:y", -2.0, randf_range(0.9, 1.6)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(m, "rotation", m.rotation + Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9)), 1.6)
		t.tween_callback(m.queue_free)


static func burst(parent: Node3D, at: Vector3, color: Color, amount: int, speed: float, lifetime := 1.8) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = particles(amount)
	p.lifetime = lifetime
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -7.0, 0)
	p.damping_min = 1.0
	p.damping_max = 2.5
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	p.scale_amount_curve = _fade_curve()
	p.mesh = _spark_mesh(color, 0.09)
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


static func _spark_mesh(color: Color, radius: float) -> SphereMesh:
	var key := "%s:%.3f" % [color.to_html(), radius]
	if _spark_cache.has(key):
		return _spark_cache[key]
	if _spark_cache.size() > 64:
		_spark_cache.clear()
	var mesh := SphereMesh.new()
	_spark_cache[key] = mesh
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = _glow_material(color, 2.2)
	return mesh


## Færre partikler på telefon og nettbrett (de har svakere prosessor, og partiklene regnes ut der).
static func particles(n: int) -> int:
	return maxi(1, n / 2) if UI.is_touch_device() else n


## Tegner effektenes materialer én gang, usynlig under brettet, så shaderne er kompilert før
## partiet er slutt. Kalles når partiet starter.
static func prewarm(board: BoardView) -> void:
	var holder := Node3D.new()
	board.add_child(holder)
	holder.position = Vector3(0, -0.6, 0)
	var spark := CPUParticles3D.new()
	spark.amount = 1
	spark.lifetime = 0.2
	spark.mesh = _spark_mesh(Color.WHITE, 0.09)
	holder.add_child(spark)
	spark.emitting = true
	var solid := MeshInstance3D.new()
	var tiny := SphereMesh.new()
	tiny.radius = 0.01
	tiny.height = 0.02
	solid.mesh = tiny
	solid.material_override = _glow_material(Color.WHITE, 2.0)
	holder.add_child(solid)
	var clear := MeshInstance3D.new()
	clear.mesh = tiny
	var see_through := _glow_material(Color.WHITE, 2.0)
	see_through.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	clear.material_override = see_through
	holder.add_child(clear)
	var t := holder.create_tween()
	t.tween_interval(0.5)
	t.tween_callback(holder.queue_free)


static func _glow_material(color: Color, boost: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r * boost, color.g * boost, color.b * boost)   # > 1 gir bloom
	return mat


static func _fade_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	return curve
