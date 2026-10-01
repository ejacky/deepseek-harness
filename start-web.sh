#!/usr/bin/env bash
# DeepSeek Harness launcher for Linux - single-icon toggle.
# Equivalent of start-web.cmd + start-web-silent.vbs on Windows:
#   not running -> start the Web GUI on $PORT (the harness opens the browser)
#   already up  -> ask for confirmation, then stop the server
#
# Usage: start-web.sh [--check]
#   --check prints the resolved pnpm/node and the port state, then exits.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PORT=3080
UNIT="dsh-web-$PORT"
LOG="$ROOT/.dsh-web.log"

log() {
  printf '%s %s\n' "$(date '+%F %T')" "$1" >>"$LOG"
}

# A .desktop launch inherits a minimal PATH; add the usual Node/pnpm locations.
# pnpm's own installer keeps the executable in $PNPM_HOME/bin.
for d in "$HOME/.local/share/pnpm/bin" "$HOME/.local/share/pnpm" "$HOME/.local/bin" \
  "$HOME/.nvm/versions/node"/*/bin "$HOME/.local/share/fnm"/*/bin "$HOME/.volta/bin" \
  /usr/local/bin /snap/bin; do
  [ -d "$d" ] || continue
  case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac
done
export PATH

notify() {
  command -v notify-send >/dev/null 2>&1 && notify-send "DeepSeek Harness" "$1" >/dev/null 2>&1
  return 0
}

info() {
  if command -v zenity >/dev/null 2>&1; then zenity --info --title="DeepSeek Harness" --text="$1"
  elif command -v kdialog >/dev/null 2>&1; then kdialog --title "DeepSeek Harness" --msgbox "$1"
  else notify "$1"; fi
}

error() {
  if command -v zenity >/dev/null 2>&1; then zenity --error --title="DeepSeek Harness" --text="$1"
  elif command -v kdialog >/dev/null 2>&1; then kdialog --title "DeepSeek Harness" --error "$1"
  else notify "$1"; fi
}

# Status 0 means the user chose to stop; status 1 means cancel or no dialog.
confirm_stop() {
  if command -v zenity >/dev/null 2>&1; then
    zenity --question --title="DeepSeek Harness" --text="$1" --ok-label="停止" --cancel-label="取消"
  elif command -v kdialog >/dev/null 2>&1; then
    kdialog --title "DeepSeek Harness" --yesno "$1"
  else
    notify "端口 $PORT 已被占用，但没有可用的图形对话框；未停止。"
    return 1
  fi
}

# Print the PID listening on $PORT, if any. Needs ss or lsof.
port_pid() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp 2>/dev/null | awk -v pat=":$PORT\$" '
      $4 ~ pat && match($0, /pid=[0-9]+/) { print substr($0, RSTART + 4, RLENGTH - 4); exit }'
  elif command -v lsof >/dev/null 2>&1; then
    lsof -tnP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | head -n 1
  fi
}

