import io
import ntpath
import os
import re
import subprocess
import sys
import time
import traceback
import urllib.request
import webbrowser
from itertools import chain
from random import randrange
from threading import Thread
from urllib.error import HTTPError

import cv2
import numpy as np
import requests
from numpy import ndarray
from PIL import Image
from PyQt5.QtCore import (QBuffer, QRect, QSize, Qt, QThread, QTimer, QPoint,
                          pyqtSignal, pyqtSlot)
from PyQt5.QtGui import (QBrush, QColor, QCursor, QFont, QIcon, QImage,
                         QKeySequence, QPainter, QPaintEvent, QPen, QPixmap,
                         QPalette)
from PyQt5.QtWidgets import (QAbstractItemView, QAction, QApplication,
                             QColorDialog, QComboBox, QDesktopWidget, QDialog,
                             QFileDialog, QFrame, QGridLayout, QGroupBox,
                             QHBoxLayout, QHeaderView, QLabel, QMainWindow,
                             QMessageBox, QPushButton, QShortcut, QSizePolicy,
                             QSlider, QStatusBar, QTableWidget,
                             QTableWidgetItem, QToolBar, QVBoxLayout, QWidget,
                             QScrollArea)

path = os.path.dirname(os.path.abspath(__file__))

# Add the current directory to the path so we can import local modules
if path not in sys.path:
    sys.path.append(path)

# Import our implementations
from rating import RateAndCutDialog, StyledIcon, pil2pixmap, getFilesWithoutEdit, getFilesOnlyEdit, rescanFilesToRate
from judge import JudgeDialog


LOGOTIME = 3000
BREAKFREQ = 120000
TABLEUPDATEFREQ = 1000
TOOLBARUPDATEFREQ = 1000
BREAKTIME = 20000
FILESCANTIME = 2000

status="idle"
idletime = 0

COLS = 4


