# session-orchestration's shell library, sourced by the skills' scripts: the project's coordination config and
# the date/file-time helpers that differ between GNU (Linux) and BSD (macOS).
#
# Config: two JSON files, each the nearest one up from the cwd within the project (a folder with its own adapter
# ends the walk: a subproject never reads its parent's), merged key by key (the person's file wins), over the
# person-wide user_config (any key but team, which only the project's file sets):
#   .claude/coordination/coordination.json   repo keys: tracker, host, key_pattern, features.review_inbox
#                                            (excluded from git until shared mode commits it; read from the team
#                                            repo's when the person file names one, see shared_dir)
#   .claude/coordination.local.json          person keys: approvals.delegate, approvals.pr_create, features.accounts,
#                                            features.accounts_weekly_switch, features.notify, features.retro, features.remote,
#                                            retro.*, start.*,
#                                            terminal, messages
#                                            (and its module's block, e.g. msgraph), trusted, team, feedback.mode,
#                                            feedback.repo_dir, feedback.project_dir, telemetry, handoff.*, compact.window,
#                                            pending.file, history.dirs, coordinator.purpose (always excluded;
#                                            the repo file can't set them)
# No file means every default. `config KEY` prints the key's value; an unknown value prints the default and one
# warning line on stderr.
# Modules (terminals/<name>.sh, messages/<name>.sh, features/<name>.sh): found by find_module, checked and sourced by load_module.
# ponytail: modules found by name along a fixed path (project-local, committed+trusted, person, plugin); a registry
# with manifests and dependencies when a module needs another, or a catalog of third-party modules appears.
LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# The project layout this plugin migrates to (session-status --init --migrate, stamped in P/setup.json): the highest
# migration id (m1…) whose detector session-init's --check has, 10 once h1 and h2 joined m9. A release that adds a
# migration adds 1.
LAYOUT=12

# pm_dir: the project-memory plugin's folder (plugin.json lists it as a dependency): the sibling in a checkout of the
# marketplace, else the installed copy of this account (installed_plugins.json) that has the scripts, this
# marketplace's (session-orchestration) over another's. Fails with a message on stderr.
pm_dir() {
  local d f
  [ -f "$LIB_DIR/../project-memory/.claude-plugin/plugin.json" ] && { (cd "$LIB_DIR/../project-memory" && pwd); return 0; }
  f=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json
  d=$(jq -r '.plugins | to_entries | map(select(.key | startswith("project-memory@")))
      | sort_by(.key == "project-memory@session-orchestration") | .[].value[].installPath' "$f" 2>/dev/null |
    while read -r p; do [ -x "$p/skills/project-memory/cases" ] && echo "$p"; done | tail -1)
  [ -n "$d" ] && { echo "$d"; return 0; }
  echo "project-memory isn't installed: claude plugin install project-memory@session-orchestration" >&2; return 1
}

# coord_file NAME: the nearest .claude/NAME up from the cwd, stopping after the first folder with its own adapter
# (the project's root). A worktree below finds the main checkout's person file even when it has the repo file.
coord_file() {
  local d
  d=$(pwd -P)
  while [ "$d" != / ]; do
    [ -e "$d/.claude/$1" ] && { echo "$d/.claude/$1"; return 0; }
    [ -x "$d/.claude/session-status-adapter" ] && return 1
    d=${d%/*}; d=${d:-/}   # no dirname: a fork per level adds up in a 5 s hook on a loaded machine
  done
  return 1
}

# tracked FILE: git tracks FILE. The person's paths (coordination.local.json, coordination.local/, the local
# adapter) are never taken from a commit: a committed one would trust, delegate or run code for everyone who clones.
tracked() {
  git -C "${1%/*}" ls-files --error-unmatch -- "${1##*/}" >/dev/null 2>&1 || return 1   # callers pass DIR/FILE
  echo "warning: $1 is committed: a personal file is never read from git: ignored" >&2
}
# person_file: the person's coordination.local.json, unless it's committed.
person_file() { local f; f=$(coord_file coordination.local.json) && ! tracked "$f" && echo "$f"; }

# The files merged; {} when there are none. A file that isn't a JSON object is skipped with a warning. The person
# keys are dropped from the repo file: a committed file never delegates for anyone, nor picks your terminal, nor names
# a personal path (pending.file, history.dirs, docs_watch.files).
user_config() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/session-orchestration/config.json"; }

# person_keys_drop [MODULE]: the jq filter that drops the person keys (and MODULE's messages block) from a repo file;
# coord_json reads the repo file through it, and --shared refuses a team file it would change.
person_keys_drop() {
  echo "del(.approvals, .terminal, .messages, .msgraph, .trusted, .team, .feedback, .telemetry, .handoff, .compact, .pending, .history, .fable, .start, .retro, .docs_watch, .pane, .coordinator, .report_artifacts$( [[ ${1:-} =~ ^[A-Za-z0-9_-]+$ ]] && echo ", .[\"$1\"]")) | if .features | type == \"object\" then del(.features.accounts, .features.accounts_weekly_switch, .features.notify, .features.retro, .features.remote, .features.docs_watch, .features.report_artifacts) else . end"
}

coord_memo= coord_memo_pwd=   # never inherited: valid only for the cwd its caller built it in
coord_json() {
  # a caller that reads several keys sets coord_memo=$(coord_json) once: each build spawns ~15 processes. With
  # coord_memo_pwd set too, the memo holds only there (a `cd ROOT` subshell reading another project builds its own).
  [ -n "${coord_memo:-}" ] && [ "${coord_memo_pwd:-$PWD}" = "$PWD" ] && { echo "$coord_memo"; return 0; }
  local f out='{}' j s m p d drop
  # The block of the person's messages module too (e.g. .slack): its settings can name a command to run.
  # Its name from either person's file, the project's winning.
  p=$(person_file)
  for f in "$(user_config)" "${p:-}"; do
    [ -n "$f" ] && [ -f "$f" ] && j=$(jq -r '.messages // empty | strings' "$f" 2>/dev/null) && [ -n "$j" ] && m=$j
  done
  drop=$(person_keys_drop "${m:-}")
  s=$(shared_dir 2>/dev/null) && s=$s/coordination.json
  # Lowest first: the person's file for every project (person-wide keys such as feedback.*), the repo file, the
  # project's person file.
  for f in "$(user_config)" "$s" "${p:-}"; do
    [ "$f" = "$s" ] && d=$drop || d=.
    [ -n "$f" ] && [ -f "$f" ] || continue
    j=$(jq -ce "if type == \"object\" then $d else error end" "$f" 2>/dev/null) || { echo "warning: $f is not a JSON object: ignored" >&2; continue; }
    out=$(jq -cn --argjson a "$out" --argjson b "$j" '$a * $b')
  done
  echo "$out"
}

