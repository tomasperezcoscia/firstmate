#!/usr/bin/env bash
# usage: lab.sh <code-dir> <tag> <evidence-dir>
set -u
CODE=$1 TAG=$2 EV=$3
SCEN=$(cd "$(dirname "$0")" && pwd)
HELPER=/home/tperez/.no-mistakes/worktrees/9cf2fb7d564f/01M5K4X85ZEW3T188VF4DA28W2/bin/fm-lab-home.sh
OUT=$EV/$TAG-transcript.txt
: > "$OUT"
say() { printf '%s\n' "$*" | tee -a "$OUT"; }
ROOT=$(mktemp -d /tmp/fm-lab.XXXXXX); ROOT=$(cd -P "$ROOT" && pwd -P)
LAB=$ROOT/home
"$HELPER" create "$LAB" >/dev/null || exit 1
TMUXD=$("$HELPER" tmux-dir "$LAB") || exit 1
NONCE=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')
ID="lab${NONCE}-ship"
PRIMARY="cc-firstmate-$$"
VIEWER="puente-v-${NONCE}0c1d"
echo "$ROOT" > "$EV/$TAG-root.path"
ls -1A "$HOME/.treehouse" 2>/dev/null | sort > "$ROOT/.treehouse-before"
ltmux() { env -i HOME="$HOME" PATH="$PATH" TMUX_TMPDIR="$TMUXD" tmux -L fm-lab "$@"; }
waitfor() { local f=$1 n=${2:-600} i=0; while [ ! -e "$f" ] && [ $i -lt $n ]; do sleep 1; i=$((i+1)); done; [ -e "$f" ]; }
inpane() { ltmux send-keys -t "$PRIMARY:main" "bash $SCEN/inpane.sh $* ; clear" Enter; }

say "== lab $TAG: code=$CODE ($(git -C "$CODE" rev-parse --short HEAD 2>/dev/null))"
say "lab root=$ROOT  task=$ID  primary session=$PRIMARY  viewer session=$VIEWER"
# project + home config
seed=$ROOT/origins/seed; origin=$ROOT/origins/notes.git
git init -q -b main "$seed"; printf '# notes\nA tiny lab project.\n' > "$seed/README.md"
git -C "$seed" add -A; git -C "$seed" -c user.name=lab -c user.email=lab@example.invalid commit -q -m seed
git clone -q --bare "$seed" "$origin"; git clone -q "$origin" "$LAB/projects/notes"
printf '# Projects\n\n- notes [local-only +yolo] - tiny lab notes project\n' > "$LAB/data/projects.md"
printf 'tmux\n' > "$LAB/config/backend"
printf 'auto\n' > "$LAB/config/claude-permission-mode"
mkdir -p "$ROOT/treehouse"

# 1. the primary's tmux session (shell in place of the harness CLI's Bash tool)
env -i HOME="$HOME" USER="${USER:-$(id -un)}" LOGNAME="${USER:-$(id -un)}" PATH="$PATH" SHELL=/bin/bash \
  TERM=xterm-256color LANG="${LANG:-C.UTF-8}" TMUX_TMPDIR="$TMUXD" TREEHOUSE_ROOT="$ROOT/treehouse" \
  DISABLE_AUTOUPDATER=1 FM_HOME="$LAB" \
  tmux -f /dev/null -L fm-lab new-session -d -s "$PRIMARY" -n main -x 200 -y 50 -c "$CODE" "bash --noprofile --norc" || exit 1
ltmux set-environment -t "$PRIMARY" META_API_KEY lab-placeholder-not-a-secret
sleep 1
# 2. the external web viewer: a grouped session with a real attached client
ltmux new-session -d -s "$VIEWER" -t "$PRIMARY" || exit 1
python3 -I "$SCEN/attach.py" "$VIEWER" "$TMUXD" & VPID=$!
sleep 2
say "--- tmux sessions (group) and clients"
ltmux list-sessions -F '#{session_name} id=#{session_id} group=#{session_group} attached=#{session_attached} activity=#{session_activity}' | tee -a "$OUT"
ltmux list-clients -F 'client #{client_tty} -> session #{client_session}' | tee -a "$OUT"

# 3. precheck from inside the primary pane
inpane precheck "$CODE" "$ROOT" "$ID"; waitfor "$ROOT/precheck.done" 30
say "--- precheck (run inside the primary pane)"; cat "$ROOT/precheck.txt" | tee -a "$OUT"

# 4. real ship spawn from inside the primary pane
inpane spawn "$CODE" "$ROOT" "$ID"; waitfor "$ROOT/spawn.done" 900 || say "spawn did not finish in time"
cp "$ROOT/spawn.log" "$EV/$TAG-spawn.log"
say "--- fm-spawn.sh tail (full log: $TAG-spawn.log)"; tail -5 "$ROOT/spawn.log" | tee -a "$OUT"
say "--- recorded endpoint in state/$ID.meta"; grep -E '^(window|backend)=' "$LAB/state/$ID.meta" 2>&1 | tee -a "$OUT"
say "--- where the task window actually lives"
ltmux list-windows -a -F '#{session_name}:#{window_name} (#{window_id})' | grep "fm-$ID" | tee -a "$OUT"

# 5. muse credential preflight while the viewer is still the most recent group member
inpane muse "$CODE" "$ROOT" "$ID"; waitfor "$ROOT/muse.done" 300 || say "muse probe did not finish"
say "--- muse credential preflight (META_API_KEY set only on the primary's own session)"; cat "$ROOT/muse.log" | tee -a "$OUT"

# 6. endpoint resolution with viewer alive, then after the viewer closes
inpane endpoint "$CODE" "$ROOT" "$ID" viewer-alive; waitfor "$ROOT/endpoint-viewer-alive.done" 120
say "--- endpoint resolution while the viewer is attached"; cat "$ROOT/endpoint-viewer-alive.txt" | tee -a "$OUT"
kill "$VPID" 2>/dev/null; wait "$VPID" 2>/dev/null
ltmux kill-session -t "$VIEWER"
say "--- viewer closed: kill-session -t $VIEWER; sessions now:"
ltmux list-sessions -F '#{session_name}' | tee -a "$OUT"
inpane endpoint "$CODE" "$ROOT" "$ID" viewer-gone; waitfor "$ROOT/endpoint-viewer-gone.done" 120
say "--- endpoint resolution after the viewer closed"; cat "$ROOT/endpoint-viewer-gone.txt" | tee -a "$OUT"
say "--- worker pane (real claude worker) capture"
ltmux capture-pane -p -t "$(ltmux list-windows -a -F '#{window_id} #{window_name}' | awk -v w="fm-$ID" '$2==w{print $1; exit}')" 2>&1 | tail -25 > "$EV/$TAG-worker-pane.txt"
tail -12 "$EV/$TAG-worker-pane.txt" | tee -a "$OUT"

# teardown
ltmux kill-server 2>/dev/null
"$HELPER" teardown "$LAB" >/dev/null 2>&1
echo "$ID" > "$EV/$TAG-task.id"
say "== lab $TAG finished; root left for trust cleanup: $ROOT"
