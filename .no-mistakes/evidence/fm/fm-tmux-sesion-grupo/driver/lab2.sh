#!/usr/bin/env bash
# Stale-session-id variant: the primary's pane was opened from the viewer's
# grouped session, then the viewer closes and the pane lives on in the
# original session. usage: lab2.sh <code-dir> <tag> <evidence-dir>
set -u
CODE=$1 TAG=$2 EV=$3
SCEN=$(cd "$(dirname "$0")" && pwd)
HELPER=/home/tperez/.no-mistakes/worktrees/9cf2fb7d564f/01M5K4X85ZEW3T188VF4DA28W2/bin/fm-lab-home.sh
OUT=$EV/$TAG-transcript.txt; : > "$OUT"
say() { printf '%s\n' "$*" | tee -a "$OUT"; }
ROOT=$(mktemp -d /tmp/fm-lab.XXXXXX); ROOT=$(cd -P "$ROOT" && pwd -P); LAB=$ROOT/home
"$HELPER" create "$LAB" >/dev/null || exit 1
TMUXD=$("$HELPER" tmux-dir "$LAB") || exit 1
NONCE=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n'); ID="lab${NONCE}-ship"
PRIMARY="cc-firstmate-$$"; VIEWER="puente-v-${NONCE}0c1d"
echo "$ROOT" > "$EV/$TAG-root.path"; echo "$ID" > "$EV/$TAG-task.id"
ltmux() { env -i HOME="$HOME" PATH="$PATH" TMUX_TMPDIR="$TMUXD" tmux -L fm-lab "$@"; }
waitfor() { local f=$1 n=${2:-600} i=0; while [ ! -e "$f" ] && [ $i -lt $n ]; do sleep 1; i=$((i+1)); done; [ -e "$f" ]; }
say "== lab $TAG: code=$CODE ($(git -C "$CODE" rev-parse --short HEAD 2>/dev/null))"
say "lab root=$ROOT task=$ID original session=$PRIMARY viewer session=$VIEWER"
seed=$ROOT/origins/seed; origin=$ROOT/origins/notes.git
git init -q -b main "$seed"; printf '# notes\n' > "$seed/README.md"
git -C "$seed" add -A; git -C "$seed" -c user.name=lab -c user.email=lab@example.invalid commit -q -m seed
git clone -q --bare "$seed" "$origin"; git clone -q "$origin" "$LAB/projects/notes"
printf '# Projects\n\n- notes [local-only +yolo] - tiny lab notes project\n' > "$LAB/data/projects.md"
printf 'tmux\n' > "$LAB/config/backend"; printf 'auto\n' > "$LAB/config/claude-permission-mode"; mkdir -p "$ROOT/treehouse"
env -i HOME="$HOME" USER="${USER:-$(id -un)}" LOGNAME="${USER:-$(id -un)}" PATH="$PATH" SHELL=/bin/bash \
  TERM=xterm-256color LANG="${LANG:-C.UTF-8}" TMUX_TMPDIR="$TMUXD" TREEHOUSE_ROOT="$ROOT/treehouse" \
  DISABLE_AUTOUPDATER=1 FM_HOME="$LAB" \
  tmux -f /dev/null -L fm-lab new-session -d -s "$PRIMARY" -n term -x 200 -y 50 -c "$CODE" "bash --noprofile --norc" || exit 1
ltmux new-session -d -s "$VIEWER" -t "$PRIMARY" || exit 1
python3 -I "$SCEN/attach.py" "$VIEWER" "$TMUXD" & VPID=$!
sleep 2
# the primary is started from the viewer side: its pane is created in the viewer session
PANE=$(ltmux new-window -dP -F '#{pane_id}' -t "$VIEWER:" -n main -c "$CODE" "bash --noprofile --norc")
sleep 1
inpane() { ltmux send-keys -t "$PANE" "bash $SCEN/inpane.sh $* ; clear" Enter; }
say "--- primary pane $PANE opened from the viewer; sessions:"
ltmux list-sessions -F '#{session_name} id=#{session_id} group=#{session_group} attached=#{session_attached}' | tee -a "$OUT"
inpane precheck "$CODE" "$ROOT" "$ID"; waitfor "$ROOT/precheck.done" 30
say "--- precheck with the viewer alive"; tee -a "$OUT" < "$ROOT/precheck.txt"
kill "$VPID" 2>/dev/null; wait "$VPID" 2>/dev/null; ltmux kill-session -t "$VIEWER"
rm -f "$ROOT/precheck.done"
say "--- viewer closed; sessions now: $(ltmux list-sessions -F '#{session_name}' | tr '\n' ' ')"
say "primary pane still lives at: $(ltmux display-message -p -t "$PANE" '#{session_name}:#{window_name}')"
inpane precheck "$CODE" "$ROOT" "$ID"; waitfor "$ROOT/precheck.done" 30
say "--- precheck after the viewer closed"; tee -a "$OUT" < "$ROOT/precheck.txt"
inpane spawn "$CODE" "$ROOT" "$ID"; waitfor "$ROOT/spawn.done" 900 || say "spawn did not finish in time"
cp "$ROOT/spawn.log" "$EV/$TAG-spawn.log"
say "--- fm-spawn.sh tail (full log: $TAG-spawn.log)"; tail -4 "$ROOT/spawn.log" | tee -a "$OUT"
say "--- recorded endpoint"; grep -E '^window=' "$LAB/state/$ID.meta" 2>&1 | tee -a "$OUT"
say "--- where the task window lives"; ltmux list-windows -a -F '#{session_name}:#{window_name} (#{window_id})' | grep "fm-$ID" | tee -a "$OUT"
inpane endpoint "$CODE" "$ROOT" "$ID" after; waitfor "$ROOT/endpoint-after.done" 120
say "--- endpoint resolution from the primary pane"; grep -v '^\s*$' "$ROOT/endpoint-after.txt" | grep -v -E '^[▄▀ ]|^[─]|⏵|Claude Code|Sonnet|▐|▝' | tee -a "$OUT"
ltmux kill-server 2>/dev/null; "$HELPER" teardown "$LAB" >/dev/null 2>&1
say "== lab $TAG finished"
