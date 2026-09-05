#!/bin/bash
# ============================================================
# doctor.sh —— 一键体检：当前工作台哪里不对劲？怎么修？
#
# 检查：配置 → 模型服务 → 模型是否可路由 → 推演引擎 → 项目结构
# 输出：绿 ✓（正常）/ 黄 ⚠（提醒）/ 红 ✗（需要处理 + 修复建议）
#
# 用法:
#   ./doctor.sh        # 全面体检
# ============================================================
set -uo pipefail

NP="$(cd "$(dirname "$0")" && pwd)"
G="\033[32m"; Y="\033[33m"; R="\033[31m"; N="\033[0m"
pass() { echo -e "  ${G}✓${N} $1"; }
warn() { echo -e "  ${Y}⚠${N} $1"; }
fail() { echo -e "  ${R}✗${N} $1"; }

echo "============================================================"
echo " 🔍 工作台体检（$(date '+%Y-%m-%d %H:%M')）"
echo "============================================================"

# ---------- 1. 配置 ----------
echo ""; echo "[1/6] 配置 ~/.novel/env"
if [ -f "$HOME/.novel/env" ]; then
  pass "配置文件存在"
  grep -q "LLM_MODEL=" "$HOME/.novel/env" && pass "已配置写作模型" || warn "未设置 LLM_MODEL"
  grep -q "NEST_LLM_MODEL=" "$HOME/.novel/env" && pass "已配置推演模型" || warn "未设置 NEST_LLM_MODEL"
else
  fail "缺少 ~/.novel/env（运行 install.sh 生成）"
fi

# ---------- 2. 模型服务 ----------
echo ""; echo "[2/6] 模型服务（:8000）"
if curl -s -m 5 "http://127.0.0.1:8000" >/dev/null 2>&1; then
  pass "模型服务在线（:8000）"
else
  fail "模型服务未响应（:8000）。请启动："
  echo "       macOS 芯片：打开 oMLX 应用，或 omlx start"
  echo "       其他系统：  ollama serve（或确认 Ollama 在运行）"
fi

# ---------- 3. 模型可路由 ----------
echo ""; echo "[3/6] 模型可路由"
# 读配置拿 key（模型列表接口可能要求鉴权）
if [ -f "$HOME/.novel/env" ]; then
  . "$HOME/.novel/env"
fi
DK="${NEST_LLM_API_KEY:-${LLM_API_KEY:-sk-omlx-local}}"
MODELS_JSON=$(curl -s -m 8 -H "Authorization: Bearer $DK" "http://127.0.0.1:8000/v1/models" 2>/dev/null)
if [ -n "$MODELS_JSON" ]; then
  WRITE="${LLM_MODEL:-}"
  NEST="${NEST_LLM_MODEL:-}"
  [ -z "$WRITE" ] && WRITE="Qwen3.6-35B-A3B-MLX-8bit"
  [ -z "$NEST" ] && NEST="Ornith-1.5-35B-A3B-MLX-8bit"
  echo "$MODELS_JSON" | grep -q "$WRITE" && pass "写作模型可路由（${WRITE}）" || fail "写作模型未就绪：${WRITE}（请先下载该模型）"
  echo "$MODELS_JSON" | grep -q "$NEST" && pass "推演模型可路由（${NEST}）" || warn "推演模型未就绪：${NEST}（推演功能不可用，写作不受影响）"
else
  fail "模型列表接口无响应"
fi

# ---------- 4. 推演引擎 ----------
echo ""; echo "[4/6] nest-drama 推演引擎（:8790）"
if curl -s -m 5 "http://127.0.0.1:8790/health" >/dev/null 2>&1; then
  pass "引擎在线（:8790）"
else
  warn "引擎未启动（推演功能暂不可用，写作不受影响）。需要时执行："
  echo "       ./nest_drama_run.sh status   # 会自动拉起引擎"
fi

# ---------- 5. 项目结构 ----------
echo ""; echo "[5/6] 项目结构"
[ -f "$NP/AGENTS.md" ] && pass "AGENTS.md 存在" || warn "缺少 AGENTS.md（导演说明书）"
[ -f "$NP/write_chapter.sh" ] && pass "write_chapter.sh 存在" || fail "缺少 write_chapter.sh"
[ -f "$NP/memory/story_bible.yaml" ] && pass "故事圣经存在" || warn "story_bible.yaml 未初始化（跑 ./new_story.sh）"
[ -f "$NP/outlines/book_outline.yaml" ] && pass "大纲存在" || warn "book_outline.yaml 未初始化（跑 ./new_story.sh）"
if [ -x "$NP/scripts/.venv/bin/python" ]; then
  "$NP/scripts/.venv/bin/python" -c "import yaml" 2>/dev/null && pass "Python 环境 + pyyaml 就绪" || fail "pyyaml 未安装（$NP/scripts/.venv/bin/pip install pyyaml）"
else
  fail "缺少 Python 虚拟环境（$NP/scripts/.venv，重跑 install.sh 或手动 python3 -m venv）"
fi

# ---------- 6. 总结 ----------
echo ""; echo "[6/6] 体检结论"
FALLBACK=""
if curl -s -m 3 "http://127.0.0.1:8000/v1/models" 2>/dev/null | grep -q .; then
  # 无红项即绿
  if [ -f "$HOME/.novel/env" ] && [ -f "$NP/write_chapter.sh" ]; then
    pass "基础可写作：模型服务在线 + 项目就绪，可以 ./write_chapter.sh 写第一章了"
  else
    warn "还需修复以上红/黄项"
  fi
else
  warn "模型服务离线，先修复[2/6]"
fi

echo ""
echo "============================================================"
echo " 修复提示：大部分问题重跑 install.sh 即可自动解决"
echo " 或按上方红/黄项旁的说明手动处理；解决不了截图给 AI 助手"
echo "============================================================"
