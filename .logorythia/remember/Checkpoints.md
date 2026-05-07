# 任务进度与可恢复点

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
