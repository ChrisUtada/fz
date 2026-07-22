## UITheme · 全局统一调色板（纯常量模块，class_name 便于全局引用）
##
## 所有 UI 面板 / 控件从这里取色，做到「换肤只改一处」。
## 设计基调：暖棕深底 + 高对比浅米字（与家园桌面 / 工坊 / 种植屏一致）。
##
## 用法：
##   $Card/Bg.color = UITheme.BG_PANEL
##   label.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)

class_name UITheme
extends RefCounted

# ── 背景 ──
const BG_PANEL   := Color(0.16, 0.13, 0.11, 0.97)   ## 弹窗 / 浮层主底（深棕）
const BG_SURFACE := Color(0.22, 0.18, 0.15, 1.0)    ## 卡片 / 槽 / 次级面底
const BG_ACCENT  := Color(0.50, 0.38, 0.18, 1.0)    ## 暖金按钮 / 当前页高亮底
const BORDER     := Color(0.42, 0.36, 0.28, 1.0)    ## 边框 / 描边
const BG_DANGER  := Color(0.55, 0.18, 0.16, 1.0)    ## 警示闪红底（专注条打断 / 错误态）

# ── 文字（深底上的浅色梯度，保证对比度）──
const TEXT_PRIMARY   := Color(0.95, 0.92, 0.88, 1.0)  ## 主文字
const TEXT_SECONDARY := Color(0.85, 0.80, 0.70, 1.0)  ## 次级（库存数 / 副标题）
const TEXT_MUTED     := Color(0.78, 0.74, 0.66, 1.0)  ## 静音 / 说明文字
const TEXT_DIM       := Color(0.62, 0.58, 0.54, 1.0)  ## 禁用 / 未解锁灰
const TEXT_DISABLED  := Color(0.72, 0.26, 0.20, 1.0)  ## 「金币不足」红（禁用态提示）
const TEXT_GOLD      := Color(0.95, 0.85, 0.40, 1.0)  ## 数量徽标暖金
const TEXT_DANGER    := Color(0.85, 0.60, 0.60, 1.0)  ## 警示 / 缺货（如展架空槽）
