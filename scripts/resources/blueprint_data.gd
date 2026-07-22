class_name BlueprintData
extends Resource

## 预加载 MaterialCost，使其在 `Array[MaterialCost]` 泛型参数里对当前文件可见。
## 仅靠另一文件的 class_name 无法在「泛型参数」中被当前作用域解析，
## 会报 "Could not find type 'MaterialCost' in the current scope"；preload 成 const 即可。
const MaterialCost = preload("res://scripts/resources/material_cost.gd")

## BlueprintData · 蓝图定义（纯定义类，非库存物）
##
## 与 ItemData 的区别：蓝图不是"拥有的物品"，而是"制作配方/解锁定义"。
## 它不进 GameManager.inventory，也不占用 ItemData 的 category/price/decompose_recipe 等库存语义；
## 解锁状态由 GameManager.unlocked_blueprints 跟踪（不存此处）。
## 所有蓝图放 res://data/blueprints/，由 GameManager 启动时统一加载（阶段 0.8）。
##
## 一条完整链路示例（跨 0.6→0.7→2.4）：
##   种植→采摘玫瑰(CROP) → 工坊分解 → 红染料+纤维(MATERIAL)
##   → 达灵感阈值解锁本蓝图 → 工坊按 required_materials 消耗材料 → 产出围巾(CLOTHING)。
##
## 关联方式（重要）：蓝图不靠 id 字符串去注册表查物品，而是直接持有资源引用——
##   - output: ItemData        → 产出物资源（编辑器硬链接，点开即见，不会拼错）
##   - required_materials: Array[MaterialCost] → 每项 MaterialCost.item 直接引用材料资源
## 因此制作逻辑不依赖 _item_registry 是否登记了对应物品，根除「拼错 id / 引用未注册物」类静默 bug。
##
## 注意：.tres 头部必须写成 `[gd_resource type="Resource" script_class="BlueprintData" ...]`，
##       绝不能把自定义 class_name 放进 type=（否则运行时报 Cannot get class 'BlueprintData'）。

@export var id: String = ""                       ## 蓝图唯一 id（GameManager 用它当解锁 key）
@export var display_name: String = ""             ## 展示名（工坊蓝图卡标题）
@export var icon: Texture2D                       ## 蓝图/产物图标（UI 用）；缺图时显示占位
@export var description: String = ""              ## 描述（可选）

## 灵感累计阈值：inspiration_total_earned（单调递增）达到此值即解锁。0 = 初始即解锁。
@export var unlock_inspiration: int = 0

## 制作所需材料：每项是一个 MaterialCost（直接引用材料资源 + 数量），
## 不再用 id 字符串字典，编辑器里是硬链接、不拼错、不依赖注册表。
@export var required_materials: Array[MaterialCost] = []

## 产出物品（直接引用 ItemData 资源；CLOTHING/CRAFT 等都行，按资源的 category 归类进库存）
@export var output: ItemData

## 产出数量（默认 1）
@export var output_count: int = 1


## 把 required_materials 渲染成 "红染料×1 纤维×2" 之类的简介，供工坊 UI 展示。
## 直接读 MaterialCost.item.display_name，无需 id→展示名 解析器（资源已硬引用）。
func materials_text() -> String:
	var parts: Array = []
	for mc in required_materials:
		if mc == null or mc.item == null:
			continue
		if mc.count <= 0:
			continue
		parts.append("%s×%d" % [mc.item.display_name, mc.count])
	return "  ".join(parts)
