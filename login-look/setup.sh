#!/usr/bin/env bash
# setup.sh — pemasangan sekali jalan untuk login-look.
#
# Mode:
#   bash setup.sh                 pasang penuh (root): tambal QML + symlink theme.conf
#   bash setup.sh --patch-only F  tambal satu berkas QML saja (tanpa root)
#   bash setup.sh --conf-only D   jadikan D/theme.conf symlink (tanpa root)
#   bash setup.sh --uninstall     cabut semua jejak
#   bash setup.sh --purge         --uninstall + hapus skrip & data
#
# Exit: 0 sukses, 2 salah pakai, 4 pola QML tidak dikenal (tanpa menulis),
#       5 bukan root / user tidak diketahui.
set -euo pipefail

THEME_DEFAULT="/usr/share/sddm/themes/win11sddm"
PATCH_EXIT=4

usage() {
    cat <<'TXT'
setup.sh — pemasangan sekali jalan untuk login-look.

Mode:
  bash setup.sh                 pasang penuh (root): tambal QML + symlink theme.conf
  bash setup.sh --patch-only F  tambal satu berkas QML saja (tanpa root)
  bash setup.sh --conf-only D   jadikan D/theme.conf symlink (tanpa root)
  bash setup.sh --uninstall     cabut semua jejak
  bash setup.sh --purge         --uninstall + hapus skrip & data

Exit: 0 sukses, 2 salah pakai, 4 pola QML tidak dikenal (tanpa menulis),
      5 bukan root / user tidak diketahui.
TXT
}

die() { printf '%s\n' "$2" >&2; exit "$1"; }

patch_only() {
    local file="$1"
    local dry="${2:-}"
    [ -f "$file" ] || die 2 "berkas tidak ditemukan: $file"
    python3 - "$file" "$dry" <<'PY'
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
dry = sys.argv[2] == "--dry-run"

BG_OLD = ('        backgroundImage.source = backgroundImages'
          '[Math.floor(Math.random() * backgroundImages.length)];\n')
BG_NEW = (
    '        // login-look: background\n'
    '        if (config.background && String(config.background).trim() !== "") {\n'
    '            backgroundImage.source = Qt.resolvedUrl(config.background);\n'
    '        } else {\n'
    '            backgroundImage.source = backgroundImages'
    '[Math.floor(Math.random() * backgroundImages.length)];\n'
    '        }\n'
)

AV_OLD = (
    '                    function reloadAvatar() {\n'
    '                        fallbackStep = 0;\n'
    '                        source = Qt.resolvedUrl("assets/avatar.png");\n'
    '                    }\n'
)
AV_NEW = (
    '                    function reloadAvatar() {\n'
    '                        // login-look: avatar\n'
    '                        fallbackStep = 0;\n'
    '                        if (config.avatar && String(config.avatar).trim() !== "") {\n'
    '                            source = Qt.resolvedUrl(config.avatar);\n'
    '                            return;\n'
    '                        }\n'
    '                        source = Qt.resolvedUrl("assets/avatar.png");\n'
    '                    }\n'
)

FB_OLD = (
    '        function onStatusChanged() {\n'
    '            if (backgroundImage.status === Image.Ready) {\n'
    '                colorExtractor.processed = false;\n'
    '                colorDelay.start();\n'
    '            }\n'
    '        }\n'
)
FB_NEW = (
    '        function onStatusChanged() {\n'
    '            if (backgroundImage.status === Image.Ready) {\n'
    '                colorExtractor.processed = false;\n'
    '                colorDelay.start();\n'
    '            }\n'
    '            // login-look: fallback\n'
    '            if (backgroundImage.status === Image.Error) {\n'
    '                backgroundImage.source = backgroundImages'
    '[Math.floor(Math.random() * backgroundImages.length)];\n'
    '            }\n'
    '        }\n'
)

PAIRS = [
    ("login-look: background", BG_OLD, BG_NEW),
    ("login-look: avatar", AV_OLD, AV_NEW),
    ("login-look: fallback", FB_OLD, FB_NEW),
]

text = path.read_bytes().decode("utf-8")
new = text
changed = 0
errors = []
for marker, old, replacement in PAIRS:
    if marker in new:
        continue
    count = new.count(old)
    if count == 1:
        new = new.replace(old, replacement, 1)
        changed += 1
    elif count == 0:
        errors.append(
            "pola untuk '%s' tidak ditemukan di %s. Tema ini tidak dikenal; "
            "tidak ada yang ditulis." % (marker, path))
    else:
        errors.append(
            "pola untuk '%s' muncul %d kali di %s (ambigu); tidak ada yang ditulis."
            % (marker, count, path))

if errors:
    for line in errors:
        print(line, file=sys.stderr)
    print("Tambalan dibatalkan. Periksa versi tema / Main.qml.", file=sys.stderr)
    sys.exit(4)

if changed == 0:
    print("sudah bertambal, tidak ada perubahan: %s" % path)
    sys.exit(0)

if dry:
    print("akan menambal %d titik di %s" % (changed, path))
    sys.exit(0)

tmp = path.with_name(path.name + ".login-look.tmp")
tmp.write_bytes(new.encode("utf-8"))
os.chmod(tmp, path.stat().st_mode & 0o777)
os.replace(tmp, path)
print("ditambal %d titik: %s" % (changed, path))
PY
}

