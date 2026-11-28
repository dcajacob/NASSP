# Apollo 7 post-SPS-3 preview for native Linux OpenGL

Download `install-apollo7`, `SHA256SUMS` and every `apollo7.tar.zst.partNN` asset into the same folder. Use Ubuntu 26.04 x86-64 with hardware OpenGL and a writable destination. Allow 9 GB free at the destination for installation. The application uses the system Qt 6.10 Widgets, OpenGL, GLU and PulseAudio libraries. PipeWire with its PulseAudio service works as the desktop sound backend.

```sh
sudo apt install python3 tar zstd libqt6widgets6 qt6-qpa-plugins libxcb-cursor0 libgl1 libglu1-mesa libpulse0
python3 install-apollo7 "$HOME"
"$HOME/NASSP-9-Apollo-7-OpenGL-preview1/launch-orbiter"
```

The installer checks the split downloads, fetches the preserved Orbiter 2016 terrain ZIP and verifies its original SHA-256. Only the required scenery and publisher notices are extracted. If you already have the original ZIP, the following installation works offline.

```sh
python3 install-apollo7 "$HOME" --terrain-zip /path/to/Orbiter2016.zip
```

Open **Apollo 7 - Precision Recovery** in the Orbiter launcher. Select **00 - SPS-3 - Postburn coast** for the start at mission elapsed time 76:42:46, **29 - SPS-8 - Ready for P40 slew** for retrofire preparation, or **33 - P63 entry guidance** for entry. Click **Launch**. Space resumes a paused flight and Ctrl+S writes a quicksave. The 36 checkpoints give you crew control. XRSound starts at 5%.

The release covers the corrected post-SPS-3 save through SPS-4 to SPS-8, reentry and recovery. The original Apollo 7 scenarios and earlier saves are also available in the launcher. The installed `qualification/` directory contains the reference flight and launcher records. See the release attachment for the checks on this build.
