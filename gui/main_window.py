#!/usr/bin/env python3
# gui/main_window.py
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QPushButton, QLabel, QLineEdit, QSpinBox, QTextEdit,
    QFileDialog, QGroupBox, QStatusBar, QMessageBox,
    QScrollArea, QFrame, QSystemTrayIcon, QMenu
)
from PyQt6.QtCore import Qt, QThread, pyqtSignal, QUrl
from PyQt6.QtGui import QDesktopServices, QFont, QIcon, QPixmap, QPainter, QColor, QAction

from core import create_app, DEFAULT_PORT, get_local_ip, is_port_free, find_free_port


# ── Font constants ────────────────────────────────────────────────────────────
MONO        = "Cascadia Code"
SZ_TITLE    = 36
SZ_SECTION  = 24
SZ_LABEL    = 22
SZ_INPUT    = 22
SZ_BTN      = 22
SZ_BTN_LG   = 26
SZ_LOG      = 20
SZ_URL      = 21
SZ_STATUS   = 19
SZ_CARD     = 21


# ── Server thread ─────────────────────────────────────────────────────────────

class ServerThread(QThread):
    log_signal   = pyqtSignal(str)
    error_signal = pyqtSignal(str)

    def __init__(self, directory: str, host: str, port: int):
        super().__init__()
        self.directory = directory
        self.host      = host
        self.port      = port
        self._server   = None

    def run(self):
        import logging
        from werkzeug.serving import make_server
        logging.getLogger('werkzeug').setLevel(logging.WARNING)
        try:
            app = create_app(self.directory)
            self._server = make_server(self.host, self.port, app)
            self.log_signal.emit(f"[+] :{self.port}  {self.directory}")
            self._server.serve_forever()
        except OSError as e:
            self.error_signal.emit(f"Port {self.port} in use — {e}")
        except Exception as e:
            self.error_signal.emit(str(e))

    def stop(self):
        if self._server:
            try:
                self._server.shutdown()
            except Exception:
                pass
            self._server = None


# ── Per-server card widget ────────────────────────────────────────────────────

class ServerCard(QFrame):
    stopped = pyqtSignal(int)   # emits port when stopped

    def __init__(self, directory: str, port: int, local_ip: str, parent=None):
        super().__init__(parent)
        self.port      = port
        self.directory = directory
        self._thread   = ServerThread(directory, "0.0.0.0", port)
        self._thread.log_signal.connect(self._on_log)
        self._thread.error_signal.connect(self._on_error)
        self._thread.finished.connect(self._on_thread_done)

        self.setObjectName("serverCard")
        self._build_ui(local_ip)
        self._thread.start()

    def _build_ui(self, local_ip: str):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 14, 16, 14)
        layout.setSpacing(8)

        # ── top row ──
        top = QHBoxLayout()
        port_lbl = QLabel(f":{self.port}")
        port_lbl.setFont(QFont(MONO, SZ_BTN_LG, QFont.Weight.Bold))
        port_lbl.setObjectName("cardPort")

        dir_lbl = QLabel(self.directory)
        dir_lbl.setFont(QFont(MONO, SZ_CARD - 1))
        dir_lbl.setObjectName("cardDir")
        dir_lbl.setWordWrap(False)

        self.stop_btn = QPushButton("■  Stop")
        self.stop_btn.setFont(QFont(MONO, SZ_BTN))
        self.stop_btn.setObjectName("cardStopBtn")
        self.stop_btn.setMinimumWidth(140)
        self.stop_btn.setMinimumHeight(50)
        self.stop_btn.clicked.connect(self.stop_server)

        top.addWidget(port_lbl)
        top.addWidget(dir_lbl, 1)
        top.addWidget(self.stop_btn)
        layout.addLayout(top)

        # ── URLs ──
        local_url   = f"http://127.0.0.1:{self.port}"
        network_url = f"http://{local_ip}:{self.port}"
        url_lbl = QLabel(f"Local: {local_url}    Network: {network_url}")
        url_lbl.setFont(QFont(MONO, SZ_URL))
        url_lbl.setObjectName("cardUrl")

        open_btn = QPushButton("🌐  Open in Browser")
        open_btn.setFont(QFont(MONO, SZ_BTN))
        open_btn.setMinimumWidth(220)
        open_btn.setMinimumHeight(44)
        open_btn.setToolTip("Open in browser")
        open_btn.clicked.connect(lambda: QDesktopServices.openUrl(QUrl(local_url)))

        url_row = QHBoxLayout()
        url_row.addWidget(url_lbl, 1)
        url_row.addWidget(open_btn)
        layout.addLayout(url_row)

        # ── log ──
        self.log_view = QTextEdit()
        self.log_view.setReadOnly(True)
        self.log_view.setFont(QFont(MONO, SZ_LOG))
        self.log_view.setMaximumHeight(80)
        self.log_view.setObjectName("cardLog")
        layout.addWidget(self.log_view)

    def _on_log(self, msg: str):
        self.log_view.append(msg)

    def _on_error(self, msg: str):
        self.log_view.append(f"[!] {msg}")
        self.stop_btn.setEnabled(False)

    def _on_thread_done(self):
        self.stopped.emit(self.port)

    def stop_server(self):
        self.stop_btn.setEnabled(False)
        self._thread.stop()
        self._thread.wait(3000)
        self.stopped.emit(self.port)

    def cleanup(self):
        self._thread.stop()
        self._thread.wait(3000)


