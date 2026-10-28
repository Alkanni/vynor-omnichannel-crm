#!/usr/bin/env bash
# PreToolUse guard for the Issue-Driven Development Workflow in AGENTS.md.
# Blocks Bash commands that only the owner may run; exit code 2 blocks the call and returns stderr to Claude.
# Pattern-based: it catches honest mistakes, not deliberate evasion.

input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
cwd=$(jq -r '.cwd // "."' <<<"$input")

block() {
  echo "Blocked by .claude/hooks/guard-workflow.sh: $1. See the Issue-Driven Development Workflow in AGENTS.md." >&2
  exit 2
}

# Global git options that may precede the subcommand (`git -c k=v -C dir --no-pager push ...`).
git_opts='([[:space:]]+((-c|-C|--git-dir|--work-tree|--namespace|--config-env)[[:space:]]+[^[:space:]]+|--[a-z-]+(=[^[:space:]]+)?|-[pP]))+'

# Branch checked out where a git command runs ($1: VAR=value prefix, $2: git command); `git -C <dir>` resolves
# against the session cwd. Prints nothing when that can't be determined (GIT_DIR/--git-dir/--work-tree, several -C,
# a dynamic dir, not a repo); callers treat it like main.
git_branch() {
  local opts dirs dir
  opts=$(grep -oE "^git$git_opts" <<<"$2")
  [[ $1 == *GIT_DIR=* || $1 == *GIT_WORK_TREE=* || $opts == *--git-dir* || $opts == *--work-tree* ]] && return
  mapfile -t dirs < <(grep -oE -- '-C[[:space:]]+[^[:space:]]+' <<<"$opts" | sed -E 's/^-C[[:space:]]+//')
  (( ${#dirs[@]} > 1 )) && return
  dir=${dirs[0]:-.}
  dir=${dir//[\"\']/}
  [[ $dir == *[\$\`]* ]] && return
  git -C "$cwd" -C "${dir/#\~/$HOME}" rev-parse --abbrev-ref HEAD 2>/dev/null
}

# Check each command segment, ignoring leading VAR=value assignments and global git options
# (vars and raw keep them for git_branch and the config-override check).
while IFS= read -r seg; do
  vars=$(grep -oE '^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)+' <<<"$seg")
  raw=$(sed -E 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//' <<<"$seg")
  seg=$(sed -E "s/^git$git_opts/git/" <<<"$raw")
  case "$seg" in
    "gh pr merge"*) block "merging pull requests is owner-only" ;;
    "gh issue close"*) block "closing issues needs an explicit owner instruction; follow the documented close path" ;;
    "gh release create"* | "gh release edit"* | "gh release delete"* | "gh release upload"*)
      block "releases are published only on an explicit owner request" ;;
    "gh issue "* | "gh pr "*)
      if [[ $seg == *chatwoot/chatwoot* && ! $seg =~ ^gh\ (issue|pr)\ (view|list|diff|checks|status) ]]; then
        block "upstream chatwoot/chatwoot is read-only"
      fi ;;
    "git push"*)
      unquoted=${seg//[\"\']/}
      [[ $unquoted =~ [[:space:]]upstream([[:space:]]|$) || $unquoted == *chatwoot/chatwoot* ]] && block "upstream chatwoot/chatwoot is read-only"
      [[ $unquoted =~ [[:space:]](-f|--force|--force-with-lease)([[:space:]=]|$)|[[:space:]]\+ ]] && block "force-push is not allowed"
      [[ $unquoted =~ [[:space:]](--all|--branches|--mirror)([[:space:]=]|$) ]] && block "pushing every branch includes main"
      [[ $unquoted =~ [[:space:]:](refs/heads/)?main([[:space:]]|$) ]] && block "pushing to main is not allowed; push the issue branch and open a PR"
      [[ $seg == *[\$\`\\]* ]] && block "push arguments must be literal so the guard can check them"
      # push.* and remote.* settings can redirect what a push updates (push.default, remote.<name>.push/url/mirror).
      if [[ ${raw,,} =~ (-c|--config-env)[[:space:]=]+(push|remote)\. || $vars == *GIT_CONFIG* ]]; then
        block "push.* and remote.* config overrides are not allowed on push"
      fi
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
      branch=$(git_branch "$vars" "$raw")
      if [[ -z $branch || $branch == main ]]; then
        (( ${#refspecs[@]} )) || block "pushing main is not allowed; push the issue branch and open a PR"
        for ref in "${refspecs[@]}"; do
          [[ $ref =~ ^[A-Za-z0-9._/-]+$ && ! $ref =~ ^(HEAD|main)$ ]] ||
            block "from main, push only explicit non-main branch names (or run the push from the issue worktree)"
        done
      fi ;;
    "git commit"*)
      branch=$(git_branch "$vars" "$raw")
      [[ -z $branch || $branch == main ]] && block "committing on main (or an undetermined branch) is not allowed; work on the issue branch" ;;
  esac
done < <(sed -E 's/&&|\|\||[;|()]/\n/g' <<<"$cmd")

exit 0
