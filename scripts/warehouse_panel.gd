extends Control
## WarehousePanel · 仓库全局浮层（覆盖层，任意屏可开）
##
## 数据驱动：展示统一 inventory（GameManager）按分类的已拥有物品。
##   - 顶部分类 chips：全部 / 服装 / 种子 / 作物 / 材料 / 摆放
##   - 主体：紧凑图标网格（带数量角标），可滚动
##   - 监听 GameManager.inventory_changed 增量刷新（仅更新当前 filter 的变化项，避免整表重建）
##   - 角落「🎒 总数」徽标实时反映总库存
##   - 可摆放物品（is_placeable）统一收进「摆放」标签页，显示「摆放」→ placement_requested 交给 Main

signal placement_requested(data: ItemData)   ## 点击「摆放」时发出，由 Main 转发给 PlacementManager

const COLUMNS := 4

## 分类筛选：label + 值
##   cat >= 0           → ItemData.Category 枚举值（服装/种子/作物/材料）
##   cat == -1（全部）  → 上述分类（跳过摆放物）+ 摆放物
##   cat == -2（摆放）  → is_placeable 物品（台灯/桌子/花盆等）
const _FILTERS := [
	{"label": "全部", "cat": -1},
	{"label": "服装", "cat": ItemData.Category.CLOTHING},
	{"label": "种子", "cat": ItemData.Category.SEED},
	{"label": "作物", "cat": ItemData.Category.CROP},
	{"label": "材料", "cat": ItemData.Category.MATERIAL},
	{"label": "摆放", "cat": -2},
]

@onready var _chips: HBoxContainer = $Card/Content/Chips
@onready var _grid: GridContainer = $Card/Content/Scroll/Grid
@onready var _close_btn: Button = $Card/Content/TitleBar/CloseButton
@onready var _total_badge: Label = $Card/Content/TitleBar/TotalBadge

var _filter: int = -1                 ## 当前筛选（-1 = 全部）
var _cells: Dictionary = {}           ## id -> cell 根节点（增量刷新用）

func _ready() -> void:
	var bg := $Card/Bg as ColorRect
	if bg != null:
		bg.color = UITheme.BG_PANEL
	var title := $Card/Content/TitleBar/Title as Label
	if title != null:
		title.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	_total_badge.add_theme_color_override("font_color", UITheme.TEXT_GOLD)
	_close_btn.pressed.connect(_on_close)
	_build_chips()
	_populate()
	GameManager.inventory_changed.connect(_on_inventory_changed)
	visibility_changed.connect(_on_visibility_changed)


## 构建分类筛选 chips（5 枚按钮，代码填充）
func _build_chips() -> void:
	for f in _FILTERS:
		var btn := Button.new()
		btn.text = f["label"]
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
		btn.pressed.connect(_on_chip_pressed.bind(int(f["cat"])))
		_chips.add_child(btn)


func _on_chip_pressed(cat: int) -> void:
	if _filter == cat:
		return
	_filter = cat
	_populate()                         ## 切换分类：重建网格


## 当前 filter 应展示的物品列表：[{data, count}]
func _items_for_filter() -> Array:
	if _filter == -1:
		var out: Array = []
		for cat in [
			ItemData.Category.CLOTHING, ItemData.Category.SEED,
			ItemData.Category.CROP, ItemData.Category.MATERIAL
		]:
			out.append_array(GameManager.get_by_category(cat))   # 默认跳过摆放物
		out.append_array(GameManager.get_placeables())            # 摆放物单独并入「全部」
		return out
	if _filter == -2:
		return GameManager.get_placeables()
	return GameManager.get_by_category(_filter)                  # 分类标签页默认跳过摆放物


## 重建当前 filter 的全部 cell（filter 切换 / 首次 / 可见刷新时调用）
func _populate() -> void:
	for c in _grid.get_children():
		c.queue_free()
	_cells.clear()
	for entry in _items_for_filter():
		var cell := _make_cell(entry["data"], entry["count"])
		_grid.add_child(cell)
		_cells[entry["data"].id] = cell
	_update_total()


## 增量刷新：仅更新当前 filter 中变化的 cell（新增 / 移除 / 数量变化），避免整表重建
func _refresh_counts() -> void:
	var items: Array = _items_for_filter()
	var want: Dictionary = {}
	for e in items:
		want[e["data"].id] = e["count"]
	# 移除不再拥有的
	for id in _cells.keys():
		if not want.has(id):
			var c = _cells[id]
			if is_instance_valid(c):
				c.queue_free()
			_cells.erase(id)
	# 更新已有 + 新增
	for e in items:
		var id: String = e["data"].id
		var count: int = e["count"]
		if _cells.has(id):
			var lbl: Label = _cells[id].get_node_or_null("CountBadge")
			if lbl != null:
				var show_count := count
				if e["data"] is ClothesData:
					show_count = max(0, count - GameManager.get_worn_count(id))
				lbl.text = "x%d" % show_count
		else:
			var cell := _make_cell(e["data"], count)
			_grid.add_child(cell)
			_cells[id] = cell
	_update_total()


## 构建一个网格单元：图标 + 名称 + 数量角标（+ 可摆放物的「摆放」按钮）
func _make_cell(data: ItemData, count: int) -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(96, 96)
	# 图标
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = data.icon
	icon.custom_minimum_size = Vector2(48, 48)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(24, 4)
	cell.add_child(icon)
	# 名称
	var name_l := Label.new()
	name_l.text = data.display_name
	name_l.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 12)
	name_l.position = Vector2(2, 54)
	name_l.size = Vector2(92, 16)
	cell.add_child(name_l)
	# 数量角标（右上）：服装类显示「可上架数」（库存−穿戴），其余显示原始库存
	var badge := Label.new()
	badge.name = "CountBadge"
	var show_count := count
	if data is ClothesData:
		show_count = max(0, count - GameManager.get_worn_count(data.id))
	badge.text = "x%d" % show_count
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", UITheme.TEXT_GOLD)
	badge.position = Vector2(60, 2)
	cell.add_child(badge)
	# 可摆放（is_placeable 且确有场景）：摆放按钮
	if data.is_placeable and data.placeable_scene != null:
		var place_btn := Button.new()
		place_btn.text = "摆放"
		place_btn.add_theme_font_size_override("font_size", 12)
		place_btn.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
		place_btn.position = Vector2(22, 72)
		place_btn.pressed.connect(func(): placement_requested.emit(data))
		cell.add_child(place_btn)
	return cell


func _update_total() -> void:
	_total_badge.text = "🎒 %d" % GameManager.get_total_count()


func _on_inventory_changed() -> void:
	if visible:
		_refresh_counts()


func _on_visibility_changed() -> void:
	if visible:
		_refresh_counts()                 ## 切回时同步最新库存


func _on_close() -> void:
	queue_free()
