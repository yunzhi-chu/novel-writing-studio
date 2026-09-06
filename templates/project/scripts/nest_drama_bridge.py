#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================
# nest_drama_bridge.py —— NEST-DRAMA × Sodarie Novel 写作流桥接
#
# 把 NEST-DRAMA 群像推演引擎接入当前小说写作流：
#   1) 把 Sodarie Novel 的记忆库（story_bible / characters / outline /
#      foreshadowing / events / timeline / summaries / relationships / style_bank）
#       → 转换为 NEST-DRAMA 材料（文本）
#   2) 通过 NEST-DRAMA 本地 API 建世界 → 角色自主推演 → 导出「故事全录」
#   3) 故事全录落到 outputs/drama/，供 Codex 提炼分镜式 idea 后交给写手成章
#
# 用法（由 nest_drama_run.sh 包装调用，用项目 venv 运行）：
#   python nest_drama_bridge.py --sync                 # 记忆库 → 材料
#   python nest_drama_bridge.py --build ["需求"]       # 建世界
#   python nest_drama_bridge.py --simulate [N]         # 推演 N 轮（默认 4）
#   python nest_drama_bridge.py --export               # 导出故事全录
#   python nest_drama_bridge.py --run [N] ["需求"]     # 全流程：sync→build→simulate→export
#   python nest_drama_bridge.py --status               # 引擎/世界/进度状态
#
# 依赖：仅项目 venv（pyyaml 用于读记忆库 YAML；API 调用走标准库 urllib）。
# ============================================================
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None

# ---------- 路径与配置 ----------
NP = Path(__file__).resolve().parent.parent          # 小说项目根目录
MEM = NP / "memory"
OUTLINES = NP / "outlines"
NEST_DIR = Path(os.environ.get(
    "NEST_DIR",
    str(Path.home() / "nest-drama"),
))
NEST_PORT = int(os.environ.get("NEST_PORT", "8790"))
API = "http://127.0.0.1:%d" % NEST_PORT

# 模型接入（Bionic 启动的本地模型）
BASE_URL = os.environ.get("NEST_LLM_BASE_URL", "http://127.0.0.1:1234/v1")
MODEL = os.environ.get("NEST_LLM_MODEL", "qwen3.8-27b-uncensored-mlx")
API_KEY = os.environ.get("NEST_LLM_API_KEY", "sk-omlx-local")

OUT_DIR = NP / "outputs" / "drama"
STAGE_DIR = NEST_DIR / "材料"


def log(msg):
    print("[nest-drama桥 %s] %s" % (datetime.now().strftime("%H:%M:%S"), msg), flush=True)


# ---------- 记忆库 → 材料 ----------
def _lines(*items):
    """把 yaml/json 结构压成人类可读文本行。"""
    return list(items)


def _fmt_char(char):
    out = ["# %s" % char.get("name", "未命名")]
    for k in ("role", "identity", "personality", "speaking_style", "current_status"):
        v = char.get(k)
        if v:
            out.append("- %s：%s" % (k, v))
    for k in ("secrets", "knows", "relationships", "constraints"):
        v = char.get(k)
        if v:
            out.append("- %s：" % k)
            for it in v:
                out.append("  · %s" % it)
    return out


def _fmt_foreshadow(sec):
    out = []
    for fs in sec or []:
        out.append("- [%s] %s（%s｜相关：%s｜规划：%s）"
                   % (fs.get("id", "?"), fs.get("description", ""),
                      fs.get("status", ""), "、".join(fs.get("related_characters") or []),
                      fs.get("planned_resolution", "")))
    return out


