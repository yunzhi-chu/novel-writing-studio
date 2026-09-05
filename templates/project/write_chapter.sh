#!/bin/bash
# ============================================================
# write_chapter.sh —— Codex × Sodarie Novel 联动桥接脚本
#
# 用法:
#   ./write_chapter.sh <章节ID> "<chapter idea>" [目标字数]
# 示例:
#   ./write_chapter.sh ch001-雨夜书店 "主角在雨夜误入午夜书店" 3000
#
# 完整流水线:
#   生成正文(3000字) → 字数兜底续写 → 写入标题 → 一致性检查
#   → 自动审查 + 自动修订闭环(发现问题自动修订到清零)
#   → 自动更新长期记忆 → 自动刷新 archify 看板(4图+诊断报告+总览页)
#   → 自动弹出看板 → 同步到桌面 + GUI 项目目录 → 重启 Sodarie GUI 同步章节
# ============================================================
set -euo pipefail

NP="$(cd "$(dirname "$0")" && pwd)"

if [ $# -lt 2 ]; then
    echo "用法: $0 <章节ID> \"<idea>\" [目标字数]"
    exit 1
fi

CHAPTER="${1}"
IDEA="${2}"
# 默认目标字数：3000 字/章（可用第三个参数覆盖）
WORDS="${3:-3000}"

# 读取统一配置（install.sh 生成的 ~/.novel/env；可按需修改）
[ -f "$HOME/.novel/env" ] && . "$HOME/.novel/env"

# 本地 oMLX 模型配置（与 Sodarie Novel 设置一致）
export LLM_BASE_URL="http://127.0.0.1:8000/v1"
export LLM_API_KEY="${LLM_API_KEY:-sk-omlx-local}"
export LLM_MODEL="${LLM_MODEL:-Qwen3.6-35B-A3B-MLX-8bit}"

echo "[写手] 开始生成章节 ${CHAPTER}，目标 ${WORDS} 字"
echo "  idea: ${IDEA}"
echo "  模型: ${LLM_MODEL} @ ${LLM_BASE_URL}"

# 1) 生成正文（no_think 由脚本内部处理，idea 保持干净）
"${NP}/scripts/.venv/bin/python" "${NP}/scripts/generate_chapter_local.py" \
    --chapter "${CHAPTER}" \
    --idea "${IDEA}" \
    --target-words "${WORDS}"

echo ""
echo "[完成] 章节已生成: ${NP}/chapters/${CHAPTER}/chapter.md"

# 2) 字数兜底：未达目标字数则自动续写补足（最多 3 轮）
echo "[字数检查] 检查 ${CHAPTER} 是否达到 ${WORDS} 字..."
"${NP}/scripts/.venv/bin/python" "${NP}/scripts/extend_chapter.py" \
    --chapter "${CHAPTER}" --target "${WORDS}" 2>&1 | grep -E "续写|结果" || true

# 3) 把标题（章节 ID 中 "-" 之后的部分）写入正文开头，例如 ch902-父子夜谈 → "# 父子夜谈"
TITLE="${CHAPTER#*-}"
if [ "${TITLE}" != "${CHAPTER}" ]; then
  CHAPTER_FILE="${NP}/chapters/${CHAPTER}/chapter.md"
  if [ -f "${CHAPTER_FILE}" ] && ! head -1 "${CHAPTER_FILE}" | grep -q "^# ${TITLE}"; then
    { echo "# ${TITLE}"; echo ""; cat "${CHAPTER_FILE}"; } > "${CHAPTER_FILE}.tmp" && mv "${CHAPTER_FILE}.tmp" "${CHAPTER_FILE}"
    echo "[标题] 已在正文开头写入: # ${TITLE}"
  fi
fi

# 4) 一致性检查：查找设定冲突（不阻断，只报告）
echo "[一致性检查] 检查 ${CHAPTER} 与长期记忆的冲突..."
"${NP}/scripts/.venv/bin/python" "${NP}/scripts/check_consistency.py" \
    --chapter "${CHAPTER}" 2>&1 | tail -5 || true

# 4.5) 自动审查 + 自动修订闭环（审查不过自动修订，报告含审查结果）
echo "[审查+修订] 自动审查 ${CHAPTER}；发现问题则自动修订..."
"${NP}/scripts/.venv/bin/python" "${NP}/scripts/revise_chapter.py" \
    --chapter "${CHAPTER}" --target "${WORDS}" --max-rounds 2 2>&1 | tail -8 || true

# 5) 自动更新长期记忆：人物状态、伏笔、章节摘要、时间线、事件
echo "[记忆更新] 把 ${CHAPTER} 沉淀进长期记忆..."
"${NP}/scripts/.venv/bin/python" "${NP}/scripts/update_memory_after_chapter.py" \
    --chapter "${CHAPTER}" 2>&1 | tail -5 || true

# 6) 创作看板自动刷新（可选组件）：4 类图表 + 4 维诊断报告（记忆已更新，图即最新）
#    未安装看板工具时自动跳过，不影响成章主流程
if [ -f "${NP}/scripts/novel_studio.py" ]; then
    echo "[看板] 刷新创作看板..."
    "${NP}/scripts/.venv/bin/python" "${NP}/scripts/novel_studio.py" 2>&1 | tail -6 || true
    # 6.5) 自动弹出创作看板总览页（浏览器，仅一页，iframe 嵌 4 图）
    if [ -f "${NP}/charts/index.html" ]; then
        open "${NP}/charts/index.html" 2>/dev/null || true
        echo "[看板] 已在浏览器打开总览页: charts/index.html"
    fi
else
    echo "[看板] （可选）创作看板工具未安装，已跳过"
fi

# 7) 同步到桌面（方便查看）
DESKTOP_DIR="${HOME}/Desktop/小说章节"
mkdir -p "${DESKTOP_DIR}"
cp "${NP}/chapters/${CHAPTER}/chapter.md" "${DESKTOP_DIR}/${CHAPTER}.md"
echo "[完成] 已同步到桌面: ${DESKTOP_DIR}/${CHAPTER}.md"

# 8) 同步到 Sodarie Novel GUI：重启 GUI 触发重扫 chapters/ 目录
echo "[Sodarie] 同步章节到 Sodarie Novel GUI..."
"${NP}/sync_sodarie.sh" 2>&1 | tail -2 || true
