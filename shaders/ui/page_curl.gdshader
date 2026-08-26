shader_type canvas_item;
render_mode unshaded, blend_mix;

// Soja-style peel hinged at the spine. Lands within the opposite page only.

uniform sampler2D front_tex : source_color, filter_linear, repeat_disable;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
// +1 = right->left (next / E), -1 = left->right (prev / Q)
uniform float direction = 1.0;
uniform float curl_radius : hint_range(0.04, 0.35) = 0.12;
// 0 = rigid vertical hinge, 1 = strong bottom-corner peel
uniform float corner_pull : hint_range(0.0, 1.0) = 0.7;
uniform vec4 back_color : source_color = vec4(0.94, 0.89, 0.78, 1.0);
uniform vec4 curl_shade : source_color = vec4(0.2, 0.12, 0.06, 0.35);
uniform vec2 page_size = vec2(320.0, 440.0);
// Gutter between left/right page frames (matches base_book SpineGutter).
uniform float spine_gap = 14.0;

varying float v_side;
varying float v_curl_shade;
varying vec2 v_uv;


void vertex() {
	vec2 uv = UV;
	// Normalize so the spine is at x=0 and the outer edge at x=1.
	float dir = sign(direction);
	if (dir < 0.0) {
		uv.x = 1.0 - uv.x;
	}

	// Bottom edge leads the peel (Soja).
	float lead = pow(clamp(uv.y, 0.0, 1.0), 1.15);
	float local_p = clamp(
		progress * (1.0 + corner_pull * lead) - corner_pull * lead * 0.35,
		0.0,
		1.0
	);

	// Rigid book hinge: 0 on the source page, PI flat on the destination page.
	float angle = local_p * PI;
	float dist = clamp(uv.x, 0.0, 1.0);
	float r = max(curl_radius, 0.04);

	// Soft tip: a short cylinder near the free edge so the silhouette peels.
	float tip = smoothstep(1.0 - r * 1.8, 1.0, dist) * sin(angle);
	float tip_roll = tip * r * page_size.x;

	float cos_a = cos(angle);
	float sin_a = sin(angle);
	// Position relative to the spine (source page grows +x).
	float x_from_spine = dist * page_size.x * cos_a - tip_roll * sin_a;
	// Cross the gutter onto the opposite page during the second half.
	float cross = smoothstep(0.5, 1.0, local_p);
	x_from_spine -= spine_gap * cross;

	// Never draw past the far edge of the opposite page, or past this page's outer edge.
	float min_x = -(page_size.x + spine_gap);
	float max_x = page_size.x;
	x_from_spine = clamp(x_from_spine, min_x, max_x);

	vec2 local = vec2(x_from_spine, uv.y * page_size.y);
	// Slight lift at mid-turn; keep it inside the page height.
	float lift = sin_a * (0.035 + tip * 0.04) * page_size.y;
	local.y = clamp(local.y - lift * 0.35, 0.0, page_size.y);

	v_uv = UV;
	v_side = cos_a >= 0.0 ? 1.0 : -1.0;
	v_curl_shade = abs(sin_a) * (0.35 + tip * 0.5);

	if (dir < 0.0) {
		// Source was the left page: spine is on its right edge.
		local.x = page_size.x - local.x;
	}

	VERTEX = local;
}


void fragment() {
	vec4 front = texture(front_tex, v_uv);
	vec4 col = front;
	if (v_side < 0.0) {
		col = mix(back_color, front, 0.08);
		col.a = max(front.a, back_color.a);
	}
	col.rgb = mix(col.rgb, curl_shade.rgb, clamp(v_curl_shade, 0.0, 1.0) * curl_shade.a);
	if (front.a < 0.01 && v_side > 0.0) {
		discard;
	}
	COLOR = col;
}
