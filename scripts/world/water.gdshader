shader_type spatial;
render_mode cull_disabled, depth_draw_always, specular_schlick_ggx;
// Stream and pond surface: colour by water thickness (from the depth buffer), foam where it meets
// the shore, refraction of the bed, two scrolling ripple normal maps (flowing along the stream).

uniform vec3 shallow : source_color = vec3(0.55, 0.78, 0.70);
uniform vec3 deep : source_color = vec3(0.10, 0.32, 0.36);
uniform vec3 sky_tint : source_color = vec3(0.62, 0.76, 0.9);
uniform vec3 foam_color : source_color = vec3(0.92, 0.95, 0.92);
uniform float flow = 0.35;
uniform sampler2D ripples_a : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D ripples_b : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uva = wpos.xz * 0.22 + vec2(TIME * 0.015, TIME * 0.01);
	vec2 uvb = vec2(UV.x * 0.9, UV.y - TIME * flow * 0.35) + wpos.xz * 0.05;
	vec3 na = texture(ripples_a, uva).rgb;
	vec3 nb = texture(ripples_b, uvb).rgb;
	NORMAL_MAP = normalize(mix(na, nb, 0.5));
	NORMAL_MAP_DEPTH = 0.6;
	// water thickness behind this pixel
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -v.z / v.w;
	float thick = max(scene_z - (-VERTEX.z), 0.0);
	float t = clamp(thick / 1.4, 0.0, 1.0);
	vec2 off = (NORMAL_MAP.xy - 0.5) * 0.03 * t;
	vec3 bed = texture(screen_tex, SCREEN_UV + off).rgb;
	vec3 col = mix(bed * shallow * 1.25, deep, smoothstep(0.0, 1.0, t) * 0.85);
	// a soft sky reflection at grazing angles
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, sky_tint, fres * 0.55 + 0.08);
	float foam = (1.0 - smoothstep(0.0, 0.14, thick)) * (0.6 + 0.4 * sin(TIME * 1.7 + wpos.x * 3.0 + wpos.z * 2.0));
	ALBEDO = mix(col, foam_color, clamp(foam, 0.0, 1.0) * 0.7);
	ROUGHNESS = 0.06;
	SPECULAR = 0.55;
	ALPHA = mix(0.88, 0.97, t);
}
