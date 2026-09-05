#!/bin/bash
# ============================================================
# install.sh —— 多系统一键安装：AI 小说写作工作台
#
# 在三种系统上自动搭起整套写作工作台：
#   本地模型服务 + 两个大模型 + nest-drama 推演引擎 + 小说项目骨架
#
# 系统适配（自动检测，无需手动选）：
#   macOS Apple Silicon (M1/M2/M3/M4)  → oMLX  + MLX 模型
#   macOS Intel                        → Ollama + GGUF 模型
#   Linux / WSL2 (Windows)             → Ollama + GGUF 模型
#   Windows 原生（非 WSL）              → 提示安装 WSL2
#
# 用法：
#   bash install.sh                 # 完整安装（推荐）
#   bash install.sh --skip-models   # 跳过模型下载（想用图形界面下载时）
#   bash install.sh --smoke-test    # 装完立即用写作模型生成一句话验证（首次加载较慢）
#   bash install.sh --help
#
# 需要：64GB+ 内存、约 120GB 磁盘
# ============================================================
set -uo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
TPL="${SELF_DIR}/templates/project"
MODEL_DIR="${MODEL_DIR:-$HOME/lmstudio/models}"
NEST_DIR="${NEST_DIR:-$HOME/nest-drama}"
PROJECT_DIR="${PROJECT_DIR:-$HOME/novel-project}"
ENV_FILE="$HOME/.novel/env"

SKIP_MODELS=0; SMOKE=0
for a in "$@"; do
  case "$a" in
    --skip-models) SKIP_MODELS=1;;
    --smoke-test)  SMOKE=1;;
    --help) sed -n '1,32p' "$0" | grep '^#' | sed 's/^# \?//'; exit 0;;
  esac
done

say()  { echo ""; echo "────────────────────────────────────────────"; echo "▶ $1"; }
ok()   { echo "  ✓ $1"; }
warn() { echo "  ⚠ $1"; }
die()  { echo "  ✗ $1" >&2; exit 1; }

echo "============================================================"
echo " AI 小说写作工作台 · 多系统一键安装"
echo "============================================================"

# ---------- 0. 系统检测 ----------
UNAME_S="$(uname -s)"
case "$UNAME_S" in
  Darwin) OS_OS="macOS"; OS_ARCH="$(uname -m)";;
  Linux)  OS_OS="Linux"; OS_ARCH="$(uname -m)"
          grep -qi microsoft /proc/version 2>/dev/null && OS_OS="WSL2";;
  MINGW*|MSYS*|CYGWIN*|Windows_NT) OS_OS="Windows"; OS_ARCH="x86_64";;
  *) OS_OS="Unknown"; OS_ARCH="$(uname -m)";;
esac

say "步骤 0/8：检查系统（检测到：$OS_OS / ${OS_ARCH}）"
if [ "$OS_OS" = "Windows" ]; then
  die "检测到 Windows 原生环境。请先安装 WSL2（Ubuntu），然后在 WSL 终端里重跑本脚本：\n    wsl --install    （PowerShell 里运行一次，重启后进 Ubuntu）\n    bash install.sh"
fi
if [ "$OS_OS" = "Unknown" ]; then
  die "无法识别系统，暂不支持。"
fi

# 内存 / 磁盘（两种后端都需要大内存）
MEM_GB=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024/1024)}')
[ -z "$MEM_GB" ] && MEM_GB=$(free -g 2>/dev/null | awk '/Mem:/{print $2}')
[ -z "$MEM_GB" ] && MEM_GB=0
if [ "$MEM_GB" -ge 64 ]; then ok "内存 ${MEM_GB}GB ✓"; else warn "内存仅 ${MEM_GB}GB（推荐 64GB+，两个 35B 模型较吃内存）"; fi
DFREE=$(df -h "$HOME" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'T')
ok "磁盘：${DFREE}T 可用"

# 决定后端
if [ "$OS_OS" = "macOS" ] && [ "$OS_ARCH" = "arm64" ]; then
  BACKEND="omlx";  ok "后端：oMLX（MLX 模型，Apple Silicon 最优）"
else
  BACKEND="ollama"; ok "后端：Ollama（GGUF 模型，跨平台）"
fi

