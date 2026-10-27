shader_type sky;
// Alien sky for a thin atmosphere: dusty butterscotch horizon, deep slate zenith, a few stars
// that show through even by day, a sharp small sun, and a banded gas giant with a ring.

uniform vec3 zenith : source_color = vec3(0.025, 0.035, 0.08);
uniform vec3 horizon : source_color = vec3(0.74, 0.56, 0.44);
uniform vec3 ground_col : source_color = vec3(0.22, 0.16, 0.13);
uniform vec3 sun_col : source_color = vec3(1.0, 0.96, 0.9);
uniform vec3 planet_dir = vec3(-0.55, 0.26, -0.75);
uniform float planet_size = 0.13;           // angular radius-ish (cos-space)
uniform vec3 planet_a : source_color = vec3(0.78, 0.62, 0.48);
uniform vec3 planet_b : source_color = vec3(0.55, 0.38, 0.32);
uniform vec3 planet_c : source_color = vec3(0.86, 0.80, 0.70);

float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}
float fbm2(vec2 p) {
	float s = 0.0; float a = 0.5;
	for (int i = 0; i < 6; i++) { s += a * n2(p); p = p * 2.02 + vec2(1.7, 9.2); a *= 0.5; }
	return s;
}
uniform float day = 1.0;              // set by DayNight: 1 = day, 0 = night
uniform float cloud_cover = 0.52;      // 0 = clear, 1 = overcast
uniform vec2 cloud_wind = vec2(0.004, 0.0015);

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = d.y;
	// gradient: wide dusty band near the horizon
	vec3 col = mix(horizon, zenith, pow(smoothstep(-0.02, 0.6, up), 0.6));   // thin air: the dust hugs the horizon
	col = mix(col, ground_col, smoothstep(0.0, -0.25, up));
	col *= mix(vec3(0.03, 0.04, 0.08), vec3(1.0), day);                // night sky
	// haze brightens around the sun
	vec3 sd = LIGHT0_DIRECTION;
	float sdot = max(dot(d, sd), 0.0);
	col += sun_col * (pow(sdot, 8.0) * 0.25 + pow(sdot, 64.0) * 0.4) * LIGHT0_ENERGY * 0.4 * day;
	// stars, faint near the horizon and in the sun's glare
	vec3 sp = floor(d * 280.0);
	float st = step(0.9955, hash(sp)) * smoothstep(0.04, 0.35, up) * (1.0 - pow(sdot, 3.0));
	col += vec3(st) * (0.5 + 0.5 * hash(sp + 3.0)) * (1.0 + 1.6 * (1.0 - day));
	// gas giant: a lit disc with bands, terminator shading and a thin ring
	vec3 pd = normalize(planet_dir);
	float pc = dot(d, pd);
	float disc = 1.0 - planet_size * 0.1;           // cos of the angular radius
	vec3 right = normalize(cross(pd, vec3(0.0, 1.0, 0.0)));
	vec3 pup = normalize(cross(right, pd));
	vec2 pl = vec2(dot(d, right), dot(d, pup)) / sqrt(1.0 - disc * disc);   // -1..1 across the disc
	// tilted ring (an ellipse around the disc)
	vec2 rl = vec2(pl.x * cos(0.35) - pl.y * sin(0.35), pl.x * sin(0.35) + pl.y * cos(0.35));
	float rr = length(vec2(rl.x, rl.y * 4.2));
	float ring = smoothstep(1.55, 1.6, rr) * (1.0 - smoothstep(1.95, 2.05, rr)) * (0.6 + 0.4 * sin(rr * 40.0));
	if (pc > disc) {
		float lat = pl.y * 0.9 + pl.x * 0.12;
		float bands = sin(lat * 11.0) * 0.5 + sin(lat * 27.0 + 1.3) * 0.25 + sin(lat * 5.0 - 0.6) * 0.25;
		vec3 pcol = mix(planet_b, planet_a, smoothstep(-0.6, 0.6, bands));
		pcol = mix(pcol, planet_c, smoothstep(0.7, 0.95, sin(lat * 7.0 + 2.0)) * 0.6);
		// lit from the sun's side; limb darkening
		vec3 n = normalize(-pd * sqrt(max(0.0, 1.0 - dot(pl, pl))) + right * pl.x + pup * pl.y);
		float lit = clamp(dot(n, sd) * 0.55 + 0.7, 0.25, 1.2);
		float limb = sqrt(max(0.0, 1.0 - dot(pl, pl)));
		pcol *= lit * (0.55 + 0.45 * limb) * mix(0.35, 1.0, day);
		// the near half of the ring passes in front of the planet
		if (rl.y < 0.0) pcol = mix(pcol, vec3(0.85, 0.78, 0.68) * 0.9, ring * 0.8);
		// soak into the haze a little
		col = mix(col, pcol, smoothstep(disc, disc + 0.002, pc) * mix(0.55, 0.85, smoothstep(0.1, 0.5, up)));   // seen through the dust
	} else {
		col = mix(col, vec3(0.85, 0.78, 0.68), ring * 0.55 * smoothstep(disc - 0.05, disc, pc + 0.04));
	}
	// a small cratered moon on the other side of the sky
	vec3 md = normalize(vec3(0.62, 0.42, 0.45));
	float mc = dot(d, md);
	float mdisc = 0.99935;
	if (mc > mdisc) {
		vec3 mr = normalize(cross(md, vec3(0.0, 1.0, 0.0))); vec3 mu = normalize(cross(mr, md));
		vec2 ml = vec2(dot(d, mr), dot(d, mu)) / sqrt(1.0 - mdisc * mdisc);
		vec3 mn = normalize(-md * sqrt(max(0.0, 1.0 - dot(ml, ml))) + mr * ml.x + mu * ml.y);
		float crater = hash(floor(vec3(ml * 5.0, 1.0))) * 0.25;
		vec3 mcol = vec3(0.62, 0.60, 0.58) * (0.85 - crater) * clamp(dot(mn, sd) * 0.9 + 0.2, 0.06, 1.0);
		col = mix(col, mcol, smoothstep(mdisc, mdisc + 0.00008, mc));
	}
	// thin high clouds (cirrus-like streaks and a few denser banks), lit by the sun from behind
	if (up > 0.0) {
		vec2 cuv = d.xz / (up + 0.12) * 0.9 + TIME * cloud_wind;
		vec2 warp = vec2(fbm2(cuv * 0.6), fbm2(cuv * 0.6 + 5.3)) - 0.5;
		vec2 suv = (cuv + warp * 1.2) * vec2(1.0, 2.6);                     // stretched into streaks
		float dens = fbm2(suv * 1.3);
		float c = smoothstep(cloud_cover, cloud_cover + 0.28, dens);
		c *= smoothstep(0.0, 0.12, up) * (1.0 - smoothstep(0.65, 0.95, up) * 0.6);
		// light: brighter edges towards the sun, warm rim, cool shadowed bellies
		float dens2 = fbm2(suv * 1.3 + sd.xz * 0.15);
		float lit = clamp(0.55 + (dens - dens2) * 6.0, 0.0, 1.0);
		vec3 shade = mix(vec3(0.42, 0.32, 0.34), vec3(1.0, 0.86, 0.72), lit);
		shade += sun_col * pow(sdot, 6.0) * 0.6;                              // silver lining near the sun
		shade *= mix(0.55, 1.0, smoothstep(0.0, 0.35, up));                   // dimmer towards the dusty horizon
		shade *= mix(vec3(0.05, 0.06, 0.1), vec3(1.0), day);
		col = mix(col, shade * (0.6 + 0.4 * LIGHT0_ENERGY / 2.5), c * 0.85);
	}
	// sun disc
	col = mix(col, sun_col * 6.0, smoothstep(0.9993, 0.9997, sdot) * day);
	COLOR = col;
}
