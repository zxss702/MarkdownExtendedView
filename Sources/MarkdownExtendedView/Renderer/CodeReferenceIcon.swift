//
//  CodeReferenceIcon.swift
//  MarkdownExtendedView
//
//  File-type icon resolution for inline code references. Ported from the
//  former `fileIconView`: full file name → asset catalog image, extension →
//  asset image, UTType → SF Symbol, then generic fallbacks.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import UniformTypeIdentifiers

extension MTImage {
    /// A copy scaled to `height` points, aspect preserved. Never
    /// mutates the receiver — baked payloads may be rendered under
    /// different fonts.
    func mdScaled(toHeight height: CGFloat) -> MTImage {
        let intrinsic = size
        guard intrinsic.height > 0, intrinsic.width > 0, height > 0 else {
            return self
        }
        let target = CGSize(
            width: intrinsic.width * (height / intrinsic.height),
            height: height
        )
        #if canImport(AppKit)
        return NSImage(size: target, flipped: false) { rect in
            self.draw(in: rect)
            return true
        }
        #elseif canImport(UIKit)
        return UIGraphicsImageRenderer(size: target).image { _ in
            self.draw(in: CGRect(origin: .zero, size: target))
        }
        #else
        return self
        #endif
    }
}

enum MCodeReferenceIcon {

    /// Resolution results memoized by `filename|ext|isDirectory|size` —
    /// deferred payloads resolve on every first render, and streaming
    /// updates keep hitting the same keys.
    /// NSCache is internally synchronized; `nonisolated(unsafe)` only
    /// satisfies the strict-concurrency check on shared state.
    nonisolated(unsafe) private static let cache = NSCache<NSString, MTImage>()

    /// Resolves the icon for a reference as a platform image at `size` pt.
    /// Asset images come from the host app's bundle (`Image("swift")` etc.);
    /// missing assets fall through to SF Symbols so the icon never drops.
    /// Guaranteed non-nil — the final fallback is an empty image so the
    /// `\u{FFFC}` glyph count stays aligned with the selection mappings.
    static func image(for reference: MCodeReference, size: CGFloat) -> MTImage {
        let url = reference.url
        let key = "\(url.lastPathComponent.lowercased())|\(url.pathExtension.lowercased())|\(url.hasDirectoryPath)|\(size)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let icon = resolve(for: reference, size: size) ?? MTImage()
        cache.setObject(icon, forKey: key)
        return icon
    }

    private static func resolve(for reference: MCodeReference, size: CGFloat) -> MTImage? {
        let url = reference.url
        if case .directory = reference {
            return symbol("folder", color: .systemBlue, size: size)
        }

        let fileName = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()

        if let name = fileNameAssets[fileName], let icon = asset(name, size: size) {
            return icon
        }
        if ext == "ppt" || ext == "pptx" {
            return symbol("play.rectangle", color: nil, size: size)
        }
        if let name = extensionAssets[ext], let icon = asset(name, size: size) {
            return icon
        }
        if let uttype = UTType(filenameExtension: ext) {
            return utTypeIcon(uttype, size: size)
        }
        if url.hasDirectoryPath {
            return symbol("folder", color: .systemBlue, size: size)
        }
        return symbol("doc", color: .systemGray, size: size)
    }

    // MARK: - Asset catalog names

