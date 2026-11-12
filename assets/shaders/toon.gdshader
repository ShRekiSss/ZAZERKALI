shader_type spatial;
render_mode blend_mix, depth_draw_opaque, specular_disabled;

// Toon Shader (Cel Shading): свет делится на жёсткие полосы без плавных
// переходов + светлая кайма по силуэту — 3D выглядит как рисунок, а не рендер.
// Поддерживает текстуру: use_texture = true → base_color умножается на текстуру.

uniform vec3 base_color : source_color = vec3(0.72, 0.64, 0.49);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap;
uniform bool use_texture = false;
// Цвет теневой стороны. Чуть фиолетовый, чтобы тени были «жутко-милыми», а не серыми.
uniform vec3 shadow_color : source_color = vec3(0.25, 0.2, 0.28);
uniform vec3 rim_color : source_color = vec3(0.95, 0.9, 0.85);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	vec4 tex = texture(texture_albedo, UV);
	ALBEDO = mix(base_color, tex.rgb * base_color, float(use_texture));
	// Прозрачность берётся из текстуры (для лица-наклейки с прозрачным фоном).
	ALPHA = mix(1.0, tex.a, float(use_texture));
}

void light() {
	// Трёхполосная заливка: тень, полутон, свет. Резкие пороги дают читаемый cel-стайл.
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.02, 0.12, ndl);
	float mid = smoothstep(0.28, 0.42, ndl);
	DIFFUSE_LIGHT += shadow_color * LIGHT_COLOR * ATTENUATION * (1.0 - mid);
	DIFFUSE_LIGHT += mix(shadow_color, ALBEDO, 0.5) * LIGHT_COLOR * ATTENUATION * (mid - lit);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * lit;
	// Rim light — подсветка края силуэта, «доводка» рисованного вида.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	DIFFUSE_LIGHT += rim_color * rim * rim_strength * ATTENUATION;
}
