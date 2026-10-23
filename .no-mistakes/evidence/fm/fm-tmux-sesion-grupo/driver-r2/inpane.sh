#!/usr/bin/env bash
# Runs INSIDE the lab primary's tmux pane, exactly where a primary harness's
# Bash tool runs firstmate scripts (it inherits that pane's $TMUX/$TMUX_PANE).
# usage: inpane.sh <phase> <code-dir> <root> <id> [label]
set -u
PHASE=$1 CODE=$2 ROOT=$3 ID=$4 LABEL=${5:-}
LAB=$ROOT/home
cd "$CODE" || exit 1
fill_brief() {  # <brief> <task> <spec>
  TASK_TEXT=$2 SPEC_TEXT=$3 python3 -I - "$1" <<'PY'
import os, sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
t = t.replace("{TASK}", os.environ["TASK_TEXT"], 1).replace("{FIRSTMATE_SPEC}", os.environ["SPEC_TEXT"], 1)
open(p, "w", encoding="utf-8").write(t)
PY
}
case "$PHASE" in
precheck)
  {
    echo "TMUX=$TMUX"
    echo "TMUX_PANE=$TMUX_PANE"
    echo "untargeted 'tmux display-message -p #S' from this pane -> $(tmux display-message -p '#S')"
    # shellcheck source=/dev/null
    . "$CODE/bin/fm-backend.sh"; fm_backend_source tmux
    echo "fm_backend_tmux_container_ensure -> '$(fm_backend_tmux_container_ensure)'"
  } > "$ROOT/precheck-$LABEL.txt" 2>&1
  ;;
spawn)
  {
    set -x
    "$CODE/bin/fm-brief.sh" "$ID" notes --mode local-only
    fill_brief "$LAB/data/$ID/brief.md" \
      "Live-validation lab task for a tmux container fix. Do not modify any files. Reply with the single word READY and end your turn." \
      "Do not run any commands and do not modify any files. Reply READY and end your turn. Nothing else is in scope."
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
    # stand-in muse binary: only reached when the credential preflight passes
    printf '#!/bin/sh\necho "LAB-MUSE-PLACEHOLDER launched: credential preflight passed"\nexec sleep 600\n' > "$ROOT/musebin/muse"
    chmod +x "$ROOT/musebin/muse"
    echo "pane's own session (\$TMUX id \$${TMUX##*,}) -> $(tmux display-message -p -t "\$${TMUX##*,}" '#S'): $(tmux show-environment -t "\$${TMUX##*,}" META_API_KEY 2>&1 | sed 's/=.*/=<set>/')"
    MR=$(tmux display-message -p '#S')
    echo "most-recent group member -> $MR: $(tmux show-environment -t "$MR" META_API_KEY 2>&1 | sed 's/=.*/=<set>/')"
    "$CODE/bin/fm-brief.sh" "$MID" notes --mode local-only >/dev/null
    fill_brief "$LAB/data/$MID/brief.md" "Lab muse preflight probe." "Lab probe only."
    "$CODE/bin/fm-tasks-axi.sh" add "$MID" "lab muse preflight" --kind ship --repo notes >/dev/null
    echo "+ fm-spawn.sh $MID ... --harness muse   (no auth.json; META_API_KEY only in the primary's own tmux session env)"
    env -u META_API_KEY PATH="$ROOT/musebin:$PATH" XDG_CONFIG_HOME="$ROOT/xdg" XDG_DATA_HOME="$ROOT/xdg" \
      timeout 150 "$CODE/bin/fm-spawn.sh" "$MID" "$LAB/projects/notes" --mode local-only --yolo on --harness muse
    echo "fm-spawn exit=$?"
  } > "$ROOT/muse.log" 2>&1
  ;;
endpoint)
  {
    echo "+ grep ^window= state/$ID.meta"; grep '^window=' "$LAB/state/$ID.meta"
    echo "+ bin/fm-peek.sh $ID 8"
    "$CODE/bin/fm-peek.sh" "$ID" 8; echo "fm-peek exit=$?"
    echo "+ bin/fm-crew-state.sh $ID"
    FM_CREW_STATE_NO_FORGE=1 "$CODE/bin/fm-crew-state.sh" "$ID"; echo "fm-crew-state exit=$?"
  } > "$ROOT/endpoint-$LABEL.txt" 2>&1
  ;;
esac
touch "$ROOT/$PHASE${LABEL:+-$LABEL}.done"
