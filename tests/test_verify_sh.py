#!/usr/bin/env python3
"""Tes verify.sh — offline, tanpa root, menggunakan stub curl."""
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
VERIFY = REPO / "verify.sh"

FAKE_CURL = r"""#!/usr/bin/env bash
url=""; out=""; wfmt=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -w) wfmt="$2"; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
rel="${url#"$RAW_BASE"/}"
src="$FAKE_MIRROR/$rel"
exists=0
[ -f "$src" ] && exists=1
if [ -n "$wfmt" ]; then
  if [ "$exists" = 1 ]; then printf '200'; else printf '404'; fi
  exit 0
fi
[ "$exists" = 1 ] || exit 22
[ -n "$out" ] || exit 23
mkdir -p "$(dirname "$out")"
cp "$src" "$out"
"""


class VerifyShTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="verify-test-"))
        self.mirror = self.tmp / "mirror"
        shutil.copytree(REPO, self.mirror,
                        ignore=shutil.ignore_patterns(".git", "__pycache__"))
        # arsip tema palsu (valid, berisi Main.qml + theme.conf)
        pkg = self.tmp / "pkg" / "win11sddm-main"
        pkg.mkdir(parents=True)
        (pkg / "Main.qml").write_text("// Main\n", encoding="utf-8")
        (pkg / "theme.conf").write_text("fontSize=11\n", encoding="utf-8")
        subprocess.run(
            ["tar", "-czf", str(self.mirror / "theme.tar.gz"),
             "-C", str(pkg.parent), pkg.name], check=True)
        self.fakebin = self.tmp / "fakebin"
        self.fakebin.mkdir()
        curl = self.fakebin / "curl"
        curl.write_text(FAKE_CURL, encoding="utf-8")
        curl.chmod(0o755)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_verify(self, *args, expect=None, cwd=None, fake_curl=True):
        env = dict(os.environ)
        env.update({
            "RAW_BASE": "https://example.invalid/repo/main",
            "THEME_TARBALL_URL": "https://example.invalid/repo/main/theme.tar.gz",
            "FAKE_MIRROR": str(self.mirror),
            "NO_COLOR": "1",
            "TERM": "dumb",
        })
        if fake_curl:
            env["PATH"] = "%s:%s" % (self.fakebin, env["PATH"])
        proc = subprocess.run(
            ["bash", str(VERIFY), *args],
            env=env, capture_output=True, text=True,
            cwd=str(cwd or self.tmp))
        if expect is not None:
            self.assertEqual(
                proc.returncode, expect,
                "exit=%d (harap %d)\n--- stdout ---\n%s\n--- stderr ---\n%s"
                % (proc.returncode, expect, proc.stdout, proc.stderr))
        return proc

    # ---------------------------------------------------------------- bantuan
    def test_help_exit_nol(self):
        proc = self.run_verify("--help", expect=0, fake_curl=False)
        self.assertIn("verify.sh", proc.stdout)

    # ------------------------------------------------------------- mode lokal
    def test_local_lulus(self):
        proc = self.run_verify("--local", str(self.mirror), expect=0)
        self.assertIn("LULUS", proc.stdout)

    def test_local_mendeteksi_berkas_hilang(self):
        (self.mirror / "xfce/win11-start").unlink()
        proc = self.run_verify("--local", str(self.mirror), expect=1)
        self.assertIn("xfce/win11-start", proc.stdout)
        self.assertIn("GAGAL", proc.stdout)

    def test_local_mendeteksi_sintaks_rusak(self):
        (self.mirror / "login-look/setup.sh").write_text(
            "#!/usr/bin/env bash\nif then fi\n", encoding="utf-8")
        proc = self.run_verify("--local", str(self.mirror), expect=1)
        self.assertIn("setup.sh", proc.stdout)

    # ------------------------------------------------------------ mode remote
    def test_remote_lulus(self):
        proc = self.run_verify(expect=0)
        self.assertIn("LULUS", proc.stdout)
        self.assertIn("theme.tar.gz", proc.stdout)

    def test_remote_mendeteksi_404(self):
        (self.mirror / "apps/mission-center/mission-center").unlink()
        proc = self.run_verify(expect=1)
        self.assertIn("apps/mission-center/mission-center", proc.stdout)
        self.assertIn("404", proc.stdout)

    def test_remote_mendeteksi_crlf(self):
        p = self.mirror / "login-look/setup.sh"
        data = p.read_bytes().replace(b"\n", b"\r\n")
        p.write_bytes(data)
        proc = self.run_verify(expect=1)
        self.assertIn("CRLF", proc.stdout)

    def test_remote_mengikuti_daftar_dari_install_sh(self):
        """Daftar berkas diambil dari install.sh, bukan hardcode di verify.sh."""
        p = self.mirror / "install.sh"
        text = p.read_text(encoding="utf-8")
        marker = '        "xfce/win11-start"\n'
        self.assertIn(marker, text)
        p.write_text(text.replace(marker, marker + '        "xfce/tidak-ada.xml"\n'),
                     encoding="utf-8")
        proc = self.run_verify(expect=1)
        self.assertIn("xfce/tidak-ada.xml", proc.stdout)

    def test_remote_tema_besar_tidak_terpotong_sigpipe(self):
        """Regresi: `tar -tzf | grep -q` bisa mati SIGPIPE & dilaporkan gagal."""
        pkg = self.tmp / "big" / "win11sddm-main"
        pkg.mkdir(parents=True)
        (pkg / "Main.qml").write_text("// Main\n", encoding="utf-8")
        (pkg / "theme.conf").write_text("fontSize=11\n", encoding="utf-8")
        for i in range(3000):
            (pkg / ("assets-%04d-dengan-nama-panjang-sekali.png" % i)).write_text(
                "x", encoding="utf-8")
        subprocess.run(
            ["tar", "--sort=name", "-czf", str(self.mirror / "theme.tar.gz"),
             "-C", str(pkg.parent), pkg.name], check=True)

        proc = self.run_verify(expect=0)
        self.assertIn("theme.tar.gz berisi Main.qml", proc.stdout)
        self.assertIn("LULUS", proc.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
