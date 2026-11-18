shader_type canvas_item;
render_mode unshaded;

float grain(vec2 p) {
	return fract(sin(dot(p, vec2(29.137, 61.521))) * 43758.5453);
}

void fragment() {
	vec2 p = floor(FRAGCOORD.xy);
	float fibers = (grain(vec2(floor(p.x / 5.0), p.y)) - 0.5) * 0.020;
	float flecks = (grain(p) - 0.5) * 0.030;
	float stain = (grain(floor(p / 21.0)) - 0.5) * 0.009;
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float wear = smoothstep(0.0, 0.25, edge) * 0.014 - 0.006;
	COLOR = vec4(max(COLOR.rgb + vec3(fibers + flecks + stain + wear), vec3(0.0)), COLOR.a);
}
