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

# Branch checked out where the git command runs: `git -C <dir>` is resolved against the session cwd.
branch_in() { git -C "$cwd" -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null; }

# Check each command segment, ignoring leading VAR=value assignments and git -c/-C options (the -C dir is kept for branch_in).
while IFS= read -r seg; do
  seg=$(sed -E 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//' <<<"$seg")
  dir=.
  [[ $seg =~ ^git([[:space:]]+-c[[:space:]]+[^[:space:]]+)*[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]] && dir=${BASH_REMATCH[2]/#\~/$HOME}
  seg=$(sed -E 's/^git([[:space:]]+-[cC][[:space:]]+[^[:space:]]+)+/git/' <<<"$seg")
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
      [[ $seg =~ [[:space:]]upstream([[:space:]]|$) ]] && block "upstream chatwoot/chatwoot is read-only"
      [[ $seg =~ [[:space:]](-f|--force|--force-with-lease)([[:space:]=]|$)|[[:space:]]\+ ]] && block "force-push is not allowed"
      [[ $seg =~ [[:space:]](--all|--mirror)([[:space:]]|$) ]] && block "pushing every branch includes main"
      [[ $seg =~ [[:space:]:](refs/heads/)?main([[:space:]]|$) ]] && block "pushing to main is not allowed; push the issue branch and open a PR"
      # Without a refspec (or with HEAD), git pushes the current branch, so that must not be main.
      # Redirections are dropped first so `2>&1` or `> log` aren't mistaken for refspecs.
      read -ra args <<<"$(sed -E 's/^git push//; s/&?[0-9]*>&[0-9-]+//g; s/&?[0-9]*(>>?|<)[[:space:]]*[^[:space:]]+//g' <<<"$seg")"
      remote= refspecs=() skip=
      for arg in "${args[@]}"; do
        if [[ -n $skip ]]; then skip=; continue; fi
        case "$arg" in
          -o | --push-option | --repo | --receive-pack | --exec) skip=1 ;;
          -*) ;;
          *) if [[ -z $remote ]]; then remote=$arg; else refspecs+=("$arg"); fi ;;
        esac
      done
      if [[ $(branch_in "$dir") == main && ( ${#refspecs[@]} -eq 0 || " ${refspecs[*]} " == *" HEAD "* ) ]]; then
        block "pushing main is not allowed; push the issue branch and open a PR"
      fi ;;
    "git commit"*) [[ $(branch_in "$dir") == main ]] && block "committing on main is not allowed; work on the issue branch" ;;
  esac
done < <(sed -E 's/&&|\|\||[;|()]/\n/g' <<<"$cmd")

exit 0