# Prefer PATH, then the known pnpm install locations.
# Print an absolute path to pnpm; status 1 when none is executable.
resolve_pnpm() {
  local c
  for c in "$(command -v pnpm 2>/dev/null)" \
    "$HOME/.local/share/pnpm/bin/pnpm" "$HOME/.local/share/pnpm/pnpm" \
    /usr/local/bin/pnpm /usr/bin/pnpm "$HOME/.nvm/versions/node"/*/bin/pnpm \
    "$HOME/.local/share/fnm"/*/bin/pnpm; do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

proc_label() {
  local label
  label="$(tr '\0' ' ' <"/proc/$1/cmdline" 2>/dev/null)"
  printf '%s' "${label:-pid $1}"
}

kill_tree() {
  local child
  for child in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$child"; done
  kill -TERM "$1" 2>/dev/null
}

# Wait up to 10s for the process to disappear.
wait_gone() {
  local i
  for i in $(seq 1 100); do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 0.1
  done
  return 1
}

if ! command -v ss >/dev/null 2>&1 && ! command -v lsof >/dev/null 2>&1; then
  notify "缺少 ss（iproute2）或 lsof，无法检测 $PORT 端口状态。"
  echo "start-web.sh: need ss (iproute2) or lsof to detect port $PORT" >&2
  exit 1
fi

# Keep the log bounded but append across runs so failures stay inspectable.
[ -f "$LOG" ] && [ "$(stat -c%s "$LOG" 2>/dev/null || echo 0)" -gt 1000000 ] && mv -f "$LOG" "$LOG.1"

if [ "${1:-}" = "--check" ]; then
  printf 'root: %s\n' "$ROOT"
  printf 'port %s: %s\n' "$PORT" "$(port_pid)"
  printf 'pnpm: %s\n' "$(resolve_pnpm || echo MISSING)"
  printf 'node: %s\n' "$(command -v node || echo MISSING)"
  printf 'log: %s (%s)\n' "$LOG" "$([ -w "$ROOT" ] && echo writable || echo 'NOT writable')"
  printf 'unit %s: %s\n' "$UNIT" "$(systemctl --user is-active "$UNIT" 2>&1 || true)"
  printf 'systemd-run: %s\n' "$(command -v systemd-run || echo MISSING)"
  exit 0
fi

# Kill the process holding the port first so the dialog returns promptly, then
# drop the transient unit when this launcher started the server.
stop_server() {
  if [ -n "$1" ]; then
    kill_tree "$1"
    if ! wait_gone "$1"; then
      kill -KILL "$1" 2>/dev/null
      wait_gone "$1"
    fi
  fi
  if systemctl --user is-active --quiet "$UNIT" 2>/dev/null; then
    log "stopping unit $UNIT"
    systemctl --user stop "$UNIT"
  fi
}

# GNOME launches .desktop entries in a systemd scope and kills every process
# left in that cgroup once the launcher exits, so a plain background child would
# die immediately. A transient user unit lives in its own cgroup and survives.
start_server() {
  if command -v systemd-run >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user reset-failed "$UNIT" >/dev/null 2>&1
    log "starting unit $UNIT: $pnpm_bin dsh web"
    if systemd-run --user --unit="$UNIT" --collect \
      --property=WorkingDirectory="$ROOT" \
      --property=StandardOutput=append:"$LOG" \
      --property=StandardError=append:"$LOG" \
      "$pnpm_bin" dsh web >/dev/null 2>&1; then
      return 0
    fi
    log "systemd-run failed; falling back to a detached child"
  fi
  log "starting detached: $pnpm_bin dsh web"
  setsid nohup "$pnpm_bin" dsh web >>"$LOG" 2>&1 </dev/null &
}

pid="$(port_pid)"
if [ -n "$pid" ]; then
  log "port $PORT busy with pid $pid ($(proc_label "$pid"))"
  if confirm_stop "DeepSeek Harness 正在运行（PID $pid：$(proc_label "$pid")）。要停止它吗？"; then
    stop_server "$pid"
    log "stopped pid $pid"
    info "已停止 DeepSeek Harness（PID $pid）。"
  else
    log "stop cancelled by user"
  fi
  exit 0
fi

pnpm_bin="$(resolve_pnpm || true)"
if [ -z "$pnpm_bin" ]; then
  log "ERROR pnpm not found; PATH=$PATH"
  error "找不到 pnpm。请先安装 Node.js 与 pnpm，或在 start-web.sh 的候选目录中加入其安装位置。
PATH=$PATH"
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  log "ERROR node not found; PATH=$PATH"
  error "找不到 node。请先安装 Node.js（^22.19 或 >=24）。"
  exit 1
fi

cd "$ROOT" || exit 1
start_server

# Success is silent on purpose: dsh web opens the browser itself.
for _ in $(seq 1 90); do
  sleep 1
  [ -n "$(port_pid)" ] && exit 0
done

log "ERROR $PORT not listening after 90s"
error "启动失败：90 秒内没有进程在 $PORT 端口监听。日志：$LOG
$(tail -n 5 "$LOG" 2>/dev/null)"
exit 1