def sync_materials():
    """把记忆库转成 NEST-DRAMA 材料文本，落盘到 NEST 材料目录，返回 (标题, 文件列表)。"""
    docs = []   # (文件名, 文本)

    # 01 世界观与写作规则
    if (MEM / "story_bible.yaml").exists() and yaml:
        sb = yaml.safe_load(open(MEM / "story_bible.yaml", encoding="utf-8")) or {}
        t = ["# 世界观与写作规则", "",
             "作品：《%s》｜题材：%s｜基调：%s" % (sb.get("title", ""), sb.get("genre", ""), sb.get("tone", "")),
             "", "## 世界规则"]
        t += ["- %s" % r for r in sb.get("world_rules") or []]
        t += ["", "## 写作规则"]
        t += ["- %s" % r for r in sb.get("writing_rules") or []]
        t += ["", "## 禁止模式"]
        t += ["- %s" % r for r in sb.get("forbidden_patterns") or []]
        docs.append(("01-世界观与写作规则.txt", "\n".join(t)))

    # 02 角色档案
    if (MEM / "characters.yaml").exists() and yaml:
        ch = yaml.safe_load(open(MEM / "characters.yaml", encoding="utf-8")) or {}
        t = ["# 角色档案", ""]
        for c in ch.get("characters") or []:
            t += _fmt_char(c)
            t.append("")
        docs.append(("02-角色档案.txt", "\n".join(t)))

    # 03 全书大纲
    if (OUTLINES / "book_outline.yaml").exists() and yaml:
        bo = yaml.safe_load(open(OUTLINES / "book_outline.yaml", encoding="utf-8")) or {}
        t = ["# 全书大纲", "",
             "书名：%s｜字数：%s｜题材：%s" % (bo.get("title", ""), bo.get("target_word_count", ""), bo.get("genre", "")),
             "", "一句话故事：%s" % bo.get("logline", ""),
             "", "核心主题：%s" % bo.get("core_theme", ""),
             "", "## 主线冲突"]
        mc = bo.get("main_conflict") or {}
        t += ["- 外部：%s" % mc.get("external", ""),
              "- 内部：%s" % mc.get("internal", ""),
              "- 情感：%s" % mc.get("emotional", "")]
        st = bo.get("structure") or {}
        for act, name in (("act1_setup", "第一幕·建置"), ("act2_confrontation", "第二幕·对抗"), ("act3_resolution", "第三幕·收束")):
            a = st.get(act) or {}
            if a:
                t += ["", "## %s（%s）" % (name, a.get("chapters", "")),
                      "- 功能：%s" % a.get("function", ""),
                      "- 关键转折：%s" % a.get("key_turning_point", "")]
        arcs = bo.get("major_arcs") or {}
        if arcs:
            t += ["", "## 主要人物弧光"]
            for k, v in arcs.items():
                t += ["- %s：起→%s｜中→%s｜终→%s" % (k, v.get("start", ""), v.get("middle", ""), v.get("end", ""))]
        if bo.get("ending_direction"):
            t += ["", "## 结局方向", bo.get("ending_direction")]
        docs.append(("03-全书大纲.txt", "\n".join(t)))

    # 04 伏笔
    if (MEM / "foreshadowing.yaml").exists() and yaml:
        fs = yaml.safe_load(open(MEM / "foreshadowing.yaml", encoding="utf-8")) or {}
        t = ["# 伏笔追踪", "", "## 未回收（active）"]
        t += _fmt_foreshadow(fs.get("active"))
        t += ["", "## 已回收（resolved）"]
        t += _fmt_foreshadow(fs.get("resolved"))
        docs.append(("04-伏笔.txt", "\n".join(t)))

    # 05 事件时间线
    ev = []
    tl = []
    for f, acc in ((MEM / "events.jsonl", ev), (MEM / "timeline.jsonl", tl)):
        if f.exists():
            for ln in f.read_text(encoding="utf-8").splitlines():
                ln = ln.strip()
                if ln.startswith("{"):
                    try:
                        acc.append(json.loads(ln))
                    except Exception:
                        pass
    t = ["# 已发生事件时间线", ""]
    # timeline 已含时序，按序输出
    for e in tl:
        t.append("- %s｜%s｜%s｜重要度%s" % (e.get("time", "?"), e.get("event_id", ""),
                                          e.get("description", ""), e.get("importance", "")))
    if ev:
        t += ["", "## 事件明细"]
        for e in ev:
            t.append("- %s：%s（%s｜%s）" % (e.get("event_id", "?"), e.get("description", ""),
                                            "、".join(e.get("characters") or []), e.get("type", "")))
    docs.append(("05-事件时间线.txt", "\n".join(t)))

    # 06 章节纪要
    cs = []
    if (MEM / "chapter_summaries.jsonl").exists():
        for ln in (MEM / "chapter_summaries.jsonl").read_text(encoding="utf-8").splitlines():
            ln = ln.strip()
            if ln.startswith("{"):
                try:
                    cs.append(json.loads(ln))
                except Exception:
                    pass
    t = ["# 既有章节纪要", ""]
    for c in cs:
        t.append("## %s" % c.get("chapter_id", "?"))
        t.append(c.get("chapter_summary", ""))
        t.append("")
    docs.append(("06-章节纪要.txt", "\n".join(t)))

    # 07 人物关系
    if (MEM / "relationships.json").exists():
        try:
            rel = json.loads((MEM / "relationships.json").read_text(encoding="utf-8"))
        except Exception:
            rel = {}
        t = ["# 人物关系图", ""]
        for e in rel.get("edges") or []:
            t.append("- %s → %s：%s｜%s" % (e.get("source", ""), e.get("target", ""),
                                            e.get("relation", ""), e.get("change", "")))
        docs.append(("07-人物关系.txt", "\n".join(t)))

    # 08 文风样例
    if (MEM / "style_bank.jsonl").exists():
        st2 = []
        for ln in (MEM / "style_bank.jsonl").read_text(encoding="utf-8").splitlines():
            ln = ln.strip()
            if ln.startswith("{"):
                try:
                    st2.append(json.loads(ln))
                except Exception:
                    pass
        t = ["# 文风样例（写作时模仿的笔调）", ""]
        for s in st2:
            t.append("## %s" % s.get("scene_type", "?"))
            t.append(s.get("text", ""))
            t.append("")
        docs.append(("08-文风样例.txt", "\n".join(t)))

    # 落盘到 NEST 材料目录（覆盖旧材料，保证每部作品独立成世界）
    STAGE_DIR.mkdir(parents=True, exist_ok=True)
    saved = []
    title = "桥下的人"
    # 优先从大纲取标题
    if (OUTLINES / "book_outline.yaml").exists() and yaml:
        bo = yaml.safe_load(open(OUTLINES / "book_outline.yaml", encoding="utf-8")) or {}
        if bo.get("title"):
            title = bo["title"]
    # 清掉旧的本次投放材料，避免旧世界材料混入新世界
    for old in STAGE_DIR.glob("*.txt"):
        try:
            old.unlink()
        except Exception:
            pass
    for fname, text in docs:
        fp = STAGE_DIR / fname
        fp.write_text(text, encoding="utf-8")
        saved.append(str(fp))
    log("已同步 %d 份记忆材料 → %s" % (len(saved), STAGE_DIR))
    return title, saved


