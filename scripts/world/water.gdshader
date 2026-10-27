shader_type spatial;
render_mode cull_disabled, depth_draw_always;
// Stream and pond surface.
// * reflections: the shader traces the reflected view ray through the depth buffer (screen-space
//   reflection) so trees, houses and the bridge show in the water; misses fall back to the sky colour
// * refraction of the bed, tinted by water thickness (from the depth buffer)
// * foam where anything breaks the surface (banks, rocks, bridge posts), streaked along the flow
// * a custom light() for a sharp sun highlight and sparkling glints on the ripples

// mineral-rich alien water: milky turquoise shallows, deep teal
uniform vec3 shallow : source_color = vec3(0.50, 0.86, 0.82);
uniform vec3 deep : source_color = vec3(0.04, 0.26, 0.30);
uniform vec3 sky_tint : source_color = vec3(0.78, 0.66, 0.58);
global uniform float night;
uniform vec3 foam_color : source_color = vec3(0.93, 0.96, 0.94);
uniform float flow = 0.35;                       // 0 for the pond
uniform float ripple_strength = 0.18;
uniform float reflect_strength = 0.85;
uniform float foam_amount = 1.0;                 // the still pond foams less than the stream
uniform sampler2D ripples_a : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D ripples_b : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D foam_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float scene_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return v.z / v.w;                                   // view-space z (negative, in front of the camera)
}

void fragment() {
	// --- ripples: world-space normal, then into view space ---
	vec2 uva = wpos.xz * 0.22 + vec2(TIME * 0.015, TIME * 0.01);
	vec2 uvb = vec2(UV.x * 0.9, UV.y - TIME * flow * 0.35) + wpos.xz * 0.05;
	vec2 uvc = wpos.xz * 0.9 + vec2(-TIME * 0.05, TIME * 0.04);
	vec2 na = texture(ripples_a, uva).xy - 0.5;
	vec2 nb = texture(ripples_b, uvb).xy - 0.5;
	vec2 nc = texture(ripples_b, uvc).xy - 0.5;
	vec2 slope = (na + nb) * ripple_strength + nc * ripple_strength * 0.6;
	vec3 nw = normalize(vec3(slope.x, 1.0, slope.y));
	vec3 n = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	NORMAL = n;

	// --- water thickness behind this pixel ---
	float scene_z = scene_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float thick = max(VERTEX.z - scene_z, 0.0);
	float t = clamp(thick / 0.75, 0.0, 1.0);

	// --- refraction ---
	vec2 off = slope * 0.06 * t;
	vec3 bed = texture(screen_tex, SCREEN_UV + off).rgb;
	vec3 refr = mix(bed * shallow, deep, smoothstep(0.0, 1.0, t) * 0.92);

	// --- screen-space reflection ---
	vec3 refl = sky_tint;
	vec3 view_dir = normalize(VERTEX);
	vec3 r = normalize(reflect(view_dir, n));
	vec3 p = VERTEX;
	float step_len = 0.25;
	float hit = 0.0;
	vec2 hit_uv = vec2(0.0);
	for (int i = 0; i < 40; i++) {
		p += r * step_len;
		step_len *= 1.12;
		vec4 clip = PROJECTION_MATRIX * vec4(p, 1.0);
		if (clip.w <= 0.0) break;
		vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) break;
		float sz = scene_depth(uv, INV_PROJECTION_MATRIX);
		float diff = sz - p.z;                          // > 0: the ray went behind the scene surface
		if (diff > 0.0 && diff < step_len * 2.5 + 0.3) {
			// refine between the last two points
			vec3 a = p - r * step_len / 1.12; vec3 b = p;
			for (int k = 0; k < 5; k++) {
				vec3 m = (a + b) * 0.5;
				vec4 cm = PROJECTION_MATRIX * vec4(m, 1.0);
				vec2 um = cm.xy / cm.w * 0.5 + 0.5;
				if (scene_depth(um, INV_PROJECTION_MATRIX) - m.z > 0.0) b = m; else a = m;
			}
			vec4 cb = PROJECTION_MATRIX * vec4(b, 1.0);
			hit_uv = cb.xy / cb.w * 0.5 + 0.5;
			vec2 edge = smoothstep(vec2(0.0), vec2(0.08), hit_uv) * smoothstep(vec2(0.0), vec2(0.08), 1.0 - hit_uv);
			hit = edge.x * edge.y * (1.0 - float(i) / 40.0);
			break;
		}
	}
	if (hit > 0.0) refl = mix(sky_tint, texture(screen_tex, hit_uv).rgb, hit);
	float ndv = clamp(dot(n, -view_dir), 0.0, 1.0);
	float fres = 0.06 + 0.94 * pow(1.0 - ndv, 4.0);
	vec3 water = mix(refr, refl, clamp(fres * reflect_strength + hit * 0.12, 0.0, 1.0));

	// --- foam: where the surface meets anything, broken up by noise flowing downstream ---
	vec2 fuv = vec2(wpos.x * 0.6, wpos.z * 0.6);
	fuv += vec2(UV.x * 0.0, -TIME * flow * 0.6) * step(0.01, flow);
	float fn = texture(foam_noise, fuv).r;
	float fn2 = texture(foam_noise, fuv * 2.3 + vec2(TIME * 0.03, 0.0)).r;
	float contact = 1.0 - smoothstep(0.0, 0.15, thick);
	float foam = smoothstep(0.45, 0.85, contact * (0.35 + fn * 0.9));
	foam = max(foam, smoothstep(0.62, 0.8, fn * fn2 * 1.6) * contact * 0.5);
	foam = clamp(foam * foam_amount, 0.0, 1.0) * 0.85;

	ALBEDO = mix(deep * 0.15, foam_color, foam);
	EMISSION = water * (1.0 - foam) * (1.0 - 0.88 * night);
	ROUGHNESS = mix(0.05, 0.9, foam);
	ALPHA = 1.0;
}

void light() {
	float nl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += nl * ATTENUATION * LIGHT_COLOR / PI;
	vec3 h = normalize(VIEW + LIGHT);
	float nh = clamp(dot(NORMAL, h), 0.0, 1.0);
	// a soft sun highlight plus tiny sparkles where ripples catch the sun just right
	float spec = pow(nh, 220.0) * 1.2 + pow(nh, 1800.0) * 9.0;
	SPECULAR_LIGHT += spec * ATTENUATION * LIGHT_COLOR * (1.0 - ROUGHNESS);
}
