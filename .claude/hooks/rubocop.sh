#!/usr/bin/env bash
# PostToolUse hook: autocorrects the Ruby file Claude just wrote, then hands back what RuboCop cannot fix
# (exit 2 shows stderr to Claude). Files git ignores are left alone, such as vendored or cloned code.
set -u

file=$(jq -r '.tool_input.file_path // empty')
case "$file" in
  "$CLAUDE_PROJECT_DIR"/*) ;;
  *) exit 0 ;;
esac
case "$file" in
  *.rb | *.rake | */Gemfile | */Rakefile | *.gemspec) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0
cd "$CLAUDE_PROJECT_DIR" || exit 0
git check-ignore --quiet "$file" && exit 0

# Autocorrect, except for removing assignments: the next edit may well be the one that reads them.
bundle exec rubocop --autocorrect --server --force-exclusion --format quiet --except Lint/UselessAssignment "$file" >/dev/null 2>&1
if ! output=$(bundle exec rubocop --server --force-exclusion --no-color --format simple "$file" 2>&1); then
  echo "$output" >&2
  exit 2
fi
