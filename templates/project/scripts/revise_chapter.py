#!/usr/bin/env python3
"""
revise_chapter.py —— 审查不通过自动修订闭环（仿 inkos 修订循环）
流程：审查 → 定位违规句 → 句子级局部替换（LLM）→ 重新审查 → 直到问题清零或达到最大轮次。

关键机制：
  1. 纯统计审查定位问题（AI 痕迹/硬规则/字数），无需 LLM
  2. 只有 critical 或 warning 才触发修订；info 仅提示
  3. 修订采用"句子级局部替换"：精确定位违规句，只让 LLM 重写这些句子，
     其余正文一字不改 → 不引入新问题
  4. 回归保护：每轮修订后逐句验证，问题未减少则回滚到上一版，防止越改越差
  5. 句子级修订失败时 fallback 到全文最小修订

用法:
    python scripts/revise_chapter.py --chapter ch907 --target 3000
    python scripts/revise_chapter.py --chapter ch907 --target 3000 --max-rounds 3
    python scripts/revise_chapter.py --chapter ch907 --target 3000 --json
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
    read_text,
    write_text,
    call_local_llm,
    configure_utf8_stdio,
)
import check_ai_tells
import check_post_write


def chinese_char_count(text: str) -> int:
    return len(re.findall(r"[\u4e00-\u9fff]", text))


# ---------------------------------------------------------------------------
# 审查
# ---------------------------------------------------------------------------

def review_body(body: str, target: int) -> list[dict]:
    """对正文文本跑统计审查，返回问题列表（不读文件、不写报告）。"""
    issues = []
    issues += check_ai_tells.check_dim20_paragraph_uniformity(body)
    issues += check_ai_tells.check_dim21_hedge_density(body)
    issues += check_ai_tells.check_dim22_formulaic_transitions(body)
    issues += check_ai_tells.check_dim23_list_like_structure(body)
    issues += check_post_write.check_forbidden(body, check_post_write.DEFAULT_FORBIDDEN)
    issues += check_post_write.check_risk(body, check_post_write.DEFAULT_RISK)

    count = chinese_char_count(body)
    if target > 0:
        if count < target * 0.95:
            issues.append({
                "severity": "warning",
                "dimension": "word-count.short",
                "location": "全章",
                "description": f"字数 {count} 字，不足目标 {target} 字",
                "suggestion": "续写补足",
            })
        elif count > target * 1.5:
            issues.append({
                "severity": "warning",
                "dimension": "word-count.overlong",
                "location": "全章",
                "description": f"字数 {count} 字，超过目标 {target} 字 1.5 倍",
                "suggestion": "精简冗余段落，把篇幅控制到目标附近",
            })
    return issues


def score_issues(issues: list[dict]) -> int:
    """问题加权分：critical=10, warning=3, info=1。分数越低越好。"""
    sev_score = {"critical": 10, "warning": 3, "info": 1}
    return sum(sev_score.get(i.get("severity", "info"), 1) for i in issues)


def format_issue_list(issues: list[dict]) -> str:
    if not issues:
        return "（无问题）"
    lines = []
    for i, issue in enumerate(issues, 1):
        sev = issue.get("severity", "info").upper()
        lines.append(
            f"{i}. [{sev}] {issue.get('dimension', '?')} @ {issue.get('location', '?')}\n"
            f"   问题：{issue.get('description', '?')}\n"
            f"   建议：{issue.get('suggestion', '?')}"
        )
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# 违规句定位
# ---------------------------------------------------------------------------

def triggered_patterns(issues: list[dict]) -> list[str]:
    """从问题清单中提取被触发的违规 pattern（只取 post-write 类）。"""
    pattern_map = {}
    for r in check_post_write.DEFAULT_FORBIDDEN:
        pattern_map[r["pattern"]] = r.get("description") or r.get("desc", "")
    for r in check_post_write.DEFAULT_RISK:
        pattern_map[r["pattern"]] = r.get("description") or r.get("desc", "")

    triggered = []
    for issue in issues:
        dim = issue.get("dimension", "")
        if not dim.startswith("post-write"):
            continue
        desc = issue.get("description", "")
        for pat in pattern_map:
            norm = pat.replace("(", "").replace(")", "")
            if norm in desc and pat not in triggered:
                triggered.append(pat)
    return triggered


def split_sentences(text: str) -> list[str]:
    parts = re.split(r"([。！？…]+)", text)
    sentences = []
    buffer = ""
    for p in parts:
        buffer += p
        if re.search(r"[。！？…]$", buffer):
            sentences.append(buffer.strip())
            buffer = ""
    if buffer.strip():
        sentences.append(buffer.strip())
    return [s for s in sentences if s.strip()]


SENT_END = "。！？…"


def expand_to_sentence(body: str, pos: int) -> str:
    """从位置 pos 向两侧扩展到最近句界，返回完整句（含结尾标点）。"""
    start = -1
    for ch in SENT_END:
        idx = body.rfind(ch, 0, pos)
        if idx > start:
            start = idx
    end = len(body)
    for ch in SENT_END:
        idx = body.find(ch, pos)
        if idx != -1 and idx < end:
            end = idx
    return body[start + 1:end + 1].strip()


def locate_offending_sentences(body: str, issues: list[dict]) -> list[dict]:
    """定位违规句：对每个违规词命中，取其所在完整句（句界扩展），去重保留原文顺序。"""
    patterns = triggered_patterns(issues)
    found = []
    for pat in patterns:
        for m in re.finditer(pat, body):
            sent = expand_to_sentence(body, m.start())
            if sent:
                found.append({"pattern": pat, "sentence": sent[:400]})
    seen = set()
    unique = []
    for f in found:
        if f["sentence"] not in seen:
            seen.add(f["sentence"])
            unique.append(f)
    return unique


def offending_count(body: str, patterns: list[str]) -> int:
    """统计 body 中所有违规 pattern 的总命中数。"""
    total = 0
    for pat in patterns:
        total += len(re.findall(pat, body))
    return total


# ---------------------------------------------------------------------------
# 句子级局部修订
# ---------------------------------------------------------------------------

def extract_json(text: str) -> dict | None:
    """容错提取 JSON（去代码块、去注释、截取第一个 {...}）。"""
    t = text.strip()
    if t.startswith("```"):
        t = re.sub(r"^```[a-zA-Z]*\n?", "", t)
        t = re.sub(r"\n?```$", "", t)
    start = t.find("{")
    end = t.rfind("}")
    if start == -1 or end == -1 or end <= start:
        return None
    t = t[start:end + 1]
    t = re.sub(r"//[^\n]*", "", t)
    t = re.sub(r",\s*([}\]])", r"\1", t)
    try:
        return json.loads(t)
    except json.JSONDecodeError:
        return None


def sentence_level_revise(body: str, offending: list[dict]) -> tuple[str, list[dict], list[dict]]:
    """
    句子级局部修订：让 LLM 逐句给出替换句，只替换违规句。
    返回 (修订后正文, 成功替换列表, 失败列表)。
    """
    if not offending:
        return body, [], []

    lines = []
    for i, f in enumerate(offending, 1):
        lines.append(f"{i}. 原句：{f['sentence']}")
    prompt = f"""你是中文小说修订编辑。下面列出了一章正文里的若干"违规句"，它们含有 AI 痕迹（突兀转折词 / 禁用句式等）。

