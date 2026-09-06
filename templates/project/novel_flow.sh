#!/bin/bash
# ============================================================
# novel_flow.sh —— 整体流程编排：推演 → 提炼 idea → 成章
#
# 把「nest-drama 推演链 + 分镜 idea 提炼 + write_chapter.sh 成章」
# 串成一个整体入口。默认跑完推演与 idea 提炼后停下供审查（尊重
# AGENTS.md 的确认门禁）；--go 全自动一条龙直接成章。
#
# 用法：
#   ./novel_flow.sh                    # 推演(4轮)+提炼idea，停下展示待确认
#   ./novel_flow.sh 2                  # 推演 2 轮 + 提炼 idea
#   ./novel_flow.sh --go               # 全自动：推演→提炼idea→直接成章
#   ./novel_flow.sh --skip-simulate --go   # 跳过推演，用已有全录提炼并成章
#   ./novel_flow.sh --idea "自定义idea"    # 推演后直接用给定 idea 成章
#   ./novel_flow.sh --chapters 3           # 一次推演联产 3 个连续分镜（一场戏多章，均摊推演成本）
#   ./novel_flow.sh --force-build      # 强制重建世界（默认已建则跳过）
#   ./novel_flow.sh --help
#
# 依赖：oMLX(:8000) + nest-drama 引擎(:8790)（novel_pipeline.sh 自动拉起）
# ============================================================
# 统一配置（~/.novel/env，可按需修改）
[ -f "$HOME/.novel/env" ] && . "$HOME/.novel/env"
set -uo pipefail

NP="$(cd "$(dirname "$0")" && pwd)"
PY="${NP}/scripts/.venv/bin/python"
GIDEA="${NP}/scripts/generate_idea.py"

ROUNDS=4
GO=0
FORCE=0
SKIP_SIM=0
IDEA=""
CHAPN=1        # --chapters N：一次推演联产 N 个连续分镜（一场戏多章）
STEP=30000     # 节拍间距（字符）：从全录末尾往前每 STEP 取一段

while [ $# -gt 0 ]; do
  case "$1" in
    --go) GO=1 ;;
    --force-build) FORCE=1 ;;
    --skip-simulate) SKIP_SIM=1 ;;
    --idea) IDEA="$2"; shift ;;
    --chapters) CHAPN="$2"; shift ;;
    --step) STEP="$2"; shift ;;
    --help|-h)
      sed -n '1,32p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0 ;;
    *) ROUNDS="$1" ;;
  esac
  shift
done

# ---------- 工具 ----------
next_id() {
  local max=0 n
  for d in "${NP}"/chapters/ch*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d" | sed -E 's/^ch([0-9]+).*/\1/')"
    [ -n "$n" ] && [ "$n" -gt "$max" ] && max="$n"
  done
  printf "ch%03d" $((max + 1))
}

extract_title() {
  local t="$1"
  case "$t" in
    【标题】*) t="${t#*】}" ;;
    ch[0-9]*) t="${t#*-}" ;;
  esac
  t="$(echo "$t" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  # 截断到 12 字内（按字符，避免整句 idea 当标题）
  t="$(printf '%s' "$t" | cut -c1-12)"
  t="$(echo "$t" | sed -E 's/[，。、！？!?；;：:、[:space:]]+$//')"
  [ -z "$t" ] && t="无题"
  echo "$t"
}

echo "============================================================"
echo " novel_flow · 整体流程（推演 → 提炼idea → 成章）"
echo " 轮数=${ROUNDS}  全自动=${GO}  跳过推演=${SKIP_SIM}  自定义idea=$([ -n "$IDEA" ] && echo 是 || echo 否)"
echo "============================================================"

# ---------- 1. 推演链 ----------
if [ "${SKIP_SIM}" = "1" ] || [ "${ROUNDS}" = "0" ]; then
  echo ""
  echo "[1/3] 跳过推演，使用现有故事全录…"
else
  echo ""
  echo "[1/3] 跑推演链（sync→build→simulate→export）…"
  PIPELINE_ARGS="${ROUNDS}"
  [ "${FORCE}" = "1" ] && PIPELINE_ARGS="${PIPELINE_ARGS} --force-build"
  "${NP}/novel_pipeline.sh" ${PIPELINE_ARGS} || { echo "[整体] ✗ 推演链失败，中止" >&2; exit 1; }
fi

# ---------- 2. 分镜 idea ----------
echo ""
echo "[2/3] 准备下一章分镜式 idea…"
CHAPTER_ID=""
if [ -n "${IDEA}" ]; then
  echo "[idea] 使用用户指定 idea"
