"""Alexa Proactive Events integration with token caching and automatic refresh."""

from __future__ import annotations

import json
import logging
import os
import threading
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional

import requests

logger = logging.getLogger("job_monitor.proactive")

_config_lock = threading.RLock()
_token_lock = threading.RLock()

_cached_config: Optional[Dict[str, Any]] = None
_token_cache: Dict[str, Any] = {"access_token": None, "expires_at": 0.0}

REQUIRED_CONFIG_KEYS = [
    "client_id",
    "client_secret",
    "refresh_token",
    "alexa_api_endpoint",
    "skill_id",
]


def _python_dir() -> str:
    return os.path.dirname(os.path.abspath(__file__))


def load_config() -> Optional[Dict[str, Any]]:
    global _cached_config
    with _config_lock:
        if _cached_config is not None:
            return _cached_config

        cfg: Dict[str, Any] = {}
        config_path = os.path.join(_python_dir(), "config.json")
        if os.path.exists(config_path):
            try:
                with open(config_path, "r", encoding="utf-8") as handle:
                    cfg = json.load(handle)
            except Exception:
                logger.exception("config_load_failed", extra={"path": config_path})
                return None

        for key in REQUIRED_CONFIG_KEYS:
            if not cfg.get(key):
                env_key = f"ALEXA_{key.upper()}"
                cfg[key] = os.environ.get(env_key, cfg.get(key, ""))

        missing = [k for k in REQUIRED_CONFIG_KEYS if not str(cfg.get(k, "")).strip()]
        if missing:
            logger.warning("config_incomplete", extra={"missing_keys": missing})
            return None

        cfg["proactive_stage"] = str(cfg.get("proactive_stage", "development")).strip() or "development"
        cfg["request_timeout_seconds"] = float(cfg.get("request_timeout_seconds", 10.0) or 10.0)

        _cached_config = cfg
        return _cached_config


def _refresh_access_token(cfg: Dict[str, Any]) -> Optional[str]:
    token_url = "https://api.amazon.com/auth/o2/token"
    timeout = float(cfg.get("request_timeout_seconds", 10.0))

    try:
        response = requests.post(
            token_url,
            data={
                "grant_type": "refresh_token",
                "refresh_token": cfg["refresh_token"],
                "client_id": cfg["client_id"],
                "client_secret": cfg["client_secret"],
            },
            timeout=timeout,
        )
        response.raise_for_status()
        data = response.json()
    except Exception:
        logger.exception("token_refresh_failed")
        return None

    token = str(data.get("access_token", "")).strip()
    expires_in = int(data.get("expires_in", 3600) or 3600)
    if not token:
        logger.error("token_refresh_invalid_response", extra={"payload": data})
        return None

    _token_cache["access_token"] = token
    _token_cache["expires_at"] = time.time() + max(60, expires_in - 60)
    return token


def _get_access_token(cfg: Dict[str, Any]) -> Optional[str]:
    with _token_lock:
        token = _token_cache.get("access_token")
        exp = float(_token_cache.get("expires_at", 0.0) or 0.0)
        if token and time.time() < exp:
            return str(token)
        return _refresh_access_token(cfg)


def _build_payload(open_jobs: int) -> Dict[str, Any]:
    now = datetime.now(timezone.utc)
    expiry = now + timedelta(hours=1)
    return {
        "timestamp": now.isoformat(),
        "referenceId": str(uuid.uuid4()),
        "expiryTime": expiry.isoformat(),
        "event": {
            "name": "AMAZON.MessageAlert.Activated",
            "payload": {
                "state": {"status": "UNREAD"},
                "messageGroup": {"creator": {"name": "Job Monitor"}, "count": 1},
                "message": {
                    "title": "Job Monitor",
                    "text": f"Es gibt jetzt {int(open_jobs)} offene Jobs.",
                },
            },
        },
        "relevantAudience": {"type": "Multicast", "payload": {}},
    }


def send_proactive_job_update(open_jobs: int):
    cfg = load_config()
    if not cfg:
        logger.warning("proactive_skipped_missing_config")
        return

    token = _get_access_token(cfg)
    if not token:
        logger.error("proactive_skipped_missing_token")
        return

    endpoint = str(cfg["alexa_api_endpoint"]).rstrip("/")
    stage = str(cfg.get("proactive_stage", "development")).strip() or "development"
    url = f"{endpoint}/v1/proactiveEvents/stages/{stage}"

    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    payload = _build_payload(open_jobs)
    timeout = float(cfg.get("request_timeout_seconds", 10.0))

    try:
        response = requests.post(url, json=payload, headers=headers, timeout=timeout)
        if response.status_code == 401:
            with _token_lock:
                _token_cache["access_token"] = None
                _token_cache["expires_at"] = 0.0
            token = _get_access_token(cfg)
            if not token:
                logger.error("proactive_retry_failed_no_token")
                return
            headers["Authorization"] = f"Bearer {token}"
            response = requests.post(url, json=payload, headers=headers, timeout=timeout)

        response.raise_for_status()
        logger.info("proactive_send_ok", extra={"status_code": response.status_code, "open_jobs": int(open_jobs)})
    except Exception:
        logger.exception("proactive_send_failed", extra={"open_jobs": int(open_jobs)})