请为每一句给出一个**修订版本**：
- 保留原句的语义、情节、人物与叙述顺序
- 消除违规模式（如"突然/忽然/猛然/猛地"等突兀转折词，或"不是…而是…"等 AI 句式）
- 用更具体的动作、感官细节或环境变化替代，不要简单换一个同义转折词
- 不要新增情节，不要删减信息
- 每句修订要自然融入原文语境

只输出 JSON，格式如下，不要输出其他任何内容：
{{"revisions": ["第1句的修订版", "第2句的修订版", "..."]}}

违规句清单：
{lines}"""

    messages = [
        {"role": "system", "content": "你是一个中文小说修订编辑。只输出 JSON。"},
        {"role": "user", "content": prompt + "\n\n/no_think"},
    ]
    raw = call_local_llm(messages)
    data = extract_json(raw)

    successes = []
    failures = []
    if not data or not isinstance(data.get("revisions"), list):
        return body, successes, [{"reason": "模型未返回有效 JSON", "raw": raw[:300]}]

    revs = data["revisions"]
    new_body = body
    for idx, f in enumerate(offending):
        if idx >= len(revs):
            failures.append({"sentence": f["sentence"], "reason": "模型漏了该句"})
            continue
        new_sent = str(revs[idx]).strip()
        old_sent = f["sentence"]
        if not new_sent or new_sent == old_sent:
            failures.append({"sentence": old_sent, "reason": "修订句为空或未变化"})
            continue
        # 用该句的 pattern 验证：新句是否已消除违规模式
        still_bad = re.search(f["pattern"], new_sent) is not None
        if still_bad:
            failures.append({"sentence": old_sent, "reason": f"修订句仍含违规模式 {f['pattern']}"})
            continue
        if old_sent not in new_body:
            failures.append({"sentence": old_sent, "reason": "原句在正文中未匹配到，无法替换"})
            continue
        new_body = new_body.replace(old_sent, new_sent, 1)
        successes.append({"old": old_sent, "new": new_sent})
    return new_body, successes, failures


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

def revise_chapter(chapter_id: str, target: int, max_rounds: int) -> dict:
    root = get_project_root()
    chapter_path = root / "chapters" / chapter_id / "chapter.md"
    if not chapter_path.exists():
        raise FileNotFoundError(f"未找到章节: {chapter_path}")

    original = read_text(chapter_path)
    original_body = check_post_write.strip_frontmatter_and_outline(original)

    issues = review_body(original_body, target)
    patterns = triggered_patterns(issues)
    actionable = [i for i in issues if i["severity"] in ("critical", "warning")]

    rounds_log = []
    best_text = original_body
    best_count = offending_count(original_body, patterns) + score_issues(issues)
    current_text = original_body
    current_count = best_count

    if not actionable:
        return {
            "chapter": chapter_id, "revised": False, "final_score": score_issues(issues),
            "final_issues": issues, "rounds": rounds_log, "target_words": target,
            "word_count": chinese_char_count(original_body),
            "note": "无 critical/warning 问题，无需修订",
        }

    print(f"[修订] {chapter_id} 有 {len(actionable)} 个待修订问题（违规 pattern {len(patterns)} 组）")

    for rnd in range(1, max_rounds + 1):
        offending = locate_offending_sentences(current_text, issues)
        if not offending:
            # 没有可定位的句子（如纯字数问题），做全文最小修订
            break
        print(f"[第{rnd}轮] 句子级修订：{len(offending)} 个违规句（违规计数 {current_count}）...")
        new_text, ok, fail = sentence_level_revise(current_text, offending)

        new_issues = review_body(new_text, target)
        new_count = offending_count(new_text, patterns) + score_issues(new_issues)
        rounds_log.append({
            "round": rnd,
            "before": current_count,
            "after": new_count,
            "word_count": chinese_char_count(new_text),
            "sentences_revised": len(ok),
            "sentences_failed": len(fail),
            "remaining_issues": len([i for i in new_issues if i["severity"] in ("critical", "warning")]),
        })

        if new_count < current_count and len(ok) > 0:
            best_text = new_text
            best_count = new_count
            current_text = new_text
            current_count = new_count
            issues = new_issues
            print(f"[第{rnd}轮] 修订有效：替换 {len(ok)} 句，违规计数 {current_count}（剩余待修 {rounds_log[-1]['remaining_issues']}）")
        else:
            print(f"[第{rnd}轮] 修订未改进（{new_count} >= {current_count}），回滚保留上一版")
            # 记录失败原因，下一轮换策略
            if not ok:
                print(f"  - 所有句子替换失败，改用全文最小修订")
                break

        if current_count == 0:
            print("[完成] 所有问题已清零")
            break

    # 若句子级修订无效，fallback 全文修订（一次性，最多 1 次）
    final_issues = review_body(best_text, target)
    if best_count != 0 and len(rounds_log) >= 1 and all(r["sentences_revised"] == 0 for r in rounds_log):
        print("[fallback] 句子级修订无效，尝试全文最小修订...")
        prompt = f"""你是中文小说修订编辑。自动审查发现以下问题。请对整章做**最小改动**修订：
