# QuickPad — macOS Native 极速笔记

> 融合 Karpathy "append-and-review" 单流思想 + Bullet Journal rapid logging + Raycast Notes 浮动体验

---

## 设计哲学

三个思想源头：

1. **Karpathy append-and-review** — 只维护一个流，append 到顶部，重要的打捞，不重要的自然沉底。拒绝文件夹、分类、标签系统的认知开销。
2. **Bullet Journal rapid logging** — 用符号前缀瞬间分类条目（task/event/note/idea），短句记录，不写完整句子。Task 有生命周期（待办 → 完成 / 迁移 / 取消）。
3. **Raycast Notes** — 菜单栏常驻，全局热键呼出，浮动窗口置顶，极低延迟。

QuickPad = **BuJo 的输入语言** + **Karpathy 的单流结构** + **Raycast 的 macOS 原生体验** + **重力下沉的视觉系统**

---

## 核心概念

### 1. The Stream（主流）

App 的灵魂。对应 Karpathy 的「一个 note」，但条目带有 BuJo bullet type。

```
┌─────────────────────────────────────────────┐
│ [—] 快速输入区（始终在顶部）                   │
│ ┌─────────────────────────────────────────┐ │
│ │ — rapid log... (enter to append)        │ │
│ │ [— note] [☐ task] [○ event] [! idea]    │ │
│ │ [r: read] [w: watch] [* priority]       │ │
│ └─────────────────────────────────────────┘ │
│─────────────── TODAY · APR 9 ───────────────│
│ !  QuickPad 融合 BuJo + gravity stream  now │
│ ☐  和标注组对齐点云密度标准            2h   │
│ —  read: SplatAD appendix B            5h   │  ← opacity 100%
│ ○  14:00 architecture review           6h   │
│─────────────── YESTERDAY · APR 8 ───────────│
│ —  kubectl logs ... | grep loss       11pm  │
│ —  watch: 3Blue1Brown Attention        8pm  │  ← opacity 85%
│ ▶  spconv 3.0 hash → 迁移到下周       3pm  │
│─────────────── APR 6 · SUN ─────────────────│
│ —  frozen ConvNeXt-T 快 3x, 差 0.4          │  ← opacity 68%
│ !  uncertainty 做 temporal weight            │
│─────────────── APR 2 · WED ─────────────────│
│ —  CMT dual-query: heatmap→near              │  ← opacity 50%
│─────────────── MAR 20 ──────────────────────│
│ —  world model: traj pred + diffusion        │  ← opacity 22%
│─── DONE (3) ▶ ──────────────────────────────│
│  ✓  提交 spconv 依赖锁定 PR          Apr 3  │  ← 折叠，极淡
│  ✓  push 监控 endpoint 部署           Mar 28 │
└─────────────────────────────────────────────┘
```

### 2. Bullet Types（BuJo 符号系统）

输入层面用简洁符号瞬间分类：

| 符号 | 类型 | 键盘触发 | 说明 |
|------|------|---------|------|
| `—` | Note | 默认 | 想法、观察、记录、临时草稿 |
| `☐` | Task | `[]` 或 Tab切换 | 待办事项 |
| `○` | Event | Tab切换 | 时间点事件（会议、deadline） |
| `!` | Idea | `!` 前缀 | 灵感、insight |

**Task 生命周期（BuJo 核心）：**

```
☐ 待办  →  ✓ 完成（自动沉入 DONE 区）
         →  ▶ 迁移（推迟到未来处理，标记原因）
         →  ✕ 取消（删除线，沉底）
```

**Signifiers（附加标记）：**

| 标记 | 含义 | 触发方式 |
|------|------|---------|
| `*` | Priority（左侧红色竖线） | `*` 前缀 |
| `read:` | 待读 | 文本前缀，自动变标签 |
| `watch:` | 待看 | 文本前缀，自动变标签 |
| `listen:` | 待听 | 文本前缀，自动变标签 |
| `?` | 待探索/研究 | `?` 前缀 |

