extends Node
## GameManager · 全局状态管理（唯一 autoload 单例）
## 职责：持有 gold / inspiration 货币状态；管理“灵感活动”计时与离线收益结算。
## 原则：低耦合 —— 其他节点通过 signal 订阅变化，不直接读写内部字段。
##       活动计时采用真实墙钟时间戳（get_unix_time_from_system）+ 存档，
##       因此关掉游戏再打开也能按真实流逝时间结算（离线收益）。

signal currency_changed(new_gold: int, new_inspiration: int)
signal activity_started
signal activity_finished(reward: Dictionary)
signal activity_cancelled

@export var initial_gold: int = 0
@export var initial_inspiration: int = 0

var gold: int:
	set(v):
		gold = v
		currency_changed.emit(gold, inspiration)

var inspiration: int:
	set(v):
		inspiration = v
		currency_changed.emit(gold, inspiration)

# ─── 灵感活动计时（墙钟 + 存档，支持离线收益） ───
const ACTIVITY_SAVE_PATH := "user://inspiration_active.json"

var _activity_running: bool = false
var _activity_name: String = ""
var _activity_per_minute: float = 0.0
var _activity_start_unix: int = 0
var _activity_duration_sec: float = 0.0


func _ready() -> void:
	gold = initial_gold
	inspiration = initial_inspiration
	_load_activity()  # 启动即检查存档：已过期则补发，未过期则后台继续


func _process(_delta: float) -> void:
	if not _activity_running:
		return
	var elapsed := Time.get_unix_time_from_system() - _activity_start_unix
	if elapsed >= _activity_duration_sec:
		_finish_activity()


# ═══════════════════ 货币 ═══════════════════

func add_gold(amount: int) -> void:
	if amount < 0:
		push_warning("add_gold 收到负值 %d，请用 subtract_gold" % amount)
	gold += amount


func subtract_gold(amount: int) -> void:
	add_gold(-amount)


func add_inspiration(amount: int) -> void:
	if amount < 0:
		push_warning("add_inspiration 收到负值 %d，请用 subtract_inspiration" % amount)
	inspiration += amount


func subtract_inspiration(amount: int) -> void:
	add_inspiration(-amount)


func complete_order(base_reward: Dictionary) -> void:
	var reward_gold: int = base_reward.get("gold", 0)
	var reward_insp: int = base_reward.get("inspiration", 0)
	add_gold(reward_gold)
	add_inspiration(reward_insp)


# ═══════════════════ 灵感活动计时 ═══════════════════

## 开始一个活动（墙钟计时，立即存档）。minutes 为设定时长（分钟）。
func start_activity(data: ActivityData, minutes: int) -> void:
	if minutes < 1:
		minutes = 1
	_activity_running = true
	_activity_name = data.activity_name
	_activity_per_minute = data.inspiration_per_minute
	_activity_start_unix = int(Time.get_unix_time_from_system())
	_activity_duration_sec = float(minutes) * 60.0
	_save_activity()
	activity_started.emit()


## 放弃当前进行中的活动（清状态 + 删存档，不发奖）
func cancel_activity() -> void:
	if not _activity_running:
		return
	_activity_running = false
	_delete_activity_save()
	activity_cancelled.emit()


## 查询：是否在进行中
func is_activity_running() -> bool:
	return _activity_running


## 查询：进行中活动名称
func get_active_activity_name() -> String:
	return _activity_name


## 查询：剩余秒数（墙钟实时算）
func get_remaining_sec() -> float:
	if not _activity_running:
		return 0.0
	var elapsed := Time.get_unix_time_from_system() - _activity_start_unix
	return maxf(0.0, _activity_duration_sec - elapsed)


## 查询：预计将获得的灵感值（基于设定时长）
func get_pending_reward() -> int:
	if not _activity_running:
		return 0
	var minutes := int(ceil(_activity_duration_sec / 60.0))
	return _compute_activity_reward(_activity_per_minute, minutes)


func _finish_activity() -> void:
	var minutes := int(ceil(_activity_duration_sec / 60.0))
	var reward := _compute_activity_reward(_activity_per_minute, minutes)
	_activity_running = false
	_delete_activity_save()
	add_inspiration(reward)
	activity_finished.emit({"inspiration": reward, "activity_name": _activity_name})


func _compute_activity_reward(per_minute: float, minutes: int) -> int:
	if minutes < 1:
		minutes = 1
	var raw := float(minutes) * per_minute
	return int(ceil(raw - 0.0001))


# ─── 存档（user://，仅持久化结算所需的最小信息） ───

func _save_activity() -> void:
	var payload := {
		"name": _activity_name,
		"per_minute": _activity_per_minute,
		"start_unix": _activity_start_unix,
		"duration_sec": _activity_duration_sec
	}
	var f := FileAccess.open(ACTIVITY_SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload))
		f.close()


func _load_activity() -> void:
	if not FileAccess.file_exists(ACTIVITY_SAVE_PATH):
		return
	var f := FileAccess.open(ACTIVITY_SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed == null or not parsed is Dictionary:
		_delete_activity_save()
		return
	_activity_name = parsed.get("name", "")
	_activity_per_minute = float(parsed.get("per_minute", 0.0))
	_activity_start_unix = int(parsed.get("start_unix", 0))
	_activity_duration_sec = float(parsed.get("duration_sec", 0.0))
	var elapsed := Time.get_unix_time_from_system() - _activity_start_unix
	if elapsed >= _activity_duration_sec:
		# 离线期间已结束 → 立即补发
		_finish_activity()
	else:
		# 仍在进行 → 后台继续倒计时
		_activity_running = true


func _delete_activity_save() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("inspiration_active.json")
