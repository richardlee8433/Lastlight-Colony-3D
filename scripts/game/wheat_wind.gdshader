shader_type spatial;
render_mode cull_disabled;
// Wheat swaying in the wind. Vertex colour (x instance colour) is the albedo;
// the sway grows with height so the stalk bases stay planted.

uniform float wind_strength = 0.07;
uniform float wind_speed = 1.2;
uniform vec2 wind_dir = vec2(1.0, 0.35);
// crop growth 0..1: young plants are short and green, ripen to the vertex colours (gold) near 1
uniform float growth = 1.0;
uniform vec3 young_color : source_color = vec3(0.30, 0.52, 0.16);

varying vec3 tint;

void vertex() {
	float height = mix(0.18, 1.0, smoothstep(0.08, 0.7, growth));
	VERTEX.y *= height;
	VERTEX.xz *= mix(0.55, 1.0, smoothstep(0.08, 0.5, growth));
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
	float ripe = smoothstep(0.62, 0.97, growth);
	float shade = 0.75 + 0.35 * clamp(VERTEX.y / max(height, 0.01), 0.0, 1.0);
	tint = mix(young_color * shade, COLOR.rgb, ripe);
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.85;
}
