shader_type canvas_item;
// Bakgrunnen bak 3D-verdenen. Alt tegnes med kode (ingen bilder), så nedlastingen ikke blir større.
//   style 0  Standard: rolig gradient, lysere oppe, en svak lysflekk i midten
//   style 1  Nebula: gass-skyer i lilla og blått med stjerner
//   style 2  Stjernehimmel: mørk himmel med blinkende stjerner
//   style 3  Kaffebar: varm brun gradient med uskarpe lys (bokeh)
// Litt støy (dithering) til slutt, så gradientene ikke får synlige striper.

uniform int style = 0;
uniform vec4 top_color : source_color = vec4(0.11, 0.125, 0.16, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.05, 0.06, 0.075, 1.0);
uniform vec4 glow_color : source_color = vec4(0.165, 0.185, 0.23, 1.0);
uniform vec2 glow_center = vec2(0.55, 0.42);
uniform float glow_strength = 0.6;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// Stjerner: én mulig stjerne per rute, som blinker sakte.
float stars(vec2 p, float density, float t) {
	vec2 cell = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = hash(cell);
	if (h > density) {
		return 0.0;
	}
	vec2 offset = vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5;
	float d = length(f - offset * 0.7);
	float twinkle = 0.6 + 0.4 * sin(t * (1.0 + h * 3.0) + h * 40.0);
	return smoothstep(0.08, 0.0, d) * twinkle;
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 uv = vec2(UV.x * aspect, UV.y);   // kvadratiske ruter uansett skjermform
	vec3 c;
	if (style == 1) {
		vec3 deep = mix(vec3(0.03, 0.02, 0.07), vec3(0.01, 0.015, 0.04), UV.y);
		vec2 q = uv * 2.2 + vec2(TIME * 0.006, 0.0);
		float n = fbm(q + fbm(q * 0.8 + TIME * 0.01));
		float m = fbm(q * 1.6 - 4.0);
		c = deep;
		c += vec3(0.32, 0.10, 0.42) * smoothstep(0.42, 0.85, n) * 0.9;
		c += vec3(0.08, 0.22, 0.45) * smoothstep(0.45, 0.9, m) * 0.8;
		c += vec3(0.85, 0.5, 0.75) * pow(smoothstep(0.6, 0.95, n * m * 1.6), 2.0) * 0.25;
		c += vec3(1.0) * stars(uv * 90.0, 0.10, TIME) * 0.8;
		c += vec3(0.8, 0.9, 1.0) * stars(uv * 40.0 + 13.0, 0.05, TIME * 0.7);
	} else if (style == 2) {
		c = mix(vec3(0.03, 0.05, 0.11), vec3(0.005, 0.01, 0.03), smoothstep(0.0, 1.0, UV.y));
		c += vec3(0.05, 0.08, 0.14) * (1.0 - smoothstep(0.0, 0.6, abs(UV.y - 0.75)));   // svak horisont
		c += vec3(1.0) * stars(uv * 120.0, 0.12, TIME) * 0.7;
		c += vec3(0.85, 0.9, 1.0) * stars(uv * 55.0 + 5.0, 0.07, TIME * 0.8);
		c += vec3(1.0, 0.95, 0.85) * stars(uv * 22.0 + 2.0, 0.04, TIME * 0.5) * 1.2;
	} else if (style == 3) {
		c = mix(vec3(0.20, 0.12, 0.07), vec3(0.07, 0.04, 0.025), smoothstep(0.0, 1.0, UV.y));
		vec2 d0 = (UV - vec2(0.5, 0.3)) * vec2(1.0, aspect);
		c += vec3(0.25, 0.14, 0.05) * (1.0 - smoothstep(0.0, 0.9, length(d0)));
		// Uskarpe lys i bakgrunnen: noen runde lysflekker per rute, som puster sakte
		vec2 g = uv * 5.0;
		for (int k = 0; k < 2; k++) {
			vec2 cell = floor(g);
			vec2 f = fract(g) - 0.5;
			float h = hash(cell + float(k) * 17.0);
			if (h < 0.45) {
				vec2 o = vec2(hash(cell + 1.3), hash(cell + 4.1)) - 0.5;
				float r = 0.12 + 0.18 * hash(cell + 9.0);
				float b = smoothstep(r, r * 0.6, length(f - o * 0.5));
				float breathe = 0.7 + 0.3 * sin(TIME * 0.6 + h * 30.0);
				vec3 tint = mix(vec3(1.0, 0.65, 0.3), vec3(1.0, 0.85, 0.55), hash(cell + 2.0));
				c += tint * b * 0.10 * breathe * (1.0 - UV.y * 0.6);
			}
			g = g * 0.55 + 3.7;
		}
	} else {
		c = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.0, 1.0, UV.y));
		vec2 d = (UV - glow_center) * vec2(1.0, aspect);
		float glow = 1.0 - smoothstep(0.0, 0.85, length(d));
		c = mix(c, glow_color.rgb, glow * glow_strength);
	}
	float dither = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	c += (dither - 0.5) / 255.0;
	COLOR = vec4(c, 1.0);
}
