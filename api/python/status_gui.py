from PyQt5.QtWidgets import (
QApplication, QTableWidget, QTableWidgetItem, QHeaderView, QLabel, QDialog,
QVBoxLayout, QHBoxLayout, QGridLayout, QWidget, QToolBar, QMainWindow, QAction, QAbstractItemView, QMessageBox, QDesktopWidget, QStatusBar, QGroupBox, QPushButton
)
from PyQt5.QtCore import QTimer, Qt, QThread, pyqtSignal, pyqtSlot, QSize 
from PyQt5.QtGui import QColor, QBrush, QFont, QPixmap, QIcon, QImage, QCursor

import sys
import os
from PIL import Image
import urllib.request
from urllib.error import HTTPError
import requests
from random import randrange
import webbrowser
import re
import numpy as np
from numpy import ndarray
import time
import cv2


LOGOTIME = 3000
BREAKFREQ = 120000
TABLEUPDATEFREQ = 1000
BREAKTIME = 20000
status="idle"
idletime = 0

path = os.path.dirname(os.path.abspath(__file__))

COLS = 4


STAGES = ["caption", "scaling", "fullsbs", "interpolate", "singleloop", "dubbing/sfx", "slides", "slideshow", "watermark/encrypt", "watermark/decrypt", "concat", ]
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
            

