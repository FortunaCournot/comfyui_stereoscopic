import bisect
import base64
import io
import ntpath
import os
import re
import subprocess
import sys
import shutil
import struct
import tempfile
import time
import traceback
import threading
import urllib.parse, urllib.request
import webbrowser
from datetime import timedelta, datetime
from functools import wraps, partial
from hashlib import sha256
from itertools import chain
from random import randrange
from typing import List, Tuple
from urllib.error import HTTPError
from pathlib import Path
import cv2
import numpy as np
import requests
from numpy import ndarray
from PIL import Image
from PyQt5.QtCore import (QBuffer, QRect, QSize, Qt, QThread, QTimer, QPoint, QPointF,
                          pyqtSignal, pyqtSlot, QRunnable, QThreadPool, QObject, 
                          QMimeData, QUrl, QEvent, QIODevice)
from PyQt5.QtGui import (QBrush, QColor, QCursor, QFont, QIcon, QImage,
                         QKeySequence, QPainter, QPaintEvent, QPen, QPixmap,
                         QTextCursor, QDrag, QClipboard)
from PyQt5.QtWidgets import (QAbstractItemView, QAction, QApplication,
                             QColorDialog, QComboBox, QDesktopWidget, QDialog,
                             QDoubleSpinBox,
                             QFileDialog, QFrame, QGridLayout, QGroupBox,
                             QHBoxLayout, QHeaderView, QLabel, QMainWindow,
                             QMenu,
                             QMessageBox, QPushButton, QShortcut, QSizePolicy,
                             QProgressBar,
                             QSlider, QStatusBar, QTableWidget,
                             QTableWidgetItem, QToolBar, QVBoxLayout, QWidget,
                             QWidgetAction,
                             QPlainTextEdit, QLayout, QStyleOptionSlider, QStyle,
                             QRubberBand)


USE_TRASHBIN=True
if USE_TRASHBIN:
    try:
        import send2trash
    except ImportError:
        USE_TRASHBIN=False

TRACELEVEL=3

# Globale statische Liste der erlaubten Suffixe
VIDEO_EXTENSIONS = ['.mp4', '.webm', '.ts', '.flv', '.mkv']
IMAGE_EXTENSIONS = ['.png', '.webp', '.jpg', '.jpeg', '.jfif']
ALL_EXTENSIONS = VIDEO_EXTENSIONS + IMAGE_EXTENSIONS
global _readyfiles, _activeExtensions, _filterEdit, _sortOrderIndex
_readyfiles=[]
_activeExtensions=ALL_EXTENSIONS
_filterEdit=False
_sortOrderIndex=3        # 0: A-Z, 1: Z-A, 2: Time Up, 3: Time Down

# global init
global cutModeActive, cutModeFolderOverrideActive, cutModeFolderOverridePath
cutModeActive=False
cutModeFolderOverrideActive=False
cutModeFolderOverridePath=str(Path.home())

global path
path = os.path.dirname(os.path.abspath(__file__))
# Add the current directory to the path so we can import local modules
if path not in sys.path:
    sys.path.append(path)

from content_filters import BaseImageFilter, create_content_filter_instances

# File Global
global videoActive, rememberThread, fileDragged, FILESCANTIME, TASKCHECKTIME, WAIT_DIALOG_THRESHOLD_TIME
videoActive=False
videoPauseRequested=False
rememberThread=[]
fileDragged=False
FILESCANTIME = 500
TASKCHECKTIME = 20
WAIT_DIALOG_THRESHOLD_TIME=2000
MAX_WAIT_DIALOG_THRESHOLD_TIME=10000
# Small UI redraw delay to ensure image appears after load
DISPLAY_REFRESH_DELAY_MS = 75
CONTENT_FILTER_PROPERTIES_FILENAME = "content_filter.properties"
INPAINT_PROPERTIES_FILENAME = "inpaint.properties"
INPAINT_PROPERTIES_KEY_TASK = "selected_task"
INPAINT_PROPERTIES_KEY_BRUSH_SIZE = "brush_size"

# ---- Tasks ----
global taskCounterUI, taskCounterAsync, showWaitDialog
taskCounterUI=0
taskCounterAsync=0
showWaitDialog=False

# Currently selected inpaint task (persisted at runtime)
global selected_inpaint_task
selected_inpaint_task = "inpaint-sd15"
global selected_inpaint_brush_size
selected_inpaint_brush_size = 25
_logged_invalid_inpaint_tasks = set()

# Temp file cleanup list and worker
TEMP_FILES_TO_CLEANUP = []
_temp_cleanup_thread_started = False

def _temp_cleanup_worker():
    while True:
        try:
            cleanup_temps(0)
        except Exception:
            pass
        time.sleep(60)

def _ensure_temp_cleanup_thread():
    global _temp_cleanup_thread_started
    if not _temp_cleanup_thread_started:
        t = threading.Thread(target=_temp_cleanup_worker, daemon=True)
        t.start()
        _temp_cleanup_thread_started = True


def cleanup_temps(cleanup: int = 0):
    """Remove temp files from TEMP_FILES_TO_CLEANUP.

    If cleanup==1: remove immediately.
    If cleanup==0: only remove files at least 10 seconds old.
    """
    now = time.time()
    min_age = 10.0
    for p in list(TEMP_FILES_TO_CLEANUP):
        try:
            if not os.path.exists(p):
                try:
                    TEMP_FILES_TO_CLEANUP.remove(p)
                except Exception:
                    pass
                continue
            if cleanup == 1:
                try:
                    os.remove(p)
                except Exception:
                    pass
                try:
                    TEMP_FILES_TO_CLEANUP.remove(p)
                except Exception:
                    pass
            else:
                try:
                    mtime = os.path.getmtime(p)
                    if now - mtime >= min_age:
                        try:
                            os.remove(p)
                        except Exception:
                            pass
                        try:
                            TEMP_FILES_TO_CLEANUP.remove(p)
                        except Exception:
                            pass
                except Exception:
                    # can't stat or remove; ignore for now
                    pass
        except Exception:
            pass



def set_selected_inpaint_task(name: str):
    global selected_inpaint_task
    try:
        if name and isinstance(name, str):
            selected_inpaint_task = _resolve_valid_inpaint_task(name)
            _save_selected_inpaint_task(selected_inpaint_task)
    except Exception:
        pass


def set_selected_inpaint_brush_size(value: int):
    global selected_inpaint_brush_size
    try:
        size = int(value)
        size = max(1, min(200, size))
        selected_inpaint_brush_size = size
        _save_inpaint_preferences(selected_inpaint_task, selected_inpaint_brush_size)
    except Exception:
        pass


def config(key, default):
        cfgFile = os.path.join(path, "../../../../user/default/comfyui_stereoscopic/config.ini")
        try:
            if os.path.exists(cfgFile):
                with open(cfgFile) as file:
                    cfglines = [line.rstrip() for line in file]
                    for line in range(len(cfglines)):
                        inputMatch=re.match(r"^"+key+r"=", cfglines[line])
                        if inputMatch:
                            valuepart=cfglines[line][inputMatch.end():]
                            return valuepart  
            return default
        except Exception as e:
            print(traceback.format_exc(), flush=True)
            return default


def get_user_config_dir() -> str:
    return os.path.abspath(  os.path.join(path, "../../../../user/default/comfyui_stereoscopic/") )


def read_properties_file(file_path: str) -> dict:
    result = {}
    try:
        if not os.path.exists(file_path):
            return result
        with open(file_path, "r", encoding="utf-8") as handle:
            for raw_line in handle:
                line = raw_line.strip()
                if not line or line.startswith("#") or line.startswith(";"):
                    continue
                if "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip()
                if key:
                    result[key] = value
    except Exception:
        pass
    return result


def write_properties_file(file_path: str, kv: dict):
    try:
        folder = os.path.dirname(file_path)
        if folder:
            os.makedirs(folder, exist_ok=True)
        with open(file_path, "w", encoding="utf-8") as handle:
            for key in sorted(kv.keys()):
                handle.write(f"{key}={kv[key]}\n")
    except Exception:
        pass


def _get_inpaint_properties_path() -> str:
    return os.path.join(get_user_config_dir(), INPAINT_PROPERTIES_FILENAME)


def _get_inpaint_tasks_dir() -> str:
    return os.path.abspath(os.path.join(path, "../../../../input/vr/tasks"))


def _get_task_blueprint_path(task_name: str) -> str:
    task = str(task_name or "").strip()
    if not task:
        return ""
    if task.startswith("_"):
        return os.path.abspath(os.path.join(path, "../../../../user/default/comfyui_stereoscopic/tasks", f"{task[1:]}.json"))
    return os.path.abspath(os.path.join(path, "../../config/tasks", f"{task}.json"))


def _is_valid_inpaint_task(task_name: str) -> bool:
    task = str(task_name or "").strip()
    if not task or "inpaint" not in task.lower():
        return False
    task_dir = os.path.join(_get_inpaint_tasks_dir(), task)
    blueprint = _get_task_blueprint_path(task)
    return os.path.isdir(task_dir) and os.path.isfile(blueprint)


def _list_valid_inpaint_tasks() -> list:
    global _logged_invalid_inpaint_tasks
    names = []
    try:
        tasks_dir = _get_inpaint_tasks_dir()
        if not os.path.isdir(tasks_dir):
            return names
        for name in sorted(os.listdir(tasks_dir)):
            full = os.path.join(tasks_dir, name)
            if not os.path.isdir(full):
                continue
            if _is_valid_inpaint_task(name):
                names.append(name)
            elif "inpaint" in str(name).lower():
                try:
                    blueprint = _get_task_blueprint_path(name)
                    key = str(name)
                    if key not in _logged_invalid_inpaint_tasks and TRACELEVEL >= 0:
                        print(f"Error: No blueprint for task {name} at {blueprint}", flush=True)
                        _logged_invalid_inpaint_tasks.add(key)
                except Exception:
                    pass
    except Exception:
        pass
    return names


def _resolve_valid_inpaint_task(preferred_task: str = "") -> str:
    preferred = str(preferred_task or "").strip()
    valid = _list_valid_inpaint_tasks()
    if preferred and preferred in valid:
        return preferred
    default_task = "inpaint-sd15"
    if default_task in valid:
        return default_task
    if len(valid) > 0:
        return valid[0]
    return default_task


def _clamp_inpaint_brush_size(value, fallback: int = 25) -> int:
    try:
        parsed = int(value)
    except Exception:
        parsed = int(fallback)
    return max(1, min(200, parsed))


def _load_selected_inpaint_task(default_value: str = "inpaint-sd15") -> str:
    try:
        values = read_properties_file(_get_inpaint_properties_path())
        stored = str(values.get(INPAINT_PROPERTIES_KEY_TASK, "")).strip()
        if stored:
            return stored
    except Exception:
        pass
    return default_value


def _load_selected_inpaint_brush_size(default_value: int = 25) -> int:
    try:
        values = read_properties_file(_get_inpaint_properties_path())
        stored = str(values.get(INPAINT_PROPERTIES_KEY_BRUSH_SIZE, "")).strip()
        if stored:
            return _clamp_inpaint_brush_size(stored, default_value)
    except Exception:
        pass
    return _clamp_inpaint_brush_size(default_value, 25)


def _save_inpaint_preferences(task_name: str, brush_size: int):
    try:
        task_value = str(task_name).strip()
        size_value = str(_clamp_inpaint_brush_size(brush_size, 25))
        if not task_value:
            return
        file_path = _get_inpaint_properties_path()
        values = read_properties_file(file_path)
        values[INPAINT_PROPERTIES_KEY_TASK] = task_value
        values[INPAINT_PROPERTIES_KEY_BRUSH_SIZE] = size_value
        write_properties_file(file_path, values)
    except Exception:
        pass


def _repair_inpaint_preferences_if_needed(task_name: str, brush_size: int):
    """Normalize old/invalid inpaint prefs and rewrite only when changed."""
    normalized_task = _resolve_valid_inpaint_task(str(task_name).strip() or "inpaint-sd15")
    normalized_brush = _clamp_inpaint_brush_size(brush_size, 25)
    try:
        file_path = _get_inpaint_properties_path()
        values = read_properties_file(file_path)

        raw_task = str(values.get(INPAINT_PROPERTIES_KEY_TASK, "")).strip()
        raw_brush = str(values.get(INPAINT_PROPERTIES_KEY_BRUSH_SIZE, "")).strip()

        if raw_task:
            normalized_task = _resolve_valid_inpaint_task(raw_task)
        if raw_brush:
            normalized_brush = _clamp_inpaint_brush_size(raw_brush, normalized_brush)

        desired_brush_str = str(normalized_brush)
        needs_write = (raw_task != normalized_task) or (raw_brush != desired_brush_str)
        if needs_write:
            values[INPAINT_PROPERTIES_KEY_TASK] = normalized_task
            values[INPAINT_PROPERTIES_KEY_BRUSH_SIZE] = desired_brush_str
            write_properties_file(file_path, values)
            if TRACELEVEL >= 0:
                print(
                    f"Error: Inpaint prefs corrected: task='{raw_task or '<empty>'}' -> '{normalized_task}', "
                    f"brush='{raw_brush or '<empty>'}' -> '{desired_brush_str}'",
                    flush=True,
                )
    except Exception:
        pass
    return normalized_task, normalized_brush


def _save_selected_inpaint_task(task_name: str):
    try:
        value = str(task_name).strip()
        if not value:
            return
        _save_inpaint_preferences(value, selected_inpaint_brush_size)
    except Exception:
        pass


try:
    selected_inpaint_task = _load_selected_inpaint_task(selected_inpaint_task)
except Exception:
    pass

try:
    selected_inpaint_brush_size = _load_selected_inpaint_brush_size(selected_inpaint_brush_size)
except Exception:
    pass

try:
    selected_inpaint_task, selected_inpaint_brush_size = _repair_inpaint_preferences_if_needed(
        selected_inpaint_task,
        selected_inpaint_brush_size,
    )
except Exception:
    pass


def isTaskActive():
    return taskCounterUI + taskCounterAsync > 0


def safe_imread(path: str):
    """Read image robustly when path contains special characters.

    Tries cv2.imread first; if that returns None, falls back to reading
    the file bytes and decoding with cv2.imdecode which avoids some
    filename-encoding issues on Windows.
    """
    try:
        img = cv2.imread(path)
        if img is None or getattr(img, 'size', 0) == 0:
            with open(path, 'rb') as f:
                data = f.read()
            arr = np.frombuffer(data, np.uint8)
            img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        return img
    except Exception:
        try:
            with open(path, 'rb') as f:
                data = f.read()
            arr = np.frombuffer(data, np.uint8)
            return cv2.imdecode(arr, cv2.IMREAD_COLOR)
        except Exception:
            return None


def open_videocapture_with_tmp(path: str):
    """Open cv2.VideoCapture robustly for paths with special characters.

    Returns a tuple (cap, tmp_path). tmp_path is None when no temporary
    copy was created. If open fails, returns (cap, tmp_path) where cap
    may be unopened.
    """
    cap = cv2.VideoCapture(path)
    if cap.isOpened():
        return cap, None

    # Try copying to a temporary file with a safe name and reopen
    try:
        suffix = os.path.splitext(path)[1]
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
        tmp.close()
        shutil.copyfile(path, tmp.name)
        cap2 = cv2.VideoCapture(tmp.name)
        if cap2.isOpened():
            return cap2, tmp.name
        else:
            try:
                cap2.release()
            except Exception:
                pass
            os.unlink(tmp.name)
    except Exception:
        pass
    return cap, None


def open_with_default_app(fullpath: str):
    """Open the given file with the system default application.

    Uses `os.startfile` on Windows, `open` on macOS and `xdg-open` on Linux.
    """
    try:
        if not fullpath:
            return
        if TRACELEVEL >= 2:
            print(f"open_with_default_app: opening '{fullpath}'", flush=True)
        if sys.platform.startswith('win'):
            os.startfile(fullpath)
        elif sys.platform == 'darwin':
            subprocess.Popen(['open', fullpath])
        else:
            subprocess.Popen(['xdg-open', fullpath])
    except Exception:
        print(traceback.format_exc(), flush=True)

def _open_and_log(fullpath: str):
    try:
        if TRACELEVEL >= 1:
            print(f"_open_and_log: thread={threading.current_thread().name} opening {fullpath}", flush=True)
        open_with_default_app(fullpath)
        if TRACELEVEL >= 1:
            print(f"_open_and_log: done {fullpath}", flush=True)
    except Exception:
        print(traceback.format_exc(), flush=True)

def needsWaitDialog():
    global showWaitDialog
    
    if taskCounterAsync > 0:
        t=int((time.time()-taskStartAsyc)*1000)
        
        if t > WAIT_DIALOG_THRESHOLD_TIME:
            showWaitDialog=True

    return showWaitDialog

def enterUITask():
    global taskCounterUI, taskStartUI
    if taskCounterUI==0:
        taskStartUI=time.time()
    taskCounterUI+=1
    if TRACELEVEL >= 3:
        print(f". enterUITask { taskCounterUI }", flush=True)
        

def leaveUITask():
    global taskCounterUI, taskStartUI
    if TRACELEVEL >= 3:
        print(f". leaveUITask { taskCounterUI }", flush=True)
    taskCounterUI-=1
    if taskCounterUI==0:
        tb=traceback.format_stack()
        tb=tb[-2][tb[-2].rfind('\\')+1:]
        tb=tb[:tb.rfind(',')]
        if TRACELEVEL >= 2:
            print(f". UI Task executed in { int((time.time()-taskStartUI)*1000) }ms, \"" + tb, flush=True)
        
def startAsyncTask():
    global taskCounterAsync, taskStartAsyc, showWaitDialog

    if taskCounterAsync==0:
        taskStartAsyc=time.time()
        showWaitDialog=False
    taskCounterAsync+=1
    if TRACELEVEL >= 3:
        print(f". startAsyncTask { taskCounterAsync }", flush=True)

def endAsyncTask():
    global taskCounterAsync, taskStartAsyc, showWaitDialog
    if TRACELEVEL >= 3:
        print(f". endAsyncTask { taskCounterAsync }", flush=True)
    taskCounterAsync-=1
    if taskCounterAsync==0:
        showWaitDialog=False
        tb=traceback.format_stack()
        tb=tb[-2][tb[-2].rfind('\\')+1:]
        tb=tb[:tb.rfind(',')]
        if TRACELEVEL >= 2:
            print(f". Async Task executed in { int((time.time()-taskStartAsyc)*1000) }ms, \"" + tb, flush=True)

def replace_file_suffix(file_path: str, new_suffix: str) -> str:
    """
    Replace the file suffix of the given file path with a new suffix.

    :param file_path: The original file path.
    :param new_suffix: The new suffix (with or without leading dot).
    :return: The updated file path with the new suffix.
    """
    # Normalize suffix to ensure it starts with a dot
    if not new_suffix.startswith("."):
        new_suffix = "." + new_suffix

    # Split file path into root and extension
    root, _ = os.path.splitext(file_path)

    # Combine root with new suffix
    return root + new_suffix            

def print_exception_stack_with_locals(exc):
    tb = exc.__traceback__
    i = 0
    while tb is not None:
        frame = tb.tb_frame
        lineno = tb.tb_lineno
        func = frame.f_code.co_name
        filename = frame.f_code.co_filename
        # source line if available
        try:
            line = traceback.extract_tb(tb, limit=1)[0].line
        except Exception:
            line = None
        print(f"#{i} {func} @ {filename}:{lineno} -> {line}")
        # show locals at the frame where exception happened (optional, might be large)
        for name, val in frame.f_locals.items():
            print(f"      {name} = {val!r}")
        tb = tb.tb_next
        i += 1


class WaitDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent, Qt.FramelessWindowHint)
        self.setModal(True)  # <-- Blockiert den Eltern-Dialog
        layout = QHBoxLayout()
        label=QLabel("processing ...")
        self.setStyleSheet("QDialog { border: 1px solid white; }");
        label.setStyleSheet("QLabel { background-color : black; color : white; }");
        layout.setContentsMargins(0,0,0,0)
        layout.addWidget(label)
        layout.setAlignment(label, Qt.AlignHCenter | Qt.AlignVCenter )
        self.setLayout(layout)
        self.setFixedSize(130, 36)


class FilterParameterMenu(QMenu):
    def __init__(self, parent, filter_instance: BaseImageFilter, on_change_callback=None):
        super().__init__(parent)
        self.filter_instance = filter_instance
        self.on_change_callback = on_change_callback
        self._parameter_sliders: List[QSlider] = []
        self._parameter_spinboxes: List[QDoubleSpinBox] = []
        self.setToolTipsVisible(True)
        self.setStyleSheet("QMenu { background-color : black; color: white; border: 1px solid #444; }")

        try:
            parameters = list(filter_instance.get_parameters())
        except Exception:
            parameters = []

        try:
            param_meta = {n: (d, lo, hi, has_mid) for n, d, lo, hi, has_mid in filter_instance._parse_parameter_defaults()}
        except Exception:
            param_meta = {}
        if len(parameters) == 0:
            no_params_action = QAction("No parameters available for this filter.", self)
            no_params_action.setEnabled(False)
            self.addAction(no_params_action)
            return

        # Try to read persisted property values directly so the UI shows stored
        # settings even if the in-memory filter instance wasn't updated earlier.
        try:
            props = {}
            props_path = getattr(parent, '_content_filter_properties_path', None) if parent is not None else None
            if not props_path:
                props_path = os.path.join(get_user_config_dir(), CONTENT_FILTER_PROPERTIES_FILENAME)
            props = read_properties_file(props_path)
        except Exception:
            props = {}

        for param_name, param_value in parameters:
            # If a persisted value exists for this filter+param, prefer it for the UI
            try:
                filter_id = getattr(filter_instance, 'filter_id', 'none')
                key = f"{filter_id}.{param_name}"
                if key in props:
                    try:
                        param_value = float(props[key])
                    except Exception:
                        pass
            except Exception:
                pass
            row_widget = QWidget(self)
            row_widget.setStyleSheet("background-color: black;")
            row_layout = QHBoxLayout(row_widget)
            row_layout.setContentsMargins(8, 4, 8, 4)
            row_layout.setSpacing(8)

            name_label = QLabel(str(param_name), row_widget)
            name_label.setMinimumWidth(180)
            name_label.setStyleSheet("QLabel { color: white; background-color: black; }")

            slider = QSlider(Qt.Horizontal, row_widget)
            slider.setRange(0, 10000)
            slider.setSingleStep(1)
            # parameter range
            _meta = param_meta.get(param_name, (param_value, 0.0, 1.0, False))
            _def, lo, hi, has_mid = _meta
            try:
                lo = float(lo)
                hi = float(hi)
            except Exception:
                lo, hi = 0.0, 1.0
            # compute slider position corresponding to param_value
            try:
                if hi > lo:
                    slider_pos = int(round((float(param_value) - lo) / (hi - lo) * 10000.0))
                else:
                    slider_pos = 0
            except Exception:
                slider_pos = 0
            slider_pos = max(0, min(10000, slider_pos))
            slider.setValue(slider_pos)
            # tick marks: center tick for parameters with a middle value,
            # otherwise show ticks below at 10% intervals
            try:
                if has_mid:
                    slider.setTickPosition(QSlider.TicksBothSides)
                    slider.setTickInterval(5000)
                else:
                    slider.setTickPosition(QSlider.TicksBelow)
                    slider.setTickInterval(1000)
            except Exception:
                pass
            slider.setFixedWidth(220)
            slider.setStyleSheet(
                "QSlider::groove:horizontal { height: 5px; background: #5a5a5a; border-radius: 2px; }"
                "QSlider::handle:horizontal { width: 12px; margin: -4px 0; background: #d0d0d0; border: 1px solid #a0a0a0; border-radius: 6px; }"
                "QSlider::sub-page:horizontal { background: #8fb9ff; border-radius: 2px; }"
                "QSlider::groove:horizontal:disabled { background: #2a2a2a; }"
                "QSlider::handle:horizontal:disabled { background: #6a6a6a; border: 1px solid #555555; }"
                "QSlider::sub-page:horizontal:disabled { background: #4a4a4a; }"
            )

            spin = QDoubleSpinBox(row_widget)
            spin.setRange(lo, hi)
            spin.setDecimals(4)
            spin.setSingleStep(max(1e-6, (hi - lo) / 1000.0))
            try:
                spin_val = float(param_value)
            except Exception:
                spin_val = lo
            spin.setValue(self._clamp_spin_value(spin_val, lo, hi))
            spin.setFixedWidth(90)
            spin.setStyleSheet(
                "QDoubleSpinBox { color: white; background-color: black; border: 1px solid #666; padding: 2px; }"
                "QDoubleSpinBox:disabled { color: #888; border: 1px solid #444; }"
            )

            reset_btn = QPushButton("Reset", row_widget)
            reset_btn.setFixedWidth(64)
            reset_btn.setStyleSheet("QPushButton { color: white; background-color: #2a2a2a; border: 1px solid #444; padding: 2px; }")
            reset_btn.clicked.connect(partial(self._on_reset_clicked, str(param_name), slider, spin, _def, lo, hi))

            slider.valueChanged.connect(partial(self._on_slider_value_changed, spin, lo, hi))
            slider.sliderReleased.connect(partial(self._on_slider_released, str(param_name), slider, spin, lo, hi))
            spin.editingFinished.connect(partial(self._on_spinbox_edit_finished, str(param_name), slider, spin, lo, hi))

            self._parameter_sliders.append(slider)
            self._parameter_spinboxes.append(spin)
            # keep parameter names in the same order to support 'Reset All' and other actions
            try:
                if not hasattr(self, '_parameter_names'):
                    self._parameter_names = []
                self._parameter_names.append(str(param_name))
            except Exception:
                pass

            row_layout.addWidget(name_label)
            row_layout.addWidget(slider, 1)
            row_layout.addWidget(spin)
            row_layout.addWidget(reset_btn)

            row_action = QWidgetAction(self)
            row_action.setDefaultWidget(row_widget)
            self.addAction(row_action)

        # --- Secondary action row: buttons that operate on the whole filter ---
        try:
            # Create a container widget for actions
            action_widget = QWidget(self)
            action_layout = QHBoxLayout(action_widget)
            action_layout.setContentsMargins(8, 6, 8, 6)
            action_layout.setSpacing(8)

            # Spacer to align buttons to the right
            filler = QWidget(action_widget)
            filler.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Preferred)
            action_layout.addWidget(filler)

            # Reset All button: present when filter has more than one parameter
            try:
                if len(getattr(self, '_parameter_names', [])) > 1:
                    reset_all_btn = QPushButton("Reset All", action_widget)
                    reset_all_btn.setFixedWidth(100)
                    reset_all_btn.setStyleSheet("QPushButton { color: white; background-color: #2a2a2a; border: 1px solid #444; padding: 4px; }")
                    def _on_reset_all():
                        try:
                            # loop through parameter names and reset each
                            for i, name in enumerate(getattr(self, '_parameter_names', []) or []):
                                try:
                                    # get default from meta if available
                                    meta = param_meta.get(name, None)
                                    if meta is not None:
                                        _def, lo, hi, _hm = meta
                                    else:
                                        _def = 0.0
                                    # update spin and slider if present
                                    try:
                                        spin = self._parameter_spinboxes[i]
                                        slider = self._parameter_sliders[i]
                                        val = float(_def)
                                        spin.blockSignals(True)
                                        spin.setValue(self._clamp_spin_value(val, lo, hi))
                                        spin.blockSignals(False)
                                        frac = 0.0
                                        if hi > lo:
                                            frac = (val - lo) / (hi - lo)
                                        slider.blockSignals(True)
                                        slider.setValue(int(round(max(0.0, min(1.0, frac)) * 10000.0)))
                                        slider.blockSignals(False)
                                    except Exception:
                                        pass
                                    # queue the parameter change to apply and persist
                                    try:
                                        self._queue_parameter_change(name, float(_def))
                                    except Exception:
                                        pass
                                except Exception:
                                    pass
                        except Exception:
                            pass
                    reset_all_btn.clicked.connect(_on_reset_all)
                    action_layout.addWidget(reset_all_btn)
            except Exception:
                pass

            # Filter-specific actions: e.g., for bcs add 'Optimal'
            try:
                fid = getattr(self.filter_instance, 'filter_id', '')
                if str(fid).strip().lower() == 'bcs':
                    opt_btn = QPushButton("Optimal", action_widget)
                    opt_btn.setFixedWidth(100)
                    opt_btn.setStyleSheet("QPushButton { color: white; background-color: #2a2a2a; border: 1px solid #444; padding: 4px; }")
                    def _on_optimal():
                        try:
                            QApplication.setOverrideCursor(Qt.WaitCursor)
                            QApplication.processEvents()
                            # Resolve the actual parent widget: support bound method or attribute
                            p_attr = getattr(self, 'parent', None)
                            parent = None
                            try:
                                if callable(p_attr):
                                    parent = p_attr()
                                else:
                                    parent = p_attr
                            except Exception:
                                parent = None
                            if parent is None:
                                try:
                                    parent = self.parent()
                                except Exception:
                                    parent = None
                            try:
                                print(f"[OPTIMAL] parent_repr={parent!r}", flush=True)
                            except Exception:
                                pass
                            if parent is None:
                                return
                            # Try to get a source pixmap from several known locations on the parent
                            src = None
                            try:
                                if hasattr(parent, 'display') and parent.display is not None:
                                    try:
                                        print("[OPTIMAL] parent has attribute 'display'", flush=True)
                                        src = parent.display.getSourcePixmap()
                                    except Exception as e:
                                        print(f"[OPTIMAL] parent.display.getSourcePixmap() error: {e}", flush=True)
                                        src = None
                                # prefer display, but also check image_label (separate UI flows)
                                if (src is None or (hasattr(src, 'isNull') and src.isNull())) and hasattr(parent, 'image_label') and parent.image_label is not None:
                                    try:
                                        print("[OPTIMAL] parent has attribute 'image_label'", flush=True)
                                        src = parent.image_label.getSourcePixmap()
                                    except Exception as e:
                                        print(f"[OPTIMAL] parent.image_label.getSourcePixmap() error: {e}", flush=True)
                                        src = None
                            except Exception:
                                src = None

                            # If still no src, probe additional attributes that may hold the pixmap
                            try:
                                if (src is None or (hasattr(src, 'isNull') and src.isNull())):
                                    for attr in ('original_pixmap', 'display_pixmap', '_original_pixmap'):
                                        cand = getattr(parent, attr, None)
                                        try:
                                            print(f"[OPTIMAL] parent.{attr} -> {cand!r}", flush=True)
                                        except Exception:
                                            pass
                                        if cand is not None and hasattr(cand, 'isNull') and not cand.isNull():
                                            src = cand
                                            try:
                                                print(f"[OPTIMAL] using parent.{attr}", flush=True)
                                            except Exception:
                                                pass
                                            break
                            except Exception:
                                pass

                            # Also try image_label.pixmap() and scaled pixmap
                            try:
                                if (src is None or (hasattr(src, 'isNull') and src.isNull())) and hasattr(parent, 'image_label') and parent.image_label is not None:
                                    try:
                                        cand = parent.image_label.pixmap()
                                        if cand is not None and not cand.isNull():
                                            src = cand
                                            try:
                                                print("[OPTIMAL] using parent.image_label.pixmap()", flush=True)
                                            except Exception:
                                                pass
                                    except Exception:
                                        pass
                            except Exception:
                                pass

                            # Log last-loaded path if available
                            try:
                                lp = getattr(parent, '_last_loaded_content_path', None)
                                print(f"[OPTIMAL] parent._last_loaded_content_path={lp}", flush=True)
                            except Exception:
                                pass

                            pil_img = None
                            # conversion helper: prefer parent's conversion if available
                            conv = None
                            try:
                                conv = getattr(parent, '_pixmap_to_pil_rgba', None)
                            except Exception:
                                conv = None
                            try:
                                if src is not None and not getattr(src, 'isNull', lambda: False)():
                                    try:
                                        try:
                                            print(f"[OPTIMAL] src present width={src.width()} height={src.height()}", flush=True)
                                        except Exception:
                                            pass
                                        if callable(conv):
                                            pil_img = conv(src)
                                        else:
                                            # local fallback conversion
                                            image = src.toImage()
                                            buffer = QBuffer()
                                            buffer.open(QIODevice.WriteOnly)
                                            image.save(buffer, "PNG")
                                            pil_img = Image.open(io.BytesIO(buffer.data())).convert('RGBA')
                                    except Exception:
                                        pil_img = None
                            except Exception:
                                pil_img = None

                            # Ask the filter instance to suggest values when given the image
                            suggested = {}
                            try:
                                try:
                                    if pil_img is None:
                                        print("[OPTIMAL] pil_img is None", flush=True)
                                    else:
                                        try:
                                            print(f"[OPTIMAL] pil_img mode={pil_img.mode} size={pil_img.size}", flush=True)
                                        except Exception:
                                            print(f"[OPTIMAL] pil_img present (no mode/size)", flush=True)
                                except Exception:
                                    pass
                                suggested = self.filter_instance.suggest_parameters(pil_img)
                            except Exception:
                                suggested = {}

                            # Fallback: if no suggestion and no pil image, try loading the last-loaded file
                            try:
                                if (not suggested) and pil_img is None:
                                    lp = getattr(parent, '_last_loaded_content_path', None)
                                    if lp and os.path.exists(lp):
                                        try:
                                            pil_img = Image.open(lp).convert('RGBA')
                                            suggested = self.filter_instance.suggest_parameters(pil_img)
                                            try:
                                                print(f"[OPTIMAL] fallback loaded file {lp}, suggested={suggested}", flush=True)
                                            except Exception:
                                                pass
                                        except Exception:
                                            suggested = {}
                            except Exception:
                                pass

                            try:
                                print(f"[OPTIMAL] suggested={suggested}", flush=True)
                            except Exception:
                                pass

                            # Apply suggested values to controls
                            for i, name in enumerate(getattr(self, '_parameter_names', []) or []):
                                try:
                                    if name in suggested:
                                        val = float(suggested[name])
                                    else:
                                        continue
                                    try:
                                        spin = self._parameter_spinboxes[i]
                                        slider = self._parameter_sliders[i]
                                        lo = param_meta.get(name, (0.0, 0.0, 1.0, False))[1]
                                        hi = param_meta.get(name, (0.0, 0.0, 1.0, False))[2]
                                        spin.blockSignals(True)
                                        spin.setValue(self._clamp_spin_value(val, lo, hi))
                                        spin.blockSignals(False)
                                        frac = 0.0
                                        if hi > lo:
                                            frac = (val - lo) / (hi - lo)
                                        slider.blockSignals(True)
                                        slider.setValue(int(round(max(0.0, min(1.0, frac)) * 10000.0)))
                                        slider.blockSignals(False)
                                    except Exception:
                                        pass
                                    try:
                                        self._queue_parameter_change(name, float(val))
                                    except Exception:
                                        pass
                                except Exception:
                                    pass
                        finally:
                            try:
                                QApplication.restoreOverrideCursor()
                            except Exception:
                                pass
                    opt_btn.clicked.connect(_on_optimal)
                    action_layout.addWidget(opt_btn)
                    # Lab chroma experimental action: applies lab_chroma to current preview
                    lab_btn = QPushButton("Lab chroma", action_widget)
                    lab_btn.setFixedWidth(100)
                    lab_btn.setStyleSheet("QPushButton { color: white; background-color: #2a2a2a; border: 1px solid #444; padding: 4px; }")
                    def _on_lab_chroma():
                        try:
                            QApplication.setOverrideCursor(Qt.WaitCursor)
                            QApplication.processEvents()
                            # Resolve the actual parent widget: support bound method or attribute
                            p_attr = getattr(self, 'parent', None)
                            parent = None
                            try:
                                if callable(p_attr):
                                    parent = p_attr()
                                else:
                                    parent = p_attr
                            except Exception:
                                parent = None
                            if parent is None:
                                try:
                                    parent = self.parent()
                                except Exception:
                                    parent = None
                            try:
                                print(f"[LAB] parent_repr={parent!r}", flush=True)
                            except Exception:
                                pass
                            if parent is None:
                                return
                            # find source pixmap (reuse same probing logic as Optimal)
                            src = None
                            try:
                                if hasattr(parent, 'display') and parent.display is not None:
                                    try:
                                        src = parent.display.getSourcePixmap()
                                    except Exception:
                                        src = None
                                if (src is None or (hasattr(src, 'isNull') and src.isNull())) and hasattr(parent, 'image_label') and parent.image_label is not None:
                                    try:
                                        src = parent.image_label.getSourcePixmap()
                                    except Exception:
                                        src = None
                            except Exception:
                                src = None

                            pil_img = None
                            # conversion helper: prefer parent's conversion if available
                            conv = None
                            try:
                                conv = getattr(parent, '_pixmap_to_pil_rgba', None)
                            except Exception:
                                conv = None
                            try:
                                if src is not None and not getattr(src, 'isNull', lambda: False)():
                                    try:
                                        try:
                                            print(f"[LAB] src present width={src.width()} height={src.height()}", flush=True)
                                        except Exception:
                                            pass
                                        if callable(conv):
                                            pil_img = conv(src)
                                        else:
                                            image = src.toImage()
                                            buffer = QBuffer()
                                            buffer.open(QIODevice.WriteOnly)
                                            image.save(buffer, "PNG")
                                            pil_img = Image.open(io.BytesIO(buffer.data())).convert('RGBA')
                                    except Exception:
                                        pil_img = None
                            except Exception:
                                pil_img = None

                            if pil_img is None:
                                return

                            # find lab_chroma_suggest helper from filter module if available
                            helper = None
                            try:
                                modname = getattr(self.filter_instance, '__module__', None)
                                if modname:
                                    mod = __import__(modname, fromlist=['lab_chroma_suggest'])
                                    helper = getattr(mod, 'lab_chroma_suggest', None)
                            except Exception:
                                helper = None

                            # fallback to module-level function if importable
                            if helper is None:
                                try:
                                    from gui.python.content_filters.bcs_filter import lab_chroma_suggest as _lc
                                    helper = _lc
                                except Exception:
                                    helper = None

                            if helper is None:
                                return

                            # Ask the helper for suggestions (same return type as suggest_parameters)
                            suggested = {}
                            try:
                                suggested = helper(pil_img) or {}
                            except Exception:
                                suggested = {}

                            try:
                                print(f"[LAB] suggested={suggested}", flush=True)
                            except Exception:
                                pass

                            # Apply suggested values to controls (same as Optimal)
                            for i, name in enumerate(getattr(self, '_parameter_names', []) or []):
                                try:
                                    if name in suggested:
                                        val = float(suggested[name])
                                    else:
                                        continue
                                    try:
                                        spin = self._parameter_spinboxes[i]
                                        slider = self._parameter_sliders[i]
                                        lo = param_meta.get(name, (0.0, 0.0, 1.0, False))[1]
                                        hi = param_meta.get(name, (0.0, 0.0, 1.0, False))[2]
                                        spin.blockSignals(True)
                                        spin.setValue(self._clamp_spin_value(val, lo, hi))
                                        spin.blockSignals(False)
                                        frac = 0.0
                                        if hi > lo:
                                            frac = (val - lo) / (hi - lo)
                                        slider.blockSignals(True)
                                        slider.setValue(int(round(max(0.0, min(1.0, frac)) * 10000.0)))
                                        slider.blockSignals(False)
                                    except Exception:
                                        pass
                                    try:
                                        self._queue_parameter_change(name, float(val))
                                    except Exception:
                                        pass
                                except Exception:
                                    pass
                        finally:
                            try:
                                QApplication.restoreOverrideCursor()
                            except Exception:
                                pass
                    lab_btn.clicked.connect(_on_lab_chroma)
                    action_layout.addWidget(lab_btn)
            except Exception:
                pass

            row_action = QWidgetAction(self)
            row_action.setDefaultWidget(action_widget)
            self.addAction(row_action)
        except Exception:
            pass

    def _set_controls_enabled(self, enabled: bool):
        for slider in self._parameter_sliders:
            try:
                slider.setEnabled(enabled)
            except Exception:
                pass
        for spin in self._parameter_spinboxes:
            try:
                spin.setEnabled(enabled)
            except Exception:
                pass
    def _clamp_spin_value(self, v: float, lo: float, hi: float) -> float:
        try:
            vv = float(v)
            if vv < lo:
                return lo
            if vv > hi:
                return hi
            return vv
        except Exception:
            return lo

    def _apply_parameter_change(self, param_name: str, value: float):
        try:
            # value is actual parameter value in its own range
            self.filter_instance.set_parameter(param_name, value)
            # Call the provided callback (usually saves + UI update)
            try:
                if callable(self.on_change_callback):
                    self.on_change_callback()
            except Exception:
                pass
            # As a fallback ensure the parent/dialog persistence method is invoked
            try:
                parent = getattr(self, 'parent', None)
                if parent is None:
                    parent = self.parent()
                if parent is not None and hasattr(parent, '_save_content_filter_parameter_values'):
                    try:
                        parent._save_content_filter_parameter_values()
                    except Exception:
                        pass
            except Exception:
                pass
        except Exception:
            pass
        finally:
            self._set_controls_enabled(True)
            try:
                QApplication.restoreOverrideCursor()
            except Exception:
                pass

    def _queue_parameter_change(self, param_name: str, value: float):
        try:
            self._set_controls_enabled(False)
            QApplication.setOverrideCursor(Qt.WaitCursor)
            QApplication.processEvents()
            QTimer.singleShot(0, partial(self._apply_parameter_change, param_name, value))
        except Exception:
            self._set_controls_enabled(True)
            try:
                QApplication.restoreOverrideCursor()
            except Exception:
                pass

    def _on_slider_value_changed(self, spin: QDoubleSpinBox, lo: float, hi: float, slider_value: int):
        try:
            # map slider [0,10000] -> [lo,hi]
            frac = max(0.0, min(1.0, float(slider_value) / 10000.0))
            actual = lo + frac * (hi - lo)
            spin.blockSignals(True)
            spin.setValue(actual)
            spin.blockSignals(False)
        except Exception:
            try:
                spin.blockSignals(False)
            except Exception:
                pass

    def _on_slider_released(self, param_name: str, slider: QSlider, spin: QDoubleSpinBox, lo: float, hi: float):
        try:
            slider_value = int(slider.value())
            frac = max(0.0, min(1.0, float(slider_value) / 10000.0))
            actual = lo + frac * (hi - lo)
            spin.blockSignals(True)
            spin.setValue(actual)
            spin.blockSignals(False)
        except Exception:
            try:
                spin.blockSignals(False)
            except Exception:
                pass

        self._queue_parameter_change(param_name, actual)

    def _on_spinbox_edit_finished(self, param_name: str, slider: QSlider, spin: QDoubleSpinBox, lo: float, hi: float):
        try:
            actual = float(spin.value())
            frac = 0.0
            if hi > lo:
                frac = (actual - lo) / (hi - lo)
            slider_value = int(round(max(0.0, min(1.0, frac)) * 10000.0))
            slider.blockSignals(True)
            slider.setValue(slider_value)
            slider.blockSignals(False)
        except Exception:
            try:
                slider.blockSignals(False)
            except Exception:
                pass
            return

        self._queue_parameter_change(param_name, actual)

    def _on_reset_clicked(self, param_name: str, slider: QSlider, spin: QDoubleSpinBox, default_value, lo: float, hi: float):
        try:
            try:
                val = float(default_value)
            except Exception:
                val = float(lo)
            val = self._clamp_spin_value(val, lo, hi)

            spin.blockSignals(True)
            spin.setValue(val)
            spin.blockSignals(False)

            frac = 0.0
            if hi > lo:
                frac = (val - lo) / (hi - lo)
            slider.blockSignals(True)
            slider.setValue(int(round(max(0.0, min(1.0, frac)) * 10000.0)))
            slider.blockSignals(False)

            self._queue_parameter_change(param_name, val)
        except Exception:
            pass

    def mousePressEvent(self, event):
        try:
            inside_menu = self.rect().contains(event.pos())
            clicked_action = self.actionAt(event.pos())
            if inside_menu and clicked_action is None:
                event.accept()
                return
        except Exception:
            pass
        super().mousePressEvent(event)

    def mouseReleaseEvent(self, event):
        try:
            inside_menu = self.rect().contains(event.pos())
            clicked_action = self.actionAt(event.pos())
            if inside_menu and clicked_action is None:
                event.accept()
                return
        except Exception:
            pass
        super().mouseReleaseEvent(event)

