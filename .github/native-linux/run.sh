#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
inputs=$(realpath "$1")
mkdir -p "$2"
output=$(realpath "$2")
runtime="$inputs/runtime"

case "${3:-}" in
    build)
        cmake -S "$source_dir/Orbitersdk/samples/ProjectApollo" -B "$output/build" -G Ninja \
            -DCMAKE_BUILD_TYPE=Release -DNASSP_BUILD_NATIVE_LINUX=ON \
            -DORBITER_NATIVE_SOURCE_DIR="$inputs/sdk" -DORBITER_NATIVE_BUILD_DIR="$runtime/engine"
        cmake --build "$output/build" --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-2}"
        rsync -a "$output/build/NativeModules/" "$runtime/engine/NativeModules/"
        for component in SaturnPanelAssets LunarPanelAssets Apollo11Assets ChecklistAssets; do
            cmake --install "$output/build" --prefix "$runtime/resources" --component "$component"
        done
        ;;
    launcher)
        # Keep the audio server private and use the same backend as a Linux desktop.
        pulse_dir=$(mktemp -d)
        export PULSE_RUNTIME_PATH="$pulse_dir"
        export PULSE_SERVER="unix:$pulse_dir/pulse.sock"
        export PULSE_SINK=nassp_ci
        export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=2 QT_QPA_PLATFORM=xcb
        pulseaudio -n --daemonize=no --exit-idle-time=-1 --log-target=stderr \
            -L "module-native-protocol-unix socket=$pulse_dir/pulse.sock" \
            -L "module-null-sink sink_name=$PULSE_SINK" > "$output/pulseaudio.log" 2>&1 &
        pulse_pid=$!
        cleanup_audio() {
            kill "$pulse_pid" 2>/dev/null || true
            wait "$pulse_pid" 2>/dev/null || true
            rm -rf "$pulse_dir"
        }
        trap cleanup_audio EXIT
        for attempt in {1..50}; do
            if pactl info >/dev/null 2>&1; then
                break
            fi
            if ! kill -0 "$pulse_pid" 2>/dev/null; then
                break
            fi
            sleep .2
        done
        pactl info || { cat "$output/pulseaudio.log"; exit 1; }
        xvfb-run -a -s '-screen 0 1600x1000x24 +extension GLX' python3 \
            "$source_dir/.github/native-linux/launchpad.py" "$runtime" \
            "$output/launcher" "$inputs/launcher-manifest.json"
        ;;
    flight)
        run_flight() (
            local case_name=$1 ticks=$2 step=$3
            mkdir -p "$output/flight/$case_name"
            cd "$output/flight/$case_name"
            cp "$inputs/flight/$case_name/"{input.scn,replay.csv} .
            printf 'Replaying %s at %s seconds per step\n' "$case_name" "$step"
            env -u WAYLAND_DISPLAY -u LD_LIBRARY_PATH LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=2 \
                xvfb-run -a -s '-screen 0 1600x1000x24 +extension GLX' stdbuf -oL -eL "$runtime/engine/run-orbiter" \
                --assets "$runtime/resources" --data "$runtime/celestial-data" \
                --modules "$runtime/engine/NativeModules" --planets "$runtime/planet-archives" \
                --config "$runtime/Orbiter.cfg" --keymap "$runtime/Keymap.cfg" \
                --xrsound-assets "$runtime/resources" --scenario input.scn --save saved.scn \
                --replay replay.csv --ticks "$ticks" --fixed-step "$step" \
                --render-every "$ticks" --run > console.log 2>&1
        )
        run_flight a12-intrepid-imu-preserved-capcom-load 7800 0.03125
        run_flight apollo8-ullage-fixed-125ms-axial 40 0.125
        run_flight apollo8-ullage-fixed-60hz-axial 300 0.0166666666666667
        run_flight apollo8-flown-first-midcourse-fixed 17200 1
        run_flight apollo12-intrepid-guided-approach-reload-shutdown 3840 0.03125
        ;;
    *)
        echo "Usage: $0 INPUTS OUTPUT {build|launcher|flight}" >&2
        exit 2
        ;;
esac
