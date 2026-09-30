// interior_sky.gdshader -- the Deep Root's firmament (S15.1,
// labs/prd-underworld.md sec 1). The underworld's sky is the INNER
// WALL of the world above: strata glow, root veins, the deep dark.
// Rendered on an inverted dome (cull_front) around the globe.
//
// The glow tide is a FUNCTION of the Concord epoch (the one-clock
// law): the material's emission_strength is driven per frame by
// globe_underworld.gd, which evaluates the same closed form the
// ferry schedule and the Moon Gate read. No second clock, ever.
//
// Params:
//   deep_color   - the base darkness of the inner wall
//   strata_color - the warm mineral glow banding the wall
//   vein_color   - the root veins that crawl the strata
//   strata_scale - how tightly the strata band (height on the dome)
//   vein_scale   - vein crawl density (angular noise)
//   tide_phase   - glow_tide(t) phase input (globe feeds it)
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_front, diffuse_burley, specular_disabled;

uniform vec3 deep_color : source_color = vec3(0.015, 0.02, 0.03);
uniform vec3 strata_color : source_color = vec3(0.85, 0.45, 0.2);
uniform vec3 vein_color : source_color = vec3(0.4, 0.75, 0.5);
uniform float strata_scale : hint_range(1.0, 40.0) = 9.0;
uniform float vein_scale : hint_range(1.0, 40.0) = 14.0;
uniform float tide_phase : hint_range(0.0, 1.0) = 0.0;

// Cheap value noise: hash the lattice, fade the corners. The veins
// do not need beauty; they need determinism and cheapness (web).
float vhash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = vhash(i);
	float b = vhash(i + vec3(1.0, 0.0, 0.0));
	float c = vhash(i + vec3(0.0, 1.0, 0.0));
	float d = vhash(i + vec3(1.0, 1.0, 0.0));
	float e = vhash(i + vec3(0.0, 0.0, 1.0));
	float g = vhash(i + vec3(1.0, 0.0, 1.0));
	float h = vhash(i + vec3(0.0, 1.0, 1.0));
	float k = vhash(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(a, b, u.x), mix(c, d, u.x), u.y),
			mix(mix(e, g, u.x), mix(h, k, u.x), u.y), u.z);
}

void fragment() {
	// Dome-space direction: the wall of a sphere. Strata band by
	// elevation (like sediment rings seen from inside), veins crawl
	// by angular position.
	vec3 dir = normalize(NORMAL);
	float band = abs(fract(dir.y * strata_scale + tide_phase * 0.35) - 0.5) * 2.0;
	float band_glow = smoothstep(0.55, 1.0, band);

	float vein_n = vnoise(dir * vein_scale);
	float vein_glow = smoothstep(0.62, 0.95, vein_n) * (0.6 + 0.4 * sin(tide_phase * 6.2831853 + dir.x * 4.0));

	float pulse = 0.75 + 0.25 * sin(tide_phase * 6.2831853);

	vec3 col = deep_color;
	col += strata_color * band_glow * pulse;
	col += vein_color * vein_glow * pulse;

	ALBEDO = col;
	EMISSION = col * max(band_glow * 0.8, vein_glow * 0.5) * pulse;
}