### 3. 重力下沉系统（Gravity Decay）

视觉上让"时间流逝"可感知，三层递进：

#### Layer 1：Opacity 衰减

条目的不透明度随天数递减，子弹点颜色同步退化：

| 时间 | Opacity | 子弹颜色 | 时间戳精度 |
|------|---------|----------|-----------|
| 今天 | 100% | text-primary | "now" / "2h" / "5h" |
| 昨天 | 85% | text-secondary | "11pm" / "3pm" |
| 2-3天 | 68% | text-secondary | "pm" / "am" |
| 4-7天 | 50% | text-tertiary | 省略 |
| 1-2周 | 35% | text-tertiary | 省略 |
| 更早 | 22% | text-tertiary | 省略 |

#### Layer 2：日期分割线（沉积层）

每天零点（或第一次打开时）在 stream 顶部自动插入一条日期分隔线：

```
─────────── TODAY · APR 9 ───────────
              （今天的条目）
─────────── YESTERDAY · APR 8 ───────
              （昨天的条目）
─────────── APR 6 · SUN ────────────
              （更早 → 只显示日期+星期）
─────────── MAR 20 ─────────────────
              （更早 → 只显示月日）
```

分隔线的日期标签精度也在衰减：TODAY → YESTERDAY → 日期+星期 → 月日。形成地质学般的沉积层感。

#### Layer 3：点击上浮（Anti-gravity Rescue）

**直接点击条目 → 上浮到 TODAY 区顶部**

这是 Karpathy "review 时打捞" 的数字化实现：

1. 点击条目 → 原位播放上浮动画（向上飘出 + 淡出）
2. 条目插入到 TODAY 分隔线下方第一位
3. 淡入归位，age 重置为 0（恢复 100% opacity）
4. 时间戳更新为 "now"
5. 顶部显示 toast："rescued ↑ back to today"

hover 时右侧显示 "click to float ↑" 引导文字。

**设计意图**：review 时向下滚动 = 考古，看到有价值的条目单击一下就打捞回来，零摩擦。这比 Karpathy 在 Apple Notes 里 copy-paste 快得多。

### 4. 毕业机制（Stream → Pinned Note）

当 Stream 中某条内容反复被打捞且已成熟，可以"毕业"为独立的 Pinned Note：

选中条目 → `⌘⇧G`（Graduate）→ 变成独立 Markdown 文件。

```
菜单栏 popover 顶部 tab 切换：
[Stream]  📌Note1  📌Note2
```

Pinned Notes 数量强制限制 < 10，多了就违背 KISS 精神。

---

## 输入设计（Rapid Logging 体验）

### Quick Append（⌥⇧N）

从想法到记录的延迟 < 1 秒：

```
按 ⌥⇧N → ┌──────────────────────────────────────┐
          │ [—] SplatAD DataParser 要处理14路cam   │
          └──────────────────────────────────────┘
按 Enter → 消失，已追加到 Stream 顶部
```

- 极简浮动输入框，无边框，无标题栏
- 左侧 bullet 按钮，点击循环切换类型（— → ☐ → ○ → !）
- Tab 键也可切换 bullet type
- 支持多行（Shift+Enter 换行）
- Enter 提交并关闭，Esc 取消
- 文本前缀自动识别：`read:` `watch:` `listen:` 自动变标签
- `*` 前缀自动标记 priority

### Popover 内输入

菜单栏点击展开 popover 时，输入区始终在顶部：

```
┌─────────────────────────────────────────┐
│ [—▾] rapid log... (enter to append)     │
│ [— note] [☐ task] [○ event] [! idea]   │  ← hint bar
│ [r: read] [w: watch] [* priority]       │
└─────────────────────────────────────────┘
```

Hint bar 提供快捷按钮，点击切换 bullet type 或插入前缀。新手引导，熟练后可隐藏。

### 自动识别规则

