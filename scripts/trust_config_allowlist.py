#!/usr/bin/env python3
"""Certificate Manager trust config allowlist helpers for GCP CAS Enterprise Client mTLS Lifecycle.

Export → edit YAML → import. Requires `gcloud` and `openssl` on PATH. Trust config must
already support allowlistedCertificates. See docs/allowlist-lifecycle.md.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml


def _run(cmd: list[str]) -> None:
    subprocess.check_call(cmd)


def gcloud_export(project: str, trust_config: str, dest: Path) -> None:
    _run(
        [
            "gcloud",
            "certificate-manager",
            "trust-configs",
            "export",
            trust_config,
            "--project",
            project,
            "--location=global",
            "--destination",
            str(dest),
        ]
    )


def gcloud_import(project: str, trust_config: str, src: Path) -> None:
    _run(
        [
            "gcloud",
            "certificate-manager",
            "trust-configs",
            "import",
            trust_config,
            "--project",
            project,
            "--location=global",
            "--source",
            str(src),
        ]
    )


def _normalize_pem(pem: str) -> str:
    pem = pem.strip()
    if not pem.endswith("\n"):
        pem += "\n"
    return pem


def _pem_fingerprint_sha256(pem: str) -> str:
    proc = subprocess.run(
        ["openssl", "x509", "-noout", "-fingerprint", "-sha256", "-inform", "PEM"],
        input=pem.encode(),
        capture_output=True,
        check=True,
    )
    # SHA256 Fingerprint=AA:BB:...
    line = proc.stdout.decode().strip().splitlines()[0]
    return line.split("=", 1)[1].strip().upper()


def _is_cert_expired(pem: str) -> bool:
    """True if not valid after now (openssl -checkend 0)."""
    proc = subprocess.run(
        ["openssl", "x509", "-inform", "PEM", "-noout", "-checkend", "0"],
        input=pem.encode(),
        capture_output=True,
    )
    return proc.returncode != 0


def _allowlist_key(doc: dict) -> str:
    if "allowlistedCertificates" in doc:
        return "allowlistedCertificates"
    if "allowlisted_certificates" in doc:
        return "allowlisted_certificates"
    return "allowlistedCertificates"


def _allowlist_entries(doc: dict) -> list:
    k = _allowlist_key(doc)
    if doc.get(k) is None:
        doc[k] = []
    return doc[k]


def cmd_add(args: argparse.Namespace) -> None:
    pem = _normalize_pem(Path(args.pem_file).read_text(encoding="utf-8"))
    with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as tmp:
        tpath = Path(tmp.name)
    try:
        gcloud_export(args.workload_project, args.trust_config, tpath)
        doc = yaml.safe_load(tpath.read_text(encoding="utf-8")) or {}
        key = _allowlist_key(doc)
        entries = _allowlist_entries(doc)
        try:
            new_fp = _pem_fingerprint_sha256(pem)
        except subprocess.CalledProcessError as e:
            print("Invalid PEM certificate.", file=sys.stderr)
            raise SystemExit(1) from e
        for item in entries:
            existing = item.get("pemChain") or item.get("pemCertificate") or item.get("pem_certificate")
            if isinstance(existing, dict):
                existing = existing.get("pemCertificate", "")
            if not existing:
                continue
            try:
                if _pem_fingerprint_sha256(str(existing)) == new_fp:
                    print("Certificate already present on allowlist; nothing to do.")
                    return
            except subprocess.CalledProcessError:
                continue
        entries.append({"pemCertificate": pem})
        # Normalise on camelCase used by gcloud import samples
        if key == "allowlisted_certificates":
            doc["allowlistedCertificates"] = doc.pop("allowlisted_certificates")
        out = yaml.dump(doc, default_flow_style=False, sort_keys=False, allow_unicode=True)
        tpath.write_text(out, encoding="utf-8")
        gcloud_import(args.workload_project, args.trust_config, tpath)
        print("Allowlist updated (certificate added).")
    finally:
        tpath.unlink(missing_ok=True)


def cmd_remove(args: argparse.Namespace) -> None:
    pem = _normalize_pem(Path(args.pem_file).read_text(encoding="utf-8"))
    try:
        target_fp = _pem_fingerprint_sha256(pem)
    except subprocess.CalledProcessError as e:
        print("Invalid PEM certificate for removal.", file=sys.stderr)
        raise SystemExit(1) from e
    with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as tmp:
        tpath = Path(tmp.name)
    try:
        gcloud_export(args.workload_project, args.trust_config, tpath)
        doc = yaml.safe_load(tpath.read_text(encoding="utf-8")) or {}
        key = _allowlist_key(doc)
        entries = list(_allowlist_entries(doc))
        kept = []
        removed = False
        for item in entries:
            raw = item.get("pemChain") or item.get("pemCertificate") or item.get("pem_certificate")
            if isinstance(raw, dict):
                raw = raw.get("pemCertificate", "")
            if not raw:
                kept.append(item)
                continue
            try:
                if _pem_fingerprint_sha256(str(raw)) == target_fp:
                    removed = True
                    continue
            except subprocess.CalledProcessError:
                pass
            kept.append(item)
        if not removed:
            print("Warning: no matching allowlisted certificate removed (fingerprint not found).", file=sys.stderr)
        doc[key] = kept
        if key == "allowlisted_certificates":
            doc["allowlistedCertificates"] = doc.pop("allowlisted_certificates")
        out = yaml.dump(doc, default_flow_style=False, sort_keys=False, allow_unicode=True)
        tpath.write_text(out, encoding="utf-8")
        gcloud_import(args.workload_project, args.trust_config, tpath)
        print("Allowlist updated (certificate removed if matched).")
    finally:
        tpath.unlink(missing_ok=True)


def cmd_cleanup(args: argparse.Namespace) -> None:
    with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as tmp:
        tpath = Path(tmp.name)
    try:
        gcloud_export(args.workload_project, args.trust_config, tpath)
        doc = yaml.safe_load(tpath.read_text(encoding="utf-8")) or {}
        key = _allowlist_key(doc)
        entries = list(_allowlist_entries(doc))
        kept = []
        dropped = 0
        for item in entries:
            raw = item.get("pemChain") or item.get("pemCertificate") or item.get("pem_certificate")
            if isinstance(raw, dict):
                raw = raw.get("pemCertificate", "")
            if not raw:
                kept.append(item)
                continue
            if _is_cert_expired(str(raw)):
                dropped += 1
                continue
            kept.append(item)
        if dropped == 0:
            print("No expired allowlisted certificates removed.")
            return
        doc[key] = kept
        if key == "allowlisted_certificates":
            doc["allowlistedCertificates"] = doc.pop("allowlisted_certificates")
        out = yaml.dump(doc, default_flow_style=False, sort_keys=False, allow_unicode=True)
        tpath.write_text(out, encoding="utf-8")
        gcloud_import(args.workload_project, args.trust_config, tpath)
        print(f"Removed {dropped} expired allowlisted certificate(s).")
    finally:
        tpath.unlink(missing_ok=True)


def main() -> None:
    p = argparse.ArgumentParser(description="TrustConfig allowlist maintenance")
    sub = p.add_subparsers(dest="cmd", required=True)

    def add_common(sp: argparse.ArgumentParser) -> None:
        sp.add_argument("--workload-project", required=True)
        sp.add_argument("--trust-config", required=True, help="Trust config resource id (short name)")

    sp_add = sub.add_parser("add", help="Append a PEM to allowlistedCertificates")
    add_common(sp_add)
    sp_add.add_argument("--pem-file", required=True)
    sp_add.set_defaults(func=cmd_add)

    sp_rm = sub.add_parser("remove", help="Remove a PEM from allowlistedCertificates by fingerprint")
    add_common(sp_rm)
    sp_rm.add_argument("--pem-file", required=True)
    sp_rm.set_defaults(func=cmd_remove)

    sp_cl = sub.add_parser("cleanup-expired", help="Drop expired PEMs from allowlistedCertificates")
    add_common(sp_cl)
    sp_cl.set_defaults(func=cmd_cleanup)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
