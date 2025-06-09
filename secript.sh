#!/bin/bash

# ===================================================================================
# Skrip Otomatis Terpadu untuk Instalasi Prometheus, Grafana, dan SNMP Exporter
# Versi 2.0: Interaktif dan Self-Cleaning
# Siap produksi untuk Ubuntu 20.04 / 22.04
# Fitur: Versi terbaru, spinner, input interaktif, konfigurasi MikroTik, firewall
# Dibuat oleh: MH + ChatGPT | Diperbarui oleh: Gemini
# ===================================================================================

set -e

# ------------------------- Validasi Akses Root -------------------------
if [ "$(id -u)" != "0" ]; then
    echo -e "\e[1;31mSkrip ini harus dijalankan sebagai root. Gunakan sudo.\e[0m"
    exit 1
fi

# ------------------------- Konfigurasi Global --------------------------
PROMETHEUS_VERSION="2.53.0"
SNMP_EXPORTER_VERSION="0.26.0"
GRAFANA_VERSION="11.0.0"

# Variabel target akan diisi secara interaktif
MIKROTIK_TARGET=""
SNMP_COMMUNITY=""

# ------------------------- Spinner & Logging --------------------------
function start_spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\\'
    echo -n "  "
    while [ -d /proc/$pid ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%$temp}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    wait $pid
    return $?
}

function log_info() {
    echo -e "\n \e[1;32m$1\e[0m"
}

function log_step() {
    echo -e "\n \e[1;34m$1\e[0m"
}

# ------------------------- Fungsi-fungsi Instalasi --------------------------
function install_dependencies() {
    log_step "Memperbarui daftar paket dan menginstal dependensi..."
    (apt-get update && apt-get install -y wget curl tar libfontconfig1 ufw software-properties-common apt-transport-https adduser libcap2-bin) &> /dev/null &
    start_spinner
    log_info "Dependensi berhasil diinstal."
}

function setup_users_and_dirs() {
    log_step "Membuat pengguna dan direktori sistem..."
    useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true
    useradd --no-create-home --shell /bin/false snmp_exporter 2>/dev/null || true

    mkdir -p /etc/prometheus/consoles /etc/prometheus/console_libraries /var/lib/prometheus
    mkdir -p /etc/snmp_exporter
    chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
    chown -R snmp_exporter:snmp_exporter /etc/snmp_exporter
    log_info "Pengguna dan direktori siap."
}

function install_prometheus() {
    log_step "Menginstal Prometheus v$PROMETHEUS_VERSION..."
    cd /tmp
    (wget -q --show-progress https://github.com/prometheus/prometheus/releases/download/v$PROMETHEUS_VERSION/prometheus-$PROMETHEUS_VERSION.linux-amd64.tar.gz && \
    tar xvf prometheus-$PROMETHEUS_VERSION.linux-amd64.tar.gz) &> /dev/null &
    start_spinner

    cp prometheus-$PROMETHEUS_VERSION.linux-amd64/prometheus /usr/local/bin/
    cp prometheus-$PROMETHEUS_VERSION.linux-amd64/promtool /usr/local/bin/
    cp -r prometheus-$PROMETHEUS_VERSION.linux-amd64/consoles/. /etc/prometheus/consoles/
    cp -r prometheus-$PROMETHEUS_VERSION.linux-amd64/console_libraries/. /etc/prometheus/console_libraries/
    chown -R prometheus:prometheus /etc/prometheus
    log_info "Prometheus berhasil diinstal."
}

function install_snmp_exporter() {
    log_step "Menginstal SNMP Exporter v$SNMP_EXPORTER_VERSION..."
    cd /tmp
    (wget -q --show-progress https://github.com/prometheus/snmp_exporter/releases/download/v$SNMP_EXPORTER_VERSION/snmp_exporter-$SNMP_EXPORTER_VERSION.linux-amd64.tar.gz && \
    tar xvf snmp_exporter-$SNMP_EXPORTER_VERSION.linux-amd64.tar.gz) &> /dev/null &
    start_spinner
    
    cp snmp_exporter-$SNMP_EXPORTER_VERSION.linux-amd64/snmp_exporter /usr/local/bin/
    cp snmp_exporter-$SNMP_EXPORTER_VERSION.linux-amd64/snmp.yml /etc/snmp_exporter/
    chown -R snmp_exporter:snmp_exporter /etc/snmp_exporter
    log_info "SNMP Exporter berhasil diinstal."
}

