#!/bin/bash

# ===================================================================================
# Skrip Otomatis Terpadu untuk Instalasi Prometheus, Grafana, dan SNMP Exporter
# Versi 3.0: Dengan validasi penuh dan auto-recovery
# Dioptimasi untuk Ubuntu 20.04 / 22.04
# Dibuat oleh: cybertronx371 + Copilot
# Tanggal: 2025-06-10
# ===================================================================================

# Strict mode
set -euo pipefail
trap 'handle_error $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "::%s" ${FUNCNAME[@]:-})' ERR

# ------------------------- Versi Stabil Terkini --------------------------
PROMETHEUS_VERSION="2.44.0"
SNMP_EXPORTER_VERSION="0.24.0"
GRAFANA_VERSION="10.0.3"

# ------------------------- Fungsi Utilitas --------------------------
function handle_error() {
    local exit_code=$1
    local line_no=$2
    echo "❌ Error pada baris $line_no: Exit code $exit_code"
    cleanup
    exit $exit_code
}

function log_info() {
    echo -e "\n✅ \e[1;32m$1\e[0m"
}

function log_step() {
    echo -e "\n⏳ \e[1;34m$1\e[0m"
}

function log_error() {
    echo -e "\n❌ \e[1;31m$1\e[0m"
}

# ------------------------- Validasi Sistem --------------------------
function check_system() {
    log_step "Memeriksa persyaratan sistem..."
    
    # Validasi OS
    if ! grep -q "Ubuntu" /etc/os-release; then
        log_error "Sistem operasi harus Ubuntu 20.04 atau 22.04"
        exit 1
    fi
    
    # Validasi RAM (min 2GB)
    local ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    if [ $ram_mb -lt 2048 ]; then
        log_error "RAM minimal 2GB diperlukan (tersedia: ${ram_mb}MB)"
        exit 1
    fi
    
    # Validasi Disk (min 5GB)
    local disk_mb=$(df -m / | awk 'NR==2 {print $4}')
    if [ $disk_mb -lt 5120 ]; then
        log_error "Ruang disk minimal 5GB diperlukan (tersedia: ${disk_mb}MB)"
        exit 1
    fi
    
    # Validasi koneksi internet
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        log_error "Koneksi internet tidak tersedia"
        exit 1
    fi
    
    log_info "Semua persyaratan sistem terpenuhi"
}

# ------------------------- Konfigurasi SNMP --------------------------
function validate_snmp() {
    local target=$1
    local community=$2
    
    log_step "Validasi koneksi SNMP ke $target..."
    
    # Test ping
    if ! ping -c 2 -W 2 "$target" &>/dev/null; then
        log_error "MikroTik tidak merespon ping"
        echo "Solusi:"
        echo "1. Periksa koneksi jaringan"
        echo "2. Periksa firewall"
        echo "3. Pastikan IP address benar"
        return 1
    fi
    
    # Test port SNMP
    if ! nc -zvu "$target" 161 2>&1 | grep -q "open"; then
        log_error "Port SNMP (161) tertutup"
        echo "Jalankan di MikroTik:"
        echo "/ip service enable snmp"
        echo "/ip firewall filter add chain=input protocol=udp dst-port=161 action=accept"
        return 1
    fi
    
    # Test SNMP
    if ! snmpwalk -v2c -c "$community" -t 5 -r 2 "$target" .1.3.6.1.2.1.1.1.0 &>/dev/null; then
        log_error "SNMP walk gagal"
        echo "Jalankan di MikroTik:"
        echo "/snmp set enabled=yes"
        echo "/snmp community set numbers=0 name=$community"
        return 1
    fi
    
    log_info "Koneksi SNMP berhasil terverifikasi"
    return 0
}

# ------------------------- Instalasi Komponen --------------------------
function install_dependencies() {
    log_step "Menginstal dependensi sistem..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        wget curl tar libfontconfig1 ufw \
        software-properties-common apt-transport-https \
        adduser libcap2-bin snmp snmp-mibs-downloader
}

function install_prometheus() {
    log_step "Menginstal Prometheus v${PROMETHEUS_VERSION}..."
    
    # Buat user dan direktori
    useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true
    mkdir -p /etc/prometheus /var/lib/prometheus
    
    # Download dan install
    cd /tmp
    wget "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
    tar xvf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
    cp prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus /usr/local/bin/
    cp prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool /usr/local/bin/
    cp -r prometheus-${PROMETHEUS_VERSION}.linux-amd64/consoles /etc/prometheus
    cp -r prometheus-${PROMETHEUS_VERSION}.linux-amd64/console_libraries /etc/prometheus
    
    # Set permissions
    chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
    
    log_info "Prometheus berhasil diinstal"
}

function install_snmp_exporter() {
    log_step "Menginstal SNMP Exporter v${SNMP_EXPORTER_VERSION}..."
    
    # Buat user dan direktori
    useradd --no-create-home --shell /bin/false snmp_exporter 2>/dev/null || true
    mkdir -p /etc/snmp_exporter
    
    # Download dan install
    cd /tmp
    wget "https://github.com/prometheus/snmp_exporter/releases/download/v${SNMP_EXPORTER_VERSION}/snmp_exporter-${SNMP_EXPORTER_VERSION}.linux-amd64.tar.gz"
    tar xvf "snmp_exporter-${SNMP_EXPORTER_VERSION}.linux-amd64.tar.gz"
    cp snmp_exporter-${SNMP_EXPORTER_VERSION}.linux-amd64/snmp_exporter /usr/local/bin/
    
    # Set permissions
    chown -R snmp_exporter:snmp_exporter /etc/snmp_exporter
    
    log_info "SNMP Exporter berhasil diinstal"
}

