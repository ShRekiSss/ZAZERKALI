extends Node3D
## ГЛАВНАЯ сцена игры (3D): тронный зал Волшебника.
## Весь игровой процесс кликера живёт здесь: тап → челик кланяется →
## +Благосклонность, апгрейды внизу экрана, сюжетные фразы, Зазеркалье.
## Логика чисел — в GameState (autoload), эта сцена только показывает.

const TOON_SHADER := preload("res://assets/shaders/toon.gdshader")
const MIRROR_SHADER := preload("res://assets/shaders/mirror.gdshader")
## Пак Kenney (CC0): модели подхватываются отсюда.
const MODELS_DIR := "res://assets/models/Models/GLB format/"
## Meshy-модели пользователя: челик (риг + анимации) и волшебник.
const CHELIK_GLB := "res://assets/models/meshy/chelik_meshy.glb"
const WIZARD_GLB := "res://assets/models/meshy/wizard_meshy.glb"
## Раб-молящийся: жёсткая модель без рига — анимация коленопреклонения процедурная
const SLAVE_GLB := "res://assets/models/meshy/slave_meshy.glb"

## Через сколько секунд без тапов челик сам делает поклон.
const IDLE_BOW_EVERY := 2.5

## Настройки громкости сохраняются сюда (шины Master/Music/SFX)
const SETTINGS_PATH := "user://settings.cfg"

var _chelik: Node3D
var _chelik_anim: AnimationPlayer
var _idle_anim := ""
var _bow_anim := ""
var _wizard: Node3D
var _mirror_mat: ShaderMaterial
var _env: Environment
var _bow_t := 0.0
var _idle_t := 0.0
var _root_bowing := false

## Welwitschia Goth: бабочки, лепестки, мерцающие свечи
var _butterflies: Array[Dictionary] = []
var _petal_mm: MultiMeshInstance3D
var _petals: Array[Dictionary] = []
var _candle_lights: Array[Dictionary] = []
var _welw_t := 0.0
## Раб: плавно опускается на колени и молится (жёсткая модель, цикл 14 с)
var _slave: Node3D
var _slave_base_y := 0.0
var _slave_t := 0.0

## Звуки: ключ → плеер. Тапы — случайный «шорох ткани» (Kenney CC0),
## эмбиент-дрон синтезируется кодом на старте — файлы не нужны.
var _sfx := {}
var _tap_players: Array[AudioStreamPlayer] = []

## Процедурные текстуры (крыло/лепесток/лист) — рисуются один раз при старте
var _tex_wing: ImageTexture
var _tex_petal: ImageTexture
var _tex_leaf: ImageTexture

## UI
var _counter_label: Label
var _rate_label: Label
var _story_label: Label
var _upgrades_panel: GridContainer
var _buttons := {}


func _ready() -> void:
	_setup_environment()
	_setup_ground()
	_setup_throne_area()
	_setup_welwitschia()
	_setup_wizard()
	_chelik = _make_character(Color(0.72, 0.64, 0.49))
	# Композиция вдоль оси Z (портретный экран узкий по X!): челик на переднем плане,
	# волшебник и трон — в глубине по центральной оси, всё влезает в кадр.
	_chelik.position.x = 0.0
	_chelik.position.z = 1.2
	_setup_slave()
	_setup_mirror()
	_setup_camera()
	_setup_audio()
	_setup_ui()
	GameState.changed.connect(_update_ui)
	GameState.story_line.connect(_show_story)
	GameState.story_line.connect(func(_t: String) -> void: _play_sfx("creak"))
	_update_ui()
	if DisplayServer.get_name() == "headless":
		_diag()


func _diag() -> void:
	var cp := _find_animation_player(_chelik)
	print("CHELIK: ", _chelik.name,
		" | анимации: ", cp.get_animation_list() if cp else ["нет"],
		" | поклон: ", _bow_anim)
	var wp := _find_animation_player(_wizard) if _wizard else null
	print("WIZARD: ", _wizard.name if _wizard else "примитивы",
		" | анимации: ", wp.get_animation_list() if wp else ["нет"])
	# Автотест тапа: синтетический тап в центр экрана → благосклонность должна вырасти.
	await get_tree().create_timer(0.5).timeout
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	ev.position = Vector2(360, 640)
	Input.parse_input_event(ev)
	await get_tree().create_timer(0.3).timeout
	print("TAP TEST: favor=", GameState.favor, " (ожидался +", GameState.tap_power(), ")")


func _process(delta: float) -> void:
	# Пассивный поклон: если игрок не тапает, челик кланяется сам.
	if not _root_bowing:
		_idle_t += delta
		if _idle_t >= IDLE_BOW_EVERY:
			_idle_t = 0.0
			if _chelik_anim:
				if _chelik_anim.current_animation != _bow_anim:
					_play_bow()
			else:
				_root_bow(0.7, 1.0, 0.85) # медленный поклон наклоном
	_update_welwitschia(delta)
	_update_slave(delta)


func _input(event: InputEvent) -> void:
	var tapped := false
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch and event.pressed:
		tapped = true
		pos = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		tapped = true
		pos = event.position
	if not tapped:
		return
	# Тапы по панелям UI — не поклоны.
	for panel: Control in [_upgrades_panel, _story_label]:
		if panel.get_global_rect().has_point(pos):
			return
	_idle_t = 0.0
	GameState.add_tap()
	_play_sfx("tap")
	if _chelik_anim:
		_play_bow()
	else:
		_root_bow(0.12, 0.45, 1.1) # быстрый резкий поклон