class SpreadsheetApp(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("VR we are - Status")
        self.setStyleSheet("background-color: black;")
        self.setWindowIcon(QIcon(os.path.join(path, '../../docs/icon/icon.png')))
        self.setGeometry(100, 100, 640, 600)
        self.move(60, 15)

        # Flags for toggles
        self.toogle_stages_expanded = False
        # Initialize caches
        self.stageTypes = []
        
        # Central widget container
        self.central_widget = QWidget()
        self.setCentralWidget(self.central_widget)
        self.layout = QVBoxLayout(self.central_widget)

        # Spreadsheet widget
        self.table = QTableWidget(ROWS, COLS)
        self.table.setStyleSheet("background-color: black; color: black; gridline-color: black")
        self.table.setShowGrid(False)
        self.table.setFrameStyle(0)
        self.table.setSelectionMode(QAbstractItemView.SelectionMode.NoSelection)
        self.table.setFocusPolicy(Qt.NoFocus)
        
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
        pixmap = QPixmap(os.path.join(path, "../../docs/icon/banner.png"))
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
        pixmap = QPixmap(os.path.join(path, "../../docs/icon/banner.png"))
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

        self.idlecount_timer = QTimer()
        self.idlecount_timer.timeout.connect(self.update_idlecount)
        self.idlecount_timer.start(1000)  # 1s

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


    def show_pipeline(self, state):
        imagepath=os.path.join(path, "../../../../user/default/comfyui_stereoscopic/uml/autoforward.png")
        if os.path.exists(imagepath):
            dialog = QDialog()
            dialog.setWindowTitle("VR We Are - Pipeline")
            lay = QVBoxLayout(dialog)
            label = QLabel()
            lay.addWidget(label)
            pixmap = QPixmap(imagepath)
            label.setPixmap(pixmap)
            self.button_show_pipeline_action.setEnabled(False)
            dialog.exec_()
            self.button_show_pipeline_action.setEnabled(True)
        
    def show_manual(self, state):
            webbrowser.open("https://github.com/FortunaCournot/comfyui_stereoscopic/blob/main/docs/VR_We_Are_User_Manual.pdf")

    def check_rate(self, state):
            dialog = RateDialog()
            self.button_show_pipeline_action.setEnabled(False)
            dialog.exec_()
            self.button_show_pipeline_action.setEnabled(True)

    def check_judge(self, state):
            dialog = QDialog()
            dialog.setWindowTitle("VR We Are - Judging")
            lay = QVBoxLayout(dialog)
            label = QLabel()
            lay.addWidget(label)
            self.button_show_pipeline_action.setEnabled(False)
            dialog.exec_()
            self.button_show_pipeline_action.setEnabled(True)

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

        self.toggle_stages_expanded_icon_true = QIcon(os.path.join(path, '../../api/img/expanded64.png'))
        self.toggle_stages_expanded_icon_false = QIcon(os.path.join(path, '../../api/img/collapsed64.png'))

        # Toggle stage expanded action with icon
        self.toggle_stages_expanded_action = QAction(self.toggle_stages_expanded_icon_true if self.toogle_stages_expanded else self.toggle_stages_expanded_icon_false, "Expanded" if self.toogle_stages_expanded else "Collapsed", self)
        self.toggle_stages_expanded_action.setCheckable(True)
        self.toggle_stages_expanded_action.setChecked(self.toogle_stages_expanded)
        self.toggle_stages_expanded_action.triggered.connect(self.toggle_stage_expanded_enabled)
        self.toolbar.addAction(self.toggle_stages_expanded_action)    
        
        self.button_show_pipeline_action = QAction(QIcon(os.path.join(path, '../../api/img/pipeline64.png')), "clicked")      
        self.button_show_pipeline_action.setCheckable(False)
        self.button_show_pipeline_action.triggered.connect(self.show_pipeline)
        self.toolbar.addAction(self.button_show_pipeline_action)    
        imagepath=os.path.join(path, "../../../../user/default/comfyui_stereoscopic/uml/autoforward.png")
        if not os.path.exists(imagepath):
            self.button_show_pipeline_action.setEnabled(False)
        
        self.button_check_rate_action = QAction(QIcon(os.path.join(path, '../../api/img/rate64.png')), "clicked")      
        self.button_check_rate_action.setCheckable(False)
        self.button_check_rate_action.triggered.connect(self.check_rate)
        self.toolbar.addAction(self.button_check_rate_action)    

        self.button_check_judge_action = QAction(QIcon(os.path.join(path, '../../api/img/judge64.png')), "clicked")      
        self.button_check_judge_action.setCheckable(False)
        self.button_check_judge_action.triggered.connect(self.check_judge)
        self.toolbar.addAction(self.button_check_judge_action)    

        self.button_show_manual_action = QAction(QIcon(os.path.join(path, '../../api/img/manual64.png')), "clicked")      
        self.button_show_manual_action.setCheckable(False)
        self.button_show_manual_action.triggered.connect(self.show_manual)
        self.toolbar.addAction(self.button_show_manual_action)    
        

    def update_idlecount(self):
        global idletime
        if status=="idle":
            idletime += 1


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
            COL_IDX_IN_TYPES=1
            header.setSectionResizeMode(COL_IDX_IN_TYPES, QHeaderView.ResizeToContents)
            COLNAMES.append("type")
            COL_IDX_IN=2
            #header.setSectionResizeMode(COL_IDX_IN, QHeaderView.ResizeToContents)
            COLNAMES.append("input (done)")
            COL_IDX_PROCESSING=3
            #header.setSectionResizeMode(COL_IDX_PROCESSING, QHeaderView.ResizeToContents)
            COLNAMES.append("processing")
            COL_IDX_OUT=4
            header.setSectionResizeMode(COL_IDX_OUT, QHeaderView.Stretch)
            COLNAMES.append("output")
        else:
            COLS=4
            self.table.setColumnCount(COLS)
            header = self.table.horizontalHeader()       
            COLNAMES.clear()
            COL_IDX_STAGENAME=0        
            header.setSectionResizeMode(COL_IDX_STAGENAME, QHeaderView.ResizeToContents)
            COLNAMES.append("")
            COL_IDX_IN=1
            #header.setSectionResizeMode(COL_IDX_IN, QHeaderView.ResizeToContents)
            COLNAMES.append("input (done)")
            COL_IDX_PROCESSING=2
            #header.setSectionResizeMode(COL_IDX_PROCESSING, QHeaderView.ResizeToContents)
            COLNAMES.append("processing")
            COL_IDX_OUT=3
            header.setSectionResizeMode(COL_IDX_OUT, QHeaderView.Stretch)
            COLNAMES.append("output")
        
        skippedrows=0
        self.table.clear()
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
                        if c==COL_IDX_IN:
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
                                    onlyfiles = next(os.walk(subfolder))[2]
                                    count = len(onlyfiles)
                                    if count>0:
                                        value = value + " " + str(count) + "!"
                                        color = "red"
                                        displayRequired=True
                            else:
                                value = "?"
                                color = "red"
                                displayRequired=True
                        elif c==COL_IDX_OUT:
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
                            if c==COL_IDX_IN_TYPES:
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
                    pixmap = self.pil2pixmap(im)
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
                        self.idle_image.setCursor(QCursor(Qt.PointingHandCursor))  
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

    def pil2pixmap(self, im):
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

    def closeEvent(self,event):
        try:
            os.remove(os.path.join(path, "../../../../user/default/comfyui_stereoscopic/.guiactive"))
        except OSError as e:
            print("Error: %s - %s." % (e.filename, e.strerror))
        event.accept()

class ClickableLabel(QLabel):
    def __init__(self, url, parent=None):
        super().__init__(parent)
        self.url = url

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            webbrowser.open(self.url)


class VideoThread(QThread):
    change_pixmap_signal = pyqtSignal(np.ndarray)

    def __init__(self, filepath):
        super().__init__()
        self._run_flag = True
        self.filepath = filepath

    def run(self):
        # capture from file
        self._run_flag = True
        self.cap = cv2.VideoCapture(self.filepath)

        # Get video properties (e.g., frame count and frame width)
        frame_count = int(self.cap.get(cv2.CAP_PROP_FRAME_COUNT))  # Get total number of frames in the video
        fps = self.cap.get(cv2.CAP_PROP_FPS)  # Get frames per second (FPS)
        print(f"Total frames: {frame_count}, FPS: {fps}")
        if fps<1:
            fps=1

        while self._run_flag:
            ret, cv_img = self.cap.read()
            if ret:
                self.change_pixmap_signal.emit(cv_img)
                time.sleep(1.0/fps)
                #status.showMessage('frame ...')

        # shut down capture system
        self.cap.release()

    def stop(self):
        """Sets run flag to False and waits for thread to finish"""
        self._run_flag = False


class Display(QLabel):

    def __init__(self, pushbutton):
        super().__init__()
        self.qt_img=None
        self.setStyleSheet("background : black; color: white;")
        self.button = pushbutton
        self.display_width = 3840
        self.display_height = 2160
        self.resize(self.display_width, self.display_height)
        
    def resizeEvent(self, event):
        super().resizeEvent(event)
        if self.qt_img:
            print(f"display geaendert auf: {event.size().width()}x{event.size().height()}")
            self.setPixmap(self.qt_img.scaled(event.size().width(), event.size().height(), Qt.KeepAspectRatio))
        
    def minimumSizeHint(self):
        return QSize(50, 50)

    @pyqtSlot(ndarray)
    def update_image(self, cv_img):
        self.qt_img = self.convert_cv_qt(cv_img)
        geometry=self.size() # self.display_layout.contentsRect()
        print(f"update_image : {geometry.width()}x{geometry.height()}")
        self.setPixmap(self.qt_img.scaled(geometry.width(), geometry.height(), Qt.KeepAspectRatio))

    def convert_cv_qt(self, cv_img):
        rgb_image = cv2.cvtColor(cv_img, cv2.COLOR_BGR2RGB)
        h, w, ch = rgb_image.shape
        bytes_per_line = ch * w
        convert_to_Qt_format = QImage(rgb_image.data, w, h, bytes_per_line, QImage.Format_RGB888)
        p = convert_to_Qt_format.scaled(self.display_width, self.display_height, Qt.KeepAspectRatio)
        return QPixmap.fromImage(p)

    def startVideo(self):
        
        self.button.clicked.disconnect(self.startVideo)
        self.button.setText('Pause')
        self.thread = VideoThread("output/testvideo.mp4")
        self.thread.change_pixmap_signal.connect(self.update_image)

        self.thread.start()
        self.button.clicked.connect(self.thread.stop)
        self.button.clicked.connect(self.pauseVideo)

    def pauseVideo(self):
        self.thread.change_pixmap_signal.disconnect()
        self.button.setText('Start')
        self.button.clicked.disconnect(self.pauseVideo)
        self.button.clicked.disconnect(self.thread.stop)
        self.button.clicked.connect(self.startVideo)


class RateDialog(QDialog):

    def __init__(self):
        super().__init__()

        self.qt_img=None

        #Set the main layout
        self.setWindowTitle("VR We Are - Rating")
        self.setWindowIcon(QIcon(os.path.join(path, '../../docs/icon/icon.png')))
        self.outer_main_layout = QVBoxLayout()
        self.setLayout(self.outer_main_layout)
        self.setStyleSheet("background : black; color: white;")

        self.button_startpause_video = QPushButton(self)
        self.button_startpause_video.setText('Start video')
        self.button_startpause_video.setStyleSheet("background : black; color: white;")
        self.button_startpause_video.resize(180, 80)

        self.display = Display(self.button_startpause_video)
        #self.display.resize(self.display_width, self.display_height)

        self.button_startpause_video.clicked.connect(self.display.startVideo)

        # Display layout
        self.display_layout = QGridLayout()
        self.display_layout.addWidget(self.display ,0 ,0, 1, 1)

        # Tool layout
        self.tool_layout = QVBoxLayout()
        self.tool_layout.addWidget(self.button_startpause_video)
        #self.display_layout.addStretch(0)

        #Main Layout
        self.main_layout = QVBoxLayout()
        self.main_layout.addLayout(self.display_layout)
        self.main_layout.addLayout(self.tool_layout)

        #Main group box
        self.main_group_box = QGroupBox()
        self.main_group_box.setStyleSheet("QGroupBox{font-size: 10px}")
        self.main_group_box.setTitle("Video")
        self.main_group_box.setLayout(self.main_layout)

        #Outer main layout to accomodate the group box

        self.outer_main_layout.addWidget(self.main_group_box)



if __name__ == "__main__":
    if len(sys.argv) != 1:
       print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " ")
    elif os.path.exists(os.path.join(path, "../../../../user/default/comfyui_stereoscopic/.daemonactive")):
        app = QApplication(sys.argv)
        window = SpreadsheetApp()
        window.show()
        sys.exit(app.exec_())
    else:
        print("no lock.", os.path.join(path, "../../../../user/default/comfyui_stereoscopic/.daemonactive"))