# --------

class JudgeDialog(QDialog):

    def __init__(self):
        super().__init__(None, Qt.WindowSystemMenuHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowMaximizeButtonHint)

        #Set the main layout
        self.setWindowTitle("VR We Are - Check Files: Judge")
        self.setWindowIcon(QIcon(os.path.join(path, '../../gui/img/icon.png')))
        self.setMaximumSize(QSize(1920,1080))
        self.setGeometry(150, 150, 1280, 768)
        self.outer_main_layout = QVBoxLayout()
        self.setLayout(self.outer_main_layout)
        self.setStyleSheet("background : black; color: white;")

           
class RateAndCutDialog(QDialog):
    frame_export_progress_signal = pyqtSignal(int, int)

    def __init__(self, cutMode):
        super().__init__(None, Qt.WindowSystemMenuHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint )
        
        try:
            self.setModal(True)
            self.setWindowFlags(Qt.CustomizeWindowHint | Qt.WindowMaximizeButtonHint | Qt.WindowCloseButtonHint )

            global cutModeActive, cutModeFolderOverrideActive
            cutModeActive=cutMode
            self.cutMode=cutMode
            cutModeFolderOverrideActive=False
            self.wait_dialog = None
            self._frame_export_progress_dialog = None
            self._frame_export_progress_bar = None
            self.frame_export_progress_signal.connect(self._update_frame_export_progress)
            self.playtype_pingpong=False
            self.sliderinitdone=False
            self.filter_img = False
            self.filter_vid = False
            self.filter_edit = not self.cutMode
            self.content_filter_mode = 0
            self.content_filters: List[BaseImageFilter] = create_content_filter_instances()
            if not self.content_filters:
                self.content_filters = [BaseImageFilter()]
            self._filter_lists_by_content_type = {
                BaseImageFilter.CONTENT_TYPE_IMAGE: [],
                BaseImageFilter.CONTENT_TYPE_VIDEO: [],
            }
            self._selected_filter_id_by_content_type = {
                BaseImageFilter.CONTENT_TYPE_IMAGE: "",
                BaseImageFilter.CONTENT_TYPE_VIDEO: "",
            }
            self._active_content_filter_list: List[BaseImageFilter] = []
            self._current_filter_combo_content_type = None
            self.active_content_filter: BaseImageFilter = BaseImageFilter()
            self._last_loaded_content_path = None
            self._content_filter_properties_path = os.path.join(get_user_config_dir(), CONTENT_FILTER_PROPERTIES_FILENAME)
            pass
            
            self._load_content_filter_parameter_values()
            self._initialize_content_filter_lists()
            # inpaint mode flag (toggled by toolbar button)
            self.inpaint_mode = False
            self.loadingOk = True
            self.drag_file_path = None
            
            setFileFilter(self.filter_img, self.filter_vid, self.filter_edit)
            rescanFilesToRate()
            
            self.qt_img=None
            self.hasCropOrTrim=False
            self.isPaused = False
            self.currentFile = None
            self.currentIndex = -1

            # Clipboard state
            self.clipboard_has_image = False
            self._last_clipboard_hash = None
            self._last_saved_hash = None

            self.init_clipboard_monitor()
            
            exifpath=gitbash_to_windows_path(config("EXIFTOOLBINARY", ""))
            if len(exifpath)>0 and os.path.exists(exifpath):
                self.exifpath=exifpath
            else:
                self.exifpath=None
                print("Warning: Exifpath not found.", exifpath, len(exifpath), flush=True)
            
            #Set the main layout
            if cutMode:
                self.setWindowTitle("VR We Are - Check Files: Edit")
            else:
                self.setWindowTitle("VR We Are - Check Files: Rating")
            self.setWindowIcon(QIcon(os.path.join(path, '../../gui/img/icon.png')))
            self.setMaximumSize(QSize(3840,2160))
            self.setGeometry(40, 120, 1920, 768)
            self.outer_main_layout = QVBoxLayout()
            self.setLayout(self.outer_main_layout)
            self.setStyleSheet("background-color : black;")

            # --- Toolbar ---
            self.cutMode_toolbar = QToolBar(self)
            self.cutMode_toolbar.setVisible(True)
            if cutMode:
                self.iconFolderAction = StyledIcon(os.path.join(path, '../../gui/img/folder64.png'))
                self.folderAction = QAction(self.iconFolderAction, "Select Custom Folder")
                self.folderAction.setCheckable(True)
                self.folderAction.setVisible(True)
                self.folderAction.triggered.connect(self.onSelectFolder)
                self.cutMode_toolbar.addAction(self.folderAction)
                self.cutMode_toolbar.widgetForAction(self.folderAction).setCursor(Qt.PointingHandCursor)

            self.iconOpenFolderAction = StyledIcon(os.path.join(path, '../../gui/img/explorer64.png'))
            self.openFolderAction = QAction(self.iconOpenFolderAction, "Open Folder")
            self.openFolderAction.setCheckable(False)
            self.openFolderAction.setVisible(True)
            self.openFolderAction.triggered.connect(self.onOpenFolder)
            self.cutMode_toolbar.addAction(self.openFolderAction)
            self.cutMode_toolbar.widgetForAction(self.openFolderAction).setCursor(Qt.PointingHandCursor)

            # --- Open Edit Folder Action (opens the 'edit' subfolder) ---
            try:
                self.iconOpenEditAction = StyledIcon(os.path.join(path, '../../gui/img/editfolder64.png'))
            except Exception:
                self.iconOpenEditAction = QIcon(os.path.join(path, '../../gui/img/editfolder64.png'))
            self.openEditAction = QAction(self.iconOpenEditAction, "Open Edit Folder")
            self.openEditAction.setCheckable(False)
            self.openEditAction.setVisible(True)
            self.openEditAction.triggered.connect(self.onOpenEdit)
            self.cutMode_toolbar.addAction(self.openEditAction)
            self.cutMode_toolbar.widgetForAction(self.openEditAction).setCursor(Qt.PointingHandCursor)

            self.iconOpenArchiveAction = StyledIcon(os.path.join(path, '../../gui/img/openarchive64.png'))
            self.openArchiveAction = QAction(self.iconOpenArchiveAction, "Open Archive")
            self.openArchiveAction.setCheckable(False)
            self.openArchiveAction.setVisible(True)
            self.openArchiveAction.triggered.connect(self.onOpenArchive)
            self.cutMode_toolbar.addAction(self.openArchiveAction)
            self.cutMode_toolbar.widgetForAction(self.openArchiveAction).setCursor(Qt.PointingHandCursor)

            self.cutMode_toolbar.addSeparator()

            self.toggle_playtype_icon_false = QIcon(os.path.join(path, '../../gui/img/replay64.png'))
            self.toggle_playtype_icon_true = QIcon(os.path.join(path, '../../gui/img/pingpong64.png'))
            self.iconPlayTypeAction = QAction(self.toggle_playtype_icon_true if self.playtype_pingpong else self.toggle_playtype_icon_false, "Change Playtype")
            self.iconPlayTypeAction.setCheckable(True)
            self.iconPlayTypeAction.setChecked(self.playtype_pingpong)
            self.iconPlayTypeAction.setVisible(True)
            self.iconPlayTypeAction.triggered.connect(self.onPlayTypeAction)
            self.cutMode_toolbar.addAction(self.iconPlayTypeAction)
            self.cutMode_toolbar.widgetForAction(self.iconPlayTypeAction).setCursor(Qt.PointingHandCursor)

            self.cutMode_toolbar.addSeparator()

            self.iconCopyFilepathToClipboardAction = StyledIcon(os.path.join(path, '../../gui/img/clipcopy64.png'))
            self.copyFilepathToClipboardAction = QAction(self.iconCopyFilepathToClipboardAction, "Copy file path")
            self.copyFilepathToClipboardAction.setCheckable(False)
            self.copyFilepathToClipboardAction.setVisible(True)
            self.copyFilepathToClipboardAction.triggered.connect(self.onCopyFilepathToClipboard)
            self.cutMode_toolbar.addAction(self.copyFilepathToClipboardAction)
            self.cutMode_toolbar.widgetForAction(self.copyFilepathToClipboardAction).setCursor(Qt.PointingHandCursor)

            self.iconPasteImageFromClipboardAction = StyledIcon(os.path.join(path, '../../gui/img/clippaste64.png'))
            self.pasteImageFromClipboardAction = QAction(self.iconPasteImageFromClipboardAction, "Paste image from clipboard")
            self.pasteImageFromClipboardAction.setCheckable(False)
            self.pasteImageFromClipboardAction.setVisible(True)
            self.pasteImageFromClipboardAction.setEnabled(False)
            self.pasteImageFromClipboardAction.triggered.connect(self.onPasteImageFromClipboard)
            self.cutMode_toolbar.addAction(self.pasteImageFromClipboardAction)
            self.cutMode_toolbar.widgetForAction(self.pasteImageFromClipboardAction).setCursor(Qt.PointingHandCursor)

            self.cutMode_toolbar.addSeparator()

            self.iconSceneFinderAction = StyledIcon(os.path.join(path, '../../gui/img/scenefinder64.png'))
            self.sceneFinderAction = QAction(self.iconSceneFinderAction, "Find scene cuts")
            self.sceneFinderAction.setCheckable(True)
            self.sceneFinderDone=False
            self.sceneFinderAction.setChecked(self.sceneFinderDone)
            self.sceneFinderAction.setVisible(True)
            self.sceneFinderAction.triggered.connect(self.onSceneFinderAction)
            self.cutMode_toolbar.addAction(self.sceneFinderAction)
            self.cutMode_toolbar.widgetForAction(self.sceneFinderAction).setCursor(Qt.PointingHandCursor)

            self.cutMode_toolbar.addSeparator()

            self.toggle_filterimg_icon_false = QIcon(os.path.join(path, '../../gui/img/filterimgoff64.png'))
            self.toggle_filterimg_icon_true = QIcon(os.path.join(path, '../../gui/img/filterimgon64.png'))
            self.filterImgAction = QAction(self.toggle_filterimg_icon_true if self.filter_img else self.toggle_filterimg_icon_false, "Toogle Image Filter")
            self.filterImgAction.setCheckable(True)
            self.filterImgAction.setChecked(self.filter_img)
            self.filterImgAction.setVisible(True)
            self.filterImgAction.triggered.connect(self.onFilterImg)
            self.cutMode_toolbar.addAction(self.filterImgAction)
            self.cutMode_toolbar.widgetForAction(self.filterImgAction).setCursor(Qt.PointingHandCursor)

            self.toggle_filtervid_icon_false = QIcon(os.path.join(path, '../../gui/img/filtervidoff64.png'))
            self.toggle_filtervid_icon_true = QIcon(os.path.join(path, '../../gui/img/filtervidon64.png'))
            self.filterVidAction = QAction(self.toggle_filtervid_icon_true if self.filter_vid else self.toggle_filtervid_icon_false, "Toogle Video Filter")
            self.filterVidAction.setCheckable(True)
            self.filterVidAction.setChecked(self.filter_vid)
            self.filterVidAction.setVisible(True)
            self.filterVidAction.triggered.connect(self.onFilterVid)
            self.cutMode_toolbar.addAction(self.filterVidAction)
            self.cutMode_toolbar.widgetForAction(self.filterVidAction).setCursor(Qt.PointingHandCursor)

            self.toggle_filteredit_icon_false = QIcon(os.path.join(path, '../../gui/img/filtereditoff64.png'))
            self.toggle_filteredit_icon_true = QIcon(os.path.join(path, '../../gui/img/filterediton64.png'))
            self.filterEditAction = QAction(self.toggle_filteredit_icon_true if self.filter_edit else self.toggle_filteredit_icon_false, "Toogle Edit Filter")
            self.filterEditAction.setCheckable(True)
            self.filterEditAction.setChecked(self.filter_edit)
            self.filterEditAction.setVisible(not self.cutMode)
            self.filterEditAction.triggered.connect(self.onFilterEdit)
            self.cutMode_toolbar.addAction(self.filterEditAction)
            self.cutMode_toolbar.widgetForAction(self.filterEditAction).setCursor(Qt.PointingHandCursor)

            self.cutMode_toolbar.addSeparator()

            self.sortfiles_icons = []
            self.sortfiles_icons.append( QIcon(os.path.join(path, '../../gui/img/sortaz64.png')) )
            self.sortfiles_icons.append( QIcon(os.path.join(path, '../../gui/img/sortza64.png')) )
            self.sortfiles_icons.append( QIcon(os.path.join(path, '../../gui/img/sorttup64.png')) )
            self.sortfiles_icons.append( QIcon(os.path.join(path, '../../gui/img/sorttdown64.png')) )
            self.sortfiles_combo = QComboBox()
            self.sortfiles_combo.setEditable(False)
            for icon in self.sortfiles_icons:
                self.sortfiles_combo.addItem(icon, "")
            self.sortfiles_combo.setItemData(0, "alpha↑", Qt.ToolTipRole)
            self.sortfiles_combo.setItemData(1, "alpha↓", Qt.ToolTipRole)
            self.sortfiles_combo.setItemData(2, "time↑", Qt.ToolTipRole)
            self.sortfiles_combo.setItemData(3, "time↓", Qt.ToolTipRole)
                
            self.sortfiles_combo.setIconSize(QSize(32,32))
            self.sortfiles_combo.setCurrentIndex(_sortOrderIndex)
            self.sortfiles_combo.setStyleSheet('selection-background-color: rgb(0,0,0)')
            # Show icon-only: fix width to icon width + small padding so no text area remains
            # Make the combo show icon-only by hiding the drop-down arrow and
            # removing internal paddings; keep a small padding around the icon.
            # Fixed width requested by user (56 px)
            w = 56
            try:
                self.sortfiles_combo.setFixedWidth(w)
                self.sortfiles_combo.setFocusPolicy(Qt.NoFocus)
                self.sortfiles_combo.setStyleSheet(
                    'selection-background-color: rgb(0,0,0); '
                    'QComboBox::drop-down{width:0px; border: none;} '
                    'QComboBox::down-arrow{image: none;} '
                    'QComboBox { padding-left: 0px; padding-right: 0px; }'
                )
            except Exception:
                pass
            self.cutMode_toolbar.addWidget(self.sortfiles_combo)
            self.sortfiles_combo.currentIndexChanged.connect(self.on_sortfiles_combobox_index_changed)

            # --- Inpaint Mode toggle (placed after sort selection) ---
            try:
                self.iconInpaintMode = StyledIcon(os.path.join(path, '../../gui/img/inpaintmode64.png'))
            except Exception:
                self.iconInpaintMode = QIcon(os.path.join(path, '../../gui/img/inpaintmode64.png'))
            self.inpaintModeAction = QAction(self.iconInpaintMode, "Inpaint Mode")
            self.inpaintModeAction.setCheckable(True)
            self.inpaintModeAction.setChecked(self.inpaint_mode)
            self.inpaintModeAction.setVisible(True)
            self.inpaintModeAction.triggered.connect(self.onToggleInpaintMode)
            # Only allow toggling inpaint mode when in cutMode; otherwise keep it disabled
            self.inpaintModeAction.setEnabled(self.cutMode)
            if not self.cutMode:
                self.inpaintModeAction.setChecked(False)
            self.cutMode_toolbar.addAction(self.inpaintModeAction)
            self.cutMode_toolbar.widgetForAction(self.inpaintModeAction).setCursor(Qt.PointingHandCursor)

            # Edit mode only: content filter dropdown, placed right of Inpaint action.
            self.filter_mode_spacing = QLabel()
            self.filter_mode_spacing.setFixedSize(10, 1)
            self.filter_mode_spacing.setVisible(self.cutMode)
            self.cutMode_toolbar.addWidget(self.filter_mode_spacing)

            self.filter_mode_combo = QComboBox()
            self.filter_mode_combo.setEditable(False)
            self.filter_mode_combo.setVisible(self.cutMode)
            self.filter_mode_combo.setIconSize(QSize(32,32))
            # Make filter mode combobox icon-only in the toolbar
            # Fixed width requested by user (56 px)
            w2 = 56
            try:
                self.filter_mode_combo.setFixedWidth(w2)
                self.filter_mode_combo.setFocusPolicy(Qt.NoFocus)
                self.filter_mode_combo.setStyleSheet(
                    'selection-background-color: rgb(0,0,0); '
                    'QComboBox::drop-down{width:0px; border: none;} '
                    'QComboBox::down-arrow{image: none;} '
                    'QComboBox { padding-left: 0px; padding-right: 0px; }'
                )
            except Exception:
                pass
            self.cutMode_toolbar.addWidget(self.filter_mode_combo)
            self.filter_mode_combo.currentIndexChanged.connect(self.on_filter_mode_combobox_index_changed)
            self._apply_content_filter_list_for_content_type(self._get_current_content_type())

            self.filter_settings_spacing = QLabel()
            self.filter_settings_spacing.setFixedSize(4, 1)
            self.filter_settings_spacing.setVisible(self.cutMode)
            self.cutMode_toolbar.addWidget(self.filter_settings_spacing)

            self.filterSettingsAction = QAction(QIcon(os.path.join(path, '../../gui/img/config64.png')), "Filter settings")
            self.filterSettingsAction.setCheckable(False)
            self.filterSettingsAction.setVisible(self.cutMode)
            self.filterSettingsAction.triggered.connect(self.on_open_filter_settings)
            self.cutMode_toolbar.addAction(self.filterSettingsAction)
            self.cutMode_toolbar.widgetForAction(self.filterSettingsAction).setCursor(Qt.PointingHandCursor)
            self._update_filter_settings_action_icon()
            self._update_filter_settings_action_state()

            empty = QWidget()
            empty.setSizePolicy(QSizePolicy.Expanding,QSizePolicy.Expanding)
            self.cutMode_toolbar.addWidget(empty)

            self.button_show_manual_action = QAction(QIcon(os.path.join(path, '../../gui/img/manual64.png')), "Manual")      
            self.button_show_manual_action.setCheckable(False)
            self.button_show_manual_action.triggered.connect(self.show_manual)
            self.cutMode_toolbar.addAction(self.button_show_manual_action)    
            self.cutMode_toolbar.widgetForAction(self.button_show_manual_action).setCursor(Qt.PointingHandCursor)


            self.outer_main_layout.addWidget(self.cutMode_toolbar)
            self.cutMode_toolbar.setContentsMargins(0,0,0,0)

            # ------

            if cutMode:
                self.dirlabel=QLabel("")
                self.dirlabel.setStyleSheet("QLabel { background-color : black; color : white; }");
                self.outer_main_layout.addWidget(self.dirlabel)
                self.outer_main_layout.setAlignment(self.dirlabel, Qt.AlignLeft )
                self.dirlabel.setContentsMargins(8,0,0,0)

            self.button_startpause_video = ActionButton()
            self.button_startpause_video.setIcon(QIcon(os.path.join(path, '../../gui/img/play80.png')))
            self.button_startpause_video.setIconSize(QSize(80,80))

            if cutMode:
                self.iconTrimA = StyledIcon(os.path.join(path, '../../gui/img/trima80.png'))
                self.iconTrimB = StyledIcon(os.path.join(path, '../../gui/img/trimb80.png'))
                self.iconClear = StyledIcon(os.path.join(path, '../../gui/img/clear80.png'))
                self.iconTrimFirst = StyledIcon(os.path.join(path, '../../gui/img/trimfirst80.png'))
                self.iconTrimToSnap = StyledIcon(os.path.join(path, '../../gui/img/trimtosnapshot.png'))

                self.button_trima_video = ActionButton()
                self.button_trima_video.setIcon(self.iconTrimA)
                self.button_trima_video.setIconSize(QSize(80,80))

                self.button_trimfirst_video = ActionButton()
                self.button_trimfirst_video.setIcon(self.iconTrimFirst)
                self.button_trimfirst_video.setIconSize(QSize(80,80))

                self.button_trimb_video = ActionButton()
                self.button_trimb_video.setIcon(self.iconTrimB)
                self.button_trimb_video.setIconSize(QSize(80,80))

                self.button_trimtosnap_video = ActionButton()
                self.button_trimtosnap_video.setIcon(self.iconTrimToSnap)
                self.button_trimtosnap_video.setIconSize(QSize(80,80))

                self.button_snapshot_from_video = ActionButton()
                self.button_snapshot_from_video.setIcon(StyledIcon(os.path.join(path, '../../gui/img/snapshot80.png')))
                self.button_snapshot_from_video.setIconSize(QSize(80,80))
                self.button_snapshot_from_video.clicked.connect(self.createSnapshot)

                self.button_startframe = ActionButton()
                self.button_startframe.setIcon(StyledIcon(os.path.join(path, '../../gui/img/startframe80.png')))
                self.button_startframe.setIconSize(QSize(80,80))

                self.button_endframe = ActionButton()
                self.button_endframe.setIcon(StyledIcon(os.path.join(path, '../../gui/img/endframe80.png')))
                self.button_endframe.setIconSize(QSize(80,80))

            self.button_prev_file = ActionButton()
            self.button_prev_file.setIcon(StyledIcon(os.path.join(path, '../../gui/img/prevf80.png')))
            self.button_prev_file.setIconSize(QSize(80,80))
            self.button_prev_file.setEnabled(False)
            self.button_prev_file.clicked.connect(self.ratePrevious)

            self.icon_compress = StyledIcon(os.path.join(path, '../../gui/img/compress80.png'))
            self.icon_justrate = StyledIcon(os.path.join(path, '../../gui/img/justrate80.png'))
            self.button_justrate_compress = ActionButton()
            if cutMode:
                self.button_justrate_compress.setIcon(self.icon_justrate)
                self.justRate=True
            else:
                self.button_justrate_compress.setIcon(self.icon_compress)
                self.justRate=False
            self.button_justrate_compress.setIconSize(QSize(80,80))
            self.button_justrate_compress.setEnabled(True)
            self.button_justrate_compress.setVisible(True)
            self.button_justrate_compress.clicked.connect(self.rateOrArchiveAndNext)

            if cutMode:
                self.button_cutandclone = ActionButton()
                self.button_cutandclone.setIcon(StyledIcon(os.path.join(path, '../../gui/img/cutclone80.png')))
                self.button_cutandclone.setIconSize(QSize(80,80))
                self.button_cutandclone.clicked.connect(self.createTrimmedAndCroppedCopy)
            else:
                self.button_return2edit = ActionButton()
                self.button_return2edit.setIcon(StyledIcon(os.path.join(path, '../../gui/img/return2edit80.png')))
                self.button_return2edit.setIconSize(QSize(80,80))
                self.button_return2edit.setEnabled(True)
                self.button_return2edit.clicked.connect(self.return2edit)
            
            self.button_next_file = ActionButton()
            self.button_next_file.setIcon(StyledIcon(os.path.join(path, '../../gui/img/nextf80.png')))
            self.button_next_file.setIconSize(QSize(80,80))
            self.button_next_file.setEnabled(False)
            self.button_next_file.clicked.connect(self.rateNext)
            
            self.button_delete_file = ActionButton()
            self.icon_delete_default = StyledIcon(os.path.join(path, '../../gui/img/trash80.png'))
            recycle_icon_path = os.path.join(path, '../../gui/img/recycle80.png')
            self.icon_delete_switch = StyledIcon(recycle_icon_path)
            self._trashbin_switch_active = False
            self._trashbin_switch_original_input = None
            self._trashbin_switch_switched_input = None
            self._last_loaded_file_for_switch = None
            self.button_delete_file.setIcon(self.icon_delete_default)
            self.button_delete_file.setIconSize(QSize(80,80))
            self.button_delete_file.setEnabled(True)
            self.button_delete_file.clicked.connect(self.on_delete_button_clicked)
            self.button_delete_file.setFocusPolicy(Qt.ClickFocus)

            
            
            self.sl = FrameSlider(Qt.Horizontal)
            
            self.display = Display(cutMode, self.button_startpause_video, self.sl, self.updatePaused, self.onVideoLoaded, self.onRectSelected, self.onUpdate, self.playtype_pingpong, self.onBlackout)
            self.display.registerForContentFilter(self.apply_active_content_filter_to_pixmap)
            #self.display.resize(self.display_width, self.display_height)

            self.sp3 = QLabel(self)
            self.sp3.setFixedSize(48, 100)
            self.sp4 = QLabel(self)
            self.sp4.setFixedSize(8, 100)

            # Display layout
            self.display_layout = QHBoxLayout()
            self.display.registerForTrimUpdate(self.onCropOrTrim)
            if cutMode:
                # Use Inpaint-capable CropWidget when in cutMode
                self.cropWidget=InpaintCropWidget(self.display)
                self.cropWidget.registerForContentFilter(self.apply_active_content_filter_to_pixmap)
                # Initialize CropWidget inpaint state from dialog
                try:
                    self.cropWidget.inpaint_mode = self.inpaint_mode
                except Exception:
                    setattr(self.cropWidget, 'inpaint_mode', self.inpaint_mode)
                self.display_layout.addWidget(self.cropWidget)
                self.cropWidget.registerForUpdate(self.onCropOrTrim)
            else:
                self.display.setMinimumSize(1000, 750)
                self.display_layout.addWidget(self.display)

            # Ensure preview updates after UI is constructed so loaded
            # parameter values are applied to the visible preview.
            try:
                # `refresh_filtered_view` is implemented on this class,
                # not on `Display` — call the wrapper so filters are applied.
                QTimer.singleShot(0, lambda: (self.refresh_filtered_view() if hasattr(self, 'refresh_filtered_view') else None))
                if hasattr(self, 'cropWidget') and self.cropWidget is not None:
                    QTimer.singleShot(0, lambda: self.cropWidget.refresh_filtered_view())
            except Exception:
                pass


            # Video Tool layout
            self.videotool_layout = QHBoxLayout()
            self.videotool_layout.addWidget(self.sp4)
            self.videotool_layout.addWidget(self.button_startpause_video)
            if cutMode:
                self.videotool_layout.addWidget(self.button_startframe)
                self.videotool_layout.addWidget(self.button_trima_video)
                self.videotool_layout.addWidget(self.button_trimfirst_video)
                self.button_trimfirst_video.setVisible(False)
            self.videotool_layout.addWidget(self.sl, alignment =  Qt.AlignVCenter)
            if cutMode:
                self.videotool_layout.addWidget(self.button_trimb_video)
                self.videotool_layout.addWidget(self.button_trimtosnap_video)
                self.button_trimtosnap_video.setVisible(False)
                self.videotool_layout.addWidget(self.button_endframe)
                self.videotool_layout.addWidget(self.button_snapshot_from_video)

            # Common Tool layout
            # QHBoxLayout
            ew=100
            self.commontool_layout = QGridLayout()

            self.filetool_layout = QGridLayout()

            self.fileSlider=QSlider(Qt.Horizontal)
            self.fileSlider.setMinimum(1)
            self.fileSlider.setSingleStep(1)
            self.fileSlider.setPageStep(10)
            self.fileSlider.setTracking(True)
            self.fileSlider.setStyleSheet("QSlider::handle:horizontal { background-color: black; border: 2px solid white; width: 12px; height: 12px; border-radius: 6px; margin: -7px 0;} QSlider::groove:horizontal { height: 0px; border-radius: 0px; } QSlider::sub-page:horizontal { /* Farbe für den gefüllten Bereich links vom Griff */ border: 1px solid #111111; height: 6px; border-radius: 3px; } QSlider::add-page:horizontal { /* Farbe für den Bereich rechts vom Griff */ border: 1px solid #111111; height: 6px; border-radius: 3px;}")
            self.fileSlider.sliderPressed.connect(self.fileSliderDragStart)
            self.fileSlider.valueChanged.connect(self.fileSliderDragged)
            self.fileSlider.sliderReleased.connect(self.fileSliderChanged)

            self.filetool_layout.addWidget(self.fileSlider, 0, 0, 1, ew)
            
            self.fileLabel=QLabel()
            global fileDragged
            self.fileDragIndex=-1
            fileDragged=False
            self.fileLabel.setStyleSheet("QLabel { background-color : black; color : white; }");
            font = QFont()
            font.setPointSize(20)
            self.fileLabel.setFont(font)
            self.fileLabel.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
            self.filetool_layout.addWidget(self.fileLabel, 0, ew, 1, 1)


            self.commontool_layout.addLayout(self.filetool_layout, 0, 0, 1, ew)

            self.commontool_layout.addWidget(self.button_prev_file, 0, ew, 1, 1)
            
            if cutMode:
                self.commontool_layout.addWidget(self.button_cutandclone, 0, ew+1, 1, 1)
                self.commontool_layout.addWidget(self.button_justrate_compress, 0, ew+2, 1, 1)
            else:
                self.rating_widget = RatingWidget(stars_count=5)
                self.commontool_layout.addWidget(self.rating_widget, 0, ew+1, 1, 1)
                self.rating_widget.ratingChanged.connect(self.on_rating_changed)
            
            
            self.commontool_layout.addWidget(self.button_next_file, 0, ew+3, 1, 1)
            self.commontool_layout.addWidget(self.sp3, 0, ew+4, 1, 1)
            if not cutMode:
                self.commontool_layout.addWidget(self.button_justrate_compress, 0, ew+5, 1, 1)
                self.commontool_layout.addWidget(self.button_return2edit, 0, ew+6, 1, 1)
            self.commontool_layout.addWidget(self.button_delete_file, 0, ew+7, 1, 1)
            
            self.msgWidget=QPlainTextEdit()
            self.msgWidget.setReadOnly(True)
            self.msgWidget.setFrameStyle(QFrame.NoFrame)
            self.commontool_layout.addWidget(self.msgWidget, 0, ew+8, 1, ew)
            self.msgWidget.setPlaceholderText("No log entries.")
            
            self.button_startpause_video.clicked.connect(self.display.tooglePausePressed)
            if cutMode:
                self.button_trima_video.clicked.connect(self.display.trimA)
                self.button_trimfirst_video.clicked.connect(self.trimFirst)
                self.button_trimb_video.clicked.connect(self.display.trimB)
                self.button_trimtosnap_video.clicked.connect(self.trimToSnap)
                self.button_startframe.clicked.connect(self.display.posA)
                self.button_endframe.clicked.connect(self.display.posB)

            #Main Layout
            self.main_layout = QVBoxLayout()
            self.main_layout.addLayout(self.display_layout, stretch=1)
            self.main_layout.addLayout(self.videotool_layout)
            self.main_layout.addLayout(self.commontool_layout)

            #Main group box
            self.main_group_box = QGroupBox()
            self.main_group_box.setStyleSheet("QGroupBox{font-size: 20px; background-color : black; color: white;}")


            self.main_group_box.setLayout(self.main_layout)

            #Outer main layout to accomodate the group box
            self.outer_main_layout.addWidget(self.main_group_box)
            self.main_group_box.setContentsMargins(0,0,0,0)

            # Timer for updating file buttons
            self.filebutton_timer = QTimer()
            self.filebutton_timer.timeout.connect(self.update_filebuttons)
            self.filebutton_timer.start(FILESCANTIME)
            
            # Timer for updating tasks
            self._blocker = None
            self.uiBlocking=isTaskActive()
            self.uiBlockingTask_timer = QTimer()
            self.uiBlockingTask_timer.timeout.connect(self.uiBlockHandling)
            self.uiBlockingTask_timer.start(TASKCHECKTIME)

            # initial invisible
            if self.cutMode:
                self.cropWidget.display_sliders(False)
                self.button_cutandclone.setVisible(False)
                self.button_justrate_compress.setVisible(False)
                self.button_trima_video.setVisible(False)
                self.button_trimb_video.setVisible(False)
                self.button_startframe.setVisible(False)
                self.button_endframe.setVisible(False)
                self.button_snapshot_from_video.setVisible(False)
            else:
                self.rating_widget.setVisible(False)
                self.button_return2edit.setVisible(False)
            self.button_prev_file.setVisible(False)
            self.button_next_file.setVisible(False)
            self.button_delete_file.setVisible(False)
            self.fileSlider.setVisible(False)
            
            self.rateNext()

        except KeyboardInterrupt:
            pass
        except:
            print(traceback.format_exc(), flush=True)

        self.reset_timer = QTimer(self)
        self.reset_timer.setSingleShot(True)
        self.reset_timer.timeout.connect(self.reset_visual)
        self.setAcceptDrops(True)  # Enable drop events
        self._install_drop_event_filters()
        # ensure cleanup on application exit if possible
        try:
            app = QApplication.instance()
            if app:
                app.aboutToQuit.connect(partial(cleanup_temps, 1))
        except Exception:
            pass
        
        self.enable_drag_for_groupbox(self.main_group_box, )
        
    # ---------------------------------------------------------------------------------------------------------------------------

    def _install_drop_event_filters(self):
        try:
            widgets = [self]
            if hasattr(self, "main_group_box") and self.main_group_box is not None:
                widgets.append(self.main_group_box)
                widgets.extend(self.main_group_box.findChildren(QWidget))
            for widget in widgets:
                try:
                    widget.setAcceptDrops(True)
                    widget.installEventFilter(self)
                except Exception:
                    pass
        except Exception:
            pass

    def eventFilter(self, obj, event):
        try:
            event_type = event.type()
            if event_type == QEvent.DragEnter:
                self.dragEnterEvent(event)
                return event.isAccepted()
            if event_type == QEvent.DragMove:
                self.dragMoveEvent(event)
                return event.isAccepted()
            if event_type == QEvent.Drop:
                self.dropEvent(event)
                return event.isAccepted()
        except Exception:
            pass
        return super().eventFilter(obj, event)


        
    def enable_drag_for_groupbox(self, box):
        self.disable_drag_for_groupbox(box)

        # Save original event handlers (only once)
        if not hasattr(box, "_original_mousePressEvent"):
            box._original_mousePressEvent = getattr(box, "mousePressEvent", None)
        if not hasattr(box, "_original_mouseMoveEvent"):
            box._original_mouseMoveEvent = getattr(box, "mouseMoveEvent", None)
        if not hasattr(box, "_original_hoverMoveEvent"):
            box._original_hoverMoveEvent = getattr(box, "hoverMoveEvent", None)
        # Install working hover detection
        if not hasattr(box, "_hover_filter"):
            box._hover_filter = GroupBoxHoverFilter(box)
            QApplication.instance().installEventFilter(box._hover_filter)
    
        # Ensure hover and cursor tracking works
        box.setAttribute(Qt.WA_Hover, True)
        box.setMouseTracking(True)

        # Also activate mouse tracking for all children
        for child in box.findChildren(QWidget):
            child.setMouseTracking(True)

        # Determine base directory
        global cutModeFolderOverrideActive, cutModeFolderOverridePath
        if cutModeFolderOverrideActive:
            box._drag_base = cutModeFolderOverridePath
        else:
            box._drag_base = os.path.join(path, "../../../../input/vr/check/rate")

        box._drag_start_pos = None

        # --- Mouse press handler ---
        def mousePressEvent(event):
            if event.button() == Qt.LeftButton:
                box._drag_start_pos = event.pos()
            if box._original_mousePressEvent:
                box._original_mousePressEvent(event)

        # --- Mouse move handler (drag start only) ---
        def mouseMoveEvent(event):
            if box._drag_start_pos is None:
                return
            if (event.pos() - box._drag_start_pos).manhattanLength() < QApplication.startDragDistance():
                return

            title = box.title().strip()
            if not title:
                return

            file_path = os.path.abspath(os.path.join(box._drag_base, title))
            if not os.path.exists(file_path):
                return

            drag = QDrag(box)
            mime = QMimeData()
            url = QUrl.fromLocalFile(file_path)
            mime.setUrls([url])
            mime.setText(file_path)
            mime.setData("application/x-vrweare-drag", b"1")            
            drag.setMimeData(mime)

            drag.exec_(Qt.CopyAction)
            box._drag_start_pos = None

        # --- Hover move handler (dynamic cursor switching) ---
        def hoverMoveEvent(event):
            widget_under = QApplication.widgetAt(QCursor.pos())
            print(widget_under, flush=True)
            if widget_under is box:
                box.setCursor(Qt.DragLinkCursor)
            else:
                box.unsetCursor()

            if box._original_hoverMoveEvent:
                box._original_hoverMoveEvent(event)

        # Install handlers
        box.mousePressEvent = mousePressEvent
        box.mouseMoveEvent = mouseMoveEvent
        box.hoverMoveEvent = hoverMoveEvent

        box._drag_enabled = True


    def disable_drag_for_groupbox(self, box):
        if not getattr(box, "_drag_enabled", False):
            return

        # Restore original handlers
        if hasattr(box, "_original_mousePressEvent"):
            if box._original_mousePressEvent:
                box.mousePressEvent = box._original_mousePressEvent
            del box._original_mousePressEvent

        if hasattr(box, "_original_mouseMoveEvent"):
            if box._original_mouseMoveEvent:
                box.mouseMoveEvent = box._original_mouseMoveEvent
            del box._original_mouseMoveEvent

        if hasattr(box, "_original_hoverMoveEvent"):
            if box._original_hoverMoveEvent:
                box.hoverMoveEvent = box._original_hoverMoveEvent
            del box._original_hoverMoveEvent

        if hasattr(box, "_hover_filter"):
            QApplication.instance().removeEventFilter(box._hover_filter)
            del box._hover_filter
            
        # Cleanup attributes
        for attr in ("_drag_base", "_drag_start_pos", "_drag_enabled"):
            if hasattr(box, attr):
                delattr(box, attr)

        # Reset cursor and disable hover
        box.unsetCursor()
        box.setAttribute(Qt.WA_Hover, False)



    def style_group_box(self, group_box, color: str):
        """
        Apply a styled look to a QGroupBox with the given color for both text and border.
        
        Args:
            group_box (QGroupBox): The target group box.
            color (str): Any valid CSS color (e.g. '#00FF00', 'red', 'rgb(255,0,0)').
        """
        group_box.setStyleSheet(f"""
            QGroupBox {{
                font-size: 20px;
                background-color: black;
                color: {color};
                border: 2px solid {color};
                border-radius: 5px;
                margin-top: 10px;
            }}
            QGroupBox::title {{
                subcontrol-origin: margin;
                left: 10px;
                padding: 0 5px;
            }}
        """)
    
    def dragEnterEvent(self, event):
        md = event.mimeData()

        # restart timer; if drag really leaves window, timer will fire and reset color

        if md.hasFormat("application/x-vrweare-drag"):
            event.ignore()
            return
        url_candidate = self._extract_url_from_mime(md)
        if url_candidate:
            self.drag_file_path = url_candidate
            self.style_group_box(self.main_group_box, "#44ff44")
            self.reset_timer.start(1000)
            event.acceptProposedAction()
            return
        elif md.hasFormat('application/x-qt-windows-mime;value="UniformResourceLocatorW"'):
            data = md.data('application/x-qt-windows-mime;value="UniformResourceLocatorW"')
            url = bytes(data).decode('utf-16', errors='ignore').strip('\x00').strip()
            
            try:
                # Use requests with a browser-like User-Agent to improve compatibility
                r = requests.get(url, stream=True, timeout=6, headers={"User-Agent": "Mozilla/5.0"})
                content_type = r.headers.get("Content-Type", "")
                if content_type.startswith("image/") or content_type.startswith("video/"):
                    pass
                else:
                    self.drag_file_path = None 
                    self.style_group_box(self.main_group_box, "#ff0000")
                    self.reset_timer.start(2000)
                    event.ignore()
                    return

                self.drag_file_path = url
                self.style_group_box(self.main_group_box, "#44ff44")
                self.reset_timer.start(1000)
                event.acceptProposedAction()
                return
            except Exception:
                self.drag_file_path = None 
                self.style_group_box(self.main_group_box, "#ff0000")
                self.reset_timer.start(2000)
                event.ignore()
                return                
                
        elif md.hasUrls() and len(md.urls())>0:
            q = md.urls()[0]
            # local file path
            if q.isLocalFile():
                self.drag_file_path = q.toLocalFile()
                if os.path.isdir(self.drag_file_path):
                    self.style_group_box(self.main_group_box, "#44ff44")
                    self.reset_timer.start(1000)
                    event.acceptProposedAction()
                    return
                elif os.path.isfile(self.drag_file_path) and any(self.drag_file_path.lower().endswith(suf.lower()) for suf in ALL_EXTENSIONS):
                    self.style_group_box(self.main_group_box, "#44ff44")
                    event.acceptProposedAction()
                    self.reset_timer.start(1000)
                    return
            else:
                # remote URL
                url = q.toString()
                try:
                    if url and (url.startswith("http://") or url.startswith("https://") or url.startswith("data:")):
                        self.drag_file_path = url
                        self.style_group_box(self.main_group_box, "#44ff44")
                        self.reset_timer.start(1000)
                        event.acceptProposedAction()
                        return
                except Exception:
                    pass
        
        print("Formats:", event.mimeData().formats())
        self.drag_file_path = None 
        self.style_group_box(self.main_group_box, "#ff0000")
        self.reset_timer.start(2000)
        event.ignore()
    
    def reset_visual(self):
        self.style_group_box(self.main_group_box, "white")
    
    def dragMoveEvent(self, event):
        md = event.mimeData()
        if md.hasFormat("application/x-vrweare-drag"):
            event.ignore()
            return
        elif not self.drag_file_path is None:
            self.style_group_box(self.main_group_box, "#44ff44")
            event.acceptProposedAction()
        else:
            self.style_group_box(self.main_group_box, "#ff0000")
            event.ignore()
        # restart timer; if drag really leaves window, timer will fire and reset color
        self.reset_timer.start(1000)
        
    def _extract_url_from_mime(self, md):
        try:
            if md.hasFormat('application/x-qt-windows-mime;value="UniformResourceLocatorW"'):
                data = md.data('application/x-qt-windows-mime;value="UniformResourceLocatorW"')
                url = bytes(data).decode('utf-16', errors='ignore').strip('\x00').strip()
                if url and (url.startswith("http://") or url.startswith("https://") or url.startswith("data:")):
                    return url
        except Exception:
            pass

        try:
            if md.hasUrls() and len(md.urls()) > 0:
                for q in md.urls():
                    if not q.isLocalFile():
                        url = q.toString().strip()
                        if url and (url.startswith("http://") or url.startswith("https://") or url.startswith("data:")):
                            return url
        except Exception:
            pass

        try:
            txt = md.text().strip() if md.hasText() else ""
            if txt and (txt.startswith("http://") or txt.startswith("https://") or txt.startswith("data:")):
                return txt
        except Exception:
            pass
        return None

    def _short_url_for_log(self, url: str) -> str:
        try:
            if not isinstance(url, str):
                return "<invalid-url>"
            trimmed = url.strip()
            if trimmed.lower().startswith("data:"):
                header = trimmed[5:].split(',', 1)[0]
                content_type = (header.split(';', 1)[0] or '').strip().lower()
                return f"data:{content_type or 'unknown'};..."
            if len(trimmed) > 180:
                return trimmed[:180] + "..."
            return trimmed
        except Exception:
            return "<url>"


    def dropEvent(self, event):
        if isTaskActive():
            event.ignore()
            return
        # Retrieve file paths
        if not self.drag_file_path is None:
            #print(f"File dropped:\n{self.drag_file_path}", flush=True)
            md = event.mimeData()
            if md.hasFormat("application/x-vrweare-drag"):
                event.ignore()
                return
            elif isinstance(self.drag_file_path, str) and (self.drag_file_path.startswith("http://") or self.drag_file_path.startswith("https://") or self.drag_file_path.startswith("data:")):
                try:
                    self.downloadAndSwithToimage(self.drag_file_path)
                    event.acceptProposedAction()
                except Exception:
                    event.ignore()
                    try:
                        self.log("Drop URL failed: " + self._short_url_for_log(self.drag_file_path), QColor("red"))
                    except Exception:
                        pass
            elif os.path.isdir(self.drag_file_path):
                self.switchDirectory(self.drag_file_path, None, None)
                event.acceptProposedAction()
            elif os.path.isfile(self.drag_file_path) and any(self.drag_file_path.lower().endswith(suf.lower()) for suf in ALL_EXTENSIONS):
                self.switchDirectory(os.path.dirname(self.drag_file_path), os.path.basename(self.drag_file_path), None)
                event.acceptProposedAction()
            else:
                event.ignore()
        else:
            event.ignore()

    def downloadAndSwithToimage(self, url: str):
        """
        Download an image from the given URL and save it into target_dir.
        The filename is automatically derived from the URL.
        
        Args:
            url (str): The image URL (HTTP/HTTPS).
        """
        # Parse URL and derive filename like main window drop handling
        if isinstance(url, str) and url.lower().startswith("data:"):
            filename = f"clipboard_{int(time.time())}"
        else:
            parsed = urllib.parse.urlparse(url)
            filename = os.path.basename(parsed.path) or f"download_{int(time.time())}"

        self.switchDirectory(None, filename, self.drag_file_path)


    # --- Drop utility helpers (moved for clarity) ---
    def _mime_to_ext(self, mime: str) -> str:
        m = (mime or '').lower()
        if m in ('image/jpeg', 'image/jpg'):
            return '.jpg'
        if m == 'image/png':
            return '.png'
        if m == 'image/gif':
            return '.gif'
        if m == 'image/webp':
            return '.webp'
        if m == 'image/bmp':
            return '.bmp'
        if m in ('image/tiff', 'image/x-tiff'):
            return '.tiff'
        if m == 'video/mp4':
            return '.mp4'
        if m in ('video/webm', 'audio/webm'):
            return '.webm'
        if m in ('video/quicktime',):
            return '.mov'
        return ''

    def _pick_nonconflicting_name(self, directory: str, filename: str) -> str:
        candidate = filename
        base, ext = os.path.splitext(filename)
        i = 1
        while os.path.exists(os.path.join(directory, candidate)):
            candidate = f"{base}_{i}{ext}"
            i += 1
        return candidate
        
    
    def switchDirectory(self, dirpath, filename, url):
        global _cutModeFolderOverrideFiles, cutModeFolderOverrideActive, cutModeFolderOverridePath
        startAsyncTask()
        self._drop_switch_op_id = getattr(self, '_drop_switch_op_id', 0) + 1
        current_op_id = self._drop_switch_op_id
        cutModeFolderOverrideActive= not dirpath is None
        try:
            thread = threading.Thread(
                target=self.switchDirectory_worker,
                args=( cutModeFolderOverrideActive, dirpath, filename, url, current_op_id),
                daemon=True
            )
            thread.start()
        except Exception:
            endAsyncTask()
            raise

    def switchDirectory_worker(self, override, dirpath, filename, url, op_id=None):
        global _cutModeFolderOverrideFiles, cutModeFolderOverrideActive, cutModeFolderOverridePath
        try:
            if not url is None:
                override=False
                target_dir = os.path.join(path, "../../../../input/vr/check/rate")
                os.makedirs(target_dir, exist_ok=True)

                content_type = ""
                output_bytes = None

                if isinstance(url, str) and url.lower().startswith("data:"):
                    try:
                        header, payload = url[5:].split(',', 1)
                    except ValueError:
                        raise ValueError("Invalid data URL")
                    content_type = (header.split(';', 1)[0] or '').strip().lower()
                    if ';base64' in header.lower():
                        output_bytes = base64.b64decode(payload)
                    else:
                        output_bytes = urllib.parse.unquote_to_bytes(payload)
                else:
                    r = requests.get(url, stream=True, timeout=20, headers={"User-Agent": "Mozilla/5.0"})
                    r.raise_for_status()
                    content_type = (r.headers.get("Content-Type", "") or "").split(";", 1)[0].strip().lower()
                    if content_type.startswith("image/") or content_type.startswith("video/"):
                        filename = self._pick_nonconflicting_name(target_dir, filename)
                        output_path_tmp = os.path.join(target_dir, filename)
                        with open(output_path_tmp, "wb") as f:
                            for chunk in r.iter_content(8192):
                                if chunk:
                                    f.write(chunk)
                        filename = os.path.basename(output_path_tmp)
                    else:
                        raise ValueError("URL content type is not image/video")

                if output_bytes is not None:
                    if '.' not in filename:
                        ext = self._mime_to_ext(content_type)
                        filename += ext
                    filename = self._pick_nonconflicting_name(target_dir, filename)
                    output_path = os.path.join(target_dir, filename)
                    with open(output_path, "wb") as f:
                        f.write(output_bytes)

                try:
                    self.log("Dropped URL -> input/vr/check/rate/" + filename, QColor("white"))
                except Exception:
                    pass
            

            if override and not os.path.samefile(dirpath, os.path.join(path, "../../../../input/vr/check/rate") ):
                if os.path.isdir(dirpath):
                    cutModeFolderOverridePath=dirpath
                    cutModeFolderOverrideActive=True
                else:
                    print(f"not a directory: {dirpath}", flush=True)
                    override=False
                    cutModeFolderOverrideActive=False   # cancel
                    dirpath=""                    
            else:
                dirpath=""
                cutModeFolderOverrideActive=False
                
            scanFilesToRate()   # can block on some drives

            QTimer.singleShot(0, partial(self.switchDirectory_updater, override, dirpath, filename, op_id))
        except:
            endAsyncTask()
            if not url is None:
                try:
                    self.log("Drop URL failed: " + self._short_url_for_log(url), QColor("red"))
                except Exception:
                    pass
            else:
                print(traceback.format_exc(), flush=True)

    def switchDirectory_updater(self, override, dirpath, filename, op_id=None):

        global _cutModeFolderOverrideFiles, cutModeFolderOverrideActive, cutModeFolderOverridePath
        try:
            if op_id is not None and op_id != getattr(self, '_drop_switch_op_id', None):
                return
            f=getFilesToRate()
            if len(f) > 0:
                self.currentIndex=1
                self.currentFile=f[0]
                if not filename is None:
                    try:
                        self.currentFile=filename
                        self.currentIndex=f.index(self.currentFile)+1
                    except ValueError as ve:
                        if self.currentFile in f:
                            self.currentIndex=f.index(self.currentFile)+1
                        else:
                            self.currentIndex=1
                            self.currentFile=f[0]
            else:
                self.currentFile=""
                self.currentIndex=-1
                
            self.rateCurrentFile()

        except:
            print(traceback.format_exc(), flush=True) 
        finally:
            if hasattr(self, 'folderAction') and self.folderAction is not None:
                self.folderAction.setChecked(override)
                self.folderAction.setEnabled(True)
            if hasattr(self, 'dirlabel') and self.dirlabel is not None:
                self.dirlabel.setText(dirpath)
            endAsyncTask()
 
 
    def onSceneFinderAction(self, state):
        if not state and self.sceneFinderDone:
            self.sceneFinderAction.setChecked(self.sceneFinderDone)
        elif state:
            self.sceneFinderAction.setChecked(False)
            self.sceneDetection()

    def on_sortfiles_combobox_index_changed(self, index):
        enterUITask()
        try:
            global _sortOrderIndex
            _sortOrderIndex=index        # 0: A-Z, 1: Z-A, 2: Time Up, 3: Time Down
            applySortOrder()
            rescanFilesToRate()
            f=getFilesToRate()
            if len(f) > 0:
                self.currentIndex=0
                self.currentFile=f[self.currentIndex]
                self.rateCurrentFile()
        finally:
            leaveUITask()

    def _get_filter_icon(self, filter_instance: BaseImageFilter, content_type: str = "") -> QIcon:
        try:
            icon_name = getattr(filter_instance, 'icon_name', 'filter64_none.png') or 'filter64_none.png'
            icon_path = os.path.join(path, '../../gui/img', icon_name)
            if os.path.exists(icon_path):
                base_icon = QIcon(icon_path)
            else:
                base_icon = QIcon(os.path.join(path, '../../gui/img/filter64_none.png'))

            normalized_type = str(content_type or '').strip().lower()
            preview_supported = normalized_type in self._get_filter_preview_supported_content_types(filter_instance)
            if not preview_supported:
                return base_icon

            size = 64
            base_pm = base_icon.pixmap(size, size)
            if base_pm.isNull():
                return base_icon

            composed = QPixmap(base_pm)
            painter = QPainter(composed)
            painter.setRenderHint(QPainter.Antialiasing)
            painter.setRenderHint(QPainter.SmoothPixmapTransform)

            badge_size = 20
            margin = 2
            bx = size - badge_size - margin
            by = margin

            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor(0, 0, 0, 170))
            painter.drawEllipse(bx - 1, by - 1, badge_size + 2, badge_size + 2)

            eye_color = QColor(230, 230, 230)
            pupil_color = QColor(80, 180, 255)

            eye_rect = QRect(bx + 2, by + 5, badge_size - 4, badge_size - 10)
            pen = QPen(eye_color)
            pen.setWidth(2)
            painter.setPen(pen)
            painter.setBrush(Qt.NoBrush)
            painter.drawArc(eye_rect, 0, 180 * 16)
            painter.drawArc(eye_rect, 180 * 16, 180 * 16)

            pupil_r = 3
            cx = bx + badge_size // 2
            cy = by + badge_size // 2
            painter.setPen(Qt.NoPen)
            painter.setBrush(pupil_color)
            painter.drawEllipse(QPoint(cx, cy), pupil_r, pupil_r)

            painter.end()
            return QIcon(composed)
        except Exception:
            pass
        return QIcon(os.path.join(path, '../../gui/img/filter64_none.png'))

    def _initialize_content_filter_lists(self):
        image_filters = []
        video_filters = []
        for filter_instance in self.content_filters:
            if not isinstance(filter_instance, BaseImageFilter):
                continue
            supported = self._get_filter_supported_content_types(filter_instance)

            if BaseImageFilter.CONTENT_TYPE_IMAGE in supported:
                image_filters.append(filter_instance)
            if BaseImageFilter.CONTENT_TYPE_VIDEO in supported:
                video_filters.append(filter_instance)

        self._filter_lists_by_content_type = {
            BaseImageFilter.CONTENT_TYPE_IMAGE: image_filters,
            BaseImageFilter.CONTENT_TYPE_VIDEO: video_filters,
        }

        for content_type in [BaseImageFilter.CONTENT_TYPE_IMAGE, BaseImageFilter.CONTENT_TYPE_VIDEO]:
            filters = self._filter_lists_by_content_type.get(content_type, [])
            selected_filter_id = self._selected_filter_id_by_content_type.get(content_type)
            if not selected_filter_id and len(filters) > 0:
                selected_filter_id = str(getattr(filters[0], 'filter_id', '')).strip()
            if selected_filter_id:
                valid_ids = {str(getattr(item, 'filter_id', '')).strip() for item in filters}
                if selected_filter_id not in valid_ids:
                    selected_filter_id = str(getattr(filters[0], 'filter_id', '')).strip() if len(filters) > 0 else ""
            self._selected_filter_id_by_content_type[content_type] = str(selected_filter_id or "")

        # Re-apply persisted parameter values to the actual filter instances
        # after lists have been initialized to ensure the instances shown in
        # the UI reflect saved settings.
        try:
            self._load_content_filter_parameter_values()
        except Exception:
            pass

    def _update_selected_filter_tooltip(self):
        if not hasattr(self, 'filter_mode_combo') or self.filter_mode_combo is None:
            return
        try:
            idx = int(self.filter_mode_combo.currentIndex())
        except Exception:
            idx = -1

        tooltip_text = ""
        try:
            current_filter = getattr(self, 'active_content_filter', None)
            current_filter_id = str(getattr(current_filter, 'filter_id', '')).strip().lower() if current_filter is not None else ""
            if current_filter_id == 'none':
                tooltip_text = "Kein Filter gewählt"
            else:
                if idx >= 0:
                    item_tip = self.filter_mode_combo.itemData(idx, Qt.ToolTipRole)
                    tooltip_text = str(item_tip).strip() if item_tip is not None else ""
        except Exception:
            tooltip_text = ""

        try:
            self.filter_mode_combo.setToolTip(tooltip_text)
        except Exception:
            pass

    def _apply_content_filter_list_for_content_type(self, content_type: str):
        if not hasattr(self, 'filter_mode_combo') or self.filter_mode_combo is None:
            return

        target_type = str(content_type or '').strip().lower()
        if target_type not in (BaseImageFilter.CONTENT_TYPE_IMAGE, BaseImageFilter.CONTENT_TYPE_VIDEO):
            target_type = BaseImageFilter.CONTENT_TYPE_IMAGE

        filters = list(self._filter_lists_by_content_type.get(target_type, []))
        selected_filter_id = self._selected_filter_id_by_content_type.get(target_type)

        selected_index = -1
        if selected_filter_id:
            for idx, filter_instance in enumerate(filters):
                if str(getattr(filter_instance, 'filter_id', '')).strip() == selected_filter_id:
                    selected_index = idx
                    break
        if selected_index < 0 and len(filters) > 0:
            selected_index = 0

        self.filter_mode_combo.blockSignals(True)
        try:
            self.filter_mode_combo.clear()
            for idx, filter_instance in enumerate(filters):
                self.filter_mode_combo.addItem(self._get_filter_icon(filter_instance, target_type), "")
                label = getattr(filter_instance, 'display_name', f'content filter {idx}')
                self.filter_mode_combo.setItemData(idx, label, Qt.ToolTipRole)

            if selected_index >= 0:
                self.filter_mode_combo.setCurrentIndex(selected_index)
            self.filter_mode_combo.setEnabled(len(filters) > 0)
        finally:
            self.filter_mode_combo.blockSignals(False)

        self._active_content_filter_list = filters
        self._current_filter_combo_content_type = target_type

        if selected_index >= 0:
            self.active_content_filter = filters[selected_index]
            self._selected_filter_id_by_content_type[target_type] = str(getattr(self.active_content_filter, 'filter_id', '')).strip()
            self.content_filter_mode = selected_index
        else:
            self.active_content_filter = BaseImageFilter()
            self.content_filter_mode = 0

        self._update_filter_settings_action_icon()
        self._update_filter_settings_action_state()
        self._update_selected_filter_tooltip()
        try:
            # Ensure the preview reflects the newly selected filter instance
            if self.cutMode and hasattr(self, 'cropWidget') and self.cropWidget is not None:
                try:
                    self.cropWidget.refresh_filtered_view()
                except Exception:
                    pass
            else:
                try:
                    self.refresh_filtered_view()
                except Exception:
                    pass
        except Exception:
            pass

    def _reset_content_filter_selection(self):
        try:
            for content_type in [BaseImageFilter.CONTENT_TYPE_IMAGE, BaseImageFilter.CONTENT_TYPE_VIDEO]:
                filters = list(self._filter_lists_by_content_type.get(content_type, []) or [])
                if len(filters) == 0:
                    self._selected_filter_id_by_content_type[content_type] = ""
                    continue

                selected_id = ""
                for filter_instance in filters:
                    if str(getattr(filter_instance, 'filter_id', '')).strip().lower() == 'none':
                        selected_id = str(getattr(filter_instance, 'filter_id', '')).strip()
                        break
                if not selected_id:
                    selected_id = str(getattr(filters[0], 'filter_id', '')).strip()
                self._selected_filter_id_by_content_type[content_type] = selected_id

            self._apply_content_filter_list_for_content_type(self._get_current_content_type())
        except Exception:
            pass

    def on_filter_mode_combobox_index_changed(self, index):
        self._invalidate_trashbin_switch_mode()
        try:
            idx = int(index)
        except Exception:
            idx = 0

        current_type = self._get_current_content_type()
        current_list = list(getattr(self, '_active_content_filter_list', []) or [])
        if self._current_filter_combo_content_type != current_type:
            self._apply_content_filter_list_for_content_type(current_type)
            current_list = list(getattr(self, '_active_content_filter_list', []) or [])

        if idx < 0 or idx >= len(current_list):
            idx = 0

        if len(current_list) > 0:
            self.content_filter_mode = idx
            self.active_content_filter = current_list[idx]
            self._selected_filter_id_by_content_type[current_type] = str(getattr(self.active_content_filter, 'filter_id', '')).strip()
        else:
            self.content_filter_mode = 0
            self.active_content_filter = BaseImageFilter()
        self._update_filter_settings_action_icon()
        self._update_filter_settings_action_state()
        self._update_selected_filter_tooltip()

        try:
            if self.cutMode and hasattr(self, 'cropWidget') and self.cropWidget is not None and not self.isVideo:
                self.cropWidget.refresh_filtered_view()
        except Exception:
            pass
        try:
            # For non-cut display refresh, call the main refresh wrapper
            if not getattr(self, 'cutMode', False):
                self.refresh_filtered_view()
        except Exception:
            pass
        pass

    def _load_content_filter_parameter_values(self):
        values = read_properties_file(self._content_filter_properties_path)
        migrated = False
        for filter_instance in self.content_filters:
            try:
                filter_id = getattr(filter_instance, 'filter_id', 'none')
                pass
                # get parameter metadata to detect ranges
                try:
                    meta = {n: (d, lo, hi, has_mid) for n, d, lo, hi, has_mid in filter_instance._parse_parameter_defaults()}
                except Exception:
                    meta = {}

                for param_name, _ in filter_instance.get_parameters():
                    key = f"{filter_id}.{param_name}"
                    if key in values:
                        pass
                        try:
                            raw = float(values[key])
                        except Exception:
                            continue
                        # If stored value looks like legacy normalized [0,1] and
                        # the parameter range is different, map into new range
                        if param_name in meta:
                            _d, lo, hi = meta[param_name]
                            if 0.0 <= raw <= 1.0 and (lo != 0.0 or hi != 1.0):
                                mapped = lo + raw * (hi - lo)
                                values[key] = f"{mapped:.6f}"
                                filter_instance.set_parameter(param_name, mapped)
                                migrated = True
                                continue

                        # otherwise use the stored absolute value
                        filter_instance.set_parameter(param_name, raw)
            except Exception:
                continue
        # if any migration occurred, persist the updated values back
        if migrated:
            try:
                write_properties_file(self._content_filter_properties_path, values)
            except Exception:
                pass

    def _save_content_filter_parameter_values(self):
        values = {}
        for filter_instance in self.content_filters:
            try:
                filter_id = getattr(filter_instance, 'filter_id', 'none')
                for param_name, param_value in filter_instance.get_parameters():
                    key = f"{filter_id}.{param_name}"
                    values[key] = f"{float(param_value):.6f}"
            except Exception:
                continue
        write_properties_file(self._content_filter_properties_path, values)

    def _on_active_filter_parameter_changed(self):
        self._invalidate_trashbin_switch_mode()
        self._save_content_filter_parameter_values()
        self._update_filter_settings_action_state()
        try:
            if self.cutMode and hasattr(self, 'cropWidget') and self.cropWidget is not None and not self.isVideo:
                self.cropWidget.refresh_filtered_view()
        except Exception:
            pass
        try:
            # Also refresh main display preview when parameters change
            if not getattr(self, 'cutMode', False):
                self.refresh_filtered_view()
        except Exception:
            pass

    def _update_filter_settings_action_state(self):
        if not hasattr(self, 'filterSettingsAction'):
            return
        enabled = False
        try:
            enabled = len(self.active_content_filter.get_parameters()) > 0
        except Exception:
            enabled = False
        self.filterSettingsAction.setEnabled(enabled)

    def _build_filter_settings_icon(self, filter_instance: BaseImageFilter) -> QIcon:
        try:
            icon_name = getattr(filter_instance, 'icon_name', 'filter64_none.png') or 'filter64_none.png'
            base_path = os.path.join(path, '../../gui/img', icon_name)
            if not os.path.exists(base_path):
                base_path = os.path.join(path, '../../gui/img/filter64_none.png')

            gear_path = os.path.join(path, '../../gui/img/config64.png')

            base = QPixmap(base_path)
            if base.isNull():
                base = QPixmap(64, 64)
                base.fill(Qt.transparent)
            else:
                base = base.scaled(64, 64, Qt.KeepAspectRatioByExpanding, Qt.SmoothTransformation)

            composed = QPixmap(64, 64)
            composed.fill(Qt.transparent)
            painter = QPainter(composed)
            painter.setRenderHint(QPainter.Antialiasing)
            painter.setRenderHint(QPainter.SmoothPixmapTransform)
            painter.drawPixmap(0, 0, base)

            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor(0, 0, 0, 150))
            painter.drawEllipse(22, 22, 40, 40)

            gear = QPixmap(gear_path)
            if not gear.isNull():
                gear = gear.scaled(40, 40, Qt.KeepAspectRatio, Qt.SmoothTransformation)
                painter.drawPixmap(22, 22, gear)
            painter.end()

            return QIcon(composed)
        except Exception:
            return QIcon(os.path.join(path, '../../gui/img/config64.png'))

    def _update_filter_settings_action_icon(self):
        if not hasattr(self, 'filterSettingsAction'):
            return
        try:
            current = self.active_content_filter if hasattr(self, 'active_content_filter') else None
            if current is None:
                self.filterSettingsAction.setIcon(QIcon(os.path.join(path, '../../gui/img/config64.png')))
                return
            self.filterSettingsAction.setIcon(self._build_filter_settings_icon(current))
        except Exception:
            self.filterSettingsAction.setIcon(QIcon(os.path.join(path, '../../gui/img/config64.png')))

    def on_open_filter_settings(self, state=False):
        try:
            if not hasattr(self, 'active_content_filter') or self.active_content_filter is None:
                return
            self._filter_settings_menu = FilterParameterMenu(self, self.active_content_filter, self._on_active_filter_parameter_changed)

            anchor = None
            if hasattr(self, 'cutMode_toolbar') and self.cutMode_toolbar is not None and hasattr(self, 'filterSettingsAction'):
                anchor = self.cutMode_toolbar.widgetForAction(self.filterSettingsAction)

            if anchor is not None:
                pos = anchor.mapToGlobal(anchor.rect().bottomLeft())
                self._filter_settings_menu.popup(pos)
            else:
                cursor_pos = QCursor.pos()
                self._filter_settings_menu.popup(cursor_pos)
        except Exception:
            pass

    def apply_active_content_filter(self, image: Image.Image) -> Image.Image:
        if image is None:
            return image

        try:
            active_filter = self.active_content_filter
        except Exception:
            active_filter = self.content_filters[0] if self.content_filters else BaseImageFilter()

        if not isinstance(active_filter, BaseImageFilter):
            active_filter = self.content_filters[0] if self.content_filters else BaseImageFilter()

        if not self._is_filter_supported_for_current_content(active_filter):
            return image

        try:
            return active_filter.transform(image)
        except Exception:
            return image

    def _get_current_content_type(self) -> str:
        try:
            return BaseImageFilter.CONTENT_TYPE_VIDEO if bool(getattr(self, 'isVideo', False)) else BaseImageFilter.CONTENT_TYPE_IMAGE
        except Exception:
            return BaseImageFilter.CONTENT_TYPE_IMAGE

    def _get_filter_supported_content_types(self, filter_instance: BaseImageFilter):
        if not isinstance(filter_instance, BaseImageFilter):
            return []
        try:
            values = filter_instance.get_supported_content_types()
            if isinstance(values, (list, tuple, set)):
                return [str(v).strip().lower() for v in values if str(v).strip()]
        except Exception:
            pass
        return []

    def _get_filter_preview_supported_content_types(self, filter_instance: BaseImageFilter):
        if not isinstance(filter_instance, BaseImageFilter):
            return []
        try:
            values = filter_instance.get_preview_supported_content_types()
            if isinstance(values, (list, tuple, set)):
                return [str(v).strip().lower() for v in values if str(v).strip()]
        except Exception:
            pass
        return []

    def _is_filter_supported_for_current_content(self, filter_instance=None) -> bool:
        active = filter_instance if isinstance(filter_instance, BaseImageFilter) else getattr(self, 'active_content_filter', None)
        if not isinstance(active, BaseImageFilter):
            return False
        content_type = self._get_current_content_type()
        return content_type in self._get_filter_supported_content_types(active)

    def _is_filter_preview_supported_for_current_content(self, filter_instance=None) -> bool:
        active = filter_instance if isinstance(filter_instance, BaseImageFilter) else getattr(self, 'active_content_filter', None)
        if not isinstance(active, BaseImageFilter):
            return False
        content_type = self._get_current_content_type()
        return content_type in self._get_filter_preview_supported_content_types(active)

    def _pixmap_to_pil_rgba(self, pixmap: QPixmap):
        try:
            if pixmap is None or pixmap.isNull():
                return None
            image = pixmap.toImage()
            buffer = QBuffer()
            buffer.open(QIODevice.WriteOnly)
            image.save(buffer, "PNG")
            return Image.open(io.BytesIO(buffer.data())).convert("RGBA")
        except Exception:
            return None

    def apply_active_content_filter_to_pixmap(self, pixmap: QPixmap) -> QPixmap:
        if pixmap is None or pixmap.isNull():
            return pixmap

        if not self._is_filter_preview_supported_for_current_content():
            return pixmap

        try:
            # Ensure persisted properties are applied to the active filter instance
            try:
                props = read_properties_file(getattr(self, '_content_filter_properties_path', os.path.join(get_user_config_dir(), CONTENT_FILTER_PROPERTIES_FILENAME)))
            except Exception:
                props = {}
            try:
                fid = getattr(self.active_content_filter, 'filter_id', None) if hasattr(self, 'active_content_filter') else None
                if fid:
                    try:
                        for name, default, lo, hi, has_mid in getattr(self.active_content_filter, '_parse_parameter_defaults')():
                            key = f"{fid}.{name}"
                            if key in props:
                                try:
                                    val = float(props[key])
                                    self.active_content_filter.set_parameter(name, val)
                                except Exception:
                                    pass
                    except Exception:
                        # fallback: use get_parameters to iterate
                        try:
                            for name, _ in self.active_content_filter.get_parameters():
                                key = f"{fid}.{name}"
                                if key in props:
                                    try:
                                        val = float(props[key])
                                        self.active_content_filter.set_parameter(name, val)
                                    except Exception:
                                        pass
                        except Exception:
                            pass
            except Exception:
                pass

            # Debug: report active filter and parameter values when TRACELEVEL >= 3
            pass

            pil_image = self._pixmap_to_pil_rgba(pixmap)
            if pil_image is None:
                return pixmap
            filtered = self.apply_active_content_filter(pil_image)
            if not isinstance(filtered, Image.Image):
                return pixmap
            return pil2pixmap(filtered)
        except Exception:
            return pixmap

    def apply_active_content_filter_to_cv_frame(self, cv_frame):
        if cv_frame is None or getattr(cv_frame, "size", 0) == 0:
            return cv_frame

        if not self._is_filter_supported_for_current_content():
            return cv_frame

        try:
            rgb_image = cv2.cvtColor(cv_frame, cv2.COLOR_BGR2RGB)
            pil_image = Image.fromarray(rgb_image).convert("RGB")
            filtered = self.apply_active_content_filter(pil_image)
            if not isinstance(filtered, Image.Image):
                return cv_frame
            filtered_rgb = np.array(filtered.convert("RGB"), dtype=np.uint8)
            return cv2.cvtColor(filtered_rgb, cv2.COLOR_RGB2BGR)
        except Exception:
            return cv_frame

    def _show_frame_export_progress(self, total_frames: int):
        try:
            total = max(1, int(total_frames))
        except Exception:
            total = 1

        try:
            if self._frame_export_progress_dialog is not None and self._frame_export_progress_bar is not None:
                self._frame_export_progress_bar.setRange(0, total)
                self._frame_export_progress_bar.setValue(0)
                self._frame_export_progress_dialog.show()
                self._frame_export_progress_dialog.raise_()
                return

            dlg = QDialog(self)
            dlg.setModal(True)
            dlg.setWindowFlags(Qt.Dialog | Qt.CustomizeWindowHint | Qt.WindowTitleHint)
            dlg.setWindowTitle(" ")
            dlg.setMinimumWidth(380)
            dlg.setMaximumWidth(520)

            layout = QVBoxLayout()
            layout.setContentsMargins(16, 16, 16, 16)
            bar = QProgressBar(dlg)
            bar.setRange(0, total)
            bar.setValue(0)
            bar.setTextVisible(False)
            bar.setMinimumHeight(18)
            layout.addWidget(bar)
            dlg.setLayout(layout)

            self._frame_export_progress_dialog = dlg
            self._frame_export_progress_bar = bar

            dlg.show()
            dlg.raise_()
        except Exception:
            pass

    def _update_frame_export_progress(self, done_frames: int, total_frames: int):
        try:
            if self._frame_export_progress_dialog is None or self._frame_export_progress_bar is None:
                self._show_frame_export_progress(total_frames)

            if self._frame_export_progress_bar is None:
                return

            total = max(1, int(total_frames))
            done = max(0, min(int(done_frames), total))
            self._frame_export_progress_bar.setRange(0, total)
            self._frame_export_progress_bar.setValue(done)
        except Exception:
            pass

    def _hide_frame_export_progress(self):
        try:
            if self._frame_export_progress_dialog is not None:
                self._frame_export_progress_dialog.hide()
                self._frame_export_progress_dialog.deleteLater()
        except Exception:
            pass
        self._frame_export_progress_dialog = None
        self._frame_export_progress_bar = None

    def _update_content_filter_visibility(self):
        if not hasattr(self, 'filter_mode_spacing') or not hasattr(self, 'filter_mode_combo'):
            return
        has_active_file = self.currentIndex >= 0 and bool(self.currentFile) and self.loadingOk
        visible = self.cutMode and has_active_file
        self.filter_mode_spacing.setVisible(visible)
        self.filter_mode_combo.setVisible(visible)
        if hasattr(self, 'filter_settings_spacing'):
            self.filter_settings_spacing.setVisible(visible)
        if hasattr(self, 'filterSettingsAction'):
            self.filterSettingsAction.setVisible(visible)
        self._update_filter_settings_action_state()

    def onToggleInpaintMode(self, state):
        self._invalidate_trashbin_switch_mode()
        """Toggle the inpaint mode flag. UI state (checked) is handled by QAction.

        The actual inpaint behavior will be implemented later; for now we only
        maintain the boolean flag and expose it for other code to use.
        """
        # Guard: only allow enabling inpaint when in cut mode
        if not getattr(self, 'cutMode', False):
            # Ensure the action remains unchecked/disabled if not in cut mode
            try:
                self.inpaintModeAction.setChecked(False)
            except Exception:
                pass
            self.inpaint_mode = False
            if TRACELEVEL >= 2:
                print("Inpaint mode toggle ignored (not in cutMode)", flush=True)
            return

        try:
            self.inpaint_mode = bool(state)
        except Exception:
            self.inpaint_mode = False

        # Propagate state to CropWidget if present. CropWidget will implement the rest.
        try:
            if hasattr(self, 'cropWidget') and self.cropWidget is not None:
                # Prefer explicit setter if provided
                if hasattr(self.cropWidget, 'setInpaintMode') and callable(self.cropWidget.setInpaintMode):
                    self.cropWidget.setInpaintMode(self.inpaint_mode)
                else:
                    try:
                        self.cropWidget.inpaint_mode = self.inpaint_mode
                    except Exception:
                        setattr(self.cropWidget, 'inpaint_mode', self.inpaint_mode)
        except Exception:
            print(traceback.format_exc(), flush=True)

        if TRACELEVEL >= 1:
            print("Inpaint mode set to", self.inpaint_mode, flush=True)
        
    def show_manual(self, state):
        webbrowser.open('file://' + os.path.realpath(os.path.join(path, "../../docs/VR_We_Are_User_Manual.pdf")))

    def onUpdate(self):
        self.button_snapshot_from_video.setEnabled(self.isPaused and self.isVideo)
        if self.isPaused and self.isVideo:
            self.button_trima_video.setVisible(True)
            self.button_trimfirst_video.setVisible(False)
            self.button_trimb_video.setVisible(True)
            self.button_trimtosnap_video.setVisible(False)
        
    def onBlackout(self):
        if self.cutMode:
            self.button_trimfirst_video.setVisible(False)
            self.button_trimtosnap_video.setVisible(False)
            l = len(getFilesToRate())
            if l <= 0:
                self.display.onNoFiles()
                if self.sliderinitdone:
                    self.cropWidget.display_sliders(False)

            

    def showEvent(self, event):
        try:
            """Wird aufgerufen, wenn der Dialog angezeigt wird."""
            super().showEvent(event)
            
            # Stelle sicher, dass das Fenster den Fokus erhält
            self.activateWindow()
            self.raise_()

            # Setze den Fokus explizit auf ein Widget
            #self.button.setFocus(Qt.OtherFocusReason)
        except:
            print(traceback.format_exc(), flush=True)

    def keyPressEvent(self, event):
        global videoPauseRequested
        if event.key() == Qt.Key_S:
            if self.display.slider.isEnabled() and self.display.slider.isVisible():
                self.display.nextScene()
        elif event.key() == Qt.Key_P:
            if self.button_startpause_video.isEnabled() and self.button_startpause_video.isVisible():
                self.display.tooglePausePressed()
        elif event.key() == Qt.Key_F11:
            # Open current file (image or video) in the system default application
            try:
                # If Shift held, create a temporary cropped/trimmed/pingpong file and open that
                if int(event.modifiers()) & int(Qt.ShiftModifier):
                    try:
                        if getattr(self, 'isVideo', False):
                            if hasattr(self, 'button_startpause_video') and self.button_startpause_video.isEnabled() and self.button_startpause_video.isVisible():
                                if not self.display.isPaused():
                                    if not videoPauseRequested:
                                        videoPauseRequested = True
                                        startAsyncTask()
                                    self.display.tooglePausePressed()
                    except Exception:
                        print(traceback.format_exc(), flush=True)
                    try:
                        self._create_temp_and_open()
                    except Exception:
                        print(traceback.format_exc(), flush=True)
                    return

                if self.currentFile:
                    # If current file is a video, ensure playback is paused first
                    try:
                        if getattr(self, 'isVideo', False):
                            if hasattr(self, 'button_startpause_video') and self.button_startpause_video.isEnabled() and self.button_startpause_video.isVisible():
                                if not self.display.isPaused():
                                    if not videoPauseRequested:
                                        videoPauseRequested = True
                                        startAsyncTask()
                                    self.display.tooglePausePressed()
                    except Exception:
                        # don't block opening if pause check fails
                        print(traceback.format_exc(), flush=True)

                    if cutModeFolderOverrideActive:
                        folder = cutModeFolderOverridePath
                    else:
                        folder = os.path.join(path, "../../../../input/vr/check/rate")
                    fullpath = os.path.abspath(os.path.join(folder, self.currentFile))
                    if os.path.exists(fullpath):
                        open_with_default_app(fullpath)
                    else:
                        # Fallback: try as absolute path or relative to module path
                        if os.path.isabs(self.currentFile) and os.path.exists(self.currentFile):
                            open_with_default_app(self.currentFile)
                        else:
                            alt = os.path.abspath(os.path.join(path, self.currentFile))
                            if os.path.exists(alt):
                                open_with_default_app(alt)
            except Exception:
                print(traceback.format_exc(), flush=True)
                
        if self.cutMode:
            if event.key() == Qt.Key_A:
                if self.button_trima_video.isEnabled() and self.button_trima_video.isVisible():
                    self.display.trimA()
            elif event.key() == Qt.Key_D:
                if self.button_trimb_video.isEnabled() and self.button_trimb_video.isVisible():
                    self.display.trimB()
            elif event.key() == Qt.Key_1:
                if self.button_trimfirst_video.isEnabled() and self.button_trimfirst_video.isVisible():
                    self.trimFirst()
            elif event.key() == Qt.Key_U:
                if self.display.slider.isEnabled() and self.display.slider.isVisible() and not self.display.slider.hasFocus():
                    self.display.slider.setFocus()
            elif event.key() == Qt.Key_PageUp or event.key() == Qt.Key_PageDown:
                if self.display.slider.isEnabled() and self.display.slider.isVisible():
                    if self.button_startpause_video.isEnabled() and self.button_startpause_video.isVisible():
                        if not self.display.isPaused():
                            if not videoPauseRequested:
                                videoPauseRequested=True
                                startAsyncTask()
                            self.display.tooglePausePressed()
                        else:
                            pass
                    if not self.display.slider.hasFocus():
                        self.display.slider.setFocus()
            #elif event.key() == Qt.Key_:
            #    if self.button_snapshot_from_video.isEnabled() and self.button_snapshot_from_video.isVisible():
            #        self.createSnapshot()
        else:
            if event.key() == Qt.Key_1:
                self.rating_widget.rate(1)
            elif event.key() == Qt.Key_2:
                self.rating_widget.rate(2)
            elif event.key() == Qt.Key_3:
                self.rating_widget.rate(3)
            elif event.key() == Qt.Key_4:
                self.rating_widget.rate(4)
            elif event.key() == Qt.Key_5:
                self.rating_widget.rate(5)
        event.accept()

    def uiBlockHandling(self):
        try:
            if not self.uiBlocking == isTaskActive():
                self.uiBlocking = isTaskActive()
                if self.uiBlocking:
                    if TRACELEVEL >= 3:
                        print("uiBlockHandling - WaitCursor", flush=True)                
                    QApplication.setOverrideCursor(Qt.WaitCursor)
                    #self.setEnabled(False)
                    if self._blocker is None:
                        self._blocker = InputBlocker(self)                
                else:
                    QApplication.restoreOverrideCursor()
                    if TRACELEVEL >= 3:
                        print("uiBlockHandling - RestoreCursor", flush=True)                
                    self.setEnabled(True)
                    if self._blocker:
                        self._blocker.deleteLater()
                        self._blocker = None
            if needsWaitDialog() and self.wait_dialog is None:
                if TRACELEVEL >= 3:
                    print("uiBlockHandling - show wait dialog", flush=True)                
                self.wait_dialog = WaitDialog(self)
                self.wait_dialog.show()
            elif not needsWaitDialog() and not self.wait_dialog is None:
                if TRACELEVEL >= 3:
                    print("uiBlockHandling - remove wait dialog", flush=True)                
                self.wait_dialog.accept()  
                self.wait_dialog = None
        except KeyboardInterrupt:
            pass
        except:
            print(traceback.format_exc(), flush=True)


    def logn(self, msg, color):
        self.log(msg, color)
        self.msgWidget.insertPlainText("\n");
        
    def log(self, msg, color):
        self.msgWidget.moveCursor (QTextCursor.End)
        old_format = self.msgWidget.currentCharFormat()
        color_format = self.msgWidget.currentCharFormat()
        color_format.setForeground(color)
        self.msgWidget.setCurrentCharFormat(color_format)
        self.msgWidget.insertPlainText(msg);
        self.msgWidget.setCurrentCharFormat(old_format)

    def closeEvent(self, evnt):
        self.filebutton_timer.stop()
        self.display.stopAndBlackout()
        global cutModeActive
        cutModeActive=False
        setFileFilter(False, False, False)
        rescanFilesToRate()
        # Force-remove any temp files now that dialog is closing.
        try:
            cleanup_temps(1)
        except Exception:
            pass
        super(QDialog, self).closeEvent(evnt)
            
    def updatePaused(self, isPaused):
        self.isPaused = isPaused
        if self.cutMode:
            self.button_trima_video.setEnabled(isPaused)
            self.button_trimb_video.setEnabled(isPaused)
            self.button_snapshot_from_video.setEnabled(isPaused and self.isVideo)
        self.button_startpause_video.setIcon(QIcon(os.path.join(path, '../../gui/img/pause80.png') if isPaused else os.path.join(path, '../../gui/img/play80.png') ))

        self.filebutton_timer.timeout.connect(self.update_filebuttons)
        if not self.isPaused:
            self.button_startpause_video.setFocus()

    def truncate_keep_suffix(self, filename: str, max_length: int = 100) -> str:
        root, ext = os.path.splitext(filename)
        if len(filename) <= max_length:
            return filename
        cutoff = max_length - len(ext) - 1  # Platz für '~' + Suffix
        return root[:cutoff] + "~" + ext
        
    def fileSliderDragStart(self):
        global fileDragged
        fileDragged=True
        self.fileLabel.setStyleSheet("QLabel { background-color : black; color : grey; }");
        self.display.stopAndBlackout()

    def fileSliderDragged(self):
        index=self.sender().value()
        if index!=self.currentIndex and index>=1 and index<=len(getFilesToRate()):
            lastIndex=len(getFilesToRate())
            self.fileDragIndex=index
            self.fileLabel.setText(str(index)+" of "+str(lastIndex))
            self.main_group_box.setTitle(self.truncate_keep_suffix(getFilesToRate()[index-1]))
            self.display.updatePreview( getFilesToRate()[index-1] )

    def fileSliderChanged(self):
        index=self.fileDragIndex
        self.display.hidePreview()
        if index!=self.currentIndex and index>=1 and index<=len(getFilesToRate()):
            #print("fileSliderChanged to", str(index+1)+" of "+str(len(getFilesToRate())), flush=True)
            self.fileLabel.setStyleSheet("QLabel { background-color : black; color : white; }");
            self.currentIndex=index
            self.currentFile=getFilesToRate()[index-1]
            self.rateCurrentFile()


    def onRectSelected(self, rect):
        self._invalidate_trashbin_switch_mode()
        if self.cutMode:
            self.cropWidget.setSliderValuesToRect(rect)

    def onCropOrTrim(self):
        self._invalidate_trashbin_switch_mode()
        self.hasCropOrTrim=True
        if self.cutMode:
            self.button_cutandclone.setEnabled(True)
            self.button_snapshot_from_video.setEnabled(self.isPaused and self.isVideo)

    def _has_active_non_default_filter(self) -> bool:
        try:
            combo_index = -1
            try:
                if hasattr(self, 'filter_mode_combo') and self.filter_mode_combo is not None:
                    combo_index = int(self.filter_mode_combo.currentIndex())
                elif hasattr(self, 'content_filter_mode'):
                    combo_index = int(self.content_filter_mode)
            except Exception:
                combo_index = -1

            active_filter = self.active_content_filter
            if not isinstance(active_filter, BaseImageFilter):
                return combo_index > 0

            if not self._is_filter_supported_for_current_content(active_filter):
                return False

            filter_id = str(getattr(active_filter, 'filter_id', 'none')).strip().lower()
            if filter_id and filter_id != 'none':
                return True

            class_name = type(active_filter).__name__.strip().lower()
            if class_name != 'baseimagefilter':
                return True

            return combo_index > 0
        except Exception:
            return False

    def _activate_custom_override_for_file(self, file_path: str):
        try:
            global cutModeFolderOverrideActive, cutModeFolderOverridePath
            target_dir = os.path.abspath(os.path.dirname(os.path.abspath(file_path)))
            if not os.path.isdir(target_dir):
                return False
            cutModeFolderOverridePath = target_dir
            cutModeFolderOverrideActive = True
            if hasattr(self, 'folderAction') and self.folderAction is not None:
                self.folderAction.setChecked(True)
                self.folderAction.setEnabled(True)
            if hasattr(self, 'dirlabel') and self.dirlabel is not None:
                self.dirlabel.setText(target_dir)
            return True
        except Exception:
            return False

    def _set_trashbin_switch_mode(self, enabled: bool, original_input=None, switched_input=None):
        self._trashbin_switch_active = bool(enabled)
        if self._trashbin_switch_active:
            self._trashbin_switch_original_input = os.path.abspath(str(original_input)) if original_input else None
            self._trashbin_switch_switched_input = os.path.abspath(str(switched_input)) if switched_input else None
        else:
            self._trashbin_switch_original_input = None
            self._trashbin_switch_switched_input = None

        try:
            self.button_delete_file.setIcon(self.icon_delete_switch if self._trashbin_switch_active else self.icon_delete_default)
            self.button_delete_file.update()
            self.button_delete_file.repaint()
        except Exception:
            pass

    def _invalidate_trashbin_switch_mode(self):
        if getattr(self, '_trashbin_switch_active', False):
            self._set_trashbin_switch_mode(False)

    def _as_current_file_reference(self, file_path: str) -> str:
        candidate = os.path.abspath(file_path)
        if cutModeFolderOverrideActive:
            base_folder = os.path.abspath(cutModeFolderOverridePath)
        else:
            base_folder = os.path.abspath(os.path.join(path, "../../../../input/vr/check/rate"))
        try:
            rel = os.path.relpath(candidate, base_folder)
            if not rel.startswith(".."):
                return rel.replace('\\', '/')
        except Exception:
            pass
        return candidate

    def _trash_single_file(self, file_path: str):
        capfile = replace_file_suffix(file_path, ".txt")
        if USE_TRASHBIN:
            self.log("Trashing " + os.path.basename(file_path), QColor("white"))
            send2trash.send2trash(file_path)
            if os.path.exists(capfile):
                send2trash.send2trash(capfile)
        else:
            self.log("Deleting " + os.path.basename(file_path), QColor("white"))
            os.remove(file_path)
            if os.path.exists(capfile):
                os.remove(capfile)

        if os.path.exists(file_path):
            self.logn(" failed", QColor("red"))
        else:
            self.logn(" done", QColor("green"))

    def on_delete_button_clicked(self):
        if getattr(self, '_trashbin_switch_active', False):
            self.deleteAndSwitchThenTrash()
        else:
            self.deleteAndNext()

    def deleteAndSwitchThenTrash(self):
        self.sliderinitdone=True
        enterUITask()
        try:
            original_input = self._trashbin_switch_original_input
            switched_input = self._trashbin_switch_switched_input
            self._set_trashbin_switch_mode(False)

            if not original_input or not switched_input:
                self.deleteAndNext()
                return

            if os.path.exists(switched_input):
                self._activate_custom_override_for_file(switched_input)
                rescanFilesToRate()
                self.currentFile = os.path.basename(switched_input)
                self.rateCurrentFile()

            if os.path.exists(original_input):
                self._trash_single_file(original_input)
                rescanFilesToRate()
            else:
                self.logn(" not found", QColor("red"))

            self.button_delete_file.setFocus()
        except Exception:
            print(traceback.format_exc(), flush=True)
        finally:
            leaveUITask()

    def update_filebuttons(self):
        self._update_content_filter_visibility()
        if self.currentIndex<0 or not self.loadingOk:
            l = len(getFilesToRate())
            #print("currentIndex-<0", l, flush=True)
            if self.currentIndex<0 and l > 0:
                #print("reset currentIndex=0", l, flush=True)
                self.currentIndex=0
                self.currentFile=getFilesToRate()[0]
                self.rateCurrentFile()
                return
            else:
                if self.cutMode:
                    self.button_snapshot_from_video.setVisible(False)
                    self.button_trima_video.setVisible(False)
                    self.button_trimb_video.setVisible(False)
                    self.cropWidget.display_sliders(False)
                    self.button_cutandclone.setVisible(False)
                    self.button_startframe.setVisible(False)
                    self.button_endframe.setVisible(False)
                else:
                    self.rating_widget.setVisible(False)
                    self.button_return2edit.setVisible(False)
                self.button_startpause_video.setVisible(False)
                self.sl.setVisible(False)
                self.button_justrate_compress.setVisible(False)
                self.button_prev_file.setVisible(self.currentIndex>=0)
                self.button_next_file.setVisible(self.currentIndex>=0)
                self.button_delete_file.setVisible(self.currentIndex>=0)
                self.fileSlider.setVisible(self.currentIndex>=0)
        else:
            if self.cutMode:
                self.cropWidget.display_sliders(not fileDragged)
                self.button_cutandclone.setVisible(True)
                self.button_cutandclone.setEnabled(not fileDragged)
                if not self.isVideo:
                    self.button_trima_video.setVisible(False)
                    self.button_trimfirst_video.setVisible(False)
                    self.button_trimb_video.setVisible(False)
                    self.button_trimtosnap_video.setVisible(False)
                else:
                    self.button_trimb_video.setVisible(not fileDragged)
                self.button_snapshot_from_video.setVisible(self.isVideo and not fileDragged)
                self.button_startframe.setVisible(self.isVideo and not fileDragged)
                self.button_endframe.setVisible(self.isVideo and not fileDragged)
                self.sceneFinderAction.setVisible(self.isVideo and not fileDragged)
            else:
                self.sceneFinderAction.setVisible(False)
                self.rating_widget.setVisible(not fileDragged)
                self.button_return2edit.setVisible(not fileDragged)
                self.button_return2edit.setEnabled("/" in self.currentFile)
            self.sl.setVisible(self.isVideo and not fileDragged)
            self.button_startpause_video.setVisible(self.isVideo and not fileDragged)
            self.button_justrate_compress.setVisible(True)
            self.button_justrate_compress.setEnabled(not fileDragged)
            self.button_prev_file.setVisible(True)
            self.button_prev_file.setEnabled(not fileDragged)
            self.button_next_file.setVisible(True)
            self.button_next_file.setEnabled(not fileDragged)
            self.button_delete_file.setVisible(True)
            self.button_delete_file.setEnabled(not fileDragged)
            self.fileSlider.setVisible(True)
            
        index=-1
        try:
            if self.currentFile:
                lastIndex=len(getFilesToRate())
                self.fileSlider.setMaximum(lastIndex)
                try:
                    index=getFilesToRate().index(self.currentFile)+1
                except ValueError as ve:
                    pass
        except StopIteration as e:
            pass
        self.button_prev_file.setEnabled(not fileDragged and index>1)
        self.button_next_file.setEnabled(not fileDragged and index>0 and index<lastIndex)
        if index>0:
            if not fileDragged:
                self.fileLabel.setText(str(index)+" of "+str(lastIndex))
        else:
            if not fileDragged:
                self.fileLabel.setText("")
            if self.cutMode:
                self.button_trima_video.setEnabled(False)
                self.button_trimb_video.setEnabled(False)
                self.button_snapshot_from_video.setEnabled(False)
                self.button_cutandclone.setEnabled(False)
            self.button_delete_file.setEnabled(False)       

        self.pasteImageFromClipboardAction.setEnabled(self.clipboard_has_image)


    def trimFirst(self):
        self.button_trimfirst_video.setVisible(False)
        self.button_trima_video.setVisible(self.isVideo)
        self.display.trimFirst()

    def trimToSnap(self):
        self.button_trimtosnap_video.setVisible(False)
        self.button_trimb_video.setVisible(self.isVideo)
        self.display.trimToSnap()
        self.display.posB()

    def deleteAndNext(self):
        self.sliderinitdone=True
        enterUITask()
        try:
            self._invalidate_trashbin_switch_mode()
            
            files=getFilesToRate()
            try:
                index=files.index(self.currentFile)
                if cutModeFolderOverrideActive:
                    folder=cutModeFolderOverridePath
                else:
                    folder=os.path.join(path, "../../../../input/vr/check/rate")
                input=os.path.abspath(os.path.join(folder, self.currentFile))
            except ValueError as ve:
                index=0
                self.currentIndex=index
                self.currentFile=files[index]
                self.rateCurrentFile()
                print(traceback.format_exc(), flush=True)                
                return
            
            if os.path.isfile(input):
                try:
                    self.display.stopAndBlackout()
                    
                    if index>=0:
                        self._trash_single_file(input)
                        files=rescanFilesToRate()

                    
                    l=len(files)

                    if l==0:    # last file deleted?
                        self.closeOnError("last file deleted (deleteAndNext)")
                        return

                    if index>=l:
                        index=l-1
                        
                    self.currentFile=files[index]
                    self.currentIndex=index
                    self.rateCurrentFile()

                    
                except Exception as any_ex:
                    print(traceback.format_exc(), flush=True)                
                    self.logn(" failed", QColor("red"))
            else:
                self.logn(" not found", QColor("red"))
        except:
            print(traceback.format_exc(), flush=True)
        finally:
            leaveUITask()

    def rateNext(self):
        enterUITask()
        try:

            if self.cutMode:
                self.button_justrate_compress.setEnabled(True)
                self.button_justrate_compress.setIcon(self.icon_justrate)
                self.justRate=True
            else:
                self.button_justrate_compress.setEnabled(True)
                self.button_justrate_compress.setIcon(self.icon_compress)
                self.justRate=False

            files=getFilesToRate()
            if len(files)==0:
                self.closeOnError("no files (rateNext)")
                return
                
            if self.currentFile is None:
                self.currentIndex=0
                self.currentFile=files[self.currentIndex]
            else:
                try:
                    index=files.index(self.currentFile)
                    self.currentIndex=index
                    l=len(files)
                    if l>index+1:
                        self.currentIndex=index+1
                        self.currentFile=files[self.currentIndex]
                    else:
                        self.currentIndex=l-1
                        self.currentFile=files[self.currentIndex]
                except ValueError as ve:
                    self.currentIndex=len[files]-1
                    self.currentFile=files[self.currentIndex]
            
            self.rateCurrentFile()
        
        except:
            print(traceback.format_exc(), flush=True)
        finally:
            leaveUITask()
            
    def ratePrevious(self):
        enterUITask()
        try:
            if self.cutMode:
                self.button_justrate_compress.setEnabled(True)
                self.button_justrate_compress.setIcon(self.icon_justrate)
                self.justRate=True
            else:
                self.button_justrate_compress.setEnabled(True)
                self.button_justrate_compress.setIcon(self.icon_compress)
                self.justRate=False
            
            files=getFilesToRate()
            if len(files)==0:
                self.currentIndex=0
                self.display.stopAndBlackout()
                return
                
            if self.currentFile is None:
                self.currentIndex=0
                self.currentFile=files[self.currentIndex]
            else:
                try:
                    index=files.index(self.currentFile)
                    self.currentIndex=index
                    l=len(files)
                    if index>=1:
                        self.currentIndex=index-1
                        self.currentFile=files[self.currentIndex]
                    else:
                        self.currentIndex=0
                        self.currentFile=files[self.currentIndex]
                except ValueError as ve:
                    self.currentIndex=0
                    self.currentFile=files[self.currentIndex]
            
            self.rateCurrentFile()
            self.button_prev_file.setFocus()
        except:
            print(traceback.format_exc(), flush=True)
        finally:
            leaveUITask()

        
    def rateCurrentFile(self):
        enterUITask()
        try:
            QApplication.setOverrideCursor(Qt.WaitCursor)
            global fileDragged
            try:
                current_file_key = str(self.currentFile) if self.currentFile is not None else None
                if current_file_key != self._last_loaded_file_for_switch:
                    self._invalidate_trashbin_switch_mode()
                self._last_loaded_file_for_switch = current_file_key
            except Exception:
                self._invalidate_trashbin_switch_mode()
            if self.currentIndex>=0:
                self.loadingOk = True
                self.fileSlider.setValue(self.currentIndex)
                self.fileSlider.setEnabled(True)
                self.main_group_box.setTitle( self.truncate_keep_suffix(self.currentFile) )
                self.enable_drag_for_groupbox(self.main_group_box, )
                if cutModeFolderOverrideActive:
                    folder=os.path.join(path, cutModeFolderOverridePath)
                else:
                    folder=os.path.join(path, "../../../../input/vr/check/rate")
                file_path=os.path.abspath(os.path.join(folder, self.currentFile))

                previous_loaded_path = str(getattr(self, '_last_loaded_content_path', '') or '')
                current_target_path = str(file_path or '')
                if previous_loaded_path != current_target_path:
                    self._reset_content_filter_selection()

                if os.path.exists(file_path):
                    self.isVideo=self.display.showFile( file_path ) == "video"
                    self._last_loaded_content_path = current_target_path
                    try:
                        self._apply_content_filter_list_for_content_type(self._get_current_content_type())
                    except Exception:
                        pass
                    self.button_startpause_video.setVisible(self.isVideo)
                    self.sl.setVisible(self.isVideo)
                    fileDragged=False
                    self.hasCropOrTrim=False
                    # Zusatz: Falls Pixmap nach Laden noch leer ist, einen verzögerten Refresh anstoßen
                    try:
                        pm = self.display.pixmap()
                        if pm is None or pm.isNull() or pm.width() == 0 or pm.height() == 0:
                            QTimer.singleShot(120, self.display._refresh_after_load)
                    except Exception:
                        pass
                else:
                    print("Error: File does not exist (rateCurrentFile): "  + file_path, flush=True)
                    self.isVideo = False
                    self._last_loaded_content_path = None
                    try:
                        self._apply_content_filter_list_for_content_type(self._get_current_content_type())
                    except Exception:
                        pass
                    fileDragged=False
                    self.hasCropOrTrim=False
                    self.button_startpause_video.setVisible(False)
                    self.sl.setVisible(False)
                self.button_delete_file.setEnabled(True)
                    
            if self.currentIndex<0:
                self.fileSlider.setEnabled(False)
                self.main_group_box.setTitle( "" )
                self.isVideo = False
                self._last_loaded_content_path = None
                try:
                    self._apply_content_filter_list_for_content_type(self._get_current_content_type())
                except Exception:
                    pass
                fileDragged=False
                self.hasCropOrTrim=False
                self.button_startpause_video.setVisible(False)
                self.sl.setVisible(False)
                self.display.stopAndBlackout()
                if self.cutMode:
                    self.cropWidget.display_sliders(False)
                
            if self.cutMode:
                self.button_trima_video.setVisible(self.isVideo)
                self.button_trimb_video.setVisible(self.isVideo)
                self.button_startframe.setVisible(self.isVideo)
                self.button_endframe.setVisible(self.isVideo)
                self.button_snapshot_from_video.setVisible(self.isVideo)
                self._update_content_filter_visibility()
                self.button_trima_video.setEnabled(False)
                self.button_trimb_video.setEnabled(False)
                self.button_cutandclone.setEnabled(False)
                self.button_snapshot_from_video.setEnabled(False)
                self.button_justrate_compress.setEnabled(True)
                self.button_justrate_compress.setIcon(self.icon_justrate)
                self.inpaintModeAction.setEnabled(not self.isVideo)
                self.inpaintModeAction.setChecked(False)
                self.inpaint_mode=False
                self.cropWidget.setInpaintMode(False)
                self.justRate=True

            else:
                self.button_justrate_compress.setEnabled(True)
                self.button_justrate_compress.setIcon(self.icon_compress)
                self.justRate=False
                
        except:
            print(traceback.format_exc(), flush=True)
        finally:
            QApplication.restoreOverrideCursor()
            leaveUITask()

    def onPlayTypeAction(self, state):
        self.playtype_pingpong = state
        self.iconPlayTypeAction.setIcon(self.toggle_playtype_icon_true if self.playtype_pingpong else self.toggle_playtype_icon_false)
        self.display.setPingPongModeEnabled(self.playtype_pingpong)
        
    def onFilterImg(self, state):
        self.filter_img = state
        self.filterImgAction.setIcon(self.toggle_filterimg_icon_true if self.filter_img else self.toggle_filterimg_icon_false)
        setFileFilter(self.filter_img, self.filter_vid, self.filter_edit)
        if self.filter_img and self.filter_vid:
            self.filterVidAction.setChecked(False)
            self.onFilterVid(False)
        else:
            rescanFilesToRate()
            self.currentFile=None
            self.currentIndex=0
            self.rateNext()
    
    def onFilterVid(self, state):
        self.filter_vid = state
        self.filterVidAction.setIcon(self.toggle_filtervid_icon_true if self.filter_vid else self.toggle_filtervid_icon_false)
        setFileFilter(self.filter_img, self.filter_vid, self.filter_edit)
        if self.filter_img and self.filter_vid:
            self.filterImgAction.setChecked(False)
            self.onFilterImg(False)
        else:
            rescanFilesToRate()
            self.currentFile=None
            self.currentIndex=0
            self.rateNext()
    
    def onFilterEdit(self, state):
        self.filter_edit = state
        self.filterEditAction.setIcon(self.toggle_filteredit_icon_true if self.filter_edit else self.toggle_filteredit_icon_false)
        setFileFilter(self.filter_img, self.filter_vid, self.filter_edit)
        rescanFilesToRate()
        self.currentFile=None
        self.currentIndex=0
        self.rateNext()
        
    def onCopyFilepathToClipboard(self, state):
        cb = QApplication.clipboard()
        cb.clear(mode=cb.Clipboard)
        if self.currentIndex >= 0:
            if cutModeFolderOverrideActive:
                folder=cutModeFolderOverridePath
            else:
                folder=os.path.join(path, "../../../../input/vr/check/rate")
            filepath=os.path.abspath(os.path.join(folder, self.currentFile))
            cb.setText(filepath, mode=cb.Clipboard)
        
    def onPasteImageFromClipboard(self, state):
        self.save_clipboard_image()
        
    def onOpenFolder(self, state):
        if cutModeFolderOverrideActive:
            dirPath=cutModeFolderOverridePath
        else:
            dirPath=srcfolder=os.path.join(path, "../../../../input/vr/check/rate")
        os.system("start \"\" " + os.path.abspath(dirPath))
        # subprocess.Popen(["explorer", os.path.abspath(dirPath) ], close_fds=True) - generates zombies
         
    def onOpenArchive(self, state):
        dirPath=srcfolder=os.path.join(path, "../../../../input/vr/check/rate/done")
        os.system("start \"\" " + os.path.abspath(dirPath))
        # subprocess.Popen(["explorer", os.path.abspath(dirPath) ], close_fds=True) - generates zombies
        
    def onOpenEdit(self, state):
        """Open the edit subfolder of the current input folder in Explorer."""
        dirPath=srcfolder=os.path.join(path, "../../../../input/vr/check/rate/edit")
        os.system("start \"\" " + os.path.abspath(dirPath))
         
    def onSelectFolder(self, state):
        enterUITask()
        self.folderAction.setEnabled(False)
        try:
            global _cutModeFolderOverrideFiles, cutModeFolderOverrideActive, cutModeFolderOverridePath
            
            self.display.stopAndBlackout()
            
            if cutModeFolderOverrideActive:
                dirpath=""
                cutModeFolderOverrideActive=False
                rescanFilesToRate()
                files=getFilesToRate()
                if len(files)>0:
                    self.currentIndex=0
                    self.currentFile=files[self.currentIndex]
                else:
                    self.currentIndex=-1
                    self.currentFile=""
            else:
                dirpath = str(QFileDialog.getExistingDirectory(self, "Select Directory", cutModeFolderOverridePath, QFileDialog.ShowDirsOnly | QFileDialog.DontResolveSymlinks))
                cutModeFolderOverrideActive=True

            thread = threading.Thread(
                target=self.customfolder_worker,
                args=( cutModeFolderOverrideActive, dirpath, ),
                daemon=True
            )
            thread.start()
        except KeyboardInterrupt:
            pass
        except:
            print(traceback.format_exc(), flush=True)
            self.folderAction.setEnabled(True)
        finally:
            leaveUITask()

    def customfolder_worker(self, override, dirpath):
        global _cutModeFolderOverrideFiles, cutModeFolderOverrideActive, cutModeFolderOverridePath
        startAsyncTask()
        try:
            if override:
                if os.path.isdir(dirpath):
                    cutModeFolderOverridePath=dirpath
                    cutModeFolderOverrideActive=True
                else:
                    print(f"not a directory: {dirpath}", flush=True)
                    override=False
                    cutModeFolderOverrideActive=False   # cancel
                    dirpath=""                    
            else:
                dirpath=""
                
            scanFilesToRate()   # can block on some drives

            QTimer.singleShot(0, partial(self.customfolder_updater, override, dirpath))
        except:
            print(traceback.format_exc(), flush=True) 

    def customfolder_updater(self, override, dirpath):

        global _cutModeFolderOverrideFiles, cutModeFolderOverrideActive, cutModeFolderOverridePath
        try:
            if len(_cutModeFolderOverrideFiles)>0:
                files=getFilesToRate()
                self.currentIndex=0
                self.currentFile=files[self.currentIndex]
            else:
                self.currentIndex=-1
            self.rateCurrentFile()
        except:
            print(traceback.format_exc(), flush=True) 
        finally:
            if hasattr(self, 'folderAction') and self.folderAction is not None:
                self.folderAction.setChecked(override)
                self.folderAction.setEnabled(True)
            if hasattr(self, 'dirlabel') and self.dirlabel is not None:
                self.dirlabel.setText(dirpath)
            endAsyncTask()
 
    def on_rating_changed(self, rating):
        enterUITask()
        try:
            self.display.stopAndBlackout()

            if TRACELEVEL >= 1:
                print(f"Rating selected: {rating}", flush=True)

            files=getFilesToRate()

            index=files.index(self.currentFile)
            name=self.currentFile
            folder_in=os.path.join(path, "../../../../input/vr/check/rate")
            folder_out=os.path.join(path, f"../../../../output/vr/check/rate/{rating}")
            os.makedirs(folder_out, exist_ok = True)
            input=os.path.abspath(os.path.join(folder_in, name))
                
            try:
                idx = name.index('/')
                output=os.path.abspath(os.path.join(folder_out, replaceSomeChars(name[idx+1:])))
            except ValueError as ve:                
                output=os.path.abspath(os.path.join(folder_out, replaceSomeChars(name)))
            
            #print("index"  , index, self.currentFile, flush=True)
            
            if os.path.isfile(input):
                self.log(f"Rated {rating} on " + name, QColor("white"))
                recreated=os.path.isfile(output)
                if recreated:
                    os.remove(output)
                os.rename(input, output)
                capfile = replace_file_suffix(input, ".txt")
                if os.path.exists(capfile):
                    os.rename(capfile, replace_file_suffix(output, ".txt"))
                
                self.rating_widget.clear_rating()
                self.log(" Overwritten" if recreated else " Moved", QColor("green"))
                
                try:
                    files=rescanFilesToRate()
                    l=len(files)
                    #print("rescanFilesToRate: len =", l, flush=True)

                    if l==0:    # last file deleted?
                        index=-1
                        self.currentFile=None
                    elif index>=l:
                        index=l-1
                        self.currentFile=files[index]
                    else:
                        self.currentFile=files[index]
                    self.currentIndex=index
                    self.rateCurrentFile()
                except Exception:
                    print(traceback.format_exc(), flush=True) 
                
                # Optional task: Exiftool
                if not self.exifpath is None:
                    # https://exiftool.org/forum/index.php?topic=6591.msg32875#msg32875
                    
                    rating_percent_values = [0, 1, 25,50, 75, 99]   # mp4
                    cmd = self.exifpath + f" -xmp:rating={rating} -SharedUserRating={rating_percent_values[rating]}" + " -overwrite_original \"" + output + "\""
                    thread = threading.Thread(
                        target=self.updateExif_worker,
                        args=(cmd,),
                        daemon=True
                    )                            
                    thread.start()

        except:
            print(traceback.format_exc(), flush=True)
        finally:
            leaveUITask()

    def updateExif_worker(self, cmd):
        startAsyncTask()
        try:
            cp = subprocess.run(cmd, shell=True, check=True, close_fds=True)
            QTimer.singleShot(0, partial(self.updateExif_updater, True, cmd))
        except subprocess.CalledProcessError as se:
            print(traceback.format_exc(), flush=True) 
            QTimer.singleShot(0, partial(self.updateExif_updater, False, cmd))
        except:
            print(traceback.format_exc(), flush=True)                
            endAsyncTask()


    def updateExif_updater(self, success, cmd):
        if success:
            self.logn(",Rated.", QColor("green"))
        else:
            self.logn(" Failed", QColor("red"))
            print("Failed: "  + cmd, flush=True)
        endAsyncTask()
    
    def sceneFinder_worker(self, pathtofile, threshold):
        startAsyncTask()
        tmp = tempfile.NamedTemporaryFile(delete=False)
        tmp.close()
        out = tempfile.NamedTemporaryFile(delete=False)
        out.close()
        try:
            cmd1 = "ffmpeg.exe -hide_banner -y -i \"" + pathtofile + "\" -filter:v \"select='gt(scene,"  + str(threshold) + ")',showinfo\" -f null - 2>> "+tmp.name
            cmd2 = "grep showinfo \"" + tmp.name + "\" | grep pts_time:[0-9.]\\* -o | grep [0-9.]\\* -o >> " + out.name

            if TRACELEVEL >= 3:
                print("Executing", cmd1, flush=True)
            cp = subprocess.run(cmd1, shell=True, check=True, close_fds=True)
            time.sleep(1)   
            if TRACELEVEL >= 3:
                print("Executing", cmd2, flush=True)
            cp = subprocess.run(cmd2, shell=True, check=False, close_fds=True)
            
            QTimer.singleShot(0, partial(self.sceneFinder_updater, pathtofile, tmp.name, out.name))
        except subprocess.CalledProcessError as se:
            print(traceback.format_exc(), flush=True) 
            os.unlink(tmp.name)
            os.unlink(out.name)
            endAsyncTask()
        except:
            print(traceback.format_exc(), flush=True)
            os.unlink(tmp.name)
            os.unlink(out.name)
            endAsyncTask()

    def sceneFinder_updater(self, pathtofile, tmpfilename, outfilename):
        scene_intersections=[]
        try:
            with open(outfilename) as file:
                while line := file.readline():
                    try:
                        scene_intersections.append(float(line.rstrip()))
                    except:
                        pass
            if self.cutMode:
                self.cropWidget.applySceneIntersections(scene_intersections)
            else:
                self.display.applySceneIntersections(scene_intersections)
            self.sceneFinderDone=True
            self.sceneFinderAction.setChecked(self.sceneFinderDone)
                
        except:
            print(traceback.format_exc(), flush=True)
        finally:
            os.unlink(tmpfilename)
            os.unlink(outfilename)
            endAsyncTask()

    def return2edit(self):
        srcfolder=os.path.join(path, "../../../../input/vr/check/rate")
        targetfolder = os.path.join(path, "../../../../input/vr/check/rate")
        actionPrefix = "Revision "
        self._moveFile(srcfolder, targetfolder, actionPrefix)
        
    def rateOrArchiveAndNext(self):
        self.sliderinitdone=True
        if cutModeFolderOverrideActive:
            srcfolder=cutModeFolderOverridePath
        else:
            srcfolder=os.path.join(path, "../../../../input/vr/check/rate")
        targetfolder = os.path.join(path, "../../../../input/vr/check/rate/ready" if self.justRate else "../../../../input/vr/check/rate/done")
        actionPrefix = "Forward " if self.justRate else "Archive "
        self._moveFile(srcfolder, targetfolder, actionPrefix)
        
    def _moveFile(self, srcfolder, targetfolder, actionPrefix):
        enterUITask()
        try:
            self.display.stopAndBlackout()

            files=getFilesToRate()
            index=files.index(self.currentFile)

            os.makedirs(targetfolder, exist_ok=True)
                
            source=os.path.abspath(os.path.join(srcfolder, self.currentFile))
            if os.path.exists(source):
                destination=os.path.abspath(os.path.join(targetfolder, replaceSomeChars(os.path.basename(self.currentFile))))
                
                self.log( actionPrefix + self.currentFile, QColor("white"))
                recreated=os.path.exists(destination)

                thread = threading.Thread(
                    target=self.move_worker,
                    args=(source, destination, index, recreated),
                    daemon=True
                )
                thread.start()
            else:
                print("Error "+actionPrefix+". Missing " + source, flush=True)
                
        except:
            print("Error " + actionPrefix + source, flush=True)
            print(traceback.format_exc(), flush=True)
        finally:
            leaveUITask()
        

    def move_worker(self, source, destination, index, recreated):
        startAsyncTask()
        try:
            capfile = replace_file_suffix(source, ".txt")
            print("move from", source, "to", destination, flush=True) 
            shutil.move(source, destination)
            if not os.path.exists(source) and os.path.exists(capfile):
                shutil.move(capfile, replace_file_suffix(destination, ".txt"))
            countdown=5
            while os.path.exists(source):
                countdown=countdown-1
                if countdown<0:
                    break
                print("source file still exists. retry ...", flush=True)
                time.sleep(2)
                shutil.move(source, destination)
                if not os.path.exists(source) and os.path.exists(capfile):
                    shutil.move(capfile, replace_file_suffix(destination, ".txt"))
            if countdown<0:
                QTimer.singleShot(0, partial(self.move_updater, index, recreated, False))
            else:
                QTimer.singleShot(0, partial(self.move_updater, index, recreated, True))
        except:
            print(traceback.format_exc(), flush=True) 
            QTimer.singleShot(0, partial(self.move_updater, index, recreated, False))


    def move_updater(self, index, recreated, success):
        if success:
            self.logn(" Overwritten" if recreated else " OK", QColor("green"))
        else:
            self.logn(" Failed", QColor("red"))
            
        try:
            files=rescanFilesToRate()
            l=len(files)
            #print("rescanFilesToRate: len =", l, flush=True)

            if l==0:    # last file deleted?
                index=-1
                self.currentFile=None
            elif index>=l:
                index=l-1
                self.currentFile=files[index]
            else:
                self.currentFile=files[index]
            self.currentIndex=index
            self.rateCurrentFile()
        except Exception:
            print("Error moving " + source, flush=True)
            print(traceback.format_exc(), flush=True) 
        finally:
            endAsyncTask()


    def buildOutputFilename(self, inputBaseFolder, outputBaseFolder, inputRelative, outputSuffix):
            outputBase=replaceSomeChars(inputRelative)
            outputBase=os.path.abspath(os.path.join(outputBaseFolder, outputBase[:outputBase.rindex('.')] + "_"))
            fnum=1
            while os.path.exists(outputBase + str(fnum) + outputSuffix):
                fnum+=1
            return outputBase + str(fnum) + outputSuffix
        

    def createTrimmedAndCroppedCopy(self):
        enterUITask()
        try:
            self.hasCropOrTrim=False
            rfolder=os.path.join(path, "../../../../input/vr/check/rate")
            if cutModeFolderOverrideActive:
                folder=cutModeFolderOverridePath
            else:
                folder=rfolder
            input=os.path.abspath(os.path.join(folder, self.currentFile))
            try:
                if self.isVideo:
                    try:
                        if hasattr(self, 'display') and self.display is not None:
                            if not self.display.isPaused():
                                self.display.tooglePausePressed()
                                try:
                                    if self.display.isPaused():
                                        self.updatePaused(True)
                                    self.button_startpause_video.update()
                                    self.button_startpause_video.repaint()
                                    QApplication.processEvents()
                                except Exception:
                                    pass
                    except Exception:
                        print(traceback.format_exc(), flush=True)

                suffix = ".mp4" if self.display.frame_count>0 else ".png"
                newfilename = self.buildOutputFilename(folder, rfolder+"/edit", self.currentFile, suffix)
                output=os.path.abspath(os.path.join(rfolder+"/edit", newfilename))
                if self.isVideo:
                    trimA=self.display.trimAFrame
                    trimB=self.display.trimBFrame
                out_w=self.cropWidget.sourceWidth - self.cropWidget.crop_left - self.cropWidget.crop_right
                out_h=self.cropWidget.sourceHeight - self.cropWidget.crop_top - self.cropWidget.crop_bottom
                if out_h % 2 == 1:
                    out_h -= 1
                x=self.cropWidget.crop_left
                y=self.cropWidget.crop_top
                self.log("Create "+newfilename, QColor("white"))
                recreated=os.path.exists(output)

                if not self.isVideo:
                    startAsyncTask()
                    success = False
                    try:
                        export_pixmap = self.cropWidget.get_export_cropped_pixmap()
                        save_pixmap = export_pixmap

                        if export_pixmap is not None and not export_pixmap.isNull():
                            save_supported = self._is_filter_supported_for_current_content()
                            preview_supported = self._is_filter_preview_supported_for_current_content()
                            if save_supported and (not preview_supported):
                                try:
                                    pil_image = self._pixmap_to_pil_rgba(export_pixmap)
                                    if pil_image is not None:
                                        filtered = self.apply_active_content_filter(pil_image)
                                        if isinstance(filtered, Image.Image):
                                            save_pixmap = pil2pixmap(filtered)
                                        if TRACELEVEL >= 2:
                                            print("createTrimmedAndCroppedCopy: applied save-only content filter for image export", flush=True)
                                except Exception:
                                    print(traceback.format_exc(), flush=True)

                        success = save_pixmap is not None and not save_pixmap.isNull() and save_pixmap.save(output, "PNG")
                    except Exception:
                        print(traceback.format_exc(), flush=True)
                    self.trimAndCrop_updater(recreated, input, output, success)
                    return

                active_filter_id = ""
                try:
                    active_filter_id = str(getattr(self.active_content_filter, 'filter_id', '') or '').strip().lower()
                except Exception:
                    active_filter_id = ""
                use_frame_export = active_filter_id == "grayscale" and self._is_filter_supported_for_current_content()

                if use_frame_export:
                    pingpong_active = bool(getattr(self, 'playtype_pingpong', False) or getattr(getattr(self, 'display', None), 'pingPongModeEnabled', False))
                    estimated_total_frames = max(1, int(trimB) - int(trimA) + 1)
                    if pingpong_active and estimated_total_frames > 1:
                        estimated_total_frames *= 2
                    self._show_frame_export_progress(estimated_total_frames)
                    thread = threading.Thread(
                        target=self.trimAndCrop_frames_worker,
                        args=(recreated, input, output, trimA, trimB, x, y, out_w, out_h, pingpong_active),
                        daemon=True,
                    )
                    thread.start()
                    return

                # Determine fps if available (for accurate audio trimming)
                fps = None
                try:
                    if getattr(self, 'display', None) and getattr(self.display, 'thread', None):
                        fps = float(self.display.thread.getFPS())
                        if fps <= 0:
                            fps = None
                except Exception:
                    fps = None

                # Build ffmpeg command. Ensure output timestamps start at 0 by using setpts/asetpts
                # If we have a trim and fps, prefer input seeking (-ss/-t) to trim both audio and video.
                if self.isVideo:
                    has_trim = False
                    try:
                        if getattr(self.display, 'frame_count', 0) > 0:
                            if trimA > 0 or (trimB >= 0 and trimB < getattr(self.display, 'frame_count', -1)):
                                has_trim = True
                    except Exception:
                        has_trim = False

                    if has_trim and fps is not None:
                        start_sec = float(trimA) / fps
                        if trimB is not None and trimB >= 0:
                            duration_sec = float(trimB - trimA + 1) / fps
                            time_opts = f"-ss {start_sec:.6f} -t {duration_sec:.6f} "
                        else:
                            time_opts = f"-ss {start_sec:.6f} "
                        cmd = f'ffmpeg.exe -hide_banner -y {time_opts}-i "{input}" -vf "crop={out_w}:{out_h}:{x}:{y},setpts=PTS-STARTPTS" -af "asetpts=PTS-STARTPTS" -shortest "{output}"'
                    else:
                        # No trim or unknown fps: crop and reset timestamps; audio will be reset but not trimmed
                        cmd = f'ffmpeg.exe -hide_banner -y -i "{input}" -vf "crop={out_w}:{out_h}:{x}:{y},setpts=PTS-STARTPTS" -af "asetpts=PTS-STARTPTS" -shortest "{output}"'
                else:
                    # images
                    cmd = "ffmpeg.exe -hide_banner -y -i \"" + input + "\" -vf \"crop="+str(out_w)+":"+str(out_h)+":"+str(x)+":"+str(y)+"\" \"" + output + "\""
                print("Executing "  + cmd, flush=True)
                # If pingpong mode enabled (either dialog flag or display flag), produce an intermediate then concat reverse to final output (video-only)
                pingpong_active = bool(getattr(self, 'playtype_pingpong', False) or getattr(getattr(self, 'display', None), 'pingPongModeEnabled', False))
                if TRACELEVEL >= 2:
                    print(f"createTrimmedAndCroppedCopy: pingpong_active={pingpong_active}, playtype_pingpong={getattr(self, 'playtype_pingpong', False)}, display.pingPongModeEnabled={getattr(getattr(self, 'display', None), 'pingPongModeEnabled', False)}, isVideo={self.isVideo}", flush=True)
                if pingpong_active and self.isVideo:
                    tmp1 = tempfile.NamedTemporaryFile(delete=False, suffix='.mp4')
                    tmp1.close()
                    out_tmp = tmp1.name
                    # produce intermediate file
                    cmd1 = "ffmpeg.exe -hide_banner -y -i \"" + input + "\" -vf \""
                    if self.isVideo:
                        cmd1 = cmd1 + "trim=start_frame=" + str(trimA) + ":end_frame=" + str(trimB) + ","
                    cmd1 = cmd1 + "crop="+str(out_w)+":"+str(out_h)+":"+str(x)+":"+str(y)+"\" -shortest \"" + out_tmp + "\""
                    # create final pingpong by concat reverse (video-only)
                    cmd2 = 'ffmpeg.exe -hide_banner -y -i "' + out_tmp + '" -filter_complex "[0:v]reverse[r];[0:v][r]concat=n=2:v=1:a=0[out]" -map "[out]" -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p "' + output + '"'
                    thread = threading.Thread(
                        target=self.trimAndCrop_pingpong_worker, args=(cmd1, cmd2, recreated, input, output, out_tmp), daemon=True)
                    thread.start()
                else:
                    thread = threading.Thread(
                        target=self.trimAndCrop_worker, args=(cmd, recreated, input, output, ), daemon=True)
                    thread.start()
                
            except ValueError as e:
                pass
        except:
            print(traceback.format_exc(), flush=True)
        finally:
            leaveUITask()

    def trimAndCrop_frames_worker(self, recreated, input, output, trimA, trimB, x, y, out_w, out_h, pingpong_active):
        startAsyncTask()
        success = False
        cap = None
        tmp_video = None
        writer = None
        try:
            cap, tmp_video = open_videocapture_with_tmp(input)
            if cap is None or not cap.isOpened():
                raise RuntimeError(f"Failed to open video for frame export: {input}")

            frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            fps = float(cap.get(cv2.CAP_PROP_FPS))
            if fps <= 0:
                fps = 24.0

            start_frame = max(0, int(trimA))
            end_frame = int(trimB) if trimB is not None else -1
            if frame_count > 0:
                max_end = frame_count - 1
                if end_frame < 0:
                    end_frame = max_end
                else:
                    end_frame = min(end_frame, max_end)

            if end_frame < start_frame:
                raise RuntimeError(f"Invalid trim range: {start_frame}..{end_frame}")

            base_total_frames = max(0, end_frame - start_frame + 1)
            total_frames_to_write = base_total_frames
            if pingpong_active and base_total_frames > 1:
                total_frames_to_write += base_total_frames
            self.frame_export_progress_signal.emit(0, max(1, total_frames_to_write))

            export_w = max(2, int(out_w))
            export_h = max(2, int(out_h))
            if export_w % 2 == 1:
                export_w -= 1
            if export_h % 2 == 1:
                export_h -= 1

            fourcc = cv2.VideoWriter_fourcc(*'mp4v')
            writer = cv2.VideoWriter(output, fourcc, fps, (export_w, export_h))
            if not writer.isOpened():
                raise RuntimeError(f"Failed to open video writer: {output}")

            cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
            frame_index = start_frame
            exported_frames = [] if pingpong_active else None
            written_frames = 0

            while frame_index <= end_frame:
                ret, frame = cap.read()
                if not ret or frame is None:
                    break

                crop = frame[y:y + export_h, x:x + export_w]
                if crop is None or getattr(crop, "size", 0) == 0:
                    frame_index += 1
                    continue

                if crop.shape[1] != export_w or crop.shape[0] != export_h:
                    crop = cv2.resize(crop, (export_w, export_h), interpolation=cv2.INTER_LINEAR)

                filtered_frame = self.apply_active_content_filter_to_cv_frame(crop)
                writer.write(filtered_frame)
                written_frames += 1
                self.frame_export_progress_signal.emit(written_frames, max(1, total_frames_to_write))

                if exported_frames is not None:
                    exported_frames.append(filtered_frame.copy())

                frame_index += 1

            if exported_frames is not None and len(exported_frames) > 1:
                for frame in reversed(exported_frames):
                    writer.write(frame)
                    written_frames += 1
                    self.frame_export_progress_signal.emit(written_frames, max(1, total_frames_to_write))

            success = os.path.exists(output) and os.path.getsize(output) > 0
        except Exception:
            print(traceback.format_exc(), flush=True)
            success = False
        finally:
            try:
                if writer is not None:
                    writer.release()
            except Exception:
                pass
            try:
                if cap is not None:
                    cap.release()
            except Exception:
                pass
            if tmp_video:
                try:
                    os.unlink(tmp_video)
                except Exception:
                    pass

            QTimer.singleShot(0, partial(self.trimAndCrop_updater, recreated, input, output, success))

            
    def trimAndCrop_worker(self, cmd, recreated, input, output):
        startAsyncTask()
        try:
            cp = subprocess.run(cmd, shell=True, check=True, close_fds=True)
            QTimer.singleShot(0, partial(self.trimAndCrop_updater, recreated, input, output, True))

        except subprocess.CalledProcessError as se:
            QTimer.singleShot(0, partial(self.trimAndCrop_updater, recreated, input, output, False))
        except:
            print(traceback.format_exc(), flush=True)                
            endAsyncTask()


    def trimAndCrop_pingpong_worker(self, cmd1, cmd2, recreated, input, output, intermediate):
        startAsyncTask()
        try:
            # run first step to produce intermediate
            subprocess.run(cmd1, shell=True, check=True, close_fds=True)
            # run second step to create pingpong (video-only)
            subprocess.run(cmd2, shell=True, check=True, close_fds=True)
            # cleanup intermediate
            try:
                if os.path.exists(intermediate):
                    os.remove(intermediate)
            except Exception:
                pass
            QTimer.singleShot(0, partial(self.trimAndCrop_updater, recreated, input, output, True))
        except subprocess.CalledProcessError as se:
            try:
                if os.path.exists(intermediate):
                    os.remove(intermediate)
            except Exception:
                pass
            QTimer.singleShot(0, partial(self.trimAndCrop_updater, recreated, input, output, False))
        except Exception:
            print(traceback.format_exc(), flush=True)
            try:
                if os.path.exists(intermediate):
                    os.remove(intermediate)
            except Exception:
                pass
        finally:
            endAsyncTask()


    def trimAndCrop_updater(self, recreated, input, output, success):
        self._hide_frame_export_progress()
        if success:
            self.log(" Overwritten" if recreated else " OK", QColor("green"))
            if self._has_active_non_default_filter() and self.display.frame_count<=0 and os.path.exists(output):
                self._set_trashbin_switch_mode(True, input, output)
            else:
                self._invalidate_trashbin_switch_mode()
            if self.display.frame_count<=0:
                cb = QApplication.clipboard()
                cb.clear(mode=cb.Clipboard)
                cb.setText(output, mode=cb.Clipboard)
                self.logn("+clipboard", QColor("gray"))
            else:
                self.logn("", QColor("gray"))
            capfile = replace_file_suffix(input, ".txt")
            if os.path.exists(capfile):
                shutil.copyfile(capfile, replace_file_suffix(output, ".txt"))
        else:
            self._invalidate_trashbin_switch_mode()
            self.logn(" Failed", QColor("red"))

        if self.cutMode:
            self.button_justrate_compress.setEnabled(True)        
            self.button_justrate_compress.setIcon(self.icon_compress)
            self.justRate=False
            self.button_justrate_compress.setFocus()

        endAsyncTask()

    def _create_temp_and_open(self):
        """Create a temporary file reflecting current crop/trim/pingpong state and open it."""
        if not self.currentFile:
            return

        if cutModeFolderOverrideActive:
            folder = cutModeFolderOverridePath
        else:
            folder = os.path.join(path, "../../../../input/vr/check/rate")

        fullpath = os.path.abspath(os.path.join(folder, self.currentFile))
        # fallback absolute
        if not os.path.exists(fullpath):
            if os.path.isabs(self.currentFile) and os.path.exists(self.currentFile):
                fullpath = self.currentFile
            else:
                alt = os.path.abspath(os.path.join(path, self.currentFile))
                if os.path.exists(alt):
                    fullpath = alt

        if not os.path.exists(fullpath):
            return

        # ensure cleanup thread running
        _ensure_temp_cleanup_thread()

        def worker():
            startAsyncTask()
            try:
                if TRACELEVEL >= 2:
                    print(f"_create_temp_and_open: worker start for currentFile={self.currentFile}", flush=True)
                suffix = os.path.splitext(fullpath)[1].lower()
                if suffix in IMAGE_EXTENSIONS:
                    try:
                        if TRACELEVEL >= 3:
                            print("_create_temp_and_open: handling image branch", flush=True)
                        # determine if a real crop exists (at least one margin > 0)
                        crop_exists = False
                        try:
                            cw = getattr(self, 'cropWidget', None)
                            if cw is not None:
                                if getattr(cw, 'crop_left', 0) > 0 or getattr(cw, 'crop_right', 0) > 0 or getattr(cw, 'crop_top', 0) > 0 or getattr(cw, 'crop_bottom', 0) > 0:
                                    crop_exists = True
                        except Exception:
                            pass

                        # if no crop, open original (behave like F11)
                        if not crop_exists:
                            if TRACELEVEL >= 2:
                                print(f"_create_temp_and_open: no crop detected; opening original: {fullpath}", flush=True)
                            _open_and_log(fullpath)
                            return
                        pix = self.cropWidget.original_pixmap
                        if pix is None:
                            _open_and_log(fullpath)
                            return
                        w = pix.width(); h = pix.height()
                        x0 = int(self.cropWidget.crop_left)
                        y0 = int(self.cropWidget.crop_top)
                        x1 = int(w - self.cropWidget.crop_right)
                        y1 = int(h - self.cropWidget.crop_bottom)
                        if x1 <= x0 or y1 <= y0:
                            QTimer.singleShot(0, partial(_open_and_log, fullpath))
                            return
                        rect = QRect(x0, y0, x1-x0, y1-y0)
                        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                        tmp.close()
                        if TRACELEVEL >= 2:
                            print(f"_create_temp_and_open: saving cropped image to {tmp.name}", flush=True)
                        cropped = pix.copy(rect)
                        cropped.save(tmp.name, 'PNG')
                        TEMP_FILES_TO_CLEANUP.append(tmp.name)
                        if TRACELEVEL >= 2:
                            print(f"_create_temp_and_open: scheduling open of temp image {tmp.name}", flush=True)
                        _open_and_log(tmp.name)
                        return
                    except Exception:
                        print(traceback.format_exc(), flush=True)
                        if TRACELEVEL >= 1:
                            print(f"_create_temp_and_open: image branch failed; scheduling open of original {fullpath}", flush=True)
                        _open_and_log(fullpath)
                        return

                # video path
                # check whether trimming/cropping/pingpong is active; if none, open original
                try:
                    has_trim = False
                    if getattr(self.display, 'frame_count', 0) > 0:
                        trimA = getattr(self.display, 'trimAFrame', 0)
                        trimB = getattr(self.display, 'trimBFrame', -1)
                        if trimA > 0 or (trimB >= 0 and trimB < getattr(self.display, 'frame_count', -1)):
                            has_trim = True
                except Exception:
                    has_trim = False

                has_crop = False
                try:
                    cw = getattr(self, 'cropWidget', None)
                    if cw is not None:
                        if getattr(cw, 'crop_left', 0) > 0 or getattr(cw, 'crop_right', 0) > 0 or getattr(cw, 'crop_top', 0) > 0 or getattr(cw, 'crop_bottom', 0) > 0:
                            has_crop = True
                except Exception:
                    has_crop = False

                if not (has_trim or has_crop or getattr(self, 'playtype_pingpong', False)):
                    if TRACELEVEL >= 2:
                        print(f"_create_temp_and_open: no trim/crop/pingpong; opening original: {fullpath}", flush=True)
                    _open_and_log(fullpath)
                    return

                tmp1 = tempfile.NamedTemporaryFile(delete=False, suffix='.mp4')
                tmp1.close()
                out_tmp = tmp1.name
                if TRACELEVEL >= 2:
                    print(f"_create_temp_and_open: will create video temp {out_tmp}", flush=True)

                # build ffmpeg command similar to createTrimmedAndCroppedCopy
                cmd = 'ffmpeg.exe -hide_banner -y -i "' + fullpath + '" -vf "'
                filters = []
                try:
                    if getattr(self.display, 'frame_count', 0) > 0:
                        trimA = getattr(self.display, 'trimAFrame', 0)
                        trimB = getattr(self.display, 'trimBFrame', -1)
                        if trimA > 0 or (trimB >= 0 and trimB < getattr(self.display, 'frame_count', -1)):
                            filters.append(f'trim=start_frame={trimA}:end_frame={trimB}')
                except Exception:
                    pass

                try:
                    if getattr(self, 'hasCropOrTrim', False) and getattr(self, 'cropWidget', None):
                        out_w = self.cropWidget.sourceWidth - self.cropWidget.crop_left - self.cropWidget.crop_right
                        out_h = self.cropWidget.sourceHeight - self.cropWidget.crop_top - self.cropWidget.crop_bottom
                        if out_h % 2 == 1:
                            out_h -= 1
                        x = self.cropWidget.crop_left
                        y = self.cropWidget.crop_top
                        filters.append(f'crop={out_w}:{out_h}:{x}:{y}')
                except Exception:
                    pass

                if len(filters) > 0:
                    cmd += ','.join(filters)
                cmd += '" -shortest "' + out_tmp + '"'

                # run ffmpeg
                try:
                    if TRACELEVEL >= 2:
                        print('Executing', cmd, flush=True)
                    subprocess.run(cmd, shell=True, check=True, close_fds=True)
                except Exception:
                    print(traceback.format_exc(), flush=True)
                    if TRACELEVEL >= 1:
                        print(f"_create_temp_and_open: ffmpeg failed; scheduling open of original {fullpath}", flush=True)
                    _open_and_log(fullpath)
                    return

                final_tmp = out_tmp
                # pingpong handling (reverse + concat) - best-effort
                if getattr(self, 'playtype_pingpong', False):
                    try:
                        tmp2 = tempfile.NamedTemporaryFile(delete=False, suffix='.mp4')
                        tmp2.close()
                        cmd2 = 'ffmpeg.exe -hide_banner -y -i "' + out_tmp + '" -filter_complex "[0:v]reverse[r];[0:v][r]concat=n=2:v=1:a=0[out]" -map "[out]" -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p "' + tmp2.name + '"'
                        if TRACELEVEL >= 2:
                            print('Executing', cmd2, flush=True)
                        subprocess.run(cmd2, shell=True, check=True, close_fds=True)
                        # remove intermediate
                        try:
                            os.remove(out_tmp)
                        except Exception:
                            pass
                        final_tmp = tmp2.name
                    except Exception:
                        print(traceback.format_exc(), flush=True)
                        final_tmp = out_tmp

                if TRACELEVEL >= 2:
                    print(f"_create_temp_and_open: scheduling open of temp video {final_tmp}", flush=True)
                TEMP_FILES_TO_CLEANUP.append(final_tmp)
                _open_and_log(final_tmp)

            finally:
                endAsyncTask()

        thread = threading.Thread(target=worker, daemon=True)
        thread.start()


    def createSnapshot(self):
        enterUITask()
        try:
            self.button_snapshot_from_video.setEnabled(False)
            self.hasCropOrTrim=False
            rfolder=os.path.join(path, "../../../../input/vr/check/rate")
            if cutModeFolderOverrideActive:
                folder=cutModeFolderOverridePath
            else:
                folder=rfolder
            input=os.path.abspath(os.path.join(folder, self.currentFile))
            frameindex=str(self.cropWidget.getCurrentFrameIndex())
            try:
                newfilename = self.buildOutputFilename(folder, rfolder+"/edit", self.currentFile, ".png")
                tmpfilename = self.buildOutputFilename(folder, rfolder+"/edit", self.currentFile, "_tmp.png")
                output=os.path.abspath(os.path.join(rfolder+"/edit", newfilename))
                tempfile=os.path.abspath(os.path.join(rfolder+"/edit", tmpfilename))
                out_w=self.cropWidget.sourceWidth - self.cropWidget.crop_left - self.cropWidget.crop_right
                out_h=self.cropWidget.sourceHeight - self.cropWidget.crop_top - self.cropWidget.crop_bottom
                if out_h % 2 == 1:
                    out_h -= 1
                x=self.cropWidget.crop_left
                y=self.cropWidget.crop_top
                self.log("Create snapshot "+newfilename, QColor("white"))
                recreated=os.path.exists(output)
                '''
                cmd1 = "ffmpeg.exe -hide_banner -y -i \"" + input + "\" -vf \"select=eq(n\\," + frameindex + ")\" -vframes 1 -update 1 \"" + tempfile + "\""
                cmd2 = "ffmpeg.exe -hide_banner -y -i \"" + tempfile + "\" -vf \"crop="+str(out_w)+":"+str(out_h)+":"+str(x)+":"+str(y) + "\" \"" + output + "\""
                
                thread = threading.Thread(
                            target=self.takeSnapshot_worker,
                            args=(cmd1, cmd2, recreated, tempfile, output, ),
                            daemon=True
                        )
                thread.start()
                '''
                
                cropped_pixmap = self.cropWidget.get_export_cropped_pixmap()
                success = cropped_pixmap is not None and not cropped_pixmap.isNull() and cropped_pixmap.save(output, "PNG")
                self.takeSnapshot_updater(success, recreated, output, )
                
            except ValueError as e:
                pass
        except:
            print(traceback.format_exc(), flush=True)
        finally:
            leaveUITask()

    '''
    def takeSnapshot_worker(self, cmd1, cmd2, recreated, temporaryfile, output):
        startAsyncTask()
        try:
            try:
                print("Executing "  + cmd1, flush=True)
                cp = subprocess.run(cmd1, shell=True, check=True, close_fds=True)
                print("Executing "  + cmd2, flush=True)
                cp = subprocess.run(cmd2, shell=True, check=True, close_fds=True)
                os.remove(temporaryfile)
                QTimer.singleShot(0, partial(self.takeSnapshot_updater, True, recreated, output))
            except subprocess.CalledProcessError as se:
                QTimer.singleShot(0, partial(self.takeSnapshot_updater, False, recreated, ""))

        except Exception:
            print(traceback.format_exc(), flush=True) 
    '''

    def takeSnapshot_updater(self, success, recreated, output):
        if success:
            self._invalidate_trashbin_switch_mode()
            self.log(" Overwritten" if recreated else " OK", QColor("green"))
            cb = QApplication.clipboard()
            cb.clear(mode=cb.Clipboard)
            cb.setText(output, mode=cb.Clipboard)
            self.logn("+clipboard", QColor("gray"))
        else:
            self._invalidate_trashbin_switch_mode()
            self.logn(" Failed", QColor("red"))
            cb = QApplication.clipboard()
            cb.clear(mode=cb.Clipboard )
            
        try:
            rescanFilesToRate()
            self.button_snapshot_from_video.setEnabled(False)
            self.button_justrate_compress.setEnabled(True)
            self.button_justrate_compress.setIcon(self.icon_compress)
            self.justRate=False
            self.button_justrate_compress.setFocus()
            self.button_trimb_video.setVisible(False)
            self.button_trimtosnap_video.setVisible(True)            
        except:
            print(traceback.format_exc(), flush=True) 
        finally:
            endAsyncTask()


    def onVideoLoaded(self, count, fps, length):
        self.sceneFinderDone=False
        self.sceneFinderAction.setChecked(self.sceneFinderDone)

        if cutModeFolderOverrideActive:
            pass
        else:
            if self.display.frame_count<0:
                self.logn("Loading video failed. Archiving forced...", QColor("red"))
                self.justRate=False
                self.rateOrArchiveAndNext()
                self.loadingOk = False
                return

        if count<0:
            self.logn("Loading video failed.", QColor("red"))
            self.display.stopAndBlackout()
            self.loadingOk = False
            return
            
        if self.cutMode:
            self.button_trima_video.setVisible(False)
            self.button_trimfirst_video.setVisible(True)

        SCENEDETECTION_INPUTLENGTHLIMIT=float(config("SCENEDETECTION_INPUTLENGTHLIMIT", "20.0"))
        if count>0 and length<=SCENEDETECTION_INPUTLENGTHLIMIT:
            self.sceneDetection()
        else:
            if self.cutMode:
                self.cropWidget.applySceneIntersections([])


    def sceneDetection(self):
        #self.logn("Scene detection...", QColor("grey"))
        if cutModeFolderOverrideActive:
            folder=cutModeFolderOverridePath
        else:
            folder=os.path.join(path, "../../../../input/vr/check/rate")
        input=os.path.abspath(os.path.join(folder, self.currentFile))
        
        SCENEDETECTION_THRESHOLD_DEFAULT=float(config("SCENEDETECTION_THRESHOLD_DEFAULT", "0.1"))
        thread = threading.Thread(
            target=self.sceneFinder_worker,
            args=(input, SCENEDETECTION_THRESHOLD_DEFAULT,),
            daemon=True
        )                            
        thread.start()
        
    def init_clipboard_monitor(self):
        """Initialize clipboard monitoring for images."""
        app = QApplication.instance() or QApplication([])
        self.clipboard = app.clipboard()
        self.clipboard.changed.connect(self._on_clipboard_changed)
        # --- Check if clipboard already contains an image at startup ---
        mime = self.clipboard.mimeData()
        if mime and mime.hasImage():
            img = self.clipboard.image()
            if isinstance(img, QImage):
                h = self._compute_hash(img)
                self._last_clipboard_hash = h
                # Mark as pending only if it is not already saved
                self.clipboard_has_image = (h != self._last_saved_hash)
            else:
                self.clipboard_has_image = False
        else:
            self.clipboard_has_image = False

    def _qimage_to_bytes(self, img: QImage) -> bytes:
        """Convert QImage to PNG bytes."""
        buf = QBuffer()
        buf.open(QIODevice.WriteOnly)
        img.save(buf, "PNG")
        return bytes(buf.data())

    def _compute_hash(self, img: QImage) -> str:
        """Return SHA256 of the PNG representation of QImage."""
        return sha256(self._qimage_to_bytes(img)).hexdigest()

    def _on_clipboard_changed(self, mode):
        """React to clipboard changes and update clipboard_has_image."""
        if mode != QClipboard.Clipboard:
            return

        mime = self.clipboard.mimeData()

        # No image -> no pending image
        if not mime or not mime.hasImage():
            self.clipboard_has_image = False
            self._last_clipboard_hash = None
            return

        img = self.clipboard.image()
        if not isinstance(img, QImage):
            self.clipboard_has_image = False
            self._last_clipboard_hash = None
            return

        # Compute new clipboard hash
        h = self._compute_hash(img)
        self._last_clipboard_hash = h

        # Mark new image only if not the last saved
        self.clipboard_has_image = (h != self._last_saved_hash)

    def save_clipboard_image(self):
        """
        Saves clipboard image if it exists and is new.
        After a successful save clipboard_has_image becomes False.
        Returns the saved filepath or None.
        """
        # Nothing new → nothing to save
        if not self.clipboard_has_image:
            return None

        mime = self.clipboard.mimeData()
        if not mime or not mime.hasImage():
            self.clipboard_has_image = False
            return None

        img = self.clipboard.image()
        if not isinstance(img, QImage):
            self.clipboard_has_image = False
            return None

        # Hash again to ensure nothing changed since the event
        h = self._compute_hash(img)

        # Already saved
        if h == self._last_saved_hash:
            self.clipboard_has_image = False
            return None

        # Build filename: Cut_YYMMDDhhmmss.png
        ts = datetime.now().strftime("%y%m%d%H%M%S")
        filename = f"Cut_{ts}.png"
        folder=os.path.join(path, "../../../../input/vr/check/rate")
        filepath = os.path.join(folder, filename)

        # Save image
        with open(filepath, "wb") as f:
            f.write(self._qimage_to_bytes(img))

        # Update state
        self._last_saved_hash = h
        self.clipboard_has_image = False

        global cutModeFolderOverrideActive
        cutModeFolderOverrideActive=False

        thread = threading.Thread(
            target=self.saveClipboardWorker,
            args=(filename, ),
            daemon=True
        )
        thread.start()

    def saveClipboardWorker(self, filename):
        try:
            startAsyncTask()

            scanFilesToRate()   # can block on some drives

            QTimer.singleShot(0, partial(self.switchDirectory_updater, False, "", filename))
        except:
            endAsyncTask()
            print(traceback.format_exc(), flush=True) 


    def closeOnError(self, msg):
        if TRACELEVEL >= 1:
            print(msg, flush=True)
        self.currentIndex=-1
        self.display.stopAndBlackout()
        self.rateCurrentFile()