## --- Поклоны -----------------------------------------------------------

func _play_bow() -> void:
	if _chelik_anim == null:
		return
	# Спам-тапы: не дёргаем плеер stop/play (из-за этого челик зависал в T-позе),
	# а просто отматываем текущую анимацию в начало.
	if _chelik_anim.current_animation == _bow_anim and _chelik_anim.is_playing():
		_chelik_anim.seek(0.0, true)
	else:
		_chelik_anim.stop()
		_chelik_anim.play(_bow_anim)


func _on_bow_finished(_anim_name: String) -> void:
	# После поклона возвращаемся в idle-анимацию.
	if _idle_anim != "" and _chelik_anim.current_animation != _idle_anim:
		_chelik_anim.play(_idle_anim)


func _root_bow(down := 0.12, up := 0.45, depth := 1.1) -> void:
	if _root_bowing:
		return
	_root_bowing = true
	# Челик стоит лицом к -Z (к трону), поклон — наклон вперёд вокруг оси X.
	var tween := create_tween()
	tween.tween_property(_chelik, "rotation:x", -depth, down) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.05)
	tween.tween_property(_chelik, "rotation:x", 0.0, up) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void: _root_bowing = false)


## --- Персонажи ---------------------------------------------------------

func _setup_wizard() -> void:
	# Великий Волшебник — Meshy-модель пользователя.
	var scene: PackedScene = load(WIZARD_GLB)
	if scene:
		var wizard: Node3D = scene.instantiate()
		add_child(wizard)
		wizard.position = Vector3(0.0, 0.0, -1.4) # перед троном, СПИНОЙ к камере (смотрит на трон)
		wizard.rotation.y = 0.0
		_fit_model(wizard, 2.3)
		_calm_materials(wizard) # гасим блики/прозрачность — «застрявшие текстуры»
		_wizard = wizard
		return
	# Запасной волшебник из примитивов.
	var fallback := Node3D.new()
	fallback.position = Vector3(0.0, 0.0, -1.4)
	add_child(fallback)
	_wizard = fallback
	var mat := _toon_material(Color(0.29, 0.18, 0.33))
	var robe := CylinderMesh.new()
	robe.top_radius = 0.25
	robe.bottom_radius = 0.55
	robe.height = 2.1
	_mesh(fallback, robe, mat, Vector3(0, 1.05, 0))
	var hat := CylinderMesh.new()
	hat.top_radius = 0.03
	hat.bottom_radius = 0.55
	hat.height = 0.6
	_mesh(fallback, hat, mat, Vector3(0, 2.35, 0))


func _make_character(_color: Color) -> Node3D:
	# Челик — Meshy-модель с ригом: анимации поклона/idle из самого файла.
	var root: Node3D
	var scene: PackedScene = load(CHELIK_GLB)
	if scene:
		root = scene.instantiate()
		root.position = Vector3.ZERO
		root.rotation.y = PI # лицом к трону (-Z); спиной — поменять знак
		add_child(root)
		_fit_model(root, 1.7)
		_chelik_anim = _find_animation_player(root)
		if _chelik_anim and _chelik_anim.get_animation_list().size() > 0:
			var anims := _chelik_anim.get_animation_list()
			_idle_anim = anims[0]
			_bow_anim = anims[1] if anims.size() > 1 else anims[0]
			_chelik_anim.get_animation(_idle_anim).loop_mode = Animation.LOOP_LINEAR
			_chelik_anim.animation_finished.connect(_on_bow_finished)
			_chelik_anim.play(_idle_anim)
		return root
	# Запасной: Kenney Character Assets (общий скелет, Mixamo-совместимый).
	scene = load(MODELS_DIR + "Textures/Casual_Male.gltf")
	if scene:
		root = scene.instantiate()
		root.position = Vector3.ZERO
		root.rotation.y = PI
		add_child(root)
		return root
	# Последний запасной: капсула.
	root = Node3D.new()
	add_child(root)
	var mat := _toon_material(Color(0.72, 0.64, 0.49))
	var body := CapsuleMesh.new()
	body.radius = 0.35
	body.height = 1.3
	_mesh(root, body, mat, Vector3(0, 0.65, 0))
	var head := SphereMesh.new()
	head.radius = 0.28
	head.height = 0.56
	_mesh(root, head, mat, Vector3(0, 1.55, 0))
	return root


## Ищет AnimationPlayer где-то в детях (Meshy кладёт его внутри иерархии).
func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null


## Meshy-модели бывают любого масштаба: нормируем рост и ставим на пол.
func _fit_model(root: Node3D, target_height: float) -> void:
	var boxes: Array[AABB] = []
	_collect_aabb(root, Transform3D(), boxes)
	if boxes.is_empty():
		return
	var box := boxes[0]
	for b in boxes:
		box = box.merge(b)
	if box.size.y < 0.001:
		return
	var scale_factor := target_height / box.size.y
	root.scale = Vector3.ONE * scale_factor
	root.position.y = -box.position.y * scale_factor


func _collect_aabb(node: Node3D, xform: Transform3D, acc: Array[AABB]) -> void:
	if node is MeshInstance3D:
		acc.append(xform * (node as MeshInstance3D).get_aabb())
	for child in node.get_children():
		if child is Node3D:
			_collect_aabb(child, xform * (child as Node3D).transform, acc)


