# 经验片段

## 2026-02-25 分块提交流程

**事件摘要**：用户用简短指令 `"再来"` 触发提交流程，将多个独立变更按逻辑分块为3个提交推送。

**上下文标签**：Swift, Git 提交, 视图优化, 代码重构

**关键结论**：
- 单次会话内可能累积多个独立变更，应按逻辑职责分块提交
- 分块粒度：重构、功能新增、特定组件优化各自独立
- 提交信息格式：`type(模块): 描述`，中文描述，动宾结构
- 删除废弃文件应与替换逻辑放在同一提交，保持历史完整

**追踪指针**：
- 提交1：`refactor(视图): 移除 SelectableMarkdownRenderer 简化层级`
- 提交2：`feat(图片): 添加加载占位背景`
- 提交3：`feat(Mermaid): 支持宽高自适应尺寸检测`
- 删除：`Sources/MarkdownExtendedView/Renderer/SelectableMarkdownRenderer.swift`
- 修改：`Sources/MarkdownExtendedView/MarkdownView.swift`, `MarkdownImageView.swift`, `MermaidView.swift`

## 2026-02-25 SoftBreak 渲染修复

**事件摘要**：修复 `MarkdownRenderer.swift` 中 `SoftBreak` 节点的渲染逻辑，将输出从空格 `" "` 改为换行符 `"\n"`。

**上下文标签**：Swift, Markdown 渲染, Git 提交

**关键结论**：
- 渲染器需区分 `SoftBreak` 与 `HardBreak` 的语义差异
- 用户通过简短指令 `"再来"` 触发提交流程，表明对分块提交流程的熟悉

**追踪指针**：
- 提交：`fix(渲染): 修正 SoftBreak 处理为换行符`
- 文件：`Sources/MarkdownExtendedView/Renderer/MarkdownRenderer.swift`

## 2026-02-25 选择功能优化

**事件摘要**：修正拼写错误并优化 Markdown 选择性能，通过 `SelectionCalculator` actor 实现异步选择计算。

**上下文标签**：Swift, Markdown 选择, Actor 并发, 性能优化

**关键结论**：
- 拼写修正：`selecable` → `selectable`（常见命名陷阱）
- Actor 适合隔离复杂计算（如选择区域计算）避免阻塞主线程
- 选择高亮层与交互覆盖层分离布局更利于维护

**追踪指针**：
- 提交：`fix(选择): 修正拼写并优化选择性能`
- 文件：`Sources/MarkdownExtendedView/Renderer/SelectableMarkdownRenderer.swift`
- 文件：`Sources/MarkdownExtendedView/Renderer/SelectableMarkdownRendererNative.swift`
