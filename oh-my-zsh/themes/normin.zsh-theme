#
# normin — built up from the stock `norm` theme.
#
#   λ mac ~/Documents/UstaTools →  main ●2 ✚1 ?3 ⇡2 →           ✗ 1  4.2s
#   │  │         │                   │   │  │  │  │                │    │
#   │  │         │                   │   │  │  │  │                │    └─ duration of last command
#   │  │         │                   │   │  │  │  │                └────── exit code (only on failure)
#   │  │         │                   │   │  │  │  └─────────────────────── 2 commits not yet pushed
#   │  │         │                   │   │  │  └────────────────────────── 3 untracked files
#   │  │         │                   │   │  └───────────────────────────── 1 file staged
#   │  │         │                   │   └──────────────────────────────── 2 files modified
#   │  │         │                   └──────────────────────────────────── branch
#   │  │         └──────────────────────────────────────────────────────── last 3 path segments
#   │  └────────────────────────────────────────────────────────────────── hostname
#   └───────────────────────────────────────────────────────────────────── red when a command fails
#
# The git segment is computed in a background job via oh-my-zsh's async prompt
# API, so none of it sits on the critical path of drawing your prompt.

# ── KNOBS ────────────────────────────────────────────────────────────────────
# Seconds a command must run before its duration is shown. 0 = always.
: ${NORMIN_DURATION_THRESHOLD:=2}
# Trailing path segments to show. 0 = whole path.
: ${NORMIN_PATH_DEPTH:=3}
# Hostname: useful over ssh, noise on a laptop. 1 = show, 0 = hide.
: ${NORMIN_SHOW_HOST:=1}
# Show counts next to git symbols (●2) or bare flags (●). 1 = counts.
: ${NORMIN_GIT_COUNTS:=1}
# Colors. Any zsh color name (yellow, cyan, ...) or a 0-255 palette number.
: ${NORMIN_HOST_COLOR:=yellow}
# Used for the quiet things: untracked count, command duration.
: ${NORMIN_DIM_COLOR:=242}

zmodload zsh/datetime
autoload -Uz add-zsh-hook

# ── command duration ─────────────────────────────────────────────────────────
# preexec stamps a start time; precmd measures it. Anything under the threshold
# is blanked so fast commands leave no trace.

_normin_preexec() { _normin_start=$EPOCHREALTIME }

_normin_precmd() {
  _normin_elapsed=""
  [[ -z "$_normin_start" ]] && return

  local elapsed=$(( EPOCHREALTIME - _normin_start ))
  unset _normin_start
  (( elapsed < NORMIN_DURATION_THRESHOLD )) && return

  if (( elapsed >= 3600 )); then
    _normin_elapsed=$(printf '%dh%dm' $((elapsed/3600)) $((elapsed%3600/60)))
  elif (( elapsed >= 60 )); then
    _normin_elapsed=$(printf '%dm%ds' $((elapsed/60)) $((elapsed%60)))
  else
    _normin_elapsed=$(printf '%.1fs' $elapsed)
  fi
}

add-zsh-hook preexec _normin_preexec
add-zsh-hook precmd  _normin_precmd

# ── git ──────────────────────────────────────────────────────────────────────
# One `git status --porcelain=v2 --branch` call gives us the branch, the
# ahead/behind counts and every file state, so we parse it once rather than
# shelling out per symbol.
#
# porcelain=v2 line shapes we care about:
#   # branch.head <name>     current branch, or "(detached)"
#   # branch.upstream <ref>  present only when the branch tracks something
#   # branch.ab +N -M        ahead N, behind M   (only when tracking)
#   1 <XY> ... <path>        tracked change   X = staged, Y = worktree
#   2 <XY> ... <path>        renamed/copied
#   u <XY> ... <path>        unmerged
#   ? <path>                 untracked

