#!/bin/bash
# ============================================================
# new_story.sh —— 一键初始化新故事（从零开始最省事的一步）
#
# 交互式问你几个问题，自动生成：
#   memory/story_bible.yaml   世界观（书名/题材/基调/世界规则占位）
#   memory/characters.yaml    人物档案（主角占位）
#   outlines/book_outline.yaml 全书大纲（一句话故事/三幕占位）
# 同时清空旧章节记忆（旧的 chapters/ 和记忆会自动备份，不删除）
#
# 用法:
#   ./new_story.sh                     # 交互式问答
#   ./new_story.sh "书名" "一句话故事"   # 直接传参（非交互）
# ============================================================
set -uo pipefail

NP="$(cd "$(dirname "$0")" && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"

say() { echo ""; echo "────────────────────────────────────────────"; echo "▶ $1"; }
ok()  { echo "  ✓ $1"; }

# ---------- 收集信息 ----------
if [ "$#" -ge 2 ]; then
  TITLE="$1"; LOGLINE="$2"
  echo "书名: $TITLE"; echo "一句话故事: $LOGLINE"
  [ -n "${3:-}" ] && GENRE="$3" || GENRE=""
  [ -n "${4:-}" ] && HERO="$4" || HERO=""
  [ -n "${5:-}" ] && ERA="$5" || ERA=""
  [ -n "${6:-}" ] && REGION="$6" || REGION=""
  [ -n "${7:-}" ] && ORIGIN="$7" || ORIGIN=""
  [ -n "${8:-}" ] && CORE="$8" || CORE=""
  [ -n "${9:-}" ] && POWERS="$9" || POWERS=""
else
  say "新建故事 · 问答（随时可回车跳过，后面再填）"
  printf "  ① 书名："; read -r TITLE
  printf "  ② 一句话故事（logline）："; read -r LOGLINE
  printf "  ③ 题材/基调（如 现实主义/悬疑）："; read -r GENRE
  printf "  ④ 主角名："; read -r HERO
  printf "  ⑤ 时代/背景（如 当下小城/架空朝代）："; read -r ERA
  printf "  ⑥ 起始地域："; read -r REGION
  printf "  ⑦ 主角出身/身份："; read -r ORIGIN
  printf "  ⑧ 性格内核（如 想躺平、遇事敢扛）："; read -r CORE
  printf "  ⑨ 主要势力（如 医院/单位/家族，可略）："; read -r POWERS
fi
[ -z "${TITLE:-}" ] && TITLE="我的新故事"
[ -z "${LOGLINE:-}" ] && LOGLINE="（一句话故事待补充）"
[ -z "${GENRE:-}" ] && GENRE="待定"
[ -z "${HERO:-}" ] && HERO="主角"
[ -z "${ERA:-}" ] && ERA="【待补充】时代/背景"
[ -z "${REGION:-}" ] && REGION="【待补充】起始地域"
[ -z "${ORIGIN:-}" ] && ORIGIN="【待补充】出身/身份"
[ -z "${CORE:-}" ] && CORE="【待补充】性格内核"
[ -z "${POWERS:-}" ] && POWERS="【待补充】主要势力"

# ---------- 备份旧故事（不删除，安全） ----------
if [ -d "$NP/chapters" ] && [ -n "$(ls -A "$NP/chapters" 2>/dev/null)" ]; then
  BK="$NP/outputs/backups/story-$TS"
  mkdir -p "$BK"
  cp -R "$NP/memory" "$BK/" 2>/dev/null
  cp -R "$NP/outlines" "$BK/" 2>/dev/null
  cp -R "$NP/chapters" "$BK/" 2>/dev/null
  ok "旧故事已备份到 outputs/backups/story-${TS}（未删除）"
fi

# ---------- 生成骨架 ----------
say "生成新故事骨架：《${TITLE}》"
mkdir -p "$NP/memory" "$NP/outlines" "$NP/chapters" "$NP/outputs" "$NP/config"

cat > "$NP/memory/story_bible.yaml" <<EOF
# 故事圣经 - 全局世界观和写作规则（new_story.sh 生成，可继续编辑）
title: "${TITLE}"
genre: "${GENRE}"
tone: "冷静、克制、朴素（可改）"

narrative_defaults:
  pov: "limited:${HERO}"
  directives:
    - "Forensic Minimalism"
    - "Diegetic Observation only (no authorial summary of feelings)"