| 输入内容 | 自动行为 |
|---------|---------|
| `read: SplatAD` | bullet=note, 添加 read 标签 |
| `watch: 3B1B` | bullet=note, 添加 watch 标签 |
| `* 紧急：对齐密度标准` | 标记 priority（红色左侧竖线） |
| `? spconv 3.0 性能` | 标记为待探索 |
| `14:00 meeting` | 如果当前 bullet=event, 保持；否则不干预 |
| `` `kubectl logs...` `` | 自动识别为代码片段，等宽渲染 |

---

## 交互设计

### 菜单栏

```
普通点击    → 展开 popover（显示 Stream，光标在输入区）
⌥ + 点击   → 直接新建条目（Quick Append 弹窗）
右键        → Pinned Notes 列表 + Preferences
```

### 全局快捷键（系统级，可在 config.toml 自定义）

| 快捷键 | 动作 | 说明 |
|--------|------|------|
| `⌥N` | Toggle Stream | 呼出/隐藏主窗口 |
| `⌥⇧N` | Quick Append | 极简输入框，回车追加并消失 |
| `⌥⇧F` | Quick Search | 全文搜索弹窗（⌘F） |
| `⌥⇧T` | Quick Task | 输入框自动设为 ☐ task 类型 |
| `⌥1-9` | Open Pinned Note | 直达毕业笔记 |

### Stream 内操作

| 操作 | 触发方式 | 说明 |
|------|---------|------|
| 上浮（rescue） | 单击条目 | 打捞回 TODAY 顶部，重置 age |
| 切换 task 状态 | 点击 checkbox | ☐ → ✓ done / 右键 → ▶ migrated |
| 编辑条目 | 双击 或 Enter | 原地进入编辑模式 |
| 毕业为 Pinned Note | `⌘⇧G` | 选中条目提取为独立笔记 |
| 合并条目 | `⌘M` | 选中多个合并为一条（review 整理用） |
| 删除 | `⌘⌫` | 软删除，30天可恢复 |
| 复制为 Markdown | `⌘⇧C` | 复制到剪贴板 |
| 全文搜索 | `⌘F` | 实时过滤，高亮匹配 |
| 按类型过滤 | `⌘1-5` | 快速过滤 read/watch/task/event/idea |

### 浮动窗口（Pin to Desktop）

从 popover 拖拽标题栏 → 拆出为独立浮动窗口，置顶于所有窗口之上。
适合把当天的 task list 钉在桌面上。

### Dynamic Island 组件

菜单栏右键 → **Show Island**，屏幕顶部中央出现一颗始终可见的胶囊：

- **Compact 态** — 显示最新一条 entry 的 bullet + 内容摘要
- **Expanded 态** — hover 时展开为更高的面板，显示更多信息
- 切换动画：SwiftUI spring（response 0.42，damping 0.8），与窗口尺寸过渡统一
- 承载窗口为 `IslandPanel`（NSPanel 子类），`.floating` level，点击穿透修复后仅在交互区截获事件
- 非交互模式下不抢焦点，不打扰前台应用
- 再次右键菜单栏 → **Hide Island** 收起

### Shortcut Hints 覆盖层

`⌘/` 在 popover 内打开一个半透明 overlay，列出所有快捷键。
给新用户做内置 cheatsheet，熟练后随时 `⌘/` 再关掉。

---

## 数据存储

遵循 KISS 原则：**纯文本 Markdown，人类可读，vim 可编辑，grep 可搜索。**

### 目录结构

```
~/.quickpad/
├── stream.md          # 主流（核心文件）
├── pinned/
│   ├── shell-cheatsheet.md
│   └── tars-architecture.md
├── archive/           # 已完成的 TODO 按月自动归档
│   └── 2025-04.md
├── trash/             # 软删除，30天自动清理
└── config.toml        # 配置（快捷键、外观、行为）
```

### stream.md 格式