_normin_git_async() {
  command git rev-parse --is-inside-work-tree &>/dev/null || return
  [[ "$(command git config --get oh-my-zsh.hide-status 2>/dev/null)" = 1 ]] && return

  local -i staged=0 modified=0 deleted=0 untracked=0 unmerged=0 stashed=0
  local -i ahead=0 behind=0 tracking=0
  local branch="" line xy

  while IFS= read -r line; do
    case "$line" in
      '# branch.head '*)     branch="${line#\# branch.head }" ;;
      '# branch.upstream '*) tracking=1 ;;
      '# branch.ab '*)
        local ab="${line#\# branch.ab }"
        ahead=${${ab%% *}#+}
        behind=${${ab##* }#-}
        ;;
      '1 '*|'2 '*)
        xy="${${line#* }%% *}"
        [[ "${xy[1]}" != '.' ]] && (( staged++ ))
        case "${xy[2]}" in
          M|T) (( modified++ )) ;;
          D)   (( deleted++ ))  ;;
        esac
        ;;
      'u '*) (( unmerged++ )) ;;
      '?'*)  (( untracked++ )) ;;
    esac
  done < <(command git status --porcelain=v2 --branch --untracked-files=normal 2>/dev/null)

  [[ -z "$branch" ]] && return
  # Detached HEAD reads better as a short sha than as the literal "(detached)".
  [[ "$branch" == '(detached)' ]] && branch="@$(command git rev-parse --short HEAD 2>/dev/null)"

  # Unpushed commits on a branch with no upstream. git reports no branch.ab in
  # that case, so a never-pushed branch would otherwise look perfectly in sync.
  # Commits reachable from HEAD but from no remote ref are exactly the unpushed
  # ones. Only meaningful once a remote exists — with none, every commit is
  # "unpushed" and the count is just noise.
  if (( ! tracking )) && [[ -n "$(command git remote 2>/dev/null)" ]]; then
    ahead=$(command git rev-list --count HEAD --not --remotes 2>/dev/null) || ahead=0
  fi

  stashed=$(command git rev-list --walk-reflogs --count refs/stash 2>/dev/null) || stashed=0

  # A count of 1 is implied by the symbol itself; only numbers >1 add signal.
  _n() { (( NORMIN_GIT_COUNTS && $1 > 1 )) && print -n "$1" }

  print -n "%F{blue}%f %F{magenta}${branch}%f"
  # An untracked branch is flagged so ⇡ can't be mistaken for "ahead of remote".
  (( tracking )) || print -n "%F{$NORMIN_DIM_COLOR}⌁%f"
  (( modified ))  && print -n " %F{yellow}●$(_n $modified)%f"
  (( staged ))    && print -n " %F{green}✚$(_n $staged)%f"
  (( deleted ))   && print -n " %F{red}✖$(_n $deleted)%f"
  (( untracked )) && print -n " %F{$NORMIN_DIM_COLOR}?$(_n $untracked)%f"
  (( unmerged ))  && print -n " %F{red}═$(_n $unmerged)%f"
  (( stashed ))   && print -n " %F{cyan}⚑$(_n $stashed)%f"
  (( ahead ))     && print -n " %F{cyan}⇡${ahead}%f"
  (( behind ))    && print -n " %F{cyan}⇣${behind}%f"
  print -n " %F{yellow}→%f"
}

# The stub the prompt actually calls: it only reads whatever the background job
# last published. Falls back to synchronous rendering if async isn't available.
if (( ${+functions[_omz_register_handler]} )); then
  _omz_register_handler _normin_git_async
  _normin_git() { print -n "${_OMZ_ASYNC_OUTPUT[_normin_git_async]}" }
else
  _normin_git() { _normin_git_async }
fi

# ── prompt ───────────────────────────────────────────────────────────────────

# %(?.A.B) picks A when the last exit code was 0, B otherwise.
_normin_lambda='%(?.%F{yellow}.%F{red})λ%f'
_normin_path="%F{green}%${NORMIN_PATH_DEPTH}~%f"
(( NORMIN_SHOW_HOST )) && _normin_host=" %F{$NORMIN_HOST_COLOR}%m%f" || _normin_host=''

PROMPT="${_normin_lambda}${_normin_host} ${_normin_path} %F{yellow}→%f"'$(_normin_git)'" "
RPROMPT="%(?..%F{red}✗ %?%f )%F{$NORMIN_DIM_COLOR}"'${_normin_elapsed}'"%f"

# normin renders git itself, so silence oh-my-zsh's built-in git segment in case
# another plugin or theme leaves these set.
ZSH_THEME_GIT_PROMPT_PREFIX=""
ZSH_THEME_GIT_PROMPT_SUFFIX=""
ZSH_THEME_GIT_PROMPT_DIRTY=""
ZSH_THEME_GIT_PROMPT_CLEAN=""