## --- Окружение ---------------------------------------------------------

func _toon_material(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TOON_SHADER
	mat.set_shader_parameter("base_color", color)
	return mat


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _prop(file: String, pos: Vector3, rot_y_deg := 0.0, color := Color(0.55, 0.5, 0.42)) -> Node3D:
	var scene: PackedScene = load(MODELS_DIR + file)
	if scene == null:
		push_warning("Модель не найдена: " + file)
		var empty := Node3D.new()
		add_child(empty)
		return empty
	var node: Node3D = scene.instantiate()
	_apply_toon(node, _toon_material(color))
	node.position = pos
	node.rotation.y = deg_to_rad(rot_y_deg)
	add_child(node)
	return node


func _apply_toon(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = mat
	for child in node.get_children():
		_apply_toon(child, mat)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_mesh(parent, mesh, mat, pos)


func _setup_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.05, 0.04, 0.075)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.45, 0.4, 0.52)
	_env.ambient_light_energy = 0.22
	# Зловещий фиолетовый туман погуще
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.09, 0.07, 0.14)
	_env.fog_density = 0.02
	# Приглушаем общую яркость — зловещесть
	_env.tonemap_exposure = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 0.8
	sun.light_color = Color(0.75, 0.68, 0.9)
	sun.shadow_enabled = true
	add_child(sun)


func _setup_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(24, 24)
	_mesh(self, plane, _toon_material(Color(0.11, 0.1, 0.14)), Vector3.ZERO)


## Тронный зал: трон по центральной оси на возвышении, ковровая дорожка,
## боковые стены, колонны, фонари. Экран портретный — всё строим в глубину.
func _setup_throne_area() -> void:
	var stone := _toon_material(Color(0.45, 0.44, 0.48))
	var wall := Color(0.33, 0.28, 0.36)

	# Торцевая стена: арки позади трона.
	for i in 4:
		_prop("wall-arch.glb", Vector3(-3.45 + i * 2.3, 0.0, -4.2), 0.0, wall)

	# Боковые стены зала.
	for i in 4:
		_prop("wall.glb", Vector3(3.6, 0.0, -3.5 + i * 2.3), -90.0, wall)
		_prop("wall.glb", Vector3(-3.6, 0.0, -3.5 + i * 2.3), 90.0, wall)

	# Лестница к трону.
	_prop("stairs-wide-stone.glb", Vector3(0.0, 0.0, -1.15), 0.0, Color(0.5, 0.49, 0.52))

	# Ковровая дорожка от трона к зрителю.
	var carpet := Node3D.new()
	add_child(carpet)
	_box(carpet, Vector3(1.8, 0.04, 5.6), Vector3(0.0, 0.02, 1.6),
		_toon_material(Color(0.28, 0.07, 0.11)))

	# Трон: каменный подиум + красное кресло с золотым навершием (по центру).
	var throne := Node3D.new()
	throne.position = Vector3(0.0, 0.0, -2.6)
	add_child(throne)
	var red := _toon_material(Color(0.3, 0.08, 0.12))
	var gold := _toon_material(Color(0.52, 0.4, 0.15))
	_box(throne, Vector3(3.2, 0.4, 2.2), Vector3(0, 0.2, 0), stone)
	_box(throne, Vector3(1.4, 0.5, 1.2), Vector3(0, 0.65, 0), red)
	_box(throne, Vector3(1.4, 2.4, 0.35), Vector3(0, 1.85, -0.55), red)
	_box(throne, Vector3(0.3, 0.9, 1.2), Vector3(-0.75, 1.05, 0), red)
	_box(throne, Vector3(0.3, 0.9, 1.2), Vector3(0.75, 1.05, 0), red)
	_box(throne, Vector3(1.55, 0.25, 0.45), Vector3(0, 3.1, -0.55), gold)

	# Колонны со знамёнами по бокам трона.
	_prop("pillar-stone.glb", Vector3(-2.7, 0.0, -2.6), 0.0, Color(0.52, 0.51, 0.55))
	_prop("pillar-stone.glb", Vector3(2.7, 0.0, -2.6), 0.0, Color(0.52, 0.51, 0.55))
	_prop("banner-red.glb", Vector3(-2.7, 1.6, -2.2), 0.0, Color(0.5, 0.16, 0.2))
	_prop("banner-red.glb", Vector3(2.7, 1.6, -2.2), 0.0, Color(0.5, 0.16, 0.2))

	# Фонари вдоль дорожки + кривое дерево (жутко-милая деталь Fran Bow).
	_prop("lantern.glb", Vector3(1.7, 0.0, 1.4), 0.0, Color(0.25, 0.22, 0.26))
	_prop("lantern.glb", Vector3(-1.7, 0.0, 1.4), 0.0, Color(0.25, 0.22, 0.26))
	_prop("lantern.glb", Vector3(1.7, 0.0, -0.6), 0.0, Color(0.25, 0.22, 0.26))
	_prop("lantern.glb", Vector3(-1.7, 0.0, -0.6), 0.0, Color(0.25, 0.22, 0.26))
	_prop("tree-crooked.glb", Vector3(2.9, 0.0, -3.6), 0.0, Color(0.24, 0.3, 0.2))


## --- Зеркало (SubViewport + «плывущее» отражение) ----------------------

