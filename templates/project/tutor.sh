#!/bin/bash
# ============================================================
# tutor.sh —— 教学模式（新手向导）
#
# 从零讲一遍整套写作工作台怎么用：
#   认识工具 → 环境体检 → 建故事 → 写一章 → 看结果 → 毕业清单
#
# 用法:
#   ./tutor.sh          完整教学（每步按回车继续）
#   ./tutor.sh brief    快速概览（一口气讲完，不等待）
#   ./tutor.sh doctor   直接进入第 2 步（体检）
# ============================================================
set -uo pipefail

NP="$(cd "$(dirname "$0")" && pwd)"
BRIEF=0
[ "${1:-}" = "brief" ] && BRIEF=1
[ "${1:-}" = "doctor" ] && { BRIEF=0; START_AT=2; }

C_B="\033[0;36m"; C_G="\033[0;32m"; C_Y="\033[0;33m"; C_0="\033[0m"

hr()  { echo "────────────────────────────────────────────────────"; }
title() { echo ""; printf "${C_B}◆ %s${C_0}\n" "$1"; }
note() { printf "  ${C_Y}· %s${C_0}\n" "$1"; }
ok()   { printf "  ${C_G}✓ %s${C_0}\n" "$1"; }
cmd()  { printf "  ${C_B}\$ %s${C_0}\n" "$1"; }

pause() {
  [ "$BRIEF" -eq 1 ] && return 0
  printf "  （按回车继续…）"; read -r _
}

# ============================================================
# 第 1 步 认识工作台
# ============================================================
step1() {
  title "第 1 步 · 认识工作台"
  echo "  Sodarie Novel 是主体：它是图形界面，你在里面阅读、编辑每一章。"
  echo "  「导演 + 写手 + 推演」全部是后台，为 Sodarie 生产章节，自动同步进去。"
  echo "  平时只需要记住一个入口："
  cmd "./workbench.sh"
  echo ""
  echo "  创作中心里 9 个工具分别是（都围绕 Sodarie 组织）："
  printf "  %-16s %s\n" "Sodarie Novel"   "主体界面：阅读/编辑 chapters/ 里的章节"
  printf "  %-16s %s\n" "novel_flow.sh"   "推演+成章一条龙：角色自主演 → 提炼分镜 → 成章，自动进 Sodarie"
  printf "  %-16s %s\n" "write_chapter.sh" "写一章：给 idea 自动成章（3000 字）+ 审查修订 + 记忆更新"
  printf "  %-16s %s\n" "novel_pipeline.sh" "一键全流程（含推演引擎拉起）"
  printf "  %-16s %s\n" "new_story.sh"    "新建故事：问答式，自动生成世界启动卡 + 世界观/人物/大纲"
  printf "  %-16s %s\n" "sync_sodarie.sh" "把新章节同步进 Sodarie（重启 GUI 重扫）"
  printf "  %-16s %s\n" "doctor.sh"       "一键体检：配置/模型/引擎/项目健康度，卡住先跑它"
  printf "  %-16s %s\n" "nest_drama_run.sh" "推演引擎管理（群像自主演绎）"
  printf "  %-16s %s\n" "workbench.sh"    "总入口菜单，Sodarie + 上面全部从这里进"
  echo ""
  echo "  两部规则书（写作时自动遵守，不用记）："
  note "WRITING_SYSTEM.md —— 禁崩线、去 AI 文风、对话铁律"
  note "WORLD_START_CARD.md —— 开新世界/新主角的五步表单"
  pause
}

# ============================================================
# 第 2 步 环境体检
# ============================================================
step2() {
  title "第 2 步 · 环境体检（安全，可以现场跑）"
  echo "  开工前先确认电脑环境是健康的。doctor 会检查 6 项："
  echo "    · 配置文件 ~/.novel/env 是否就绪"
  echo "    · 模型服务（oMLX :8000）是否在线"
  echo "    · 写作/推演模型能否路由"
  echo "    · 推演引擎（:8790）是否在线"
  echo "    · 项目结构（记忆/大纲/Python 环境）"
  echo ""
  cmd "./doctor.sh"
  echo ""
  if [ "$BRIEF" -eq 1 ]; then
    echo "  （brief 模式不实际执行，你自己跑一下看看）"
  else
    printf "  现在就现场跑一次体检？(y/N) "; read -r DOIT
    if [ "$DOIT" = "y" ] || [ "$DOIT" = "Y" ]; then
      "$NP/doctor.sh"
    fi
  fi
  note "体检有红/黄项？大多重跑 install.sh 能解决；解决不了截图给 AI 助手。"
  pause
}

