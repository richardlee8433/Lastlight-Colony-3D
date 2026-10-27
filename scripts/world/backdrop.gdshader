shader_type spatial;
render_mode cull_disabled;
// The land beyond the colony: regolith in the same palette as the ground, layered strata on steep slopes,
// dark basalt caps on the mesas, pale dust settled in the hollows, fine noise so it holds up up close.

uniform vec3 dust : source_color = vec3(0.68, 0.52, 0.38);
uniform vec3 rust : source_color = vec3(0.56, 0.34, 0.24);
uniform vec3 basalt : source_color = vec3(0.24, 0.20, 0.21);
uniform vec3 pale : source_color = vec3(0.80, 0.66, 0.52);

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { s += a * vnoise(p); p *= 2.03; a *= 0.5; }
	return s;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (!FRONT_FACING) NORMAL = -NORMAL;
	float slope = 1.0 - clamp(abs(wnrm.y), 0.0, 1.0);
	float n = fbm(wpos.xz * 0.06);
	float fine = fbm(wpos.xz * 0.9);
	vec3 col = mix(rust, dust, smoothstep(0.35, 0.7, n));
	// strata: horizontal bands on the steep faces, wavering a little
	float band = sin((wpos.y + (n - 0.5) * 2.0) * 2.4) * 0.5 + 0.5;
	float band2 = sin((wpos.y + fine * 0.6) * 9.0) * 0.5 + 0.5;
	vec3 strata = mix(basalt, rust * 0.9, band) * (0.85 + 0.3 * band2);
	col = mix(col, strata, smoothstep(0.35, 0.65, slope));
	// dark caprock on the high ground, pale dust drifts in the low hollows
	col = mix(col, basalt * 1.2, smoothstep(11.0, 16.0, wpos.y) * (1.0 - slope) * 0.7);
	col = mix(col, pale, smoothstep(2.0, 0.0, wpos.y) * smoothstep(0.4, 0.8, n) * 0.4);
	col *= 0.82 + 0.3 * fine;
	ALBEDO = col;
	ROUGHNESS = 0.96;
	// break up the lighting with a little fine relief
	vec2 e = vec2(0.15, 0.0);
	float h0 = fbm(wpos.xz * 1.6);
	vec3 dn = vec3(fbm((wpos.xz + e.xy) * 1.6) - h0, 0.0, fbm((wpos.xz + e.yx) * 1.6) - h0) / e.x * -0.08;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(dn, 0.0)).xyz);
}