func _setup_mirror() -> void:
	var mirror_view := SubViewport.new()
	mirror_view.size = Vector2i(512, 640)
	mirror_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(mirror_view)

	var mirror_cam := Camera3D.new()
	mirror_cam.fov = 55
	mirror_view.add_child(mirror_cam)
	mirror_cam.position = Vector3(4.4, 1.6, 0.6)
	mirror_cam.rotation.y = PI / 2

	_mirror_mat = ShaderMaterial.new()
	_mirror_mat.shader = MIRROR_SHADER
	# Явно задаём параметры — иначе get_shader_parameter вернёт Nil (источник краша)
	_mirror_mat.set_shader_parameter("invert_amount", 0.0)
	_mirror_mat.set_shader_parameter("distortion_strength", 0.015)
	_mirror_mat.set_shader_parameter("distort_speed", 1.0)
	var tex := ViewportTexture.new()
	tex.viewport_path = mirror_view.get_path()
	_mirror_mat.set_shader_parameter("reflection", tex)

	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 3.4)
	var screen := MeshInstance3D.new()
	screen.mesh = quad
	screen.material_override = _mirror_mat
	screen.position = Vector3(3.55, 1.7, 0.6)
	screen.rotation.y = PI / 2
	add_child(screen)

	var frame_quad := QuadMesh.new()
	frame_quad.size = Vector2(2.9, 3.7)
	var frame := MeshInstance3D.new()
	frame.mesh = frame_quad
	frame.material_override = _toon_material(Color(0.16, 0.12, 0.14))
	frame.position = Vector3(3.59, 1.7, 0.6)
	frame.rotation.y = PI / 2
	add_child(frame)


func _setup_camera() -> void:
	# Портретный кадр: камера по центральной оси, смотрит в глубину зала.
	var cam := Camera3D.new()
	cam.fov = 55
	cam.position = Vector3(0.0, 2.7, 6.6)
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.2, -0.8))
	cam.current = true


## --- UI кликера --------------------------------------------------------

func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_counter_label = Label.new()
	_counter_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_counter_label.position = Vector2(-300, 24)
	_counter_label.size = Vector2(600, 56)
	_counter_label.add_theme_font_size_override("font_size", 36)
	_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter_label.text = "Благосклонность: 0"
	layer.add_child(_counter_label)

	_rate_label = Label.new()
	_rate_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_rate_label.position = Vector2(-300, 84)
	_rate_label.size = Vector2(600, 40)
	_rate_label.add_theme_font_size_override("font_size", 22)
	_rate_label.modulate = Color(0.7, 0.65, 0.75)
	_rate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_rate_label)

	_story_label = Label.new()
	_story_label.visible = false
	_story_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_story_label.position = Vector2(-330, -500)
	_story_label.size = Vector2(660, 150)
	_story_label.add_theme_font_size_override("font_size", 24)
	_story_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_story_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_story_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(_story_label)

	_upgrades_panel = GridContainer.new()
	_upgrades_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_upgrades_panel.position = Vector2(20, -290)
	_upgrades_panel.add_theme_constant_override("h_separation", 12)
	_upgrades_panel.add_theme_constant_override("v_separation", 12)
	_upgrades_panel.columns = 2
	layer.add_child(_upgrades_panel)
	for id in GameState.UPGRADES:
		var button := Button.new()
		button.pressed.connect(func() -> void:
			if GameState.buy(id):
				_play_sfx("coins"))
		_upgrades_panel.add_child(button)
		_buttons[id] = button

	var zazerkalie := Button.new()
	zazerkalie.text = "Зазеркалье: ВЫКЛ"
	zazerkalie.position = Vector2(24, 24)
	zazerkalie.pressed.connect(func() -> void:
		var cur: Variant = _mirror_mat.get_shader_parameter("invert_amount")
		var on := (0.0 if cur == null else float(cur)) < 0.5
		_mirror_mat.set_shader_parameter("invert_amount", 1.0 if on else 0.0)
		_env.background_color = Color(0.45, 0.28, 0.5) if on else Color(0.05, 0.04, 0.075)
		zazerkalie.text = "Зазеркалье: ВКЛ" if on else "Зазеркалье: ВЫКЛ")
	layer.add_child(zazerkalie)

	var flat := Button.new()
	flat.text = "2D-режим"
	flat.position = Vector2(24, 76)
	flat.pressed.connect(
		func() -> void: get_tree().change_scene_to_file("res://scenes/main.tscn"))
	layer.add_child(flat)

	# --- Настройки звука ---
	var gear := Button.new()
	gear.text = "Настройки звука"
	gear.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	gear.grow_horizontal = Control.GROW_DIRECTION_BEGIN # расти влево, не за экран
	layer.add_child(gear)

	var panel := PanelContainer.new()
	panel.visible = false
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 58)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	layer.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Настройки"
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	for row in [["Общая громкость", "Master"], ["Музыка", "Music"], ["Эффекты", "SFX"]]:
		var lbl := Label.new()
		lbl.text = row[0]
		lbl.add_theme_font_size_override("font_size", 17)
		vbox.add_child(lbl)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = _bus_volume(row[1])
		slider.custom_minimum_size = Vector2(250, 24)
		slider.value_changed.connect(func(v: float) -> void:
			_set_bus_volume(row[1], v)
			_save_settings())
		vbox.add_child(slider)

	gear.pressed.connect(func() -> void: panel.visible = not panel.visible)


