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

           

