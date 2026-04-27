"""Stub `python -m dlm_sway` entrypoint for the smoke workflow.

Routes the two subcommands the action's bash entrypoint shells out
to (``gate`` and ``report``) at canned outputs. Anything that's not
``gate`` or ``report`` exits non-zero so the smoke catches the case
where the action grew a new sway dependency we forgot to stub.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def _gate(argv: list[str]) -> None:
    """Pretend to run a sway gate. Writes a canned PASS report."""
    if "--report" not in argv:
        print("stub: --report is required", file=sys.stderr)
        sys.exit(2)
    out_path = Path(argv[argv.index("--report") + 1])
    report = {
        "score": {"overall": 0.84, "components": {"adherence": 0.9, "attribution": 0.8}},
        "probes": [
            {"name": "smoke", "kind": "delta_kl", "verdict": "pass", "score": 0.84},
        ],
    }
    out_path.write_text(json.dumps(report), encoding="utf-8")
    sys.exit(0)


def _report(argv: list[str]) -> None:
    """Pretend to render the JSON report to markdown."""
    if not argv:
        print("stub: report needs a json path", file=sys.stderr)
        sys.exit(2)
    json_path = Path(argv[0])
    data = json.loads(json_path.read_text(encoding="utf-8"))
    score = data["score"]["overall"]
    lines = [f"# sway report (stub) — score {score:.2f}", ""]
    for p in data["probes"]:
        lines.append(f"- **{p['name']}** ({p['kind']}): `{p['verdict']}` — {p['score']:.2f}")
    print("\n".join(lines))
    sys.exit(0)


def _main() -> None:
    if len(sys.argv) < 2:
        print("stub: usage: python -m dlm_sway {gate,report} ...", file=sys.stderr)
        sys.exit(2)
    cmd, rest = sys.argv[1], sys.argv[2:]
    if cmd == "gate":
        _gate(rest)
    elif cmd == "report":
        _report(rest)
    else:
        print(f"stub: unknown command {cmd!r}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    _main()
