#!/usr/bin/env bash
# 校验 preview/ 里的图是不是按**当前源码**渲染的。
#
# 真实事故：改了应用署名、重新构建了应用，却忘了重新渲染预览图 ——
# 仓库里的图片于是长期显示旧署名，直到被人看出来。
# 渲染产物是构建输出：源码变了，它就该跟着变。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$ROOT/preview/.source-hash"
# 只统计**参与预览构建**的源文件 —— 必须与 preview-build.sh 用同一套规则，
# 否则两边算出的指纹永远对不上。
#
# 注意：别把 case 写进 $( … ) 里 —— `;;` 在命令替换中会让 bash 解析失败。
SRCS=$(ls "$ROOT"/Sources/*.swift | grep -v -E '/(SelfTest|main)\.swift$')
CUR=$(cat "$ROOT/app.conf" $SRCS | shasum -a 256 | awk '{print $1}')

if [ ! -f "$STAMP" ]; then
    echo "❌ preview/.source-hash 不存在 —— 先运行 ./preview-build.sh" >&2
    exit 1
fi
if [ "$(cat "$STAMP")" != "$CUR" ]; then
    echo "❌ preview/ 里的图不是按当前源码渲染的" >&2
    echo "   记录: $(cat "$STAMP")" >&2
    echo "   当前: $CUR" >&2
    echo "   修复: ./preview-build.sh  然后提交 preview/" >&2
    exit 1
fi
echo "✅ 预览图与当前源码一致"
