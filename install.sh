#!/usr/bin/env bash
# =============================================================================
# install.sh — Pemasang satu baris untuk Desktop XFCE Win11 + login-look
#
# Pemakaian:
#   curl -fsSL https://raw.githubusercontent.com/fajricoding2/desktop_enviroimentwin11/main/install.sh | bash
#
# Pilihan:
#   bash install.sh --help        tampilkan bantuan
#
# Didukung: Arch Linux, Debian (dan turunan seperti Ubuntu/Mint/Pop!_OS)
#
# Sifat:
#   - Idempotent: aman dijalankan berulang; yang sudah terpasang dilewati.
#   - Selalu membuat cadangan bertimestamp sebelum menimpa konfigurasi.
#   - Bisa diuji tanpa root: source berkas ini, lalu panggil fungsinya.
# =============================================================================
set -euo pipefail

# Hindari prompt interaktif saat memasang paket di Debian/Ubuntu
export DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# Konfigurasi repo GitHub
# -----------------------------------------------------------------------------
GITHUB_USER="${GITHUB_USER:-fajricoding2}"
GITHUB_REPO="${GITHUB_REPO:-desktop_enviroimentwin11}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}}"

# Tema SDDM Win11 (MIT, upstream abhinand128/win11sddm).
# Dipatok ke commit tertentu agar hasilnya dapat direproduksi.
THEME_SHA="${THEME_SHA:-d10502f278bf43ed8d24c73df3deef28db0264c7}"
THEME_TARBALL_URL="${THEME_TARBALL_URL:-https://github.com/abhinand128/win11sddm/archive/${THEME_SHA}.tar.gz}"
THEME_DIR="${THEME_DIR:-/usr/share/sddm/themes/win11sddm}"
OS_RELEASE="${OS_RELEASE:-/etc/os-release}"

# Variabel global yang diisi fungsi (bukan lewat stdout)
SUDO_CMD="${SUDO_CMD:-}"
DOWNLOAD_DIR=""
BACKUP_DIR=""

# -----------------------------------------------------------------------------
# Warna & log (selalu ke stderr agar stdout tetap bersih)
# -----------------------------------------------------------------------------
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
    RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BLUE=$'\e[34m'; RESET=$'\e[0m'
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi

info() { printf '%s[INFO]%s  %s\n' "$BLUE" "$RESET" "$*" >&2; }
ok()   { printf '%s[OK]%s    %s\n' "$GREEN" "$RESET" "$*" >&2; }
warn() { printf '%s[WARN]%s  %s\n' "$YELLOW" "$RESET" "$*" >&2; }
err()  { printf '%s[ERR]%s   %s\n' "$RED" "$RESET" "$*" >&2; }

usage() {
    cat <<'TXT'
install.sh — pemasang Desktop XFCE Win11 + login-look (Arch / Debian)

  bash install.sh            pasang semuanya (butuh sudo untuk paket & tema)
  bash install.sh --help     tampilkan bantuan ini

Override lewat variabel lingkungan:
  GITHUB_USER, GITHUB_REPO, GITHUB_BRANCH   sumber berkas (default: repo ini)
  THEME_DIR                                  folder tema SDDM
  THEME_TARBALL_URL                          sumber tema (dipatok ke commit)
  RAW_BASE                                   basis URL mentah

Contoh:
  GITHUB_BRANCH=dev bash install.sh
TXT
}

# -----------------------------------------------------------------------------
# Deteksi distribusi
# -----------------------------------------------------------------------------
detect_distro() {
    if [ ! -f "$OS_RELEASE" ]; then
        err "Tidak dapat mendeteksi distribusi ($OS_RELEASE tidak ada)"
        exit 1
    fi
    # shellcheck disable=SC1090
    . "$OS_RELEASE"
    DISTRO="${ID:-tidak-dikenal}"
    DISTRO_LIKE="${ID_LIKE:-}"
    case "$DISTRO $DISTRO_LIKE" in
        *arch*)                          DISTRO_FAMILY="arch" ;;
        *debian*|*ubuntu*)               DISTRO_FAMILY="debian" ;;
        *)
            err "Distribusi tidak didukung: $DISTRO (ID_LIKE='$DISTRO_LIKE')"
            err "Yang didukung: Arch Linux, Debian, dan turunannya."
            exit 1
            ;;
    esac
    info "Distribusi: $DISTRO (keluarga: $DISTRO_FAMILY)"
}

