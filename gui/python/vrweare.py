import os
import re
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

import faulthandler
faulthandler.enable()

path = os.path.dirname(os.path.abspath(__file__))

# Add the current directory to the path so we can import local modules
if path not in sys.path:
    sys.path.append(path)

# Import our implementations
from rating import RateAndCutDialog, StyledIcon, pil2pixmap, getFilesWithoutEdit, getFilesOnlyEdit, getFilesOnlyReady, rescanFilesToRate, scanFilesToRate, initCutMode, config, VIDEO_EXTENSIONS, IMAGE_EXTENSIONS
from judge import JudgeDialog


LOGOTIME = 3000
BREAKFREQ = 1200000
TABLEUPDATEFREQ = 1000
TOOLBARUPDATEFREQ = 1000
BREAKTIME = 20000
FILESCANTIME = 2000

status="idle"
idletime = 0

COLS = 4

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
        with open(file_path, "r", encoding="utf-8") as f:
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

    with open(file_path, "r", encoding="utf-8") as f:
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
        with open(defFile, "r", encoding="utf-8", errors="ignore") as f:
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

    # normalize input types
    if isinstance(input_type, str):
        types = [t.strip().lower() for t in input_type.split(';') if t.strip()]
    else:
        types = [str(input_type).strip().lower()]

    try:
        # Use requests with a browser-like UA to improve compatibility
        resp = requests.get(url, stream=True, timeout=6, headers={"User-Agent": "Mozilla/5.0"})
        # don't read body; headers are available
        content_type = resp.headers.get('Content-Type', '')
    except Exception:
        return False

    if not content_type:
        return False

    for t in types:
        if t == 'image' and content_type.startswith('image/'):
            return True
        if t == 'video' and content_type.startswith('video/'):
            return True
        if t in ('file', 'any'):
            return True

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

    # If extension absent or unknown, report False to avoid network probes during drag
    return False

