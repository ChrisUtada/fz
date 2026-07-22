extends Control
## InspirationPanel · 灵感弹窗（覆盖层）
##
## 三个视图状态（同场景内切换）：
##   列表视图：从 activity_pool 数据驱动生成活动按钮
##   计时视图：选中活动后显示，HSlider + SpinBox 双向绑定设时
##   进行中视图：开始后台计时后显示，实时读 GameManager 剩余时间
##
## 计时由 GameManager 持有（墙钟时间戳 + 存档），本面板只负责 UI：
##   - 开始 → GameManager.start_activity()（后台继续，支持离线收益）
##   - 放弃 → GameManager.cancel_activity()
##   - 关闭 × → 仅收起弹窗，后台计时不中止
##   - 完成 → GameManager 自动发奖（HUD 滚动），弹窗收到 activity_finished 回列表
##
## 奖励 = 时长 × 每分钟灵感值（见 GameManager._compute_activity_reward）

const LIST_VIEW := 0
const TIMER_VIEW := 1
const RUNNING_VIEW := 2

@export var activity_pool: Array[ActivityData] = []

var _current_view: int = LIST_VIEW
var _current_activity: ActivityData
var _minutes: int = 25

## 初始化期间抑制 value_changed 回调
var _suppress: bool = false

@onready var _list_view: Control = $Card/Content/ListView
@onready var _timer_view: Control = $Card/Content/TimerView
@onready var _activity_list: VBoxContainer = $Card/Content/ListView/ActivityList
@onready var _close_button: Button = $Card/Content/TitleBar/CloseButton
@onready var _back_button: Button = $Card/Content/TimerView/BackButton
@onready var _activity_title: Label = $Card/Content/TimerView/ActivityTitle
@onready var _time_row: HBoxContainer = $Card/Content/TimerView/TimeRow
@onready var _slider: HSlider = $Card/Content/TimerView/TimeRow/HSlider
@onready var _spinbox: SpinBox = $Card/Content/TimerView/TimeRow/SpinBox
@onready var _countdown_box: Control = $Card/Content/TimerView/CountdownBox
@onready var _countdown_label: Label = $Card/Content/TimerView/CountdownBox/CountdownLabel
@onready var _start_button: Button = $Card/Content/TimerView/StartButton
@onready var _cancel_button: Button = $Card/Content/TimerView/CancelButton
@onready var _minimize_btn: Button = $Card/Content/TimerView/MinimizeButton
@onready var _outing_box: Control = $Card/Content/TimerView/OutingBox
@onready var _outing_counts: Label = $Card/Content/TimerView/OutingBox/OutingCounts
@onready var _end_button: Button = $Card/Content/TimerView/EndButton
@onready var _reward_hint: Label = $Card/Content/TimerView/RewardHint

## 当前进行中活动是否为「外出」（无时间条、手动结束）
func _is_outing() -> bool:
	return GameManager.get_activity_mode() == ActivityData.Mode.OUTING


