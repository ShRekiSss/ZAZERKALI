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

## Через сколько секунд без тапов челик сам делает поклон.
const IDLE_BOW_EVERY := 2.5

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
	_setup_wizard()
	_chelik = _make_character(Color(0.72, 0.64, 0.49))
	_chelik.position = Vector3(0.8, 0.0, 0.0)
	_setup_mirror()
	_setup_camera()
	_setup_ui()
	GameState.changed.connect(_update_ui)
	GameState.story_line.connect(_show_story)
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
			if _chelik_anim == null:
				_root_bow(0.7, 1.0, 0.85) # медленный глубокий поклон наклоном
			elif not _chelik_anim.current_animation == _bow_anim:
				_play_bow()
	# Запасной визуал поклона, если анимации в модели нет.
	if _chelik_anim == null and not _root_bowing:
		_bow_t += delta
		_chelik.rotation.z = 0.5 * absf(sin(_bow_t * 1.6))


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
	if _chelik_anim:
		_play_bow()
	else:
		_root_bow(0.12, 0.45, 1.1) # быстрый резкий поклон


## --- Поклоны -----------------------------------------------------------

func _play_bow() -> void:
	if _chelik_anim == null:
		return
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
	var tween := create_tween()
	tween.tween_property(_chelik, "rotation:z", depth, down) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.05)
	tween.tween_property(_chelik, "rotation:z", 0.0, up) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void: _root_bowing = false)


## --- Персонажи ---------------------------------------------------------

func _setup_wizard() -> void:
	# Великий Волшебник — Meshy-модель пользователя.
	var scene: PackedScene = load(WIZARD_GLB)
	if scene:
		var wizard: Node3D = scene.instantiate()
		add_child(wizard)
		wizard.position = Vector3(-2.2, 0.0, -1.9)
		wizard.rotation.y = PI / 2 # лицом к челику (+X)
		_fit_model(wizard, 2.3)
		_wizard = wizard
		var player := _find_animation_player(wizard)
		if player and player.get_animation_list().size() > 0:
			var first := player.get_animation_list()[0]
			player.get_animation(first).loop_mode = Animation.LOOP_LINEAR
			player.play(first)
		return
	# Запасной волшебник из примитивов.
	var fallback := Node3D.new()
	fallback.position = Vector3(-2.2, 0.0, -0.5)
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
		root.position = Vector3(0.8, 0.0, 0.0)
		root.rotation.y = -PI / 2 # лицом к трону (-X); спиной — поменять знак
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
		root.position = Vector3(0.8, 0.0, 0.0)
		root.rotation.y = -PI / 2
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
	_env.background_color = Color(0.10, 0.086, 0.12)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.55, 0.5, 0.6)
	_env.ambient_light_energy = 0.35
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)


func _setup_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(24, 24)
	_mesh(self, plane, _toon_material(Color(0.18, 0.22, 0.16)), Vector3.ZERO)