world_rules:
  - "时代/背景：${ERA}"
  - "起始地域：${REGION}"
  - "主要势力：${POWERS}"
  - "【待补充】社会运行规则（现实法律/人情世故优先级永远高于任何系统/金手指）。"
  - "【待补充】主角的身份与处境。"
  - "【待补充】这个世界里'不能发生'的事。"

writing_rules:
  - "对白克制，潜台词优先于直白抒情。"
  - "每章结尾留一个未解答的画面或声音（钩子）。"

cinematic_rules:
  - "每章有一个能'拍下来'的视觉主句。"
  - "场景切换用画面变化连接，不用'此时'等过渡词。"
EOF

cat > "$NP/memory/characters.yaml" <<EOF
# 角色档案 - 每个角色一条记录（new_story.sh 生成，可继续编辑）
${HERO}:
  role: "主角"
  identity: "${ORIGIN}"
  personality: "${CORE}"
  speaking_style: "【待补充】说话风格"
  current_status: "故事开始时：${LOGLINE}"
  secrets: []
  knows: []
  relationships: {}
  constraints: []
EOF

cat > "$NP/outlines/book_outline.yaml" <<EOF
# 全书大纲 - 方向、主线冲突、分幕结构（new_story.sh 生成，可继续编辑）
title: "${TITLE}"
genre: "${GENRE}"
core_theme: "【待补充】一句话主题"
logline: "${LOGLINE}"

main_conflict:
  external: "【待补充】主角面临的外部困难"
  internal: "【待补充】主角的内心矛盾"
  emotional: "【待补充】情感线张力"

structure:
  act1_setup:
    chapters: "ch001-ch005"
    function: "建立世界观、主角处境、核心冲突。"
    key_turning_point: "【待补充】第一幕转折点"
  act2_confrontation:
    chapters: "ch006-ch018"
    function: "冲突升级，秘密逐渐浮出水面。"
    key_turning_point: "【待补充】第二幕转折点"
  act3_resolution:
    chapters: "ch019-ch030"
    function: "关系修复，主角学会承担。"
    key_turning_point: "【待补充】收束"
EOF

# 清空增量记忆（jsonl 类）
: > "$NP/memory/chapter_summaries.jsonl"
: > "$NP/memory/events.jsonl"
: > "$NP/memory/style_bank.jsonl"
: > "$NP/memory/timeline.jsonl"
echo '{"empty": true}' > "$NP/memory/relationships.json"
cat > "$NP/memory/foreshadowing.yaml" <<'EOF'
# 伏笔台账 - active(埋下未收) / resolved(已回收)
EOF

# ---------- 世界启动卡快照（WORLD_START_CARD 4.4 冷启动） ----------
cat > "$NP/memory/world_start_card.md" <<EOF
# 世界启动卡 · 《${TITLE}》（WORLD_START_CARD 4.4 冷启动快照）

## 第一步｜时代地域参数
- 时代：${ERA}
- 起始地域切片：${REGION}
- 起始内历（全局锚点）：${TS}

## 第二步｜势力开关表
| 势力分组 | 具体势力 | 状态 | 启用说明 |
|---|---|---|---|
| 主要势力 | ${POWERS} | 开 | ${LOGLINE} |

（额外自定义势力：按需增删）

## 第三步｜主角原创表单（禁止原著人物替身）
- 姓名：${HERO}
- 出身/所属势力与身份地位：${ORIGIN}
- 性格内核：${CORE}
- （性别/年龄/家庭背景/特质/执念/短板：见 memory/characters.yaml 补充）

## 第四步｜宿主初始推理边界
- 初始设定由后台按前三步推演；后续可通过系统查询宿主档查看。

## 第五步｜开局快照 & 知情边界
- 当前所处地点：【待补充】
- 当下处境：${LOGLINE}
- 主角知情范围（知道/不知道）：【待补充】

> 开局快照与知情边界确认后，正式开启写作/推演。
EOF

ok "记忆/大纲骨架 + 世界启动卡已生成"

# ---------- 完成提示 ----------
say "新故事《${TITLE}》已就绪！"
echo "  接下来三选一："
echo "  1. 用 AI 导演填细节（推荐）：把 AGENTS.md 交给豆包/Codex，说"
echo "     「我是《${TITLE}》的导演，请先给我一份世界观/人物/大纲计划，我确认后你动手」"
echo "  2. 手动编辑：open $NP/memory/story_bible.yaml（世界启动卡见 memory/world_start_card.md）"
echo "  3. 直接写第一章：./write_chapter.sh ch001-标题 \"一句话 idea\" 3000"
echo ""
echo "  （旧故事备份在 outputs/backups/story-${TS}，想恢复就拷回来）"
