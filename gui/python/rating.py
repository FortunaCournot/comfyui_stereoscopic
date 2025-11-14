import bisect
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
from datetime import timedelta
from functools import wraps, partial
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
                          QMimeData, QUrl, QEvent)
from PyQt5.QtGui import (QBrush, QColor, QCursor, QFont, QIcon, QImage,
                         QKeySequence, QPainter, QPaintEvent, QPen, QPixmap,
                         QTextCursor, QDrag)
from PyQt5.QtWidgets import (QAbstractItemView, QAction, QApplication,
                             QColorDialog, QComboBox, QDesktopWidget, QDialog,
                             QFileDialog, QFrame, QGridLayout, QGroupBox,
                             QHBoxLayout, QHeaderView, QLabel, QMainWindow,
                             QMessageBox, QPushButton, QShortcut, QSizePolicy,
                             QSlider, QStatusBar, QTableWidget,
                             QTableWidgetItem, QToolBar, QVBoxLayout, QWidget,
                             QPlainTextEdit, QLayout, QStyleOptionSlider, QStyle,
                             QRubberBand)



USE_TRASHBIN=True
if USE_TRASHBIN:
    try:
        import send2trash
    except ImportError:
        USE_TRASHBIN=False

TRACELEVEL=0

# Globale statische Liste der erlaubten Suffixe
VIDEO_EXTENSIONS = ['.mp4', '.webm', '.ts', '.flv']
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

# File Global
global videoActive, rememberThread, fileDragged, FILESCANTIME, TASKCHECKTIME, WAIT_DIALOG_THRESHOLD_TIME
videoActive=False
rememberThread=None
fileDragged=False
FILESCANTIME = 500
TASKCHECKTIME = 20
WAIT_DIALOG_THRESHOLD_TIME=2000
MAX_WAIT_DIALOG_THRESHOLD_TIME=10000

# ---- Tasks ----
global taskCounterUI, taskCounterAsync, showWaitDialog
taskCounterUI=0
taskCounterAsync=0
showWaitDialog=False

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


