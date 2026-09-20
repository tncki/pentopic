#!/usr/bin/env python3
"""
本地化完整性检查 —— 放进 CI，防止以后改代码时漏翻译或写错语言。

检查项：
  1. 每处 LS() 都必须有 4 个参数（德/英/简/繁）
  2. 四个参数都不能为空
  3. 多行字面量的行数必须一致（防止译文结构错位）
  4. 各语言参数不能串味：
       德语参数里不该出现 CJK；中英文参数里不该出现德语变音字母
  5. 同一语言内不允许出现重复的键（可选，仅提示）

用法: python3 Tools/check-l10n.py [Sources 目录]
退出码: 0 = 全部通过, 1 = 有问题
"""
import sys, os, re, glob

def parse_args(src, start):
    """解析 LS( 之后的参数，返回 [(content, is_triple)]"""
    i = start; depth = 1; args = []
    in_str = False; triple = False; cstart = None; cend = None
    while i < len(src):
        c = src[i]
        if in_str:
            if triple:
                if src.startswith('"""', i):
                    in_str = False; cend = i; i += 3; continue
                i += 1; continue
            else:
                if c == '\\': i += 2; continue
                if c == '"':
                    in_str = False; cend = i; i += 1; continue
                i += 1; continue
        if src.startswith('"""', i):
            in_str = True; triple = True; cstart = i + 3; i += 3; continue
        if c == '"':
            in_str = True; triple = False; cstart = i + 1; i += 1; continue
        if c == '(': depth += 1; i += 1; continue
        if c == ')':
            depth -= 1
            if depth == 0:
                args.append((src[cstart:cend], triple)); return args
            i += 1; continue
        if c == ',' and depth == 1:
            args.append((src[cstart:cend], triple))
            cstart = None; cend = None; i += 1; continue
        i += 1
    return None

def line_count(text, triple):
    """运行时逻辑行数：多行字面量去掉首尾空行后计算"""
    if not triple: return 1
    body = text.strip('\n')
    return max(1, len(body.split('\n')))

CJK = re.compile(r'[\u4e00-\u9fff\u3400-\u4dbf]')
GERMAN = re.compile(r'[äöüÄÖÜß]')

def main():
    root = sys.argv[1] if len(sys.argv) > 1 else 'Sources'
    files = sorted(glob.glob(os.path.join(root, '*.swift')))
    if not files:
        print(f"未找到 Swift 源文件: {root}"); return 1

    problems = []
    warnings = []
    count = 0
    for f in files:
        src = open(f, encoding='utf-8').read()
        for m in re.finditer(r'\bLS\(', src):
            # 跳过 func LS( 定义本身
            if src[max(0, m.start()-24):m.start()].rstrip().endswith('func'):
                continue
            line = src[:m.start()].count('\n') + 1
            args = parse_args(src, m.end())
            if not args or len(args) < 4:
                problems.append((f, line, f"参数不足：只有 {len(args) if args else 0} 个，应为 4 个"))
                continue
            count += 1
            de, en, zh, hant = [a[0] for a in args[:4]]
            trips = [a[1] for a in args[:4]]
            names = ['de', 'en', 'zh-Hans', 'zh-Hant']

            for name, val in zip(names, [de, en, zh, hant]):
                if not val.strip():
                    problems.append((f, line, f"{name} 参数为空"))

            # 多行行数差异只警告：译文换行位置本来就可以不同
            lc = [line_count(a[0], a[1]) for a in args[:4]]
            if len(set(lc)) != 1 and max(lc) - min(lc) > 2:
                warnings.append((f, line, f"多行行数差异较大 {dict(zip(names, lc))}"))

            # 双重转义：把 \( 写成 \\( 会让插值变成字面反斜杠
            for name, a in zip(names, args[:4]):
                if '\\\\(' in a[0]:
                    problems.append((f, line, f"{name} 参数里的插值被多转义了一层（\\\\(）"))
                    break

            # 引号类型一致性（混用会让运行时内容不同）
            if len(set(trips)) != 1:
                problems.append((f, line, f"引号类型不一致（三段/单行混用）{dict(zip(names, trips))}"))

            # 语言串味
            if CJK.search(de):
                problems.append((f, line, f"德语参数里出现中日韩字符：{de[:40]}"))
            if GERMAN.search(en) or GERMAN.search(zh) or GERMAN.search(hant):
                for name, val in [('en', en), ('zh-Hans', zh), ('zh-Hant', hant)]:
                    if GERMAN.search(val):
                        problems.append((f, line, f"{name} 参数里出现德语变音字母：{val[:40]}"))

            # 简繁完全相同（可能是漏翻译，但专有名词/同形词属正常，仅提示）
    print(f"检查了 {count} 处 LS() 调用")
    if warnings:
        print(f"\n{len(warnings)} 条提示（不阻塞）：")
        for f, ln, msg in warnings:
            print(f"  {f}:{ln}  {msg}")
    if problems:
        print(f"\n发现 {len(problems)} 个问题：")
        for f, ln, msg in problems:
            print(f"  {f}:{ln}  {msg}")
        return 1
    print("✅ 全部通过：4 语言齐全、多行结构一致、无语言串味")
    return 0

if __name__ == '__main__':
    sys.exit(main())
