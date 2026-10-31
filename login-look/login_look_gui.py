#!/usr/bin/env python3
"""login-look-gui — GUI PyQt6 untuk mengubah wallpaper & avatar layar login SDDM.

Hanya membungkus CLI login-look (subprocess). Semua logika inti ada di
login-look; GUI ini hanya antarmuka pengguna.

Dijalankan: login-look-gui
"""
import json
import os
import pathlib
import shutil
import subprocess
import sys

from PyQt6.QtCore import Qt, QSize, QTimer
from PyQt6.QtGui import QPixmap
from PyQt6.QtWidgets import (
    QApplication, QFileDialog, QFrame, QGroupBox, QHBoxLayout, QLabel,
    QMainWindow, QMessageBox, QPushButton, QVBoxLayout, QWidget,
)

# selamatkan jika PyQt6 tidak tersedia saat di-import sebagai modul
try:
    from PyQt6.QtCore import QSize as _QSize  # noqa: F401
except Exception:  # pragma: no cover
    pass

CLI = "login-look"
PREVIEW_SIZE = QSize(260, 160)  # ukuran thumbnail preview di GUI


def _which_cli():
    """Cari berkas executable login-look di PATH."""
    return shutil.which(CLI) or CLI


class LoginLookController:
    """Logika bisnis: memanggil CLI login-look via subprocess.

    Semua method dapat di-mock dalam tes tanpa memerlukan display.
    """

    def __init__(self, theme_dir=None):
        self._theme_dir_arg = theme_dir

    def _run(self, *args):
        """Jalankan `login-look <args>`; kembalikan (returncode, stdout, stderr)."""
        cli = _which_cli()
        proc = subprocess.run(
            [cli, *args], capture_output=True, text=True)
        return proc.returncode, proc.stdout, proc.stderr

    def get_status(self):
        """Ambil status tema dalam bentuk dict."""
        rc, out, err = self._run("status", "--json")
        if rc != 0:
            raise RuntimeError(err.strip() or "gagal membaca status tema")
        try:
            return json.loads(out)
        except json.JSONDecodeError:
            raise RuntimeError("status tema tidak dapat diuraikan: %s" % out)

    def theme_dir(self):
        """Kembalikan path folder tema."""
        rc, out, err = self._run("theme-dir")
        if rc != 0:
            raise RuntimeError(err.strip() or "gagal menentukan folder tema")
        return out.strip()

    def set_wallpaper(self, path):
        """Ganti wallpaper layar login."""
        return self._run("bg", str(path))

    def set_avatar(self, path):
        """Ganti avatar layar login."""
        return self._run("avatar", str(path))

    def reset(self, what):
        """Kembalikan ke bawaan: bg, avatar, atau all."""
        return self._run("reset", what)

    def preview(self, state="lock", out=None):
        """Pratinjau greeter; kembalikan (rc, stdout, stderr)."""
        args = ["preview", "--state", state]
        if out:
            args += ["--out", str(out)]
        return self._run(*args)


class ImagePreview(QLabel):
    """Label yang menampilkan thumbnail gambar, dengan placeholder jika kosong."""

    def __init__(self, title, parent=None):
        super().__init__(parent)
        self.setFixedSize(PREVIEW_SIZE)
        self.setFrameShape(QFrame.Shape.StyledPanel)
        self.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.setStyleSheet(
            "QLabel { background: #2b2b2b; color: #bbbbbb; "
            "border: 1px solid #555555; border-radius: 6px; }")
        self._set_placeholder(title)

    def _set_placeholder(self, title):
        self.setText("%s\n(belum ada)\npreview" % title)
        self._pixmap = None

    def set_image(self, path):
        """Tampilkan gambar sebagai thumbnail, atau placeholder jika gagal."""
        path = pathlib.Path(path)
        if not path.is_file():
            self._set_placeholder(path.name)
            return False
        pix = QPixmap(str(path))
        if pix.isNull():
            self._set_placeholder(path.name)
            return False
        self._pixmap = pix.scaled(
            PREVIEW_SIZE, Qt.AspectRatioMode.KeepAspectRatio,
            Qt.TransformationMode.SmoothTransformation)
        self.setPixmap(self._pixmap)
        self.setText("")
        return True

    def clear(self):
        self._set_placeholder("kosong")