# -----------------------------------------------------------------------------
# Deteksi sudo / root
# -----------------------------------------------------------------------------
detect_privilege() {
    if [ "$(id -u)" -eq 0 ]; then
        SUDO_CMD=""
        info "Menjalankan sebagai root"
    elif command -v sudo >/dev/null 2>&1; then
        SUDO_CMD="sudo"
        info "Menggunakan sudo untuk paket sistem dan tema"
    else
        err "Perlu hak root atau sudo untuk memasang paket sistem"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Paket sistem
#   Wajib  -> gagal = installer berhenti
#   Opsional -> gagal = peringatan, lanjut
# -----------------------------------------------------------------------------
install_packages_arch() {
    local required=(sddm xfce4-panel xfconf thunar imagemagick python-pyqt6 curl tar)
    local optional=(python-gobject xfce4-pulseaudio-plugin xfce4-power-manager
                    xorg-xrandr xorg-xwininfo git)

    info "Memeriksa paket Arch Linux..."
    local pkg
    for pkg in "${required[@]}"; do
        if pacman -Q "$pkg" >/dev/null 2>&1; then
            ok "$pkg sudah terpasang"
        elif $SUDO_CMD pacman -S --needed --noconfirm "$pkg"; then
            ok "$pkg terpasang"
        else
            err "Gagal memasang paket wajib: $pkg"
            return 1
        fi
    done
    for pkg in "${optional[@]}"; do
        if pacman -Q "$pkg" >/dev/null 2>&1; then
            ok "$pkg sudah terpasang"
        elif $SUDO_CMD pacman -S --needed --noconfirm "$pkg"; then
            ok "$pkg terpasang"
        else
            warn "Paket opsional gagal dipasang: $pkg (dilewati)"
        fi
    done
}

install_packages_debian() {
    local required=(sddm xfce4-panel xfconf thunar imagemagick python3-pyqt6 curl tar)
    local optional=(python3-gi xfce4-pulseaudio-plugin xfce4-power-manager
                    xfce4-power-manager-plugins x11-xserver-utils x11-utils git)

    info "Memperbarui indeks paket Debian..."
    if ! $SUDO_CMD apt-get update -qq; then
        warn "apt-get update gagal; mencoba lanjut dengan indeks lama"
    fi
    local pkg
    for pkg in "${required[@]}"; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            ok "$pkg sudah terpasang"
        elif $SUDO_CMD apt-get install -y -qq "$pkg"; then
            ok "$pkg terpasang"
        else
            err "Gagal memasang paket wajib: $pkg"
            return 1
        fi
    done
    for pkg in "${optional[@]}"; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            ok "$pkg sudah terpasang"
        elif $SUDO_CMD apt-get install -y -qq "$pkg"; then
            ok "$pkg terpasang"
        else
            warn "Paket opsional gagal dipasang: $pkg (dilewati)"
        fi
    done
}

install_packages() {
    case "$DISTRO_FAMILY" in
        arch)   install_packages_arch ;;
        debian) install_packages_debian ;;
        *)      err "Keluarga distro tidak dikenal: $DISTRO_FAMILY"; return 1 ;;
    esac
}

