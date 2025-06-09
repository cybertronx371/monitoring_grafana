Skrip Instalasi Monitoring Stack (Prometheus, Grafana, SNMP Exporter)
Skrip ini dirancang untuk mengotomatiskan seluruh proses instalasi dan konfigurasi monitoring stack yang siap produksi di server Ubuntu 20.04 / 22.04. Stack ini terdiri dari Prometheus, Grafana, dan SNMP Exporter yang dikonfigurasi secara khusus untuk memonitor perangkat jaringan seperti MikroTik.

Skrip ini bersifat interaktif, aman, dan akan menangani semua kebutuhan mulai dari dependensi hingga konfigurasi firewall.

Fitur Utama
Otomatis & Cepat: Menginstal seluruh stack dalam beberapa menit tanpa intervensi manual yang rumit.
Interaktif: Meminta input untuk konfigurasi penting seperti IP Address target dan komunitas SNMP, sehingga tidak perlu mengedit skrip secara manual.
Konfigurasi Siap Pakai: Menghasilkan file konfigurasi untuk Prometheus dan SNMP Exporter yang dioptimalkan untuk metrik umum MikroTik.
Manajemen Layanan systemd: Secara otomatis membuat dan mengaktifkan layanan untuk Prometheus, Grafana, dan SNMP Exporter agar berjalan saat boot.
Konfigurasi Firewall: Mengamankan server dengan membuka port yang diperlukan saja (9090, 3000, 9116) menggunakan UFW.
Pembersihan Otomatis: Menghapus file-file installer yang sudah tidak diperlukan setelah instalasi selesai untuk menjaga kebersihan sistem.
Komponen yang Diinstal
Prometheus v2.53.0
Grafana v11.0.0
SNMP Exporter v0.26.0
UFW (Uncomplicated Firewall)
Persyaratan
Server dengan sistem operasi Ubuntu 20.04 LTS atau Ubuntu 22.04 LTS.
Akses sebagai root atau pengguna dengan hak sudo.
Koneksi internet yang stabil untuk mengunduh paket.
SNMP telah diaktifkan pada perangkat MikroTik yang akan dimonitor.
Cara Penggunaan
Unduh Skrip
Unduh file skrip ke server Anda menggunakan wget atau curl.

Bash

wget https://gist.githubusercontent.com/user/repo/raw/instalasi_monitoring_stack_final.sh
(Catatan: Ganti URL di atas dengan URL skrip Anda yang sebenarnya)

Berikan Izin Eksekusi
Jadikan skrip dapat dieksekusi dengan perintah chmod.

Bash

chmod +x instalasi_monitoring_stack_final.sh
Jalankan Skrip
Eksekusi skrip dengan hak akses sudo.

Bash

sudo ./instalasi_monitoring_stack_final.sh
Proses Instalasi
Skrip akan menanyakan dua hal saat pertama kali dijalankan:

Masukkan IP Address MikroTik: IP dari perangkat yang akan Anda monitor.
Masukkan Komunitas SNMP MikroTik: Community string yang telah Anda atur di MikroTik (jika Anda tidak mengisi, defaultnya adalah public).
Setelah itu, skrip akan berjalan secara otomatis melakukan langkah-langkah berikut:

Menginstal semua dependensi yang dibutuhkan.
Membuat pengguna sistem yang aman untuk setiap layanan.
Mengunduh, mengekstrak, dan menginstal Prometheus, Grafana, dan SNMP Exporter.
Membuat file konfigurasi berdasarkan input Anda.
Membuat dan mengaktifkan service systemd.
Mengonfigurasi ufw (firewall).
Membersihkan file-file sementara.
Setelah Instalasi
Setelah skrip selesai, Anda dapat mengakses layanan berikut melalui browser:

Prometheus: http://<IP_SERVER_ANDA>:9090
Grafana: http://<IP_SERVER_ANDA>:3000
SNMP Exporter: http://<IP_SERVER_ANDA>:9116
Login Default Grafana:

Username: admin
Password: admin
PENTING: Segera ganti password default Grafana setelah login pertama untuk alasan keamanan.

Untuk menampilkan data MikroTik, import dashboard yang sudah ada dari komunitas Grafana. ID yang populer dan bekerja baik dengan skrip ini adalah 11029 atau 7497.