# ---------- NEST-DRAMA API ----------
def _req(method, path, data=None, headers=None, timeout=300, ctype=None):
    url = API + path
    h = dict(headers or {})
    body = None
    if data is not None:
        if isinstance(data, (bytes, str)):
            body = data
            if ctype:
                h["Content-Type"] = ctype
        else:
            body = json.dumps(data).encode("utf-8")
            h.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, method=method, headers=h)
    with urllib.request.urlopen(req, data=body, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def _multipart(files, fields):
    """构造 multipart/form-data（files: [(文件名,文本)]，fields: dict）。"""
    boundary = "----nestbridge%d" % int(time.time() * 1000)
    buf = []
    for k, v in fields.items():
        buf.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n"
                    % (boundary, k, v)).encode("utf-8"))
    for fname, text in files:
        buf.append(("--%s\r\nContent-Disposition: form-data; name=\"files\"; filename=\"%s\"\r\n"
                    "Content-Type: text/plain\r\n\r\n" % (boundary, fname)).encode("utf-8"))
        buf.append(text.encode("utf-8"))
        buf.append(b"\r\n")
    buf.append(("--%s--\r\n" % boundary).encode("utf-8"))
    body = b"".join(buf)
    return body, "multipart/form-data; boundary=%s" % boundary


def build_world(requirement=""):
    title, files = sync_materials()
    req = requirement or ("让角色依据当前故事状态自主行动，推演故事下一拍。"
                          "重点是人物关系、伏笔与情感的自然发展；行为必须符合角色性格。")
    body, ctype = _multipart([(Path(f).name, Path(f).read_text(encoding="utf-8")) for f in files],
                             {"project_name": title, "simulation_requirement": req})
    try:
        r = _req("POST", "/api/graph/ontology/generate", data=body,
                 ctype=ctype, timeout=60)
    except Exception as e:
        log("建世界请求失败：%s" % e)
        return False
    log("建世界已提交：%s" % (r.get("data", r).get("project_name", "?")))
    # 轮询进度（本地 27B 稠密模型较慢，整局建世界可达 30-60 分钟，上限 90 分钟）
    deadline = time.time() + 5400
    while time.time() < deadline:
        time.sleep(8)
        try:
            st = _req("GET", "/api/graph/task/qx", timeout=30)
            d = st.get("data", {})
            status = d.get("status", "")
            if status == "completed":
                log("建世界完成：%s" % d.get("message", ""))
                return True
            if status == "failed":
                log("建世界失败：%s" % d.get("error", "未知原因"))
                return False
            log("建世界中：%s（%s%%）" % (d.get("message", ""), d.get("progress", "")))
        except Exception as e:
            log("轮询建世界异常：%s" % e)
    log("建世界超时（30 分钟）")
    return False