function install_grafana() {
    log_step "Menginstal Grafana v$GRAFANA_VERSION..."
    cd /tmp
    (wget -q --show-progress https://dl.grafana.com/oss/release/grafana_${GRAFANA_VERSION}_amd64.deb && dpkg -i grafana_${GRAFANA_VERSION}_amd64.deb) &> /dev/null &
    start_spinner
    log_info "Grafana berhasil diinstal."
}

# ------------------------- Fungsi Konfigurasi --------------------------
function configure_services() {
    log_step "Mengonfigurasi Prometheus untuk target $MIKROTIK_TARGET..."
    cat <<EOF > /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'snmp_mikrotik'
    static_configs:
      - targets: ['$MIKROTIK_TARGET']
    metrics_path: /snmp
    params:
      module: [mikrotik]
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: 127.0.0.1:9116
EOF
    chown prometheus:prometheus /etc/prometheus/prometheus.yml

    log_step "Mengonfigurasi SNMP Exporter..."
    cat <<EOF > /etc/snmp_exporter/snmp.yml
mikrotik:
  walk:
    - 1.3.6.1.2.1.1 # System
    - 1.3.6.1.2.1.2 # Interfaces
    - 1.3.6.1.2.1.4.20 # IP
    - 1.3.6.1.2.1.31.1.1 # Interface High-Speed Counters
    - 1.3.6.1.4.1.14988.1.1.1 # Health (CPU, Temp)
    - 1.3.6.1.4.1.14988.1.1.2.1 # Wireless
    - 1.3.6.1.4.1.14988.1.1.3.8.0 # Hotspot users
    - 1.3.6.1.4.1.14988.1.1.4.1 # DHCP Leases
    - 1.3.6.1.4.1.14988.1.1.5.1 # Queues
  version: 2
  auth:
    community: $SNMP_COMMUNITY
EOF
    chown snmp_exporter:snmp_exporter /etc/snmp_exporter/snmp.yml
    log_info "Konfigurasi layanan selesai."
}

function setup_services() {
    log_step "Membuat dan mengaktifkan service systemd..."
    cat <<EOF > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus Monitoring
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
EOF

    cat <<EOF > /etc/systemd/system/snmp_exporter.service
[Unit]
Description=Prometheus SNMP Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=snmp_exporter
Group=snmp_exporter
Type=simple
ExecStart=/usr/local/bin/snmp_exporter \
  --config.file=/etc/snmp_exporter/snmp.yml

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now prometheus snmp_exporter grafana-server &> /dev/null &
    start_spinner
    log_info "Semua service telah aktif dan berjalan."
}

function configure_firewall() {
    log_step "Mengatur firewall (UFW)..."
    ufw allow 22/tcp      # SSH (Sangat disarankan)
    ufw allow 9090/tcp    # Prometheus
    ufw allow 3000/tcp    # Grafana
    ufw allow 9116/tcp    # SNMP Exporter
    ufw --force enable
    log_info "Firewall dikonfigurasi."
}

function cleanup() {
    log_step "Membersihkan file instalasi sementara..."
    (rm -f /tmp/prometheus-*.tar.gz \
           /tmp/snmp_exporter-*.tar.gz \
           /tmp/grafana_*.deb) &> /dev/null &
    start_spinner
    log_info "File sementara telah dihapus."
}


# ------------------------- Eksekusi Utama --------------------------
function main() {
    # --- MULAI: Input Interaktif ---
    echo -e "\n\e[1;33m===================================================\e[0m"
    echo -e "\e[1;33m  Instalasi Prometheus, Grafana, SNMP Exporter     \e[0m"
    echo -e "\e[1;33m===================================================\e[0m"
    echo -e "\n\e[1;36mSilakan masukkan detail konfigurasi target:\e[0m"

    read -p "  -> Masukkan IP Address MikroTik: " MIKROTIK_TARGET
    if [ -z "$MIKROTIK_TARGET" ]; then
        echo -e "\n\e[1;31mIP Address tidak boleh kosong. Skrip berhenti.\e[0m"
        exit 1
    fi

    read -p "  -> Masukkan Komunitas SNMP MikroTik [default: public]: " SNMP_COMMUNITY
    SNMP_COMMUNITY=${SNMP_COMMUNITY:-public}
    # --- SELESAI: Input Interaktif ---

    install_dependencies
    setup_users_and_dirs
    install_prometheus
    install_snmp_exporter
    install_grafana
    configure_services
    setup_services
    configure_firewall
    cleanup

    IP=$(hostname -I | awk '{print $1}')
    echo -e "\n \e[1;32mINSTALASI SELESAI!\e[0m"
    echo "-------------------------------------------"
    echo "Prometheus aktif di: http://$IP:9090"
    echo "Grafana aktif di:    http://$IP:3000"
    echo "SNMP Exporter:       http://$IP:9116"
    echo "Login Grafana: admin / admin"
    echo "-------------------------------------------"
    echo "Target MikroTik yang dimonitor: $MIKROTIK_TARGET"
    echo "Silakan import dashboard MikroTik di Grafana (ID: 11029 atau 7497)."
}

main