# shared_dir: the folder with the committed files, .claude/coordination: the one in the repo the person key team
# names (a path, relative to the project root: a workspace that isn't the repo itself), else the nearest one up.
shared_dir() {
  local p t
  if p=$(person_file) && t=$(jq -r '.team // empty | strings' "$p" 2>/dev/null) && [ -n "$t" ]; then
    t=${t/#\~/$HOME}; [[ $t == /* ]] || t=${p%/.claude/coordination.local.json}/$t
    [ -d "$t/.claude/coordination" ] && { echo "$t/.claude/coordination"; return 0; }
    echo "warning: team=$t has no .claude/coordination: ignored" >&2
  fi
  coord_file coordination
}

sha256_of() { { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1"; } | cut -d' ' -f1; }

# trusted REL: the committed .claude/coordination/REL (shared_dir), when its sha256 is the one the person recorded
# under trusted (setup records it once they've read the file). A new or changed file fails with a warning; no file
# fails silently.
trusted() {
  local d f want
  d=$(shared_dir) && f=$d/$1 && [ -f "$f" ] || return 1
  want=$(coord_json | jq -r --arg k "$1" '.trusted | if type == "object" then .[$k] // empty | strings else empty end')
  [ -n "$want" ] && [ "$(sha256_of "$f")" = "$want" ] && { echo "$f"; return 0; }
  echo "warning: $1 $([ -n "$want" ] && echo changed upstream || echo is not trusted yet): run setup to review it" >&2
  return 1
}

# is_root DIR: DIR is a project root: it has an adapter, or the person file (a team workspace uses the team repo's
# committed adapter).
is_root() { [ -x "$1/.claude/session-status-adapter" ] || [ -f "$1/.claude/coordination.local.json" ]; }
# find_root: the project root up from the cwd.
find_root() {
  local d
  d=$(pwd -P)   # Claude names transcript dirs and reports cwd by the physical path
  # The root has an adapter, or the person file (a team workspace uses the team repo's committed adapter).
  while [ "$d" != / ]; do
    is_root "$d" && { echo "$d"; return; }
    d=${d%/*}; d=${d:-/}   # no dirname: a fork per level adds up in a 5 s hook on a loaded machine
  done
  git rev-parse --show-toplevel 2>/dev/null || pwd
}
# replies_path [ROOT]: the replies folder ROOT's CLAUDE.md section names (ROOT: $ROOT, else find_root), absolute; empty when it
# names none.
replies_path() {
  local root=${1:-${ROOT:-$(find_root)}} r
  r=$(cd "$root" && sed -nE 's/.*[Rr]eplies folder[^`]*`([^`]+)`.*/\1/p' CLAUDE.md CLAUDE.local.md 2>/dev/null | head -1)
  r=${r%/}; r=${r/#\~/$HOME}; case $r in ''|/*) echo "$r" ;; *) echo "$root/$r" ;; esac
}
# proj_dir [ROOT]: ROOT's own folder in the state dir (replies/, memory.md, the handoff file, the briefs, tasks/), outside
# every checkout so a worktree-isolated session writes there; ROOT's physical path, other characters as -.
proj_dir() { local r=${1:-${ROOT:-$(find_root)}}; echo "${XDG_STATE_HOME:-$HOME/.local/state}/session-orchestration/projects/$(enc_path "$r")"; }
# enc_path PATH: PATH as one folder name, each character but a letter or digit a - (Claude Code's project folders, the
# state folders). project-memory's cases and memory-init spell it out: that plugin can't source this file.
enc_path() { sed 's/[^A-Za-z0-9]/-/g' <<<"$1"; }
# pending_path [ROOT]: config pending.file, absolute (relative: to ROOT); empty when unset.
pending_path() {
  local p; p=$(config pending.file 2>/dev/null) && [ -n "$p" ] || return 0
  case $p in /*) echo "$p" ;; *) echo "${1:-${ROOT:-$(find_root)}}/$p" ;; esac
}
# plugin_root: the project root of config feedback.repo_dir, whose coordinator is the plugin coordinator
# (features/plugin-coordinator.md); fails when the key is unset.
plugin_root() { local d; d=$(config feedback.repo_dir 2>/dev/null) && [ -n "$d" ] && (cd "$d" 2>/dev/null && find_root); }
# slug TEXT: lowercase, each run of other characters one dash. A coordinator is named `$(slug FOLDER)-coordinator`
# (register.tsx's nameCoordinator does the same).
slug() { tr 'A-Z' 'a-z' <<<"$1" | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g'; }
# coord_name ROOT: ROOT's coordinator name.
coord_name() { echo "$(slug "$(basename "$1")")-coordinator"; }
# sock_addr PID: the `uds:` address SendMessage reaches a live session at, under any account: every session listens on
# SOCK_DIR/<pid>.sock, a same-user channel. Only a listed pid whose process lives and whose socket exists, never a scan
# of the folder: a dead session's socket can linger. Fails otherwise.
SOCK_DIR=${SESSION_STATUS_SOCK_DIR:-/tmp/cc-socks}
sock_addr() { [[ ${1:-} =~ ^[0-9]+$ ]] && kill -0 "$1" 2>/dev/null && [ -S "$SOCK_DIR/$1.sock" ] && echo "uds:$SOCK_DIR/$1.sock"; }
# coord_live ROOT: ROOT's coordinator, when it runs: a live session by its name in ROOT, under any account sharing
# this transcript store (whatever this project's features.accounts says). Prints its name, and when it's under another
# account, that account and the address SendMessage reaches it at (features.accounts on; off, only from there). Never
# the caller (a subproject named like its parent). Exit 1: not running; 3: not found, but an account's listing failed.
coord_live() {
  local TMP rc out a n p pid; TMP=$(mktemp -d) || return 3
  load_module features accounts list_accounts 2>/dev/null
  # No early exit in awk: list_sessions would die of SIGPIPE, and pipefail would fail a found one.
  out=$(list_sessions | awk -F'\t' -v n="$(coord_name "$1")" -v r="$1" -v me="${CLAUDE_CODE_SESSION_ID:-}" '!f && $2 == n && $1 != me && $3 !~ /^(done|failed|stopped)$/ &&
    ($6 == r || index($6, r "/") == 1) { f = 1; print n "\t" $4 "\t" $9 }
    END { if (!f) exit 1 }')
  rc=$?; [ "$rc" = 0 ] || [ ! -e "$TMP/ask.failed" ] || rc=3
  rm -rf "$TMP"; [ "$rc" = 0 ] || return "$rc"
  IFS=$'\t' read -r n p pid <<<"$out"
  if [ "$p" = claude ]; then echo "$n"
  elif [ "$(config features.accounts 2>/dev/null)" = true ] && a=$(sock_addr "$pid"); then echo "$n, under another account ($p): SendMessage to \"$a\""
  else echo "$n, under another account ($p): SendMessage reaches it only from there"; fi
}
# coord_purpose [ROOT]: config coordinator.purpose of ROOT (default the cwd's project): one line on what its
# coordinator is for, from that project's person file only (.claude/coordination.local.json), never the repo file or
# the person-wide one; empty when unset.
coord_purpose() {
  ( [ -z "${1:-}" ] || cd "$1" 2>/dev/null || exit 0
    local f; f=$(person_file 2>/dev/null) && [ -f "$f" ] || exit 0
    jq -r '.coordinator.purpose | strings | split("\n")[0] // empty | .[0:200] | select(length > 0)' "$f" 2>/dev/null )
}
# report_artifacts_cfg KEY: config features.report_artifacts (the kinds, one per line) or report_artifacts.account (an
# absolute config dir, ~ expanded), from this project's person file only (features/report-artifacts.md): what may
# leave the machine is set per project and per person. Unset or invalid prints nothing (off).
report_artifacts_cfg() {
  local f v
  f=$(person_file 2>/dev/null) && [ -f "$f" ] || return 0
  if [ "$1" = features.report_artifacts ]; then
    v=$(jq -c '.features.report_artifacts // []' "$f" 2>/dev/null) || return 0
    jq -r 'if type == "array" and all(.[]; IN("research", "retro", "design", "review")) then .[] else error end' <<<"$v" 2>/dev/null ||
      echo "warning: config features.report_artifacts=$v is not a list of research, retro, design, review: off" >&2
  else
    v=$(jq -r '.report_artifacts.account // empty | strings' "$f" 2>/dev/null)
    [ -n "$v" ] || return 0
    [[ $v == '~'/* ]] && v=$HOME/${v#'~/'}
    v=${v%/}
    [[ $v == /* ]] && [ -d "$v" ] && echo "$v" ||
      echo "warning: config report_artifacts.account=$v is not an absolute folder: unset" >&2
  fi
  return 0
}
# purpose_set TEXT: writes coordinator.purpose to this project's person file (session-status --purpose).
purpose_set() {
  local t; t=$(one_line "${1:-}")
  [ -n "$t" ] || { echo "usage: session-status --purpose 'ONE LINE, at most 200 characters'" >&2; return 2; }
  person_set purpose '.coordinator.purpose = $v' --arg v "$t"
}
# The person's coordinator registry: one coordinated project per line, ROOT<TAB>ACCOUNT<TAB>EPOCH (the Claude config
# dir and time of its coordinator's last --start). In the state dir, per person, never committed: it names the
# person's projects, so only their own sessions read it (session-status --coordinators).
coord_registry() { echo "${XDG_STATE_HOME:-$HOME/.local/state}/session-orchestration/coordinators.tsv"; }
# tsv_put FILE KEY [LINE]: FILE's line whose first field is KEY replaced by LINE (no LINE: dropped), under a flock on
# FILE.flock (two writers at once each keep their line), in a subshell so fd 9 closes with it.
tsv_put() {
  ( f=$1; mkdir -p "${f%/*}" && exec 9>>"$f.flock" || exit 1
    perl -MFcntl=:flock -e 'alarm 10; open(my $l, ">>&=", 9) or exit 1; flock($l, LOCK_EX) or exit 1' ||
      echo "couldn't lock $f; going on unlocked" >&2
    t=$(mktemp "$f.XXXXXX") || exit 1
    { K=$2 awk -F'\t' '$1 != ENVIRON["K"]' "$f" 2>/dev/null   # not -v: it would read the key's backslashes as escapes
      [ -z "${3:-}" ] || printf '%s\n' "$3"; } > "$t" && mv "$t" "$f" || { rm -f "$t"; exit 1; } )
}
# coord_register ROOT: ROOT's line, added or brought up to date.
coord_register() { tsv_put "$(coord_registry)" "$1" "$(printf '%s\t%s\t%s' "$1" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" "$(date +%s)")"; }
# The person's remote coordinators (features/remote.md): NAME<TAB>KIND<TAB>PURPOSE<TAB>EPOCH, KIND `rc` (one of their
# coordinators on another computer, same claude.ai account, reached by SendMessage over Remote Control). Beside the
# registry, never committed (session-status --remote, --coordinators).
remote_registry() { echo "${XDG_STATE_HOME:-$HOME/.local/state}/session-orchestration/remote.tsv"; }
# one_line TEXT: TEXT as one line of at most 200 characters (control characters as spaces, trimmed), else nothing.
# Characters are counted by jq (code points), the same on GNU and BSD and in any locale.
one_line() { jq -rn --arg v "${1:-}" '$v | gsub("[[:cntrl:]]"; " ") | gsub("^ +| +$"; "") | select(length > 0 and length <= 200)'; }

# remote_flag ROOT: ` --remote-control` when ROOT's config features.remote is on (features/remote.md), else nothing. The
# flag goes before -n: it takes an optional name, and the session's own name (-n) titles it on claude.ai.
remote_flag() { [ "$(cd "$1" 2>/dev/null && config features.remote 2>/dev/null)" != true ] || echo ' --remote-control'; }

# coord_start ROOT: opens ROOT's coordinator in a terminal tab (config terminal), named already so others find it
# before open_pane names it; prints what happened. Exit 1: nothing started (the command to run is printed).
coord_start() {
  local n out rc cmd
  n=$(coord_name "$1")
  # SESSION_STATUS_CLAUDE: the claude command, as for --successor (a dev build's `claude --plugin-dir DIR`).
  local me   # ROOT's config, not the caller's
  me=$(cd "$1" 2>/dev/null && config plan.models.coordinator 2>/dev/null)
  local a   # config plan.advisor.coordinator, where it pairs (as session-status --kind)
  a=$(cd "$1" 2>/dev/null && a=$(config plan.advisor.coordinator 2>/dev/null) && advisor_ok "${me%%/*}" "$a" && echo "$a")
  local rc_; rc_=$(remote_flag "$1")
  # %q: a [1m] model would glob in the shell that runs cmd
  cmd="${SESSION_STATUS_CLAUDE:-claude}${me:+ --model $(printf %q "${me%%/*}") --effort ${me#*/}}${a:+ --advisor $a}$rc_ -n $n 'Act as a coordinator'"
  load_terminal; out=$(open_view "$n" "$1" "$cmd" 2>&1); rc=$?
  case $rc in
    0) [ "${out#reused}" = "$out" ] || { echo "a tab titled \"$n\" is open already ($out), so nothing started: close it, or run $cmd there"; return 1; }
       echo "started $n in $(tilde "$1") ($out)" ;;
    2) echo "no terminal opens it here (config terminal): run in a new terminal: cd $(printf %q "$1") && $cmd"; return 1 ;;
    *) echo "opening it failed ($out): run in a new terminal: cd $(printf %q "$1") && $cmd"; return 1 ;;
  esac
}

