extends Node
class_name ActivityManager

## 活动子管理器：灵感活动（番茄钟 POMODORO + 外出 OUTING）、专注条计时、连击 streak、
## 打断计数、外出真实键鼠统计（GlobalInput GDExtension）。
## 由 GameManager（autoload）在 _ready 中实例化并 add_child；GameManager 仍暴露等价的
## GameManager.start_activity / get_activity_streak ... 方法（委托转发），全代码库调用点无需改动。
## GameManager 仅通过信号 re-emit 把活动状态广播出去。

signal activity_started
signal activity_finished(reward: Dictionary)
signal activity_cancelled
signal activity_interrupted(interrupts: int)  ## 番茄钟进行中发生一次打断（带累计次数）
signal activity_streak_changed(streak: int)  ## 连击数变化（完成 +1 / 放弃归零）

const ACTIVITY_SAVE_PATH := "user://inspiration_active.json"
const STREAK_SAVE_PATH := "user://focus_streak.cfg"   ## 连击持久化（跨会话保留，放弃清零）

## 打断衰减系数常量（单一真相源，避免与 UI 双处维护魔法数）：
## 中断 n 次后灵感保留比例 = maxf(REWARD_DECAY_MIN, 1.0 - n * REWARD_DECAY_STEP)
const REWARD_DECAY_MIN := 0.5
const REWARD_DECAY_STEP := 0.2

var owner_mgr = null  ## GameManager 反向引用（finish_activity / finish_outing 经 add_inspiration 发灵感）

# ─── 活动计时状态（墙钟 + 存档，支持离线收益） ───
var _activity_running: bool = false
var _activity_name: String = ""
var _activity_per_minute: float = 0.0
var _activity_start_unix: int = 0
var _activity_duration_sec: float = 0.0
var _activity_interrupts: int = 0   ## 本次番茄钟的打断次数（进程内，不持久化；离线补发不记打断）
var _activity_streak: int = 0   ## 连续完成番茄钟次数（连击；持久化，放弃清零）

# ─── 外出活动：GlobalInput GDExtension 进程内键鼠统计（仅 OUTING 模式使用） ───
var _global_input: GlobalInput = null   ## 全局键鼠钩子扩展节点（进程内常驻，无需外部进程）
var _activity_mode: int = 0             ## 0=POMODORO, 1=OUTING（与 ActivityData.Mode 对应）
var _outing_per_action: float = 0.05
var _outing_active: bool = false        ## OUTING 进行中且钩子已启动
var _outing_total: int = 0              ## 统一计数：OUTING 期间累计键鼠输入次数（单一数据源，避免重复计数）
var _prev_keys: Dictionary = {}         ## 上一帧按下的键（字符串集合），用于差分


func _ready() -> void:
	_init_global_input()
	tree_exiting.connect(_on_tree_exiting)


func _process(_delta: float) -> void:
	if _activity_running and _activity_mode == ActivityData.Mode.POMODORO:
		var elapsed := Time.get_unix_time_from_system() - _activity_start_unix
		if elapsed >= _activity_duration_sec:
			_finish_activity()
	if _outing_active and _global_input != null:
		_tick_outing_inputs()


## 由 GameManager._ready 调用：还原连击数 + 离线补发/后台继续活动。
func load_all() -> void:
	_load_streak()
	_load_activity()


# ═══════════════════ 对外 API（GameManager 委托转发） ═══════════════════

## 开始一个活动（番茄钟/外出）。成功返回 true；数据为空或已有活动进行中则拒绝并返回 false。
func start_activity(data: ActivityData, minutes: int) -> bool:
	if data == null:
		return false
	if _activity_running:
		return false
	_activity_running = true
	_activity_interrupts = 0
	_activity_name = data.activity_name
	_activity_mode = data.mode
	if data.mode == ActivityData.Mode.OUTING:
		_start_outing(data)
		activity_started.emit()
		return true
	if minutes < 1:
		minutes = 1
	_activity_per_minute = data.inspiration_per_minute
	_activity_start_unix = int(Time.get_unix_time_from_system())
	_activity_duration_sec = float(minutes) * 60.0
	_save_activity()
	activity_started.emit()
	return true


## 放弃当前进行中的活动（清状态，不发奖）。OUTING 会先杀掉伴生进程。
func cancel_activity() -> void:
	if not _activity_running:
		return
	var was_outing := (_activity_mode == ActivityData.Mode.OUTING)
	if was_outing:
		_stop_outing_hook()
	_activity_running = false
	_activity_interrupts = 0
	if not was_outing and _activity_streak > 0:
		_activity_streak = 0
		_save_streak()
		activity_streak_changed.emit(0)
	_activity_mode = 0
	if not was_outing:
		_delete_activity_save()
	activity_cancelled.emit()


func is_activity_running() -> bool:
	return _activity_running


## 记录一次打断（仅 POMODORO 进行中做了非灵感活动的分心行为）。OUTING 不记打断。
func register_interrupt() -> void:
	if not _activity_running:
		return
	if _activity_mode != ActivityData.Mode.POMODORO:
		return
	_activity_interrupts += 1
	activity_interrupted.emit(_activity_interrupts)


func get_activity_interrupts() -> int:
	return _activity_interrupts


## 打断衰减系数（单一真相源）：中断 n 次后灵感保留比例 = maxf(REWARD_DECAY_MIN, 1.0 - n*REWARD_DECAY_STEP)。
## 结算（_finish_activity）与 UI 预览（inspiration_panel._update_countdown_label）都走它，
## 不再各自写 maxf(0.5, 1.0 - n*0.2) 魔法数，杜绝双处维护不一致。
func get_reward_factor() -> float:
	return maxf(REWARD_DECAY_MIN, 1.0 - float(_activity_interrupts) * REWARD_DECAY_STEP)


