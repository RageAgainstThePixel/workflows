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
    success=false
    # Retry the operation up to 3 times. Use an if/else around the command so 'set -e' doesn't
    # cause the script to exit on the first non-zero gh exit code. Capture both output and rc
    # for better diagnostics.
    for attempt in {1..3}
    do
        echo "Attempt $attempt of 3"
        if output=$(gh repo create RageAgainstThePixel/"${package}" --public --template RageAgainstThePixel/google-package-archive-template 2>&1); then
            rc=0
        else
            rc=$?
        fi

        echo "gh exit code: ${rc}"
        if [ $rc -eq 0 ]; then
            echo "Repository created successfully @ https://github.com/RageAgainstThePixel/${package}"
            success=true
            break
        else
            # Print the output for debugging. If it looks like a server error, wait then retry.
            echo "gh output: ${output}"
            if [[ ${output} == *"HTTP 5"* ]] || [[ ${output} == *"server error"* ]] || [[ ${output} == *"500"* ]]; then
                echo "Server error detected, waiting before retrying..."
            else
                echo "Non-zero exit from gh; will retry in case of transient issue."
            fi
            sleep 10
        fi
    done

    if [ "$success" = false ]; then
        echo "::error:: Failed to create repository after 3 attempts."
        exit 1
    fi

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

    token=$(gh auth token)
    echo "::add-mask::${token}"
    curl -s -o /dev/null -w "%{http_code}\n" -X PATCH -H "Authorization: token ${token}" -d "${json_payload}" https://api.github.com/repos/RageAgainstThePixel/"${package}"

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
done