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

# Incremental builds may contain no compiler invocations. Replay retained logs
# oldest first, then keep the latest valid Development settings for each module.
transorma_logs=(.build/Xcode/Logs/Build/*.xcactivitylog(NOm))
if (( ${#transorma_logs} == 0 )); then
    print -u2 'No Xcode build logs found. Run make build first.'
    exit 1
fi
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
import shlex
import sys

modules = {}
for log in sys.argv[2:]:
    for entry in json.loads(Path(log).read_text()):
        command = entry.get("command", "")
        if "/Development/" not in command:
            continue
        files = list(entry.get("files", []))
        if entry.get("file"):
            files.append(entry["file"])
        for response in entry.pop("fileLists", []):
            if Path(response).is_file():
                files.extend(shlex.split(Path(response).read_text()))
        entry["files"] = sorted({file for file in files if Path(file).is_file()})
        if entry["files"]:
            modules[entry.get("module_name") or entry.get("file")] = entry
if not modules:
    sys.exit("No current Development compiler settings found. Run make reindex.")
output = Path(sys.argv[1])
output.write_text(json.dumps(list(modules.values()), indent=4) + "\n")
os.replace(output, ".compile")
print(f"Updated VS Code settings for {len(modules)} compiled modules.")
PY
