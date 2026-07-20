extends Control
## ProductCatalog · 产品目录弹窗（覆盖层）
##
## 列表视图：网格化展示 product_pool 商品（图标占位/名称/价格/配送时长 + 购买按钮）。
## 点「购买」→ 确认视图（显示将扣除的金币）→ 确认 → GameManager.start_order（扣金币）→ 关闭弹窗。
## 金币不足时购买按钮禁用，并在列表上方提示。
##
## 提示：图标占位阶段多为空，自动用灰色方块代替；填了 ProductData.icon 才显示贴图。

const LIST_VIEW := 0
const CONFIRM_VIEW := 1

@export var product_pool: Array[ProductData] = []

var _current_view: int = LIST_VIEW
var _pending: ProductData

@onready var _list_view: Control = $Card/Content/ListView
@onready var _product_list: VBoxContainer = $Card/Content/ListView/ProductList
@onready var _hint: Label = $Card/Content/ListView/Hint
@onready var _close_button: Button = $Card/Content/TitleBar/CloseButton
@onready var _confirm_view: Control = $Card/Content/ConfirmView
@onready var _confirm_label: Label = $Card/Content/ConfirmView/ConfirmLabel
@onready var _confirm_ok: Button = $Card/Content/ConfirmView/ConfirmButton
@onready var _confirm_cancel: Button = $Card/Content/ConfirmView/CancelButton


func _ready() -> void:
	_close_button.pressed.connect(_on_close)
	_confirm_ok.pressed.connect(_on_confirm_ok)
	_confirm_cancel.pressed.connect(_show_list)
	_ensure_pool()
	_populate()
	_show_list()


# ═══════════════════ 数据驱动 ═══════════════════

## 数据驱动回退：未传入 product_pool 时，自动加载内置三个产品，开箱即用
func _ensure_pool() -> void:
	if not product_pool.is_empty():
		return
	for path in ["res://data/product_chair.tres", "res://data/product_desk.tres", "res://data/product_lamp.tres"]:
		var res = load(path)
		if res != null:
			product_pool.append(res)


func _populate() -> void:
	for child in _product_list.get_children():
		child.queue_free()
	if product_pool.is_empty():
		var empty := Label.new()
		empty.text = "（暂无商品）"
		_product_list.add_child(empty)
		return
	for p in product_pool:
		_add_product_row(p)


func _add_product_row(p: ProductData) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var icon := _make_icon(p)
	var name_l := Label.new()
	name_l.text = p.display_name
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var price_l := Label.new()
	price_l.text = "%d 金币" % p.price
	var deliv_l := Label.new()
	deliv_l.text = "%d 分送达" % p.delivery_minutes
	var buy := Button.new()
	buy.text = "购买"
	buy.pressed.connect(func(): _on_buy_pressed(p))
	if GameManager.gold < p.price:
		buy.disabled = true

	row.add_child(icon)
	row.add_child(name_l)
	row.add_child(price_l)
	row.add_child(deliv_l)
	row.add_child(buy)
	_product_list.add_child(row)


func _make_icon(p: ProductData) -> Control:
	if p.icon != null:
		var tex := TextureRect.new()
		tex.texture = p.icon
		tex.custom_minimum_size = Vector2(32, 32)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tex
	var ph := ColorRect.new()
	ph.color = Color(0.7, 0.7, 0.7)
	ph.custom_minimum_size = Vector2(32, 32)
	return ph


# ═══════════════════ 购买 / 确认 ═══════════════════

func _on_buy_pressed(p: ProductData) -> void:
	_pending = p
	_confirm_label.text = "购买 %s？\n将扣除 %d 金币，%d 分钟后到货" % [p.display_name, p.price, p.delivery_minutes]
	_show_confirm()


func _on_confirm_ok() -> void:
	# 二次校验（防止期间金币被其他逻辑消耗）
	if _pending == null or GameManager.gold < _pending.price:
		_show_list()
		return
	GameManager.start_order(_pending)
	queue_free()  # 确认后扣除金币并关闭弹窗


# ═══════════════════ 视图切换 ═══════════════════

func _show_list() -> void:
	_current_view = LIST_VIEW
	_list_view.visible = true
	_confirm_view.visible = false
	_hint.text = "金币：%d" % GameManager.gold
	_populate()  # 重建以刷新购买按钮可用性（金币可能变了）


func _show_confirm() -> void:
	_current_view = CONFIRM_VIEW
	_list_view.visible = false
	_confirm_view.visible = true


func _on_close() -> void:
	queue_free()
