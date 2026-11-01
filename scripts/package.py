"""Build the mod-only release ZIP from an explicit file allowlist."""
import argparse
import hashlib
import pathlib
import re
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MOD = ROOT / "mod/NightCityLottery"
INSTALL_PATH = "bin/x64/plugins/cyber_engine_tweaks/mods/NightCityLottery"
FILES = ("init.lua", "battlefield.lua", "pool.lua", "THIRD_PARTY.txt")


def version():
    match = re.search(r'local VERSION = "([0-9]+\.[0-9]+\.[0-9]+)"',
                      (MOD / "init.lua").read_text(encoding="utf-8"))
    if not match:
        raise ValueError("Cannot find the mod version")
    return match.group(1)


def build(output):
    output = pathlib.Path(output)
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"NightCityLottery-{version()}.zip"
    sources = [(f"{INSTALL_PATH}/{name}", MOD / name) for name in FILES]
    sources.append((f"{INSTALL_PATH}/LICENSE", ROOT / "LICENSE"))
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for name, source in sorted(sources):
            # Fixed metadata makes the archive reproducible for identical sources.
            info = zipfile.ZipInfo(name, date_time=(2026, 11, 2, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            bundle.writestr(info, source.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    (output / "SHA256SUMS.txt").write_text(f"{checksum}  {archive.name}\n", encoding="utf-8")
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=pathlib.Path, default=ROOT / "dist")
    args = parser.parse_args()
    archive = build(args.output)
    print(archive)
    print((archive.parent / "SHA256SUMS.txt").read_text(encoding="utf-8"), end="")
