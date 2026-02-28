# MarkdownExtendedView 项目画像

## 仓库基线
- **项目类型**：Swift 库（Swift Package / Xcode 项目）
- **核心功能**：Markdown 渲染视图组件
- **技术栈**：Swift，面向 Apple 平台
- **版本管理**：Git，远程仓库 origin/main

## 关键目录结构
```
Sources/MarkdownExtendedView/
├── MarkdownView.swift                      # 主视图入口，直接使用 MarkdownRenderer + .selectable()
├── Views/
│   ├── MarkdownImageView.swift             # 图片渲染，含加载占位背景
│   └── MermaidView.swift                   # Mermaid 图表渲染，支持宽高自适应
└── Renderer/
    ├── MarkdownRenderer.swift              # 核心渲染器入口
    └── SelectableMarkdownRendererNative.swift  # Native 平台选择实现
```

## 视图组件职责
- **MarkdownView**：主视图，整合渲染器与选择功能，不再依赖独立的选择渲染器中间层
- **MarkdownImageView**：图片加载时展示白色圆角占位，固定高度 320pt
- **MermaidView**：通过完整尺寸检测 (width, height) 实现宽度自适应布局

## 标准开发流程
- 提交前检查：通过 `git status` 和 `git diff --stat` 确认变更范围
- 提交规范：中文提交信息，遵循 `fix(模块): 描述` 格式
- 推送目标：origin main 分支
