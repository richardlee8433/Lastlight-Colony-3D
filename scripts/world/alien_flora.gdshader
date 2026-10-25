shader_type spatial;
render_mode cull_disabled;
// Alien flora (tools/flora.py): vertex colour x a per-plant tint (instance uniform for single plants;
// MultiMesh instance colours arrive through COLOR for the border flora), a slow sway, and pulsing
// emissive parts (spore bulbs, tube throats, rims) on the "flora_glow" surface.

uniform float wind_strength = 0.05;
uniform float wind_speed = 0.6;
uniform vec2 wind_dir = vec2(1.0, 0.35);
uniform float glow = 0.0;
uniform vec3 glow_color : source_color = vec3(0.55, 1.0, 0.92);
instance uniform vec4 tint : source_color = vec4(1.0);

varying vec3 vcol;
varying float phase;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(wp.y - origin.y, 0.0);
	float k = pow(h / 6.0, 1.6);
	float gust = sin(TIME * wind_speed + dot(origin.xz, wind_dir) * 0.3) * 0.7 + sin(TIME * wind_speed * 2.1 + wp.x * 0.9) * 0.3;
	vec3 wdir = normalize(vec3(wind_dir.x, 0.0, wind_dir.y));
	VERTEX += (inverse(MODEL_MATRIX) * vec4(wdir * gust * wind_strength * k, 0.0)).xyz;
	vcol = COLOR.rgb * tint.rgb;
	phase = origin.x * 0.7 + origin.z * 1.3;
}

void fragment() {
	ROUGHNESS = 0.55;
	SPECULAR = 0.4;
	if (glow > 0.0) {
		float pulse = 0.75 + 0.25 * sin(TIME * 1.6 + phase);
		vec3 g = mix(glow_color, vcol, 0.35);
		ALBEDO = g * 0.4;
		EMISSION = g * glow * pulse;
	} else {
		ALBEDO = vcol;
		BACKLIGHT = vcol * 0.2;
	}
}
