"""Identity for this packaged B/S server; keeps other project copies separate."""
from pathlib import Path
import hashlib
from compatibility import SOFTWARE_VERSION, FPGA_STATUS_VERSIONS, FPGA_CONTROL_VERSIONS, TARGET_FPGA_PROTOCOL

ROOT = Path(__file__).resolve().parent
PROJECT_ID = "latest_plus_v3_fixed"
SOFTWARE_ID = "plus_v3_sort_app"
DEPLOYMENT_ID = hashlib.sha256(str(ROOT).casefold().encode("utf-8")).hexdigest()[:20]

def identity():
    return dict(project_id=PROJECT_ID, software_id=SOFTWARE_ID,
                software_version=SOFTWARE_VERSION, deployment_id=DEPLOYMENT_ID,
                fpga_status_versions=list(FPGA_STATUS_VERSIONS),
                fpga_control_versions=list(FPGA_CONTROL_VERSIONS),target_fpga_protocol=TARGET_FPGA_PROTOCOL)

