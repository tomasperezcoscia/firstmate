#!/usr/bin/env bash
# Adversarial $TMUX inputs against the real fm_backend_tmux_container_ensure on
# a private tmux server. Each call carries the exact $TMUX/$TMUX_PANE shape a
# firstmate pane inherits, so bare `tmux` reaches only this lab socket.
# usage: edge.sh <code-dir>
set -u
CODE=$1
D=$(mktemp -d /tmp/fma.XXXXXX); chmod 700 "$D"
t() { env -i HOME="$HOME" PATH="$PATH" TMUX_TMPDIR="$D" tmux -f /dev/null -L edge "$@"; }
trap 't kill-server 2>/dev/null; rm -rf "$D"' EXIT
t new-session -d -s cc-firstmate-edge -n main -x 120 -y 30 "sleep 600"
SOCK=$(t display-message -p '#{socket_path}'); SPID=$(t display-message -p '#{pid}')
PANE=$(t display-message -p -t cc-firstmate-edge:main '#{pane_id}')
OWN=$(t display-message -p -t cc-firstmate-edge '#{session_id}'); OWN=${OWN#\$}
t new-session -d -s puente-v-aaaa -t cc-firstmate-edge
t select-window -t puente-v-aaaa:main
VA=$(t display-message -p -t puente-v-aaaa '#{session_id}'); VA=${VA#\$}
# shellcheck source=/dev/null
. "$CODE/bin/fm-backend.sh"; fm_backend_source tmux
probe() {  # <label> <tmux-env>
  local got rc
  got=$(TMUX=$2 TMUX_PANE=$PANE fm_backend_tmux_container_ensure 2>&1); rc=$?
  printf '%-58s TMUX=...,%-5s -> %-22s rc=%s\n' "$1" "${2##*,}" "'$got'" "$rc"
}
echo "sessions: $(t list-sessions -F '#{session_name}(#{session_id})' | tr '\n' ' ')"
echo "untargeted #S from the pane: $(TMUX="$SOCK,$SPID,$OWN" TMUX_PANE=$PANE tmux display-message -p '#S')"
probe "own session id, viewer is most recent"               "$SOCK,$SPID,$OWN"
probe "malformed id (non-numeric)"                           "$SOCK,$SPID,abc"
probe "empty id"                                             "$SOCK,$SPID,"
probe "id prefixed with \$ (not a bare number)"              "$SOCK,$SPID,\$$OWN"
probe "viewer's id while the viewer is alive"                "$SOCK,$SPID,$VA"
t kill-session -t puente-v-aaaa
probe "stale id: viewer killed, only own session left"       "$SOCK,$SPID,$VA"
t new-session -d -s puente-v-bbbb -t cc-firstmate-edge
t select-window -t puente-v-bbbb:main
echo "sessions: $(t list-sessions -F '#{session_name}(#{session_id})' | tr '\n' ' ')"
probe "stale id while a SECOND viewer is now most recent"    "$SOCK,$SPID,$VA"
probe "own id while a second viewer is most recent"          "$SOCK,$SPID,$OWN"
