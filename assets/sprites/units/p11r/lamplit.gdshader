shader_type canvas_item;

// Light falls across the upper-left edges of the painted silhouette inside the atlas.
varying vec4 sprite_tint;
void vertex() {
	sprite_tint = COLOR;
}
void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	if (TEXTURE_PIXEL_SIZE.x < 0.003 && TEXTURE_PIXEL_SIZE.y < 0.006) {
		float open_edge = 1.0 - texture(TEXTURE, UV - TEXTURE_PIXEL_SIZE * vec2(1.0, 1.0)).a;
		vec3 exposed = sqrt(max(texel.rgb, vec3(0.0))) * vec3(0.92, 0.85, 0.75);
		texel.rgb = mix(texel.rgb, exposed, 0.58);
		texel.rgb += vec3(0.38, 0.26, 0.13) * smoothstep(0.12, 0.95, open_edge);
	}
	COLOR = texel * sprite_tint;
}
