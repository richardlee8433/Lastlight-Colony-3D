shader_type spatial;
// Loose stones and boulders (Scatter): instance colour x layered noise, faint strata, rust dust settled
// on the upper faces, a pitted surface from a small normal perturbation.
varying vec3 vcol;
varying vec3 opos;
varying vec3 wn;
float h3(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float n3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void vertex() {
	vcol = pow(COLOR.rgb, vec3(2.2));      // instance colours are given in sRGB
	opos = VERTEX * 3.0 + vec3(float(INSTANCE_ID % 97), 0.0, float(INSTANCE_ID % 31));
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float n = n3(opos * 2.0) * 0.6 + n3(opos * 7.0) * 0.4;
	float strata = sin(opos.y * 9.0 + n * 3.0) * 0.5 + 0.5;
	vec3 c = vcol * (0.7 + 0.45 * n) * (0.9 + 0.15 * strata);
	c = mix(c, vec3(0.55, 0.38, 0.27), smoothstep(0.55, 0.95, wn.y) * 0.45 * smoothstep(0.4, 0.7, n3(opos * 3.3)));
	ALBEDO = c;
	ROUGHNESS = 0.9 - 0.15 * n;
	float e = 0.05;
	vec3 g = vec3(n3((opos + vec3(e, 0, 0)) * 7.0), n3((opos + vec3(0, e, 0)) * 7.0), n3((opos + vec3(0, 0, e)) * 7.0)) - n3(opos * 7.0);
	NORMAL = normalize(NORMAL - (VIEW_MATRIX * vec4(g / e * 0.04, 0.0)).xyz);
}