# adapter_path ROOT: the project's adapter: ROOT/.claude/session-status-adapter when executable, else the committed
# one once trusted; prints nothing when there's neither. (The plugin's templates are what setup copies, not a
# fallback: they have placeholders.)
adapter_path() {
  [ -x "$1/.claude/session-status-adapter" ] && ! tracked "$1/.claude/session-status-adapter" &&
    { echo "$1/.claude/session-status-adapter"; return 0; }
  local f; f=$(cd "$1" && trusted session-status-adapter) && [ -x "$f" ] && echo "$f"
}

# The code host from the origin remote of the repo at DIR (default: the cwd), else of the first repo below it (a
# workspace), as setup picks it. GitLab isn't supported yet (TODO: GitLab support): none, with a warning.
detect_host() {
  local d=${1:-.} g
  git -C "$d" rev-parse --git-dir >/dev/null 2>&1 ||
    { g=$(find "$d" -mindepth 2 -maxdepth 3 -name .git 2>/dev/null | sort | head -1); [ -z "$g" ] || d=${g%/.git}; }
  case $(git -C "$d" remote get-url origin 2>/dev/null) in
    *github.com*) echo github ;; *bitbucket*) echo bitbucket ;; *forgejo*) echo forgejo ;;
    *gitlab*) echo "warning: a GitLab remote: host=none until GitLab support (a TODO)" >&2; echo none ;;
    *) echo none ;;
  esac
}

