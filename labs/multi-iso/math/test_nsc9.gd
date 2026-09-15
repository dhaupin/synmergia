## Tests for NSC-9 encoding
extends SceneTree

func _init() -> void:
	var ok = true
	if not _test_encode_decode_int():
		push_error("FAIL: encode_decode_int")
		ok = false
	if not _test_axis_reservation():
		push_error("FAIL: axis_reservation")
		ok = false
	if not _test_spatial_faction_social():
		push_error("FAIL: spatial_faction_social")
		ok = false
	if not _test_projection():
		push_error("FAIL: projection")
		ok = false
	if not _test_cell_key():
		push_error("FAIL: cell_key")
		ok = false
	if not _test_deterministic_seq():
		push_error("FAIL: deterministic_seq")
		ok = false
	if not _test_year_encoding():
		push_error("FAIL: year_encoding")
		ok = false
	quit(0 if ok else 1)

func _test_encode_decode_int() -> bool:
	var nsc9 = Nsc9.new()
	var code = nsc9.encode_int(7, 42, 123456)
	var parsed = nsc9.decode_int(code)
	assert(parsed["prefix"] == 9)
	assert(parsed["facility"] == 7)
	assert(parsed["axis"] == 42)
	assert(parsed["sequence"] == 123456)
	return true

func _test_axis_reservation() -> bool:
	var nsc9 = Nsc9.new()
	assert(nsc9.spatial_axis(0) == 1)
	assert(nsc9.spatial_axis(11) == 12)
	assert(nsc9.faction_axis(0) == 100)
	assert(nsc9.faction_axis(99) == 199)
	assert(nsc9.social_axis(0) == 300)
	assert(nsc9.social_axis(99) == 399)
	assert(nsc9.game_axis(0) == 400)
	assert(nsc9.game_axis(99) == 499)
	return true

func _test_spatial_faction_social() -> bool:
	var nsc9 = Nsc9.new()
	var spatial = nsc9.encode_entity_spatial(1, 5)
	var faction = nsc9.encode_entity_faction(1, 7)
	var social = nsc9.encode_entity_social(1, 3)
	var game = nsc9.encode_entity_game(1, 2)
	assert(nsc9.decode_int(spatial)["axis"] == 6)
	assert(nsc9.decode_int(faction)["axis"] == 107)
	assert(nsc9.decode_int(social)["axis"] == 303)
	assert(nsc9.decode_int(game)["axis"] == 402)
	return true

func _test_projection() -> bool:
	var nsc9 = Nsc9.new()
	var latlon = nsc9.project_to_latlon(Vector3(1, 0, 0))
	assert(abs(latlon.x) < 0.01)
	assert(abs(latlon.y) < 0.01)
	var v = nsc9.nearest_vertex(Vector3(0, 1, 0))
	assert(v >= 0 and v < 12)
	return true

func _test_cell_key() -> bool:
	var nsc9 = Nsc9.new()
	var key = nsc9.cell_key(7, 42, 123456)
	assert("nsc9" in key)
	var key2 = nsc9.cell_key_from_int(nsc9.encode_int(7, 42, 123456))
	assert(key == key2)
	return true

func _test_deterministic_seq() -> bool:
	var nsc9 = Nsc9.new()
	var s1 = nsc9.deterministic_seq("player_42", "s")
	var s2 = nsc9.deterministic_seq("player_42", "s")
	assert(s1 == s2)
	assert(s1 >= 0 and s1 < 1000000)
	var s3 = nsc9.deterministic_seq("player_42", "f")
	assert(s1 != s3)
	return true

func _test_year_encoding() -> bool:
	var nsc9 = Nsc9.new()
	assert(nsc9.encode_year(2026) == 2026)
	assert(nsc9.decode_year(2026) == 2026)
	var code = nsc9.encode_entity_temporal_year(1, 2026)
	var parsed = nsc9.decode_int(code)
	assert(parsed["axis"] == 200)
	assert(parsed["sequence"] == 2026)
	return true