# -----------------------------------------------------------------------------
# Cadangkan konfigurasi lama (folder bertimestamp, tidak pernah menimpa)
# -----------------------------------------------------------------------------
backup_configs() {
    local base="$HOME/xfce-win11-backup-$(date +%Y%m%d-%H%M%S)"
    BACKUP_DIR="$base"
    local n=1
    while [ -d "$BACKUP_DIR" ]; do
        n=$((n + 1))
        BACKUP_DIR="$base-$n"
    done
    mkdir -p "$BACKUP_DIR"

    if [ -d "$HOME/.config/xfce4" ]; then
        cp -a "$HOME/.config/xfce4" "$BACKUP_DIR/xfce4"
        ok "Cadang ~/.config/xfce4"
    fi
    if [ -d "$HOME/.config/Thunar" ]; then
        cp -a "$HOME/.config/Thunar" "$BACKUP_DIR/Thunar"
        ok "Cadang ~/.config/Thunar"
    fi
    local d
    for d in bin share src; do
        if [ -d "$HOME/.local/$d" ]; then
            cp -a "$HOME/.local/$d" "$BACKUP_DIR/local-$d"
            ok "Cadang ~/.local/$d"
        fi
    done
    if [ -d "$THEME_DIR" ]; then
        $SUDO_CMD cp -a "$THEME_DIR" "$BACKUP_DIR/tema-sddm" 2>/dev/null \
            && ok "Cadang $THEME_DIR" \
            || warn "Tidak bisa mencadangkan $THEME_DIR (izin)"
    fi
    info "Cadangan: $BACKUP_DIR"
}

# -----------------------------------------------------------------------------
# Unduh berkas pendukung dari GitHub (struktur folder dipertahankan)
# Mengisi $DOWNLOAD_DIR, tidak mencetak apa pun ke stdout.
# -----------------------------------------------------------------------------
download_files() {
    local files=(
        "login-look/login-look"
        "login-look/login-look-gui"
        "login-look/login_look_gui.py"
        "login-look/setup.sh"
        "xfce/xfce4-panel.xml"
        "xfce/win11-start-daemon"
        "xfce/win11-start"
        "xfce/17000000001.desktop"
        "apps/wordcraft/wordcraft"
        "apps/wordcraft/wordcraft.desktop"
        "apps/artcraft-launcher/artcraft-launcher"
        "apps/artcraft-launcher/artcraft-launcher.desktop"
        "apps/mission-center/mission-center"
        "apps/mission-center/mission-center.desktop"
    )

    DOWNLOAD_DIR="$(mktemp -d)"
    info "Mengunduh berkas pendukung dari GitHub..."
    local f out missing=0
    for f in "${files[@]}"; do
        out="$DOWNLOAD_DIR/$f"
        mkdir -p "$(dirname "$out")"
        if curl -fsSL "$RAW_BASE/$f" -o "$out" 2>/dev/null; then
            ok "Unduh $f"
        else
            warn "Gagal unduh $f"
            rm -f "$out"
            missing=$((missing + 1))
        fi
    done
    if [ "$missing" -gt 0 ]; then
        warn "$missing berkas gagal diunduh; bagian terkait akan dilewati"
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Pasang tema SDDM Win11 (dipatok ke commit; dilewati bila sudah ada)
# -----------------------------------------------------------------------------
install_theme() {
    if [ -f "$THEME_DIR/Main.qml" ]; then
        ok "Tema SDDM sudah ada di $THEME_DIR (dilewati, kustomisasi aman)"
        return 0
    fi

    local work
    work="$(mktemp -d)"
    info "Mengunduh tema SDDM Win11..."
    if ! curl -fsSL "$THEME_TARBALL_URL" -o "$work/theme.tar.gz"; then
        warn "Gagal mengunduh tema dari $THEME_TARBALL_URL"
        rm -rf "$work"
        return 0
    fi
    if ! tar -xzf "$work/theme.tar.gz" -C "$work" --strip-components=1; then
        warn "Gagal mengekstrak tema"
        rm -rf "$work"
        return 0
    fi
    if [ ! -f "$work/Main.qml" ]; then
        warn "Arsip tema tidak berisi Main.qml; dilewati"
        rm -rf "$work"
        return 0
    fi

    $SUDO_CMD mkdir -p "$THEME_DIR"
    $SUDO_CMD cp -a "$work/." "$THEME_DIR/"
    rm -rf "$work"
    ok "Tema SDDM dipasang di $THEME_DIR"
}

# -----------------------------------------------------------------------------
# Pasang login-look (CLI + GUI + setup.sh)
# -----------------------------------------------------------------------------
install_login_look() {
    local dir="$1"
    local src="$dir/login-look"

    mkdir -p "$HOME/.local/bin" "$HOME/.local/src/login-look"

    local f
    for f in login-look login-look-gui login_look_gui.py setup.sh; do
        [ -f "$src/$f" ] || { warn "Berkas login-look/$f tidak tersedia"; continue; }
        cp "$src/$f" "$HOME/.local/src/login-look/$f"
        case "$f" in
            login-look|login-look-gui)
                cp "$src/$f" "$HOME/.local/bin/$f"
                chmod +x "$HOME/.local/bin/$f"
                ;;
        esac
        ok "Pasang $f"
    done
    chmod +x "$HOME/.local/src/login-look/setup.sh" 2>/dev/null || true

    # Pastikan ~/.local/bin ada di PATH
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.zshrc"; do
        [ -f "$rc" ] || continue
        if ! grep -qF '$HOME/.local/bin' "$rc"; then
            {
                printf '\n# Tambahan PATH untuk login-look\n'
                printf 'export PATH="$HOME/.local/bin:$PATH"\n'
            } >> "$rc"
            ok "Tambah PATH ke $(basename "$rc")"
        fi
    done
}