# config KEY: the key's value, or its default. Keys and values:
#   tracker             none | github | jira                          default none
#   host                github | bitbucket | forgejo | none           default from the origin remote
#   key_pattern         an ERE matching a task key                    default empty (session-status's own)
#   approvals.delegate  true | false: a coordinator's message counts as the user's approval, except what the
#                       project's CLAUDE.md reserves                    default false
#   approvals.pr_create true | false: a session opens its own task's PR (gh pr create) without an ask (person only)
#                       default true in the plugin coordinator's project (plugin_root), else false
#   feedback.send       ask | auto: auto lets a session open its plugin-feedback PR or issue on the plugin's own repo
#                       (gh pr|issue create) without a relay once feedback scrub passes the title and body (person only)
#                       default ask
#   features.accounts   true | false: ask every Claude account sharing this transcript store (features/accounts.*)
#                                                                       default false
#   features.accounts_weekly_switch  true | false: past 90% of the weekly limit, the coordinator hands over to an
#                       account under it (features/accounts.md, Weekly limits; person only)   default false
#   features.review_inbox  true | false: PR findings go to the review inbox page (features/review-inbox.md);
#                       Bitbucket or Forgejo (TODO: GitHub support)     default false
#   features.remote     true | false: coordinators start with Remote Control, so the person's coordinators on their
#                       other computers reach them (features/remote.md; person only)   default false
#   features.notify     integer minutes, 0 = off: one local macOS notification when an ask has waited unseen this
#                       long (features/notify.md; person only)          default 0
#   start.mode          read_only | propose | at_once: when the coordinator starts a session for new work without the
#                       user's yes (orchestrating-sessions sessions.md, Starting a session; person only)   default read_only
#   start.kinds.feedback_apply  the same values, for a plugin feedback apply session (person only)
#                       default start.mode's value
#   start.sidebar       true | false: a Claude Code Desktop coordinator may start a task as a sidebar session
#                       (start_session); the status doesn't see one (person only)   default false
#   features.retro      true | false: scheduled retro runs and their coordinator doc (features/retro.md; person only)
#                                                                       default false
#   retro.scope         project | plugin | both: whose sessions a retro run reads (person only)   default project
#   retro.schedule      DAY HH:MM, local time, DAY mon…sun (e.g. mon 12:00): when the launcher starts a run (person
#                       only)                                           default empty: by hand only
#   retro.account       a Claude config dir (~ expanded) a scheduled run starts under (person only)
#                                                                       default the current one
#   retro.sections      JSON list of section names (units context waste spend feedback coordinator memory protocol features
#                       sizing), printed one per line (person only)     default empty: every section of the scope
#   terminal            plain | ghostty | your own module's name (find_module terminals NAME): where the pane's
#                       Attach in tab and Logs in split open             default plain
#   messages            none | msgraph | your own module's name (find_module messages NAME): the chat and mail
#                       notices under the status table (messages/msgraph.md)                default none
#   feedback.mode       auto | pr | fork-pr | issue | local: how plugin feedback cases are sent
#                       (skills/orchestrating-sessions/feedback.md)    default auto
#   feedback.repo_dir   a clone of the plugin repo you can push to (~ expanded); its coordinator is the plugin
#                       coordinator (features/plugin-coordinator.md)     default empty
#   feedback.project_dir  this project's feedback cases (feedback --project; ~ expanded, relative: to the project
#                       root; keep it out of git)     default empty: the state dir's feedback-projects/<root>
#   telemetry           full | local | off: what goes to the local usage log (usage below); nothing leaves the machine.
#                       local: pane presses, path counts, task starts, chunk ends and escalations; full: those, and
#                       the faults: hook blocks, refused tool calls, passed-over relays, watcher wakes and script
#                       errors with exit codes. off: nothing. An explicit value stays as set; an invalid one reads as off   default full
#   pane.sections       JSON object, a pane section's slug (PANE_SLUGS) to open | line | hidden: how the coordinator
#                       pane draws it (open: its rows; line: its title alone; hidden: only named in the pane's last
#                       line). Read from this project's .claude/coordination.local.json only, never a committed or
#                       the person-wide file; a title press writes it (session-status --pane-section). Bad entries are
#                       dropped with a warning; hidden reads as line for the on-you sections (PANE_ON_YOU).
#                       default {}: every section open, resolved one line
#   coordinator.purpose one line (at most 200 characters) on what this project's coordinator is for, which other
#                       coordinators route matters by (session-status --coordinators, --purpose writes it). Read from
#                       this project's .claude/coordination.local.json only (coord_purpose)    default empty
#   features.report_artifacts  JSON list of report kinds (research retro design review) a session may publish as a
#                       private claude.ai page (features/report-artifacts.md), printed one per line. This project's
#                       .claude/coordination.local.json only (report_artifacts_cfg)    default empty: off
#   report_artifacts.account  the Claude config dir (~ expanded) whose sessions publish them; needed when
#                       features.accounts is on. The same file only     default empty
#   pending.file        the coordinator's handoff file, *.md, relative to the project root, ~ or absolute (pending_path): its entries' history
#                       and archive (skills/orchestrating-sessions/pending); person only    default empty (none)
#   history.dirs        JSON list of folders (relative to the root, ~ or absolute) the Stop hook keeps a local git
#                       history of, besides the replies folder and handoff files (skills/orchestrating-sessions/history-git);
#                       a folder git tracks is skipped (its history is the project's git); person only   default empty
#   plan.enabled        true | false: the task planner splits big tasks into chunks         default true
#   plan.max_parallel   integer >= 1: chunk sessions at once                                default 3
#   fable.accounts      JSON list of Claude config dirs (~ expanded) whose account has the fable model (person
#                       only; no reliable check exists, so the person lists them)          default empty: none
#   plan.models.KIND    MODEL/EFFORT (effort low|medium|high|xhigh|max; fable only under an account fable.accounts
#                       lists, else the default), KIND design | build | mechanical | review
#                       | release | scan | coordinator | retro | research     default opus/xhigh, opus/medium,
#                       sonnet/medium, opus/xhigh, sonnet/medium, haiku/low, opus/medium, opus/xhigh, opus/high
#                       (coordinator: what coord_start, the feature doc's start and --successor fall back to when the
#                       predecessor's transcript names none; fable/medium under an account fable.accounts lists;
#                       design, review, retro: fable/xhigh there)
#   plan.advisor.KIND   fable | opus | sonnet: session-status --kind KIND adds `--advisor A` for that kind's task
#                       starts, only where advisor_ok holds (the advisor trial; KIND as plan.models)   default unset: off
#   handoff.at.KIND     integer tokens, 0 = off: context where hooks/context-watch.sh asks a session to hand off,
#                       KIND chunk | task | coordinator (person only)   default 125000, 145000, 145000 (a task's
#                       successor starts at ~45K: at 120K, handed-over review rounds handed off again within minutes)
#   handoff.hard_after  integer tokens: the hard stop, this far past handoff.at (person only)   default 25000
#   handoff.stop_room   integer tokens: room left under the compaction ceiling (person only)   default 15000
#   compact.window      integer tokens: the autoCompactWindow sessions are expected to have (person only)
#                                                                       default 220000
# fable_ok: the account a session starts under (FABLE_ACCT, else the current one) has fable: config fable.accounts
# lists its config dir.
fable_ok() {
  local d=${FABLE_ACCT:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}} a
  while IFS= read -r a; do a=${a/#\~/$HOME}; [ -n "$a" ] && [ "${a%/}" = "${d%/}" ] && ! fable_out "$d" && return 0; done < <(config fable.accounts 2>/dev/null)
  return 1
}
# fable_out DIR: the account's Fable limit is reached and hasn't reset. hooks/register.tsx stamps usage/<dir's name>.fable
# with "SESSION<TAB>ROW" when Claude Code adds its "You've hit your Fable limit" row; that row's quotaLimits says
# rejected for seven_day_overage_included until resetsAt (epoch s). No percent is readable: only a hit limit shows.
fable_out() {
  local d=${1%/} s u
  IFS=$'\t' read -r s u 2>/dev/null < "${XDG_CACHE_HOME:-$HOME/.cache}/session-status/usage/${d##*/}.fable" || return 1
  [[ $s =~ ^[A-Za-z0-9-]+$ && $u =~ ^[A-Za-z0-9-]+$ ]] || return 1
  # || :: a glob matching nothing fails cat, which pipefail would make the whole test fail
  { cat "$d"/projects/*/"$s".jsonl "$d"/projects/*/"$s"/subagents/*.jsonl 2>/dev/null || :; } | grep -F "\"$u\"" |
    jq -e --arg u "$u" --argjson now "$(date +%s)" 'select(.uuid == $u) | .quotaLimits // empty |
      select(.status == "rejected" and .rateLimitType == "seven_day_overage_included" and (.resetsAt | numbers) > $now)' \
    >/dev/null 2>&1
}
# fable_no DIR: fable is known not to run under DIR's account: at its Fable limit, or config fable.accounts lists others.
# A fable the user chose by hand stays where nothing says so (the list unset).
fable_no() {
  fable_out "$1" || { [ -n "$(config fable.accounts 2>/dev/null)" ] && ! FABLE_ACCT=$1 fable_ok; }
}
# model_ok MODEL [EFFORT]: a model name the CLI takes (a 1M-context [1m] suffix too), fable only where fable_ok, and
# an effort it takes. The one rule for config plan.models, --plan and --handover's flags.
# FABLE_OK=1: fable passes anyway (a model the user chose for that session by hand, which a handover keeps).
model_ok() {
  local re='^[a-z][a-z0-9.-]*(\[1m\])?$'
  [[ $1 =~ $re ]] && { [ "${FABLE_OK:-}" = 1 ] || [[ $1 != *fable* ]] || fable_ok; } &&
    { [ $# = 1 ] || [[ $2 =~ ^(low|medium|high|xhigh|max)$ ]]; }
}
# effort_step EFFORT N: EFFORT moved N steps (-1, 0, 1) along low medium high xhigh max, held at either end; fails on
# any other EFFORT.
effort_step() {
  local l=(low medium high xhigh max) i j=
  for i in 0 1 2 3 4; do [ "${l[i]}" = "$1" ] && j=$i; done
  [ -n "$j" ] || return 1
  j=$(( j + $2 )); (( j < 0 )) && j=0; (( j > 4 )) && j=4; echo "${l[j]}"
}
# escalate_rung MODEL EFFORT: "MODEL EFFORT" one rung up (session-status --handover --escalate): the effort first, up
# to xhigh; then the model (haiku → sonnet → opus at the same effort, a [1m] suffix kept, a full id taking its next
# family's alias); then opus (or any other model, fable too) xhigh → max; then opus max → fable max where fable_ok.
# Fails at the top (opus/max without fable, fable/max) or on an unknown effort.
escalate_rung() {
  local m=$1 e=$2 s=; [[ $m == *'[1m]' ]] && s='[1m]'
  case $e in
    low|medium|high) echo "$m $(effort_step "$e" 1)" ;;
    xhigh|max) case $m in *haiku*) echo "sonnet$s $e" ;; *sonnet*) echo "opus$s $e" ;;
      *) if [ "$e" = xhigh ]; then echo "$m max"; else [[ $m == *opus* ]] && fable_ok && echo "fable$s max"; fi ;; esac ;;
    *) return 1 ;;
  esac
}
# advisor_ok MODEL ADVISOR: ADVISOR (fable, opus or sonnet) pairs with a MODEL main session: at or above it (opus takes
# fable or opus, sonnet and haiku take any), never on a fable main (only fable pairs there: the same model again), and
# fable only where fable_ok (FABLE_OK=1: anyway, as model_ok). Claude Code drops an advisor below its main model
# silently, so nothing prints one that doesn't pair.
advisor_ok() {
  case $2 in fable) [ "${FABLE_OK:-}" = 1 ] || fable_ok ;; opus|sonnet) ;; *) false ;; esac &&
    case $1 in *fable*) false ;; *opus*) [ "$2" != sonnet ] ;; *sonnet*|*haiku*) ;; *) false ;; esac
}
# denied_tools KIND: the `--disallowedTools=…` flag a task session of KIND starts with, else nothing (coordinator):
# tools it never uses that every request would carry. AskUserQuestion and ScheduleWakeup always (a task asks through
# reply; a background command or the coordinator wakes it); Agent too, except research and review (web-fetch,
# subagents); EnterWorktree where the project's worktrees live in .worktrees/ (git worktree add: EnterWorktree is
# refused there). The `=` form: a spaced list would take the brief that follows as another tool.
denied_tools() {
  local t=AskUserQuestion,ScheduleWakeup
  case $1 in coordinator) return 0 ;; research|review) ;; *) t=Agent,$t ;; esac
  [ ! -d "$(find_root)/.worktrees" ] || t+=,EnterWorktree
  printf ' --disallowedTools=%s' "$t"
}
# last_advisor TRANSCRIPT: the advisor (fable, opus or sonnet) its session last ran with (advisorModel on its last
# main-thread reply), else nothing.
last_advisor() {
  local a
  a=$(grep '"type":"assistant"' "$1" 2>/dev/null | jq -r 'select(.type == "assistant" and .isSidechain != true) | .advisorModel // ""' 2>/dev/null | tail -1)
  [[ $a =~ (fable|opus|sonnet) ]] && echo "${BASH_REMATCH[1]}"
  return 0
}
# last_model TRANSCRIPT: "MODEL EFFORT" its session last ran on (its last main-thread reply; EFFORT is empty from a
# Claude Code that didn't record it), fable included; prints nothing when no reply names a valid one.
last_model() {
  local m e
  read -r m e < <(grep '"type":"assistant"' "$1" 2>/dev/null | jq -r 'select(.type == "assistant" and .isSidechain != true and (.message.model // "") != "<synthetic>")
    | "\(.requestedModel // .message.model // "") \(.effort // "")"' 2>/dev/null | tail -1)   # requestedModel keeps [1m]
  FABLE_OK=1 model_ok "${m:-}" || return 0
  model_ok x "${e:-}" || e=
  echo "$m${e:+ $e}"
}
# docs_watch (features/docs-watch.md): the watched docs pages' slugs, and the plugin's own reviewed list, from the root
DOCS_WATCH_PATTERN='^(prompt-engineering|agent-skills|strengthen-guardrails)/|^cc/(memory|best-practices|skills|sub-agents|hooks-guide|context-window|cross-session-messaging|large-codebases|agent-teams|workflows|goal|plugins/components)$|^cc/.*(claude-md|instruction)'
DOCS_WATCH_PLUGIN_DOC=plugins/session-orchestration/writing-instructions.md
config() {
  local key=${1:-} v ok=
  case $key in
    tracker|host|key_pattern|approvals.delegate|approvals.pr_create|features.accounts|features.accounts_weekly_switch|features.review_inbox|features.notify|start.mode|start.kinds.feedback_apply|start.sidebar|terminal|messages|feedback.mode|feedback.send|feedback.repo_dir|feedback.project_dir|telemetry|pending.file|history.dirs|fable.accounts) ;;
    features.retro|features.remote|retro.scope|retro.schedule|retro.account|retro.sections) ;;
    features.docs_watch|docs_watch.files|docs_watch.pattern) ;;
    plan.enabled|plan.max_parallel|plan.models.design|plan.models.build|plan.models.mechanical|plan.models.review|plan.models.release|plan.models.scan|plan.models.coordinator|plan.models.retro|plan.models.research) ;;
    plan.advisor.design|plan.advisor.build|plan.advisor.mechanical|plan.advisor.review|plan.advisor.release|plan.advisor.scan|plan.advisor.coordinator|plan.advisor.retro|plan.advisor.research) ;;
    handoff.at.chunk|handoff.at.task|handoff.at.coordinator|handoff.hard_after|handoff.stop_room|compact.window) ;;
    pane.sections) pane_sections; return 0 ;;
    coordinator.purpose) coord_purpose; return 0 ;;
    features.report_artifacts|report_artifacts.account) report_artifacts_cfg "$key"; return 0 ;;
    *) echo "unknown config key: ${key:-(none)} (one of tracker host key_pattern approvals.delegate approvals.pr_create features.accounts features.accounts_weekly_switch features.review_inbox features.notify start.mode start.kinds.feedback_apply start.sidebar features.retro features.remote retro.scope retro.schedule retro.account retro.sections features.docs_watch docs_watch.files docs_watch.pattern terminal messages feedback.mode feedback.send feedback.repo_dir feedback.project_dir telemetry pending.file history.dirs fable.accounts coordinator.purpose plan.enabled plan.max_parallel plan.models.{design,build,mechanical,review,release,scan,coordinator,retro,research} plan.advisor.{design,build,mechanical,review,release,scan,coordinator,retro,research} handoff.at.{chunk,task,coordinator} handoff.hard_after handoff.stop_room compact.window pane.sections features.report_artifacts report_artifacts.account)" >&2; return 2 ;;
  esac
  v=$(coord_json | jq -r --arg k "$key" 'getpath($k | split(".")) | if . == null then empty else tostring end')
  [ -n "$v" ] && case $key in
    tracker) case $v in none|github|jira) ok=1 ;; esac ;;
    host) case $v in github|bitbucket|forgejo|none) ok=1 ;; esac ;;
    key_pattern|docs_watch.pattern) { grep -qE -- "$v" </dev/null; [ $? -le 1 ]; } 2>/dev/null && ok=1 ;;
    approvals.delegate|approvals.pr_create|features.accounts|features.accounts_weekly_switch|features.retro|features.remote|features.docs_watch|plan.enabled|start.sidebar) case $v in true|false) ok=1 ;; esac ;;
    retro.scope) case $v in project) ok=1 ;; plugin|both) local pr; ok=1
      # plugin scope has one home: feedback.repo_dir's root when that is set, so all-project numbers are measured once
      pr=$(plugin_root) && [ "$pr" != "$(find_root)" ] &&
        { echo "warning: retro.scope=$v runs only from feedback.repo_dir's root ($pr): project" >&2; echo project; return 0; } ;; esac ;;
    retro.schedule) [[ $v =~ ^(mon|tue|wed|thu|fri|sat|sun)\ ([01][0-9]|2[0-3]):[0-5][0-9]$ ]] && ok=1 ;;
    retro.account) [[ $v == '~'/* ]] && v=$HOME/${v#'~/'}; [[ $v == /* ]] && [ -d "$v" ] && ok=1 ;;   # absolute: the launcher runs from elsewhere
    retro.sections) local l; l=$(jq -r 'if type == "array" and length > 0 and all(.[]; IN("units", "context", "waste", "spend", "feedback", "coordinator", "memory", "protocol", "features", "sizing")) then .[] else error end' <<<"$v" 2>/dev/null) && v=$l && ok=1 ;;
    features.review_inbox) case $v in false) ok=1 ;;
      true) case $(config host 2>/dev/null) in bitbucket|forgejo) ok=1 ;; esac; [ -n "$ok" ] ||
              { echo "warning: features.review_inbox needs host=bitbucket or forgejo (GitHub support is a TODO): off" >&2; echo false; return 0; } ;;
    esac ;;
    terminal) [[ $v =~ ^[A-Za-z0-9_-]+$ ]] && find_module terminals "$v" >/dev/null && ok=1 ;;
    messages) [ "$v" = none ] && ok=1 || { [[ $v =~ ^[A-Za-z0-9_-]+$ ]] && find_module messages "$v" >/dev/null && ok=1; } ;;
    start.*) case $v in read_only|propose|at_once) ok=1 ;; esac ;;
    feedback.mode) case $v in auto|pr|fork-pr|issue|local) ok=1 ;; esac ;;
    feedback.send) case $v in ask|auto) ok=1 ;; esac ;;
    telemetry) case $v in full|local|off) ok=1 ;; esac ;;
    pending.file) [[ $v == '~'/* ]] && v=$HOME/${v#'~/'}; [[ $v == *.md && $v != '~'* && $v != *..* ]] && ok=1 ;;
    # a JSON list of folders, printed one per line
    history.dirs|fable.accounts|docs_watch.files) local l; l=$(jq -r 'if type == "array" and all(.[]; type == "string" and length > 0 and (test("\n") | not)) then .[] else error end' <<<"$v" 2>/dev/null) && v=$l && ok=1 ;;
    plan.max_parallel) [[ $v =~ ^[1-9][0-9]{0,2}$ ]] && ok=1 ;;
    plan.models.*) [[ $v == */* ]] && model_ok "${v%%/*}" "${v#*/}" && ok=1 ;;
    plan.advisor.*) case $v in fable|opus|sonnet) ok=1 ;; esac ;;
    handoff.*|compact.window) [[ $v =~ ^(0|[1-9][0-9]{0,6})$ ]] && ok=1 ;;
    features.notify) [[ $v =~ ^(0|[1-9][0-9]{0,2})$ ]] && ok=1 ;;
    feedback.repo_dir) [[ $v == '~'/* ]] && v=$HOME/${v#'~/'}; [ -d "$v" ] && ok=1 ;;
    feedback.project_dir) [[ $v == '~'/* ]] && v=$HOME/${v#'~/'}; [[ $v != *$'\n'* ]] && ok=1 ;;
  esac
  [ -n "$ok" ] && { echo "$v"; return 0; }
  local kind=; [ "$key" = terminal ] && kind=terminals; [ "$key" = messages ] && kind=messages
  [ -z "$v" ] || echo "warning: config $key=$v is not valid${kind:+ (no $kind/$v.sh found)}: using the default" >&2
  case $key in
    tracker) echo none ;; host) detect_host ;; key_pattern) ;; features.notify) echo 0 ;;
    approvals.pr_create) local pr; pr=$(plugin_root) && [ "$pr" = "$(find_root)" ] && echo true || echo false ;;
    # on where a project names a doc to watch (docs_watch.files)
    features.docs_watch) [ -n "$(config docs_watch.files 2>/dev/null)" ] && echo true || echo false ;;
    # the plugin's own doc, watched from the plugin repo's project only
    docs_watch.files) local pr; pr=$(plugin_root) && [ "$pr" = "$(find_root)" ] && [ -f "$pr/$DOCS_WATCH_PLUGIN_DOC" ] && echo "$DOCS_WATCH_PLUGIN_DOC" ;;
    docs_watch.pattern) echo "$DOCS_WATCH_PATTERN" ;;
    approvals.delegate|features.*|start.sidebar) echo false ;; terminal) echo plain ;; messages) echo none ;;
    start.mode) echo read_only ;; start.kinds.feedback_apply) config start.mode ;;
    feedback.mode) echo auto ;; feedback.send) echo ask ;; feedback.repo_dir|feedback.project_dir|pending.file|history.dirs|fable.accounts|retro.schedule|retro.sections|plan.advisor.*) ;;
    retro.scope) echo project ;; retro.account) echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ;; telemetry) [ -n "$v" ] && echo off || echo full ;;   # a mistyped value opts out
    plan.enabled) echo true ;; plan.max_parallel) echo 3 ;;
    plan.models.*) case ${key#plan.models.} in design|review) v=opus/xhigh ;; build|coordinator) v=opus/medium ;;
        mechanical|release) v=sonnet/medium ;; scan) v=haiku/low ;; retro) v=opus/xhigh ;; research) v=opus/high ;; esac
      # the kinds that default to fable where the account has it (fable_ok), at the same effort; today's model elsewhere
      case ${key#plan.models.} in design|review|coordinator|retro) ! fable_ok || v=fable/${v#*/} ;; esac
      echo "$v" ;;
    handoff.at.chunk) echo 125000 ;; handoff.at.task) echo 145000 ;; handoff.at.coordinator) echo 145000 ;;
    handoff.hard_after) echo 25000 ;; handoff.stop_room) echo 15000 ;; compact.window) echo 220000 ;;
  esac
}

