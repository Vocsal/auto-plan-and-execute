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
#      curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/latest/install.sh | bash
#      curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/latest/install.sh | bash -s -- /path/to/project
#      curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/latest/install.sh | bash -s -- -g
#      curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/latest/install.sh | bash -s -- --uninstall
#      curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/latest/install.sh | bash -s -- -g --uninstall
#
# 在 curl|bash 模式下，脚本会从 GitHub 拉取整个仓库的 tar 包再展开。
# 通过环境变量自定义来源:
#   APE_REPO   仓库 owner/name（默认见下方 DEFAULT_REPO）
#   APE_REF    分支、tag 或 commit SHA（默认 latest，由 release 工作流滚动到最新稳定版）
#   APE_SRC    本地源目录（手动指定）— 强制使用此目录作为源
#
# 如果已存在旧版本，会先删除再复制（更新场景）。
#
# 全局安装额外行为:
#   会在 PATH 中创建可执行命令 `auto-plan-and-execute`，优先位置:
#     1) $HOME/.local/bin/auto-plan-and-execute   （推荐，无需 sudo）
#     2) /usr/local/bin/auto-plan-and-execute     （需要该目录可写）
#   若两个位置都不可写，则跳过并保留完整路径调用方式。
#   若所选目录不在 PATH 中，安装脚本会提示需要追加的 export 行（不会自动修改 shell 配置）。
#   `-g --uninstall` 会同时清理软链接。

set -euo pipefail

# ---------- 默认远程仓库（首次发布时请修改） ----------
DEFAULT_REPO="${APE_REPO:-Vocsal/auto-plan-and-execute}"
DEFAULT_REF="${APE_REF:-latest}"

# ---------- 安装目标 ----------
SKILL_NAME="auto-plan-and-execute"
INSTALL_DIRS=(".agents/skills" ".claude/skills")

# 全局安装时创建的可执行命令名
GLOBAL_CMD_NAME="auto-plan-and-execute"
# 全局命令候选目录（按优先级）
GLOBAL_BIN_CANDIDATES=("$HOME/.local/bin" "/usr/local/bin")

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
  APE_REF    分支 / tag / commit SHA（默认 ${DEFAULT_REF}；latest 由 release 工作流滚动到最新稳定版）
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
  # 通用形式，可同时接受 branch / tag / commit SHA
  local url="https://codeload.github.com/${DEFAULT_REPO}/tar.gz/${DEFAULT_REF}"
  warn "从远程下载: $url" >&2
  if ! curl -fsSL "$url" | tar -xz -C "$tmp"; then
    err "下载或解压失败（ref=${DEFAULT_REF}）"
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

# 选择全局命令软链接的目标位置
# 输出选中的完整路径（如 $HOME/.local/bin/auto-plan-and-execute）；找不到可写位置则返回 1
pick_global_bin() {
  for dir in "${GLOBAL_BIN_CANDIDATES[@]}"; do
    # 目录已存在且可写 -> 直接用
    if [ -d "$dir" ] && [ -w "$dir" ]; then
      echo "$dir/$GLOBAL_CMD_NAME"
      return 0
    fi
    # 目录不存在但父目录可写 -> 可以 mkdir
    local parent
    parent="$(dirname "$dir")"
    if [ ! -e "$dir" ] && [ -d "$parent" ] && [ -w "$parent" ]; then
      echo "$dir/$GLOBAL_CMD_NAME"
      return 0
    fi
  done
  return 1
}

# 判断目录是否在 PATH 中
dir_in_path() {
  case ":$PATH:" in
    *":$1:"*) return 0 ;;
    *) return 1 ;;
  esac
}

# 创建全局命令软链接
install_global_command() {
  local script_path="$1"
  local link_path
  if ! link_path="$(pick_global_bin)"; then
    warn "未找到可写的全局 bin 目录（已尝试: ${GLOBAL_BIN_CANDIDATES[*]}）"
    warn "跳过全局命令安装；你仍可用完整路径调用: $script_path"
    return 0
  fi

  local link_dir
  link_dir="$(dirname "$link_path")"
  mkdir -p "$link_dir"

  # 冲突处理：已存在且不是指向本脚本的链接，则警告并跳过
  if [ -e "$link_path" ] || [ -L "$link_path" ]; then
    local existing_target=""
    if [ -L "$link_path" ]; then
      existing_target="$(readlink "$link_path" 2>/dev/null || true)"
    fi
    if [ "$existing_target" = "$script_path" ]; then
      log "全局命令链接已存在且指向当前安装，跳过: $link_path"
      return 0
    fi
    warn "目标位置已存在非本脚本创建的文件，跳过以避免覆盖: $link_path"
    warn "如需替换，请手动删除后重新安装"
    return 0
  fi

  ln -s "$script_path" "$link_path"
  log "✅ 已创建全局命令: $link_path -> $script_path"

  if ! dir_in_path "$link_dir"; then
    warn "目录不在 PATH 中: $link_dir"
    warn "请将下面这行加入 ~/.zshrc（或 ~/.bashrc）后重新打开终端:"
    warn "  export PATH=\"$link_dir:\$PATH\""
  fi
}

# 卸载全局命令软链接
uninstall_global_command() {
  local removed=0
  for dir in "${GLOBAL_BIN_CANDIDATES[@]}"; do
    local link_path="$dir/$GLOBAL_CMD_NAME"
    if [ -L "$link_path" ]; then
      rm -f "$link_path"
      log "✅ 已删除全局命令: $link_path"
      removed=$((removed + 1))
    elif [ -e "$link_path" ]; then
      warn "存在同名文件但不是软链接，跳过: $link_path"
    fi
  done
  if [ "$removed" -eq 0 ]; then
    warn "未发现全局命令软链接"
  fi
}

# 安装到一个目标目录的两个 skill 路径
do_install() {
  local target_root="$1" src="$2" global="$3"
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

  # 全局模式额外创建命令软链接
  if [ "$global" -eq 1 ]; then
    local script_path="$target_root/.agents/skills/$SKILL_NAME/auto-flow.sh"
    install_global_command "$script_path"
  fi

  log ""
  log "安装完成！可使用:"
  if [ "$global" -eq 1 ]; then
    log "  $GLOBAL_CMD_NAME \"<需求文本>\"           # 全局命令（若 PATH 已配置）"
    log "  $GLOBAL_CMD_NAME ./requirements.md"
    log ""
    log "或使用完整路径:"
  fi
  log "  $target_root/.agents/skills/$SKILL_NAME/auto-flow.sh \"<需求文本>\""
  log "  $target_root/.agents/skills/$SKILL_NAME/auto-flow.sh ./requirements.md"
  log ""
  log "在 Claude Code 中也可调用斜杠命令: /auto-plan-and-execute"
}

# 卸载
do_uninstall() {
  local target_root="$1" global="$2"
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

  # 全局模式额外清理命令软链接
  if [ "$global" -eq 1 ]; then
    uninstall_global_command
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
    do_uninstall "$target" "$global"
    return 0
  fi

  local src
  src="$(resolve_source)" || { err "无法确定源目录"; exit 1; }

  do_install "$target" "$src" "$global"

  # 如果是远程下载的，清理临时目录
  case "$src" in
    /tmp/ape-install.*|/var/folders/*/T/ape-install.*)
      rm -rf "$(dirname "$src")"
      ;;
  esac
}

main "$@"
