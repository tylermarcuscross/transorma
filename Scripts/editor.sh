#!/bin/zsh
# Bridge Xcode compiler settings to SourceKit-LSP; this is development tooling.
set -euo pipefail
cd "${0:A:h:h}"

transorma_server="$(command -v xcode-build-server || true)"
if [[ -z "$transorma_server" ]]; then
    for transorma_candidate in /opt/homebrew/bin/xcode-build-server /usr/local/bin/xcode-build-server; do
        if [[ -x "$transorma_candidate" ]]; then
            transorma_server="$transorma_candidate"
            break
        fi
    done
fi
if [[ -z "$transorma_server" ]]; then
    print -u2 'Install the VS Code adapter with: brew install xcode-build-server'
    [[ "${1:-}" == index && "${2:-}" == --if-installed ]] && exit 0
    exit 1
fi

case "${1:-}" in
    serve) exec /bin/zsh Scripts/toolchain.sh "$transorma_server" ;;
    doctor) print -r -- "Editor adapter: $transorma_server"; exit 0 ;;
    index) ;;
    *) print -u2 'Usage: zsh Scripts/editor.sh {serve|index [--if-installed]|doctor}'; exit 2 ;;
esac

DEVELOPER_DIR="$(/bin/zsh Scripts/toolchain.sh)"
export DEVELOPER_DIR

# Incremental builds may contain no compiler invocations, and Xcode rotates its
# logs. Update the previous index with retained logs, oldest first, so untouched
# modules keep their latest valid Development settings.
transorma_logs=(.build/Xcode/Logs/Build/*.xcactivitylog(NOm))
if (( ${#transorma_logs} == 0 )) && [[ ! -f .compile ]]; then
    print -u2 'No Xcode build logs found. Run make build first.'
    exit 1
fi
mkdir -p .build
transorma_temporary="$(mktemp -d .build/editor-index.XXXXXX)"
trap 'rm -rf -- "$transorma_temporary"' EXIT
: > .build/index.log
transorma_outputs=()
for transorma_log in "${transorma_logs[@]}"; do
    transorma_output="$transorma_temporary/${transorma_log:t}.json"
    if ! "$transorma_server" parse -l "$transorma_log" -o "$transorma_output" >> .build/index.log 2>&1; then
        cat .build/index.log >&2
        exit 1
    fi
    transorma_outputs+=("$transorma_output")
done

# Resolve response-file membership now so moved/deleted files do not retain old
# settings. Python is already required by xcode-build-server; no package is added.
python3 - "$transorma_temporary/compile.json" "${transorma_outputs[@]}" <<'PY'
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys

compiler = subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip()
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
modules = {}
previous = [".compile"] if Path(".compile").is_file() else []
for log in [*previous, *sys.argv[2:]]:
    for entry in json.loads(Path(log).read_text()):
        command = entry.get("command", "")
        if "/Development/" not in command:
            continue
        arguments = shlex.split(command)
        if Path(arguments[0]).resolve() != Path(compiler).resolve():
            continue
        if "-sdk" not in arguments or Path(arguments[arguments.index("-sdk") + 1]).resolve() != Path(sdk).resolve():
            continue
        responses = set(entry.get("fileLists", []))
        responses.update(argument[1:] for argument in arguments if argument.startswith("@"))
        if any(not Path(response).is_file() for response in responses):
            continue
        # Response files are authoritative membership for cached settings too:
        # removed sources must disappear, and newly built sources must appear.
        files = [] if responses else list(entry.get("files", []))
        if entry.get("file"):
            files.append(entry["file"])
        for response in responses:
            files.extend(shlex.split(Path(response).read_text()))
        entry.pop("fileLists", None)
        entry["files"] = sorted({file for file in files if Path(file).is_file()})
        if entry["files"]:
            modules[entry.get("module_name") or entry.get("file")] = entry
if not modules:
    sys.exit("No current Development compiler settings found. Run make reindex.")

# The manifest is compiled by SwiftPM, outside Xcode's target build logs. Give
# it its own PackageDescription search path and API version; applying an app's
# compiler arguments to Package.swift produces a false missing-module error.
manifest = Path("Package.swift").resolve()
tools_version = re.match(r"//\s*swift-tools-version:\s*(\d+)\.(\d+)(?:\.(\d+))?", manifest.read_text())
if tools_version is None:
    sys.exit("Package.swift must begin with a swift-tools-version declaration.")
target = json.loads(subprocess.check_output([compiler, "-print-target-info"], text=True))
manifest_api = Path(target["paths"]["runtimeResourcePath"]) / "pm" / "ManifestAPI"
if not manifest_api.is_dir():
    sys.exit(f"The selected Swift toolchain has no manifest API at {manifest_api}.")
manifest_entry = {
    "directory": str(manifest.parent),
    "file": str(manifest),
    "command": shlex.join([
        compiler, "-typecheck", str(manifest), "-sdk", sdk,
        "-I", str(manifest_api), "-swift-version", tools_version[1],
        "-package-description-version", ".".join(part or "0" for part in tools_version.groups()),
    ]),
}
output = Path(sys.argv[1])
output.write_text(json.dumps([*modules.values(), manifest_entry], indent=4) + "\n")
os.replace(output, ".compile")
print(f"Updated VS Code settings for {len(modules)} compiled modules and Package.swift.")
PY
