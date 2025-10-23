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
from functools import partial
from itertools import chain
from random import randrange
from urllib.error import HTTPError

import cv2
import numpy as np
import requests
from numpy import ndarray
from PIL import Image
from PyQt5.QtCore import (QBuffer, QRect, QSize, Qt, QThread, QTimer,
                          pyqtSignal, pyqtSlot)
from PyQt5.QtGui import (QBrush, QColor, QCursor, QFont, QIcon, QImage,
                         QKeySequence, QPainter, QPaintEvent, QPen, QPixmap,
                         QTextCursor)
from PyQt5.QtWidgets import (QAbstractItemView, QAction, QApplication,
                             QColorDialog, QComboBox, QDesktopWidget, QDialog,
                             QFileDialog, QFrame, QGridLayout, QGroupBox,
                             QHBoxLayout, QHeaderView, QLabel, QMainWindow,
                             QMessageBox, QPushButton, QShortcut, QSizePolicy,
                             QSlider, QStatusBar, QTableWidget,
                             QTableWidgetItem, QToolBar, QVBoxLayout, QWidget,
                             QPlainTextEdit, QLayout)

from rating import StyledIcon

path = os.path.dirname(os.path.abspath(__file__))

# Add the current directory to the path so we can import local modules
if path not in sys.path:
    sys.path.append(path)

VIDEO_EXTENSIONS = ['.mp4', '.webm', '.ts']
IMAGE_EXTENSIONS = ['.png', '.webp', '.jpg', '.jpeg', '.jfif']

