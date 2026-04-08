# Setup and use — GCP CAS Enterprise Client mTLS Lifecycle

This solution provisions **Certificate Authority Service (CAS)** resources and automates **validate → issue → revoke** with **Certificate Manager allowlists**, backups, and cleanup.

---

## Prerequisites

| Requirement | Notes |
|-------------|--------|
| **Google Cloud** | Billing enabled; IAM to create CAS, buckets, secrets, Certificate Manager. |
| **Terraform** | ~1.5+ recommended; remote state and locking per your standards. |
| **`gcloud`** | For manual tests and Cloud Build; pipeline images use `google/cloud-sdk`. |
| **Python 3 + PyYAML** | For `scripts/trust_config_allowlist.py` (`scripts/requirements.txt`). |
| **Linux / GNU tools** | Validation uses GNU `date` in **`scripts/validate-cert-request.sh`**. |

---

## Setup — Terraform (PKI foundation)

1. **Copy variables file**

   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit `terraform.tfvars`**

   - Set **`crl_bucket_name`** (globally unique).
   - Set **`trust_config_admin_folder_ids`** (or grant Certificate Manager admin separately per your org).
   - Adjust region, pool/CA names, and labels as needed.

3. **Initialize and apply**

   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Record outputs** used by pipelines (pool/Ca names, template id, bucket, service account emails) — see [terraform.md](terraform.md) and root **README** for mapping.

5. **Secrets for CI**

   - **GitHub / ADO:** base64 **JSON key** for the lifecycle service account as **`GCP_SA_KEY`** (or use **Workload Identity Federation** instead).
   - **Cloud Build:** use a dedicated service account with the same IAM as in Terraform outputs.

---

## Use — validation locally

Run **`scripts/validate-cert-request.sh`** from the repo root with the same **environment variables** your pipelines export for the validate stage (see **`cloudbuild/cert-lifecycle.yaml`** and workflow inputs for names). This matches the **first gate** before any issue path touches CAS.

Example (adjust values to your naming rules):

```bash
cd scripts
export WORKLOAD_ENV=dev WORKLOAD_APP=sample-app \
  COMMON_NAME=api-dev.example.internal ORGANIZATIONAL_UNIT=dev-sample-app \
  VALIDITY_DAYS=400 MIN_VALIDITY_DAYS=365 MAX_VALIDITY_DAYS=730 MAX_VALIDITY_DAYS_PROD=548 \
  MAINT_WINDOW_START_MONTH=11 MAINT_WINDOW_END_MONTH=1 MAINT_WINDOW_END_DAY=7 \
  ALLOWED_APPS=sample-app,sample-service STRICT_VALIDITY_ENVS=prod
chmod +x validate-cert-request.sh
./validate-cert-request.sh
```

---

## Use — GitHub Actions

1. Store **`GCP_SA_KEY`** (or configure OIDC/WIF) in repo secrets.
2. Open **Actions** → **GCP CAS Enterprise mTLS lifecycle** (`cert-lifecycle.yaml`).
3. Choose **operation** (e.g. issue / revoke), set parameters (app, env, CN, OU, validity, trust config name, test mode).
4. Caller should reference **`cert-lifecycle-reusable.yaml`** for consistency.

Details: [pipeline.md](pipeline.md).

---

## Use — Azure DevOps

1. Import **`cicd/cas-cert-workflow.yaml`** as the entry pipeline and **`cicd/templates/cas-cert-lifecycle.yaml`** as the template.
2. Create variable group or pipeline variables: **`GCP_SA_KEY`**, project/region, pool/CA names from Terraform outputs, bucket names, trust config naming.
3. Run with **test mode** until sandbox paths succeed.

---

## Use — Cloud Build

```bash
gcloud builds submit --config=cloudbuild/cert-lifecycle.yaml \
  --substitutions=_OPERATION=issue,_WORKLOAD_APP=..., ...
```

Substitutions must match **`cloudbuild/cert-lifecycle.yaml`**. Service account for the build needs CAS signing, GCS, Secret Manager, and trust config update permissions as defined in Terraform.

---

## Operational checklist

- **Before production:** Review [trust-config.md](trust-config.md) (anchor vs allowlist), [allowlist-lifecycle.md](allowlist-lifecycle.md), retention, backup paths under **`trustconfig/`**, and monitoring for out-of-band trust changes.

Return to [README](../README.md)
