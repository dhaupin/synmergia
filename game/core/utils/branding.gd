## Branding asset loader (static helper, preload-only -- no class_name,
## no autoload). The logo pack lives in assets/branding/; the shipped
## pack uses the logo-synmergia-* filenames below. Every lookup is
## runtime load() with existence checks: a missing file returns null
## and callers fall back to text, so the game never breaks over
## cosmetics and partial packs are fine.
extends RefCounted

const DIR := "res://assets/branding/"


static func _tex(file_name: String, dir: String = DIR) -> Texture2D:
	var path := dir + file_name
	# Imported pack (editor scanned it / exported build): normal path.
	if ResourceLoader.exists(path, "Texture2D"):
		return load(path) as Texture2D
	# Dev drop-in: the file exists but the import DB has not picked it
	# up yet (fresh drop before an editor scan, headless runs). Decode
	# the PNG directly so the branding shows up with zero ceremony.
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			return ImageTexture.create_from_image(img)
	return null


## The star emblem alone. Square; use at 128px and up.
static func emblem(dir: String = DIR) -> Texture2D:
	return _tex("logo-synmergia-emblem.png", dir)


## Compact emblem for dense UI spots (loading panel, tooltips).
static func emblem_small(dir: String = DIR) -> Texture2D:
	return _tex("logo-synmergia-emblem-small.png", dir)


## Full-width horizontal lockup: emblem + SYNMERGIA banner bar.
static func lockup(dir: String = DIR) -> Texture2D:
	return _tex("logo-synmergia-horizontal.png", dir)


## Wordmark alone (footers, splash text).
static func wordmark(dir: String = DIR) -> Texture2D:
	return _tex("logo-synmergia-wordmark.png", dir)


## True when at least one branding asset is present.
static func has_pack(dir: String = DIR) -> bool:
	return emblem(dir) != null or wordmark(dir) != null or lockup(dir) != null