class JudgeDialog(QDialog):

    def __init__(self):
        super().__init__(None, Qt.WindowSystemMenuHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint)

        self.setModal(True)

        #Set the main layout
        self.setWindowTitle("VR We Are - Check Files: Release")
        self.setWindowIcon(QIcon(os.path.join(path, '../../gui/img/icon.png')))
        self.setMaximumSize(QSize(640,480))
        self.setMinimumSize(QSize(640,480))
        self.setGeometry(150, 150, 640, 480)
        self.outer_main_layout = QVBoxLayout()
        self.setLayout(self.outer_main_layout)
        self.setStyleSheet("background : black; color: white;")
        self.sw=1
        self.filter_vid=False
        self.filter_img=False
        
        # --- Toolbar ---
        self.judge_toolbar = QToolBar(self)
        self.judge_toolbar.setVisible(True)

        self.iconOpenFolderAction = StyledIcon(os.path.join(path, '../../gui/img/explorer64.png'))
        self.openFolderAction = QAction(self.iconOpenFolderAction, "Open Folder")
        self.openFolderAction.setCheckable(False)
        self.openFolderAction.setVisible(True)
        self.openFolderAction.triggered.connect(self.onOpenFolder)
        self.judge_toolbar.addAction(self.openFolderAction)
        self.judge_toolbar.widgetForAction(self.openFolderAction).setCursor(Qt.PointingHandCursor)

        self.toggle_filterimg_icon_false = QIcon(os.path.join(path, '../../gui/img/filterimgoff64.png'))
        self.toggle_filterimg_icon_true = QIcon(os.path.join(path, '../../gui/img/filterimgon64.png'))
        self.filterImgAction = QAction(self.toggle_filterimg_icon_true if self.filter_img else self.toggle_filterimg_icon_false, "Toogle Image Filter")
        self.filterImgAction.setCheckable(True)
        self.filterImgAction.setChecked(self.filter_img)
        self.filterImgAction.setVisible(True)
        self.filterImgAction.triggered.connect(self.onFilterImg)
        self.judge_toolbar.addAction(self.filterImgAction)
        self.judge_toolbar.widgetForAction(self.filterImgAction).setCursor(Qt.PointingHandCursor)

        self.toggle_filtervid_icon_false = QIcon(os.path.join(path, '../../gui/img/filtervidoff64.png'))
        self.toggle_filtervid_icon_true = QIcon(os.path.join(path, '../../gui/img/filtervidon64.png'))
        self.filterVidAction = QAction(self.toggle_filtervid_icon_true if self.filter_vid else self.toggle_filtervid_icon_false, "Toogle Video Filter")
        self.filterVidAction.setCheckable(True)
        self.filterVidAction.setChecked(self.filter_vid)
        self.filterVidAction.setVisible(True)
        self.filterVidAction.triggered.connect(self.onFilterVid)
        self.judge_toolbar.addAction(self.filterVidAction)
        self.judge_toolbar.widgetForAction(self.filterVidAction).setCursor(Qt.PointingHandCursor)

        empty = QWidget()
        empty.setSizePolicy(QSizePolicy.Expanding,QSizePolicy.Expanding)
        self.judge_toolbar.addWidget(empty)

        self.button_show_manual_action = QAction(QIcon(os.path.join(path, '../../gui/img/manual64.png')), "Manual")      
        self.button_show_manual_action.setCheckable(False)
        self.button_show_manual_action.triggered.connect(self.show_manual)
        self.judge_toolbar.addAction(self.button_show_manual_action)    
        self.judge_toolbar.widgetForAction(self.button_show_manual_action).setCursor(Qt.PointingHandCursor)

        self.outer_main_layout.addWidget(self.judge_toolbar)
        self.judge_toolbar.setContentsMargins(0,0,0,0)

        # ------
        
        # layout in Grid
        self.display_layout = QGridLayout()
        self.display_layout.setSizeConstraint(QLayout.SetMinimumSize)
        self.outer_main_layout.addLayout(self.display_layout)
        
        # Make Labels for cells: 0,1-5=catStatusLabels, 1,1-5=catCountLabels, 2-4,1-5 is reserved for actions
        self.catStatusLabels = []
        self.catCountLabels = []
        font = QFont()
        font.setPointSize(20)
        pmSpace = QPixmap(os.path.join(path, '../../gui/img/black80.png'))
        space = QLabel()
        space.setPixmap(pmSpace)
        sw=self.sw
        self.display_layout.addWidget(space, 0, 0, sw, 1)
        for c in range(5):
            label = QLabel()
            self.catStatusLabels.append(label)
            self.display_layout.addWidget(label, 0, sw+c, 1, 1)
            self.display_layout.setAlignment(label,  Qt.AlignHCenter | Qt.AlignBottom)
            label = QLabel()
            label.setFont(font)
            self.catCountLabels.append(label)
            self.display_layout.addWidget(label, 1, sw+c, 1, 1)
            self.display_layout.setAlignment(label,  Qt.AlignHCenter | Qt.AlignTop)
        space = QLabel()
        space.setPixmap(pmSpace)
        self.display_layout.addWidget(space, 0, sw+5, sw, 1)

        # Action List, Icons for Actions
        self.actionList = []
        self.iconActionDelete=QIcon(os.path.join(path, '../../gui/img/trash80.png'))
        self.iconActionArchive=QIcon(os.path.join(path, '../../gui/img/archive80.png'))
        self.iconActionForward=QIcon(os.path.join(path, '../../gui/img/ok80.png'))

        # Status Images
        self.pmStatusNoFiles=QPixmap(os.path.join(path, '../../gui/img/starnnothing80.png'))
        self.pmStatusArchived=QPixmap(os.path.join(path, '../../gui/img/stararchive80.png'))
        self.pmStatusDeleted=QPixmap(os.path.join(path, '../../gui/img/stardel80.png'))
        self.pmStatusForwarded=QPixmap(os.path.join(path, '../../gui/img/starforward80.png'))
        self.pmStatusToDo=QPixmap(os.path.join(path, '../../gui/img/startodo80.png'))

        # Take rest of layout below at row 5
        space = QLabel()
        space.setPixmap(pmSpace)
        self.display_layout.addWidget(space, 2, 0, 1, 1)
        space = QLabel()
        space.setPixmap(pmSpace)
        self.display_layout.addWidget(space, 3, 0, 1, 1)
        space = QLabel()
        space.setPixmap(pmSpace)
        self.display_layout.addWidget(space, 4, 0, 1, 1)
        space = QLabel()
        space.setPixmap(pmSpace)
        self.display_layout.addWidget(space, 5, 0, sw, 1)
            
        self.done = QLabel()
        self.done.setPixmap(QPixmap(os.path.join(path, '../../gui/img/donedone.png')))
        self.display_layout.addWidget(self.done, 2, 0, 4, 5+2*self.sw)
        self.display_layout.setAlignment(self.done,  Qt.AlignHCenter | Qt.AlignTop)
        self.done.setVisible(False)

        fileCounts = self.updateContents()
        for c in range(5):
            if fileCounts[c]==0:
                self.catStatusLabels[c].setPixmap(self.pmStatusNoFiles)
            else:
                self.catStatusLabels[c].setPixmap(self.pmStatusToDo)

    def show_manual(self, state):
        webbrowser.open('file://' + os.path.realpath(os.path.join(path, "../../docs/VR_We_Are_User_Manual.pdf")))

    def onOpenFolder(self, state):
        dirPath=srcfolder=os.path.join(path, "../../../../output/vr/check/rate")
        os.system("start \"\" " + os.path.abspath(dirPath))
        # subprocess.Popen(["explorer", os.path.abspath(dirPath) ], close_fds=True) - generates zombies

    def onFilterImg(self, state):
        self.done.setVisible(False)
        self.filter_img = state
        self.filterImgAction.setIcon(self.toggle_filterimg_icon_true if self.filter_img else self.toggle_filterimg_icon_false)
        if self.filter_img and self.filter_vid:
            self.filterVidAction.setChecked(False)
            self.onFilterVid(False)
        else:
            fileCounts = self.updateContents()
            for c in range(5):
                if fileCounts[c]==0:
                    self.catStatusLabels[c].setPixmap(self.pmStatusNoFiles)
                else:
                    self.catStatusLabels[c].setPixmap(self.pmStatusToDo)
    
    def onFilterVid(self, state):
        self.done.setVisible(False)
        self.filter_vid = state
        self.filterVidAction.setIcon(self.toggle_filtervid_icon_true if self.filter_vid else self.toggle_filtervid_icon_false)
        if self.filter_img and self.filter_vid:
            self.filterImgAction.setChecked(False)
            self.onFilterImg(False)
        else:
            fileCounts = self.updateContents()
            for c in range(5):
                if fileCounts[c]==0:
                    self.catStatusLabels[c].setPixmap(self.pmStatusNoFiles)
                else:
                    self.catStatusLabels[c].setPixmap(self.pmStatusToDo)

    def applyFileFilter(self, allfiles):
        _activeExtensions=[]
        if not self.filter_img:
            _activeExtensions = _activeExtensions + IMAGE_EXTENSIONS
        if not self.filter_vid:
            _activeExtensions = _activeExtensions + VIDEO_EXTENSIONS
        
        files = []
        try:
            for f in allfiles:
                if any(f.lower().endswith(suf.lower()) for suf in _activeExtensions):
                    files.append(f) 
        except Exception:
            print(traceback.format_exc(), flush=True)
            
        return files
        
        
    def executeForward(self, catIndex):
        folder = os.path.join(path, "../../../../output/vr/check/rate")
        subfolder = os.path.join(folder, str(catIndex+1))
        targetfolder = os.path.join(path, "../../../../output/vr/check/released")
        os.makedirs(targetfolder, exist_ok=True)
        try:
            files = self.applyFileFilter( next(os.walk(subfolder))[2] )
            for f in files:
                try:
                    source=os.path.join(subfolder, f)
                    destination=os.path.join(targetfolder, f)
                    os.rename(source, destination)
                except Exception as anyex:
                    print("Error forwarding " + source, flush=True)
                    print(traceback.format_exc(), flush=True)
        except StopIteration as e:
            print("Error forwarding " + "StopIteration", flush=True)
        self.catStatusLabels[catIndex].setPixmap(self.pmStatusForwarded)
        self.updateContents()

    def executeArchive(self, catIndex):
        folder = os.path.join(path, "../../../../output/vr/check/rate")
        subfolder = os.path.join(folder, str(catIndex+1))
        targetfolder = os.path.join(path, "../../../../input/vr/check/released/done")
        os.makedirs(targetfolder, exist_ok=True)
        try:
            files = self.applyFileFilter( next(os.walk(subfolder))[2] )
            for f in files:
                try:
                    source=os.path.join(subfolder, f)
                    destination=os.path.join(targetfolder, f)
                    os.rename(source, destination)
                except Exception as anyex:
                    print("Error archiving " + source, flush=True)
                    print(traceback.format_exc(), flush=True)
        except StopIteration as e:
            print("Error archiving " + "StopIteration", flush=True)
        self.catStatusLabels[catIndex].setPixmap(self.pmStatusArchived)
        self.updateContents()

    def executeDelete(self, catIndex):
        folder = os.path.join(path, "../../../../output/vr/check/rate")
        subfolder = os.path.join(folder, str(catIndex+1))
        try:
            files = self.applyFileFilter( next(os.walk(subfolder))[2] )
            for f in files:
                try:
                    source=os.path.join(subfolder, f)
                    os.remove(source)
                except Exception as anyex:
                    print("Error deleting " + source, flush=True)
                    print(traceback.format_exc(), flush=True)
        except StopIteration as e:
            print("Error deleting " + "StopIteration", flush=True)
        self.catStatusLabels[catIndex].setPixmap(self.pmStatusDeleted)
        self.updateContents()

    def removeActions(self):
        for a in self.actionList:
            self.display_layout.removeWidget(a)
        self.actionList = []
            
    def updateContents(self):
        
        folder = os.path.join(path, "../../../../output/vr/check/rate")
        fileCounts = []
        for c in range(5):
            subfolder = os.path.join(folder, str(c+1))
            try:
                files = self.applyFileFilter( next(os.walk(subfolder))[2] )
                fileCounts.append((len(files)))
            except StopIteration as e:
                fileCounts.append(0)

        for c in range(5):
            if fileCounts[c]==0:
                self.catCountLabels[c].setText("")
            else:
                self.catCountLabels[c].setText(str(fileCounts[c]))

        self.removeActions()

        highest=-1
        for c in reversed(range(5)):
            if fileCounts[c]!=0:
                highest=c
                break
    
        if highest<0:
            self.done.setVisible(True)
        else:
            self.done.setVisible(False)
            lowest=-1
            for c in range(5):
                if fileCounts[c]!=0:
                    lowest=c                    
                    break
            

            sw = self.sw
            
            action = ActionButton(highest)
            action.setIcon(self.iconActionForward)
            action.setIconSize(QSize(80,80))
            action.setCursor(Qt.PointingHandCursor)
            action.clicked.connect(partial(self.executeForward, highest))
            self.display_layout.addWidget(action, 2, sw+highest, 1, 1)
            self.display_layout.setAlignment(action,  Qt.AlignHCenter | Qt.AlignVCenter)
            self.actionList.append(action)

            action = ActionButton(lowest)
            action.setIcon(self.iconActionArchive)
            action.setIconSize(QSize(80,80))
            action.setCursor(Qt.PointingHandCursor)
            action.clicked.connect(partial(self.executeArchive, lowest))
            self.display_layout.addWidget(action, 3, sw+lowest, 1, 1)
            self.display_layout.setAlignment(action,  Qt.AlignHCenter | Qt.AlignVCenter)
            self.actionList.append(action)
            
            action = ActionButton(lowest)
            action.setIcon(self.iconActionDelete)
            action.setIconSize(QSize(80,80))
            action.setCursor(Qt.PointingHandCursor)
            action.clicked.connect(partial(self.executeDelete, lowest))
            self.display_layout.addWidget(action, 4, sw+lowest , 1, 1)
            self.display_layout.setAlignment(action,  Qt.AlignHCenter | Qt.AlignVCenter)
            self.actionList.append(action)


        return fileCounts

class ActionButton(QPushButton):
    def __init__(self, catIndex):
        super().__init__()
        self.catIndex = catIndex
        #self.button_prev_file.setStyleSheet("background : black; color: white;")
        #self.updateStylesheet()

