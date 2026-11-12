#!/usr/bin/env python3
"""Configure this Mac's existing development identity without handling private keys."""
from pathlib import Path
import argparse
import json
import re
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--team-id", required=True)
parser.add_argument("--identity", help="SHA-1 fingerprint of an existing signing identity")
parser.add_argument("--app-group", help="Defaults to the macOS Team-ID-prefixed group")
args = parser.parse_args()
if not re.fullmatch(r"[A-Z0-9]{10}", args.team_id):
    parser.error("Team ID must be 10 uppercase letters/digits")
if args.identity and not re.fullmatch(r"[0-9A-Fa-f]{40}", args.identity):
    parser.error("Identity must be a 40-character certificate fingerprint")
group = args.app_group or args.team_id + ".com.nuistgo.shared"
if not re.fullmatch(r"[A-Za-z0-9.-]+", group) or not (group.startswith(args.team_id + ".") or group.startswith("group.")):
    parser.error("Use a Team-ID-prefixed macOS group or a registered group.* identifier")
root = Path(__file__).resolve().parents[1]
config = {"teamID": args.team_id, "appGroup": group, "style": "Manual" if args.identity else "Automatic"}
if args.identity:
    config["identity"] = args.identity.upper()
(root / "Signing.local.json").write_text(json.dumps(config, indent=2) + "\n")
subprocess.run([sys.executable, str(root / "Tools/generate_project.py")], check=True)
print("Configured both targets and their shared container. No private key was read or exported.")
