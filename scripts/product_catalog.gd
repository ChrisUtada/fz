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

## 数据驱动回退：未传入 product_pool 时自动加载的内置产品路径（常量化，避免散落魔法串）
const DEFAULT_PRODUCT_PATHS := ["res://data/product_chair.tres", "res://data/product_desk.tres", "res://data/product_lamp.tres"]

## 文字配色：弹窗背景统一深棕（UITheme.BG_PANEL），故所有文字用浅米色高对比；
## 「金币不足」禁用态用偏红（UITheme.TEXT_DISABLED），既可见又提示不可购买。
## 颜色统一取自 UITheme，换肤只改 scripts/ui_theme.gd 一处。

@export var product_pool: Array[ProductData] = []
@export var seed_pool: Array[SeedData] = []      ## 阶段 2.3：种子商品（与产品同列，单独分区）

var _current_view: int = LIST_VIEW
var _pending: ItemData

@onready var _list_view: Control = $Card/Content/ListView
@onready var _product_list: VBoxContainer = $Card/Content/ListView/ProductList
@onready var _hint: Label = $Card/Content/ListView/Hint
@onready var _close_button: Button = $Card/Content/TitleBar/CloseButton
@onready var _confirm_view: Control = $Card/Content/ConfirmView
@onready var _confirm_label: Label = $Card/Content/ConfirmView/ConfirmLabel
@onready var _confirm_ok: Button = $Card/Content/ConfirmView/ConfirmButton
@onready var _confirm_cancel: Button = $Card/Content/ConfirmView/CancelButton


func _ready() -> void:
	var bg := get_node_or_null("Card/Bg") as ColorRect
	if bg != null:
		bg.color = UITheme.BG_PANEL
	_close_button.pressed.connect(_on_close)
	_confirm_ok.pressed.connect(_on_confirm_ok)
	_confirm_cancel.pressed.connect(_show_list)
	# 场景内已有节点也统一上深色文字（标题、金币提示、确认视图等）
	var title := get_node_or_null("Card/Content/TitleBar/Title") as Label
	if title != null:
		_style_label(title)
	_style_label(_hint)
	_style_label(_confirm_label)
	_style_button(_close_button)
	_style_button(_confirm_ok)
	_style_button(_confirm_cancel)
	_ensure_pool()
	_populate()
	_show_list()


# ═══════════════════ 文字配色 ═══════════════════

## 给 Label 覆盖浅米字（深棕底高对比可读）
func _style_label(l: Label) -> void:
	l.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)


## 给 Button 覆盖各状态字体色：统一浅米字；font_disabled_color 用偏红，
## 让「金币不足」禁用态更直观（否则退回默认灰白也可辨，但红字提示更明确）。
func _style_button(b: Button) -> void:
	b.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	b.add_theme_color_override("font_hover_color", UITheme.TEXT_PRIMARY)
	b.add_theme_color_override("font_pressed_color", UITheme.TEXT_PRIMARY)
	b.add_theme_color_override("font_focus_color", UITheme.TEXT_PRIMARY)
	b.add_theme_color_override("font_disabled_color", UITheme.TEXT_DISABLED)


# ═══════════════════ 数据驱动 ═══════════════════

## 数据驱动回退：未传入 product_pool 时，自动加载内置三个产品，开箱即用
func _ensure_pool() -> void:
	if not product_pool.is_empty():
		return
	for path in DEFAULT_PRODUCT_PATHS:
		var res = load(path)
		if res != null:
			product_pool.append(res)


func _populate() -> void:
	for child in _product_list.get_children():
		child.queue_free()
	if product_pool.is_empty() and seed_pool.is_empty():
		var empty := Label.new()
		empty.text = "（暂无商品）"
		_style_label(empty)
		_product_list.add_child(empty)
		return
	for p in product_pool:
		_add_product_row(p)
	if not seed_pool.is_empty():
		var header := Label.new()
		header.text = "—— 种子 ——"
		_style_label(header)
		_product_list.add_child(header)
		for s in seed_pool:
			_add_seed_row(s)


func _add_product_row(p: ProductData) -> void:
	_add_item_row(p, "%d 分送达" % p.delivery_minutes)


func _add_seed_row(s: SeedData) -> void:
	_add_item_row(s, "5 分送达")


## 通用行：产品与种子共用（ItemData 基类字段），配送文案由调用方给出
func _add_item_row(item: ItemData, delivery_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var icon := Utils.make_icon(item)
	var name_l := Label.new()
	name_l.text = item.display_name
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_label(name_l)
	var price_l := Label.new()
	price_l.text = "%d 金币" % item.price
	_style_label(price_l)
	var deliv_l := Label.new()
	deliv_l.text = delivery_text
	_style_label(deliv_l)
	var buy := Button.new()
	buy.text = "购买"
	buy.pressed.connect(_on_buy_pressed.bind(item))
	_style_button(buy)
	if GameManager.gold < item.price:
		# 买不起：禁用并给出可见提示（原先只灰掉按钮、浅底浅字像「无响应」）
		buy.disabled = true
		buy.text = "金币不足"
		buy.tooltip_text = "需要 %d 金币，当前 %d" % [item.price, GameManager.gold]

	row.add_child(icon)
	row.add_child(name_l)
	row.add_child(price_l)
	row.add_child(deliv_l)
	row.add_child(buy)
	_product_list.add_child(row)


# 图标生成已统一到 Utils.make_icon（见 scripts/utils.gd）


# ═══════════════════ 购买 / 确认 ═══════════════════

func _on_buy_pressed(item: ItemData) -> void:
	_pending = item
	var dur_text := "5 分"            ## 种子等无 delivery_minutes 的物品用默认配送时长
	if item is ProductData:
		dur_text = "%d 分" % item.delivery_minutes
	_confirm_label.text = "购买 %s？\n将扣除 %d 金币，%s后到货" % [item.display_name, item.price, dur_text]
	_show_confirm()


func _on_confirm_ok() -> void:
	# 二次校验（防止期间金币被其他逻辑消耗）
	if _pending == null or GameManager.gold < _pending.price:
		_show_list()
		return
	# 校验下单结果：成功才关闭；失败（金币不足等）退回列表刷新可用性，不静默关闭
	if GameManager.start_order(_pending):
		queue_free()  # 确认后扣除金币并关闭弹窗
	else:
		_show_list()


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
