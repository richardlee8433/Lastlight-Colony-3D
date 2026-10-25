shader_type spatial;
// Scenery baked with Earth colours (bushes, mossy rocks). On barren Lastlight the bush clumps read as
// dark basalt boulders dusted with rust, and moss on the rocks becomes faint lilac / teal lichen.
// Other colours (grey rock) pass through, a little darker and redder.
varying vec3 vcol;
varying vec3 wpos;
varying vec3 lpos;
void vertex() {
	vcol = COLOR.rgb;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lpos = VERTEX;
}
float hash(vec3 p) { return fract(sin(dot(floor(p), vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
void fragment() {
	vec3 c = vcol;
	float other = max(max(c.r, c.b), 0.0005);
	float green = clamp((c.g / other - 1.12) * 2.5, 0.0, 1.0);
	float v = max(c.g, max(c.r, c.b));
	// boulder: dark basalt, rust dust settled on top
	float n = hash(wpos * 3.1) * 0.5 + hash(wpos * 7.3) * 0.5;
	vec3 basalt = mix(vec3(0.13, 0.11, 0.12), vec3(0.24, 0.19, 0.19), n);
	vec3 rust = vec3(0.46, 0.27, 0.17);
	vec3 rock = mix(basalt, rust, smoothstep(0.55, 0.85, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y) * 0.7);
	// sparse lichen speckles
	float pick = 0.5 + 0.5 * sin(wpos.x * 0.37 + wpos.z * 0.29) * sin(wpos.z * 0.21 - wpos.x * 0.13);
	vec3 lichen = mix(vec3(0.52, 0.40, 0.62), vec3(0.32, 0.58, 0.56), smoothstep(0.35, 0.65, pick));
	rock = mix(rock, lichen * (0.6 + v), step(0.93, hash(wpos * 11.0)) * 0.8);
	vec3 plain = c * vec3(0.92, 0.84, 0.84);
	ALBEDO = mix(plain, rock, green);
	ROUGHNESS = 0.9;
}
