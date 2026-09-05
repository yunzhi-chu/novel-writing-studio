# 🖋️ AI 小说写作工作台

[![Download v1.0.0](https://img.shields.io/badge/Download%20v1.0.0-2ea44f?style=for-the-badge&logo=github&logoColor=white)](https://github.com/yunzhi-chu/novel-writing-studio/releases/tag/v1.0.0)
[![Release](https://img.shields.io/github/v/release/yunzhi-chu/novel-writing-studio?style=flat-square&label=最新版本)](https://github.com/yunzhi-chu/novel-writing-studio/releases)

> 一条命令，在你自己电脑上搭起一个「导演 + 写手」的 AI 小说工作室。
> 角色自主推演剧情 → 自动提炼分镜 → 本地大模型成章（每章约 3000 字）→ 创作看板自动更新。

**全程本地运行，不需要联网 API，不花钱，隐私在自己电脑里。**

## ⏩ 快速开始（新手 3 步）

```bash
# 1. 下载本项目
git clone https://github.com/yunzhi-chu/novel-writing-studio.git
cd novel-writing-studio

# 2. 一键安装（自动检测系统：macOS 芯片用 oMLX，其他用 Ollama）
bash install.sh        # 完整安装（含下载约 70GB 模型，需 0.5-2 小时）

# 3. 开始写第一章
cd ~/novel-project
./write_chapter.sh ch001-标题 "一句话 idea" 3000
```

> 第一次上手请跟着 **[`GETTING_STARTED.md`](GETTING_STARTED.md)**（从零开始的新故事 Check 清单）一步步打勾。
> 各系统差异与常见问题见下文。

---

## ✨ 它能做什么

| 你想要 | 你做什么 | 它做什么 |
|---|---|---|
| 写一章 | 给一句话想法 | 自动生成 3000 字正文，自动续写补足、查设定冲突、审查修订、更新记忆、刷新看板、同步到桌面 |
| 剧情走向没想好 | 说"让角色自己演" | nest-drama 引擎让角色按各自性格自主推演几轮，导出「故事全录」 |
| 从推演到成章一条龙 | 跑一条命令 | 推演 → 自动提炼分镜 idea → 直接成章 |
| 换新故事 | 改 3 个记忆文件 | 从零开始新书的写作循环 |

## 🖥️ 支持的系统（自动适配，无需手动选）

| 系统 | 推理后端 | 模型格式 | 推荐度 |
|---|---|---|---|
| **macOS（Apple Silicon M1-M4）** | oMLX | MLX | ⭐ 最优（安装脚本自动选） |
| **macOS（Intel）** | Ollama | GGUF | 可用（较慢） |
| **Windows（WSL2 / Ubuntu）** | Ollama | GGUF | 可用（NVIDIA 显卡加速） |
| **Linux** | Ollama | GGUF | 可用（NVIDIA/AMD 显卡加速） |
| Windows 原生（非 WSL） | — | — | 请装 WSL2 后再跑 |

**安装脚本会检测你的系统，自动选好后端**（macOS 芯片 → oMLX；其他 → Ollama）。

## ⚙️ 你需要什么（硬件门槛，先看清）

- **内存 64GB+**（推荐；两个 35B 大模型各占约 34GB）
- **磁盘约 120GB 空闲**（两个模型约 70GB）
- Mac 用户：2020 年后 Apple Silicon 最佳；Intel Mac 也能装（用 Ollama，速度慢一些）
- Windows 用户：先装 WSL2（`wsl --install`，PowerShell 里运行一次）
- Linux 用户：装好 Ollama（`curl -fsSL https://ollama.com/install.sh | sh`）

> 内存 16-32GB 也能装，但跑不动 35B 模型，需在 oMLX 应用里改选更小的模型。

---

## 🚀 三步安装

### 第 1 步：把本文件夹放到 Mac 上
把这个 `starter` 文件夹拷贝到你的 Mac（U 盘 / 微信文件传输 / iCloud 都行）。

### 第 2 步：打开「终端」

| 你的系统 | 怎么打开终端 |
|---|---|
| Mac | `Command + 空格` → 输入 `终端` 回车 |
| Windows（装了 WSL2） | 开始菜单搜 `Ubuntu`，打开它（这是 Linux 终端） |
| Linux | `Ctrl + Alt + T` |

输入下面命令，进入文件夹：

```bash
cd ~/Downloads/starter        # 如果你放在"下载"里；放到哪就 cd 到哪
```

> 💡 Windows 用户：WSL2 里访问你下载的文件夹，路径类似
> `/mnt/c/Users/你的用户名/Downloads/starter`，直接 `cd /mnt/c/Users/你的用户名/Downloads/starter` 即可。

### 第 3 步：一键安装

```bash
bash install.sh
```

脚本会自动完成：
1. 检测你的系统，自动选择后端（macOS 芯片→oMLX；其他→Ollama）
2. 检查你的内存 / 磁盘是否够
3. 安装 / 启动模型服务（统一端口 :8000）
4. 下载两个大模型（约 70GB，需 0.5-2 小时，中途可离开）
5. 安装 nest-drama 推演引擎（纯 Python，全平台通用）
6. 生成你的小说项目（`~/novel-project`）
7. 自检

看到 **「✅ 安装完成！」** 就装好了。

> 💡 网络慢 / 想用图形界面下模型：`bash install.sh --skip-models`。
> Mac 用 oMLX 应用界面下载模型；其他系统在 Ollama 界面或命令行 `ollama pull 模型名` 下载。

---

## ✍️ 开始写你的第一本书

> **第一次上手？直接跟着 `GETTING_STARTED.md`（从零开始的新故事 Check 清单）一步步打勾就行。**

### 1. 告诉系统你的故事设定（只需 3 个文件，都是"填空"模板）

打开终端，编辑项目里的记忆文件（也可以让 AI 帮你填）：

```bash
cd ~/novel-project
open memory/story_bible.yaml      # 世界观：标题、基调、世界规则
open memory/characters.yaml       # 人物：主角、配角、秘密
open outlines/book_outline.yaml   # 大纲：故事简介、三幕结构
```

### 2. 用 AI 导演规划章节（推荐：豆包/Codex）

把 `~/novel-project/AGENTS.md` 的内容交给 AI 助手（比如豆包），说"你是这部小说的导演"，
AI 会按工作流：先给你计划 → 你确认 → 它调本地模型写章节。

### 3. 或者直接手动写一章

```bash
cd ~/novel-project
./write_chapter.sh ch001-雨夜书店 "主角在雨夜误入一家午夜书店" 3000
```

等几分钟，`chapters/ch001-雨夜书店/chapter.md` 就生成了，桌面 `小说章节` 文件夹也能看到。

---

## 🎬 高级：让角色自主推演剧情

不知道该往哪写时，让角色自己"演"出来：

```bash
cd ~/novel-project

./novel_flow.sh                    # 推演 6 轮 → 自动提炼分镜 idea → 停下给你审
./novel_flow.sh --go               # 全自动：推演 → 提炼 idea → 直接成章
./novel_flow.sh --skip-simulate --go   # 跳过推演，用已有全录提炼并成章（最快）
./novel_flow.sh 4                  # 指定推演 4 轮
```

### 其他常用命令

```bash
./nest_drama_run.sh status         # 推演引擎状态
./novel_pipeline.sh 6              # 只跑推演链：同步→建世界→推演→导出故事全录
./sync_sodarie.sh                  # 手动同步章节到 Sodarie Novel GUI
```

---

## 📁 目录结构

```
~/novel-project/
├── AGENTS.md                # AI 导演工作流说明书（交给 AI 助手用）
├── novel_flow.sh            # 整体编排：推演→idea→成章 一条龙
├── novel_pipeline.sh        # 一键推演链
├── nest_drama_run.sh        # 推演引擎入口（sync/build/simulate/export）
├── write_chapter.sh         # 成章入口（自动完成全流程）
├── memory/                  # 长期记忆（世界观/人物/伏笔/文风）
├── outlines/                # 全书大纲
├── chapters/                # 每章一个文件夹（chapter.md）
├── outputs/                 # 报告、备份、故事全录
├── charts/                  # 创作看板（自动刷新）
└── scripts/                 # 内部脚本（不用动）
```

---

## ❓ 常见问题

**Q：安装卡在"下载模型"？**
A：网速问题。可 Ctrl+C 中断，改跑 `bash install.sh --skip-models`，再用图形界面（Mac 的 oMLX / 其他系统的 Ollama）下载模型。

**Q：Windows 怎么装？**
A：先装 WSL2：在 PowerShell 里运行 `wsl --install`，重启进 Ubuntu，然后把 `starter` 文件夹放进 WSL（如 `/mnt/c/Users/你的用户名/Downloads/starter`），再 `bash install.sh` 即可。脚本会走 Ollama 分支。

**Q：macOS Intel / Linux 用的模型和 Mac 芯片版一样吗？**
A：功能一样，格式不同。Mac 芯片用 MLX 格式（oMLX 加载）；Intel/Linux/Windows 用 GGUF 格式（Ollama 加载）。脚本已按系统配好模型名，你不需要关心格式。

**Q：`write_chapter.sh` 报错说找不到模型？**
A：确认模型服务已启动（Mac 打开 oMLX 应用；其他系统确认 Ollama 在运行），并且两个模型都下载完成。`~/novel-project` 下的 `./nest_drama_run.sh status` 会告诉你模型状态。配置在 `~/.novel/env` 里可改。

**Q：一定要装 Sodarie Novel 吗？**
A：不必须。它是可选的可视化阅读界面；没有它，章节照样生成在 `chapters/` 和桌面。

**Q：换一台电脑怎么迁移？**
A：把 `~/novel-project` 拷走（模型需重新下载），到新机器跑 `bash install.sh`，再把项目文件夹覆盖回 `~/novel-project` 即可。换了系统（如 Mac→Windows）也没关系，模型名脚本会自动配好。

**Q：换一个故事？**
A：清空 `memory/` 和 `outlines/` 里的内容（用模板重填），或新建一个项目文件夹，把 `templates/project` 复制一份改名。

---

## 🏗️ 架构速览

```
                你（用户）
                 │ 想法/确认
                 ▼
          AI 导演（Codex/豆包）
                 │ 分镜 idea（AGENTS.md 工作流）
                 ▼
          ┌────────────────────────────────────┐
          │  本地模型服务（OpenAI 兼容 :8000）    │
          │   ├─ 写作模型 Qwen3.6-35B → 成章    │
          │   └─ 推演模型 Ornith-35B  → 推演/idea│
          │  （macOS 芯片用 oMLX；其他用 Ollama） │
          └────────────────────────────────────┘
                 ▲            │
      nest-drama 引擎(:8790)    │
      角色自主推演 → 故事全录     │
                 └────────────┘
          章节 → 记忆更新 → 看板 → 桌面/GUI
```

---

*遇到问题先看本页，解决不了把终端报错截图给 AI 助手，它能帮你诊断。*
