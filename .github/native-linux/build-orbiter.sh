#!/usr/bin/env bash
# Build the external Orbiter host, SDK and the two auxiliary stock-mission vessels once per CI run.
set -euo pipefail
source_dir=$(realpath "$1")
work=$(realpath -m "$2")
ports=$(realpath "$(dirname "$0")/ports")
revision=$(git -C "$source_dir" rev-parse HEAD)
test "$revision" = "$(cat "$ports/../orbiter-revision")"
# Orbiter verifies the complete Dragonfly sources against their historical Git tree.
dragonfly=f725194209634f7fd5d1d44d426cfa9b5e303e37
if ! git -C "$source_dir" cat-file -e "$dragonfly^{commit}" 2>/dev/null; then
    git -C "$source_dir" fetch --no-tags --depth=1 origin "$dragonfly"
fi
mkdir "$work"
cd "$work"
export CMAKE_BUILD_PARALLEL_LEVEL=${CMAKE_BUILD_PARALLEL_LEVEL:-4}
engine="$work/build-engine"
base=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON
      '-DCMAKE_INSTALL_RPATH=$ORIGIN;$ORIGIN/..;$ORIGIN/../..;$ORIGIN/../../..;$ORIGIN/native-lua')
python3 -B "$source_dir/Tests/Production/NativeScene/dependencies.py" --cache "$work/deps"
cmake -S "$source_dir/Src/Orbiter/Production" -B "$engine" "${base[@]}" \
    -DORBITER_MATH_FORCE_SSE2=ON -DORBITER_BUILD_NATIVE_VESSELS=ON -DORBITER_BUILD_NATIVE_COCKPIT=ON \
    -DORBITER_BUILD_NATIVE_CELESTIAL_MODULES=ON -DBUILD_TESTING=OFF -DORBITER_NATIVE_UI_ARCHIVE="$work/deps/imgui.zip"
cmake --build "$engine" --target orbiter-production native_xrsound native_deltaglider native_shuttle_a \
    native_shuttle_a_payload native_atlantis native_atlantis_tank native_atlantis_srb native_hst \
    native_solar_sail native_quadcopter native_dragonfly native_lua_inline native_lua_mfd \
    orbiter_native_spice orbiter_native_EarthAtmJ71G orbiter_native_EarthAtm2006 orbiter_native_MarsAtm2006
cmake -S "$source_dir/OVP/OGLClient/Native" -B renderer "${base[@]}" \
    -DORBITER_ENGINE_BUILD="$engine" -DORBITER_RENDERER_DEPENDENCIES="$work/deps"
cmake --build renderer --target orbiter_ogl_native
cmake -S "$source_dir/Src/Celbody/NativeEphemeris" -B ephemeris "${base[@]}" -DORBITER_ENGINE_BUILD="$engine"
cmake --build ephemeris
cmake -S "$source_dir/Utils/Launchpad" -B launchpad "${base[@]}" -DORBITER_GLFW_ARCHIVE="$work/deps/glfw.tar.gz"
cmake --build launchpad --target orbiter-launchpad

# The frozen scenarios also fly these third-party vessels. Rebuild their Linux ports for this SDK.
curl -fLsS --retry 3 https://www.orbiter-forum.com/resources/stage-dll-for-orbiter-2010.1628/download -o stage.zip
curl -fLsS --retry 3 https://codeload.github.com/fredenigma/VesselBuilder1/tar.gz/4f332ec4e6fa80e1a63d8d920bb50e033c5b67f6 -o vesselbuilder.tar.gz
sha256sum --check <<'SHA'
e8398c557fb6e69032f6fff29c2066a99b50f45b6f5139542f5f6bf1e58ef920  stage.zip
8440295a404b00cf681a9555e44a88d2f2208f60170255a83b3766e565c4f105  vesselbuilder.tar.gz
SHA
mkdir Stage2010 VesselBuilder1
unzip -p stage.zip Orbitersdk/Samples/Stage_dll_2010/stage.cpp | tr -d '\r' > Stage2010/stage.cpp
tar -xzf vesselbuilder.tar.gz --strip-components=1 -C VesselBuilder1
cp "$ports/VesselBuilder1/"*.h VesselBuilder1/
for vessel in Stage2010 VesselBuilder1; do
    patch --batch --fuzz=0 -d "$vessel" -p1 < "$ports/$vessel/linux.patch"
    cp "$ports/$vessel/CMakeLists.txt" "$vessel/"
    cmake -S "$vessel" -B "build-$vessel" "${base[@]}" \
        -DORBITER_NATIVE_BUILD_DIR="$engine" -DORBITER_NATIVE_SOURCE_DIR="$source_dir"
    cmake --build "build-$vessel"
done

pack="$work/package"
bin="$pack/runtime/engine"
mkdir -p "$pack/sdk" "$bin/native-lua"
git -C "$source_dir" archive "$revision" Orbitersdk/include Src/Orbiter Sound/XRSound/src LICENSE | tar -xf - -C "$pack/sdk"
cp -a "$engine/NativeModules" "$engine/native-sdk" "$bin/"
cp "$engine/"{orbiter-production,liborbiter*.so} launchpad/orbiter-launchpad "$bin/"
cp -a "$engine/native-lua/"{sdk,liblua.so} "$bin/native-lua/"
cp build-Stage2010/stage.so build-VesselBuilder1/VesselBuilder1.so "$bin/NativeModules/Vessel/"
cp VesselBuilder1/LICENSE "$bin/NativeModules/Licenses/VesselBuilder1-LICENSE.txt"
unzip -p stage.zip 'Doc/STAGE DLL 2010/stage_dll_2010_README.txt' > "$bin/NativeModules/Licenses/Stage2010-README.txt"
install -m755 "$ports/../run-orbiter" "$bin/run-orbiter"
(cd "$pack" && printf '%s\n' "$revision" > orbiter-source.txt &&
    find runtime sdk -type f -print0 | sort -z | xargs -0 sha256sum > orbiter-files.sha256)
tar -C "$pack" --zstd -cf orbiter-host.tar.zst .
