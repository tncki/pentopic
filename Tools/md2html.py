#!/usr/bin/env python3
"""把 HELP.md 转成可离线阅读的单文件 HTML，打包进 .app。

为什么不用现成的转换器：本项目**零第三方依赖**，构建只需要 Command Line Tools。
这个转换器只覆盖 HELP.md 实际用到的语法，够用且可测。

用法：
    python3 Tools/md2html.py HELP.md > Help.html
    python3 Tools/md2html.py --selftest        # 跑内置用例
"""

import html
import re
import sys


# ---------------------------------------------------------------- 行内语法

def inline(text: str) -> str:
    """处理行内标记。先转义，再替换 —— 顺序反了会把生成的标签也转义掉。"""
    out = html.escape(text, quote=False)
    # 行内代码先处理，避免里面的 * 或 _ 被当成强调
    codes: list[str] = []

    def stash(m):
        codes.append(m.group(1))
        return f"\x00{len(codes) - 1}\x00"

    out = re.sub(r"`([^`]+)`", stash, out)
    # 粗体在斜体之前，否则 ** 会被 * 抢先匹配
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<em>\1</em>", out)
    out = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', out)
    out = re.sub(r"\x00(\d+)\x00", lambda m: f"<code>{codes[int(m.group(1))]}</code>", out)
    return out


def slug(text: str) -> str:
    """标题 → 锚点 id。中文直接保留（浏览器能处理），只去掉标点。"""
    s = re.sub(r"<[^>]+>", "", text)
    s = re.sub(r"[^\w\u4e00-\u9fff\- ]+", "", s)
    return s.strip().lower().replace(" ", "-")


# ---------------------------------------------------------------- 块级语法

def convert(md: str) -> str:
    lines = md.split("\n")
    out: list[str] = []
    i = 0
    n = len(lines)
    toc_done = False

    def close_list(tag: str):
        out.append(f"</{tag}>")

    list_tag: str | None = None

    def end_list():
        nonlocal list_tag
        if list_tag:
            close_list(list_tag)
            list_tag = None

    while i < n:
        line = lines[i]

        # --- 代码块
        if line.strip().startswith("```"):
            end_list()
            i += 1
            buf = []
            while i < n and not lines[i].strip().startswith("```"):
                buf.append(html.escape(lines[i]))
                i += 1
            i += 1
            out.append("<pre><code>" + "\n".join(buf) + "</code></pre>")
            continue

        # --- 分隔线（必须早于表格和列表判断）
        if re.match(r"^\s*---+\s*$", line):
            end_list()
            out.append("<hr>")
            i += 1
            continue

        # --- 表格
        if "|" in line and i + 1 < n and re.match(r"^\s*\|?[\s:|-]+\|[\s:|-]*$", lines[i + 1]):
            end_list()
            header = [c.strip() for c in line.strip().strip("|").split("|")]
            rows = []
            i += 2
            while i < n and "|" in lines[i] and lines[i].strip():
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
                i += 1
            out.append("<table><thead><tr>")
            out.extend(f"<th>{inline(c)}</th>" for c in header)
            out.append("</tr></thead><tbody>")
            for r in rows:
                out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>")
            out.append("</tbody></table>")
            continue

        # --- 标题
        m = re.match(r"^(#{1,6})\s+(.*)$", line)
        if m:
            end_list()
            level = len(m.group(1))
            body = inline(m.group(2))
            out.append(f'<h{level} id="{slug(m.group(2))}">{body}</h{level}>')
            i += 1
            continue

        # --- 引用块
        if line.lstrip().startswith(">"):
            end_list()
            buf = []
            while i < n and (lines[i].lstrip().startswith(">") or
                             (buf and lines[i].strip() and not lines[i].startswith("#"))):
                if lines[i].lstrip().startswith(">"):
                    buf.append(lines[i].lstrip()[1:].strip())
                else:
                    buf.append(lines[i].strip())
                i += 1
            out.append("<blockquote>" + "<br>".join(inline(b) for b in buf if b) + "</blockquote>")
            continue

        # --- 列表
        m = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)$", line)
        if m:
            want = "ul" if m.group(2) in ("-", "*") else "ol"
            if list_tag != want:
                end_list()
                out.append(f"<{want}>")
                list_tag = want
            out.append(f"<li>{inline(m.group(3))}</li>")
            i += 1
            continue

        # --- 空行
        if not line.strip():
            end_list()
            i += 1
            continue

        # --- 段落
        end_list()
        out.append(f"<p>{inline(line.strip())}</p>")
        i += 1

    end_list()
    return "\n".join(out)


