extends Control
## FarmScreen · 种植屏（阶段 2.3）
## 6 个功能槽，每槽四态：空 → 有盆无种 → 生长中 → 成熟。
## 数据全部走 GameManager 农场槽方法（place_pot/plant/get_growth_info/harvest/clear_slot），
## 本屏只做渲染与交互，符合数据-外观分离 + SRP。

const COLS := 3
const SLOT_COUNT := 6

@export var pot_id: String = ""              ## 功能花盆 id 覆盖；留空则按 ItemData.garden_placement 标志自动识别首个可用花盆（推荐留空）

signal shop_requested                          ## 资源不足时请求打开商城（main 接 _on_phone_shop_requested）

@onready var _grid: GridContainer = $Bg/Grid
var _slot_nodes: Array = []                   ## 每个槽的根 Panel（meta 存 slot/vbox/state/progress/remain）

func _ready() -> void:
	_grid.columns = COLS
	for i in range(SLOT_COUNT):
		var slot := _make_slot(i)
		_grid.add_child(slot)
		_slot_nodes.append(slot)
	GameManager.farm_changed.connect(_on_farm_changed)
	visibility_changed.connect(_on_visibility_changed)
	_rebuild_all()


## 单个槽：Panel（拦截点击，不穿透家园）+ 内部 VBoxContainer 排布内容
func _make_slot(i: int) -> Panel:
	var p := Panel.new()
	p.set_meta("slot", i)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.custom_minimum_size = Vector2(190, 140)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	## 微弱底色区分格子（深棕面板上的稍浅棕）
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.BG_SURFACE
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(6)
	p.add_theme_stylebox_override("panel", sb)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	p.add_child(vbox)
	p.set_meta("vbox", vbox)
	return p


func _content(slot: Panel) -> VBoxContainer:
	if not slot.has_meta("vbox"):
		return null
	return slot.get_meta("vbox")


func _on_farm_changed() -> void:
	if visible:
		_rebuild_all()


func _on_visibility_changed() -> void:
	if visible:
		_rebuild_all()


func _rebuild_all() -> void:
	for i in range(SLOT_COUNT):
		_rebuild_slot(i)


## 按槽状态重建内容；state 存入 meta，供 _process 决定是否需要逐帧刷进度
func _rebuild_slot(i: int) -> void:
	var slot: Panel = _slot_nodes[i]
	var vbox := _content(slot)
	if vbox == null:
		return
	for c in vbox.get_children():
		c.queue_free()
	var s: Dictionary = GameManager.farm_slots[i] if GameManager.farm_slots.size() > i else {}
	var has_pot: bool = not str(s.get("pot_id", "")).is_empty()
	var seed_id: String = str(s.get("seed_id", ""))
	var state: int = -1   # 0=空 1=有盆无种 2=生长中 3=成熟
	if not has_pot:
		state = 0
	elif seed_id.is_empty():
		state = 1
	else:
		state = 3 if GameManager.is_slot_mature(i) else 2
	slot.set_meta("state", state)
	match state:
		0: _build_empty(slot, i)
		1: _build_potted(slot, i)
		2: _build_growing(slot, i)
		3: _build_mature(slot, i)


func _build_empty(slot: Panel, i: int) -> void:
	var vbox := _content(slot)
	var pid := _resolve_pot_id()
	if not pid.is_empty() and GameManager.get_count(pid) > 0:
		_add_button(vbox, "＋ 放花盆", _on_place_pot.bind(i))
	else:
		_add_label(vbox, "空槽")
		_add_button(vbox, "去商城买花盆", _emit_shop)


func _build_potted(slot: Panel, i: int) -> void:
	var vbox := _content(slot)
	_add_label(vbox, "已放花盆")
	var seeds := GameManager.get_by_category(ItemData.Category.SEED)
	if seeds.is_empty():
		_add_button(vbox, "去商城买种子", _emit_shop)
	else:
		_add_label(vbox, "选种子：")
		for entry in seeds:
			var sd: ItemData = entry["data"]
			var cnt: int = entry["count"]
			_add_button(vbox, "%s ×%d" % [sd.display_name, cnt], _on_plant.bind(i, sd.id))
	# 回收花盆（花盆退回库存）
	_add_button(vbox, "清空", _on_clear.bind(i))


func _build_growing(slot: Panel, i: int) -> void:
	var vbox := _content(slot)
	var info: Dictionary = GameManager.get_growth_info(i)
	var name: String = info.get("stage_name", "生长中") if not info.is_empty() else "生长中"
	_add_label(vbox, name)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	vbox.add_child(bar)
	slot.set_meta("progress", bar)
	var rem := Label.new()
	rem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(rem)
	slot.set_meta("remain", rem)
	_add_button(vbox, "清空", _on_clear.bind(i))


func _build_mature(slot: Panel, i: int) -> void:
	var vbox := _content(slot)
	_add_label(vbox, "成熟！可采摘")
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	bar.value = 100.0
	vbox.add_child(bar)
	_add_button(vbox, "采摘", _on_harvest.bind(i))


func _add_label(vbox: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(l)


func _add_button(vbox: VBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	vbox.add_child(b)


func _emit_shop() -> void:
	shop_requested.emit()


## 解析当前可用花盆 id：优先用导出覆盖 pot_id，否则按 garden_placement 标志自动取首个库存>0 的园艺盆
func _resolve_pot_id() -> String:
	if not pot_id.is_empty():
		return pot_id
	for e in GameManager.get_garden_pots():
		if e["count"] > 0:
			return e["data"].id
	return ""


func _on_place_pot(i: int) -> void:
	var pid := _resolve_pot_id()
	if pid.is_empty() or GameManager.get_count(pid) <= 0:
		_emit_shop()
		return
	GameManager.place_pot(i, pid)


func _on_plant(i: int, seed_id: String) -> void:
	GameManager.plant(i, seed_id)


func _on_harvest(i: int) -> void:
	GameManager.harvest(i)


func _on_clear(i: int) -> void:
	GameManager.clear_slot(i)


## 逐帧更新生长中槽的进度条与剩余时间（仅 state==2 需要；成熟槽只刷剩余文案）
func _process(_delta: float) -> void:
	if not visible:
		return
	for i in range(SLOT_COUNT):
		var slot: Panel = _slot_nodes[i]
		if not slot.has_meta("state"):
			continue
		var st: int = slot.get_meta("state")
		if st == 2:
			var info: Dictionary = GameManager.get_growth_info(i)
			if info.is_empty():
				continue
			if slot.has_meta("progress"):
				slot.get_meta("progress").value = info.get("progress", 0.0) * 100.0
			if slot.has_meta("remain"):
				slot.get_meta("remain").text = "剩余 %s" % _fmt_time(info.get("remaining_sec", 0.0))
		elif st == 3:
			# 成熟槽由 _build_mature 静态展示"成熟！可采摘"，不保证有 rem 标签，
			# 故用 has_meta 守卫，避免 get_meta(key, null) 在 key 缺失时 ERR_FAIL。
			if slot.has_meta("remain"):
				slot.get_meta("remain").text = "可采摘"


func _fmt_time(sec: float) -> String:
	var s := int(ceil(sec))
	var m := s / 60
	var ss := s % 60
	return "%02d:%02d" % [m, ss]