```markdown
--- 2025-04-09 Wednesday ---

- 2025-04-09T22:31+09:00 [idea] QuickPad 融合 BuJo rapid logging
- 2025-04-09T20:15+09:00 [task] 和标注组对齐点云密度标准 — 300pts@50m
- 2025-04-09T18:00+09:00 [note] *priority read: SplatAD appendix B
- 2025-04-09T14:00+09:00 [event] architecture review meeting

--- 2025-04-08 Tuesday ---

- 2025-04-08T23:11+09:00 [note] `kubectl logs -f pod/tars-train-0 -c main | grep loss`
- 2025-04-08T20:00+09:00 [note] watch: 3Blue1Brown — Attention in Transformers
- 2025-04-08T15:00+09:00 [task>migrated] spconv 3.0 hash 冲突 → 迁移到下周 spike

--- 2025-04-06 Sunday ---

- 2025-04-06T16:22+09:00 [note] frozen ConvNeXt-T 比 finetune 快 3x, 精度差 0.4 mAP
- 2025-04-06T10:15+09:00 [idea] uncertainty 做 temporal attention 的 internal weight

--- 2025-04-02 Wednesday ---

- 2025-04-02T14:30+09:00 [note] CMT dual-query: heatmap queries → near, grid → far

--- 2025-03-20 Thursday ---

- 2025-03-20T21:00+09:00 [note] world model 入门: trajectory prediction + diffusion
```

**格式规则：**
- 日期分割线 `--- YYYY-MM-DD Weekday ---` 对应 app 中的沉积层
- 每条格式：`- ISO-TIMESTAMP [bullet-type] content`
- bullet-type：`note` `task` `event` `idea`
- task 状态后缀：`[task]` 待办，`[task>done]` 完成，`[task>migrated]` 迁移，`[task>cancelled]` 取消
- `*priority` 前缀标记优先级
- `read:` `watch:` `listen:` `?` 等前缀保留为 Karpathy 式标签
- 行内 Markdown 格式（反引号、粗体、链接）均支持

**rescue 操作在文件层面 = 剪切该行，粘贴到当天分割线下第一行，更新时间戳。**

### 终端兼容

```bash
# vim 直接编辑
vim ~/.quickpad/stream.md

# grep 按类型搜索
grep '\[task\]' ~/.quickpad/stream.md       # 所有待办
grep '\[idea\]' ~/.quickpad/stream.md       # 所有灵感
grep 'read:' ~/.quickpad/stream.md          # 所有待读
grep '\*priority' ~/.quickpad/stream.md     # 所有优先级

# 命令行快速追加（shell alias）
qp() {
  local type="${1:-note}"
  shift
  local ts=$(date +%Y-%m-%dT%H:%M%z)
  local today=$(date +"%Y-%m-%d %A")
  local file="$HOME/.quickpad/stream.md"
  local sep="--- $today ---"

  # 确保今天的分割线存在
  if ! head -1 "$file" 2>/dev/null | grep -qF "$sep"; then
    printf '%s\n\n' "$sep" | cat - "$file" > /tmp/qp_tmp && mv /tmp/qp_tmp "$file"
  fi

  # 在分割线后插入
  sed -i '' "s|^$sep$|$sep\n- ${ts} [${type}] $*|" "$file"
}

# 用法
qp note "spconv 3.0 看起来不错"
qp task "提交 PR"
qp idea "用 VLM 做 data quality spot check"
qp note "read: Fusion4CA section 3.2"
qp note "*priority 明天 demo 前必须修好 heading regression"
```

### config.toml

```toml
[hotkeys]
toggle_stream = "opt+n"
quick_append = "opt+shift+n"
quick_search = "opt+shift+f"
quick_task = "opt+shift+t"

[hotkeys.pinned]
"shell-cheatsheet" = "opt+1"
"tars-architecture" = "opt+2"

[appearance]
theme = "auto"                # auto | light | dark
font_family = "JetBrains Mono"
font_size = 13
popover_width = 420
floating_opacity = 0.95

[behavior]
todo_auto_archive = true
todo_archive_after_hours = 24
trash_cleanup_days = 30
max_pinned_notes = 10
show_hint_bar = true          # 熟练后可关闭

[gravity]
# opacity 衰减曲线（天数 → opacity）
# 默认值，可微调
day_0 = 1.0
day_1 = 0.85
day_3 = 0.68
day_7 = 0.50
day_14 = 0.35
day_30 = 0.22

[prefixes]
# Karpathy 式前缀 → 标签映射
"read:" = "read"
"watch:" = "watch"
"listen:" = "listen"
"?" = "explore"
```

