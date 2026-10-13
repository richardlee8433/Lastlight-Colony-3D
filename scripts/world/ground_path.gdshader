shader_type spatial;
// Ground with organic, foot-worn paths. Wear comes from PathWear (0 = grass, 1 = bare dirt).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D wear_tex : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 wear_rect;                                   // x0, z0, size_x, size_z (world)
uniform vec3 dirt_light : source_color = vec3(0.56, 0.45, 0.31);
uniform vec3 dirt_dark : source_color = vec3(0.38, 0.29, 0.19);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
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
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
