#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
inputs=$(realpath "$1")
mkdir -p "$2"
output=$(realpath "$2")
runtime="$inputs/runtime"

if [[ "${3:-}" == launcher || "${3:-}" == flight ]]; then
    # Keep the audio server private and use the same backend as a Linux desktop.
    pulse_dir=$(mktemp -d)
    # The GitHub job container's mounted home is inaccessible to PulseAudio.
    export HOME="$pulse_dir"
    export PULSE_RUNTIME_PATH="$pulse_dir"
    export PULSE_SERVER="unix:$pulse_dir/pulse.sock"
    export PULSE_SINK=nassp_ci
    export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=2 QT_QPA_PLATFORM=xcb
    env DBUS_SESSION_BUS_ADDRESS="unix:path=$pulse_dir/no-session-bus" pulseaudio -n --daemonize=no --exit-idle-time=-1 --log-target=stderr \
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
    pactl set-sink-volume "$PULSE_SINK" 5%
fi

case "${3:-}" in
    build)
        cmake -S "$source_dir/Orbitersdk/samples/ProjectApollo" -B "$output/build" -G Ninja \
            -DCMAKE_BUILD_TYPE=Release -DNASSP_BUILD_NATIVE_LINUX=ON \
            -DORBITER_NATIVE_SOURCE_DIR="$inputs/sdk" -DORBITER_NATIVE_BUILD_DIR="$runtime/engine"
        cmake --build "$output/build" --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-2}"
        rsync -a "$output/build/NativeModules/" "$runtime/engine/NativeModules/"
        for component in SaturnPanelAssets LunarPanelAssets Apollo11Assets ChecklistAssets ApolloReplayAssets; do
            cmake --install "$output/build" --prefix "$runtime/resources" --component "$component"
        done
        ;;
    launcher)
        xvfb-run -a -s '-screen 0 1600x1000x24 +extension GLX' python3 \
            "$source_dir/.github/native-linux/launchpad.py" "$runtime" \
            "$output/launcher" "$inputs/launcher-manifest.json"
        ;;
    flight)
        run_flight() (
            local case_name=$1 ticks=$2 step=$3 render_every=$4 keymap_profile=$5
            local keymap=()
            # Some original scripts send native numeric-keypad RCS controls.
            if [[ "$keymap_profile" == package ]]; then
                keymap=(--keymap "$runtime/Keymap.cfg")
            fi
            mkdir -p "$output/flight/$case_name"
            cd "$output/flight/$case_name"
            cp "$inputs/flight/$case_name/"* .
            printf 'Replaying %s at %s seconds per step\n' "$case_name" "$step"
            env -u WAYLAND_DISPLAY -u LD_LIBRARY_PATH LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=2 \
                xvfb-run -a -s '-screen 0 1600x1000x24 +extension GLX' stdbuf -oL -eL "$runtime/engine/run-orbiter" \
                --assets "$runtime/resources" --data "$runtime/celestial-data" \
                --modules "$runtime/engine/NativeModules" --planets "$runtime/planet-archives" \
                --config "$runtime/Orbiter.cfg" "${keymap[@]}" \
                --xrsound-assets "$runtime/resources" --scenario input.scn --save saved.scn \
                --replay replay.csv --ticks "$ticks" --fixed-step "$step" \
                --render-every "$render_every" --run < /dev/null > console.log 2>&1
        )
        suite="${4:-baseline}"
        matched=false
        while read -r group name ticks step render_every keymap_profile; do
            if [[ "$group" == "$suite" ]]; then
                matched=true
                run_flight "$name" "$ticks" "$step" "$render_every" "$keymap_profile"
            fi
        done < "$source_dir/.github/native-linux/replays.tsv"
        if ! "$matched"; then
            echo "Unknown replay suite: $suite" >&2
            exit 2
        fi
        ;;
    *)
        echo "Usage: $0 INPUTS OUTPUT {build|launcher|flight} [suite]" >&2
        exit 2
        ;;
esac