STAGES = ["caption", "scaling", "fullsbs", "interpolate", "singleloop", "dubbing/sfx", "slides", "slideshow", "watermark/encrypt", "watermark/decrypt", "concat", "check/rate", "check/released"]
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
        # Initialize caches
        self.stageTypes = []

        self.pipelinedialog=None

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
        self.table = HoverTableWidget(ROWS, COLS, self.isCellClickable, self.onCellClick)
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
        
    def mousePressEvent(self, event):
        """Wenn auf das MainWindow geklickt wird und der Dialog offen ist → bringe Dialog nach vorne"""
        if self.dialog and self.dialog.isVisible():
            self.dialog.raise_()
            self.dialog.activateWindow()
        else:
            super().mousePressEvent(event)
            
    def show_manual(self, state):
        webbrowser.open("https://github.com/FortunaCournot/comfyui_stereoscopic/blob/main/docs/VR_We_Are_User_Manual.pdf")

    def check_cutandclone(self, state):
        dialog = RateAndCutDialog(True)
        self.dialog = dialog
        dialog.show()
        self.dialog = None

    def check_rate(self, state):
        dialog = RateAndCutDialog(False)
        self.dialog = dialog
        dialog.show()
        self.dialog = None

    def check_judge(self, state):
        dialog = JudgeDialog()
        self.dialog = dialog
        dialog.show()
        self.dialog = None

    def toggle_stage_expanded_enabled(self, state):
        self.toogle_stages_expanded = state
        self.table.setRowCount(0)
        self.table.clear()
        if self.toogle_stages_expanded:
            self.toggle_stages_expanded_action.setIcon(self.toggle_stages_expanded_icon_true)
        else:
            self.toggle_stages_expanded_action.setIcon(self.toggle_stages_expanded_icon_false)

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

        self.toolbar.addSeparator()
        
        self.button_check_cutclone_action = QAction(StyledIcon(os.path.join(path, '../../gui/img/cut64.png')), "Crop & Trim")      
        self.button_check_cutclone_action.setCheckable(False)
        self.button_check_cutclone_action.setEnabled(False)
        self.button_check_cutclone_action.triggered.connect(self.check_cutandclone)
        self.toolbar.addAction(self.button_check_cutclone_action)    
                             
        self.button_check_rate_action = QAction(StyledIcon(os.path.join(path, '../../gui/img/rate64.png')), "Rate")      
        self.button_check_rate_action.setCheckable(False)
        self.button_check_rate_action.setEnabled(False)
        self.button_check_rate_action.triggered.connect(self.check_rate)
        self.toolbar.addAction(self.button_check_rate_action)    

        self.button_check_judge_action = QAction(StyledIcon(os.path.join(path, '../../gui/img/judge64.png')), "Release")      
        self.button_check_judge_action.setCheckable(False)
        self.button_check_judge_action.triggered.connect(self.check_judge)
        self.button_check_judge_action.setEnabled(False)
        self.toolbar.addAction(self.button_check_judge_action)    
        
        empty = QWidget()
        empty.setSizePolicy(QSizePolicy.Expanding,QSizePolicy.Expanding)
        self.toolbar.addWidget(empty)

        self.button_show_pipeline_action = QAction(QIcon(os.path.join(path, '../../gui/img/pipeline64.png')), "Worflow")      
        self.button_show_pipeline_action.setCheckable(False)
        self.button_show_pipeline_action.triggered.connect(self.show_pipeline)
        self.toolbar.addAction(self.button_show_pipeline_action)    
        imagepath=os.path.join(path, "../../../../user/default/comfyui_stereoscopic/uml/autoforward.png")
        if not os.path.exists(imagepath):
            self.button_show_pipeline_action.setEnabled(False)
        
        self.toolbar.addSeparator()

        self.button_show_manual_action = QAction(QIcon(os.path.join(path, '../../gui/img/manual64.png')), "Manual")      
        self.button_show_manual_action.setCheckable(False)
        self.button_show_manual_action.triggered.connect(self.show_manual)
        self.toolbar.addAction(self.button_show_manual_action)    
        

    def update_idlecount(self):
        global idletime
        if status=="idle":
            idletime += 1

    def update_toolbar(self):
        count1=len(getFilesWithoutEdit())
        count2=len(getFilesOnlyEdit())

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

    def update_table(self):
        global idletime

        
        if not os.path.exists(os.path.join(path, "../../../../user/default/comfyui_stereoscopic/.daemonactive")):
            sys.exit(app.exec_())

        if self.idle_container_active:
            if idletime < 15:
                self.show_table()
            
        status="idle"
        activestage=""
        statusfile = os.path.join(path, "../../../../user/default/comfyui_stereoscopic/.daemonstatus")
        if os.path.exists(statusfile):
            with open(statusfile) as file:
                statuslines = [line.rstrip() for line in file]
                for line in range(len(statuslines)):
                    if line==0:
                        activestage=statuslines[0]
                        status="processing"
                        idletime=0
                    else:
                        status=status + " " + statuslines[line]
        self.setWindowTitle("VR we are - " + activestage + " " + status)

        fontC0 = QFont()
        fontC0.setBold(True)
        fontC0.setItalic(True)

        fontR0 = QFont()
        fontR0.setBold(True)
        fontR0.setItalic(True)

        COLNAMES = []
        if self.toogle_stages_expanded:
            COLS=5
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

    def show_table(self):
        self.idle_container_active=False
        # Replace logo page with table
        self.layout.removeWidget(self.logo_container)
        self.layout.removeWidget(self.idle_container)
        self.logo_container.setParent(None)
        self.idle_container.setParent(None)
        self.layout.addWidget(self.table)
        self.update_table()
        self.update_timer.start(TABLEUPDATEFREQ)

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
        return False

    def onCellClick(self, row, col):
        try:
            idx = ROW2STAGE[row-1]
            
            if col == self.COL_IDX_IN:
                folder =  os.path.abspath( os.path.join(path, "../../../../input/vr/" + STAGES[idx]) )
                subprocess.Popen(r'explorer "'  + folder + '"')
            if col == self.COL_IDX_OUT:
                folder =  os.path.abspath( os.path.join(path, "../../../../output/vr/" + STAGES[idx]) )
                subprocess.Popen(r'explorer "'  + folder + '"')
            
        except Exception:
            print(f"Error on cell click: row={row}, col={col}", ROW2STAGE, flush=True)
            pass
        

   
    def closeEvent(self,event):
        try:
            os.remove(os.path.join(path, "../../../../user/default/comfyui_stereoscopic/.guiactive"))
        except OSError as e:
            print("Error: %s - %s." % (e.filename, e.strerror))
        event.accept()

    def show_pipeline(self, state):
        
        global pipelinedialog, lay
        pipelinedialog = QDialog()
        pipelinedialog.setWindowTitle("VR We Are - Pipeline")
        pipelinedialog.setModal(True)
        #pipelinedialog.setWindowFlags(self.windowFlags() | Qt.WindowStaysOnTopHint)
        lay = QVBoxLayout(pipelinedialog)
        pal=QPalette()
        bgcolor = QColor("gray") # usally not visible
        role = QPalette.Background
        pal.setColor(role, bgcolor)
        self.setPalette(pal)

        pipeline_toolbar = QToolBar("Pipeline Actions")
        lay.addWidget(pipeline_toolbar)
        global editAction
        editAction = QAction("Edit")
        editAction.setCheckable(False)
        editAction.triggered.connect(self.edit_pipeline)
        pipeline_toolbar.addAction(editAction)

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
        w, h = 4096, 2160
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
        self.dialog = None
        self.button_show_pipeline_action.setEnabled(True)
            
    def edit_pipeline(self, state):
        configFile=os.path.join(path, r'..\..\..\..\user\default\comfyui_stereoscopic\autoforward.yaml')
        global editActive, pipelineModified, editthread
        pipelineModified=False
        editActive=True
        editAction.setEnabled(False)
        editthread = PipelineEditThread(window)
        editthread.start()

