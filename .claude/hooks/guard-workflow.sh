#!/usr/bin/env bash
# PreToolUse guard for the Issue-Driven Development Workflow in AGENTS.md.
# Blocks Bash commands that only the owner may run; exit code 2 blocks the call and returns stderr to Claude.
# Pattern-based: it catches honest mistakes, not deliberate evasion.

input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
branch=$(git -C "$(jq -r '.cwd // "."' <<<"$input")" rev-parse --abbrev-ref HEAD 2>/dev/null)

block() {
  echo "Blocked by .claude/hooks/guard-workflow.sh: $1. See the Issue-Driven Development Workflow in AGENTS.md." >&2
  exit 2
}

# Check each command segment, ignoring leading VAR=value assignments and git -c/-C options.
while IFS= read -r seg; do
  seg=$(sed -E 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//; s/^git([[:space:]]+-[cC][[:space:]]+[^[:space:]]+)+/git/' <<<"$seg")
  case "$seg" in
    "gh pr merge"*) block "merging pull requests is owner-only" ;;
    "gh issue close"*) block "closing issues is owner-only, after post-merge verification" ;;
    "gh release create"* | "gh release edit"* | "gh release delete"* | "gh release upload"*)
      block "releases are published only on an explicit owner request" ;;
    "gh issue "* | "gh pr "*)
      if [[ $seg == *chatwoot/chatwoot* && ! $seg =~ ^gh\ (issue|pr)\ (view|list|diff|checks|status) ]]; then
        block "upstream chatwoot/chatwoot is read-only"
      fi ;;
    "git push"*)
      [[ $seg =~ [[:space:]]upstream([[:space:]]|$) ]] && block "upstream chatwoot/chatwoot is read-only"
      [[ $seg =~ [[:space:]](-f|--force|--force-with-lease)([[:space:]=]|$)|[[:space:]]\+ ]] && block "force-push is not allowed"
      if [[ $seg =~ [[:space:]:](refs/heads/)?main([[:space:]]|$) || $branch == main ]]; then
        block "pushing to main is not allowed; push the issue branch and open a PR"
      fi ;;
    "git commit"*) [[ $branch == main ]] && block "committing on main is not allowed; work on the issue branch" ;;
  esac
done < <(sed -E 's/&&|\|\||[;|(]/\n/g' <<<"$cmd")

exit 0
