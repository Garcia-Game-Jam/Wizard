shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 rim_color : source_color = vec4(0.42, 0.78, 1.0, 1.0);
uniform vec4 energy_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float fresnel_power : hint_range(0.5, 6.0) = 2.8;
uniform float base_alpha : hint_range(0.0, 0.4) = 0.05;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.92;
uniform float energy_amount : hint_range(0.0, 2.0) = 1.15;
uniform float pattern_scale : hint_range(0.05, 8.0) = 0.28;
uniform float scroll_speed : hint_range(0.0, 1.0) = 0.11;
uniform float proximity_fade : hint_range(0.0, 4.0) = 1.2;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

varying vec3 v_world;
varying vec3 v_view;


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}


float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += value_noise(p) * amp;
		p *= 2.07;
		amp *= 0.5;
	}
	return v;
}


float voronoi_edge(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float best = 8.0;
	vec2 best_r = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(n + g), hash(n + g + vec2(17.2, 9.1)));
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < best) {
				best = d;
				best_r = r;
			}
		}
	}
	float edge = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(n + g), hash(n + g + vec2(17.2, 9.1)));
			vec2 r = g + o - f;
			vec2 diff = r - best_r;
			float len = length(diff);
			if (len > 0.0001) {
				edge = min(edge, dot(0.5 * (best_r + r), diff / len));
			}
		}
	}
	return edge;
}


void vertex() {
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	v_world = world.xyz;
	v_view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec3 n = NORMAL;
	if (!FRONT_FACING) {
		n = -n;
	}
	float ndv = abs(dot(normalize(n), normalize(VIEW)));
	float fresnel = pow(1.0 - clamp(ndv, 0.0, 1.0), fresnel_power);

	vec2 p = vec2(v_world.x + v_world.z, v_world.y) * pattern_scale;
	p += vec2(TIME * scroll_speed, TIME * scroll_speed * -0.37);
	float splash = smoothstep(0.48, 0.78, fbm(p * 0.45 + TIME * 0.04));
	float veins = 1.0 - smoothstep(0.0, 0.085, voronoi_edge(p * 2.4));
	float cracks = pow(veins, 2.4) * (0.35 + splash);
	float energy = cracks * energy_amount;

	float fade = 1.0;
	if (proximity_fade > 0.001) {
		float depth = texture(depth_tex, SCREEN_UV).r;
		vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		scene.xyz /= scene.w;
		float dist = abs(scene.z - v_view.z);
		fade = smoothstep(0.0, proximity_fade, dist);
	}

	vec3 col = mix(rim_color.rgb, energy_color.rgb, clamp(energy * 1.6, 0.0, 1.0));
	float alpha = base_alpha + fresnel * rim_strength + energy;
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0) * fade * opacity;
}
