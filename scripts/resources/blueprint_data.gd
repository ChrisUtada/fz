class_name BlueprintData
extends Resource
## BlueprintData · 蓝图定义（纯定义类，非库存物）
##
## 与 ItemData 的区别：蓝图不是"拥有的物品"，而是"制作配方/解锁定义"。
## 它不进 GameManager.inventory，也不占用 ItemData 的 category/price/decompose_recipe 等库存语义；
## 解锁状态由 GameManager.unlocked_blueprints 跟踪（不存此处）。
## 所有蓝图放 res://data/blueprints/，由 GameManager 启动时统一加载（阶段 0.8）。
##
## 一条完整链路示例（跨 0.6→0.7→2.4）：
##   种植→采摘玫瑰(CROP) → 工坊分解 → 红染料+纤维(MATERIAL)
##   → 达灵感阈值解锁本蓝图 → 工坊按 required_materials 消耗材料 → 产出围巾(CRAFT)。
##
## 注意：.tres 头部必须写成 `[gd_resource type="Resource" script_class="BlueprintData" ...]`，
##       绝不能把自定义 class_name 放进 type=（否则运行时报 Cannot get class 'BlueprintData'）。
##       required_materials 是 Array[Dictionary]，.tres 里 dict 的 key 必须加引号
##       （如 [{"item_id": "red_dye", "count": 1}]），裸标识符会触发 Parse Error。

@export var id: String = ""                       ## 蓝图唯一 id（GameManager 用它当解锁 key）
@export var display_name: String = ""             ## 展示名（工坊蓝图卡标题）
@export var icon: Texture2D                       ## 蓝图/产物图标（UI 用）；缺图时显示占位
@export var description: String = ""              ## 描述（可选）

## 灵感累计阈值：inspiration_total_earned（单调递增）达到此值即解锁。0 = 初始即解锁。
@export var unlock_inspiration: int = 0

## 制作所需材料：每项 {item_id:String, count:int}（按 id 从 _item_registry 解析元数据）
@export var required_materials: Array[Dictionary] = []

## 产出物品 id（对应某个 category=CLOTHING/CRAFT 的 ItemData，需提前注册进 _item_registry）
@export var output_id: String = ""

## 产出数量（默认 1）
@export var output_count: int = 1


## 把 required_materials 渲染成 "红染料×1 纤维×2" 之类的简介，供工坊 UI 展示。
## 需要 id->展示名 的解析器（通常传 GameManager.get_item）。若解析不到则回退显示 id。
func materials_text(resolve: Callable = Callable()) -> String:
	var parts: Array = []
	for e in required_materials:
		if not e is Dictionary:
			continue
		var iid: String = str(e.get("item_id", ""))
		var n: int = int(e.get("count", 0))
		if iid.is_empty() or n <= 0:
			continue
		var name: String = iid
		if resolve.is_valid():
			var d = resolve.call(iid)
			if d != null and d.has_method("get"):
				name = str(d.display_name)
		parts.append("%s×%d" % [name, n])
	return "  ".join(parts)
