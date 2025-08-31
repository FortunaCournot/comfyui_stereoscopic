from PyQt5.QtWidgets import QApplication, QTableWidget, QTableWidgetItem, QHeaderView, QLabel, QVBoxLayout, QWidget
from PyQt5.QtCore import QTimer, Qt
from PyQt5.QtGui import QColor, QBrush, QFont, QPixmap
import sys
import os

LOGOTIME = 3000

path = os.path.dirname(os.path.abspath(__file__))

COLNAMES = ["", "input (done)", "processing", "output"]
COLS = len(COLNAMES)


STAGES = ["caption", "scaling", "fullsbs", "interpolate", "singleloop", "dubbing/sfx", "slides", "slideshow", "watermark/encrypt", "watermark/decrypt", "concat", ]
ROWS = 1 + len(STAGES)

class SpreadsheetApp(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("VR we are - Status")
        self.setStyleSheet("background-color: black;")
        self.setGeometry(100, 100, 300, 400)
        self.move(60, 15)

        # Spreadsheet widget
        self.table = QTableWidget(ROWS, COLS)
        self.table.setStyleSheet("background-color: black; color: black; gridline-color: black")
        self.table.setShowGrid(False)
        self.table.setFrameStyle(0)
        self.table.setSelectionMode(0)

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

        # Layout
        self.layout = QVBoxLayout()
        self.setLayout(self.layout)
        self.layout.addWidget(self.logo_container)

        # Timer for switching views
        self.switch_timer = QTimer()
        self.switch_timer.timeout.connect(self.show_table)
        self.switch_timer.setSingleShot(True)
        self.switch_timer.start(LOGOTIME)  # Show logo page for 2 seconds on startup

        # Cycle timer for repeating logo page every 3 minutes
        self.cycle_timer = QTimer()
        self.cycle_timer.timeout.connect(self.show_logo_page)
        self.cycle_timer.start(180000)  # 3 minutes

        # Timer for updating table content
        self.update_timer = QTimer()
        self.update_timer.timeout.connect(self.update_table)

    def update_table(self):
        
        if not os.path.exists(os.path.join(path, "../../../../user/default/comfyui_stereoscopic/.daemonactive")):
            sys.exit(app.exec_())
            
        for r in range(ROWS):
            for c in range(COLS):
                if c==0:
                    if r==0:
                        value = ""
                    else:
                        value = STAGES[r-1]
                    item = QTableWidgetItem(value)
                    font = QFont()
                    font.setBold(True)
                    font.setItalic(True)
                    item.setFont(font)
                    item.setForeground(QBrush(QColor("lightgray")))
                    item.setBackground(QBrush(QColor("black")))
                    item.setTextAlignment(Qt.AlignLeft + Qt.AlignVCenter)
                else:
                    color = "lightgray"
                    if r==0:
                        value = COLNAMES[c]
                        color = "gray"
                    else:
                        if c==1:
                            folder =  os.path.join(path, "../../../../input/vr/" + STAGES[r-1])
                            if os.path.exists(folder):
                                onlyfiles = next(os.walk(folder))[2]
                                onlyfiles = [f for f in onlyfiles if not f.lower().endswith(".txt")]
                                count = len(onlyfiles)
                                if count>0:
                                    value = str(count)
                                else:
                                    value = ""
                                subfolder =  os.path.join(path, "../../../../input/vr/" + STAGES[r-1] + "/done")
                                if os.path.exists(subfolder):
                                    onlyfiles = next(os.walk(subfolder))[2]
                                    nocleanup = False
                                    #for f in onlyfiles:
                                    #    print ( "f=", f, flush=True)
                                    for f in onlyfiles:
                                        if ".nocleanup" == f.lower():
                                            nocleanup = True
                                    if nocleanup:
                                        onlyfiles = [f for f in onlyfiles if f.lower() != ".nocleanup"]
                                        count = len(onlyfiles)
                                        if count>0:
                                            value = value + " ( " + str(count) + ")"
                                            color = "green"
                                subfolder =  os.path.join(path, "../../../../input/vr/" + STAGES[r-1] + "/error")
                                if os.path.exists(subfolder):
                                    onlyfiles = next(os.walk(subfolder))[2]
                                    nocleanup = False
                                    #for f in onlyfiles:
                                    #    print ( "f=", f, flush=True)
                                    onlyfiles = [f for f in onlyfiles if f.lower() != ".nocleanup"]
                                    count = len(onlyfiles)
                                    if count>0:
                                        value = value + " " + str(count) + "!"
                                        color = "red"
                            else:
                                value = "?"
                                color = "red"
                        elif c==3:
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
                                    value = str(count)
                                else:
                                    value = ""
                            else:
                                value = "?"
                                color = "red"
                        elif c==2:
                            value = ""
                        else:
                            value = "?"
                            color = "red"
                    item = QTableWidgetItem(value)
                    if r==0:
                        font = QFont()
                        font.setBold(True)
                        font.setItalic(True)
                        item.setFont(font)
                    item.setForeground(QBrush(QColor(color)))
                    item.setTextAlignment(Qt.AlignHCenter + Qt.AlignVCenter)
                    item.setBackground(QBrush(QColor("black")))
                self.table.setItem(r, c, item)

    def show_table(self):
        # Replace logo page with table
        self.layout.removeWidget(self.logo_container)
        self.logo_container.setParent(None)
        self.layout.addWidget(self.table)
        self.update_table()
        self.update_timer.start(5000)

    def show_logo_page(self):
        # Switch back to logo page for 5 seconds
        self.update_timer.stop()
        self.layout.removeWidget(self.table)
        self.table.setParent(None)
        self.layout.addWidget(self.logo_container)
        self.switch_timer.start(5000)

    def process_exists(self, pid):
        return False

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
