## Branding asset loader (static helper, preload-only -- no class_name,
## no autoload). The logo pack lives in assets/branding/; drop the four
## exports there (see that folder's README) and every Brand.* consumer
## picks them up with zero code changes.
##
## All lookups are runtime load() with existence checks: a missing file
## returns null and callers fall back to text, so the game never breaks
## over cosmetics and partial packs are fine.
extends RefCounted

const DIR := "res://assets/branding/"


static func _tex(file_name: String) -> Texture2D:
	var path := DIR + file_name
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


## The star emblem alone (sheet: bottom-left variant). Square; use at
## 128px and up.
static func emblem() -> Texture2D:
	return _tex("emblem.png")


## Compact emblem (sheet: top-left emblem) for dense UI spots.
static func emblem_small() -> Texture2D:
	return _tex("emblem_small.png")


## Full-width horizontal lockup: emblem + SYNMERGIA banner bar
## (sheet: top-right variant).
static func lockup() -> Texture2D:
	return _tex("logo_horizontal.png")


## Wordmark alone (sheet: bottom-right variant).
static func wordmark() -> Texture2D:
	return _tex("wordmark.png")


## True when at least one branding asset is present.
static func has_pack() -> bool:
	return emblem() != null or wordmark() != null or lockup() != null
