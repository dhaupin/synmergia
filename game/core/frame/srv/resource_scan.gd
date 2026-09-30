## ResourceScan - the ONE export-safe data scanner (frame primitive)
##
## THE BUG IT KILLS: thirteen runtime scanners filtered
## `ends_with(".tres")`. That works in the project tree, but Godot's
## EXPORTER converts text .tres resources into BINARY .res files
## inside the pack (rewriting path references through .remap
## sidecars). Inside an exported pack a by-extension scan finds no
## .tres at all -- DataService booted with 0 species, 0 classes, 0
## everything, and the character-select card strip rendered empty.
## The dev tree never saw it; the exported web client did.
##
## What a data file looks like inside a pack:
##   x.res            the converted binary resource (loads directly)
##   x.tres.remap     remap sidecar: path "x.tres" resolves to x.res
##   x.tres           kept as text when NOT converted (loads directly)
## One resource can therefore appear as TWO directory entries
## (x.res and x.tres.remap) -- the scan dedupes them to one.
##
## Frame primitive rules: pure statics, no autoload, no class_name,
## co-located test.
extends RefCounted


## All loadable resource paths under `dir_path` (recursive; a trailing
## slash is tolerated), deduped and sorted -- every returned path is
## directly load()able in BOTH the dev tree and an exported pack.
static func list_resources(dir_path: String) -> Array[String]:
	var found: Dictionary = {}  # base path (no final ext) -> stored path
	_scan(_normalized(dir_path), found)
	var out: Array[String] = []
	for key in found.keys():
		out.append(str(found[key]))
	out.sort()
	return out


## All loadable resources in `dir_path`, keyed by `id_of` (called as
## id_of.call(resource, path) -- keep it pure; it feeds a Dictionary
## key). Skips resources that fail to load.
static func load_dir(dir_path: String, id_of: Callable) -> Dictionary:
	var results: Dictionary = {}
	for path in list_resources(dir_path):
		var res: Resource = load(path)
		if res != null:
			results[str(id_of.call(res, path))] = res
	return results


## "species_human.res" -> "species_human";
## "species_human.tres" -> "species_human";
## "species_human.tres.remap" -> "species_human" (same resource as
## the .res -- the dedupe key). Non-resource files -> "".
static func resource_base(fname: String) -> String:
	var f := fname
	if f.ends_with(".remap"):
		f = f.substr(0, f.length() - ".remap".length())
	if f.ends_with(".tres"):
		return f.substr(0, f.length() - ".tres".length())
	if f.ends_with(".res"):
		return f.substr(0, f.length() - ".res".length())
	return ""


## A trailing slash (common in existing callers, e.g.
## "res://data/targets/") must scan exactly like the bare dir -- and
## must never leak into the built paths as a mid-path "//".
static func _normalized(dir_path: String) -> String:
	return dir_path.trim_suffix("/")


static func _scan(dir_path: String, found: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if dir.current_is_dir():
			if fname != "." and fname != "..":
				_scan(dir_path + "/" + fname, found)
		else:
			var base := resource_base(fname)
			if base != "":
				var key := dir_path + "/" + base
				if not found.has(key):
					# Store the exact file seen; both forms load.
					var stored := fname
					if stored.ends_with(".remap"):
						stored = stored.substr(0, stored.length() - ".remap".length())
					found[key] = dir_path + "/" + stored
		fname = dir.get_next()
	dir.list_dir_end()