func get_active_activity_name() -> String:
	return _activity_name


func get_activity_mode() -> int:
	return _activity_mode


## 当前连击数（连续完成的番茄钟次数；放弃清零，跨会话保留）
func get_activity_streak() -> int:
	return _activity_streak


# ─── 外出活动：GlobalInput 键鼠统计 ───

## 创建并常驻 GlobalInput 节点。钩子本身默认不启用，仅 OUTING 模式 start 时启用。
func _init_global_input() -> void:
	if not ClassDB.class_exists("GlobalInput"):
		push_warning("GlobalInput 扩展未加载（缺少 addons/godot_global_input/global_input.gdextension 或对应 .dll）")
		return
	_global_input = GlobalInput.new()
	_global_input.name = "GlobalInput"
	_global_input.process_priority = -10
	add_child(_global_input)


## 开始 OUTING：启用真实全局钩子，立即生效。
func _start_outing(data: ActivityData) -> void:
	_outing_active = false
	_outing_total = 0
	_prev_keys = {}
	_outing_per_action = data.inspiration_per_action
	if _global_input == null:
		push_warning("外出活动：GlobalInput 扩展不可用，本次不计统计")
		return
	_global_input.set_backend("windows")
	_outing_active = true


## 每帧差分累计键鼠输入次数（统一计数）。
func _tick_outing_inputs() -> void:
	var cur: Dictionary = _global_input.get_keys_pressed_detailed()
	for k in cur.keys():
		if k == "os":
			continue
		if not _prev_keys.has(k):
			_outing_total += 1
	_prev_keys = cur


## 公开给 UI：当前是否未就绪（钩子启动即就绪，仅扩展缺失时返回原因）。
func get_outing_error() -> String:
	if _global_input == null:
		return "GlobalInput 扩展未加载"
	return ""


## 公开给 UI：OUTING 实时统计。统一计数以 total 为准。
func get_outing_counts() -> Dictionary:
	if not _outing_active:
		return {"total": 0, "active": false}
	return {"total": _outing_total, "active": true}


## 结束外出并折算灵感（手动「结束并领取」触发）
func finish_outing() -> void:
	if not _activity_running or _activity_mode != ActivityData.Mode.OUTING:
		return
	var inputs := _outing_total
	var reward := int(ceil(float(inputs) * _outing_per_action - 0.0001))
	_activity_running = false
	_stop_outing_hook()
	if owner_mgr != null:
		owner_mgr.add_inspiration(reward)
	activity_finished.emit({"inspiration": reward, "activity_name": _activity_name, "inputs": inputs, "mode": "outing"})
	_activity_interrupts = 0
	_activity_mode = 0


## OUTING 结束后停止真实钩子（切回 dummy 后端，零开销）。
func _stop_outing_hook() -> void:
	_outing_active = false
	if _global_input != null:
		_global_input.set_backend("dummy")


func _on_tree_exiting() -> void:
	if _global_input != null:
		_global_input.stop_hook()


func get_remaining_sec() -> float:
	if not _activity_running:
		return 0.0
	var elapsed := Time.get_unix_time_from_system() - _activity_start_unix
	return maxf(0.0, _activity_duration_sec - elapsed)


func get_activity_total_sec() -> float:
	if not _activity_running:
		return 0.0
	return _activity_duration_sec


func get_pending_reward() -> int:
	if not _activity_running:
		return 0
	var minutes := int(ceil(_activity_duration_sec / 60.0))
	return _compute_activity_reward(_activity_per_minute, minutes)


func _finish_activity() -> void:
	var minutes := int(ceil(_activity_duration_sec / 60.0))
	var base := _compute_activity_reward(_activity_per_minute, minutes)
	var factor := get_reward_factor()
	var streak_factor := 1.0
	if _activity_mode == ActivityData.Mode.POMODORO:
		_activity_streak += 1
		streak_factor = _streak_factor(_activity_streak)
		activity_streak_changed.emit(_activity_streak)
	var decayed := int(ceil(float(base) * factor - 0.0001))
	var reward := int(ceil(float(base) * factor * streak_factor - 0.0001))
	var streak_bonus := maxi(0, reward - decayed)
	_activity_running = false
	_delete_activity_save()
	if owner_mgr != null:
		owner_mgr.add_inspiration(reward)
	activity_finished.emit({"inspiration": reward, "activity_name": _activity_name, "base": base, "interrupts": _activity_interrupts, "minutes": minutes, "streak": _activity_streak, "streak_bonus": streak_bonus})
	_activity_interrupts = 0


func _compute_activity_reward(per_minute: float, minutes: int) -> int:
	if minutes < 1:
		minutes = 1
	var raw := float(minutes) * per_minute
	return int(ceil(raw - 0.0001))


## 连击加成系数：连续完成的番茄钟越多，额外灵感越高（封顶 +50%）。
## 仅作用于 POMODORO 结算；与打断衰减相乘叠加。
func _streak_factor(streak: int) -> float:
	if streak >= 10:
		return 1.5
	if streak >= 5:
		return 1.25
	if streak >= 2:
		return 1.10
	return 1.0


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
		_finish_activity()
	else:
		_activity_running = true
		_activity_mode = ActivityData.Mode.POMODORO


func _delete_activity_save() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("inspiration_active.json")


# ─── 连击存档（跨会话保留；放弃清零） ───

func _save_streak() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("streak", "count", _activity_streak)
	cfg.save(STREAK_SAVE_PATH)


func _load_streak() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(STREAK_SAVE_PATH) == OK:
		_activity_streak = int(cfg.get_value("streak", "count", 0))
