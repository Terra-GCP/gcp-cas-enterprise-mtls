# Architecture

How the **GCP CAS Enterprise Client mTLS Lifecycle** is structured—and how it **extends** a plain Certificate Authority Service deployment.

---

## Beyond “Terraform + CAS only”

| Plain CAS / mTLS baseline | What this solution adds |
|---------------------------|-------------------------|
| CA pools, template, CRL bucket in code | Same **Terraform** foundation (see `terraform/`). |
| Manual CSRs and ad hoc issuance | **Pipeline-driven** issue path: validate → **openssl** key+CSR → **gcloud privateca** → GCS + Secret Manager. |
| Trust config with **CA anchor only** | **Allowlisted leaf PEMs** + automation to **add/remove** entries so the **load balancer** enforces **explicit** trust (see below). |
| CRL as primary revocation story for LBs | Many **external LBs do not check CRLs** for client certs; **shrinking the allowlist** revokes **at handshake** without depending on that behavior. |
| No standard backup of trust state | **BEFORE/AFTER** YAML export to GCS on **every** run. |
| Stale certs on allowlist | **Expired-entry cleanup** after issue/revoke. |
| Informal policy | **Central validation script** gates issuance (**OU, CN, lifetime, env rules, blackout window**). |

---

## Projects and responsibilities

- **PKI project:** CAS **pools**, **root/sub CAs**, **CRL / artifact bucket**, **certificate template**, **lifecycle service account**, **Secret Manager** usage for issued keys.
- **Workload projects:** **Certificate Manager trust configs** (here: **allowlist**-oriented), apps and load balancers that consume them.

“Where we sign” (PKI) vs “what the LB accepts” (per-app/env allowlist in workload projects).

---

## System context

```mermaid
flowchart TB
  subgraph operators [People and automation]
    Op[Operators / pipelines]
  end
  subgraph pki [PKI project]
    CAS[Certificate Authority Service]
    GCS[Cloud Storage bucket]
    IAM[Lifecycle service account]
    CAS --> GCS
    IAM --> CAS
    IAM --> GCS
  end
  subgraph workloads [Workload projects]
    CM[Certificate Manager trust configs allowlist]
    Svc[Load balancers / services]
    CM --> Svc
  end
  Op -->|1 validate 2 issue or revoke 3 allowlist 4 backup cleanup| IAM
  IAM -->|export import YAML| CM
  IAM -->|sign with template| CAS
```

---

## Issuance sequence (automation — the core story)

This sequence is what ties **validation**, **CAS**, **allowlist**, **backup**, and **cleanup** together:

```mermaid
sequenceDiagram
  participant P as Pipeline
  participant T0 as trust-config-backup BEFORE
  participant V as validate-cert-request.sh
  participant I as issue-cert.sh
  participant CA as Subordinate CA
  participant SM as Secret Manager
  participant B as GCS bucket
  participant A as trust_config_allowlist.py
  participant T1 as trust-config-backup AFTER
  P->>T0: Export allowlist YAML snapshot
  P->>V: Policy checks before any CAS call
  V-->>P: Pass or fail stop
  P->>I: Key CSR openssl + privateca create
  I->>CA: Sign certificate
  CA-->>I: PEM
  I->>B: Store PEM copy
  I->>SM: Store private key
  P->>A: Add PEM to allowlistedCertificates
  P->>A: Remove expired allowlist PEMs
  P->>T1: Export allowlist YAML snapshot
  T1->>B: Upload backups trustconfig app-env
```

Paths: `trustconfig/{app}-{env}/BEFORE|AFTER-*.yaml` — see [allowlist-lifecycle.md](allowlist-lifecycle.md).

---

## Load balancer enforcement: anchor vs allowlist

```mermaid
flowchart LR
  subgraph anchor [Anchor only common gap]
    L1[Valid chain to CA]
    L2[CRL not checked on many LBs]
    L3[Revocation lag or blind spot]
    L1 --> L2 --> L3
  end
  subgraph allow [This solution]
    M1[Leaf PEM in allowlist]
    M2[LB checks explicit list]
    M3[Remove PEM equals immediate deny]
    M1 --> M2 --> M3
  end
```

---

## IAM (high level)

| Principal | Scope | Role |
|-----------|--------|------|
| Lifecycle SA | Subordinate **pool** | Issue / manage end-entity certs. |
| Lifecycle SA | **Bucket** | PEM copies, **trust config YAML backups**. |
| Lifecycle SA | Optional **folders** | `certificatemanager.editor` for trust config import/export. |
| Lifecycle SA | **PKI project** | Secret Manager (narrow in production). |
| Private CA service agent | **Bucket** | CRL/CA publication material. |

---

## CRL bucket

Holds CRL-related objects **and** operational prefixes (`certificates/…`, `trustconfig/…`). Align **lifecycle rules** with retention and audit policy.

---

## Certificate template

**Pool** policy + **template** narrow **client-auth** profiles and optional **CEL** on SANs. Template is **not** a substitute for **pipeline validation** or **allowlist** enforcement at the LB.

Return to [README](../README.md).