    /// Full file names (configs, lockfiles, docs) → asset catalog name.
    private static let fileNameAssets: [String: String] = [
        "package.json": "nodejs",
        "package-lock.json": "npm",
        "yarn.lock": "yarn",
        ".yarnrc": "yarn",
        "pnpm-lock.yaml": "pnpm",
        ".pnpmrc": "pnpm",
        "bun.lockb": "bun",
        "bunfig.toml": "bun",
        ".gitignore": "git",
        ".gitattributes": "git",
        "dockerfile": "docker",
        ".dockerignore": "docker",
        "docker-compose.yml": "docker",
        "docker-compose.yaml": "docker",
        "makefile": "makefile",
        "cmakelists.txt": "cmake",
        "cargo.toml": "rust",
        "cargo.lock": "rust",
        "go.mod": "go-mod",
        "go.sum": "go-mod",
        "gemfile": "gemfile",
        "gemfile.lock": "gemfile",
        "rakefile": "ruby",
        "pubspec.yaml": "dart",
        "pubspec.lock": "dart",
        "gradle.properties": "gradle",
        "pom.xml": "maven",
        "tsconfig.json": "tsconfig",
        "jsconfig.json": "jsconfig",
        "webpack.config.js": "webpack",
        "webpack.config.ts": "webpack",
        "vite.config.js": "vite",
        "vite.config.ts": "vite",
        "rollup.config.js": "rollup",
        "rollup.config.ts": "rollup",
        "tailwind.config.js": "tailwindcss",
        "tailwind.config.ts": "tailwindcss",
        ".eslintrc": "eslint",
        ".eslintrc.js": "eslint",
        ".eslintrc.json": "eslint",
        ".eslintrc.cjs": "eslint",
        ".prettierrc": "prettier",
        ".prettierrc.js": "prettier",
        ".prettierrc.json": "prettier",
        ".babelrc": "babel",
        ".babelrc.js": "babel",
        ".babelrc.json": "babel",
        ".stylelintrc": "stylelint",
        ".stylelintrc.js": "stylelint",
        ".stylelintrc.json": "stylelint",
        "postcss.config.js": "postcss",
        ".postcssrc": "postcss",
        ".editorconfig": "editorconfig",
        ".browserslistrc": "browserlist",
        ".npmrc": "npm",
        ".env": "settings",
        ".env.local": "settings",
        ".env.development": "settings",
        ".env.production": "settings",
        "license": "license",
        "license.md": "license",
        "license.txt": "license",
        "readme": "readme",
        "readme.md": "readme",
        "readme.txt": "readme",
        "changelog": "changelog",
        "changelog.md": "changelog",
        "changelog.txt": "changelog",
        "todo": "todo",
        "todo.md": "todo",
        "todo.txt": "todo",
    ]

    /// Extensions → asset catalog name.
    private static let extensionAssets: [String: String] = [
        "js": "javascript", "mjs": "javascript", "cjs": "javascript",
        "jsx": "react",
        "ts": "typescript", "mts": "typescript", "cts": "typescript",
        "tsx": "react_ts",
        "vue": "vue", "svelte": "svelte", "astro": "astro",
        "next": "next", "nuxt": "nuxt", "remix": "remix", "qwik": "qwik",
        "css": "css", "scss": "sass", "sass": "sass", "less": "less",
        "py": "python", "pyw": "python", "pyx": "python",
        "rb": "ruby", "rake": "ruby",
        "go": "go",
        "rs": "rust",
        "java": "java",
        "kt": "kotlin", "kts": "kotlin",
        "c": "c", "h": "h",
        "cpp": "cpp", "cc": "cpp", "cxx": "cpp",
        "hpp": "hpp", "hh": "hpp", "hxx": "hpp",
        "m": "objective-c", "mm": "objective-cpp",
        "php": "php", "lua": "lua", "dart": "dart", "scala": "scala",
        "r": "r", "jl": "julia", "zig": "zig",
        "ex": "elixir", "exs": "elixir", "elm": "elm", "hs": "haskell",
        "ml": "ocaml", "mli": "ocaml",
        "clj": "clojure", "cljs": "clojure", "cljc": "clojure",
        "erl": "erlang", "hrl": "erlang",
        "pl": "perl", "pm": "perl",
        "sh": "bashly", "bash": "bashly", "zsh": "bashly",
        "v": "vlang", "gleam": "gleam", "nim": "nim", "cr": "crystal",
        "ps1": "powershell",
        "toml": "toml", "graphql": "graphql", "gql": "graphql",
        "prisma": "prisma",
        "md": "markdown", "markdown": "markdown", "mdx": "mdx",
        "tex": "tex",
        "jsonc": "json", "json5": "json",
        "yaml": "yaml", "yml": "yaml",
        "html": "html", "htm": "html",
        "svg": "svg", "gif": "gif",
        "xcstrings": "xcstrings-badge",
        "xml": "xml",
        "sql": "database",
        "proto": "proto",
        "lock": "lock",
    ]

    // MARK: - UTType → SF Symbol

