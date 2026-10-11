## WeatherEventData - Data-driven weather-triggered world events.
##
## Makes the sun->sword seam a content pipeline (the HordeData
## convention): designers author .tres files under data/weather_events/
## and WeatherEventService stages them when their trigger fires —
## no code change to add a new storm ritual, an aurora giveaway,
## a fog-mystery night, or a custom server event ("Kp 9 calls the
## Ancient down").
##
## Triggers (one .tres may declare several; ANY match fires):
##   trigger_kind SPARK_BAND  — a cosmic spark whose band name is in
##     band_names (e.g. storm/tempest sparks stir packs).
##   trigger_kind BAND_STATE  — a weather RESOLVE state change whose
##     name is in band_names (trad-fallback storms included — the
##     world reacts without waiting for the sun).
##   trigger_kind AURORA_BAND — a cosmic spark whose band aurora value
##     >= aurora_min (custom aurora windows, aurora rituals).
##
## Actions (evaluated in declaration order; each is optional):
##   stir_horde_config  — start this horde config id (data/hordes/)
##     capped at stir_waves, boss suppressed. Empty = no pack.
##   open_aurora_window — open an aurora observation window on the
##     highest-value mystery for open_window_sec seconds.
##   notify_message     — toast to the realm (kind WEATHER_STORM_STIRRED
##     unless custom_notify_kind is set).
##
## Timing: cooldown_sec between fires of THE SAME .tres (per-service,
## one WeatherEventService per world). first_fire_free matches the
## ground truth the tests pin: a fresh engine's get_ticks_msec starts
## near 0 and must not gate the first event.
extends Resource

enum TriggerKind {
	SPARK_BAND,    ## Cosmic spark whose band name is in band_names
	BAND_STATE,    ## Weather resolve state change named in band_names
	AURORA_BAND,   ## Cosmic spark whose band aurora >= aurora_min
}

## Stable id (== file stem convention: weather_<id>.tres).
@export var id: String = ""
## Display name for logs/notifications.
@export var display_name: String = ""

## --- Triggering ---
@export var trigger_kinds: Array[int] = [TriggerKind.SPARK_BAND]
## Band/state names that satisfy SPARK_BAND / BAND_STATE triggers
## (e.g. ["storm", "tempest"] or ["rain", "storm"]).
@export var band_names: Array[String] = []
## Aurora threshold for AURORA_BAND triggers (e.g. 0.5).
@export var aurora_min: float = 0.5
## Seconds between fires of this event (0 = fire every trigger).
@export var cooldown_sec: float = 240.0
## Zones where this event may fire. Empty = zone_starter_plains (the
## stirred-pack ground truth lives there in v1).
@export var zone_ids: Array[String] = []

## --- Actions ---
## Horde config id (data/hordes/) to stir. Empty = no pack.
@export var stir_horde_config: String = ""
## Wave cap applied over the config's own wave count (a stirred pack
## is short; the config's full extension only fires on real triggers).
@export var stir_waves: int = 2
## Open an aurora observation window for this many seconds
## (0 = no window from this event).
@export var open_window_sec: float = 0.0
## Toast text. Empty = no notification from this event.
@export var notify_message: String = ""

## Flatten to the runtime Dictionary WeatherEventService consumes
## (mirrors HordeData.to_config's contract).
func to_config() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"trigger_kinds": trigger_kinds.duplicate(),
		"band_names": band_names.duplicate(),
		"aurora_min": aurora_min,
		"cooldown_sec": maxf(0.0, cooldown_sec),
		"zone_ids": zone_ids.duplicate(),
		"stir_horde_config": stir_horde_config,
		"stir_waves": stir_waves,
		"open_window_sec": maxf(0.0, open_window_sec),
		"notify_message": notify_message,
	}
