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

The Linux workflow checks out `dcajacob/orbiter-cross-platform` at the full commit in
`.github/native-linux/orbiter-revision`. It builds Orbiter, the OpenGL renderer,
Qt Launchpad, Earth and Moon modules and matching SDK together on Ubuntu 26.04.
Stage2010 and VesselBuilder1 are rebuilt from checksum-verified sources with the
Linux port changes in `.github/native-linux/ports`. The Stage2010 source archive
contains the unmodified `stage.cpp` and readme from BrianJ’s September 2010
[Orbiter Forum download](https://www.orbiter-forum.com/resources/stage-dll-for-orbiter-2010.1628/).
The original download has SHA-256
`e8398c557fb6e69032f6fff29c2066a99b50f45b6f5139542f5f6bf1e58ef920`.
Every test job verifies the
shared build and compiles the NASSP modules from its own checkout against that SDK.
The NASSP input archives supply the frozen scenarios, terrain, configuration and
replays. The workflow excludes the former executable, renderer and SDK.

The default check flies the frozen Apollo 11 lunar-orbit save with sound off,
saves it and reloads it in a second process. It checks graphics, simulation time
and the Columbia/Eagle docking links. Its receipt records both source revisions
and the hashes of the executable, SDK header and scenario. Request the complete
mission matrix with the `full` workflow input or the `full-native-linux` PR
label. The full checks retain the original replay table and expected outcomes.

The Qt Launchpad opens 53 frozen scenarios under Xvfb and Mesa software
OpenGL. For 26 scenarios the job also resizes the simulation window, resumes
with the keyboard, checks that simulation time advances in a quicksave, and
verifies the native XRSound PulseAudio backend.

The workflow builds from the same PR in parallel jobs and runs 71 fixed-step
flight replays from the pinned saves:

- Apollo 5 orbital insertion, the first descent-engine burn and cutoff,
  alternate descent and staging sequence, and final ascent-engine depletion.
- Apollo 7 crew ascent, SPS-3 at 62.5 ms and 31.25 ms with a linked post-burn
  reload and 30-minute P00 coast after each burn, SPS-4 through SPS-8, and Earth entry.
- Apollo 8 ullage at two step sizes and the first midcourse checkpoint.
- Apollo 9 launch, SPS burns, docked DPS and undocked LM burns, rendezvous,
  docking, retrofire and AGC-guided entry through splashdown.
- Apollo 10 MCC-2, Snoopy's lunar low pass and docking, and entry through
  splashdown at 0.25 s and 0.0625 s from the same pre-entry state.
- Apollo 11 TLI completion, Eagle's landing, ascent and docking, Columbia's
  P40 trans-Earth injection and midcourse correction with AGC readback,
  and AGC-guided entry, parachute deployment, splashdown and main chute release.
- Apollo 12 ascent and TLI, CSM separation, translunar corrections, LOI,
  Intrepid DOI, landing and ascent, rendezvous and docking, LM jettison and
  disposal impact, TEI, return corrections and AGC-guided entry and splashdown.
  The existing P27 uplink and guided landing reload checks also run.

The baseline job attaches `native-linux-opengl-results`. The other jobs
attach `native-linux-opengl-<suite>-results`. Each artifact includes the
build log, replay saves and telemetry, and a JSON result summary.

To reproduce locally on Ubuntu 26.04, install the development and virtual-desktop
packages listed in the workflow. Check out the pinned Orbiter commit and run
`bash .github/native-linux/build-orbiter.sh /path/to/orbiter /new/build-dir`.
In a fresh inputs directory, follow the workflow's checksum and extraction steps,
excluding `./runtime/engine` and `./sdk` from the old fixture. Extract the new
`orbiter-host.tar.zst` in that directory. Add the original locked terrain and
SPICE kernel as in the workflow, then build the NASSP modules and run the short check.

```sh
bash .github/native-linux/run.sh /path/to/inputs /path/to/results build
export ORBITER_REVISION=$(cat .github/native-linux/orbiter-revision)
export GITHUB_SHA=$(git rev-parse HEAD)
xvfb-run -a python3 -B .github/native-linux/lunar_smoke.py /path/to/inputs /path/to/results
```

For the additional missions, unpack `nassp-native-ci-apollo-replays-v2.tar.zst`
into the same inputs directory. Use a fresh results directory per suite.
After `build`, run the selected suite with the fourth argument to the replay
runner and the third argument to the verifier. Suite names are in
`.github/native-linux/replays.tsv`.

```sh
bash .github/native-linux/run.sh /path/to/inputs /path/to/results flight apollo10-entry
python3 .github/native-linux/verify.py /path/to/inputs/launcher-manifest.json /path/to/results apollo10-entry
```


The additional Apollo 7, 9 and 12 fixtures come from
`nassp-native-ci-apollo7912-v1.tar.zst`. Their expected vessel states,
telemetry events and final physical measurements are recorded in
`.github/native-linux/mission_expectations.json`. Each measurement specifies
absolute and relative tolerances. The job fails on missing events, invalid
vessel state, Lua errors, or measurements outside those tolerances.

Launcher and replay audio use a private PulseAudio virtual output set to 5%.

The shared Orbiter source includes the OpenGL tile texture fix. The historical
renderer supplement belongs to the older runtime.

Apollo 7 SPS-3 uses the crew procedure in
`Script/ProjectApollo/apollo7-countdown-sps3-scs-burn-rate-mode.lua`, installed
from the PR after the frozen replay assets. The old replay held DIRECT ULLAGE
for the full 15 seconds, bypassing pitch/yaw stabilization. Its weak,
step-dependent thrust had masked the resulting pointing error. With the
correct continuous direct thrust, that procedure missed the maneuver PAD orbit.
The corrected procedure uses the normal THC forward command for four-jet,
15-second ullage, with LOW rate and LIM CYCLE OFF as specified by the Apollo 7
SPS-3 checklist. DIRECT ULLAGE is used only briefly for the manual ignition
interlock. The full-thrust implementation remains in place.

Both SPS-3 step sizes must meet the original PAD orbit limits of 175.838 km
perigee and 309.339 km apogee, each within 15 km. The checks also require full
ullage impulse, less than two degrees of attitude loss, ignition at TIG, and
EMS cutoff with no continuing SPS fuel consumption. A correction-needed
result fails CI. The runner then reloads the newly flown save, changing only
its script, and verifies SPS shutdown, return to P00, AGC clock advancement
and orbital stability during a 30-minute coast. The subsequent SPS-4 through
SPS-8 and entry jobs remain checkpoint regressions from their pinned saves.

The older SPS-4 through SPS-7 procedures still record their historical and
current physical endpoints in the expectations. Passing those checkpoint
checks establishes repeatable current behavior for those inputs.

The replay table's optional seventh column selects an existing input fixture.
SPS-3 uses it to fly the identical pre-burn state at both step sizes.

### Linked Apollo 7 return

The `apollo7-linked-return` suite starts from the corrected SPS-3 62.5 ms
post-burn coast save at GET 76:42:46. Each subsequent coast, uplink, maneuver
and entry procedure loads the save written by its immediate predecessor.
The runner changes only the scenario's crew-script line between legs. The CMC
receives fresh targets from simulated Mission Control, and its P30 ignition
time and three velocity components are checked against each maneuver PAD.
The linked replay enables nonspherical Earth gravity and runs simulated Mission
Control calculations synchronously. The crew waits for the CMC navigation
cycle before loading the final state vectors for SPS-7 and SPS-8. It keeps the
calibrated retrofire platform through P61 and uses the CMC entry autopilot
from service-module separation through atmospheric entry.

With both additional mission replay archives installed as described above,
run the linked flight in a fresh results directory:

```sh
bash .github/native-linux/run.sh /path/to/inputs /path/to/results flight apollo7-linked-return
python3 .github/native-linux/verify.py /path/to/inputs/launcher-manifest.json /path/to/results apollo7-linked-return
```

GitHub Actions selects the linked flight for PRs that change the Apollo 7 crew
procedures or Mission C targeting. It can also be selected under **Run
workflow**. The artifact `native-linux-opengl-apollo7-linked-return-results`
contains each leg's input, crew script, telemetry, console log and output save.
Under `linked-return/`, `lineage.json` records the SHA-256 of every handoff.
The verifier writes `results.json` after it checks the complete sequence through
main parachute release and settled recovery. It compares the coordinates
loaded in the CMC with the live RTCC target after converting the CMC’s
geodetic latitude back to RTCC’s geocentric latitude, checks the IMU reference at five
checkpoints, and requires settled water contact within 10 nautical miles of
the target. The report gives the target, recovered position and great-circle
miss distance.