# ── Tray icon (simple colored circle) ────────────────────────────────────────

def _make_tray_icon(active: bool) -> QIcon:
    px = QPixmap(32, 32)
    px.fill(Qt.GlobalColor.transparent)
    p = QPainter(px)
    p.setRenderHint(QPainter.RenderHint.Antialiasing)
    color = QColor("#3dba74") if active else QColor("#7a7e94")
    p.setBrush(color)
    p.setPen(Qt.PenStyle.NoPen)
    p.drawEllipse(4, 4, 24, 24)
    p.end()
    return QIcon(px)


# ── Main Window ───────────────────────────────────────────────────────────────

class ShareForgeWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self._cards: dict[int, ServerCard] = {}   # port → card
        self._setup_ui()
        self._setup_tray()
        self._apply_dark_theme()
        self._check_port_live(DEFAULT_PORT)

    # ─── UI build ─────────────────────────────────────────────────────────

    def _setup_ui(self):
        self.setWindowTitle("share-forge  |  Forge Suite")
        self.setMinimumWidth(1300)
        self.resize(1500, 950)

        central = QWidget()
        self.setCentralWidget(central)
        root = QVBoxLayout(central)
        root.setContentsMargins(24, 24, 24, 24)
        root.setSpacing(18)

        # title
        title = QLabel("🔗  share-forge")
        title.setFont(QFont(MONO, SZ_TITLE, QFont.Weight.Bold))
        title.setObjectName("title")
        root.addWidget(title)

        # ── config group ──
        cfg_group = QGroupBox("New Server")
        cfg_group.setFont(QFont(MONO, SZ_SECTION))
        cfg = QVBoxLayout(cfg_group)
        cfg.setSpacing(14)

        # directory
        dir_row = QHBoxLayout()
        dir_lbl = QLabel("Directory:")
        dir_lbl.setFont(QFont(MONO, SZ_LABEL))
        dir_lbl.setFixedWidth(170)
        self.dir_input = QLineEdit(os.path.abspath("."))
        self.dir_input.setFont(QFont(MONO, SZ_INPUT))
        self.dir_input.setMinimumHeight(54)
        browse_btn = QPushButton("Browse…")
        browse_btn.setFont(QFont(MONO, SZ_BTN))
        browse_btn.setFixedWidth(160)
        browse_btn.setMinimumHeight(54)
        browse_btn.clicked.connect(self._browse_directory)
        dir_row.addWidget(dir_lbl)
        dir_row.addWidget(self.dir_input)
        dir_row.addWidget(browse_btn)
        cfg.addLayout(dir_row)

        # port
        port_row = QHBoxLayout()
        port_lbl = QLabel("Port:")
        port_lbl.setFont(QFont(MONO, SZ_LABEL))
        port_lbl.setFixedWidth(170)
        self.port_input = QSpinBox()
        self.port_input.setRange(1024, 65535)
        self.port_input.setValue(DEFAULT_PORT)
        self.port_input.setFixedWidth(190)
        self.port_input.setMinimumHeight(54)
        self.port_input.setFont(QFont(MONO, SZ_INPUT))
        self.port_input.valueChanged.connect(self._check_port_live)
        self.port_status_lbl = QLabel("")
        self.port_status_lbl.setFont(QFont(MONO, SZ_LABEL - 1))
        self.port_status_lbl.setObjectName("portStatus")
        port_row.addWidget(port_lbl)
        port_row.addWidget(self.port_input)
        port_row.addWidget(self.port_status_lbl)
        port_row.addStretch()
        cfg.addLayout(port_row)

        root.addWidget(cfg_group)

        # ── start button ──
        self.start_btn = QPushButton("▶  Start Server")
        self.start_btn.setMinimumHeight(72)
        self.start_btn.setFont(QFont(MONO, SZ_BTN_LG, QFont.Weight.Bold))
        self.start_btn.setObjectName("startBtn")
        self.start_btn.clicked.connect(self._start_server)
        root.addWidget(self.start_btn)

        # ── active servers ──
        servers_lbl = QLabel("Active Servers")
        servers_lbl.setFont(QFont(MONO, SZ_SECTION, QFont.Weight.Bold))
        servers_lbl.setObjectName("sectionLbl")
        root.addWidget(servers_lbl)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        scroll.setMinimumHeight(260)

        self._cards_widget = QWidget()
        self._cards_layout = QVBoxLayout(self._cards_widget)
        self._cards_layout.setContentsMargins(0, 0, 0, 0)
        self._cards_layout.setSpacing(10)
        self._cards_layout.addStretch()

        self._empty_lbl = QLabel("No active servers")
        self._empty_lbl.setFont(QFont(MONO, SZ_LABEL))
        self._empty_lbl.setObjectName("emptyLbl")
        self._empty_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._cards_layout.insertWidget(0, self._empty_lbl)

        scroll.setWidget(self._cards_widget)
        root.addWidget(scroll, 1)

        # status bar
        self.status_bar = QStatusBar()
        self.status_bar.setFont(QFont(MONO, SZ_STATUS))
        self.setStatusBar(self.status_bar)
        self.status_bar.showMessage("No active servers")

    # ─── Tray ─────────────────────────────────────────────────────────────

    def _setup_tray(self):
        self._tray = QSystemTrayIcon(self)
        self._tray.setIcon(_make_tray_icon(False))
        self._tray.setToolTip("share-forge — no active servers")
        self._tray.activated.connect(self._tray_activated)

        menu = QMenu()
        menu.setStyleSheet("""
            QMenu { background: #1a1d27; color: #e2e4ef; font-size: 15px;
                    border: 1px solid #2a2d3a; padding: 4px; }
            QMenu::item { padding: 8px 20px; }
            QMenu::item:selected { background: #22253a; }
        """)
        self._show_action  = QAction("Show Window", self)
        self._stop_action  = QAction("Stop All Servers", self)
        self._quit_action  = QAction("Quit", self)

        self._show_action.triggered.connect(self._show_window)
        self._stop_action.triggered.connect(self._stop_all)
        self._quit_action.triggered.connect(self._quit_app)

        menu.addAction(self._show_action)
        menu.addAction(self._stop_action)
        menu.addSeparator()
        menu.addAction(self._quit_action)
        self._tray.setContextMenu(menu)
        self._tray.show()

    def _tray_activated(self, reason):
        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            self._show_window()

    def _show_window(self):
        self.showNormal()
        self.raise_()
        self.activateWindow()

    # ─── Theme ────────────────────────────────────────────────────────────

    def _apply_dark_theme(self):
        self.setStyleSheet("""
            QMainWindow, QWidget { background-color: #0f1117; color: #e2e4ef; }
            QScrollArea { background: transparent; }
            QScrollArea > QWidget > QWidget { background: transparent; }

            QLabel { color: #e2e4ef; }
            QLabel#title   { color: #5c8aff; font-size: 36px; }
            QLabel#sectionLbl { color: #9aa0c0; font-size: 24px; }
            QLabel#emptyLbl   { color: #3a3d4a; font-size: 22px; padding: 30px; }
            QLabel#portStatus { font-size: 21px; }

            QGroupBox {
                color: #7a7e94; font-size: 22px; border: 1px solid #2a2d3a;
                border-radius: 8px; margin-top: 12px; padding-top: 12px;
            }
            QGroupBox::title { subcontrol-origin: margin; left: 14px; padding: 0 6px; }

            QLineEdit, QSpinBox {
                background: #1a1d27; color: #e2e4ef; border: 1px solid #2a2d3a;
                border-radius: 6px; padding: 8px 12px; font-size: 22px;
            }
            QLineEdit:focus, QSpinBox:focus { border-color: #5c8aff; }

            QPushButton {
                background: #1a1d27; color: #e2e4ef; border: 1px solid #2a2d3a;
                border-radius: 8px; padding: 8px 16px; font-size: 22px;
            }
            QPushButton:hover  { background: #22253a; border-color: #5c8aff; }
            QPushButton:disabled { color: #3a3d4a; border-color: #1a1d27; }

            QPushButton#startBtn {
                background: #1a3a1f; color: #3dba74;
                border: 1px solid #2a6a40; font-size: 26px;
            }
            QPushButton#startBtn:hover { background: #1f4a26; }

            /* Server cards */
            QFrame#serverCard {
                background: #1a1d27; border: 1px solid #2a2d3a; border-radius: 10px;
            }
            QLabel#cardPort { color: #5c8aff; font-size: 26px; }
            QLabel#cardDir  { color: #9aa0c0; font-size: 20px; }
            QLabel#cardUrl  { color: #3dba74; font-size: 21px; }
            QTextEdit#cardLog {
                background: #0a0c12; color: #7a8090; border: 1px solid #1a1d27;
                border-radius: 4px; font-size: 20px;
            }
            QPushButton#cardStopBtn {
                background: #3a1a1a; color: #e05c5c;
                border: 1px solid #6a2a2a; font-size: 22px;
            }
            QPushButton#cardStopBtn:hover  { background: #4a2020; }
            QPushButton#cardStopBtn:disabled { color: #3a3d4a; }

            QStatusBar { color: #7a7e94; background: #0a0c12; font-size: 19px; }
            QSpinBox::up-button, QSpinBox::down-button { background: #2a2d3a; border: none; width: 22px; }
            QScrollBar:vertical {
                background: #0f1117; width: 8px; margin: 0;
            }
            QScrollBar::handle:vertical { background: #2a2d3a; border-radius: 4px; min-height: 30px; }
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }
        """)

    # ─── Port check ───────────────────────────────────────────────────────

    def _check_port_live(self, port: int):
        if port in self._cards:
            self.port_status_lbl.setText("✖ already serving")
            self.port_status_lbl.setStyleSheet("color: #e05c5c;")
        elif is_port_free(port):
            self.port_status_lbl.setText("✔ free")
            self.port_status_lbl.setStyleSheet("color: #3dba74;")
        else:
            suggested = find_free_port(port + 1)
            self.port_status_lbl.setText(f"✖ in use → try {suggested}")
            self.port_status_lbl.setStyleSheet("color: #e05c5c;")

    # ─── Server management ────────────────────────────────────────────────

    def _browse_directory(self):
        d = QFileDialog.getExistingDirectory(self, "Select Directory", self.dir_input.text())
        if d:
            self.dir_input.setText(d)

    def _start_server(self):
        directory = self.dir_input.text().strip()
        if not os.path.isdir(directory):
            self._show_error("Invalid directory.")
            return

        port = self.port_input.value()

        if port in self._cards:
            self._show_error(f"Port {port} is already serving.")
            return

        if not is_port_free(port):
            suggested = find_free_port(port + 1)
            dlg = QMessageBox(self)
            dlg.setWindowTitle("Port In Use")
            dlg.setText(f"Port <b>{port}</b> is already in use.")
            dlg.setInformativeText(f"Use port <b>{suggested}</b> instead?")
            dlg.setStandardButtons(
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel
            )
            dlg.setDefaultButton(QMessageBox.StandardButton.Yes)
            dlg.setStyleSheet("""
                QMessageBox { background: #1a1d27; color: #e2e4ef; }
                QLabel { color: #e2e4ef; font-size: 16px; }
                QPushButton {
                    background: #1a3a1f; color: #3dba74; border: 1px solid #2a6a40;
                    border-radius: 6px; padding: 8px 24px; font-size: 16px;
                }
            """)
            if dlg.exec() == QMessageBox.StandardButton.Yes:
                port = suggested
                self.port_input.setValue(port)
            else:
                return

        local_ip = get_local_ip()
        card = ServerCard(directory, port, local_ip, self)
        card.stopped.connect(self._on_card_stopped)
        self._cards[port] = card

        # insert before the stretch
        idx = self._cards_layout.count() - 1
        self._cards_layout.insertWidget(idx, card)
        self._empty_lbl.setVisible(False)

        self._update_status()
        # suggest next free port
        self.port_input.setValue(find_free_port(port + 1))

    def _on_card_stopped(self, port: int):
        card = self._cards.pop(port, None)
        if card:
            self._cards_layout.removeWidget(card)
            card.deleteLater()
        self._empty_lbl.setVisible(len(self._cards) == 0)
        self._update_status()
        self._check_port_live(self.port_input.value())

    def _stop_all(self):
        for port, card in list(self._cards.items()):
            card.cleanup()
        self._cards.clear()
        # remove all card widgets
        for i in reversed(range(self._cards_layout.count())):
            w = self._cards_layout.itemAt(i).widget()
            if w and w is not self._empty_lbl:
                self._cards_layout.removeWidget(w)
                w.deleteLater()
        self._empty_lbl.setVisible(True)
        self._update_status()

    def _update_status(self):
        n = len(self._cards)
        if n == 0:
            msg = "No active servers"
            self._tray.setIcon(_make_tray_icon(False))
            self._tray.setToolTip("share-forge — no active servers")
        else:
            ports = ", ".join(f":{p}" for p in sorted(self._cards))
            msg = f"{n} server{'s' if n > 1 else ''} running: {ports}"
            self._tray.setIcon(_make_tray_icon(True))
            self._tray.setToolTip(f"share-forge — {msg}")
        self.status_bar.showMessage(msg)
        self._stop_action.setEnabled(n > 0)

    # ─── Window close ─────────────────────────────────────────────────────

    def closeEvent(self, event):
        if self._cards:
            # hide to tray instead of closing
            event.ignore()
            self.hide()
            self._tray.showMessage(
                "share-forge",
                f"{len(self._cards)} server(s) still running. Right-click tray to stop.",
                QSystemTrayIcon.MessageIcon.Information,
                3000
            )
        else:
            self._quit_app()

    def _quit_app(self):
        self._stop_all()
        self._tray.hide()
        QApplication.quit()

    # ─── Helpers ──────────────────────────────────────────────────────────

    def _show_error(self, msg: str):
        dlg = QMessageBox(self)
        dlg.setWindowTitle("Error")
        dlg.setText(msg)
        dlg.setStyleSheet("""
            QMessageBox { background: #1a1d27; }
            QLabel { color: #e05c5c; font-size: 16px; }
            QPushButton { background: #3a1a1a; color: #e05c5c; border: 1px solid #6a2a2a;
                          border-radius: 6px; padding: 8px 20px; font-size: 16px; }
        """)
        dlg.exec()


def run_gui():
    app = QApplication(sys.argv)
    app.setApplicationName("share-forge")
    app.setQuitOnLastWindowClosed(False)   # keep alive in tray
    window = ShareForgeWindow()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    run_gui()
