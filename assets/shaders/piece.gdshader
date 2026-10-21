shader_type spatial;
render_mode unshaded;
// Brikke-shader med flere stiler (skins). Alt er laget i shaderen (ingen teksturer),
// så det er lett og fungerer i Compatibility-rendereren (web og mobil).
// Lyset er «falskt» (fra skjermens oppside), slik at brikkene ser like ut overalt.
//
// Stiler: 0 glatt, 1 metall, 2 lava, 3 galakse, 4 holografisk, 5 neon, 6 marmor, 7 karbon, 8 striper,
//         9 nordlys, 10 is, 11 tre, 12 keramikk, 13 glass, 14 kobber med patina,
//         15 plasma, 16 kintsugi, 17 damaskusstål, 18 kretskort, 19 disco, 20 opal, 21 piksel,
//         22 kode, 23 giftig, 24 sort hull
// Merker (decal på toppen): 0 ingen, 1 stjerne, 2 prikk, 3 ring, 4 kryss, 5 diamant, 6 hjerte,
//         7 sekskant, 8 måne, 9 krone, 10 lyn, 11 pil

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

// Polygoner for krone og lyn (avstand til kanten, negativ inni)
const vec2 CROWN[7] = vec2[7](vec2(-0.62, -0.38), vec2(0.62, -0.38), vec2(0.62, 0.38), vec2(0.3, 0.02),
	vec2(0.0, 0.48), vec2(-0.3, 0.02), vec2(-0.62, 0.38));
const vec2 BOLT[6] = vec2[6](vec2(0.18, 0.66), vec2(-0.38, 0.02), vec2(-0.04, 0.02), vec2(-0.2, -0.66),
	vec2(0.38, 0.1), vec2(0.04, 0.1));

float sd_crown(vec2 p) {
	float d = dot(p - CROWN[0], p - CROWN[0]);
	float s = 1.0;
	for (int i = 0; i < 7; i++) {
		vec2 vi = CROWN[i];
		vec2 vj = CROWN[(i + 6) % 7];
		vec2 e = vj - vi;
		vec2 w = p - vi;
		vec2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
		d = min(d, dot(b, b));
		bool c1 = p.y >= vi.y;
		bool c2 = p.y < vj.y;
		bool c3 = e.x * w.y > e.y * w.x;
		if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) s *= -1.0;
	}
	return s * sqrt(d);
}

float sd_bolt(vec2 p) {
	float d = dot(p - BOLT[0], p - BOLT[0]);
	float s = 1.0;
	for (int i = 0; i < 6; i++) {
		vec2 vi = BOLT[i];
		vec2 vj = BOLT[(i + 5) % 6];
		vec2 e = vj - vi;
		vec2 w = p - vi;
		vec2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
		d = min(d, dot(b, b));
		bool c1 = p.y >= vi.y;
		bool c2 = p.y < vj.y;
		bool c3 = e.x * w.y > e.y * w.x;
		if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) s *= -1.0;
	}
	return s * sqrt(d);
}

