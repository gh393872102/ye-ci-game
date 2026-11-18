#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_engine=${GODOT_BIN:-}
if [ -z "$task_engine" ]; then
  for task_candidate in /Applications/Godot.app/Contents/MacOS/Godot "$HOME/Applications/Godot.app/Contents/MacOS/Godot" "$task_root/../zhizhacun/.runtime/Godot"; do
    if [ -x "$task_candidate" ]; then
      task_engine=$task_candidate
      break
    fi
  done
fi
if [ -z "$task_engine" ]; then
  task_engine=$(command -v godot || command -v godot4 || true)
fi
if [ -z "$task_engine" ] || [ ! -x "$task_engine" ]; then
  echo '请安装 Godot 4.7.2 stable，或将 GODOT_BIN 设置为引擎可执行文件。' >&2
  exit 1
fi
exec "$task_engine" --path "$task_root" "$@"