# The coordinator pane's section slugs (hooks/register.tsx sectionSlug: a title, lowercase, its "(…)" dropped), and
# the on-you ones, which are never hidden.
PANE_SLUGS=" waiting-on-you decisions needs-action in-review working landing idle other-sessions leftovers notices stale-prompts stale other-projects pending resolved actions moved waits-on-you you-wait-on new-for-you worked-on tasks sent report-pages scheduled-starts "
PANE_ON_YOU=" waiting-on-you decisions needs-action "
# pane_sections: config pane.sections, from the project's person file only (a per-project, per-person key), as one
# JSON object of its valid entries.
pane_sections() {
  local f j k v out='{}'
  f=$(person_file 2>/dev/null) && [ -f "$f" ] && j=$(jq -c '.pane.sections // {}' "$f" 2>/dev/null) || j='{}'
  [ "$(jq -r type <<<"$j")" = object ] || { echo "warning: config pane.sections=$j is not a JSON object: using the default" >&2; j='{}'; }
  while IFS=$'\t' read -r k v; do
    [[ $PANE_SLUGS == *" $k "* ]] || { echo "warning: config pane.sections: no section $k (one of$PANE_SLUGS): ignored" >&2; continue; }
    case $v in open|line) ;; hidden) [[ $PANE_ON_YOU != *" $k "* ]] ||
      { echo "warning: config pane.sections.$k=hidden: what needs you is never hidden: line" >&2; v=line; } ;;
      *) echo "warning: config pane.sections.$k=$v is not open, line or hidden: ignored" >&2; continue ;; esac
    out=$(jq -c --arg k "$k" --arg v "$v" '.[$k] = $v' <<<"$out")
  done < <(jq -r 'to_entries[] | "\(.key)\t\(.value | tostring)"' <<<"$j")
  echo "$out"
}
# pane_section_set SLUG STATE: pane.sections.SLUG = STATE in the project's person file (.claude/coordination.local.json
# at the root, made when missing), never a committed one. Two quick presses are two runs: a flock(2) on the file (as
# session-status's inbox_lock; held on fd 9 until the run exits) keeps one from losing the other's write, and the write
# goes through the file itself, so its mode and a symlink stay.
pane_section_set() {
  local f out
  [[ $PANE_SLUGS == *" ${1:-} "* ]] && [[ ${2:-} =~ ^(open|line|hidden)$ ]] ||
    { echo "usage: session-status --pane-section SLUG open|line|hidden (SLUG one of$PANE_SLUGS)" >&2; return 2; }
  [ "$2" != hidden ] || [[ $PANE_ON_YOU != *" $1 "* ]] || { echo "pane-section: $1 needs you: open or line only" >&2; return 2; }
  person_set pane-section '.pane.sections[$k] = $v' --arg k "$1" --arg v "$2"
}
# person_set WHO FILTER [JQ_ARGS…]: applies the jq FILTER to the project's person file (.claude/coordination.local.json,
# created at the root when there's none), under a flock; refuses a committed file or one that isn't a JSON object. WHO
# prefixes its messages.
person_set() {
  local who=$1 jf=$2 f out; shift 2
  f=$(coord_file coordination.local.json) || f=$(find_root)/.claude/coordination.local.json
  ! tracked "$f" 2>/dev/null || { echo "$who: $f is committed: not written" >&2; return 1; }
  mkdir -p "${f%/*}" && exec 9>>"$f" || return 1
  perl -MFcntl=:flock -e 'alarm 10; open(my $l, ">>&=", 9) or exit 1; flock($l, LOCK_EX) or exit 1' ||
    echo "$who: couldn't lock $f; going on unlocked" >&2
  [ -s "$f" ] || echo '{}' > "$f" || return 1
  out=$(jq "$@" "if type == \"object\" then $jf else error(\"not a JSON object\") end" "$f") ||
    { echo "$who: $f isn't a JSON object: not written" >&2; return 1; }
  printf '%s\n' "$out" > "$f" && coord_memo=
}

