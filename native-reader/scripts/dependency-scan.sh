#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
repo_root=$(git -C "$root" rev-parse --show-toplevel)

python3 - "$root" "$repo_root" <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
repo = pathlib.Path(sys.argv[2])

dependencies = json.loads((root / "DEPENDENCIES.json").read_text())
assert dependencies["schema_version"] == 1
assert dependencies["project_license"] == "AGPL-3.0-only"
by_name = {item["name"]: item for item in dependencies["dependencies"]}

expected = {
    "Quill": ("39262ee0bef69915e3ead3ac218d5973916f422a", "MIT"),
    "rm-appload": ("5bb34a362f09f753f18bd6261558f8e2737aacdb", "GPL-3.0-only"),
    "Xovi": ("0c8d5269b55c851901d4e4a754dc2d7deab40b17", "LGPL-3.0-only"),
    "qt-resource-rebuilder (rm-xovi-extensions)":
        ("7874154dba6793cc68a15fae0fb9dd272c4ed20a", "GPL-3.0-only"),
    "actions/checkout": ("d23441a48e516b6c34aea4fa41551a30e30af803", "MIT"),
    "actions/upload-artifact": ("043fb46d1a93c77aae656e7c1c64a875d1fc6a0a", "MIT"),
}
for name, (commit, license_id) in expected.items():
    item = by_name[name]
    assert item["commit"] == commit, (name, "commit")
    assert item["license"] == license_id, (name, "license")
    assert item["source"].startswith("https://github.com/"), (name, "source")

sdk = by_name["Ferrari public SDK"]
assert sdk["version"] == "remarkable-production-image-5.7.119-ferrari-public (3.27.0.97)"
assert sdk["sha256"] == "324d77d84dda5ba8fac484107b3c9981daaa28fe5ebed6589172f0cb1bcdd020"
vendor = by_name["libqsgepaper.so"]
assert vendor["redistributed"] == "never"
assert vendor["license"].startswith("proprietary")

quill_header = (root / "platform/paperpro/display/quill_display_backend.h").read_text()
assert expected["Quill"][0] in quill_header
qtfb_header = (root / "platform/paperpro/display/qtfb_protocol.h").read_text()
assert expected["rm-appload"][0] in qtfb_header
assert (root / "third_party/quill/LICENSE").is_file()

workflow = (repo / ".github/workflows/native-reader.yml").read_text()
uses = re.findall(r"^\s*-?\s*uses:\s*([^@\s]+)@([^\s#]+)", workflow, re.MULTILINE)
assert uses, "no workflow actions found"
for action, revision in uses:
    assert re.fullmatch(r"[0-9a-f]{40}", revision), (action, "not commit pinned", revision)
assert ("actions/checkout", "d23441a48e516b6c34aea4fa41551a30e30af803") in uses
assert ("actions/upload-artifact", "043fb46d1a93c77aae656e7c1c64a875d1fc6a0a") in uses
assert sdk["sha256"] in workflow
assert "3.27.0.97/ferrari/remarkable-production-image-5.7.119-ferrari-public-x86_64-toolchain.sh" in workflow

manifest = json.loads((root / "platform/paperpro/lifecycle/external.manifest.json").read_text())
assert manifest["qtfb"] is True
assert manifest["environment"]["PPR_DISPLAY_BACKEND"] == "qtfb"
assert manifest["application"] == "scripts/launch-qtfb.sh"

package_script = (root / "scripts/package-device.sh").read_text()
for required in ("BUILD-VERSION.txt", "DEPENDENCIES.json", "SOURCE.json",
                 "PACKAGE-CONTENTS.sha256", "QUILL-MIT.txt", "AGPL-3.0.txt"):
    assert required in package_script, required

print("native-reader dependency/pin scan: PASS")
PY
