# NASSP on native Linux

This port targets the native production cockpit and OpenGL build of
Orbiter Cross Platform. Use the SDK headers and runtime libraries from the
same Orbiter build. The runtime must support the native Project Apollo vessel
modules, the Virtual AGC Earth and Moon ephemerides, and Apollo RTCC MFD.

Configure and build the modules from this checkout:

```sh
cmake -S Orbitersdk/samples/ProjectApollo -B build-linux -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DNASSP_BUILD_NATIVE_LINUX=ON \
  -DORBITER_NATIVE_SOURCE_DIR=/path/to/orbiter-cross-platform \
  -DORBITER_NATIVE_BUILD_DIR=/path/to/configured/orbiter-engine
cmake --build build-linux --parallel
```

The build writes the Apollo shared objects to
`build-linux/NativeModules/Vessel/ProjectApollo` and
`build-linux/NativeModules/Plugin`. Merge these directories into the matching
Orbiter runtime's `NativeModules` tree. Include the NASSP configuration,
meshes, textures, missions, sound, and scenarios in the launcher profile's
asset directory. Install the generated panel and launch platform assets along with the checklist workbooks:

```sh
for component in SaturnPanelAssets LunarPanelAssets Apollo11Assets ChecklistAssets; do
  cmake --install build-linux --prefix /path/to/profile/resources --component "$component"
done
```

In the Orbiter Launchpad, open the matching native simulator profile from the
Setup menu. Select an Apollo scenario from the scenario tree and start the
flight. To enable the RTCC MFD, put `ApolloRTCCMFD` in the profile's
`ACTIVE_MODULES` configuration block.

The Apollo 11 verification includes Saturn V and Lunar Module operation,
RTCC uplinks, a P40 transearth injection and correction, and CMC-guided
entry through automatic parachute deployment and splashdown. This is a
mission-specific port and qualification.

## Native Linux pull request checks

GitHub Actions runs **Native Linux OpenGL** on pull requests targeting
`codex/native-linux-apollo11-baseline`, the native Linux integration branch.
It builds the NASSP modules from the PR checkout against the pinned Orbiter
runtime and SDK in the fork's `native-linux-ci-inputs-v1` release. The job
verifies the input archives and Orbiter SPICE kernel checksums before use.

The Qt Launchpad opens 53 frozen scenarios under Xvfb and Mesa software
OpenGL. For 26 scenarios the job also resizes the simulation window, resumes
with the keyboard, checks that simulation time advances in a quicksave, and
verifies the native XRSound PulseAudio backend. Five fixed-step flight
replays cover Apollo 8 ullage at two step sizes and the first midcourse
checkpoint, plus Apollo 12 P27 uplink and the Intrepid approach, touchdown,
and shutdown. The run attaches launcher logs, replay saves and telemetry,
and a JSON result summary as `native-linux-opengl-results`.

To run the same checks on Ubuntu 26.04, extract the CI input archive into a scratch
directory, unpack the terrain archive under `runtime/planet-archives`, and add `Kernels/orbiter.bsp` from the workflow's stock
data archive under `runtime/celestial-data`. Install the workflow dependencies
and run the commands below. The build installs modules and generated assets
into that scratch runtime.

```sh
for phase in build launcher flight; do
  bash .github/native-linux/run.sh /path/to/inputs /path/to/results "$phase" || exit
done
python3 .github/native-linux/verify.py /path/to/inputs/launcher-manifest.json /path/to/results
```
