#!/usr/bin/env bash
# =============================================================================
# install.sh — Pemasang satu baris untuk Desktop XFCE Win11 + login-look
#
# Pemakaian:
#   curl -fsSL https://raw.githubusercontent.com/USER/REPO/main/install.sh | bash
#
# Didukung: Arch Linux, Debian (dan turunan seperti Ubuntu)
# =============================================================================
set -euo pipefail

# Hindari prompt interaktif saat memasang paket di Debian/Ubuntu
export DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# Konfigurasi repo GitHub — GANTI sesuai akun dan repo Anda
# -----------------------------------------------------------------------------
GITHUB_USER="${GITHUB_USER:-fajricoding2}"
GITHUB_REPO="${GITHUB_REPO:-desktop_enviroimentwin11}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}"

# -----------------------------------------------------------------------------
# Warna output
# -----------------------------------------------------------------------------
RED=$'\e[31m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
BLUE=$'\e[34m'
RESET=$'\e[0m'

info()  { printf '%s[INFO]%s  %s\n' "$BLUE" "$RESET" "$*"; }
ok()    { printf '%s[OK]%s    %s\n' "$GREEN" "$RESET" "$*"; }
warn()  { printf '%s[WARN]%s  %s\n' "$YELLOW" "$RESET" "$*"; }
err()   { printf '%s[ERR]%s   %s\n' "$RED" "$RESET" "$*" >&2; }

# -----------------------------------------------------------------------------
# Deteksi distribusi
# -----------------------------------------------------------------------------
detect_distro() {
    if [ ! -f /etc/os-release ]; then
        err "Tidak dapat mendeteksi distribusi Linux (/etc/os-release hilang)"
        exit 1
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO="$ID"
    DISTRO_ID_LIKE="${ID_LIKE:-}"
    info "Distribusi terdeteksi: $DISTRO"
}

