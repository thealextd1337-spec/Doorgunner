#!/usr/bin/env bash
# Export the Web build and force-push it to the gh-pages branch (GitHub Pages).
# Stamps the build with config/version + commit + date (scripts/build_info.gd, removed again after the export)
# and tags the deployed commit v<version> unless that tag exists already or the tree has uncommitted changes.
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
GODOT="${GODOT:-C:/Users/alex/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe}"
VERSION="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)"
HASH="$(git rev-parse --short HEAD)"
DIRTY=""
git diff --quiet HEAD || DIRTY="-dirty"
echo "const BUILD := \"$HASH$DIRTY $(date -u +%Y-%m-%d)\"" > scripts/build_info.gd
trap 'rm -f "$ROOT/scripts/build_info.gd" "$ROOT/scripts/build_info.gd.uid"' EXIT
rm -rf build/web && mkdir -p build/web
"$GODOT" --headless --path . --export-release "Web" build/web/index.html > /dev/null
touch build/web/.nojekyll
cd build/web
git init -q -b gh-pages
git add -A
git -c user.name="deploy" -c user.email="deploy@localhost" commit -q -m "web build v$VERSION ($HASH$DIRTY) $(date -u +%Y-%m-%dT%H:%MZ)"
git push -q -f https://github.com/thealextd1337-spec/Doorgunner.git gh-pages:gh-pages
cd "$ROOT"
TAG="v$VERSION"
if [ -n "$DIRTY" ]; then
	echo "not tagged: uncommitted changes are in this build"
elif ! git rev-parse -q --verify "refs/tags/$TAG" > /dev/null; then
	git tag -a "$TAG" -m "Doorgunner $TAG"
	git push -q origin "$TAG"
	echo "tagged $TAG"
elif [ "$(git rev-list -n 1 "$TAG")" != "$(git rev-parse HEAD)" ]; then
	echo "note: $TAG already tags an older commit; bump config/version in project.godot for a new release"
fi
echo "deployed v$VERSION ($HASH$DIRTY): https://thealextd1337-spec.github.io/Doorgunner/"