func _update_ui() -> void:
	_counter_label.text = "Благосклонность: %s" % _fmt(GameState.favor)
	_rate_label.text = "%s/сек · сила поклона +%d" % [_fmt(GameState.auto_rate()), GameState.tap_power()]
	for id in _buttons:
		var u: Dictionary = GameState.UPGRADES[id]
		var lvl := int(GameState.levels.get(id, 0))
		var bonus := ""
		if int(u["tap"]) > 0:
			bonus = "+%d к поклону" % int(u["tap"])
		if float(u["auto"]) > 0.0:
			bonus = "+%s/сек" % _fmt(float(u["auto"]))
		var level_part := "" if lvl == 0 else "  ур.%d" % lvl
		var button: Button = _buttons[id]
		button.text = "%s%s\n%s  ·  %s" % [u["name"], level_part, bonus, _fmt(GameState.cost_of(id))]
		button.disabled = not GameState.can_buy(id)


func _show_story(text: String) -> void:
	_story_label.text = "«%s»" % text
	_story_label.visible = true
	_story_label.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_story_label, "modulate:a", 1.0, 0.6)
	tween.tween_interval(5.0)
	tween.tween_property(_story_label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func() -> void: _story_label.visible = false)


## 1234 → "1.23K", 5600000 → "5.60M" — чтобы цифры не уезжали за экран.
func _fmt(n: float) -> String:
	var suffixes := ["", "K", "M", "B", "T", "Qa"]
	var i := 0
	while n >= 1000.0 and i < suffixes.size() - 1:
		n /= 1000.0
		i += 1
	if i == 0:
		return str(int(n))
	return "%.2f%s" % [n, suffixes[i]]


## ================= WELWITSCHIA GOTH: задник из веб-сцены =================
## Мёртвый лес над стенами, каменные плиты, канделябры с мерцанием,
## бабочки с полупрозрачными крыльями, падающие лепестки.

func _setup_welwitschia() -> void:
	# Каменные плиты поверх пола (у каждой свой оттенок и поворот)
	var slab_a := _toon_material(Color(0.21, 0.19, 0.26))
	var slab_b := _toon_material(Color(0.17, 0.15, 0.22))
	for i in 36:
		var slab := BoxMesh.new()
		slab.size = Vector3(1.3, 0.08, 0.95)
		var a := randf() * TAU
		var r := randf_range(2.6, 11.0)
		var mi := _mesh(self, slab, slab_a if i % 5 == 0 else slab_b,
			Vector3(cos(a) * r, 0.02 + randf() * 0.04, sin(a) * r - 1.0))
		mi.rotation.y = randf() * PI

	# Мёртвый искривлённый лес за стенами — кроны видны над арками
	var spots := [
		Vector3(-6.5, 0, -7.0), Vector3(0.0, 0, -9.5), Vector3(6.5, 0, -7.5),
		Vector3(-9.0, 0, -3.0), Vector3(9.5, 0, -3.5), Vector3(-3.4, 0, -10.0),
	]
	for pos in spots:
		_make_tree(pos, randf_range(4.5, 6.5))

	# Мышьяково-зелёное свечение из чащи
	var green := OmniLight3D.new()
	green.light_color = Color(0.45, 0.55, 0.3)
	green.omni_range = 11.0
	green.light_energy = 1.5
	green.position = Vector3(-5.5, 2.6, -7.5)
	add_child(green)

	# Канделябры со свечами вдоль дорожки
	_make_candelabra(Vector3(-1.9, 0.1, 0.8), true)
	_make_candelabra(Vector3(1.9, 0.1, 0.2), true)

	# Бабочки
	for i in 5:
		_make_butterfly(Vector3(randf_range(-3.0, 3.0), randf_range(1.2, 2.4), randf_range(-3.0, 1.5)))

	# Падающие лепестки и опавшие листья
	if _tex_petal == null:
		_tex_petal = _make_petal_texture()
	if _tex_leaf == null:
		_tex_leaf = _make_leaf_texture()
	_setup_petals()
	_setup_fallen_leaves()