## Тронный зал: трон на возвышении, ковровая дорожка, колонны, стены, свет.
func _setup_throne_area() -> void:
	var stone := _toon_material(Color(0.45, 0.44, 0.48))
	var wall := Color(0.33, 0.28, 0.36)

	# Задник: арки-стена позади трона.
	for i in 4:
		_prop("wall-arch.glb", Vector3(-4.6 + i * 2.3, 0.0, -4.2), 0.0, wall)

	# Боковые стены зала (создают «коробку» помещения на камере).
	for i in 4:
		_prop("wall.glb", Vector3(2.9, 0.0, -3.0 + i * 2.0), -90.0, wall)
		_prop("wall.glb", Vector3(-5.7, 0.0, -3.0 + i * 2.0), 90.0, wall)

	# Лестница к трону + площадка.
	_prop("stairs-wide-stone.glb", Vector3(-2.2, 0.0, -1.15), 0.0, Color(0.5, 0.49, 0.52))

	# Ковровая дорожка от трона к зрителю.
	var carpet := Node3D.new()
	add_child(carpet)
	_box(carpet, Vector3(1.8, 0.04, 5.2), Vector3(-1.4, 0.02, 1.6),
		_toon_material(Color(0.42, 0.13, 0.18)))

	# Трон: каменный подиум + красное кресло с золотым навершием.
	var throne := Node3D.new()
	throne.position = Vector3(-2.2, 0.0, -2.6)
	add_child(throne)
	var red := _toon_material(Color(0.42, 0.13, 0.18))
	var gold := _toon_material(Color(0.85, 0.68, 0.3))
	_box(throne, Vector3(3.2, 0.4, 2.2), Vector3(0, 0.2, 0), stone)
	_box(throne, Vector3(1.4, 0.5, 1.2), Vector3(0, 0.65, 0), red)
	_box(throne, Vector3(1.4, 2.4, 0.35), Vector3(0, 1.85, -0.55), red)
	_box(throne, Vector3(0.3, 0.9, 1.2), Vector3(-0.75, 1.05, 0), red)
	_box(throne, Vector3(0.3, 0.9, 1.2), Vector3(0.75, 1.05, 0), red)
	_box(throne, Vector3(1.55, 0.25, 0.45), Vector3(0, 3.1, -0.55), gold)

	# Колонны со знамёнами по бокам трона.
	_prop("pillar-stone.glb", Vector3(-4.4, 0.0, -2.6), 0.0, Color(0.52, 0.51, 0.55))
	_prop("pillar-stone.glb", Vector3(0.0, 0.0, -2.6), 0.0, Color(0.52, 0.51, 0.55))
	_prop("banner-red.glb", Vector3(-4.4, 1.6, -2.2), 0.0, Color(0.5, 0.16, 0.2))
	_prop("banner-red.glb", Vector3(0.0, 1.6, -2.2), 0.0, Color(0.5, 0.16, 0.2))

	# Фонари вдоль дорожки + кривое дерево (жутко-милая деталь Fran Bow).
	_prop("lantern.glb", Vector3(1.8, 0.0, 1.8), 0.0, Color(0.25, 0.22, 0.26))
	_prop("lantern.glb", Vector3(-3.9, 0.0, 1.4), 0.0, Color(0.25, 0.22, 0.26))
	_prop("lantern.glb", Vector3(1.8, 0.0, -0.4), 0.0, Color(0.25, 0.22, 0.26))
	_prop("lantern.glb", Vector3(-3.9, 0.0, -0.8), 0.0, Color(0.25, 0.22, 0.26))
	_prop("tree-crooked.glb", Vector3(2.6, 0.0, -3.4), 0.0, Color(0.24, 0.3, 0.2))


## --- Зеркало (SubViewport + «плывущее» отражение) ----------------------

func _setup_mirror() -> void:
	var mirror_view := SubViewport.new()
	mirror_view.size = Vector2i(512, 640)
	mirror_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(mirror_view)

	var mirror_cam := Camera3D.new()
	mirror_cam.fov = 55
	mirror_view.add_child(mirror_cam)
	mirror_cam.position = Vector3(4.6, 1.6, 0.0)
	mirror_cam.rotation.y = PI / 2

	_mirror_mat = ShaderMaterial.new()
	_mirror_mat.shader = MIRROR_SHADER
	var tex := ViewportTexture.new()
	tex.viewport_path = mirror_view.get_path()
	_mirror_mat.set_shader_parameter("reflection", tex)

	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 3.4)
	var screen := MeshInstance3D.new()
	screen.mesh = quad
	screen.material_override = _mirror_mat
	screen.position = Vector3(3.0, 1.7, 0.0)
	screen.rotation.y = PI / 2
	add_child(screen)

	var frame_quad := QuadMesh.new()
	frame_quad.size = Vector2(2.9, 3.7)
	var frame := MeshInstance3D.new()
	frame.mesh = frame_quad
	frame.material_override = _toon_material(Color(0.16, 0.12, 0.14))
	frame.position = Vector3(3.04, 1.7, 0.0)
	frame.rotation.y = PI / 2
	add_child(frame)


func _setup_camera() -> void:
	var cam := Camera3D.new()
	cam.fov = 55
	cam.position = Vector3(-2.4, 2.8, 5.4)
	add_child(cam)
	cam.look_at(Vector3(0.6, 1.3, -0.8))
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
		button.pressed.connect(GameState.buy.bind(id))
		_upgrades_panel.add_child(button)
		_buttons[id] = button

	var zazerkalie := Button.new()
	zazerkalie.text = "Зазеркалье: ВЫКЛ"
	zazerkalie.position = Vector2(24, 24)
	zazerkalie.pressed.connect(func() -> void:
		var on: bool = _mirror_mat.get_shader_parameter("invert_amount") < 0.5
		_mirror_mat.set_shader_parameter("invert_amount", 1.0 if on else 0.0)
		_env.background_color = Color(0.55, 0.35, 0.6) if on else Color(0.10, 0.086, 0.12)
		zazerkalie.text = "Зазеркалье: ВКЛ" if on else "Зазеркалье: ВЫКЛ")
	layer.add_child(zazerkalie)

	var flat := Button.new()
	flat.text = "2D-режим"
	flat.position = Vector2(24, 76)
	flat.pressed.connect(
		func() -> void: get_tree().change_scene_to_file("res://scenes/main.tscn"))
	layer.add_child(flat)


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
