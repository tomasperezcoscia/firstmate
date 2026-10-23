#!/usr/bin/env bash
# Runs INSIDE the lab primary's tmux pane, exactly where a primary harness's
# Bash tool would run firstmate scripts (it inherits $TMUX/$TMUX_PANE).
# usage: inpane.sh <phase> <code-dir> <root> <id>
set -u
PHASE=$1 CODE=$2 ROOT=$3 ID=$4
LAB=$ROOT/home
cd "$CODE" || exit 1
case "$PHASE" in
precheck)
  {
    echo "TMUX=$TMUX"
    echo "TMUX_PANE=$TMUX_PANE"
    echo "untargeted 'tmux display-message -p #S' from this pane -> $(tmux display-message -p '#S')"
    echo "pane's own session (display-message -t \$TMUX_PANE '#{session_name}') -> $(tmux display-message -p -t "$TMUX_PANE" '#{session_name}')"
    # shellcheck source=/dev/null
    . "$CODE/bin/fm-backend.sh"; fm_backend_source tmux
    echo "fm_backend_tmux_container_ensure -> $(fm_backend_tmux_container_ensure)"
  } > "$ROOT/precheck.txt" 2>&1
  ;;
spawn)
  {
    set -x
    "$CODE/bin/fm-brief.sh" "$ID" notes --mode local-only
    TASK_TEXT="Live-validation lab task for a tmux container fix. Do not modify any files. Reply with the single word READY and end your turn." \
    SPEC_TEXT="Do not run any commands and do not modify any files. Reply READY and end your turn. Nothing else is in scope." \
      python3 - "$LAB/data/$ID/brief.md" <<'PY'
import os, sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
t = t.replace("{TASK}", os.environ["TASK_TEXT"], 1).replace("{FIRSTMATE_SPEC}", os.environ["SPEC_TEXT"], 1)
open(p, "w", encoding="utf-8").write(t)
PY
    "$CODE/bin/fm-tasks-axi.sh" add "$ID" "lab grouped-session ship" --kind ship --repo notes
    "$CODE/bin/fm-spawn.sh" "$ID" "$LAB/projects/notes" --mode local-only --yolo on --harness claude --model sonnet --effort low
    echo "fm-spawn exit=$?"
    set +x
  } > "$ROOT/spawn.log" 2>&1
  ;;
muse)
  MID="${ID%-ship}-muse"
  {
    mkdir -p "$ROOT/musebin" "$ROOT/xdg"
    # placeholder only so PATH resolution reaches the credential preflight; never executed
    printf '#!/bin/sh\necho "placeholder muse must not run" >&2\nexit 99\n' > "$ROOT/musebin/muse"; chmod +x "$ROOT/musebin/muse"
    printf 'notes 1\n' > "$LAB/config/project-capacity"
    OWN="\$${TMUX##*,}"
    echo "own session ($(tmux display-message -p -t "$OWN" '#S')) META_API_KEY: $(tmux show-environment -t "$OWN" META_API_KEY 2>&1)"
    echo "most-recent group member ($(tmux display-message -p '#S')) META_API_KEY: $(tmux show-environment -t "$(tmux display-message -p '#S')" META_API_KEY 2>&1)"
    "$CODE/bin/fm-brief.sh" "$MID" notes --mode local-only >/dev/null
    TASK_TEXT="Lab muse preflight probe; never launched." SPEC_TEXT="Never launched." python3 - "$LAB/data/$MID/brief.md" <<'PY'
import os, sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
t = t.replace("{TASK}", os.environ["TASK_TEXT"], 1).replace("{FIRSTMATE_SPEC}", os.environ["SPEC_TEXT"], 1)
open(p, "w", encoding="utf-8").write(t)
PY
    "$CODE/bin/fm-tasks-axi.sh" add "$MID" "lab muse preflight" --kind ship --repo notes >/dev/null
    echo "+ fm-spawn.sh $MID ... --harness muse (META_API_KEY only in the primary's own tmux session env; XDG auth.json absent)"
    env -u META_API_KEY PATH="$ROOT/musebin:$PATH" XDG_CONFIG_HOME="$ROOT/xdg" XDG_DATA_HOME="$ROOT/xdg" \
      "$CODE/bin/fm-spawn.sh" "$MID" "$LAB/projects/notes" --mode local-only --yolo on --harness muse
    echo "fm-spawn exit=$?"
    rm -f "$LAB/config/project-capacity"
  } > "$ROOT/muse.log" 2>&1
  ;;
endpoint)
  LABEL=$5
  {
    echo "+ grep ^window= state/$ID.meta"; grep '^window=' "$LAB/state/$ID.meta"
    echo "+ bin/fm-peek.sh $ID 12"
    "$CODE/bin/fm-peek.sh" "$ID" 12; echo "fm-peek exit=$?"
    echo "+ bin/fm-crew-state.sh $ID"
    FM_CREW_STATE_NO_FORGE=1 "$CODE/bin/fm-crew-state.sh" "$ID"; echo "fm-crew-state exit=$?"
  } > "$ROOT/endpoint-$LABEL.txt" 2>&1
  ;;
esac
touch "$ROOT/$PHASE${5:+-$5}.done"
