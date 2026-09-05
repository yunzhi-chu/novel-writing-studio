#!/bin/bash
# ============================================================
# sync_sodarie.sh —— 把章节同步进 Sodarie Novel GUI
#
# 背景：Sodarie Novel 的章节列表在启动时扫描 chapters/ 目录，
#       之后只会在 GUI 内生成/重置章节时刷新。外部（Codex →
#       write_chapter.sh）生成的章节不会自动出现。
#       本脚本通过优雅重启 GUI 触发重扫，让新章节立即可见。
#
# 用法:
#   ./sync_sodarie.sh          # 重启 GUI，同步所有章节
#   ./sync_sodarie.sh --skip   # 仅检查 GUI 状态，不重启
# ============================================================
set -u

APP_NAME="Sodarie Novel"
APP_PATH="/Applications/Sodarie Novel.app"

# 判断 GUI 是否在运行
is_running() {
    pgrep -f "Sodarie Novel.app/Contents/MacOS" >/dev/null 2>&1
}

# 仅检查模式
if [ "${1:-}" = "--skip" ]; then
    if is_running; then
        echo "[Sodarie] GUI 正在运行（章节需重启 GUI 后可见）"
    else
        echo "[Sodarie] GUI 未运行"
    fi
    exit 0
fi

if ! is_running; then
    # 未运行：直接启动
    open "$APP_PATH"
    echo "[Sodarie] GUI 未运行，已启动；将扫描 chapters/ 目录"
    exit 0
fi

# 运行中：优雅退出 → 等待退出 → 重新打开（带重试）
echo "[Sodarie] 正在重启 GUI 以重扫 chapters/ 目录..."
osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true

for _ in $(seq 1 30); do
    if ! is_running; then
        break
    fi
    sleep 0.5
done

if is_running; then
    # 优雅退出失败，强制结束
    pkill -f "Sodarie Novel.app/Contents/MacOS" 2>/dev/null || true
    sleep 1
fi

# 等待 LaunchServices 处理完 app 退出/注册，避免 open 报 -600
sleep 2

# 重新打开（open 偶发失败，最多重试 5 次）
opened=0
for attempt in 1 2 3 4 5; do
    open "$APP_PATH" 2>/dev/null
    sleep 3
    if is_running; then
        opened=1
        break
    fi
    sleep 2
done

if [ "${opened}" = "1" ]; then
    echo "[Sodarie] 已重启完成，GUI 将显示 chapters/ 下全部章节"
else
    echo "[Sodarie] 自动重启失败，请手动打开 Sodarie Novel.app"
    exit 1
fi
