// Blurred, dimmed copy of everything drawn beneath this rect — the
// backdrop behind modal dialogs, so the player reads the dialog as a
// choice they have to make before the game continues.
//
// Blur comes from sampling a mip of the screen texture with a 3×3
// tent filter on top (a single mip lookup alone looks blocky).
// `amount` scales both blur and dim so a tween on it fades the
// backdrop in/out.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float blur_lod : hint_range(0.0, 6.0) = 3.0;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 0.4);

void fragment() {
	float lod = blur_lod * amount;
	vec2 px = SCREEN_PIXEL_SIZE * exp2(lod);
	vec3 c = textureLod(screen_tex, SCREEN_UV, lod).rgb * 0.25;
	c += textureLod(screen_tex, SCREEN_UV + vec2(px.x, 0.0), lod).rgb * 0.125;
	c += textureLod(screen_tex, SCREEN_UV - vec2(px.x, 0.0), lod).rgb * 0.125;
	c += textureLod(screen_tex, SCREEN_UV + vec2(0.0, px.y), lod).rgb * 0.125;
	c += textureLod(screen_tex, SCREEN_UV - vec2(0.0, px.y), lod).rgb * 0.125;
	c += textureLod(screen_tex, SCREEN_UV + px, lod).rgb * 0.0625;
	c += textureLod(screen_tex, SCREEN_UV - px, lod).rgb * 0.0625;
	c += textureLod(screen_tex, SCREEN_UV + vec2(px.x, -px.y), lod).rgb * 0.0625;
	c += textureLod(screen_tex, SCREEN_UV + vec2(-px.x, px.y), lod).rgb * 0.0625;
	COLOR = vec4(mix(c, tint.rgb, tint.a * amount), 1.0);
}
