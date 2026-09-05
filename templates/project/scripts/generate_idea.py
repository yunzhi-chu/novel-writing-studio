#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
generate_idea.py —— 从 nest-drama 故事全录自动提炼「下一章分镜式 idea」

遵循 AGENTS.md「分镜式 idea 的写法」（导演视角：视觉主句 / 场景单元 / 章末钩子），
基于最新故事全录 + 全书大纲 + 角色当前状态，用本地模型（oMLX ornith）产出
可直接交给 write_chapter.sh 的分镜式 idea。

用法：
    python scripts/generate_idea.py                     # 从最新故事全录提炼
    python scripts/generate_idea.py --tail 30000        # 只读全录末尾 N 字符（默认 30000）
    python scripts/generate_idea.py --model Ornith-1.5-35B-A3B-MLX-8bit
"""
import argparse
import json
import os
import re
import sys
import urllib.request
import yaml


def _load_env_file() -> None:
    """直接跑 python 时也加载 ~/.novel/env 统一配置（已存在的变量不覆盖）。"""
    p = os.path.expanduser("~/.novel/env")
    if not os.path.exists(p):
        return
    try:
        with open(p, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, _, v = line.partition("=")
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))
    except Exception:
        pass


_load_env_file()

from datetime import datetime
from pathlib import Path

NP = Path(__file__).resolve().parent.parent          # 项目根
OUT_DIR = NP / "outputs" / "drama"
CHAPTERS_DIR = NP / "chapters"

BASE_URL = os.environ.get("NEST_LLM_BASE_URL", "http://127.0.0.1:8000/v1")
MODEL = os.environ.get("NEST_LLM_MODEL", "Ornith-1.5-35B-A3B-MLX-8bit")
API_KEY = os.environ.get("NEST_LLM_API_KEY", "sk-omlx-local")


def log(msg):
    print("[idea] %s" % msg, file=sys.stderr, flush=True)


def latest_drama():
    files = sorted(OUT_DIR.glob("*.md"), key=lambda p: p.stat().st_mtime)
    if not files:
        log("未找到故事全录，请先跑推演导出（./novel_pipeline.sh）")
        return None
    return files[-1]


def read_tail(path, tail_chars):
    txt = path.read_text(encoding="utf-8")
    if len(txt) <= tail_chars:
        return txt
    return txt[-tail_chars:]


def book_title() -> str:
    """从 story_bible 读书名（无则回退到大纲标题，再回退通用名）。"""
    for p in (NP / "memory" / "story_bible.yaml", NP / "outlines" / "book_outline.yaml"):
        try:
            if p.exists():
                d = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
                t = d.get("title")
                if t:
                    return str(t).strip()
        except Exception:
            pass
    return "未命名"



def outline_ctx():
    p = NP / "outlines" / "book_outline.yaml"
    if not p.exists():
        return ""
    txt = p.read_text(encoding="utf-8")
    # 保留前 120 行（标题/主题/主线/分幕结构/关键转折）
    return "\n".join(txt.splitlines()[:120])


def chars_ctx():
    p = NP / "memory" / "characters.yaml"
    if not p.exists():
        return ""
    txt = p.read_text(encoding="utf-8")
    return "\n".join(txt.splitlines()[:80])


def next_chapter_id():
    """从 chapters/ 推断下一个 chXXX-标题 编号"""
    nums = []
    if CHAPTERS_DIR.exists():
        for d in CHAPTERS_DIR.iterdir():
            if d.is_dir():
                m = re.match(r"ch(\d+)", d.name)
                if m:
                    nums.append(int(m.group(1)))
    nxt = (max(nums) + 1) if nums else 1
    return "ch%03d" % nxt


def call_llm(system, user, max_tokens=3000, timeout=300):
    url = BASE_URL.rstrip("/") + "/chat/completions"
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "temperature": 0.7,
        "max_tokens": max_tokens,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer %s" % API_KEY,
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    return data["choices"][0]["message"]["content"].strip()


IDEA_FORMAT = """分镜式 idea 的写法（导演视角，像拍电影一样规划章节）：
【视觉主句】一句能"拍下来"的画面变化，贯穿全章。
【场景1】地点·时间
- 叙述距离（景别）：特写/中景/远景
- 核心动作：谁做了什么（动作要有结束状态）
- 调度：人物站位/朝向/远近（传达权力与亲疏）
- 潜台词：表面在说什么 / 实际在讲什么
- 节奏：短句快切 or 长句缓推
- 声音：环境音/对话/静默
【场景2】...
【章末钩子】停在哪个画面/声音上（不要把话说尽）

要求：
- 只写画面、动作、调度、节奏、声音，不要写"机位/镜头术语"
- 场景单元 2-4 个，每个要点一句话
- 与故事全录最新进展紧密衔接（延续刚推演出的剧情）
- 符合本书文风与人物性格，不偏离既有伏笔与禁忌
- 输出第一行写标题：【标题】一句话标题（简短、与内容对应）；不要自行编写 chXXX 章节编号（由系统分配）"""


def main():
    global MODEL
    ap = argparse.ArgumentParser()
    ap.add_argument("--tail", type=int, default=30000)
    ap.add_argument("--model", default=MODEL)
    args = ap.parse_args()
    MODEL = args.model

    drama = latest_drama()
    if drama is None:
        return 1
    log("故事全录：%s" % drama.name)

    tail_txt = read_tail(drama, args.tail)
    outl = outline_ctx()
    chrs = chars_ctx()
    cid = next_chapter_id()
    log("模型：%s｜建议章节 ID：%s-标题（可改）" % (MODEL, cid))

    system = (
        "你是长篇现实主义小说《%s》的策划导演兼编剧。"
        "你从群像推演产出的故事全录里，挑出'有戏、可拍'的片段，"
        "为下一章做导演级分镜规划。只输出分镜式 idea 本身，不要解释。"
        "\n\n【写作系统规则 · WRITING_SYSTEM.md】（规划 idea 时遵守）"
        "\n- 对话字面留白：只规划能写出的字面台词，不规划旁白式心理剖白，不用情绪定性提示语。"
        "\n- 禁崩线：女配不雌竞、正宫稳定、主角不越界养鱼、反派不降智、系统不跳阶。"
        "\n- 感情线守雷 1：涉及独处场景必须来自客观公事（突发事故/既定排班/他人离场），禁止制造人为独处。"
        "\n- 文风：多闲笔、允许平淡留白、拒绝全程高能；转折必须有前置铺垫；性格变化有事件链。"
    ) % book_title()
    user = "\n".join([
        "【全书大纲】\n" + outl,
        "",
        "【角色当前状态】\n" + chrs,
        "",
        "【故事全录（最新推演）】\n" + tail_txt,
        "",
        "请为下一章提炼分镜式 idea（章节标题要简短、与内容对应，格式 chXXX-标题）。",
        IDEA_FORMAT,
    ])

    log("提炼中（可能需 1-2 分钟）…")
    idea = call_llm(system, user)
    # 提取标题（第一行【标题】xxx），编号由脚本按实际进度分配
    title = ""
    m = re.search(r"【标题】\s*(.+)", idea.splitlines()[0] if idea else "")
    if m:
        title = m.group(1).strip().strip("[]（）() ")
    if not title:
        title = "无题"
    chapter_id = "%s-%s" % (cid, title)
    log("完成。分镜式 idea 如下：\n")
    print(idea)
    print("\n[idea] 建议成章命令：", file=sys.stderr)
    print("  ./write_chapter.sh %s \"<上面的 idea>\" 3000" % chapter_id, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
