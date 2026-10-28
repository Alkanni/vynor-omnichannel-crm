#!/usr/bin/env bash
# PreToolUse guard for the Issue-Driven Development Workflow in AGENTS.md.
# Blocks Bash commands that only the owner may run; exit code 2 blocks the call and returns stderr to Claude.
# Scope: direct `git`/`gh` invocations at the start of a command segment (after VAR=value, env, or command
# prefixes). It fails closed on git input it can't read, but it is a pattern check, not a sandbox: other wrappers
# (bash -c, eval, scripts), persistent git config, and API calls are out of scope. Server-side branch protection
# is the control that actually enforces main.

input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
cwd=$(jq -r '.cwd // "."' <<<"$input")

block() {
  echo "Blocked by .claude/hooks/guard-workflow.sh: $1. See the Issue-Driven Development Workflow in AGENTS.md." >&2
  exit 2
}

# Global git options that may precede the subcommand (`git -c k=v -C dir --no-pager push ...`).
git_opts='([[:space:]]+((-c|-C|--git-dir|--work-tree|--namespace|--config-env)[[:space:]]+[^[:space:]]+|--[a-z-]+(=[^[:space:]]+)?|-[pP]))+'

# Branch checked out where a git command runs; `git -C <dir>` resolves against the session cwd.
# Prints nothing when that can't be determined (--git-dir/--work-tree, several -C, not a repo);
# callers treat it like main.
git_branch() {
  local opts dirs dir
  opts=$(grep -oE "^git$git_opts" <<<"$1")
  [[ $opts == *--git-dir* || $opts == *--work-tree* ]] && return
  mapfile -t dirs < <(grep -oE -- '-C[[:space:]]+[^[:space:]]+' <<<"$opts" | sed -E 's/^-C[[:space:]]+//')
  (( ${#dirs[@]} > 1 )) && return
  dir=${dirs[0]:-.}
  git -C "$cwd" -C "${dir/#\~/$HOME}" rev-parse --abbrev-ref HEAD 2>/dev/null
}

# The shell removes quotes and escapes before git/gh see their words, so every word the checks below rely on must
# already be plain: the program name, git's global options and subcommand, and gh's command group and verb.
plain='^[a-z][a-z0-9-]*$'
unsafe=$'["\'\\\\$`]'

# Check each command segment; raw drops leading VAR=value/env/command prefixes and a path on git/gh,
# seg additionally drops the global git options.
while IFS= read -r seg; do
  raw=$(sed -E 's/^[[:space:]]*((env|command)[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//; s#^[^[:space:]]*/(git|gh)([[:space:]]|$)#\1\2#' <<<"$seg")
  read -r first _ <<<"$raw"
  [[ $first =~ $unsafe && ${first//[\"\'\\]/} =~ (^|/)(git|gh)$ ]] && block "write git and gh as plain words"
  seg=$(sed -E "s/^git$git_opts/git/" <<<"$raw")
  if [[ $raw =~ ^git([[:space:]]|$) ]]; then
    opts=$(grep -oE "^git$git_opts" <<<"$raw")
    read -r _ sub _ <<<"$seg"
    [[ $opts =~ $unsafe ]] && block "git options must be plain words (no quotes, escapes, or expansions)"
    [[ -z $sub || $sub =~ $plain ]] || block "the git subcommand must be a plain word"
    # In-command config can redirect a push or hide it behind an alias or include (push.*, remote.*, url.*,
    # alias.*, include.*); allow only core.hooksPath. GIT_CONFIG* is the env form of -c.
    mapfile -t keys < <(grep -oE -- '(-c|--config-env)[[:space:]=]+[^[:space:]=]+' <<<"$opts" | sed -E 's/^(-c|--config-env)[[:space:]=]+//')
    for key in "${keys[@]}"; do
      [[ ${key,,} == core.hookspath ]] || block "git config overrides other than core.hooksPath are not allowed"
    done
    [[ $cmd =~ GIT_CONFIG ]] && block "GIT_CONFIG* overrides are not allowed on git commands"
    # These variables, set anywhere in the command, can retarget a push or commit.
    if [[ $seg =~ ^git[[:space:]]+(push|commit)([[:space:]]|$) && $cmd =~ GIT_(DIR|WORK_TREE) ]]; then
      block "GIT_DIR and GIT_WORK_TREE must not be set around push or commit"
    fi
  fi
  if [[ $raw =~ ^gh[[:space:]] ]]; then
    read -r _ group verb _ <<<"$raw"
    [[ $group =~ $plain ]] || block "the gh command group must be a plain word"
    [[ ! $group =~ ^(pr|issue|release)$ || $verb =~ $plain ]] || block "gh pr/issue/release subcommands must come first, as plain words"
  fi
  case "$seg" in
    "gh pr merge"*) block "merging pull requests is owner-only" ;;
    "gh issue close"*) block "closing issues needs an explicit owner instruction; follow the documented close path" ;;
    "gh release create"* | "gh release edit"* | "gh release delete"* | "gh release upload"*)
      block "releases are published only on an explicit owner request" ;;
    "gh issue "* | "gh pr "*)
      if [[ ${seg,,} == *chatwoot/chatwoot* && ! $seg =~ ^gh\ (issue|pr)\ (view|list|diff|checks|status) ]]; then
        block "upstream chatwoot/chatwoot is read-only"
      fi ;;
    "git push"*)
      unquoted=${seg//[\"\']/}
      [[ ${unquoted,,} =~ [[:space:]]upstream([[:space:]]|$) || ${unquoted,,} == *chatwoot/chatwoot* ]] && block "upstream chatwoot/chatwoot is read-only"
      [[ $unquoted =~ [[:space:]](-f|--force|--force-with-lease)([[:space:]=]|$)|[[:space:]]\+ ]] && block "force-push is not allowed"
      [[ $unquoted =~ [[:space:]](--all|--branches|--mirror)([[:space:]=]|$) ]] && block "pushing every branch includes main"
      [[ $unquoted =~ [[:space:]:](refs/heads/)?main([[:space:]]|$) ]] && block "pushing to main is not allowed; push the issue branch and open a PR"
      [[ $seg == *[\$\`\\]* ]] && block "push arguments must be literal so the guard can check them"
      # From main (or an undetermined branch), allow only explicit non-main branch names: no refspec, HEAD, @,
      # or src:dst forms would push main. Redirections are dropped so `2>&1` or `> log` aren't taken as refspecs.
      read -ra args <<<"$(sed -E 's/^git push//; s/&?[0-9]*>&[0-9-]+//g; s/&?[0-9]*(>>?|<)[[:space:]]*[^[:space:]]+//g' <<<"$unquoted")"
      remote= refspecs=() skip=
      for arg in "${args[@]}"; do
        if [[ -n $skip ]]; then skip=; continue; fi
        case "$arg" in
          -o | --push-option | --repo | --receive-pack | --exec) skip=1 ;;
          -*) ;;
          *) if [[ -z $remote ]]; then remote=$arg; else refspecs+=("$arg"); fi ;;
        esac
      done
      branch=$(git_branch "$raw")
      if [[ -z $branch || $branch == main ]]; then
        (( ${#refspecs[@]} )) || block "pushing main is not allowed; push the issue branch and open a PR"
        for ref in "${refspecs[@]}"; do
          [[ $ref =~ ^[A-Za-z0-9._/-]+$ && ! $ref =~ ^(HEAD|main)$ ]] ||
            block "from main, push only explicit non-main branch names (or run the push from the issue worktree)"
        done
      fi ;;
    "git commit"*)
      branch=$(git_branch "$raw")
      [[ -z $branch || $branch == main ]] && block "committing on main (or an undetermined branch) is not allowed; work on the issue branch" ;;
  esac
done < <(sed -E 's/&&|\|\||[;|()]/\n/g' <<<"$cmd")

exit 0