# ============================================================
# 第 3 步 建故事
# ============================================================
step3() {
  title "第 3 步 · 建你的第一个故事"
  echo "  用 new_story.sh 问答式建故事，会问你 9 个问题："
  echo "    ① 书名  ② 一句话故事  ③ 题材/基调  ④ 主角名"
  echo "    ⑤ 时代  ⑥ 起始地域  ⑦ 主角出身  ⑧ 性格内核  ⑨ 主要势力"
  echo ""
  echo "  它会自动生成："
  printf "    %-28s %s\n" "memory/world_start_card.md" "世界启动卡（时代/势力/主角/知情边界）"
  printf "    %-28s %s\n" "memory/story_bible.yaml"     "世界观 + 写作规则"
  printf "    %-28s %s\n" "memory/characters.yaml"      "人物档案"
  printf "    %-28s %s\n" "outlines/book_outline.yaml"  "全书大纲（三幕）"
  echo ""
  cmd "./new_story.sh"
  echo ""
  note "教学模式下不实际执行：它会重置当前故事（旧故事自动备份，不删除）。"
  note "想练手：装好后在真实项目跑一次即可，旧故事会安全备份到 outputs/backups/。"
  pause
}

# ============================================================
# 第 4 步 写一章
# ============================================================
step4() {
  title "第 4 步 · 写第一章"
  echo "  写一章有两条路："
  echo ""
  echo "  路线 A · 推演+成章一条龙（推荐，角色自己演剧情）"
  cmd "./novel_flow.sh"
  echo "    nest-drama 引擎让角色按性格自主推演 → 自动提炼分镜 idea → 成章"
  echo ""
  echo "  路线 B · 直接写（你已经想好这一章写什么）"
  cmd "./write_chapter.sh ch001-标题 \"一句话 idea\" 3000"
  echo "    自动完成：生成正文 → 续写补足字数 → 查设定冲突 → 审查修订 → 更新记忆"
  echo ""
  echo "  写的时候系统自动遵守 WRITING_SYSTEM.md 铁律："
  note "对话只写字面台词（不写'他冷冷地说'）"
  note "动作全是肉眼可见的（低头、踩灭烟头），情绪让读者自己读"
  note "女配不雌竞、主角不越界、系统不跳阶"
  note "有闲笔、有平淡，不全程高能"
  pause
}

# ============================================================
# 第 5 步 看结果
# ============================================================
step5() {
  title "第 5 步 · 看结果"
  echo "  写完后，成果在 Sodarie 主体界面里读，也会出现在："
  echo "    1. Sodarie Novel GUI          主体界面（写章后自动同步，重扫即见）"
  echo "    2. ~/Desktop/小说章节/         自动同步到桌面（方便快速翻看）"
  echo "    3. chapters/chXXX-标题/       章节文件（项目内，Sodarie 扫描的就是这里）"
  echo ""
  echo "  还有一张「创作看板」（4 图 + 诊断报告）："
  cmd "./workbench.sh board"
  echo "    · 人物关系图 / 时间线 / 字数趋势 / AI 痕迹诊断"
  echo ""
  echo "  想看当前状态，随时："
  cmd "./workbench.sh status"
  pause
}

# ============================================================
# 第 6 步 毕业清单
# ============================================================
step6() {
  title "第 6 步 · 毕业清单（全勾上就算学会了）"
  echo "  □ 能跑 ./workbench.sh 看到状态总览"
  echo "  □ 卡住时会先跑 ./doctor.sh 而不是乱猜"
  echo "  □ 知道 ./new_story.sh 会生成世界启动卡 + 世界观/人物/大纲"
  echo "  □ 知道日常写章用 ./workbench.sh 里的「推演+成章」"
  echo "  □ 知道章节会同步到桌面 / Sodarie / 看板"
  echo "  □ 知道 WRITING_SYSTEM 的禁崩线铁律自动生效，不用自己盯"
  echo ""
  echo "  遇到报错的顺序：1) ./doctor.sh  2) 看 GETTING_STARTED.md  3) 截图问 AI"
  echo ""
  ok "教学模式结束。开始写你的第一个故事吧！"
}

# ============================================================
# 主流程
# ============================================================
echo ""
echo "  ════════════════════════════════════════════"
echo "   📚 AI 小说写作工作台 · 教学模式"
echo "  ════════════════════════════════════════════"
[ "$BRIEF" -eq 1 ] && echo "  （快速概览模式：一口气讲完）"

step1
step2
step3
step4
step5
step6
echo ""
