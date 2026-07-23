extends Control
## WorkshopScreen · 工坊屏（阶段 2.4）
## 两子页：A「制作」（蓝图列表，消耗材料产出成品） / B「分解」（背包可分解物 → 材料）。
## 数据全部走 GameManager（blueprints / inventory / craft / decompose），本屏只渲染与交互。

@onready var _make_btn: Button = $Bg/Layout/SubTabs/MakeBtn
@onready var _decompose_btn: Button = $Bg/Layout/SubTabs/DecomposeBtn
@onready var _make_scroll: ScrollContainer = $Bg/Layout/MakeScroll
@onready var _decompose_scroll: ScrollContainer = $Bg/Layout/DecomposeScroll
@onready var _make_list: VBoxContainer = $Bg/Layout/MakeScroll/MakeList
@onready var _decompose_list: VBoxContainer = $Bg/Layout/DecomposeScroll/DecomposeList

## 颜色统一取自 UITheme（scripts/ui_theme.gd），换肤只改一处。
const _CARD_BG := UITheme.BG_SURFACE
const _CARD_BORDER := UITheme.BORDER
const _LOCKED_COL := UITheme.TEXT_DIM
const _ACCENT_BG := UITheme.BG_ACCENT
const _DIM := UITheme.TEXT_DIM
const _TEXT := UITheme.TEXT_PRIMARY

var _active: String = "make"     # "make" | "decompose"


func _ready() -> void:
	_make_btn.pressed.connect(_on_make_pressed)
	_decompose_btn.pressed.connect(_on_decompose_pressed)
	GameManager.blueprint_unlocked.connect(_on_blueprint_unlocked)
	GameManager.inventory_changed.connect(_on_inventory_changed)
	visibility_changed.connect(_on_visibility_changed)
	_set_sub("make")


func _on_make_pressed() -> void:
	_set_sub("make")


func _on_decompose_pressed() -> void:
	_set_sub("decompose")


## 切换子页：显隐对应面板 + 高亮当前按钮
func _set_sub(sub: String) -> void:
	_active = sub
	_make_scroll.visible = sub == "make"
	_decompose_scroll.visible = sub == "decompose"
	_style_tab(_make_btn, sub == "make")
	_style_tab(_decompose_btn, sub == "decompose")
	_render_active()


func _style_tab(btn: Button, active: bool) -> void:
	btn.flat = false
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	if active:
		sb.bg_color = _ACCENT_BG
		btn.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	else:
		sb.bg_color = UITheme.BG_SURFACE
		btn.add_theme_color_override("font_color", _DIM)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)


func _render_active() -> void:
	if _active == "make":
		_render_make()
	else:
		_render_decompose()


func _on_visibility_changed() -> void:
	if visible:
		_render_active()


func _on_blueprint_unlocked(_id: String) -> void:
	if visible and _active == "make":
		_render_make()


func _on_inventory_changed() -> void:
	if visible:
		_render_active()


# ───────────────────────── 子页 A：制作 ─────────────────────────

func _render_make() -> void:
	_clear(_make_list)
	var bps := GameManager.get_all_blueprints()
	if bps.is_empty():
		_make_list.add_child(_empty_label("（暂无蓝图）"))
		return
	for bp in bps:
		if not GameManager.is_blueprint_unlocked(bp.id):
			_make_list.add_child(_build_locked_card(bp))
		else:
			_make_list.add_child(_build_blueprint_card(bp))


func _build_blueprint_card(bp: BlueprintData) -> Panel:
	var ok := _materials_sufficient(bp)
	var sub := "材料：" + bp.materials_text()
	return _make_card(bp.icon, bp.display_name, sub, ("制作" if ok else "材料不足"), ok, _on_craft.bind(bp.id))


