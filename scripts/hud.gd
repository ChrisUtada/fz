extends Control
## HUD · 货币显示面板（观察者模式）
## 职责单一：展示金币/灵感数值，监听 GameManager.currency_changed 并用 Tween 动画过渡。
## 原则：
##   - 低耦合：只通过 signal 订阅 GameManager，不持有其引用做主动轮询
##   - 高内聚：所有 UI 更新逻辑封装于此

@onready var gold_label: Label = $HBox/GoldPanel/GoldInner/GoldValue
@onready var inspiration_label: Label = $HBox/InspirationPanel/InspirationInner/InspirationValue

var _display_gold := 0.0
var _display_inspiration := 0.0
var _tween: Tween


func _ready() -> void:
	if not GameManager.is_node_ready():
		await GameManager.ready
	# 初始化显示值与实际一致
	_display_gold = float(GameManager.gold)
	_display_inspiration = float(GameManager.inspiration)
	_refresh_labels()

	# 订阅货币变化信号 —— 观察者模式的核心连接
	GameManager.currency_changed.connect(_on_currency_changed)


func _on_currency_changed(new_gold: int, new_inspiration: int) -> void:
	_animate_to(float(new_gold), float(new_inspiration))


func _animate_to(target_gold: float, target_insp: float) -> void:
	# 终止旧动画，避免快速连续变化时多条 tween 并行写 _display_* 抖动
	if is_instance_valid(_tween):
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)

	var duration := 0.5
	var ease_type := Tween.EASE_OUT
	var trans_type := Tween.TRANS_QUART

	# 金币数字滚动
	_tween.set_ease(ease_type).set_trans(trans_type)
	_tween.tween_method(_update_gold_label, _display_gold, target_gold, duration)

	# 灵感数字滚动
	_tween.set_ease(ease_type).set_trans(trans_type)
	_tween.tween_method(_update_inspiration_label, _display_inspiration, target_insp, duration)


func _update_gold_label(value: float) -> void:
	_display_gold = value
	gold_label.text = "%d" % int(round(value))


func _update_inspiration_label(value: float) -> void:
	_display_inspiration = value
	inspiration_label.text = "%d" % int(round(value))


func _refresh_labels() -> void:
	gold_label.text = "%d" % int(round(_display_gold))
	inspiration_label.text = "%d" % int(round(_display_inspiration))
