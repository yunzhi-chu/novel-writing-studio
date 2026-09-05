#!/bin/bash
# ============================================================
# workbench.sh —— AI 小说写作工作台（总入口菜单）
#
# 一个入口管全部：体检 / 建故事 / 写章 / 推演 / 短篇 / 同步 / 看板
# 进入时自动预检模型服务，顶部显示工作台状态总览。
#
# 用法:
#   ./workbench.sh              交互式菜单
#   ./workbench.sh doctor       直跑体检
#   ./workbench.sh new          直跑新建故事
#   ./workbench.sh flow         直跑推演+成章一条龙
#   ./workbench.sh pipeline     直跑一键全流程
#   ./workbench.sh factory      直跑短篇工厂
#   ./workbench.sh sync         直跑同步 Sodarie
#   ./workbench.sh engine       直跑推演引擎管理
#   ./workbench.sh board        打开创作看板
#   ./workbench.sh status       只看状态总览
# ============================================================
set -uo pipefail

NP="$(cd "$(dirname "$0")" && pwd)"
OAPI="http://127.0.0.1:8000"
ENGINE="http://127.0.0.1:8790/"

C_R="\033[0;31m"; C_G="\033[0;32m"; C_Y="\033[0;33m"; C_0="\033[0m"

say() { echo ""; echo "────────────────────────────────────────────"; echo "▶ $1"; }

dot() { printf "  %s" "$1"; }

# ---------- 状态检测 ----------
svc() {  # $1=url → 返回 0/1
  curl -s -m 5 "$1" >/dev/null 2>&1
}

status_view() {
  echo ""
  echo "  ┌────────── 工作台状态 ──────────"
  if svc "$OAPI/health"; then printf "  ${C_G}●${C_0} 模型服务在线（:8000）\n"; else printf "  ${C_R}○${C_0} 模型服务离线（:8000）\n"; fi
  if svc "$ENGINE"; then printf "  ${C_G}●${C_0} 推演引擎在线（:8790）\n"; else printf "  ${C_R}○${C_0} 推演引擎离线（:8790）\n"; fi
  if [ -f "$HOME/.novel/env" ]; then printf "  ${C_G}●${C_0} 配置 ~/.novel/env 就绪\n"; else printf "  ${C_Y}○${C_0} 缺 ~/.novel/env（脚本用默认值）\n"; fi
  if [ -d "$NP/.git" ]; then
    BR=$(git -C "$NP" branch --show-current 2>/dev/null || echo "?")
    DIRTY=$(git -C "$NP" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [ "$DIRTY" -gt 0 ]; then printf "  ${C_Y}●${C_0} git ${BR}（${DIRTY} 个未提交改动）\n"; else printf "  ${C_G}●${C_0} git ${BR}（干净）\n"; fi
  fi
  if [ -d "$NP/chapters" ]; then
    CN=$(ls "$NP/chapters" 2>/dev/null | wc -l | tr -d ' ')
    printf "  已有 ${CN} 章（chapters/）\n"
  fi
  echo "  └────────────────────────────────"
}

precheck_omlx() {
  if ! svc "$OAPI/health"; then
    echo "  oMLX 未就绪，尝试自动启动（omlx start）…"
    command -v omlx >/dev/null 2>&1 && omlx start --timeout 120 >/dev/null 2>&1 || true
    sleep 3
  fi
  if svc "$OAPI/health"; then
    echo "  ✓ 模型服务在线"
  else
    echo "  ✗ 模型服务无法启动（手动打开 oMLX 应用后重试）"
  fi
}

# ---------- 操作 ----------
# run_script 统一做存在性检查：脚本缺失时友好提示（如 novel_factory 不在发行包）
run_script() {  # $1=脚本名，其余参数透传
  local name="$1"; shift
  if [ -f "$NP/$name" ]; then
    "$NP/$name" "$@"
  else
    echo "  未找到 ${name}（当前安装不含此脚本）"
  fi
}
run_tutor()    { run_script tutor.sh; }
run_doctor()   { run_script doctor.sh; }
run_new()      { run_script new_story.sh; }
run_flow()     { run_script novel_flow.sh; }
run_pipeline() { run_script novel_pipeline.sh; }
run_factory()  { run_script novel_factory.sh; }
run_sync()     { run_script sync_sodarie.sh; }
run_engine()   { run_script nest_drama_run.sh; }
run_board()    { open "$NP/charts/index.html" 2>/dev/null || echo "看板不存在，先跑一次写章/推演生成"; }

# ---------- 菜单 ----------
menu() {
  echo ""
  echo "  ════════════════════════════════════════════"
  echo "   AI 小说写作工作台 · 总入口"
  echo "  ════════════════════════════════════════════"
  echo "   0. 教学模式      tutor.sh         （新手从零入门）"
  echo "   1. 体检          doctor.sh        （卡住/开工前先跑）"
  echo "   2. 新建故事      new_story.sh     （接世界启动卡）"
  echo "   3. 推演+成章     novel_flow.sh    （一条龙，日常写章）"
  echo "   4. 一键全流程    novel_pipeline.sh"
  echo "   5. 短篇工厂      novel_factory.sh （一句话写短篇）"
  echo "   6. 同步 Sodarie  sync_sodarie.sh"
  echo "   7. 推演引擎管理  nest_drama_run.sh"
  echo "   8. 打开创作看板  charts/index.html"
  echo "   r. 规则文档      WRITING_SYSTEM / WORLD_START_CARD"
  echo "   s. 状态          status"
  echo "   q. 退出"
  echo "  ────────────────────────────────────────────"
}

# ---------- 直跑分发 ----------
case "${1:-}" in
  tutor)    run_tutor; exit $? ;;
  doctor)   run_doctor; exit $? ;;
  new)      run_new; exit $? ;;
  flow)     precheck_omlx; run_flow; exit $? ;;
  pipeline) run_pipeline; exit $? ;;
  factory)  run_factory; exit $? ;;
  sync)     run_sync; exit $? ;;
  engine)   run_engine; exit $? ;;
  board)    run_board; exit $? ;;
  status)   status_view; exit 0 ;;
  "")       ;;  # 进入交互菜单
  *)
    echo "未知命令: ${1}（可用: doctor|new|flow|pipeline|factory|sync|engine|board|status）"
    exit 1 ;;
esac

# ---------- 交互菜单 ----------
say "欢迎回到写作工作台"
precheck_omlx
status_view
while true; do
  menu
  printf "  请选择 > "
  read -r CHOICE
  case "$CHOICE" in
    0) run_tutor ;;
    1) run_doctor ;;
    2) run_new ;;
    3) precheck_omlx; run_flow ;;
    4) run_pipeline ;;
    5) run_factory ;;
    6) run_sync ;;
    7) run_engine ;;
    8) run_board ;;
    r|R) open "$NP/WRITING_SYSTEM.md" 2>/dev/null; open "$NP/WORLD_START_CARD.md" 2>/dev/null; echo "  已打开规则文档" ;;
    s|S) status_view ;;
    q|Q) echo "  再见 👋"; exit 0 ;;
    *) echo "  无效选项：$CHOICE" ;;
  esac
done