---

## 技术架构

```
┌──────────────────────────────────────────────────────┐
│                    QuickPad.app                       │
│                                                      │
│  ┌──────────────┐  ┌─────────────────────────────┐   │
│  │ MenuBarMgr   │  │    HotkeyManager            │   │
│  │ (NSStatusItem│  │    (Carbon RegisterEvent     │   │
│  │  + popover)  │  │     HotKey)                  │   │
│  └──────┬───────┘  └──────────────┬──────────────┘   │
│         │                         │                   │
│  ┌──────▼─────────────────────────▼──────────────┐   │
│  │              StreamViewModel                   │   │
│  │  - entries: [StreamEntry]                      │   │
│  │  - append(type, text)  → prepend to stream     │   │
│  │  - rescue(entry)       → move to today top     │   │
│  │  - graduate(entries)   → create pinned note    │   │
│  │  - toggleTask(entry)   → done/migrated/cancel  │   │
│  │  - merge(entries)      → combine into one      │   │
│  │  - search(query)       → filtered entries      │   │
│  │  - filterByType(type)  → type-filtered view    │   │
│  │  - gravityOpacity(entry) → computed opacity    │   │
│  └──────────────────┬────────────────────────────┘   │
│                     │                                 │
│  ┌──────────────────▼────────────────────────────┐   │
│  │           MarkdownFileStore                    │   │
│  │  - read/write stream.md                        │   │
│  │  - parse day separators + entries              │   │
│  │  - ensureTodaySeparator()                      │   │
│  │  - FSEvents watcher（vim 外部编辑同步）         │   │
│  │  - pinned note CRUD                            │   │
│  │  - archive rotation (monthly)                  │   │
│  │  - trash cleanup (30-day)                      │   │
│  └───────────────────────────────────────────────┘   │
│                                                      │
│  UI Layer (SwiftUI + AppKit):                        │
│  ┌────────────┐ ┌──────────────┐ ┌───────────────┐  │
│  │ PopoverView│ │ QuickAppend  │ │ FloatingWindow│  │
│  │ (stream +  │ │ Panel        │ │ (detached,    │  │
│  │  input +   │ │ (⌥⇧N, mini  │ │  .floating    │  │
│  │  tabs)     │ │  input only) │ │  level)       │  │
│  └────────────┘ └──────────────┘ └───────────────┘  │
│  ┌────────────┐ ┌──────────────┐                    │
│  │ IslandPanel│ │ Theme.swift  │                    │
│  │ + IslandVw │ │ (palette,    │                    │
│  │ (compact/  │ │  subtle      │                    │
│  │  expanded) │ │  buttons,    │                    │
│  │            │ │  fade divs)  │                    │
│  └────────────┘ └──────────────┘                    │
└──────────────────────────────────────────────────────┘

#### Theme 系统

`Views/Theme.swift` 集中管理配色、按钮样式、分隔线。

- 统一 palette：text-primary / secondary / tertiary、accent、subtleBackground、fadeDivider
- `SubtleButton` 样式：hover 才显色，避免视觉噪音
- 分隔线使用两端渐隐的 `fadeDivider`
- 主题切换：Auto / Light / Dark（菜单栏右键 → Appearance 循环）
- 所有视图组件从 Theme 读取，而非写死颜色，方便一处改全局生效
```

### 关键实现

#### StreamEntry 数据模型

