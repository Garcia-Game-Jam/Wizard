extends Object

## Maps the mic dial (0 = mute, 1 = unity, 2 = max) to linear gain for
## hearback / VoIP. Past unity, gain expands to SettingsManager.MIC_BOOST_CEILING
## so boost is obvious in the mic test (plain 2× was too subtle / clipped).


static func linear_from_dial(dial: float) -> float:
	var lo := 0.0
	var hi := SettingsManager.MIC_VOLUME_MAX
	var v := clampf(dial, lo, hi)
	if v <= 1.0:
		return v
	var t := (v - 1.0) / (hi - 1.0)
	## Linear past unity: ~150% dial ≈ 3×, max dial ≈ 5× (~14 dB).
	return lerpf(1.0, SettingsManager.MIC_BOOST_CEILING, t)


static func from_settings() -> float:
	return linear_from_dial(SettingsManager.mic_volume)


## Soft-saturate under boost so hot mics get louder instead of brickwall ±1.
static func apply_sample(sample: float, dial: float = -1.0) -> float:
	var gain := from_settings() if dial < 0.0 else linear_from_dial(dial)
	var scaled := sample * gain
	if gain <= 1.0:
		return clampf(scaled, -1.0, 1.0)
	return tanh(scaled)
