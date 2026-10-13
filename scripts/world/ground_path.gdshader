shader_type spatial;
// Ground with organic, foot-worn paths. Wear comes from PathWear (0 = grass, 1 = bare dirt).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D wear_tex : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 wear_rect;                                   // x0, z0, size_x, size_z (world)
uniform sampler2D meadow_tex : filter_linear, repeat_disable;   // Meadow lushness 0 dry .. 1 lush
uniform vec4 meadow_rect;
uniform vec3 grass_dry : source_color = vec3(0.56, 0.56, 0.22);
uniform vec3 grass_mid : source_color = vec3(0.31, 0.50, 0.13);
uniform vec3 grass_lush : source_color = vec3(0.17, 0.38, 0.08);
uniform sampler2D zone_tex : filter_linear, repeat_disable;    // residential zones (1 = zoned)
uniform vec4 zone_rect;
uniform float zone_strength = 0.45;
uniform vec3 zone_color : source_color = vec3(0.98, 0.88, 0.55);
uniform vec3 dirt_light : source_color = vec3(0.56, 0.45, 0.31);
uniform vec3 dirt_dark : source_color = vec3(0.38, 0.29, 0.19);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
