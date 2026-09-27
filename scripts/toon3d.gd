extends Node3D
## 3D-демо: Toon Shader + зеркало (SubViewport + вторая камера + «плывущий» дисторшн).
## Открывается кнопкой «3D-зеркало» из кликера, или F6 при открытом toon3d.tscn.
## Вся сцена собирается кодом — все размеры и позиции правятся константами ниже.

const TOON_SHADER := preload("res://assets/shaders/toon.gdshader")
const MIRROR_SHADER := preload("res://assets/shaders/mirror.gdshader")
## Пак Kenney (CC0): модели подхватываются отсюда.
const MODELS_DIR := "res://assets/models/Models/GLB format/"
## Meshy-модели пользователя: волшебник (риг + анимации) и челик.
const WIZARD_GLB := "res://assets/models/meshy/wizard_meshy.glb"
const CHELIK_GLB := "res://assets/models/meshy/chelik_meshy.glb"

var _chelik: Node3D
var _chelik_anim: AnimationPlayer
var _wizard: Node3D
var _mirror_mat: ShaderMaterial
var _env: Environment
var _bow_t := 0.0
## Текстуры челика грузим в рантайме (load), чтобы их отсутствие
## не ломало загрузку всей сцены.
var _robe_tex: Texture2D
var _face_tex: Texture2D


func _ready() -> void:
	_robe_tex = load("res://assets/textures/chelik_robe.png")
	_face_tex = load("res://assets/textures/chelik_face.png")
	_setup_environment()
	_setup_ground()
	_setup_throne_area()
	_setup_wizard()
	_chelik = _make_character(Color(0.72, 0.64, 0.49)) # пергаментный челик
	_chelik.position = Vector3(0.8, 0.0, 0.0)
	_setup_mirror()
	_setup_camera()
	_setup_ui()
	# Диагностика для headless-теста (godot --headless): видно, что загрузилось.
	if DisplayServer.get_name() == "headless":
		var chelik_player := _find_animation_player(_chelik)
		print("CHELIK: ", _chelik.name,
			" | анимации: ", chelik_player.get_animation_list() if chelik_player else ["нет"],
			" | поклон играет: ", _chelik_anim != null)
		var wizard_player := _find_animation_player(_wizard) if _wizard else null
		print("WIZARD: ", _wizard.name if _wizard else "не найден (fallback-примитивы)",
			" | анимации: ", wizard_player.get_animation_list() if wizard_player else ["нет"],
			" | scale: ", _wizard.scale if _wizard else "-")


func _process(delta: float) -> void:
	# Челик кланяется: настоящей анимацией из модели (если есть) или наклоном.
	_bow_t += delta
	if _chelik_anim == null:
		_chelik.rotation.z = 0.5 * absf(sin(_bow_t * 1.6))


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


## Модель из пака Kenney + toon-материал поверх (плоский цвет вместо текстуры).
func _prop(file: String, pos: Vector3, rot_y_deg := 0.0, color := Color(0.55, 0.5, 0.42)) -> Node3D:
	var scene: PackedScene = load(MODELS_DIR + file)
	if scene == null:
		# Модель ещё не импортирована Godot — пропускаем, сцена продолжает собираться.
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