float sd_hexagon(vec2 p, float r) {
	vec3 k = vec3(-0.866025404, 0.5, 0.577350269);
	p = abs(p);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
	p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float decal_sdf(vec2 p) {
	if (decal == 1) return sd_star(p, 0.62, 0.45);
	if (decal == 2) return length(p) - 0.32;
	if (decal == 3) return abs(length(p) - 0.55) - 0.09;
	if (decal == 4) {
		vec2 q = abs(mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071)) * p);
		return min(max(q.x - 0.6, q.y - 0.12), max(q.y - 0.6, q.x - 0.12));
	}
	if (decal == 5) return (abs(p.x) + abs(p.y)) - 0.55;
	if (decal == 6) return sd_heart(p * 1.35 + vec2(0.0, 0.62)) / 1.35;
	if (decal == 7) return abs(sd_hexagon(p, 0.5)) - 0.08;
	if (decal == 8) return max(length(p) - 0.56, -(length(p - vec2(0.26, 0.16)) - 0.46));
	if (decal == 9) return sd_crown(p);
	if (decal == 10) return sd_bolt(p);
	if (decal == 11) {
		// Pil (chevron): to skrå bjelker som møtes i en spiss
		vec2 q = vec2(abs(p.x), -p.y);
		q = mat2(vec2(0.766, -0.643), vec2(0.643, 0.766)) * (q - vec2(0.26, 0.0));
		return sd_box(q, vec2(0.36, 0.11));
	}
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
		// Fargene glir mellom draktens to farger etter synsvinkel og høyde. sin/cos av vinkelen
		// (ikke vinkelen selv) gir ingen søm rundt brikken.
		float t = dot(N, V) * 1.6 + h * 0.9 + 0.35 * sin(ang * 2.0) + 0.25 * cos(ang * 3.0) + TIME * 0.12;
		vec3 shift = mix(color_a.rgb, color_b.rgb, 0.5 + 0.5 * sin(t * 6.2831853));
		vec3 sheen = hue(t * 0.5) * 0.18;   // en svak regnbuehinne
		vec3 pearl = mix(shift, vec3(1.0), 0.18) + sheen;
		col = pearl * (0.78 + 0.22 * toon) + vec3(spec) * 0.8 + shift * rim * 0.5;
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
	} else if (style == 9) {    // nordlys: mørk himmel med bølgende lysbånd
		vec3 sky = color_a.rgb * (0.7 + 0.5 * toon);
		float flow = fbm(vec3(lpos.x * 18.0, lpos.y * 10.0 - TIME * 0.15, lpos.z * 18.0));
		float wave = sin(ang * 3.0 + h * 7.0 + TIME * 0.7 + flow * 5.0);
		float band = smoothstep(0.35, 1.0, wave) * smoothstep(0.05, 0.6, h);
		vec3 light = mix(color_b.rgb, color_b.rgb.bgr, 0.5 + 0.5 * sin(h * 4.0 + TIME * 0.3));
		col = sky + light * band * 1.4 + color_b.rgb * rim * 0.35;
		glow = light * band * 0.35;
	} else if (style == 10) {   // is: frostede fasetter, blank kant og små glimt
		float facet = hash3(floor(lpos * 55.0 + vec3(0.5)));
		vec3 icec = mix(color_a.rgb, color_b.rgb, facet * 0.6 + h * 0.4);
		vec3 cell = floor(lpos * 140.0);
		float spark = step(0.992, hash3(cell)) * (0.5 + 0.5 * sin(TIME * 4.0 + hash3(cell + 3.0) * 20.0));
		col = icec * (0.75 + 0.25 * toon) + vec3(1.0) * rim * 0.55 + vec3(spec) * 1.2 + vec3(spark);
	} else if (style == 11) {   // tre: årringer og fiber
		float r = length(lpos.xz) * 70.0 + fbm(lpos * 28.0) * 2.5 + lpos.y * 4.0;
		float rings = smoothstep(0.15, 0.85, abs(fract(r) - 0.5) * 2.0);
		float fiber = noise3(vec3(lpos.x * 300.0, lpos.y * 18.0, lpos.z * 300.0)) * 0.12;
		vec3 wood = mix(color_a.rgb, color_b.rgb, rings) - fiber;
		col = wood * (0.65 + 0.35 * toon) + vec3(spec) * 0.12;
	} else if (style == 12) {   // keramikk: matt glasur med fine prikker
		float speck = step(0.975, hash3(floor(lpos * 320.0)));
		vec3 c = mix(color_a.rgb, color_b.rgb, h);
		col = c * (0.72 + 0.28 * toon) - speck * 0.12 + c * rim * 0.12;
	} else if (style == 13) {   // glass: mørk, farget kropp med lys kant og skarpe refleksjoner
		vec3 body = color_a.rgb * (0.22 + 0.25 * ndl);
		float inner = smoothstep(0.2, 0.9, h) * (1.0 - smoothstep(0.9, 1.0, h));
		col = body + color_a.rgb * inner * 0.25 + color_b.rgb * rim * 1.1 + vec3(spec) * 1.6;
		glow = color_b.rgb * rim * 0.2;
	} else if (style == 14) {   // kobber med grønn patina i flekker
		float sky = smoothstep(-0.35, 0.75, dot(R, up));
		vec3 metal = mix(base * 0.25, mix(base, vec3(1.0), 0.3), sky) + vec3(spec) * mix(vec3(1.0), base, 0.3);
		float mask = smoothstep(0.52, 0.68, fbm(lpos * 26.0 + vec3(3.1)));
		vec3 patina = vec3(0.33, 0.68, 0.58) * (0.6 + 0.4 * toon);
		col = mix(metal, patina, mask * 0.85);
	} else if (style == 15) {   // plasma: elektriske buer som kryper over en mørk kjerne
		vec3 q = lpos * 30.0;
		float n1 = fbm(q + vec3(0.0, TIME * 0.6, 0.0));
		float n2 = fbm(q * 1.3 + vec3(TIME * 0.4, 5.2, -TIME * 0.3));
		float dn = abs(n1 - n2);
		float arc = 1.0 - smoothstep(0.0, 0.035 + fwidth(dn), dn);
		float flicker = 0.8 + 0.2 * sin(TIME * 23.0 + n1 * 40.0);
		col = color_a.rgb * (0.2 + 0.25 * toon) + color_b.rgb * arc * 2.2 * flicker + color_b.rgb * rim * 0.9;
		glow = color_b.rgb * (arc * 0.7 + rim * 0.3);
	} else if (style == 16) {   // kintsugi: matt keramikk reparert med gull i sprekkene
		float n = fbm(lpos * 15.0 + vec3(7.3));
		float dn = abs(n - 0.5);
		float crack = 1.0 - smoothstep(0.012, 0.012 + fwidth(dn) * 1.5, dn);
		float n2 = noise3(lpos * 60.0 + vec3(1.7));
		float dn2 = abs(n2 - 0.5);
		crack = max(crack, (1.0 - smoothstep(0.015, 0.015 + fwidth(dn2) * 1.5, dn2)) * smoothstep(0.47, 0.5, n) * (1.0 - smoothstep(0.5, 0.53, n)));
		vec3 glaze = color_a.rgb * (0.72 + 0.28 * toon) + vec3(spec) * 0.1;
		float sky = smoothstep(-0.3, 0.8, dot(R, up));
		vec3 gold = mix(color_b.rgb * 0.5, color_b.rgb * 1.4, sky) + vec3(spec) * 1.4;
		col = mix(glaze, gold, crack);
	} else if (style == 17) {   // damaskusstål: bølgende lag i blankt stål
		// Mange tynne lag som vris av støy: vannrette på siden, ringer på toppen
		float warp = fbm(lpos * 26.0) * 15.0 + noise3(lpos * 80.0) * 2.0;
		float t = lpos.y * 420.0 + length(lpos.xz) * 300.0 + warp;
		float band = smoothstep(0.25, 0.75, 0.5 + 0.5 * sin(t));
		vec3 steel = mix(color_a.rgb, color_b.rgb, 0.25 + 0.6 * band);
		float sky = smoothstep(-0.35, 0.75, dot(R, up));
		col = mix(steel * 0.3, steel * 1.15, sky) + vec3(spec) * 1.2 + steel * rim * 0.3;
	} else if (style == 18) {   // kretskort: ledningsbaner og loddepunkter med pulser som løper
		vec2 uv = is_top ? lpos.xz * 160.0 : vec2(ang * 7.0028, lpos.y * 160.0);   // 44 ruter rundt
		vec2 cell = floor(uv);
		vec2 f = fract(uv) - 0.5;
		float hrow = step(0.45, hash3(vec3(cell.y, floor(cell.x / 4.0), 1.3)));
		float vcol = step(0.7, hash3(vec3(cell.x, floor(cell.y / 3.0), 5.1)));
		float hl = hrow * (1.0 - smoothstep(0.1, 0.17, abs(f.y)));
		float vl = vcol * (1.0 - smoothstep(0.1, 0.17, abs(f.x)));
		float pad = (1.0 - smoothstep(0.24, 0.31, length(f))) * max(hrow * vcol, step(0.93, hash3(vec3(cell, 8.7))));
		float trace = max(max(hl, vl), pad);
		float pulse = smoothstep(0.8, 1.0, sin(TIME * 2.4 - (cell.x + cell.y) * 0.45 + hash3(vec3(cell.y, 2.0, 2.0)) * 6.0));
		vec3 pcb = color_a.rgb * (0.45 + 0.4 * toon);
		col = pcb + color_b.rgb * trace * (0.45 + 1.4 * pulse) * (0.7 + 0.3 * toon) + vec3(spec) * 0.2;
		glow = color_b.rgb * trace * pulse * 0.45;
	} else if (style == 19) {   // disco: speilfliser som blinker i lysshowet
		vec2 uv = is_top ? lpos.xz * 105.0 : vec2(ang * 4.7746, lpos.y * 105.0);   // 30 fliser rundt
		vec2 cell = floor(uv);
		vec2 f = fract(uv);
		float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
		float tile = smoothstep(0.05, 0.12, edge);
		float r = hash3(vec3(cell, 2.3));
		float flash = pow(max(0.0, sin(TIME * 2.2 + r * 40.0)), 14.0);
		float sky = smoothstep(-0.5, 0.9, dot(R, up) + (r - 0.5) * 0.9);
		vec3 mirror = mix(color_a.rgb * 0.22, mix(color_a.rgb, vec3(1.0), 0.4), sky);
		vec3 light = mix(color_b.rgb, hue(r + TIME * 0.07), 0.45);
		col = (mirror + light * flash * 1.8 + vec3(spec) * 0.8) * tile + vec3(0.04) * (1.0 - tile);
		glow = light * flash * 0.45 * tile;
	} else if (style == 20) {   // opal: melkehvit stein med fargespill som flytter seg med blikket
		float n = fbm(lpos * 26.0);
		float r = hash3(floor(lpos * 85.0 + vec3(n * 3.0)));
		float play = smoothstep(0.6, 0.95, sin(dot(N, V) * 10.0 + r * 30.0 + TIME * 0.3));
		vec3 fire = mix(hue(r + dot(N, V) * 0.7), color_b.rgb, 0.25);
		vec3 milk = mix(color_a.rgb, color_b.rgb, n * 0.6) * (0.78 + 0.22 * toon);
		col = milk + fire * play * 0.6 + vec3(spec) * 0.7 + color_b.rgb * rim * 0.3;
	} else if (style == 21) {   // piksel: 8-bit-klosser med få fargetrinn
		vec3 vox = floor(lpos * 75.0);
		float r = hash3(vox);
		float shade = floor(clamp(toon * 0.9 + r * 0.3, 0.0, 0.999) * 4.0) / 3.0;
		vec3 c = mix(color_a.rgb, color_b.rgb, step(0.8, r));
		vec3 fv = fract(lpos * 75.0);
		float bevel = step(0.86, max(fv.x, max(fv.y, fv.z)));
		col = c * (0.4 + 0.65 * shade) * (1.0 - bevel * 0.18);
	} else if (style == 22) {   // kode: fallende tegn i kolonner
		vec2 uv = is_top ? lpos.xz * 150.0 : vec2(ang * 6.3662, lpos.y * 150.0);   // 40 kolonner rundt
		vec2 cell = floor(uv);
		vec2 f = fract(uv);
		float off = hash3(vec3(cell.x, 3.0, 1.0));
		float t = fract(-cell.y * 0.045 - TIME * (0.25 + off * 0.45) + off * 7.0);
		float bright = pow(t, 6.0);
		vec2 g = floor(f * vec2(3.0, 5.0));
		float bit = step(0.45, hash3(vec3(cell * 7.0 + g, floor(TIME * 4.0 + off * 10.0))));
		float inside = step(0.14, f.x) * step(f.x, 0.86) * step(0.08, f.y) * step(f.y, 0.92);
		float glyph = bit * inside;
		col = color_a.rgb * (0.3 + 0.3 * toon) + color_b.rgb * glyph * (0.12 + bright * 1.8) + color_b.rgb * rim * 0.25;
		glow = color_b.rgb * glyph * bright * 0.5;
	} else if (style == 23) {   // giftig: selvlysende slim med bobler som stiger
		float n = fbm(lpos * 24.0 + vec3(0.0, -TIME * 0.25, 0.0));
		vec3 slime = mix(color_a.rgb * 0.3, color_a.rgb * 1.1, smoothstep(0.3, 0.75, n));
		vec3 bp = lpos * 110.0 + vec3(0.0, -TIME * 2.5, 0.0);
		vec3 bf = fract(bp) - 0.5;
		float br = hash3(floor(bp));
		float dl = abs(length(bf) - 0.3);
		float bubble = step(0.86, br) * (1.0 - smoothstep(0.04, 0.04 + fwidth(dl) * 1.5, dl));
		col = slime * (0.6 + 0.4 * toon) + color_b.rgb * bubble * 1.4 + color_b.rgb * rim * 0.6;
		glow = color_a.rgb * smoothstep(0.5, 0.8, n) * 0.35 + color_b.rgb * bubble * 0.3;
	} else if (style == 24) {   // sort hull: nesten svart, med en virvlende ring av lys
		vec3 voidc = vec3(0.012, 0.012, 0.018);
		if (is_top) {
			float r = length(lpos.xz) / TOP_R;
			float arms = 0.5 + 0.5 * sin((ang + r * 5.0 - TIME * 1.2) * 3.0 + fbm(lpos * 40.0) * 4.0);
			float disk = smoothstep(0.32, 0.5, r) * (1.0 - smoothstep(0.85, 1.05, r));
			float horizon = 1.0 - smoothstep(0.0, 0.05, abs(r - 0.33));
			vec3 hot = mix(color_a.rgb, color_b.rgb, arms);
			col = voidc + hot * disk * arms * 1.7 + color_b.rgb * horizon * 1.6;
			glow = hot * disk * arms * 0.45 + color_b.rgb * horizon * 0.3;
		} else {
			float band = 1.0 - smoothstep(0.0, 0.22, abs(h - 0.5 - 0.12 * sin(ang * 2.0 - TIME)));
			vec3 hot = mix(color_a.rgb, color_b.rgb, 0.5 + 0.5 * sin(ang * 6.0 - TIME * 3.0));
			col = voidc + hot * band * 0.9 + color_b.rgb * rim * 1.1;
			glow = color_b.rgb * rim * 0.4 + hot * band * 0.2;
		}
	}

	// Merke på toppen av brikken
	if (decal > 0 && is_top) {
		// y snus, så merket står rett vei sett fra spillerens side av brettet
		vec2 p = lpos.xz / TOP_R * vec2(1.0, -1.0);
		float d = decal_sdf(p);
		float aa = fwidth(d) * 1.2;
		float m = (1.0 - smoothstep(-aa, aa, d)) * decal_color.a;
		col = mix(col, decal_color.rgb * (0.85 + 0.15 * toon), m);
	}

	col = col * (1.0 - dim * 0.6) + base * emission_energy + glow * (1.0 - dim);
	ALBEDO = col;
}
