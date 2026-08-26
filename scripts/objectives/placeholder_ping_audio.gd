class_name PlaceholderPingAudio
extends RefCounted

## Generates a short decaying sine ping (no audio asset required).


static func create_stream(
	duration_sec: float = 0.18,
	frequency_hz: float = 880.0,
	sample_rate: int = 22050
) -> AudioStreamWAV:
	var sample_count := int(duration_sec * float(sample_rate))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / float(sample_rate)
		var envelope := 1.0 - (t / duration_sec)
		var sample := sin(TAU * frequency_hz * t) * envelope * 0.35
		var sample_i16 := int(clampi(int(sample * 32767.0), -32768, 32767))
		data[i * 2] = sample_i16 & 0xFF
		data[i * 2 + 1] = (sample_i16 >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream
