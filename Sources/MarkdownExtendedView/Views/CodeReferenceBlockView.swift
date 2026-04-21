// CodeReferenceBlockView.swift
//  MarkdownExtendedView
//
//  Created by OpenAI Codex on 2026-04-21.
// Licensed under MIT License

import SwiftUI
import UniformTypeIdentifiers

struct CodeReferenceBlockView: View {
    let reference: CodeReference
    let theme: MarkdownTheme
    let tapHandler: (@Sendable (CodeReference) -> Void)?

    var body: some View {
        Button(action: handleTap) {
            HStack(alignment: VerticalAlignment.lastTextBaseline, spacing: 6) {
                fileIconView(fileURL: reference.url)
                    .frame(width: 12, height: 12)

                Text(titleText)
                    .lineLimit(1)
                    .font(theme.codeSwiftUIFont.weight(.semibold))
                    .foregroundStyle(theme.secondaryTextColor)
                
                if let detailText {
                    Text(detailText)
                        .lineLimit(1)
                        .font(lineNumberFont)
                        .foregroundStyle(theme.secondaryTextColor.opacity(0.9))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.codeBackgroundColor.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var titleText: String {
        let url = reference.url
        if case .directory = reference {
            return url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        }

        let baseName = url.deletingPathExtension().lastPathComponent
        return baseName.removingPercentEncoding ?? baseName
    }

    private var detailText: String? {
        let ranges = reference.lineRanges
        guard !ranges.isEmpty else {
            return nil
        }

        return ranges
            .map { range in
                if range.lowerBound == range.upperBound {
                    return "\(range.lowerBound)"
                }
                return "\(range.lowerBound) - \(range.upperBound)"
            }
            .joined(separator: ",")
    }

    private var lineNumberFont: Font {
        .system(
            size: max(theme.codeFont.pointSize - 4, 8),
            weight: .regular,
            design: .monospaced
        )
    }

    private func handleTap() {
        tapHandler?(reference)
    }
}


import UniformTypeIdentifiers

struct fileIconView: View {
    let fileURL: URL

    var body: some View {
        let fileName = fileURL.lastPathComponent.lowercased()
        let ext = fileURL.pathExtension.lowercased()

        // 先检查完整文件名（配置文件等）
        if let customIcon = iconForFileName(fileName) {
            customIcon
                .scaledToFit()
        } else if let customIcon = iconForExtension(ext) {
            // 再检查扩展名
            customIcon
                .scaledToFit()
        } else if let uttype = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType {
            iconForUTType(uttype)
                .scaledToFit()
        } else {
            Image(systemName: "doc")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.gray)
        }
    }

    // MARK: - 基于文件名的图标匹配
    private func iconForFileName(_ fileName: String) -> Image? {
        switch fileName {
        // 包管理器文件
        case "package.json":
            Image("nodejs").resizable()
        case "package-lock.json":
            Image("npm").resizable()
        case "yarn.lock":
            Image("yarn").resizable()
        case ".yarnrc":
            Image("yarn").resizable()
        case "pnpm-lock.yaml":
            Image("pnpm").resizable()
        case ".pnpmrc":
            Image("pnpm").resizable()
        case "bun.lockb":
            Image("bun").resizable()
        case "bunfig.toml":
            Image("bun").resizable()

        // Git 文件
        case ".gitignore", ".gitattributes":
            Image("git").resizable()

        // Docker 文件
        case "dockerfile":
            Image("docker").resizable()
        case ".dockerignore":
            Image("docker").resizable()
        case "docker-compose.yml", "docker-compose.yaml":
            Image("docker").resizable()

        // 构建工具
        case "makefile":
            Image("makefile").resizable()
        case "cmakelists.txt":
            Image("cmake").resizable()
        case "cargo.toml", "cargo.lock":
            Image("rust").resizable()
        case "go.mod", "go.sum":
            Image("go-mod").resizable()
        case "gemfile", "gemfile.lock":
            Image("gemfile").resizable()
        case "rakefile":
            Image("ruby").resizable()
        case "pubspec.yaml", "pubspec.lock":
            Image("dart").resizable()
        case "gradle.properties":
            Image("gradle").resizable()
        case "pom.xml":
            Image("maven").resizable()

        // TypeScript/JavaScript 配置
        case "tsconfig.json":
            Image("tsconfig").resizable()
        case "jsconfig.json":
            Image("jsconfig").resizable()
        case "webpack.config.js", "webpack.config.ts":
            Image("webpack").resizable()
        case "vite.config.js", "vite.config.ts":
            Image("vite").resizable()
        case "rollup.config.js", "rollup.config.ts":
            Image("rollup").resizable()
        case "tailwind.config.js", "tailwind.config.ts":
            Image("tailwindcss").resizable()

        // Linter/Formatter 配置
        case ".eslintrc", ".eslintrc.js", ".eslintrc.json", ".eslintrc.cjs":
            Image("eslint").resizable()
        case ".prettierrc", ".prettierrc.js", ".prettierrc.json":
            Image("prettier").resizable()
        case ".babelrc", ".babelrc.js", ".babelrc.json":
            Image("babel").resizable()
        case ".stylelintrc", ".stylelintrc.js", ".stylelintrc.json":
            Image("stylelint").resizable()
        case "postcss.config.js", ".postcssrc":
            Image("postcss").resizable()

        // 其他配置
        case ".editorconfig":
            Image("editorconfig").resizable()
        case ".browserslistrc":
            Image("browserlist").resizable()
        case ".npmrc":
            Image("npm").resizable()
        case ".env", ".env.local", ".env.development", ".env.production":
            Image("settings").resizable()

        // 文档文件
        case "license", "license.md", "license.txt":
            Image("license").resizable()
        case "readme", "readme.md", "readme.txt":
            Image("readme").resizable()
        case "changelog", "changelog.md", "changelog.txt":
            Image("changelog").resizable()
        case "todo", "todo.md", "todo.txt":
            Image("todo").resizable()

        default:
            nil
        }
    }

    // MARK: - 基于扩展名的图标匹配
    private func iconForExtension(_ ext: String) -> Image? {
        switch ext {
        // JavaScript/TypeScript
        case "js", "mjs", "cjs":
            Image("javascript")
                .resizable()
        case "jsx":
            Image("react")
                .resizable()
        case "ts", "mts", "cts":
            Image("typescript")
                .resizable()
        case "tsx":
            Image("react_ts")
                .resizable()

        // Web 框架
        case "vue":
            Image("vue")
                .resizable()
        case "svelte":
            Image("svelte")
                .resizable()
        case "astro":
            Image("astro")
                .resizable()
        case "next":
            Image("next")
                .resizable()
        case "nuxt":
            Image("nuxt")
                .resizable()
        case "remix":
            Image("remix")
                .resizable()
        case "qwik":
            Image("qwik")
                .resizable()

        // CSS 相关
        case "css":
            Image("css")
                .resizable()
        case "scss", "sass":
            Image("sass")
                .resizable()
        case "less":
            Image("less")
                .resizable()

        // Python
        case "py", "pyw", "pyx":
            Image("python")
                .resizable()

        // Ruby
        case "rb", "rake":
            Image("ruby")
                .resizable()

        // Go
        case "go":
            Image("go")
                .resizable()

        // Rust
        case "rs":
            Image("rust")
                .resizable()

        // Java/Kotlin
        case "java":
            Image("java")
                .resizable()
        case "kt", "kts":
            Image("kotlin")
                .resizable()

        // C/C++
        case "c":
            Image("c")
                .resizable()
        case "h":
            Image("h")
                .resizable()
        case "cpp", "cc", "cxx":
            Image("cpp")
                .resizable()
        case "hpp", "hh", "hxx":
            Image("hpp")
                .resizable()
        case "m":
            Image("objective-c")
                .resizable()
        case "mm":
            Image("objective-cpp")
                .resizable()

        // 其他编程语言
        case "php":
            Image("php")
                .resizable()
        case "lua":
            Image("lua")
                .resizable()
        case "dart":
            Image("dart")
                .resizable()
        case "scala":
            Image("scala")
                .resizable()
        case "r":
            Image("r")
                .resizable()
        case "jl":
            Image("julia")
                .resizable()
        case "zig":
            Image("zig")
                .resizable()
        case "ex", "exs":
            Image("elixir")
                .resizable()
        case "elm":
            Image("elm")
                .resizable()
        case "hs":
            Image("haskell")
                .resizable()
        case "ml", "mli":
            Image("ocaml")
                .resizable()
        case "clj", "cljs", "cljc":
            Image("clojure")
                .resizable()
        case "erl", "hrl":
            Image("erlang")
                .resizable()
        case "pl", "pm":
            Image("perl")
                .resizable()
        case "sh":
            Image("bashly")
                .resizable()
        case "bash", "zsh":
            Image("bashly")
                .resizable()
        case "v":
            Image("vlang")
                .resizable()
        case "gleam":
            Image("gleam")
                .resizable()
        case "nim":
            Image("nim")
                .resizable()
        case "cr":
            Image("crystal")
                .resizable()
        case "ps1":
            Image("powershell")
                .resizable()

        // 配置文件（仅扩展名）
        case "toml":
            Image("toml")
                .resizable()
        case "graphql", "gql":
            Image("graphql")
                .resizable()
        case "prisma":
            Image("prisma")
                .resizable()

        // Markdown & 文档（仅扩展名）
        case "md", "markdown":
            Image("markdown")
                .resizable()
        case "mdx":
            Image("mdx")
                .resizable()
        case "tex":
            Image("tex")
                .resizable()

        // 数据格式
        case "jsonc", "json5":
            Image("json")
                .resizable()
        case "yaml", "yml":
            Image("yaml")
                .resizable()
        case "html", "htm":
            Image("html")
                .resizable()
        case "svg":
            Image("svg")
                .resizable()
        case "gif":
            Image("gif")
                .resizable()
        case "xcstrings":
            Image("xcstrings-badge")
                .resizable()
        case "xml":
            Image("xml")
                .resizable()
        case "sql":
            Image("database")
                .resizable()
        case "proto":
            Image("proto")
                .resizable()
        case "lock":
            Image("lock")
                .resizable()

        default:
            nil
        }
    }

    // MARK: - 基于 UTType 的图标匹配
    @ViewBuilder
    private func iconForUTType(_ uttype: UTType) -> some View {
        switch uttype {
        // MARK: - Apple/Xcode 专用格式 (优先使用 SF Symbols)
        case .swiftSource:
            Image(systemName: "swift")
                .resizable()
                .foregroundStyle(.orange)
        case UTType("com.apple.dt.assetcatalog"):
            Image(systemName: "photo.on.rectangle.angled")
                .resizable()
                .foregroundStyle(.blue)
        case UTType("com.apple.xcode.entitlements-property-list"):
            Image(systemName: "seal")
                .resizable()
                .foregroundStyle(.yellow)
        case UTType("com.apple.property-list"):
            Image(systemName: "list.bullet.rectangle")
                .resizable()
                .foregroundStyle(.gray)
        case UTType("com.apple.interfacebuilder.document.storyboard"):
            Image(systemName: "rectangle.on.rectangle")
                .resizable()
                .foregroundStyle(.blue)
        case UTType("com.apple.interfacebuilder.document.xib"):
            Image(systemName: "rectangle.on.rectangle")
                .resizable()
                .foregroundStyle(.orange)
        case UTType("com.apple.coredata.model"):
            Image(systemName: "cylinder.split.1x2")
                .resizable()
                .foregroundStyle(.purple)

        // MARK: - 数据格式 (SF Symbols)
        case .json:
            Image(systemName: "curlybraces")
                .resizable()
                .foregroundStyle(.yellow)
        case .xml:
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .resizable()
                .foregroundStyle(.green)

        // MARK: - 文档 (SF Symbols)
        case .pdf:
            Image(systemName: "doc.richtext")
                .resizable()
                .foregroundStyle(.red)
        case .rtf, .rtfd:
            Image(systemName: "doc.richtext.fill")
                .resizable()
                .foregroundStyle(.blue)
        case .plainText:
            Image(systemName: "doc.text")
                .resizable()
                .foregroundStyle(.gray)
        case .log:
            Image(systemName: "doc.text.magnifyingglass")
                .resizable()
                .foregroundStyle(.gray)

        // MARK: - 多媒体 (SF Symbols)
        case .ico:
            Image(systemName: "app.badge")
                .resizable()
                .foregroundStyle(.blue)

        // MARK: - 字体 (SF Symbols)
        case .font:
            Image(systemName: "textformat")
                .resizable()
                .foregroundStyle(.blue)

        // MARK: - 压缩文件 (SF Symbols)
        case .zip, .gzip, .bz2:
            Image(systemName: "doc.zipper")
                .resizable()
                .foregroundStyle(.gray)

        // MARK: - Shell 脚本 (SF Symbols)
        case .shellScript:
            Image(systemName: "terminal")
                .resizable()
                .foregroundStyle(.green)

        default:
            defaultIconView(for: uttype)
        }
    }

    // MARK: - 默认图标 (SF Symbols)
    @ViewBuilder
    private func defaultIconView(for uttype: UTType) -> some View {
        if uttype.conforms(to: .image) {
            Image(systemName: "photo")
                .resizable()
                .foregroundStyle(.yellow)
        } else if uttype.conforms(to: .movie) {
            Image(systemName: "film")
                .resizable()
                .foregroundStyle(.purple)
        } else if uttype.conforms(to: .audio) {
            Image(systemName: "waveform")
                .resizable()
                .foregroundStyle(.pink)
        } else if uttype.conforms(to: .archive) {
            Image(systemName: "doc.zipper")
                .resizable()
                .foregroundStyle(.gray)
        } else if uttype.conforms(to: .sourceCode) {
            Image(systemName: "curlybraces.square")
                .resizable()
                .foregroundStyle(.blue)
        } else if uttype.conforms(to: .executable) {
            Image(systemName: "terminal")
                .resizable()
                .foregroundStyle(.green)
        } else if uttype.conforms(to: .directory) {
            Image(systemName: "folder")
                .resizable()
                .foregroundStyle(.blue)
        } else if uttype.conforms(to: .text) {
            Image(systemName: "doc.text")
                .resizable()
                .foregroundStyle(.gray)
        } else {
            Image(systemName: "doc")
                .resizable()
                .foregroundStyle(.gray)
        }
    }
}
