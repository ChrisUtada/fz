class_name SeedData
extends ItemData
## SeedData · 种子数据模型（继承统一 ItemData，category=SEED）
##
## 职责：只描述"这颗种子种下去会长什么、长多久"。
## 通用字段（id/display_name/icon/price/description/category…）继承自 ItemData；
## 本类只补充种植专属字段。纯数据，不持有节点/逻辑。
##
## 三阶段生长（墙钟计时，检查器可配分钟数）：
##   苗(sprout) → 成长(growing) → 成熟(mature)
## 成熟后采摘产出 `crop_output_id` 对应的 CROP 物品（进 inventory[CROP]）。
##
## 购买/入库：种子作为 SEED 类商品，购买流程（电话→产品目录）走统一定价 price，
## 收货后 `GameManager.add_item(id, 1)` 进 inventory[SEED]（与其他物品一致）。
##
## 种植逻辑（plant/compute_stage/harvest）由 GameManager 农场槽（阶段 0.9）+ 种植屏（2.3）实现，
## 本类只提供数据，符合数据-逻辑分离原则。
##
## 注意：.tres 头部必须写成 `[gd_resource type="Resource" script_class="SeedData" ...]`，
##       绝不能把自定义 class_name 放进 type=（否则运行时报 Cannot get class 'SeedData'）。

@export var sprout_minutes: int = 2     ## 苗阶段时长（分钟）；>0
@export var growing_minutes: int = 5    ## 成长阶段时长（分钟）；>0
@export var mature_minutes: int = 3     ## 成熟阶段时长（分钟）；>0

## 成熟后产出的 CROP 物品 id（对应一个 category=CROP 的 ItemData，需提前注册进 _item_registry）
@export var crop_output_id: String = ""

## 三阶段显示图标（可选）：[0]=苗 / [1]=成长 / [2]=成熟。
## 留空时种植屏回退到通用占位图标（或本类 icon）。
@export var stage_icons: Array[Texture2D] = []


func _init() -> void:
	category = ItemData.Category.SEED


## 总生长时长（分钟）= 三阶段之和；供 UI 预估/进度换算用。
func total_grow_minutes() -> int:
	return maxi(1, sprout_minutes) + maxi(1, growing_minutes) + maxi(1, mature_minutes)


## 按"已生长分钟数"返回当前阶段（0=苗, 1=成长, 2=成熟）。供 GameManager.compute_stage 复用。
## grown_minutes：从种下到现在的墙钟分钟数。
func stage_at(grown_minutes: float) -> int:
	var s := float(maxi(1, sprout_minutes))
	var g := float(maxi(1, growing_minutes))
	var m := float(maxi(1, mature_minutes))
	if grown_minutes < s:
		return 0
	if grown_minutes < s + g:
		return 1
	return 2  # 进入成熟阶段（mature_minutes 之后视为可采摘）
