class_name PlacementManager
extends Node
## PlacementManager · 摆放物生命周期管理（非 autoload，挂 Main 下常驻，遵循 autoload 最小化）
## 职责：从产品数据实例化摆放物、移除、记录位置、存档 / 还原。
## 存档：user://placements.cfg，记录每个摆放物 {id, scene_path, x, y, scale}。

const SAVE_PATH := "user://placements.cfg"

## 桌面装饰花盆限量（阶段 4.6）：花盆除在种植屏功能槽外，还可经仓库摆桌面作装饰，
## 但数量限量，避免纯装饰盆铺满桌面。功能盆（种植屏 6 槽）不计入此限。
const DESKTOP_POT_LIMIT := 3
const POT_ID := "pot"                  ## 与 data/product_pot.tres 的 id 对齐

signal placement_rejected(reason: String)

var _container: Node2D
var _data_by_id: Dictionary = {}      # id -> ProductData
var _pool_ready := false


## Main._ready 调用：注入产品池与摆放容器，建索引并还原存档
func init(pool: Array[ProductData], container: Node2D) -> void:
	_container = container
	for p in pool:
		if p != null and not p.id.is_empty():
			_data_by_id[p.id] = p
	_pool_ready = true
	restore()


## 从产品数据实例化一个摆放物到世界（首次随机位置），并立即存档
func spawn_from_product(data: ProductData) -> void:
	if not _pool_ready or _container == null:
		return
	if data == null or data.placeable_scene == null:
		push_warning("PlacementManager.spawn_from_product: 数据或 placeable_scene 缺失，无法摆放 %s" % (data.id if data != null else "null"))
		return
	# 装饰花盆限量（阶段 4.6）：仅统计已摆到桌面的花盆，功能盆（种植屏槽）不计入
	if data.id == POT_ID:
		var count := 0
		for c in _container.get_children():
			if c is Placeable and c.data != null and c.data.id == POT_ID:
				count += 1
		if count >= DESKTOP_POT_LIMIT:
			push_warning("PlacementManager: 装饰花盆已达上限（%d），本次摆放被忽略" % DESKTOP_POT_LIMIT)
			placement_rejected.emit("装饰花盆已达上限（%d）" % DESKTOP_POT_LIMIT)
			return
	var inst: Placeable = data.placeable_scene.instantiate()
	if inst == null:
		return
	inst.global_position = Vector2(340.0 + randf_range(-80.0, 80.0), 240.0 + randf_range(-50.0, 50.0))
	_container.add_child(inst)        # 先入树：_ready 创建 _sprite 后才能 apply_data
	inst.apply_data(data)
	inst.moved.connect(_on_placed_moved)
	save_placements()


func _on_placed_moved(_p: Placeable) -> void:
	save_placements()


## 移除一个摆放物（预留给未来的移除 UI）
func remove_placed(p: Placeable) -> void:
	if is_instance_valid(p):
		p.queue_free()
	save_placements()


func save_placements() -> void:
	if _container == null:
		return
	var cfg := ConfigFile.new()
	for c in _container.get_children():
		if c is Placeable and c.data != null:
			var rec := {
				"id": c.data.id,
				"scene_path": c.data.placeable_scene.resource_path,
				"x": c.global_position.x,
				"y": c.global_position.y,
				"scale": c.scale.x
			}
			cfg.set_value("placed", str(c.get_instance_id()), rec)
	cfg.save(SAVE_PATH)


func restore() -> void:
	if _container == null:
		return
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for key in cfg.get_section_keys("placed"):
		var rec: Dictionary = cfg.get_value("placed", key)
		var scene: PackedScene = load(rec.get("scene_path", ""))
		if scene == null:
			continue
		var inst: Placeable = scene.instantiate()
		if inst == null:
			continue
		var data: ProductData = _data_by_id.get(rec.get("id", ""), null)
		inst.global_position = Vector2(float(rec.get("x", 340.0)), float(rec.get("y", 240.0)))
		var s: float = float(rec.get("scale", 1.0))
		inst.scale = Vector2(s, s)
		_container.add_child(inst)        # 先入树：_ready 创建 _sprite 后才能 apply_data
		if data != null:
			inst.apply_data(data)
		inst.moved.connect(_on_placed_moved)
