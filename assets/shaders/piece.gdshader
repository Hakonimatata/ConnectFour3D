shader_type spatial;
render_mode unshaded;
// Brikke-shader med flere stiler (skins). Alt er laget i shaderen (ingen teksturer),
// så det er lett og fungerer i Compatibility-rendereren (web og mobil).
// Lyset er «falskt» (fra skjermens oppside), slik at brikkene ser like ut overalt.
//
// Stiler: 0 glatt, 1 metall, 2 lava, 3 galakse, 4 holografisk, 5 neon, 6 marmor, 7 karbon, 8 striper
// Merker (decal på toppen): 0 ingen, 1 stjerne, 2 prikk, 3 ring, 4 kryss, 5 diamant, 6 hjerte

uniform int style = 0;
uniform vec4 color_a : source_color = vec4(0.0, 0.5, 1.0, 1.0);   // nederst / hovedfarge
uniform vec4 color_b : source_color = vec4(0.3, 0.75, 1.0, 1.0);  // øverst / detaljfarge
uniform int decal = 0;
uniform vec4 decal_color : source_color = vec4(1.0, 1.0, 1.0, 0.9);
uniform float emission_energy = 0.0;   // glød (vinnerlinje)
uniform float dim = 0.0;               // 0..1, mørkere (brikker utenfor vinnerlinjen)

// piece.obj: radius ~0.087, høyde 0..0.126 (før skalering)
const float HEIGHT = 0.126;
const float TOP_R = 0.068;

varying vec3 lpos;
varying vec3 lnorm;