conf_only() {
    local theme="$1"
    [ -d "$theme" ] || die 2 "folder tema tidak ditemukan: $theme"
    local conf="$theme/theme.conf"
    [ -f "$conf" ] || [ -L "$conf" ] || die 2 "theme.conf tidak ditemukan di $theme"
    mkdir -p "$theme/assets/custom"
    local target="$theme/assets/custom/theme.conf"
    if [ -L "$conf" ]; then
        # sudah symlink: pastikan target ada dan berisi
        if [ ! -f "$target" ]; then
            die 2 "symlink theme.conf menunjuk target hilang: $(readlink "$conf")"
        fi
        echo "theme.conf sudah symlink -> $(readlink "$conf")"
        return 0
    fi
    if [ -f "$target" ]; then
        # tema dipasang ulang: theme.conf baru dari tema, target lama masih ada.
        # Simpan isi baru sebagai sumber kebenaran.
        cp -f "$conf" "$target"
    else
        mv -f "$conf" "$target"
    fi
    ( cd "$theme" && ln -sfn "assets/custom/theme.conf" theme.conf )
    chmod 644 "$target"
    chmod 755 "$theme/assets/custom" "$theme/assets"
    echo "theme.conf -> $(readlink "$theme/theme.conf")"
}

mode="install"
THEME="$THEME_DEFAULT"
USER_NAME="${SUDO_USER:-}"
ACTION_ARG=""

user_home() {
    [ -n "$USER_NAME" ] || return 1
    getent passwd "$USER_NAME" | cut -d: -f6
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die 5 "mode ini butuh root: sudo bash $0 ${*:-}"
}

install_menu_best_effort() {
    local home
    home="$(user_home)" || { echo "perhatian: user tidak diketahui, menu tidak dipasang"; return 0; }
    local cli="$home/.local/bin/login-look"
    if [ -x "$cli" ]; then
        if sudo -u "$USER_NAME" "$cli" install-menu; then
            echo "menu dipasang untuk $USER_NAME"
        else
            echo "perhatian: install-menu gagal (dijalankan manual nanti)"
        fi
    else
        echo "perhatian: $cli belum ada, menu belum dipasang"
    fi
}

remove_menu_best_effort() {
    local home
    home="$(user_home)" || { echo "perhatian: user tidak diketahui, menu tidak dibersihkan"; return 0; }
    local cli="$home/.local/bin/login-look"
    if [ -x "$cli" ]; then
        sudo -u "$USER_NAME" "$cli" remove-menu || echo "perhatian: remove-menu gagal"
    else
        echo "perhatian: $cli tidak ada, entri menu dibiarkan"
    fi
}

