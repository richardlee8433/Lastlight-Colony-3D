shader_type spatial;
// Scenery baked with Earth colours (bushes, mossy rocks): green turns into alien violet / teal,
// varied by position so neighbouring bushes differ. Other colours pass through.
varying vec3 vcol;
varying vec3 wpos;
void vertex() {
	vcol = COLOR.rgb;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 c = vcol;
	float other = max(max(c.r, c.b), 0.0005);
	float green = clamp((c.g / other - 1.12) * 2.5, 0.0, 1.0);
	float v = max(c.g, max(c.r, c.b)) * 1.5;
	float pick = 0.5 + 0.5 * sin(wpos.x * 0.37 + wpos.z * 0.29) * sin(wpos.z * 0.21 - wpos.x * 0.13);
	vec3 violet = vec3(0.70, 0.46, 0.86) * v;
	vec3 teal = vec3(0.36, 0.76, 0.72) * v;
	vec3 alien = mix(violet, teal, smoothstep(0.35, 0.65, pick));
	ALBEDO = mix(c, alien, green);
	ROUGHNESS = 0.85;
}
