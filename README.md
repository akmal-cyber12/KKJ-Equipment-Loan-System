# KKJ Inventory V1

Sistem Inventori Makmal Komputer Kolej Kemahiran Johor (KKJ).

## V1 sudah ada
- Login menggunakan Supabase Auth
- Role `admin` dan `technician`
- Dashboard statistik
- CRUD aset
- Kategori aset
- Lokasi makmal
- Status & kondisi aset
- Carian dan filter
- Responsive untuk phone / laptop
- PostgreSQL cloud melalui Supabase
- Row Level Security (RLS)
- Logo KKJ

## Cara setup melalui phone

### 1. Buat projek Supabase
Buka laman Supabase melalui browser phone dan cipta satu project baru.

### 2. Jalankan database
Masuk:
`SQL Editor` → `New Query`

Copy semua isi fail `database.sql`, paste dan tekan **Run**.

### 3. Cipta user
Masuk:
`Authentication` → `Users` → `Add user`

Contoh:
- Email: `admin@kkj.com`
- Password: pilih password sendiri

### 4. Jadikan user sebagai Admin
Selepas user dicipta, buka SQL Editor dan run:

```sql
update public.profiles
set role = 'admin', full_name = 'Admin KKJ'
where id = (
  select id from auth.users where email = 'admin@kkj.com'
);
```

Untuk Technician, tidak perlu ubah role kerana default ialah `technician`.

### 5. Ambil Supabase URL dan anon key
Masuk:
`Project Settings` → `API`

Salin:
- Project URL
- `anon` / public key

Buka `config.js` dan gantikan:

```js
SUPABASE_URL: "PASTE_YOUR_SUPABASE_URL_HERE",
SUPABASE_ANON_KEY: "PASTE_YOUR_SUPABASE_ANON_KEY_HERE"
```

**Jangan sekali-kali masukkan `service_role` key ke dalam `config.js`.**

### 6. Jalankan website
Upload folder ini ke browser coding environment / static hosting yang menyokong fail HTML biasa.

Fail utama ialah:
`index.html`

Oleh sebab projek menggunakan CDN Supabase JS, internet diperlukan ketika website digunakan.

## Role V1

### Admin
- Lihat aset
- Tambah aset
- Edit aset
- Padam aset
- Tambah/edit/padam kategori
- Tambah/edit/padam lokasi

### Technician
- Lihat aset
- Tambah aset
- Edit aset
- Cari/filter aset
- View kategori/lokasi
- Tidak boleh padam aset atau ubah master data

## Struktur projek

```text
kkj_inventory_v1/
├── index.html
├── style.css
├── config.js
├── app.js
├── database.sql
├── README.md
└── assets/
    └── logo-kkj.png
```

## V2 yang boleh ditambah kemudian
- QR Code + scanner kamera phone
- Gambar aset dengan Supabase Storage
- Pinjaman aset
- Maintenance
- Aduan kerosakan
- Supplier
- Warranty reminder
- Notification
- Audit trail
- Laporan / Print / Export PDF & Excel
