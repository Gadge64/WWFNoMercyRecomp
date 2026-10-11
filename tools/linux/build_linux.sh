#!/usr/bin/env bash
# WWF No Mercy: Recompiled -- Linux build + package (2026-09-26).
#
# Run from the Linux side of a dual-boot PC, pointing at this repo on the Windows drive:
#   bash /path/to/WWFNoMercyRecomp/tools/linux/build_linux.sh
#
# What it does:
#   1. installs build dependencies (apt / dnf / pacman / zypper; asks for sudo)
#   2. copies the source to ~/nomercy-linux/src (NTFS mounts are often read-only or lose the
#      execute bit that the vendored shader compiler needs; git history and build dirs are skipped)
#   3. configures + builds with clang/Ninja in ~/nomercy-linux/build
#   4. packages a self-contained folder + tarball in ~/nomercy-linux/dist (bundles libSDL2 so the
#      same folder can be copied to a Steam Deck)
#
# Options (environment): SKIP_DEPS=1  KEEP_GOING=1 (report all compile errors)  JOBS=<n>  WORK=<dir, default ~/nomercy-linux>
#                         INCLUDE_ROM=1 (personal use only: copy ./nomercy.z64 into the package; never share such a package)
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="${WORK:-$HOME/nomercy-linux}"
JOBS="${JOBS:-$(nproc)}"
say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[ -f "$SRC/CMakeLists.txt" ] && [ -d "$SRC/RecompiledFuncs" ] || die "run this from inside the WWFNoMercyRecomp repo (couldn't find CMakeLists.txt + RecompiledFuncs under $SRC)"

# ---------------------------------------------------------------- 1. dependencies
if [ "${SKIP_DEPS:-0}" != "1" ]; then
    say "Installing build dependencies"
    if command -v apt-get >/dev/null; then
        sudo apt-get update
        sudo apt-get install -y clang lld cmake ninja-build pkg-config make \
            libsdl2-dev libgtk-3-dev libx11-dev libxrandr-dev libfreetype-dev libvulkan-dev patchelf
    elif command -v dnf >/dev/null; then
        sudo dnf install -y clang lld cmake ninja-build pkgconf-pkg-config make \
            SDL2-devel gtk3-devel libX11-devel libXrandr-devel freetype-devel vulkan-loader-devel patchelf
    elif command -v pacman >/dev/null; then
        sudo pacman -S --needed --noconfirm clang lld cmake ninja pkgconf make \
            sdl2 gtk3 libx11 libxrandr freetype2 vulkan-icd-loader vulkan-headers patchelf
    elif command -v zypper >/dev/null; then
        sudo zypper install -y clang lld cmake ninja pkg-config make \
            SDL2-devel gtk3-devel libX11-devel libXrandr-devel freetype2-devel vulkan-devel patchelf
    else
        die "unknown package manager -- install clang, cmake, ninja, SDL2/GTK3/X11/Xrandr/freetype/vulkan dev packages, then rerun with SKIP_DEPS=1"
    fi
fi

# ---------------------------------------------------------------- 2. copy source
say "Copying source to $WORK/src"
mkdir -p "$WORK/src"
tar -C "$SRC" \
    --exclude='./.git' --exclude='*/.git' --exclude='./build-*' --exclude='./state_snapshots' \
    --exclude='./disasm' --exclude='*.exe' --exclude='*.pdb' \
    -cf - . | tar -C "$WORK/src" -xf -
chmod +x "$WORK/src/lib/rt64/src/contrib/dxc/bin/"*/dxc-linux 2>/dev/null || true

# ---------------------------------------------------------------- 3. build
say "Configuring (clang, Release)"
cmake -S "$WORK/src" -B "$WORK/build" -G Ninja \
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld"

say "Building NoMercyRecompiled with $JOBS jobs (the recompiled game is ~38 MB of C -- this takes a while)"
cmake --build "$WORK/build" --target NoMercyRecompiled -j "$JOBS" ${KEEP_GOING:+-- -k 0}

