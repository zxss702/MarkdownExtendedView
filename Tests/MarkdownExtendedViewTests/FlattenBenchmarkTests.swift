import XCTest
import Markdown
@testable import MarkdownExtendedView

/// Init-cost benchmark: parses + flattens a representative mixed
/// document (big CJK paragraph, inline + block LaTeX, mermaid, code
/// references, code block, tables) and reports per-phase timings.
final class FlattenBenchmarkTests: XCTestCase {

    private static let content = #"""

## 二级标题

这里包含了6种不同的 Mermaid 图表：

### 1. 序列图 (Sequence Diagram)
```mermaid
sequenceDiagram
    Alice ->> Bob: Hello Bob, how are you?
    Bob-->>John: How about you John?
    Bob--x Alice: I am good thanks!
    Bob-x John: I am good thanks!
    Note right of John: Bob thinks a long<br/>long time.
    Bob-->Alice: Checking with John...
    Alice->John: Yes... John, how are you?
```

### 2. 流程图 (Flowchart)
```mermaid
graph TD;
    A[Start] --> B{Is it?};
    B -- Yes --> C[OK];
    C --> D[Rethink];
    D --> B;
    B -- No ----> E[End];
```

### 3. 类图 (Class Diagram)
```mermaid
classDiagram
    Animal <|-- Duck
    Animal <|-- Fish
    Animal <|-- Zebra
    Animal : +int age
    Animal : +String gender
    Animal: +isMammal()
    class Duck{
        +String beakColor
        +swim()
        +quack()
    }
    class Fish{
        -int sizeInFeet
        -canEat()
    }
    class Zebra{
        +bool is_wild
        +run()
    }
```

### 4. 实体关系图 (ER Diagram)
```mermaid
erDiagram
    CUSTOMER ||--o{ ORDER : places
    ORDER ||--|{ LINE-ITEM : contains
    CUSTOMER }|..|{ DELIVERY-ADDRESS : uses
```

### 5. XY 图表 (XY Chart)
```mermaid
xychart-beta
    title "Sales Revenue"
    x-axis [jan, feb, mar, apr, may, jun, jul, aug, sep, oct, nov, dec]
    y-axis "Revenue (in $)" 4000 --> 11000
    bar [5000, 6000, 7500, 8200, 9500, 10500, 11000, 10200, 9200, 8500, 7000, 6000]
    line [5000, 6000, 7500, 8200, 9500, 10500, 11000, 10200, 9200, 8500, 7000, 6000]
```

### 6. 状态图 (State Diagram)
```mermaid
stateDiagram-v2
    [*] --> Still
    Still --> [*]
    Still --> Moving
    Moving --> Still
    Moving --> Crash
    Crash --> [*]
```

这是一段普通文字：

予观夫巴陵胜状，在洞庭一湖。衔远山，吞长江，浩浩汤汤，横无际涯；朝晖夕阴，气象万千。此则岳阳楼之大观也，前人之述备矣。然则北通巫峡，南极潇湘，迁客骚人，多会于此，览物之情，得无异乎？ 若夫霪雨霏霏，连月不开，阴风怒号，浊浪排空；日星隐曜，山岳潜形；商旅不行，樯倾楫摧；薄暮冥冥，虎啸猿啼。登斯楼也，则有去国怀乡，忧谗畏讥，满目萧然，感极而悲$L \cdot \frac{di}{dt}$者矣。至若春和景明，波澜不惊，上下天光，一碧万顷；沙鸥翔集，锦鳞游泳；岸芷汀兰，郁郁青青。而或长烟一空，皓月千里，浮光跃金，静影沉璧，渔歌互答，此乐何极！登斯楼也，则有心旷神怡，宠辱偕忘，把酒临风，其喜洋洋者矣。予观夫巴陵胜状，在洞庭一湖。衔远山，吞长江，浩浩汤汤，横无际涯；朝晖夕阴，气象万千。此则岳阳楼之大观也，前人之述备矣。然则北通巫峡，南极潇湘，迁客骚人，多会于此，览物之情，得无异乎？ 若夫霪雨霏霏，连月不开，阴风怒号，浊浪排空；日星隐曜，山岳潜形；商旅不行，樯倾楫摧；薄暮冥冥，虎啸猿啼。登斯楼也，则有去国怀乡，忧谗畏讥，满目萧然，感极而悲 $L \cdot \frac{di}{dt}$ 者矣。至若春和景明，波澜不惊，上下天光，一碧万顷；沙鸥翔集，锦鳞游泳；岸芷汀兰，郁郁青青。而或长烟一空，皓月千里，浮光跃金，静影沉璧，渔歌互答，此乐何极！登斯楼也，则有心旷神怡，宠辱偕忘，把酒临风，其喜洋洋者矣。予观夫巴陵胜状，在洞庭一湖。衔远山，吞长江，浩浩汤汤，横无际涯；朝晖夕阴，气象万千。此则岳阳楼之大观也，前人之述备矣。然则北通巫峡，南极潇湘，迁客骚人，多会于此，览物之情，得无异乎？ 若夫霪雨霏霏，连月不开，阴风怒号，浊浪排空；日星隐曜，山岳潜形；商旅不行，樯倾楫摧；薄暮冥冥，虎啸猿啼。登斯楼也，则有去国怀乡，忧谗畏讥，满目萧然，感极而悲 $L \cdot \frac{di}{dt}$ 者矣。至若春和景明，波澜不惊，上下天光，一碧万顷；沙鸥翔集，锦鳞游泳；岸芷汀兰，郁郁青青。而或长烟一空，皓月千里，浮光跃金，静影沉璧，渔歌互答，此乐何极！登斯楼也，则有心旷神怡，宠辱偕忘，把酒临风，其喜洋洋者矣。予观夫巴陵胜状，在洞庭一湖。衔远山，吞长江，浩浩汤汤，横无际涯；朝晖夕阴，气象万千 `file:///Volumes/知阳/开发/Packges/JsonData/Sources/JsonData/ModelContext.swift:46-58` 。此则岳阳楼之大观也，前人之述备矣。然则北通巫峡，南极潇湘，迁客骚人，多会于此，览物之情，得无异乎？ 若夫霪雨霏霏，连月不开，阴风怒号，浊浪排空；日星隐曜，山岳潜形；商旅不行，樯倾楫摧；薄暮冥冥，虎啸猿啼。登斯楼也，则有去国怀乡，忧谗畏讥，满目萧然，感极而悲 $L \cdot \frac{di}{dt}$览物之情，得无异乎？ 若夫霪雨霏霏，连月不开，阴风怒号，浊浪排空；日星隐曜，山岳潜形；商旅不行，樯倾楫摧；薄暮冥冥，虎啸猿啼。登斯楼也，则有去国怀乡，忧谗畏讥，满目萧然，感极而悲 $L \cdot \frac{di}{dt}$ 者矣。至若春和景明，波澜不惊，上下天光，一碧万顷；沙鸥翔集，锦鳞游泳；岸芷汀兰，郁郁青青。而或长烟一空，皓月千里，浮光跃金，静影沉璧，渔歌互答，此乐何极！登斯楼也，则有心旷神怡，宠辱偕忘，把酒临风，其喜洋洋者矣。予观夫巴陵胜状，在洞庭一湖。衔远山，吞长江，浩浩汤汤，横无际涯；朝晖夕阴，气象万千。此则岳阳楼之大观也，前人之述备矣。然则北通巫峡，南极潇湘，迁客骚人，多会于此，览物之情，得无异乎？ 若夫霪雨霏霏，连月不开，阴风怒号，浊浪排空；日星隐曜，山岳潜形；商旅不行，樯倾楫摧；薄暮冥冥，虎啸猿啼。登斯楼也，则有去国怀乡，忧谗畏讥，满目萧然，感极而悲 $L \cdot \frac{di}{dt}$ 者矣。至若春和景明，波澜不惊，上下天光，一碧万顷；沙鸥翔集，锦鳞游泳；岸芷汀兰，郁郁青青。而或长烟一空，皓月千里，浮光跃金，静影沉璧，渔歌互答，此乐何极！登斯楼也，则有心旷神怡，宠辱偕忘，把酒临风，其喜洋洋者矣。予观夫巴陵胜状，在洞庭一湖。衔远山，吞长江，浩浩汤汤，横无际涯；朝晖夕阴，气象万千。此则岳阳楼之大观也，前人之述备矣。然则北通巫峡，南极潇湘，迁客骚人，多会于此，览物之情，得无异乎？ 若夫霪雨霏霏，连月不开，阴风怒号，浊浪排空；日星隐曜，山岳潜形；商旅不行，樯倾楫摧；薄暮冥冥，虎啸猿啼。登斯楼也，则有去国怀乡，忧谗畏讥，满目萧然，感极而悲 $L \cdot \frac{di}{dt}$ 者矣。至若春和景明，波澜不惊，上下天光，一碧万顷；沙鸥翔集，锦鳞游泳；岸芷汀兰，郁郁青青。而或长烟一空，皓月千里，浮光跃金，静影沉璧，渔歌互答，此乐何极！登斯楼也，则有心旷神怡，宠辱偕忘，把酒临风，其喜洋洋者矣。予观夫巴陵胜状，在洞庭一湖。衔远山，吞长江，浩浩汤汤，横无际涯；朝晖夕阴，气象万千。此则岳阳楼之大观也，前人之述备矣。然则北通巫峡，南极潇湘，迁客骚人，多会于此，览物之情，得无异乎？ 若夫霪雨霏霏，连月不开，阴风怒号，浊浪排空；日星隐曜，山岳潜形；商旅不行，樯倾楫摧；薄暮冥冥，虎啸猿啼。登斯楼也，则有去国怀乡，忧谗畏讥，满目萧然，感极而悲 $L \cdot \frac{di}{dt}$

这是**加粗**，*斜体*，~~删除线~~，[链接](https://blog.imalan.cn)。

这是块引用与嵌套块引用：

> 安得广厦千万间，大庇天下寒士俱欢颜！风雨不动安如山。
> > 呜呼！何时眼前突兀见此屋，吾庐独破受冻死亦足！

这是行内代码：`int a=1;`。这是代码块：

```c++
int main(int argc , char** argv){
    std::cout << "Hello World!\n";
    return 0;
}
```

这是无序列表：
$$i(t) = \sqrt{2}I \cos(\omega t)$$

* 苹果
    * 红将军
    * 元帅
* 香蕉
* 梨

这是有序列表：

1. 打开冰箱
    1. 右手放在冰箱门拉手上
    2. 左手扶住冰箱主体
    3. 右手向后用力
2. 把大象放进冰箱
3. 关上冰箱

> 这是行内公式：$m\times n$，这是块级公式：

$$C_{m\times k}=A_{m\times n}\cdot B_{n\times k}$$

这是一张图片：

![logo.jpg](https://blog.imalan.cn/logo.jpg)
![1fa0f7b958d4234db58eac4f75318d7b.jpeg](https://cdn.imalan.cn/img/post/2934349b033b5bb5a19efc7233d3d539b700bcf5.jpg)

# 哈哈哈吃吧 `file:///Volumes/知阳/开发/Packges/JsonData/Sources/JsonData/ModelContext.swift:46-58`
这是表格：
`file:///Volumes/知阳/开发/Packges/JsonData/Sources/JsonData/ModelContext.swift:46-58`
第一格表头 | 第二格表头
--------- | -------------
内容单元格 第一列第一格 | 内容单元格第二列第一格 `file:///Volumes/知阳/开发/Packges/JsonData/Sources/JsonData/ModelContext.swift:46-58`
内容单元格 第一列第二格 多加文字 | 内容单元格第二列第二格内容单元格第二列第二格内容单元格第二列第二格内容单元格第二列第二格内容单元格第二列第二格内容单元格第二列第二格内容单元格第二列第二格内容单元格第二列第二格内容单元格第二列第二格内容单元格第二列第二格内容单元格第二列第二格内容单元格第二列第二格

First | Second | Third | Fourth
----- | ------ | ----- | ------
One   | Two    | Three | Four
^     | Five   | ^     | Six
Seven | ^      | ^     | Eight

First | Second | Third
----- | ------ | -----
One           || Two
^             || Three

Leading | Center | Trailing |
:------ | :----: | -------: |
One             || Two      |
Three   | Four             ||
Five                      |||

First | Second | Third |
----- | ------ | ----- |
One           || Two   |
Three | Four          ||
Five                 |||

水平分割线[^这是脚注]：

"""#

    @MainActor
    func testFlattenBenchmark() {
        // First pass on cold caches — the real init cost (latex/icon
        // resolution is now lazy, so this measures parse + flatten).
        let coldStart = ContinuousClock.now
        _ = MarkdownFlattener.flatten(Self.content, baseURL: nil, previousBlocks: [])
        print("[BENCH] COLD total=\(coldStart.duration(to: ContinuousClock.now))")

        var previous: [MDBlock] = []
        for i in 0..<5 {
            #if PROFILING
            MarkdownFlattener.benchReset()
            #endif
            let start = ContinuousClock.now
            let blocks = MarkdownFlattener.flatten(Self.content, baseURL: nil, previousBlocks: previous)
            let total = start.duration(to: ContinuousClock.now)
            previous = blocks
            print("[BENCH] iteration \(i) blocks=\(blocks.count) total=\(total)")
            #if PROFILING
            MarkdownFlattener.benchReport()
            #endif
        }

        // Split the remaining cost: cmark parse alone vs everything else.
        let parseStart = ContinuousClock.now
        _ = Markdown.Document(parsing: Self.content, options: [.disableSmartOpts, .disableSourcePosOpts])
        print("[BENCH] parse-only=\(parseStart.duration(to: ContinuousClock.now))")

        // Same document minus the giant paragraph — isolates per-glyph
        // mapping cost from structural work.
        let shortContent = """
        ## 标题

        短文本 `file:///tmp/a.swift:46-58` 和 $x^2$ 混排。

        ```c++
        int main() { return 0; }
        ```
        """
        for i in 0..<3 {
            let start = ContinuousClock.now
            _ = MarkdownFlattener.flatten(shortContent, baseURL: nil, previousBlocks: [])
            print("[BENCH] short \(i) total=\(start.duration(to: ContinuousClock.now))")
        }

        // The giant paragraph alone.
        let giantParagraph = Self.content
            .components(separatedBy: "\n\n")
            .first { $0.contains("予观夫") } ?? ""
        for i in 0..<3 {
            let start = ContinuousClock.now
            _ = MarkdownFlattener.flatten(giantParagraph, baseURL: nil, previousBlocks: [])
            print("[BENCH] giantPara \(i) total=\(start.duration(to: ContinuousClock.now))")
        }
        // A pure-text paragraph of similar length.
        let pureText = String(repeating: "予观夫巴陵胜状在洞庭一湖衔远山吞长江浩浩汤汤横无际涯。", count: 60)
        for i in 0..<3 {
            let start = ContinuousClock.now
            _ = MarkdownFlattener.flatten(pureText, baseURL: nil, previousBlocks: [])
            print("[BENCH] pureText(\(pureText.count)ch) \(i) total=\(start.duration(to: ContinuousClock.now))")
        }

        // Isolate `finishInline`'s AttributeContainer + mergeAttributes
        // cost — the per-block fixed overhead.
        let m: [GlobalSelectionCache.CharacterMapping] = [.init(char: "a")]
        var mergeCost: Duration = .zero
        var attrCost: Duration = .zero
        for _ in 0..<28 {
            var s = AttributedString("测试文字")
            let a0 = ContinuousClock.now
            var container = AttributeContainer()
            container[MarkdownBakedMappingsKey.self] = m
            container[MarkdownBakedSignatureKey.self] = "m:a"
            attrCost += a0.duration(to: ContinuousClock.now)
            let m0 = ContinuousClock.now
            s.mergeAttributes(container)
            mergeCost += m0.duration(to: ContinuousClock.now)
        }
        print("[BENCH] 28x container=\(attrCost) merge=\(mergeCost)")

        // Per-piece AttributedString cost: init + append, small vs big.
        let big = giantParagraph
        var t0 = ContinuousClock.now
        var acc = AttributedString()
        for _ in 0..<10 {
            acc.append(AttributedString(big))
        }
        print("[BENCH] 10x bigAttrInit+append=\(t0.duration(to: ContinuousClock.now))")

        t0 = ContinuousClock.now
        var inits: [AttributedString] = []
        for _ in 0..<10 {
            inits.append(AttributedString(big))
        }
        print("[BENCH] 10x bigAttrInitOnly=\(t0.duration(to: ContinuousClock.now)) n=\(inits.count)")

        // Single-init alternative: join plain strings, one init.
        t0 = ContinuousClock.now
        var joined = ""
        for _ in 0..<10 { joined += big }
        var single = AttributedString(joined)
        print("[BENCH] join+singleInit=\(t0.duration(to: ContinuousClock.now)) len=\(single.characters.count)")
        single.append(acc)

        // Small-piece fixed cost.
        t0 = ContinuousClock.now
        var acc2 = AttributedString()
        for _ in 0..<100 {
            acc2.append(AttributedString("小段落文本 abc"))
        }
        print("[BENCH] 100x smallAttrInit+append=\(t0.duration(to: ContinuousClock.now))")

        // NSAttributedString round trip.
        t0 = ContinuousClock.now
        let ns = NSMutableAttributedString()
        for _ in 0..<10 {
            ns.append(NSAttributedString(string: big))
        }
        let nsAppendDone = t0.duration(to: ContinuousClock.now)
        t0 = ContinuousClock.now
        var converted = AttributedString(ns)
        print("[BENCH] 10x bigNSAttr append=\(nsAppendDone) convert=\(t0.duration(to: ContinuousClock.now)) len=\(converted.characters.count)")
        converted.append(single)

        // String += cost (signatureText path).
        t0 = ContinuousClock.now
        var sig = ""
        for _ in 0..<10 { sig += big }
        print("[BENCH] 10x bigStringAppend=\(t0.duration(to: ContinuousClock.now)) sig=\(sig.count)")
    }
}