class GroupBoxHoverFilter(QObject):
    def __init__(self, box):
        super().__init__()
        self.box = box

    def eventFilter(self, obj, event):
        if event.type() == QEvent.MouseMove:
            pos = QCursor.pos()
            widget_under = QApplication.widgetAt(pos)

            # Cursor auf GroupBox selbst
            if widget_under is self.box:
                self.box.setCursor(Qt.CursorShape.DragLinkCursor)
            else:
                # Cursor auf Kind oder außerhalb
                if self.box.cursor().shape() == Qt.CursorShape.DragLinkCursor:
                    self.box.unsetCursor()

        return False
        

class HoverLabel(QLabel):
    """A QLabel that detects hover and click events."""
    def __init__(self, index, parent=None):
        super().__init__(parent)
        self.index = index
        self.setMouseTracking(True)
        self.setCursor(QCursor(Qt.PointingHandCursor))  # Hand cursor on hover

    def enterEvent(self, event):
        if self.parent():
            self.parent().on_hover(self.index)
        super().enterEvent(event)

    def leaveEvent(self, event):
        if self.parent():
            self.parent().on_leave()
        super().leaveEvent(event)

    def mousePressEvent(self, event):
        """When clicked, notify the parent to lock the rating."""
        if event.button() == Qt.LeftButton and self.parent():
            self.parent().on_click(self.index)
        super().mousePressEvent(event)


