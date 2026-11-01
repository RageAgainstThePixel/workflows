#!/bin/bash
set -e -o pipefail
# This script generates GitHub repositories for each Google Unity package
# found on the Google Unity Archive page, using a predefined template repository.

# DISCORD_WEBHOOK_URL: discord webhook for tag announcements, added to every package repository missing it
ensure_discord_hook() {
    local repo="RageAgainstThePixel/${1}"

    if [ -z "${DISCORD_WEBHOOK_URL}" ]; then
        echo "DISCORD_WEBHOOK_URL is not set, skipping discord hook for ${repo}."
        return
    fi

    existing=$(gh api "repos/${repo}/hooks" --jq '[.[] | select(.config.url | test("discord.com"))] | length')

    if [ "${existing}" != "0" ]; then
        return
    fi

    gh api -X POST "repos/${repo}/hooks" --silent \
        -f name=web -F active=true \
        -f 'events[]=create' \
        -f "config[url]=${DISCORD_WEBHOOK_URL%/github}/github" -f 'config[content_type]=json' -f 'config[insecure_ssl]=0'
    echo "Added discord hook to ${repo}."
}

packages=$(curl -sS https://developers.google.com/unity/archive | grep -oP 'com.google.[a-z.-]*\d+\.\d+\.\d+\.tgz' | sed -r 's/-?[0-9]+\.[0-9]+\.[0-9]+\.tgz//g' | sort -u)
echo "Found ${#packages[@]} packages:"
for package in ${packages}; do
    if gh repo view RageAgainstThePixel/"${package}" >/dev/null 2>&1; then
        echo "Repository for ${package} already exists, skipping."
        ensure_discord_hook "${package}"
        continue
    fi

    echo "Creating repository for ${package}..."
    gh repo create RageAgainstThePixel/"${package}" --public --template RageAgainstThePixel/google-package-archive-template
    echo "Repository created successfully @ https://github.com/RageAgainstThePixel/${package}"

    json_payload='{
        "has_issues": false,
        "has_wiki": false,
        "has_projects": false,
        "allow_rebase_merge": false,
        "allow_squash_merge": false,
        "allow_merge_commit": true,
        "delete_branch_on_merge": true,
        "description": "Wrapper over original package distribution. This repository replicates the license terms of his original distribution location. For more information check https://firebase.google.com/terms and https://firebase.google.com/support/release-notes/unity",
        "homepage": "https://developers.google.com/unity/archive"
    }'

    echo "Configuring repository settings for ${package} with metadata:"
    echo "${json_payload}" | jq .

    response_code=$(curl -s -o /dev/null -w "%{http_code}\n" -X PATCH -H "Authorization: token ${GH_TOKEN}" -d "${json_payload}" https://api.github.com/repos/RageAgainstThePixel/"${package}")

    if [ "${response_code}" -ne 200 ]; then
        echo "Failed to configure repository settings for ${package}. HTTP response code: ${response_code}"
        exit 1
    else
        echo "Repository settings configured successfully for ${package}."
    fi

    ensure_discord_hook "${package}"

    echo "::group:: Triggering initial sync workflow for ${package}"
    # Poll for the workflow file to be available
    for i in {1..10}
    do
        echo "Checking if workflow file is available ($i/10)..."
        if gh workflow view upm-sync.yaml -R RageAgainstThePixel/"${package}" > /dev/null 2>&1
        then
            echo "Workflow file is available, running workflow..."
            gh workflow run upm-sync.yaml -R RageAgainstThePixel/"${package}"
            break
        else
            echo "Workflow file is not available yet, waiting..."
            sleep 10
        fi
    done
    echo "::endgroup::"
done