def simulate(rounds=6):
    # 基准轮：引擎 round 是全局累计（"可随时续跑"），用户要的 N 轮 = 从当前基准续跑 N 轮
    try:
        base_rnd = int(_req("GET", "/api/health", timeout=30).get("round", 0) or 0)
    except Exception as e:
        base_rnd = 0
        log("读取基准轮次失败（%s），按 round=0 计" % e)
    try:
        r = _req("POST", "/api/simulation/start", data={"max_rounds": rounds}, timeout=60)
    except Exception as e:
        log("启动推演失败：%s" % e)
        return False
    log("推演已启动（目标 %d 轮，从第 %d 轮续跑，预计止于第 %d 轮）：%s"
        % (rounds, base_rnd + 1, base_rnd + rounds, r.get("data") if isinstance(r, dict) else r))
    # 轮询：running=false 且 round>0 视为收束/结束
    deadline = time.time() + 7200
    last_round = 0
    stall = 0
    while time.time() < deadline:
        time.sleep(15)
        try:
            h = _req("GET", "/api/health", timeout=30)
            rnd = int(h.get("round", 0) or 0)
            running = bool(h.get("running"))
            phase = h.get("phase", "")
            if rnd != last_round:
                log("推演进行中：已到第 %d 轮｜阶段 %s" % (rnd, phase))
                last_round = rnd
                stall = 0
            else:
                stall += 1
            if not running and rnd > 0:
                log("推演结束：共 %d 轮（本轮 %d 轮）" % (rnd, rnd - base_rnd))
                return True
            if rnd >= base_rnd + rounds:
                # 保险丝：引擎未自停（自停通常先触发上面分支），主动停，避免多跑
                log("已达目标 %d 轮（round=%d 停止线 %d），主动停止…"
                    % (rounds, rnd, base_rnd + rounds))
                try:
                    _req("POST", "/api/simulation/stop", data={}, timeout=30)
                except Exception:
                    pass
                time.sleep(20)
                return True
            if not running and rnd == 0 and stall > 2:
                log("推演未产出轮次（可能未收束或无剧本），请人工查看：%s" % h)
                return False
            if stall > 80:  # 20 分钟无新轮且仍在 running（本地 27B 模型单轮可长达 10+ 分钟）
                log("推演疑似停滞，尝试停止…")
                try:
                    _req("POST", "/api/simulation/stop", data={}, timeout=30)
                except Exception:
                    pass
                time.sleep(20)
                return True
        except Exception as e:
            log("轮询推演异常：%s" % e)
    log("推演超时（2 小时）")
    return False