class RatingWidget(QWidget):
    """Custom rating widget with hover effect, click-to-lock, and signal emission."""
    
    # Signal that emits the chosen rating (1-5)
    ratingChanged = pyqtSignal(int)

    def __init__(self, parent=None, stars_count=5):
        super().__init__(parent)

        self.stars_count = stars_count

        # Images: Default empty and filled star
        self.default_image = QPixmap(os.path.join(path, '../../gui/img/starn80.png'))
        self.hover_image = QPixmap(os.path.join(path, '../../gui/img/starp80.png'))

        # Optional: Resize star images
        self.icon_size = QSize(80, 80)
        self.default_image = self.default_image.scaled(
            self.icon_size, Qt.KeepAspectRatio, Qt.SmoothTransformation
        )
        self.hover_image = self.hover_image.scaled(
            self.icon_size, Qt.KeepAspectRatio, Qt.SmoothTransformation
        )

        # Layout setup
        layout = QHBoxLayout(self)
        layout.setSpacing(5)
        layout.setContentsMargins(0, 0, 0, 0)

        # Create star labels
        self.labels = []
        for i in range(self.stars_count):
            label = HoverLabel(i, self)
            label.setPixmap(self.default_image)
            layout.addWidget(label)
            self.labels.append(label)
            

        self.setLayout(layout)

        # State variables
        self.current_hover = -1  # Currently hovered index
        self.current_rating = -1  # Locked rating (selected by click)

    def rate(self, value):
        """Lock the rating and emit a signal."""
        self.current_rating = value-1
        self.update_stars(value-1)
        self.ratingChanged.emit(value)  # Emit 1-based rating
        
        
    # -------------------------
    # Hover Handling
    # -------------------------
    def on_hover(self, hover_index):
        """Update all labels up to hover_index with the hover image."""
        self.current_hover = hover_index
        self.update_stars(hover_index)

    def on_leave(self):
        """When mouse leaves, show locked rating instead of hover."""
        self.current_hover = -1
        self.update_stars(self.current_rating)

    # -------------------------
    # Click Handling
    # -------------------------
    def on_click(self, clicked_index):
        self.rate(clicked_index + 1)

    # -------------------------
    # Internal Update Logic
    # -------------------------
    def update_stars(self, active_index):
        """
        Update all labels based on the active index.
        If active_index is -1, all stars are empty.
        """
        for i, label in enumerate(self.labels):
            if i <= active_index:
                label.setPixmap(self.hover_image)
            else:
                label.setPixmap(self.default_image)

    # -------------------------
    # External API
    # -------------------------
    def set_rating(self, rating):
        """
        Set the rating programmatically.
        Rating should be between 1 and stars_count.
        """
        if 0 <= rating <= self.stars_count:
            self.current_rating = rating - 1
            self.update_stars(self.current_rating)
            self.ratingChanged.emit(rating)

    def clear_rating(self):
        """Clear the locked rating (all empty stars)."""
        self.current_rating = -1
        self.update_stars(-1)
        #self.ratingChanged.emit(0)