```swift
struct StreamEntry: Identifiable, Codable {
    let id: UUID
    var timestamp: Date
    var bulletType: BulletType      // .note, .task, .event, .idea
    var taskState: TaskState?       // .pending, .done, .migrated, .cancelled
    var content: String
    var isPriority: Bool
    var prefixTag: String?          // "read", "watch", "listen", "explore"

    // Gravity
    var ageInDays: Int { Calendar.current.dateComponents([.day], from: timestamp, to: .now).day ?? 0 }
    var gravityOpacity: Double {
        switch ageInDays {
        case 0: return 1.0
        case 1: return 0.85
        case 2...3: return 0.68
        case 4...7: return 0.50
        case 8...14: return 0.35
        default: return 0.22
        }
    }
}

enum BulletType: String, Codable {
    case note, task, event, idea
}

enum TaskState: String, Codable {
    case pending, done, migrated, cancelled
}
```

#### 全局热键（Carbon API）

```swift
import Carbon

class HotkeyManager {
    private var hotKeyRefs: [EventHotKeyRef] = []

    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, handler: @escaping () -> Void) {
        var hotKeyID = EventHotKeyID(signature: fourCharCode("QPAD"), id: id)
        var hotKeyRef: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
        if let ref = hotKeyRef { hotKeyRefs.append(ref) }
    }
}
```

#### FSEvents 文件监控（vim 外部编辑同步）

```swift
class FileWatcher {
    private var stream: FSEventStreamRef?

    func watch(path: String, onChange: @escaping () -> Void) {
        let callback: FSEventStreamCallback = { _, _, numEvents, eventPaths, _, _ in
            onChange()
        }
        var context = FSEventStreamContext()
        stream = FSEventStreamCreate(nil, callback, &context,
            [path as CFString] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5, // 500ms debounce
            UInt32(kFSEventStreamCreateFlagFileEvents))
        FSEventStreamScheduleWithRunLoop(stream!, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream!)
    }
}
```

#### Quick Append Panel（不抢焦点）

```swift
let panel = NSPanel(
    contentRect: NSRect(x: 0, y: 0, width: 420, height: 48),
    styleMask: [.nonactivatingPanel, .fullSizeContentView],
    backing: .buffered, defer: false
)
panel.level = .floating
panel.isMovableByWindowBackground = true
panel.titlebarAppearsTransparent = true
panel.backgroundColor = .clear
panel.hasShadow = true
// 居中屏幕上方 1/4 处
panel.center()
panel.setFrameOrigin(NSPoint(
    x: panel.frame.origin.x,
    y: NSScreen.main!.frame.height * 0.7
))
```

#### Rescue 动画

```swift
// SwiftUI
func rescueEntry(_ entry: StreamEntry) {
    withAnimation(.easeOut(duration: 0.35)) {
        // 1. 标记 rescuing 状态（触发上浮动画）
        entry.isRescuing = true
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        // 2. 移动到 today 区顶部
        viewModel.rescue(entry)
        // 3. 淡入归位
        withAnimation(.easeIn(duration: 0.25)) {
            entry.isRescuing = false
        }
    }
}
```

---

## 开发路线

### Phase 1 — MVP（能日常使用）

- [x] 菜单栏常驻 NSStatusItem + NSPopover
- [x] Stream 列表渲染（SwiftUI LazyVStack）
- [x] 输入区：bullet type 切换 + 回车追加
- [x] stream.md 读写 + 日期分割线解析
- [x] 全局热键 ⌥N (toggle) + ⌥⇧N (quick append)
- [x] FSEvents 文件监控（vim 编辑同步）
- [x] ⌘F 全文搜索
- [x] Pin 按钮保持 popover 不关闭

### Phase 1.5 — 编辑 + 软删除

- [x] 右键菜单 → 编辑条目（保留时间戳）
- [x] 右键菜单 → 软删除（`[type>deleted]` 标记）
- [x] 撤销删除（⌘Z，5 秒窗口）

### Phase 2 — 重力系统 + BuJo 交互

