#!/usr/bin/env bash
# install.sh — 安装 auto-plan-and-execute skill 到目标项目
#
# 安装位置:
#   <目标目录>/.agents/skills/auto-plan-and-execute/
#   <目标目录>/.claude/skills/auto-plan-and-execute/
#
# 两种调用方式:
#
# 1) 本地（已 clone 仓库）:
#      ./install.sh [<目标目录>]              # 项目级：装到 <目标>/.agents/skills + .claude/skills
#      ./install.sh -g                       # 全局：装到 ~/.agents/skills + ~/.claude/skills
#      ./install.sh --uninstall [<目标目录>]  # 卸载项目级
#      ./install.sh -g --uninstall           # 卸载全局
#
# 2) 远程一行安装（curl | bash）:
#      curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/main/install.sh | bash
#      curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/main/install.sh | bash -s -- /path/to/project
#      curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/main/install.sh | bash -s -- -g
#      curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/main/install.sh | bash -s -- --uninstall
#      curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/main/install.sh | bash -s -- -g --uninstall
#
# 在 curl|bash 模式下，脚本会从 GitHub 拉取整个仓库的 tar 包再展开。
# 通过环境变量自定义来源:
#   APE_REPO   仓库 owner/name（默认见下方 DEFAULT_REPO）
#   APE_REF    分支或 tag（默认 main）
#   APE_SRC    本地源目录（手动指定）— 强制使用此目录作为源
#
# 如果已存在旧版本，会先删除再复制（更新场景）。

set -euo pipefail

# ---------- 默认远程仓库（首次发布时请修改） ----------
DEFAULT_REPO="${APE_REPO:-Vocsal/auto-plan-and-execute}"
DEFAULT_REF="${APE_REF:-main}"

# ---------- 安装目标 ----------
SKILL_NAME="auto-plan-and-execute"
INSTALL_DIRS=(".agents/skills" ".claude/skills")

# ---------- 工具函数 ----------
log()  { printf "\033[1;34m[install]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[install]\033[0m %s\n" "$*" >&2; }
err()  { printf "\033[1;31m[install]\033[0m %s\n" "$*" >&2; }

usage() {
  cat <<EOF
auto-plan-and-execute 安装脚本

用法:
  ./install.sh [<目标目录>]                   # 项目级安装（默认当前目录）
  ./install.sh -g | --global                  # 全局安装到用户主目录
  ./install.sh --uninstall [<目标目录>]       # 卸载项目级
  ./install.sh -g --uninstall                 # 卸载全局
  curl ... | bash                             # 远程项目级安装到当前目录
  curl ... | bash -s -- <目标目录>            # 远程项目级安装到指定目录
  curl ... | bash -s -- -g                    # 远程全局安装

参数:
  <目标目录>   默认是当前工作目录（仅项目级模式有效）
  -g, --global 全局安装；与 <目标目录> 互斥

环境变量:
  APE_REPO   远程仓库（owner/name，默认 ${DEFAULT_REPO}）
  APE_REF    分支/tag（默认 ${DEFAULT_REF}）
  APE_SRC    本地源目录，跳过自动检测

项目级安装位置:
  <目标目录>/.agents/skills/${SKILL_NAME}/
  <目标目录>/.claude/skills/${SKILL_NAME}/

全局安装位置:
  \$HOME/.agents/skills/${SKILL_NAME}/
  \$HOME/.claude/skills/${SKILL_NAME}/

项目级和全局可共存。Claude Code 优先识别项目级。
已存在旧版本会先删除再复制（更新场景）。
EOF
}

# 判断脚本是否在 pipe（curl | bash）下运行
is_piped() {
  # 当通过管道运行时，BASH_SOURCE[0] 通常为 "bash" 或空，且不是常规文件
  [ ! -t 0 ] && [ ! -f "${BASH_SOURCE[0]:-}" ]
}

# 解析"源目录"
# 优先级: APE_SRC > 本地脚本所在目录（如果有 SKILL.md）> 远程下载
resolve_source() {
  if [ -n "${APE_SRC:-}" ]; then
    if [ -d "$APE_SRC" ] && [ -f "$APE_SRC/SKILL.md" ]; then
      echo "$APE_SRC"
      return 0
    else
      err "APE_SRC=$APE_SRC 不是有效的源目录（缺少 SKILL.md）"
      return 1
    fi
  fi

  # 尝试用脚本所在目录（本地 clone 调用）
  local script_dir=""
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$script_dir/SKILL.md" ]; then
      echo "$script_dir"
      return 0
    fi
  fi

  # 远程下载
  download_remote
}

