shader_type canvas_item;

uniform bool outline = false;

float luminance(vec2 point, sampler2D artwork) {
	return dot(texture(artwork, point).rgb, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	float light = luminance(UV, TEXTURE);
	float shape = smoothstep(0.08, 0.26, light);
	if (outline) {
		vec2 sample_step = TEXTURE_PIXEL_SIZE * 2.0;
		float edge = abs(light - luminance(UV + vec2(sample_step.x, 0.0), TEXTURE));
		edge += abs(light - luminance(UV + vec2(0.0, sample_step.y), TEXTURE));
		vec3 wash = mix(vec3(0.12, 0.17, 0.16), vec3(0.63, 0.67, 0.58), shape * 0.85);
		COLOR = vec4(mix(wash, vec3(0.19, 0.24, 0.21), clamp(edge * 5.0, 0.0, 1.0)), 1.0);
	} else {
		COLOR = vec4(mix(vec3(0.08, 0.11, 0.11), vec3(0.25, 0.32, 0.30), shape), 1.0);
	}
}