## Задник по роадмапу: трон Великого Волшебника на возвышении,
## колонны со знамёнами, арки-стена, фонари. Трон собираем из «кирпичей»,
## потому что готового трона в паке Kenney нет.
func _setup_throne_area() -> void:
	var stone := _toon_material(Color(0.45, 0.44, 0.48))
	var wall := Color(0.33, 0.28, 0.36)

	# Арки-стена позади трона (задник зала).
	for i in 4:
		_prop("wall-arch.glb", Vector3(-4.6 + i * 2.3, 0.0, -4.2), 0.0, wall)

	# Ведущая к трону лестница и площадка.
	_prop("stairs-wide-stone.glb", Vector3(-2.2, 0.0, -1.15), 0.0, Color(0.5, 0.49, 0.52))

	# Сам трон: каменный подиум + красное кресло с золотым навершием.
	var throne := Node3D.new()
	throne.position = Vector3(-2.2, 0.0, -2.6)
	add_child(throne)
	var red := _toon_material(Color(0.42, 0.13, 0.18))
	var gold := _toon_material(Color(0.85, 0.68, 0.3))
	_box(throne, Vector3(3.2, 0.4, 2.2), Vector3(0, 0.2, 0), stone)          # подиум
	_box(throne, Vector3(1.4, 0.5, 1.2), Vector3(0, 0.65, 0), red)           # сиденье
	_box(throne, Vector3(1.4, 2.4, 0.35), Vector3(0, 1.85, -0.55), red)      # спинка
	_box(throne, Vector3(0.3, 0.9, 1.2), Vector3(-0.75, 1.05, 0), red)       # подлокотник L
	_box(throne, Vector3(0.3, 0.9, 1.2), Vector3(0.75, 1.05, 0), red)        # подлокотник R
	_box(throne, Vector3(1.55, 0.25, 0.45), Vector3(0, 3.1, -0.55), gold)    # золото на спинке

	# Колонны со знамёнами по бокам трона.
	_prop("pillar-stone.glb", Vector3(-4.4, 0.0, -2.6), 0.0, Color(0.52, 0.51, 0.55))
	_prop("pillar-stone.glb", Vector3(0.0, 0.0, -2.6), 0.0, Color(0.52, 0.51, 0.55))
	_prop("banner-red.glb", Vector3(-4.4, 1.6, -2.2), 0.0, Color(0.5, 0.16, 0.2))
	_prop("banner-red.glb", Vector3(0.0, 1.6, -2.2), 0.0, Color(0.5, 0.16, 0.2))

	# Фонари у дорожки и кривое дерево для жутко-милой атмосферы Fran Bow.
	_prop("lantern.glb", Vector3(1.8, 0.0, 1.8), 0.0, Color(0.25, 0.22, 0.26))
	_prop("lantern.glb", Vector3(-3.9, 0.0, 1.4), 0.0, Color(0.25, 0.22, 0.26))
	_prop("tree-crooked.glb", Vector3(2.6, 0.0, -3.4), 0.0, Color(0.24, 0.3, 0.2))


func _setup_wizard() -> void:
	# Великий Волшебник — Meshy-модель пользователя (риг + анимации).
	# Материалы НЕ перекрашиваем: у модели свои текстуры.
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
			player.get_animation(player.get_animation_list()[0]).loop_mode = Animation.LOOP_LINEAR
			player.play(player.get_animation_list()[0])
		return
	# Запасной волшебник из примитивов, если модель не подгрузилась.
	var fallback := Node3D.new()
	fallback.position = Vector3(-2.2, 0.0, -0.5)
	add_child(fallback)
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


## Проигрывает анимацию поклона, если она есть в модели (ищем "bow" в имени).
func _try_play_bow(root: Node3D) -> AnimationPlayer:
	var player := _find_animation_player(root)
	if player == null:
		return null
	for anim_name in player.get_animation_list():
		if "bow" in anim_name.to_lower():
			player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
			player.play(anim_name)
			return player
	return null


