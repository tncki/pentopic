# 署名与权利声明 / Notice and Attribution

## 本项目与原作的关系

**PentoPic** 是一个**独立的 macOS 屏幕标注应用**，在功能设计上**受
[Pointofix](https://www.pointofix.de/) 1.8（作者 Thomas Gottfried EDV）启发**。

**本项目与原作没有代码或资源上的关联**，具体来说：

- ✅ **已获得原作者的书面不反对**（2026-09-29）——许可其公开发布，并同意本项目的署名方式。
  原件与原文见 [AUTHORIZATION.md](AUTHORIZATION.md)
- ❌ 仍**不是** Pointofix 的官方版本、移植版或衍生版
- ❌ 原作**未对本项目的质量或行为背书**（许可措辞是 „keine Einwände" —— 不反对，不是合作）
- ❌ **不包含原作的任何源代码**（原作是 Windows/Delphi 程序，本项目是纯 Swift 从零编写）
- ❌ **不包含原作的任何图像、图标或美术资源**（工具图标使用 Apple SF Symbols，
  对勾/叉号/应用图标均为本项目矢量自绘）
- ❌ 不使用原作的产品名、商标或域名

## 为什么这样做是合法的

著作权保护的是**表达**（具体的代码、图像、文案），不保护**功能与思想**
（idea–expression dichotomy）。屏幕冻结、画笔、箭头、放大镜、区域导出等功能，
以及"竖排双列工具栏"这类功能性布局，属于不受著作权保护的范畴。
本项目依据公开的功能说明独立实现，属于合法的功能兼容实现。

## 发布检查清单（本项目已完成）

- [x] 产品名不使用 `Pointofix` —— 本产品名为 **PentoPic**
- [x] Bundle ID 不使用 `de.pointofix.mac` —— 本项目为 `io.github.tncki.pentopic`
- [x] 应用图标为自绘（蓝色圆角方块 + 白板 + 黄色马克笔迹 + 红色箭头 + 绿色对勾）
- [x] 工具图标来自 Apple SF Symbols 或矢量自绘，未使用原作图标
- [x] `ref/` 目录（从 pointofix.de 下载的原始截图）已排除在 `.gitignore` 之外
- [x] 保留本文件与 README 中的署名段落
- [x] `app.conf` 中的仓库地址为真实地址（`github.com/tncki/pentopic`）
- [x] 合成示例画面中不含真实邮箱等个人信息
- [x] 已获得原作者书面不反对，并存档于 [`AUTHORIZATION.md`](AUTHORIZATION.md)

## 如果你是原作作者并希望调整

虽然我们已获得发布许可，但若您对任何署名措辞、功能呈现或产品命名有新的意见，
请通过仓库 Issue 联系，我们会立即配合调整或下架。

---

## Notice (English)

This is an **independent** macOS screen-annotation app **inspired by**
[Pointofix](https://www.pointofix.de/) 1.8 by Thomas Gottfried EDV.

The original author has given **written permission to publish** (2026-09-29);
see [AUTHORIZATION.md](AUTHORIZATION.md). Their wording is *„keine Einwände"* —
**no objection** — which is not an endorsement.

It is **not affiliated with, endorsed by, or derived from** that project.
It contains **no source code, images, icons, or other assets** from the original,
and does not use the original's name, trademark, or domain.

Copyright protects expression, not functionality. This project is a lawful
independent implementation of publicly documented functionality.
