#!/bin/bash
set -e -o pipefail
# This script unpacks a google package.tgz and commits it to the repo to get a valid diff from previous version

REGISTRY=https://dl.google.com/games/registry/unity/
git config --local user.email "github-actions[bot]@users.noreply.github.com"
git config --local user.name "GitHub Actions"

echo "::group:: clean workspace"
find . -mindepth 1 ! -regex '^./\..*' -print -delete
echo "::endgroup::"

PACKAGE_NAME=$(echo "${GITHUB_REPOSITORY}" | cut -d'/' -f2)
echo " downloading package ${PACKAGE_NAME}@${MATRIX_VERSION}"
curl -sSf "${REGISTRY}${PACKAGE_NAME}/${PACKAGE_NAME}-${MATRIX_VERSION}.tgz" --output content.tgz

if [ ! -f content.tgz ]; then
    echo "Error: Failed to download package ${PACKAGE_NAME}@${MATRIX_VERSION}"
    exit 1
fi

tar -xzf content.tgz --strip-components=1
rm content.tgz

echo "::group:: commit version changes"
git status -u
git add --all
git commit -m "${PACKAGE_NAME}@${MATRIX_VERSION}"
git tag "${MATRIX_VERSION}"
git push origin main --tags
echo "::endgroup::"
