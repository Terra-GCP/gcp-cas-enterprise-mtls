# Allowlist-based lifecycle (automation)

**GCP CAS Enterprise Client mTLS Lifecycle** (`gcp-cas-enterprise-mtls`) is not only “run CAS”—it automates **client certificate lifecycle** end-to-end: **rules before issuance**, **one pipeline for issue or revoke**, **allowlist updates** for **immediate load-balancer effect**, **backups of allowlist state**, and **expired-certificate cleanup**.

---

## Why this pattern exists (highlight)

1. **Validation first** — `validate-cert-request.sh` runs **before** `gcloud privateca certificates create`. Bad OU/CN/lifetime/blackout requests **never touch** the CA.
2. **Operational simplicity** — Operators choose app/env/parameters; the pipeline generates **key + CSR**, calls CAS, uploads artifacts, updates Secret Manager, then **mutates the allowlist** in Certificate Manager.
3. **Revocation that matches how many LBs work** — **Trust-anchor-only** configs plus “revoke in CAS / publish CRL” often **does not** change what an **external HTTPS load balancer** accepts for **client certificates**, because **CRL checks are frequently absent**. **Allowlisted leaf PEMs**: remove the PEM list entry → **handshake fails** as soon as config propagates.
4. **Recovery and audit** — **BEFORE** and **AFTER** YAML snapshots of the trust config (including allowlist) land in GCS every run.
5. **Hygiene** — **Expired** entries are stripped from the allowlist automatically (`cleanup-expired`).

---

## Trust anchor vs allowlist (recap)

| Mode | LB / client-auth behavior (simplified) | Revocation story |
|------|----------------------------------------|------------------|
| **Trust anchor (CA only)** | “Any leaf signed by this CA (chain valid)” may be accepted. | **CRL/OCSP** may be **ignored** by the LB → revoked certs can still connect. |
| **Allowlisted PEMs (this solution)** | “Only these **exact** leaf certificates.” | **Remove PEM from list** → **not accepted** regardless of CRL. |

---

## Components

| Piece | Role |
|--------|------|
| **Pipelines** (ADO / GitHub / Cloud Build) | Orchestrate validate → issue **or** revoke → backup → allowlist maintenance. |
| **CAS + template** | Signs CSRs; remains CA of record and audit trail. |
| **GCS** | Issued PEM copies; **trustconfig/{app}-{env}/BEFORE\|AFTER-*.yaml** snapshots. |
| **Secret Manager** | Private keys (per cert id), deleted on revoke path. |
| **Trust config** (per app/env) | `allowlistedCertificates` consumed by front ends. |
| **`trust_config_allowlist.py`** | Safe YAML **add / remove / cleanup-expired** between `export` and `import`. |

---

## Issue pipeline (ordered steps)

1. **BEFORE** — Export current trust config YAML to GCS.  
2. **Validate** — All policy checks (`validate-cert-request.sh`); **fail = stop** (no issuance).  
3. **Issue** — Generate key + CSR; CAS sign; PEM → GCS; key → Secret Manager.  
4. **Activate** — Add issued PEM to **`allowlistedCertificates`**.  
5. **Cleanup** — Remove **expired** allowlist entries.  
6. **AFTER** — Export updated trust config YAML to GCS.  

---

## Revoke pipeline (ordered steps)

1. **BEFORE** — Export snapshot.  
2. **Remove** — Match PEM (from GCS if present); **remove from allowlist** (fingerprint).  
3. **Delete** — GCS PEM object; Secret Manager secret.  
4. **CAS** — Record revocation for audit.  
5. **Cleanup** — Expired entries again.  
6. **AFTER** — Export snapshot.  

---

## Trust config naming

Default: **`trust-config-${WORKLOAD_APP}-${WORKLOAD_ENV}`**. Override: `TRUST_CONFIG_NAME` / **`trustConfigName`**.

You must **create** the trust config resource (allowlist-capable) before pipelines import updates—see Google’s Certificate Manager docs for initial YAML.

---

## Strict lifetimes

**`STRICT_VALIDITY_ENVS`** (default in scripts: `prod`) lists env labels that use **`MAX_VALIDITY_DAYS_PROD`** instead of **`MAX_VALIDITY_DAYS`**. Adjust the list to match your naming convention.

---

## Recovery

1. `gsutil ls gs://BUCKET/trustconfig/${APP}-${ENV}/`  
2. Download **`AFTER-*`** (or **`BEFORE-*`** for rollback).  
3. `gcloud certificate-manager trust-configs import … --source=file.yaml`  
4. `gcloud certificate-manager trust-configs describe …`  

---

## Operational notes

- Prefer **rare** manual Console edits; alert on changes outside the lifecycle SA.  
- Pin `gcloud` / Terraform; re-read `privateca` and `trust-configs import` help on upgrades.  
- Agents need **PyYAML** (`scripts/requirements.txt`).

Return to [README](../README.md).