class Card(QGroupBox):
    """Kartu untuk satu aset (wallpaper atau avatar)."""

    def __init__(self, title, kind, controller, parent=None):
        super().__init__(title, parent)
        self.kind = kind  # "wallpaper" atau "avatar"
        self.controller = controller
        self._build_ui()

    def _build_ui(self):
        layout = QVBoxLayout(self)

        # baris preview + aksi samping
        top = QHBoxLayout()
        self.preview = ImagePreview(self.kind.title(), self)
        top.addWidget(self.preview)

        actions = QVBoxLayout()
        self.btn_choose = QPushButton("Pilih file…")
        self.btn_preview = QPushButton("Pratinjau layar")
        self.btn_reset = QPushButton("Kembalikan ke bawaan")
        for btn in (self.btn_choose, self.btn_preview, self.btn_reset):
            btn.setMinimumHeight(30)
            actions.addWidget(btn)
        actions.addStretch()
        top.addLayout(actions)
        layout.addLayout(top)

        # status label
        self.status_label = QLabel("memuat status…")
        self.status_label.setStyleSheet(
            "QLabel { color: #888888; font-size: 11px; }")
        layout.addWidget(self.status_label)

        # sinyal
        self.btn_choose.clicked.connect(self._on_choose)
        self.btn_preview.clicked.connect(self._on_preview)
        self.btn_reset.clicked.connect(self._on_reset)

    def _on_choose(self):
        filters = ("Gambar (*.png *.jpg *.jpeg *.bmp *.tif *.tiff *.webp)")
        path, _ = QFileDialog.getOpenFileName(
            self, "Pilih gambar %s" % self.kind, "", filters)
        if not path:
            return
        self._apply(path)

    def _apply(self, path):
        kind = self.kind
        try:
            if kind == "wallpaper":
                rc, out, err = self.controller.set_wallpaper(path)
            else:
                rc, out, err = self.controller.set_avatar(path)
        except FileNotFoundError:
            self.window()._show_error(
                "login-look tidak ditemukan di PATH. Pasang dulu lewat setup.sh.")
            return
        if rc == 0:
            self.preview.set_image(path)
            rel = out.strip().splitlines()[-1] if out.strip() else path
            self.status_label.setText("terpasang: %s" % rel)
            self.window()._show_info("Berhasil: %s layar login diubah." %
                                     kind.title())
        else:
            self.status_label.setText("gagal (exit %d)" % rc)
            self.window()._show_error(err.strip() or "gagal mengubah %s" % kind)

    def _on_preview(self):
        try:
            rc, out, err = self.controller.preview("lock")
        except FileNotFoundError:
            self.window()._show_error(
                "login-look tidak ditemukan di PATH.")
            return
        if rc == 0:
            self.window()._show_info("Pratinjau tersimpan: %s" % out.strip())
        else:
            self.window()._show_error(err.strip() or "pratinjau gagal")

    def _on_reset(self):
        try:
            rc, out, err = self.controller.reset(self.kind)
        except FileNotFoundError:
            self.window()._show_error(
                "login-look tidak ditemukan di PATH.")
            return
        if rc == 0:
            self.preview.clear()
            self.status_label.setText("dikembalikan ke bawaan")
            self.window()._show_info("Berhasil: %s dikembalikan ke bawaan." %
                                     self.kind.title())
        else:
            self.status_label.setText("reset gagal (exit %d)" % rc)
            self.window()._show_error(err.strip() or "gagal me-reset %s" %
                                      self.kind)

    def refresh(self, status):
        """Update label status dari dict status tema."""
        key = "background" if self.kind == "wallpaper" else "avatar"
        exists_key = key + "_exists"
        rel = status.get(key) or None
        if rel and status.get(exists_key):
            self.preview.set_image(
                pathlib.Path(status["theme_dir"]) / rel)
            self.status_label.setText("terpasang: %s" % rel)
        else:
            self.preview.clear()
            self.status_label.setText(
                "(bawaan)" if self.kind == "wallpaper" else "(bawaan tema)")


class LoginLookWindow(QMainWindow):
    """Jendela utama GUI login-look-gui."""

    def __init__(self, controller=None):
        super().__init__()
        self.controller = controller or LoginLookController()
        self.wallpaper_card = None
        self.avatar_card = None
        self.banner = None
        self.setWindowTitle("Pengaturan Layar Login — login-look")
        self.resize(700, 420)
        self._build_ui()
        QTimer.singleShot(100, self._refresh_status)

    def _build_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        root = QVBoxLayout(central)

        # kartu wallpaper + avatar berdampingan
        cards = QHBoxLayout()
        self.wallpaper_card = Card("Wallpaper layar login", "wallpaper",
                                   self.controller, self)
        self.avatar_card = Card("Avatar layar login", "avatar",
                                self.controller, self)
        cards.addWidget(self.wallpaper_card)
        cards.addWidget(self.avatar_card)
        root.addLayout(cards, stretch=1)

        # status banner
        self.banner = QLabel("siap")
        self.banner.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.banner.setStyleSheet(
            "QLabel { background: #e8f4ea; color: #1b5e20; "
            "border: 1px solid #81c784; border-radius: 4px; "
            "padding: 6px; font-size: 12px; }")
        root.addWidget(self.banner)

        # tombol muat ulang status
        btn_reload = QPushButton("Muat ulang status")
        btn_reload.setMinimumHeight(32)
        btn_reload.clicked.connect(self._refresh_status)
        root.addWidget(btn_reload)

    def _refresh_status(self):
        try:
            st = self.controller.get_status()
        except RuntimeError as exc:
            self._show_error(str(exc))
            return
        self.wallpaper_card.refresh(st)
        self.avatar_card.refresh(st)

    def _show_info(self, text):
        self._show_banner(text, error=False)

    def _show_error(self, text):
        self._show_banner(text, error=True)

    def _show_banner(self, text, error=False):
        self.banner.setText(text)
        if error:
            self.banner.setStyleSheet(
                "QLabel { background: #fdecea; color: #b71c1c; "
                "border: 1px solid #e57373; border-radius: 4px; "
                "padding: 6px; font-size: 12px; }")
        else:
            self.banner.setStyleSheet(
                "QLabel { background: #e8f4ea; color: #1b5e20; "
                "border: 1px solid #81c784; border-radius: 4px; "
                "padding: 6px; font-size: 12px; }")


def main(argv=None):
    app = QApplication.instance() or QApplication(argv or sys.argv)
    ctrl = LoginLookController()
    win = LoginLookWindow(controller=ctrl)
    win.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
