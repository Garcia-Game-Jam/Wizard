class_name HorrorMatchConfig
extends Resource

## Designer-tunable defaults for asymmetric horror matches.

@export var anchor_count: int = 3
@export var match_time_limit_seconds: int = 1200


static func defaults() -> HorrorMatchConfig:
	var config := HorrorMatchConfig.new()
	config.anchor_count = 3
	config.match_time_limit_seconds = 1200
	return config
