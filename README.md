# MarkdownExtendedView

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat)](https://opensource.org/licenses/MIT)
[![GitHub Release](https://img.shields.io/github/v/release/ChrisGVE/MarkdownExtendedView?style=flat&logo=github)](https://github.com/ChrisGVE/MarkdownExtendedView/releases)
[![CI](https://github.com/ChrisGVE/MarkdownExtendedView/actions/workflows/ci.yml/badge.svg)](https://github.com/ChrisGVE/MarkdownExtendedView/actions/workflows/ci.yml)
[![Swift Package Index](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FChrisGVE%2FMarkdownExtendedView%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ChrisGVE/MarkdownExtendedView)
[![Swift Package Index](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FChrisGVE%2FMarkdownExtendedView%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ChrisGVE/MarkdownExtendedView)
[![Documentation](https://img.shields.io/badge/Documentation-DocC-blue.svg?style=flat&logo=readthedocs&logoColor=white)](https://swiftpackageindex.com/ChrisGVE/MarkdownExtendedView/documentation)
[![iOS 18+](https://img.shields.io/badge/iOS-18%2B-blue.svg?style=flat)](https://developer.apple.com/ios/)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue.svg?style=flat)](https://developer.apple.com/macos/)

一个原生 SwiftUI Markdown 渲染器，支持 LaTeX 数学公式。

## 特性

- 通过 Apple 的 swift-markdown 实现 **GitHub Flavored Markdown** 解析
- 通过 SwiftMath 原生渲染 **LaTeX 数学公式**
  - 行内公式：`$...$`
  - 块级公式：`$$...$$`
- **任务列表**支持复选框渲染（`- [ ]` 和 `- [x]`）
- **可点击的链接**，支持应用内浏览器（iOS）或系统浏览器（macOS）
- 使用 AsyncImage 进行**远程图片加载**
- 支持 **13+ 种编程语言的语法高亮**
- 通过内嵌 WKWebView 支持 **Mermaid 图表**
- **大范围文本选择**，支持跨段落选择
- **主题系统**，内置主题（default、gitHub、compact）
- **跨平台**支持 iOS 18+ 和 macOS 15+
- **纯 SwiftUI** - WebView 使用最小化（仅 Mermaid 使用）

## 支持的 Markdown 元素

| 元素 | 语法 | 状态 |
|---------|--------|--------|
| 标题 | `# H1` 至 `###### H6` | 已支持 |
| 粗体 | `**text**` 或 `__text__` | 已支持 |
| 斜体 | `*text*` 或 `_text_` | 已支持 |
| 删除线 | `~~text~~` | 已支持 |
| 行内代码 | `` `code` `` | 已支持 |
| 代码块 | ` ``` ` 围栏代码块 | 已支持（含语法高亮） |
| 引用块 | `> quote` | 已支持 |
| 有序列表 | `1. item` | 已支持（含嵌套） |
| 无序列表 | `- item` 或 `* item` | 已支持（含嵌套） |
| 任务列表 | `- [ ]` 和 `- [x]` | 已支持 |
| 表格 | GFM 管道表格 | 已支持 |
| 链接 | `[text](url)` | 已支持 |
| 图片 | `![alt](url)` | 已支持 |
| Mermaid 图表 | ` ```mermaid ` | 已支持 |
| 脚注 | `[^1]` 和 `[^1]: text` | 已支持 |
| 分隔线 | `---` 或 `***` | 已支持 |
| 行内 LaTeX | `$E=mc^2$` | 已支持 |
| 块级 LaTeX | `$$...$$` | 已支持 |

## 安装

添加到你的 `Package.swift`：

```swift
dependencies: [
    .package(url: "https://github.com/ChrisGVE/MarkdownExtendedView.git", from: "1.0.0")
]
```

然后将依赖项添加到你的目标：

```swift
.target(
    name: "YourApp",
    dependencies: ["MarkdownExtendedView"]
)
```

或在 Xcode 中：文件 > 添加包依赖，然后输入仓库 URL。

## 使用

```swift
import SwiftUI
import MarkdownExtendedView

struct ContentView: View {
    var body: some View {
        ScrollView {
            MarkdownView("""
                # Hello World

                This is **bold** and this is *italic*.

                Inline equation: $E = mc^2$

                Display equation:
                $$\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}$$
            """)
            .padding()
        }
    }
}
```

### 主题

```swift
MarkdownView(content)
    .markdownTheme(.gitHub)
```

可用主题：
- `.default` - 简洁、易读的默认样式，自动适配系统外观
- `.gitHub` - 类 GitHub 渲染风格，使用特定字体大小
- `.compact` - 紧凑间距，适合密集内容展示

### 自定义主题

通过修改可用属性来创建自定义主题：

```swift
var customTheme = MarkdownTheme.default

// 字体
customTheme.bodyFont = .systemFont(ofSize: 15)
customTheme.heading1Font = .systemFont(ofSize: 28, weight: .bold)
customTheme.codeFont = .monospacedSystemFont(ofSize: 15, weight: .regular)
customTheme.codeBlockFont = .monospacedSystemFont(ofSize: 13, weight: .regular)

// 颜色
customTheme.textColor = .primary
customTheme.secondaryTextColor = .secondary
customTheme.linkColor = .blue
customTheme.codeBackgroundColor = Color(white: 0.95)
customTheme.blockQuoteBorderColor = Color(white: 0.75)

// 间距
customTheme.paragraphSpacing = 12
customTheme.listItemSpacing = 4
customTheme.indentation = 20
customTheme.codeBlockPadding = 12

MarkdownView(content)
    .markdownTheme(customTheme)
```

## 默认行为

- 链接、图片、Mermaid、语法高亮、脚注默认开启
- 文本默认支持跨段落选择和复制
- 通过 `MarkdownTheme` 统一控制字体、颜色和间距
- 通过 `.onLinkTap(_:)` 覆盖默认的链接打开行为

### 自定义链接处理器

覆盖默认的链接行为：

```swift
MarkdownView(content)
    .onLinkTap { url in
        // 自定义处理
        print("Tapped: \(url)")
    }
```

### 大范围文本选择

跨段落选择和复制默认开启，适合长文本阅读和摘录。

在 iOS 18+ 和 macOS 15+ 上，选择使用基于布局的原生覆盖层，以实现更好的跨块对齐。

### 语法高亮

带语言标识符的代码块会自动着色：

```swift
MarkdownView("""
    ```swift
    let greeting = "Hello, World!"
    print(greeting)
    ```
""")
```

支持的语言：Swift、Python、JavaScript、TypeScript、Java、C、C++、Go、Rust、Ruby、Kotlin、PHP、C#。

通过主题自定义语法颜色：

```swift
var theme = MarkdownTheme.default
theme.syntaxColors.keyword = .purple
theme.syntaxColors.string = .red
theme.syntaxColors.comment = .gray
```

### Mermaid 图表

Mermaid 代码块会自动渲染为图表：

```swift
MarkdownView("""
    ```mermaid
    graph TD
        A[Start] --> B{Decision}
        B -->|Yes| C[OK]
        B -->|No| D[Cancel]
    ```
""")
```

支持所有 Mermaid 图表类型：流程图、序列图、类图、状态图、甘特图、饼图等。

### 脚注

脚注语法会自动处理并渲染：

```swift
MarkdownView("""
    This statement needs a citation[^1].

    Another point with a named reference[^note].

    [^1]: Source: Academic Paper, 2024.
    [^note]: See the documentation for details.
""")
```

脚注特点：
- 以上标数字形式渲染（¹、²、³...）
- 收集并显示在脚注区域末尾
- 按在文本中首次出现的顺序编号

## LaTeX 支持

MarkdownExtendedView 使用 [ExtendedSwiftMath](https://github.com/ChrisGVE/ExtendedSwiftMath) 进行原生 LaTeX 渲染（SwiftMath 的分支，扩展了符号覆盖范围）。

### 行内公式

使用单美元符号表示与文本混排的行内公式：

```markdown
The famous equation $E = mc^2$ changed physics.
```

### 块级公式

使用双美元符号表示居中、块级公式：

```markdown
The quadratic formula:

$$x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}$$
```

### 支持的 LaTeX 命令

SwiftMath 支持广泛的 LaTeX 数学命令，包括：

- **希腊字母**：`\alpha`, `\beta`, `\gamma`, `\pi`, `\theta` 等
- **运算符**：`\sum`, `\prod`, `\int`, `\lim`, `\log`, `\sin`, `\cos` 等
- **分数**：`\frac{a}{b}`
- **根号**：`\sqrt{x}`, `\sqrt[n]{x}`
- **上标/下标**：`x^2`, `x_i`, `x_i^2`
- **括号**：`\left(`, `\right)`, `\{`, `\}`, `\langle`, `\rangle`
- **矩阵**：`\begin{matrix}...\end{matrix}`, `\begin{pmatrix}...\end{pmatrix}`
- **重音符号**：`\hat{x}`, `\bar{x}`, `\vec{x}`, `\dot{x}`
- **符号**：`\infty`, `\partial`, `\nabla`, `\forall`, `\exists`

完整参考请参见 [SwiftMath 文档](https://github.com/mgriebling/SwiftMath)。

## 已知限制

当前版本中可能在未来版本解决的限制：

| 特性 | 状态 | 说明 |
|---------|--------|-------|
| 引用式链接 | 未验证 | `[text][ref]` 语法可能无法正常工作 |
| HTML 块 | 部分支持 | 原始 HTML 不会被渲染 |
| 定义列表 | 不支持 | 非 GFM 标准 |

## 系统要求

- iOS 18.0+ / macOS 15.0+
- Swift 6.0+
- Xcode 16.0+

## 依赖项

- [swift-markdown](https://github.com/apple/swift-markdown) - Apple 的 Markdown 解析器（CommonMark + GFM）
- [ExtendedSwiftMath](https://github.com/ChrisGVE/ExtendedSwiftMath) - 原生 LaTeX 渲染（SwiftMath 的分支）

## 贡献

欢迎贡献！请随时提交问题和拉取请求。

1. Fork 仓库
2. 创建你的特性分支（`git checkout -b feature/amazing-feature`）
3. 提交你的更改（`git commit -m 'Add amazing feature'`）
4. 推送到分支（`git push origin feature/amazing-feature`）
5. 打开一个拉取请求

## 许可证

MIT 许可证 - 版权所有 (c) 2025 Christian C. Berclaz。详情请参见 [LICENSE](LICENSE)。