# ---------- 1. 安装推理后端 ----------
say "步骤 1/8：安装模型服务（${BACKEND}）"
if [ "$BACKEND" = "omlx" ]; then
  if command -v brew >/dev/null 2>&1; then ok "brew 已装"; else die "请先安装 Homebrew 后重跑：\n    /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""; fi
  if command -v omlx >/dev/null 2>&1; then ok "oMLX 已装（$(omlx --version 2>/dev/null | tail -1)）"; else
    echo "  安装 oMLX（约 1-2 分钟）…"
    brew tap jundot/omlx https://github.com/jundot/omlx 2>/dev/null || true
    brew install jundot/omlx/omlx || die "oMLX 安装失败。备选：https://github.com/jundot/omlx/releases 下载 .dmg"
    ok "oMLX 已安装"
  fi
else
  if command -v ollama >/dev/null 2>&1; then
    ok "Ollama 已装（$(ollama --version 2>/dev/null | head -1)）"
  elif [ -x "$HOME/bin/ollama" ] || [ -x "$HOME/.local/bin/ollama" ]; then
    export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
    ok "Ollama 便携版已存在（~/.local/bin 或 ~/bin）"
  else
    say "  Ollama 未安装，尝试自动安装便携版（免 sudo）…"
    mkdir -p "$HOME/bin"
    if [ "$OS_OS" = "macOS" ]; then
      curl -fsSL -o /tmp/ollama.tgz "https://ollama.com/download/ollama-darwin.tgz" 2>/dev/null || true
    else
      curl -fsSL -o /tmp/ollama.tgz "https://ollama.com/download/ollama-linux-amd64.tgz" 2>/dev/null || true
    fi
    if [ -s /tmp/ollama.tgz ]; then
      tar -xzf /tmp/ollama.tgz -C "$HOME/bin" 2>/dev/null && chmod +x "$HOME/bin/ollama" 2>/dev/null && export PATH="$HOME/bin:$PATH" && ok "Ollama 已装到 ~/bin（免 sudo）"
    fi
    if ! command -v ollama >/dev/null 2>&1; then
      warn "自动安装失败。请手动安装后重跑本脚本："
      warn "  macOS Intel：brew install ollama"
      warn "  Linux/WSL：  curl -fsSL https://ollama.com/install.sh | sh"
    fi
  fi
fi

# ---------- 2. 启动后端（统一 API 端口 :8000） ----------
say "步骤 2/8：启动模型服务（:8000）"
if [ "$BACKEND" = "omlx" ]; then
  omlx start --timeout 120 2>&1 | tail -1 || warn "oMLX 启动失败，可手动打开 oMLX 应用"
  sleep 3
else
  # Ollama 默认 11434，这里统一成 8000 以便项目脚本零改动
  echo 'export OLLAMA_HOST=127.0.0.1:8000' >> "$HOME/.bashrc" 2>/dev/null
  echo 'export OLLAMA_HOST=127.0.0.1:8000' >> "$HOME/.zshrc" 2>/dev/null
  if ! curl -s -m 3 "http://127.0.0.1:8000" >/dev/null 2>&1; then
    pkill -f "ollama serve" 2>/dev/null || true
    sleep 1
    OLLAMA_HOST=127.0.0.1:8000 nohup ollama serve >/dev/null 2>&1 &
    sleep 3
  fi
fi
curl -s -m 5 "http://127.0.0.1:8000" >/dev/null 2>&1 && ok "模型服务已就绪（:8000）" || warn "服务端口未就绪，稍后自检会再确认"

# ---------- 3. 下载模型 ----------
if [ "$SKIP_MODELS" = "1" ]; then
  say "步骤 3/8：跳过模型下载（--skip-models）"
  if [ "$BACKEND" = "omlx" ]; then
    warn "请用 oMLX 应用下载：Ornith-1.5-35B-A3B-MLX-8bit（推演）、Qwen3.6-35B-A3B-MLX-8bit（写作）"
  else
    warn "请手动下载两个模型："
    warn "  ollama pull hf.co/ornith-ai/Ornith-1.5-35B-A3B-GGUF"
    warn "  ollama pull lmstudio-community/Qwen3.6-35B-A3B-GGUF"
  fi
