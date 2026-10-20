class_name BoardMesh
extends RefCounted
## Lager brettplaten: en flat, firkantet plate med avrundede hjørner.
## Overflate 0 = toppen (y = 0), overflate 1 = sidene (ned til y = -thickness).


static func build(width: float, thickness: float, radius: float, segments := 10) -> ArrayMesh:
	var outline := _rounded_rect(width * 0.5 - radius, radius, segments)
	var mesh := ArrayMesh.new()

	# Toppen: vifte av trekanter fra midten (formen er konveks).
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3.ZERO
	for i in outline.size():
		var a: Vector2 = outline[i].p
		var b: Vector2 = outline[(i + 1) % outline.size()].p
		_tri(top, center, Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3.UP, Vector3.UP, Vector3.UP)
	top.commit(mesh)

	# Sidene: firkanter rundt kanten, med myke normaler i hjørnene.
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in outline.size():
		var a: Dictionary = outline[i]
		var b: Dictionary = outline[(i + 1) % outline.size()]
		var at := Vector3(a.p.x, 0, a.p.y)
		var bt := Vector3(b.p.x, 0, b.p.y)
		var ab := at - Vector3(0, thickness, 0)
		var bb := bt - Vector3(0, thickness, 0)
		var na := Vector3(a.n.x, 0, a.n.y)
		var nb := Vector3(b.n.x, 0, b.n.y)
		_tri(sides, at, bt, bb, na, nb, nb)
		_tri(sides, at, bb, ab, na, nb, na)
	sides.commit(mesh)
	return mesh


## Punktene rundt et avrundet kvadrat (x, z), med utovervendt normal for hvert punkt.
static func _rounded_rect(half_inner: float, radius: float, segments: int) -> Array:
	var out := []
	var corners := [Vector2(half_inner, half_inner), Vector2(-half_inner, half_inner),
		Vector2(-half_inner, -half_inner), Vector2(half_inner, -half_inner)]
	for c in 4:
		for s in segments + 1:
			var angle := deg_to_rad(90.0 * c + 90.0 * s / segments)
			var n := Vector2(cos(angle), sin(angle))
			out.append({ "p": corners[c] + n * radius, "n": n })
	return out


## Legger til en trekant med riktig omløpsretning (Godot: med klokka = forside),
## uansett hvilken rekkefølge punktene kommer i.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	var facing := (b - a).cross(c - a).dot(na + nb + nc)
	if facing > 0.0:
		var tmp := b
		b = c
		c = tmp
		var tn := nb
		nb = nc
		nc = tn
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)