## Искривлённый ствол из сегментов + ветви
func _make_tree(pos: Vector3, h: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = randf() * TAU
	add_child(root)
	var mat := _toon_material(Color(0.2, 0.15, 0.23))
	var x := 0.0
	var y := 0.0
	var r := 0.13 + h * 0.018
	for i in 5:
		var seg_h := h / 5.0
		var tilt := randf_range(-0.3, 0.3)
		var seg := CylinderMesh.new()
		seg.top_radius = r * 0.72
		seg.bottom_radius = r
		seg.height = seg_h
		var mi := _mesh(root, seg, mat, Vector3(x, y + seg_h / 2.0, 0.0))
		mi.rotation.z = tilt
		x += sin(tilt) * seg_h * 0.8
		y += seg_h
		r *= 0.72
	for b in 3:
		var bl := randf_range(0.6, 1.1)
		var branch := CylinderMesh.new()
		branch.top_radius = 0.012
		branch.bottom_radius = 0.045
		branch.height = bl
		var mi := _mesh(root, branch, mat, Vector3(x, y * randf_range(0.5, 0.9), 0.0))
		mi.rotation.z = randf_range(0.9, 1.5)
		mi.rotation.y = randf() * TAU


func _make_candelabra(pos: Vector3, with_light: bool) -> void:
	var g := Node3D.new()
	g.position = pos
	add_child(g)
	var brass := _toon_material(Color(0.55, 0.44, 0.24))
	var candle_mat := _toon_material(Color(0.82, 0.77, 0.68))
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.albedo_color = Color(1.0, 0.83, 0.5)

	var stem := CylinderMesh.new()
	stem.top_radius = 0.04
	stem.bottom_radius = 0.08
	stem.height = 1.5
	_mesh(g, stem, brass, Vector3(0, 0.75, 0))
	var base := CylinderMesh.new()
	base.top_radius = 0.02
	base.bottom_radius = 0.2
	base.height = 0.16
	_mesh(g, base, brass, Vector3(0, 0.08, 0))
	var bar := BoxMesh.new()
	bar.size = Vector3(0.72, 0.05, 0.05)
	_mesh(g, bar, brass, Vector3(0, 1.52, 0))
	for cx in [-0.3, 0.0, 0.3]:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.03
		cm.bottom_radius = 0.035
		cm.height = 0.34
		_mesh(g, cm, candle_mat, Vector3(cx, 1.7, 0))
		var fm := CylinderMesh.new()
		fm.top_radius = 0.0
		fm.bottom_radius = 0.03
		fm.height = 0.12
		_mesh(g, fm, flame_mat, Vector3(cx, 1.93, 0))
	if with_light:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.75, 0.45)
		l.omni_range = 6.0
		l.light_energy = 1.3
		l.position = Vector3(0, 1.9, 0)
		g.add_child(l)
		_candle_lights.append({"light": l, "base": 1.3, "phase": randf() * TAU})


func _make_butterfly(pos: Vector3) -> void:
	if _tex_wing == null:
		_tex_wing = _make_wing_texture()
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _tex_wing
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wing := QuadMesh.new()
	wing.size = Vector2(0.26, 0.26)
	var lw := Node3D.new()
	root.add_child(lw)
	_mesh(lw, wing, mat, Vector3(-0.015, 0.05, 0))
	var rw := Node3D.new()
	root.add_child(rw)
	var rmi := _mesh(rw, wing, mat, Vector3(0.015, 0.05, 0))
	rmi.scale = Vector3(-1, 1, 1) # зеркальное правое крыло
	# Тельце и усики
	var body := CapsuleMesh.new()
	body.radius = 0.018
	body.height = 0.18
	_mesh(root, body, _toon_material(Color(0.1, 0.08, 0.12)), Vector3(0, 0.02, 0))
	var ant_mat := _toon_material(Color(0.1, 0.08, 0.12))
	for side in [-1.0, 1.0]:
		var ant := CylinderMesh.new()
		ant.top_radius = 0.002
		ant.bottom_radius = 0.004
		ant.height = 0.09
		var ami := _mesh(root, ant, ant_mat, Vector3(side * 0.012, 0.13, 0))
		ami.rotation.z = side * 0.5
	_butterflies.append({
		"root": root, "lw": lw, "rw": rw, "phase": randf() * TAU,
		"orbit": randf() < 0.4, "home": pos, "r": randf_range(0.5, 1.2),
	})


## Крыло: силуэт из двух «лопастей», прожилки от корня, тёмная кромка, пятна
func _make_wing_texture() -> ImageTexture:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var root_x := 10.0
	var root_y := 64.0
	for y in size:
		for x in size:
			var fx := float(x)
			var fy := float(y)
			var d_fore := pow((fx - 62.0) / 54.0, 2.0) + pow((fy - 42.0) / 40.0, 2.0)
			var d_hind := pow((fx - 44.0) / 38.0, 2.0) + pow((fy - 94.0) / 32.0, 2.0)
			if d_fore > 1.0 and d_hind > 1.0:
				continue
			var dist := sqrt(pow(fx - root_x, 2.0) + pow(fy - root_y, 2.0)) / 110.0
			var col := Color(0.6 - 0.28 * dist, 0.38 - 0.2 * dist, 0.75 - 0.32 * dist, 0.92)
			var vein := false
			for ang in [-0.55, -0.2, 0.15, 0.5]:
				var vx := cos(ang)
				var vy := sin(ang)
				var t := (fx - root_x) * vx + (fy - root_y) * vy
				if t > 0.0:
					var px := root_x + vx * t
					var py := root_y + vy * t
					if Vector2(fx - px, fy - py).length() < 1.6:
						vein = true
						break
			if vein:
				col = Color(0.15, 0.1, 0.2, 0.95)
			elif d_fore > 0.86 or d_hind > 0.82:
				col = Color(0.2, 0.12, 0.26, 0.95)
			if Vector2(fx - 86.0, fy - 34.0).length() < 5.0 \
					or Vector2(fx - 66.0, fy - 104.0).length() < 4.0:
				col = Color(0.85, 0.78, 0.55, 0.95)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## Лепесток: капля с тёмными загнутыми краями
