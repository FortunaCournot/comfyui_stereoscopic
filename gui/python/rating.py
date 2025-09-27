import bisect
import io
import ntpath
import os
import re
import subprocess
import sys
import shutil
import time
import traceback
import urllib.request
import webbrowser
from datetime import timedelta
from functools import wraps
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
from PyQt5.QtCore import (QBuffer, QRect, QSize, Qt, QThread, QTimer, QPoint,
                          pyqtSignal, pyqtSlot, QRunnable, QThreadPool, QObject)
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
                             QPlainTextEdit, QLayout, QStyleOptionSlider, QStyle,
                             QRubberBand)

path = os.path.dirname(os.path.abspath(__file__))

# Add the current directory to the path so we can import local modules
if path not in sys.path:
    sys.path.append(path)

# File Global
videoActive=False
rememberThread=None
fileDragged=False
FILESCANTIME = 500

# ---- Tasks ----
taskActive=0


def isTaskActive():
    return taskActive>0

def enterTask():
    global taskActive
    taskActive+=1
    print(f"enterTask {taskActive}", flush=True)

def leaveTask():
    global taskActive
    print(f"leaveTask {taskActive}", flush=True)
    taskActive-=1

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
        self.setWindowFlags(Qt.CustomizeWindowHint | Qt.WindowMaximizeButtonHint | Qt.WindowCloseButtonHint )

        global cutModeActive, cutModeFolderOverrideActive
        cutModeActive=cutMode
        self.cutMode=cutMode
        cutModeFolderOverrideActive=False
        
        rescanFilesToRate()
        
        self.qt_img=None
        self.hasCropOrTrim=False
        self.isPaused = False
        self.currentFile = None
        
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
        self.setGeometry(150, 150, 1280, 768)
        self.outer_main_layout = QVBoxLayout()
        self.setLayout(self.outer_main_layout)
        self.setStyleSheet("background-color : black;")

        if cutMode:
            self.cutMode_toolbar = QToolBar(self)
            self.cutMode_toolbar.setVisible(True)
            self.iconFolderAction = StyledIcon(os.path.join(path, '../../gui/img/folder64.png'))
            self.folderAction = QAction(self.iconFolderAction, "Select Custom Folder")
            self.folderAction.setCheckable(True)
            self.folderAction.setVisible(True)
            self.folderAction.triggered.connect(self.onSelectFolder)
            self.cutMode_toolbar.addAction(self.folderAction)
            self.outer_main_layout.addWidget(self.cutMode_toolbar)

        self.button_startpause_video = ActionButton()
        self.button_startpause_video.setIcon(QIcon(os.path.join(path, '../../gui/img/play80.png')))
        self.button_startpause_video.setIconSize(QSize(80,80))

        if cutMode:
            self.iconTrimA = StyledIcon(os.path.join(path, '../../gui/img/trima80.png'))
            self.iconTrimB = StyledIcon(os.path.join(path, '../../gui/img/trimb80.png'))
            self.iconClear = StyledIcon(os.path.join(path, '../../gui/img/clear80.png'))

            self.button_trima_video = ActionButton()
            self.button_trima_video.setIcon(self.iconTrimA)
            self.button_trima_video.setIconSize(QSize(80,80))

            self.button_trimb_video = ActionButton()
            self.button_trimb_video.setIcon(self.iconTrimB)
            self.button_trimb_video.setIconSize(QSize(80,80))

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

        if cutMode:
            self.button_cutandclone = ActionButton()
            self.button_cutandclone.setIcon(StyledIcon(os.path.join(path, '../../gui/img/cutclone80.png')))
            self.button_cutandclone.setIconSize(QSize(80,80))
            self.button_cutandclone.clicked.connect(self.createTrimmedAndCroppedCopy)

            self.icon_compress = StyledIcon(os.path.join(path, '../../gui/img/compress80.png'))
            self.icon_justrate = StyledIcon(os.path.join(path, '../../gui/img/justrate80.png'))
            self.button_justrate_compress = ActionButton()
            self.button_justrate_compress.setIcon(self.icon_justrate)
            self.button_justrate_compress.setIconSize(QSize(80,80))
            self.button_justrate_compress.setEnabled(True)
            self.button_justrate_compress.setVisible(cutMode)
            self.button_justrate_compress.clicked.connect(self.rateOrArchiveAndNext)
            self.justRate=True
        
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
        
        self.display = Display(self.button_startpause_video, self.sl, self.updatePaused, self.onVideoloaded, self.onRectSelected)
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
        self.videotool_layout.addWidget(self.sl, alignment =  Qt.AlignVCenter)
        if cutMode:
            self.videotool_layout.addWidget(self.button_trimb_video)
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
        self.commontool_layout.addWidget(self.button_delete_file, 0, ew+5, 1, 1)
        
        self.msgWidget=QPlainTextEdit()
        self.msgWidget.setReadOnly(True)
        self.msgWidget.setFrameStyle(QFrame.NoFrame)
        self.commontool_layout.addWidget(self.msgWidget, 0, ew+6, 1, ew)
        self.msgWidget.setPlaceholderText("No log entries.")
        
        self.button_startpause_video.clicked.connect(self.display.startVideo)
        if cutMode:
            self.button_trima_video.clicked.connect(self.display.trimA)
            self.button_trimb_video.clicked.connect(self.display.trimB)
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

        # Timer for updating file buttons
        self.filebutton_timer = QTimer()
        self.filebutton_timer.timeout.connect(self.update_filebuttons)
        self.filebutton_timer.start(FILESCANTIME)
        
        self.rateNext()

    def onSelectFolder(self, state):
        global _cutModeFolderOverrideFiles, cutModeFolderOverrideActive, cutModeFolderOverridePath
        
        self.display.stopAndBlackout()
        
        if cutModeFolderOverrideActive: # and not state:
            cutModeFolderOverrideActive=False
            scanFilesToRate()
            files=getFilesToRate()
            self.currentIndex=0
            self.currentFile=files[self.currentIndex]

        if state:
            dirpath = str(QFileDialog.getExistingDirectory(self, "Select Directory", cutModeFolderOverridePath, QFileDialog.ShowDirsOnly | QFileDialog.DontResolveSymlinks))
            if not os.path.isdir(dirpath):
                self.folderAction.setChecked(False)
            else:
                cutModeFolderOverridePath=dirpath
                cutModeFolderOverrideActive=True
                scanFilesToRate()
                if len(_cutModeFolderOverrideFiles)>0:
                    files=getFilesToRate()
                    self.currentIndex=0
                    self.currentFile=files[self.currentIndex]
                else:
                    self.folderAction.setChecked(False)
            
        self.rateCurrentFile()

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
        super(QDialog, self).closeEvent(evnt)
            
    def updatePaused(self, isPaused):
        self.isPaused = isPaused
        if self.cutMode:
            self.button_trima_video.setEnabled(isPaused)
            self.button_trimb_video.setEnabled(isPaused)
            self.button_snapshot_from_video.setEnabled(isPaused and self.isVideo)
        self.button_startpause_video.setIcon(QIcon(os.path.join(path, '../../gui/img/play80.png') if isPaused else os.path.join(path, '../../gui/img/pause80.png') ))

        self.filebutton_timer.timeout.connect(self.update_filebuttons)
        self.button_startpause_video.setFocus()

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
            self.main_group_box.setTitle(getFilesToRate()[index-1])

    def fileSliderChanged(self):
        index=self.fileDragIndex
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
        self.button_prev_file.setEnabled(index>1)
        self.button_next_file.setEnabled(index>0 and index<lastIndex)
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

    def rateNext(self):
        enterTask()
        try:

            if self.cutMode:
                self.button_justrate_compress.setEnabled(True)
                self.button_justrate_compress.setIcon(self.icon_justrate)
                self.justRate=True

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
        
        except Exception:
            pass
        leaveTask()

    def ratePrevious(self):
        enterTask()
        try:
            if self.cutMode:
                self.button_justrate_compress.setEnabled(True)
                self.button_justrate_compress.setIcon(self.icon_justrate)
                self.justRate=True
            
            files=getFilesToRate()
            if len(files)==0:
                self.closeOnError("no files (ratePrevious)")
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
        except Exception:
            pass
        leaveTask()

        
    def rateCurrentFile(self):
        enterTask()
        try:
            self.fileSlider.setValue(self.currentIndex)
            global fileDragged
            fileDragged=False
            self.hasCropOrTrim=False
            self.main_group_box.setTitle( self.currentFile )
            if cutModeFolderOverrideActive:
                folder=os.path.join(path, cutModeFolderOverridePath)
            else:
                folder=os.path.join(path, "../../../../input/vr/check/rate")
            file_path=os.path.abspath(os.path.join(folder, self.currentFile))
            if not os.path.exists(file_path):
                print("Error: File does not exist: "  + file_path, flush=True)
                return
            self.isVideo=self.display.showFile( file_path ) == "video"
            self.button_startpause_video.setVisible(self.isVideo)
            self.sl.setVisible(self.isVideo)
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
        except Exception:
            pass
        leaveTask()

    def on_rating_changed(self, rating):
        enterTask()
        try:
            print(f"Rating selected: {rating}", flush=True)

            files=getFilesToRate()
            try:
                index=files.index(self.currentFile)
                name=self.currentFile
                folder_in=os.path.join(path, "../../../../input/vr/check/rate")
                folder_out=os.path.join(path, f"../../../../output/vr/check/rate/{rating}")
                os.makedirs(folder_out, exist_ok = True)
                input=os.path.abspath(os.path.join(folder_in, name))
            except ValueError as ve:
                print(traceback.format_exc(), flush=True)                
                index=0
                self.currentIndex=index
                self.currentFile=files[index]
                self.rateCurrentFile()
                return
            try:
                idx = name.index('/')
                output=os.path.abspath(os.path.join(folder_out, replaceSomeChars(name[idx+1:])))
            except ValueError as ve:                
                output=os.path.abspath(os.path.join(folder_out, replaceSomeChars(name)))
            
            #print("index"  , index, self.currentFile, flush=True)
            
            if os.path.isfile(input):
                try:
                    self.display.stopAndBlackout()
                    
                    if index>=0:
                        self.log(f"Rated {rating} on " + name, QColor("white"))
                        recreated=os.path.isfile(output)
                        if recreated:
                            os.remove(output)
                        os.rename(input, output)
                        del getFilesToRate()[index]
                        files=rescanFilesToRate()
                        self.rating_widget.clear_rating()
                        self.log(" Overwritten" if recreated else " Moved", QColor("green"))
                        
                        if not self.exifpath is None:
                            # https://exiftool.org/forum/index.php?topic=6591.msg32875#msg32875
                            rating_percent_values = [0, 1, 25,50, 75, 99]   # mp4
                            cmd = self.exifpath + f" -xmp:rating={rating} -SharedUserRating={rating_percent_values[rating]}" + " -overwrite_original \"" + output + "\""
                            try:
                                cp = subprocess.run(cmd, shell=True, check=True)
                                self.logn(",Rated.", QColor("green"))
                            except subprocess.CalledProcessError as se:
                                self.logn(" Failed", QColor("red"))
                                print("Failed: "  + cmd, flush=True)
                        else:
                            self.logn(".", QColor("white"))

                    l=len(files)

                    if l==0:    # last file?
                        self.closeOnError("last file rated (on_rating_changed)")
                        return

                    if index>=l:
                        print("index--", index, l, flush=True)                
                        index=l-1
                        
                    self.currentFile=files[index]
                    self.currentIndex=index
                    #print("index next"  , index, l, self.currentFile, flush=True)
                    self.rateCurrentFile()
                        
                except Exception as any_ex:
                    print(traceback.format_exc(), flush=True)                
                    self.logn(" failed", QColor("red"))
            else:
                self.logn(" not found", QColor("red"))

        except Exception:
            pass
        leaveTask()


    def deleteAndNext(self):
        enterTask()
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
                        self.log("Deleting " + os.path.basename(input), QColor("white"))
                        os.remove(input)
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

                    self.logn(" done", QColor("green"))
                    
                except Exception as any_ex:
                    print(traceback.format_exc(), flush=True)                
                    self.logn(" failed", QColor("red"))
            else:
                self.logn(" not found", QColor("red"))
        except Exception:
            pass
        leaveTask()


    def rateOrArchiveAndNext(self):
        enterTask()
        try:
            if self.cutMode:
                self.button_justrate_compress.setEnabled(False)
            
            files=getFilesToRate()
            try:
                index=files.index(self.currentFile)
                if cutModeFolderOverrideActive:
                    folder=cutModeFolderOverridePath
                else:
                    folder=os.path.join(path, "../../../../input/vr/check/rate")
                targetfolder = os.path.join(path, "../../../../input/vr/check/rate/ready" if self.justRate else "../../../../input/vr/check/rate/done")
                os.makedirs(targetfolder, exist_ok=True)
            except ValueError as ve:
                print(traceback.format_exc(), flush=True)                
                index=0
                self.currentFile=files[index]
                self.currentIndex=index
                self.rateCurrentFile()
                return
                
            try:
                self.display.stopAndBlackout()

                if index>=0:
                    source=os.path.join(folder, self.currentFile)
                    destination=os.path.join(targetfolder, replaceSomeChars(self.currentFile))
                    
                    self.log( ( "Forward " if self.justRate else "Archive " ) + self.currentFile, QColor("white"))
                    recreated=os.path.exists(destination)
                    #os.replace(source, destination)
                    shutil.move(source, destination)
                    files=rescanFilesToRate()
                
                l=len(files)

                if l==0:    # last file deleted?
                    self.closeOnError("last file deleted (rateOrArchiveAndNext)")
                    return

                if index>=l:
                    index=l-1
                    
                self.currentFile=files[index]
                self.currentIndex=index
                self.rateCurrentFile()
                    
                self.logn(" Overwritten" if recreated else " OK", QColor("green"))

            except Exception as anyex:
                self.logn(" Failed", QColor("red"))
                print("Error archiving/forwarding " + source, flush=True)
                print(traceback.format_exc(), flush=True)
        except Exception:
            pass
        leaveTask()

        
    def createTrimmedAndCroppedCopy(self):
        enterTask()
        try:
            self.hasCropOrTrim=False
            rfolder=os.path.join(path, "../../../../input/vr/check/rate")
            if cutModeFolderOverrideActive:
                folder=cutModeFolderOverridePath
            else:
                folder=rfolder
            input=os.path.abspath(os.path.join(folder, replaceSomeChars(self.currentFile)))
            try:
                outputBase=os.path.abspath(input[:input.rindex('.')] + "_")
                fnum=1
                while os.path.exists(outputBase + str(fnum) + ".mp4"):
                    fnum+=1
                newfilename=self.currentFile[:self.currentFile.rindex('.')] + "_" + str(fnum) + ".mp4"
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
                cmd = "ffmpeg.exe -y -i \"" + input + "\" -vf \""
                if self.isVideo:
                    cmd = cmd + "trim=start_frame=" + str(trimA) + ":end_frame=" + str(trimB) + ","
                cmd = cmd + "crop="+str(out_w)+":"+str(out_h)+":"+str(x)+":"+str(y)+"\" \"" + output + "\""
                print("Executing "  + cmd, flush=True)
                try:
                    recreated=os.path.exists(output)
                    cp = subprocess.run(cmd, shell=True, check=True)
                    self.logn(" Overwritten" if recreated else " OK", QColor("green"))
                    
                    rescanFilesToRate()
                except subprocess.CalledProcessError as se:
                    self.logn(" Failed", QColor("red"))
                    print(traceback.format_exc(), flush=True)
            except ValueError as e:
                pass
            if self.cutMode:
                self.button_justrate_compress.setEnabled(True)        
                self.button_justrate_compress.setIcon(self.icon_compress)
                self.justRate=False
                self.button_justrate_compress.setFocus()
        except Exception:
            pass
        leaveTask()


    def createSnapshot(self):
        enterTask()
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
                newfilename=replaceSomeChars(self.currentFile[:self.currentFile.rindex('.')]) + "_" + frameindex + ".png"
                output=os.path.abspath(os.path.join(rfolder+"/edit", newfilename))
                out_w=self.cropWidget.sourceWidth - self.cropWidget.crop_left - self.cropWidget.crop_right
                out_h=self.cropWidget.sourceHeight - self.cropWidget.crop_top - self.cropWidget.crop_bottom
                if out_h % 2 == 1:
                    out_h -= 1
                x=self.cropWidget.crop_left
                y=self.cropWidget.crop_top
                self.log("Create snapshot "+newfilename, QColor("white"))
                cmd = "ffmpeg.exe -y -i \"" + input + "\" -vf \"select=eq(n\\," + frameindex + ")" + ","  
                cmd = cmd + "crop="+str(out_w)+":"+str(out_h)+":"+str(x)+":"+str(y) + "\" -vframes 1 -update 1 \"" + output + "\""
                print("Executing "  + cmd, flush=True)
                try:
                    recreated=os.path.exists(output)
                    cp = subprocess.run(cmd, shell=True, check=True)
                    self.logn(" Overwritten" if recreated else " OK", QColor("green"))

                    rescanFilesToRate()
                except subprocess.CalledProcessError as se:
                    self.logn(" Failed", QColor("red"))
            except ValueError as e:
                pass
            self.button_snapshot_from_video.setEnabled(False)
            self.button_justrate_compress.setEnabled(True)
            self.button_justrate_compress.setIcon(self.icon_compress)
            self.justRate=False
            self.button_justrate_compress.setFocus()
        except Exception:
            pass
        leaveTask()


    def onVideoloaded(self):
        if self.display.frame_count<0:
            self.logn("Loading video failed. Archiving forced...", QColor("red"))
            self.justRate=False
            self.rateOrArchiveAndNext()
        pass


    def closeOnError(self, msg):
        print(msg, flush=True)
        self.display.stopAndBlackout()
        self.done(QDialog.Rejected)

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
        """Lock the rating and emit a signal."""
        self.current_rating = clicked_index
        self.update_stars(clicked_index)
        self.ratingChanged.emit(clicked_index + 1)  # Emit 1-based rating

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

    def __init__(self, filepath, uid, slider, update, onVideoLoaded):
        super().__init__()
        global videoActive
        videoActive=False

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
        #print("Created thread with uid " + str(uid) , flush=True)

    def run(self):
        global videoActive
        global rememberThread
        
        if not os.path.exists(self.filepath):
            print("Failed to open", self.filepath, flush=True)
            self.onVideoLoaded()
            return
            
        self.cap = cv2.VideoCapture(self.filepath)
        if not self.cap.isOpened():
            print("Failed to open", self.filepath, flush=True)
            self.cap=None
            self.onVideoLoaded()
            return

        self.frame_count = int(self.cap.get(cv2.CAP_PROP_FRAME_COUNT))
        self.a = 0
        self.b = self.frame_count - 1
        #print("frames", self.frame_count, flush=True)
        self.fps = self.cap.get(cv2.CAP_PROP_FPS)
        #print("Started video. framecount:", self.frame_count, "fps:", self.fps, flush=True)
        
        self.slider.setMinimum(0)
        self.slider.setMaximum(self.frame_count-1)
        self.slider.setValue(0)
        if self.fps<1:
            self.fps=1
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

        self.onVideoLoaded()
        self.update(self.pause)

        self.currentFrame=-1      # before start. first frame will be number 0
        while self._run_flag:
            if not self.pause:
                if self.currentFrame+1>self.b or self.currentFrame+1<self.a:
                    self.seek(self.a)
                else:
                    ret, cv_img = self.cap.read()
                    if self._run_flag:
                        if ret and not cv_img is None:
                            self.currentFrame+=1
                            self.slider.setValue(self.currentFrame)
                            self.change_pixmap_signal.emit(cv_img, self.uid)
                            #status.showMessage('frame ...')
                        else:
                            print("Error: failed to load frame", self.currentFrame)
                            self.cap.release()
                            self.cap = cv2.VideoCapture(self.filepath)
                            self.seek(self.a)

            time.sleep(1.0/float(self.fps))
            
        self.cap.release()
        videoActive=False
        #print("Thread ends.", flush=True)
        #rememberThread=None

    def requestStop(self):
        #print("stopping thread...", flush=True)
        self._run_flag=False
        self.change_pixmap_signal.emit(np.array([]), -1)
        while videoActive:
            pass
        #print("done.", flush=True)
    
    def getFrameCount(self):
        return self.frame_count

    def getCurrentFrameIndex(self):
        return self.currentFrame
    
    def isPaused(self):
        return self.pause

    def tooglePause(self):
        self.pause = not self.pause
        #self.slider.setEnabled(self.pause)
        self.update(self.pause)


    def seek(self, frame_number):
        self.cap.set(cv2.CAP_PROP_POS_FRAMES, frame_number)  # frame_number starts with 0
        ret, cv_img = self.cap.read()
        if ret and self._run_flag:
            self.currentFrame=frame_number
            if (frame_number!=self.slider.value()):
                self.slider.setValue(self.currentFrame+1)
            self.change_pixmap_signal.emit(cv_img, self.uid)
        else:
            self._run_flag = False
                
    def sliderChanged(self):
        if self.pause:  # do not call while playback
            #print("sliderChanged. seek", self.sender().value(), flush=True)
            self.seek(self.sender().value())

    def onSliderMouseClick(self):
        if not self.pause:
            self.pause=True
            self.update(self.pause)
            #print("onSliderMouseClick. seek", self.slider.value(), flush=True)
            self.seek(self.slider.value())

    def posA(self):
        if not self.pause:
            self.pause=True
            self.update(self.pause)
        self.seek(self.a-1)
        
    def posB(self):
        if not self.pause:
            self.pause=True
            self.update(self.pause)
        self.seek(self.b-1)

    def setA(self, frame_number):
        self.a=frame_number
        if self.a>self.b:
            self.b=self.a
            
    def setB(self, frame_number):
        self.b=frame_number
        if self.b<self.a:
            self.a=self.b

    