- [x] Opacity 衰减渲染（6 级透明度曲线）
- [x] 日期分割线标签衰减（TODAY → YESTERDAY → APR 6 · SUN → MAR 20）
- [x] Hover 旧条目 → 点击上浮 rescue（更新时间戳到今天）
- [x] 撤销 rescue（⌘Z，5 秒窗口，文件快照恢复）
- [x] Task 状态切换（点击 glyph: pending ↔ done；右键: migrated / cancelled）
- [x] 前缀自动识别（read: / watch: / listen: / ? → 标签列）
- [x] `*priority` 标记 → 红色左边框
- [x] 按类型过滤 ⌘1-4，⌘5 清除

### Phase 3 — 浮动窗口

- [x] ⌘D 拆出为浮动窗口 / 合回 popover
- [x] 浮动窗口置顶（NSPanel.level = .floating）
- [x] 多显示器感知（跟随 status item 所在屏幕）
- [ ] ~~Pinned Notes + 毕业 ⌘⇧G~~ — 跳过，保持 KISS
- [ ] ~~条目合并 ⌘M~~ — 跳过
- [ ] ~~config.toml~~ — 跳过

### Phase 4 — 润色

- [x] Markdown 行内渲染（code、bold、link）
- [x] 已完成任务按月自动归档（30 天阈值 → `~/.quickpad/archive/YYYY-MM.md`）
- [x] 软删除条目 30 天后自动清理
- [x] 导出可见条目为 Markdown（⌘E + NSSavePanel）
- [x] 深色/浅色/自动主题切换
- [x] 新条目顶部插入（newest-first）
- [x] 日历日 ageInDays 计算（startOfDay 对齐）
- [x] Rescue undo（⌘Z，文件快照恢复）
- [x] 右键菜单 → Bullet Type 重新分类已有条目
- [x] Shortcut Hints 覆盖层（⌘/）
- [x] CJK/Latin 混排字距与密度调优
- [x] Theme 集中化（调色板 / SubtleButton / fadeDivider）

### Phase 5 — Dynamic Island

- [x] IslandPanel + IslandView（compact / expanded 双态）
- [x] Hover 驱动的 spring 动画（response 0.42, damping 0.8）
- [x] 点击穿透修复（只在交互区截获事件，其余区域透明）
- [x] 菜单栏右键 Show/Hide Island 切换

> **归档阈值说明**：早期 `config.toml` 草案中的 `todo_archive_after_hours = 24`
> 仅为设计示意。当前实现在 `Store/StreamArchiver.swift` 中硬编码为
> **30 天**（完成/取消的任务超过 30 天自动搬进 `archive/YYYY-MM.md`）。
> config.toml 目前未实现，见 ROADMAP。

完整发布时间线见项目根目录 `CHANGELOG.md`，未来计划见 `ROADMAP.md`。

---

## 与终端工作流集成

QuickPad 的纯 Markdown 存储天然适配 terminal-centric 环境：

```bash
# 直接编辑
vim ~/.quickpad/stream.md

# 按类型搜索
grep '\[task\]' ~/.quickpad/stream.md
grep '\[idea\]' ~/.quickpad/stream.md
grep 'read:' ~/.quickpad/stream.md

# shell alias 追加
qp() {
  local type="${1:-note}"; shift
  local ts=$(date +%Y-%m-%dT%H:%M%z)
  local today=$(date +"%Y-%m-%d %A")
  local file="$HOME/.quickpad/stream.md"
  local sep="--- $today ---"
  if ! head -1 "$file" 2>/dev/null | grep -qF "$sep"; then
    printf '%s\n\n' "$sep" | cat - "$file" > /tmp/qp_tmp && mv /tmp/qp_tmp "$file"
  fi
  sed -i '' "s|^$sep$|$sep\n- ${ts} [${type}] $*|" "$file"
}

# 用法
qp note "spconv 3.0 表现不错"
qp task "提交 PR"
qp idea "VLM 做 data quality spot check"
qp note "*priority demo 前修好 heading regression"

# 在 K8s pod 或 SSH 远程机器上也能用（通过 NFS 或同步）
ssh gpu-server 'echo "- $(date +%Y-%m-%dT%H:%M%z) [note] training loss 降到 0.42" >> ~/.quickpad/stream.md'
```