# ---------------------------------------------------------------- 4. package
DIST="$WORK/dist/NoMercyRecompiled-linux"
say "Packaging into $DIST"
rm -rf "$DIST"; mkdir -p "$DIST/lib/sdl2-fallback"
cp "$WORK/build/NoMercyRecompiled" "$DIST/"
cp -r "$WORK/build/assets" "$DIST/"
cp "$WORK/src/recompcontrollerdb.txt" "$DIST/"
# The ROM is never packaged unless asked for (INCLUDE_ROM=1, personal use only).
if [ "${INCLUDE_ROM:-0}" = "1" ] && [ -f "$SRC/nomercy.z64" ]; then cp "$SRC/nomercy.z64" "$DIST/"; fi
# Bundle SDL2 as a FALLBACK only: this Debian build hard-links libsamplerate/libdecor/libXss etc., which
# a Deck may lack, so the WWFNoMercy launcher uses the system SDL2 (SteamOS/Bazzite ship one) whenever it exists.
sdl="$(ldd "$DIST/NoMercyRecompiled" | awk '/libSDL2-2\.0\.so/{print $3}')"
[ -n "$sdl" ] && cp -L "$sdl" "$DIST/lib/sdl2-fallback/"

# Portable mode, as in the Windows zip: the game folder is the app folder, so modpacks/, saves and
# config live next to the launcher instead of ~/.config (where nobody would find modpacks/).
touch "$DIST/portable.txt"
mkdir -p "$DIST/modpacks"
cat > "$DIST/modpacks/HOW-TO-ADD-MODS.txt" <<'EOF'
WWF No Mercy: Recompiled 0.2.1 - mods and texture packs
=======================================================

Each mod is a folder in here. Its name is the name shown in the launcher.

  modpacks/
      <Mod Name>/
          textures/   PNG texture replacements (subfolders are fine)
          save/       optional starting save: a Project64 .fla, or a .bin
                      from this game

On the launcher, click "Mod: Base Game" to step through your mods, then
Start Game. The choice is remembered.

Adding textures (no tools or code needed)
-----------------------------------------
1. Dump the texture you want to replace with Project64 (GLideN64 or Rice
   Video texture dumping). The dump's file name identifies the texture, e.g.
     WWF No Mercy#2220AF21#2#0#14BCB5C9_ciByRGBA.png
2. Edit or redraw it at any size (hi-res is fine). Keep the file name.
3. Put it in modpacks/<Mod Name>/textures/ and restart the game.

Only the part of the name between the first "#" and the last "_" matters.
Jabo Direct3D8 packs (32-character hash names) work too. If the same name
is in two places, the one whose path sorts last alphabetically wins.
Linux file names are case-sensitive: keep the dump's exact name.

Saves - read this
-----------------
Each mod has its own save in saves/<Mod Name>/. It is created from the
mod's save/ folder the FIRST time you start that mod.

If you start a mod before its save is in save/, a blank save is created
and kept, so the mod's custom wrestlers (and their textures) won't show.
To fix it: close the game, delete saves/<Mod Name>/, start the mod again.

The Base Game save is never changed by mods.

Textures for created or edited wrestlers only show when those wrestlers
are in the roster, which comes from the mod's save.
EOF

cat > "$DIST/WWFNoMercy" <<'EOF'
#!/usr/bin/env bash
# WWF No Mercy: Recompiled launcher. Put your ROM next to this file as nomercy.z64
# to skip the ROM picker, or choose it in the launcher.
cd "$(dirname "$0")"
# System SDL2 if present, else the bundled copy.
/sbin/ldconfig -p 2>/dev/null | grep -q "libSDL2-2.0.so.0 " || export LD_LIBRARY_PATH="$PWD/lib/sdl2-fallback${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
[ -f nomercy.z64 ] && export WCW_AUTOBOOT="$PWD/nomercy.z64"
exec ./NoMercyRecompiled "$@"
EOF
chmod +x "$DIST/WWFNoMercy" "$DIST/NoMercyRecompiled"
cat > "$DIST/README_STEAM_DECK.txt" <<'EOF'
WWF No Mercy: Recompiled 0.2.1 -- Steam Deck / Linux

