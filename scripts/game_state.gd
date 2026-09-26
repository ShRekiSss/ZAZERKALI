extends Node
## GameState — автозагрузка (синглтон): вся логика чисел игры живёт ТОЛЬКО здесь.
## Сцены (main.gd и будущие) только показывают то, что отсюда приходит.

## Выдаётся при любом изменении чисел — UI слушает и перерисовывается.
signal changed
## Выдаётся, когда благосклонность перевалила очередной сюжетный порог.
signal story_line(text: String)

const SAVE_PATH := "user://save.json"
const SAVE_EVERY_SEC := 30.0
## Сколько часов оффлайн-дохода копим максимум, чтобы не ломать баланс.
const OFFLINE_CAP_HOURS := 8.0
## Благосклонность, при которой откроется Зеркало (престиж, Этап 4).
const MIRROR_COST := 100_000.0

## Апгрейды. growth — во сколько раз дорожает каждый следующий уровень.
## tap — прибавка к силе поклона за уровень; auto — прибавка к доходу в секунду.
const UPGRADES := {
	"bow_deep": {"name": "Глубокий поклон", "base_cost": 15.0, "growth": 1.15, "tap": 1, "auto": 0.0},
	"bow_lower": {"name": "Поклон до земли", "base_cost": 200.0, "growth": 1.18, "tap": 5, "auto": 0.0},
	"forehead": {"name": "Лбом об пол", "base_cost": 2500.0, "growth": 1.2, "tap": 25, "auto": 0.0},
	"crowd": {"name": "Толпа зевак", "base_cost": 100.0, "growth": 1.15, "tap": 0, "auto": 1.0},
	"monks": {"name": "Монашеский хор", "base_cost": 1200.0, "growth": 1.17, "tap": 0, "auto": 8.0},
	"relic": {"name": "Реликвия храма", "base_cost": 9000.0, "growth": 1.2, "tap": 0, "auto": 40.0},
}

## Сюжет: показывается по очереди, когда благосклонность доходит до порога "at".
const STORY := [
	{"at": 10.0, "text": "Волшебник молчит. Но взгляд у него — как будто он ждал именно тебя."},
	{"at": 50.0, "text": "Ты замечаешь: его тень кланяется не в ту сторону."},
	{"at": 200.0, "text": "Старик у колонны шепчет: «Он не всегда был велик…»"},
	{"at": 1000.0, "text": "На мраморе пола — царапины. Кто-то уже стоял здесь на коленях. Долго."},
	{"at": 5000.0, "text": "Во сне ты видел зеркало. В зеркале — трон. На троне — ты."},
	{"at": 20000.0, "text": "Волшебник впервые улыбнулся. Улыбка была чуть шире, чем надо."},
	{"at": 80000.0, "text": "Голоса в стенах считают вместе с тобой. Они радуются каждому числу."},
	{"at": 300000.0, "text": "Зеркало в западном крыле запотело. Изнутри."},
	{"at": 1000000.0, "text": "Ты понимаешь: благосклонность не растёт. Она перетекает. Из тебя."},
	{"at": 4000000.0, "text": "В глубине зала есть дверь, которой нет на планах замка."},
	{"at": 15000000.0, "text": "Эхо твоих поклонов возвращается на полтакта раньше, чем нужно."},
	{"at": 60000000.0, "text": "Волшебник шепчет: «Ещё немного, и ты увидишь, кому кланяешься на самом деле»."},
	{"at": 250000000.0, "text": "В зеркале толпа кланяется тебе. Ты не помнишь, чтобы останавливался."},
	{"at": 1000000000.0, "text": "Порог Зеркала открыт. За ним — зал. В зале — трон."},
	{"at": 5000000000.0, "text": "ЗАЗЕРКАЛЬЕ ждёт. Кланяйся. Кланяйся. Кланяйся."},
]

var favor: float = 0.0
var levels := {}
var story_unlocked := 0
var total_taps := 0

var _save_timer := 0.0


func tap_power() -> int:
	var power := 1
	for id in UPGRADES:
		power += int(UPGRADES[id]["tap"]) * int(levels.get(id, 0))
	return power


func auto_rate() -> float:
	var rate := 0.0
	for id in UPGRADES:
		rate += float(UPGRADES[id]["auto"]) * float(levels.get(id, 0))
	return rate


func cost_of(id: String) -> int:
	var lvl := int(levels.get(id, 0))
	var base := float(UPGRADES[id]["base_cost"])
	var growth := float(UPGRADES[id]["growth"])
	return int(round(base * pow(growth, lvl)))


func can_buy(id: String) -> bool:
	return favor >= cost_of(id)


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	favor -= cost_of(id)
	levels[id] = int(levels.get(id, 0)) + 1
	changed.emit()
	save()
	return true


func add_tap() -> void:
	favor += tap_power()
	total_taps += 1
	_after_gain()


func _process(delta: float) -> void:
	if auto_rate() > 0.0:
		favor += auto_rate() * delta
		_after_gain()
	_save_timer += delta
	if _save_timer >= SAVE_EVERY_SEC:
		_save_timer = 0.0
		save()


func _after_gain() -> void:
	_check_story()
	changed.emit()


func _check_story() -> void:
	while story_unlocked < STORY.size() and favor >= float(STORY[story_unlocked]["at"]):
		story_line.emit(String(STORY[story_unlocked]["text"]))
		story_unlocked += 1


func save() -> void:
	var data := {
		"favor": favor,
		"levels": levels,
		"story_unlocked": story_unlocked,
		"total_taps": total_taps,
		"time": Time.get_unix_time_from_system(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))


func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	favor = float(data.get("favor", 0.0))
	story_unlocked = int(data.get("story_unlocked", 0))
	total_taps = int(data.get("total_taps", 0))
	var saved_levels: Variant = data.get("levels", {})
	if typeof(saved_levels) == TYPE_DICTIONARY:
		levels = saved_levels
	# Оффлайн-доход: пока игры не было, толпа кланялась сама.
	var elapsed: float = Time.get_unix_time_from_system() - float(data.get("time", 0.0))
	elapsed = minf(elapsed, OFFLINE_CAP_HOURS * 3600.0)
	var earned := auto_rate() * elapsed
	if earned > 0.0:
		favor += earned
		_check_story.call_deferred()
		changed.emit.call_deferred()


func _notification(what: int) -> void:
	# На телефоне приложение сворачивают — сохраняемся в этот момент,
	# а не при выходе (его на Android «нет»).
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()


func _ready() -> void:
	load_data()
