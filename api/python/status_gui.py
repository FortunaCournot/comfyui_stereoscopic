from PyQt5.QtWidgets import QApplication, QTableWidget, QTableWidgetItem, QHeaderView, QLabel, QVBoxLayout, QWidget
from PyQt5.QtCore import QTimer, Qt
from PyQt5.QtGui import QColor, QBrush, QFont, QPixmap
import sys, random
import os

path = os.path.dirname(os.path.abspath(__file__))

ROWS = 10
COLS = 4
VALUES = ["ok", "error", "warn", "info", "idle"]

# Color mapping
def get_color(value):
    mapping = {
        "error": QColor("red"),
        "ok": QColor("green"),
        "warn": QColor("yellow"),
        "info": QColor("blue")
    }
    return mapping.get(value.lower(), QColor("lightgray"))

class SpreadsheetApp(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("VR we are - Status")
        self.setStyleSheet("background-color: black;")

        # Spreadsheet widget
        self.table = QTableWidget(ROWS, COLS)
        self.table.setStyleSheet("background-color: black;")
        self.table.setShowGrid(False)

        # Configure headers
        self.table.horizontalHeader().setVisible(True)
        self.table.verticalHeader().setVisible(True)
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
        pixmap = QPixmap(os.path.join(path, "../../docs/icon/VR1.png"))
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
        self.switch_timer.start(5000)  # Show logo page for 5 seconds on startup

        # Cycle timer for repeating logo page every 3 minutes
        self.cycle_timer = QTimer()
        self.cycle_timer.timeout.connect(self.show_logo_page)
        self.cycle_timer.start(180000)  # 3 minutes

        # Timer for updating table content
        self.update_timer = QTimer()
        self.update_timer.timeout.connect(self.update_table)

    def update_table(self):
        for r in range(ROWS):
            for c in range(COLS):
                value = random.choice(VALUES)
                item = QTableWidgetItem(value)
                item.setForeground(QBrush(get_color(value)))
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

if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = SpreadsheetApp()
    window.show()
    sys.exit(app.exec_())
