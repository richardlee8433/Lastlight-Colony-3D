shader_type spatial;
render_mode cull_disabled;
// Grass tufts: dark at the root, light at the tips, gently moving in the wind.
// Instance colour (from Meadow) sets the hue so tufts blend with the ground patches.

uniform float wind_strength = 0.035;
uniform float wind_speed = 1.4;
uniform vec2 wind_dir = vec2(1.0, 0.35);
uniform float tuft_height = 0.32;

varying vec3 tint;
varying float hgt;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	hgt = clamp(VERTEX.y / tuft_height, 0.0, 1.0);
	float gust = sin(TIME * wind_speed + dot(origin.xz, wind_dir) * 0.55) * 0.7
		+ sin(TIME * wind_speed * 3.1 + origin.x * 4.0 + origin.z * 2.3) * 0.3;
	vec3 local_dir = normalize((inverse(MODEL_MATRIX) * vec4(normalize(vec3(wind_dir.x, 0.0, wind_dir.y)), 0.0)).xyz);
	VERTEX += local_dir * gust * wind_strength * hgt * hgt * 3.0;
	tint = COLOR.rgb;
}

void fragment() {
	vec3 col = tint * mix(0.8, 1.3, hgt);
	// sun-bleached tips
	col = mix(col, col * vec3(1.08, 1.0, 1.12), smoothstep(0.75, 1.0, hgt) * 0.5);   // pale lilac tips
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
