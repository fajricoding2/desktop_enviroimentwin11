# desktop_enviroimentwin11

Pemasang satu perintah untuk **desktop XFCE bergaya Windows 11** + **layar login SDDM Win11**
di **Arch Linux** dan **Debian** (termasuk turunan: Ubuntu, Linux Mint, Pop!_OS).

```bash
curl -fsSL https://raw.githubusercontent.com/fajricoding2/desktop_enviroimentwin11/main/install.sh | bash
```

---

## Yang dipasang

| Bagian | Isi |
|---|---|
| **Tema SDDM** | Tema Win11 (`win11sddm`, MIT, karya [abhinand128](https://github.com/abhinand128/win11sddm)) — dipatok ke commit tertentu |
| **login-look** | CLI + GUI PyQt6 untuk mengganti **wallpaper** dan **avatar** layar login tanpa sudo |
| **Taskbar** | Panel XFCE bergaya Win11 (ikon tengah, Start di kiri, jam di kanan) |
| **Menu Start** | `win11-start-daemon` (menu Start bergaya Win11, GTK3) |
| **Aplikasi** | `wordcraft`, `artcraft-launcher`, `mission-center` + entri menu |
| **Integrasi** | Entri "Pengaturan Layar Login" di menu Start dan klik-kanan Thunar |

Semua berkas pengguna diletakkan di `~/.local/` — tidak ada yang ditulis ke `/usr`
kecuali tema SDDM (`/usr/share/sddm/themes/win11sddm`).

---

## Sifat installer

- **Idempotent** — aman dijalankan berkali-kali. Yang sudah terpasang dilewati;
  tema yang sudah ada **tidak** ditimpa (wallpaper/avatar pilihan Anda aman).
- **Selalu mencadangkan** konfigurasi lama ke `~/xfce-win11-backup-<tanggal>/`
  (folder baru tiap run, tidak pernah menimpa cadangan lama).
- **Distro-aware** — memakai `pacman` di Arch dan `apt` di Debian;
  turunan Debian dikenali lewat `ID_LIKE`.
- **Tanpa dependensi baru di luar paket distro** — tidak ada pip/npm.

---

## Pemakaian sehari-hari

```bash
login-look-gui        # GUI: ganti wallpaper + avatar layar login
login-look --help     # CLI
```

Atau: **menu Start → "Pengaturan Layar Login"**, atau **klik kanan berkas di Thunar → "Ubah layar login"**.

Perubahan wallpaper/avatar tampil pada **greeter berikutnya** (logout/reboot),
bukan pada sesi yang sedang berjalan.

---

## Struktur repo

```
install.sh                     # pemasang utama (satu-satunya yang perlu diunduh user)
verify.sh                      # pemeriksa repo: lokal (pra-push) & GitHub (pasca-push)
login-look/
  login-look                   # CLI inti (config, gambar, preview, install-menu)
  login-look-gui               # pembungkus GUI
  login_look_gui.py            # modul PyQt6
  setup.sh                     # penambal QML tema SDDM (butuh root)
xfce/
  xfce4-panel.xml              # konfigurasi panel Win11 (taskbar tengah)
  win11-start-daemon           # daemon menu Start
  win11-start                  # pemicu menu Start (dipakai tombol panel)
  17000000001.desktop          # tombol Start untuk plugin launcher panel
apps/
  wordcraft/                   # binary + .desktop
  artcraft-launcher/
  mission-center/
tests/
  test_install_sh.py           # 14 tes: offline, tanpa root
  test_verify_sh.py            # 9 tes: offline, tanpa root
```

---

## Sebelum & sesudah push

`verify.sh` memeriksa semua berkas yang dipakai installer — daftarnya **dibaca
langsung dari `install.sh`**, jadi tidak bisa melenceng.

```bash
# sebelum push: cek folder lokal (tanpa internet)
bash verify.sh --local

# sesudah push: cek apa yang benar-benar ada di GitHub
bash verify.sh
```

Yang diperiksa: setiap berkas dapat diunduh (HTTP 200), sintaks bash/python/`.desktop`
valid, tidak ada CRLF, arsip tema berisi `Main.qml` + `theme.conf`, dan tidak ada
placeholder `ganti-dengan` tertinggal. Exit code `0` = semua lulus.

> `apps/*/wordcraft`, `artcraft-launcher`, `mission-center` saat ini berupa
> **placeholder** yang menjalankan aplikasi bawaan sistem. Ganti dengan binary
> asli bila sudah tersedia — installer menyalinnya apa adanya ke `~/.local/bin`.

---

## Opsi lanjutan

```bash
bash install.sh --help
```

| Variabel | Arti |
|---|---|
| `GITHUB_USER`, `GITHUB_REPO`, `GITHUB_BRANCH` | sumber berkas (untuk fork) |
| `RAW_BASE` | basis URL mentah |
| `THEME_DIR` | folder tema SDDM (default `/usr/share/sddm/themes/win11sddm`) |
| `THEME_TARBALL_URL`, `THEME_SHA` | sumber tema (dipatok ke commit) |
| `OS_RELEASE` | berkas deteksi distro (untuk pengujian) |

Contoh memakai fork:

```bash
curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/main/install.sh \
  | GITHUB_USER=<user> GITHUB_REPO=<repo> bash
```

---

## Menguji tanpa mengubah sistem

```bash
python3 tests/test_install_sh.py
```

Tes memakai `HOME` palsu, mirror palsu, dan stub `curl`/`sudo`/`pacman` —
tidak menyentuh sistem dan tidak butuh root.

---

## Rollback manual

1. `sudo bash ~/.local/src/login-look/setup.sh --uninstall` — cabut tambalan QML + menu.
2. Kembalikan konfigurasi lama dari `~/xfce-win11-backup-<tanggal>/`:
   `xfce4/`, `Thunar/`, `local-bin/`, `local-share/`, `tema-sddm/`.
3. `sudo pacman -Rns sddm` / `sudo apt remove sddm` bila tidak diinginkan.

---

## Lisensi

Skrip installer & login-look: bebas dipakai dan diubah.
Tema SDDM `win11sddm`: MIT © abhinand128.
