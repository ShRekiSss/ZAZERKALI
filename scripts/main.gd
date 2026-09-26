extends Control
## Главная сцена: ввод (тап), анимация поклона, весь UI прототипа.

@onready var bowman: TextureRect = $BowMan
@onready var wizard_rect: TextureRect = $Wizard
@onready var counter_label: Label = $CounterLabel
@onready var rate_label: Label = $RateLabel
@onready var story_label: Label = $StoryLabel
@onready var upgrades_panel: GridContainer = $UpgradesPanel
@onready var toon3d_button: Button = $Toon3DButton

var _bowing := false
var _buttons := {}
var _idle_t := 0.0

## Через сколько секунд без тапов челик сам делает медленный поклон.
const IDLE_BOW_EVERY := 2.2


func _ready() -> void:
	# Поклон — вращение вокруг ног, поэтому точка вращения внизу по центру.
	bowman.pivot_offset = bowman.size * Vector2(0.5, 1.0)
	# Спрайты рисует скрипт tools/generate_2d_characters.ps1. load(), а не preload:
	# если текстур вдруг нет — останутся цветные прямоугольники-заглушки, но игра запустится.
	var chelik_tex: Texture2D = load("res://assets/textures/chelik_2d.png")
	if chelik_tex:
		bowman.texture = chelik_tex
	var wizard_tex: Texture2D = load("res://assets/textures/wizard_2d.png")
	if wizard_tex:
		wizard_rect.texture = wizard_tex
	GameState.changed.connect(_update_ui)
	GameState.story_line.connect(_show_story)
	for id in GameState.UPGRADES:
		var button := Button.new()
		button.pressed.connect(GameState.buy.bind(id))
		upgrades_panel.add_child(button)
		_buttons[id] = button
	toon3d_button.pressed.connect(
		func() -> void: get_tree().change_scene_to_file("res://scenes/toon3d.tscn"))
	_update_ui()


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
	# Тапы по кнопкам (апгрейды, переход в 3D) — это нажатия, а не поклоны.
	if upgrades_panel.get_global_rect().has_point(pos) \
			or toon3d_button.get_global_rect().has_point(pos):
		return
	_idle_t = 0.0
	GameState.add_tap()
	_bow()


func _process(delta: float) -> void:
	# Пассивный поклон: пока игрок не тапает, челик сам медленно кланяется.
	if not _bowing:
		_idle_t += delta
		if _idle_t >= IDLE_BOW_EVERY:
			_idle_t = 0.0
			_bow(0.7, 1.0, 0.85)


func _bow(down := 0.12, up := 0.45, depth := 1.1) -> void:
	if _bowing:
		return
	_bowing = true
	var tween := create_tween()
	tween.tween_property(bowman, "rotation", -depth, down) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.05)
	tween.tween_property(bowman, "rotation", 0.0, up) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void: _bowing = false)


func _update_ui() -> void:
	counter_label.text = "Благосклонность: %s" % _fmt(GameState.favor)
	rate_label.text = "%s/сек · сила поклона +%d" % [_fmt(GameState.auto_rate()), GameState.tap_power()]
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
	story_label.text = "«%s»" % text
	story_label.visible = true
	story_label.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(story_label, "modulate:a", 1.0, 0.6)
	tween.tween_interval(5.0)
	tween.tween_property(story_label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func() -> void: story_label.visible = false)


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
