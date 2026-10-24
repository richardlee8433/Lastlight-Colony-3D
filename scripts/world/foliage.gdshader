shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, shadows_disabled;
// Tree crowns made of leaf cards: alpha-scissored leaf texture, crown-shaped normals from the model,
// whole-tree sway plus a small per-card flutter, and a per-tree tint (instance uniform for single
// trees; MultiMesh instance colours arrive through COLOR for the border forest).

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float alpha_cut = 0.5;
uniform float wind_strength = 0.14;
uniform float wind_speed = 0.9;
uniform vec2 wind_dir = vec2(1.0, 0.35);
uniform vec3 backlight : source_color = vec3(0.22, 0.24, 0.26);
instance uniform vec4 tint : source_color = vec4(1.0);

varying vec3 vcol;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(wp.y - origin.y, 0.0);
	float k = pow(h / 6.0, 1.5);
	float gust = sin(TIME * wind_speed + dot(origin.xz, wind_dir) * 0.3) * 0.7
		+ sin(TIME * wind_speed * 2.3 + wp.x * 1.3 + wp.z * 0.9) * 0.3;
	vec3 wdir = normalize(vec3(wind_dir.x, 0.0, wind_dir.y));
	float flutter = sin(TIME * 3.1 + wp.x * 4.0 + wp.y * 3.0 + wp.z * 5.0) * 0.035 * k;
	vec3 disp = wdir * gust * wind_strength * k + vec3(0.0, flutter, 0.0);
	VERTEX += (inverse(MODEL_MATRIX) * vec4(disp, 0.0)).xyz;
	vcol = COLOR.rgb * tint.rgb;
}

void fragment() {
	vec4 t = texture(leaf_tex, UV);
	// keep cards solid at a distance: smaller mip levels average the alpha down, so boost it with the level
	vec2 px = UV * vec2(textureSize(leaf_tex, 0));
	float lod = max(0.0, 0.5 * log2(max(dot(dFdx(px), dFdx(px)), dot(dFdy(px), dFdy(px)))));
	ALBEDO = t.rgb * vcol;
	ALPHA = clamp(t.a * (1.0 + lod * 0.35), 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.85;
	BACKLIGHT = backlight * vcol;
}
