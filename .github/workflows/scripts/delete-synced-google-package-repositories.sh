#!/bin/bash
set -e -o pipefail
# This script deletes all GitHub repositories for each synced Google Unity package

packages=$(curl -sS https://developers.google.com/unity/archive | grep -o 'com.google[^<]*' | cut -d'/' -f1 | grep -v '^com$' | sort -u)
echo "Found ${#packages[@]} packages:"
for package in $packages; do
    if gh repo view RageAgainstThePixel/"${package}" >/dev/null 2>&1; then
        echo "Deleting repository for ${package}..."
        gh repo delete RageAgainstThePixel/"${package}" --yes
    fi
done