class Display(QLabel):

    def __init__(self, pushbutton, slider, updatePaused, loaded, rectSelected):
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
        self.qt_img = None
        
        self.rubberBand = QRubberBand(QRubberBand.Line, self)
        self.origin = QPoint()
        self.selection_rect = QRect()
        
        self.closeEvent = self.stopAndBlackout
        
    def resizeEvent(self, event):
        super().resizeEvent(event)
        if self.qt_img:
            self.setPixmap(self.qt_img.scaled(event.size().width(), event.size().height(), Qt.KeepAspectRatio))
        
    def getSourcePixmap(self):
        return self.sourcePixmap
        
    def getScaledPixmap(self):
        return self.scaledPixmap
        
    def minimumSizeHint(self):
        return QSize(50, 50)

    @pyqtSlot(ndarray, int)
    def update_image(self, cv_img, uid):
        
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
            #print("original_pixmap (Display)", w, h, flush=True)
            
            self.imggeometry=self.size()
            self.setPixmap(self.qt_img.scaled(self.imggeometry.width(), self.imggeometry.height(), Qt.KeepAspectRatio))
            if self.onUpdateImage:
                if self.thread:
                    self.onUpdateImage( self.thread.getCurrentFrameIndex() )
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
        videoExtensions = ['.mp4']
        if filepath.endswith(tuple(videoExtensions)):
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
        
    def registerForUpdates(self, onUpdateImage):
        self.onUpdateImage = onUpdateImage

    def registerForFileChange(self, onUpdateFile):
        self.onUpdateFile = onUpdateFile
        
    def registerForTrimUpdate(self, onCropOrTrim):
        self.onCropOrTrim = onCropOrTrim


    def startVideo(self, uid):
        enterTask()
        try:
            if self.thread:
                self.releaseVideo()
            try:
                self.button.clicked.disconnect(self.startVideo)
            except TypeError:
                pass
            self.button.setIcon(QIcon(os.path.join(path, '../../gui/img/pause80.png')))
            self.button.setVisible(True)
            self.thread = VideoThread(self.filepath, uid, self.slider, self.updatePaused, self.onVideoLoaded)
            global rememberThread
            rememberThread=self.thread
            self.trimAFrame=0
            self.trimBFrame=-1
            self.slider.resetAB()
            self.slider.setVisible(True)
            self.thread.change_pixmap_signal.connect(self.update_image)
            self.thread.start()
            self.button.clicked.connect(self.tooglePausePressed)
        except Exception:
            pass
        leaveTask()

    def releaseVideo(self):
        if self.thread:
            t=self.thread
            self.thread=None
            self.button.clicked.disconnect(self.tooglePausePressed)
            t.change_pixmap_signal.disconnect(self.update_image)
            t.requestStop()
            self.update_image(np.array([]), -1)

    def onVideoLoaded(self):
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
            self.loaded()
        
    def updatePaused(self, isPaused):
        self.update(isPaused)

    def tooglePausePressed(self):
        if self.thread:
            self.button.setEnabled(False)
            self.thread.tooglePause()
            self.button.setEnabled(True)

    def isTrimmed(self):
        return self.trimAFrame > 0 or self.trimBFrame < self.frame_count-1
        
    def buildSliderText(self):
        ms=int( 1000.0 * float( self.trimBFrame - self.trimAFrame) / float(self.thread.fps) )
        td = timedelta(milliseconds=ms)
        text=format_timedelta_hundredth(td)
        return text

    def trimA(self):
        if self.thread:
            count=self.thread.getFrameCount()
            if count>1:
                self.slider.setA(float(self.thread.getCurrentFrameIndex())/float(count-1))
                self.trimAFrame=self.thread.getCurrentFrameIndex()
                self.thread.setA(self.thread.getCurrentFrameIndex())
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
                self.slider.setB(float(self.thread.getCurrentFrameIndex())/float(count-1))
                print("setB", float(self.thread.getCurrentFrameIndex()), float(count-1), flush=True)
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
            if event.button() == Qt.LeftButton:
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
        self.postextColor = Qt.blue
        self.textColor=Qt.white
        self.fps=-1.0
        self.frame_count=-1
        self.setMinimumHeight(42)
        self.sliderMoved.connect(self.onSliderMoved)
        self.sliderReleased.connect(self.onSliderReleased)
        self.setTracking(True)
     
    def resetAB(self):
        self.a = 0.0
        self.b = 1.0
        
    def setA(self, a):
        self.a = min(max(0.0, a), 1.0)
        self.update()

    def setB(self, b):
        self.b = min(max(0.0, b), 1.0)
        self.update()

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

    def paintEvent(self, event: QPaintEvent):

        super().paintEvent(event)

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

    def buildPosSliderText(self, sliderpos):
        ms=int( 1000.0 * sliderpos * (self.frame_count) / float(self.fps) )
        td = timedelta(milliseconds=ms)
        text=format_timedelta_hundredth(td)
        return text

    def onSliderReleased(self):
        self._setTempPositioningText(0.5, "", Qt.blue)
        
    def onSliderMoved(self, value):
        sliderpos = value / (self.maximum()+1)
        self._setTempPositioningText(sliderpos, self.buildPosSliderText(sliderpos), Qt.blue)
        
    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            val = self.pixelPosToRangeValue(event.pos())
            self.setValue(val)
            self.onSliderMouseClick()
        super(FrameSlider, self).mousePressEvent(event)

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
        self.slider_right = self.create_slider(Qt.Horizontal, True)
        self.slider_top = self.create_slider(Qt.Vertical, True)
        self.slider_bottom = self.create_slider(Qt.Vertical, False)

        # Lupen-Label
        self.magnifier = QLabel(self)
        self.magnifier.setFixedSize(self.magsize, self.magsize)
        self.magnifier.setFrameStyle(QFrame.Box)
        self.magnifier.setStyleSheet("background-color: black; border: 2px solid gray;")
        self.magnifier.hide()

 
        # Layouts
        main_layout = QGridLayout()
        iw=1000
        cw=1
        main_layout.addWidget(QLabel(),           0,     0,           cw, cw)
        main_layout.addWidget(self.slider_left,   0,     cw,          cw, iw,       alignment=Qt.AlignmentFlag.AlignBottom)

        main_layout.addWidget(self.slider_top,    cw,    0,           iw, cw,       alignment=Qt.AlignmentFlag.AlignRight)
        main_layout.addWidget(self.image_label,   cw,    cw,          iw, iw)
        main_layout.addWidget(self.slider_bottom, cw,    cw+iw,       iw, cw,       alignment=Qt.AlignmentFlag.AlignLeft)

        main_layout.addWidget(self.slider_right,  cw+iw, cw,          cw, iw,       alignment=Qt.AlignmentFlag.AlignTop)
        main_layout.addWidget(QLabel(),           cw+iw, cw+iw,       cw, cw)

        # Buttons unten
        #controls_layout = QHBoxLayout()
        #main_layout.addLayout(controls_layout, 3, 0, 1, 1002)

        self.setLayout(main_layout)

        # Signale verbinden
        self.slider_left.valueChanged.connect(lambda val: self.update_crop("left", val))
        self.slider_right.valueChanged.connect(lambda val: self.update_crop("right", val))
        self.slider_top.valueChanged.connect(lambda val: self.update_crop("top", val))
        self.slider_bottom.valueChanged.connect(lambda val: self.update_crop("bottom", val))

        # Slider deaktivieren, bis Bild geladen
        self.enable_sliders(False)

        # Hotkey STRG+S zum Speichern
        #self.save_shortcut = QShortcut(QKeySequence("Ctrl+S"), self)

    def fileChanged(self):
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

    
    def imageUpdated(self, currentFrameIndex):
       
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

        self.original_pixmap = pixmap.copy()
        w = self.original_pixmap.width()
        h = self.original_pixmap.height()
        #print("original_pixmap", w, h, flush=True)
        
        
        self.display_pixmap = pixmap.copy()
        self.image_label.setPixmap(self.display_pixmap)

        if not self.slidersInitialized:
            # Slider aktivieren und konfigurieren
            self.update_slider_ranges()
            self.enable_sliders(True)
            self.slidersInitialized = True

        self.apply_crop()

    def enable_sliders(self, enable: bool):
        """Aktiviert oder deaktiviert alle Slider."""
        self.slider_left.setEnabled(enable)
        self.slider_right.setEnabled(enable)
        self.slider_top.setEnabled(enable)
        self.slider_bottom.setEnabled(enable)

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
        else:
            slider.setStyleSheet("QSlider::handle:Vertical { background-color: black; border: 2px solid white; }")
        return slider

    def update_slider_ranges(self):
        if not self.original_pixmap:
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


    def apply_crop(self):
        if not self.original_pixmap:
            return

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

    def updateStylesheet(self):

        self.setStyleSheet(
            """
        QPushButton:pressed {
            background-color: qlineargradient(x1: 0, y1: 0, x2: 0, y2: 1, stop: 0 #000000, stop: 1 #000000);
        }
        """
        )
        