class VideoThread(QThread):
    change_pixmap_signal = pyqtSignal(np.ndarray, int)

    def __init__(self, parent, filepath, uid, slider, update, onVideoLoaded, pingpong):
        super().__init__()
        global videoActive
        videoActive=False

        self.parent = parent
        self.uid = uid
        self.filepath = filepath
        self.slider = slider
        self.update = update
        self.cap=None
        self.pause = True
        self.update(self.pause)
        self.onVideoLoaded = onVideoLoaded
        self.currentFrame=-1
        self.frame_count=-1
        self.fps=1
        self._run_flag = True
        self.pingPongModeEnabled=pingpong
        self.pingPongReverseState=False
        self.seekRequest=-1
        self.busy=False
        self.WarnOdd=False
        #print("Created thread with uid " + str(uid) , flush=True)

    def run(self):
        enterUITask()
        
        global videoActive
        global rememberThread
        global videoPauseRequested
        
        if not os.path.exists(self.filepath):
            print("Failed to open", self.filepath, flush=True)
            self.onVideoLoaded(-1, 1.0, 0.0)
            leaveUITask()
            return

        # Try opening normally, fall back to a temporary ASCII-named copy
        cap, tmp_video = open_videocapture_with_tmp(self.filepath)
        self.cap = cap
        if tmp_video:
            self._temp_video_file = tmp_video
        if not self.cap.isOpened():
            print("Failed to open", self.filepath, flush=True)
            try:
                self.cap.release()
            except:
                pass
            # cleanup temp copy if present
            if getattr(self, '_temp_video_file', None):
                try:
                    os.unlink(self._temp_video_file)
                except Exception:
                    pass
            self.cap = None
            self.onVideoLoaded(-1, 1.0, 0.0)
            leaveUITask()
            return

        self.frame_count = int(self.cap.get(cv2.CAP_PROP_FRAME_COUNT))
        if int(self.cap.get(cv2.CAP_PROP_FRAME_HEIGHT)) % 2 != 0:
            self.WarnOdd=True
        self.a = 0
        self.b = self.frame_count - 1
        self.fps = self.cap.get(cv2.CAP_PROP_FPS)
        if TRACELEVEL >= 1:
            print("Started video. framecount:", self.frame_count, "fps:", self.fps, flush=True)
        
        self.slider.setMinimum(0)
        self.slider.setMaximum(self.frame_count-1)
        self.slider.setValue(0)
        if self.fps<1.0:
            self.fps=1.0
        interval=int(self.fps)
        vlength = (self.frame_count-1) / self.fps
        if vlength > 7200:
            self.slider.setTickPosition(QSlider.TicksBothSides)
            interval=3600*interval
        elif vlength > 120:
            self.slider.setTickPosition(QSlider.TicksAbove)
            interval=60*interval
        else:
            self.slider.setTickPosition(QSlider.TicksBelow)
        self.slider.setTickInterval(interval)
        self.slider.setSingleStep(1)        
        self.slider.setPageStep(int(self.fps))        
        self.slider.valueChanged.connect(self.sliderChanged)
        self.slider.registerForMouseEvent(self.onSliderMouseClick)

        videoActive=True

        leaveUITask()

        try:
            self.onVideoLoaded(self.frame_count, self.fps, vlength)
            self.update(self.pause)

            self.currentFrame=-1      # before start. first frame will be number 0
            self.lastLoadedFrame= -1
            self.idle=True
            
            while self._run_flag:
                timestamp=time.time() 
                if TRACELEVEL >= 4:
                    print("VideoThread run ", self.currentFrame, int(timestamp*1000), flush=True)
                self.idle=False
                if not self.pause or self.lastLoadedFrame==-1:
                    if self.pingPongModeEnabled and self.pingPongReverseState and self.currentFrame>self.a:
                        self.currentFrame-=1
                        self.seek(self.currentFrame)
                    elif self.pingPongModeEnabled and self.pingPongReverseState and self.currentFrame<=self.a:
                        self.pingPongReverseState=False
                        self.currentFrame=self.a
                        if self.currentFrame+1<=self.b:
                            self.currentFrame+=1
                            self.seek(self.currentFrame)
                    else:
                        if self.currentFrame!=self.lastLoadedFrame:
                            self.seek(self.currentFrame)
                        elif self.currentFrame+1>self.b:
                            if self.pingPongModeEnabled:
                                self.pingPongReverseState=True
                                if self.b-1 >= self.a:
                                    self.seek(self.b-1)
                            else:
                                self.seek(self.a)   # replay
                        elif self.currentFrame+1<self.a:
                            self.seek(self.a)
                        else:
                            ret, cv_img = self.cap.read()
                            if not self.is_frame_valid(ret, cv_img):
                                # Fehlerbehandlung: EOF, defekter Frame oder Lesefehler
                                print("Fehler beim Laden des Frames", flush=True)
                            
                            if self.pause and self.lastLoadedFrame>=0:
                                print("meanwhile paused. ignore image.", flush=True)
                                pass # ignore image
                            elif self._run_flag:
                                if ret and not cv_img is None:
                                    self.currentFrame+=1
                                    self.lastLoadedFrame=self.currentFrame
                                    self.slider.setValue(self.currentFrame)
                                    self.change_pixmap_signal.emit(cv_img, self.uid)
                                else:
                                    if self.pingPongModeEnabled:
                                        self.pingPongReverseState=True
                                        if self.b-1 >= self.a:
                                            self.seek(self.b-1)
                                    else:
                                        print("Error: failed to load frame", self.currentFrame, flush=True)
                                        try:
                                            self.cap.release()
                                        except Exception:
                                            pass
                                        cap2, tmp_video2 = open_videocapture_with_tmp(self.filepath)
                                        self.cap = cap2
                                        if tmp_video2:
                                            # remove previous temp if any
                                            if getattr(self, '_temp_video_file', None):
                                                try:
                                                    os.unlink(self._temp_video_file)
                                                except Exception:
                                                    pass
                                            self._temp_video_file = tmp_video2
                                        self.seek(self.a)
                elif self.seekRequest>=0:
                    self.idle=True
                    self.seek(self.seekRequest)
                    self.seekRequest=-1
                else:
                    self.idle=True
                    if videoPauseRequested:
                        videoPauseRequested=False
                        endAsyncTask()
                
                elapsed = time.time()-timestamp
                sleeptime = max(0.02, 1.0/float(self.fps) - elapsed)
                time.sleep(sleeptime)
            
        except:
            print(traceback.format_exc(), flush=True)
        finally:
            try:
                if self.cap is not None:
                    try:
                        self.cap.release()
                    except Exception:
                        pass
            except Exception:
                pass
            # Remove any temporary video copy we created
            if getattr(self, '_temp_video_file', None):
                try:
                    os.unlink(self._temp_video_file)
                except Exception:
                    pass
            videoActive=False
            #print("Thread ends.", flush=True)

            if videoPauseRequested:
                videoPauseRequested=False
                endAsyncTask()

            global rememberThread
            rememberThread.remove(self)
             

    def requestStop(self):
        self._run_flag=False
        self.change_pixmap_signal.emit(np.array([]), -1)
        if TRACELEVEL >= 2:
            print("waiting for thread to stop...", flush=True)
        while videoActive:
            pass
        if TRACELEVEL >= 2:            
            print("stopped.", flush=True)
        #print("done.", flush=True)
    
    def getFrameCount(self):
        return self.frame_count

    def getCurrentFrameIndex(self):
        return self.currentFrame
    
    def getFPS(self):
        return self.fps

    def isPaused(self):
        return self.pause

    def tooglePause(self):
        self.pause = not self.pause
        self.update(self.pause)


    def seek(self, frame_number):
        if self.currentFrame == frame_number and self.currentFrame == self.lastLoadedFrame:
            return
        if self.busy:
            self.seekRequest = frame_number
            return
        self.busy=True
        try:
            if TRACELEVEL >= 2:
                print("seeking for", frame_number, flush=True)
            self.cap.set(cv2.CAP_PROP_POS_FRAMES, frame_number)  # frame_number starts with 0
            ret, cv_img = self.cap.read()
            if TRACELEVEL >= 2:
                print("seeking done", self.currentFrame, frame_number, ret , self._run_flag, self.pause, flush=True)
        finally:
            self.busy=False
            
        if ret and self._run_flag:
            self.currentFrame=frame_number
            self.lastLoadedFrame=frame_number
            #print("seek", frame_number, self.slider.value(), flush=True)
            if (frame_number!=self.slider.value()):
                self.slider.blockSignals(True)
                try:
                    self.slider.setValue(self.currentFrame)
                finally:
                    self.slider.blockSignals(False)
            self.change_pixmap_signal.emit(cv_img, self.uid)
            #QTimer.singleShot(100, partial(self.seekUpdate, cv_img))
        else:
            self._run_flag = False

    #def seekUpdate(self, cv_img):
    #    self.change_pixmap_signal.emit(cv_img, self.uid)
        
    def is_frame_valid(self, ret, frame) -> bool:
        """
        Robust prüfen, ob cap.read() ein gültiges Bild geliefert hat.
        - ret: bool (Rückgabewert von cap.read())
        - frame: ndarray oder None
        """
        if not bool(ret):
            return False
        if frame is None:
            return False
        # ndarray hat .size: 0 bedeutet kein Pixelinhalt
        if getattr(frame, "size", 0) == 0:
            return False
        # optional: sicherstellen, dass es ein numpy-array ist mit min. 2 Dimensionen (H,W[,C])
        if not isinstance(frame, np.ndarray) or frame.ndim < 2:
            return False
        return True
    
    def setPingPongModeEnabled(self, state):
        self.pingPongModeEnabled=state
        self.pingPongReverseState=False

    def sliderChanged(self):
        slider = self.sender()
        if slider is None:
            return
        if self.pause:  # do not call while playback
            self.seekRequest = slider.value()
        slider.sliderChanged(slider.value())

    def onSliderMouseClick(self):
        if not self.pause:
            if TRACELEVEL >= 1:
                print("onSliderMouseClick. stop playback and seek", self.slider.value(), flush=True)
            self.pause=True
            self.seekRequest=self.slider.value()
            self.update(self.pause)

            frame=self.slider.value()
            QTimer.singleShot(200, partial(self.onSliderMouseClickUpdate, frame))

    def onSliderMouseClickUpdate(self, frame):
            self.currentFrame=frame
            self.slider.setFocus()

    def posA(self):
        if not self.pause:
            self.pause=True
            self.update(self.pause)
        if TRACELEVEL >= 1:
            print("posA", flush=True)
        self.seekRequest=self.a
        
    def posB(self):
        if not self.pause:
            self.pause=True
            self.update(self.pause)
        if TRACELEVEL >= 1:
            print("posB", flush=True)
        self.seekRequest=self.b

    def setA(self, frame_number):
        self.a=frame_number
        if self.a>self.b:
            self.b=self.a
            
    def setB(self, frame_number):
        self.b=frame_number
        if self.b<self.a:
            self.a=self.b

    
