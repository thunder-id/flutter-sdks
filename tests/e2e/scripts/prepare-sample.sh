#!/usr/bin/env bash
#
# Fetch the Flutter Quickstart sample from the samples repository and point it at this SDK
# checkout, so the E2E suite and the PR builder exercise the local plugin rather than the release
# published on pub.dev. Prints the prepared sample directory on stdout; progress goes to stderr.
#
# Environment:
#   THUNDERID_SAMPLES_DIR   An existing local checkout of the samples repository to copy the sample
#                           from, never modified (default: fetch one into tests/e2e/.samples)
#   THUNDERID_SAMPLES_REPO  Repository to fetch (default https://github.com/thunder-id/samples.git)
#   THUNDERID_SAMPLES_REF   Branch, tag or commit to fetch (default main)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2E_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$E2E_DIR/../.." && pwd)"

SAMPLES_REPO="${THUNDERID_SAMPLES_REPO:-https://github.com/thunder-id/samples.git}"
SAMPLES_REF="${THUNDERID_SAMPLES_REF:-main}"
# The quickstart's path in the samples repository. A samples checkout from before the quickstarts
# were renamed has it at the bare platform name, so an older THUNDERID_SAMPLES_REF still works.
SAMPLE_PATHS=("quickstarts/quickstart-flutter" "quickstarts/flutter")

# Prints the first of SAMPLE_PATHS that holds a sample under the given samples checkout.
find_sample() {
    local path
    for path in "${SAMPLE_PATHS[@]}"; do
        if [ -f "$1/$path/pubspec.yaml" ]; then echo "$path"; return 0; fi
    done
    echo "ERROR: no Flutter Quickstart sample at ${SAMPLE_PATHS[*]} in $1." >&2
    return 1
}

if [ -n "${THUNDERID_SAMPLES_DIR:-}" ]; then
    source_root="$(cd "$THUNDERID_SAMPLES_DIR" && pwd)"
    sample_path="$(find_sample "$source_root")"
    samples_dir="$E2E_DIR/.samples"
    echo "==> Copying the sample from $source_root/$sample_path" >&2
    rm -rf "$samples_dir"
    mkdir -p "$samples_dir/$sample_path"
    rsync -a --exclude build --exclude .dart_tool --exclude pubspec_overrides.yaml \
        "$source_root/$sample_path/" "$samples_dir/$sample_path/"
else
    samples_dir="$E2E_DIR/.samples"
    echo "==> Fetching $SAMPLES_REPO@$SAMPLES_REF into $samples_dir" >&2
    # init + fetch rather than clone, so a re-run updates the existing checkout in place and the
    # ref can be a commit as well as a branch or tag.
    git init -q "$samples_dir"
    git -C "$samples_dir" fetch -q --depth 1 "$SAMPLES_REPO" "$SAMPLES_REF"
    git -C "$samples_dir" checkout -q --force FETCH_HEAD
    # Drop anything a previous run left behind (build output, a copied sample).
    git -C "$samples_dir" clean -q -f -d -x
    sample_path="$(find_sample "$samples_dir")"
fi

sample_dir="$samples_dir/$sample_path"

echo "==> Pointing the sample at the local SDK in $REPO_ROOT" >&2
# pubspec_overrides.yaml takes precedence over the sample's pub.dev constraint without editing
# its pubspec.yaml.
cat > "$sample_dir/pubspec_overrides.yaml" <<YAML
dependency_overrides:
  thunderid_flutter:
    path: $REPO_ROOT
YAML

echo "$sample_dir"
