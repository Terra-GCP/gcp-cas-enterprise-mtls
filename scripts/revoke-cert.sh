#!/usr/bin/env bash
set -euo pipefail

# Revocation aligned with allowlist-style mTLS: remove PEM from TrustConfig, delete artifacts,
# drop Secret Manager key material, then record revocation in CAS. Order is intentional.

: "${PKI_PROJECT_ID:?}"
: "${PKI_REGION:?}"
: "${CA_POOL_ID:?}"
: "${CERTIFICATE_ID:?}"
: "${STORAGE_BUCKET:?}"
: "${WORKLOAD_APP:?}"
: "${WORKLOAD_ENV:?}"
: "${WORKLOAD_PROJECT_ID:?}"
: "${TEST_MODE:?}"

TRUST_CONFIG_NAME="${TRUST_CONFIG_NAME:-trust-config-${WORKLOAD_APP}-${WORKLOAD_ENV}}"

PEM_OBJ="certificates/${WORKLOAD_APP}/${WORKLOAD_ENV}/${CERTIFICATE_ID}.pem"
MTLS_KEY_SECRET_ID="${MTLS_KEY_SECRET_ID:-mtls-key-${WORKLOAD_APP}-${WORKLOAD_ENV}-${CERTIFICATE_ID}}"
ROOT_DIR="${GITHUB_WORKSPACE:-${BUILD_SOURCESDIRECTORY:-.}}"
PY="${ROOT_DIR}/scripts/trust_config_allowlist.py"

echo "Revoke cert id: ${CERTIFICATE_ID}"
echo "Trust config:   ${TRUST_CONFIG_NAME} (project ${WORKLOAD_PROJECT_ID})"
echo "GCS object:     gs://${STORAGE_BUCKET}/${PEM_OBJ}"
echo "Secret id:      ${MTLS_KEY_SECRET_ID}"

if [[ "${TEST_MODE}" == "true" ]]; then
  echo "TEST_MODE=true: skip allowlist, gsutil, secrets, privateca revoke, cleanup"
  exit 0
fi

PEM_LOCAL="$(mktemp)"
trap 'rm -f "${PEM_LOCAL}"' EXIT

if gsutil cp "gs://${STORAGE_BUCKET}/${PEM_OBJ}" "${PEM_LOCAL}" 2>/dev/null; then
  python3 "${PY}" remove \
    --workload-project "${WORKLOAD_PROJECT_ID}" \
    --trust-config "${TRUST_CONFIG_NAME}" \
    --pem-file "${PEM_LOCAL}"
else
  echo "Warning: certificate PEM not found in GCS; allowlist removal skipped (restore from backup if needed)." >&2
fi

gsutil rm "gs://${STORAGE_BUCKET}/${PEM_OBJ}" 2>/dev/null || true

if gcloud secrets describe "${MTLS_KEY_SECRET_ID}" --project="${PKI_PROJECT_ID}" &>/dev/null; then
  gcloud secrets delete "${MTLS_KEY_SECRET_ID}" \
    --project="${PKI_PROJECT_ID}" \
    --quiet || true
fi

gcloud privateca certificates revoke "${CERTIFICATE_ID}" \
  --project="${PKI_PROJECT_ID}" \
  --location="${PKI_REGION}" \
  --issuer-pool="${CA_POOL_ID}" \
  --quiet || true

python3 "${PY}" cleanup-expired \
  --workload-project "${WORKLOAD_PROJECT_ID}" \
  --trust-config "${TRUST_CONFIG_NAME}"

echo "Revocation flow complete."