- 只修改含问题的句子，其余内容一字不改
- 消除问题清单中的 AI 痕迹（突兀转折词、禁用句式等）
- 保留全部情节、人物、字数（约 {target} 字）
直接输出修订后的完整正文，不要解释。

## 问题清单
{format_issue_list(final_issues)}

## 正文
{best_text}"""
        try:
            raw = call_local_llm([
                {"role": "system", "content": "你是中文小说修订编辑。只输出修订后的正文。"},
                {"role": "user", "content": prompt + "\n\n/no_think"},
            ])
            fb_text = raw.strip()
            fb_issues = review_body(fb_text, target)
            fb_count = offending_count(fb_text, patterns) + score_issues(fb_issues)
            if fb_count < best_count:
                best_text = fb_text
                best_count = fb_count
                final_issues = fb_issues
                rounds_log.append({"round": "fallback", "before": best_count, "after": fb_count,
                                   "sentences_revised": -1, "sentences_failed": -1,
                                   "remaining_issues": len([i for i in fb_issues if i["severity"] in ("critical", "warning")])})
                print(f"[fallback] 全文修订有效：违规计数 {best_count}")
        except Exception as e:
            print(f"[fallback] 失败：{e}")

    # 仅在实际发生修订（内容变化）时备份原版，供对比/回滚
    if best_text != original_body:
        backup_dir = root / "outputs" / "backups"
        backup_dir.mkdir(parents=True, exist_ok=True)
        backup_path = backup_dir / f"{chapter_id}_original.md"
        if not backup_path.exists():
            write_text(backup_path, original)
            print(f"[备份] 原版已备份: {backup_path}")

    write_text(chapter_path, best_text)

    return {
        "chapter": chapter_id,
        "revised": best_count < offending_count(original_body, patterns) + score_issues(issues) if issues else False,
        "final_score": best_count,
        "final_issues": review_body(best_text, target),
        "rounds": rounds_log,
        "target_words": target,
        "word_count": chinese_char_count(best_text),
        "original_word_count": chinese_char_count(original_body),
    }


def write_revise_report(chapter_id: str, result: dict):
    root = get_project_root()
    lines = [
        "<!-- 自动修订报告（审查不通过自动修订闭环）-->",
        f"<!-- 生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} -->",
        "",
        f"# 自动修订报告: {chapter_id}",
        "",
        f"- 字数: {result['original_word_count']} → {result['word_count']} 字（目标 {result['target_words']}）",
        f"- 修订轮次: {len(result['rounds'])}",
        f"- 最终问题分: {result['final_score']}（0 = 全部清零）",
        "",
        "## 修订过程",
        "",
    ]
    if result["rounds"]:
        lines.append("| 轮次 | 修订前 | 修订后 | 字数 | 替换句数 | 失败句数 | 剩余待修 |")
        lines.append("|---|---|---|---|---|---|---|")
        for r in result["rounds"]:
            lines.append(
                f"| {r['round']} | {r['before']} | {r['after']} | {r['word_count']} | "
                f"{r['sentences_revised']} | {r['sentences_failed']} | {r['remaining_issues']} |"
            )
        lines.append("")
    else:
        lines.append("未触发修订（生成时即无待处理问题）。")
        lines.append("")

    lines.append("## 残留问题（如有）")
    lines.append("")
    remaining = [i for i in result["final_issues"] if i["severity"] in ("critical", "warning")]
    if remaining:
        for issue in remaining:
            sev = issue["severity"].upper()
            lines.append(f"### [{sev}] {issue['dimension']}")
            lines.append(f"- **位置**: {issue['location']}")
            lines.append(f"- **问题**: {issue['description']}")
            lines.append(f"- **建议**: {issue['suggestion']}")
            lines.append("")
    else:
        lines.append("无残留 critical/warning 问题。")

    report_path = root / "outputs" / "reports" / f"{chapter_id}_revise_report.md"
    write_text(report_path, "\n".join(lines))
    return report_path


def main():
    configure_utf8_stdio()
    parser = argparse.ArgumentParser(description="审查不通过自动修订闭环")
    parser.add_argument("--chapter", required=True, help="章节 ID，如 ch907")
    parser.add_argument("--target", type=int, default=3000, help="目标中文字数")
    parser.add_argument("--max-rounds", type=int, default=3, help="最大修订轮次，默认 3")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    args = parser.parse_args()

    ensure_dirs()
    result = revise_chapter(args.chapter.strip(), args.target, args.max_rounds)

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    print(f"\n===== 修订结果: {result['chapter']} =====")
    print(f"  字数: {result['original_word_count']} → {result['word_count']}（目标 {result['target_words']}）")
    print(f"  轮次: {len(result['rounds'])}")
    print(f"  最终问题分: {result['final_score']}")
    if result["final_score"] == 0:
        print("  结论: ✅ 问题已全部清零")
    elif result["revised"]:
        print("  结论: ⚠️ 已尽力修订，仍有残留问题（见报告）")
    else:
        print("  结论: ⏭️ 未触发修订")

    report_path = write_revise_report(result["chapter"], result)
    print(f"[完成] 修订报告已保存: {report_path}")


if __name__ == "__main__":
    main()
