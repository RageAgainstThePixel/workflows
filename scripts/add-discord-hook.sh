#!/usr/bin/env bash
# Adds a discord webhook to a repository that doesn't have one yet.
# usage: add-discord-hook.sh <owner/repo> <event>...
# DISCORD_WEBHOOK_URL: discord webhook url, from a secret so it never lives in source control
set -euo pipefail

repo="${1:?usage: add-discord-hook.sh <owner/repo> <event>...}"
shift

if [[ $# -eq 0 ]]; then
  echo "usage: add-discord-hook.sh <owner/repo> <event>..." >&2
  exit 1
fi

if [[ -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
  echo "::warning::DISCORD_WEBHOOK_URL is not set, skipping discord hook for $repo"
  exit 0
fi

existing="$(gh api "repos/$repo/hooks" --jq '[.[] | select(.config.url | test("discord.com"))] | length')"

if [[ "$existing" != "0" ]]; then
  echo "$repo already has a discord hook"
  exit 0
fi

events=()
for event in "$@"; do
  events+=(-f "events[]=$event")
done

gh api -X POST "repos/$repo/hooks" --silent \
  -f name=web -F active=true "${events[@]}" \
  -f "config[url]=${DISCORD_WEBHOOK_URL%/github}/github" -f 'config[content_type]=json' -f 'config[insecure_ssl]=0'
echo "Added discord hook to $repo"
