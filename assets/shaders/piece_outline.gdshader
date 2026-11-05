shader_type spatial;
render_mode unshaded, cull_front;
// Tegnet kant rundt brikken til cel-shading, tegneserie og skisse (runde 19). Brukes som neste pass
// (next_pass) etter brikke-shaderen: brikken tegnes litt større, bare baksiden, så bare kanten stikker ut.
// Brikken forstørres fra midten (ikke langs normalene), så kanten ikke sprekker ved de skarpe kantene.

uniform vec4 outline_color : source_color = vec4(0.06, 0.06, 0.08, 1.0);
uniform float grow = 0.07;   // hvor mye større (0,07 = 7 %)

// piece.obj: høyde 0..0.126
const vec3 CENTER = vec3(0.0, 0.063, 0.0);

void vertex() {
	VERTEX = CENTER + (VERTEX - CENTER) * (1.0 + grow);
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
