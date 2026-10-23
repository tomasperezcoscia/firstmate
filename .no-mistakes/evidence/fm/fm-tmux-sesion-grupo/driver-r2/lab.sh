#!/usr/bin/env bash
# Round-2 live lab. usage: lab.sh <code-dir> <tag> <evidence-dir> <grouped|stale>
#   grouped: the primary's pane lives in cc-firstmate-<pid>; a web viewer
#            attaches a grouped session (the most recent group member); a real
#            ship spawn runs from the primary pane; then the viewer closes.
#   stale:   the primary's pane is opened from the viewer's grouped session; the
#            viewer closes (pane lives on in cc-firstmate-<pid>); then the spawn.
set -u
CODE=$1 TAG=$2 EV=$3 MODE=$4
SCEN=$(cd "$(dirname "$0")" && pwd)
HELPER=/home/tperez/.no-mistakes/worktrees/9cf2fb7d564f/01M5K4X85ZEW3T188VF4DA28W2/bin/fm-lab-home.sh
OUT=$EV/$TAG-transcript.txt; : > "$OUT"
say() { printf '%s\n' "$*" | tee -a "$OUT"; }
ROOT=$(mktemp -d /tmp/fm-lab.XXXXXX); ROOT=$(cd -P "$ROOT" && pwd -P); LAB=$ROOT/home
"$HELPER" create "$LAB" >/dev/null || exit 1
TMUXD=$("$HELPER" tmux-dir "$LAB") || exit 1
NONCE=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n'); ID="lab${NONCE}-ship"
PRIMARY="cc-firstmate-$$"; VIEWER="puente-v-${NONCE}0c1d"
ltmux() { env -i HOME="$HOME" PATH="$PATH" TMUX_TMPDIR="$TMUXD" tmux -L fm-lab "$@"; }
waitfor() { local f=$1 n=${2:-600} i=0; while [ ! -e "$f" ] && [ $i -lt $n ]; do sleep 1; i=$((i+1)); done; [ -e "$f" ]; }
teardown() {
  [ -n "${VPID:-}" ] && kill "$VPID" 2>/dev/null
  ltmux kill-server 2>/dev/null
  "$HELPER" teardown "$LAB" >/dev/null 2>&1
  say "--- teardown: claude trust entries removed for this lab: $(node "$SCEN/forget-trust.js" "$HOME/.claude.json" "$ROOT" 2>&1)"
  chmod -R u+w "$ROOT" 2>/dev/null; rm -rf "$ROOT" /tmp/fm-"$ID" /tmp/fm-"${ID%-ship}"-muse
  say "--- ~/.treehouse unchanged: $(ls -1A "$HOME/.treehouse" 2>/dev/null | sort | diff -q - "$EV/$TAG.treehouse-before" >/dev/null && echo yes || echo NO)"
  rm -f "$EV/$TAG.treehouse-before"
}
trap teardown EXIT
ls -1A "$HOME/.treehouse" 2>/dev/null | sort > "$EV/$TAG.treehouse-before"
say "== lab $TAG ($MODE): code=$CODE ($(git -C "$CODE" rev-parse --short HEAD 2>/dev/null))"
say "lab root=$ROOT task=$ID primary session=$PRIMARY viewer session=$VIEWER"
seed=$ROOT/origins/seed; origin=$ROOT/origins/notes.git
git init -q -b main "$seed"; printf '# notes\nA tiny lab project.\n' > "$seed/README.md"
git -C "$seed" add -A; git -C "$seed" -c user.name=lab -c user.email=lab@example.invalid commit -q -m seed
git clone -q --bare "$seed" "$origin"; git clone -q "$origin" "$LAB/projects/notes"
printf '# Projects\n\n- notes [local-only +yolo] - tiny lab notes project\n' > "$LAB/data/projects.md"
printf 'tmux\n' > "$LAB/config/backend"; printf 'auto\n' > "$LAB/config/claude-permission-mode"; mkdir -p "$ROOT/treehouse"

env -i HOME="$HOME" USER="${USER:-$(id -un)}" LOGNAME="${USER:-$(id -un)}" PATH="$PATH" SHELL=/bin/bash \
  TERM=xterm-256color LANG="${LANG:-C.UTF-8}" TMUX_TMPDIR="$TMUXD" TREEHOUSE_ROOT="$ROOT/treehouse" \
  DISABLE_AUTOUPDATER=1 FM_HOME="$LAB" \
  tmux -f /dev/null -L fm-lab new-session -d -s "$PRIMARY" -n main -x 200 -y 50 -c "$CODE" "bash --noprofile --norc" || exit 1
ltmux set-environment -t "$PRIMARY" META_API_KEY lab-placeholder-not-a-secret
ltmux new-session -d -s "$VIEWER" -t "$PRIMARY" || exit 1
python3 -I "$SCEN/attach.py" "$VIEWER" "$TMUXD" & VPID=$!
sleep 2
if [ "$MODE" = grouped ]; then
  PANE=$(ltmux display-message -p -t "$PRIMARY:main" '#{pane_id}')