# -----------------------------------------------------------------------------
# Deteksi sudo / root
# -----------------------------------------------------------------------------
detect_privilege() {
    if [ "$(id -u)" -eq 0 ]; then
        SUDO=""
        info "Menjalankan sebagai root"
    elif command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
        info "Menggunakan sudo untuk pemasangan paket sistem"
    else
        err "Perlukan hak root atau sudo untuk memasang paket sistem"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Pasang paket sistem (Arch)
# -----------------------------------------------------------------------------
install_packages_arch() {
    local pkgs=(
        sddm sddm-greeter python-pyqt6 imagemagick thunar
        xfce4-panel xfconf xorg-xrandr xorg-xwininfo curl git
    )
    info "Memeriksa paket Arch Linux..."
    for pkg in "${pkgs[@]}"; do
        if ! pacman -Q "$pkg" >/dev/null 2>&1; then
            info "Memasang $pkg..."
            $SUDO pacman -S --needed --noconfirm "$pkg"
        else
            ok "$pkg sudah terpasang"
        fi
    done
}

# -----------------------------------------------------------------------------
# Pasang paket sistem (Debian / Ubuntu)
# -----------------------------------------------------------------------------
install_packages_debian() {
    local pkgs=(
        sddm sddm-greeter python3-pyqt6 imagemagick thunar
        xfce4-panel xfconf x11-xserver-utils curl git
    )
    info "Memperbarui indeks paket Debian..."
    $SUDO apt-get update -qq
    for pkg in "${pkgs[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            info "Memasang $pkg..."
            $SUDO apt-get install -y -qq "$pkg"
        else
            ok "$pkg sudah terpasang"
        fi
    done
}

# -----------------------------------------------------------------------------
# Cadangkan konfigurasi lama (dengan timestamp)
# -----------------------------------------------------------------------------
backup_configs() {
    local backup_dir="$HOME/xfce-win11-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"

    # ~/.config/xfce4
    if [ -d "$HOME/.config/xfce4" ]; then
        cp -a "$HOME/.config/xfce4" "$backup_dir/xfce4"
        ok "Cadang ~/.config/xfce4"
    fi

    # ~/.local/bin, share, src
    for d in bin share src; do
        if [ -d "$HOME/.local/$d" ]; then
            cp -a "$HOME/.local/$d" "$backup_dir/local-$d"
            ok "Cadang ~/.local/$d"
        fi
    done

    # /usr/share/sddm/themes/win11sddm
    if [ -d /usr/share/sddm/themes/win11sddm ]; then
        $SUDO cp -a /usr/share/sddm/themes/win11sddm "$backup_dir/win11sddm"
        ok "Cadang /usr/share/sddm/themes/win11sddm"
    fi

    info "Cadangan disimpan di: $backup_dir"
}

# -----------------------------------------------------------------------------
# Unduh berkas pendukung dari GitHub ke folder temporer
# -----------------------------------------------------------------------------
download_files() {
    local tmpdir
    tmpdir=$(mktemp -d)
    info "Mengunduh berkas pendukung dari GitHub..."

    local files=(
        "login-look/login-look"
        "login-look/login-look-gui"
        "login-look/login_look_gui.py"
        "login-look/setup.sh"
        "xfce/uca.xml"
        "apps/wordcraft/wordcraft"
        "apps/wordcraft/wordcraft.desktop"
        "apps/artcraft-launcher/artcraft-launcher"
        "apps/artcraft-launcher/artcraft-launcher.desktop"
        "apps/mission-center/mission-center"
        "apps/mission-center/mission-center.desktop"
    )

    for f in "${files[@]}"; do
        local url="$RAW_BASE/$f"
        local out="$tmpdir/$(basename "$f")"
        if curl -fsSL "$url" -o "$out" 2>/dev/null; then
            ok "Unduh $f"
        else
            warn "Gagal unduh $f (mungkin belum ada di repo)"
        fi
    done

    # Unduh konfigurasi panel XFCE (opsional)
    if curl -fsSL "$RAW_BASE/xfce/xfce4-panel.xml" -o "$tmpdir/xfce4-panel.xml" 2>/dev/null; then
        ok "Unduh xfce4-panel.xml"
    fi

    echo "$tmpdir"
}

# -----------------------------------------------------------------------------
# Pasang login-look (CLI + GUI + setup.sh)
# -----------------------------------------------------------------------------
install_login_look() {
    local tmpdir="$1"

    mkdir -p "$HOME/.local/bin" "$HOME/.local/src/login-look"

    # Salin berkas jika ada di tmpdir
    for f in login-look login-look-gui login_look_gui.py setup.sh; do
        if [ -f "$tmpdir/$f" ]; then
            cp "$tmpdir/$f" "$HOME/.local/src/login-look/$f"
            if [ "$f" = "login-look" ] || [ "$f" = "login-look-gui" ]; then
                cp "$tmpdir/$f" "$HOME/.local/bin/$f"
                chmod +x "$HOME/.local/bin/$f"
            fi
            ok "Pasang $f"
        fi
    done

    # setup.sh tidak usah di-copy ke bin, cukup di src
    if [ -f "$HOME/.local/src/login-look/setup.sh" ]; then
        chmod +x "$HOME/.local/src/login-look/setup.sh"
    fi

    # Pastikan ~/.local/bin ada di PATH
    local profile_rc
    for profile_rc in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.zshrc"; do
        if [ -f "$profile_rc" ] && ! grep -q 'HOME\/.local\/bin' "$profile_rc"; then
            echo '' >> "$profile_rc"
            echo '# Tambahan PATH untuk login-look' >> "$profile_rc"
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$profile_rc"
            ok "Tambah PATH ke $profile_rc"
        fi
    done

    # Jalankan setup.sh sebagai root (patch QML, symlink theme.conf, menu)
    if [ -f "$HOME/.local/src/login-look/setup.sh" ]; then
        info "Menjalankan setup.sh (root) untuk tema SDDM..."
        $SUDO bash "$HOME/.local/src/login-look/setup.sh" --user "$USER"
        ok "setup.sh selesai"
    fi
}

# -----------------------------------------------------------------------------
# Pasang aplikasi tambahan (wordcraft, artcraft-launcher, mission-center)
# -----------------------------------------------------------------------------
install_apps() {
    local tmpdir="$1"

    mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"

    local apps=(
        "wordcraft:wordcraft"
        "artcraft-launcher:artcraft-launcher"
        "mission-center:mission-center"
    )

    for entry in "${apps[@]}"; do
        local name="${entry%%:*}"
        local binary="${entry##*:}"

        if [ -f "$tmpdir/$name/$binary" ]; then
            cp "$tmpdir/$name/$binary" "$HOME/.local/bin/$binary"
            chmod +x "$HOME/.local/bin/$binary"
            ok "Pasang binary $binary"
        fi

        if [ -f "$tmpdir/$name/$binary.desktop" ]; then
            cp "$tmpdir/$name/$binary.desktop" "$HOME/.local/share/applications/$binary.desktop"
            ok "Pasang .desktop $binary"
        fi
    done
}

# -----------------------------------------------------------------------------
# Konfigurasi XFCE panel (taskbar di tengah)
# -----------------------------------------------------------------------------
configure_xfce_panel() {
    mkdir -p "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
    mkdir -p "$HOME/.config/xfce4/panel"

    local tmpdir="$1"
    if [ -f "$tmpdir/xfce4-panel.xml" ]; then
        cp "$tmpdir/xfce4-panel.xml" \
           "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
        ok "Konfigurasi panel XFCE dipasang"
    else
        warn "Berkas xfce4-panel.xml tidak ditemukan, dilewati"
    fi

    # Muat ulang panel jika sedang berjalan
    if pgrep -x xfce4-panel >/dev/null 2>&1; then
        xfce4-panel -r 2>/dev/null || true
        ok "Panel XFCE dimuat ulang"
    fi
}

# -----------------------------------------------------------------------------
# Konfigurasi Thunar UCA (klik kanan file manager)
# -----------------------------------------------------------------------------
configure_thunar() {
    local tmpdir="$1"
    mkdir -p "$HOME/.config/Thunar"

    local uca_file="$HOME/.config/Thunar/uca.xml"
    local new_uca="$tmpdir/uca.xml"

    if [ ! -f "$new_uca" ]; then
        warn "Berkas uca.xml tidak tersedia di repo, dilewati"
        return
    fi

    if [ -f "$uca_file" ] && ! grep -q "login-look-menu-1" "$uca_file"; then
        # Sisipkan action login-look sebelum </actions> (idempotent)
        sed -i 's|</actions>|	<action>\n		<icon>preferences-desktop-wallpaper</icon>\n		<name>Ubah layar login</name>\n		<submenu></submenu>\n		<unique-id>login-look-menu-1</unique-id>\n		<command>login-look-gui</command>\n		<description>Buka Pengaturan Layar Login</description>\n		<patterns>*</patterns>\n		<startup-notify/>\n	</action>\n</actions>|' "$uca_file"
        ok "Thunar UCA action 'Ubah layar login' ditambahkan"
    elif [ ! -f "$uca_file" ]; then
        cp "$new_uca" "$uca_file"
        ok "Thunar uca.xml dipasang"
    else
        ok "Thunar UCA action sudah ada"
    fi
}

# -----------------------------------------------------------------------------
# Verifikasi instalasi
# -----------------------------------------------------------------------------
verify_install() {
    info "Memverifikasi instalasi..."

    if command -v login-look >/dev/null 2>&1; then
        ok "login-look tersedia di PATH"
    else
        warn "login-look tidak ditemukan di PATH. Pastikan ~/.local/bin ada di PATH"
    fi

    if command -v login-look-gui >/dev/null 2>&1; then
        ok "login-look-gui tersedia di PATH"
    else
        warn "login-look-gui tidak ditemukan di PATH"
    fi

    if [ -d /usr/share/sddm/themes/win11sddm ]; then
        ok "Tema SDDM win11sddm terpasang"
    else
        warn "Tema SDDM win11sddm tidak ditemukan"
    fi

    # Verifikasi aplikasi tambahan
    for app in wordcraft artcraft-launcher mission-center; do
        if command -v "$app" >/dev/null 2>&1; then
            ok "$app tersedia di PATH"
        else
            warn "$app tidak ditemukan di PATH"
        fi
    done
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "============================================================"
    echo "  Pemasang Desktop XFCE Win11 + login-look"
    echo "============================================================"
    echo ""

    detect_distro
    detect_privilege

    case "$DISTRO" in
        arch)         install_packages_arch ;;
        debian|ubuntu) install_packages_debian ;;
        *)
            err "Distribusi tidak didukung: $DISTRO (hanya Arch dan Debian)"
            exit 1
            ;;
    esac

    backup_configs

    local tmpdir
    tmpdir=$(download_files)

    install_login_look "$tmpdir"
    install_apps "$tmpdir"
    configure_xfce_panel "$tmpdir"
    configure_thunar "$tmpdir"

    rm -rf "$tmpdir"

    verify_install

    echo ""
    echo "============================================================"
    echo "  PEMASANGAN SELESAI"
    echo "============================================================"
    echo ""
    echo "Langkah berikutnya:"
    echo "  1. Muat ulang shell:  source ~/.bashrc  (atau buka terminal baru)"
    echo "  2. Buka GUI:          login-look-gui"
    echo "  3. Atau lewat menu Start: 'Pengaturan Layar Login'"
    echo "  4. Logout atau reboot untuk melihat layar login SDDM Win11"
    echo ""
    echo "Catatan: Perubahan wallpaper/avatar berlaku pada greeter berikutnya"
    echo "         (logout/reboot), bukan pada sesi yang sedang berjalan."
    echo ""
}

main "$@"
