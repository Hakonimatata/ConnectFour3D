shader_type spatial;
render_mode unshaded;
// Enkel toon-shader for brikkene. Fungerer i Compatibility-rendereren (web og mobil).

uniform vec4 base_color : source_color = vec4(0.7, 0.7, 0.7, 1.0);

// Toon-kontroller
uniform float steps : hint_range(1.0, 8.0) = 3.0;
uniform float shadow_floor : hint_range(0.0, 1.0) = 0.35;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.3;

// Glød (bloom). 0 betyr av.
uniform float emission_energy : hint_range(0.0, 20.0) = 0.0;

void fragment() {
	// «Falskt» lys ovenfra i view-space, gir stabil toon-look uavhengig av lysoppsett.
	vec3 N = normalize(NORMAL);
	vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float ndl = clamp(dot(N, up_view) * 0.5 + 0.5, 0.0, 1.0);

	float s = max(steps, 2.0);
	float q = floor(ndl * s) / (s - 1.0);
	q = clamp(max(q, shadow_floor), 0.0, 1.0);

	float rim = pow(1.0 - max(dot(N, VIEW), 0.0), 2.0) * rim_strength;

	vec3 base = base_color.rgb;
	// Unshaded: fargen vises som den er. Verdier over 1 gir glød via bloom.
	ALBEDO = base * q + base * rim + base * emission_energy;
}
