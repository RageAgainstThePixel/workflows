#!/usr/bin/env bash
# Applies the repository settings that org rulesets and security configurations can't inherit to a GitHub Action repository.
# usage: configure-action-repo.sh <owner/repo> [--dry-run]
# DISCORD_HOOK_SOURCE: existing action repo whose discord release/star hook is copied, so the url never lives in source control
set -euo pipefail

repo="${1:?usage: configure-action-repo.sh <owner/repo> [--dry-run]}"
dry_run="${2:-}"
hook_source="${DISCORD_HOOK_SOURCE:-RageAgainstThePixel/unity-action}"

if [[ ! "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "invalid repository: $repo" >&2
  exit 1
fi

# action.yml name must be unique across the whole Marketplace
action_yaml=""
for file in action.yml action.yaml; do
  if action_yaml="$(gh api "repos/$repo/contents/$file" -H 'Accept: application/vnd.github.raw' 2>/dev/null)"; then
    break
  fi
  action_yaml=""
done

if [[ -z "$action_yaml" ]]; then
  echo "$repo has no action.yml on its default branch" >&2
  exit 1
fi

action_name="$(printf '%s\n' "$action_yaml" | sed -n 's/^name:[[:space:]]*//p' | head -n 1 | tr -d "\r\"'")"
slug="$(printf '%s' "$action_name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"

# repos created from the template keep its action name until they are renamed
if [[ "$action_name" == "github-action-template" ]]; then
  echo "::warning::$repo still uses the template action name; rename it in action.yml and check it is unused on the Marketplace"
else
  listing="$(mktemp)"
  trap 'rm -f "$listing"' EXIT
  status="$(curl -sS -o "$listing" -w '%{http_code}' "https://github.com/marketplace/actions/$slug")"

  if [[ "$status" == "200" ]] && ! grep -qF "$repo@" "$listing"; then
    echo "Marketplace name '$action_name' is already taken: https://github.com/marketplace/actions/$slug" >&2
    exit 1
  fi

  echo "Marketplace name '$action_name' is available"
fi

if [[ "$dry_run" == "--dry-run" ]]; then
  echo "dry run: skipping settings for $repo"
  exit 0
fi

gh api -X PATCH "repos/$repo" --silent --input - <<'EOF'
{
  "allow_squash_merge": true,
  "allow_merge_commit": false,
  "allow_rebase_merge": false,
  "squash_merge_commit_title": "PR_TITLE",
  "squash_merge_commit_message": "PR_BODY",
  "delete_branch_on_merge": true,
  "allow_auto_merge": true,
  "allow_update_branch": true,
  "has_wiki": false,
  "has_projects": false,
  "has_discussions": false,
  "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" }
  }
}
EOF

gh api -X PATCH "repos/$repo/properties/values" --silent --input - <<'EOF'
{ "properties": [{ "property_name": "type", "value": "action" }] }
EOF

# org security configuration enables default setup, but only with the default query suite
gh api -X PATCH "repos/$repo/code-scanning/default-setup" -f state=configured -f query_suite=extended --silent

existing="$(gh api "repos/$repo/hooks" --jq '[.[] | select(.config.url | test("discord.com"))] | length')"

if [[ "$existing" == "0" ]]; then
  discord_url="$(gh api "repos/$hook_source/hooks" --jq '[.[] | select(.config.url | test("discord.com"))][0].config.url // empty')"

  if [[ -z "$discord_url" ]]; then
    echo "$hook_source has no discord hook to copy" >&2
    exit 1
  fi

  gh api -X POST "repos/$repo/hooks" --silent \
    -f name=web -F active=true \
    -f 'events[]=release' -f 'events[]=star' \
    -f "config[url]=$discord_url" -f 'config[content_type]=json' -f 'config[insecure_ssl]=0'
  unset discord_url
fi

echo "Configured $repo"