else
  PANE=$(ltmux new-window -dP -F '#{pane_id}' -t "$VIEWER:" -n viewer-opened -c "$CODE" "bash --noprofile --norc")
fi
sleep 1
inpane() { ltmux send-keys -t "$PANE" "bash $SCEN/inpane.sh $* ; clear" Enter; }
say "--- primary pane $PANE created in session $(ltmux display-message -p -t "$PANE" '#{session_name}'); sessions and clients:"
ltmux list-sessions -F '#{session_name} id=#{session_id} group=#{session_group} attached=#{session_attached}' | tee -a "$OUT"
ltmux list-clients -F 'client #{client_tty} -> session #{client_session}' | tee -a "$OUT"
inpane precheck "$CODE" "$ROOT" "$ID" viewer-alive; waitfor "$ROOT/precheck-viewer-alive.done" 30
say "--- precheck from the primary pane, viewer attached"; tee -a "$OUT" < "$ROOT/precheck-viewer-alive.txt"

close_viewer() {
  kill "$VPID" 2>/dev/null; wait "$VPID" 2>/dev/null; VPID=
  ltmux kill-session -t "$VIEWER"
  say "--- viewer closed (kill-session -t $VIEWER); sessions now: $(ltmux list-sessions -F '#{session_name}' | tr '\n' ' ')"
  say "primary pane $PANE still lives at: $(ltmux display-message -p -t "$PANE" '#{session_name}:#{window_name}')"
}
if [ "$MODE" = stale ]; then
  close_viewer
  inpane precheck "$CODE" "$ROOT" "$ID" viewer-gone; waitfor "$ROOT/precheck-viewer-gone.done" 30
  say "--- precheck from the primary pane after the viewer closed (\$TMUX now names a killed session)"; tee -a "$OUT" < "$ROOT/precheck-viewer-gone.txt"
fi

inpane spawn "$CODE" "$ROOT" "$ID"; waitfor "$ROOT/spawn.done" 900 || say "spawn did not finish in time"
cp "$ROOT/spawn.log" "$EV/$TAG-spawn.log"
say "--- fm-spawn.sh tail (full log: $TAG-spawn.log)"; grep -E '^(spawned|error|fm-spawn exit)' "$ROOT/spawn.log" | tee -a "$OUT"
say "--- recorded endpoint in state/$ID.meta"; grep -E '^(window|backend)=' "$LAB/state/$ID.meta" 2>&1 | tee -a "$OUT"
say "--- where the task window actually lives"
ltmux list-windows -a -F '#{session_name}:#{window_name} (#{window_id})' | grep "fm-$ID" | tee -a "$OUT"

if [ "$MODE" = grouped ]; then
  inpane muse "$CODE" "$ROOT" "$ID"; waitfor "$ROOT/muse.done" 300 || say "muse probe did not finish"
  cp "$ROOT/muse.log" "$EV/$TAG-muse.log"
  say "--- muse credential preflight (full log: $TAG-muse.log)"
  grep -E "^(pane's own|most-recent|\+ fm-spawn|error|spawned|fm-spawn exit)" "$ROOT/muse.log" | tee -a "$OUT"
  MW=$(ltmux list-windows -a -F '#{window_id} #{window_name}' | awk -v w="fm-${ID%-ship}-muse" '$2==w{print $1; exit}')
  say "muse task window: ${MW:-<none>}${MW:+ -> $(ltmux capture-pane -p -t "$MW" | grep -m1 LAB-MUSE-PLACEHOLDER)}"
  inpane endpoint "$CODE" "$ROOT" "$ID" viewer-alive; waitfor "$ROOT/endpoint-viewer-alive.done" 120
  say "--- endpoint resolution while the viewer is attached"
  grep -E '^\+ |exit=|^state:|^window=|^error' "$ROOT/endpoint-viewer-alive.txt" | tee -a "$OUT"
  close_viewer
fi
inpane endpoint "$CODE" "$ROOT" "$ID" viewer-gone; waitfor "$ROOT/endpoint-viewer-gone.done" 120
cp "$ROOT/endpoint-viewer-gone.txt" "$EV/$TAG-endpoint-after-viewer-closed.txt"
say "--- endpoint resolution after the viewer closed (full: $TAG-endpoint-after-viewer-closed.txt)"
grep -E '^\+ |exit=|^state:|^window=|^error' "$ROOT/endpoint-viewer-gone.txt" | tee -a "$OUT"
WW=$(ltmux list-windows -a -F '#{window_id} #{window_name}' | awk -v w="fm-$ID" '$2==w{print $1; exit}')
[ -n "$WW" ] && ltmux capture-pane -p -t "$WW" > "$EV/$TAG-worker-pane.txt" 2>&1
echo "$ID" > "$EV/$TAG-task.id"
say "== lab $TAG finished"
