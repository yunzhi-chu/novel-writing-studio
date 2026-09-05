#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
extend_chapter.py —— 章节字数兜底续写
当生成的章节未达到目标字数时，自动调用本地模型续写补足。

用法:
    python extend_chapter.py --chapter ch001 [--target 3000]
"""
import argparse
import os
import re
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))

from utils import get_llm_config, get_project_root, load_config, call_local_llm


def count_cjk(text: str) -> int:
    """统计中文字符数。"""
    return len(re.findall(r"[\u4e00-\u9fff]", text))


def build_extend_prompt(chapter_id: str, tail: str, current: int, target: int, remaining: int) -> str:
    return f"""你正在续写中文长篇小说第 {chapter_id} 章的正文。

【硬性要求】
- 本章总目标约 {target} 中文字，当前已写 {current} 字，还需约 {remaining} 字。
- 继续推进这一章的正文，展开场景描写、人物动作与对话、心理活动、环境氛围、情节起伏。
- 【禁止】现在就收尾、写总结、写"尾声/结尾"、重复已写过的内容。
- 只输出续写的正文本身，不要解释，不要写标题。

【已写内容的末尾（衔接点，从此处继续往下写）】
{tail}"""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--chapter", required=True)
    parser.add_argument("--target", type=int, default=3000)
    parser.add_argument("--min-ratio", type=float, default=0.95, help="达标比例，默认 0.95（目标 3000 字时约 2850 字）")
    parser.add_argument("--max-rounds", type=int, default=3, help="最多续写轮数")
    args = parser.parse_args()

    root = get_project_root()
    chapter_file = root / "chapters" / args.chapter / "chapter.md"
    if not chapter_file.exists():
        print(f"[错误] 章节不存在: {chapter_file}")
        sys.exit(1)

    cfg = load_config()
    threshold = int(args.target * args.min_ratio)
    rounds = 0
    final_cjk = count_cjk(chapter_file.read_text(encoding="utf-8"))

    while final_cjk < threshold and rounds < args.max_rounds:
        rounds += 1
        text = chapter_file.read_text(encoding="utf-8")
        tail = text[-500:]
        remaining = max(args.target - final_cjk, 1)
        prompt = build_extend_prompt(args.chapter, tail, final_cjk, args.target, remaining)
        print(f"[续写 {rounds}/{args.max_rounds}] 当前 {final_cjk} 字 < 目标 {args.target} 字，调用模型续写...")

        # 续写请求带更长输出额度
        extend = call_local_llm(
            [
                {"role": "system", "content": "你是中文长篇小说写手，只输出小说正文。"},
                {"role": "user", "content": prompt + "\n\n/no_think"},
            ],
            temperature=cfg.get("generation_temperature", 0.8),
            top_p=cfg.get("generation_top_p", 0.9),
            max_tokens=cfg.get("max_output_tokens", 4000),
        )
        if not extend or not extend.strip():
            print("[警告] 续写返回为空，停止。")
            break

        # 追加续写内容（去掉可能重复的衔接处）
        new_text = (text + "\n\n" + extend.strip()).strip()
        chapter_file.write_text(new_text + "\n", encoding="utf-8")
        final_cjk = count_cjk(chapter_file.read_text(encoding="utf-8"))
        print(f"[续写完成] 当前 {final_cjk} 字")

    print(f"[结果] 章节 {args.chapter} 最终约 {final_cjk} 中文字（目标 {args.target}）")
    if final_cjk < threshold:
        print(f"[提示] 未完全达标（已尽力续写 {rounds} 轮），可手动调整或再生成。")
    else:
        print("[结果] 字数达标 ✅")


if __name__ == "__main__":
    main()
