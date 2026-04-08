# Diagram gallery

Visual index for **GCP CAS Enterprise Client mTLS Lifecycle**. Use these in design reviews, onboarding decks, and architecture records.

---

## 1. Solution positioning (Terraform vs automation)

```mermaid
flowchart TB
  subgraph tf [Terraform — PKI foundation]
    T1[API enables]
    T2[CRL bucket + IAM]
    T3[CA pools + root + sub CA]
    T4[Certificate template]
    T5[Lifecycle SA + folder IAM]
    T1 --> T2 --> T3 --> T4 --> T5
  end
  subgraph cicd [CI/CD — certificate lifecycle]
    C1[Validate policy]
    C2[Issue or revoke]
    C3[Allowlist YAML]
    C4[Backup + cleanup]
    C1 --> C2 --> C3 --> C4
  end
  tf -->|produces ids bucket SA| cicd
```

---

## 2. Multi-platform automation (same semantics)

```mermaid
flowchart LR
  subgraph runners [Execution planes]
    ADO[Azure DevOps]
    GHA[GitHub Actions]
    CB[Cloud Build]
  end
  Core[scripts validate issue revoke backup allowlist]
  ADO --> Core
  GHA --> Core
  CB --> Core
```

---

## 3. Issue path — decision / state flow

```mermaid
stateDiagram-v2
  [*] --> PreBackup
  PreBackup --> Validate
  Validate --> Reject: failed
  Validate --> IssueCAS: passed
  Reject --> [*]
  IssueCAS --> UploadGCS
  UploadGCS --> SecretSM
  SecretSM --> AllowlistAdd
  AllowlistAdd --> CleanupExpired
  CleanupExpired --> PostBackup
  PostBackup --> [*]
```

---

## 4. Revoke path — state flow

```mermaid
stateDiagram-v2
  [*] --> PreBackup
  PreBackup --> AllowlistRemove
  AllowlistRemove --> DeleteGCS
  DeleteGCS --> DeleteSM
  DeleteSM --> CASRevoke
  CASRevoke --> CleanupExpired
  CleanupExpired --> PostBackup
  PostBackup --> [*]
```

---

## 5. Validation gate (before CAS)

```mermaid
flowchart TD
  Start([Request]) --> A{App in allow-list?}
  A -->|no| X[Fail]
  A -->|yes| B{OU equals env-app?}
  B -->|no| X
  B -->|yes| C{CN contains env token?}
  C -->|no| X
  C -->|yes| D{CN length and charset OK?}
  D -->|no| X
  D -->|yes| E{Validity in range for env?}
  E -->|no| X
  E -->|yes| F{notAfter outside blackout?}
  F -->|no| X
  F -->|yes| OK([Pass to CAS])
```

---

## 6. Data artifacts per issue

```mermaid
flowchart LR
  subgraph outputs [Artifacts]
    PEM[GCS issued PEM path]
    SM[Secret Manager private key]
    TC[Trust config allowlist entry]
    Y1[YAML backup BEFORE]
    Y2[YAML backup AFTER]
  end
  CAS[CAS signed cert] --> PEM
  Key[Generated key] --> SM
  PEM --> TC
```

---

## 7. Per-app / per-env isolation

```mermaid
flowchart TB
  subgraph dev [Environment dev]
    DTC[trust-config-appA-dev]
    DTC2[trust-config-appB-dev]
  end
  subgraph prod [Environment prod]
    PTC[trust-config-appA-prod]
  end
  Pipe[Pipeline parameters] --> DTC
  Pipe --> DTC2
  Pipe --> PTC
```

---

## 8. Allowlist vs anchor (enforcement)

```mermaid
flowchart LR
  subgraph anchor [Anchor-only mental model]
    a1[Valid chain to CA?] --> a2[Often no CRL check]
  end
  subgraph whitelist [Allowlist model]
    w1[Leaf PEM in list?] --> w2[Remove PEM equals deny]
  end
```

---

## 9. Recovery from backups

```mermaid
flowchart TD
  L[gsutil ls trustconfig app-env] --> P[Pick BEFORE or AFTER yaml]
  P --> I[gcloud trust-configs import]
  I --> V[gcloud trust-configs describe]
```

---

## 10. Operator journey (issue)

```mermaid
journey
  title Issue client certificate (happy path)
  section Intake
    Open pipeline: 5: Operator
    Enter app env CN OU days: 5: Operator
  section Gate
    BEFORE backup: 4: System
    Validation: 5: System
  section Issue
    CAS sign: 5: System
    GCS PEM: 5: System
    SM key: 5: System
  section Trust
    Allowlist add: 5: System
    Expired cleanup: 3: System
    AFTER backup: 4: System
  section Handoff
    Client uses cert: 5: Operator
```

---

## 11. Terraform layering (conceptual)

```mermaid
flowchart TB
  L4[certificate-template + lifecycle IAM]
  L3[subordinate CA]
  L2[root CA + CA pools]
  L1[CRL bucket + API enable + Private CA service identity]
  L1 --> L2 --> L3 --> L4
```

---

## 12. Failure containment

```mermaid
flowchart TD
  V[Validation fails] --> Stop1[No CAS no SM no allowlist change]
  I[Issue fails mid-flight] --> R[Restore from BEFORE yaml + runbook]
```

---

## 13. Audit artifacts per run

| Source | Examples |
|--------|-----------|
| **CI** | Azure DevOps run logs, GitHub Actions job logs, Cloud Build logs |
| **GCS** | `trustconfig/.../BEFORE-*.yaml`, `AFTER-*.yaml`, issued PEM paths |
| **GCP audit** | Cloud Audit Logs for CAS, Certificate Manager, Secret Manager |

---

Return to [README](../README.md) · [architecture.md](architecture.md) · [pipeline.md](pipeline.md) · [terraform.md](terraform.md)