else
  DRAMA=$(ls -t "${NP}/outputs/drama/"*.md 2>/dev/null | head -1)
  if [ -z "${DRAMA}" ]; then echo "[整体] ✗ 未找到故事全录" >&2; exit 1; fi
  LEN=$("${PY}" -c "import sys;print(len(open(sys.argv[1],encoding='utf-8').read()))" "${DRAMA}")
  BASE="$(next_id)"
  BN=$(( 10#${BASE#ch} ))
  if [ "${CHAPN}" -gt 1 ]; then
    echo "[idea] 从故事全录联产 ${CHAPN} 个连续分镜（全录 ${LEN} 字符，节拍间距 ${STEP}）…"
    IDEA_DIR="${NP}/outputs/ideas/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${IDEA_DIR}"
    CHAPTER_ID=""
    IDX=0
    while [ "${IDX}" -lt "${CHAPN}" ]; do
      K=$(( CHAPN - 1 - IDX ))          # K=0 最晚(尾部)；其余从早到晚向前取段
      if [ "${K}" -eq 0 ]; then START=0; else START=$(( LEN - (CHAPN - IDX) * STEP - 20000 )); [ "${START}" -lt 0 ] && START=0; fi
      CNUM="$(printf 'ch%03d' $(( BN + IDX )))"
      echo ""
      echo "──── [分镜 $((IDX + 1))/${CHAPN}] ${CNUM} · 全录偏移 ${START}（由早到晚）────"
      CUR_IDEA="$("${PY}" "${GIDEA}" --tail 20000 --from "${START}" --chapter-id "${CNUM}" 2>/dev/null)" \
        || { echo "[整体] ✗ idea 提炼失败（分镜 $((IDX + 1))）" >&2; exit 1; }
      T="$(printf '%s\n' "${CUR_IDEA}" | head -1 | sed -E 's/^【标题】\s*//' | cut -c1-12)"
      T="$(echo "${T}" | sed -E 's/[，。、！？!?；;：:、[:space:]]+$//')"
      [ -z "${T}" ] && T="无题"
      FINAL="${CNUM}-${T}"
      printf '%s\n' "${CUR_IDEA}" > "${IDEA_DIR}/${FINAL}.md"
      echo "  ✓ 已存: ${IDEA_DIR}/${FINAL}.md"
      [ -z "${CHAPTER_ID}" ] && CHAPTER_ID="${FINAL}"
      IDX=$((IDX + 1))
    done
    echo ""
    echo "──── 全部 ${CHAPN} 个连续分镜（叙事顺序，从早到晚）────"
    ls "${IDEA_DIR}"/*.md | sed -E 's#.*/##; s/\.md$//'
    echo "目录: ${IDEA_DIR}"
  else
    echo "[idea] 从故事全录自动提炼（约 1-2 分钟）…"
    IDEA="$("${PY}" "${GIDEA}" --tail 20000 2>/dev/null)" || { echo "[整体] ✗ idea 提炼失败" >&2; exit 1; }
    CID="$(next_id)"
    TITLE="$(extract_title "$(printf '%s\n' "${IDEA}" | head -1)")"
    CHAPTER_ID="${CID}-${TITLE}"
    [ "${TITLE}" = "无题" ] && echo "[提示] 未能从 idea 提取标题，章节 ID 暂用 ${CHAPTER_ID}（可手动改名）"
    echo ""
    echo "──── 下一章分镜式 idea ────"
    echo "${IDEA}"
    echo "──── 章节 ID：${CHAPTER_ID} ────"
  fi
fi

# --idea 指定时补章节 ID（多分镜联产不走此分支）
if [ -n "${IDEA}" ] && [ -z "${CHAPTER_ID}" ]; then
  CID="$(next_id)"
  TITLE="$(extract_title "$(printf '%s\n' "${IDEA}" | head -1)")"
  CHAPTER_ID="${CID}-${TITLE}"
  [ "${TITLE}" = "无题" ] && echo "[提示] 未能从 idea 提取标题，章节 ID 暂用 ${CHAPTER_ID}（可手动改名）"
  echo "──── 章节 ID：${CHAPTER_ID} ────"
fi

# ---------- 3. 成章（或停下待确认） ----------
if [ "${GO}" = "1" ]; then
  if [ "${CHAPN}" -gt 1 ] && [ -n "${IDEA_DIR}" ]; then
    echo ""
    echo "[3/3] --go 全自动：联产 ${CHAPN} 章（每章约 3000 字，write_chapter.sh）…"
    for F in "${IDEA_DIR}"/*.md; do
      FID="$(basename "${F}" .md)"
      FIDEA="$(cat "${F}")"
      echo ""
      echo "──── 成章 ${FID} ────"
      "${NP}/write_chapter.sh" "${FID}" "${FIDEA}" 3000 || { echo "[整体] ✗ 成章失败: ${FID}" >&2; exit 1; }
    done
    echo ""
    echo "✅ 整体流程完成：${CHAPN} 章已生成（Sodarie GUI / 桌面可见）"
  else
    echo ""
    echo "[3/3] --go 全自动：开始成章（write_chapter.sh，约 3000 字）…"
    "${NP}/write_chapter.sh" "${CHAPTER_ID}" "${IDEA}" 3000 || { echo "[整体] ✗ 成章失败" >&2; exit 1; }
    echo ""
    echo "✅ 整体流程完成：${CHAPTER_ID} 已生成，Sodarie GUI / 桌面可见"
  fi
else
  echo ""
  echo "[3/3] idea 已就绪，等待确认（AGENTS.md 门禁）"
  if [ "${CHAPN}" -gt 1 ] && [ -n "${IDEA_DIR}" ]; then
    echo "  · 《${CHAPN} 个连续分镜存于：${IDEA_DIR}》逐章确认后："
    echo "    认可全部 → 运行： ./novel_flow.sh --go --skip-simulate --chapters ${CHAPN}"
    echo "    认可部分 → 直接调用 write_chapter.sh（文件名即章节 ID）"
  else
    echo "  · 认可当前 idea → 运行： ./novel_flow.sh --go --skip-simulate"
    echo "     （或直接： ./write_chapter.sh \"${CHAPTER_ID}\" \"<上面的 idea>\" 3000）"
    echo "  · 想改 idea → 告诉我调整方向，或手动改上面文本"
  fi
fi
echo "============================================================"