else
  say "步骤 3/8：下载两个大模型（各约 35GB，共约 70GB，视网速 0.5-2 小时）"
  if [ "$BACKEND" = "omlx" ]; then
    mkdir -p "$MODEL_DIR"
    python3 -m pip install --user -q huggingface_hub 2>/dev/null || die "安装下载工具失败，检查网络后重试"
    DL() { python3 - "$1" "$2" <<'PYEOF'
import sys
from huggingface_hub import snapshot_download
repo, out = sys.argv[1], sys.argv[2]
print("  …… %s → %s" % (repo, out))
snapshot_download(repo_id=repo, local_dir=out)
print("  ✓ %s 完成" % repo)
PYEOF
    }
    echo "  ① 推演模型 ornith（约 35GB）…"
    if [ -f "$MODEL_DIR/ornith-ai/Ornith-1.5-35B-A3B-MLX-8bit/config.json" ]; then
      ok "推演模型已存在，跳过下载"
    else
      DL ornith-ai/Ornith-1.5-35B-A3B-MLX-8bit "$MODEL_DIR/ornith-ai/Ornith-1.5-35B-A3B-MLX-8bit" 2>&1 | tail -2 || warn "推演模型下载失败（可重跑 --skip-models 用 oMLX 应用下载）"
    fi
    echo "  ② 写作模型 Qwen3.6（约 35GB）…"
    if [ -f "$MODEL_DIR/lmstudio-community/Qwen3.6-35B-A3B-MLX-8bit/config.json" ]; then
      ok "写作模型已存在，跳过下载"
    else
      DL lmstudio-community/Qwen3.6-35B-A3B-MLX-8bit "$MODEL_DIR/lmstudio-community/Qwen3.6-35B-A3B-MLX-8bit" 2>&1 | tail -2 || warn "写作模型下载失败（可重跑 --skip-models 用 oMLX 应用下载）"
    fi
  else
    echo "  ① 推演模型 ornith（约 35GB）…"
    ollama pull hf.co/ornith-ai/Ornith-1.5-35B-A3B-GGUF 2>&1 | tail -2 || warn "推演模型下载失败（可重跑 --skip-models 手动 ollama pull）"
    echo "  ② 写作模型 Qwen3.6（约 35GB）…"
    ollama pull lmstudio-community/Qwen3.6-35B-A3B-GGUF 2>&1 | tail -2 || warn "写作模型下载失败（可重跑 --skip-models 手动 ollama pull）"
  fi
  ok "模型下载完成（或已给出失败提示）"
fi

# ---------- 4. nest-drama 引擎 ----------
say "步骤 4/8：安装 nest-drama 推演引擎（纯 Python，跨平台）"
if [ -d "$NEST_DIR/.git" ]; then
  ok "已存在 $NEST_DIR"
else
  git clone --depth 1 https://github.com/63435212cwu-ops/nest-drama.git "$NEST_DIR" 2>&1 | tail -2 || die "clone nest-drama 失败（检查网络）"
  ok "已 clone 到 $NEST_DIR"
fi

# ---------- 5. 展开小说项目骨架 ----------
say "步骤 5/8：初始化小说项目（${PROJECT_DIR}）"
if [ -d "$PROJECT_DIR" ]; then
  warn "$PROJECT_DIR 已存在，跳过展开（如需重置请先手动删除）"
