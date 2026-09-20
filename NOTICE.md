# 署名与权利声明 / Notice and Attribution

## 本项目与原作的关系

**PentoPic** 是一个**独立的 macOS 屏幕标注应用**，在功能设计上**受
[Pointofix](https://www.pointofix.de/) 1.8（作者 Thomas Gottfried EDV）启发**。

**本项目与原作没有任何关系**，具体来说：

- ❌ 不是 Pointofix 的官方版本、移植版、衍生版或授权版本
- ❌ 未获得原作者的授权、认可或背书
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
- [ ] 发布前把 `app.conf` 里的 GitHub 用户名占位值换成真实用户名

## 如果你是原作作者并对此有异议

请通过仓库 Issue 联系，我们会立即配合调整或下架。

---

## Notice (English)

This is an **independent** macOS screen-annotation app **inspired by**
[Pointofix](https://www.pointofix.de/) 1.8 by Thomas Gottfried EDV.

It is **not affiliated with, endorsed by, or derived from** that project.
It contains **no source code, images, icons, or other assets** from the original,
and does not use the original's name, trademark, or domain.

Copyright protects expression, not functionality. This project is a lawful
independent implementation of publicly documented functionality.