# -----------------------------------------------------------------------------
# Pasang aplikasi tambahan (wordcraft, artcraft-launcher, mission-center)
# -----------------------------------------------------------------------------
install_apps() {
    local dir="$1"
    mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"

    local name
    for name in wordcraft artcraft-launcher mission-center; do
        if [ -f "$dir/apps/$name/$name" ]; then
            cp "$dir/apps/$name/$name" "$HOME/.local/bin/$name"
            chmod +x "$HOME/.local/bin/$name"
            ok "Pasang aplikasi $name"
        else
            warn "Binary $name tidak tersedia di repo"
        fi
        if [ -f "$dir/apps/$name/$name.desktop" ]; then
            cp "$dir/apps/$name/$name.desktop" \
               "$HOME/.local/share/applications/$name.desktop"
            chmod 644 "$HOME/.local/share/applications/$name.desktop"
            ok "Daftarkan menu $name"
        fi
    done
}

# -----------------------------------------------------------------------------
# Pasang daemon menu Start + konfigurasi panel (taskbar Win11)
# -----------------------------------------------------------------------------
install_panel() {
    local dir="$1"

    mkdir -p "$HOME/.local/bin" \
             "$HOME/.config/xfce4/panel/launcher-22" \
             "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"

    local f
    for f in win11-start-daemon win11-start; do
        if [ -f "$dir/xfce/$f" ]; then
            cp "$dir/xfce/$f" "$HOME/.local/bin/$f"
            chmod +x "$HOME/.local/bin/$f"
            ok "Pasang $f"
        else
            warn "xfce/$f tidak tersedia; menu Start tidak akan berfungsi"
        fi
    done

    if [ -f "$dir/xfce/17000000001.desktop" ]; then
        cp "$dir/xfce/17000000001.desktop" \
           "$HOME/.config/xfce4/panel/launcher-22/17000000001.desktop"
        chmod 644 "$HOME/.config/xfce4/panel/launcher-22/17000000001.desktop"
        ok "Pasang tombol Start panel"
    fi

    local panel="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
    if [ ! -f "$dir/xfce/xfce4-panel.xml" ]; then
        warn "xfce4-panel.xml tidak tersedia; panel tidak diubah"
    elif [ -f "$panel" ] && cmp -s "$dir/xfce/xfce4-panel.xml" "$panel"; then
        ok "Panel XFCE sudah sesuai (tidak ditulis ulang)"
    else
        if [ -f "$panel" ]; then
            cp "$panel" "$panel.pre-win11-$(date +%Y%m%d-%H%M%S)"
            ok "Panel lama disimpan di $(basename "$panel").pre-win11-*"
        fi
        cp "$dir/xfce/xfce4-panel.xml" "$panel"
        ok "Panel XFCE dipasang (taskbar Win11)"
    fi

    # Muat ulang panel hanya jika sesi XFCE sedang berjalan
    if [ -n "${DISPLAY:-}" ] && pgrep -x xfce4-panel >/dev/null 2>&1; then
        if xfce4-panel -r 2>/dev/null; then
            ok "Panel XFCE dimuat ulang"
        else
            warn "Panel gagal dimuat ulang; logout lalu login"
        fi
    fi
}

