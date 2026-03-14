#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
PID_FILE="${SCRIPT_DIR}/alexa.pid"
LOG_FILE="${SCRIPT_DIR}/alexa.log"

if [[ ! -f "${PID_FILE}" ]]; then
  echo "No PID file found. Nothing to stop."
  exit 0
fi

PID="$(cat "${PID_FILE}" 2>/dev/null || true)"
if [[ -z "${PID}" ]]; then
  rm -f "${PID_FILE}"
  echo "PID file was empty. Removed."
  exit 0
fi

if kill -0 "${PID}" 2>/dev/null; then
  echo "{\"level\": \"INFO\", \"logger\": \"job_monitor.stop\", \"message\": \"stop_requested\", \"pid\": ${PID}}" >> "${LOG_FILE}" 2>/dev/null || true
  kill "${PID}" || true
  for _ in {1..50}; do
    if ! kill -0 "${PID}" 2>/dev/null; then
      break
    fi
    sleep 0.2
  done

  if kill -0 "${PID}" 2>/dev/null; then
    kill -9 "${PID}" || true
    echo "{\"level\": \"WARNING\", \"logger\": \"job_monitor.stop\", \"message\": \"stop_forced\", \"pid\": ${PID}}" >> "${LOG_FILE}" 2>/dev/null || true
  else
    echo "{\"level\": \"INFO\", \"logger\": \"job_monitor.stop\", \"message\": \"stop_graceful\", \"pid\": ${PID}}" >> "${LOG_FILE}" 2>/dev/null || true
  fi

  echo "Stopped Alexa backend (PID ${PID})."
else
  echo "Process ${PID} not running."
fi

rm -f "${PID_FILE}"