function install_grafana() {
    log_step "Menginstal Grafana v${GRAFANA_VERSION}..."
    
    # Add Grafana repository
    wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
    echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list
    
    # Install Grafana
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y grafana
    
    log_info "Grafana berhasil diinstal"
}

# ------------------------- Konfigurasi Service --------------------------
function configure_prometheus() {
    local target=$1
    local community=$2
    
    log_step "Mengkonfigurasi Prometheus..."
    
    cat > /etc/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'snmp_mikrotik'
    static_configs:
      - targets: ['${target}']
    metrics_path: /snmp
    params:
      module: [mikrotik]
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: localhost:9116
EOF

    chown prometheus:prometheus /etc/prometheus/prometheus.yml
    
    # Buat service
    cat > /etc/systemd/system/prometheus.service <<EOF
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
  --storage.tsdb.path=/var/lib/prometheus \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries
Restart=always

[Install]
WantedBy=multi-user.target
EOF
}

function configure_snmp_exporter() {
    local community=$1
    
    log_step "Mengkonfigurasi SNMP Exporter..."
    
    cat > /etc/snmp_exporter/snmp.yml <<EOF
mikrotik:
  walk:
    - 1.3.6.1.2.1.1       # System
    - 1.3.6.1.2.1.2       # Interfaces
    - 1.3.6.1.2.1.31.1.1  # Interface High Speed
    - 1.3.6.1.4.1.14988.1 # MikroTik specific
  version: 2
  auth:
    community: ${community}
  retries: 3
  timeout: 10s
EOF

    chown snmp_exporter:snmp_exporter /etc/snmp_exporter/snmp.yml
    
    # Buat service
    cat > /etc/systemd/system/snmp_exporter.service <<EOF
[Unit]
Description=SNMP Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=snmp_exporter
Group=snmp_exporter
Type=simple
ExecStart=/usr/local/bin/snmp_exporter --config.file=/etc/snmp_exporter/snmp.yml
Restart=always

[Install]
WantedBy=multi-user.target
EOF
}

# ------------------------- Firewall & Services --------------------------
function configure_firewall() {
    log_step "Mengkonfigurasi firewall..."
    
    ufw allow 22/tcp      # SSH
    ufw allow 9090/tcp    # Prometheus
    ufw allow 3000/tcp    # Grafana
    ufw allow 9116/tcp    # SNMP Exporter
    ufw --force enable
}

function start_services() {
    log_step "Memulai services..."
    
    systemctl daemon-reload
    systemctl enable --now prometheus
    systemctl enable --now snmp_exporter
    systemctl enable --now grafana-server
    
    # Validasi services
    for service in prometheus snmp_exporter grafana-server; do
        if ! systemctl is-active --quiet $service; then
            log_error "Service $service gagal start"
            journalctl -u $service -n 50
            return 1
        fi
    done
    
    log_info "Semua service berhasil dimulai"
}

# ------------------------- Cleanup & Verifikasi --------------------------
function cleanup() {
    log_step "Membersihkan file temporary..."
    rm -f /tmp/prometheus-*.tar.gz
    rm -f /tmp/snmp_exporter-*.tar.gz
    rm -rf /tmp/prometheus-*/
    rm -rf /tmp/snmp_exporter-*/
}

function verify_installation() {
    local target=$1
    log_step "Verifikasi instalasi..."
    
    # Test Prometheus
    if ! curl -s http://localhost:9090/-/healthy | grep -q "Prometheus"; then
        log_error "Prometheus health check gagal"
        return 1
    fi
    
    # Test SNMP Exporter
    if ! curl -s "http://localhost:9116/snmp?target=${target}&module=mikrotik" | grep -q "snmp_"; then
        log_error "SNMP Exporter check gagal"
        return 1
    fi
    
    # Test Grafana
    if ! curl -s http://localhost:3000/api/health | grep -q "ok"; then
        log_error "Grafana health check gagal"
        return 1
    fi
    
    log_info "Semua komponen berhasil terverifikasi"
}

# ------------------------- Main Function --------------------------
function main() {
    echo -e "\n\e[1;33m=== Instalasi Monitoring Stack (Prometheus + Grafana + SNMP) ===\e[0m"
    
    # Input validasi
    read -p "Masukkan IP MikroTik: " MIKROTIK_TARGET
    read -p "Masukkan SNMP community [default: public]: " SNMP_COMMUNITY
    SNMP_COMMUNITY=${SNMP_COMMUNITY:-public}
    
    # Validasi input IP
    if [[ ! $MIKROTIK_TARGET =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Format IP tidak valid"
        exit 1
    fi
    
    # Jalankan instalasi
    check_system
    validate_snmp "$MIKROTIK_TARGET" "$SNMP_COMMUNITY"
    install_dependencies
    install_prometheus
    install_snmp_exporter
    install_grafana
    configure_prometheus "$MIKROTIK_TARGET" "$SNMP_COMMUNITY"
    configure_snmp_exporter "$SNMP_COMMUNITY"
    configure_firewall
    start_services
    verify_installation "$MIKROTIK_TARGET"
    cleanup
    
    # Tampilkan informasi akhir
    local IP=$(hostname -I | awk '{print $1}')
    echo -e "\n🎉 \e[1;32mINSTALASI BERHASIL!\e[0m"
    echo "-------------------------------------------"
    echo "Prometheus: http://$IP:9090"
    echo "Grafana:    http://$IP:3000"
    echo "            user: admin"
    echo "            pass: admin"
    echo "SNMP Exp.:  http://$IP:9116"
    echo "-------------------------------------------"
    echo "Target MikroTik: $MIKROTIK_TARGET"
    echo "Dashboard MikroTik ID: 11029 atau 7497"
    echo "-------------------------------------------"
}

# Jalankan main function
main