class StyledIcon(QIcon):
    def __init__(self, path):
        enabled_icon = QPixmap(path)
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
        pixm= QPixmap(path)
        h=pixm.height()
        w=pixm.width()
        y=h-1
        p.begin(pixm)
        p.setRenderHints(QPainter.RenderHint.Antialiasing, True)
        p.setPen(pen)
        p.drawLine(QPoint(0,y), QPoint(w,y))
        p.end()
        self.addPixmap( pixm, QIcon.Normal, QIcon.On)


def scanFilesToRate():
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
        filesCut = buildList(_filesWithoutEdit, None)

    if cutModeActive:
        files = filesCut
    else:
        files = filesNoCut
        
    return files

    
def rescanFilesToRate():
    #print("rescanFilesToRate", flush=True)
    global _filesWithoutEdit, _editedfiles, _readyfiles, filesNoCut, filesCut, _cutModeFolderOverrideFiles
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
        filesNoCut = buildList(_editedfiles, "edit/") + buildList(_readyfiles, "ready/") + buildList(_filesWithoutEdit, None)
        files = filesNoCut
        
    return files


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

def get_initial_file_list(base_path: str) -> List[Tuple[str, float]]:
    """
    Erstellt eine sortierte Liste mit Tupeln (Dateiname, Modifikationsdatum).
    Sortiert nach Modifikationsdatum aufsteigend (alte zuerst).
    """
    bpath = os.path.abspath(os.path.join(path, base_path))
    files = [
        (f, os.path.getmtime(os.path.join(bpath, f)))
        for f in os.listdir(bpath)
            if os.path.isfile(os.path.join(bpath, f))
    ]
    return sorted(files, key=lambda x: x[1], reverse=False)


