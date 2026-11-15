// THE TERRAIN SKIN SHADER (the spike round's splat law):
// five tileable texture skins blended by the mesh's per-vertex
// splat weights -- COLOR = (grass, dirt, rock, sand), UV2 = (snow, bright).
// The weights derive from the SAME law the vertex colors read
// (TerrainGen.splat_skin: climate weights, slope rock, snowline, wet
// dim) -- the shader only samples, it never re-decides a biome.
// The planar world position (not the wrapped per-chunk UV) reads the
// tiles so chunk seams stay invisible and the web round-12 UV law
// stays untouched.
// License note: textures are original procedural spike stand-ins;
// Quixel scans slot into these five slots when claimed.
shader_type spatial;

uniform sampler2D tex_grass : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_dirt : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rock : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_sand : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_snow : source_color, filter_linear_mipmap, repeat_enable;
// Meters per texture tile at ground level.
uniform float u_tile_meters : hint_range(0.5, 64.0) = 6.0;
// Cliff ambience: how much the side projection blends in on steep
// faces (the rock layer reads triplanar, the soft layers stay top).
uniform float u_cliff_mix : hint_range(0.0, 1.0) = 0.65;

varying vec3 v_world_pos;
// Model-space up-ness (1.0 - normal.y): computed in the vertex stage,
// because the fragment-stage NORMAL is view-space and a view-dependent
// cliff factor would wobble with the camera.
varying float v_steep;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_steep = clamp(1.0 - NORMAL.y, 0.0, 1.0);
}

vec4 _tri(sampler2D tex, vec3 pos, float oxy) {
	vec2 top = pos.xz / u_tile_meters;
	vec2 side = mix(pos.xy, pos.yz, step(pos.z, pos.y)) / u_tile_meters;
	return mix(texture(tex, top), texture(tex, side), clamp(oxy, 0.0, 1.0));
}

void fragment() {
	// THE SPLAT CHANNELS: COLOR = (grass, dirt, rock, sand) with sand
	// riding the ALPHA channel, so the weights read as a full vec4.
	vec4 w = COLOR;
	float wsum = max(w.r + w.g + w.b + w.a, 0.001);
	w /= wsum;
	vec3 pos = v_world_pos;
	// Steep faces read the side projection (cliff ambience); the rest
	// samples the top plane so grass mowing stripes stay lawful.
	float cliff = v_steep * u_cliff_mix;
	vec4 grass = mix(texture(tex_grass, pos.xz / u_tile_meters), texture(tex_grass, pos.xy / u_tile_meters), cliff);
	vec4 dirt = mix(texture(tex_dirt, pos.xz / u_tile_meters), texture(tex_dirt, pos.yz / u_tile_meters), cliff);
	vec4 sand = mix(texture(tex_sand, pos.xz / u_tile_meters), texture(tex_sand, pos.yz / u_tile_meters), cliff);
	vec4 snow = texture(tex_snow, pos.xz / (u_tile_meters * 2.0));
	vec4 rock = _tri(tex_rock, pos, cliff * 0.5);
	vec4 albedo = w.r * grass + w.g * dirt + w.b * rock + w.a * sand;
	// THE SNOW LAW RIDES: UV2.x is the vertex's snowline weight, same
	// factor the color law lerps toward the snow palette.
	albedo.rgb = mix(albedo.rgb, snow.rgb, clamp(UV2.x, 0.0, 1.0));
	// THE BRIGHT LAW RIDES: UV2.y carries every per-vertex dimming the
	// color law applies after the biome blend (wet dim, foam wash,
	// waterfall seam, bluff shading) as one faithful multiplier.
	albedo.rgb *= clamp(UV2.y, 0.05, 2.0);
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
