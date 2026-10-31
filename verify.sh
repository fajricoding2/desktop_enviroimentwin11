#!/usr/bin/env bash
# =============================================================================
# verify.sh — periksa kesiapan repo desktop_enviroimentwin11
#
# Pemakaian:
#   bash verify.sh                 periksa berkas di GitHub (setelah push)
#   bash verify.sh --local [DIR]   periksa folder lokal (sebelum push)
#
# Yang diperiksa:
#   1. Semua berkas yang diunduh install.sh benar-benar ada (HTTP 200).
#   2. Sintaks bash / python / .desktop tiap berkas valid.
#   3. Tidak ada akhir baris CRLF (penyebab "bad interpreter").
#   4. Arsip tema SDDM dapat diunduh dan berisi Main.qml.
#   5. Tidak ada placeholder "ganti-dengan" tertinggal di install.sh.
#
# Exit: 0 semua lulus, 1 ada yang gagal, 2 salah pakai.
# =============================================================================
set -euo pipefail

GITHUB_USER="${GITHUB_USER:-fajricoding2}"
GITHUB_REPO="${GITHUB_REPO:-desktop_enviroimentwin11}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}}"
THEME_SHA="${THEME_SHA:-d10502f278bf43ed8d24c73df3deef28db0264c7}"
THEME_TARBALL_URL="${THEME_TARBALL_URL:-https://github.com/abhinand128/win11sddm/archive/${THEME_SHA}.tar.gz}"

MODE="remote"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$HERE"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    GREEN=$'\e[32m'; RED=$'\e[31m'; YELLOW=$'\e[33m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
else
    GREEN=""; RED=""; YELLOW=""; BOLD=""; RESET=""
fi

PASS=0
FAIL=0
TMPDIR_VERIFY=""

pass() { PASS=$((PASS + 1)); printf '%s[OK]%s    %s\n' "$GREEN" "$RESET" "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '%s[GAGAL]%s %s\n' "$RED" "$RESET" "$1"; }
note() { printf '%s[INFO]%s  %s\n' "$YELLOW" "$RESET" "$1"; }
die()  { printf '%s\n' "$1" >&2; exit 2; }

cleanup() {
    if [ -n "$TMPDIR_VERIFY" ]; then
        rm -rf "$TMPDIR_VERIFY"
    fi
    return 0
}
trap cleanup EXIT

usage() {
    cat <<'TXT'
verify.sh — periksa repo desktop_enviroimentwin11

  bash verify.sh                periksa berkas di GitHub (butuh internet)
  bash verify.sh --local [DIR]  periksa folder lokal (tanpa internet)
  bash verify.sh --help         bantuan ini

Override: GITHUB_USER, GITHUB_REPO, GITHUB_BRANCH, RAW_BASE,
          THEME_TARBALL_URL, THEME_SHA
TXT
}

while [ $# -gt 0 ]; do
    case "$1" in
        --local)
            MODE="local"
            if [ $# -ge 2 ] && [ "${2#-}" = "$2" ]; then
                LOCAL_DIR="$2"
                shift
            fi
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) die "opsi tidak dikenal: $1 (coba --help)" ;;
    esac
done

# -----------------------------------------------------------------------------
# Daftar berkas diambil dari install.sh agar tidak pernah melenceng
# -----------------------------------------------------------------------------
extract_files() {
    sed -n '/^[[:space:]]*local files=(/,/^[[:space:]]*)/p' "$1" \
        | sed -n 's/^[[:space:]]*"\([^"]*\)".*/\1/p'
}

# -----------------------------------------------------------------------------
# Pemeriksaan isi berkas
# -----------------------------------------------------------------------------
check_content() {
    local file="$1" rel="$2"
    local base
    base="$(basename "$rel")"

    case "$rel" in
        *.sh)
            if bash -n "$file" 2>/dev/null; then
                pass "$rel (sintaks bash)"
            else
                fail "$rel (sintaks bash rusak)"
            fi
            ;;
        *.py)
            if python3 -c 'import sys; compile(open(sys.argv[1], "rb").read(), sys.argv[1], "exec")' \
                 "$file" 2>/dev/null; then
                pass "$rel (sintaks python)"
            else
                fail "$rel (sintaks python rusak)"
            fi
            ;;
        *.desktop)
            if grep -q '^\[Desktop Entry\]' "$file"; then
                pass "$rel (.desktop valid)"
            else
                fail "$rel (bukan berkas .desktop)"
            fi
            ;;
        *) pass "$rel" ;;
    esac

    # Berkas tanpa ekstensi tetap bisa berupa skrip
    case "$base" in
        login-look|login-look-gui|win11-start-daemon)
            if head -n 1 "$file" | grep -q '^#!.*python'; then
                python3 -c 'import sys; compile(open(sys.argv[1], "rb").read(), sys.argv[1], "exec")' \
                    "$file" 2>/dev/null \
                    && pass "$rel (sintaks python)" \
                    || fail "$rel (sintaks python rusak)"
            else
                bash -n "$file" 2>/dev/null \
                    && pass "$rel (sintaks bash)" \
                    || fail "$rel (sintaks bash rusak)"
            fi
            ;;
        win11-start)
            bash -n "$file" 2>/dev/null \
                && pass "$rel (sintaks bash)" \
                || fail "$rel (sintaks bash rusak)"
            ;;
    esac

    # CRLF membuat skrip gagal dieksekusi di Linux
    if grep -qU $'\r' "$file" 2>/dev/null; then
        fail "$rel (mengandung CRLF; harus LF)"
    fi
}

