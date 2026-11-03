"""Prepare TD's project and ROM paths for the current checkout."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent
project = root / "td_project/latest_plus_v3_hdmi_capture.al"
source = root / "user_source/hdl_source/astra"


def replace(path, pattern, substitution):
    data = path.read_bytes().decode("utf-8")
    updated, count = re.subn(pattern, substitution, data)
    if not count:
        raise SystemExit(f"Expected path not found in {path.name}")
    if updated != data:
        path.write_bytes(updated.encode("utf-8"))


def rom_path(match):
    rom = root / "user_source" / match[1]
    if not rom.is_file():
        raise SystemExit(f"ROM file not found: {rom}")
    return rom.as_posix()


replace(project, r'(?<=<Project Version="3" Minor="2" Path=")[^"]+', lambda _: project.parent.as_posix())
for name in ("face_candidate_v14_pro.sv", "font_row_rom_pro.v"):
    replace(source / name, r'(?<=\$readmemh\(")[^"]*?/user_source/([^"]+)', rom_path)
