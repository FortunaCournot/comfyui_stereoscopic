"""Flask + ASK SDK backend for Alexa Custom Skill 'job monitor'."""

from __future__ import annotations

import json
import logging
import os
import sys
import atexit
import signal
import re
import threading
from typing import Any, Dict

from ask_sdk_core.dispatch_components import AbstractRequestHandler
from ask_sdk_core.handler_input import HandlerInput
from ask_sdk_core.skill_builder import CustomSkillBuilder
from ask_sdk_model import Response
from ask_sdk_model.ui import SimpleCard
from ask_sdk_webservice_support.webservice_handler import WebserviceSkillHandler
from flask import Flask, jsonify, request

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
ACCESS_LOG_FILE = os.path.abspath(os.path.join(CURRENT_DIR, "../script/access.log"))
if CURRENT_DIR not in sys.path:
    sys.path.insert(0, CURRENT_DIR)

from job_store import decrement_jobs, get_open_jobs, increment_jobs, set_open_jobs
from proactive_events import send_proactive_job_update


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

class JsonFormatter(logging.Formatter):
    """Simple JSON log formatter for structured logging."""

    def format(self, record: logging.LogRecord) -> str:
        payload: Dict[str, Any] = {
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        for key, value in record.__dict__.items():
            if key.startswith("_"):
                continue
            if key in {
                "name", "msg", "args", "levelname", "levelno", "pathname", "filename",
                "module", "exc_info", "exc_text", "stack_info", "lineno", "funcName",
                "created", "msecs", "relativeCreated", "thread", "threadName", "processName",
                "process", "message", "asctime", "taskName",
            }:
                continue
            payload[key] = value
        return json.dumps(payload, ensure_ascii=False)


def setup_logging() -> None:
    root = logging.getLogger()
    root.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

    # Avoid duplicate handlers when reloaded.
    if root.handlers:
        root.handlers.clear()


    # Schreibe alle Log-Ausgaben in eine eigene Logdatei mit UTF-8-Encoding
    stream_logfile = os.path.abspath(os.path.join(CURRENT_DIR, "../script/alexa_stdout.log"))
    stream_handler = logging.FileHandler(stream_logfile, encoding="utf-8")
    stream_handler.setFormatter(JsonFormatter())
    root.addHandler(stream_handler)

    os.makedirs(os.path.dirname(ACCESS_LOG_FILE), exist_ok=True)
    werkzeug_logger = logging.getLogger("werkzeug")
    werkzeug_logger.handlers.clear()
    werkzeug_logger.propagate = False
    werkzeug_logger.setLevel(logging.INFO)

    access_handler = logging.FileHandler(ACCESS_LOG_FILE, encoding="utf-8")
    access_handler.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
    werkzeug_logger.addHandler(access_handler)


setup_logging()
logger = logging.getLogger("job_monitor.app")

_shutdown_lock = threading.Lock()
_shutdown_logged = False
_shutdown_reason = "atexit"

DAEMONSTATUS_FILE = os.path.abspath(
    os.path.join(CURRENT_DIR, "../../../../user/default/comfyui_stereoscopic/.daemonstatus")
)
DAEMONSTATUS_INTERVAL_SECONDS = 1.0
DAEMONSTATUS_PROGRESS_RE = re.compile(r"^\D*(\d+)\s+of\s+(\d+)\s*:")

_daemonstatus_stop_event = threading.Event()
_daemonstatus_thread: threading.Thread | None = None


def _log_shutdown_once(reason: str, signum: int | None = None):
    global _shutdown_logged
    with _shutdown_lock:
        if _shutdown_logged:
            return
        _shutdown_logged = True

    extra = {"reason": reason}
    if signum is not None:
        try:
            extra["signal"] = signal.Signals(signum).name
        except Exception:
            extra["signal"] = int(signum)
    logger.info("server_shutdown", extra=extra)


def _handle_shutdown_signal(signum, frame):
    global _shutdown_reason
    try:
        _shutdown_reason = f"signal:{signal.Signals(signum).name}"
    except Exception:
        _shutdown_reason = f"signal:{int(signum)}"
    raise SystemExit(0)


def _on_process_exit():
    _daemonstatus_stop_event.set()
    if _daemonstatus_thread and _daemonstatus_thread.is_alive():
        _daemonstatus_thread.join(timeout=1.5)

    reason = _shutdown_reason
    signum = None
    if isinstance(reason, str) and reason.startswith("signal:"):
        sig_name = reason.split(":", 1)[1]
        try:
            signum = int(getattr(signal.Signals, sig_name).value)
        except Exception:
            signum = None
        _log_shutdown_once(reason="signal", signum=signum)
    else:
        _log_shutdown_once(reason="atexit")


# ---------------------------------------------------------------------------
# Alexa Skill Handlers
# ---------------------------------------------------------------------------

class LaunchRequestHandler(AbstractRequestHandler):
    def can_handle(self, handler_input: HandlerInput) -> bool:
        return handler_input.request_envelope.request.object_type == "LaunchRequest"

    def handle(self, handler_input: HandlerInput) -> Response:
        speak_output = "Job Monitor ist bereit."
        return (
            handler_input.response_builder
            .speak(speak_output)
            .set_card(SimpleCard("Job Monitor", speak_output))
            .set_should_end_session(False)
            .response
        )


class GetOpenJobsIntentHandler(AbstractRequestHandler):
    def can_handle(self, handler_input: HandlerInput) -> bool:
        request_obj = handler_input.request_envelope.request
        return (
            request_obj.object_type == "IntentRequest"
            and request_obj.intent
            and request_obj.intent.name == "GetOpenJobsIntent"
        )

    def handle(self, handler_input: HandlerInput) -> Response:
        count = get_open_jobs()
        speak_output = f"Aktuell gibt es {count} offene Jobs."
        return (
            handler_input.response_builder
            .speak(speak_output)
            .set_card(SimpleCard("Offene Jobs", speak_output))
            .set_should_end_session(True)
            .response
        )


class FallbackIntentHandler(AbstractRequestHandler):
    def can_handle(self, handler_input: HandlerInput) -> bool:
        request_obj = handler_input.request_envelope.request
        return (
            request_obj.object_type == "IntentRequest"
            and request_obj.intent
            and request_obj.intent.name == "AMAZON.FallbackIntent"
        )

    def handle(self, handler_input: HandlerInput) -> Response:
        speak_output = "I did not understand that. For example, you can ask: How many open jobs are there?"
        return (
            handler_input.response_builder
            .speak(speak_output)
            .set_card(SimpleCard("Help", speak_output))
            .set_should_end_session(False)
            .response
        )


class CatchAllExceptionHandler(AbstractRequestHandler):
    def can_handle(self, handler_input: HandlerInput) -> bool:  # pragma: no cover
        return False


sb = CustomSkillBuilder()
sb.add_request_handler(LaunchRequestHandler())
sb.add_request_handler(GetOpenJobsIntentHandler())
sb.add_request_handler(FallbackIntentHandler())

skill_webservice_handler = WebserviceSkillHandler(skill=sb.create())


# ---------------------------------------------------------------------------
# Flask App
# ---------------------------------------------------------------------------

app = Flask(__name__)


def _parse_value(payload: Dict[str, Any], default: int = 1) -> int:
    value = payload.get("value", default)
    return int(value)


def _trigger_proactive_update() -> None:
    open_jobs = get_open_jobs()
    send_proactive_job_update(open_jobs)


def _read_daemonstatus_count() -> int:
    try:
        with open(DAEMONSTATUS_FILE, "r", encoding="utf-8", errors="replace") as status_file:
            lines = status_file.read().splitlines()
        if len(lines) < 2:
            return 0

        second_line = lines[1].strip()
        match = DAEMONSTATUS_PROGRESS_RE.match(second_line)
        if not match:
            return 0
        first_value = int(match.group(1))
        second_value = int(match.group(2))
        return max(0, second_value - first_value + 1)
    except Exception:
        return 0


def _daemonstatus_poll_loop() -> None:
    while not _daemonstatus_stop_event.is_set():
        count = _read_daemonstatus_count()
        if count != get_open_jobs():
            set_open_jobs(count)
        _daemonstatus_stop_event.wait(DAEMONSTATUS_INTERVAL_SECONDS)


def _start_daemonstatus_polling() -> None:
    global _daemonstatus_thread
    _daemonstatus_thread = threading.Thread(
        target=_daemonstatus_poll_loop,
        name="daemonstatus-poller",
        daemon=True,
    )
    _daemonstatus_thread.start()


@app.route("/jobs", methods=["GET"])
def get_jobs():
    return jsonify({"open_jobs": get_open_jobs()})


@app.route("/jobs/set", methods=["POST"])
def set_jobs():
    payload = request.get_json(silent=True) or {}
    value = _parse_value(payload, default=0)
    set_open_jobs(value)
    _trigger_proactive_update()
    logger.info("rest_jobs_set", extra={"open_jobs": get_open_jobs()})
    return jsonify({"open_jobs": get_open_jobs()})


@app.route("/jobs/inc", methods=["POST"])
def inc_jobs():
    payload = request.get_json(silent=True) or {}
    delta = _parse_value(payload, default=1)
    increment_jobs(delta)
    _trigger_proactive_update()
    logger.info("rest_jobs_inc", extra={"delta": delta, "open_jobs": get_open_jobs()})
    return jsonify({"open_jobs": get_open_jobs()})


@app.route("/jobs/dec", methods=["POST"])
def dec_jobs():
    payload = request.get_json(silent=True) or {}
    delta = _parse_value(payload, default=1)
    decrement_jobs(delta)
    _trigger_proactive_update()
    logger.info("rest_jobs_dec", extra={"delta": delta, "open_jobs": get_open_jobs()})
    return jsonify({"open_jobs": get_open_jobs()})


@app.route("/alexa", methods=["POST"])
def alexa_webhook():
    try:
        body = request.get_json(silent=True) or {}
        req_type = body.get("request", {}).get("type", "unknown")
        intent_name = body.get("request", {}).get("intent", {}).get("name")
        logger.info("alexa_request_in", extra={"request_type": req_type, "intent": intent_name})
    except Exception:
        logger.exception("alexa_request_log_failed")

    return skill_webservice_handler.verify_request_and_dispatch(request.data, request.headers)


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "open_jobs": get_open_jobs()})


if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "5000"))

    atexit.register(_on_process_exit)
    try:
        signal.signal(signal.SIGTERM, _handle_shutdown_signal)
        signal.signal(signal.SIGINT, _handle_shutdown_signal)
    except Exception:
        pass

    _start_daemonstatus_polling()
    logger.info("server_start", extra={"host": host, "port": port})
    app.run(host=host, port=port, threaded=True)
