#!/usr/bin/env bash
# 推送辅助：端口 22 不通时自动改走 GitHub 的 443 端口。
#
# 背景：不少网络（公司/学校/部分运营商）会屏蔽出站 22 端口，表现为
#   Connection closed by <ip> port 22
#   fatal: Could not read from remote repository.
# 看起来像"没权限"，其实是连不上。GitHub 另外提供 ssh.github.com:443。
#
# 用法：./Tools/push.sh [分支名]      默认 main

set -euo pipefail

BRANCH="${1:-main}"
KH="${HOME}/workspace/.ssh_known_hosts"

# 开发沙箱不允许写 ~/.ssh/known_hosts，所以把 known_hosts 放在工作区
SSH_BASE="ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"
[ -f "$KH" ] && SSH_BASE="$SSH_BASE -o UserKnownHostsFile=$KH"

echo "==> 尝试端口 22"
if GIT_SSH_COMMAND="$SSH_BASE" git push origin "$BRANCH" 2>/dev/null; then
    echo "==> 完成（端口 22）"
    exit 0
fi

echo "==> 端口 22 不通，改走 ssh.github.com:443"
GIT_SSH_COMMAND="$SSH_BASE -o Hostname=ssh.github.com -p 443" git push origin "$BRANCH"
echo "==> 完成（端口 443）"
