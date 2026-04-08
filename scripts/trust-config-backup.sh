#!/usr/bin/env bash
set -euo pipefail

# Backs up Certificate Manager trust config to GCS (BEFORE/AFTER style path).

: "${WORKLOAD_PROJECT_ID:?}"
: "${WORKLOAD_APP:?}"
: "${WORKLOAD_ENV:?}"
: "${STORAGE_BUCKET:?}"
: "${PHASE:?}"
: "${TEST_MODE:?}"

TRUST_CONFIG="${TRUST_CONFIG_NAME:-trust-config-${WORKLOAD_APP}-${WORKLOAD_ENV}}"
TS=$(date -u +%Y%m%d-%H%M%S)

PHASE_NORM="$(echo "${PHASE}" | tr '[:upper:]' '[:lower:]')"
case "${PHASE_NORM}" in
  before) LABEL="BEFORE" ;;
  after) LABEL="AFTER" ;;
  *) LABEL="$(echo "${PHASE}" | tr '[:lower:]' '[:upper:]')" ;;
esac

OBJ="trustconfig/${WORKLOAD_APP}-${WORKLOAD_ENV}/${LABEL}-${TS}.yaml"

echo "Trust config: ${TRUST_CONFIG}"
echo "Destination:  gs://${STORAGE_BUCKET}/${OBJ}"

if [[ "${TEST_MODE}" == "true" ]]; then
  echo "TEST_MODE=true: skip export/upload"
  exit 0
fi

TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT

gcloud certificate-manager trust-configs export "${TRUST_CONFIG}" \
  --project="${WORKLOAD_PROJECT_ID}" \
  --location=global \
  --destination="${TMP}"

gsutil cp "${TMP}" "gs://${STORAGE_BUCKET}/${OBJ}"
echo "Backup written."