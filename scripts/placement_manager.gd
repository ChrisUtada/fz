class_name PlacementManager
extends Node
## PlacementManager · 摆放物生命周期管理（非 autoload，挂 Main 下常驻，遵循 autoload 最小化）
## 职责：从产品数据实例化摆放物、移除、记录位置、存档 / 还原。
## 存档：user://placements.cfg，记录每个摆放物 {id, scene_path, x, y, scale}。

const SAVE_PATH := "user://placements.cfg"

## 桌面装饰花盆限量（阶段 4.6）：花盆除在种植屏功能槽外，还可经仓库摆桌面作装饰，
## 但数量限量，避免纯装饰盆铺满桌面。功能盆（种植屏 6 槽）不计入此限。
const DESKTOP_POT_LIMIT := 3
const POT_ID := "pot"                  ## 历史兜底 id（data/product_pot.tres）；优先用 init(pot_id=) 注入的运行时值
## 首次摆放的随机中心（桌面中央偏右下）。原散落的 (340,240) 魔法数收口到此常量。
const DEFAULT_SPAWN_CENTER := Vector2(340.0, 240.0)

signal placement_rejected(reason: String)

var _container: Node2D
var _data_by_id: Dictionary = {}      # id -> ProductData
var _pot_id := POT_ID                 # 装饰花盆限量判定用的 id，由 init 注入（Main 按 garden_placement 推导）
var _pool_ready := false
var _save_timer: Timer                # 落盘节流（摆放移动频繁，0.5s 合并一次）


## Main._ready 调用：注入产品池与摆放容器，建索引并还原存档
## pot_id：装饰花盆限量判定用的产品 id（Main 按 garden_placement 推导，找不到时兜底 "pot"）
func init(pool: Array[ProductData], container: Node2D, pot_id: String = POT_ID) -> void:
	_container = container
	_pot_id = pot_id
	_create_save_timer()
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
	if data.id == _pot_id:
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
	inst.global_position = DEFAULT_SPAWN_CENTER + Vector2(randf_range(-80.0, 80.0), randf_range(-50.0, 50.0))
	_container.add_child(inst)        # 先入树：_ready 创建 _sprite 后才能 apply_data
	inst.apply_data(data)
	inst.moved.connect(_on_placed_moved)
	save_placements()


func _on_placed_moved(_p: Placeable) -> void:
	_request_save()


## 落盘节流：0.5s 内连续的摆放移动只合并保存一次（避免拖拽时每帧写盘卡顿）。
## 即时存档（spawn / remove）仍直接调 save_placements()，不受此节流影响。
func _request_save() -> void:
	if _save_timer != null:
		_save_timer.start()   # 已运行则重启计时窗口


func _flush_save() -> void:
	save_placements()


func _create_save_timer() -> void:
	_save_timer = Timer.new()
	_save_timer.name = "SaveDebounceTimer"
	_save_timer.wait_time = 0.5
	_save_timer.one_shot = true
	_save_timer.timeout.connect(_flush_save)
	add_child(_save_timer)


func _exit_tree() -> void:
	# 退出前补齐尚未触发的节流存档，避免最后 0.5s 内的移动丢失
	if _save_timer != null and not _save_timer.is_stopped():
		_flush_save()


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
		# 跳过已排队删除的节点：queue_free() 延迟到帧末执行，此刻仍在 get_children() 里，
		# 若不排除会被重新写入存档，导致下次 restore() 复活（摆放物删不掉，越删越多）。
		if c is Placeable and c.data != null and not c.is_queued_for_deletion():
			var rec := {
				"id": c.data.id,
				"scene_path": c.data.placeable_scene.resource_path,
				"x": c.global_position.x,
				"y": c.global_position.y,
				"scale": c.scale.x
			}
			cfg.set_value("placed", str(c.get_instance_id()), rec)
	Utils.write_save_version(cfg)
	if cfg.save(SAVE_PATH) != OK:
		push_warning("PlacementManager.save_placements: 存档写入失败 %s" % SAVE_PATH)


func restore() -> void:
	if _container == null:
		return
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	# 旧档迁移占位：当前 SAVE_VERSION=1，v0（无版本戳）或更低在此扩展迁移逻辑。
	# 现有格式与 v1 一致，无需转换；仅作框架起步，统一各存档的版本判定入口。
	if Utils.is_legacy_save(cfg):
		pass
	if not cfg.has_section("placed"):
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
		inst.global_position = Vector2(float(rec.get("x", DEFAULT_SPAWN_CENTER.x)), float(rec.get("y", DEFAULT_SPAWN_CENTER.y)))
		var s: float = float(rec.get("scale", 1.0))
		inst.scale = Vector2(s, s)
		_container.add_child(inst)        # 先入树：_ready 创建 _sprite 后才能 apply_data
		if data != null:
			inst.apply_data(data)
		inst.moved.connect(_on_placed_moved)
