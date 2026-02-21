#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
PYTHON_EXE="$(realpath "${SCRIPT_DIR}/../../../../../python_embeded/python.exe")"
PID_FILE="${SCRIPT_DIR}/alexa.pid"
LOG_FILE="${SCRIPT_DIR}/alexa.log"
ACCESS_LOG_FILE="${SCRIPT_DIR}/access.log"
ACCESS_LOG_MAX_LINES="10000"

if [[ -f "${PID_FILE}" ]]; then
  OLD_PID="$(cat "${PID_FILE}" 2>/dev/null || true)"
  if [[ -n "${OLD_PID}" ]] && kill -0 "${OLD_PID}" 2>/dev/null; then
    echo "Alexa backend already running with PID ${OLD_PID}."
    exit 0
  else
    rm -f "${PID_FILE}"
  fi
fi

cd "${SCRIPT_DIR}/../python"

if [[ ! -x "${PYTHON_EXE}" ]]; then
  echo "Assigned Python not found or not executable: ${PYTHON_EXE}"
  exit 1
fi

# Always start with a clean log file so only current-run messages are visible.
: > "${LOG_FILE}"

# Keep access.log between runs, but cap it to the newest 10,000 lines.
if [[ -f "${ACCESS_LOG_FILE}" ]]; then
  TMP_ACCESS_LOG="${ACCESS_LOG_FILE}.tmp"
  tail -n "${ACCESS_LOG_MAX_LINES}" "${ACCESS_LOG_FILE}" > "${TMP_ACCESS_LOG}" || true
  mv -f "${TMP_ACCESS_LOG}" "${ACCESS_LOG_FILE}" || true
fi

nohup "${PYTHON_EXE}" app.py >> "${LOG_FILE}" 2>&1 &
NEW_PID=$!
echo "${NEW_PID}" > "${PID_FILE}"

echo "Alexa backend started (PID ${NEW_PID})."
echo "Log: ${LOG_FILE}"
