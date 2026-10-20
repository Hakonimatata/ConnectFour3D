shader_type canvas_item;
// Rolig bakgrunnsgradient: lysere oppe, mørkere nede, en svak lysflekk i midten
// og litt støy (dithering) så gradienten ikke får synlige striper.

uniform vec4 top_color : source_color = vec4(0.11, 0.125, 0.16, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.05, 0.06, 0.075, 1.0);
uniform vec4 glow_color : source_color = vec4(0.165, 0.185, 0.23, 1.0);
uniform vec2 glow_center = vec2(0.55, 0.42);
uniform float glow_strength = 0.6;

void fragment() {
	vec3 c = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.0, 1.0, UV.y));
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 d = (UV - glow_center) * vec2(1.0, aspect);
	float g = 1.0 - smoothstep(0.0, 0.85, length(d));
	c = mix(c, glow_color.rgb, g * glow_strength);
	float n = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	c += (n - 0.5) / 255.0;
	COLOR = vec4(c, 1.0);
}
