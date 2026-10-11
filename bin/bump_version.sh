#!/usr/bin/env bash
#
# bump_version.sh — Bump version and build number, commit, and tag locally.
#
# Usage:
#   ./bin/bump_version.sh v2.5.0           # release
#   ./bin/bump_version.sh v2.5.0-beta.1    # pre-release
#
# Versions follow Semantic Versioning 2.0.0; pre-releases carry a -beta.N suffix.
#
# What it does:
#   1. Validates the version format (vX.Y.Z or vX.Y.Z-beta.N).
#   2. Checks the working tree is clean.
#   3. Ensures the tag does not already exist.
#   4. Derives the next build number: the larger of the appcast's last
#      sparkle:version and the project's CURRENT_PROJECT_VERSION, plus 1.
#   5. Updates MARKETING_VERSION (main app target only, X.Y.Z without the -beta.N
#      suffix) and CURRENT_PROJECT_VERSION (all targets) in project.pbxproj.
#   6. For a release, moves the [Unreleased] entries of CHANGELOG.md under
#      "## [X.Y.Z] - date" (bin/changelog.py). A pre-release leaves them under
#      [Unreleased].
#   7. Commits with "Version bump to vX.Y.Z (build N)".
#   8. Creates a local git tag vX.Y.Z, unsigned like the earlier release tags.
#
# Push manually when ready:
#   git push origin main --tags

set -euo pipefail

PBXPROJ="Volume Control.xcodeproj/project.pbxproj"
APPCAST="Releases/VolumeControlCast.xml"

# ── Argument validation ────────────────────────────────────────────────────────

VERSION="${1:-}"

if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$ ]]; then
    echo "Usage: $0 vX.Y.Z | vX.Y.Z-beta.N"
    exit 1
fi

SHORT="${VERSION#v}"   # strip leading 'v', e.g. "2.5.0" or "2.5.0-beta.1"
BASE="${SHORT%%-*}"    # without the pre-release suffix, e.g. "2.5.0"

# ── Pre-flight checks ──────────────────────────────────────────────────────────

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Error: working tree is dirty. Commit or stash changes first."
    exit 1
fi

if git rev-parse --verify --quiet "$VERSION" > /dev/null; then
    echo "Error: tag '$VERSION' already exists."
    exit 1
fi

# ── Derive build number ────────────────────────────────────────────────────────
# Take the larger of the most recent sparkle:version in the appcast and the
# CURRENT_PROJECT_VERSION in project.pbxproj, and increment by 1. A pre-release
# does not update the appcast, so after one the project holds the higher
# number; reusing it would give the next release the pre-release's build
# number, and Sparkle would not offer the release to the pre-release's users.

APPCAST_BUILD=$(grep -o '<sparkle:version>[0-9]*</sparkle:version>' "$APPCAST" \
    | head -1 \
    | sed 's/<[^>]*>//g')

if [[ -z "$APPCAST_BUILD" ]]; then
    echo "Error: could not read last build number from $APPCAST."
    exit 1
fi

PROJECT_BUILD=$(grep -o 'CURRENT_PROJECT_VERSION = [0-9]*;' "$PBXPROJ" \
    | sed 's/[^0-9]//g' \
    | sort -n \
    | tail -1)

if [[ -z "$PROJECT_BUILD" ]]; then
    echo "Error: could not read CURRENT_PROJECT_VERSION from $PBXPROJ."
    exit 1
fi

LAST_BUILD=$(( APPCAST_BUILD > PROJECT_BUILD ? APPCAST_BUILD : PROJECT_BUILD ))
NEW_BUILD=$(( LAST_BUILD + 1 ))

echo "Bumping to ${VERSION} (build ${NEW_BUILD})..."

# ── Update project.pbxproj ─────────────────────────────────────────────────────
#
# MARKETING_VERSION strategy:
#   - Main app target uses 3-component versioning (e.g. 0.0.0, 2.1.0).
#   - Helper target uses 2-component versioning (1.0) — left unchanged.
#   A regex that matches exactly X.Y.Z (three numeric components) naturally
#   targets only the main app target.
#
# CURRENT_PROJECT_VERSION:
#   Updated for all targets (main app + helper share the same build number).

sed -i '' \
    -e "s/MARKETING_VERSION = [0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*;/MARKETING_VERSION = ${BASE};/g" \
    -e "s/CURRENT_PROJECT_VERSION = [0-9][0-9]*;/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g" \
    "$PBXPROJ"

# ── Verify the substitutions landed ───────────────────────────────────────────

FOUND_VER=$(grep -c "MARKETING_VERSION = ${BASE};" "$PBXPROJ" || true)
FOUND_BUILD=$(grep -c "CURRENT_PROJECT_VERSION = ${NEW_BUILD};" "$PBXPROJ" || true)

if [[ "$FOUND_VER" -lt 2 ]]; then
    echo "Warning: expected at least 2 MARKETING_VERSION replacements, found ${FOUND_VER}."
fi
if [[ "$FOUND_BUILD" -lt 4 ]]; then
    echo "Warning: expected at least 4 CURRENT_PROJECT_VERSION replacements, found ${FOUND_BUILD}."
fi

# ── Update CHANGELOG.md (releases only) ───────────────────────────────────────

if [[ "$SHORT" == "$BASE" ]]; then
    if ! python3 bin/changelog.py release "$BASE"; then
        git checkout -- "$PBXPROJ"
        exit 1
    fi
    git add CHANGELOG.md
fi

# ── Commit and tag ─────────────────────────────────────────────────────────────

git add "$PBXPROJ"
git commit -m "Version bump to ${VERSION} (build ${NEW_BUILD})"
# --no-sign: with tag.gpgsign set, a plain "git tag" asks for a message and fails.
git tag --no-sign "$VERSION"

echo ""
echo "Done:"
echo "  Version : ${VERSION}  (marketing: ${BASE})"
echo "  Build   : ${NEW_BUILD}"
echo ""
echo "Push when ready:"
echo "  git push origin main --tags"