void vertex() {
	lpos = VERTEX;
	lnorm = NORMAL;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
				   mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
				   mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise3(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

vec3 hue(float h) {
	return clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

// --- Merker (avstandsfelt i en enhetssirkel på toppen) ---
float sd_star(vec2 p, float r, float rf) {
	vec2 k1 = vec2(0.809016994375, -0.587785252292);
	vec2 k2 = vec2(-0.809016994375, -0.587785252292);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0, 1);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

float sd_heart(vec2 p) {
	p.x = abs(p.x);
	if (p.y + p.x > 1.0) {
		return sqrt(dot(p - vec2(0.25, 0.75), p - vec2(0.25, 0.75))) - sqrt(2.0) / 4.0;
	}
	vec2 a = p - vec2(0.0, 1.0);
	vec2 b = p - 0.5 * max(p.x + p.y, 0.0);
	return sqrt(min(dot(a, a), dot(b, b))) * sign(p.x - p.y);
}

float decal_sdf(vec2 p) {
	if (decal == 1) return sd_star(p * vec2(1.0, -1.0), 0.62, 0.45);
	if (decal == 2) return length(p) - 0.32;
	if (decal == 3) return abs(length(p) - 0.55) - 0.09;
	if (decal == 4) {
		vec2 q = abs(mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071)) * p);
		return min(max(q.x - 0.6, q.y - 0.12), max(q.y - 0.6, q.x - 0.12));
	}
	if (decal == 5) return (abs(p.x) + abs(p.y)) - 0.55;
	if (decal == 6) return sd_heart(p * 1.35 + vec2(0.0, 0.62)) / 1.35;
	return 1.0;
}

void fragment() {
	vec3 N = normalize(NORMAL);
	vec3 V = normalize(VIEW);
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 key = normalize(up + normalize((VIEW_MATRIX * vec4(0.4, 0.0, 0.3, 0.0)).xyz) * 0.6);
	float h = clamp(lpos.y / HEIGHT, 0.0, 1.0);
	float ang = atan(lpos.z, lpos.x);
	bool is_top = lnorm.y > 0.7;

	float ndl = clamp(dot(N, up) * 0.5 + 0.5, 0.0, 1.0);
	// Myke «toon»-trinn (harde trinn gir korn på flater som ligger nær en grense)
	float toon = 0.42 + 0.58 * (0.5 * smoothstep(0.3, 0.45, ndl) + 0.5 * smoothstep(0.62, 0.78, ndl));
	float rim = pow(1.0 - max(dot(N, V), 0.0), 2.2);
	vec3 R = reflect(-V, N);
	float spec = pow(max(dot(R, key), 0.0), 36.0);
	vec3 base = mix(color_a.rgb, color_b.rgb, h);
	vec3 col = base;
	vec3 glow = vec3(0.0);

	if (style == 0) {           // glatt toon med myk gradient
		col = base * toon + base * rim * 0.35 + vec3(spec) * 0.18;
	} else if (style == 1) {    // metall: falsk speiling av en lys himmel og et mørkt gulv
		float sky = smoothstep(-0.35, 0.75, dot(R, up));
		vec3 env = mix(base * 0.22, mix(base, vec3(1.0), 0.35), sky);
		col = env + vec3(spec) * mix(vec3(1.0), base, 0.25) * 1.3 + base * rim * 0.4;
	} else if (style == 2) {    // lava: mørk stein med glødende sprekker
		float n = fbm(lpos * 38.0 + vec3(0.0, -TIME * 0.35, 0.0));
		float crack = 1.0 - smoothstep(0.02, 0.09, abs(n - 0.5));
		vec3 stone = color_b.rgb * (0.25 + 0.35 * toon);
		float pulse = 0.75 + 0.25 * sin(TIME * 2.2 + n * 9.0);
		col = stone + color_a.rgb * crack * pulse * 1.6;
		glow = color_a.rgb * crack * 0.6;
	} else if (style == 3) {    // galakse: tåke og blinkende stjerner
		float neb = fbm(lpos * 22.0 + vec3(TIME * 0.05));
		col = mix(color_a.rgb, color_b.rgb, neb) * (0.55 + 0.45 * toon);
		vec3 cell = floor(lpos * 160.0);
		float star = step(0.985, hash3(cell));
		float tw = 0.5 + 0.5 * sin(TIME * 3.0 + hash3(cell + 7.0) * 30.0);
		col += vec3(star * tw * 1.4);
		col += color_b.rgb * rim * 0.6;
	} else if (style == 4) {    // holografisk: regnbue som skifter med synsvinkel
		float t = dot(N, V) * 1.2 + h * 0.6 + ang * 0.08 + TIME * 0.05;
		vec3 iris = mix(hue(t), vec3(1.0), 0.35);   // perlemor: regnbue blandet med hvitt
		col = mix(base, iris, 0.4) * (0.78 + 0.22 * toon) + vec3(spec) * 0.8 + iris * rim * 0.35;
	} else if (style == 5) {    // neon: mørk kropp med glødende kanter
		vec3 body = vec3(0.06, 0.065, 0.08) * (0.6 + 0.6 * toon);
		float pulse = 0.8 + 0.2 * sin(TIME * 3.0);
		float g;
		if (is_top) {
			// Toppen: mørk, med en lysende ring langs kanten
			float r = length(lpos.xz) / TOP_R;
			g = smoothstep(0.78, 0.9, r) * (1.0 - smoothstep(1.02, 1.12, r));
		} else {
			float bands = smoothstep(0.88, 0.96, h) + (1.0 - smoothstep(0.04, 0.12, h));
			float lines = pow(max(0.0, sin(ang * 6.0)), 60.0);
			g = clamp(bands + lines * 0.8 + rim * 0.5, 0.0, 1.0);
		}
		g *= pulse;
		col = body + mix(color_a.rgb, color_b.rgb, h) * g * 1.7;
		glow = color_a.rgb * g * 0.5;
	} else if (style == 6) {    // marmor: årer gjennom steinen
		float n = fbm(lpos * 30.0);
		float vein = abs(sin((lpos.x + lpos.y * 0.6) * 90.0 + n * 9.0));
		vein = 1.0 - smoothstep(0.0, 0.18, vein);
		col = mix(color_a.rgb, color_b.rgb, vein * 0.85) * (0.7 + 0.3 * toon) + vec3(spec) * 0.35;
	} else if (style == 7) {    // karbonfiber med en farget stripe
		vec2 w = vec2(ang * 9.0, h * 14.0);
		float weave = step(0.5, fract(w.x + floor(w.y) * 0.5)) * 0.5 + step(0.5, fract(w.y)) * 0.25;
		vec3 carbon = vec3(0.07 + weave * 0.08) * (0.6 + 0.6 * toon) + vec3(spec) * 0.5;
		float stripe = smoothstep(0.42, 0.45, h) * (1.0 - smoothstep(0.58, 0.61, h));
		col = mix(carbon, color_a.rgb * toon, stripe);
	} else if (style == 8) {    // racingstriper
		float band = step(0.3, h) * (1.0 - step(0.42, h)) + step(0.58, h) * (1.0 - step(0.7, h));
		vec3 c = mix(color_a.rgb, color_b.rgb, band);
		col = c * toon + c * rim * 0.3 + vec3(spec) * 0.25;
	}

	// Merke på toppen av brikken
	if (decal > 0 && is_top) {
		vec2 p = lpos.xz / TOP_R;
		float d = decal_sdf(p);
		float aa = fwidth(d) * 1.2;
		float m = (1.0 - smoothstep(-aa, aa, d)) * decal_color.a;
		col = mix(col, decal_color.rgb * (0.85 + 0.15 * toon), m);
	}

	col = col * (1.0 - dim * 0.6) + base * emission_energy + glow * (1.0 - dim);
	ALBEDO = col;
}