class SpreadsheetApp(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("VR we are - Status")
        self.setStyleSheet("background-color: black;")
        self.setWindowIcon(QIcon(os.path.join(path, '../../gui/img/icon.png')))
        self.setGeometry(100, 100, 640, 600)
        self.move(60, 15)

        # Flags for toggles
        self.toogle_stages_expanded = False
        self.toogle_pipeline_active = not os.path.exists(pipelinePauseLockPath)
        self.toogle_pipeline_isForwarding = config("PIPELINE_AUTOFORWARD", "0") == "1"

        # Initialize caches
        self.stageTypes = []

        self.pipelinedialog=None
        self.dialog=None
        
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
            
    def show_manual(self, state):
        webbrowser.open('file://' + os.path.realpath(os.path.join(path, "../../docs/VR_We_Are_User_Manual.pdf")))
        # webbrowser.open("https://github.com/FortunaCournot/comfyui_stereoscopic/blob/main/docs/VR_We_Are_User_Manual.pdf")

    def check_cutandclone(self, state):
        dialog = RateAndCutDialog(True)
        self.dialog = dialog
        dialog.show()

    def check_rate(self, state):
        dialog = RateAndCutDialog(False)
        self.dialog = dialog
        dialog.show()

    def check_judge(self, state):
        dialog = JudgeDialog()
        self.dialog = dialog
        dialog.show()

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

            pipeline_status = not os.path.exists(pipelinePauseLockPath)
            self.toogle_pipeline_active = pipeline_status
            self.toggle_pipeline_active_action.setChecked(self.toogle_pipeline_active)
            self.update_comfyui_count()

            self.toogle_pipeline_isForwarding = config("PIPELINE_AUTOFORWARD", "0") == "1"
            self.toggle_pipeline_forwarding_action.setChecked(self.toogle_pipeline_isForwarding)
            if self.toogle_pipeline_isForwarding:
                self.toggle_pipeline_forwarding_action.setIcon(self.toggle_pipeline_forwarding_icon_true)
            else:
                self.toggle_pipeline_forwarding_action.setIcon(self.toggle_pipeline_forwarding_icon_false)
                
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
            self.setWindowTitle("VR we are - " + activestage + ": " + status)
            # Wenn ein Doppelpunkt in status vorkommt, alles ab diesem Zeichen entfernen
            if ':' in status:
                status = status.split(':', 1)[0]

            fontC0 = QFont()
            fontC0.setBold(True)
            fontC0.setItalic(True)

            fontR0 = QFont()
            fontR0.setBold(True)
            fontR0.setItalic(True)

            COLNAMES = []
            if self.toogle_stages_expanded:
                COLS=6
                self.table.setColumnCount(COLS)
                header = self.table.horizontalHeader()    
                header.setSectionResizeMode(QHeaderView.Fixed);
                COLNAMES.clear()
                COL_IDX_STAGENAME=0        
                header.setSectionResizeMode(COL_IDX_STAGENAME, QHeaderView.ResizeToContents)
                COLNAMES.append("")
                self.COL_IDX_IN_TYPES=1
                header.setSectionResizeMode(self.COL_IDX_IN_TYPES, QHeaderView.ResizeToContents)
                COLNAMES.append("type")
                self.COL_IDX_IN=2
                #header.setSectionResizeMode(self.COL_IDX_IN, QHeaderView.ResizeToContents)
                COLNAMES.append("input (done)")
                COL_IDX_PROCESSING=3
                #header.setSectionResizeMode(COL_IDX_PROCESSING, QHeaderView.ResizeToContents)
                COLNAMES.append("processing")
                self.COL_IDX_OUT=4
                header.setSectionResizeMode(self.COL_IDX_OUT, QHeaderView.Stretch)
                COLNAMES.append("output")
                header.setSectionResizeMode(self.COL_IDX_OUT+1, QHeaderView.Fixed)
                COLNAMES.append("Config")
            else:
                COLS=4
                self.table.setColumnCount(COLS)
                header = self.table.horizontalHeader()       
                COLNAMES.clear()
                COL_IDX_STAGENAME=0        
                header.setSectionResizeMode(COL_IDX_STAGENAME, QHeaderView.ResizeToContents)
                COLNAMES.append("")
                self.COL_IDX_IN=1
                #header.setSectionResizeMode(self.COL_IDX_IN, QHeaderView.ResizeToContents)
                COLNAMES.append("input (done)")
                COL_IDX_PROCESSING=2
                #header.setSectionResizeMode(COL_IDX_PROCESSING, QHeaderView.ResizeToContents)
                COLNAMES.append("processing")
                self.COL_IDX_OUT=3
                header.setSectionResizeMode(self.COL_IDX_OUT, QHeaderView.Stretch)
                COLNAMES.append("output")
            
            skippedrows=0
            self.table.clear()
            ROW2STAGE.clear()
            for r in range(ROWS):
                displayRequired=False
                currentRowItems = []
                for c in range(COLS):
                    if c==COL_IDX_STAGENAME:
                        if r==0:
                            displayRequired=True
                            value = ""
                        else:
                            value = STAGES[r-1]
                        item = QTableWidgetItem(value)
                        item.setFont(fontC0)
                        if value.startswith("tasks/_"):
                            item.setForeground(QBrush(QColor("#666666")))
                        elif value.startswith("tasks/"):
                            item.setForeground(QBrush(QColor("#888888")))
                        else:
                            item.setForeground(QBrush(QColor("#CCCCCC")))
                        item.setBackground(QBrush(QColor("black")))
                        item.setTextAlignment(Qt.AlignLeft + Qt.AlignVCenter)
                    else:
                        color = "lightgray"
                        if r==0:
                            displayRequired=True
                            value = COLNAMES[c]
                            color = "gray"
                        else:
                            if c==self.COL_IDX_IN:
                                folder =  os.path.join(path, "../../../../input/vr/" + STAGES[r-1])
                                if os.path.exists(folder):
                                    onlyfiles = next(os.walk(folder))[2]
                                    onlyfiles = [f for f in onlyfiles if not f.lower().endswith(".txt")]
                                    count = len(onlyfiles)
                                    if count>0:
                                        value = str(count)
                                        displayRequired=True
                                    else:
                                        value = ""
                                    subfolder =  os.path.join(path, "../../../../input/vr/" + STAGES[r-1] + "/done")
                                    if os.path.exists(subfolder):
                                        onlyfiles = next(os.walk(subfolder))[2]
                                        nocleanup = False
                                        for f in onlyfiles:
                                            if ".nocleanup" == f.lower():
                                                nocleanup = True                                            
                                        if nocleanup:
                                            displayRequired=True
                                            onlyfiles = [f for f in onlyfiles if f.lower() != ".nocleanup"]
                                            count2 = len(onlyfiles)
                                            if count2>0:
                                                value = value + " (" + str(count2) + ")"
                                                color = "green"
                                            elif count == 0:
                                                value = value + " (-)"
                                        else:
                                            color = "yellow"
                                    subfolder =  os.path.join(path, "../../../../input/vr/" + STAGES[r-1] + "/error")
                                    if os.path.exists(subfolder):
                                        try:
                                            onlyfiles = next(os.walk(subfolder))[2]
                                            count = len(onlyfiles)
                                            if count>0:
                                                value = value + " " + str(count) + "!"
                                                color = "red"
                                                displayRequired=True
                                        except StopIteration as se:
                                            pass
                                else:
                                    value = "?"
                                    color = "red"
                                    displayRequired=True
                            elif c==self.COL_IDX_OUT:
                                folder =  os.path.join(path, "../../../../output/vr/" + STAGES[r-1])
                                if os.path.exists(folder):
                                    onlyfiles = next(os.walk(folder))[2]
                                    forward = False
                                    for f in onlyfiles:
                                        if "forward.txt" == f.lower():
                                            forward = True
                                    if not forward:
                                        color = "green"
                                    onlyfiles = [f for f in onlyfiles if not f.lower().endswith(".txt")]
                                    count = len(onlyfiles)
                                    if count>0:
                                        displayRequired=True
                                        value = str(count)
                                        if idletime>15:
                                            color = "green"
                                    else:
                                        value = ""
                                    if forward:
                                        value = value + " ➤"
                                else:
                                    value = "?"
                                    color = "red"
                                    displayRequired=True
                            elif c==COL_IDX_PROCESSING:
                                value = ""
                                if status!="idle":
                                    if activestage==STAGES[r-1]:
                                        value=status
                                        color="yellow"
                                        displayRequired=True
                            elif self.toogle_stages_expanded:
                                if c==self.COL_IDX_IN_TYPES:
                                    if len(self.stageTypes)+1==ROWS:  # use cache
                                        value = self.stageTypes[r-1]
                                        color = "#5E271F" # need also to set below
                                        if value == "video":
                                            color = "#04018C"   # need also to set below
                                        elif value == "image":
                                            color = "#018C08"   # need also to set below
                                        elif value == "?":
                                            displayRequired=True
                                            color = "red"
                                    else:   # build and store in cache
                                        if re.match(r"tasks/_.*", STAGES[r-1]):
                                            stageDefRes="user/default/comfyui_stereoscopic/tasks/" + STAGES[r-1][7:] + ".json"
                                        elif re.match(r"tasks/.*", STAGES[r-1]):
                                            stageDefRes="custom_nodes/comfyui_stereoscopic/config/tasks/" + STAGES[r-1][6:] + ".json"
                                        else:
                                            stageDefRes="custom_nodes/comfyui_stereoscopic/config/stages/" + STAGES[r-1] + ".json"

                                        value = "?"
                                        defFile = os.path.join(path, "../../../../" + stageDefRes)
                                        if os.path.exists(defFile):
                                            with open(defFile) as file:
                                                color = "#5E271F" # need also to set above at cache
                                                deflines = [line.rstrip() for line in file]
                                                for line in range(len(deflines)):
                                                    inputMatch=re.match(r".*\"input\":", deflines[line])
                                                    if inputMatch:
                                                        valuepart=deflines[line][inputMatch.end():]
                                                        match = re.search(r"\".*\"", valuepart)
                                                        if match:
                                                            value = valuepart[match.start()+1:match.end()][:-1]
                                                            if value == "video":
                                                                color = "#04018C"   # need also to set above at cache
                                                            elif value == "image":
                                                                color = "#018C08"   # need also to set above at cache
                                                        else:
                                                            value = "?"
                                        self.stageTypes.append(value)
                                        if value == "?":
                                            displayRequired=True
                                            color = "red"
                                elif c==self.COL_IDX_OUT+1:
                                    if re.match(r"tasks/.*", STAGES[r-1]):
                                        value = "⚙"
                                    else:
                                        value = ""
                                    color = "lightgray"
                                else:
                                    value = "?"
                                    color = "red"
                                    displayRequired=True
                            else:
                                value = "?"
                                color = "red"
                                displayRequired=True
                        if value=="":
                            value="  "
                        item = QTableWidgetItem(value)
                        if r==0:
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
                        
                    currentRowItems.append(item)
                    
                if displayRequired or self.toogle_stages_expanded:
                    for c in range(len(currentRowItems)):
                        self.table.setItem(r-skippedrows, c, currentRowItems[c])
                        if r>0 and c==0:
                            ROW2STAGE.append(r-1)
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
            if col == self.COL_IDX_OUT+1:
                return True
        return False

    def onCellClick(self, row, col):
        try:
            idx = ROW2STAGE[row-1]
            # "/select,",  
            if col == self.COL_IDX_IN:
                folder =  os.path.abspath( os.path.join(path, "../../../../input/vr/" + STAGES[idx]) )
                os.system("start \"\" " + folder)
                # subprocess.Popen(["explorer", folder ], close_fds=True) - does not close properly

            if col == self.COL_IDX_OUT:
                folder =  os.path.abspath( os.path.join(path, "../../../../output/vr/" + STAGES[idx]) )
                os.system("start \"\" " + folder)
                # subprocess.Popen(["explorer", folder ], close_fds=True) - does not close properly

            if col == self.COL_IDX_OUT+1:
                if re.match(r"tasks/_.*", STAGES[idx]):
                    stageDefRes="user/default/comfyui_stereoscopic/tasks/" + STAGES[idx][7:] + ".json"
                elif re.match(r"tasks/.*", STAGES[idx]):
                    stageDefRes="custom_nodes/comfyui_stereoscopic/config/tasks/" + STAGES[idx][6:] + ".json"
                else:
                    stageDefRes=""
                defFile = os.path.join(path, "../../../../" + stageDefRes)
                if os.path.exists(defFile):
                    os.startfile(defFile)

        except Exception as e:
            print(f"Error on cell click: row={row}, col={col}", flush=True)
            print(e, traceback.format_exc(), flush=True)
            pass
        

   
    def closeEvent(self,event):
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
        editAction.setCheckable(False)
        editAction.triggered.connect(self.edit_pipeline)
        pipeline_toolbar.addAction(editAction)
        pipeline_toolbar.widgetForAction(editAction).setCursor(Qt.PointingHandCursor)

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
        pipelinedialog.show()
        self.button_show_pipeline_action.setEnabled(True)
    def edit_pipeline(self, state):
        configFile=os.path.join(path, r'..\..\..\..\user\default\comfyui_stereoscopic\autoforward.yaml')
        global editActive, pipelineModified, editthread
        pipelineModified=False
        editActive=True
        editAction.setEnabled(False)
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

    def dragEnterEvent(self, event):
        md = event.mimeData()
        if md.hasUrls() or md.hasFormat('application/x-qt-windows-mime;value="UniformResourceLocatorW"'):
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

    def dragMoveEvent(self, event):
        # Only accept if over a stage-name cell (column 0) and row>0
        index = self.indexAt(event.pos())
        if not index.isValid():
            event.ignore()
            return
        row, col = index.row(), index.column()
        if row <= 0 or col != 0:
            event.ignore()
            return

        md = event.mimeData()
        qurls = md.urls()
        local_paths = [u.toLocalFile() for u in qurls if u.isLocalFile()]
        remote_urls = [u.toString() for u in qurls if not u.isLocalFile()]

        # Handle Windows URL clipboard flavor
        url_from_clip = None
        if md.hasFormat('application/x-qt-windows-mime;value="UniformResourceLocatorW"'):
            try:
                data = md.data('application/x-qt-windows-mime;value="UniformResourceLocatorW"')
                url_from_clip = bytes(data).decode('utf-16', errors='ignore').strip('\x00').strip()
            except Exception:
                url_from_clip = None

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

        # use cached allowed map computed at drag start when available
        all_ok = True
        if isinstance(self._drag_allowed_map, list):
            # map is a list keyed by stage index (value from ROW2STAGE)
            try:
                table_stage_idx = ROW2STAGE[row-1]
            except Exception:
                table_stage_idx = None
            if table_stage_idx is not None and 0 <= table_stage_idx < len(self._drag_allowed_map):
                all_ok = bool(self._drag_allowed_map[table_stage_idx])
        else:
            # fallback: compute on the fly (previous behavior)
            input_type = get_stage_input_type(stage_name)
            all_ok = True
            for p in local_paths:
                if not _is_allowed_for_type(p, input_type):
                    all_ok = False
                    break
            if all_ok:
                for u in remote_urls:
                    if not _is_url_allowed_for_type_quick(u, input_type):
                        all_ok = False
                        break
            if all_ok and url_from_clip:
                if not _is_url_allowed_for_type_quick(url_from_clip, input_type):
                    all_ok = False

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
                    if isinstance(prev, int) and 0 <= prev < len(self._drag_hover_saved) and self._drag_hover_saved[prev] is not None:
                        # find table row for prev
                        try:
                            if prev in ROW2STAGE:
                                pos = ROW2STAGE.index(prev)
                                prev_row = pos + 1
                                prev_item = self.item(prev_row, col)
                                orig = self._drag_hover_saved[prev]
                                self._drag_hover_saved[prev] = None
                                # restore the pre-hover color (may be brown or original)
                                if prev_item and orig:
                                    prev_item.setForeground(QBrush(QColor(orig)))
                        except Exception:
                            # best-effort
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
            self._drag_forced_colors = forced_list
            item.setForeground(QBrush(forced))
            self._current_drag_stage = table_stage_idx

        if all_ok:
            event.acceptProposedAction()
        else:
            event.ignore()

    def dropEvent(self, event):
        index = self.indexAt(event.pos())
        if not index.isValid():
            event.ignore()
            return
        row, col = index.row(), index.column()
        if row <= 0 or col != 0:
            event.ignore()
            return

        md = event.mimeData()
        qurls = md.urls()
        local_paths = [u.toLocalFile() for u in qurls if u.isLocalFile()]
        remote_urls = [u.toString() for u in qurls if not u.isLocalFile()]
        url_from_clip = None
        if md.hasFormat('application/x-qt-windows-mime;value="UniformResourceLocatorW"'):
            try:
                data = md.data('application/x-qt-windows-mime;value="UniformResourceLocatorW"')
                url_from_clip = bytes(data).decode('utf-16', errors='ignore').strip('\x00').strip()
            except Exception:
                url_from_clip = None

        try:
            idx = ROW2STAGE[row-1]
            stage_name = STAGES[idx]
        except Exception:
            event.ignore()
            return

        input_type = get_stage_input_type(stage_name)

        # validate local files
        for p in local_paths:
            if not _is_allowed_for_type(p, input_type):
                event.ignore()
                return

        # validate remote urls
        for u in remote_urls:
            if not _is_url_allowed_for_type(u, input_type):
                event.ignore()
                return

        if url_from_clip:
            if not _is_url_allowed_for_type(url_from_clip, input_type):
                event.ignore()
                return

        dest_folder = os.path.abspath(os.path.join(path, "../../../../input/vr/" + stage_name))
        os.makedirs(dest_folder, exist_ok=True)

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
                parsed = urllib.parse.urlparse(u)
                fname = os.path.basename(parsed.path) or f"download_{int(time.time())}"
                dest = os.path.join(dest_folder, fname)
                try:
                    r = requests.get(u, stream=True, timeout=20, headers={"User-Agent": "Mozilla/5.0"})
                    r.raise_for_status()
                    with open(dest, 'wb') as fh:
                        for chunk in r.iter_content(8192):
                            if chunk:
                                fh.write(chunk)
                except Exception:
                    event.ignore()
                    return

            # download URL from clipboard flavor
            if url_from_clip:
                parsed = urllib.parse.urlparse(url_from_clip)
                fname = os.path.basename(parsed.path) or f"download_{int(time.time())}"
                dest = os.path.join(dest_folder, fname)
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
                        event.ignore()
                        return

        except Exception:
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
        event.acceptProposedAction()

    def dragLeaveEvent(self, event):
        """Called when an ongoing drag operation leaves the widget without dropping.

        Restore any forced colors keyed by stage name and clear drag state so
        a cancelled/aborted drag does not leave a lingering color.
        """
        self._reset_drag_state()
        try:
            super().dragLeaveEvent(event)
        except Exception:
            pass

    def _reset_drag_state(self):
        """Restore original foreground colors and clear drag state."""
        try:
            for stage_idx, orig in enumerate(self._drag_orig_colors):
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
        self._drag_orig_colors = [None] * len(STAGES)
        self._drag_forced_colors = [None] * len(STAGES)
        self._current_drag_stage = None
        # clear cached allowed map
        self._drag_allowed_map = None
        # also reset hover/underline state
        self.reset_hover_style()
        self.current_hover = None

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
        # If a drag was in progress but no drop occurred, ensure reset
        self._reset_drag_state()
        try:
            super().mouseReleaseEvent(event)
        except Exception:
            pass

    def apply_hover_style(self, row, col):
        if self.isCellClickable(row, col):
            """Setzt den Text der Zelle auf unterstrichen."""
            item = self.item(row, col)
            if item:
                font = item.font()
                font.setUnderline(True)
                item.setFont(font)

    def reset_hover_style(self):
        if self.current_hover:
            row, col = self.current_hover
            if self.isCellClickable(row, col):
                """Entfernt die Unterstreichung von der aktuell gehighlighteten Zelle."""
                item = self.item(row, col)
                if item:
                    font = item.font()
                    font.setUnderline(False)
                    item.setFont(font)

    def on_cell_clicked(self, row, col):
        if self.isCellClickable(row, col):
            """Wird aufgerufen, wenn auf eine Zelle geklickt wird."""
            self.onCellClick(row, col)

    def on_item_changed(self, item):
        """
        Wird aufgerufen, wenn eine Zelle aktualisiert wurde.
        Wenn die aktuell gehighlightete Zelle geändert wird,
        erneuern wir den Unterstreichungsstil.
        """
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
