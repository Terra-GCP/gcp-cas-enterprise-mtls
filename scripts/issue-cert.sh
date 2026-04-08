#!/usr/bin/env bash
set -euo pipefail

# Issues a client certificate from the subordinate CA. Requires openssl, gcloud, gsutil.
# Optionally stores the private key in Secret Manager (same pattern as LB allowlist + SM guidance).

: "${PKI_PROJECT_ID:?}"
: "${PKI_REGION:?}"
: "${CA_POOL_ID:?}"
: "${CA_ID:?}"
: "${CERT_TEMPLATE:?}"
: "${COMMON_NAME:?}"
: "${ORGANIZATIONAL_UNIT:?}"
: "${VALIDITY_DAYS:?}"
: "${STORAGE_BUCKET:?}"
: "${WORKLOAD_APP:?}"
: "${WORKLOAD_ENV:?}"
: "${TEST_MODE:?}"

STATE_DIR="${CAS_STATE_DIR:-${GITHUB_WORKSPACE:-${BUILD_SOURCESDIRECTORY:-.}}}"
STORE_PRIVATE_KEY_IN_SECRET_MANAGER="${STORE_PRIVATE_KEY_IN_SECRET_MANAGER:-true}"

CERT_ID="cert-${WORKLOAD_APP}-${WORKLOAD_ENV}-$(date -u +%Y%m%d%H%M%S)"
PEM_OBJ="certificates/${WORKLOAD_APP}/${WORKLOAD_ENV}/${CERT_ID}.pem"
MTLS_KEY_SECRET_ID="${MTLS_KEY_SECRET_ID:-mtls-key-${WORKLOAD_APP}-${WORKLOAD_ENV}-${CERT_ID}}"

emit_cert_id_output() {
  local id="$1"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf 'certId=%s\n' "${id}" >>"${GITHUB_OUTPUT}"
  fi
  echo "##vso[task.setvariable variable=certId;isOutput=true]${id}"
}

echo "Certificate id: ${CERT_ID}"
echo "Upload path:    gs://${STORAGE_BUCKET}/${PEM_OBJ}"
echo "Secret id (key): ${MTLS_KEY_SECRET_ID} (project ${PKI_PROJECT_ID})"

if [[ "${TEST_MODE}" == "true" ]]; then
  echo "TEST_MODE=true: skip keygen, CSR, privateca create, SM, state file"
  emit_cert_id_output "${CERT_ID}"
  exit 0
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

openssl genrsa -out "${WORKDIR}/private.key" 2048
openssl req -new \
  -key "${WORKDIR}/private.key" \
  -out "${WORKDIR}/request.csr" \
  -subj "/CN=${COMMON_NAME}/OU=${ORGANIZATIONAL_UNIT}/O=Workload"

gcloud privateca certificates create "${CERT_ID}" \
  --project="${PKI_PROJECT_ID}" \
  --issuer="${CA_ID}" \
  --issuer-pool="${CA_POOL_ID}" \
  --location="${PKI_REGION}" \
  --csr="${WORKDIR}/request.csr" \
  --certificate-template="${CERT_TEMPLATE}" \
  --validity="${VALIDITY_DAYS}d" \
  --cert-output-file="${WORKDIR}/cert.pem"

gsutil cp "${WORKDIR}/cert.pem" "gs://${STORAGE_BUCKET}/${PEM_OBJ}"

if [[ "${STORE_PRIVATE_KEY_IN_SECRET_MANAGER}" == "true" ]]; then
  if ! gcloud secrets describe "${MTLS_KEY_SECRET_ID}" --project="${PKI_PROJECT_ID}" &>/dev/null; then
    gcloud secrets create "${MTLS_KEY_SECRET_ID}" \
      --project="${PKI_PROJECT_ID}" \
      --replication-policy=automatic
  fi
  gcloud secrets versions add "${MTLS_KEY_SECRET_ID}" \
    --project="${PKI_PROJECT_ID}" \
    --data-file="${WORKDIR}/private.key"
  echo "Private key stored in Secret Manager."
else
  echo "Private key not sent to Secret Manager (STORE_PRIVATE_KEY_IN_SECRET_MANAGER=false). Handle out-of-band."
fi

printf '%s\n' "${CERT_ID}" >"${STATE_DIR}/.cas-lifecycle-cert-id"
printf '%s\n' "${MTLS_KEY_SECRET_ID}" >"${STATE_DIR}/.cas-lifecycle-secret-id"
emit_cert_id_output "${CERT_ID}"
echo "Issuance complete; activate allowlist in pipeline next step."