# 从 GitHub 下载 tarball 并解压
download_remote() {
  command -v curl >/dev/null 2>&1 || { err "缺少 curl"; return 1; }
  command -v tar  >/dev/null 2>&1 || { err "缺少 tar"; return 1; }

  local tmp
  tmp="$(mktemp -d -t ape-install.XXXXXX)"
  local url="https://codeload.github.com/${DEFAULT_REPO}/tar.gz/refs/heads/${DEFAULT_REF}"
  warn "从远程下载: $url" >&2
  if ! curl -fsSL "$url" | tar -xz -C "$tmp"; then
    err "下载或解压失败"
    rm -rf "$tmp"
    return 1
  fi

  # GitHub tarball 顶层目录是 {repo}-{ref}
  local top
  top="$(ls -1 "$tmp" | head -n1)"
  local extracted="$tmp/$top"
  if [ ! -f "$extracted/SKILL.md" ]; then
    err "下载的内容里没找到 SKILL.md（路径: ${extracted}）"
    rm -rf "$tmp"
    return 1
  fi
  echo "$extracted"
}

# 复制源到目标，排除 install.sh 和版本控制目录
copy_payload() {
  local src="$1" dst="$2"
  mkdir -p "$dst"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a \
      --exclude='install.sh' \
      --exclude='.git/' \
      --exclude='.auto-flow/' \
      --exclude='node_modules/' \
      "$src/" "$dst/"
  else
    # rsync 不存在时手动复制
    (cd "$src" && tar -cf - \
      --exclude='install.sh' \
      --exclude='.git' \
      --exclude='.auto-flow' \
      --exclude='node_modules' \
      .) | (cd "$dst" && tar -xf -)
  fi
}

# 安装到一个目标目录的两个 skill 路径
do_install() {
  local target_root="$1" src="$2"
  log "源: $src"
  log "目标: $target_root"

  for sub in "${INSTALL_DIRS[@]}"; do
    local dst="$target_root/$sub/$SKILL_NAME"
    if [ -e "$dst" ]; then
      warn "已存在旧版本，先删除: $dst"
      rm -rf "$dst"
    fi
    copy_payload "$src" "$dst"
    chmod +x "$dst"/scripts/*.sh "$dst"/auto-flow.sh 2>/dev/null || true
    log "✅ 已安装: $dst"
  done

  log ""
  log "安装完成！可使用:"
  log "  $target_root/.agents/skills/$SKILL_NAME/auto-flow.sh \"<需求文本>\""
  log "  $target_root/.agents/skills/$SKILL_NAME/auto-flow.sh ./requirements.md"
  log ""
  log "在 Claude Code 中也可调用斜杠命令: /auto-plan-and-execute"
}

# 卸载
do_uninstall() {
  local target_root="$1"
  log "目标: $target_root"

  local removed=0
  for sub in "${INSTALL_DIRS[@]}"; do
    local dst="$target_root/$sub/$SKILL_NAME"
    if [ -e "$dst" ]; then
      rm -rf "$dst"
      log "✅ 已删除: $dst"
      removed=$((removed + 1))
    fi
  done

  if [ "$removed" -eq 0 ]; then
    warn "未发现任何已安装的 ${SKILL_NAME}（在 ${target_root} 下）"
  fi
}

# ---------- 主入口 ----------
main() {
  local mode="install"
  local target=""
  local global=0

  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --uninstall) mode="uninstall"; shift ;;
      -g|--global) global=1; shift ;;
      -*) err "未知选项: $1"; usage; exit 1 ;;
      *)
        if [ -z "$target" ]; then
          target="$1"
        else
          err "多余参数: $1"; exit 1
        fi
        shift
        ;;
    esac
  done

  # -g 与 <目标目录> 互斥
  if [ "$global" -eq 1 ] && [ -n "$target" ]; then
    err "-g/--global 与 <目标目录> 互斥，请只用其中之一"
    exit 1
  fi

  # 解析最终安装根
  if [ "$global" -eq 1 ]; then
    target="$HOME"
    log "模式: 全局安装（\$HOME=${HOME}）"
  else
    if [ -z "$target" ]; then
      target="$PWD"
    fi
    if [ ! -d "$target" ]; then
      err "目标目录不存在: $target"
      exit 1
    fi
    target="$(cd "$target" && pwd)"
    log "模式: 项目级安装"
  fi

  if [ "$mode" = "uninstall" ]; then
    do_uninstall "$target"
    return 0
  fi

  local src
  src="$(resolve_source)" || { err "无法确定源目录"; exit 1; }

  do_install "$target" "$src"

  # 如果是远程下载的，清理临时目录
  case "$src" in
    /tmp/ape-install.*|/var/folders/*/T/ape-install.*)
      rm -rf "$(dirname "$src")"
      ;;
  esac
}

main "$@"
