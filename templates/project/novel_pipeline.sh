#!/bin/bash
# ============================================================
# novel_pipeline.sh —— 一键启动：nest-drama 推演流水线
#
# 把融合后的写作流推演链打包成一键执行：
#   记忆库 → sync → 建世界(已建则跳过) → 推演 N 轮 → 导出故事全录
# 完成后输出故事全录路径与交接提示（Codex 提炼分镜 → write_chapter.sh 成章）。
#
# 用法：
#   ./novel_pipeline.sh                        # 完整跑一遍（默认 4 轮）
#   ./novel_pipeline.sh 2                      # 推演 2 轮
#   ./novel_pipeline.sh --force-build          # 强制重建世界（默认已建则跳过）
#   ./novel_pipeline.sh --requirement "让王二…"  # 自定义建世界/推演需求
#   ./novel_pipeline.sh --help
#
# 依赖：oMLX(:8000) 已启动并加载 Ornith-1.5-35B-A3B-MLX-8bit；
#       nest_drama_run.sh（自动拉起 nest-drama 引擎 :8790）
# ============================================================
# 统一配置（~/.novel/env，可按需修改）
[ -f "$HOME/.novel/env" ] && . "$HOME/.novel/env"
set -uo pipefail

NP="$(cd "$(dirname "$0")" && pwd)"
RUN="${NP}/nest_drama_run.sh"
OAPI="http://127.0.0.1:8000"
NAPI="http://127.0.0.1:8790"

# ---------- 参数 ----------
ROUNDS=4
FORCE_BUILD=0
REQ=""
while [ $# -gt 0 ]; do
  case "$1" in
    --force-build) FORCE_BUILD=1 ;;
    --requirement) REQ="$2"; shift ;;
    --help|-h)
      sed -n '1,22p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0 ;;
    *) ROUNDS="$1" ;;
  esac
  shift
done

echo "============================================================"
echo " novel_pipeline · nest-drama 推演流水线一键启动"
echo " 轮数=${ROUNDS}  强制重建=${FORCE_BUILD}  需求=${REQ:-默认}"
echo "============================================================"

# ---------- 0. 预检 oMLX（未就绪则尝试自动拉起） ----------
echo ""
echo "[1/5] 预检本地模型服务 oMLX(:8000)…"
if ! curl -s -m 5 "${OAPI}/health" >/dev/null 2>&1; then
  echo "[预检] oMLX 未就绪，尝试自动启动（omlx start）…"
  omlx start --timeout 120 >/dev/null 2>&1 || true
  sleep 3
fi
if ! curl -s -m 5 "${OAPI}/health" >/dev/null 2>&1; then
  echo "[预检] ✗ oMLX 无法启动。请手动打开 oMLX 应用（需加载 Ornith-1.5-35B-A3B-MLX-8bit）" >&2
  exit 1
fi
echo "[预检] ✓ oMLX 就绪"

# ---------- 1. 确保 nest-drama 引擎 ----------
echo "[2/5] 确保 nest-drama 引擎(:8790)运行…"
if ! curl -s -m 5 "${NAPI}/api/health" >/dev/null 2>&1; then
  "${RUN}" status >/dev/null 2>&1   # run.sh 会自动拉起引擎
fi
if ! curl -s -m 5 "${NAPI}/api/health" >/dev/null 2>&1; then
  echo "[引擎] ✗ 启动失败，日志见 /tmp/nest-drama.log" >&2
  exit 1
fi
echo "[引擎] ✓ 就绪"

# ---------- 2. sync 记忆库 → 材料 ----------
echo "[3/5] 同步记忆库 → 推演材料…"
"${RUN}" sync || { echo "[sync] ✗ 失败" >&2; exit 1; }

# ---------- 3. build 建世界（已建则跳过） ----------
echo "[4/5] 建世界…"
BUILT=$(curl -s -m 5 "${NAPI}/api/health" 2>/dev/null | python3 -c "import sys,json;print(bool(json.load(sys.stdin).get('built')))" 2>/dev/null || echo "False")
if [ "${BUILT}" = "True" ] && [ "${FORCE_BUILD}" = "0" ]; then
  echo "[build] 世界已建好，跳过重建（--force-build 可强制重建）"
else
  echo "[build] 开始建世界（预计 5-15 分钟）…"
  "${RUN}" build "${REQ}" || { echo "[build] ✗ 失败" >&2; exit 1; }
fi

# ---------- 4. simulate 推演 ----------
echo "[5/5] 推演 ${ROUNDS} 轮（每轮或需数分钟，请耐心）…"
"${RUN}" simulate "${ROUNDS}" || echo "[simulate] ⚠ 推演未完全收束，继续导出已有轮次"

# ---------- 5. export 故事全录 ----------
echo "导出故事全录…"
"${RUN}" export || { echo "[export] ✗ 失败" >&2; exit 1; }

# ---------- 摘要 ----------
LATEST=$(ls -t "${NP}/outputs/drama/"*.md 2>/dev/null | head -1)
echo ""
echo "============================================================"
echo " ✅ 推演流水线完成"
[ -n "${LATEST}" ] && echo " 故事全录：${LATEST}"
echo ""
echo " 下一步（交接 Codex）："
echo "   1. 让 Codex 读取故事全录，提炼下一章分镜式 idea"
echo "   2. Codex 确认 idea 后，用以下命令成章："
echo "      ./write_chapter.sh chXXX-标题 \"<分镜 idea>\" 3000"
echo "============================================================"