func _make_petal_texture() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var fx := (float(x) / size - 0.5) * 2.0
			var fy := (float(y) / size - 0.5) * 2.0
			var belly := pow(fx, 2.0) / 0.3 + pow(fy - 0.2, 2.0) / 0.75
			var tip := absf(fx) < 0.1 + 0.13 * (-fy) and fy < -0.05 and fy > -1.0
			if belly <= 1.0 or tip:
				var shade := clampf(0.85 + 0.2 * fy, 0.55, 1.0)
				var col := Color(0.42 * shade + 0.05, 0.05 * shade + 0.01, 0.1 * shade + 0.02, 0.96)
				if absf(fx) > 0.5:
					col = col.darkened(0.4)
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## Опавший лист: ромб с жилкой и подгоревшими краями
func _make_leaf_texture() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var fx := (float(x) / size - 0.5) * 2.0
			var fy := (float(y) / size - 0.5) * 2.0
			var w := 0.42 * (1.0 - absf(fy))
			if absf(fx) <= w:
				var col := Color(0.36, 0.3, 0.14)
				if fy < 0.0:
					col = Color(0.42, 0.34, 0.13)
				if absf(fx) > w * 0.62:
					col = col.darkened(0.3)
				elif absf(fx) < 0.04:
					col = Color(0.24, 0.2, 0.1)
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


func _setup_petals() -> void:
	_petal_mm = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(0.075, 0.11)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_texture = _tex_petal
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	pm.alpha_scissor_threshold = 0.5
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = pm
	mm.mesh = quad
	mm.instance_count = 90
	_petal_mm.multimesh = mm
	add_child(_petal_mm)
	for i in 90:
		var p := {
			"x": randf_range(-10.0, 10.0), "y": randf_range(0.5, 8.0), "z": randf_range(-9.0, 5.0),
			"speed": randf_range(0.12, 0.3), "sway": randf_range(0.3, 0.8),
			"phase": randf() * TAU, "spin": randf() * TAU, "rspeed": randf_range(-0.8, 0.8),
		}
		_petals.append(p)
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(p["x"], p["y"], p["z"])))


## Статичные опавшие листья — разбросаны по плитам
func _setup_fallen_leaves() -> void:
	var leaf_mm := MultiMeshInstance3D.new()
	var lmm := MultiMesh.new()
	lmm.transform_format = MultiMesh.TRANSFORM_3D
	lmm.use_colors = true
	var lquad := QuadMesh.new()
	lquad.size = Vector2(0.1, 0.14)
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_texture = _tex_leaf
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	lm.alpha_scissor_threshold = 0.5
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	lquad.material = lm
	lmm.mesh = lquad
	lmm.instance_count = 70
	leaf_mm.multimesh = lmm
	add_child(leaf_mm)
	var leaf_colors := [
		Color(1.15, 1.0, 0.85), Color(0.8, 1.1, 0.7),
		Color(1.1, 0.75, 0.6), Color(0.75, 0.7, 0.65),
	]
	for i in 70:
		var a := randf() * TAU
		var r := randf_range(1.6, 10.5)
		var basis := Basis(Vector3.UP, randf() * TAU) \
			.rotated(Vector3.RIGHT, -PI / 2.0 + randf_range(-0.25, 0.25))
		var t := Transform3D(basis, Vector3(cos(a) * r, 0.06 + randf() * 0.05, sin(a) * r - 1.0))
		lmm.set_instance_transform(i, t)
		lmm.set_instance_color(i, leaf_colors[i % 4] * randf_range(0.8, 1.2))


func _update_welwitschia(delta: float) -> void:
	_welw_t += delta
	# «Дыхание» волшебника: у модели нет анимаций, оживляем процедурно —
	# едва заметное покачивание и приподнимание на вдохе
	if _wizard:
		_wizard.rotation.z = sin(_welw_t * 0.8) * 0.025
		_wizard.position.y = absf(sin(_welw_t * 1.1)) * 0.03
	# мерцание свечей
	for c in _candle_lights:
		c["light"].light_energy = c["base"] * (
			0.85 + 0.1 * sin(_welw_t * 10.0 + c["phase"])
			+ 0.05 * sin(_welw_t * 23.0 + c["phase"] * 2.0))
	# бабочки: мягкий трепет с «проплывами», часть кружит
	for b in _butterflies:
		var glide := 0.45 + 0.55 * absf(sin(_welw_t * 0.7 + b["phase"] * 0.3))
		var flap := sin(_welw_t * 6.0 + b["phase"]) * glide
		b["lw"].rotation.y = 0.6 * flap
		b["rw"].rotation.y = -0.6 * flap
		var bob: float = sin(_welw_t * 1.1 + b["phase"]) * 0.08
		if b["orbit"]:
			var a: float = _welw_t * 0.35 + b["phase"]
			b["root"].position = b["home"] + Vector3(
				cos(a) * b["r"], bob, sin(a) * b["r"])
			b["root"].rotation.y = -a + PI / 2.0
	# падающие лепестки
	if _petal_mm:
		var mm := _petal_mm.multimesh
		for i in _petals.size():
			var p: Dictionary = _petals[i]
			p["y"] -= p["speed"] * delta
			p["x"] += sin(_welw_t * p["sway"] + p["phase"]) * 0.3 * delta
			if p["y"] < 0.12:
				p["y"] = randf_range(5.0, 8.0)
				p["x"] = randf_range(-10.0, 10.0)
				p["z"] = randf_range(-9.0, 5.0)
			p["spin"] += p["rspeed"] * delta
			var basis := Basis(Vector3.UP, p["spin"])
			mm.set_instance_transform(i, Transform3D(basis, Vector3(p["x"], p["y"], p["z"])))


