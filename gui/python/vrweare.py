import os
import re
import base64
import subprocess
import sys
import time
import traceback
import urllib.request
import urllib.parse
import webbrowser
from random import randrange
from threading import Thread
from urllib.error import HTTPError
from functools import partial

import requests
from PIL import Image
import shutil
import tempfile
from PyQt5.QtCore import (QRect, QSize, Qt, QThread, QTimer)
from PyQt5.QtGui import (QBrush, QColor, QCursor, QFont, QIcon, QPainter, QPen, QPixmap,
                         QPalette, QPainterPath, QFontMetrics)
from PyQt5.QtWidgets import (QAbstractItemView, QAction, QApplication,
                             QDesktopWidget, QDialog,
                             QHeaderView, QLabel, QMainWindow,
                             QSizePolicy,
                             QTableWidget,
                             QTableWidgetItem, QToolBar, QVBoxLayout, QWidget,
                             QScrollArea)
from PyQt5.QtCore import Qt as _QtRoles

import faulthandler
faulthandler.enable()

path = os.path.dirname(os.path.abspath(__file__))

# Add the current directory to the path so we can import local modules
if path not in sys.path:
    sys.path.append(path)

# Import our implementations
from rating import RateAndCutDialog, StyledIcon, pil2pixmap, getFilesWithoutEdit, getFilesOnlyEdit, getFilesOnlyReady, rescanFilesToRate, scanFilesToRate, initCutMode, config, VIDEO_EXTENSIONS, IMAGE_EXTENSIONS, TRACELEVEL
from judge import JudgeDialog


LOGOTIME = 3000
BREAKFREQ = 1200000
TABLEUPDATEFREQ = 50
# Throttle expensive data (filesystem/status) recomputation; UI redraw still runs at TABLEUPDATEFREQ
TABLEDATAUPDATETHRESHOLD = 20
TOOLBARUPDATEFREQ = 1000
BREAKTIME = 20000
FILESCANTIME = 2000

status="idle"
idletime = 0

COLS = 4

# Files to store pin/used states (simple properties format: key=csv)

PIN_STATE_FILE = os.path.abspath(os.path.join(path, '../../../../user/default/comfyui_stereoscopic/pin.properties'))
UNUSED_STATE_FILE = os.path.abspath(os.path.join(path, '../../../../user/default/comfyui_stereoscopic/unused.properties'))

def _load_flag_file(file_path: str) -> dict:
    """Load a simple properties file with keys 'stage','task','customtask' mapping to comma-separated lists.
    Returns dict of sets.
    """
    result = {'stage': set(), 'task': set(), 'customtask': set()}
    try:
        with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#') or '=' not in line:
                    continue
                k, v = line.split('=', 1)
                k = k.strip()
                v = v.strip()
                if k in result and v:
                    for part in v.split(','):
                        p = part.strip()
                        if p:
                            result[k].add(p)
    except FileNotFoundError:
        # treat missing file as empty
        pass
    except Exception:
        pass
    return result

def _save_flag_file(file_path: str, data: dict):
    try:
        d = {'stage':'', 'task':'', 'customtask':''}
        for k in ['stage','task','customtask']:
            vals = list(data.get(k, []))
            d[k] = ','.join(vals)
        with open(file_path, 'w', encoding='utf-8') as f:
            for k in ['stage','task','customtask']:
                f.write(f"{k}={d[k]}\n")
    except Exception:
        pass

pipelinePauseLockPath = os.path.abspath(os.path.join(path, '../../../../user' , 'default', 'comfyui_stereoscopic', '.pipelinepause'))
pipelineActiveLockPath = os.path.abspath(os.path.join(path, '../../../../user' , 'default', 'comfyui_stereoscopic', '.pipelineactive'))
pipelineFowardingLockPath = os.path.abspath(os.path.join(path, '../../../../user' , 'default', 'comfyui_stereoscopic', '.forwardstop'))

STAGES = ["caption", "scaling", "fullsbs", "interpolate", "singleloop", "dubbing/music", "dubbing/sfx", "slides", "slideshow", "watermark/encrypt", "watermark/decrypt", "concat", "check/rate", "check/released"]
subfolder = os.path.join(path, "../../../../custom_nodes/comfyui_stereoscopic/config/tasks")
if os.path.exists(subfolder):
    onlyfiles = next(os.walk(subfolder))[2]
    for f in onlyfiles:
        fl=f.lower()
        if fl.endswith(".json"):
            STAGES.append("tasks/" + fl[:-5])
subfolder = os.path.join(path, "../../../../user/default/comfyui_stereoscopic/tasks")
if os.path.exists(subfolder):
    onlyfiles = next(os.walk(subfolder))[2]
    for f in onlyfiles:
        fl=f.lower()
        if fl.endswith(".json"):
            STAGES.append("tasks/_" + fl[:-5])
ROWS = 1 + len(STAGES)
ROW2STAGE= []

def updatePipeline():
    imagepath=os.path.join(path, "../../../../user/default/comfyui_stereoscopic/uml/autoforward.png")
    if os.path.exists(imagepath):
        pixmap = QPixmap(imagepath)
        labelPipeline.clear()
        labelPipeline.setPixmap(pixmap)
        if pipelinedialog:
            screen = QDesktopWidget().availableGeometry()
            screen_width = screen.width()
            max_width = min(pixmap.width(), screen_width - 50)
            pipelinedialog.resize(max_width, pixmap.height() + 70)
            
    else:
        labelPipeline.clear()
        hidePipelineShowText("No pipeline defined.")

def hidePipelineShowText(text):
    labelPipeline.clear()
    labelPipeline.setText(text)
    
def setPipelineErrorText(text):
    if text is None:
        pipelineErrors.setVisible(False)
        pipelineErrors.setText("")
    else:
        pipelineErrors.setText(text)
        pipelineErrors.setVisible(True)

def touch(fname):
    if os.path.exists(fname):
        os.utime(fname, None)
    else:
        open(fname, 'a').close()