def isTaskActive():
    return taskCounterUI + taskCounterAsync > 0

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
            self.playtype_pingpong=False
            self.sliderinitdone=False
            self.filter_img = False
            self.filter_vid = False
            self.filter_edit = not self.cutMode
            self.loadingOk = True
            self.drag_file_path = None
            
            setFileFilter(self.filter_img, self.filter_vid, self.filter_edit)
            rescanFilesToRate()
            
            self.qt_img=None
            self.hasCropOrTrim=False
            self.isPaused = False
            self.currentFile = None
            self.currentIndex = -1
            
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

            self.iconCopyFilepathToClipboardAction = StyledIcon(os.path.join(path, '../../gui/img/clipboard64.png'))
            self.copyFilepathToClipboardAction = QAction(self.iconCopyFilepathToClipboardAction, "Copy file path")
            self.copyFilepathToClipboardAction.setCheckable(False)
            self.copyFilepathToClipboardAction.setVisible(True)
            self.copyFilepathToClipboardAction.triggered.connect(self.onCopyFilepathToClipboard)
            self.cutMode_toolbar.addAction(self.copyFilepathToClipboardAction)
            self.cutMode_toolbar.widgetForAction(self.copyFilepathToClipboardAction).setCursor(Qt.PointingHandCursor)

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
            self.cutMode_toolbar.addWidget(self.sortfiles_combo)
            self.sortfiles_combo.currentIndexChanged.connect(self.on_sortfiles_combobox_index_changed)

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
            self.button_delete_file.setIcon(StyledIcon(os.path.join(path, '../../gui/img/trash80.png')))
            self.button_delete_file.setIconSize(QSize(80,80))
            self.button_delete_file.setEnabled(True)
            self.button_delete_file.clicked.connect(self.deleteAndNext)
            self.button_delete_file.setFocusPolicy(Qt.ClickFocus)

            
            
            self.sl = FrameSlider(Qt.Horizontal)
            
            self.display = Display(cutMode, self.button_startpause_video, self.sl, self.updatePaused, self.onVideoLoaded, self.onRectSelected, self.onUpdate, self.playtype_pingpong, self.onBlackout)
            #self.display.resize(self.display_width, self.display_height)

            self.sp3 = QLabel(self)
            self.sp3.setFixedSize(48, 100)
            self.sp4 = QLabel(self)
            self.sp4.setFixedSize(8, 100)

            # Display layout
            self.display_layout = QHBoxLayout()
            self.display.registerForTrimUpdate(self.onCropOrTrim)
            if cutMode:
                self.cropWidget=CropWidget(self.display)
                self.display_layout.addWidget(self.cropWidget)
                self.cropWidget.registerForUpdate(self.onCropOrTrim)
            else:
                self.display.setMinimumSize(1000, 750)
                self.display_layout.addWidget(self.display)


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
        
        self.enable_drag_for_groupbox(self.main_group_box, )
        
    # ---------------------------------------------------------------------------------------------------------------------------


        
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
        elif md.hasFormat('application/x-qt-windows-mime;value="UniformResourceLocatorW"'):
            data = md.data('application/x-qt-windows-mime;value="UniformResourceLocatorW"')
            url = bytes(data).decode('utf-16', errors='ignore').strip('\x00').strip()
            
            try:
                with urllib.request.urlopen(url) as response:
                    content_type = response.headers.get("Content-Type", "")
                    if content_type.startswith("image/"):
                        pass
                    elif content_type.startswith("video/"):
                        pass
                    else:
                        self.drag_file_path = None 
                        self.style_group_box(self.main_group_box, "#ff0000")
                        self.reset_timer.start(2000)
                        event.ignore()
                        return
                
                self.drag_file_path=url
                self.style_group_box(self.main_group_box, "#44ff44")
                self.reset_timer.start(1000)
                event.acceptProposedAction()
                return
            except:
                self.drag_file_path = None 
                self.style_group_box(self.main_group_box, "#ff0000")
                self.reset_timer.start(2000)
                event.ignore()
                return                
                
        elif md.hasUrls() and len(md.urls())>0:
            # Standardweg (wenn funktioniert)
            self.drag_file_path = md.urls()[0].toLocalFile()
            #print("File (URI):", self.drag_file_path)
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
        

    def dropEvent(self, event):
        # Retrieve file paths
        if not self.drag_file_path is None:
            #print(f"File dropped:\n{self.drag_file_path}", flush=True)
            md = event.mimeData()
            if md.hasFormat("application/x-vrweare-drag"):
                event.ignore()
                return
            elif md.hasFormat('application/x-qt-windows-mime;value="UniformResourceLocatorW"'):
                try:
                    self.downloadAndSwithToimage(self.drag_file_path)
                except:
                    event.ignore()
                    print(traceback.format_exc(), flush=True) 
            elif os.path.isdir(self.drag_file_path):
                self.switchDirectory(self.drag_file_path, None, None)
            elif os.path.isfile(self.drag_file_path) and any(self.drag_file_path.lower().endswith(suf.lower()) for suf in ALL_EXTENSIONS):
                self.switchDirectory(os.path.dirname(self.drag_file_path), os.path.basename(self.drag_file_path), None)
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
        # Parse URL and derive a safe filename
        parsed = urllib.parse.urlparse(url)
        filename = os.path.basename(parsed.path)
        
        if not filename:
            raise ValueError("URL does not contain a valid filename")

        self.switchDirectory(None, filename, self.drag_file_path)
        
    
    def switchDirectory(self, dirpath, filename, url):
        global _cutModeFolderOverrideFiles, cutModeFolderOverrideActive, cutModeFolderOverridePath
        cutModeFolderOverrideActive= not dirpath is None
        thread = threading.Thread(
            target=self.switchDirectory_worker,
            args=( cutModeFolderOverrideActive, dirpath, filename, url),
            daemon=True
        )
        thread.start()

    def get_safe_unique_filename(self, directory: str, filename: str) -> str:
        """
        Generate a sanitized and unique filename within a given directory.
        
        Steps:
          1. Remove problematic shell/batch characters from filename.
          2. If a file with the same name already exists, append "_N" before the extension,
             where N is an increasing integer.
        
        Args:
            directory (str): Target directory path.
            filename (str): Original filename (may contain unsafe characters).
        
        Returns:
            str: A safe, unique filename (not a full path).
        """
        # Step 1: sanitize filename (remove unsafe characters)
        # Keep letters, digits, dot, underscore, hyphen, and space
        safe_name = re.sub(r'[^A-Za-z0-9._\- ]+', '_', filename)
        
        # Prevent hidden or empty names
        if not safe_name or safe_name.startswith('.'):
            safe_name = 'file'

        # Separate base and extension
        base, ext = os.path.splitext(safe_name)
        if not ext:
            ext = ""

        # Step 2: ensure uniqueness
        candidate = safe_name
        counter = 1
        while os.path.exists(os.path.join(directory, candidate)):
            candidate = f"{base}_{counter}{ext}"
            counter += 1

        return candidate
    
    def switchDirectory_worker(self, override, dirpath, filename, url):
        global _cutModeFolderOverrideFiles, cutModeFolderOverrideActive, cutModeFolderOverridePath
        startAsyncTask()
        try:
            if not url is None:
                # Download
                with urllib.request.urlopen(url) as response:
                    content_type = response.headers.get("Content-Type", "")
                    
                    # Optional: fallback extension if missing
                    if content_type.startswith("image/"):
                        if '.' not in filename:
                            filename += ".jpg"
                    elif content_type.startswith("video/"):
                        if '.' not in filename:
                            filename += ".mp4"
                    else:
                        raise ValueError(f"URL is not an image (Content-Type: {content_type})")
                
                    # Build full output path, ignore dirpath (assume None)
                    override=False
                    target_dir = os.path.join(path, "../../../../input/vr/check/rate")
                    #os.makedirs(target_dir, exist_ok=True)
                    filename = self.get_safe_unique_filename(target_dir, filename)
                    output_path = os.path.join(target_dir, filename)
                    
                    # Write to file
                    with open(output_path, "wb") as f:
                        block_size = 8192
                        while True:
                            chunk = response.read(block_size)
                            if not chunk:
                                break
                            f.write(chunk)
            

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

            QTimer.singleShot(0, partial(self.switchDirectory_updater, override, dirpath, filename))
        except:
            endAsyncTask()
            print(traceback.format_exc(), flush=True) 

    def switchDirectory_updater(self, override, dirpath, filename):

        global _cutModeFolderOverrideFiles, cutModeFolderOverrideActive, cutModeFolderOverridePath
        try:
            f=getFilesToRate()
            if len(f) > 0:
                self.currentIndex=0
                self.currentFile=f[self.currentIndex]
                if not filename is None:
                    try:
                        self.currentFile=filename
                        self.currentIndex=f.index(self.currentFile)+1
                    except ValueError as ve:
                        self.currentFile=f[self.currentIndex]
            else:
                self.currentFile=""
                self.currentIndex=-1
                
            self.rateCurrentFile()

        except:
            print(traceback.format_exc(), flush=True) 
        finally:
            self.folderAction.setChecked(override)
            self.folderAction.setEnabled(True)
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
        if event.key() == Qt.Key_S:
            if self.display.slider.isEnabled() and self.display.slider.isVisible():
                self.display.nextScene()
        elif event.key() == Qt.Key_P:
            if self.button_startpause_video.isEnabled() and self.button_startpause_video.isVisible():
                self.display.tooglePausePressed()
                
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
            elif event.key() == Qt.Key_PageUp:
                if self.display.slider.isEnabled() and self.display.slider.isVisible() and not self.display.slider.hasFocus():
                    if self.button_startpause_video.isEnabled() and self.button_startpause_video.isVisible() and not self.display.isPaused():
                        self.display.tooglePausePressed()
                    self.display.slider.setFocus()
            elif event.key() == Qt.Key_PageDown:
                if self.display.slider.isEnabled() and self.display.slider.isVisible() and not self.display.slider.hasFocus():
                    if self.button_startpause_video.isEnabled() and self.button_startpause_video.isVisible() and not self.display.isPaused():
                        self.display.tooglePausePressed()
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
        if self.cutMode:
            self.cropWidget.setSliderValuesToRect(rect)

    def onCropOrTrim(self):
        self.hasCropOrTrim=True
        if self.cutMode:
            self.button_cutandclone.setEnabled(True)
            self.button_snapshot_from_video.setEnabled(self.isPaused and self.isVideo)

    def update_filebuttons(self):
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
                        try:
                            if USE_TRASHBIN:
                                self.log("Trashing " + os.path.basename(input), QColor("white"))
                                send2trash.send2trash(input)
                            else:
                                self.log("Deleting " + os.path.basename(input), QColor("white"))
                                os.remove(input)
                        finally:
                            if os.path.exists(input):
                                self.logn(" failed", QColor("red"))
                            else:
                                self.logn(" done", QColor("green"))
                            
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
                if os.path.exists(file_path):
                    self.isVideo=self.display.showFile( file_path ) == "video"
                    self.button_startpause_video.setVisible(self.isVideo)
                    self.sl.setVisible(self.isVideo)
                    fileDragged=False
                    self.hasCropOrTrim=False
                else:
                    print("Error: File does not exist (rateCurrentFile): "  + file_path, flush=True)
                    self.isVideo = False
                    fileDragged=False
                    self.hasCropOrTrim=False
                    self.button_startpause_video.setVisible(False)
                    self.sl.setVisible(False)
                self.button_delete_file.setEnabled(True)
                    
            if self.currentIndex<0:
                self.fileSlider.setEnabled(False)
                self.main_group_box.setTitle( "" )
                self.isVideo = False
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
                self.button_trima_video.setEnabled(False)
                self.button_trimb_video.setEnabled(False)
                self.button_cutandclone.setEnabled(False)
                self.button_snapshot_from_video.setEnabled(False)
                self.button_justrate_compress.setEnabled(True)
                self.button_justrate_compress.setIcon(self.icon_justrate)
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
            self.folderAction.setChecked(override)
            self.folderAction.setEnabled(True)
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
            self.folderAction.setEnabled(True)
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
            cmd2 = "grep showinfo \"" + tmp.name + "\" | grep pts_time:[0-9.]* -o | grep [0-9.]* -o > " + out.name
            
            if TRACELEVEL >= 3:
                print("Executing", cmd1, flush=True)
            cp = subprocess.run(cmd1, shell=True, check=True, close_fds=True)
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
            print("move from", source, "to", destination, flush=True) 
            shutil.move(source, destination)
            countdown=5
            while os.path.exists(source):
                countdown=countdown-1
                if countdown<0:
                    break
                print("source file still exists. retry ...", flush=True)
                time.sleep(2)
                shutil.move(source, destination)
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
            return inputRelative[:inputRelative.rindex('.')] + "_" + str(fnum) + outputSuffix
        

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
                cmd = "ffmpeg.exe -hide_banner -y -i \"" + input + "\" -vf \""
                if self.isVideo:
                    cmd = cmd + "trim=start_frame=" + str(trimA) + ":end_frame=" + str(trimB) + ","
                cmd = cmd + "crop="+str(out_w)+":"+str(out_h)+":"+str(x)+":"+str(y)+"\" -shortest \"" + output + "\""
                print("Executing "  + cmd, flush=True)
                recreated=os.path.exists(output)
                thread = threading.Thread(
                    target=self.trimAndCrop_worker, args=(cmd, recreated, output, ), daemon=True)
                thread.start()
                
            except ValueError as e:
                pass
        except:
            print(traceback.format_exc(), flush=True)
        finally:
            leaveUITask()

            
    def trimAndCrop_worker(self, cmd, recreated, output):
        startAsyncTask()
        try:
            cp = subprocess.run(cmd, shell=True, check=True, close_fds=True)
            QTimer.singleShot(0, partial(self.trimAndCrop_updater, recreated, output, True))

        except subprocess.CalledProcessError as se:
            QTimer.singleShot(0, partial(self.trimAndCrop_updater, recreated, output, False))
        except:
            print(traceback.format_exc(), flush=True)                
            endAsyncTask()


    def trimAndCrop_updater(self, recreated, output, success):
        if success:
            self.log(" Overwritten" if recreated else " OK", QColor("green"))
            if self.display.frame_count<=0:
                cb = QApplication.clipboard()
                cb.clear(mode=cb.Clipboard)
                cb.setText(output, mode=cb.Clipboard)
                self.logn("+clipboard", QColor("gray"))
            else:
                self.logn("", QColor("gray"))
        else:
            self.logn(" Failed", QColor("red"))

        if self.cutMode:
            self.button_justrate_compress.setEnabled(True)        
            self.button_justrate_compress.setIcon(self.icon_compress)
            self.justRate=False
            self.button_justrate_compress.setFocus()

        endAsyncTask()


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
                
                rect = QRect(x, y, out_w, out_h)
                cropped_pixmap = self.cropWidget.original_pixmap.copy(rect)        
                success = cropped_pixmap.save(output)
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
            self.log(" Overwritten" if recreated else " OK", QColor("green"))
            cb = QApplication.clipboard()
            cb.clear(mode=cb.Clipboard)
            cb.setText(output, mode=cb.Clipboard)
            self.logn("+clipboard", QColor("gray"))
        else:
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
        self.pause = False
        self.update(self.pause)
        self.onVideoLoaded = onVideoLoaded
        self.currentFrame=-1
        self.frame_count=-1
        self.fps=1
        self._run_flag = False
        self.pingPongModeEnabled=pingpong
        self.pingPongReverseState=False
        self.seekRequest=-1
        self.busy=False
        #print("Created thread with uid " + str(uid) , flush=True)

    def run(self):
        enterUITask()
        
        global videoActive
        global rememberThread
        
        if not os.path.exists(self.filepath):
            print("Failed to open", self.filepath, flush=True)
            self.onVideoLoaded(-1, 1.0, 0.0)
            self.cap.release()
            leaveUITask()
            return
            
        self.cap = cv2.VideoCapture(self.filepath)
        if not self.cap.isOpened():
            print("Failed to open", self.filepath, flush=True)
            try:
                self.cap.release()
            except:
                pass
            self.cap=None
            self.onVideoLoaded(-1, 1.0, 0.0)
            leaveUITask()
            return

        self.frame_count = int(self.cap.get(cv2.CAP_PROP_FRAME_COUNT))
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

        self._run_flag = True
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
                if not self.pause:
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
                            if self.pause:
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
                                        self.cap.release()
                                        self.cap = cv2.VideoCapture(self.filepath)
                                        self.seek(self.a)
                elif self.seekRequest>=0:
                    self.idle=True
                    self.seek(self.seekRequest)
                    self.seekRequest=-1
                else:
                    self.idle=True
                
                elapsed = time.time()-timestamp
                sleeptime = max(0.02, 1.0/float(self.fps) - elapsed)
                time.sleep(sleeptime)
            
        except:
            print(traceback.format_exc(), flush=True)
        finally:
            self.cap.release()
            videoActive=False
            #print("Thread ends.", flush=True)
            #rememberThread=None
             

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
        while self.busy:
            pass
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
                self.slider.setValue(self.currentFrame)
            self.change_pixmap_signal.emit(cv_img, self.uid)
            #QTimer.singleShot(100, partial(self.seekUpdate, cv_img))
        else:
            self._run_flag = False

    #def seekUpdate(self, cv_img):
    #    self.change_pixmap_signal.emit(cv_img, self.uid)
        
    def setPingPongModeEnabled(self, state):
        self.pingPongModeEnabled=state
        self.pingPongReverseState=False

    def sliderChanged(self):
        if self.pause:  # do not call while playback
            #print("sliderChanged. seek", self.sender().value(), flush=True)
            self.seek(self.sender().value())
        self.sender().sliderChanged(self.sender().value())

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
        self.seek(self.a)
        
    def posB(self):
        if not self.pause:
            self.pause=True
            self.update(self.pause)
        if TRACELEVEL >= 1:
            print("posB", flush=True)
        self.seek(self.b)

    def setA(self, frame_number):
        self.a=frame_number
        if self.a>self.b:
            self.b=self.a
            
    def setB(self, frame_number):
        self.b=frame_number
        if self.b<self.a:
            self.a=self.b

    
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
        
        self.rubberBand = QRubberBand(QRubberBand.Line, self)
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
                    cap = cv2.VideoCapture(input)
                    try:
                        if cap.isOpened():
                            ret, cv_img = cap.read()
                            if not ret or cv_img is None:                        
                                return
                    finally:
                        cap.release()
            else:
                cv_img  = cv2.imread( input )
        
            rgb_image = cv2.cvtColor(cv_img, cv2.COLOR_BGR2RGB)
            h, w, ch = rgb_image.shape
            bytes_per_line = ch * w
            convert_cv_qt_img = QImage(rgb_image.data, w, h, bytes_per_line, QImage.Format_RGB888)
            self.thumbnail.setPixmap( QPixmap.fromImage(convert_cv_qt_img).scaled( self.thumbnailsize, self.thumbnailsize, Qt.KeepAspectRatio ) )
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
                        
                self.thread.seek(nextsceneframeindex)
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
        
        if uid!=self.displayUid:
            self.qt_img = None
            self.imggeometry=self.size()
            blackpixmap = QPixmap(16,16)
            blackpixmap.fill(Qt.black)
            self.setPixmap(blackpixmap.scaled(self.imggeometry.width(), self.imggeometry.height(), Qt.KeepAspectRatio))
            return
        if cv_img is None or cv_img.size == 0:
            #print("update Image - none", flush=True)
            self.qt_img = None
            self.imggeometry=self.size()
            blackpixmap = QPixmap(16,16)
            blackpixmap.fill(Qt.black)
            self.setPixmap(blackpixmap.scaled(self.imggeometry.width(), self.imggeometry.height(), Qt.KeepAspectRatio))
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
            pm = self.qt_img.scaled(self.imggeometry.width(), self.imggeometry.height(), Qt.KeepAspectRatio)
            #if TRACELEVEL >= 3:
            #    print("pm. w:", pm.width(), "h:", pm.height(), flush=True)
            self.setPixmap(pm)
            if self.onUpdateImage:
                if self.thread:
                    self.onUpdateImage( self.thread.getCurrentFrameIndex() )
                    self.parentUpdate()
                else:
                    self.onUpdateImage( -1 )
                
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
        cv_img  = cv2.imread(self.filepath)
        #print("setImage from cv2", flush=True)
        self.update_image(cv_img, self.displayUid)        

    def stopAndBlackout(self):
        
        if self.thread:
            self.releaseVideo()
            self.update_image(np.array([]), -1)
        else:
            self.update_image(np.array([]), -1)
        self.filepath = ""
        self.frame_count=-1
        self.scene_intersections = []
        self.onBlackout()
        
    def onNoFiles(self):
        self.update_image(np.array([]), -1)
        
    def registerForUpdates(self, onUpdateImage):
        self.onUpdateImage = onUpdateImage

    def registerForFileChange(self, onUpdateFile):
        self.onUpdateFile = onUpdateFile
        
    def registerForTrimUpdate(self, onCropOrTrim):
        self.onCropOrTrim = onCropOrTrim

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
            rememberThread=self.thread
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
        if self.thread:
            t=self.thread
            self.thread=None
            self.button.clicked.disconnect(self.tooglePausePressed)
            t.change_pixmap_signal.disconnect(self.update_image)
            t.requestStop()
            t.deleteLater()
            self.update_image(np.array([]), -1)

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
        
        self.sourceWidth=sourcePixmap.width()
        self.sourceHeight=sourcePixmap.height()
        #print("sourcePixmap", self.sourceWidth, self.sourceHeight, flush=True)
        
        scaledPixmap = self.image_label.getScaledPixmap()
        self.scaledWidth=sourcePixmap.width()
        self.scaledHeight=sourcePixmap.height()
        #print("scaledPixmap", self.scaledWidth, self.scaledHeight, flush=True)


        pixmap = self.image_label.getUnscaledPixmap()
        if pixmap is None or pixmap.isNull():
            print("Das übergebene QLabel enthält kein gültiges Bild.")
            return

        self.original_pixmap = sourcePixmap.copy()
        w = self.original_pixmap.width()
        h = self.original_pixmap.height()
        #print("original_pixmap", w, h, flush=True)
        
        
        self.display_pixmap = pixmap.copy()
        self.image_label.setPixmap(self.display_pixmap)

        self.update_slider_ranges()
        if not self.slidersInitialized:
            # Slider aktivieren und konfigurieren
            self.enable_sliders(True)
            self.slidersInitialized = True

        self.apply_crop()
        
        self.resizeEvent(None)
        
        self.main_layout.invalidate()



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