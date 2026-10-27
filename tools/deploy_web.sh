#!/usr/bin/env bash
# Export the Web build and force-push it to the gh-pages branch (GitHub Pages).
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-C:/Users/alex/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe}"
rm -rf build/web && mkdir -p build/web
"$GODOT" --headless --path . --export-release "Web" build/web/index.html > /dev/null
touch build/web/.nojekyll
cd build/web
git init -q -b gh-pages
git add -A
git -c user.name="deploy" -c user.email="deploy@localhost" commit -q -m "web build $(date -u +%Y-%m-%dT%H:%MZ)"
git push -q -f https://github.com/thealextd1337-spec/Doorgunner.git gh-pages:gh-pages
echo "deployed: https://thealextd1337-spec.github.io/Doorgunner/"