# -----------------------------------------------------------------------------
# Tambal tema SDDM (QML) + symlink theme.conf + daftarkan menu
# -----------------------------------------------------------------------------
configure_theme() {
    local setup="$HOME/.local/src/login-look/setup.sh"
    if [ ! -f "$setup" ]; then
        warn "setup.sh tidak ada; tema SDDM tidak ditambal"
        return 0
    fi
    if [ ! -f "$THEME_DIR/Main.qml" ]; then
        warn "Tema tidak ada di $THEME_DIR; penambalan dilewati"
        return 0
    fi

    info "Menambal QML tema SDDM (root)..."
    if $SUDO_CMD bash "$setup" --user "$(id -un)" --theme "$THEME_DIR"; then
        ok "Tema SDDM ditambal"
    else
        warn "Penambalan tema gagal; layar login tetap tema asli"
    fi
}

# -----------------------------------------------------------------------------
# Daftarkan entri menu (login-look-gui, aplikasi, Thunar UCA, PINNED)
# -----------------------------------------------------------------------------
configure_menu() {
    local cli="$HOME/.local/bin/login-look"
    if [ ! -x "$cli" ]; then
        warn "login-look tidak ada; entri menu dilewati"
        return 0
    fi
    if "$cli" install-menu >/dev/null 2>&1; then
        ok "Entri menu & PINNED dipasang"
    else
        warn "install-menu gagal; jalankan 'login-look install-menu' manual"
    fi
}

# -----------------------------------------------------------------------------
# Verifikasi
# -----------------------------------------------------------------------------
verify_install() {
    info "Memverifikasi instalasi..."
    local cmd
    for cmd in login-look login-look-gui win11-start-daemon; do
        if [ -x "$HOME/.local/bin/$cmd" ]; then
            ok "$cmd terpasang"
        else
            warn "$cmd tidak ditemukan di ~/.local/bin"
        fi
    done
    for cmd in wordcraft artcraft-launcher mission-center; do
        if [ -x "$HOME/.local/bin/$cmd" ]; then
            ok "aplikasi $cmd terpasang"
        else
            warn "aplikasi $cmd tidak terpasang"
        fi
    done
    if [ -f "$THEME_DIR/Main.qml" ]; then
        ok "tema SDDM ada di $THEME_DIR"
        if grep -q "login-look: background" "$THEME_DIR/Main.qml" 2>/dev/null; then
            ok "QML tema sudah ditambal login-look"
        else
            warn "QML tema belum ditambal login-look"
        fi
    else
        warn "tema SDDM tidak ada di $THEME_DIR"
    fi
    if [ -f "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" ]; then
        ok "konfigurasi panel terpasang"
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
        usage
        return 0
    fi

    printf '\n============================================================\n' >&2
    printf '  Pemasang Desktop XFCE Win11 + login-look\n' >&2
    printf '============================================================\n\n' >&2

    detect_distro
    detect_privilege
    install_packages

    backup_configs
    download_files
    trap 'rm -rf "${DOWNLOAD_DIR:-}"' EXIT

    install_theme
    install_login_look "$DOWNLOAD_DIR"
    install_apps "$DOWNLOAD_DIR"
    install_panel "$DOWNLOAD_DIR"
    configure_theme
    configure_menu
    verify_install

    cat <<TXT

============================================================
  PEMASANGAN SELESAI
============================================================

Cadangan konfigurasi lama: $BACKUP_DIR

Langkah berikutnya:
  1. Muat ulang shell:  source ~/.bashrc   (atau buka terminal baru)
  2. Buka GUI:          login-look-gui
  3. Menu Start:        klik tombol Start di taskbar -> "Pengaturan Layar Login"
  4. Logout atau reboot untuk melihat layar login SDDM Win11

Catatan: perubahan wallpaper/avatar berlaku pada greeter berikutnya
         (logout/reboot), bukan pada sesi yang sedang berjalan.

TXT
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
