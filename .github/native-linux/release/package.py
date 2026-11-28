"""Build split Linux media from a qualified Apollo 7 installation and fresh NASSP modules."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
ARCHITEXT = "a6b8e33ce190ee9c871590b982cff37e137b303bb73dcab55ef3ff7154ba143a"


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main(args):
    stage = args.work / "stage"
    media = args.work / "media"
    if stage.exists() or media.exists():
        raise ValueError("Choose an empty staging and media directory")
    skip = {"user", "cockpit-test-font.json", "resources.json", "remaining-vessels-resources.json",
            "architext.regular.ttf", "OGLClient-original-staged", "Solar Serenity.ogg", "stage.so"}
    shutil.copytree(args.qualified, stage, ignore=lambda directory, names: skip.intersection(names))
    media.mkdir()
    proof = stage / "qualification"
    (proof / "files.sha256").unlink()
    cfg = stage / "Orbiter.cfg"
    cfg.write_text("ImGui_ManuscriptFontFile = Fonts/Cousine-Regular.ttf\n" + cfg.read_text())
    sound = stage / "resources/XRSound/XRSound.cfg"
    data = sound.read_bytes()
    if b'MasterVolume = 0.05' not in data:
        raise ValueError("Expected the quiet XRSound configuration")
    sound.write_bytes(data.replace(b'MusicFolder = XRSound\\Default\\Music', b'MusicFolder = none'))
    engine = stage / "engine"
    plugins = engine / "NativeModules"
    built = {file.relative_to(args.modules) for file in args.modules.rglob("*.so")}
    required = {file.relative_to(plugins) for file in (plugins / "Vessel/ProjectApollo").glob("*.so")}
    required.update(Path("Plugin") / name for name in ("ApolloRTCCMFD.so", "ProjectApolloMFD.so"))
    if built != required:
        raise ValueError(f"Module set changed: {built.symmetric_difference(required)}")
    for path in built:
        shutil.copy2(args.modules / path, plugins / path)
    for path in engine.rglob("*"):
        if not path.is_file():
            continue
        with path.open("rb") as stream:
            if stream.read(4) != b"\x7fELF":
                continue
        dynamic = subprocess.check_output(["readelf", "-d", path], text=True)
        for line in dynamic.splitlines():
            if "(RUNPATH)" in line or "(RPATH)" in line:
                entries = line.split("[", 1)[1].split("]", 1)[0].split(":")
                if any(e != "$ORIGIN" and not e.startswith("$ORIGIN/") for e in entries):
                    raise ValueError(f"Non-relocatable library search path in {path}: {entries}")

    licenses = stage / "licenses"
    for name in ("Cousine-LICENSE.txt", "Roboto-LICENSE.txt", "lua-lua.h", "NRLMSISE-NOTICE.txt", "tracy-LICENSE"):
        shutil.copy2(args.orbiter / "Tests/Production/Licenses" / name, licenses / name)
    for name in ("Lekton - SIL License.txt", "License-FA.txt"):
        shutil.copy2(args.orbiter / "Extern/imgui" / name, licenses / name)
    for name in ("Project Apollo License.txt", "CDK Copyright.txt"):
        shutil.copy2(REPO / "Orbitersdk/samples/ProjectApollo/Doc" / name, licenses / name)
    shutil.copy2(HERE / "SOURCES.md", licenses)
    with zipfile.ZipFile(args.terrain) as original:
        for member, name in [("Doc/Orbiter.pdf", "Orbiter2016.pdf"), ("readme.txt", "Orbiter2016-readme.txt")]:
            with original.open(member) as src, (licenses / name).open("wb") as dst:
                shutil.copyfileobj(src, dst)
    terrain = stage / "planet-archives"
    (proof / "terrain-files.txt").write_text("".join(str(p.relative_to(terrain)) + "\n" for p in sorted(terrain.rglob("*.tree"))))
    build = json.loads((proof / "build.json").read_text())
    build["module_sha256"] = {str(p.relative_to(stage)): sha(p) for p in sorted(plugins.rglob("*.so"))}
    build["release_tag"] = "apollo7-post-sps3-linux-opengl-preview1"
    build["release_source_commit"] = subprocess.check_output(["git", "-C", REPO, "rev-parse", "HEAD"], text=True).strip()
    (proof / "build.json").write_text(json.dumps(build, indent=2) + "\n")
    with (stage / "README.md").open("a") as guide:
        guide.write("\nThis preview targets Ubuntu 26.04 x86-64, Qt 6.10 and hardware OpenGL. "
                    "The manuscript font uses Cousine. See licenses/SOURCES.md for credits and source.\n")
    files = sorted(path for path in stage.rglob("*") if path.is_file())
    with (proof / "files.sha256").open("w") as sums:
        for path in files:
            digest = sha(path)
            if digest == ARCHITEXT:
                raise ValueError(f"Restricted font in {path}")
            sums.write(f"{digest}  {path.relative_to(stage)}\n")
    # The installer imports the eight original terrain members and their notices
    # from the publisher archive. They are still part of the installed-file check.
    tar = ["tar", "--sort=name", "--mtime=@0", "--owner=0", "--group=0", "--numeric-owner",
           "--exclude=./planet-archives", "--exclude=./licenses/Orbiter2016.pdf",
           "--exclude=./licenses/Orbiter2016-readme.txt", "-I", "zstd -T2 -3", "-cf", "-", "-C", stage, "."]
    with subprocess.Popen(tar, stdout=subprocess.PIPE) as archive:
        subprocess.run(["split", "--bytes=768MiB", "--numeric-suffixes=1", "--suffix-length=2",
                        "-", media / "apollo7.tar.zst.part"], stdin=archive.stdout, check=True)
        if archive.wait():
            raise RuntimeError("Archive creation failed")
    parts = sorted(media.glob("apollo7.tar.zst.part*"))
    (media / "SHA256SUMS").write_text("".join(f"{sha(part)}  {part.name}\n" for part in parts))
    shutil.copy2(HERE / "install-apollo7", media)
    shutil.copy2(HERE / "INSTALL.md", media)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("qualified", "modules", "orbiter", "terrain", "work"):
        parser.add_argument("--" + name, type=lambda p: Path(p).resolve(strict=True), required=True)
    main(parser.parse_args())