def export_story():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    try:
        r = _req("POST", "/cmd", data={"type": "export"}, timeout=60)
    except Exception as e:
        log("导出失败：%s" % e)
        return None
    if not r.get("ok"):
        log("导出失败：%s" % r.get("error", "未知"))
        return None
    name = r.get("name", "")
    dl = r.get("download", "/exports/%s" % urllib.parse.quote(name))
    try:
        txt = _req("GET", dl, timeout=60)
    except Exception:
        # download 可能是下载接口而非 json
        try:
            url = API + dl
            with urllib.request.urlopen(urllib.request.Request(url), timeout=120) as resp:
                txt = resp.read().decode("utf-8")
        except Exception as e:
            log("下载故事全录失败：%s" % e)
            return None
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    out = OUT_DIR / ("%s-%s.md" % (re.sub(r"[^\w\u4e00-\u9fff-]", "", name.replace("·故事全录.txt", "")), stamp))
    if isinstance(txt, dict):
        txt = json.dumps(txt, ensure_ascii=False, indent=2)
    out.write_text(txt if isinstance(txt, str) else str(txt), encoding="utf-8")
    log("故事全录已导出：%s（%d 字符）" % (out, len(str(txt))))
    return out


def status():
    try:
        h = _req("GET", "/api/health", timeout=20)
    except Exception as e:
        print("NEST-DRAMA 引擎未就绪：%s" % e)
        return
    print("引擎版本：%s｜运行态：%s｜轮次：%d｜单元：%s｜建世界：%s"
          % (h.get("version"), "推演中" if h.get("running") else "空闲",
             h.get("round", 0), h.get("unit", ""), "是" if h.get("built") else "否"))
    print("模型：%s @ %s" % (MODEL, BASE_URL))


def run(rounds, requirement):
    if not build_world(requirement):
        log("建世界失败，全流程中止")
        return 1
    if not simulate(rounds):
        log("推演未正常完成，仍尝试导出已有轮次")
    out = export_story()
    if out:
        log("== 全流程完成：故事全录 → %s ==" % out)
        return 0
    return 1


def main():
    ap = argparse.ArgumentParser(description="NEST-DRAMA × Sodarie 写作流桥接")
    ap.add_argument("--sync", action="store_true", help="记忆库 → 材料")
    ap.add_argument("--build", nargs="?", const="", help="建世界（可带推演需求）")
    ap.add_argument("--simulate", nargs="?", const=4, type=int, help="推演 N 轮（默认 4）")
    ap.add_argument("--export", action="store_true", help="导出故事全录")
    ap.add_argument("--run", nargs="?", const=4, type=int, help="全流程，N 轮（默认 4）")
    ap.add_argument("--requirement", default="", help="推演需求（可选）")
    ap.add_argument("--status", action="store_true", help="状态")
    a = ap.parse_args()

    if a.status:
        status(); return 0
    if a.sync:
        title, files = sync_materials()
        print("材料已就绪：%s（%d 份）" % (title, len(files)))
        return 0
    if a.build is not None:
        return 0 if build_world(a.requirement or a.build) else 1
    if a.simulate is not None:
        return 0 if simulate(a.simulate) else 1
    if a.export:
        return 0 if export_story() else 1
    if a.run is not None:
        return run(a.run, a.requirement)
    ap.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
