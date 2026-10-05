# PentoPic 1.0.1

**把屏幕冻结成画板，直接在画面上讲解。**

PentoPic 是一个 macOS 屏幕标注工具：按一下热键，当前屏幕就被冻结成画板，
你可以用画笔、箭头、矩形、文字、打码、聚焦……直接在画面上标注，
然后保存、复制或发送。

> 经 Pointofix 原作者许可发布 —— 详见下方「与 Pointofix 的关系」。

---

## 1.0.1 修了什么

`1.0.0` 发布后收到的问题报告。**其中几项只有在实机使用中才会暴露** ——
当时自动化自检是全绿的，所以这一版把它们都补上了防回归测试。

### 新增

- **光标旁的放大面板**：跟随鼠标显示放大后的画面、该像素的坐标与色值，
  贴边时自动翻到光标另一侧。默认开启，可在「设置 → 光标与缩放」里关掉。
- **`⌘C` 复制光标处的色值**，任何工具下都能用。
- **光标按上下文变化**：能抓的笔画/选区上显示张开的手，空白处是箭头，
  拖动中握紧，画框时是十字。

### 修复

- **选区拖不动** —— 指针工具在选区内拖动只会拉框，选区工具则只有顶部一小条能抓。
  现在整个选区都能拖动；想在选区内部框选笔画时按住 `⌥`。
- **`⌘C` 复制的是截图不是色值** —— 主菜单的「复制」抢走了这个快捷键。
  现在 `⌘C` 是色值，**复制整张截图改为 `⌘⇧C`**。
- **放大面板贴边时一片空白**、**移走后留下残影**、**显示的是上一版画面**、
  **关掉后不消失** —— 四个都在这一版修掉。

> 光学取色、拖拽移动这类操作，用起来才知道哪里别扭。发现问题欢迎提 issue。

---

## 几个它做得不错的地方

**🔒 打码是真的打码。** 用实心矩形"盖住"内容，底下的像素其实原封不动 ——
截图发出去就泄露了。PentoPic 的模糊和马赛克**真正读取底图做滤镜**，
抹掉的就是抹掉了。

**🧭 画布不一定是整块屏幕。** 可以只抓一个窗口、只裁一块区域、或者延时 5 秒
等你把下拉菜单展开再冻结。

**✍️ 标注是可以改的。** 画完发现箭头位置不对？切到指针拖动它。
多个对象可以对齐、等距分布、组合。**撤销覆盖全部操作** —— 包括删除和移动。

**🕘 有捕捉历史。** 截图存进文件夹后想找回上一张，不用去访达里翻 ——
历史窗口里双击就能**丢回标注会话继续编辑**。

**🌏 四语界面。** Deutsch · English · 简体中文 · 繁體中文
（繁体是独立维护的，不是机械转换 —— 设置→設定、剪贴板→剪貼簿、撤销→復原）。

**🔌 不联网。** 不收集任何数据，不发起任何网络请求。只读屏幕，全部本机处理。

---

## 安装

### 方式一：下载预编译版本（推荐给大多数用户）

下载下方的 `PentoPic-1.0.1-universal.zip`（Intel + Apple Silicon 通用），
解压后把 `PentoPic.app` 拖进「应用程序」。

**首次打开需要多做一步。** 本版本**未经 Apple 公证**（公证需要每年 $99 的
开发者账号，个人免费软件没有走这条路），所以 Gatekeeper 会拦截。执行一次即可：

```bash
xattr -dr com.apple.quarantine /Applications/PentoPic.app
```

然后**首次运行必须授权屏幕录制**：
系统设置 › 隐私与安全性 › 屏幕录制 → 勾选 PentoPic → 重新启动应用。

### 方式二：从源码构建（推荐给开发者，也绕开 Gatekeeper）

本地编译不经过 Gatekeeper，只需要 Command Line Tools：

```bash
git clone https://github.com/tncki/pentopic.git
cd pentopic
./build.sh
open build/PentoPic.app
```

---

## 系统要求

- macOS 14 (Sonoma) 或更高
- **屏幕录制权限**（macOS 系统限制，无法绕过）

---

## 快捷键

| 键 | 功能 | 键 | 功能 |
|---|---|---|---|
| `F9` | 开始 / 完成 | `⌘Z` | 撤销 |
| `B` | 画笔 | `⇧⌘Z` | 重做 |
| `E` | 橡皮 | `⌘C` | 复制 |
| `G` `P` `D` | 直线 / 箭头 / 双向箭头 | `⌘S` | 保存 |
| `R` `O` | 矩形 / 椭圆（`⇧` 实心） | `⌘P` | 打印 |
| `T` `H` `K` | 文字 / 对勾 / 叉号 | `⌘V` | 粘贴 |
| `N` | 序号标注 | `V` | 指针 |
| `U` `I` | 模糊 / 马赛克打码 | `F` | 选区 |
| `S` | 聚焦高亮 | `M` | 放大镜 |
| `L` | 屏幕标尺 | `C` | 颜色吸管 |
| `⇧`+拖动笔画 | 临时移动它 | `空格`（按住） | 临时借用指针 |

---

## 与 Pointofix 的关系

PentoPic 在功能设计上**受 [Pointofix](https://www.pointofix.de/) 1.8
（作者 Thomas Gottfried EDV）启发**，是**独立的重新实现** ——
纯 Swift 从零编写，**不包含原作的任何源代码、图标或美术资源**。

**本项目已获得原作者书面许可。** Thomas Gottfried EDV 于 2026-09-29 表示
不反对本项目在 GitHub 公开发布，并同意本项目所用的署名方式。原文与存档见
[`AUTHORIZATION.md`](AUTHORIZATION.md)。

需要说清楚的是：许可措辞是 *„keine Einwände"*（**不反对**），
**不是背书或官方合作**。PentoPic 不是 Pointofix 的官方 Mac 版本，
原作也不为本项目的质量或行为负责。

---

## English

**Freeze the screen and explain directly on it.**

PentoPic is a macOS screen-annotation tool: hit a hotkey, the screen freezes into
a canvas, and you draw on it with pens, arrows, shapes, text, redaction and
spotlight — then save, copy or send it.

**Highlights**

- **Redaction that actually redacts.** Covering something with an opaque
  rectangle leaves the pixels underneath intact. PentoPic's blur and mosaic read
  the real image through a filter, so what is gone is gone.
- **The canvas need not be the whole screen** — capture a single window, crop to
  a selection, or delay the capture so a menu can be open first.
- **Annotations stay editable** — move, align, distribute, group them.
  Undo covers every edit, deletions and moves included.
- **Capture history** — reopen a past capture straight back into an annotation
  session instead of hunting through Finder.
- **Four languages** — Deutsch, English, 简体中文, 繁體中文.
- **No network access.** No data collected, no requests made.

**Install** — download the universal build below, or build from source with
Command Line Tools only (`./build.sh`). Not notarised, so a downloaded copy needs:

```bash
xattr -dr com.apple.quarantine /Applications/PentoPic.app
```

Screen Recording permission is required on first run.

**Relation to Pointofix** — an independent reimplementation inspired by
Pointofix 1.8 by Thomas Gottfried EDV, written from scratch in Swift, containing
no source code or assets from the original. Published with the original author's
written permission ([`AUTHORIZATION.md`](AUTHORIZATION.md)); that permission is a
non-objection, not an endorsement.

---

**许可证** MIT · **隐私** 不收集数据、不联网 · **源码** [github.com/tncki/pentopic](https://github.com/tncki/pentopic)

*PentoPic 1.0.1 · © 2026 Zhao Bin*
