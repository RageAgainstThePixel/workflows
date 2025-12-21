#!/bin/bash
set -e -o pipefail
# This script generates GitHub repositories for each Google Unity package
# found on the Google Unity Archive page, using a predefined template repository.

packages=$(curl -sS https://developers.google.com/unity/archive | grep -oP 'com.google.[a-z.-]*\d+\.\d+\.\d+\.tgz' | sed -r 's/-?[0-9]+\.[0-9]+\.[0-9]+\.tgz//g' | sort -u)
echo "Found ${#packages[@]} packages:"
for package in ${packages}; do
    if gh repo view RageAgainstThePixel/"${package}" >/dev/null 2>&1; then
        echo "Repository for ${package} already exists, skipping."
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

    token=$(gh auth token)
    echo "::add-mask::${token}"
    response_code=$(curl -s -o /dev/null -w "%{http_code}\n" -X PATCH -H "Authorization: token ${token}" -d "${json_payload}" https://api.github.com/repos/RageAgainstThePixel/"${package}")

    if [ "${response_code}" -ne 200 ]; then
        echo "Failed to configure repository settings for ${package}. HTTP response code: ${response_code}"
        exit 1
    fi

    echo "::start-group::Triggering initial sync workflow for ${package}"
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
    echo "::end-group::"
done