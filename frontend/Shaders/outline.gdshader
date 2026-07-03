shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never;

uniform float width = 0.03;
uniform vec4 outline_color : source_color = vec4(0,0,0,1);

void vertex() { VERTEX += NORMAL * width; }
void fragment() { ALBEDO = outline_color.rgb; ALPHA = 1.0; }