class QRubberBandCustom(QRubberBand):
    def __init__(self, shape, parent=None):
        super().__init__(shape, parent)
        # Make the widget background translucent so a semi-transparent
        # fill is composited over the parent (the image) instead of
        # painting over an opaque widget background.
        self.setAttribute(Qt.WA_TranslucentBackground, True)
        self.setAttribute(Qt.WA_NoSystemBackground, True)
        # Ensure Qt knows the paintEvent is non-opaque so composition works
        self.setAttribute(Qt.WA_OpaquePaintEvent, False)
        self.setAutoFillBackground(False)

        # Default colors (QColor). Alpha in QColor is 0-255.
        self._border_qcolor = QColor("#0078D7")
        # use a semi-transparent default fill (alpha 50)
        self._fill_qcolor = QColor(0, 120, 215, 50)
        self.frame_thickness = 1

    def setColor(self, border_color: str, fill_color: str = None, frame_thickness: int = 1):
        """Set the border and optional fill color for the rubber band.

        Args:
            border_color: color string understood by QColor (e.g. '#FF0000' or 'red').
            fill_color: optional fill color string (e.g. 'rgba(255,0,0,50)').
        """

        self.frame_thickness = frame_thickness
        
        try:
            self._border_qcolor = QColor(border_color)
        except Exception:
            # keep existing color if conversion fails
            pass
        if fill_color is not None:
            try:
                self._fill_qcolor = QColor(fill_color)
            except Exception:
                pass
        # Schedule a repaint with the new colors
        self.update()

    def paintEvent(self, event):
        painter = QPainter(self)
        # Ensure semi-transparent painting is composited over parent
        painter.setCompositionMode(QPainter.CompositionMode_Source)
        painter.setBackgroundMode(Qt.TransparentMode)
        painter.setRenderHint(QPainter.Antialiasing)
        rect = self.rect()

        # Fill (if any alpha > 0) — use fillRect to ensure proper composition
        # if self._fill_qcolor is not None and self._fill_qcolor.alpha() > 0:
        #     painter.setPen(Qt.NoPen)
        #    painter.fillRect(rect, self._fill_qcolor)

        # Border
        pen = QPen(self._border_qcolor)
        pen.setWidth(self.frame_thickness)
        painter.setBrush(Qt.NoBrush)
        painter.setPen(pen)
        # drawRect uses inclusive coordinates; adjust so 1px border is visible
        painter.drawRect(rect.adjusted(0, 0, -1, -1))


class Display(QLabel):

    def __init__(self, cutMode, pushbutton, slider, updatePaused, loaded, rectSelected, parentUpdate, pingpong, onBlackout):
        super().__init__()
        self.qt_img=None
        self.displayUid=0
        self.setStyleSheet("background : black; color: white;")
        self.button = pushbutton
        self.button.setVisible(False)
        self.slider = slider
        self.slider.setVisible(False)
        self.updatePaused = updatePaused
        self.loaded = loaded
        self.rectSelected = rectSelected
        self.parentUpdate = parentUpdate
        self.playtype_pingpong=pingpong
        self.onBlackout = onBlackout
        self.onUpdateFile=None
        self.onUpdateImage=None
        self.onCropOrTrim = None
        self.content_filter_callback = None
        self.sourcePixmap=None
        self.thread=None
        self.frame_count=-1
        self.imggeometry=None
        self.pos = None
        self.display_width = 3840
        self.display_height = 2160
        self.resize(self.display_width, self.display_height)
        self.setAlignment(Qt.AlignCenter)
        self.filepath = ""
        self.qt_img = None
        if cutMode:
            self.setCursor(Qt.CrossCursor)
        
        self.rubberBand = QRubberBandCustom(QRubberBand.Line, self)
        self.origin = QPoint()
        self.selection_rect = QRect()
        
        self.scene_intersections = []

        self.closeEvent = self.stopAndBlackout

        # Thumbnail-Label
        self.thumbnailsize=640
        self.thumbnail = QLabel(self)
        self.thumbnail.setFixedSize(self.thumbnailsize, self.thumbnailsize)
        self.thumbnail.setFrameStyle(QFrame.Box)
        self.thumbnail.setStyleSheet("background-color: black; border: 2px solid black;")
        self.thumbnail.hide()
        

    def hidePreview(self):
        self.thumbnail.hide()

    def _set_black_pixmap(self):
        try:
            self.qt_img = None
            self.imggeometry = self.size()
            blackpixmap = QPixmap(16, 16)
            blackpixmap.fill(Qt.black)
            self.setPixmap(blackpixmap.scaled(self.imggeometry.width(), self.imggeometry.height(), Qt.KeepAspectRatio))
            try:
                self.update()
                self.repaint()
            except Exception:
                pass
        except Exception:
            pass

    def showEvent(self, event):
        try:
            super().showEvent(event)
        except Exception:
            pass
        # Sobald sichtbar, kurz verzögert neu setzen
        try:
            QTimer.singleShot(0, self._refresh_after_load)
        except Exception:
            pass

    def updatePreview(self, relativePath):
        blackpixmap = QPixmap(self.thumbnailsize, self.thumbnailsize)
        blackpixmap.fill(Qt.black)
        self.thumbnail.setPixmap(blackpixmap)
        self.thumbnail.move(int(self.width()/2 - self.thumbnail.width()/2), int(self.height()/2 - self.thumbnail.height()/2))
        self.thumbnail.show()
        self.thumbnail.raise_()  # <-- Bringt die Vorschau in den Vordergrund!

        if cutModeFolderOverrideActive:
            folder=cutModeFolderOverridePath
        else:
            folder=os.path.join(path, "../../../../input/vr/check/rate")
        input=os.path.abspath(os.path.join(folder, relativePath))

        try:
            if input.endswith(tuple(VIDEO_EXTENSIONS)):
                    cap, tmp_video = open_videocapture_with_tmp(input)
                    try:
                        if cap.isOpened():
                            ret, cv_img = cap.read()
                            if not ret or cv_img is None:
                                return
                        else:
                            return
                    finally:
                        try:
                            cap.release()
                        except Exception:
                            pass
                        if 'tmp_video' in locals() and tmp_video:
                            try:
                                os.unlink(tmp_video)
                            except Exception:
                                pass
            else:
                cv_img  = safe_imread(input)
        
            rgb_image = cv2.cvtColor(cv_img, cv2.COLOR_BGR2RGB)
            h, w, ch = rgb_image.shape
            bytes_per_line = ch * w
            convert_cv_qt_img = QImage(rgb_image.data, w, h, bytes_per_line, QImage.Format_RGB888)
            preview_pixmap = QPixmap.fromImage(convert_cv_qt_img)
            try:
                if callable(self.content_filter_callback):
                    candidate = self.content_filter_callback(preview_pixmap.copy())
                    if candidate is not None and not candidate.isNull():
                        preview_pixmap = candidate
            except Exception:
                pass
            self.thumbnail.setPixmap(preview_pixmap.scaled(self.thumbnailsize, self.thumbnailsize, Qt.KeepAspectRatio))
        except:
            print(traceback.format_exc(), flush=True)
        

    def setPingPongModeEnabled(self, state):
        self.playtype_pingpong=state
        if not self.thread is None:
            self.thread.setPingPongModeEnabled(self.playtype_pingpong)


    def nextScene(self):
        if len(self.scene_intersections)>0:
            if self.thread:
                if not self.thread.isPaused():
                    self.thread.tooglePause()
                nextsceneframeindex=int(self.scene_intersections[0]*self.thread.getFPS())
                for t in self.scene_intersections:
                    idx=int(t*self.thread.getFPS())
                    if idx>self.thread.getCurrentFrameIndex():
                        nextsceneframeindex=idx
                        break
                        
                self.thread.seekRequest=nextsceneframeindex
                self.slider.setFocus()
            
    def applySceneIntersections(self, scene_intersections):
        self.scene_intersections=scene_intersections
        self.slider.applySceneIntersections(scene_intersections)
        
    def resizeEvent(self, event):
        super().resizeEvent(event)
        if self.qt_img:
            self.setPixmap(self.qt_img.scaled(event.size().width(), event.size().height(), Qt.KeepAspectRatio))
            #self.scaledPixmap=self.qt_img.scaled(event.size().width(), event.size().height(), Qt.KeepAspectRatio)
            #self.setPixmap(self.scaledPixmap)
        
    def getSourcePixmap(self):
        return self.sourcePixmap
        
    def getScaledPixmap(self):
        return self.scaledPixmap
        
    def minimumSizeHint(self):
        return QSize(50, 50)

    @pyqtSlot(ndarray, int)
    def update_image(self, cv_img, uid):
        if TRACELEVEL>=4:
            print("update_image", uid, self.displayUid, time.time() , flush=True)
        
        self.thumbnail.hide()
        # Ignore late updates from previous media; do not blank
        if uid != self.displayUid:
            return
        if cv_img is None or cv_img.size == 0:
            #print("update Image - none", flush=True)
            self._set_black_pixmap()
        else:
            #print("update Image - cv", flush=True)
            self.qt_img = self.convert_cv_qt(cv_img)
            
            w = self.qt_img.width()
            h = self.qt_img.height()
            #if TRACELEVEL >= 3:
            #    print("frame. w:", w, "h:", h, flush=True)
            
            self.imggeometry=self.size()
            #if TRACELEVEL >= 3:
            #    print("imggeometry. w:", self.imggeometry.width(), "h:", self.imggeometry.height(), flush=True)
            display_pixmap = self.qt_img
            try:
                if callable(self.content_filter_callback):
                    candidate = self.content_filter_callback(self.qt_img.copy())
                    if candidate is not None and not candidate.isNull():
                        display_pixmap = candidate
            except Exception:
                pass
            pm = display_pixmap.scaled(self.imggeometry.width(), self.imggeometry.height(), Qt.KeepAspectRatio)
            #if TRACELEVEL >= 3:
            #    print("pm. w:", pm.width(), "h:", pm.height(), flush=True)
            self.setPixmap(pm)
            # Ensure an immediate UI refresh regardless of media type
            try:
                self.update()
                self.repaint()
            except Exception:
                pass
            if self.onUpdateImage:
                try:
                    if self.thread:
                        self.onUpdateImage( self.thread.getCurrentFrameIndex() )
                        # Also notify parent to keep UI in sync
                        self.parentUpdate()
                    else:
                        self.onUpdateImage( -1 )
                        # For static images also trigger parent update to stabilize layout/overlays
                        if callable(self.parentUpdate):
                            self.parentUpdate()
                except Exception:
                    pass
                
    def getUnscaledPixmap(self, ):
        return self.sourcePixmap
         
    def convert_cv_qt(self, cv_img):    # scaled!
        rgb_image = cv2.cvtColor(cv_img, cv2.COLOR_BGR2RGB)
        h, w, ch = rgb_image.shape
        bytes_per_line = ch * w
        convert_cv_qt_img = QImage(rgb_image.data, w, h, bytes_per_line, QImage.Format_RGB888)
        self.sourcePixmap=QPixmap.fromImage(convert_cv_qt_img)

        h = self.display_height
        if h % 2 == 1:
            h -= 1
        self.scaledPixmap=convert_cv_qt_img.scaled(self.display_width, h, Qt.KeepAspectRatio)
        #self.setMaximumSize(QSize(self.scaledPixmap.width(), self.scaledPixmap.height()))
        pix = QPixmap.fromImage(self.scaledPixmap)
        return pix


    def showFile(self, filepath):
        self.stopAndBlackout()
        #print("Show file "  + filepath, flush=True) 

        if filepath.endswith(tuple(VIDEO_EXTENSIONS)):
            self.setVideo(filepath)
            return "video"
        else:
            self.setImage(filepath)
            return "image"

    def setVideo(self, filepath):
        self.frame_count=-1
        self.filepath = filepath
        self.displayUid+=1
        if self.onUpdateFile:
            self.onUpdateFile()
        self.startVideo(self.displayUid)

    def setImage(self, filepath):
        self.frame_count=-1
        self.filepath = filepath
        self.displayUid+=1
        if self.onUpdateFile:
            self.onUpdateFile()
        cv_img  = safe_imread(self.filepath)
        #print("setImage from cv2", flush=True)
        self.update_image(cv_img, self.displayUid)
        # In manchen Fällen erscheint das Bild erst nach Interaktion (z.B. Crop-Slider).
        # Ein kleiner verzögerter Refresh nach dem Laden stellt sicher, dass
        # die Anzeige aktualisiert wird, sobald der Event-Loop wieder läuft.
        try:
            QTimer.singleShot(DISPLAY_REFRESH_DELAY_MS, self._refresh_after_load)
        except Exception:
            pass

    def _refresh_after_load(self):
        try:
            # Warten, bis Widget sichtbar und mit gültiger Größe
            if not self.isVisible() or self.width() <= 0 or self.height() <= 0:
                try:
                    QTimer.singleShot(100, self._refresh_after_load)
                except Exception:
                    pass
                return

            # Falls bereits ein Bild vorhanden ist, erneut skaliert setzen und Redraw anstoßen
            if self.qt_img is not None:
                w = self.width()
                h = self.height()
                pm = self.qt_img.scaled(w, h, Qt.KeepAspectRatio)
                self.setPixmap(pm)
                # Leichte UI-Aktualisierung
                try:
                    self.update()
                    self.repaint()
                    QApplication.processEvents()
                except Exception:
                    pass

            # Fallback: wenn Pixmap noch leer, später erneut versuchen
            try:
                current_pm = self.pixmap()
                if current_pm is None or current_pm.isNull() or current_pm.width() == 0 or current_pm.height() == 0:
                    QTimer.singleShot(200, self._refresh_after_load)
            except Exception:
                pass
        except Exception:
            pass

    def stopAndBlackout(self):
        # Stop any running video and blank the display synchronously
        if self.thread:
            self.releaseVideo()
        self._set_black_pixmap()
        self.filepath = ""
        self.frame_count=-1
        self.scene_intersections = []
        self.onBlackout()
        
    def onNoFiles(self):
        self._set_black_pixmap()
        
    def registerForUpdates(self, onUpdateImage):
        self.onUpdateImage = onUpdateImage

    def registerForFileChange(self, onUpdateFile):
        self.onUpdateFile = onUpdateFile
        
    def registerForTrimUpdate(self, onCropOrTrim):
        self.onCropOrTrim = onCropOrTrim

    def registerForContentFilter(self, callback):
        self.content_filter_callback = callback

    def startVideo(self, uid):
        enterUITask()
        try:
            if self.thread:
                self.releaseVideo()
            try:
                self.button.clicked.disconnect(self.tooglePausePressed)
            except TypeError:
                pass
            self.button.setIcon(QIcon(os.path.join(path, '../../gui/img/pause80.png')))
            self.button.setVisible(True)
            self.thread = VideoThread(self, self.filepath, uid, self.slider, self.updatePaused, self.onVideoLoaded, self.playtype_pingpong)
            global rememberThread
            rememberThread.append(self.thread)
            self.trimAFrame=0
            self.trimBFrame=-1
            self.slider.resetAB()
            self.slider.setVisible(True)
            self.thread.change_pixmap_signal.connect(self.update_image)
            self.thread.start()
            self.button.clicked.connect(self.tooglePausePressed)
        except:
            print(traceback.format_exc(), flush=True)
        finally:
            leaveUITask()
            
            
    def releaseVideo(self):
        try:
            if self.thread:
                t=self.thread
                self.thread=None
                self.button.clicked.disconnect(self.tooglePausePressed)
                t.change_pixmap_signal.disconnect(self.update_image)
                t.requestStop()
                # t.deleteLater()
                self.update_image(np.array([]), -1)
        except:
            print(traceback.format_exc(), flush=True)

    def onVideoLoaded(self, count, fps, length):
        if self.thread:
            if not videoActive:
                self.button.clicked.disconnect(self.tooglePausePressed)
                self.thread=None
                self.frame_count=-1
                self.trimAFrame=0
                self.trimBFrame=-1
                self.slider.setText( "", Qt.white )
                self.slider.setPosTextValues( -1.0, -1)
            else:
                self.frame_count=self.thread.frame_count
                self.trimAFrame=0
                self.trimBFrame=self.frame_count-1
                self.slider.setText( self.buildSliderText(), Qt.white )
                self.slider.setPosTextValues( self.thread.fps, self.frame_count)
            self.button.setEnabled(True)
            self.button.setFocus()
            self.loaded(count, fps, length)
        
    def updatePaused(self, isPaused):
        self.update(isPaused)

    def tooglePausePressed(self):
        if self.thread:
            self.thread.tooglePause()
            self.button.setEnabled(True)
            if not self.thread.isPaused():
                self.button.setFocus()

    def isPaused(self):
        if self.thread:
            return self.thread.isPaused()
        else:
            return True

    def isTrimmed(self):
        return self.trimAFrame > 0 or self.trimBFrame < self.frame_count-1
        
    def buildSliderText(self):
        ms=int( 1000.0 * float( self.trimBFrame - self.trimAFrame) / float(self.thread.fps) )
        td = timedelta(milliseconds=ms)
        text=format_timedelta_hundredth(td)
        return text

    def trimFirst(self):
        if self.thread:
            count=self.thread.getFrameCount()
            if count>1:
                self.slider.setText("", Qt.white)
                newIndex=1
                newValue=float(newIndex/float(count-1))
                self.slider.setA(newValue)
                self.thread.setA(newIndex)
                self.trimAFrame=newIndex
                if self.onCropOrTrim:
                    self.onCropOrTrim()
        
    def trimToSnap(self):
        if self.thread and self.thread.getCurrentFrameIndex()>0:
            count=self.thread.getFrameCount()
            if count>1:
                self.slider.setText("", Qt.white)
                newIndex=self.thread.getCurrentFrameIndex()-1
                newValue=float(newIndex/float(count-1))
                self.slider.setB(newValue)
                self.thread.setB(newIndex)
                self.trimBFrame=newIndex
                if self.onCropOrTrim:
                    self.onCropOrTrim()

    def trimA(self):
        if self.thread:
            count=self.thread.getFrameCount()
            if count>1:
                newValue=float(self.thread.getCurrentFrameIndex())/float(count-1)
                if self.slider.getA()==newValue:
                    self.slider.setText("", Qt.white)
                    self.slider.setA(0.0)
                    self.thread.setA(0)
                    self.trimAFrame=0
                else:
                    self.slider.setA(newValue)
                    if TRACELEVEL >= 2:
                        print("setA", newValue, flush=True)
                    self.thread.setA(self.thread.getCurrentFrameIndex())
                    self.trimAFrame=self.thread.getCurrentFrameIndex()
                self.slider.setText( self.buildSliderText(), Qt.red if self.isTrimmed() else Qt.white )
            else:
                self.slider.setText("", Qt.white)
                self.slider.setA(0.0)
                self.thread.setA(0)
            if self.onCropOrTrim:
                self.onCropOrTrim()
        
    def trimB(self):
        if self.thread:
            count=self.thread.getFrameCount()
            if count>1:
                newValue=float(self.thread.getCurrentFrameIndex())/float(count-1)
                if self.slider.getB()==newValue:
                    self.slider.setText("", Qt.white)
                    self.slider.setB(1.0)
                    self.thread.setB(count-1)
                    self.thread.setB(count-1)
                else:
                    self.slider.setB(newValue)
                    if TRACELEVEL >= 2:
                        print("setB", newValue, flush=True)
                    self.trimBFrame=self.thread.getCurrentFrameIndex()
                    self.thread.setB(self.thread.getCurrentFrameIndex())
                self.slider.setText( self.buildSliderText(), Qt.red if self.isTrimmed() else Qt.white )
            else:
                self.slider.setText("", Qt.white)
                self.slider.setB(1.0)
                self.thread.setB(count-1)
            if self.onCropOrTrim:
                self.onCropOrTrim()

    def posA(self):
        if self.thread:
            self.thread.posA()
        
    def posB(self):
        if self.thread:
            self.thread.posB()

    def applyRubberBandColor(self):
        sel_rect = self.rubberBand.geometry()
        w = sel_rect.width()
        h = sel_rect.height()
        if w>0 and h>0:
            aspect = float(w) / float(h)
            min_aspect = 9.0 / 16.0
            max_aspect = 16.0 / 9.0

        if  w>0 and h>0 and (aspect < min_aspect or aspect > max_aspect):
            # print("applyRubberBandColor: setting OUT_OF_RANGE style", flush=True)
            # Use the custom API to set border + fill
            try:
                self.rubberBand.setColor("#FF3F00", "rgba(255, 63, 0, 50)", 5)
            except Exception:
                # Fallback to stylesheet if rubberBand is not the custom class
                self.rubberBand.setStyleSheet(
                    "border: 1px solid #FFFFFF; background-color: rgba(255, 255, 255, 50);"
                )

        else:
            # print("applyRubberBandColor: setting NORMAL style", flush=True)
            # Windows 11 style: Blue border, light blue fill, thin line
            try:
                self.rubberBand.setColor("#0078D7", "rgba(0, 120, 215, 50)", 1)
            except Exception:
                self.rubberBand.setStyleSheet(
                    "border: 1px solid #0078D7; background-color: rgba(0, 120, 215, 50);"
                )

    def enterEvent(self, event):
        self.setMouseTracking(True)
        super().enterEvent(event)

    def leaveEvent(self, event):
        self.setMouseTracking(False)
        self.pos = None
        super().leaveEvent(event)

    def mousePressEvent(self, event):
        if cutModeActive:
            """Startpunkt des Auswahlrechtecks"""
            if event.button() == Qt.LeftButton and self.underMouse():
                # start selecting rect
                self.origin = event.pos()
                self.rubberBand.setGeometry(QRect(self.origin, QSize()))
                self.applyRubberBandColor()
                self.rubberBand.setGeometry(QRect(self.origin, QSize()))
                self.rubberBand.show()
                #print("show!", flush=True)

    def mouseMoveEvent(self, event):
        # Für Lupe...
        self.pos = event.pos()
        
        if cutModeActive:
            # update rect while selecting
            if not self.origin == None and not self.origin.isNull():
                current_pos = event.pos()
                rect = QRect(self.origin, current_pos).normalized()
                self.rubberBand.setGeometry(rect)
                self.applyRubberBandColor()
                self.rubberBand.setGeometry(rect)
                #print("setGeometry!", flush=True)
                
        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event):
        self.origin=None
        if cutModeActive:
            # update rect on release and notify observer
            if event.button() == Qt.LeftButton and not self.sourcePixmap is None:
                self.selection_rect = self.rubberBand.geometry()
                self.rubberBand.hide()
                #print("hide!", flush=True)

                
                #print("rect", self.selection_rect.x(), self.selection_rect.y(), self.selection_rect.width(), self.selection_rect.height(), flush=True)
                      
                w1 = self.size().width()
                h1 = self.size().height()
                w2 = self.sourcePixmap.width()
                h2 = self.sourcePixmap.height()
                #print("sizes", w1, h1, "-->", w2, h2, flush=True)
                
                display_scalefactor=min( float(w1) / float(w2), float(h1) / float(h2) )
                offset_x1 = (w1 - w2 * display_scalefactor) / 2.0
                offset_y1 = (h1 - h2 * display_scalefactor) / 2.0
                #print("offsets", offset_x1, offset_y1, flush=True)

                x0 = self.selection_rect.x() - offset_x1
                y0 = self.selection_rect.y() - offset_y1
                w = self.selection_rect.width()
                h = self.selection_rect.height()
                #print("trans xywh", x0, y0, w, h, flush=True)
                if w<8 or h<8:
                    x0=0
                    y0=0
                    w=w1
                    h=h1
                    
                
                xs = int(float(x0) / display_scalefactor)
                ys = int(float(y0) / display_scalefactor)
                ws = int(float(w) / display_scalefactor)
                hs = int(float(h) / display_scalefactor)
                #print("src xywh", xs, ys, ws, hs, flush=True)

                if xs>=w2 or ys>=h2 or xs+ws<0 or ys+hs<0:
                    return
                srcRect=QRect(xs, ys, ws, hs)
                srcRect = srcRect.intersected(QRect(0, 0, w2, h2))
                #print("srcRect w2 h2", srcRect.width(), w2, srcRect.height(), h2, flush=True)
                #if srcRect.width()==w2 and srcRect.height()==h2:
                    #print("small!", flush=True)
                    #self.rubberBand.setGeometry(QRect(0,0,0,0))
                    
                #print("result", srcRect.x(), srcRect.y(), srcRect.width(), srcRect.height(), flush=True)
                self.rectSelected(srcRect)