func _make_character(_color: Color) -> Node3D:
	# Челик — Meshy-модель пользователя. Если внутри есть анимация поклона —
	# играем её, иначе кланяемся наклоном корня (в _process).
	var root: Node3D
	var scene: PackedScene = load(CHELIK_GLB)
	if scene:
		root = scene.instantiate()
		root.position = Vector3(0.8, 0.0, 0.0)
		# Стоит лицом к трону (в сторону -X). Если увидишь спину — поменяй знак.
		root.rotation.y = -PI / 2
		add_child(root)
		_fit_model(root, 1.7)
		_chelik_anim = _try_play_bow(root)
		return root
	# Запасной вариант: персонаж из Kenney Character Assets (общий скелет Mixamo).
	scene = load(MODELS_DIR + "Textures/Casual_Male.gltf")
	if scene:
		root = scene.instantiate()
		root.position = Vector3(0.8, 0.0, 0.0)
		# Стоит лицом к трону (в сторону -X). Если увидишь спину — поменяй знак.
		root.rotation.y = -PI / 2
		add_child(root)
		return root
	# Запасной вариант, если пак не подгрузился: капсула с лицом.
	root = Node3D.new()
	add_child(root)
	var mat := _toon_material(Color(0.72, 0.64, 0.49))
	if _robe_tex:
		mat.set_shader_parameter("use_texture", true)
		mat.set_shader_parameter("texture_albedo", _robe_tex)
		mat.set_shader_parameter("base_color", Color(1.0, 1.0, 1.0))
	var body := CapsuleMesh.new()
	body.radius = 0.35
	body.height = 1.3
	_mesh(root, body, mat, Vector3(0, 0.65, 0))
	var head := SphereMesh.new()
	head.radius = 0.28
	head.height = 0.56
	_mesh(root, head, _toon_material(Color(0.72, 0.64, 0.49)), Vector3(0, 1.55, 0))
	if _face_tex:
		var face_mat := _toon_material(Color.WHITE)
		face_mat.set_shader_parameter("use_texture", true)
		face_mat.set_shader_parameter("texture_albedo", _face_tex)
		var face := QuadMesh.new()
		face.size = Vector2(0.42, 0.42)
		var face_mi := _mesh(root, face, face_mat, Vector3(0.2, 1.55, 0.2))
		face_mi.rotation.y = PI / 4
	return root


func _setup_mirror() -> void:
	# Зеркало стоит на x=3 и «смотрит» на сцену; вторая камера — позади него,
	# рендерит сцену с обратного ракурса: это и есть отражение.
	var mirror_view := SubViewport.new()
	mirror_view.size = Vector2i(512, 640)
	mirror_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(mirror_view)

	var mirror_cam := Camera3D.new()
	mirror_cam.fov = 55
	mirror_view.add_child(mirror_cam)
	mirror_cam.position = Vector3(4.6, 1.6, 0.0)
	mirror_cam.rotation.y = PI / 2 # камера смотрит по -X, обратно в сцену

	_mirror_mat = ShaderMaterial.new()
	_mirror_mat.shader = MIRROR_SHADER
	var tex := ViewportTexture.new()
	tex.viewport_path = mirror_view.get_path()
	_mirror_mat.set_shader_parameter("reflection", tex)

	# Само зеркальное полотно.
	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 3.4)
	var screen := MeshInstance3D.new()
	screen.mesh = quad
	screen.material_override = _mirror_mat
	screen.position = Vector3(3.0, 1.7, 0.0)
	screen.rotation.y = PI / 2
	add_child(screen)

	# Тёмная рама чуть позади полотна.
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


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var hint := Label.new()
	hint.text = "Тронный задник: трон Волшебника (справа в зеркале — «плывущее» отражение). " \
		+ "Кнопка «Зазеркалье» инвертирует палитру."
	hint.position = Vector2(24, 20)
	hint.size = Vector2(680, 80)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.9, 0.85, 0.95)
	layer.add_child(hint)

	var back := Button.new()
	back.text = "< назад к кликеру"
	back.position = Vector2(24, 110)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main.tscn"))
	layer.add_child(back)

	var zazerkalie := Button.new()
	zazerkalie.text = "Зазеркалье: ВЫКЛ"
	zazerkalie.position = Vector2(24, 160)
	zazerkalie.pressed.connect(func() -> void:
		var on: bool = _mirror_mat.get_shader_parameter("invert_amount") < 0.5
		_mirror_mat.set_shader_parameter("invert_amount", 1.0 if on else 0.0)
		# Палитра мира тоже «плывёт», пока мы в Зазеркалье.
		_env.background_color = Color(0.55, 0.35, 0.6) if on else Color(0.10, 0.086, 0.12)
		zazerkalie.text = "Зазеркалье: ВКЛ" if on else "Зазеркалье: ВЫКЛ")
	layer.add_child(zazerkalie)