# -----------------------------------------------------------------------------
# Mode lokal
# -----------------------------------------------------------------------------
verify_local() {
    local dir="$1"
    printf '%s== Memeriksa folder lokal: %s ==%s\n' "$BOLD" "$dir" "$RESET"

    local install_sh="$dir/install.sh"
    if [ ! -f "$install_sh" ]; then
        fail "install.sh tidak ditemukan di $dir"
        return
    fi
    pass "install.sh ada"

    local files
    files="$(extract_files "$install_sh")"
    if [ -z "$files" ]; then
        fail "tidak bisa membaca daftar berkas dari install.sh"
        return
    fi
    note "daftar berkas diambil dari install.sh ($(printf '%s\n' "$files" | wc -l) entri)"

    local rel
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        if [ ! -f "$dir/$rel" ]; then
            fail "$rel (tidak ada)"
            continue
        fi
        check_content "$dir/$rel" "$rel"
    done <<< "$files"

    check_placeholder "$install_sh"
    check_theme_local "$dir"
}

# -----------------------------------------------------------------------------
# Mode remote (GitHub)
# -----------------------------------------------------------------------------
verify_remote() {
    printf '%s== Memeriksa repo GitHub: %s/%s (%s) ==%s\n' \
        "$BOLD" "$GITHUB_USER" "$GITHUB_REPO" "$GITHUB_BRANCH" "$RESET"

    TMPDIR_VERIFY="$(mktemp -d)"
    local install_sh="$TMPDIR_VERIFY/install.sh"

    if ! curl -fsSL "$RAW_BASE/install.sh" -o "$install_sh" 2>/dev/null; then
        fail "install.sh tidak dapat diunduh dari $RAW_BASE/install.sh"
        note "pastikan repo public dan branch '$GITHUB_BRANCH' sudah di-push"
        return
    fi
    pass "install.sh dapat diunduh"

    local files
    files="$(extract_files "$install_sh")"
    if [ -z "$files" ]; then
        fail "tidak bisa membaca daftar berkas dari install.sh"
        return
    fi
    note "daftar berkas diambil dari install.sh ($(printf '%s\n' "$files" | wc -l) entri)"

    local rel out
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        out="$TMPDIR_VERIFY/$rel"
        mkdir -p "$(dirname "$out")"
        if ! curl -fsSL "$RAW_BASE/$rel" -o "$out" 2>/dev/null; then
            fail "$rel (404 / tidak dapat diunduh)"
            continue
        fi
        check_content "$out" "$rel"
    done <<< "$files"

    check_placeholder "$install_sh"
    check_theme_remote
}

# -----------------------------------------------------------------------------
# Pemeriksaan tambahan
# -----------------------------------------------------------------------------
check_placeholder() {
    local install_sh="$1"
    if grep -q 'ganti-dengan' "$install_sh"; then
        fail "install.sh masih berisi placeholder 'ganti-dengan'"
    else
        pass "tidak ada placeholder tertinggal"
    fi
}

check_theme_local() {
    local dir="$1"
    note "arsip tema tidak diperiksa pada mode --local (butuh internet)"
}

check_theme_remote() {
    local tar="$TMPDIR_VERIFY/theme.tar.gz"
    if ! curl -fsSL "$THEME_TARBALL_URL" -o "$tar" 2>/dev/null; then
        fail "theme.tar.gz tidak dapat diunduh dari $THEME_TARBALL_URL"
        return
    fi
    # Simpan daftar isi lebih dulu: grep -q bisa memutus pipa (SIGPIPE + pipefail)
    local listing="$TMPDIR_VERIFY/theme.list"
    if ! tar -tzf "$tar" > "$listing" 2>/dev/null; then
        fail "theme.tar.gz rusak / bukan arsip gzip"
        return
    fi
    if grep -q '/Main\.qml$' "$listing"; then
        pass "theme.tar.gz berisi Main.qml"
    else
        fail "theme.tar.gz tidak berisi Main.qml"
    fi
    if grep -q '/theme\.conf$' "$listing"; then
        pass "theme.tar.gz berisi theme.conf"
    else
        fail "theme.tar.gz tidak berisi theme.conf"
    fi
}

# -----------------------------------------------------------------------------
# Ringkasan
# -----------------------------------------------------------------------------
if [ "$MODE" = "local" ]; then
    verify_local "$LOCAL_DIR"
else
    verify_remote
fi

printf '\n'
if [ "$FAIL" -eq 0 ]; then
    printf '%sLULUS%s: %d pemeriksaan berhasil, 0 gagal\n' "$GREEN" "$RESET" "$PASS"
    exit 0
else
    printf '%sGAGAL%s: %d berhasil, %d gagal\n' "$RED" "$RESET" "$PASS" "$FAIL"
    exit 1
fi
