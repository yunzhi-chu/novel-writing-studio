#!/bin/bash
# ============================================================
# workbench.sh —— Sodarie 创作中心（以 Sodarie Novel 为主体的总入口）
#
# Sodarie Novel 是主体界面（阅读/编辑 novel-project/chapters/ 的章节），
# 本脚本是它的后台控制台：推演 / 导演 / 写手 / 审查 / 看板全部为 Sodarie 服务。
# 进入时自动预检模型服务，顶部显示创作中心状态总览。
#
# 用法:
#   ./workbench.sh              交互式菜单
#   ./workbench.sh sodarie      打开 Sodarie Novel（主体界面）
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
SODARIE_APP="/Applications/Sodarie Novel.app"

C_R="\033[0;31m"; C_G="\033[0;32m"; C_Y="\033[0;33m"; C_0="\033[0m"

say() { echo ""; echo "────────────────────────────────────────────"; echo "▶ $1"; }

dot() { printf "  %s" "$1"; }

# ---------- 状态检测 ----------
svc() {  # $1=url → 返回 0/1
  curl -s -m 5 "$1" >/dev/null 2>&1
}

status_view() {
  echo ""
  echo "  ┌────────── Sodarie 创作中心 ──────────"
  if pgrep -f "Sodarie Novel.app/Contents/MacOS" >/dev/null 2>&1; then printf "  ${C_G}●${C_0} Sodarie Novel 运行中（主体界面）\n"; else printf "  ${C_R}○${C_0} Sodarie Novel 未运行（按 1 打开）\n"; fi
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
    printf "  已有 ${CN} 章（Sodarie 可见 chapters/）\n"
  fi
  echo "  └─────────────────────────────────────"
}