install_full() {
    require_root install
    [ -d "$THEME" ] || die 2 "folder tema tidak ditemukan: $THEME"
    local qml="$THEME/Main.qml"
    [ -f "$qml" ] || die 2 "Main.qml tidak ditemukan di $THEME"
    [ -e "$THEME/theme.conf" ] || die 2 "theme.conf tidak ditemukan di $THEME"
    [ -n "$USER_NAME" ] || die 5 "jalankan lewat sudo dari akun Anda (SUDO_USER kosong)"

    if ! grep -q "login-look: background" "$qml"; then
        local backup="$qml.bak-login-look-$(date +%Y%m%d-%H%M%S)"
        cp -p "$qml" "$backup"
        echo "cadangan: $backup"
    fi

    patch_only "$qml"
    conf_only "$THEME"

    local custom="$THEME/assets/custom"
    local target="$custom/theme.conf"
    chown "$USER_NAME" "$custom" "$target"
    chown "$USER_NAME" "$custom"/* 2>/dev/null || true
    chmod 755 "$custom"
    chmod 644 "$target"
    find "$custom" -type f -exec chmod 644 {} +
    chmod a+rX "$THEME" "$THEME/assets" 2>/dev/null || true

    echo
    echo "verifikasi izin:"
    if id sddm >/dev/null 2>&1; then
        if sudo -u sddm test -r "$THEME/theme.conf" && \
           sudo -u sddm test -r "$THEME/Main.qml"; then
            echo "  sddm bisa membaca tema: OK"
        else
            echo "  GAGAL: sddm tidak bisa membaca tema" >&2
            exit 6
        fi
    else
        echo "  user sddm tidak ada; pemeriksaan dilewati"
    fi

    # kunci background/avatar sengaja TIDAK ditulis di sini
    install_menu_best_effort
    echo
    echo "Selesai. Ganti wallpaper/avatar lewat: login-look-gui"
    echo "Perubahan terlihat pada greeter berikutnya (logout/reboot)."
}

restore_conf() {
    local theme="$1"
    local conf="$theme/theme.conf"
    local target="$theme/assets/custom/theme.conf"
    if [ ! -L "$conf" ]; then
        echo "theme.conf sudah file biasa"
        return 0
    fi
    if [ ! -f "$target" ]; then
        echo "perhatian: target symlink hilang, theme.conf dibiarkan" >&2
        return 0
    fi
    python3 - "$conf" "$target" <<'PY'
import os
import pathlib
import sys

conf = pathlib.Path(sys.argv[1])
target = pathlib.Path(sys.argv[2])
text = target.read_text("utf-8")
marker = "# Login-look: wallpaper & avatar pilihan user (ubah lewat login-look / menu)"
lines = text.splitlines(keepends=True)
out = []
skipping = False
for line in lines:
    if line.strip() == marker:
        skipping = True
        continue
    if skipping:
        stripped = line.strip()
        if not stripped or stripped.startswith("background=") or stripped.startswith("avatar="):
            continue
        skipping = False
    out.append(line)
tmp = conf.with_name(conf.name + ".restore.tmp")
tmp.write_text("".join(out), "utf-8")
os.chmod(tmp, 0o644)
try:
    os.chown(tmp, 0, 0)
except PermissionError:
    pass
os.replace(tmp, conf)
PY
    echo "theme.conf dikembalikan menjadi file biasa"
}

uninstall_all() {
    local purge="$1"
    require_root uninstall
    local qml="$THEME/Main.qml"
    local backup
    backup="$(ls -1t "$qml".bak-login-look-* 2>/dev/null | head -n1 || true)"

    remove_menu_best_effort
    restore_conf "$THEME"

    if [ -n "$backup" ] && [ -f "$backup" ]; then
        cp -p "$backup" "$qml"
        echo "Main.qml dipulihkan dari $(basename "$backup")"
    else
        echo "perhatian: tidak ada cadangan Main.qml; tambalan dibiarkan"
    fi

    rm -rf "$THEME/assets/custom"
    rm -f "$THEME"/Main.qml.login-look.tmp "$THEME"/theme.conf.login-look.tmp
    echo "assets/custom dihapus"

    if [ "$purge" = "1" ]; then
        local home
        if home="$(user_home)" && [ -n "$home" ]; then
            rm -f "$home/.local/bin/login-look" "$home/.local/bin/login-look-gui"
            rm -rf "$home/.local/src/login-look" "$home/.local/share/login-look"
            echo "skrip & data login-look dihapus (purge)"
        else
            echo "perhatian: home user tidak diketahui, purge dilewati" >&2
        fi
    fi
    echo
    echo "Selesai. Tema kembali ke tampilan bawaan."
}

while [ $# -gt 0 ]; do
    case "$1" in
        --patch-only) mode="patch"; ACTION_ARG="${2:-}"; shift 2 || die 2 "--patch-only butuh berkas" ;;
        --conf-only)  mode="conf";  ACTION_ARG="${2:-}"; shift 2 || die 2 "--conf-only butuh folder" ;;
        --uninstall)  mode="uninstall"; shift ;;
        --purge)      mode="purge"; shift ;;
        --theme)      THEME="${2:-}"; shift 2 || die 2 "--theme butuh folder" ;;
        --user)       USER_NAME="${2:-}"; shift 2 || die 2 "--user butuh nama" ;;
        --dry-run)    DRY="--dry-run"; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)            die 2 "opsi tidak dikenal: $1" ;;
    esac
done

case "$mode" in
    patch) patch_only "$ACTION_ARG" "${DRY:-}" ;;
    conf)  conf_only "$ACTION_ARG" ;;
    install) install_full ;;
    uninstall) uninstall_all 0 ;;
    purge) uninstall_all 1 ;;
esac