    private static func utTypeIcon(_ uttype: UTType, size: CGFloat) -> MTImage? {
        switch uttype {
        case .swiftSource:
            return symbol("swift", color: .systemOrange, size: size)
        case UTType("com.apple.dt.assetcatalog"):
            return symbol("photo.on.rectangle.angled", color: .systemBlue, size: size)
        case UTType("com.apple.xcode.entitlements-property-list"):
            return symbol("seal", color: .systemYellow, size: size)
        case UTType("com.apple.property-list"):
            return symbol("list.bullet.rectangle", color: .systemGray, size: size)
        case UTType("com.apple.interfacebuilder.document.storyboard"):
            return symbol("rectangle.on.rectangle", color: .systemBlue, size: size)
        case UTType("com.apple.interfacebuilder.document.xib"):
            return symbol("rectangle.on.rectangle", color: .systemOrange, size: size)
        case UTType("com.apple.coredata.model"):
            return symbol("cylinder.split.1x2", color: .systemPurple, size: size)
        case .json:
            return symbol("curlybraces", color: .systemYellow, size: size)
        case .xml:
            return symbol("chevron.left.forwardslash.chevron.right", color: .systemGreen, size: size)
        case .pdf:
            return symbol("doc.richtext", color: .systemRed, size: size)
        case .rtf, .rtfd:
            return symbol("doc.richtext.fill", color: .systemBlue, size: size)
        case .plainText:
            return symbol("doc.text", color: .systemGray, size: size)
        case .log:
            return symbol("doc.text.magnifyingglass", color: .systemGray, size: size)
        case .ico:
            return symbol("app.badge", color: .systemBlue, size: size)
        case .font:
            return symbol("textformat", color: .systemBlue, size: size)
        case .zip, .gzip, .bz2:
            return symbol("doc.zipper", color: .systemGray, size: size)
        case .shellScript:
            return symbol("terminal", color: .systemGreen, size: size)
        default:
            break
        }

        if uttype.conforms(to: .image) {
            return symbol("photo", color: .systemYellow, size: size)
        } else if uttype.conforms(to: .movie) {
            return symbol("film", color: .systemPurple, size: size)
        } else if uttype.conforms(to: .audio) {
            return symbol("waveform", color: .systemPink, size: size)
        } else if uttype.conforms(to: .archive) {
            return symbol("doc.zipper", color: .systemGray, size: size)
        } else if uttype.conforms(to: .sourceCode) {
            return symbol("curlybraces.square", color: .systemBlue, size: size)
        } else if uttype.conforms(to: .executable) {
            return symbol("terminal", color: .systemGreen, size: size)
        } else if uttype.conforms(to: .directory) {
            return symbol("folder", color: .systemBlue, size: size)
        } else if uttype.conforms(to: .text) {
            return symbol("doc.text", color: .systemGray, size: size)
        }
        return symbol("doc", color: .systemGray, size: size)
    }

    // MARK: - Platform image construction

    /// Scales to fit inside `size`×`size`, preserving aspect ratio —
    /// the equivalent of `scaledToFit` in the former icon view.
    private static func scaledToFit(_ image: MTImage, size: CGFloat) -> MTImage {
        let intrinsic = image.size
        guard intrinsic.width > 0, intrinsic.height > 0 else { return image }
        let target = CGSize(
            width: intrinsic.width * (size / max(intrinsic.width, intrinsic.height)),
            height: intrinsic.height * (size / max(intrinsic.width, intrinsic.height))
        )
        #if canImport(AppKit)
        image.size = target
        return image
        #elseif canImport(UIKit)
        return UIGraphicsImageRenderer(size: target).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        #else
        return image
        #endif
    }

    private static func asset(_ name: String, size: CGFloat) -> MTImage? {
        #if canImport(AppKit)
        guard let image = NSImage(named: name) else { return nil }
        return scaledToFit(image, size: size)
        #elseif canImport(UIKit)
        guard let image = UIImage(named: name) else { return nil }
        return scaledToFit(image, size: size)
        #else
        return nil
        #endif
    }

    private static func symbol(_ name: String, color: MTColor?, size: CGFloat) -> MTImage? {
        #if canImport(AppKit)
        var configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        if let color {
            configuration = configuration.applying(.init(paletteColors: [color]))
        }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        return scaledToFit(image, size: size)
        #elseif canImport(UIKit)
        let configuration = UIImage.SymbolConfiguration(pointSize: size, weight: .regular)
        var image = UIImage(systemName: name, withConfiguration: configuration)
        if let color {
            image = image?.withTintColor(color, renderingMode: .alwaysOriginal)
        }
        guard let image else { return nil }
        return scaledToFit(image, size: size)
        #else
        return nil
        #endif
    }
}