# ---------- 下一步建议（工作台状态机） ----------
next_steps() {
  echo ""
  echo "  ▶ 下一步建议："
  while IFS= read -r NEW_IDEAS; do break; done < <(ls -dt "$NP"/outputs/ideas/*/ 2>/dev/null | head -1)
  NEW_IDEAS="${NEW_IDEAS:-}" 
  if [ -n "${NEW_IDEAS}" ]; then
    N=$(ls "${NEW_IDEAS}"*.md 2>/dev/null | wc -l | tr -d ' ')
    DONE=0
    for f in "${NEW_IDEAS}"*.md; do
      [ -f "$f" ] || continue
      CH="$(basename "$f" .md | sed -E 's/-.*//')"
      ls "$NP"/chapters/${CH}-* >/dev/null 2>&1 && DONE=$((DONE + 1))
    done
    if [ "$DONE" -lt "$N" ]; then
      printf "  ● 有 %s 个分镜待成章（已写 %s/%s）→ ./workbench.sh flow --go --skip-simulate --chapters %s\n" "$N" "$DONE" "$N" "$N"
    else
      LATEST=$(ls -t "$NP"/outputs/drama/*.md 2>/dev/null | head -1)
      AGE=$(( $(date +%s) - $(stat -f "%m" "$LATEST") ))
      if [ "$AGE" -lt 86400 ]; then
        printf "  ○ 上一炉 %s 章已写完，全录仍新鲜 → 再联产一炉: ./workbench.sh flow --skip-simulate --chapters 3；或推演下一场: ./workbench.sh flow --go\n" "$N"
      else
        printf "  ○ 上一炉已写完，全录已旧 → ./workbench.sh flow（推演下一场）\n"
      fi
    fi
  else
    LATEST=$(ls -t "$NP"/outputs/drama/*.md 2>/dev/null | head -1)
    if [ -n "${LATEST}" ]; then
      AGE=$(( $(date +%s) - $(stat -f "%m" "$LATEST") ))
      if [ "$AGE" -lt 86400 ]; then
        printf "  ● 有新鲜故事全录 → ./workbench.sh flow --skip-simulate --chapters 3（联产 3 个分镜）\n"
      else
        printf "  ○ 全录较旧（>24h）→ ./workbench.sh flow（推演 4 轮 + 联产 3 分镜，约 45 分钟）\n"
      fi
    else
      printf "  ○ 尚无故事全录 → 先 ./workbench.sh flow（推演一次）\n"
    fi
  fi
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
run_sodarie()  { open "$SODARIE_APP" && echo "  已打开 Sodarie Novel（主体界面）"; }
run_doctor()   { run_script doctor.sh; }
run_new()      { run_script new_story.sh; }
run_flow()     { run_script novel_flow.sh; }
run_pipeline() { run_script novel_pipeline.sh; }
run_factory()  { run_script novel_factory.sh; }
run_sync()     { run_script sync_sodarie.sh; }
run_engine()   { run_script nest_drama_run.sh; }
run_board()    { open "$NP/charts/index.html" 2>/dev/null || echo "看板不存在，先跑一次写章/推演生成"; }
run_history()  { run_script history.sh; }
run_bg() {
  # 后台跑一条龙：nohup + 日志落 outputs/logs/，状态页可见
  mkdir -p "$NP/outputs/logs"
  TS="$(date +%Y%m%d-%H%M%S)"
  LOG="$NP/outputs/logs/flow-$TS.log"
  echo "  后台启动 novel_flow.sh（日志: outputs/logs/flow-$TS.log）"
  echo "  查看进度: ./workbench.sh history"
  ( { time "$NP/novel_flow.sh" "$@" > "$LOG" 2>&1; echo "EXIT=$?"; } & ) 2>/dev/null
}

# ---------- 菜单 ----------
menu() {
  echo ""
  echo "  ════════════════════════════════════════════"
  echo "   Sodarie 创作中心 · 以 Sodarie Novel 为主体"
  echo "  ════════════════════════════════════════════"
  echo "  ── 主体 ────────────────────────────────────"
  echo "   1. 打开 Sodarie Novel   （阅读/编辑章节，主体界面）"
  echo "  ── 为 Sodarie 生产 ────────────────────────"
  echo "   2. 推演+成章一条龙      novel_flow.sh     （生成下一章自动进 Sodarie）"
  echo "   3. 一键全流程          novel_pipeline.sh"
  echo "   4. 新建故事            new_story.sh       （接世界启动卡）"
  echo "   5. 同步章节到 Sodarie   sync_sodarie.sh    （重启 GUI 重扫章节）"
  echo "   6. 刷新创作看板        charts/index.html"
  echo "  ── 维护 ────────────────────────────────────"
  echo "   7. 体检                doctor.sh          （卡住/开工前先跑）"
  echo "   8. 推演引擎管理        nest_drama_run.sh"
  echo "   9. 短篇工厂            novel_factory.sh"
  echo "   0. 教学模式            tutor.sh           （新手从零入门）"
  echo "   h. 生产历史            history.sh         （章节/报告/分镜/任务）"
  echo "   b. 后台跑一条龙        日志落 outputs/logs/"
  echo "   r. 规则文档            WRITING_SYSTEM / WORLD_START_CARD"
  echo "   s. 状态                status"
  echo "   q. 退出"
  echo "  ────────────────────────────────────────────"
}

# ---------- 直跑分发 ----------
case "${1:-}" in
  sodarie)  run_sodarie; exit $? ;;
  tutor)    run_tutor; exit $? ;;
  doctor)   run_doctor; exit $? ;;
  new)      run_new; exit $? ;;
  flow)     precheck_omlx; run_flow; exit $? ;;
  pipeline) run_pipeline; exit $? ;;
  factory)  run_factory; exit $? ;;
  sync)     run_sync; exit $? ;;
  engine)   run_engine; exit $? ;;
  board)    run_board; exit $? ;;
  history|h) run_history; exit $? ;;
  next)     precheck_omlx; status_view; next_steps; exit 0 ;;
  daily)    precheck_omlx; status_view; next_steps; run_history; exit 0 ;;
  bg|b)     shift 2>/dev/null; run_bg "$@"; exit $? ;;
  status)   status_view; exit 0 ;;
  "")       ;;  # 进入交互菜单
  *)
    echo "未知命令: ${1}（可用: sodarie|doctor|new|flow|pipeline|factory|sync|engine|board|tutor|status）"
    exit 1 ;;
esac

# ---------- 交互菜单 ----------
say "欢迎回到写作工作台"
precheck_omlx
status_view
next_steps
while true; do
  menu
  printf "  请选择 > "
  read -r CHOICE
  case "$CHOICE" in
    1) run_sodarie ;;
    2) precheck_omlx; run_flow ;;
    3) run_pipeline ;;
    4) run_new ;;
    5) run_sync ;;
    6) run_board ;;
    7) run_doctor ;;
    8) run_engine ;;
    9) run_factory ;;
    0) run_tutor ;;
    h|H) run_history ;;
    b|B) run_bg ;;
    r|R) open "$NP/WRITING_SYSTEM.md" 2>/dev/null; open "$NP/WORLD_START_CARD.md" 2>/dev/null; echo "  已打开规则文档" ;;
    s|S) status_view; next_steps ;;
    q|Q) echo "  再见 👋"; exit 0 ;;
    *) echo "  无效选项：$CHOICE" ;;
  esac
done