def get_property(file_path: str, key: str, default: str = None) -> str:
    """
    Reads a key=value property from a simple properties file.
    Returns the default value if the key is not found.
    """

    try:
        with open(file_path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()

                # ignore empty lines & comments
                if not line or line.startswith("#") or "=" not in line:
                    continue

                k, v = line.split("=", 1)
                k = k.strip()
                v = v.strip()

                if k == key:
                    return v

    except FileNotFoundError:
        raise FileNotFoundError(f"Property file not found: {file_path}")

    # return default if key not found
    return default


def set_property(file_path: str, key: str, value: str) -> None:
    """
    Setzt oder ersetzt in einer Property-Datei (Format: KEY=VALUE) den Eintrag mit dem gegebenen Key.
    Wenn der Key nicht existiert, wird er am Ende hinzugefügt.
    """
    lines = []
    key_found = False
    new_line = f"{key}={value}\n"

    with open(file_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            stripped = line.strip()
            # Kommentare oder leere Zeilen beibehalten
            if not stripped or stripped.startswith("#"):
                lines.append(line)
                continue

            if stripped.split("=", 1)[0] == key:
                lines.append(new_line)
                key_found = True
            else:
                lines.append(line)

    if not key_found:
        # Key noch nicht vorhanden → am Ende hinzufügen
        if not lines or not lines[-1].endswith("\n"):
            lines.append("\n")
        lines.append(new_line)

    with open(file_path, "w", encoding="utf-8") as f:
        f.writelines(lines)


def get_stage_input_type(stage_name: str) -> str:
    """
    Bestimmt den input-Typ (z.B. "image" oder "video") einer Stage/Task
    durch Einlesen der zugehörigen JSON-Definition wie im Rest der Anwendung.
    Gibt None zurück, wenn unbekannt.
    """
    if re.match(r"tasks/_.*", stage_name):
        stageDefRes = "user/default/comfyui_stereoscopic/tasks/" + stage_name[7:] + ".json"
    elif re.match(r"tasks/.*", stage_name):
        stageDefRes = "custom_nodes/comfyui_stereoscopic/config/tasks/" + stage_name[6:] + ".json"
    else:
        stageDefRes = "custom_nodes/comfyui_stereoscopic/config/stages/" + stage_name + ".json"

    defFile = os.path.join(path, "../../../../" + stageDefRes)
    if not os.path.exists(defFile):
        return None

    try:
        with open(defFile, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                if '"input"' in line:
                    # einfaches Parsen wie im Originalcode
                    part = line.split('"input":', 1)[1]
                    m = re.search(r'"(.*?)"', part)
                    if m:
                        return m.group(1)
    except Exception:
        return None

    return None


def _is_allowed_for_type(file_path: str, input_type: str) -> bool:
    """Prüft, ob Datei-Endung zu input_type passt.

    Unterstützt mehrere Typen, getrennt mit Semikolon ('image;video').
    Der Drop ist gültig, wenn mindestens ein Typ mit der Datei übereinstimmt.
    """
    if not input_type:
        return False

    # Normalize to a list of types (support semicolon-separated definitions)
    if isinstance(input_type, str):
        types = [t.strip().lower() for t in input_type.split(';') if t.strip()]
    else:
        types = [str(input_type).strip().lower()]

    ext = os.path.splitext(file_path)[1].lower()
    # Use global definitions from rating.py (normalize to lowercase)
    try:
        image_exts = set(e.lower() for e in IMAGE_EXTENSIONS)
    except Exception:
        image_exts = {'.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp', '.tif', '.tiff'}
    try:
        video_exts = set(e.lower() for e in VIDEO_EXTENSIONS)
    except Exception:
        video_exts = {'.mp4', '.mov', '.avi', '.mkv', '.webm', '.mpeg', '.mpg'}

    for t in types:
        if t == 'image' and ext in image_exts:
            return True
        if t == 'video' and ext in video_exts:
            return True
        if t in ('file', 'any'):
            return True

    return False


def _is_url_allowed_for_type(url: str, input_type: str) -> bool:
    """Prüft, ob eine URL (Content-Type) zu input_type passt.

    Öffnet kurz die URL-Header und prüft `Content-Type`.
    """
    if not input_type or not url:
        return False

    try:
        url = str(url).strip().strip('\x00').strip('"\'<>')
    except Exception:
        return False
    if not url:
        return False

    # normalize input types
    if isinstance(input_type, str):
        types = [t.strip().lower() for t in input_type.split(';') if t.strip()]
    else:
        types = [str(input_type).strip().lower()]

    if any(t in ('file', 'any') for t in types):
        return True

    # Handle data URLs directly without network I/O
    try:
        if url.lower().startswith('data:'):
            data_header = url[5:].split(',', 1)[0]
            data_content_type = (data_header.split(';', 1)[0] or '').strip().lower()
            for t in types:
                if t == 'image' and data_content_type.startswith('image/'):
                    return True
                if t == 'video' and data_content_type.startswith('video/'):
                    return True
            return False
    except Exception:
        return False

    try:
        image_exts = set(e.lower() for e in IMAGE_EXTENSIONS)
    except Exception:
        image_exts = {'.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp', '.tif', '.tiff'}
    try:
        video_exts = set(e.lower() for e in VIDEO_EXTENSIONS)
    except Exception:
        video_exts = {'.mp4', '.mov', '.avi', '.mkv', '.webm', '.mpeg', '.mpg'}

    candidate_exts = set()
    try:
        parsed = urllib.parse.urlparse(url)
        path_ext = os.path.splitext(parsed.path)[1].lower()
        if path_ext:
            candidate_exts.add(path_ext)
        if parsed.query:
            for _, vals in urllib.parse.parse_qs(parsed.query).items():
                for v in vals:
                    qext = os.path.splitext(urllib.parse.unquote(v or ''))[1].lower()
                    if qext:
                        candidate_exts.add(qext)
    except Exception:
        pass

    def _allowed_by_ext() -> bool:
        for t in types:
            if t == 'image' and any(ext in image_exts for ext in candidate_exts):
                return True
            if t == 'video' and any(ext in video_exts for ext in candidate_exts):
                return True
        return False

    def _allowed_by_sniff(data: bytes) -> bool:
        if not data:
            return False

        header = bytes(data[:64])
        is_image = False
        is_video = False

        # Image signatures
        if header.startswith(b'\xff\xd8\xff'):  # JPEG
            is_image = True
        elif header.startswith(b'\x89PNG\r\n\x1a\n'):  # PNG
            is_image = True
        elif header.startswith((b'GIF87a', b'GIF89a')):  # GIF
            is_image = True
        elif header.startswith(b'BM'):  # BMP
            is_image = True
        elif len(header) >= 12 and header[:4] == b'RIFF' and header[8:12] == b'WEBP':  # WEBP
            is_image = True
        elif header.startswith((b'II*\x00', b'MM\x00*')):  # TIFF
            is_image = True
        elif len(header) >= 12 and header[4:8] == b'ftyp' and b'heic' in header.lower():  # HEIC
            is_image = True

        # Video/container signatures
        if len(header) >= 12 and header[4:8] == b'ftyp':  # MP4/MOV family
            is_video = True
        elif len(header) >= 12 and header[:4] == b'RIFF' and header[8:11] == b'AVI':  # AVI
            is_video = True
        elif header.startswith(b'\x1a\x45\xdf\xa3'):  # Matroska/WebM
            is_video = True
        elif header.startswith((b'\x00\x00\x01\xba', b'\x00\x00\x01\xb3')):  # MPEG
            is_video = True

        for t in types:
            if t == 'image' and is_image:
                return True
            if t == 'video' and is_video:
                return True
        return False

    resp = None
    try:
        # Use requests with a browser-like UA to improve compatibility
        resp = requests.get(url, stream=True, timeout=6, allow_redirects=True, headers={"User-Agent": "Mozilla/5.0"})
        # don't read body; headers are available
        content_type = (resp.headers.get('Content-Type', '') or '').split(';', 1)[0].strip().lower()
    except Exception:
        return _allowed_by_ext()

    if content_type:
        for t in types:
            if t == 'image' and content_type.startswith('image/'):
                try:
                    if resp is not None:
                        resp.close()
                except Exception:
                    pass
                return True
            if t == 'video' and content_type.startswith('video/'):
                try:
                    if resp is not None:
                        resp.close()
                except Exception:
                    pass
                return True

    # Fall back to Content-Disposition filename extension when present.
    try:
        content_disp = resp.headers.get('Content-Disposition', '') if resp is not None else ''
    except Exception:
        content_disp = ''
    if content_disp:
        try:
            m = re.search(r'filename\*?=(?:UTF-8\'\')?"?([^";]+)"?', content_disp, flags=re.IGNORECASE)
            if m:
                disp_name = urllib.parse.unquote((m.group(1) or '').strip())
                disp_ext = os.path.splitext(disp_name)[1].lower()
                if disp_ext:
                    candidate_exts.add(disp_ext)
        except Exception:
            pass

    if _allowed_by_ext():
        try:
            if resp is not None:
                resp.close()
        except Exception:
            pass
        return True

    # Some hosts return generic or missing MIME types for downloadable media.
    if content_type in ('', 'application/octet-stream', 'binary/octet-stream', 'application/download'):
        try:
            probe = b''
            if resp is not None and getattr(resp, 'raw', None) is not None:
                probe = resp.raw.read(64) or b''
        except Exception:
            probe = b''
        finally:
            try:
                if resp is not None:
                    resp.close()
            except Exception:
                pass

        if _allowed_by_sniff(probe):
            return True

        return False

    try:
        if resp is not None:
            resp.close()
    except Exception:
        pass

    return False


def _is_url_allowed_for_type_quick(url: str, input_type: str) -> bool:
    """Quick check whether a URL *probably* matches input_type without network I/O.

    This inspects only the URL path/extension and known extension lists. It is
    intended for use during drag events to avoid starting network downloads.
    """
    if not input_type or not url:
        return False

    # Normalize input types
    if isinstance(input_type, str):
        types = [t.strip().lower() for t in input_type.split(';') if t.strip()]
    else:
        types = [str(input_type).strip().lower()]

    try:
        parsed = urllib.parse.urlparse(url)
        ext = os.path.splitext(parsed.path)[1].lower()
    except Exception:
        ext = ''

    try:
        image_exts = set(e.lower() for e in IMAGE_EXTENSIONS)
    except Exception:
        image_exts = {'.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp', '.tif', '.tiff'}
    try:
        video_exts = set(e.lower() for e in VIDEO_EXTENSIONS)
    except Exception:
        video_exts = {'.mp4', '.mov', '.avi', '.mkv', '.webm', '.mpeg', '.mpg'}

    for t in types:
        if t == 'image' and ext in image_exts:
            return True
        if t == 'video' and ext in video_exts:
            return True
        if t in ('file', 'any') and ext:
            # if caller accepts generic files and there's an extension, allow
            return True

    # During drag we intentionally avoid network I/O. If extension is missing or
    # not decisive (e.g. .php endpoint), do not reject early: allow hover/drop
    # and let dropEvent do strict Content-Type validation via
    # _is_url_allowed_for_type().
    ext_is_decisive = bool(ext and (ext in image_exts or ext in video_exts))
    if not ext_is_decisive:
        for t in types:
            if t in ('image', 'video', 'file', 'any'):
                return True

    # Unknown extension with explicit media constraints stays rejected.
    return False

class SpreadsheetApp(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("VR we are - Status")
        self.setStyleSheet("background-color: black;")
        self.setWindowIcon(QIcon(os.path.join(path, '../../gui/img/icon.png')))
        self.setGeometry(100, 100, 1024, 600)
        self.move(60, 15)

        # Flags for toggles
        self.toogle_stages_expanded = False
        self.toogle_pipeline_active = not os.path.exists(pipelinePauseLockPath)
        self.toogle_pipeline_isForwarding = config("PIPELINE_AUTOFORWARD", "0") == "1"

        # Initialize caches
        self.stageTypes = []
        # Load persisted pin/unused states once at startup to avoid repeated I/O
        self._pin_states = _load_flag_file(PIN_STATE_FILE)
        self._pin_states_file = PIN_STATE_FILE
        # Rename used -> unused semantics: file lists disabled (unused) entries
        self._unused_states_file = UNUSED_STATE_FILE
        self._unused_states = _load_flag_file(self._unused_states_file)
        # Preload stage types once at startup to avoid repeated file I/O during updates
        try:
            for stage in STAGES:
                value = "?"
                if re.match(r"tasks/_.*", stage):
                    stageDefRes = "user/default/comfyui_stereoscopic/tasks/" + stage[7:] + ".json"
                elif re.match(r"tasks/.*", stage):
                    stageDefRes = "custom_nodes/comfyui_stereoscopic/config/tasks/" + stage[6:] + ".json"
                else:
                    stageDefRes = "custom_nodes/comfyui_stereoscopic/config/stages/" + stage + ".json"
                defFile = os.path.join(path, "../../../../" + stageDefRes)
                if os.path.exists(defFile):
                    try:
                        with open(defFile, encoding="utf-8", errors="replace") as file:
                            deflines = [line.rstrip() for line in file]
                            for line in range(len(deflines)):
                                inputMatch = re.match(r".*\"input\":", deflines[line])
                                if inputMatch:
                                    valuepart = deflines[line][inputMatch.end():]
                                    match = re.search(r"\".*\"", valuepart)
                                    if match:
                                        value = valuepart[match.start()+1:match.end()][:-1]
                                        break
                    except Exception:
                        value = "?"
                self.stageTypes.append(value)
        except Exception:
            self.stageTypes = []
        # cache mapping (raw_preview_candidate, stage_name) -> (final_path_or_None, status)
        self._preview_path_cache = {}
        # remember last read daemonstatus lines to avoid re-parsing unchanged status repeatedly
        self._last_daemon_status = None
        # remember what preview (path,status) we attached per stage index to avoid re-logging
        self._last_attached_previews = {}

        # Ensure column index attributes exist early so other components
        # can call `isCellClickable()` before `update_table()` runs.
        self.COL_IDX_IN = 1
        self.COL_IDX_OUT = 3
        self.COL_IDX_IN_TYPES = 1

        self.pipelinedialog=None
        self.dialog=None
        self._open_tool_dialogs = set()
        self._tool_dialog_refs = {}
        self.pipeline_edit_action = None
        
        # prerequisites
        folder=os.path.join(path, f"../../../../input/vr/check/rate")
        os.makedirs(folder, exist_ok = True)
        folder=os.path.join(path, f"../../../../input/vr/check/rate/edit")
        os.makedirs(folder, exist_ok = True)
        
        # Central widget container
        self.central_widget = QWidget()
        self.setCentralWidget(self.central_widget)
        self.layout = QVBoxLayout(self.central_widget)

        # Spreadsheet widget
        self.table = HoverTableWidget(ROWS, COLS, self.isCellClickable, self.onCellClick, self)
        self.table.setStyleSheet("background-color: black; color: black; gridline-color: black")
        self.table.setShowGrid(False)
        self.table.setFrameStyle(0)
        self.table.setSelectionMode(QAbstractItemView.SelectionMode.NoSelection)
        self.table.setFocusPolicy(Qt.NoFocus)
        #self.table.itemChanged.connect(self.itemChanged)
        
        # Configure headers
        self.table.horizontalHeader().setVisible(False)
        self.table.verticalHeader().setVisible(False)
        font = QFont()
        font.setBold(True)
        self.table.horizontalHeader().setFont(font)
        self.table.verticalHeader().setFont(font)
        self.table.horizontalHeader().setStyleSheet("QHeaderView::section { color: white; background-color: black; }")
        self.table.verticalHeader().setStyleSheet("QHeaderView::section { color: white; background-color: black; }")

        # Set column widths (first column 2.5x larger)
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.table.setColumnWidth(0, 250)
        for c in range(1, COLS):
            self.table.setColumnWidth(c, 100)

        self.table.resizeRowsToContents()
        self.table.resizeColumnsToContents()

        # Logo page widget (image + text)
        self.logo_container = QWidget()
        vbox = QVBoxLayout()
        self.logo_container.setLayout(vbox)
        self.logo_image = QLabel()
        pixmap = QPixmap(os.path.join(path, "../../gui/img/banner.png"))
        if not pixmap.isNull():
            self.logo_image.setPixmap(pixmap.scaled(300, 300, Qt.KeepAspectRatio, Qt.SmoothTransformation))
        self.logo_image.setAlignment(Qt.AlignCenter)
        self.logo_text = QLabel("★ VR we are! ★")
        self.logo_text.setAlignment(Qt.AlignCenter)
        self.logo_text.setStyleSheet("color: white; background-color: black;")
        logo_font = QFont()
        logo_font.setPointSize(20)
        logo_font.setBold(True)
        self.logo_text.setFont(logo_font)
        vbox.addWidget(self.logo_image)
        vbox.addWidget(self.logo_text)
        
        # Idle page widget (image + text)
        self.idle_container = QWidget()
        vbox = QVBoxLayout()
        self.idle_container.setLayout(vbox)
        self.idle_image = QLabel()
        pixmap = QPixmap(os.path.join(path, "../../gui/img/banner.png"))
        if not pixmap.isNull():
            self.idle_image.setPixmap(pixmap.scaled(300, 300, Qt.KeepAspectRatio, Qt.SmoothTransformation))
        self.idle_image.setAlignment(Qt.AlignCenter)
        self.idle_text = QLabel("Idle - waiting for files...")
        self.idle_text.setAlignment(Qt.AlignCenter)
        self.idle_text.setStyleSheet("color: white; background-color: black;")
        idle_font = QFont()
        idle_font.setPointSize(20)
        idle_font.setBold(False)
        self.idle_text.setFont(idle_font)
        vbox.addWidget(self.idle_image)
        vbox.addWidget(self.idle_text)
        
        # Setup toolbar
        self.init_toolbar()
        
        # Initially show logo page
        self.layout.addWidget(self.logo_container)

        self.idle_container_active = False

        # Timer for switching views
        self.switch_timer = QTimer()
        self.switch_timer.timeout.connect(self.show_table)
        self.switch_timer.setSingleShot(True)
        self.switch_timer.start(LOGOTIME)  # Show logo page for 2 seconds on startup

        # Cycle timer for displaying idle page
        self.cycle_timer = QTimer()
        self.cycle_timer.timeout.connect(self.show_idle_page)
        self.cycle_timer.start(BREAKFREQ)  

        # Timer for updating table content
        self.update_timer = QTimer()
        self.update_timer.timeout.connect(self.update_table)

        # Timer for updating toolbar actions
        self.toolbar_timer = QTimer()
        self.toolbar_timer.timeout.connect(self.update_toolbar)
        self.toolbar_timer.start(TOOLBARUPDATEFREQ)

        self.idlecount_timer = QTimer()
        self.idlecount_timer.timeout.connect(self.update_idlecount)
        self.idlecount_timer.start(1000)  # 1s

        # Timer for updating file buttons
        self.fileRescan_timer = QTimer()
        self.fileRescan_timer.timeout.connect(rescanFilesToRate)
        self.fileRescan_timer.start(FILESCANTIME)

        self.imageurls = []
        self.linkurls = []
        self.imagecache = []
        try:
            for line in urllib.request.urlopen("https://www.3d-gallery.org/gui/gui_image_list.txt"):
                text=line.decode('utf-8', errors='ignore')
                if text != "":
                    parts=text.partition(" ")
                    self.imageurls.append(parts[0])
                    self.linkurls.append(parts[2])
                    self.imagecache.append(None)
        except HTTPError as err:
            print("Notice: Can't fetch image list.", flush=True)
        except Exception:
            pass
        
        
    def get_pending_workflows():
        url = "http://127.0.0.1:8188/queue"
        data = requests.get(url).json()

        running = len(data.get("queue_running", []))
        pending = len(data.get("queue_pending", []))

        return running, pending
    
    def mousePressEvent(self, event):
        """Wenn auf das MainWindow geklickt wird und der Dialog offen ist → bringe Dialog nach vorne"""
        if not self.dialog is None and self.dialog.isVisible():
            self.dialog.raise_()
            self.dialog.activateWindow()
        else:
            super().mousePressEvent(event)

    def open_config(self, state):
        os.startfile(os.path.realpath(os.path.join(path, "../../../../user/default/comfyui_stereoscopic/config.ini")))

    def open_user_config(self, state):
        folder = os.path.abspath(os.path.join(path, r'../../../../user/default/comfyui_stereoscopic/'))
        os.system(f'start "" "{folder}"')
            
    def show_manual(self, state):
        webbrowser.open('file://' + os.path.realpath(os.path.join(path, "../../docs/VR_We_Are_User_Manual.pdf")))
        # webbrowser.open("https://github.com/FortunaCournot/comfyui_stereoscopic/blob/main/docs/VR_We_Are_User_Manual.pdf")

    def _apply_dialog_action_lock(self):
        """Apply lock state for dialog-launch actions and pipeline edit action."""
        self._reconcile_tool_dialog_state()
        locked = bool(getattr(self, '_open_tool_dialogs', set()))
        open_keys = set(getattr(self, '_open_tool_dialogs', set()))

        try:
            if hasattr(self, 'button_check_cutclone_action') and self.button_check_cutclone_action is not None:
                if locked:
                    self.button_check_cutclone_action.setEnabled('cutandclone' in open_keys)
        except Exception:
            pass
        try:
            if hasattr(self, 'button_check_rate_action') and self.button_check_rate_action is not None:
                if locked:
                    self.button_check_rate_action.setEnabled('rate' in open_keys)
        except Exception:
            pass
        try:
            if hasattr(self, 'button_check_judge_action') and self.button_check_judge_action is not None:
                if locked:
                    self.button_check_judge_action.setEnabled('judge' in open_keys)
        except Exception:
            pass

        try:
            action = getattr(self, 'pipeline_edit_action', None)
            if action is not None:
                edit_active = bool(globals().get('editActive', False))
                action.setEnabled((not locked) and (not edit_active))
        except Exception:
            pass

    def _set_tool_dialog_state(self, key: str, is_open: bool):
        try:
            if is_open:
                self._open_tool_dialogs.add(key)
            else:
                self._open_tool_dialogs.discard(key)
                try:
                    self._tool_dialog_refs.pop(key, None)
                except Exception:
                    pass
        except Exception:
            pass

        try:
            self.update_toolbar()
        except Exception:
            pass
        self._apply_dialog_action_lock()

    def _reconcile_tool_dialog_state(self):
        """Remove stale dialog-open flags if dialogs are no longer visible/alive."""
        try:
            stale = []
            for key in list(self._open_tool_dialogs):
                dlg = self._tool_dialog_refs.get(key)
                if dlg is None:
                    stale.append(key)
                    continue
                try:
                    if not dlg.isVisible():
                        stale.append(key)
                except Exception:
                    stale.append(key)
            for key in stale:
                self._open_tool_dialogs.discard(key)
                try:
                    self._tool_dialog_refs.pop(key, None)
                except Exception:
                    pass
        except Exception:
            pass

    def _register_tool_dialog(self, key: str, dialog):
        try:
            self._tool_dialog_refs[key] = dialog
        except Exception:
            pass
        self._set_tool_dialog_state(key, True)

        def _clear(*_args):
            self._set_tool_dialog_state(key, False)
            try:
                if getattr(self, 'dialog', None) is dialog:
                    self.dialog = None
            except Exception:
                pass

        try:
            if hasattr(dialog, 'finished'):
                dialog.finished.connect(_clear)
        except Exception:
            pass
        try:
            dialog.destroyed.connect(_clear)
        except Exception:
            pass

    def _focus_existing_tool_dialog(self, key: str) -> bool:
        """Bring an already-open tool dialog to the foreground.

        Returns True if an open dialog was found and focused.
        """
        try:
            dlg = self._tool_dialog_refs.get(key)
        except Exception:
            dlg = None
        if dlg is None:
            return False
        try:
            if not dlg.isVisible():
                return False
            dlg.raise_()
            dlg.activateWindow()
            try:
                dlg.showNormal()
            except Exception:
                pass
            self.dialog = dlg
            return True
        except Exception:
            return False

    def check_cutandclone(self, state):
        if self._focus_existing_tool_dialog('cutandclone'):
            return
        dialog = RateAndCutDialog(True)
        try:
            dialog.setModal(False)
            dialog.setWindowModality(Qt.NonModal)
        except Exception:
            pass
        self.dialog = dialog
        dialog.show()
        self._register_tool_dialog('cutandclone', dialog)

    def check_rate(self, state):
        if self._focus_existing_tool_dialog('rate'):
            return
        dialog = RateAndCutDialog(False)
        try:
            dialog.setModal(False)
            dialog.setWindowModality(Qt.NonModal)
        except Exception:
            pass
        self.dialog = dialog
        dialog.show()
        self._register_tool_dialog('rate', dialog)

    def check_judge(self, state):
        if self._focus_existing_tool_dialog('judge'):
            return
        dialog = JudgeDialog()
        try:
            dialog.setModal(False)
            dialog.setWindowModality(Qt.NonModal)
        except Exception:
            pass
        self.dialog = dialog
        dialog.show()
        self._register_tool_dialog('judge', dialog)

    def toggle_stage_expanded_enabled(self, state):
        self.toogle_stages_expanded = state
        self.table.setRowCount(0)
        self.table.clear()
        if self.toogle_stages_expanded:
            self.toggle_stages_expanded_action.setIcon(self.toggle_stages_expanded_icon_true)
        else:
            self.toggle_stages_expanded_action.setIcon(self.toggle_stages_expanded_icon_false)
            
    def toggle_pipeline_active_enabled(self, state):
        #if not config("PIPELINE_AUTOFORWARD", "0") == "1":
        #    os.startfile(os.path.realpath(os.path.join(path, "../../../../user/default/comfyui_stereoscopic/config.ini")))
        #else:        
        
        self.toogle_pipeline_active = state
        if self.toogle_pipeline_active:
            if os.path.exists(pipelinePauseLockPath): os.remove(pipelinePauseLockPath)
        else:
            touch( pipelinePauseLockPath )

        #if not config("PIPELINE_AUTOFORWARD", "0") == "1":
        #    self.toggle_pipeline_active_action.setBaseIcon(self.toggle_pipeline_active_icon_stopped)
        #el
        
        if self.toogle_pipeline_active:
            self.toggle_pipeline_active_action.setBaseIcon(self.toggle_pipeline_active_icon_true)
        else:
            if os.path.exists(pipelineActiveLockPath):
                self.toggle_pipeline_active_action.setBaseIcon(self.toggle_pipeline_active_icon_transit)
            else:
                self.toggle_pipeline_active_action.setBaseIcon(self.toggle_pipeline_active_icon_false)
    
    def toogle_pipeline_forwarding_enabled(self, state):
        self.toogle_pipeline_isForwarding = state
        set_property(os.path.realpath(os.path.join(path, "../../../../user/default/comfyui_stereoscopic/config.ini")), "PIPELINE_AUTOFORWARD", "1" if self.toogle_pipeline_isForwarding else "0")

    def init_toolbar(self):
        self.toolbar = QToolBar("Main Toolbar")
        self.addToolBar(self.toolbar)

        self.toggle_stages_expanded_icon_true = QIcon(os.path.join(path, '../../gui/img/expanded64.png'))
        self.toggle_stages_expanded_icon_false = QIcon(os.path.join(path, '../../gui/img/collapsed64.png'))

        # Toggle stage expanded action with icon
        self.toggle_stages_expanded_action = QAction(self.toggle_stages_expanded_icon_true if self.toogle_stages_expanded else self.toggle_stages_expanded_icon_false, "Expanded" if self.toogle_stages_expanded else "Collapsed", self)
        self.toggle_stages_expanded_action.setCheckable(True)
        self.toggle_stages_expanded_action.setChecked(self.toogle_stages_expanded)
        self.toggle_stages_expanded_action.triggered.connect(self.toggle_stage_expanded_enabled)
        self.toolbar.addAction(self.toggle_stages_expanded_action)    
        self.toolbar.widgetForAction(self.toggle_stages_expanded_action).setCursor(Qt.PointingHandCursor)

        self.toggle_pipeline_active_icon_true = QIcon(os.path.join(path, '../../gui/img/pipelineResume.png'))
        self.toggle_pipeline_active_icon_false = QIcon(os.path.join(path, '../../gui/img/pipelinePause.png'))
        self.toggle_pipeline_active_icon_transit = QIcon(os.path.join(path, '../../gui/img/pipelineRequestedPause.png'))
        self.toggle_pipeline_active_icon_stopped = QIcon(os.path.join(path, '../../gui/img/pipelineStopped.png'))
        
        # Toggle pipeline active action with icon
        self.toggle_pipeline_active_action = QCounterAction(self.toggle_pipeline_active_icon_transit, "Task Execution Status", self)
        #if not config("PIPELINE_AUTOFORWARD", "0") == "1":
        #    self.toggle_pipeline_active_action.setBaseIcon(self.toggle_pipeline_active_icon_stopped)
        #el
        if self.toogle_pipeline_active:
            self.toggle_pipeline_active_action.setBaseIcon(self.toggle_pipeline_active_icon_true)
        else:
            if os.path.exists(pipelineActiveLockPath):
                self.toggle_pipeline_active_action.setBaseIcon(self.toggle_pipeline_active_icon_transit)
            else:
                self.toggle_pipeline_active_action.setBaseIcon(self.toggle_pipeline_active_icon_false)
        
        self.toggle_pipeline_active_action.setCheckable(True)
        self.toggle_pipeline_active_action.setChecked(self.toogle_pipeline_active)
        self.toggle_pipeline_active_action.triggered.connect(self.toggle_pipeline_active_enabled)
        self.toolbar.addAction(self.toggle_pipeline_active_action)    
        self.toolbar.widgetForAction(self.toggle_pipeline_active_action).setCursor(Qt.PointingHandCursor)

        # Toggle pipeline forwarding action with icon
        self.toggle_pipeline_forwarding_icon_true = QIcon(os.path.join(path, '../../gui/img/forwardon64.png'))
        self.toggle_pipeline_forwarding_icon_false = QIcon(os.path.join(path, '../../gui/img/forwardoff64.png'))
        self.toggle_pipeline_forwarding_action = QAction(self.toggle_pipeline_forwarding_icon_false,"Forwarding Status", self)
        self.toggle_pipeline_forwarding_action.setCheckable(True)
        if self.toogle_pipeline_isForwarding:
            self.toggle_pipeline_forwarding_action.setIcon(self.toggle_pipeline_forwarding_icon_true)
        else:
            self.toggle_pipeline_forwarding_action.setIcon(self.toggle_pipeline_forwarding_icon_false)
            
        self.toggle_pipeline_forwarding_action.setChecked(self.toogle_pipeline_isForwarding)
        self.toggle_pipeline_forwarding_action.triggered.connect(self.toogle_pipeline_forwarding_enabled)
        self.toolbar.addAction(self.toggle_pipeline_forwarding_action)    
        self.toolbar.widgetForAction(self.toggle_pipeline_forwarding_action).setCursor(Qt.PointingHandCursor)

        self.toolbar.addSeparator()

        self.toolbar.addSeparator()
        
        self.button_check_cutclone_action = QAction(StyledIcon(os.path.join(path, '../../gui/img/cut64.png')), "Crop & Trim")      
        self.button_check_cutclone_action.setCheckable(False)
        self.button_check_cutclone_action.setEnabled(False)
        self.button_check_cutclone_action.triggered.connect(self.check_cutandclone)
        self.toolbar.addAction(self.button_check_cutclone_action)    
        self.toolbar.widgetForAction(self.button_check_cutclone_action).setCursor(Qt.PointingHandCursor)
                             
        self.button_check_rate_action = QAction(StyledIcon(os.path.join(path, '../../gui/img/rate64.png')), "Rate")      
        self.button_check_rate_action.setCheckable(False)
        self.button_check_rate_action.setEnabled(False)
        self.button_check_rate_action.triggered.connect(self.check_rate)
        self.toolbar.addAction(self.button_check_rate_action)    
        self.toolbar.widgetForAction(self.button_check_rate_action).setCursor(Qt.PointingHandCursor)

        self.button_check_judge_action = QAction(StyledIcon(os.path.join(path, '../../gui/img/judge64.png')), "Release")      
        self.button_check_judge_action.setCheckable(False)
        self.button_check_judge_action.triggered.connect(self.check_judge)
        self.button_check_judge_action.setEnabled(False)
        self.toolbar.addAction(self.button_check_judge_action)    
        self.toolbar.widgetForAction(self.button_check_judge_action).setCursor(Qt.PointingHandCursor)
        
        empty = QWidget()
        empty.setSizePolicy(QSizePolicy.Expanding,QSizePolicy.Expanding)
        self.toolbar.addWidget(empty)

        self.button_show_pipeline_action = QAction(QIcon(os.path.join(path, '../../gui/img/pipeline64.png')), "Worflow")      
        self.button_show_pipeline_action.setCheckable(False)
        self.button_show_pipeline_action.triggered.connect(self.show_pipeline)
        self.toolbar.addAction(self.button_show_pipeline_action)    
        self.toolbar.widgetForAction(self.button_show_pipeline_action).setCursor(Qt.PointingHandCursor)
        imagepath=os.path.join(path, "../../../../user/default/comfyui_stereoscopic/uml/autoforward.png")
        if not os.path.exists(imagepath):
            self.button_show_pipeline_action.setEnabled(False)

        self.toolbar.addSeparator()

        self.button_open_config_action = QAction(QIcon(os.path.join(path, '../../gui/img/config64.png')), "Configuration")      
        self.button_open_config_action.setCheckable(False)
        self.button_open_config_action.triggered.connect(self.open_config)
        self.toolbar.addAction(self.button_open_config_action)    
        self.toolbar.widgetForAction(self.button_open_config_action).setCursor(Qt.PointingHandCursor)
        
        self.toolbar.addSeparator()

        self.button_open_user_config_action = QAction(QIcon(os.path.join(path, '../../gui/img/explorerconfig64.png')), "User Config")
        self.button_open_user_config_action.setCheckable(False)
        self.button_open_user_config_action.triggered.connect(self.open_user_config)
        self.toolbar.addAction(self.button_open_user_config_action)
        self.toolbar.widgetForAction(self.button_open_user_config_action).setCursor(Qt.PointingHandCursor)

        self.toolbar.addSeparator()

        self.button_show_manual_action = QAction(QIcon(os.path.join(path, '../../gui/img/manual64.png')), "Manual")      
        self.button_show_manual_action.setCheckable(False)
        self.button_show_manual_action.triggered.connect(self.show_manual)
        self.toolbar.addAction(self.button_show_manual_action)    
        self.toolbar.widgetForAction(self.button_show_manual_action).setCursor(Qt.PointingHandCursor)
        

    def update_idlecount(self):
        try:
            global idletime
            if status=="idle":
                idletime += 1
        except KeyboardInterrupt:
            sys.exit(app.exec_())

    def update_toolbar(self):
        count1=len(getFilesWithoutEdit())
        count2=len(getFilesOnlyEdit()) + len(getFilesOnlyReady())

        self.button_check_cutclone_action.setEnabled(True)
        self.button_check_rate_action.setEnabled(count2+count1>0)
    
        count3=0
        paths = ("../../../../output/vr/check/rate/1", "../../../../output/vr/check/rate/2", "../../../../output/vr/check/rate/3", "../../../../output/vr/check/rate/4", "../../../../output/vr/check/rate/5")
        for p in paths:
            try:
                checkfiles = next(os.walk(os.path.join(path, p)))[2]
                count3+=len(checkfiles)
            except StopIteration as e:
                pass
        self.button_check_judge_action.setEnabled(count3>0)
        self._apply_dialog_action_lock()

    def get_pending_workflows(self):
        hostname = get_property(os.path.realpath(os.path.join(path, "../../../../user/default/comfyui_stereoscopic/config.ini")), "COMFYUIHOST", "127.0.0.1") 
        port = get_property(os.path.realpath(os.path.join(path, "../../../../user/default/comfyui_stereoscopic/config.ini")), "COMFYUIPORT", "8188") 
        url = "http://"+hostname+":"+port+"/queue"
        try:
            data = requests.get(url).json()
            running = len(data.get("queue_running", []))
            pending = len(data.get("queue_pending", []))
            return running, pending
        except:
            return 0, 0
        
    def update_comfyui_count(self):
        running, pending = self.get_pending_workflows()
        count = running + pending
        if count>999:
            self.toggle_pipeline_active_action.setCounterText("***")
        elif count>0:
            self.toggle_pipeline_active_action.setCounterText(str(count))
        else:
            self.toggle_pipeline_active_action.setCounterText("")
        
    def update_table(self):
        global idletime

        try:
            if not os.path.exists(os.path.join(path, "../../../../user/default/comfyui_stereoscopic/.daemonactive")):
                print("QUIT (external signal)", flush=True)
                sys.exit(app.exec_())

            self.toogle_pipeline_active = not os.path.exists(pipelinePauseLockPath)
            self.toggle_pipeline_active_action.setChecked(self.toogle_pipeline_active)
            self.toggle_pipeline_forwarding_action.setChecked(config("PIPELINE_AUTOFORWARD", "0") == "1")
            self.toggle_pipeline_forwarding_action.setIcon(self.toggle_pipeline_forwarding_icon_true if self.toggle_pipeline_forwarding_action.isChecked() else self.toggle_pipeline_forwarding_icon_false)

            # Decide whether to refresh cached data this tick
            try:
                self._table_data_update_tick = getattr(self, '_table_data_update_tick', 0) + 1
            except Exception:
                self._table_data_update_tick = 1
            do_refresh = (self._table_data_update_tick % TABLEDATAUPDATETHRESHOLD == 0)

            # Initialize file-system caches if missing
            try:
                if not hasattr(self, '_fs_cache') or self._fs_cache is None:
                    self._fs_cache = {'input': {}, 'output': {}}
            except Exception:
                self._fs_cache = {'input': {}, 'output': {}}

            # Refresh caches every TABLEDATAUPDATETHRESHOLD ticks (or first run)
            if do_refresh or not self._fs_cache['input'] or not self._fs_cache['output']:
                try:
                    for stage in STAGES:
                        # Input side
                        try:
                            folder_in = os.path.join(path, "../../../../input/vr/" + stage)
                            info_in = {'exists': False, 'count': 0, 'done_count': 0, 'done_nocleanup': False, 'error_count': 0}
                            if os.path.exists(folder_in):
                                info_in['exists'] = True
                                try:
                                    onlyfiles = next(os.walk(folder_in))[2]
                                    onlyfiles = [f for f in onlyfiles if not f.lower().endswith(".txt")]
                                    info_in['count'] = len(onlyfiles)
                                except Exception:
                                    pass
                                # done subfolder
                                subfolder_done = os.path.join(path, "../../../../input/vr/" + stage + "/done")
                                if os.path.exists(subfolder_done):
                                    try:
                                        done_files = next(os.walk(subfolder_done))[2]
                                        info_in['done_nocleanup'] = any(f.lower() == ".nocleanup" for f in done_files)
                                        # exclude marker file from counts
                                        done_files = [f for f in done_files if f.lower() != ".nocleanup"]
                                        info_in['done_count'] = len([f for f in done_files if not f.lower().endswith(".txt")])
                                    except Exception:
                                        pass
                                # error subfolder
                                subfolder_err = os.path.join(path, "../../../../input/vr/" + stage + "/error")
                                if os.path.exists(subfolder_err):
                                    try:
                                        err_files = next(os.walk(subfolder_err))[2]
                                        info_in['error_count'] = len([f for f in err_files if not f.lower().endswith(".txt")])
                                    except Exception:
                                        pass
                            self._fs_cache['input'][stage] = info_in
                        except Exception:
                            pass

                        # Output side
                        try:
                            folder_out = os.path.join(path, "../../../../output/vr/" + stage)
                            info_out = {'exists': False, 'count': 0, 'forward': False}
                            if os.path.exists(folder_out):
                                info_out['exists'] = True
                                try:
                                    onlyfiles = next(os.walk(folder_out))[2]
                                    info_out['forward'] = any(f.lower() == "forward.txt" for f in onlyfiles)
                                    onlyfiles = [f for f in onlyfiles if not f.lower().endswith(".txt")]
                                    info_out['count'] = len(onlyfiles)
                                except Exception:
                                    pass
                            self._fs_cache['output'][stage] = info_out
                        except Exception:
                            pass
                except Exception:
                    pass
                
            #if not config("PIPELINE_AUTOFORWARD", "0") == "1":
            #    self.toggle_pipeline_active_action.setBaseIcon(self.toggle_pipeline_active_icon_stopped)
            #el
            if self.toogle_pipeline_active:
                self.toggle_pipeline_active_action.setBaseIcon(self.toggle_pipeline_active_icon_true)
            else:
                if os.path.exists(pipelineActiveLockPath):
                    self.toggle_pipeline_active_action.setBaseIcon(self.toggle_pipeline_active_icon_transit)
                else:
                    self.toggle_pipeline_active_action.setBaseIcon(self.toggle_pipeline_active_icon_false)


            if self.idle_container_active:
                if idletime < 15:
                    self.show_table()
                
            status="idle"
            activestage=""
            statusfile = os.path.join(path, "../../../../user/default/comfyui_stereoscopic/.daemonstatus")
            # Read status only on refresh ticks, reuse cached values otherwise
            try:
                if do_refresh:
                    if os.path.exists(statusfile):
                        with open(statusfile, 'r', encoding='utf-8', errors='replace') as file:
                            statuslines = [line.rstrip() for line in file]
                            for line in range(len(statuslines)):
                                if line==0:
                                    activestage=statuslines[0]
                                    status="processing"
                                    idletime=0
                                else:
                                    status=status + " " + statuslines[line]
                    # cache status
                    self._status_cache = {
                        'status': status,
                        'activestage': activestage,
                        'statuslines': statuslines if 'statuslines' in locals() else []
                    }
                else:
                    sc = getattr(self, '_status_cache', None)
                    if sc:
                        status = sc.get('status', status)
                        activestage = sc.get('activestage', activestage)
                        statuslines = sc.get('statuslines', [])
                    else:
                        statuslines = []
            except Exception:
                statuslines = []
            self.setWindowTitle("VR we are - " + activestage + ": " + status)
            # Wenn ein Doppelpunkt in status vorkommt, alles ab diesem Zeichen entfernen
            if ':' in status:
                status = status.split(':', 1)[0]

            # Try to find a relative file path in the daemonstatus lines (heuristic).
            # Store absolute path on the app for tooltip usage.
            # Only re-parse the status contents when the file changed since the
            # last read to avoid repeated work at TABLEUPDATEFREQ.
            try:
                tuple_status = tuple(statuslines)
            except Exception:
                tuple_status = None

            # If we couldn't read statuslines (e.g. status file missing), skip
            # re-evaluation. Only re-parse when we have a valid tuple_status.
            if tuple_status is None:
                # clear any known processing file when status is not available
                try:
                    self._last_daemon_status = None
                except Exception:
                    self._last_daemon_status = None
                self.current_processing_file = None
            elif tuple_status == getattr(self, '_last_daemon_status', None):
                # status unchanged -> keep previous self.current_processing_file
                pass
            else:
                # status changed -> re-evaluate candidate
                try:
                    self._last_daemon_status = tuple_status
                except Exception:
                    self._last_daemon_status = None
                self.current_processing_file = None
                # Robust filename extraction: collect all tokens that look like image/video files
                # and choose the longest match to avoid truncated pieces like "_1.png".
                rel_candidate = None
                try:
                    try:
                        image_exts = set(e.lower() for e in IMAGE_EXTENSIONS)
                    except Exception:
                        image_exts = {'.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp', '.tif', '.tiff'}
                    try:
                        video_exts = set(e.lower() for e in VIDEO_EXTENSIONS)
                    except Exception:
                        video_exts = {'.mp4', '.mov', '.avi', '.mkv', '.webm', '.mpeg', '.mpg'}
                    ext_group = '|'.join(sorted({e.lstrip('.') for e in (image_exts | video_exts)}))
                    pattern = rf"([^\s]+\.(?:{ext_group}))"
                except Exception:
                    pattern = r"([^\s]+\.(?:png|jpg|jpeg|bmp|gif|webp|tif|tiff|mp4|mov|avi|mkv|webm|mpeg|mpg))"

                try:
                    all_matches = []
                    for ln in statuslines[1:]:
                        try:
                            ms = re.findall(pattern, ln, flags=re.IGNORECASE)
                            if ms:
                                all_matches.extend(ms)
                        except Exception:
                            pass
                    if all_matches:
                        # pick the longest to favor full names over fragments
                        rel_candidate = max(all_matches, key=len)
                        try:
                            if TRACELEVEL >= 1:
                                print(f"daemonstatus matches: {all_matches} -> chosen: {rel_candidate}", flush=True)
                        except Exception:
                            pass
                except Exception:
                    rel_candidate = None
                if rel_candidate:
                    # Try sensible locations in order:
                    # 1) If status first line names the stage, look under input/vr/<stage>/<rel_candidate>
                    # 2) Fallback: treat rel_candidate as repository-relative path as before
                    candidate_paths = []
                    # stage name from statuslines[0] if available
                    try:
                        stage_name = statuslines[0] if len(statuslines) > 0 else None
                    except Exception:
                        stage_name = None

                    # If rel_candidate looks like a bare filename, prefer input/vr/<stage>/
                    # Also include input/vr/tasks/<stage>/ variant to cover task-staged inputs.
                    # Additionally, apply CLI-like sanitization to filename to match renamed files.
                    if stage_name and not any(sep in rel_candidate for sep in ('/', '\\')):
                        # Normalize stage name and try both direct and tasks/ variants
                        try:
                            sn_norm = stage_name.replace('\\', '/').strip()
                        except Exception:
                            sn_norm = stage_name
                        base_input_vr = os.path.abspath(os.path.join(path, "../../../../input/vr"))
                        # Compute sanitized filename variant: replace non [A-Za-z0-9._-] chars with '_'
                        try:
                            base_name = rel_candidate
                            sanitized_name = re.sub(r'[^A-Za-z0-9._-]', '_', base_name)
                        except Exception:
                            sanitized_name = rel_candidate
                        # If stage already includes 'tasks/', don't add another 'tasks/'
                        if sn_norm.lower().startswith('tasks/'):
                            # Direct tasks/<stage>/<file>
                            candidate_paths.append(os.path.join(base_input_vr, sn_norm, rel_candidate))
                            if sanitized_name and sanitized_name != rel_candidate:
                                candidate_paths.append(os.path.join(base_input_vr, sn_norm, sanitized_name))
                            # Also try without the 'tasks/' prefix in case files live under input/vr/<stage>/<file>
                            try:
                                without_tasks = sn_norm.split('/', 1)[1] if '/' in sn_norm else sn_norm[len('tasks/'):]
                            except Exception:
                                without_tasks = sn_norm
                            candidate_paths.append(os.path.join(base_input_vr, without_tasks, rel_candidate))
                            if sanitized_name and sanitized_name != rel_candidate:
                                candidate_paths.append(os.path.join(base_input_vr, without_tasks, sanitized_name))
                        else:
                            candidate_paths.append(os.path.join(base_input_vr, sn_norm, rel_candidate))
                            candidate_paths.append(os.path.join(base_input_vr, 'tasks', sn_norm, rel_candidate))
                            if sanitized_name and sanitized_name != rel_candidate:
                                candidate_paths.append(os.path.join(base_input_vr, sn_norm, sanitized_name))
                                candidate_paths.append(os.path.join(base_input_vr, 'tasks', sn_norm, sanitized_name))

                    # Always try the original heuristic too
                    candidate_paths.append(os.path.abspath(os.path.join(path, "../../../../" + rel_candidate)))
                    # Also try sanitized name with repo-relative heuristic
                    try:
                        if sanitized_name and sanitized_name != rel_candidate:
                            candidate_paths.append(os.path.abspath(os.path.join(path, "../../../../" + sanitized_name)))
                    except Exception:
                        pass

                    found_path = None
                    for pth in candidate_paths:
                        try:
                            exists = os.path.exists(pth)
                        except Exception:
                            exists = False
                        try:
                            if TRACELEVEL >= 1:
                                print(f"daemonstatus candidate: {rel_candidate} -> {pth} exists={exists}", flush=True)
                        except Exception:
                            pass
                        if exists:
                            found_path = pth
                            break

                    if found_path:
                        self.current_processing_file = found_path

            fontC0 = QFont()
            fontC0.setBold(True)
            fontC0.setItalic(True)

            fontR0 = QFont()
            fontR0.setBold(True)
            fontR0.setItalic(True)

            COLNAMES = []
            if self.toogle_stages_expanded:
                COLS = 8
                self.table.setColumnCount(COLS)
                header = self.table.horizontalHeader()
                header.setSectionResizeMode(QHeaderView.Fixed)
                COLNAMES.clear()
                COL_IDX_STAGENAME = 0
                header.setSectionResizeMode(COL_IDX_STAGENAME, QHeaderView.ResizeToContents)
                COLNAMES.append("")
                self.COL_IDX_IN_TYPES = 1
                header.setSectionResizeMode(self.COL_IDX_IN_TYPES, QHeaderView.ResizeToContents)
                COLNAMES.append("type")
                self.COL_IDX_IN = 2
                COLNAMES.append("input (done)")
                COL_IDX_PROCESSING = 3
                COLNAMES.append("processing")
                self.COL_IDX_OUT = 4
                header.setSectionResizeMode(self.COL_IDX_OUT, QHeaderView.Stretch)
                COLNAMES.append("output")
                # Insert Pin and Used columns before Config; keep Config at the end
                self.COL_IDX_PIN = self.COL_IDX_OUT + 1
                self.COL_IDX_USED = self.COL_IDX_OUT + 2
                self.COL_IDX_CONFIG = self.COL_IDX_OUT + 3
                header.setSectionResizeMode(self.COL_IDX_PIN, QHeaderView.Fixed)
                header.setSectionResizeMode(self.COL_IDX_USED, QHeaderView.Fixed)
                header.setSectionResizeMode(self.COL_IDX_CONFIG, QHeaderView.Fixed)
                # small fixed widths for icon-only columns
                self.table.setColumnWidth(self.COL_IDX_PIN, 56)
                self.table.setColumnWidth(self.COL_IDX_USED, 56)
                self.table.setColumnWidth(self.COL_IDX_CONFIG, 56)
                COLNAMES.append("Pin")
                COLNAMES.append("Used")
                COLNAMES.append("Config")
            else:
                # Compact view: include Used column always (icon-only)
                COLS = 5
                self.table.setColumnCount(COLS)
                header = self.table.horizontalHeader()
                COLNAMES.clear()
                COL_IDX_STAGENAME = 0
                header.setSectionResizeMode(COL_IDX_STAGENAME, QHeaderView.ResizeToContents)
                COLNAMES.append("")
                self.COL_IDX_IN = 1
                COLNAMES.append("input (done)")
                COL_IDX_PROCESSING = 2
                COLNAMES.append("processing")
                self.COL_IDX_OUT = 3
                header.setSectionResizeMode(self.COL_IDX_OUT, QHeaderView.Stretch)
                COLNAMES.append("output")
                # In compact mode we do not show Pin/Config, but Always show Used
                self.COL_IDX_PIN = None
                self.COL_IDX_USED = self.COL_IDX_OUT + 1
                self.COL_IDX_CONFIG = None
                header.setSectionResizeMode(self.COL_IDX_USED, QHeaderView.Fixed)
                self.table.setColumnWidth(self.COL_IDX_USED, 56)
                COLNAMES.append("Used")
            
            skippedrows = 0
            self.table.clear()
            # cache of default per-row formats (stage_idx -> {col: (QFont, color_name)})
            try:
                self.table._row_default_formats = {}
            except Exception:
                pass
            ROW2STAGE.clear()
            for r in range(ROWS):
                displayRequired = False
                currentRowItems = []
                for c in range(COLS):
                    preview_for_row = None
                    if c == COL_IDX_STAGENAME:
                        if r == 0:
                            value = ""
                        else:
                            displayRequired = True
                            value = STAGES[r-1]
                        item = QTableWidgetItem(value)
                        item.setFont(fontC0)
                        if r > 0:
                            if value.startswith("tasks/_"):
                                item.setForeground(QBrush(QColor("#666666")))
                            elif value.startswith("tasks/"):
                                item.setForeground(QBrush(QColor("#888888")))
                            else:
                                item.setForeground(QBrush(QColor("#CCCCCC")))
                        else:
                            item.setForeground(QBrush(QColor("#CCCCCC")))
                        item.setBackground(QBrush(QColor("black")))
                        item.setTextAlignment(Qt.AlignLeft + Qt.AlignVCenter)
                    else:
                        color = "lightgray"
                        if r == 0:
                            displayRequired = True
                            value = COLNAMES[c]
                            color = "gray"
                        else:
                            if c == self.COL_IDX_IN:
                                stage_name = STAGES[r-1]
                                info = getattr(self, '_fs_cache', {'input':{}}).get('input', {}).get(stage_name, None)
                                if info and info.get('exists', False):
                                    count = info.get('count', 0)
                                    if count > 0:
                                        value = str(count)
                                        displayRequired = True
                                    else:
                                        value = ""
                                    # done subfolder interpretation
                                    if info.get('done_nocleanup', False):
                                        displayRequired = True
                                        count2 = info.get('done_count', 0)
                                        if count2 > 0:
                                            value = value + " (" + str(count2) + ")"
                                            color = "green"
                                        elif count == 0:
                                            value = value + " (-)"
                                    else:
                                        color = "yellow"
                                    # error files
                                    errc = info.get('error_count', 0)
                                    if errc > 0:
                                        value = value + " " + str(errc) + "!"
                                        color = "red"
                                        displayRequired = True
                                else:
                                    value = "?"
                                    color = "red"
                                    displayRequired = True
                            elif c == self.COL_IDX_OUT:
                                stage_name = STAGES[r-1]
                                info = getattr(self, '_fs_cache', {'output':{}}).get('output', {}).get(stage_name, None)
                                if info and info.get('exists', False):
                                    forward = info.get('forward', False)
                                    if not forward:
                                        color = "green"
                                    count = info.get('count', 0)
                                    if count > 0:
                                        displayRequired = True
                                        value = str(count)
                                        if idletime > 15:
                                            color = "green"
                                    else:
                                        value = ""
                                    if forward:
                                        value = value + " ➤"
                                else:
                                    value = "?"
                                    color = "red"
                                    displayRequired = True
                            elif c == COL_IDX_PROCESSING:
                                value = ""
                                if status != "idle":
                                    if activestage == STAGES[r-1]:
                                        value = status
                                        color = "yellow"
                                        displayRequired = True
                                        try:
                                            if hasattr(self, 'current_processing_file') and self.current_processing_file:
                                                preview_for_row = self.current_processing_file
                                        except Exception:
                                            preview_for_row = None
                            elif self.toogle_stages_expanded:
                                if c == self.COL_IDX_IN_TYPES:
                                    if len(self.stageTypes) + 1 == ROWS:  # use cache
                                        value = self.stageTypes[r-1]
                                        color = "#5E271F"  # need also to set below
                                        if value == "video":
                                            color = "#04018C"   # need also to set below
                                        elif value == "image":
                                            color = "#018C08"   # need also to set below
                                        elif value == "?":
                                            displayRequired = True
                                            color = "red"
                                    else:  # build and store in cache
                                        if re.match(r"tasks/_.*", STAGES[r-1]):
                                            stageDefRes = "user/default/comfyui_stereoscopic/tasks/" + STAGES[r-1][7:] + ".json"
                                        elif re.match(r"tasks/.*", STAGES[r-1]):
                                            stageDefRes = "custom_nodes/comfyui_stereoscopic/config/tasks/" + STAGES[r-1][6:] + ".json"
                                        else:
                                            stageDefRes = "custom_nodes/comfyui_stereoscopic/config/stages/" + STAGES[r-1] + ".json"

                                        value = "?"
                                        defFile = os.path.join(path, "../../../../" + stageDefRes)
                                        if os.path.exists(defFile):
                                            with open(defFile, encoding="utf-8", errors="replace") as file:
                                                color = "#5E271F"
                                                deflines = [line.rstrip() for line in file]
                                                for line in range(len(deflines)):
                                                    inputMatch = re.match(r".*\"input\":", deflines[line])
                                                    if inputMatch:
                                                        valuepart = deflines[line][inputMatch.end():]
                                                        match = re.search(r"\".*\"", valuepart)
                                                        if match:
                                                            value = valuepart[match.start()+1:match.end()][:-1]
                                                            if value == "video":
                                                                color = "#04018C"
                                                            elif value == "image":
                                                                color = "#018C08"
                                                        else:
                                                            value = "?"
                                        self.stageTypes.append(value)
                                        if value == "?":
                                            displayRequired = True
                                            color = "red"
                                elif c == self.COL_IDX_OUT + 1:
                                    # Pin column (icon-only)
                                    value = ""
                                    color = "lightgray"
                                elif c == self.COL_IDX_OUT + 2:
                                    # Used column (icon-only)
                                    value = ""
                                    color = "lightgray"
                                elif c == self.COL_IDX_OUT + 3:
                                    # Config column (gear) only for tasks
                                    if re.match(r"tasks/.*", STAGES[r-1]):
                                        value = "⚙"
                                    else:
                                        value = ""
                                    color = "lightgray"
                                else:
                                    value = "?"
                                    color = "red"
                                    displayRequired = True
                            else:
                                value = "?"
                                color = "red"
                                displayRequired = True
                        if value == "":
                            value = "  "
                        item = QTableWidgetItem(value)
                        if r == 0:
                            item.setFont(fontR0)
                        # preserve drag-forced color if present (use stage index key)
                        try:
                            if r > 0:
                                stage_idx = r-1
                                forced = None
                                if hasattr(self.table, '_drag_forced_colors'):
                                    lst = self.table._drag_forced_colors
                                    try:
                                        if stage_idx < len(lst):
                                            forced = lst[stage_idx]
                                    except Exception:
                                        forced = None
                                if forced and c == COL_IDX_STAGENAME:
                                    item.setForeground(QBrush(forced))
                                else:
                                    item.setForeground(QBrush(QColor(color)))
                            else:
                                item.setForeground(QBrush(QColor(color)))
                        except Exception:
                            item.setForeground(QBrush(QColor(color)))
                        item.setTextAlignment(Qt.AlignHCenter + Qt.AlignVCenter)
                        item.setBackground(QBrush(QColor("black")))

                    # Substitute Pin/Used/Config items with icons. Pin/Config only in expanded view; Used always visible if column present.
                    if r > 0:
                        c_pin = getattr(self, 'COL_IDX_PIN', None)
                        c_used = getattr(self, 'COL_IDX_USED', None)
                        c_config = getattr(self, 'COL_IDX_CONFIG', None)
                        if c == c_pin and getattr(self, 'toogle_stages_expanded', False):
                            # create icon item for pin state (use cached pin states)
                            try:
                                stage_name = STAGES[r-1]
                                states = getattr(self, '_pin_states', _load_flag_file(PIN_STATE_FILE))
                                if re.match(r"tasks/_.*", stage_name):
                                    key = 'customtask'
                                elif re.match(r"tasks/.*", stage_name):
                                    key = 'task'
                                else:
                                    key = 'stage'
                                active = stage_name in states.get(key, set())
                                icon_path = os.path.join(path, '../../gui/img', 'pin_on.png' if active else 'pin_off.png')
                                item.setIcon(QIcon(icon_path))
                                item.setText('')
                            except Exception:
                                pass
                        elif c == c_used and c_used is not None:
                            # show Used status even in compact view
                            try:
                                stage_name = STAGES[r-1]
                                # UNUSED file stores disabled items. If not present => default active
                                if not os.path.exists(getattr(self, '_unused_states_file', UNUSED_STATE_FILE)):
                                    active = True
                                else:
                                    states = getattr(self, '_unused_states', _load_flag_file(getattr(self, '_unused_states_file', UNUSED_STATE_FILE)))
                                    if re.match(r"tasks/_.*", stage_name):
                                        key = 'customtask'
                                    elif re.match(r"tasks/.*", stage_name):
                                        key = 'task'
                                    else:
                                        key = 'stage'
                                    # active if NOT listed in unused set
                                    active = stage_name not in states.get(key, set())
                                icon_path = os.path.join(path, '../../gui/img', 'used_on.png' if active else 'used_off.png')
                                item.setIcon(QIcon(icon_path))
                                item.setText('')
                            except Exception:
                                pass
                        elif c == c_config and getattr(self, 'toogle_stages_expanded', False):
                            # keep existing config glyph (text) for now; icon will be set via style if available
                            pass
                    currentRowItems.append(item)
                    # attach preview data to processing item if available
                    try:
                        if preview_for_row and r > 0 and c == COL_IDX_PROCESSING:
                            # Resolve preview path once here, but use a persistent cache so we don't
                            # re-check the filesystem on every table update if the candidate didn't change.
                            final_path = None
                            status = None
                            try:
                                stage_name = STAGES[r-1]
                            except Exception:
                                stage_name = None
                            cache_key = (preview_for_row, stage_name)
                            if cache_key in self._preview_path_cache:
                                try:
                                    final_path, status = self._preview_path_cache[cache_key]
                                except Exception:
                                    final_path, status = None, None
                            else:
                                try:
                                    if os.path.exists(preview_for_row):
                                        final_path = preview_for_row
                                    else:
                                        # attempt fallback using stage name
                                        if stage_name:
                                            folder = os.path.abspath(os.path.join(path, "../../../../input/vr/", stage_name))
                                            if os.path.exists(folder):
                                                b = os.path.basename(preview_for_row)
                                                files = next(os.walk(folder))[2]
                                                for f in files:
                                                    if f == b:
                                                        final_path = os.path.join(folder, f)
                                                        break
                                                if final_path is None:
                                                    # look for any image/video
                                                    try:
                                                        image_exts = set(e.lower() for e in IMAGE_EXTENSIONS)
                                                    except Exception:
                                                        image_exts = {'.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp', '.tif', '.tiff'}
                                                    try:
                                                        video_exts = set(e.lower() for e in VIDEO_EXTENSIONS)
                                                    except Exception:
                                                        video_exts = {'.mp4', '.mov', '.avi', '.mkv', '.webm', '.mpeg', '.mpg'}
                                                    for f in files:
                                                        ext = os.path.splitext(f)[1].lower()
                                                        if ext in image_exts or ext in video_exts:
                                                            final_path = os.path.join(folder, f)
                                                            break
                                except Exception:
                                    final_path = None
                                # store in cache (even None) to avoid repeated checks
                                try:
                                    stat = 'found' if final_path and os.path.exists(final_path) else 'missing'
                                    self._preview_path_cache[cache_key] = (final_path, stat)
                                    status = stat
                                except Exception:
                                    try:
                                        self._preview_path_cache[cache_key] = (final_path, 'missing')
                                    except Exception:
                                        pass

                            # attach final preview info to item: UserRole+1 = path or None, UserRole+4 = status
                            try:
                                stage_idx = r-1
                                # get previously attached tuple for this stage to avoid re-logging
                                try:
                                    last_attached = getattr(self, '_last_attached_previews', {}).get(stage_idx)
                                except Exception:
                                    last_attached = None

                                if status == 'found' and final_path:
                                    new_tuple = (final_path, 'found')
                                else:
                                    new_tuple = (None, 'missing')

                                # If it changed, set and log; otherwise set silently to provide data on the new item
                                try:
                                    if last_attached != new_tuple:
                                        item.setData(_QtRoles.UserRole + 1, new_tuple[0])
                                        item.setData(_QtRoles.UserRole + 2, stage_name)
                                        item.setData(_QtRoles.UserRole + 4, new_tuple[1])
                                        try:
                                            if TRACELEVEL >= 1:
                                                if new_tuple[1] == 'found':
                                                    print(f"Attached preview for row {stage_idx}: {new_tuple[0]}", flush=True)
                                                else:
                                                    print(f"Preview missing for row {stage_idx}: {preview_for_row}", flush=True)
                                        except Exception:
                                            pass
                                        try:
                                            self._last_attached_previews[stage_idx] = new_tuple
                                        except Exception:
                                            pass
                                    else:
                                        # same as before; ensure the new item carries the data but don't log
                                        item.setData(_QtRoles.UserRole + 1, new_tuple[0])
                                        item.setData(_QtRoles.UserRole + 2, stage_name)
                                        item.setData(_QtRoles.UserRole + 4, new_tuple[1])
                                except Exception:
                                    # best-effort: set values
                                    try:
                                        item.setData(_QtRoles.UserRole + 1, new_tuple[0])
                                        item.setData(_QtRoles.UserRole + 2, stage_name)
                                        item.setData(_QtRoles.UserRole + 4, new_tuple[1])
                                    except Exception:
                                        pass
                            except Exception:
                                pass
                    except Exception:
                        pass
                    
                if displayRequired or self.toogle_stages_expanded:
                    for c in range(len(currentRowItems)):
                        self.table.setItem(r-skippedrows, c, currentRowItems[c])
                        if r>0 and c==0:
                            ROW2STAGE.append(r-1)
                    # store default font/foreground for this stage so we can restore later
                    try:
                        if r > 0:
                            stage_idx = r - 1
                            formats = {}
                            for cc in range(len(currentRowItems)):
                                try:
                                    it = self.table.item(r - skippedrows, cc)
                                    if it:
                                        fcopy = QFont(it.font())
                                        try:
                                            fg = it.foreground().color().name() if it.foreground() else None
                                        except Exception:
                                            fg = None
                                        formats[cc] = (fcopy, fg)
                                except Exception:
                                    pass
                            try:
                                self.table._row_default_formats[stage_idx] = formats
                            except Exception:
                                pass
                    except Exception:
                        pass
                else:
                    skippedrows+=1
                    
            if ROWS-skippedrows == 1:
                for c in range(COLS):
                    if c==COL_IDX_PROCESSING:
                        item=QTableWidgetItem("Nothing to display.")
                    else:
                        item=QTableWidgetItem("")
                    font = QFont()
                    font.setBold(False)
                    font.setItalic(True)
                    item.setFont(font)
                    item.setForeground(QBrush(QColor("lightgreen")))
                    item.setTextAlignment(Qt.AlignHCenter + Qt.AlignVCenter)
                    item.setBackground(QBrush(QColor("black")))
                    self.table.setItem(1, c, item)
                self.table.setRowCount(2)
            else:
                self.table.setRowCount(ROWS-skippedrows)
            self.table.resizeRowsToContents()
            # Re-apply any drag-forced colors (keyed by stage name) after table rebuild
            try:
                forced = getattr(self.table, '_drag_forced_colors', []) or []
                for stage_idx, color in enumerate(forced):
                    try:
                        if color is None:
                            continue
                        if stage_idx in ROW2STAGE:
                            pos = ROW2STAGE.index(stage_idx)
                            table_row = pos + 1
                            # apply to stage name column
                            item = self.table.item(table_row, COL_IDX_STAGENAME)
                            if item and color is not None:
                                item.setForeground(QBrush(color))
                            # If this stage was marked clickable-bold, reapply bold across row
                            try:
                                if getattr(self.table, '_clickable_bold_stage', None) == stage_idx:
                                    for cc in range(self.table.columnCount()):
                                        try:
                                            it = self.table.item(table_row, cc)
                                            if it:
                                                f = it.font()
                                                f.setUnderline(True)
                                                it.setFont(f)
                                        except Exception:
                                            pass
                            except Exception:
                                pass
                    except Exception:
                        pass
            except Exception:
                pass
            # Re-apply bold marking for clickable stage even if no forced colors
            try:
                bold_stage = getattr(self.table, '_clickable_bold_stage', None)
                if bold_stage is not None and bold_stage in ROW2STAGE:
                    pos = ROW2STAGE.index(bold_stage)
                    table_row = pos + 1
                    for cc in range(self.table.columnCount()):
                        try:
                            it = self.table.item(table_row, cc)
                            if it:
                                # Use a fresh QFont instance and explicitly force underline
                                # for column 0 to ensure any previous font overrides
                                # are replaced reliably.
                                newf = QFont(it.font())
                                newf.setUnderline(True)
                                it.setFont(newf)
                        except Exception:
                            pass
            except Exception:
                pass
        except KeyboardInterrupt:
            sys.exit(app.exec_())
        except SystemExit:
            sys.exit(app.exec_())
        except:
            print(traceback.format_exc(), flush=True)

    def show_table(self):
        try:
            self.idle_container_active=False
            # Replace logo page with table
            self.layout.removeWidget(self.logo_container)
            self.layout.removeWidget(self.idle_container)
            self.logo_container.setParent(None)
            self.idle_container.setParent(None)
            self.layout.addWidget(self.table)
            self.update_table()
            self.update_timer.start(TABLEUPDATEFREQ)
        except KeyboardInterrupt:
            sys.exit(app.exec_())

    def show_logo_page(self):
        # Switch back to logo page for 5 seconds
        self.update_timer.stop()
        self.layout.removeWidget(self.table)
        self.table.setParent(None)
        self.idle_container.setParent(None)
        self.layout.addWidget(self.logo_container)
        self.switch_timer.start(TABLEUPDATEFREQ)

    def show_idle_page(self):
        if idletime<15:
            return
        
        if len(self.imageurls) > 0:
            newindex=randrange(len(self.imageurls))
            try:
                if self.imagecache[newindex] == None:
                    im = Image.open(requests.get(self.imageurls[newindex], stream=True).raw)
                    pixmap = pil2pixmap(im)
                    self.imagecache[newindex] = pixmap
                else:
                    pixmap = self.imagecache[newindex]
                if not pixmap.isNull():
                    self.idle_container.deleteLater()
                    self.idle_container = QWidget()
                    vbox = QVBoxLayout()
                    self.idle_container.setLayout(vbox)
                    if self.linkurls[newindex] != "":
                        self.idle_image = ClickableLabel(self.linkurls[newindex])
                    else:
                        self.idle_image = QLabel()
                    self.idle_image.setPixmap(pixmap.scaled(512, 512, Qt.KeepAspectRatio, Qt.SmoothTransformation))
                    self.idle_image.setAlignment(Qt.AlignCenter)
                    self.idle_text = QLabel("Idle - waiting for files...")
                    self.idle_text.setAlignment(Qt.AlignCenter)
                    self.idle_text.setStyleSheet("color: white; background-color: black;")
                    idle_font = QFont()
                    idle_font.setPointSize(20)
                    idle_font.setBold(False)
                    self.idle_text.setFont(idle_font)
                    vbox.addWidget(self.idle_image)
                    vbox.addWidget(self.idle_text)
            except Exception as e:
                print("Unexpected error:", sys.exc_info()[0], flush=True)
        self.layout.removeWidget(self.table)
        self.table.setParent(None)
        self.logo_container.setParent(None)
        self.layout.addWidget(self.idle_container)
        # Switch back to main page after BREAKTIME seconds
        self.switch_timer.start(BREAKTIME)
        self.idle_container_active = True

    def isCellClickable(self, row, col):
        if row>0:
            if col == self.COL_IDX_IN:
                return True
            if col == self.COL_IDX_OUT:
                return True
            # allow clicks on Config and our new Pin/Used columns when expanded
            try:
                # Always allow clicking the Used column when present
                try:
                    if col == self.COL_IDX_USED:
                        return True
                except Exception:
                    pass
                # Pin and Config remain expanded-only
                if getattr(self, 'toogle_stages_expanded', False):
                    if col in (self.COL_IDX_PIN, self.COL_IDX_CONFIG):
                        return True
            except Exception:
                pass
        return False

    def onCellClick(self, row, col):
        try:
            idx = ROW2STAGE[row-1]
            # "/select,",  
            if col == self.COL_IDX_IN:
                folder =  os.path.abspath( os.path.join(path, "../../../../input/vr/" + STAGES[idx]) )
                cmd = f'start "" "{folder}"'
                if TRACELEVEL >= 1:
                    print(f"[CLICK] input row={row} stage={STAGES[idx]!r} cmd={cmd!r}", flush=True)
                exit_code = os.system(cmd)
                if TRACELEVEL >= 1:
                    print(f"[CLICK] input row={row} exit_code={exit_code}", flush=True)
                # subprocess.Popen(["explorer", folder ], close_fds=True) - does not close properly

            if col == self.COL_IDX_OUT:
                folder =  os.path.abspath( os.path.join(path, "../../../../output/vr/" + STAGES[idx]) )
                cmd = f'start "" "{folder}"'
                if TRACELEVEL >= 1:
                    print(f"[CLICK] output row={row} stage={STAGES[idx]!r} cmd={cmd!r}", flush=True)
                exit_code = os.system(cmd)
                if TRACELEVEL >= 1:
                    print(f"[CLICK] output row={row} exit_code={exit_code}", flush=True)
                # subprocess.Popen(["explorer", folder ], close_fds=True) - does not close properly

            # Config column (open definition)
            try:
                if getattr(self, 'toogle_stages_expanded', False) and col == self.COL_IDX_CONFIG:
                    if re.match(r"tasks/_.*", STAGES[idx]):
                        stageDefRes="user/default/comfyui_stereoscopic/tasks/" + STAGES[idx][7:] + ".json"
                    elif re.match(r"tasks/.*", STAGES[idx]):
                        stageDefRes="custom_nodes/comfyui_stereoscopic/config/tasks/" + STAGES[idx][6:] + ".json"
                    else:
                        stageDefRes=""
                    defFile = os.path.join(path, "../../../../" + stageDefRes)
                    if os.path.exists(defFile):
                        os.startfile(defFile)
            except Exception:
                pass

            # Pin toggle
            try:
                if getattr(self, 'toogle_stages_expanded', False) and col == self.COL_IDX_PIN:
                    stage_name = STAGES[idx]
                    # use cached pin states
                    states = self._pin_states
                    # determine type key
                    if re.match(r"tasks/_.*", stage_name):
                        key = 'customtask'
                    elif re.match(r"tasks/.*", stage_name):
                        key = 'task'
                    else:
                        key = 'stage'
                    sset = states.get(key, set())
                    if stage_name in sset:
                        sset.remove(stage_name)
                        activated = False
                    else:
                        sset.add(stage_name)
                        activated = True
                    states[key] = sset
                    _save_flag_file(self._pin_states_file, states)
                    # update cell icon immediately
                    try:
                        img_dir = os.path.join(path, '../../gui/img')
                        icon = QIcon(os.path.join(img_dir, 'pin_on.png' if activated else 'pin_off.png'))
                        itm = self.table.item(row, col)
                        if itm:
                            itm.setIcon(icon)
                    except Exception:
                        pass
                    return
            except Exception:
                pass

            # Used/Unused toggle (unused.properties lists disabled entries)
            try:
                if col == self.COL_IDX_USED:
                    stage_name = STAGES[idx]
                    # use cached unused states
                    states = self._unused_states
                    if re.match(r"tasks/_.*", stage_name):
                        key = 'customtask'
                    elif re.match(r"tasks/.*", stage_name):
                        key = 'task'
                    else:
                        key = 'stage'
                    sset = states.get(key, set())
                    # presence in the set means "unused" (disabled)
                    if stage_name in sset:
                        # remove -> now activated/used
                        sset.remove(stage_name)
                        activated = True
                    else:
                        # add -> now deactivated/unused
                        sset.add(stage_name)
                        activated = False
                    states[key] = sset
                    _save_flag_file(self._unused_states_file, states)
                    try:
                        img_dir = os.path.join(path, '../../gui/img')
                        icon = QIcon(os.path.join(img_dir, 'used_on.png' if activated else 'used_off.png'))
                        itm = self.table.item(row, col)
                        if itm:
                            itm.setIcon(icon)
                    except Exception:
                        pass
                    return
            except Exception:
                pass

        except Exception as e:
            print(f"Error on cell click: row={row}, col={col}", flush=True)
            print(e, traceback.format_exc(), flush=True)
            pass
        

   
    def closeEvent(self,event):
        # Close all known open dialogs when main window is closing.
        try:
            dialogs_to_close = []
            seen = set()

            def _add_dialog(dlg):
                try:
                    if dlg is None:
                        return
                    key = id(dlg)
                    if key in seen:
                        return
                    seen.add(key)
                    dialogs_to_close.append(dlg)
                except Exception:
                    pass

            try:
                for dlg in getattr(self, '_tool_dialog_refs', {}).values():
                    _add_dialog(dlg)
            except Exception:
                pass

            _add_dialog(getattr(self, 'dialog', None))
            _add_dialog(getattr(self, 'pipelinedialog', None))
            try:
                _add_dialog(pipelinedialog)
            except Exception:
                pass

            for dlg in dialogs_to_close:
                try:
                    if hasattr(dlg, 'isVisible') and dlg.isVisible():
                        dlg.close()
                except Exception:
                    pass

            try:
                self._open_tool_dialogs.clear()
                self._tool_dialog_refs.clear()
            except Exception:
                pass
        except Exception:
            pass

        try:
            os.remove(os.path.join(path, "../../../../user/default/comfyui_stereoscopic/.guiactive"))
        except OSError as e:
            print("Error: %s - %s." % (e.filename, e.strerror))
        event.accept()

    def show_pipeline(self, state):
        global pipelinedialog, lay
        pipelinedialog = QDialog(None, Qt.WindowSystemMenuHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint)
        pipelinedialog.setWindowTitle("VR We Are - Pipeline")
        pipelinedialog.setModal(True)
        lay = QVBoxLayout(pipelinedialog)
        pal=QPalette()
        bgcolor = QColor("gray") # usually not visible
        role = QPalette.Background
        pal.setColor(role, bgcolor)
        self.setPalette(pal)

        pipeline_toolbar = QToolBar("Pipeline Actions")
        self.pipeline_toolbar = pipeline_toolbar
        lay.addWidget(pipeline_toolbar)
        global editAction
        editAction = QAction("Edit")
        self.pipeline_edit_action = editAction
        editAction.setCheckable(False)
        editAction.triggered.connect(self.edit_pipeline)
        pipeline_toolbar.addAction(editAction)
        pipeline_toolbar.widgetForAction(editAction).setCursor(Qt.PointingHandCursor)
        self._apply_dialog_action_lock()

        empty = QWidget()
        empty.setSizePolicy(QSizePolicy.Expanding,QSizePolicy.Expanding)
        pipeline_toolbar.addWidget(empty)

        self.button_show_pipeline_manual_action = QAction(QIcon(os.path.join(path, '../../gui/img/manualinv64.png')), "Manual")      
        self.button_show_pipeline_manual_action.setCheckable(False)
        self.button_show_pipeline_manual_action.triggered.connect(self.show_manual)
        pipeline_toolbar.addAction(self.button_show_pipeline_manual_action)    
        pipeline_toolbar.widgetForAction(self.button_show_pipeline_manual_action).setCursor(Qt.PointingHandCursor)


        global pipelineErrors
        pipelineErrors=QLabel("Error")
        pipelineErrors.setStyleSheet("color: red; background-color: darkgrey;")
        error_font = QFont()
        error_font.setPointSize(12)
        error_font.setBold(False)
        pipelineErrors.setFont(error_font)
        pipelineErrors.setVisible(False)
        lay.addWidget(pipelineErrors)
        
        global labelPipeline, scroll_area
        labelPipeline = QLabel()
        w, h = 3840, 2160
        pixmap = QPixmap(w, h)
        pixmap.fill(bgcolor)
        
        p = QPainter(pixmap)
        p.drawText(pixmap.rect(), Qt.AlignCenter, "No pipeline")
        p.end()
        
        labelPipeline.setPixmap(pixmap)
        labelPipeline.setSizePolicy(QSizePolicy.Fixed, QSizePolicy.Fixed)
        labelPipeline.setAlignment(Qt.AlignLeft | Qt.AlignTop)
        
        # ScrollArea für horizontales Scrollen
        scroll_area = QScrollArea()
        scroll_area.setWidgetResizable(False)  # Keine Skalierung des Inhalts
        scroll_area.setBackgroundRole(QPalette.Dark)  # Used on right side
        scroll_area.setWidget(labelPipeline)
        scroll_area.setHorizontalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        scroll_area.setVerticalScrollBarPolicy(Qt.ScrollBarAlwaysOff)

        lay.addWidget(scroll_area)
        updatePipeline()
        
        self.button_show_pipeline_action.setEnabled(False)
        self.dialog = pipelinedialog
        try:
            pipelinedialog.finished.connect(self._on_pipeline_dialog_closed)
        except Exception:
            pass
        try:
            pipelinedialog.destroyed.connect(self._on_pipeline_dialog_closed)
        except Exception:
            pass
        pipelinedialog.show()
        self.button_show_pipeline_action.setEnabled(True)

    def _on_pipeline_dialog_closed(self, *_args):
        try:
            self.pipeline_edit_action = None
        except Exception:
            pass
        try:
            self.pipelinedialog = None
        except Exception:
            pass
        try:
            self.dialog = None
        except Exception:
            pass

    def edit_pipeline(self, state):
        configFile=os.path.join(path, r'..\..\..\..\user\default\comfyui_stereoscopic\autoforward.yaml')
        global editActive, pipelineModified, editthread
        pipelineModified=False
        editActive=True
        editAction.setEnabled(False)
        self._apply_dialog_action_lock()
        editthread = PipelineEditThread(window)
        editthread.start()



class QCounterAction(QAction):

    def __init__(self, icon: QIcon, text: str, parent=None):
        super().__init__(text, parent)

        # store base icon
        self._original_icon = icon
        self._counter_text = ""

        self._update_base_pixmap()
        self._render_icon()

    def _update_base_pixmap(self):
        """Extract 80x80 pixmap from the current base icon."""
        if self._original_icon:
            self._base_pixmap = self._original_icon.pixmap(80, 80)
        else:
            pm = QPixmap(80, 80)
            pm.fill(QColor(60, 60, 60))
            self._base_pixmap = pm

    def setBaseIcon(self, icon: QIcon):
        """Call this instead of setIcon() if the image changes."""
        self._original_icon = icon
        self._update_base_pixmap()
        self._render_icon()

    def setCounterText(self, text: str):
        if len(text) > 3:
            text = text[:3]
        self._counter_text = text
        self._render_icon()

    def _render_icon(self):
        """Draw overlay text with a proper outline on a copy of the base pixmap."""
        pixmap = QPixmap(self._base_pixmap)

        if self._counter_text:
            painter = QPainter()
            try:
                painter.begin(pixmap)
                painter.setRenderHints(
                    QPainter.Antialiasing |
                    QPainter.TextAntialiasing |
                    QPainter.SmoothPixmapTransform
                )

                # Auto-scaling for up to 3 characters
                length = len(self._counter_text)
                font_size = 38 if length == 1 else 34 if length == 2 else 30

                font = QFont("Arial", font_size)
                font.setBold(True)

                # Compute centered text placement
                fm = QFontMetrics(font)
                rect = pixmap.rect()

                text_width = fm.horizontalAdvance(self._counter_text)
                text_height = fm.ascent()

                x = (rect.width() - text_width) / 2
                y = (rect.height() + text_height) / 2
                # Move text 1 pixel upward
                y -= 1

                # Create vector outline path
                path = QPainterPath()
                path.addText(x, y, font, self._counter_text)

                # 1️⃣ Real outline stroke: thick & black
                outline_pen = QPen(QColor(0, 0, 0), 6, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin)
                painter.setPen(outline_pen)
                painter.setBrush(Qt.NoBrush)
                painter.drawPath(path)

                # 2️⃣ Fill text in white
                painter.setPen(Qt.NoPen)
                painter.setBrush(QColor(255, 255, 255))
                painter.drawPath(path)

            finally:
                painter.end()

        self.setIcon(QIcon(pixmap))

    def sizeHint(self):
        return QSize(80, 80)


class ImageTooltip(QLabel):
    """Simple tooltip-like widget that displays an image (pixmap).

    Use `show_at(global_pos)` to display near the cursor and `hide()` to dismiss.
    """
    def __init__(self, parent=None):
        super().__init__(parent, Qt.ToolTip)
        self.setWindowFlags(Qt.ToolTip)
        self.setAttribute(Qt.WA_ShowWithoutActivating)
        self.setScaledContents(True)

    def show_at(self, pixmap=None, global_pos=None, max_size=(160, 160), text: str = None):
        try:
            if text:
                # show simple text
                self.setPixmap(QPixmap())
                self.setText(text)
                self.setStyleSheet('color: white; background-color: black; padding: 6px;')
                self.adjustSize()
            elif pixmap is not None and not pixmap.isNull():
                # image: scale so largest side is <= max_size[0]
                w, h = pixmap.width(), pixmap.height()
                max_side = max_size[0]
                if max(w, h) > max_side:
                    scale = max_side / max(w, h)
                    pixmap = pixmap.scaled(int(w * scale), int(h * scale), Qt.KeepAspectRatio, Qt.SmoothTransformation)
                self.setText("")
                self.setPixmap(pixmap)
                self.setStyleSheet('background-color: black;')
                self.setFixedSize(self.pixmap().size())
            else:
                return

            # position slightly offset from cursor
            if global_pos is None:
                pos = QCursor.pos()
            else:
                pos = global_pos
            x = pos.x() + 16
            y = pos.y() + 16
            self.move(x, y)
            self.show()
        except Exception:
            print(traceback.format_exc(), flush=True)



class PipelineEditThread(QThread):
    def __init__(self, parent):
        super().__init__()
        self.parent = parent

    def run(self):


        watchthread = Thread(
            target=self.pipelineWatch,
            args=(),
            daemon=True
        )
        watchthread.start()

        configFile=os.path.join(path, r'..\..\..\..\user\default\comfyui_stereoscopic\autoforward.yaml')
        #os.startfile(os.path.realpath(configFile))

        subprocess.Popen(["notepad", configFile ], close_fds=True).wait()

        global editActive, pipelineModified, editthread

        #if pipelineModified:
        #    softkillFile=os.path.join(path, r'..\..\..\..\user\default\comfyui_stereoscopic\.daemonactive')
        #    os.remove(softkillFile)
            
        editActive=False
        editthread=None
        editAction.setEnabled(True)
        try:
            QTimer.singleShot(0, self.parent._apply_dialog_action_lock)
        except Exception:
            pass

    def pipelineWatch(self):
        try:
            configFile=os.path.join(path, r'..\..\..\..\user\default\comfyui_stereoscopic\autoforward.yaml')
            pythonExe=os.path.join(path, r'..\..\..\..\..\python_embeded\python.exe')
            uml_build_forwards=os.path.join(path, r'..\..\api\python\rebuild_autoforward.py')
            uml_build_definition=os.path.join(path, r'..\..\api\python\uml_build_definition.py')
            uml_generate_image=os.path.join(path, r'..\..\api\python\uml_generate_image.py')

            mtime=os.path.getmtime(configFile)
            while editActive:
                time.sleep(1)
                if not mtime == os.path.getmtime(configFile):
                    mtime=os.path.getmtime(configFile)
                    #print("changed", flush=True)
                    QTimer.singleShot(0, partial(self._setPipelineErrorText, None ))
                    QTimer.singleShot(0, partial(self._hidePipelineShowText, "Rebuilding forward files" ))
                    
                    exit_code, rebuildMsg = self.waitOnSubprocess( subprocess.Popen(pythonExe + r' "' + uml_build_forwards + '"', stderr=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=1, shell=True, text=True, close_fds=False) )
                    if not rebuildMsg == "":
                        QTimer.singleShot(0, partial(self._setPipelineErrorText, rebuildMsg ))
                    
                    #print("forwards", exit_code, flush=True)
                    QTimer.singleShot(0, partial(self._hidePipelineShowText, "Prepare rendering..." ))
                    exit_code, msg = self.waitOnSubprocess( subprocess.Popen(pythonExe + r' "' + uml_build_definition + '"', stderr=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=1, shell=True, text=True, close_fds=False) )
                    #print("prepare rendering", exit_code, flush=True)
                    QTimer.singleShot(0, partial(self._hidePipelineShowText, "Generate new image..." ))
                    exit_code, msg = self.waitOnSubprocess( subprocess.Popen(pythonExe + r' "' + uml_generate_image + '"', stderr=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=1, shell=True, text=True, close_fds=False) )
                    #print("rendered", exit_code, flush=True)
                    QTimer.singleShot(0, partial(self._hidePipelineShowText, "Updating new image..." ))
                    QTimer.singleShot(0, partial(self._updatePipeline))
                    pipelineModified=True
        except:
            print(traceback.format_exc(), flush=True)

    def _updatePipeline(self):
        updatePipeline()

    def _hidePipelineShowText(self, text):
        hidePipelineShowText(text)

    def _setPipelineErrorText(self, text):
        setPipelineErrorText(text)

    def waitOnSubprocess(self, process):
        msgboxtext=""
        try:
            ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
            while True:
                line = process.stdout.readline()
                if not line:
                    break
                line = line.rstrip()
                print(line, flush=True)
                if "Error:" in line:
                    msgboxtext = msgboxtext + ansi_escape.sub('', line) + "\n"
        finally:
            rc = process.wait()
            process.stdout.close()
            process.stderr.close()        
        return (rc, msgboxtext)

class HoverTableWidget(QTableWidget):
    def __init__(self, rows, cols, isCellClickable, onCellClick, parent=None):
        super().__init__(rows, cols, parent)
        self.setEditTriggers(QTableWidget.NoEditTriggers)  # Nur-Lese-Modus
        self.setMouseTracking(True)  # Mausbewegungen ohne Klick erfassen
        self.current_hover = None
        self.isCellClickable=isCellClickable
        self.onCellClick=onCellClick
        self.app = parent  # expected to be SpreadsheetApp
        self.setAcceptDrops(True)
        n_stages = len(STAGES)
        # original colors to restore at drag end
        self._drag_saved_orig = [None] * n_stages
        # color values to restore when hover leaves a row
        self._drag_hover_saved = [None] * n_stages
        # forced colors per stage (e.g. brown for not-allowed, green/red for current)
        self._drag_forced_colors = [None] * n_stages
        self._current_drag_stage = None
        # cache mapping stage_index -> bool (allowed) for current drag
        self._drag_allowed_map = None
        # image tooltip instance (created on demand)
        self._image_tooltip = None
        # cache for preview pixmaps: path -> QPixmap
        self._preview_pixmap_cache = {}
        # last hover debug tuple to avoid repeated prints
        self._last_hover_debug = None
        # currently-clickable stage index (stage_idx) which should be shown bold
        self._clickable_bold_stage = None
        # Auto-scroll timer for drag near-edge behavior
        self._auto_scroll_timer = QTimer(self)
        self._auto_scroll_rows_per_second = 5
        try:
            self._auto_scroll_interval_ms = int(1000 / self._auto_scroll_rows_per_second)
        except Exception:
            self._auto_scroll_interval_ms = 200
        self._auto_scroll_timer.setInterval(self._auto_scroll_interval_ms)
        self._auto_scroll_direction = 0
        self._auto_scroll_timer.timeout.connect(self._perform_auto_scroll)
        # Cached drag payload to avoid re-parsing QMimeData on every move
        self._drag_payload_local_paths = None
        self._drag_payload_remote_urls = None
        self._drag_payload_clip_url = None
        # Ensure rejected drop trace is printed only once per drop operation
        self._drop_reject_logged = False
        # Pending reject details for cases where dropEvent is not emitted
        self._drop_reject_pending = False
        self._drop_reject_pending_reason = None
        self._drop_reject_pending_input_type = None
        # Suppress itemChanged callbacks while we programmatically tint items during drag
        self._suppress_item_changed = False
        # Remember press-handled click to avoid double execution with cellClicked
        self._last_press_handled = None

        # Tabelle mit Beispielwerten füllen
        #for row in range(rows):
        #    for col in range(cols):
        #        item = QTableWidgetItem(f"Zelle {row},{col}")
        #        self.setItem(row, col, item)

        # Signal verbinden, wenn eine Zelle angeklickt wird
        self.cellClicked.connect(self.on_cell_clicked)

        # Signal verbinden, wenn Daten geändert werden
        self.itemChanged.connect(self.on_item_changed)

    def mouseMoveEvent(self, event):
        """Wird aufgerufen, wenn die Maus bewegt wird."""
        index = self.indexAt(event.pos())

        if index.isValid():
            row, col = index.row(), index.column()
            # Nur aktualisieren, wenn sich die Zelle geändert hat
            if self.current_hover != (row, col):
                self.reset_hover_style()
                self.current_hover = (row, col)
                self.apply_hover_style(row, col)
                if self.isCellClickable(row, col):
                    self.setCursor(Qt.PointingHandCursor)
                else:
                    self.setCursor(Qt.ArrowCursor)
        else:
            # Maus außerhalb der Tabelle -> Reset
            self.reset_hover_style()
            self.current_hover = None
            self.setCursor(Qt.ArrowCursor)
            
        super().mouseMoveEvent(event)

    def mousePressEvent(self, event):
        """Handle IO-cell clicks on press to avoid missed cellClicked during frequent table updates."""
        try:
            if event.button() == Qt.LeftButton:
                index = self.indexAt(event.pos())
                if index.isValid():
                    row, col = index.row(), index.column()
                    try:
                        in_col = getattr(self.app, 'COL_IDX_IN', None)
                        out_col = getattr(self.app, 'COL_IDX_OUT', None)
                        used_col = getattr(self.app, 'COL_IDX_USED', None)
                        pin_col = getattr(self.app, 'COL_IDX_PIN', None)
                    except Exception:
                        in_col = out_col = used_col = pin_col = None

                    # treat IO, Used and Pin columns as press-dispatch targets to avoid missed clicks
                    is_io_col = (col == in_col) or (col == out_col) or (col == used_col) or (col == pin_col)
                    if is_io_col and self.isCellClickable(row, col):
                        try:
                            self._last_press_handled = (row, col, time.monotonic())
                        except Exception:
                            self._last_press_handled = (row, col, 0.0)
                        if TRACELEVEL >= 1:
                            print(f"[CLICK] press-dispatch row={row} col={col}", flush=True)
                        self.onCellClick(row, col)
                        event.accept()
                        return
        except Exception:
            pass

        super().mousePressEvent(event)

    def _perform_auto_scroll(self):
        """Called by timer to perform one auto-scroll step in the current direction."""
        try:
            if self._auto_scroll_direction == 0:
                return
            sb = self.verticalScrollBar()
            if not sb:
                return
            # approximate one-row scroll using first row height
            row_count = self.rowCount()
            if row_count <= 0:
                return
            try:
                row_height = max(1, self.rowHeight(0))
            except Exception:
                row_height = 20
            # Prefer using the scrollbar's configured singleStep (pixels) which
            # typically corresponds to a small, sane increment. Fallback to
            # row height if singleStep is not useful.
            try:
                step = int(sb.singleStep()) if sb.singleStep() and sb.singleStep() > 0 else row_height
            except Exception:
                step = row_height
            delta = int(step * self._auto_scroll_direction)
            newv = sb.value() + delta
            # clamp
            newv = max(sb.minimum(), min(sb.maximum(), newv))
            if newv == sb.value():
                # can't scroll further in this direction -> stop
                self._stop_auto_scroll()
                return
            sb.setValue(newv)
        except Exception:
            pass

    def dragEnterEvent(self, event):
        # reset one-shot reject logging for a new drag operation
        self._drop_reject_logged = False
        self._drop_reject_pending = False
        self._drop_reject_pending_reason = None
        self._drop_reject_pending_input_type = None
        md = event.mimeData()
        if md.hasUrls() or md.hasFormat('application/x-qt-windows-mime;value="UniformResourceLocatorW"'):
            # suppress itemChanged during drag tinting
            self._suppress_item_changed = True
            # compute allowed map for all stages once at drag start
            try:
                qurls = md.urls()
                local_paths = [u.toLocalFile() for u in qurls if u.isLocalFile()]
                remote_urls = [u.toString() for u in qurls if not u.isLocalFile()]
            except Exception:
                local_paths = []
                remote_urls = []

            url_from_clip = None
            if md.hasFormat('application/x-qt-windows-mime;value="UniformResourceLocatorW"'):
                try:
                    data = md.data('application/x-qt-windows-mime;value="UniformResourceLocatorW"')
                    url_from_clip = bytes(data).decode('utf-16', errors='ignore').strip('\x00').strip()
                except Exception:
                    url_from_clip = None

            allowed = [False] * len(STAGES)
            # Evaluate against all known stages by index (stage_idx)
            for stage_idx, stage_name in enumerate(STAGES):
                input_type = get_stage_input_type(stage_name)
                ok = True
                for p in local_paths:
                    if not _is_allowed_for_type(p, input_type):
                        ok = False
                        break
                if ok:
                    for u in remote_urls:
                        if not _is_url_allowed_for_type_quick(u, input_type):
                            ok = False
                            break
                if ok and url_from_clip:
                    if not _is_url_allowed_for_type_quick(url_from_clip, input_type):
                        ok = False
            
                allowed[stage_idx] = ok

            self._drag_allowed_map = allowed
            # cache payload for subsequent dragMove/dropEvent to avoid repeated decoding
            try:
                self._drag_payload_local_paths = list(local_paths)
                self._drag_payload_remote_urls = list(remote_urls)
                self._drag_payload_clip_url = url_from_clip
            except Exception:
                pass
            # Set forced dark-brown for stages that are not allowed and remember originals
            dark_brown = QColor("#5E271F")
            try:
                for stage_idx, ok in enumerate(allowed):
                    if not ok:
                        # remember original color for final restore if not already saved
                        try:
                            if self._drag_saved_orig[stage_idx] is None:
                                if stage_idx in ROW2STAGE:
                                    pos = ROW2STAGE.index(stage_idx)
                                    table_row = pos + 1
                                    it = self.item(table_row, 0)
                                    if it and it.foreground():
                                        self._drag_saved_orig[stage_idx] = it.foreground().color().name()
                        except Exception:
                            pass
                        # apply forced brown in the forced colors list and on visible item if possible
                        try:
                            self._drag_forced_colors[stage_idx] = dark_brown
                            if stage_idx in ROW2STAGE:
                                pos = ROW2STAGE.index(stage_idx)
                                table_row = pos + 1
                                it = self.item(table_row, 0)
                                if it:
                                    it.setForeground(QBrush(dark_brown))
                        except Exception:
                            pass
            except Exception:
                pass
            event.acceptProposedAction()
        else:
            event.ignore()

    def _set_pending_drop_reject(self, reason: str, input_type=None):
        """Remember why current drag would be rejected; emitted on dragLeave if no dropEvent happens."""
        self._drop_reject_pending = True
        self._drop_reject_pending_reason = reason
        self._drop_reject_pending_input_type = input_type

    def _clear_pending_drop_reject(self):
        self._drop_reject_pending = False
        self._drop_reject_pending_reason = None
        self._drop_reject_pending_input_type = None

    def dragMoveEvent(self, event):
        # Accept drag over stage name, type, or input columns when row>0
        index = self.indexAt(event.pos())
        if not index.isValid():
            event.ignore()
            return
        row, col = index.row(), index.column()
        # determine allowed drop columns
        allowed_cols = [0]
        try:
            if hasattr(self.app, 'COL_IDX_IN_TYPES') and isinstance(self.app.COL_IDX_IN_TYPES, int):
                allowed_cols.append(self.app.COL_IDX_IN_TYPES)
        except Exception:
            pass
        try:
            if hasattr(self.app, 'COL_IDX_IN') and isinstance(self.app.COL_IDX_IN, int):
                allowed_cols.append(self.app.COL_IDX_IN)
        except Exception:
            pass
        if row <= 0 or col not in allowed_cols:
            event.ignore()
            return

        # Use cached payload from dragEnterEvent to avoid expensive QMimeData parsing per move
        local_paths = self._drag_payload_local_paths or []
        remote_urls = self._drag_payload_remote_urls or []
        url_from_clip = self._drag_payload_clip_url or None

        if not local_paths and not remote_urls and not url_from_clip:
            event.ignore()
            return

        stage_idx = None
        try:
            if hasattr(self.app, 'ROW2STAGE'):
                pass
        except Exception:
            pass

        # Map table row to stage name via parent window variable ROW2STAGE
        try:
            idx = ROW2STAGE[row-1]
            stage_name = STAGES[idx]
        except Exception:
            event.ignore()
            return

        # use cached allowed map computed at drag start; if missing, compute once and store
        all_ok = True
        try:
            table_stage_idx = ROW2STAGE[row-1]
        except Exception:
            table_stage_idx = None
        if not isinstance(self._drag_allowed_map, list):
            # compute a one-off map now
            try:
                allowed = [False] * len(STAGES)
                for s_idx, s_name in enumerate(STAGES):
                    input_type = get_stage_input_type(s_name)
                    ok = True
                    for p in local_paths:
                        if not _is_allowed_for_type(p, input_type):
                            ok = False
                            break
                    if ok:
                        for u in remote_urls:
                            if not _is_url_allowed_for_type_quick(u, input_type):
                                ok = False
                                break
                    if ok and url_from_clip:
                        if not _is_url_allowed_for_type_quick(url_from_clip, input_type):
                            ok = False
                    allowed[s_idx] = ok
                self._drag_allowed_map = allowed
            except Exception:
                pass
        if table_stage_idx is not None and isinstance(self._drag_allowed_map, list) and 0 <= table_stage_idx < len(self._drag_allowed_map):
            all_ok = bool(self._drag_allowed_map[table_stage_idx])

        # change color of item text: green if ok else red
        item = self.item(row, col)
        if item:
            # use stage index as key for drag state
            try:
                table_stage_idx = ROW2STAGE[row-1]
            except Exception:
                table_stage_idx = None

            # if we moved from another stage, restore its color
            prev = self._current_drag_stage
            if prev is not None and prev != table_stage_idx:
                try:
                    if isinstance(prev, int) and 0 <= prev < len(self._drag_hover_saved):
                        # find table row for prev
                        try:
                            if prev in ROW2STAGE:
                                pos = ROW2STAGE.index(prev)
                                prev_row = pos + 1
                                prev_item = self.item(prev_row, col)
                                saved_hover_orig = self._drag_hover_saved[prev]
                                # determine allowed status from cached map
                                allowed = True
                                if isinstance(self._drag_allowed_map, list) and 0 <= prev < len(self._drag_allowed_map):
                                    allowed = bool(self._drag_allowed_map[prev])
                                dark_brown = QColor("#5E271F")
                                # clear hover-saved value
                                self._drag_hover_saved[prev] = None
                                # set forced color state for prev according to allowed
                                try:
                                    if 0 <= prev < len(self._drag_forced_colors):
                                        self._drag_forced_colors[prev] = dark_brown if not allowed else None
                                except Exception:
                                    pass
                                # restore visible color: prefer saved hover original, otherwise apply allowed-based color or saved original
                                if prev_item:
                                    if saved_hover_orig:
                                        prev_item.setForeground(QBrush(QColor(saved_hover_orig)))
                                    else:
                                        if not allowed:
                                            prev_item.setForeground(QBrush(dark_brown))
                                        else:
                                            # try to restore any original color saved at drag-start
                                            try:
                                                orig_final = self._drag_saved_orig[prev] if 0 <= prev < len(self._drag_saved_orig) else None
                                            except Exception:
                                                orig_final = None
                                            if orig_final:
                                                prev_item.setForeground(QBrush(QColor(orig_final)))
                                            else:
                                                # no saved color — leave as-is (no forced color)
                                                pass
                        except Exception:
                            try:
                                self._drag_hover_saved[prev] = None
                            except Exception:
                                pass
                except Exception:
                    pass

            # store hover-original color (restore when hover leaves)
            if table_stage_idx is not None and isinstance(table_stage_idx, int) and 0 <= table_stage_idx < len(self._drag_hover_saved) and self._drag_hover_saved[table_stage_idx] is None:
                orig = item.foreground().color().name() if item.foreground() else None
                self._drag_hover_saved[table_stage_idx] = orig

            forced = QColor("green" if all_ok else "red")
            # set forced only for current stage, preserve initial not-allowed browns
            try:
                forced_list = list(self._drag_forced_colors)
            except Exception:
                forced_list = [None] * len(STAGES)

            # restore previous index forced entry according to allowed map
            try:
                if prev is not None and isinstance(prev, int) and 0 <= prev < len(forced_list):
                    if isinstance(self._drag_allowed_map, list) and 0 <= prev < len(self._drag_allowed_map) and not self._drag_allowed_map[prev]:
                        forced_list[prev] = QColor("#5E271F")
                    else:
                        forced_list[prev] = None
            except Exception:
                pass

            if table_stage_idx is not None and isinstance(table_stage_idx, int) and 0 <= table_stage_idx < len(forced_list):
                forced_list[table_stage_idx] = forced
            # Only apply foreground change if different to avoid itemChanged storms
            try:
                current_name = item.foreground().color().name() if item.foreground() else None
                forced_name = forced.name()
            except Exception:
                current_name = None
                forced_name = None
            self._drag_forced_colors = forced_list
            if forced_name != current_name:
                item.setForeground(QBrush(forced))

        # Auto-scroll when hovering the first/last visible row and scrolling is possible
        try:
            first_visible = self.rowAt(0)
            last_visible = self.rowAt(self.viewport().height() - 1)
            sb = self.verticalScrollBar()
            # when over last visible row and can scroll down
            if row == last_visible and sb is not None and sb.value() < sb.maximum():
                # start scrolling down
                if self._auto_scroll_direction != 1:
                    self._start_auto_scroll(1)
            # when over first visible row and can scroll up
            elif row == first_visible and sb is not None and sb.value() > sb.minimum():
                if self._auto_scroll_direction != -1:
                    self._start_auto_scroll(-1)
            else:
                # stop any auto-scroll if not at edges
                if self._auto_scroll_direction != 0:
                    self._stop_auto_scroll()
        except Exception:
            pass

        # remember current hovered stage index for next move
        try:
            self._current_drag_stage = table_stage_idx
        except Exception:
            self._current_drag_stage = None

        if all_ok:
            self._clear_pending_drop_reject()
            event.acceptProposedAction()
        else:
            try:
                stage_input_type = get_stage_input_type(stage_name)
            except Exception:
                stage_input_type = None
            self._set_pending_drop_reject("dragMove disallowed for hovered stage", stage_input_type)
            event.ignore()

    def _trace_drop_reject_once(self, reason: str, input_type=None, local_paths=None, remote_urls=None, url_from_clip=None):
        """Emit one TRACELEVEL>=1 log for a rejected drop with type-identification details."""
        if TRACELEVEL < 1:
            return
        if getattr(self, '_drop_reject_logged', False):
            return
        self._drop_reject_logged = True

        local_paths = local_paths or []
        remote_urls = remote_urls or []

        if isinstance(input_type, str):
            types = [t.strip().lower() for t in input_type.split(';') if t.strip()]
        elif input_type is None:
            types = []
        else:
            types = [str(input_type).strip().lower()]

        def _allowed_by_content_type(content_type_value: str) -> bool:
            if not content_type_value:
                return False
            for t in types:
                if t == 'image' and content_type_value.startswith('image/'):
                    return True
                if t == 'video' and content_type_value.startswith('video/'):
                    return True
                if t in ('file', 'any'):
                    return True
            return False

        print(f"[DND] Drop rejected: reason={reason!r}", flush=True)
        print(f"[DND] expected_input_type={input_type!r} expected_types={types!r}", flush=True)

        for p in local_paths:
            try:
                ext = os.path.splitext(p)[1].lower()
            except Exception:
                ext = ''
            try:
                allowed_local = _is_allowed_for_type(p, input_type) if isinstance(input_type, str) else False
            except Exception:
                allowed_local = False
            print(f"[DND] local path={p!r} ext={ext!r} allowed={allowed_local}", flush=True)

        def _log_url_probe(label: str, url: str):
            if not url:
                return
            display_url = url
            data_content_type = ''
            is_data_url = False
            try:
                if isinstance(url, str) and url.lower().startswith('data:'):
                    is_data_url = True
                    data_header = url[5:].split(',', 1)[0]
                    data_content_type = (data_header.split(';', 1)[0] or '').strip().lower()
                    display_url = f"data:{data_content_type or 'unknown'};..."
            except Exception:
                pass
            try:
                if is_data_url:
                    path_ext = ''
                else:
                    parsed = urllib.parse.urlparse(url)
                    path_ext = os.path.splitext(parsed.path)[1].lower()
            except Exception:
                path_ext = ''

            try:
                quick_allowed = _is_url_allowed_for_type_quick(url, input_type) if isinstance(input_type, str) else False
            except Exception:
                quick_allowed = False

            content_type = ''
            content_type_probe_error = None
            if is_data_url:
                content_type = data_content_type
            else:
                try:
                    resp = requests.get(url, stream=True, timeout=6, headers={"User-Agent": "Mozilla/5.0"})
                    content_type = resp.headers.get('Content-Type', '')
                    try:
                        resp.close()
                    except Exception:
                        pass
                except Exception as e:
                    content_type_probe_error = str(e)

            allowed_content_type = _allowed_by_content_type(content_type)
            try:
                strict_allowed = _is_url_allowed_for_type(url, input_type) if isinstance(input_type, str) else False
            except Exception:
                strict_allowed = False
            print(
                f"[DND] {label} url={display_url!r} path_ext={path_ext!r} quick_allowed={quick_allowed} "
                f"content_type={content_type!r} content_type_probe_error={content_type_probe_error!r} "
                f"allowed_by_content_type={allowed_content_type} strict_allowed={strict_allowed}",
                flush=True,
            )

        for u in remote_urls:
            _log_url_probe('remote', u)
        if url_from_clip:
            _log_url_probe('clip', url_from_clip)
        self._clear_pending_drop_reject()

    def dropEvent(self, event):
        # ensure auto-scroll stops when dropping
        try:
            self._stop_auto_scroll()
        except Exception:
            pass
        index = self.indexAt(event.pos())
        if not index.isValid():
            self._trace_drop_reject_once("invalid drop target index", None, self._drag_payload_local_paths, self._drag_payload_remote_urls, self._drag_payload_clip_url)
            event.ignore()
            return
        row, col = index.row(), index.column()
        # allow drops on stage name, type, or input columns
        allowed_cols = [0]
        try:
            if hasattr(self.app, 'COL_IDX_IN_TYPES') and isinstance(self.app.COL_IDX_IN_TYPES, int):
                allowed_cols.append(self.app.COL_IDX_IN_TYPES)
        except Exception:
            pass
        try:
            if hasattr(self.app, 'COL_IDX_IN') and isinstance(self.app.COL_IDX_IN, int):
                allowed_cols.append(self.app.COL_IDX_IN)
        except Exception:
            pass
        if row <= 0 or col not in allowed_cols:
            self._trace_drop_reject_once("drop target row/column not allowed", None, self._drag_payload_local_paths, self._drag_payload_remote_urls, self._drag_payload_clip_url)
            event.ignore()
            return

        # Use cached payload from dragEnterEvent
        local_paths = self._drag_payload_local_paths or []
        remote_urls = self._drag_payload_remote_urls or []
        url_from_clip = self._drag_payload_clip_url or None

        # Avoid double-processing the same URL: if the Windows URL clipboard
        # flavor contains the same URL as one of the QUrls, prefer the
        # clipboard form and remove it from remote_urls to prevent downloading twice.
        try:
            if url_from_clip and url_from_clip in remote_urls:
                remote_urls = [u for u in remote_urls if u != url_from_clip]
        except Exception:
            pass

        # Deduplicate remote_urls to avoid repeated downloads when multiple
        # QUrls carry the same string representation.
        try:
            if remote_urls:
                # preserve order while removing duplicates
                seen = set()
                uniq = []
                for u in remote_urls:
                    if u in seen:
                        continue
                    seen.add(u)
                    uniq.append(u)
                remote_urls = uniq
        except Exception:
            pass

        try:
            idx = ROW2STAGE[row-1]
            stage_name = STAGES[idx]
        except Exception:
            self._trace_drop_reject_once("could not map row to stage", None, local_paths, remote_urls, url_from_clip)
            event.ignore()
            return

        input_type = get_stage_input_type(stage_name)

        # validate local files
        for p in local_paths:
            if not _is_allowed_for_type(p, input_type):
                self._trace_drop_reject_once("local file type not allowed", input_type, local_paths, remote_urls, url_from_clip)
                event.ignore()
                return

        # validate remote urls
        for u in remote_urls:
            if not _is_url_allowed_for_type(u, input_type):
                self._trace_drop_reject_once("remote URL type not allowed", input_type, local_paths, remote_urls, url_from_clip)
                event.ignore()
                return

        if url_from_clip:
            if not _is_url_allowed_for_type(url_from_clip, input_type):
                self._trace_drop_reject_once("clipboard URL type not allowed", input_type, local_paths, remote_urls, url_from_clip)
                event.ignore()
                return

        dest_folder = os.path.abspath(os.path.join(path, "../../../../input/vr/" + stage_name))
        os.makedirs(dest_folder, exist_ok=True)

        def _mime_to_ext(mime: str) -> str:
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

        def _save_data_url_to_file(data_url: str, destination_dir: str, name_prefix: str) -> str:
            if not isinstance(data_url, str) or not data_url.lower().startswith('data:'):
                raise ValueError('not a data URL')
            try:
                header_and_data = data_url[5:]
                meta, payload = header_and_data.split(',', 1)
            except Exception:
                raise ValueError('invalid data URL format')

            meta = meta or ''
            payload = payload or ''
            mime = (meta.split(';', 1)[0] or '').strip().lower()
            is_base64 = ';base64' in meta.lower()

            if is_base64:
                compact_payload = re.sub(r'\s+', '', payload)
                pad = (-len(compact_payload)) % 4
                if pad:
                    compact_payload += '=' * pad
                raw = base64.b64decode(compact_payload)
            else:
                raw = urllib.parse.unquote_to_bytes(payload)

            ext = _mime_to_ext(mime)
            fname = f"{name_prefix}_{int(time.time())}{ext}"
            dest = os.path.join(destination_dir, fname)

            try:
                if os.path.exists(dest):
                    base, ext2 = os.path.splitext(fname)
                    i = 1
                    while True:
                        newname = f"{base}_{i}{ext2}"
                        newdest = os.path.join(destination_dir, newname)
                        if not os.path.exists(newdest):
                            dest = newdest
                            break
                        i += 1
            except Exception:
                pass

            with open(dest, 'wb') as fh:
                fh.write(raw)

            return dest

        move = bool(event.keyboardModifiers() & Qt.ShiftModifier)
        try:
            # copy/move local files
            for p in local_paths:
                base = os.path.basename(p)
                dest = os.path.join(dest_folder, base)
                if move:
                    shutil.move(p, dest)
                else:
                    shutil.copy2(p, dest)

            # download remote URLs
            for u in remote_urls:
                if isinstance(u, str) and u.lower().startswith('data:'):
                    try:
                        _save_data_url_to_file(u, dest_folder, 'download')
                    except Exception:
                        self._trace_drop_reject_once("failed decoding remote data URL", input_type, local_paths, remote_urls, url_from_clip)
                        event.ignore()
                        return
                    continue
                parsed = urllib.parse.urlparse(u)
                fname = os.path.basename(parsed.path) or f"download_{int(time.time())}"
                dest = os.path.join(dest_folder, fname)
                # If destination exists, pick a non-conflicting name by appending _N before the suffix
                try:
                    if os.path.exists(dest):
                        base, ext = os.path.splitext(fname)
                        i = 1
                        while True:
                            newname = f"{base}_{i}{ext}"
                            newdest = os.path.join(dest_folder, newname)
                            if not os.path.exists(newdest):
                                dest = newdest
                                break
                            i += 1
                except Exception:
                    pass
                try:
                    r = requests.get(u, stream=True, timeout=20, headers={"User-Agent": "Mozilla/5.0"})
                    r.raise_for_status()
                    with open(dest, 'wb') as fh:
                        for chunk in r.iter_content(8192):
                            if chunk:
                                fh.write(chunk)
                except Exception:
                    self._trace_drop_reject_once("failed downloading remote URL", input_type, local_paths, remote_urls, url_from_clip)
                    event.ignore()
                    return

            # download URL from clipboard flavor
            if url_from_clip:
                if isinstance(url_from_clip, str) and url_from_clip.lower().startswith('data:'):
                    try:
                        _save_data_url_to_file(url_from_clip, dest_folder, 'clipboard')
                    except Exception:
                        self._trace_drop_reject_once("failed decoding clipboard data URL", input_type, local_paths, remote_urls, url_from_clip)
                        event.ignore()
                        return
                    # keep existing behavior for normal URLs only
                    url_from_clip = None
                if url_from_clip:
                    parsed = urllib.parse.urlparse(url_from_clip)
                    fname = os.path.basename(parsed.path) or f"download_{int(time.time())}"
                    dest = os.path.join(dest_folder, fname)
                    # avoid overwriting existing files from URL drops: append _N before extension
                    try:
                        if os.path.exists(dest):
                            base, ext = os.path.splitext(fname)
                            i = 1
                            while True:
                                newname = f"{base}_{i}{ext}"
                                newdest = os.path.join(dest_folder, newname)
                                if not os.path.exists(newdest):
                                    dest = newdest
                                    break
                                i += 1
                    except Exception:
                        pass
                    try:
                        urllib.request.urlretrieve(url_from_clip, dest)
                    except Exception:
                        try:
                            r = requests.get(url_from_clip, stream=True, timeout=10)
                            r.raise_for_status()
                            with open(dest, 'wb') as fh:
                                for chunk in r.iter_content(8192):
                                    fh.write(chunk)
                        except Exception:
                            self._trace_drop_reject_once("failed downloading clipboard URL", input_type, local_paths, remote_urls, url_from_clip)
                            event.ignore()
                            return

        except Exception:
            self._trace_drop_reject_once("unexpected exception during drop handling", input_type, local_paths, remote_urls, url_from_clip)
            event.ignore()
            return

        # restore color for this stage (keys are stage indices)
        try:
            key_stage_idx = ROW2STAGE[row-1]
        except Exception:
            key_stage_idx = None
        item = self.item(row, col)
        if item and key_stage_idx is not None and isinstance(key_stage_idx, int) and 0 <= key_stage_idx < len(self._drag_saved_orig) and self._drag_saved_orig[key_stage_idx] is not None:
            orig = self._drag_saved_orig[key_stage_idx]
            self._drag_saved_orig[key_stage_idx] = None
            try:
                if 0 <= key_stage_idx < len(self._drag_forced_colors):
                    self._drag_forced_colors[key_stage_idx] = None
            except Exception:
                pass
            if orig:
                item.setForeground(QBrush(QColor(orig)))
        self._current_drag_stage = None
        # clear allowed map at end of drag/drop
        self._drag_allowed_map = None
        # clear cached payload and stop suppressing itemChanged
        self._drag_payload_local_paths = None
        self._drag_payload_remote_urls = None
        self._drag_payload_clip_url = None
        self._drop_reject_logged = False
        self._clear_pending_drop_reject()
        self._suppress_item_changed = False
        event.acceptProposedAction()

    def dragLeaveEvent(self, event):
        """Called when an ongoing drag operation leaves the widget without dropping.

        Restore any forced colors keyed by stage name and clear drag state so
        a cancelled/aborted drag does not leave a lingering color.
        """
        # stop any auto-scroll when drag leaves
        try:
            self._stop_auto_scroll()
        except Exception:
            pass
        # If dropEvent was not triggered (common after dragMove ignore), emit pending reject now.
        try:
            if self._drop_reject_pending and not self._drop_reject_logged:
                self._trace_drop_reject_once(
                    self._drop_reject_pending_reason or "drop not accepted",
                    self._drop_reject_pending_input_type,
                    self._drag_payload_local_paths,
                    self._drag_payload_remote_urls,
                    self._drag_payload_clip_url,
                )
        except Exception:
            pass
        self._reset_drag_state()
        # clear payload and suppression when leaving without drop
        self._drag_payload_local_paths = None
        self._drag_payload_remote_urls = None
        self._drag_payload_clip_url = None
        self._drop_reject_logged = False
        self._clear_pending_drop_reject()
        self._suppress_item_changed = False
        try:
            super().dragLeaveEvent(event)
        except Exception:
            pass

    def _reset_drag_state(self):
        """Restore original foreground colors and clear drag state."""
        try:
            for stage_idx, orig in enumerate(self._drag_saved_orig):
                try:
                    if orig is None:
                        continue
                    if stage_idx in ROW2STAGE:
                        pos = ROW2STAGE.index(stage_idx)
                        table_row = pos + 1
                        item = self.item(table_row, 0)
                        if item and orig:
                            item.setForeground(QBrush(QColor(orig)))
                except Exception:
                    pass
        except Exception:
            pass
        self._drag_saved_orig = [None] * len(STAGES)
        self._drag_hover_saved = [None] * len(STAGES)
        self._drag_forced_colors = [None] * len(STAGES)
        self._current_drag_stage = None
        # clear cached allowed map
        self._drag_allowed_map = None
        # also reset hover/underline state
        self.reset_hover_style()
        self.current_hover = None

    def _start_auto_scroll(self, direction: int):
        """Start auto-scrolling in given direction (1 down, -1 up)."""
        try:
            if direction == 0:
                return
            self._auto_scroll_direction = 1 if direction > 0 else -1
            if not self._auto_scroll_timer.isActive():
                self._auto_scroll_timer.start()
        except Exception:
            pass

    def _stop_auto_scroll(self):
        """Stop any active auto-scrolling."""
        try:
            if self._auto_scroll_timer.isActive():
                self._auto_scroll_timer.stop()
        except Exception:
            pass
        self._auto_scroll_direction = 0

    def leaveEvent(self, event):
        self._reset_drag_state()
        try:
            super().leaveEvent(event)
        except Exception:
            pass

    def focusOutEvent(self, event):
        # Reset drag colors when widget loses focus (mouse may have left window)
        self._reset_drag_state()
        try:
            super().focusOutEvent(event)
        except Exception:
            pass

    def hideEvent(self, event):
        # Reset when widget is hidden
        self._reset_drag_state()
        try:
            super().hideEvent(event)
        except Exception:
            pass

    def mouseReleaseEvent(self, event):
        # ensure auto-scroll stops and reset drag state
        try:
            self._stop_auto_scroll()
        except Exception:
            pass
        # If a drag was in progress but no drop occurred, ensure reset
        self._reset_drag_state()
        # also clear suppression
        self._suppress_item_changed = False
        try:
            super().mouseReleaseEvent(event)
        except Exception:
            pass

    def apply_hover_style(self, row, col):
        # Always check for a preview attached to the item and show tooltip if present
        item = self.item(row, col)
        try:
            if item is not None:
                preview = item.data(_QtRoles.UserRole + 1)
                preview_status = item.data(_QtRoles.UserRole + 4)
            else:
                preview = None
                preview_status = None
        except Exception:
            preview = None
            preview_status = None

        # Extra debug: if status claims 'found' but preview is falsy, log item data once
        try:
            if preview_status == 'found' and not preview:
                try:
                    print(f"Hover inconsistency: status='found' but preview empty for row={row} col={col}. item data roles: role1={item.data(_QtRoles.UserRole + 1)!r}, role2={item.data(_QtRoles.UserRole + 2)!r}, role4={item.data(_QtRoles.UserRole + 4)!r}", flush=True)
                except Exception:
                    pass
        except Exception:
            pass

        # Debug helper: when hovering a processing cell, log a concise state line once per change
        try:
            txt = item.text() if item is not None and hasattr(item, 'text') else ''
            debug_key = (row, col, txt, preview, preview_status, getattr(self.app, 'current_processing_file', None))
            if txt and 'processing' in txt.lower():
                if debug_key != self._last_hover_debug:
                    try:
                        roles = None
                        try:
                            roles = (item.data(_QtRoles.UserRole + 1), item.data(_QtRoles.UserRole + 2), item.data(_QtRoles.UserRole + 4))
                        except Exception:
                            roles = None
                        if TRACELEVEL >= 1:
                            print(f"Hover debug row={row} col={col} text={txt!r} roles={roles!r} preview_var={preview!r} status_var={preview_status!r} app.current_processing_file={getattr(self.app, 'current_processing_file', None)!r}", flush=True)
                    except Exception:
                        pass
                    try:
                        self._last_hover_debug = debug_key
                    except Exception:
                        self._last_hover_debug = None
        except Exception:
            pass

        if preview_status == 'missing':
            if self._image_tooltip is None:
                self._image_tooltip = ImageTooltip(self)
            self._image_tooltip.show_at(text="Error", global_pos=QCursor.pos())
        elif preview_status == 'found' and preview:
            # create tooltip widget if needed
            if self._image_tooltip is None:
                self._image_tooltip = ImageTooltip(self)
            pix = None
            # use cached pixmap if available
            try:
                if preview in self._preview_pixmap_cache:
                    pix = self._preview_pixmap_cache.get(preview)
                else:
                    # attempt to load image via PIL
                    try:
                        from PIL import Image
                        im = Image.open(preview)
                        pix = pil2pixmap(im)
                    except Exception:
                        pix = None
                    # try video frame if no image
                    if pix is None:
                        try:
                            import cv2
                            cap = cv2.VideoCapture(preview)
                            ret, frame = cap.read()
                            cap.release()
                            if ret:
                                frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                                h, w, ch = frame.shape
                                from PyQt5.QtGui import QImage
                                img = QImage(frame.data, w, h, 3 * w, QImage.Format_RGB888)
                                pix = QPixmap.fromImage(img)
                        except Exception:
                            pix = None

                    # ffmpeg fallback: extract first frame to a temp PNG and load it
                    if pix is None:
                        try:
                            # Resolve ffmpeg binary using configuration FFMPEGPATHPREFIX (same semantics as shell scripts)
                            ffmpeg_bin = None
                            try:
                                ffmpeg_prefix = config('FFMPEGPATHPREFIX', '') or ''
                            except Exception:
                                ffmpeg_prefix = ''

                            # If a prefix is configured, try to resolve it. Shell scripts set FFMPEGPATHPREFIX
                            # to either an absolute path or a path fragment; handle both.
                            if ffmpeg_prefix:
                                fp = ffmpeg_prefix.strip()
                                # If fp looks like an executable path, try it directly
                                if os.path.exists(fp) and os.access(fp, os.X_OK):
                                    ffmpeg_bin = fp
                                else:
                                    # Try interpreting fp as a folder containing ffmpeg
                                    candidate = fp
                                    if os.path.isdir(candidate):
                                        exe_name = 'ffmpeg.exe' if os.name == 'nt' else 'ffmpeg'
                                        candidate2 = os.path.join(candidate, exe_name)
                                        if os.path.exists(candidate2) and os.access(candidate2, os.X_OK):
                                            ffmpeg_bin = candidate2
                                    # Try resolving relative to repo root (like installer does)
                                    if ffmpeg_bin is None:
                                        try:
                                            abs_candidate = os.path.abspath(os.path.join(path, '../../../../', fp))
                                            if os.path.isdir(abs_candidate):
                                                exe_name = 'ffmpeg.exe' if os.name == 'nt' else 'ffmpeg'
                                                candidate3 = os.path.join(abs_candidate, exe_name)
                                                if os.path.exists(candidate3) and os.access(candidate3, os.X_OK):
                                                    ffmpeg_bin = candidate3
                                        except Exception:
                                            pass

                            # Fallback to PATH lookup if not resolved by config
                            if not ffmpeg_bin:
                                ffmpeg_bin = shutil.which('ffmpeg')
                            if ffmpeg_bin:
                                # create temp file in system temp dir
                                fd, tmp_path = tempfile.mkstemp(suffix='.png')
                                try:
                                    os.close(fd)
                                except Exception:
                                    pass
                                try:
                                    # extract first frame, scale small to limit size
                                    cmd = [ffmpeg_bin, '-y', '-i', preview, '-vframes', '1', '-vf', 'scale=320:-1', tmp_path]
                                    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8)
                                    if proc.returncode == 0 and os.path.exists(tmp_path):
                                        try:
                                            from PIL import Image
                                            im = Image.open(tmp_path)
                                            pix = pil2pixmap(im)
                                        except Exception:
                                            pix = None
                                except Exception:
                                    pix = None
                                finally:
                                    # remove temp file immediately
                                    try:
                                        if os.path.exists(tmp_path):
                                            os.remove(tmp_path)
                                    except Exception:
                                        pass
                        except Exception:
                            pix = None

                    # cache result (even if None to avoid repeated attempts)
                    try:
                        self._preview_pixmap_cache[preview] = pix
                    except Exception:
                        pass

                if pix is not None:
                    self._image_tooltip.show_at(pix, QCursor.pos(), max_size=(160, 160))
                else:
                    try:
                        print(f"Error loading preview for {preview}", flush=True)
                    except Exception:
                        pass
                    self._image_tooltip.show_at(text="Error", global_pos=QCursor.pos())
            except Exception:
                try:
                    print(traceback.format_exc(), flush=True)
                except Exception:
                    pass
                if self._image_tooltip is None:
                    self._image_tooltip = ImageTooltip(self)
                self._image_tooltip.show_at(text="Error", global_pos=QCursor.pos())

        # existing underline behavior for clickable cells; also set whole-row bold
        if self.isCellClickable(row, col):
            """Setzt den Text der Zelle auf unterstrichen und macht die Zeile fett."""
            if item:
                font = item.font()
                font.setUnderline(True)
                item.setFont(font)
            # determine stage index for this table row and bold entire row
            try:
                if row > 0 and row-1 < len(ROW2STAGE):
                    stage_idx = ROW2STAGE[row-1]
                else:
                    stage_idx = None
            except Exception:
                stage_idx = None
            # if a different stage was previously marked bold, clear it first
            try:
                prev = getattr(self, '_clickable_bold_stage', None)
                if prev is not None and prev != stage_idx:
                    if prev in ROW2STAGE:
                        pos = ROW2STAGE.index(prev)
                        prev_table_row = pos + 1
                        # Restore the default font and foreground for all columns
                        try:
                            defaults = getattr(self.app.table, '_row_default_formats', {}) or {}
                            row_defaults = defaults.get(prev, None)
                        except Exception:
                            row_defaults = None
                        for cc in range(self.columnCount()):
                            try:
                                it = self.item(prev_table_row, cc)
                                if it:
                                    if row_defaults and cc in row_defaults:
                                        fcopy, fgname = row_defaults.get(cc, (None, None))
                                        try:
                                            if fcopy is not None:
                                                it.setFont(QFont(fcopy))
                                        except Exception:
                                            pass
                                        try:
                                            if fgname:
                                                it.setForeground(QBrush(QColor(fgname)))
                                        except Exception:
                                            pass
                                    else:
                                        # best-effort: remove underline and leave color as-is
                                        try:
                                            f = it.font()
                                            f.setUnderline(False)
                                            it.setFont(f)
                                        except Exception:
                                            pass
                            except Exception:
                                pass
                    try:
                        self._clickable_bold_stage = None
                    except Exception:
                        self._clickable_bold_stage = None
                # apply bold for current stage
                if stage_idx is not None:
                    if stage_idx in ROW2STAGE:
                        pos = ROW2STAGE.index(stage_idx)
                        table_row = pos + 1
                        for cc in range(self.columnCount()):
                            try:
                                it = self.item(table_row, cc)
                                if it:
                                    f = it.font()
                                    f.setUnderline(True)
                                    it.setFont(f)
                            except Exception:
                                pass
                        self._clickable_bold_stage = stage_idx
            except Exception:
                pass
        else:
            # Only show 'processing...' when there is no usable preview to display.
            try:
                has_preview = (preview_status == 'found' and preview)
            except Exception:
                has_preview = False
            if not has_preview:
                try:
                    if item is not None and isinstance(item.text, type(lambda:None)) is False:
                        txt = item.text() if item else ""
                        if txt and 'processing' in txt.lower():
                            if self._image_tooltip is None:
                                self._image_tooltip = ImageTooltip(self)
                            self._image_tooltip.show_at(text="processing...", global_pos=QCursor.pos())
                except Exception:
                    pass

    def reset_hover_style(self):
        if self.current_hover:
            row, col = self.current_hover
            # Entfernt die Unterstreichung von der aktuell gehighlighteten Zelle
            item = self.item(row, col)
            if item:
                try:
                    font = item.font()
                    font.setUnderline(False)
                    item.setFont(font)
                except Exception:
                    pass
            # Tooltip IMMER ausblenden, wenn die Maus die Zelle verlässt
            try:
                if self._image_tooltip is not None:
                    self._image_tooltip.hide()
            except Exception:
                pass
            # clear any bold marking for clickable row when hover leaves
            try:
                prev = getattr(self, '_clickable_bold_stage', None)
                if prev is not None:
                    if prev in ROW2STAGE:
                        pos = ROW2STAGE.index(prev)
                        table_row = pos + 1
                        for cc in range(self.columnCount()):
                            try:
                                it = self.item(table_row, cc)
                                if it:
                                    f = it.font()
                                    f.setUnderline(False)
                                    it.setFont(f)
                            except Exception:
                                pass
                    try:
                        self._clickable_bold_stage = None
                    except Exception:
                        self._clickable_bold_stage = None
            except Exception:
                pass

    def on_cell_clicked(self, row, col):
        # Deduplicate against immediate press-dispatch fallback
        try:
            if self._last_press_handled is not None:
                prow, pcol, pts = self._last_press_handled
                if prow == row and pcol == col and (time.monotonic() - float(pts)) < 0.7:
                    self._last_press_handled = None
                    if TRACELEVEL >= 1:
                        print(f"[CLICK] release-ignored row={row} col={col} reason='already handled on press'", flush=True)
                    return
        except Exception:
            pass

        if self.isCellClickable(row, col):
            """Wird aufgerufen, wenn auf eine Zelle geklickt wird."""
            self.onCellClick(row, col)

    def on_item_changed(self, item):
        """
        Wird aufgerufen, wenn eine Zelle aktualisiert wurde.
        Wenn die aktuell gehighlightete Zelle geändert wird,
        erneuern wir den Unterstreichungsstil.
        """
        # avoid recursion during drag tinting
        if getattr(self, '_suppress_item_changed', False):
            return
        if self.current_hover:
            current_row, current_col = self.current_hover
            if item.row() == current_row and item.column() == current_col:
                self.apply_hover_style(current_row, current_col)


class ClickableLabel(QLabel):
    def __init__(self, url, parent=None):
        super().__init__(parent)
        try:
            self.url = url
            self.setMouseTracking(True)
            self.closeCursor=QCursor(Qt.PointingHandCursor)
            self.linkCursor=QCursor(Qt.WhatsThisCursor)
        except Exception:
            print(traceback.format_exc())

    def paintEvent(self, event):
        super().paintEvent(event)
        
        pm=self.pixmap()
        if not pm is None:
            gl=self.geometry()
            gp=pm.rect()
            x0=int((gl.width()-gp.width())/2)
            y0=int((gl.height()-gp.height())/2)
            w=gp.width()
            h=gp.height()
            qp = QPainter(self)
            qp.setPen(QColor(Qt.white))
            qp.fillRect(x0+w-16, y0, 16, 16, QColor("black") )
            qp.drawRect(x0+w-16, y0, 16, 16)
            qp.drawLine(x0+w-16, y0+16-1, x0+w-1, y0)
            qp.drawLine(x0+w-16, y0, x0+w-1, y0+16-1)
            #qp.setFont(QFont('Arial', 20))
            #qp.drawText(40, 40, "X")
            qp.end()        
        

    def mousePressEvent(self, event):
        pm=self.pixmap()
        if not pm is None:
            x = event.pos().x()
            y = event.pos().y()
            gl=self.geometry()
            gp=pm.rect()
            x0=int((gl.width()-gp.width())/2)
            y0=int((gl.height()-gp.height())/2)
            w=gp.width()
            h=gp.height()
            closeRect=QRect(x0+w-16, y0, 16, 16)
            if event.button() == Qt.LeftButton:
                if closeRect.contains(x, y, True):
                    global idletime
                    idletime=0
                else:
                    webbrowser.open(self.url)
            #self.update()

    def mouseMoveEvent(self, event):
        self.end = event.pos()
        #self.update()

        pm=self.pixmap()
        if not pm is None:
            x = event.pos().x()
            y = event.pos().y()
            gl=self.geometry()
            gp=pm.rect()
            x0=int((gl.width()-gp.width())/2)
            y0=int((gl.height()-gp.height())/2)
            w=gp.width()
            h=gp.height()
            closeRect=QRect(x0+w-16, y0, 16, 16)
            if closeRect.contains(x, y, True):
                self.setCursor(self.closeCursor)  
            else:
                self.setCursor(self.linkCursor)  


if __name__ == "__main__":
    errorfile=os.path.join(path, "../../../../user/default/comfyui_stereoscopic/.guierror")
    try:
        if len(sys.argv) != 1:
           print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " ")
        elif os.path.exists(os.path.join(path, "../../../../user/default/comfyui_stereoscopic/.daemonactive")):
            app = None
            try:
                initCutMode()
                scanFilesToRate()
                
                global window, cb
                app = QApplication(sys.argv)
                
                window = SpreadsheetApp()
                window.show()
            except:
                print(traceback.format_exc(), flush=True)
            if not app is None:
                sys.exit(app.exec_())
        else:
            #print("no lock.", os.path.join(path, "../../../../user/default/comfyui_stereoscopic/.daemonactive"))
            print("\033[91mError:\033[0m The 'VR we are' service daemon is not active.", flush=True)
            with open(errorfile, 'w'): pass
            time.sleep(10)
    except KeyboardInterrupt:
        if app is None:
            sys.exit(0)
        else:
            sys.exit(app.exec_())
    except Exception as e:
        with open(errorfile, 'w') as f:
            print(traceback.format_exc(), flush=True, file=f)
        print(e, traceback.format_exc(), flush=True)