## ================= ЗВУК =================
## Шины: Master (всё) → Music (главная тема) и SFX (эффекты).
## Тема: theme.wav (трек пользователя). Если файла нет — синтез-дрон.
## Эффекты: cloth1-4.ogg (Kenney CC0), coins.ogg, creak.ogg.
func _setup_audio() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")

	var theme_path := "res://assets/audio/theme.wav"
	var a := AudioStreamPlayer.new()
	a.bus = "Music"
	if FileAccess.file_exists(theme_path):
		a.stream = load(theme_path) # главная тема: Vaanrile — Drowning Into Despair
	else:
		a.stream = _make_ambient_stream() # запасной синтез-дрон
	a.volume_db = -8.0
	add_child(a)
	a.finished.connect(a.play) # повтор по окончании (луп)
	a.play()

	for i in range(1, 5):
		var cloth_path := "res://assets/audio/cloth%d.ogg" % i
		if FileAccess.file_exists(cloth_path):
			var cp := AudioStreamPlayer.new()
			cp.stream = load(cloth_path)
			cp.bus = "SFX"
			cp.volume_db = -8.0
			add_child(cp)
			_tap_players.append(cp)
	for pair in [["coins", -6.0], ["creak", -4.0]]:
		var path := "res://assets/audio/%s.ogg" % pair[0]
		if FileAccess.file_exists(path):
			var p := AudioStreamPlayer.new()
			p.stream = load(path)
			p.bus = "SFX"
			p.volume_db = pair[1]
			add_child(p)
			_sfx[pair[0]] = p

	_apply_saved_volumes()


func _ensure_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return idx


func _bus_volume(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1 or AudioServer.is_bus_mute(idx):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


func _set_bus_volume(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, v <= 0.001)
	if v > 0.001:
		AudioServer.set_bus_volume_db(idx, linear_to_db(v))


func _apply_saved_volumes() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for bus_name in ["Master", "Music", "SFX"]:
			_set_bus_volume(bus_name, float(cfg.get_value("audio", bus_name.to_lower(), 1.0)))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	for bus_name in ["Master", "Music", "SFX"]:
		cfg.set_value("audio", bus_name.to_lower(), _bus_volume(bus_name))
	cfg.save(SETTINGS_PATH)


## Генерируем 24-секундный бесшовный луп: все частоты — целые герцы,
## поэтому период ровно укладывается в длину лупа и стыка не слышно.
func _make_ambient_stream() -> AudioStreamWAV:
	var rate := 22050
	var seconds := 24.0
	var n := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		v += sin(TAU * 55.0 * t)          # низкий гул
		v += 0.7 * sin(TAU * 56.0 * t)    # биения 1 Гц — «тревожность»
		v += 0.5 * sin(TAU * 82.0 * t)
		v += 0.35 * sin(TAU * 41.0 * t)
		var swell := 0.6 + 0.4 * sin(TAU * t / seconds)      # один «прилив» за луп
		var tremble := 1.0 + 0.15 * sin(TAU * 3.0 * t)       # едва заметная дрожь
		v *= 0.22 * swell * tremble
		var s := int(clampf(v, -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	wav.data = data
	return wav


func _play_sfx(key: String) -> void:
	if key == "tap":
		if not _tap_players.is_empty():
			_tap_players.pick_random().play()
	elif _sfx.has(key):
		_sfx[key].play()


## ================= РАБ-МОЛЯЩИЙСЯ =================
## У модели нет рига (один жёсткий меш), поэтому коленопреклонение —
## анимация всей фигуры: плавно опускается, кланяется, качается в молитве.

func _setup_slave() -> void:
	var scene: PackedScene = load(SLAVE_GLB)
	if scene == null:
		push_warning("Модель раба не найдена: " + SLAVE_GLB)
		return
	var root: Node3D = scene.instantiate()
	root.position = Vector3(-0.9, 0.0, -0.4) # на ковре, левее челика
	root.rotation.y = 0.0 # лицом к трону (-Z)
	add_child(root)
	_fit_model(root, 1.55)
	_calm_materials(root)
	_slave_base_y = root.position.y
	_slave = root


func _update_slave(delta: float) -> void:
	if _slave == null:
		return
	# Цикл 14 с: стоит → плавно на колени (3–6) → молится (6–11) → встаёт (11–14)
	_slave_t = fmod(_slave_t + delta, 14.0)
	var t := _slave_t
	var kneel := 0.0
	if t < 3.0:
		kneel = 0.0
	elif t < 6.0:
		kneel = smoothstep(3.0, 6.0, t)
	elif t < 11.0:
		kneel = 1.0
	else:
		kneel = 1.0 - smoothstep(11.0, 14.0, t)
	# опускание на колени + наклон вперёд
	_slave.position.y = _slave_base_y - kneel * 0.4
	# молитва: мерные покачивания корпусом, пока стоит на коленях
	var pray := sin(t * 1.6) * 0.08 * kneel
	_slave.rotation.x = -kneel * 0.3 + pray
	# лёгкое дыхание в любой позе
	_slave.rotation.z = sin(_slave_t * 1.2) * 0.02


## Приглушаем PBR Meshy-моделей: без бликов и прозрачности — иначе на тёмной
## сцене глянцевые пятна выглядят как «застрявшие текстуры»
func _calm_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(i)
				if mat is BaseMaterial3D:
					var b := mat as BaseMaterial3D
					b.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
					b.roughness = 1.0
					b.metallic = 0.0
	for child in node.get_children():
		_calm_materials(child)