else
  cp -R "$TPL" "$PROJECT_DIR"
  mkdir -p "$PROJECT_DIR/chapters" "$PROJECT_DIR/outputs" "$PROJECT_DIR/charts" "$PROJECT_DIR/config"
  chmod +x "$PROJECT_DIR"/*.sh 2>/dev/null
  ok "项目骨架已生成"
fi

say "  准备 Python 运行环境（venv + pyyaml）…"
python3 -m venv "$PROJECT_DIR/scripts/.venv" 2>/dev/null || warn "创建 venv 失败（Linux/WSL 可先装：sudo apt install python3-venv，再重跑）"
if [ -x "$PROJECT_DIR/scripts/.venv/bin/pip" ]; then
  "$PROJECT_DIR/scripts/.venv/bin/pip" install -q pyyaml 2>/dev/null && ok "依赖就绪" || warn "pyyaml 安装失败（可手动装）"
fi

# ---------- 6. 生成配置（按后端写模型名） ----------
say "步骤 6/8：生成配置（~/.novel/env）"
mkdir -p "$HOME/.novel"
if [ ! -f "$ENV_FILE" ]; then
  if [ "$BACKEND" = "omlx" ]; then
    cat > "$ENV_FILE" <<EOF
# AI 小说写作工作台 · 本地模型配置（后端：oMLX）
# 若 oMLX 应用里设置了自定义 API Key，把下面的 Key 换成你的
LLM_BACKEND="omlx"
LLM_API_KEY="sk-omlx-local"
NEST_LLM_API_KEY="sk-omlx-local"
LLM_MODEL="Qwen3.6-35B-A3B-MLX-8bit"
NEST_LLM_MODEL="Ornith-1.5-35B-A3B-MLX-8bit"
EOF
  else
    cat > "$ENV_FILE" <<EOF
# AI 小说写作工作台 · 本地模型配置（后端：Ollama）
# 若换了其他 GGUF 模型，把下面的模型名改成你的 ollama tag
LLM_BACKEND="ollama"
LLM_API_KEY="ollama"
NEST_LLM_API_KEY="ollama"
LLM_MODEL="lmstudio-community/Qwen3.6-35B-A3B-GGUF"
NEST_LLM_MODEL="hf.co/ornith-ai/Ornith-1.5-35B-A3B-GGUF"
EOF
  fi
fi
ok "配置已生成：$ENV_FILE"

# ---------- 7. 自检 ----------
say "步骤 7/8：自检"
curl -s -m 5 "http://127.0.0.1:8000" >/dev/null 2>&1 && ok "模型服务 ✓" || warn "模型服务未响应（模型未下完属正常）"
if (cd "$PROJECT_DIR" && ./nest_drama_run.sh status >/dev/null 2>&1); then
  ok "nest-drama 引擎可启动 ✓"
else
  warn "nest-drama 引擎未就绪（等模型就绪后：cd $PROJECT_DIR && ./nest_drama_run.sh status）"
fi

# ---------- 8. 冒烟测试（可选） ----------
if [ "$SMOKE" = "1" ]; then
  say "冒烟测试：用写作模型生成一句话验证（首次加载 35B 模型约 1-3 分钟，请耐心）"
  WMODEL=$(grep "^LLM_MODEL=" "$ENV_FILE" 2>/dev/null | cut -d'"' -f2)
  [ -z "$WMODEL" ] && WMODEL="${LLM_MODEL:-}"
  K=$(grep "^LLM_API_KEY=" "$ENV_FILE" 2>/dev/null | cut -d'"' -f2)
  [ -z "$K" ] && K="sk-omlx-local"
  R=$(curl -s -m 300 "http://127.0.0.1:8000/v1/chat/completions" \
    -H "Content-Type: application/json" -H "Authorization: Bearer $K" \
    -d "{\"model\":\"$WMODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"只回复两个字：你好\"}],\"max_tokens\":16}" 2>/dev/null)
  if echo "$R" | grep -q "你好"; then
    ok "冒烟测试通过：模型已能正常生成 ✓"
  else
    warn "冒烟测试未通过（模型仍在加载或未就绪）。稍后跑 ~/novel-project/doctor.sh 复查"
  fi
fi

# ---------- 9. 结束语 ----------
say "完成！"
echo ""
echo "============================================================"
echo " ✅ 安装完成！系统：$OS_OS · 后端：$BACKEND"
echo ""
echo "  0. 体检一下（推荐，30 秒）：cd $PROJECT_DIR && ./doctor.sh"
echo ""
echo "  1. 写故事设定（3 个填空模板）："
echo "     $PROJECT_DIR/memory/story_bible.yaml"
echo "     $PROJECT_DIR/memory/characters.yaml"
echo "     $PROJECT_DIR/outlines/book_outline.yaml"
echo "     或用一键初始化：cd $PROJECT_DIR && ./new_story.sh"
echo ""
echo "  2. 写第一章（示例）："
echo "     cd $PROJECT_DIR && ./write_chapter.sh ch001-标题 \"一句话 idea\" 3000"
echo ""
echo "  3. 角色自主推演剧情："
echo "     cd $PROJECT_DIR && ./novel_flow.sh         # 推演+提炼idea（停待确认）"
echo "     cd $PROJECT_DIR && ./novel_flow.sh --go    # 全自动一条龙成章"
echo ""
echo "  4. 第一次上手看同目录 GETTING_STARTED.md；系统差异看 README.md"
echo "============================================================"
