extends SceneTree

func _init() -> void:
	print("--- FULL BOOT ---")
	await process_frame
	await process_frame
	await process_frame
	print("--- BOOT DONE ---")
	quit(0)
