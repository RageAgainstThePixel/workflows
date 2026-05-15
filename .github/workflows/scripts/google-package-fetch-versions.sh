#!/bin/bash
set -e -o pipefail
# This Script fetches the latest versions for a given google package

ARCHIVE=https://developers.google.com/unity/archive
PACKAGE_NAME=$(echo "${GITHUB_REPOSITORY}" | cut -d'/' -f2)

echo "Package name: ${PACKAGE_NAME}"

GIT_VERSIONS=$(git tag | sort -Vu | tr '\n' ',')
ALL_VERSIONS=$(curl -sSf "${ARCHIVE}" | grep -oP "${PACKAGE_NAME}-\K\d+\.\d+\.\d+(?=\.tgz)" | sort -Vu | awk -v last_version="${LAST_VERSION}" '$0 > last_version' | tr '\n' ',')

if [ -z "${GIT_VERSIONS}" ]; then
    VERSIONS=$ALL_VERSIONS
else
    VERSIONS=$(echo "$ALL_VERSIONS" | tr ',' '\n' | awk -v git_versions="${GIT_VERSIONS}" '!index(git_versions,$0)' | tr '\n' ',')
fi

if [ -z "${VERSIONS}" ]; then
    VERSIONS_JSON="[]"
else
    VERSIONS_JSON=$(echo "[\"${VERSIONS//,/\",\"}\"]" | jq -c '. | map(select(length > 0))')
fi

echo "Next versions: ${VERSIONS_JSON}"
echo "versions=${VERSIONS_JSON}" >> "${GITHUB_OUTPUT}"