# ---------------------------------------------------------------- 页面外壳

CSS = """
:root { color-scheme: light dark; }
body { font: 15px/1.7 -apple-system, "PingFang SC", "Helvetica Neue", sans-serif;
       max-width: 780px; margin: 0 auto; padding: 40px 24px 80px; }
h1 { font-size: 28px; border-bottom: 2px solid #8884; padding-bottom: 10px; }
h2 { font-size: 21px; margin-top: 38px; border-bottom: 1px solid #8883; padding-bottom: 6px; }
h3 { font-size: 17px; margin-top: 26px; }
h4 { font-size: 15px; margin-top: 20px; }
code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .9em;
       background: #8881; padding: 2px 5px; border-radius: 4px; }
pre { background: #8881; padding: 12px 14px; border-radius: 8px; overflow-x: auto; }
pre code { background: none; padding: 0; }
blockquote { margin: 14px 0; padding: 10px 16px; border-left: 4px solid #0a7;
             background: #0a71; border-radius: 0 6px 6px 0; }
blockquote p { margin: 0; }
table { border-collapse: collapse; width: 100%; margin: 14px 0; }
th, td { border: 1px solid #8884; padding: 7px 10px; text-align: left; }
th { background: #8881; }
hr { border: none; border-top: 1px solid #8884; margin: 34px 0; }
a { color: #0a7; }
li { margin: 4px 0; }
"""

TEMPLATE = """<!DOCTYPE html>
<html lang="zh-Hans">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PentoPic 使用手册</title>
<style>{css}</style>
</head>
<body>
{body}
</body>
</html>
"""


def render(md: str) -> str:
    return TEMPLATE.format(css=CSS, body=convert(md))


# ---------------------------------------------------------------- 自检

def selftest() -> int:
    failures = []

    def eq(name, got, want):
        if got != want:
            failures.append(f"{name}\n    实际: {got!r}\n    期望: {want!r}")

    eq("一级标题", convert("# 标题"), '<h1 id="标题">标题</h1>')
    eq("粗体", convert("**粗**"), "<p><strong>粗</strong></p>")
    eq("斜体", convert("*斜*"), "<p><em>斜</em></p>")
    eq("粗体不被斜体抢先", convert("**a**"), "<p><strong>a</strong></p>")
    eq("行内代码", convert("`x`"), "<p><code>x</code></p>")
    eq("代码里的星号不被当强调", convert("`a*b*c`"), "<p><code>a*b*c</code></p>")
    eq("链接", convert("[t](u)"), '<p><a href="u">t</a></p>')
    eq("HTML 被转义", convert("<script>"), "<p>&lt;script&gt;</p>")
    eq("代码块内的标记不解析", convert("```\n**x**\n```"), "<pre><code>**x**</code></pre>")
    eq("无序列表", convert("- a\n- b"), "<ul>\n<li>a</li>\n<li>b</li>\n</ul>")
    eq("有序列表", convert("1. a"), "<ol>\n<li>a</li>\n</ol>")
    eq("列表切换会闭合", convert("- a\n1. b"), "<ul>\n<li>a</li>\n</ul>\n<ol>\n<li>b</li>\n</ol>")
    eq("分隔线", convert("---"), "<hr>")
    eq("引用", convert("> hi"), "<blockquote>hi</blockquote>")
    eq("段落", convert("hi"), "<p>hi</p>")
    eq("表格", convert("| a | b |\n|---|---|\n| 1 | 2 |"),
       "<table><thead><tr>\n<th>a</th>\n<th>b</th>\n</tr></thead><tbody>\n"
       "<tr><td>1</td><td>2</td></tr>\n</tbody></table>")
    # 中文标题的锚点
    eq("中文锚点", convert("## 安装与首次运行")[0:20].startswith('<h2 id="安装与首次运行"'),
       True)

    if failures:
        print(f"❌ {len(failures)} 项失败：", file=sys.stderr)
        for f in failures:
            print("  - " + f, file=sys.stderr)
        return 1
    print("✅ 转换器自检全部通过")
    return 0


def main() -> int:
    if "--selftest" in sys.argv:
        return selftest()
    src = sys.argv[1] if len(sys.argv) > 1 else "HELP.md"
    with open(src, encoding="utf-8") as f:
        sys.stdout.write(render(f.read()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