class PipelineEditThread(QThread):
    def __init__(self, parent):
        super().__init__()
        self.parent = parent

    def run(self):

        watchthread = PipelineWatchThread(self.parent)
        watchthread.start()

        configFile=os.path.join(path, r'..\..\..\..\user\default\comfyui_stereoscopic\autoforward.yaml')
        subprocess.Popen(r'notepad "'  + configFile + '"').wait()

        global editActive, pipelineModified, editthread

        #if pipelineModified:
        #    softkillFile=os.path.join(path, r'..\..\..\..\user\default\comfyui_stereoscopic\.daemonactive')
        #    os.remove(softkillFile)
            
        editActive=False
        editthread=None
        editAction.setEnabled(True)
        
class PipelineWatchThread(QThread):
    def __init__(self, parent):
        super().__init__()
        self.parent = parent

    def run(self):
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
                print("changed", flush=True)
                setPipelineErrorText(None)
                hidePipelineShowText("Rebuilding forward files")
                
                exit_code, rebuildMsg = self.waitOnSubprocess( subprocess.Popen(pythonExe + r' "' + uml_build_forwards + '"', stderr=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=1, shell=True, text=True) )
                if not rebuildMsg == "":
                    setPipelineErrorText(rebuildMsg)

                
                print("forwards", exit_code, flush=True)
                hidePipelineShowText("Prepare rendering...")
                exit_code, msg = self.waitOnSubprocess( subprocess.Popen(pythonExe + r' "' + uml_build_definition + '"', stderr=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=1, shell=True, text=True) )
                print("prepare rendering", exit_code, flush=True)
                hidePipelineShowText("Generate new image...")
                exit_code, msg = self.waitOnSubprocess( subprocess.Popen(pythonExe + r' "' + uml_generate_image + '"', stderr=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=1, shell=True, text=True) )
                print("rendered", exit_code, flush=True)
                hidePipelineShowText("Updating new image...")
                updatePipeline()
                pipelineModified=True

                
    def waitOnSubprocess(self, process):
        ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
        msgboxtext=""
        while True:
            line = process.stdout.readline()
            if not line:
                break
            line = line.rstrip()
            print(line, flush=True)
            if "Error:" in line:
                msgboxtext = msgboxtext + ansi_escape.sub('', line) + "\n"
        
        rc = process.wait()
        return (rc, msgboxtext)

class HoverTableWidget(QTableWidget):
    def __init__(self, rows, cols, isCellClickable, onCellClick, parent=None):
        super().__init__(rows, cols, parent)
        self.setEditTriggers(QTableWidget.NoEditTriggers)  # Nur-Lese-Modus
        self.setMouseTracking(True)  # Mausbewegungen ohne Klick erfassen
        self.current_hover = None
        self.isCellClickable=isCellClickable
        self.onCellClick=onCellClick

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
        else:
            # Maus außerhalb der Tabelle -> Reset
            self.reset_hover_style()
            self.current_hover = None

        super().mouseMoveEvent(event)

    def leaveEvent(self, event):
        """Wenn die Maus den TableWidget-Bereich verlässt."""
        self.reset_hover_style()
        self.current_hover = None
        super().leaveEvent(event)

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
    if len(sys.argv) != 1:
       print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " ")
    elif os.path.exists(os.path.join(path, "../../../../user/default/comfyui_stereoscopic/.daemonactive")):
        try:
            global window
            app = QApplication(sys.argv)
            window = SpreadsheetApp()
            window.show()
        except:
            print(traceback.format_exc(), flush=True)                
        sys.exit(app.exec_())
    else:
        print("no lock.", os.path.join(path, "../../../../user/default/comfyui_stereoscopic/.daemonactive"))