def update_file_list(base_path: str, file_list: List[Tuple[str, float]]) -> List[Tuple[str, float]]:
    """
    Aktualisiert die bestehende Datei-Liste:
      - Entfernt nicht mehr existierende Dateien
      - Fügt neue Dateien ein (holt mtime nur für neue Dateien)
      - Behält die Sortierung bei, ohne vollständige Neusortierung
    """
    # Aktuell vorhandene Dateien NUR als Menge laden (kein mtime!)
    bpath = os.path.abspath(os.path.join(path, base_path))
    current_files = {
        f for f in os.listdir(bpath)
        if os.path.isfile(os.path.join(bpath, f))
    }

    # ---- 1. Entferne Dateien, die nicht mehr existieren ----
    existing_names_in_list = {fname for fname, _ in file_list}
    file_list[:] = [(fname, mtime) for fname, mtime in file_list if fname in current_files]

    # ---- 2. Finde neue Dateien (die noch nicht in der Liste sind) ----
    new_files = current_files - existing_names_in_list

    # ---- 3. Füge neue Dateien mit mtime ein (nur hier wird getmtime aufgerufen) ----
    for fname in new_files:
        full_path = os.path.join(bpath, fname)
        mtime = os.path.getmtime(bpath)  # Nur für neue Dateien aufrufen
        insert_sorted(file_list, (fname, mtime))

    return file_list

def insert_sorted(file_list: List[Tuple[str, float]], new_item: Tuple[str, float]):
    """
    Fügt ein neues Element (Dateiname, Modifikationsdatum) an der richtigen Stelle in eine
    absteigend sortierte Liste ein, ohne komplette Neusortierung.
    """
    times = [mtime for _, mtime in file_list]
    pos = bisect.bisect_left(times, -new_item[1])
    file_list.insert(pos, new_item)


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


# global init
cutModeActive=False
cutModeFolderOverrideActive=False
cutModeFolderOverridePath=str(Path.home())
scanFilesToRate()