class FrameSlider(QSlider):
    def __init__(self, orientation):
        super().__init__(orientation)
        self.resetAB()
        self.text=""
        self.postext = ""
        self.postextColor = Qt.cyan
        self.textColor=Qt.white
        self.fps=-1.0
        self.frame_count=-1
        self.setMinimumHeight(42)
        self.sliderMoved.connect(self.onSliderMoved)
        self.sliderReleased.connect(self.onSliderReleased)
        self.setTracking(True)
        self.setCursor(Qt.PointingHandCursor)
        self.scene_intersections = []
        self.isHovered=False
        self._hasFocus=False

     
    def resetAB(self):
        self.a = 0.0
        self.b = 1.0
        
    def setA(self, a):
        self.a = min(max(0.0, a), 1.0)
        self.update()

    def setB(self, b):
        self.b = min(max(0.0, b), 1.0)
        self.update()

    def getA(self):
        return self.a

    def getB(self):
        return self.b

    def setText(self, text, textColor=Qt.white):
        self.text = text
        self.textColor = textColor
        self.update()

    def setPosTextValues(self, fps, frame_count):
        self.fps=fps
        self.frame_count=frame_count

    def _setTempPositioningText(self, sliderpos, text, textColor):
        self.postext = text
        self.postextColor = textColor
        self.sliderpos = sliderpos
        self.update()

    def applySceneIntersections(self, scene_intersections):
        self.scene_intersections = scene_intersections
        self.update()

    def paintEvent(self, event: QPaintEvent):

        super().paintEvent(event)

        try:
            with QPainter(self) as painter:
                
                geo = self.geometry()

                x = geo.x()
                y = geo.y()
                width = geo.width()
                height = geo.height()

                painter.fillRect(x, y, width, height, QColor(220,0,0))
        
                painter.setPen(QPen(Qt.red, 4, Qt.SolidLine, Qt.RoundCap))
                if self.a > 0.0:
                    painter.drawLine(0, 0, int(width*self.a), 0)
                if self.b < 1.0:
                    painter.drawLine(int(width*self.b), 0, width, 0)

                painter.setPen(QPen(self.textColor if self.postext == "" else self.postextColor, 2, Qt.SolidLine, Qt.RoundCap))
                rct = QRect(0, 0, width, height)
                font=painter.font()
                font.setPointSize(10)
                painter.setFont(font)
                # QPoint(int(width-1), int(height-1))
                if self.postext == "":
                    painter.drawText(rct, (Qt.AlignRight if self.textColor==Qt.white else Qt.AlignCenter) | Qt.AlignBottom, self.text)
                else:
                    rct = QRect(0, 0, width, height)
                    painter.drawText(rct, Qt.AlignCenter | Qt.AlignBottom, self.postext)

                vlen=(self.frame_count-1)/self.fps
                if vlen>0:
                    painter.setPen(QPen(Qt.red, 4, Qt.SolidLine, Qt.RoundCap))
                    for t in self.scene_intersections:
                        x=width*t/vlen
                        painter.drawPoint(QPointF(x, height-1))
                        #print(str(t), str(x), str(vlen), str(width), flush=True)
        except:       
            print(traceback.format_exc(), flush=True)

    def buildPosSliderText(self, sliderpos):
        ms=int( 1000.0 * sliderpos * (self.frame_count) / float(self.fps) )
        td = timedelta(milliseconds=ms)
        text=format_timedelta_hundredth(td)
        return text

    def onSliderReleased(self):
        if not self.isHovered and not self._hasFocus:
            self._setTempPositioningText(0.5, "", Qt.cyan)
        self.setCursor(Qt.PointingHandCursor)
        slider=self

        
    def onSliderMoved(self, value):
        sliderpos = self.value() / (self.maximum()+1)
        self._setTempPositioningText(sliderpos, self.buildPosSliderText(sliderpos), Qt.cyan)
        self.setCursor(Qt.SizeHorCursor)
        
    def mousePressEvent(self, event):
        super(FrameSlider, self).mousePressEvent(event)
        if event.button() == Qt.LeftButton:
            val = self.pixelPosToRangeValue(event.pos())
            self.setValue(val)
            self.onSliderMouseClick()

    def pixelPosToRangeValue(self, pos):
        opt = QStyleOptionSlider()
        self.initStyleOption(opt)
        gr = self.style().subControlRect(QStyle.CC_Slider, opt, QStyle.SC_SliderGroove, self)
        sr = self.style().subControlRect(QStyle.CC_Slider, opt, QStyle.SC_SliderHandle, self)

        if self.orientation() == Qt.Horizontal:
            sliderLength = sr.width()
            sliderMin = gr.x()
            sliderMax = gr.right() - sliderLength + 1
        else:
            sliderLength = sr.height()
            sliderMin = gr.y()
            sliderMax = gr.bottom() - sliderLength + 1;
        pr = pos - sr.center() + sr.topLeft()
        p = pr.x() if self.orientation() == Qt.Horizontal else pr.y()
        return QStyle.sliderValueFromPosition(self.minimum(), self.maximum(), p - sliderMin,
                                               sliderMax - sliderMin, opt.upsideDown)

    def registerForMouseEvent(self, onSliderMouseClick):
        self.onSliderMouseClick=onSliderMouseClick
        
    def focusInEvent(self, event):
        self._hasFocus=True
        sliderpos = self.value() / (self.maximum()+1)
        self._setTempPositioningText(sliderpos, self.buildPosSliderText(sliderpos), Qt.cyan)
        super().focusInEvent(event)  # wichtig: Standardverhalten beibehalten

    def focusOutEvent(self, event):
        self._hasFocus=False
        if not self.isHovered and not self._hasFocus:
            self._setTempPositioningText(0.5, "", Qt.cyan)
        super().focusOutEvent(event)
        
    def enterEvent(self, event):
        self.isHovered=True
        sliderpos = self.value() / (self.maximum()+1)
        self._setTempPositioningText(sliderpos, self.buildPosSliderText(sliderpos), Qt.cyan)
        super().enterEvent(event)

    def leaveEvent(self, event):
        self.isHovered=False
        if not self.isHovered and not self._hasFocus:
            self._setTempPositioningText(0.5, "", Qt.cyan)
        super().leaveEvent(event)

    def sliderChanged(self, value):
        if self.isHovered or self._hasFocus:
            sliderpos = value / (self.maximum()+1)
            self._setTempPositioningText(sliderpos, self.buildPosSliderText(sliderpos), Qt.cyan)
        
class CropWidget(QWidget):
    def __init__(self, display, parent=None):
        """
        CropWidget, das erst später angewiesen wird, welches Bild aus einem externen QLabel verwendet werden soll.
        """
        super().__init__(parent)

        self.onCropOrTrim = None
        self.currentFrameIndex = -1
        self.zoom_factor = 4
        self.magsize = 150
        self.center_x = -1
        
        #self.setWindowTitle("Bild zuschneiden mit Lupenansicht")
        self.setMinimumSize(1000, 750)

        # Internes Label, in dem wir das Bild anzeigen
        self.image_label = display
        self.image_label.registerForUpdates(self.imageUpdated)
        self.image_label.registerForFileChange(self.fileChanged)
        self.content_filter_callback = None
        #self.image_label.setAlignment(Qt.AlignCenter)
        #self.image_label.setFrameStyle(QFrame.Box)
        #self.image_label.setStyleSheet("background-color: black;")

        # Noch kein Bild vorhanden
        self.original_pixmap = None
        self.display_pixmap = None
        self.slidersInitialized = False
        self.currentW=0
        self.currentH=0
        self.scene_intersections=[]

        # Crop-Werte
        self.crop_left = 0
        self.crop_right = 0
        self.crop_top = 0
        self.crop_bottom = 0
        self.clean = True;
        
        # Standard-Rahmen-Einstellungen
        self.frame_color = QColor(255, 255, 255)  # Weiß
        self.frame_thickness = 2
        self.frame_style = Qt.DashLine

        # Slider
        self.slider_left = self.create_slider(Qt.Horizontal, False)
        self.slider_left.setFocusPolicy(Qt.ClickFocus)
        self.slider_right = self.create_slider(Qt.Horizontal, True)
        self.slider_right.setFocusPolicy(Qt.ClickFocus)
        self.slider_top = self.create_slider(Qt.Vertical, True)
        self.slider_top.setFocusPolicy(Qt.ClickFocus)
        self.slider_bottom = self.create_slider(Qt.Vertical, False)
        self.slider_bottom.setFocusPolicy(Qt.ClickFocus)

        # Lupen-Label
        self.magnifier = QLabel(self)
        self.magnifier.setFixedSize(self.magsize, self.magsize)
        self.magnifier.setFrameStyle(QFrame.Box)
        self.magnifier.setStyleSheet("background-color: black; border: 2px solid gray;")
        self.magnifier.hide()

 
        # Layouts
        self.main_layout = QGridLayout()
        main_layout=self.main_layout
        
        iw=200
        cw=5
        
        self.sp1=QLabel()
        self.sp1.setMinimumHeight(32)
        self.sp1.setMinimumWidth(32)
        self.sp2=QLabel()
        self.sp2.setMinimumHeight(32)
        self.sp2.setMinimumWidth(32)
        
        main_layout.addWidget(self.sp1,           0,     0,           cw, cw)
        main_layout.addWidget(self.slider_left,   0,     cw,          cw, iw,       alignment=Qt.AlignmentFlag.AlignBottom|Qt.AlignmentFlag.AlignHCenter)

        main_layout.addWidget(self.slider_top,    cw,    0,           iw, cw,       alignment=Qt.AlignmentFlag.AlignRight|Qt.AlignmentFlag.AlignVCenter)
        main_layout.addWidget(self.image_label,   cw,    cw,          iw, iw)
        main_layout.addWidget(self.slider_bottom, cw,    cw+iw,       iw, cw,       alignment=Qt.AlignmentFlag.AlignLeft|Qt.AlignmentFlag.AlignVCenter)

        main_layout.addWidget(self.slider_right,  cw+iw, cw,          cw, iw,       alignment=Qt.AlignmentFlag.AlignTop|Qt.AlignmentFlag.AlignHCenter)
        main_layout.addWidget(self.sp2,           cw+iw, cw+iw,       cw, cw)

        # Buttons unten
        #controls_layout = QHBoxLayout()
        #main_layout.addLayout(controls_layout, 3, 0, 1, 1002)

        '''
        ow=1
        cw=2
        self.spUL=QLabel()
        self.spUL.setMinimumHeight(1)
        self.spUL.setMinimumWidth(1)
        self.spBR=QLabel()
        self.spBR.setMinimumHeight(1)
        self.spBR.setMinimumWidth(1)
        self.outer_layout = QGridLayout()
        self.outer_layout.addWidget(self.spUL,           0,     0,           ow, ow)
        self.outer_layout.addLayout(main_layout,         ow,    ow,          cw, cw)
        self.outer_layout.addWidget(self.spBR,           ow+cw,  ow+cw,      ow, ow)
        '''
        self.setLayout(self.main_layout)

        # Signale verbinden
        self.slider_left.valueChanged.connect(lambda val: self.update_crop("left", val))
        self.slider_right.valueChanged.connect(lambda val: self.update_crop("right", val))
        self.slider_top.valueChanged.connect(lambda val: self.update_crop("top", val))
        self.slider_bottom.valueChanged.connect(lambda val: self.update_crop("bottom", val))
        
        # Slider deaktivieren, bis Bild geladen
        self.enable_sliders(False)
        self.display_sliders(False)
        
        # Hotkey STRG+S zum Speichern
        #self.save_shortcut = QShortcut(QKeySequence("Ctrl+S"), self)
        
        self.resizeEvent(None)

    def applySceneIntersections(self, scene_intersections):
        self.scene_intersections = scene_intersections
        self.image_label.applySceneIntersections(scene_intersections)
        
    def fileChanged(self):
        if TRACELEVEL >= 2:
            print("fileChanged", flush=True)
        self.sourceWidth=0
        self.sourceHeight=0
        
        self.scene_intersections=[]

        # Crop-Werte zurücksetzen
        self.crop_left = 0
        self.crop_right = 0
        self.crop_top = 0
        self.crop_bottom = 0
        self.clean = True;
        
        self.slider_right.setValue(0)
        self.slider_left.setValue(0)
        self.slider_bottom.setValue(0)
        self.slider_top.setValue(0)
        
        self.slidersInitialized = False
        self.enable_sliders(False)
        
        self.resizeEvent(None)

    def resizeEvent(self, newSize):
        sourcePixmap = self.image_label.getSourcePixmap()
        if sourcePixmap is None or sourcePixmap.isNull():
            return

        #print("resizeEvent", newSize, flush=True)
        w1 = self.image_label.size().width()
        h1 = self.image_label.size().height()

        if w1==self.currentW or h1==self.currentH:
            return
           
        self.currentW=w1
        self.currentH=h1

        #self.sp1.setMinimumHeight(32)
        #self.sp2.setMinimumHeight(32)
            
        w2 = sourcePixmap.width()
        h2 = sourcePixmap.height()
        #print("sizes", w1, h1, "-->", w2, h2, flush=True)
        
        display_scalefactor=min( float(w1) / float(w2), float(h1) / float(h2) )
        pad_x = (w1 - w2 * display_scalefactor) 
        pad_y = (h1 - h2 * display_scalefactor) 
        #print("padding", pad_x, pad_y, flush=True)

        w  = int(w1 - pad_x)
        h  = int(h1 - pad_y)

        self.slider_left.setMinimumWidth(w)
        self.slider_left.setMaximumWidth(w)
        self.slider_right.setMinimumWidth(w)
        self.slider_right.setMaximumWidth(w)
        self.slider_top.setMinimumHeight(h)
        self.slider_top.setMaximumHeight(h)
        self.slider_bottom.setMinimumHeight(h)
        self.slider_bottom.setMaximumHeight(h)
        

    def imageUpdated(self, currentFrameIndex):
        if TRACELEVEL >= 4:
            print("imageUpdated", currentFrameIndex, flush=True)

        self.currentFrameIndex = currentFrameIndex
       
        sourcePixmap = self.image_label.getSourcePixmap()
        if sourcePixmap is None or sourcePixmap.isNull():
            raise ValueError("Das Source Image enthält kein gültiges Bild.")

        filtered_pixmap = sourcePixmap.copy()
        try:
            if callable(self.content_filter_callback):
                candidate = self.content_filter_callback(filtered_pixmap)
                if candidate is not None and not candidate.isNull():
                    filtered_pixmap = candidate
        except Exception:
            pass
        
        self.sourceWidth=filtered_pixmap.width()
        self.sourceHeight=filtered_pixmap.height()
        #print("sourcePixmap", self.sourceWidth, self.sourceHeight, flush=True)
        
        scaledPixmap = self.image_label.getScaledPixmap()
        self.scaledWidth=filtered_pixmap.width()
        self.scaledHeight=filtered_pixmap.height()
        #print("scaledPixmap", self.scaledWidth, self.scaledHeight, flush=True)

        self.original_pixmap = filtered_pixmap.copy()
        w = self.original_pixmap.width()
        h = self.original_pixmap.height()
        #print("original_pixmap", w, h, flush=True)
        
        
        self.display_pixmap = filtered_pixmap.copy()
        self.image_label.setPixmap(self.display_pixmap)

        self.update_slider_ranges()
        if not self.slidersInitialized:
            # Slider aktivieren und konfigurieren
            self.enable_sliders(True)
            self.slidersInitialized = True

        self.apply_crop()
        
        self.resizeEvent(None)
        
        self.main_layout.invalidate()

    def refresh_filtered_view(self):
        try:
            self.imageUpdated(self.currentFrameIndex)
            self.image_label.update()
            self.image_label.repaint()
        except Exception:
            pass


class InpaintOverlay(QWidget):
    """Transparent overlay used for painting an inpaint mask on top of the image label."""
    executeRequested = pyqtSignal()
    
    class TaskComboBox(QComboBox):
        """ComboBox that (re)populates with available tasks containing 'inpaint' when opened."""
        def __init__(self, parent=None):
            super().__init__(parent)
            self.setCursor(Qt.PointingHandCursor)
            self.setEditable(False)
            self.populate()

        def populate(self):
            try:
                self.blockSignals(True)
                self.clear()
                names = _list_valid_inpaint_tasks()
                # prefer explicit 'inpaint-sd15' as the startup default if present
                preferred = "inpaint-sd15"
                for n in names:
                    self.addItem(n)
                # choose startup selection: prefer persisted selection, then fallback default
                try:
                    idx = -1
                    if selected_inpaint_task and selected_inpaint_task in names:
                        idx = self.findText(selected_inpaint_task)
                    elif preferred in names:
                        idx = self.findText(preferred)
                        set_selected_inpaint_task(preferred)
                    elif len(names) > 0:
                        idx = 0
                        set_selected_inpaint_task(names[0])
                    if idx >= 0:
                        self.setCurrentIndex(idx)
                except Exception:
                    pass
            except Exception:
                pass
            finally:
                try:
                    self.blockSignals(False)
                except Exception:
                    pass

        def showPopup(self):
            # refresh list each time the user opens the dropdown
            try:
                self.populate()
            except Exception:
                pass
            super().showPopup()
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setAttribute(Qt.WA_TransparentForMouseEvents, True)
        self.setAttribute(Qt.WA_NoSystemBackground, True)
        self.setAttribute(Qt.WA_TranslucentBackground, True)
        self.setMouseTracking(True)
        self._init_mask()
        self.drawing = False
        self.brush_size = int(selected_inpaint_brush_size)
        self._last_pos = None
        # UI controls (created but hidden by default)
        self.control_widget = None
        self.brush_slider = None
        self.brush_label = None
        self._create_controls()

    def _init_mask(self, size=None):
        if size is None and self.parent() is not None:
            size = self.parent().size()
        if size is None:
            size = QSize(1, 1)
        self.mask = QImage(size, QImage.Format_ARGB32)
        self.mask.fill(Qt.transparent)

    def ensure_mask_size(self, size):
        if self.mask.size() != size:
            self._init_mask(size)
            self.update()
            # adjust control widget geometry if present
            if self.control_widget is not None:
                self._position_controls()

    def clear_mask(self):
        self.mask.fill(Qt.transparent)
        self.update()
        try:
            # Disable export button when mask is cleared
            if hasattr(self, 'execute_button') and self.execute_button is not None:
                self.execute_button.setEnabled(False)
            if hasattr(self, 'clear_button') and self.clear_button is not None:
                self.clear_button.setEnabled(False)
        except Exception:
            pass

    def paintEvent(self, event):
        if self.mask is None:
            return
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        # Show mask semi-transparently while mask itself stores full-opacity coverage
        try:
            painter.setOpacity(0.55)
        except Exception:
            pass
        painter.drawImage(0, 0, self.mask)
        painter.end()

    def _draw_circle(self, pos):
        if self.mask is None:
            return
        painter = QPainter(self.mask)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.setPen(Qt.NoPen)
        # paint fully opaque mask pixels (alpha=255) to ensure contiguous coverage
        painter.setBrush(QColor(255, 0, 0, 255))
        r = int(self.brush_size / 2)
        painter.drawEllipse(pos, r, r)
        painter.end()

        # Ensure we didn't draw outside the visible pixmap area
        try:
            self._clear_outside_mask_area()
        except Exception:
            pass

        self.update()
        try:
            # Enable Export button when painting occurs
            if hasattr(self, 'execute_button') and self.execute_button is not None:
                self.execute_button.setEnabled(True)
            if hasattr(self, 'clear_button') and self.clear_button is not None:
                self.clear_button.setEnabled(True)
        except Exception:
            pass

    def _draw_line(self, p1, p2):
        """Draw a continuous stroke between p1 and p2 using a pen with round cap."""
        if self.mask is None:
            return
        painter = QPainter(self.mask)
        try:
            painter.setRenderHint(QPainter.Antialiasing)
            # pen uses full alpha so mask becomes continuous; visualization opacity
            # is handled in paintEvent above.
            pen = QPen(QColor(255, 0, 0, 255))
            pen.setWidth(int(self.brush_size))
            pen.setCapStyle(Qt.RoundCap)
            pen.setJoinStyle(Qt.RoundJoin)
            painter.setPen(pen)
            painter.setBrush(Qt.NoBrush)
            painter.drawLine(p1, p2)
        finally:
            painter.end()

        try:
            self._clear_outside_mask_area()
        except Exception:
            pass

        self.update()
        try:
            # Enable Export button when painting occurs
            if hasattr(self, 'execute_button') and self.execute_button is not None:
                self.execute_button.setEnabled(True)
            if hasattr(self, 'clear_button') and self.clear_button is not None:
                self.clear_button.setEnabled(True)
        except Exception:
            pass

    def _clear_outside_mask_area(self):
        """Clear mask pixels that lie outside the displayed pixmap region.

        The overlay covers the entire QLabel (`self.parent()`); the actual image
        may be centered with padding. Compute the pixmap rect inside the label
        and clear any mask pixels outside that rect.
        """
        if self.mask is None:
            return
        parent = self.parent()
        if parent is None:
            return
        pix = None
        try:
            pix = parent.pixmap()
        except Exception:
            pix = None
        if pix is None or pix.isNull():
            return

        lw = self.width()
        lh = self.height()
        pw = pix.width()
        ph = pix.height()

        # compute offsets (pixmap is centered in the label due to alignment)
        offset_x = int((lw - pw) / 2)
        offset_y = int((lh - ph) / 2)

        # clamp values
        if pw <= 0 or ph <= 0:
            return

        left_w = max(0, offset_x)
        top_h = max(0, offset_y)
        right_x = max(0, offset_x + pw)
        bottom_y = max(0, offset_y + ph)

        painter = QPainter(self.mask)
        try:
            painter.setCompositionMode(QPainter.CompositionMode_Clear)
            # top strip
            if top_h > 0:
                painter.fillRect(0, 0, lw, top_h, QColor(0, 0, 0, 0))
            # bottom strip
            if bottom_y < lh:
                painter.fillRect(0, bottom_y, lw, lh - bottom_y, QColor(0, 0, 0, 0))
            # left strip
            if left_w > 0:
                painter.fillRect(0, top_h, left_w, max(0, ph), QColor(0, 0, 0, 0))
            # right strip
            if right_x < lw:
                painter.fillRect(right_x, top_h, lw - right_x, max(0, ph), QColor(0, 0, 0, 0))
        finally:
            painter.end()

    def _create_controls(self):
        try:
            self.control_widget = QWidget(self)
            # Container with black background and gold border
            self.control_widget.setStyleSheet("background-color: black; border: 2px solid gold; border-radius: 6px;")
            vlayout = QVBoxLayout(self.control_widget)
            # left-align children so controls sit aligned to the left edge
            try:
                vlayout.setAlignment(Qt.AlignLeft)
            except Exception:
                pass
            layout1 = QHBoxLayout()
            layout1.setContentsMargins(8, 6, 8, 6)
            try:
                layout1.setAlignment(Qt.AlignLeft)
            except Exception:
                pass
            # Brush label (transparent background to let container show)
            self.brush_label = QLabel(f"Brush: {self.brush_size}", self.control_widget)
            self.brush_label.setStyleSheet("color: white; border: none;")
            self.brush_label.setFixedWidth(70)
            # Slider for brush size
            self.brush_slider = QSlider(Qt.Horizontal, self.control_widget)
            self.brush_slider.setStyleSheet("color: white; border: none;")
            self.brush_slider.setRange(1, 200)
            self.brush_slider.setValue(self.brush_size)
            self.brush_slider.setFixedWidth(160)
            # Clear mask button (no gold border; container shows gold)
            self.clear_button = QPushButton("Clear Mask", self.control_widget)
            self.clear_button.setStyleSheet(
                "QPushButton { color: white; background-color: black; border: 1px solid white; padding: 4px; border-radius: 4px; }"
                "QPushButton:disabled { color: #777777; background-color: #444444; border: 1px solid #666666; }"
            )
            self.clear_button.setFixedWidth(100)
            self.clear_button.setCursor(Qt.PointingHandCursor)
            # Execute/Export button: will later perform export of mask/background
            self.execute_button = QPushButton("Export", self.control_widget)
            self.execute_button.setStyleSheet(
                "QPushButton { color: white; background-color: black; border: 1px solid white; padding: 4px; border-radius: 4px; }"
                "QPushButton:disabled { color: #777777; background-color: #444444; border: 1px solid #666666; }"
            )
            self.execute_button.setFixedWidth(100)
            self.execute_button.setCursor(Qt.PointingHandCursor)
            # start disabled until user paints (both Export and Clear)
            try:
                self.execute_button.setEnabled(False)
                self.clear_button.setEnabled(False)
            except Exception:
                pass
            # Add widgets to layout
            layout1.addWidget(self.brush_label)
            layout1.addWidget(self.brush_slider)
            vlayout.addLayout(layout1)
            layout2 = QHBoxLayout()
            layout2.setContentsMargins(8, 6, 8, 6)
            try:
                layout2.setAlignment(Qt.AlignLeft)
            except Exception:
                pass
            # Place Clear on this row
            layout2.addWidget(self.clear_button)
            vlayout.addLayout(layout2)

            # Third row: Task dropdown + Export button
            layout3 = QHBoxLayout()
            layout3.setContentsMargins(8, 6, 8, 6)
            try:
                layout3.setAlignment(Qt.AlignLeft)
            except Exception:
                pass
            # Task selector: shows available tasks containing 'inpaint'
            try:
                self.task_combo = InpaintOverlay.TaskComboBox(self.control_widget)
                self.task_combo.setFixedWidth(180)
                self.task_combo.setStyleSheet("color: white; background-color: black; border: 1px solid white; padding: 2px; border-radius: 4px;")
                # update global when selection changes
                self.task_combo.currentTextChanged.connect(lambda txt: set_selected_inpaint_task(txt))
                layout3.addWidget(self.task_combo)
            except Exception:
                self.task_combo = None

            layout3.addWidget(self.execute_button)
            vlayout.addLayout(layout3)
            self.control_widget.hide()
            # Connect signals
            self.brush_slider.valueChanged.connect(self._on_brush_slider_changed)
            self.clear_button.clicked.connect(lambda: self.clear_mask())
            # Emit signal when Execute pressed; handler lives in InpaintCropWidget
            self.execute_button.clicked.connect(lambda: self.executeRequested.emit())
            # compute control widget width to avoid overlap
            self._position_controls()
        except Exception:
            self.control_widget = None
            self.brush_slider = None
            self.brush_label = None

    def _position_controls(self):
        if self.control_widget is None:
            return
        w = self.width()
        h = self.height()
        layout = self.control_widget.layout()
        # calculate width from children preferred/fixed sizes plus margins and spacing
        try:
            left = layout.contentsMargins().left()
            right = layout.contentsMargins().right()
            spacing = layout.spacing()
        except Exception:
            left = right = spacing = 8

        # Prefer actual widget sizes (fixed widths) otherwise fall back to sizeHint
        try:
            lw = self.brush_label.width() if self.brush_label is not None else 0
            if lw == 0 and self.brush_label is not None:
                lw = self.brush_label.sizeHint().width()
        except Exception:
            lw = 0
        try:
            sw = self.brush_slider.width() if self.brush_slider is not None else 0
            if sw == 0 and self.brush_slider is not None:
                sw = self.brush_slider.sizeHint().width()
        except Exception:
            sw = 0
        try:
            bw = self.clear_button.width() if self.clear_button is not None else 0
            if bw == 0 and self.clear_button is not None:
                bw = self.clear_button.sizeHint().width()
        except Exception:
            bw = 0

        cw = left + lw + spacing + sw + spacing + bw + right
        # minimal safety width
        if cw < 160:
            cw = 160

        # compute control height from layout/content or fallback
        ch = self.control_widget.sizeHint().height() if self.control_widget.sizeHint().height() > 0 else 36

        # place bottom-left with margin
        margin = 8
        x = margin
        y = max(0, h - ch - margin)
        self.control_widget.setGeometry(x, y, cw, ch)
        # ensure it's on top of overlay
        try:
            self.control_widget.raise_()
        except Exception:
            pass

    def _on_brush_slider_changed(self, val):
        try:
            self.brush_size = int(val)
            set_selected_inpaint_brush_size(self.brush_size)
            if self.brush_label:
                self.brush_label.setText(f"Brush: {self.brush_size}")
        except Exception:
            pass

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton and not self.testAttribute(Qt.WA_TransparentForMouseEvents):
            self.drawing = True
            pos = event.pos()
            self._last_pos = pos
            self._draw_circle(pos)

    def mouseMoveEvent(self, event):
        if self.drawing and not self.testAttribute(Qt.WA_TransparentForMouseEvents):
            pos = event.pos()
            if self._last_pos is None:
                self._draw_circle(pos)
                self._last_pos = pos
            else:
                # draw continuous line between last and current
                self._draw_line(self._last_pos, pos)
                self._last_pos = pos

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.drawing = False
            self._last_pos = None


