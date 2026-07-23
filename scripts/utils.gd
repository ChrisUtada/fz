class_name Utils
extends RefCounted
## Utils · 无状态公共工具（全局可直接调用，无需 autoload）。
##
## 抽自多处重复的样板：时间格式化、图标生成、物理点命中、拖拽阈值判定。
## 目的：消除 P2 重复代码（原 _format_time 4 处 / _make_icon 3 处 /
## pet·customer contains_point 样板 / phone·clothing_rack·pet 拖拽阈值判定）。

## 秒数 → "MM:SS"（向上取整到整秒）。
static func format_time(total_sec: float) -> String:
	var s := int(ceil(total_sec))
	var m := int(s / 60)
	var sec := s % 60
	return "%02d:%02d" % [m, sec]


## 由 ItemData（含 ProductData 子类）生成 32×32 图标控件；无图标则回退占位块。
static func make_icon(data: ItemData) -> Control:
	if data != null and data.icon != null:
		var tex := TextureRect.new()
		tex.texture = data.icon
		tex.custom_minimum_size = Vector2(32, 32)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tex
	var ph := ColorRect.new()
	ph.color = UITheme.BG_SURFACE
	ph.custom_minimum_size = Vector2(32, 32)
	return ph


## 物理点查询：global_pos 是否落在 area 的碰撞形状内（collision_mask 指定层）。
## 统一 pet / customer 的 contains_point 样板（仅 mask 与 area 变量不同）。
static func point_in_area(global_pos: Vector2, area: Node2D, mask: int) -> bool:
	var space := area.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = global_pos
	query.collision_mask = mask
	query.collide_with_bodies = false
	query.collide_with_areas = true
	var results := space.intersect_point(query)
	for r in results:
		if r.collider == area:
			return true
	return false


## 拖拽阈值判定：当前指针与按下点距离是否越过阈值（默认 4px）。
## 统一 phone / clothing_rack / pet 三处重复的 distance_to(...) >= DRAG_THRESHOLD。
static func exceeds_drag_threshold(current: Vector2, pressed: Vector2, threshold := 4.0) -> bool:
	return current.distance_to(pressed) >= threshold
