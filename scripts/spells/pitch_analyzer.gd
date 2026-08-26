class_name PitchAnalyzer
extends RefCounted

## Simple autocorrelation pitch estimation for monophonic voice slices.


static func estimate_hz(samples: PackedFloat32Array, sample_rate: int) -> float:
	if samples.is_empty() or sample_rate <= 0:
		return 0.0

	var mono := _to_mono(samples)
	if mono.is_empty():
		return 0.0

	var min_lag: int = maxi(1, int(sample_rate / 500.0))
	var max_lag: int = mini(mono.size() - 1, int(sample_rate / 70.0))
	if max_lag <= min_lag:
		return 0.0

	var best_lag := min_lag
	var best_corr := -1.0
	for lag in range(min_lag, max_lag + 1):
		var corr := _correlation_at_lag(mono, lag)
		if corr > best_corr:
			best_corr = corr
			best_lag = lag

	if best_corr < 0.2:
		return 0.0
	return float(sample_rate) / float(best_lag)


static func _to_mono(samples: PackedFloat32Array) -> PackedFloat32Array:
	return samples


static func pitch_band_score(
	detected_hz: float,
	target_hz: float,
	tolerance_ratio: float = 0.18
) -> float:
	if detected_hz <= 0.0 or target_hz <= 0.0:
		return 0.0
	var ratio: float = detected_hz / target_hz
	var diff: float = absf(ratio - 1.0)
	if diff <= tolerance_ratio:
		return 1.0 - diff / tolerance_ratio
	return 0.0


static func _correlation_at_lag(samples: PackedFloat32Array, lag: int) -> float:
	var sum := 0.0
	var count := samples.size() - lag
	if count <= 0:
		return 0.0
	for i in count:
		sum += samples[i] * samples[i + lag]
	return sum / float(count)