func _build_locked_card(bp: BlueprintData) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(0, 52)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.BG_PANEL
	sb.border_color = UITheme.BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(row)

	var name_l := Label.new()
	name_l.text = bp.display_name
	name_l.add_theme_font_size_override("font_size", 14)
	name_l.add_theme_color_override("font_color", _LOCKED_COL)
	row.add_child(name_l)

	var lock := Label.new()
	lock.text = "🔒 需灵感 %d" % bp.unlock_inspiration
	lock.add_theme_font_size_override("font_size", 12)
	lock.add_theme_color_override("font_color", _LOCKED_COL)
	row.add_child(lock)
	return p


func _on_craft(bp_id: String) -> void:
	GameManager.craft(bp_id)


# ───────────────────────── 子页 B：分解 ─────────────────────────

func _render_decompose() -> void:
	_clear(_decompose_list)
	var items := GameManager.get_decomposables()
	if items.is_empty():
		_decompose_list.add_child(_empty_label("（暂无可分解的物品）"))
		return
	for entry in items:
		var d: ItemData = entry["data"]
		var cnt: int = entry["count"]
		var sub := "分解 → " + _recipe_text(d)
		_decompose_list.add_child(_make_card(d.icon, "%s ×%d" % [d.display_name, cnt], sub, "分解", true, _on_decompose.bind(d.id)))


func _on_decompose(item_id: String) -> void:
	GameManager.decompose(item_id)


# ───────────────────────── 通用卡片 ─────────────────────────

## 一张横向卡片：图标 | 名称+副文本 | 右侧操作按钮。交互干净、无堆叠。
func _make_card(icon: Texture2D, name_text: String, sub_text: String, btn_text: String, btn_enabled: bool, on_press: Callable) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(0, 64)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = _CARD_BG
	sb.border_color = _CARD_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(row)

	if icon != null:
		var tex := TextureRect.new()
		tex.texture = icon
		tex.custom_minimum_size = Vector2(40, 40)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tex)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)

	var name_l := Label.new()
	name_l.text = name_text
	name_l.add_theme_font_size_override("font_size", 15)
	name_l.add_theme_color_override("font_color", _TEXT)
	info.add_child(name_l)

	if not sub_text.is_empty():
		var sub_l := Label.new()
		sub_l.text = sub_text
		sub_l.add_theme_font_size_override("font_size", 12)
		sub_l.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		info.add_child(sub_l)

	var btn := Button.new()
	btn.text = btn_text
	btn.custom_minimum_size = Vector2(76, 36)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_action_btn(btn, btn_enabled)
	if btn_enabled and on_press.is_valid():
		btn.pressed.connect(on_press)
	row.add_child(btn)
	return p


func _style_action_btn(btn: Button, enabled: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(6)
	if enabled:
		sb.bg_color = _ACCENT_BG
		btn.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	else:
		sb.bg_color = UITheme.BG_SURFACE
		btn.add_theme_color_override("font_color", _DIM)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("disabled", sb)
	btn.disabled = not enabled


func _empty_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", _LOCKED_COL)
	return l


## 重渲染前先把旧卡片从树中移除（避免 queue_free 延迟导致的堆叠/混乱）
func _clear(list: VBoxContainer) -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()


# ───────────────────────── 数据辅助 ─────────────────────────

func _materials_sufficient(bp: BlueprintData) -> bool:
	for mc in bp.required_materials:
		if mc == null or mc.item == null or mc.count <= 0:
			continue
		if GameManager.get_count(mc.item.id) < mc.count:
			return false
	return true


func _recipe_text(d: ItemData) -> String:
	var parts: Array = []
	for e in d.decompose_recipe:
		if not e is Dictionary:
			continue
		var norm := {}
		for k in e.keys():
			norm[str(k)] = e[k]
		var iid: String = str(norm.get("item_id", ""))
		var n: int = int(norm.get("count", 0))
		if iid.is_empty() or n <= 0:
			continue
		var item: ItemData = GameManager.get_item(iid)
		var nm: String = iid if item == null else item.display_name
		parts.append("%s×%d" % [nm, n])
	return "  ".join(parts)
