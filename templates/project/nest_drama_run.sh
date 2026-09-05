#!/bin/bash
# ============================================================
# nest_drama_run.sh —— NEST-DRAMA 群像推演（写作流桥接入口）
#
# 把 NEST-DRAMA（单元剧情引擎）接入当前写作流：
#   记忆库 → 建世界 → 角色自主推演 → 导出「故事全录」到 outputs/drama/
# 推演结果供 Codex 提炼分镜式 idea，再交 write_chapter.sh 成章。
#
# 模型：oMLX 启动的 Qwen3.8-27B-Uncensored-MLX（:8000，与 Sodarie 写作流
#       的 Qwen3.6-35B 同实例共存，按 model 名路由，互不干扰）
#
# 用法：
#   ./nest_drama_run.sh status                    # 查看引擎状态
#   ./nest_drama_run.sh sync                      # 只同步记忆库 → 材料
#   ./nest_drama_run.sh build "推演需求"           # 只建世界
#   ./nest_drama_run.sh simulate [N]              # 只推演 N 轮（默认 6）
#   ./nest_drama_run.sh export                    # 只导出故事全录
#   ./nest_drama_run.sh [N] ["推演需求"]           # 全流程（默认 6 轮）
# ============================================================
set -uo pipefail

NP="$(cd "$(dirname "$0")" && pwd)"
NEST_DIR="${NEST_DIR:-$HOME/nest-drama}"
NEST_PORT="8790"
LOG_FILE="/tmp/nest-drama.log"

# 读取统一配置（install.sh 生成的 ~/.novel/env；可按需修改）
[ -f "$HOME/.novel/env" ] && . "$HOME/.novel/env"

# 本地模型接入（oMLX 启动 Ornith-1.5-35B-A3B-MLX-8bit：Qwen3.5-MoE 架构，
# 35B 总量/3B 激活，约 65 tok/s，远快于 27B 稠密模型；oMLX 原生遵守
# chat_template_kwargs.enable_thinking=false，建世界摄取自动关思考）
export NEST_LLM_BASE_URL="${NEST_LLM_BASE_URL:-http://127.0.0.1:8000/v1}"
export NEST_LLM_MODEL="${NEST_LLM_MODEL:-Ornith-1.5-35B-A3B-MLX-8bit}"
export NEST_LLM_API_KEY="${NEST_LLM_API_KEY:-${LLM_API_KEY:-sk-omlx-local}}"
# 单次模型调用超时：MoE 模型较快（建世界整体约 5-15 分钟），默认 300s 足够；
# 若换回稠密 27B 模型，请调回 900s。
export NEST_BUILD_CALL_TIMEOUT="${NEST_BUILD_CALL_TIMEOUT:-300}"

PY="${NP}/scripts/.venv/bin/python"
BRIDGE="${NP}/scripts/nest_drama_bridge.py"

# ---------- 确保 nest-drama 引擎在跑 ----------
ensure_engine() {
  if curl -s -m 3 "http://127.0.0.1:${NEST_PORT}/api/health" >/dev/null 2>&1; then
    echo "[推演] NEST-DRAMA 引擎已在运行（:${NEST_PORT}）"
    return 0
  fi
  echo "[推演] 启动 NEST-DRAMA 引擎（:${NEST_PORT}，模型 ${NEST_LLM_MODEL}）…"
  ( cd "${NEST_DIR}" && \
    LLM_BASE_URL="${NEST_LLM_BASE_URL}" \
    LLM_MODEL_NAME="${NEST_LLM_MODEL}" \
    LLM_API_KEY="${NEST_LLM_API_KEY}" \
    nohup python3 ui/serve.py "${NEST_PORT}" > "${LOG_FILE}" 2>&1 & )
  for i in $(seq 1 30); do
    sleep 1
    if curl -s -m 3 "http://127.0.0.1:${NEST_PORT}/api/health" >/dev/null 2>&1; then
      echo "[推演] 引擎就绪（:${NEST_PORT}）"
      return 0
    fi
  done
  echo "[推演] 引擎启动失败，日志见 ${LOG_FILE}" >&2
  return 1
}

ensure_engine || exit 1

CMD="$1"; shift 2>/dev/null || true

case "${CMD}" in
  status)   "${PY}" "${BRIDGE}" --status ;;
  sync)     "${PY}" "${BRIDGE}" --sync ;;
  build)    "${PY}" "${BRIDGE}" --build "${1:-}" ;;
  simulate) "${PY}" "${BRIDGE}" --simulate "${1:-6}" ;;
  export)   "${PY}" "${BRIDGE}" --export ;;
  *)
    ROUNDS="${CMD:-6}"
    REQ="${1:-}"
    "${PY}" "${BRIDGE}" --run "${ROUNDS}" --requirement "${REQ}"
    ;;
esac
