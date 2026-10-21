shader_type spatial;
render_mode cull_disabled;
// Toppen av brettet: flat flate med et diskré rutenett.
// Bare de indre linjene tegnes (på 4×4: 3 + 3 = 6 streker), med avrundede ender.
// Koordinatene kommer fra meshen (lokal x/z), så rutenettet følger brettstørrelsen.

uniform vec3 base_color : source_color = vec3(0.17, 0.185, 0.215);
uniform vec3 line_color : source_color = vec3(0.235, 0.252, 0.285);
uniform float cells = 4.0;          // antall ruter per side
uniform float spacing = 1.0;        // størrelse på en rute
uniform float half_width = 0.03;    // halv linjebredde, i ruter
uniform float end_inset = 0.12;     // hvor langt fra kanten linjene slutter, i ruter
uniform float grain = 0.0;          // 1 = treverk (årer i platen)

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

// Avstand fra p til en linje med avrundede ender langs x = k, fra y = a til y = b.
float capsule(vec2 p, float k, float a, float b) {
	float dy = max(max(a - p.y, p.y - b), 0.0);
	return length(vec2(p.x - k, dy));
}

void fragment() {
	vec2 p = local_pos.xz / spacing + vec2(cells * 0.5);   // 0..cells over spilleområdet
	float a = end_inset;
	float b = cells - end_inset;

	// Nærmeste indre linje i hver retning (1 .. cells-1)
	float kx = clamp(round(p.x), 1.0, cells - 1.0);
	float ky = clamp(round(p.y), 1.0, cells - 1.0);
	float d = min(capsule(p, kx, a, b), capsule(p.yx, ky, a, b));

	float aa = fwidth(d) * 1.2;
	float line = 1.0 - smoothstep(half_width, half_width + aa, d);

	vec3 base = base_color;
	if (grain > 0.0) {
		// Treårer langs platen: lange, svakt bølgende striper og fine fibre
		float x = local_pos.x + sin(local_pos.z * 0.45 + local_pos.x * 0.8) * 0.35;
		float g = sin(x * 6.0 + sin(x * 2.1) * 2.0);
		float fiber = sin(x * 47.0 + sin(local_pos.z * 0.9) * 3.0) * sin(x * 13.0);
		base *= 1.0 + grain * (0.05 * g + 0.025 * fiber);
	}
	ALBEDO = mix(base, line_color, line);
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
