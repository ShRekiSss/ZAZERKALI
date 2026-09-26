shader_type spatial;
render_mode unshaded, cull_disabled;

// Поверхность зеркала: берёт картинку из SubViewport (второй камера),
// зеркалит по X, добавляет «плывущий» дисторшн; в Зазеркалье — инвертирует палитру.

uniform sampler2D reflection : source_color, filter_linear;
uniform float distortion_strength : hint_range(0.0, 0.1) = 0.015;
uniform float distort_speed : hint_range(0.0, 5.0) = 1.0;
// 0.0 = обычное зеркало, 1.0 = полное Зазеркалье (палитра инвертирована).
uniform float invert_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 0.9, 1.0);

float hash_noise(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	uv.x = 1.0 - uv.x; // отражение — это горизонтальный флип картинки
	// «плывущий» эффект: волна + шум
	vec2 warp = vec2(
		sin(uv.y * 22.0 + TIME * distort_speed) + hash_noise(uv * 6.0 + TIME * 0.3 * distort_speed) - 0.5,
		cos(uv.x * 17.0 + TIME * distort_speed * 0.8)
	) * distortion_strength;
	vec3 col = texture(reflection, uv + warp).rgb;
	// Инверсия палитры (в GLSL это то же самое, что встроенная идея invert(): 1.0 - цвет)
	col = mix(col, vec3(1.0) - col, invert_amount);
	ALBEDO = col * tint;
}