# usage NAME [KIND [MODEL EFFORT EST [ACT]]]: with telemetry=local or full, one line in the local usage log:
# {"t":EPOCH,"k":KIND,"what":NAME}. KIND is press (a pane button, from the mod), path (default: a script counting a
# path no transcript shows) or chunk (session-status --plan --done: NAME is the chunk's kind, then its model, effort,
# est and act in K of context growth; act may be left out) or start (session-status --kind: a plain task start, NAME
# its kind, then its model, effort and optionally the -n session name, logged as sess: the first 12 hex of its sha256,
# so retro can join a start to its session by hashing session names; the name isn't in clear, but someone who knows or
# guesses a name can confirm it; then optionally its size S, M or L, logged as size; env ADVISOR, the advisor it
# starts with, logged as advisor) or escalate (session-status
# --handover --escalate: NAME task or chunk, then the successor's model and effort and the old session's name, as
# sess) or auto (the watcher acting on its own: NAME stop, a finished task's session at rest, or remove, its
# landed worktree). With telemetry=full only, the fault kinds too, as `usage NAME KIND [N [AT]]`, each with the plugin's version
# as v: block (a hook's deny or ask: NAME approved-action-deny|-ask or coordinator-guard-cd|-edit|-sidebar, AT the hook file:line
# that decided), refuse (Claude Code refused a tool call, the PermissionDenied hook: NAME the tool's name), relay (the
# approval hook passed over a relayed approval: NAME why: used-once, no-key, not-landing, unverified), wake
# (session-status --watch: NAME wake with N the lines it reports, poll-failed or gave-up with N the poll's exit code)
# and error (a script's non-zero exit: NAME the script, N its exit code, AT its first argument when a --flag, or the
# file:line that failed). N is an integer, AT a plugin-relative path[:line] or a --flag. NAME is a fixed word
# (lowercase, digits, -), never a key, path or id, and every field is validated, so the file is shareable as is.
# Never fails its caller.
usage_log() { echo "${XDG_STATE_HOME:-$HOME/.local/state}/session-orchestration/usage.jsonl"; }
usage() {
  local f x=
  [[ ${1:-} =~ ^[a-z0-9-]{1,40}$ && ${2:-path} =~ ^(press|path|chunk|start|escalate|auto|block|refuse|relay|wake|error)$ ]] || return 0
  if [[ ${2:-} =~ ^(block|refuse|relay|wake|error)$ ]]; then
    [[ $# -le 4 && ${3:-0} =~ ^[0-9]{1,6}$ && ${4:-x} =~ ^[A-Za-z0-9._-][A-Za-z0-9._/-]{0,79}(:[0-9]{1,5})?$ && ${4:-} != *..* ]] || return 0
    [ "$(config telemetry 2>/dev/null)" = full ] || return 0
    x=",\"v\":\"$(jq -r '.version // ""' "${BASH_SOURCE[0]%/*}/.claude-plugin/plugin.json" 2>/dev/null | tr -cd '0-9.')\"${3:+,\"n\":$((10#$3))}${4:+,\"at\":\"$4\"}"
  elif [ "${2:-}" = start ] || [ "${2:-}" = escalate ]; then
    [[ ${3:-} =~ ^[a-z][a-z0-9.-]{0,39}$ && ${4:-} =~ ^(low|medium|high|xhigh|max)$ && ${5-x} =~ ^[A-Za-z0-9._-]{1,80}$ &&
       ${6-S} =~ ^[SML]$ && $# -le 6 && ( $2 = start || $# = 5 ) ]] || return 0
    x=",\"model\":\"$3\",\"effort\":\"$4\""
    [ $# -ge 5 ] && x+=",\"sess\":\"$(sha256_of <(printf %s "$5") | cut -c1-12)\""
    [ $# = 6 ] && x+=",\"size\":\"$6\""
    [ "$2" = start ] && [[ ${ADVISOR:-} =~ ^(fable|opus|sonnet)$ ]] && x+=",\"advisor\":\"$ADVISOR\""
  elif [ "${2:-}" = chunk ]; then
    [[ ${3:-} =~ ^[a-z][a-z0-9.-]{0,39}$ && ${4:-} =~ ^(low|medium|high|xhigh|max)$ && ${5:-} =~ ^[0-9]{1,4}$ &&
       ${6:-0} =~ ^[0-9]{1,5}$ && $# -le 6 ]] || return 0
    x=",\"model\":\"$3\",\"effort\":\"$4\",\"est\":$((10#$5))${6:+,\"act\":$((10#$6))}"
  fi
  case ${2:-} in block|refuse|relay|wake|error) ;; *) case $(config telemetry 2>/dev/null) in local|full) ;; *) return 0 ;; esac ;; esac
  f=$(usage_log); mkdir -p "${f%/*}" 2>/dev/null &&
    printf '{"t":%s,"k":"%s","what":"%s"%s}\n' "$(date +%s)" "${2:-path}" "$1" "$x" >> "$f" 2>/dev/null
  return 0
}

# coord_re [NAMES]: an ERE matching a coordinator's transcript line: a run of session-status (or NAMES, the adapter's
# status-names alternation) with --start, --changes, --watch or --owner, or an open_pane tool use. A plain run (a worker
# checking its own task) doesn't match, nor a command that only mentions it (`grep 'session-status --watch' f`): it
# must be a command word, at the start or after ;, &, |, ( or a newline, with optional VAR=value prefixes, `bash `
# and a path. session-status and hooks/context-watch.sh both read it; context-watch tests a keyed task or a review
# against coord_pane_re alone (the open_pane branch): one runs session-status --start only to test or measure it.
coord_pane_re() { echo '"(tool_)?name":"mcp__session-orchestration__open_pane"'; }
coord_re() { echo "\"command\":\"([^\"]*([;&|(]|\\\\n))? *([A-Za-z_][A-Za-z0-9_]*=[^\" ]* +)*(bash +)?([^\" ;&|]*/)?(session-status${1:+|$1}) +--(start|changes|watch|owner)|$(coord_pane_re)"; }

# key_re [ADAPTER]: the task-key ERE, in parentheses: config key_pattern, else ADAPTER's key-pattern, else the default.
key_re() {
  local r; r=$(config key_pattern 2>/dev/null)
  [ -n "$r" ] || [ -z "${1:-}" ] || r=$("$1" key-pattern 2>/dev/null) || r=
  echo "(${r:-[A-Z][A-Z0-9]+-[0-9]+})"
}
# first_key FIRST: the key a first prompt names: only at its start (`Work on KEY`, `Session task: KEY`, `Coordinate
# KEY`, `KEY:`), not one it mentions further on (history, an example key in docs work). Needs KEYRE (key_re).
first_key() {
  local l re="^[[:space:]]*(([Ww]ork on|Session task:|Coordinate) +$KEYRE([^0-9]|$)|$KEYRE:)"
  # bash's regex (the system regcomp) has no \w, \< or \b, which grep -E takes: a pattern with a \ goes through grep
  [[ $KEYRE != *\\* ]] || { grep -m 1 . <<<"$1" | grep -oE "$re" | grep -oE "$KEYRE" | head -1; return; }
  while IFS= read -r l; do [ -z "$l" ] || break; done <<<"$1"   # its first non-empty line, in bash: no process per call
  [[ $l =~ $re ]] && l=${BASH_REMATCH[0]} && [[ $l =~ $KEYRE ]] && echo "${BASH_REMATCH[0]}"
}
# sub_key FIRST: KEY when FIRST starts `Coordinate KEY` (a sub-coordinator, KEY-coordinator, run by the project's
# coordinator for one big task: it owns KEY although it runs the coordinator commands); fails otherwise. Needs KEYRE.
sub_key() {
  local l re="^[[:space:]]*Coordinate +" k="^$KEYRE" c="^[[:space:]]*Coordinate +$KEYRE([^0-9]|$)"
  [[ $KEYRE != *\\* ]] || { grep -m 1 . <<<"$1" | grep -oE "$c" | sed -E "s/$re//" | grep -oE "$k"; return; }   # as first_key
  while IFS= read -r l; do [ -z "$l" ] || break; done <<<"$1"
  [[ $l =~ $c ]] && l=${BASH_REMATCH[0]} && [[ $l =~ $re ]] && l=${l:${#BASH_REMATCH[0]}} &&
    [[ $l =~ $k ]] && echo "${BASH_REMATCH[0]}"
}
# first_prompt TRANSCRIPT [N]: its first prompt (within its first N lines: the hook passes 50), a string or text
# blocks, skipping isMeta lines and a compaction summary; "" when none. The hook and session-status.
first_prompt() {
  { if [ -n "${2:-}" ]; then head -n "$2" "$1"; else cat "$1"; fi; } 2>/dev/null | jq -Rrn 'first(inputs | fromjson? | select(.type == "user" and (.isMeta | not)) | .message.content
    | if type == "string" then . elif type == "array" then map(select(.type == "text") | .text) | join("\n") else "" end
    | select(length > 0 and (startswith("This session is being continued") | not))) // ""'
}
# chunk_of FIRST: "KEY N" from a first prompt's `Chunk: KEY/N` line; fails when it has none. The hook and --handover.
chunk_of() {
  local c k; c=$(grep -m1 -oE '^Chunk: [^/]+/[A-Za-z0-9]+' <<<"$1") || return 1
  c=${c#Chunk: }; k=${c%%/*}; k=${k//[^A-Za-z0-9_.-]/}; [ -n "$k" ] && echo "$k ${c#*/}"
}
# compact_window [DIR]: "W SOURCE", the session's autoCompactWindow, in Claude Code's order: the env variable (env),
# DIR's (default $CLAUDE_PROJECT_DIR) .claude/settings.local.json then settings.json (project), the user's
# settings.json (settings), else config compact.window (config).
compact_window() {
  local w=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-} p=${1:-${CLAUDE_PROJECT_DIR:-}} f
  [[ $w =~ ^[0-9]+$ ]] && { echo "$w env"; return 0; }
  for f in ${p:+"project:$p/.claude/settings.local.json" "project:$p/.claude/settings.json"} "settings:${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"; do
    w=$(jq -r '.autoCompactWindow // empty' "${f#*:}" 2>/dev/null); [[ $w =~ ^[0-9]+$ ]] && { echo "$w ${f%%:*}"; return 0; }
  done
  echo "$(config compact.window 2>/dev/null) config"
}

# find_module KIND NAME: the first KIND/NAME.sh along the lookup path; fails when there's none.
#   1. <root>/.claude/coordination.local/KIND/NAME.sh   this person, this project (excluded from git)
#   2. .claude/coordination/KIND/NAME.sh   committed (shared mode): only once trusted, else warned and skipped
#   3. ${XDG_CONFIG_HOME:-~/.config}/session-orchestration/KIND/NAME.sh   this person, every project
#   4. the plugin's KIND/NAME.sh
find_module() {
  local f
  f=$(coord_file "coordination.local/$1/$2.sh") && [ -f "$f" ] && ! tracked "$f" && { echo "$f"; return 0; }
  trusted "$1/$2.sh" && return 0   # checked only when tier 1 has none: a warning only for a file that would run
  for f in "${XDG_CONFIG_HOME:-$HOME/.config}/session-orchestration/$1/$2.sh" "$LIB_DIR/$1/$2.sh"; do
    [ -f "$f" ] && { echo "$f"; return 0; }
  done
  return 1
}

# load_module KIND NAME FUNCTION…: sources KIND/NAME.sh over the defaults already defined. Skipped whole, with a
# warning naming file and line, when it doesn't parse. A contract FUNCTION it doesn't define keeps the default, with
# a warning, and the call fails (so does one for a module found nowhere). One that shadows the plugin's is noted.
load_module() {
  local kind=$1 name=$2 f err miss; shift 2
  f=$(find_module "$kind" "$name") || { echo "warning: $kind/$name.sh found nowhere: not loaded" >&2; return 1; }
  err=$(bash -n "$f" 2>&1) || { echo "warning: ${f/#$HOME/~} skipped: $(head -1 <<<"${err#"$f": }")" >&2; return 1; }
  [ "$f" = "$LIB_DIR/$kind/$name.sh" ] || [ ! -e "$LIB_DIR/$kind/$name.sh" ] || echo "note: $name: using ${f/#$HOME/~}" >&2
  miss=$(unset -f "$@"; . "$f" >/dev/null 2>&1; for fn; do declare -F "$fn" >/dev/null || printf '%s ' "$fn"; done)
  . "$f" >/dev/null || true # its status is its last top-level line's; the probe above checked the functions
  [ -z "$miss" ] || { echo "warning: $kind/$name.sh: no ${miss% }, using the default" >&2; return 1; }
}

# load_terminal: open_view and open_split of the configured terminal (config terminal), over plain's.
load_terminal() {
  local t
  . "$LIB_DIR/terminals/plain.sh" || return 1
  t=$(config terminal) && [ "$t" != plain ] || return 0
  load_module terminals "$t" open_view open_split || true
}

# Sessions.
# ponytail: Claude Code only; another CLI adds runtimes/<name>.sh overriding these two, plus a start/attach command —
# workers of that kind report through the replies file and never get gated actions; a non-Claude coordinator also
# needs send_message and coordinator_log there.

# list_accounts: "CONFIG_DIR<TAB>command prefix" per Claude account whose sessions are asked. The current one only;
# with features.accounts on, every config dir sharing its transcript store (features/accounts.sh replaces this).
list_accounts() {
  if [ "$(config features.accounts 2>/dev/null)" = true ]; then
    load_module features accounts list_accounts 2>/dev/null && { list_accounts; return; }
  fi
  local d=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
  printf '%s\tclaude\n' "${d%/}"
}

# no_cli: when no `claude` is on PATH (Claude Code Desktop alone: its own binary usually isn't), says so with the
# install command and succeeds; else prints nothing and fails. Sessions start with `claude --bg`, list with `claude agents`.
no_cli() {
  command -v claude >/dev/null && return 1
  echo "no claude CLI on PATH (Claude Code Desktop alone?): task sessions start with claude --bg and are listed by claude agents; install it: curl -fsSL https://claude.ai/install.sh | bash"
}

# list_sessions [--all]: one session per line of every account list_accounts names: id, name, state, command prefix
# to reach it, started (epoch s), cwd, kind (background/interactive), status, pid, waitingFor (tabs). `--all` adds
# retired ones (stopped, done, failed, and blocked background ones whose process ended: no pid). A listing that
# failed touches $TMP/ask.failed (when TMP is set): callers mustn't read "not listed" into it.
# state vs status: a background session at rest reads blocked both when it has finished its turn (status idle) and
# when it waits on a permission prompt or a question (status waiting, waitingFor says on what); a running one is busy.
# Agent view (2.1.330 on) reports a finished turn as done with the process alive: that is listed as blocked too, so
# done here means retired, except done with a stale busy status (a cut turn: mid_turn reads it). waitingFor (empty on older engines) has tabs and newlines flattened, 80 chars.
list_sessions() {
  local d pre out
  no_cli >&2 && { [ -z "${TMP:-}" ] || : > "$TMP/ask.failed"; return; }
  while IFS=$'\t' read -r d pre; do
    if [ "$pre" = claude ]; then out=$(claude agents --json "$@" 2>/dev/null)
    elif [ "$d" = "$HOME/.claude" ]; then out=$(env -u CLAUDE_CONFIG_DIR claude agents --json "$@" 2>/dev/null)
    else out=$(CLAUDE_CONFIG_DIR=$d claude agents --json "$@" 2>/dev/null)
    fi
    jq -e 'type == "array"' <<<"$out" >/dev/null 2>&1 || { [ -z "${TMP:-}" ] || : > "$TMP/ask.failed"; continue; }
    # Background sessions report `state` (e.g. blocked) beside `status`. One whose process ended is still listed as
    # blocked, with no pid: it has ended, so only --all lists it.
    jq -r --arg pre "$pre" --arg all "$*" '.[]? | select(.sessionId)
      | select(($all | test("--all")) or .kind != "background" or .pid != null or .state != "blocked")
      | (if .state == "done" and .pid != null and .status != "busy" then "blocked" else .state // .status // "?" end) as $st
      | "\(.sessionId)\t\(.name)\t\($st)\t\($pre)\t\((.startedAt // 0) / 1000 | floor)\t\(.cwd)\t\(.kind // "")\t\(.status // "")\t\(.pid // "")\t\(.waitingFor // "" | tostring | gsub("[\t\n\r]"; " ") | .[:80])"' <<<"$out"
  done < <(list_accounts) |
    # one row per id across accounts: the owning account's (a live process, else not done) beats a stale copy; ties keep the first (this account)
    awk -F'\t' '{ r = $9 != "" ? 2 : $3 !~ /^(done|stopped|failed)$/ } !($1 in b) { o[++n] = $1; b[$1] = $0; k[$1] = r; next }
      r > k[$1] { b[$1] = $0; k[$1] = r } END { for (i = 1; i <= n; i++) print b[o[i]] }'
}

# weekly_use: "CONFIG_DIR<TAB>PERCENT<TAB>RESETS" (whole percent, epoch s) per account list_accounts names, the current
# one first, from the last 7-day reading any of its sessions took (register.tsx's session.measure hook writes
# usage/<config dir's name> under the stamp folder). PERCENT and RESETS are empty with no reading, or once it reset.
weekly_use() {
  local d p r now; now=$(date +%s)
  while IFS=$'\t' read -r d _; do
    p= r=; IFS=$'\t' read -r p r 2>/dev/null < "${XDG_CACHE_HOME:-$HOME/.cache}/session-status/usage/${d##*/}"
    [[ $p =~ ^[0-9]+(\.[0-9]+)?$ && $r =~ ^[0-9]+$ ]] && [ "$r" -gt "$now" ] || p= r=
    printf '%s\t%s\t%s\n' "$d" "${p%.*}" "$r"
  done < <(list_accounts)
}
# weekly_warn [WEEKLY_USE]: one line when this account is past 90% of its weekly limit and another is under it (the
# first listed, not the least used: that one would flip between polls), naming both; nothing otherwise. Stable while
# it holds, so --changes reports it once.
weekly_warn() {
  local d p r cur= cp= cr= best=
  [ "$(config features.accounts_weekly_switch 2>/dev/null)" = true ] || return 0
  while IFS=$'\t' read -r d p r; do
    if [ -z "$cur" ]; then cur=$d cp=$p cr=$r
    elif [ -z "$best" ] && [ -n "$p" ] && [ "$p" -lt 90 ]; then best=$d
    fi
  done <<<"${1-$(weekly_use)}"
  [ -n "$cp" ] && [ "$cp" -ge 90 ] && [ -n "$best" ] || return 0
  printf '%s is past 90%% of its weekly limit (resets %s), %s is under it: hand over to a coordinator under %s (session-status --successor --account %s; features/accounts.md, Weekly limits)\n' \
    "$(tilde "$cur")" "$(epochfmt "$cr" '%m-%d %H:%M')" "$(tilde "$best")" "$(tilde "$best")" "$(tilde "$best")"
}
# tilde PATH: PATH with a leading $HOME as ~ (bash 5.2 expands a bare ~ in ${x/#$HOME/~}, so it goes in a variable).
tilde() { local t='~'; printf '%s' "${1/#$HOME/$t}"; }

# activity_of TRANSCRIPT: session-activity.jq's line (doing, since, last text line, …); last_text: its last text line.
activity_of() { tail -n 2000 "$1" | jq -rRn -f "$LIB_DIR/skills/orchestrating-sessions/session-activity.jq" 2>/dev/null; }
last_text() { activity_of "$1" | cut -f3; }

# chain_transcripts TRANSCRIPT MINS: TRANSCRIPT, then each coordinator it succeeds, back along the typed first prompt's
# `You succeed "NAME" (ID8)` (session-status --successor), one path a line. A predecessor counts while it was written
# to within MINS minutes, never ran a bg turn and went by NAME; the walk stops at the first that doesn't.
chain_transcripts() {
  local t=$1 mins=$2 first name p i
  echo "$t"
  for i in $(seq 50); do   # a bound against a cycle of prompts
    first=$(jq -rn 'first(inputs | select(.type == "user")) | select(.origin.kind == "human") | .message.content
          | if type == "string" then . else ([.[]? | .text? // empty] | join(" ")) end' "$t" 2>/dev/null |
        grep -oE 'You succeed "[^"]*" \([0-9a-f]{8}\)' | head -1)
    [ -n "$first" ] || return 0
    name=${first#You succeed \"}; name=${name%\" (*}; p=${first##*(}; p=${p%)}
    set -- "$(dirname "$t")/$p"*.jsonl; [ $# = 1 ] && [ -f "$1" ] && [ "$1" != "$t" ] || return 0
    t=$1; [ -n "$(find "$t" -mmin "-$mins")" ] || return 0
    [ "$(jq -rn --arg n "$name" 'reduce inputs as $e ({bg: false, named: false};
        if $e.sessionKind == "bg" then .bg = true elif $e.type == "agent-name" and $e.agentName == $n then .named = true else . end)
        | if (.bg | not) and .named then "ok" else "no" end' "$t" 2>/dev/null)" = ok ] || return 0
    echo "$t"
  done
}

# mtime FILE…: each file's modification time (epoch s). mtime_named FILE…: "EPOCH PATH" per file. stat_sig FILE…:
# "EPOCH SIZE INODE PATH" per file (a rewrite in the same second still changes its size or inode).
if stat -c %Y / >/dev/null 2>&1; then
  mtime() { stat -c %Y -- "$@"; }
  mtime_named() { stat -c '%Y %n' -- "$@"; }
  stat_sig() { stat -c '%Y %s %i %n' -- "$@"; }
else
  mtime() { stat -f %m -- "$@"; }
  mtime_named() { stat -f '%m %N' -- "$@"; }
  stat_sig() { stat -f '%m %z %i %N' -- "$@"; }
fi

# dayfmt YYYY-MM-DD FORMAT [±N]: that day (local midnight), N days later or earlier, in date's FORMAT; fails on a
# date that doesn't exist. epoch YYYY-MM-DD: its local midnight in epoch seconds. epochfmt SECONDS FORMAT: that
# moment, local time, in date's FORMAT. at_epoch 'YYYY-MM-DD HH:MM': that local minute in epoch seconds; fails on one
# that doesn't exist.
if date -d @0 +%s >/dev/null 2>&1; then
  dayfmt() { date -d "$1 ${3:-+0} days" +"$2" 2>/dev/null; }
  epochfmt() { date -d "@$1" +"$2"; }
  at_epoch() { local e; e=$(date -d "$1" +%s 2>/dev/null) && [ "$(epochfmt "$e" '%F %H:%M')" = "$1" ] && echo "$e"; }
else
  dayfmt() { date -j -v"${3:-+0}"d -f '%F %T' "$1 00:00:00" +"$2" 2>/dev/null; }
  epochfmt() { date -r "$1" +"$2"; }
  at_epoch() { local e; e=$(date -j -f '%F %T' "$1:00" +%s 2>/dev/null) && [ "$(epochfmt "$e" '%F %H:%M')" = "$1" ] && echo "$e"; }
fi
epoch() { dayfmt "$1" %s; }