class InpaintCropWidget(CropWidget):
    """CropWidget variant that supports painting an inpaint mask via an overlay."""
    def __init__(self, display, parent=None):
        super().__init__(display, parent)
        self.inpaint_mode = False
        # Create overlay as a child of the image_label so it sits on top
        try:
            self.overlay = InpaintOverlay(self.image_label)
            self.overlay.setGeometry(0, 0, self.image_label.width(), self.image_label.height())
            self.overlay.hide()
            # connect Execute signal if overlay provides it
            try:
                self.overlay.executeRequested.connect(self._on_execute)
            except Exception:
                pass
        except Exception:
            self.overlay = None

        # Watch for resizes of the underlying image_label
        try:
            self.image_label.installEventFilter(self)
        except Exception:
            pass

    def eventFilter(self, obj, event):
        # Keep overlay sized to image_label
        try:
            if obj is self.image_label and event.type() == QEvent.Resize and self.overlay:
                new_size = event.size()
                self.overlay.setGeometry(0, 0, new_size.width(), new_size.height())
                self.overlay.ensure_mask_size(new_size)
        except Exception:
            pass
        return super().eventFilter(obj, event)

    def setInpaintMode(self, enabled: bool):
        self.inpaint_mode = bool(enabled)
        self.overlay.clear_mask()
        if self.overlay is None:
            return
        # Keep overlay visible so mask is always shown; intercept events only in inpaint mode
        try:
            if enabled:
                self.overlay.show()
            else:
                self.overlay.hide()
        except Exception:
            pass

        # Toggle event transparency so overlay intercepts events only when inpaint_mode
        self.overlay.setAttribute(Qt.WA_TransparentForMouseEvents, not self.inpaint_mode)

        try:
            # Always use ArrowCursor in the drawing area
            self.overlay.setCursor(QCursor(Qt.ArrowCursor))
        except Exception:
            pass

        # Show/hide control widget, position it and ensure it accepts mouse events when visible
        try:
            if hasattr(self.overlay, 'control_widget') and self.overlay.control_widget is not None:
                if self.inpaint_mode:
                    try:
                        self.overlay.control_widget.show()
                        # reposition and size correctly
                        self.overlay._position_controls()
                        # make sure it's on top and accepts events
                        self.overlay.control_widget.raise_()
                        self.overlay.control_widget.setAttribute(Qt.WA_TransparentForMouseEvents, False)
                    except Exception:
                        pass
                else:
                    try:
                        self.overlay.control_widget.setAttribute(Qt.WA_TransparentForMouseEvents, True)
                        self.overlay.control_widget.hide()
                    except Exception:
                        pass
        except Exception:
            pass

    def getInpaintMask(self) -> QImage:
        """Return the current inpaint mask as QImage (transparent = not masked)."""
        if self.overlay is None:
            return QImage()
        return self.overlay.mask

    def _on_execute(self):
        """Save the cropped background image and inpaint mask.
        
        First saves the cropped background image as PNG to rfolder+"/edit" with _N suffix.
        Then saves the current inpaint mask as BMP in original-image resolution,
        cropped to the current crop rectangle. Filename uses the same base
        name as the currently displayed image, with .bmp extension.
        """
        final_bg_path = None
        final_mask_path = None
        target_folder = None
        try:
            if self.overlay is None or self.original_pixmap is None:
                return
            # Use image_label.filepath for the source filename
            filepath = getattr(self.image_label, 'filepath', '')
            if not filepath:
                return

            mask = self.overlay.mask
            if mask is None:
                return

            # Determine overlay/label and displayed pixmap geometry
            lw = self.overlay.width()
            lh = self.overlay.height()
            pix = self.image_label.pixmap()
            if pix is None or pix.isNull():
                return
            pw = pix.width()
            ph = pix.height()

            # compute offsets (pixmap centered in label)
            offset_x = int((lw - pw) / 2)
            offset_y = int((lh - ph) / 2)

            # extract mask region corresponding to the displayed pixmap
            display_mask = mask.copy(offset_x, offset_y, pw, ph)

            # scale mask to original image resolution
            w_orig = self.original_pixmap.width()
            h_orig = self.original_pixmap.height()
            if pw <= 0 or ph <= 0 or w_orig <= 0 or h_orig <= 0:
                return
            scaled_mask = display_mask.scaled(w_orig, h_orig, Qt.IgnoreAspectRatio, Qt.SmoothTransformation)

            crop_rect = self.get_export_crop_rect()
            if crop_rect.isNull() or crop_rect.width() <= 0 or crop_rect.height() <= 0:
                return
            x0 = int(crop_rect.x())
            y0 = int(crop_rect.y())
            crop_w = int(crop_rect.width())
            crop_h = int(crop_rect.height())

            # Use the currently selected inpaint task (stored in `selected_inpaint_task`)
            selected_task = _resolve_valid_inpaint_task(selected_inpaint_task)
            set_selected_inpaint_task(selected_task)
            if not _is_valid_inpaint_task(selected_task):
                raise RuntimeError(f"Invalid inpaint task selection: {selected_task}")
            target_folder = os.path.abspath(os.path.join(path, "../../../../input/vr/tasks", selected_task))

            # ========== STEP 1: Save cropped background image ==========
            # Crop the original image to the crop rectangle
            cropped_image = self.original_pixmap.copy(crop_rect)

            # Determine output directory for background image
            rfolder = os.path.join(path, "../../../../input/vr/check/rate")
            bg_dirpath = os.path.abspath(os.path.join(rfolder, "edit"))
            os.makedirs(bg_dirpath, exist_ok=True)

            # Build unique filename with _N suffix
            # Check in edit, selected task folder, and selected task's done folder
            base = os.path.splitext(os.path.basename(filepath))[0]
            n = 1
            while (os.path.exists(os.path.join(bg_dirpath, f"{base}_{n}.png")) or
                        os.path.exists(os.path.join(target_folder, f"{base}_{n}.png")) or
                        os.path.exists(os.path.join(target_folder, "done", f"{base}_{n}.png"))):
                    n += 1
            bg_outpath = os.path.abspath(os.path.join(bg_dirpath, f"{base}_{n}.png"))

            # Save cropped background as PNG
            if not cropped_image.save(bg_outpath, "PNG"):
                raise RuntimeError(f"Saving background failed: {bg_outpath}")
            if TRACELEVEL >= 1:
                print(f"Execute: saved cropped background to {bg_outpath}", flush=True)

            # ========== STEP 2: Save cropped mask ==========
            cropped_mask = scaled_mask.copy(x0, y0, crop_w, crop_h)

            # Use same base filename as background image, but with .bmp extension
            mask_outpath = os.path.abspath(os.path.splitext(bg_outpath)[0] + ".bmp")

            # save as BMP
            if not cropped_mask.save(mask_outpath, "BMP"):
                raise RuntimeError(f"Saving mask failed: {mask_outpath}")
            if TRACELEVEL >= 1:
                print(f"Execute: saved mask to {mask_outpath}", flush=True)

            # ========== STEP 3: Move both files to selected inpaint task folder ==========
            os.makedirs(target_folder, exist_ok=True)

            # Determine final paths
            final_bg_path = os.path.abspath(os.path.join(target_folder, os.path.basename(bg_outpath)))
            final_mask_path = os.path.abspath(os.path.join(target_folder, os.path.basename(mask_outpath)))

            # Move background image
            shutil.move(bg_outpath, final_bg_path)
            if TRACELEVEL >= 1:
                print(f"Execute: moved background to {final_bg_path}", flush=True)

            # Move mask
            shutil.move(mask_outpath, final_mask_path)
            if TRACELEVEL >= 1:
                print(f"Execute: moved mask to {final_mask_path}", flush=True)

            # Mirror regular save logging in main dialog status log
            try:
                owner = self.window()
                if owner is not None and hasattr(owner, 'log') and hasattr(owner, 'logn'):
                    owner.log("Create " + final_bg_path, QColor("white"))
                    owner.logn(" OK", QColor("green"))
                    owner.log("Create " + final_mask_path, QColor("white"))
                    owner.logn(" OK", QColor("green"))
            except Exception:
                pass

            # Disable Export and Clear buttons after successful export
            try:
                if hasattr(self, 'execute_button') and self.execute_button is not None:
                    self.execute_button.setEnabled(False)
                if hasattr(self, 'clear_button') and self.clear_button is not None:
                    self.clear_button.setEnabled(False)
            except Exception:
                pass

        except Exception:
            try:
                owner = self.window()
                if owner is not None and hasattr(owner, 'log') and hasattr(owner, 'logn'):
                    if final_bg_path:
                        owner.log("Create " + final_bg_path, QColor("white"))
                    elif final_mask_path:
                        owner.log("Create " + final_mask_path, QColor("white"))
                    elif target_folder:
                        owner.log("Create " + os.path.abspath(target_folder), QColor("white"))
                    else:
                        owner.log("Create Inpaint export", QColor("white"))
                    owner.logn(" Failed", QColor("red"))
            except Exception:
                pass
            print(traceback.format_exc(), flush=True)



    def enable_sliders(self, enable: bool):
        """Aktiviert oder deaktiviert alle Slider."""
        self.slider_left.setEnabled(enable)
        self.slider_right.setEnabled(enable)
        self.slider_top.setEnabled(enable)
        self.slider_bottom.setEnabled(enable)

    def display_sliders(self, visible: bool):
        """Aktiviert oder deaktiviert Sichtbarkeit aller Slider."""
        self.slidersVisible=visible
        self.slider_left.setVisible(visible)
        self.slider_right.setVisible(visible)
        self.slider_top.setVisible(visible)
        self.slider_bottom.setVisible(visible)

    def setSliderValuesToRect(self, rect):
        x0 = rect.x()
        x1 = rect.x() + rect.width()
        y0 = rect.y()
        y1 = rect.y() + rect.height()

        w = self.sourceWidth
        h = self.sourceHeight

        self.slider_left.setValue(x0)
        self.slider_right.setValue(w-x1)
        self.slider_top.setValue(y0)
        self.slider_bottom.setValue(h-y1)
        
        
    # ----------- FRAME SETTINGS -----------
    def change_frame_color(self):
        if not self.original_pixmap:
            return
        color = QColorDialog.getColor(self.frame_color, self, "Rahmenfarbe auswählen")
        if color.isValid():
            self.frame_color = color
            self.apply_crop()

    def change_frame_thickness(self, value):
        if not self.original_pixmap:
            return
        self.frame_thickness = value
        self.apply_crop()

    def change_frame_style(self):
        if not self.original_pixmap:
            return
        self.frame_style = self.style_combo.currentData()
        self.apply_crop()

    # ----------- SLIDERS -----------
    def create_slider(self, orientation, inverted):
        slider = QSlider(orientation)
        slider.setMinimum(0)
        slider.setSingleStep(1)
        slider.setTracking(True)
        slider.setInvertedAppearance(inverted)
        if orientation==Qt.Horizontal:
            slider.setStyleSheet("QSlider::handle:Horizontal { background-color: black; border: 2px solid white;}")
            slider.setSizePolicy(QSizePolicy.Fixed, QSizePolicy.Minimum)
        else:
            slider.setStyleSheet("QSlider::handle:Vertical { background-color: black; border: 2px solid white; }")
            slider.setSizePolicy(QSizePolicy.Minimum, QSizePolicy.Fixed)
        return slider

    def update_slider_ranges(self):
        if not self.original_pixmap:
            #print("not self.original_pixmap", flush=True)
            return

        w = self.sourceWidth
        h = self.sourceHeight
        self.slider_left.setMaximum(w)
        self.slider_right.setMaximum(w)
        self.slider_top.setMaximum(h)
        self.slider_bottom.setMaximum(h)

        #print("update_slider_ranges=", w // 2, h // 2, flush=True)

    def update_crop(self, side, value):
        if not self.original_pixmap:
            return

        if value>0:
            self.clean = False;

        if side == "left":
            self.crop_left = value
            if self.crop_left + self.crop_right > self.sourceWidth:
                self.crop_right = self.sourceWidth - self.crop_left
                self.slider_right.setValue(self.crop_right)
        elif side == "right":
            self.crop_right = value
            if self.crop_left + self.crop_right > self.sourceWidth:
                self.crop_left = self.sourceWidth - self.crop_right
                self.slider_left.setValue(self.crop_left)
        elif side == "top":
            self.crop_top = value
            if self.crop_top + self.crop_bottom > self.sourceHeight:
                self.crop_bottom = self.sourceHeight - self.crop_top
                self.slider_bottom.setValue(self.crop_bottom)
        elif side == "bottom":
            self.crop_bottom = value
            if self.crop_top + self.crop_bottom > self.sourceHeight:
                self.crop_top = self.sourceHeight - self.crop_bottom
                self.slider_top.setValue(self.crop_top)


        #print("update_crop=", self.crop_left, self.crop_right, self.crop_top, self.crop_bottom, flush=True)

        self.apply_crop()
        if self.onCropOrTrim:
            self.onCropOrTrim()

    def get_export_crop_rect(self) -> QRect:
        if not self.original_pixmap or self.original_pixmap.isNull():
            return QRect()

        w = self.original_pixmap.width()
        h = self.original_pixmap.height()

        x0 = max(0, min(int(self.crop_left), w))
        y0 = max(0, min(int(self.crop_top), h))
        x1 = min(w, max(x0, w - int(self.crop_right)))
        y1 = min(h, max(y0, h - int(self.crop_bottom)))

        crop_w = x1 - x0
        crop_h = y1 - y0

        if crop_w <= 0 or crop_h <= 0:
            return QRect(0, 0, w, h)

        return QRect(x0, y0, crop_w, crop_h)

    def get_export_cropped_pixmap(self) -> QPixmap:
        if not self.original_pixmap or self.original_pixmap.isNull():
            return QPixmap()
        rect = self.get_export_crop_rect()
        if rect.isNull() or rect.width() <= 0 or rect.height() <= 0:
            return self.original_pixmap.copy()
        return self.original_pixmap.copy(rect)
                

    def darken_outside_area(self, pixmap: QPixmap, clear_rect: QRect, darkness: int = 120) -> QPixmap:
        """
        Gibt eine neue QPixmap zurück, bei der der Bereich außerhalb von `clear_rect`
        mit einer halbtransparenten schwarzen Farbe abgedunkelt wird.
        :param pixmap: Originalbild als QPixmap (Koordinaten für clear_rect in Pixmap-Koordinaten!)
        :param clear_rect: Bereich, der unverändert bleiben soll
        :param darkness: Transparenzwert (0-255), 0 = transparent, 255 = vollständig schwarz
        :return: Neue QPixmap mit Abdunklung
        """
        if pixmap is None or pixmap.isNull():
            return QPixmap()

        try:
            # Beschneide clear_rect auf Bildgrenzen (sicherer)
            img_rect = pixmap.rect()
            clear_rect = clear_rect.intersected(img_rect)
            if clear_rect.isEmpty():
                # Kein sichtbarer Ausschnitt -> ganzes Bild abdunkeln
                result = QPixmap(pixmap.size())
                result.fill(Qt.transparent)
                
                p = QPainter(result)
                p.drawPixmap(0, 0, pixmap)
                p.fillRect(result.rect(), QColor(0, 0, 0, darkness))
                p.end()
                
                return result

            # 1) Overlay mit Alphakanal erzeugen
            overlay = QPixmap(pixmap.size())
            overlay.fill(Qt.transparent)  # Start mit transparentem Hintergrund
            
            painter = QPainter(overlay)
            painter.setRenderHint(QPainter.Antialiasing)

            # 2) Ganze Overlayfläche mit halbtransparentem Schwarz füllen
            painter.fillRect(overlay.rect(), QColor(0, 0, 0, darkness))

            # 3) "Loch" in das Overlay stanzen (macht Region transparent)
            painter.setCompositionMode(QPainter.CompositionMode_Clear)
            painter.fillRect(clear_rect, QColor(0, 0, 0, 0))

            painter.end()

            # 4) Original und Overlay zusammenführen
            result = QPixmap(pixmap.size())
            result.fill(Qt.transparent)
            painter = QPainter(result)
            painter.setRenderHint(QPainter.Antialiasing)
            painter.drawPixmap(0, 0, pixmap)    # Original
            painter.drawPixmap(0, 0, overlay)   # Overlay oben drauf
            painter.end()
            
            return result
        except:       
            print(traceback.format_exc(), flush=True)
            return QPixmap()


    def apply_crop(self):
        if not self.original_pixmap:
            return
        if self.sourceWidth == 0 or self.sourceHeight == 0:
            return

        try:
                
            if self.crop_left == 0 and self.crop_right == 0 and self.crop_top == 0 and self.crop_bottom == 0:
                self.clean = True
                
            if not self.clean:
                
                w = self.original_pixmap.width()
                h = self.original_pixmap.height()

                mx = float(w) / float(self.sourceWidth)
                my = float(h) / float(self.sourceHeight)

                #print("whmxy", w, h, mx, my, flush=True)
            
                crop_rect = QRect(
                    int(self.crop_left * mx),
                    int(self.crop_top * my),
                    w - int(self.crop_left * mx) - int(self.crop_right * mx),
                    h - int(self.crop_top * my) - int(self.crop_bottom * my)
                )

                temp_pixmap=self.darken_outside_area(self.original_pixmap, crop_rect)

                # Rahmenfarbe anpassen
                cw = crop_rect.width()
                ch = crop_rect.height()
                if cw>0 and ch>0:
                    aspect = float(cw) / float(ch)
                    min_aspect = 9.0 / 16.0
                    max_aspect = 16.0 / 9.0

                if  cw>0 and ch>0 and (aspect < min_aspect or aspect > max_aspect):
                    self.frame_color = QColor(255, 63, 0)  # Orange
                    self.frame_thickness = 5
                else:
                    self.frame_color = QColor(255, 255, 255)  # Weiß
                    self.frame_thickness = 1

                # Rahmen zeichnen
                painter = QPainter(temp_pixmap)
                painter.setRenderHint(QPainter.Antialiasing)
                painter.setCompositionMode(QPainter.CompositionMode_SourceOver)
                pen = QPen(self.frame_color, self.frame_thickness, self.frame_style)
                painter.setPen(pen)
                painter.drawRect(crop_rect)
                painter.end()
                
            else:
                temp_pixmap = self.original_pixmap

            self.display_pixmap = temp_pixmap
            #self.image_label.setPixmap(self.display_pixmap)
            self.image_label.setPixmap(self.display_pixmap.scaled(self.image_label.width(), self.image_label.height(), Qt.KeepAspectRatio))
            
        except:       
            print(traceback.format_exc(), flush=True)

    def update_magnifier(self):
        if not self.original_pixmap:
            return

        if self.center_x < 0:
            return

        if not self.image_label.thread is None:
            if not self.image_label.thread.pause:
                self.magnifier.hide()
                return

        dw=self.image_label.geometry().width()
        dh=self.image_label.geometry().height()

        display_scalefactor=min( float(dw) / float(self.scaledWidth), float(dh) / float(self.scaledHeight) )
        offset_x = (dw - self.scaledWidth * display_scalefactor) / 2.0
        offset_y = (dh - self.scaledHeight * display_scalefactor) / 2.0
        
        x = float(self.center_x - offset_x) / display_scalefactor 
        y = float(self.center_y - offset_y) / display_scalefactor 

        img_scalefactor=self.original_pixmap.width() // self.scaledWidth
        zoom_rect = QRect(int((x - 0.2 * self.magsize / 2) * img_scalefactor) , 
                          int((y - self.magsize / 2) * img_scalefactor),
                          int(self.magsize * img_scalefactor),
                          int(self.magsize * img_scalefactor)
                         )
        zoom_pixmap = self.original_pixmap.copy(zoom_rect).scaled(
            self.magnifier.size()*self.zoom_factor, Qt.KeepAspectRatio, Qt.SmoothTransformation
        )

        self.magnifier.setPixmap(zoom_pixmap)
        self.magnifier.move(self.width() - self.magnifier.width() - 36, 30)
        if self.slidersVisible:
            self.magnifier.show()
            self.magnifier.raise_()  # <-- Bringt die Lupe in den Vordergrund!


    def enterEvent(self, event):
        self.setMouseTracking(True)
        super().enterEvent(event)

    def leaveEvent(self, event):
        self.setMouseTracking(False)
        self.magnifier.hide()
        super().leaveEvent(event)

    def mouseMoveEvent(self, event):
        pos = self.image_label.pos
        if not pos == None:
            
            #print("xy", pos.x(),pos.y(), flush=True)
            
            self.center_x = pos.x()
            self.center_y = pos.y()

            self.update_magnifier()

        super().mouseMoveEvent(event)


    def mouseReleaseEvent(self, event):
        super().mouseReleaseEvent(event)

    def registerForUpdate(self, onCropOrTrim):
        self.onCropOrTrim = onCropOrTrim

    def registerForContentFilter(self, callback):
        self.content_filter_callback = callback
        
    def getCurrentFrameIndex(self):
        return self.currentFrameIndex

class ActionButton(QPushButton):
    def __init__(self):
        super().__init__()
        #self.button_prev_file.setStyleSheet("background : black; color: white;")
        self.updateStylesheet()
        self.setCursor(Qt.PointingHandCursor)

    def updateStylesheet(self):

        self.setStyleSheet(
            """
        QPushButton:pressed {
            background-color: qlineargradient(x1: 0, y1: 0, x2: 0, y2: 1, stop: 0 #000000, stop: 1 #000000);
        }
        """
        )
        
class StyledIcon(QIcon):
    def __init__(self, pathtofile):
        enabled_icon = QPixmap(pathtofile)
        super().__init__(enabled_icon)
        
        img = enabled_icon.toImage()
        buffer = QBuffer()
        buffer.open(QBuffer.ReadWrite)
        img.save(buffer, "PNG")
        pil_im = Image.open(io.BytesIO(buffer.data()))
       
        DIMFACTOR=0.25
        image_arr = np.array(pil_im) / 255.0 * DIMFACTOR
        convolved = Image.fromarray(np.uint8(255 * image_arr), 'RGB') 
        disabled_icon=pil2pixmap(convolved)
        self.addPixmap( disabled_icon, QIcon.Disabled )
        
        self.addPixmap( enabled_icon, QIcon.Normal, QIcon.Off)

        p = QPainter()
        pen = QPen()
        pen.setWidth(10)
        pen.setCapStyle(Qt.PenCapStyle.RoundCap)
        pen.setJoinStyle(Qt.PenJoinStyle.RoundJoin)
        pen.setColor(QColor("green"))
        pixm= QPixmap(pathtofile)
        h=pixm.height()
        w=pixm.width()
        y=h-1
        
        p.begin(pixm)
        p.setRenderHints(QPainter.RenderHint.Antialiasing, True)
        p.setPen(pen)
        p.drawLine(QPoint(0,y), QPoint(w,y))
        p.end()
        
        self.addPixmap( pixm, QIcon.Normal, QIcon.On)

class InputBlocker(QWidget):
    """Transparente Sperr-Schicht über dem Dialog."""
    def __init__(self, parent):
        super().__init__(parent)
        self.setAttribute(Qt.WA_TransparentForMouseEvents, False)  # Wichtig: Events abfangen!
        self.setWindowFlags(Qt.FramelessWindowHint)
        self.setStyleSheet("background: transparent;")  # Unsichtbar
        self.setGeometry(parent.rect())
        self.show()

    def resizeEvent(self, event):
        """Overlay immer an Fenstergröße anpassen."""
        self.setGeometry(self.parent().rect())

def setFileFilter(filterImg, filterVid, filterEdit):
    global _activeExtensions, _filterEdit
    _activeExtensions=[]
    if not filterImg:
        _activeExtensions = _activeExtensions + IMAGE_EXTENSIONS
    if not filterVid:
        _activeExtensions = _activeExtensions + VIDEO_EXTENSIONS
    _filterEdit=filterEdit

# ASYNC CONTEXT
def scanFilesToRate():
    try:
        #print("scanFilesToRate", flush=True)
        global _filesWithoutEdit, _editedfiles, _readyfiles, filesNoCut, filesCut, _cutModeFolderOverrideFiles
        _filesWithoutEdit = get_initial_file_list("../../../../input/vr/check/rate")
        _editedfiles = get_initial_file_list("../../../../input/vr/check/rate/edit")
        _readyfiles = get_initial_file_list("../../../../input/vr/check/rate/ready")
        filesNoCut = buildList(_editedfiles, "edit/") + buildList(_readyfiles, "ready/") + buildList(_filesWithoutEdit, None)
        if cutModeFolderOverrideActive:
            _cutModeFolderOverrideFiles = get_initial_file_list(cutModeFolderOverridePath)
            filesCut = buildList(_cutModeFolderOverrideFiles, None)
        else:
            _cutModeFolderOverrideFiles = _filesWithoutEdit
            filesCut = buildList(_filesWithoutEdit, None)

        if cutModeActive:
            files = filesCut
        else:
            files = filesNoCut
        return files
    except KeyboardInterrupt:
        pass
    except Exception:
        print(traceback.format_exc(), flush=True)
    return ()


# ASYNC CONTEXT    
def rescanFilesToRate():
    try:
        #print("rescanFilesToRate", flush=True)
        global _filesWithoutEdit, _editedfiles, _readyfiles, _cutModeFolderOverrideFiles, filesNoCut, filesCut
        _filesWithoutEdit = update_file_list("../../../../input/vr/check/rate", _filesWithoutEdit)
        _editedfiles = update_file_list("../../../../input/vr/check/rate/edit", _editedfiles)
        _readyfiles = update_file_list("../../../../input/vr/check/rate/ready", _readyfiles)
        if cutModeActive:
            if cutModeFolderOverrideActive:
                _cutModeFolderOverrideFiles = update_file_list(cutModeFolderOverridePath, _cutModeFolderOverrideFiles)
                filesCut = buildList(_cutModeFolderOverrideFiles, None)
            else:
                filesCut = buildList(_filesWithoutEdit, None)
            files = filesCut
        else:
            if _filterEdit:
                filesNoCut  = buildList(_editedfiles, "edit/") + buildList(_readyfiles, "ready/")
            else:
                filesNoCut  = buildList(_editedfiles, "edit/") + buildList(_readyfiles, "ready/") + buildList(_filesWithoutEdit, None)
            files = filesNoCut 
            
        return files
    except KeyboardInterrupt:
        pass
    except Exception:
        print(traceback.format_exc(), flush=True)
    return ()


def getFilesToRate():
    if cutModeActive:
        return filesCut
    else:
        return filesNoCut

def getFilesWithoutEdit():
    return buildList(_filesWithoutEdit, None)

def getFilesOnlyEdit():
    return buildList(_editedfiles, "edit/")

def getFilesOnlyReady():
    return buildList(_readyfiles, "ready/")

def buildList(files, subpath):
    newList=[]
    for i in range(len(files)):
        tuple=files[i]
        if subpath is None:
            newList.append( tuple[0] )
        else:
            newList.append( subpath + tuple[0] )
    return newList

# Modification Time (any touch)
def statMTime(path):
    #c=os.stat(path).st_ctime
    m=os.stat(path).st_mtime
    #print("?", c, m, path, flush=True)
    return m


def update_file_list(base_path: str, file_list: List[Tuple[str, float]]) -> List[Tuple[str, float]]:
    """
    Aktualisiert die bestehende Datei-Liste:
      - Entfernt nicht mehr existierende Dateien
      - Fügt neue Dateien ein (holt mtime nur für neue Dateien)
      - Behält die Sortierung bei, ohne vollständige Neusortierung
    """
    try:
        fullbasepath=os.path.join(path, base_path)
        if not os.path.exists(fullbasepath):
            os.makedirs(fullbasepath)

        # Aktuell vorhandene Dateien NUR als Menge laden (kein mtime!)
        bpath = os.path.abspath(os.path.join(path, fullbasepath))
        current_files = {
            f for f in os.listdir(bpath)
            if os.path.isfile(os.path.join(bpath, f))
            and any(f.lower().endswith(suf.lower()) for suf in _activeExtensions)
        }

        # ---- 1. Entferne Dateien, die nicht mehr existieren ----
        existing_names_in_list = {fname for fname, _ in file_list}
        file_list[:] = [(fname, mtime) for fname, mtime in file_list if fname in current_files]

        # ---- 2. Finde neue Dateien (die noch nicht in der Liste sind) ----
        new_files = current_files - existing_names_in_list

        # ---- 3. Füge neue Dateien mit mtime ein (nur hier wird getmtime aufgerufen) ----
        for fname in new_files:
            full_path = os.path.join(bpath, fname)
            mtime = statMTime(bpath)  # Nur für neue Dateien aufrufen
            insert_sorted(file_list, (fname, mtime))
    except:
        print(traceback.format_exc(), flush=True)
        
    return file_list

def _get_sort_key(item: Tuple[str, float]):
    """
    Liefert den Sortierschlüssel für ein Element (Dateiname, mtime)
    basierend auf dem globalen _sortOrderIndex.
    """
    global _sortOrderIndex

    if _sortOrderIndex in (0, 1):  # alphabetisch
        return item[0].lower()
    elif _sortOrderIndex in (2, 3):  # nach Zeit
        return item[1]
    else:
        # Fallback: Zeit aufsteigend
        return item[1]


def _sort_file_list(file_list: List[Tuple[str, float]]):
    """
    Sortiert eine Datei-Liste gemäß der aktuellen globalen Sortierregel.
    """
    global _sortOrderIndex

    reverse = _sortOrderIndex in (1, 3)  # 1 = alpha↓, 3 = time↓
    return sorted(file_list, key=_get_sort_key, reverse=reverse)

def get_initial_file_list(base_path: str) -> List[Tuple[str, float]]:
    """
    Erstellt eine sortierte Liste mit Tupeln (Dateiname, Modifikationsdatum).
    Sortiert nach Modifikationsdatum aufsteigend (alte zuerst).
    """
    fullbasepath=os.path.join(path, base_path)
    if not os.path.exists(fullbasepath):
        os.makedirs(fullbasepath)
    
    bpath = os.path.abspath(fullbasepath)
    files = []
    for f in os.listdir(bpath):
        full_path = os.path.join(bpath, f)
        if os.path.isfile(full_path) and any(f.lower().endswith(suf.lower()) for suf in ALL_EXTENSIONS):
            mtime = statMTime(full_path)
            files.append((f, mtime))    

    #return sorted(files, key=lambda x: x[1], reverse=False)
    global _sortOrderIndex
    reverse = _sortOrderIndex in (1, 3)  # 1 = alpha↓, 3 = time↓
    return sorted(files, key=_get_sort_key, reverse=reverse)

def insert_sorted(file_list: List[Tuple[str, float]], new_item: Tuple[str, float]):
    """
    Fügt ein neues Element (Dateiname, Modifikationsdatum) an der richtigen
    Stelle in die bestehende Liste ein, basierend auf der aktuellen Sortierlogik.
    """
    global _sortOrderIndex

    if not file_list:
        file_list.append(new_item)
        return

    # Bestimme den Sortierschlüssel für das neue Element
    new_key = _get_sort_key(new_item)

    # Liste der bestehenden Sortierschlüssel erzeugen
    keys = [_get_sort_key(item) for item in file_list]

    # Je nach Sortierreihenfolge passende Einfügelogik
    if _sortOrderIndex in (0, 2):  # aufsteigend
        pos = bisect.bisect_left(keys, new_key)
    elif _sortOrderIndex in (1, 3):  # absteigend
        reversed_keys = list(reversed(keys))
        insert_pos = bisect.bisect_left(reversed_keys, new_key)
        pos = len(file_list) - insert_pos
    else:
        pos = bisect.bisect_left(keys, new_key)

    file_list.insert(pos, new_item)


def applySortOrder():
    """
    Sortiert alle relevanten globalen Listen anhand der aktuellen Einstellung
    von _sortOrderIndex neu. Wird aufgerufen, wenn die Sortiermethode geändert wird.
    """
    global _filesWithoutEdit, _editedfiles, _readyfiles, _cutModeFolderOverrideFiles

    try:
        if _filesWithoutEdit is not None:
            _filesWithoutEdit = _sort_file_list(_filesWithoutEdit)
        if _editedfiles is not None:
            _editedfiles = _sort_file_list(_editedfiles)
        if _readyfiles is not None:
            _readyfiles = _sort_file_list(_readyfiles)
        if _cutModeFolderOverrideFiles is not None:
            _cutModeFolderOverrideFiles = _sort_file_list(_cutModeFolderOverrideFiles)
    except Exception:
        print(traceback.format_exc(), flush=True)


def pil2pixmap(im):
    if im.mode == "RGB":
        r, g, b = im.split()
        im = Image.merge("RGB", (b, g, r))
    elif  im.mode == "RGBA":
        r, g, b, a = im.split()
        im = Image.merge("RGBA", (b, g, r, a))
    elif im.mode == "L":
        im = im.convert("RGBA")
    # Bild in RGBA konvertieren, falls nicht bereits passiert
    im2 = im.convert("RGBA")
    data = im2.tobytes("raw", "RGBA")
    qim = QImage(data, im.size[0], im.size[1], QImage.Format_ARGB32)
    pixmap = QPixmap.fromImage(qim)
    return pixmap

def replaceSomeChars(path: str) -> str:
    return path.replace(' ', '_')

def gitbash_to_windows_path(unix_path: str) -> str:
    if unix_path.startswith('/') and len(unix_path) > 2 and unix_path[1].isalpha() and unix_path[2] == '/':
        drive_letter = unix_path[1].upper()
        rest_of_path = unix_path[3:]
        return os.path.join(f"{drive_letter}:", *rest_of_path.split('/'))
    return os.path.join(*unix_path.split('/'))

def format_timedelta_hundredth(td: timedelta) -> str:
    """
    Gibt ein timedelta als String auf Hundertstel Sekunden genau aus.
    
    Parameter:
        td (timedelta): Ein timedelta-Objekt
    
    Rückgabe:
        str: Zeit im Format "HH:MM:SS.ss"
    """
    # Gesamtdauer in Sekunden als float
    total_seconds = td.total_seconds()
    
    # Stunden, Minuten, Sekunden extrahieren
    hours = int(total_seconds // 3600)
    minutes = int((total_seconds % 3600) // 60)
    seconds = total_seconds % 60  # Sekunden inkl. Bruchteile
    
    # Auf zwei Nachkommastellen (Hundertstel) runden
    return f"{hours:02}:{minutes:02}:{seconds:05.2f}"


def initCutMode():
    pass