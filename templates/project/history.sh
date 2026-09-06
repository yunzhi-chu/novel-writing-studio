#!/bin/bash
# ============================================================
# history.sh —— Sodarie 创作中心 · 生产历史视图
#
# 聚合工作台的生产足迹：章节产出、审查报告、分镜 idea、后台任务。
# 由 workbench.sh h 调用；可直接运行查看。
# ============================================================
NP="$(cd "$(dirname "$0")" && pwd)"

say() { echo ""; echo "────────────────────────────────────────────"; echo "▶ $1"; }

echo "  ═══ Sodarie 创作中心 · 生产历史 ═══"

# ---------- 1. 章节产出 ----------
echo ""
echo "  ── 章节（最新 8 章）──────────────────────"
if [ -d "$NP/chapters" ]; then
  CN=$(ls "$NP/chapters" 2>/dev/null | wc -l | tr -d ' ')
  echo "  共 ${CN} 章"
  while IFS= read -r d; do
    ID=$(basename "$d")
    MT=$(stat -f "%Sm" -t "%m-%d %H:%M" "$d" 2>/dev/null)
    WC=$(wc -m "$d/chapter.md" 2>/dev/null | awk '{print $1}')
    echo "    ${ID}  ${WC}字  ${MT}"
  done < <(ls -dt "$NP"/chapters/ch*/ 2>/dev/null | head -8)
fi

# ---------- 2. 审查報告 ----------
echo ""
echo "  ── 审查报告（最近 5 份）──────────────────"
if [ -d "$NP/outputs/reports" ]; then
  while IFS= read -r f; do
    ID=$(basename "$f" _consistency_report.md)
    MT=$(stat -f "%Sm" -t "%m-%d %H:%M" "$f" 2>/dev/null)
    VERDICT=$(awk '/^<!--/{next} /^## 发现的问题/{exit} /^#/{next} /^[[:space:]]*$/{next} {print; exit}' "$f" 2>/dev/null)
    VERDICT="${VERDICT:0:62}"   # 总评首段摘要(截 62 字)
    echo "    ${ID}  ${MT}  ${VERDICT}"
  done < <(ls -t "$NP"/outputs/reports/*consistency_report.md 2>/dev/null | head -5)
fi

# ---------- 3. 待确认分镜 ----------
say "待确认分镜（outputs/ideas/）"
IDEA_DIRS=$(ls -dt "$NP"/outputs/ideas/*/ 2>/dev/null)
if [ -z "$IDEA_DIRS" ]; then
  echo "  暂无（推演后可 ./workbench.sh flow --chapters N 联产）"
else
  while IFS= read -r d; do
    N=$(ls "$d"*.md 2>/dev/null | wc -l | tr -d ' ')
    DONE=0
    for f in "$d"*.md; do
      [ -f "$f" ] || continue
      CH=$(basename "$f" .md | sed -E 's/-.*//')
      ls "$NP"/chapters/${CH}-* >/dev/null 2>&1 && DONE=$((DONE + 1))
    done
    MT=$(stat -f "%Sm" -t "%m-%d %H:%M" "$d" 2>/dev/null)
    if [ "$DONE" -ge "$N" ]; then
      echo "  ✓ ${MT}  ${N} 个分镜（全部已成章）"
    else
      echo "  ● ${MT}  ${N} 个分镜（已写入 $DONE/N，剩余待确认成章： ./workbench.sh flow --go --skip-simulate --chapters ${N}）"
    fi
  done < <(ls -dt "$NP"/outputs/ideas/*/ 2>/dev/null)
fi

# ---------- 4. 后台任务 ----------
say "最近后台任务（outputs/logs/）"
LOGS=$(ls -t "$NP"/outputs/logs/*.log 2>/dev/null | head -5)
if [ -z "$LOGS" ]; then
  echo "  暂无"
else
  while IFS= read -r f; do
    NAME=$(basename "$f" .log)
    MT=$(stat -f "%Sm" -t "%m-%d %H:%M" "$f" 2>/dev/null)
    RC="运行中"
    grep -q "^EXIT=" "$f" && RC="$(grep '^EXIT=' "$f" | tail -1)"
    echo "    ${NAME}  ${MT}  ${RC}"
  done < <(ls -t "$NP"/outputs/logs/*.log 2>/dev/null | head -5)
fi
echo ""