You need your own WWF No Mercy (USA) ROM. It is not included.

SETUP (in Desktop Mode)
1. Extract this zip somewhere permanent, e.g. ~/Games/NoMercyRecompiled-linux
2. Copy your ROM into that folder, next to WWFNoMercy, and rename it to: nomercy.z64
   (the game then boots straight in; no ROM picker needed)
3. Open Steam -> Games -> "Add a Non-Steam Game to My Library..." -> Browse.
   Set the file type filter to "All Files", select WWFNoMercy and click "Add Selected Programs".
4. Do NOT start the game from Desktop Mode. In Desktop Mode, Steam turns the Deck's
   controls into a keyboard and mouse, and the game will clash with that.

PLAY (in Gaming Mode)
5. Switch to Gaming Mode (desktop shortcut "Return to Gaming Mode").
6. Find WWFNoMercy in your Library (under Non-Steam) and launch it.
   You can give it artwork in its Steam properties.
7. If the buttons don't respond correctly: Steam button -> Controller Settings ->
   choose the "Gamepad" layout template.

CONTROLS (Xbox-style layout)
A = A, X = B, B = C-Down, Y = C-Up, L1/R1 = C-Left/C-Right, L2/R2 = L/R, L3 (left stick click) = Z,
Menu = Start, D-pad or left stick = move, right stick = N64 analog stick, View = settings menu.
Tip: in Controller Settings, bind a back grip to "Left Stick Click" for an easier Z.

MODS AND TEXTURE PACKS
Put each mod in its own folder inside modpacks/ (see modpacks/HOW-TO-ADD-MODS.txt), then pick it
on the launcher with "Mod: Base Game". Saves and settings are kept in this folder too (saves/),
so back it up before deleting it. Coming from an older Deck build? Its save is in
~/.config/NoMercyRecompiled/ -- copy that folder's contents into this one to keep it.

If the game won't start, run ./WWFNoMercy from Konsole in Desktop Mode and note the last lines
it prints.
EOF

commit="$(cat "$SRC/.git/HEAD" 2>/dev/null || true)"
{
    echo "WWF No Mercy: Recompiled -- Linux build"
    echo "Built $(date -u +%Y-%m-%dT%H:%MZ) on $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}")"
    echo "glibc: $(ldd --version | head -1)"
    echo
    echo "Libraries the binary needs (a Steam Deck needs these present; SDL2 comes from the system, with lib/sdl2-fallback used only if it has none):"
    ldd "$DIST/NoMercyRecompiled" | awk '{print "  " $1}'
} > "$DIST/BUILD_INFO.txt"

tar -C "$WORK/dist" -czf "$WORK/dist/NoMercyRecompiled-linux.tar.gz" NoMercyRecompiled-linux
# Zip for easy transfer to a Deck (Info-ZIP keeps the execute bits).
if command -v zip >/dev/null; then
    rm -f "$WORK/dist/NoMercyRecompiled-SteamDeck.zip"
    (cd "$WORK/dist" && zip -q -r -9 NoMercyRecompiled-SteamDeck.zip NoMercyRecompiled-linux)
fi
say "Done."
echo "  Run here:        $DIST/WWFNoMercy"
echo "  Steam Deck:      copy $WORK/dist/NoMercyRecompiled-SteamDeck.zip across, extract, see README_STEAM_DECK.txt"
echo "                   (add WWFNoMercy to Steam as a non-Steam game and ALWAYS launch it from Steam)"
echo "  Build details:   $DIST/BUILD_INFO.txt"
