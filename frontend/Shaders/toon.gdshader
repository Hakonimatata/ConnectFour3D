shader_type spatial;

// Farge fra script
uniform vec4 base_color : source_color = vec4(0.7, 0.7, 0.7, 1.0);

// Toon-kontroller
uniform float steps : hint_range(1.0, 8.0) = 3.0;
uniform float shadow_floor : hint_range(0.0, 1.0) = 0.18;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.22;

// Glød (BLOOM) – 0 betyr AV
uniform float emission_energy : hint_range(0.0, 20.0) = 0.0;

void fragment() {
	vec3 N = normalize(NORMAL);
	// Godot gir en "default" light dir i shading; for enkel/stabil toon bruker vi N.y som fake-lys
	// (Bytt til ekte lys hvis du vil senere)
	float ndl = clamp(N.y * 0.5 + 0.5, 0.0, 1.0);

	// Toon quantize
	float s = max(steps, 1.0);
	float q = floor(ndl * s) / (s - 1.0);
	q = max(q, shadow_floor);

	// Rim light
	vec3 V = normalize(VIEW);
	float rim = pow(1.0 - max(dot(N, V), 0.0), 2.0) * rim_strength;

	vec3 base = base_color.rgb;
	vec3 lit = base * q + base * rim;

	ALBEDO = lit;
	ALPHA = base_color.a;

	// Bloom/Glow: samme farge som brikken, bare lysere
	EMISSION = base * emission_energy;
}
