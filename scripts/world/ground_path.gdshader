shader_type spatial;
// Ground with organic, foot-worn paths. Wear comes from PathWear (0 = grass, 1 = bare dirt).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D wear_tex : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 wear_rect;                                   // x0, z0, size_x, size_z (world)
uniform sampler2D meadow_tex : filter_linear, repeat_disable;   // Meadow lushness 0 dry .. 1 lush
uniform vec4 meadow_rect;
// alien regolith: pale ochre dust, rust, dark violet-grey basalt
uniform vec3 grass_dry : source_color = vec3(0.68, 0.52, 0.38);
uniform vec3 grass_mid : source_color = vec3(0.56, 0.34, 0.24);
uniform vec3 grass_lush : source_color = vec3(0.30, 0.24, 0.27);
uniform sampler2D zone_tex : filter_linear, repeat_disable;    // residential zones (1 = zoned)
uniform vec4 zone_rect;
uniform float zone_strength = 0.45;
uniform vec3 zone_color : source_color = vec3(0.98, 0.88, 0.55);
uniform sampler2D field_tex : filter_linear, repeat_disable;   // farm fields (1 = field, 0.78 = other field while editing)
uniform sampler2D field_ang_tex : filter_nearest, repeat_disable;  // furrow direction (angle mod PI) / PI
uniform vec4 field_rect;
uniform float field_edit = 0.0;
uniform sampler2D forest_tex : filter_linear, repeat_disable;  // woodcutter forest areas (same grid as fields)
uniform float forest_strength = 0.35;
uniform vec3 forest_color : source_color = vec3(0.55, 0.92, 0.45);                          // 1 while painting a field
uniform vec3 soil_light : source_color = vec3(0.43, 0.31, 0.19);
uniform vec3 soil_dark : source_color = vec3(0.24, 0.16, 0.09);
uniform sampler2D water_tex : filter_linear, repeat_disable;   // Water carve: R = lowered (0..1), G = bank
uniform vec4 water_rect;
uniform float bed_depth = 0.0;
uniform vec3 mud : source_color = vec3(0.22, 0.19, 0.2);
uniform vec3 dirt_light : source_color = vec3(0.52, 0.46, 0.42);
uniform vec3 dirt_dark : source_color = vec3(0.32, 0.28, 0.27);

varying vec3 wpos;

