#!/usr/bin/env bash
# Runs the same phases as GitHub Actions: BEFORE backup → issue|revoke path → AFTER backup.
# Intended for Cloud Build: set env vars via substitutions (see cloudbuild/cert-lifecycle.yaml).
set -euo pipefail

: "${ACTION:?}"
: "${TEST_MODE:?}"
: "${WORKLOAD_PROJECT_ID:?}"
: "${WORKLOAD_APP:?}"
: "${WORKLOAD_ENV:?}"
: "${STORAGE_BUCKET:?}"
: "${PKI_PROJECT_ID:?}"
: "${PKI_REGION:?}"
: "${CA_POOL_ID:?}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"
export CAS_STATE_DIR="${CAS_STATE_DIR:-${ROOT}}"

if [[ "${TEST_MODE}" == "true" ]] || [[ "${TEST_MODE}" == "True" ]]; then
  export TEST_MODE=true
else
  export TEST_MODE=false
fi

if [[ "${TRUST_CONFIG_NAME:-}" == "__default__" ]] || [[ "${TRUST_CONFIG_NAME:-}" == "-" ]]; then
  unset TRUST_CONFIG_NAME
fi
export TRUST_CONFIG_NAME="${TRUST_CONFIG_NAME:-}"

run_backup_before() {
  export WORKLOAD_PROJECT_ID WORKLOAD_APP WORKLOAD_ENV STORAGE_BUCKET PHASE=before TEST_MODE
  export TRUST_CONFIG_NAME
  chmod +x scripts/trust-config-backup.sh
  scripts/trust-config-backup.sh
}

run_backup_after() {
  chmod +x scripts/trust-config-backup.sh
  export WORKLOAD_PROJECT_ID WORKLOAD_APP WORKLOAD_ENV STORAGE_BUCKET PHASE=after TEST_MODE
  export TRUST_CONFIG_NAME
  scripts/trust-config-backup.sh
}

MAIN_OK=false

case "${ACTION}" in
  issue)
    export PKI_PROJECT_ID PKI_REGION CA_POOL_ID CA_ID CERT_TEMPLATE
    export COMMON_NAME ORGANIZATIONAL_UNIT VALIDITY_DAYS STORAGE_BUCKET
    export WORKLOAD_APP WORKLOAD_ENV WORKLOAD_PROJECT_ID
    : "${COMMON_NAME:?}"
    : "${ORGANIZATIONAL_UNIT:?}"
    : "${VALIDITY_DAYS:?}"
    : "${CA_ID:?}"
    : "${CERT_TEMPLATE:?}"
    : "${ALLOWED_APPS:?}"
    : "${MIN_VALIDITY_DAYS:?}"
    : "${MAX_VALIDITY_DAYS:?}"
    : "${MAX_VALIDITY_DAYS_PROD:?}"
    : "${MAINT_WINDOW_START_MONTH:?}"
    : "${MAINT_WINDOW_END_MONTH:?}"
    : "${MAINT_WINDOW_END_DAY:?}"
    export STRICT_VALIDITY_ENVS="${STRICT_VALIDITY_ENVS:-prod}"

    run_backup_before

    chmod +x scripts/validate-cert-request.sh
    scripts/validate-cert-request.sh

    python3 -m pip install -q -r scripts/requirements.txt
    chmod +x scripts/issue-cert.sh
    scripts/issue-cert.sh

    if [[ "${TEST_MODE}" != "true" ]]; then
      CERT_ID="$(cat "${CAS_STATE_DIR}/.cas-lifecycle-cert-id")"
      PEM_LOCAL="$(mktemp)"
      trap 'rm -f "${PEM_LOCAL}"' EXIT
      gsutil cp "gs://${STORAGE_BUCKET}/certificates/${WORKLOAD_APP}/${WORKLOAD_ENV}/${CERT_ID}.pem" "${PEM_LOCAL}"
      TC_NAME="${TRUST_CONFIG_NAME:-trust-config-${WORKLOAD_APP}-${WORKLOAD_ENV}}"
      python3 scripts/trust_config_allowlist.py add \
        --workload-project "${WORKLOAD_PROJECT_ID}" \
        --trust-config "${TC_NAME}" \
        --pem-file "${PEM_LOCAL}"
      python3 scripts/trust_config_allowlist.py cleanup-expired \
        --workload-project "${WORKLOAD_PROJECT_ID}" \
        --trust-config "${TC_NAME}"
    fi
    MAIN_OK=true
    ;;
  revoke)
    : "${CERTIFICATE_ID:?}"
    export PKI_PROJECT_ID PKI_REGION CA_POOL_ID CERTIFICATE_ID STORAGE_BUCKET
    export WORKLOAD_APP WORKLOAD_ENV WORKLOAD_PROJECT_ID

    run_backup_before

    python3 -m pip install -q -r scripts/requirements.txt
    chmod +x scripts/revoke-cert.sh
    scripts/revoke-cert.sh
    MAIN_OK=true
    ;;
  *)
    echo "ACTION must be issue or revoke (got '${ACTION}')" >&2
    exit 2
    ;;
esac

if [[ "${MAIN_OK}" == true ]]; then
  run_backup_after
fi

echo "Cloud Build lifecycle finished (action=${ACTION})."
