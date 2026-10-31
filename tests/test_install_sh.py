#!/usr/bin/env python3
"""Tes install.sh — offline, tanpa root, tanpa sudo.

Setiap tes memasang HOME palsu, mirror palsu, dan stub `curl`,
lalu meng-source install.sh untuk menguji fungsinya satu per satu.
"""
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
INSTALL_SH = REPO / "install.sh"

MIRROR_FILES = {
    "login-look/login-look": "#!/usr/bin/env bash\necho cli\n",
    "login-look/login-look-gui": "#!/usr/bin/env bash\necho gui\n",
    "login-look/login_look_gui.py": "# gui module\n",
    "login-look/setup.sh": "#!/usr/bin/env bash\ntrue\n",
    "xfce/uca.xml": "<actions></actions>\n",
    "xfce/xfce4-panel.xml": "<channel name=\"xfce4-panel\"/>\n",
    "xfce/win11-start-daemon": "#!/usr/bin/env python3\n",
    "xfce/win11-start": "#!/bin/sh\ntrue\n",
    "xfce/17000000001.desktop": "[Desktop Entry]\nName=Start\n",
    "apps/wordcraft/wordcraft": "#!/usr/bin/env bash\n",
    "apps/wordcraft/wordcraft.desktop": "[Desktop Entry]\nName=Wordcraft\n",
    "apps/artcraft-launcher/artcraft-launcher": "#!/usr/bin/env bash\n",
    "apps/artcraft-launcher/artcraft-launcher.desktop": "[Desktop Entry]\nName=Artcraft\n",
    "apps/mission-center/mission-center": "#!/usr/bin/env bash\n",
    "apps/mission-center/mission-center.desktop": "[Desktop Entry]\nName=Mission\n",
}

FAKE_CURL = r"""#!/usr/bin/env bash
# Stub curl: -fsSL URL -o OUT  ->  salin dari $FAKE_MIRROR/<rel>
url=""; out=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
rel="${url#"$RAW_BASE"/}"
printf '%s\n' "$rel" >> "$CURL_LOG"
src="$FAKE_MIRROR/$rel"
[ -f "$src" ] || exit 22
[ -n "$out" ] || exit 23
mkdir -p "$(dirname "$out")"
cp "$src" "$out"
"""


class InstallShTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="installsh-test-"))
        self.home = self.tmp / "home"
        self.home.mkdir()
        self.mirror = self.tmp / "mirror"
        for rel, body in MIRROR_FILES.items():
            p = self.mirror / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(body, encoding="utf-8")
        self.fakebin = self.tmp / "fakebin"
        self.fakebin.mkdir()
        curl = self.fakebin / "curl"
        curl.write_text(FAKE_CURL, encoding="utf-8")
        curl.chmod(0o755)

        # stub pacman: anggap semua paket sudah terpasang
        pacman = self.fakebin / "pacman"
        pacman.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
        pacman.chmod(0o755)

        # stub sudo: jalankan perintah langsung (tanpa -u)
        sudo = self.fakebin / "sudo"
        sudo.write_text(
            "#!/usr/bin/env bash\n"
            'if [ "${1:-}" = "-u" ]; then shift 2; fi\n'
            'exec "$@"\n',
            encoding="utf-8")
        sudo.chmod(0o755)

        self.curl_log = self.tmp / "curl.log"
        self.curl_log.write_text("", encoding="utf-8")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    # ------------------------------------------------------------------ util
    def env(self, **extra):
        env = {
            "HOME": str(self.home),
            "PATH": "%s:%s" % (self.fakebin, os.environ["PATH"]),
            "RAW_BASE": "https://example.invalid/repo/main",
            "FAKE_MIRROR": str(self.mirror),
            "CURL_LOG": str(self.curl_log),
            "THEME_DIR": str(self.tmp / "theme"),
            "OS_RELEASE": str(self.tmp / "os-release"),
            "NO_COLOR": "1",
            "TERM": "dumb",
        }
        env.update({k: str(v) for k, v in extra.items()})
        return env

    def bash(self, snippet, expect=0, **extra):
        script = "set -euo pipefail\nsource %s\n%s\n" % (
            subprocess.list2cmdline([str(INSTALL_SH)]), snippet)
        proc = subprocess.run(
            ["bash", "--noprofile", "--norc", "-c", script],
            env=self.env(**extra), capture_output=True, text=True)
        if proc.returncode != expect:
            self.fail(
                "exit=%d (harap %d)\n--- stdout ---\n%s\n--- stderr ---\n%s"
                % (proc.returncode, expect, proc.stdout, proc.stderr))
        return proc

    # ------------------------------------------------------- A: tidak menelan log
    def test_source_tidak_menjalankan_main(self):
        proc = self.bash('echo "sourced-ok"')
        self.assertEqual(proc.stdout.strip(), "sourced-ok")
        self.assertEqual(self.curl_log.read_text(), "")

    def test_download_files_mengisi_download_dir_tanpa_stdout(self):
        """Bug A: hasil unduhan lewat variabel global, stdout tetap kosong."""
        proc = self.bash(textwrap.dedent("""
            download_files
            test -n "$DOWNLOAD_DIR"
            test -d "$DOWNLOAD_DIR"
            printf 'ispath=%s\\n' "$(case "$DOWNLOAD_DIR" in /*) echo yes;; *) echo no;; esac)"
        """))
        self.assertEqual(proc.stdout.strip(), "ispath=yes")
        self.assertNotIn("[INFO]", proc.stdout)
        self.assertNotIn("[OK]", proc.stdout)

    def test_download_files_mempertahankan_struktur_folder(self):
        """Bug B: $tmpdir/<folder>/<file> harus ada, bukan hanya basename."""
        self.bash(textwrap.dedent("""
            download_files; tmpdir="$DOWNLOAD_DIR"
            test -f "$tmpdir/apps/wordcraft/wordcraft"
            test -f "$tmpdir/apps/mission-center/mission-center.desktop"
            test -f "$tmpdir/login-look/login-look"
            test -f "$tmpdir/xfce/xfce4-panel.xml"
        """))

    # ------------------------------------------------------------ B: install_apps
    def test_install_apps_menyalin_binary_dan_desktop(self):
        self.bash(textwrap.dedent("""
            download_files; tmpdir="$DOWNLOAD_DIR"
            install_apps "$tmpdir"
            test -x "$HOME/.local/bin/wordcraft"
            test -x "$HOME/.local/bin/mission-center"
            test -f "$HOME/.local/share/applications/artcraft-launcher.desktop"
        """))

    # ------------------------------------------------------ C: tema SDDM
    def _make_theme_tarball(self):
        src = self.tmp / "pkg" / "win11sddm-main"
        (src / "components").mkdir(parents=True)
        (src / "Main.qml").write_text("// Main\n", encoding="utf-8")
        (src / "theme.conf").write_text("fontSize=11\n", encoding="utf-8")
        (src / "components" / "Clock.qml").write_text("// clock\n", encoding="utf-8")
        tar = self.mirror / "theme.tar.gz"
        subprocess.run(["tar", "-czf", str(tar), "-C", str(src.parent),
                        src.name], check=True)
        return tar

    def test_install_theme_mengekstrak_tarball(self):
        self._make_theme_tarball()
        theme = self.tmp / "theme"
        self.bash(textwrap.dedent("""
            install_theme
        """), THEME_TARBALL_URL="https://example.invalid/repo/main/theme.tar.gz",
            THEME_DIR=theme)
        self.assertTrue((theme / "Main.qml").is_file())
        self.assertTrue((theme / "components" / "Clock.qml").is_file())
        self.assertTrue((theme / "theme.conf").is_file())

    def test_install_theme_idempotent_tidak_unduh_ulang(self):
        self._make_theme_tarball()
        theme = self.tmp / "theme"
        args_theme = dict(
            THEME_TARBALL_URL="https://example.invalid/repo/main/theme.tar.gz",
            THEME_DIR=theme)
        self.bash("install_theme", **args_theme)
        first = self.curl_log.read_text().count("theme.tar.gz")
        self.bash("install_theme", **args_theme)
        second = self.curl_log.read_text().count("theme.tar.gz")
        self.assertEqual(first, 1)
        self.assertEqual(second, 1, "tema sudah ada tetapi diunduh ulang")
        self.assertTrue((theme / "Main.qml").is_file())

    # --------------------------------------------------------- D: daemon/panel
    def test_install_panel_memasang_daemon_dan_launcher(self):
        self.bash(textwrap.dedent("""
            download_files; tmpdir="$DOWNLOAD_DIR"
            install_panel "$tmpdir"
            test -x "$HOME/.local/bin/win11-start-daemon"
            test -f "$HOME/.config/xfce4/panel/launcher-22/17000000001.desktop"
            test -f "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
        """))

    def test_install_panel_idempotent_tidak_menimpa_konfigurasi_sama(self):
        self.bash(textwrap.dedent("""
            download_files; tmpdir="$DOWNLOAD_DIR"
            install_panel "$tmpdir"
            f="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
            before=$(stat -c %Y "$f")
            sleep 1
            install_panel "$tmpdir"
            after=$(stat -c %Y "$f")
            printf 'same=%s\\n' "$([ "$before" = "$after" ] && echo yes || echo no)"
        """))

    # ----------------------------------------------------------- E: deteksi distro
    def test_detect_distro_turunan_debian(self):
        (self.tmp / "os-release").write_text(
            'ID=linuxmint\nID_LIKE="ubuntu debian"\n', encoding="utf-8")
        proc = self.bash('detect_distro\nprintf "family=%s\\n" "$DISTRO_FAMILY"')
        self.assertIn("family=debian", proc.stdout)

    def test_detect_distro_arch(self):
        (self.tmp / "os-release").write_text(
            'ID=arch\nID_LIKE=\n', encoding="utf-8")
        proc = self.bash('detect_distro\nprintf "family=%s\\n" "$DISTRO_FAMILY"')
        self.assertIn("family=arch", proc.stdout)

    def test_detect_distro_tidak_dikenal_gagal(self):
        (self.tmp / "os-release").write_text('ID=fedora\n', encoding="utf-8")
        proc = self.bash('detect_distro; echo "harusnya-gagal"', expect=1)
        self.assertNotIn("harusnya-gagal", proc.stdout)

    # ------------------------------------------------------------- backup aman
    def test_backup_configs_membuat_folder_unik(self):
        (self.home / ".config" / "xfce4").mkdir(parents=True)
        (self.home / ".config" / "xfce4" / "x.xml").write_text("x", encoding="utf-8")
        proc = self.bash(textwrap.dedent("""
            backup_configs
            backup_configs
            ls -d "$HOME"/xfce-win11-backup-* | wc -l
        """))
        self.assertEqual(proc.stdout.strip(), "2")

    # ------------------------------------------------- end-to-end di sandbox
    def test_main_end_to_end_di_sandbox(self):
        """Satu putaran penuh: paket, backup, tema, login-look, apps, panel."""
        (self.tmp / "os-release").write_text("ID=arch\n", encoding="utf-8")
        self._make_theme_tarball()

        proc = self.bash("main", THEME_TARBALL_URL=(
            "https://example.invalid/repo/main/theme.tar.gz"))

        self.assertIn("PEMASANGAN SELESAI", proc.stdout)
        self.assertTrue((self.home / ".local/bin/login-look").is_file())
        self.assertTrue((self.home / ".local/bin/win11-start-daemon").is_file())
        self.assertTrue((self.home / ".local/bin/wordcraft").is_file())
        self.assertTrue((self.home / ".local/share/applications/"
                         "mission-center.desktop").is_file())
        self.assertTrue((self.tmp / "theme/Main.qml").is_file())
        self.assertTrue((self.home / ".config/xfce4/xfconf/xfce-perchannel-xml/"
                         "xfce4-panel.xml").is_file())
        backups = list(self.home.glob("xfce-win11-backup-*"))
        self.assertEqual(len(backups), 1)

    def test_main_dua_kali_tetap_berhasil_dan_tidak_menimpa_tema(self):
        (self.tmp / "os-release").write_text("ID=arch\n", encoding="utf-8")
        self._make_theme_tarball()
        theme = self.tmp / "theme"
        args = dict(
            THEME_TARBALL_URL="https://example.invalid/repo/main/theme.tar.gz",
            THEME_DIR=theme)
        self.bash("main", **args)
        (theme / "Main.qml").write_text("// sudah ditambal + kustom\n",
                                        encoding="utf-8")
        panel = (self.home / ".config/xfce4/xfconf/xfce-perchannel-xml/"
                 "xfce4-panel.xml")
        before = panel.read_text()

        self.bash("main", **args)

        self.assertEqual((theme / "Main.qml").read_text(),
                         "// sudah ditambal + kustom\n",
                         "tema milik user tertimpa pada run kedua")
        self.assertEqual(panel.read_text(), before)
        self.assertEqual(len(list(self.home.glob("xfce-win11-backup-*"))), 2)



if __name__ == "__main__":
    unittest.main(verbosity=2)
