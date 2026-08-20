#!/usr/bin/env bash
# Arclume PR baseline: static validation and a Debug build only.
# XCTest is intentionally excluded until docs/testing.md Phase 1 is complete.
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_path="$project_root/Arclume.xcodeproj"
scheme="Arclume"
manifest_path="$project_root/Arclume/Resources/OnlineGameDependencies/arclume-wine-runtime.json"
base_ref="${BASE_REF:-origin/main}"
derived_data=""

fail() {
  printf '前置审核失败：%s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [ -n "$derived_data" ] && [ -d "$derived_data" ]; then
    rm -rf "$derived_data"
  fi
}
trap cleanup EXIT

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少命令：$1"
}

collect_changed_files() {
  local list_file="$1"
  : > "$list_file"

  # The range is the submitted PR; the latter two commands also make the
  # script useful before a local commit is created.
  if git rev-parse --verify --quiet "$base_ref" >/dev/null; then
    git diff --name-only "$base_ref...HEAD" >> "$list_file"
  fi
  git diff --name-only >> "$list_file"
  git diff --cached --name-only >> "$list_file"
  git ls-files --others --exclude-standard >> "$list_file"
  sort -u "$list_file" -o "$list_file"
}

check_change_log() {
  local changed_file_list="$1"
  local non_log_changes
  local log_entries

  non_log_changes="$(grep -Ev '^(CHANGELOG/|$)' "$changed_file_list" || true)"
  [ -z "$non_log_changes" ] && return 0

  log_entries="$(grep -E '^CHANGELOG/(unreleased/[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}-[a-z0-9-]+\.md|released/[A-Za-z0-9._-]+\.md)$' "$changed_file_list" || true)"
  [ -n "$log_entries" ] || fail "每个非 CHANGELOG 改动都必须同时新增或更新一个符合命名规则的 CHANGELOG 条目。"
}

printf '== Arclume PR 前置审核 ==\n'
cd "$project_root"

for command_name in git jq ruby shasum xcodebuild; do
  require_command "$command_name"
done

git lfs version >/dev/null 2>&1 || fail "Git LFS 未就绪；请先安装并执行 git lfs pull。"
git diff --check
if git rev-parse --verify --quiet "$base_ref" >/dev/null; then
  git diff --check "$base_ref...HEAD"
else
  printf '提示：未找到 %s，只审核当前工作区差异。\n' "$base_ref"
fi

changed_files="$(mktemp "${TMPDIR:-/tmp}/arclume-changed-files.XXXXXX")"
trap 'rm -f "$changed_files"; cleanup' EXIT
collect_changed_files "$changed_files"
check_change_log "$changed_files"

printf '检查 Git LFS 状态…\n'
# `git lfs fsck` may move unavailable local objects into .git/lfs/bad. A PR
# preflight must be non-mutating: the release-critical Runtime archive is
# verified by its exact SHA-256 below, while `git lfs status` exposes pending
# LFS changes without altering the local object store.
git lfs status

printf '校验 Runtime Manifest…\n'
[ -f "$manifest_path" ] || fail "找不到 Runtime Manifest：$manifest_path"
jq -e '
  .schemaVersion == 1 and
  (.id | type == "string" and length > 0) and
  (.version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+([.-][0-9A-Za-z.-]+)?$")) and
  (.runtimeABI | type == "number" and . >= 1) and
  (.prefixABI | type == "string" and length > 0) and
  (.archive.name | type == "string" and test("^[A-Za-z0-9._-]+\\.tar\\.xz$")) and
  (.archive.sha256 | type == "string" and test("^[a-f0-9]{64}$"))
' "$manifest_path" >/dev/null || fail "Runtime Manifest 结构或版本格式无效。"

archive_name="$(jq -r '.archive.name' "$manifest_path")"
archive_sha256="$(jq -r '.archive.sha256' "$manifest_path")"
archive_path="$project_root/Arclume/Resources/OnlineGameDependencies/$archive_name"
[ -f "$archive_path" ] || fail "Runtime 归档不存在：$archive_name"
actual_sha256="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
[ "$actual_sha256" = "$archive_sha256" ] || fail "Runtime 归档 SHA-256 与 Manifest 不一致。"

printf '校验 GitHub Actions YAML…\n'
ruby -e 'require "yaml"; ARGV.each { |path| YAML.load_file(path) }' .github/workflows/*.yml

printf '读取 Xcode 版本设置…\n'
build_settings="$(xcodebuild -showBuildSettings -project "$project_path" -scheme "$scheme" -configuration Debug)"
marketing_version="$(printf '%s\n' "$build_settings" | awk -F ' = ' '/^[[:space:]]*MARKETING_VERSION = / { print $2; exit }')"
build_number="$(printf '%s\n' "$build_settings" | awk -F ' = ' '/^[[:space:]]*CURRENT_PROJECT_VERSION = / { print $2; exit }')"
[ -n "$marketing_version" ] || fail "无法读取 MARKETING_VERSION。"
[ -n "$build_number" ] || fail "无法读取 CURRENT_PROJECT_VERSION。"

printf '执行未签名 Debug build（不执行 XCTest）…\n'
derived_data="$(mktemp -d "${TMPDIR:-/tmp}/arclume-preflight.XXXXXX")"
xcodebuild build \
  -project "$project_path" \
  -scheme "$scheme" \
  -configuration Debug \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=- \
  SWIFT_EMIT_LOC_STRINGS=NO

printf '通过：Arclume %s (%s)，Runtime SHA-256 已核对，未运行 XCTest。\n' "$marketing_version" "$build_number"
