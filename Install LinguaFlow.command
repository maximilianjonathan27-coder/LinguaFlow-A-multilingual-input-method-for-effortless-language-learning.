#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY_ONLY=false
SKIP_UPDATE=false

for argument in "$@"; do
  case "$argument" in
    --verify-only) VERIFY_ONLY=true ;;
    --skip-update) SKIP_UPDATE=true ;;
    *)
      echo "Unknown option: $argument" >&2
      echo "usage: ./Install\\ LinguaFlow.command [--verify-only] [--skip-update]" >&2
      exit 2
      ;;
  esac
done

finish() {
  local status=$?
  if [[ -t 0 ]]; then
    echo
    if [[ $status -eq 0 ]]; then
      read -r -p "完成。按回车键关闭窗口。" _
    else
      read -r -p "安装未完成，请查看上面的原因。按回车键关闭窗口。" _
    fi
  fi
  exit "$status"
}
trap finish EXIT

update_patches() {
  if [[ "$SKIP_UPDATE" == true ]]; then
    echo "已按要求跳过 GitHub 补丁检查。"
    return
  fi

  if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "当前是 GitHub ZIP 版本；将使用压缩包内自带的完整补丁。"
    return
  fi

  if ! git -C "$ROOT_DIR" diff --quiet \
      || ! git -C "$ROOT_DIR" diff --cached --quiet; then
    echo "检测到尚未保存的源码修改，无法安全地自动更新补丁。" >&2
    echo "请先提交或备份这些修改，再重新运行安装程序。" >&2
    return 1
  fi

  echo "正在检查 GitHub main 的最新补丁..."
  git -C "$ROOT_DIR" fetch origin main
  local head remote_main
  head="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  remote_main="$(git -C "$ROOT_DIR" rev-parse origin/main)"

  if [[ "$head" == "$remote_main" ]]; then
    echo "补丁已是最新版本：${head:0:7}"
  elif git -C "$ROOT_DIR" merge-base --is-ancestor "$head" "$remote_main"; then
    git -C "$ROOT_DIR" merge --ff-only "$remote_main"
    echo "补丁已更新到：${remote_main:0:7}"
  elif git -C "$ROOT_DIR" merge-base --is-ancestor "$remote_main" "$head"; then
    echo "当前版本包含尚未上传的本地提交，将继续使用当前版本：${head:0:7}"
  else
    echo "当前分支与 GitHub main 已分叉，无法安全地自动合并。" >&2
    return 1
  fi
}

echo "LinguaFlow 使用前准备"
echo "===================="
update_patches

if [[ "$VERIFY_ONLY" == true ]]; then
  "$ROOT_DIR/script/build_and_run.sh" --verify-ime
  echo "LinguaFlow、librime 和全部补丁验证通过。"
else
  "$ROOT_DIR/script/build_and_run.sh" --install-ime
  echo "LinguaFlow 已安装；librime 和全部补丁均已验证。"
fi
