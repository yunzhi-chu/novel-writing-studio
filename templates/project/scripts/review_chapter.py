#!/usr/bin/env python3
"""
review_chapter.py —— 章节自动审查统一入口（纯统计快检，无需 LLM）
整合 novel-suite（MIT）的统计审查算法：
  1. check_ai_tells   —— 4 维 AI 痕迹检测（段落均匀度/套话密度/公式化转折/列表化句式）
  2. check_post_write —— 硬规则违规检测（13 禁用模式 + 8 风险词频）
  3. 字数检查         —— 不足/达标/超长对比（修复"章节超长"问题）

用法:
    python scripts/review_chapter.py --chapter ch907
    python scripts/review_chapter.py --chapter ch907 --target 3000
    python scripts/review_chapter.py --chapter ch907 --json
    # PROJECT_ROOT 环境变量可指定其他项目（短篇小说工厂使用）
"""

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent / "review"))

from utils import (
    get_project_root,
    ensure_dirs,
    load_config,
    read_text,
    write_text,
    configure_utf8_stdio,
)
import check_ai_tells
import check_post_write


def chinese_char_count(text: str) -> int:
    return len(re.findall(r"[\u4e00-\u9fff]", text))


def check_word_count(body: str, target: int) -> list[dict]:
    """字数检查：不足/达标/超长。"""
    count = chinese_char_count(body)
    if target <= 0:
        return []
    issues = []
    if count < target * 0.95:
        issues.append({
            "severity": "warning",
            "dimension": "word-count.short",
            "location": "全章",
            "description": f"字数 {count} 字，不足目标 {target} 字（达标线 {int(target*0.95)}）",
            "suggestion": "自动续写补足（流水线已处理）",
        })
    elif count > target * 1.5:
        issues.append({
            "severity": "warning",
            "dimension": "word-count.overlong",
            "location": "全章",
            "description": f"字数 {count} 字，超过目标 {target} 字 1.5 倍（{int(target*1.5)}）",
            "suggestion": "篇幅明显超出，建议拆分或精简冗余段落；若要控制篇幅可在生成提示词约束上限",
        })
    return issues


def run_review(chapter_id: str, target: int) -> dict:
    root = get_project_root()
    chapter_path = root / "chapters" / chapter_id / "chapter.md"
    if not chapter_path.exists():
        raise FileNotFoundError(f"未找到章节: {chapter_path}")

    text = read_text(chapter_path)
    body = check_post_write.strip_frontmatter_and_outline(text)

    issues = []
    issues += check_ai_tells.run(chapter_path).get("issues", [])
    issues += check_post_write.run(chapter_path, root).get("issues", [])
    issues += check_word_count(body, target)

    critical = [i for i in issues if i["severity"] == "critical"]
    warnings = [i for i in issues if i["severity"] == "warning"]
    infos = [i for i in issues if i["severity"] == "info"]

    return {
        "checker": "review_chapter",
        "chapter": chapter_id,
        "word_count": chinese_char_count(body),
        "target_words": target,
        "passed": len(critical) == 0,
        "summary": {
            "critical": len(critical),
            "warning": len(warnings),
            "info": len(infos),
            "total": len(issues),
        },
        "issues": issues,
    }


def write_report(chapter_id: str, result: dict):
    root = get_project_root()
    config = load_config()
    lines = [
        "<!-- 自动审查报告（统计快检：AI 痕迹 + 硬规则 + 字数）-->",
        f"<!-- 生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} -->",
        f"<!-- 模型: 无（纯统计，无需 LLM）-->",
        "",
        f"# 自动审查报告: {chapter_id}",
        "",
        f"- 字数: {result['word_count']} 字（目标 {result['target_words']} 字）",
        f"- 结论: {'✅ 通过（无 critical）' if result['passed'] else '❌ 有 critical 需处理'}",
        f"- 统计: critical {result['summary']['critical']} / warning {result['summary']['warning']} / info {result['summary']['info']}",
        "",
        "## 发现的问题",
        "",
    ]
    if not result["issues"]:
        lines.append("未发现 AI 痕迹 / 硬规则 / 字数问题。")
    for issue in result["issues"]:
        sev = issue["severity"].upper()
        lines.append(f"### [{sev}] {issue['dimension']}")
        lines.append(f"- **位置**: {issue['location']}")
        lines.append(f"- **问题**: {issue['description']}")
        lines.append(f"- **建议**: {issue['suggestion']}")
        lines.append("")
    report_path = root / "outputs" / "reports" / f"{chapter_id}_review_report.md"
    write_text(report_path, "\n".join(lines))
    return report_path


def main():
    configure_utf8_stdio()
    parser = argparse.ArgumentParser(description="章节自动审查（统计快检）")
    parser.add_argument("--chapter", required=True, help="章节 ID，如 ch907")
    parser.add_argument("--target", type=int, default=3000, help="目标中文字数，用于字数检查")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    args = parser.parse_args()

    ensure_dirs()
    result = run_review(args.chapter.strip(), args.target)

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    print(f"🔍 review_chapter - {result['chapter']}")
    print(f"   字数: {result['word_count']}（目标 {result['target_words']}）")
    print(f"   结论: {'通过 ✅' if result['passed'] else '需处理 ❌'}")
    print(f"   issues: critical {result['summary']['critical']} / warning {result['summary']['warning']} / info {result['summary']['info']}")
    for issue in result["issues"]:
        sev = issue["severity"].upper()
        print(f"\n   [{sev}] {issue['dimension']} @ {issue['location']}")
        print(f"     {issue['description']}")
        print(f"     建议：{issue['suggestion']}")

    report_path = write_report(result["chapter"], result)
    print(f"\n[完成] 审查报告已保存: {report_path}")


if __name__ == "__main__":
    main()
