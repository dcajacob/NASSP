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
asset directory. Install the generated panel and launch platform assets over
those resources:

```sh
for component in SaturnPanelAssets LunarPanelAssets Apollo11Assets; do
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
