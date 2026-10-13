shader_type spatial;
render_mode cull_disabled;
// Wheat swaying in the wind. Vertex colour (x instance colour) is the albedo;
// the sway grows with height so the stalk bases stay planted.

uniform float wind_strength = 0.07;
uniform float wind_speed = 1.2;
uniform vec2 wind_dir = vec2(1.0, 0.35);

varying vec3 tint;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y, 0.0);
	float k = h * h * 2.6;
	// a slow travelling gust plus a faster flutter, phase-shifted by position
	float gust = sin(TIME * wind_speed + dot(origin.xz, wind_dir) * 0.55) * 0.65
		+ sin(TIME * wind_speed * 2.7 + origin.x * 3.1 + origin.z * 1.7) * 0.25;
	vec3 wdir = normalize(vec3(wind_dir.x, 0.0, wind_dir.y));
	// wind_dir is in world space; bring it into the instance's local space
	vec3 local_dir = normalize((inverse(MODEL_MATRIX) * vec4(wdir, 0.0)).xyz);
	VERTEX += local_dir * gust * wind_strength * k;
	VERTEX.y -= abs(gust) * wind_strength * k * 0.25;
	tint = COLOR.rgb;
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.85;
}
