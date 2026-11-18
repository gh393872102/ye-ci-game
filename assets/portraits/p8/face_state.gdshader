shader_type canvas_item;
uniform bool face_hidden = false;
uniform bool native_faceless = false;
uniform int portrait_mode = 0;
uniform vec4 face_region = vec4(0.34, 0.055, 0.32, 0.22);
void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec2 q = (UV-face_region.xy)/face_region.zw;
	float oval = 1.0-smoothstep(0.40,0.50,length((q-vec2(0.5))*vec2(1.12,0.94)));
	if (face_hidden) {
		vec3 cheek = (texture(TEXTURE,face_region.xy+face_region.zw*vec2(0.20,0.58)).rgb + texture(TEXTURE,face_region.xy+face_region.zw*vec2(0.80,0.58)).rgb)*0.5;
		vec3 blank = mix(cheek,vec3(0.30,0.37,0.34),0.38)*(0.90+0.06*sin(q.y*23.0));
		base.rgb = mix(base.rgb,blank,oval*0.98);
	} else if (native_faceless) {
		vec3 mask = vec3(0.65,0.68,0.57)*(0.86+0.13*q.x);
		float eye = max(1.0-smoothstep(0.035,0.075,length((q-vec2(0.34,0.45))*vec2(1.0,1.8))),1.0-smoothstep(0.035,0.075,length((q-vec2(0.66,0.45))*vec2(1.0,1.8))));
		float mouth = (1.0-smoothstep(0.025,0.045,abs(q.y-0.72)))*(1.0-smoothstep(0.12,0.18,abs(q.x-0.5)));
		mask = mix(mask,vec3(0.11,0.17,0.17),max(eye,mouth)*0.9);
		base.rgb = mix(base.rgb,mask,oval*0.9);
	}
	if (portrait_mode == 1) {
		base.rgb = vec3(dot(base.rgb,vec3(0.299,0.587,0.114)))*vec3(0.12,0.18,0.18);
	} else if (portrait_mode == 2) {
		vec2 texel = TEXTURE_PIXEL_SIZE*2.0;
		float l = dot(base.rgb,vec3(0.299,0.587,0.114));
		float dx = abs(l-dot(texture(TEXTURE,UV+vec2(texel.x,0.0)).rgb,vec3(0.299,0.587,0.114)));
		float dy = abs(l-dot(texture(TEXTURE,UV+vec2(0.0,texel.y)).rgb,vec3(0.299,0.587,0.114)));
		base.rgb = mix(vec3(0.73,0.75,0.65),vec3(0.16,0.23,0.22),clamp((dx+dy)*8.0+(1.0-l)*0.25,0.0,1.0));
	}
	COLOR = base;
}