func _ready() -> void:
	_close_button.pressed.connect(_on_close)
	_back_button.pressed.connect(_show_list)
	_start_button.pressed.connect(_on_start_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_minimize_btn.pressed.connect(_on_minimize_pressed)
	_end_button.pressed.connect(_on_end_pressed)
	_slider.value_changed.connect(_on_slider_changed)
	_spinbox.value_changed.connect(_on_spinbox_changed)
	GameManager.activity_finished.connect(_on_activity_finished)

	# 先抑制回调，统一设好范围与初值，再放开，保证 _minutes 保持 25（不被夹值回调改掉）
	_suppress = true
	_slider.min_value = 1
	_slider.max_value = 60
	_slider.step = 1
	_slider.value = _minutes
	_spinbox.min_value = 1
	_spinbox.max_value = 60
	_spinbox.step = 1
	_spinbox.value = _minutes
	_suppress = false

	# 倒计时大字号，确保一眼可见
	_countdown_label.add_theme_font_size_override("font_size", 40)

	_populate_activities()

	# 打开时若后台已有进行中的活动，直接进入“进行中”视图
	if GameManager.is_activity_running():
		_show_running()
	else:
		_show_list()


# ═══════════════════ 列表视图（数据驱动） ═══════════════════

func _populate_activities() -> void:
	for child in _activity_list.get_children():
		child.queue_free()
	if activity_pool.is_empty():
		# 回退：无任何 .tres 时，给一个默认“阅读”按钮（@export 默认值）
		_add_activity_button(null)
		return
	for data in activity_pool:
		_add_activity_button(data)


func _add_activity_button(data: ActivityData) -> void:
	var btn := Button.new()
	if data != null:
		if data.mode == ActivityData.Mode.OUTING:
			btn.text = "%s   ·   按真实键鼠折算灵感" % data.activity_name
		else:
			btn.text = "%s   ·   每分钟 +%.1f 灵感" % [data.activity_name, data.inspiration_per_minute]
	else:
		btn.text = "阅读   ·   每分钟 +0.4 灵感"
	btn.pressed.connect(func(): _open_activity(data))
	_activity_list.add_child(btn)


func _open_activity(data: ActivityData) -> void:
	if data != null:
		_current_activity = data
		_minutes = data.default_duration_minutes
		_activity_title.text = data.activity_name
	else:
		_current_activity = null
		_minutes = 25
		_activity_title.text = "阅读"
	# 外出：点击即出发，无需设定时间（无时间条）
	if _current_activity != null and _current_activity.mode == ActivityData.Mode.OUTING:
		GameManager.start_activity(_current_activity, 0)
		_show_running()
		return
	_slider.value = _minutes
	_spinbox.value = _minutes
	_countdown_label.text = _format_time(float(_minutes) * 60.0)
	_update_reward_hint()
	_show_timer()


# ═══════════════════ 视图切换 ═══════════════════

func _show_list() -> void:
	_current_view = LIST_VIEW
	_list_view.visible = true
	_timer_view.visible = false


func _show_timer() -> void:
	_current_view = TIMER_VIEW
	_list_view.visible = false
	_timer_view.visible = true
	_back_button.visible = true
	_time_row.visible = true
	_start_button.visible = true
	_cancel_button.visible = false
	_countdown_box.visible = false
	_minimize_btn.visible = false
	_outing_box.visible = false
	_end_button.visible = false
	_update_reward_hint()


func _show_running() -> void:
	_current_view = RUNNING_VIEW
	_list_view.visible = false
	_timer_view.visible = true
	_activity_title.text = GameManager.get_active_activity_name()
	_back_button.visible = false
	_time_row.visible = false
	_start_button.visible = false
	if _is_outing():
		# 外出：无时间条、无专注条（专注条仅番茄钟）；显示实时统计 + 结束/放弃
		_countdown_box.visible = false
		_minimize_btn.visible = false
		_outing_box.visible = true
		_end_button.visible = true
		_cancel_button.visible = true
		_update_outing_counts()
	else:
		# 番茄钟：倒计时 + 专注条
		_countdown_box.visible = true
		_minimize_btn.visible = true
		_outing_box.visible = false
		_end_button.visible = false
		_cancel_button.visible = true
		_update_countdown_label()


# ═══════════════════ 时间设定（滑条 + 输入框双向绑定） ═══════════════════

func _on_slider_changed(v: float) -> void:
	if _suppress:
		return
	_minutes = int(v)
	if _spinbox.value != _minutes:
		_spinbox.value = _minutes
	_countdown_label.text = _format_time(float(_minutes) * 60.0)
	_update_reward_hint()


func _on_spinbox_changed(v: float) -> void:
	if _suppress:
		return
	_minutes = int(v)
	if _slider.value != _minutes:
		_slider.value = _minutes
	_countdown_label.text = _format_time(float(_minutes) * 60.0)
	_update_reward_hint()


# ═══════════════════ 开始 / 放弃 / 完成 ═══════════════════

func _on_start_pressed() -> void:
	if _minutes < 1:
		_minutes = 1
	# 委托 GameManager：墙钟计时 + 存档（支持离线收益），本弹窗只显示
	GameManager.start_activity(_current_activity, _minutes)
	_show_running()


func _on_cancel_pressed() -> void:
	GameManager.cancel_activity()
	_show_list()


## RUNNING 视图「结束并领取」：仅外出可用，手动结算键鼠折算的灵感
func _on_end_pressed() -> void:
	GameManager.finish_outing()


## RUNNING 视图「最小化专注条」：收起为专注条，转去做现实中的事
func _on_minimize_pressed() -> void:
	var main = get_tree().current_scene
	if main != null and main.has_method("_enter_focus_mode"):
		main.call("_enter_focus_mode")


func _on_activity_finished(reward: Dictionary) -> void:
	# 弹窗开着时自然完成 → 显示结算摘要，几秒后回列表
	if _current_view == RUNNING_VIEW:
		_show_summary(reward)
	elif _current_view == LIST_VIEW:
		# 列表态收到完成（已不在进行中视图）→ 无需动作
		pass


## 完成后展示结算摘要，3 秒后回列表（外出：键鼠 N 次；番茄钟：专注 X 分·中断）
func _show_summary(reward: Dictionary) -> void:
	var insp: int = reward.get("inspiration", 0)
	_back_button.visible = false
	_time_row.visible = false
	_start_button.visible = false
	_cancel_button.visible = false
	_minimize_btn.visible = false
	_outing_box.visible = false
	_end_button.visible = false
	var line := ""
	if reward.get("mode", "") == "outing":
		# 外出：无时间条，按真实键鼠折算
		_countdown_box.visible = false
		var inputs: int = reward.get("inputs", 0)
		line = "外出完成 · 键鼠 %d 次 · 灵感 +%d" % [inputs, insp]
	else:
		# 番茄钟：专注 X 分 · 中断 N 次
		_countdown_box.visible = true
		_countdown_label.text = "✓ 完成"
		var minutes: int = reward.get("minutes", 0)
		var interrupts: int = reward.get("interrupts", 0)
		var base: int = reward.get("base", insp)
		var streak: int = reward.get("streak", 0)
		var streak_bonus: int = reward.get("streak_bonus", 0)
		line = "专注 %d 分 · 中断 %d 次 · 灵感 +%d（原 +%d）" % [minutes, interrupts, insp, base]
		if streak >= 2:
			line += "  ·  🔥连击 %d（奖励 +%d）" % [streak, streak_bonus]
		elif streak == 1:
			line += "  ·  🔥连击 1"
	_reward_hint.text = line
	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(self):
		_show_list()


func _process(_delta: float) -> void:
	if _current_view == RUNNING_VIEW and GameManager.is_activity_running():
		if _is_outing():
			_update_outing_counts()
		else:
			_update_countdown_label()


# ═══════════════════ 辅助 ═══════════════════

func _update_countdown_label() -> void:
	var rem := GameManager.get_remaining_sec()
	_countdown_label.text = _format_time(rem)
	var base := GameManager.get_pending_reward()
	var n := GameManager.get_activity_interrupts()
	var st := GameManager.get_activity_streak()
	if n > 0:
		var factor := maxf(0.5, 1.0 - float(n) * 0.2)
		var est := int(ceil(float(base) * factor - 0.0001))
		_reward_hint.text = "进行中 · 已中断 %d 次 · 预计 +%d（满额 +%d）" % [n, est, base]
	else:
		_reward_hint.text = "进行中 · 预计获得 +%d 灵感值" % base
	if st >= 1:
		_reward_hint.text += "  ·  🔥连击 %d" % st


## 外出进行中：实时显示键鼠增量与预计灵感（无时间条）
func _update_outing_counts() -> void:
	var c := GameManager.get_outing_counts()
	if not bool(c.get("active", false)):
		# 统计未就绪：透出具体原因，避免用户只看到"0"却不知为何
		var err := GameManager.get_outing_error()
		if not err.is_empty():
			_outing_counts.text = "统计未启动"
			_reward_hint.text = "输入统计失败：%s\n（可能无管理员权限 / 被安全软件拦截，或 python 路径不可用）" % err
		else:
			# Python 冷启动期间（收拾行装）：尚未开始计数，给出明确等待提示而非让玩家误以为坏了
			_outing_counts.text = "收拾行装中…"
			_reward_hint.text = "正在收拾行装…（启动输入统计中）"
		return
	_outing_counts.text = "键 %d / 鼠 %d 次" % [c.get("keys", 0), c.get("mouse", 0)]
	var per_action := 0.05
	if _current_activity != null:
		per_action = _current_activity.inspiration_per_action
	var est := int(ceil(float(c.get("total", 0)) * per_action - 0.0001))
	_reward_hint.text = "统计中 · 已输入 %d 次 · 预计 +%d 灵感" % [c.get("total", 0), est]


func _update_reward_hint() -> void:
	var per_min := 0.4
	if _current_activity != null:
		per_min = _current_activity.inspiration_per_minute
	var reward := int(ceil(float(_minutes) * per_min - 0.0001))
	_reward_hint.text = "预计获得 +%d 灵感值（每分钟 +%.1f）" % [reward, per_min]


func _format_time(total_sec: float) -> String:
	var s := int(ceil(total_sec))
	var m := s / 60
	var sec := s % 60
	return "%02d:%02d" % [int(m), sec]


func _on_close() -> void:
	queue_free()