float carve_at(vec2 xz) {
	return textureLod(water_tex, (xz - water_rect.xy) / water_rect.zw, 0.0).r;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (bed_depth > 0.0) {
		// stream bed and pond: the same profile lowers the walk-grid heights (Water.apply_to_nav)
		float c = carve_at(wpos.xz);
		VERTEX.y -= c * bed_depth;
		float e = 0.3;
		float hx = (carve_at(wpos.xz + vec2(e, 0.0)) - carve_at(wpos.xz - vec2(e, 0.0))) * -bed_depth / (2.0 * e);
		float hz = (carve_at(wpos.xz + vec2(0.0, e)) - carve_at(wpos.xz - vec2(0.0, e))) * -bed_depth / (2.0 * e);
		NORMAL = normalize(NORMAL + vec3(-hx, 0.0, -hz));
		wpos.y -= c * bed_depth;
	}
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	// recolour the baked grass with meadow patches (dirt in the bake is left alone)
	float lush = texture(meadow_tex, (wpos.xz - meadow_rect.xy) / meadow_rect.zw).r;
	vec3 target = lush < 0.5 ? mix(grass_dry, grass_mid, lush * 2.0) : mix(grass_mid, grass_lush, (lush - 0.5) * 2.0);
	float grassy = smoothstep(-0.01, 0.04, base.g - base.r);
	float lum = dot(base, vec3(0.3, 0.55, 0.15));
	vec3 recol = target * (0.6 + lum * 1.2);                 // keep the baked light/dark detail
	base = mix(base, recol, grassy * 0.9);
	// farm fields: tilled soil with furrows across the farmhouse direction
	vec2 fuv = (wpos.xz - field_rect.xy) / field_rect.zw;
	float fm = texture(field_tex, fuv).r;
	if (fm > 0.01) {
		float fn = texture(noise_tex, wpos.xz * 0.6).r;
		float soil = smoothstep(0.3, 0.6, fm + (fn - 0.5) * 0.25);
		float a = texture(field_ang_tex, fuv).r * PI;
		vec2 nrm = vec2(sin(a), cos(a));
		float sx = dot(wpos.xz, nrm) / 0.6;
		float ridge = 0.5 + 0.5 * cos(TAU * (sx - 0.5));
		vec3 scol = mix(soil_dark, soil_light, ridge * 0.75 + (fn - 0.5) * 0.4);
		base = mix(base, scol, soil);
		if (field_edit > 0.0) {
			float fe = smoothstep(0.15, 0.4, fm) * (1.0 - smoothstep(0.45, 0.75, fm));
			float mine = smoothstep(0.88, 0.97, fm);
			base = mix(base, vec3(1.0, 0.82, 0.4), fe * 0.7 + mine * 0.12);
		}
	}
	// stream banks: wet mud, darker towards the water
	if (bed_depth > 0.0) {
		vec2 wt = texture(water_tex, (wpos.xz - water_rect.xy) / water_rect.zw).rg;
		float mn = texture(noise_tex, wpos.xz * 0.7).r;
		base = mix(base, mud * (0.8 + 0.35 * mn), wt.g * 0.85);
		base *= 1.0 - 0.45 * smoothstep(0.35, 0.95, wt.r);
	}
	vec2 wuv = (wpos.xz - wear_rect.xy) / wear_rect.zw;
	float w = texture(wear_tex, wuv).r;
	float n1 = texture(noise_tex, wpos.xz * 0.11).r;      // large wobble of the path edge
	float n2 = texture(noise_tex, wpos.xz * 0.9).r;       // small grit
	float edge = w + (n1 - 0.5) * 0.30 + (n2 - 0.5) * 0.12;
	float dirt = smoothstep(0.24, 0.48, edge);
	vec3 dcol = mix(dirt_dark, dirt_light, smoothstep(0.3, 0.75, n2) * 0.8 + w * 0.2);
	// a trodden, slightly darker band where grass is being worn away
	float rim = smoothstep(0.10, 0.24, edge) * (1.0 - dirt);
	vec3 col = mix(base, base * vec3(0.78, 0.74, 0.62), rim * 0.7);
	col = mix(col, dcol, dirt);
	// residential zones: soft warm fill with a brighter outline
	if (zone_strength > 0.0) {
		float z = texture(zone_tex, (wpos.xz - zone_rect.xy) / zone_rect.zw).r;
		float edge = smoothstep(0.15, 0.45, z) * (1.0 - smoothstep(0.55, 0.85, z));
		col = mix(col, zone_color, (z * 0.16 + edge * 0.55) * zone_strength);
	}
	// woodcutter forest areas: outline (stronger while painting)
	float fa = texture(forest_tex, (wpos.xz - field_rect.xy) / field_rect.zw).r;
	if (fa > 0.01) {
		float fedge = smoothstep(0.08, 0.35, fa) * (1.0 - smoothstep(0.5, 0.82, fa));
		float mine = smoothstep(0.88, 0.97, fa);
		float e = forest_strength;            // 0.35 normally, 1 while painting
		col = mix(col, forest_color, clamp(fedge * (0.2 + 0.7 * e) + mine * 0.25 * e * e, 0.0, 0.9));
	}
	// --- regolith detail (realism pass): drifts of pale dust, dark basalt grit, scattered pebbles,
	// and a small-scale height field that roughens the lighting ---
	float big = texture(noise_tex, wpos.xz * 0.035).r;
	float mid = texture(noise_tex, wpos.xz * 0.27 + vec2(3.1, 7.7)).r;
	float fine = texture(noise_tex, wpos.xz * 2.3).r;
	float grit = texture(noise_tex, wpos.xz * 7.9 + vec2(1.3, 0.4)).r;
	float drift = smoothstep(0.55, 0.8, big * 0.7 + mid * 0.3);
	float basalt = smoothstep(0.62, 0.85, 1.0 - (big * 0.5 + mid * 0.5));
	float ground_only = (1.0 - dirt) * (1.0 - smoothstep(0.05, 0.3, texture(field_tex, fuv).r));
	col = mix(col, col * vec3(1.18, 1.12, 1.05) + vec3(0.04, 0.03, 0.02), drift * 0.55 * ground_only);
	col = mix(col, col * vec3(0.55, 0.52, 0.55), basalt * 0.6 * ground_only);
	col *= 0.86 + 0.28 * fine;
	float pebble = smoothstep(0.78, 0.86, grit);
	col = mix(col, col * (0.45 + 0.9 * step(0.5, fract(grit * 37.0))), pebble * 0.55);
	ALBEDO = col;
	ROUGHNESS = 0.97 - drift * 0.05;
	// height-field normal from the noise (finite differences)
	float e = 0.06;
	float h0 = texture(noise_tex, wpos.xz * 2.3).r * 0.6 + texture(noise_tex, wpos.xz * 7.9 + vec2(1.3, 0.4)).r * 0.4;
	float hx = texture(noise_tex, (wpos.xz + vec2(e, 0.0)) * 2.3).r * 0.6 + texture(noise_tex, (wpos.xz + vec2(e, 0.0)) * 7.9 + vec2(1.3, 0.4)).r * 0.4;
	float hz = texture(noise_tex, (wpos.xz + vec2(0.0, e)) * 2.3).r * 0.6 + texture(noise_tex, (wpos.xz + vec2(0.0, e)) * 7.9 + vec2(1.3, 0.4)).r * 0.4;
	vec3 dn = vec3(-(hx - h0) / e, 0.0, -(hz - h0) / e) * 0.035;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(dn, 0.0)).xyz);
}
