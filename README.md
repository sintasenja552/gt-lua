# gt-lua
## 🎯 Growtopia/GTPS Target Assist (State Machine Engine)

Script internal berbasis **Lua State Machine** untuk Client Launcher Growtopia/GTPS. Dirancang khusus untuk mempermudah pengerjaan balok secara semi-otomatis hingga otomatis penuh (*Full Auto*) dengan optimasi jaringan adaptif berbasis **Ping Client** untuk mencegah terjadinya *Disconnect (DC)* atau *Anti-Cheat Kick*.

> ⚠️ **Catatan Penting:** Script ini berjalan murni di sisi Client (Karakter Utama/Local Player) menggunakan API bawaan launcher seperti `GetLocal()`, `FindPath()`, dan overlay `ImGui`. Ini **bukan** script untuk multi-botting / fake-player.

---

## ✨ Fitur Unggulan

* **State Machine Architecture:** Alur logika sistem yang terbagi rapi (`IDLE` ➔ `INIT` ➔ `SCAN` ➔ `PATH` ➔ `READY`) sehingga tidak ada eksekusi fungsi yang tumpang tindih.
* **Ping Adaptive Buffer Engine:** Kecepatan pukulan otomatis menyesuaikan dengan latensi (ping) internet asli kamu secara *real-time* ditambah buffer aman 40ms.
* **Anti-Stuck Pathfinding Timeout:** Jika jalur navigasi terhalang oleh balok lain selama lebih dari 2 detik, script otomatis membatalkan target dan mencari balok terdekat yang baru.
* **ImGui HUD Overlay:** Menampilkan status sistem saat ini dan koordinat balok yang sedang dikunci (*Locked*) langsung di layar game kamu.

---

## ⚙️ Konfigurasi Script (Awal)

Sebelum menjalankan script, kamu bisa mengubah ID balok dan item di bagian atas kode sesuai kebutuhan:

| Variabel | Nilai Default | Keterangan |
| :--- | :--- | :--- |
| `farm_block_id` | `3200` | ID Balok yang ingin dihancurkan otomatis (Target). |
| `restock_item_id` | `3206` | ID Item logistik / equipment pendukung yang akan di-equip otomatis di fase awal. |
| `fist_id` | `18` | ID Alat pemukul (Tangan kosong / Pickaxe). |

---

## 🚀 Cara Penggunaan

1. Salin seluruh kode dari file `script.lua` yang ada di repositori ini.
2. Buka Menu Eksploit/Script di Launcher kamu, lalu tempel (*paste*) kodenya.
3. Jalankan script (*Execute*).
4. Gunakan perintah teks berikut di kolom obrolan (Chat) game kamu:
   * **`/start`** : Mengaktifkan radar pencarian balok terdekat dalam radius 5x5 kotak dan memulai siklus otomatis.
   * **`/stop`** : Menonaktifkan seluruh fungsi script secara bersih (*clean reset*) dan mengembalikan kontrol karakter penuh ke tanganmu.

---

## 🛠️ Penjelasan Alur Logika (Tutorial Struktur)

Script ini bekerja dengan mendeteksi perubahan kondisi sekitar melalui 5 status utama:
