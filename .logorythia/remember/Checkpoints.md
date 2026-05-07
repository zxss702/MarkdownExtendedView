## 2026-05-08 · MarkdownExtendedView 第七轮分块提交已推送（「再来」）

**任务目标**：用户以「再来」触发第七轮分块提交并直接推送。

**当前状态**：工作区再次清空，远端已同步。累计已达十六笔 commit。

- `fix(layout)`：2 个文件（`MarkdownRenderer.swift`、`SelectableMarkdownRenderer.swift`）
  - `MarkdownRenderer` 中提供 `TableAdaptiveLayout` 处理超宽表格避免内容被 `FixedSize` 硬截断
  - LaTeXView Block 级公式新增 `BlockFormulaKey` 支持 FlowLayout 提供宽度占位避免溢出
  - 修复 `SelectableMarkdownRenderer` 中多余的 content 背景视图叠层以避免拖字诀影响性能
- `docs`：2 个文件（`.logorythia/remember/Checkpoints.md`、`.logorythia/remember/ProjectProfile.md`）
  - 记录第六轮的分块内容及同步最新的并发梳理进度

**已做变更**：修复表格列宽与大块公式折行布局问题，清理多余背景视图叠层，归档日志并推送。

**下一步行动**：无，任务已彻底结束。

**风险与未决事项**：无。

**复现与验证路径**：
- `git log --oneline -16` 可查看全部十六笔 commit
- `git status` 确认工作区为空

---

# 任务进度与可恢复点

## 2026-05-08 · MarkdownExtendedView 第六轮分块提交已推送（「再来」）

**任务目标**：用户以「再来」触发第六轮分块提交并直接推送。

**当前状态**：工作区再次清空，远端已同步。累计已达十四笔 commit。

- `chore(deps)`：3 个文件（`MTFontV2.swift`、`MTMathAtomFactory.swift`、`RWLock.swift`）
  - `MTFontV2` 中 lazy `mathTable` 改用 `Mutex` 替代 `NSLock`
  - `MTMathAtomFactory` 的字典缓存由 `NSLock` 迁移至 `Mutex`，移除多余 `nonisolated(unsafe)`
  - `RWLock` 底层改为 `Mutex` 且符合 `@unchecked Sendable`
- `chore(log)`：1 个文件（`.logorythia/remember/Checkpoints.md`）
  - 记录第五轮的分块内容

**已做变更**：完成 SwiftMath 内部并发安全重构（Mutex 替代 NSLock），并推送。

**下一步行动**：无，任务已彻底结束。

**风险与未决事项**：无。

**复现与验证路径**：
- `git log --oneline -14` 可查看全部十四笔 commit
- `git status` 确认工作区为空

---

## 2026-05-08 · MarkdownExtendedView 第五轮分块提交已推送（「再来，同样」）

**任务目标**：用户以「再来，同样」触发第五轮分块提交并直接推送。

**当前状态**：工作区再次清空，远端已同步。累计已达十二笔 commit。

- `style(view)`：2 个文件（`MarkdownRenderer.swift`、`CodeReferenceBlockView.swift`）
  - 移除表格 Grid 外部在自适应宽度时的底边横线重叠
  - `MCodeReferenceBlockView` 样式更改为 Capsule 防止两端过于生硬
- `chore(log)`：1 个文件（`.logorythia/remember/Checkpoints.md`）
  - 记录第四轮的分块内容

**已做变更**：完成表格边框微调、代码引用视图样式优化及日志归档，并推送。

**下一步行动**：无，任务已彻底结束。

**风险与未决事项**：无。

**复现与验证路径**：
- `git log --oneline -12` 可查看全部十二笔 commit
- `git status` 确认工作区为空

---

## 2026-05-08 · MarkdownExtendedView 第四轮分块提交已推送（「再来」）

**任务目标**：用户以「再来」触发第四轮分块提交并直接推送。

**当前状态**：工作区再次清空，远端已同步。

- `feat(layout)`：2 个文件（`MarkdownRenderer.swift`、`MarkdownHeightEstimator.swift`）
  - 使用 `Grid` 重构表格渲染，支持不同列宽自适应与 `ColumnAlignment`
  - 支持 colspan 表格单元格
  - `MarkdownHeightEstimator` 增加单元格高度安全余量
- `feat(view)`：1 个文件（`CodeReferenceBlockView.swift`）
  - `MCodeReferenceBlockView` 增加 macOS 悬停交互光标
- `docs`：1 个文件（`.logorythia/remember/ProjectProfile.md`）
  - 补充 Selection 提取与缓存策略的说明

**已做变更**：完成表格布局优化、代码引用视图交互优化及文档补充，并推送。

**下一步行动**：无，任务已彻底结束。

**风险与未决事项**：无。

**复现与验证路径**：
- `git log --oneline -10` 可查看全部十笔 commit
- `git status` 确认工作区为空

---

## 2026-05-07 · MarkdownExtendedView 第三轮分块提交已推送（「再来。同样」）

**任务目标**：用户以「再来。同样」触发新一轮分块提交并直接推送。

**当前状态**：工作区再次清空，远端已同步。

- `feat(selection)`：5 个文件
  - `LaTeXView.swift`：添加 `FormulaSelectionKey` 锚点提取
  - `MarkdownRenderer.swift`：简化 Run 和 SoftBreak 的拆分层级
  - `SelectableMarkdownRenderer.swift`、`SelectionDocument.swift`、`SelectionDocumentBuilder.swift`：兼容 `FormulaSelectionData` 数据源、优化选择算法（垂直相近时水平截取、重叠率判断同行）

**已做变更**：完成 LaTeX 公式选中功能的相关文件提交与推送。

**下一步行动**：无，任务已彻底结束。

**风险与未决事项**：无。

**复现与验证路径**：
- `git log --oneline -7` 可查看全部七笔 commit
- `git status` 确认工作区为空

---

## 2026-05-07 · MarkdownExtendedView 两轮分块提交已全部推送

**任务目标**：完成当前工作区变更的 git 分块提交并推送。

**当前状态**：工作区完全清空，远端已同步。两轮分块提交如下：

第一轮：
- `feat(theme)`：3 个文件（`Package.swift`、`LaTeXView.swift`、`MarkdownHeightEstimator.swift`）
- `chore(deps)`：6 个文件（`SwiftMath` 内置源码同步与编译警告修复）

第二轮（由用户「再来，结束后push」触发）：
- `docs`：1 个文件（`.logorythia/remember/ProjectProfile.md`，补充 SwiftMath 内嵌说明）
- `chore(deps)`：1 个文件（`MTMathListDisplay.swift`，补充 `@unchecked Sendable` 声明）
- `chore(test)`：2 个文件（`FootnoteTests.swift` 重命名禁用、`MathBenchmarkTests.swift` 新增）

**已做变更**：
- 移除 `ExtendedSwiftMath` 外部包依赖
- `LaTeXView` 引入 `MathDisplayCache` 实现渲染列表缓存
- `LaTeXView` 底层改用 SwiftUI `Canvas` 直接承载显示列表
- `SwiftMath` 内置源码中部分全局状态标注为 `nonisolated(unsafe)` 或 `@unchecked Sendable`
- `MTDisplay` 设备系统能力验证判断简化
- 测试侧：禁用旧 Footnote 测试，新增 Math 渲染与缓存性能基准测试

**下一步行动**：无，任务已彻底结束。

**风险与未决事项**：无。

**复现与验证路径**：
- `git log --oneline -6` 可查看全部六笔 commit
- `git status` 确认工作区为空

---
