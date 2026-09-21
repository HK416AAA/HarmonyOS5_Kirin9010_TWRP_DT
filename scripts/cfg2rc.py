#!/usr/bin/env python3
"""cfg2rc.py - translate the HarmonyOS init config into TWRP's Android init rc.

AUTHORITATIVE SOURCES (edit these, never the generated file)
  harmony/init.kirin9010.cfg   OpenHarmony init jobs (JSON)
  harmony/ohos.recovery.cfg    OpenHarmony recovery-mode overlay (JSON)

TWRP's init is Android init: it reads `.rc` files and cannot parse the
OpenHarmony JSON `.cfg`. This script is the single bridge between the two, so
the device tree keeps one source of truth (the OHOS config) and the Android rc
TWRP actually loads is generated from it. They cannot drift.

Why only init is bridged
  An Android ueventd rc is deliberately NOT generated. Both the OHOS and the
  Android device tables are kept, but only the OHOS one is authoritative and it
  is shipped at its stock path (`/system/etc/ueventd.config`). Android's ueventd
  cannot be handed the table either way:
    * it resolves uid/gid with getpwnam()/getgrnam(), so the numeric HarmonyOS
      gids the stock table uses are rejected as "invalid gid";
    * its extra-config file `/ueventd.<ro.hardware>.rc` is only parsed when
      `ro.product.first_api_level` is old enough, and this tree never sets
      PRODUCT_SHIPPING_API_LEVEL.
  See harmony/README.md.

Translation tables
  job name        Android trigger
  pre-init        early-init
  init            init
  post-fs         fs
  late-fs         late-fs
  post-fs-data    post-fs-data
  boot            boot

  condition `param:K=V` -> `on property:K=V`. Any other condition (a bare
  name, wildcards, `&&`, `${...}`) is dropped: TWRP has no HarmonyOS param
  service, so the trigger could never fire.

  `setparam K V` -> `setprop K V`.
  `mount <type> <source> <target> [opts]` -> `mount <source> <target> <type>
  [opts]` (OHOS puts the filesystem type first, Android's init puts it last).
  Commands with an identical meaning (mkdir, chown, chmod, symlink, write,
  wait, rmdir, restorecon, export) pass through unchanged. Commands with no
  Android equivalent (mkswap, swapon, swapoff, seteswap, start, stop) are
  dropped with a warning.

Usage
  scripts/cfg2rc.py <cfg> [<cfg> ...] --out <file.rc>
"""

import argparse
import json
import os
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def display(path):
    """Repo-relative path for messages and the header, so the generated output
    is identical whether the script is run with relative or absolute paths."""
    resolved = os.path.abspath(path)
    prefix = REPO_ROOT + os.sep
    return resolved[len(prefix):] if resolved.startswith(prefix) else path

STAGE = {
    "pre-init": "early-init",
    "init": "init",
    "post-fs": "fs",
    "late-fs": "late-fs",
    "post-fs-data": "post-fs-data",
    "boot": "boot",
}

DROP_STAGES = {"post-init"}

PASSTHROUGH = {
    "mkdir", "chown", "chmod", "symlink",
    "write", "wait", "rmdir", "restorecon", "export",
}

REMAP = {"setparam": "setprop"}

DROP_CMDS = {"seteswap", "swapoff", "swapon", "mkswap", "start", "stop",
             "exec", "exec_start"}


def translate_condition(cond):
    """Return the Android `on <trigger>` body, or None if unmappable."""
    cond = cond.strip()
    if cond.startswith("param:"):
        expr = cond[len("param:"):]
        if "&&" in expr or "||" in expr or "${" in expr or expr.endswith("*"):
            return None
        return "property:" + expr
    if cond.startswith("property:"):
        return cond
    return None


def translate_cmd(cmd, warn):
    parts = cmd.split()
    if not parts:
        return None
    verb = parts[0]
    if verb in PASSTHROUGH:
        return cmd
    if verb in REMAP:
        return " ".join([REMAP[verb]] + parts[1:])
    if verb == "mount":
        # OHOS: mount <type> <source> <target> [options...]
        # Android init: mount <source> <target> <type> [options...]
        if len(parts) < 4:
            warn("dropping `%s` (mount needs type, source and target)" % cmd)
            return None
        fs_type, source, target = parts[1], parts[2], parts[3]
        return " ".join(["mount", source, target, fs_type] + parts[4:])
    if verb in DROP_CMDS:
        warn("dropping `%s` (no Android init equivalent)" % cmd)
        return None
    warn("dropping unknown command `%s`" % cmd)
    return None


def generate(paths, warn):
    order = []
    stage_lines = {}
    stage_seen = {}
    for path in paths:
        with open(path) as fh:
            data = json.load(fh)
        if not isinstance(data, dict) or "jobs" not in data:
            warn("%s: no `jobs` array, skipped" % display(path))
            continue
        for job in data.get("jobs", []):
            name = job.get("name", "")
            cond = job.get("condition")
            if cond:
                stage = translate_condition(cond)
                if stage is None:
                    warn("%s: dropping job `%s` (unsupported condition `%s`)"
                         % (display(path), name, cond))
                    continue
            elif name in DROP_STAGES:
                warn("%s: dropping job `%s` (no Android equivalent)"
                     % (display(path), name))
                continue
            else:
                stage = STAGE.get(name)
                if stage is None:
                    warn("%s: dropping job `%s` (unknown stage)"
                     % (display(path), name))
                    continue
            if stage not in stage_lines:
                order.append(stage)
                stage_lines[stage] = []
                stage_seen[stage] = set()
            for cmd in job.get("cmds", []):
                line = translate_cmd(cmd, warn)
                if line is None:
                    continue
                if line in stage_seen[stage]:
                    warn("%s: duplicate `%s` in `on %s`, skipped"
                         % (display(path), line, stage))
                    continue
                stage_seen[stage].add(line)
                stage_lines[stage].append(line)

    out = ["# GENERATED by scripts/cfg2rc.py - DO NOT EDIT.",
           "# HarmonyOS sources: " + ", ".join(display(p) for p in paths),
           ""]
    for stage in order:
        out.append("on %s" % stage)
        for line in stage_lines[stage]:
            out.append("    " + line)
        out.append("")
    return "\n".join(out).rstrip("\n") + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("cfgs", nargs="+", help="OpenHarmony .cfg files, in order")
    parser.add_argument("--out", required=True, help="Android rc to write")
    args = parser.parse_args()

    warnings = []

    def warn(message):
        warnings.append(message)
        print("cfg2rc: warning: " + message, file=sys.stderr)

    text = generate(args.cfgs, warn)
    with open(args.out, "w") as fh:
        fh.write(text)
    print("cfg2rc: wrote %s (%d lines, %d warnings)"
          % (args.out, len(text.splitlines()), len(warnings)))


if __name__ == "__main__":
    main()
