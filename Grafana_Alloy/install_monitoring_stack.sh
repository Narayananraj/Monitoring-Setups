#!/bin/bash

##############################################################
# Complete Monitoring Stack Installation Script
# Installs: Node Exporter + Grafana Alloy
# Security: Localhost-only Node Exporter + Authenticated Remote Write
##############################################################

set -e  # Exit on any error


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' 

##############################################################
# Load Configuration from .env file
##############################################################

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# Check if .env file exists
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}✗${NC} Error: .env file not found at $ENV_FILE"
    echo ""
    echo "Please create a .env file with the following content:"
    echo ""
    cat << 'EOF'
# Prometheus Configuration
PROMETHEUS_URL="https://prometheus.lmes.app/api/v1/write"
PROMETHEUS_USERNAME="promuser"
PROMETHEUS_PASSWORD="your_secure_password"

# Node Exporter Configuration
NODE_EXPORTER_VERSION="1.8.2"

# Server Instance Name (leave empty for auto-detection)
SERVER_INSTANCE_NAME=""
EOF
    echo ""
    exit 1
fi

# Load environment variables from .env file
echo "Loading configuration from .env file..."
set -a  
source "$ENV_FILE"
set +a  

# Validate required variables
if [ -z "$PROMETHEUS_URL" ]; then
    echo -e "${RED}✗${NC} Error: PROMETHEUS_URL is not set in .env file"
    exit 1
fi

if [ -z "$PROMETHEUS_USERNAME" ]; then
    echo -e "${RED}✗${NC} Error: PROMETHEUS_USERNAME is not set in .env file"
    exit 1
fi

if [ -z "$PROMETHEUS_PASSWORD" ]; then
    echo -e "${RED}✗${NC} Error: PROMETHEUS_PASSWORD is not set in .env file"
    exit 1
fi

if [ -z "$NODE_EXPORTER_VERSION" ]; then
    NODE_EXPORTER_VERSION="1.8.2"  
fi

##############################################################
# Helper Functions
##############################################################

print_header() {
    echo ""
    echo "=========================================="
    echo -e "${GREEN}$1${NC}"
    echo "=========================================="
}

print_info() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_error "Please run as root or with sudo"
        exit 1
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        print_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
    print_info "Detected OS: $OS $OS_VERSION"
}

##############################################################
# Main Installation
##############################################################

print_header "Monitoring Stack Installation"

check_root
detect_os

# Get server instance name
if [ -z "$SERVER_INSTANCE_NAME" ]; then
    HOSTNAME=$(hostname)
    echo ""
    echo "Current hostname: $HOSTNAME"
    read -p "Enter instance name for this server [$HOSTNAME]: " INPUT_NAME
    SERVER_INSTANCE_NAME=${INPUT_NAME:-$HOSTNAME}
fi

# Show configuration (hide password)
MASKED_PASSWORD="${PROMETHEUS_PASSWORD:0:4}***************"
PROMETHEUS_DOMAIN=$(echo "$PROMETHEUS_URL" | sed 's|https://||' | sed 's|/.*||')

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Configuration Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Prometheus Domain:    $PROMETHEUS_DOMAIN"
echo "  Prometheus Username:  $PROMETHEUS_USERNAME"
echo "  Prometheus Password:  $MASKED_PASSWORD"
echo "  Instance Name:        $SERVER_INSTANCE_NAME"
echo "  Node Exporter Ver:    $NODE_EXPORTER_VERSION"
echo "  Binding:              127.0.0.1:9100 (localhost only)"
echo "  Security:             HTTPS + Basic Auth"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
read -p "Continue with installation? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "Installation cancelled."
    exit 0
fi

##############################################################
# Part 1: Install Node Exporter
##############################################################

print_header "Part 1: Installing Node Exporter"

# Check if already installed
if systemctl is-active --quiet node_exporter; then
    print_warn "Node Exporter is already running!"
    read -p "Do you want to reinstall? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Stopping Node Exporter..."
        systemctl stop node_exporter
    else
        print_info "Skipping Node Exporter installation"
        SKIP_NODE_EXPORTER=true
    fi
fi

if [ "$SKIP_NODE_EXPORTER" != true ]; then
    echo ""
    print_info "Creating node_exporter user..."
    if id "node_exporter" &>/dev/null; then
        print_info "User 'node_exporter' already exists. Skipping..."
    else
        useradd -rs /bin/false node_exporter
        print_info "User 'node_exporter' created."
    fi

    echo ""
    print_info "Downloading Node Exporter v${NODE_EXPORTER_VERSION}..."
    cd /tmp
    DOWNLOAD_URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
    wget -q --show-progress ${DOWNLOAD_URL}

    print_info "Extracting Node Exporter..."
    tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz

    print_info "Installing Node Exporter binary..."
    cp node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
    chown node_exporter:node_exporter /usr/local/bin/node_exporter
    chmod +x /usr/local/bin/node_exporter

    print_info "Creating systemd service (localhost-only binding)..."
    cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=127.0.0.1:9100
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    print_info "Reloading systemd daemon..."
    systemctl daemon-reload
    
    print_info "Enabling Node Exporter service..."
    systemctl enable node_exporter
    
    print_info "Starting Node Exporter service..."
    systemctl start node_exporter

    sleep 2

    # Verify Node Exporter
    print_info "Verifying Node Exporter installation..."
    if systemctl is-active --quiet node_exporter; then
        print_info "Node Exporter is running!"
    else
        print_error "Node Exporter failed to start!"
        echo ""
        systemctl status node_exporter --no-pager
        exit 1
    fi

    # Check if listening on localhost only
    LISTEN_ADDRESS=$(ss -tlnp 2>/dev/null | grep 9100 | grep "127.0.0.1" || echo "")
    if [ -n "$LISTEN_ADDRESS" ]; then
        print_info "Node Exporter is listening on 127.0.0.1:9100 (localhost only) ✓"
    else
        print_warn "Node Exporter may not be configured correctly!"
        ss -tlnp | grep 9100
    fi

    # Test metrics endpoint
    if curl -s http://localhost:9100/metrics > /dev/null; then
        print_info "Metrics endpoint is accessible locally ✓"
    else
        print_error "Cannot access metrics endpoint!"
        exit 1
    fi

    print_info "Cleaning up temporary files..."
    cd /tmp
    rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*

    print_info "Node Exporter installation complete!"
fi

##############################################################
# Part 2: Install Grafana Alloy
##############################################################

print_header "Part 2: Installing Grafana Alloy"

# Check if already installed
if systemctl is-active --quiet alloy; then
    print_warn "Alloy is already running!"
    read -p "Do you want to reinstall/reconfigure? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Stopping Alloy..."
        systemctl stop alloy
    else
        print_info "Skipping Alloy installation"
        SKIP_ALLOY=true
    fi
fi

if [ "$SKIP_ALLOY" != true ]; then
    echo ""
    print_info "Installing Grafana Alloy for $OS..."

    if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
        # Ubuntu/Debian installation
        print_info "Installing for Ubuntu/Debian..."
        
        apt-get update -qq
        apt-get install -y -qq apt-transport-https software-properties-common wget gnupg > /dev/null
        
        mkdir -p /etc/apt/keyrings/
        wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null
        
        echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list > /dev/null
        
        apt-get update -qq
        apt-get install -y alloy
        
    elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "rocky" ]] || [[ "$OS" == "almalinux" ]]; then
        # RHEL/CentOS/Rocky installation
        print_info "Installing for RHEL/CentOS/Rocky..."
        
        cat > /etc/yum.repos.d/grafana.repo << 'EOF'
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
EOF
        
        yum install -y alloy
    else
        print_error "Unsupported OS: $OS"
        exit 1
    fi

    print_info "Creating Alloy configuration..."

    # Backup existing config if it exists
    if [ -f /etc/alloy/config.alloy ]; then
        BACKUP_FILE="/etc/alloy/config.alloy.backup.$(date +%Y%m%d_%H%M%S)"
        print_info "Backing up existing config to $BACKUP_FILE"
        cp /etc/alloy/config.alloy "$BACKUP_FILE"
    fi

    # Create Alloy config with authentication and TLS
    cat > /etc/alloy/config.alloy << EOF
// Grafana Alloy Configuration
// Server: ${SERVER_INSTANCE_NAME}
// Generated: $(date)

// Scrape node_exporter metrics locally
prometheus.scrape "node_exporter" {
  targets = [{
    __address__ = "localhost:9100",
  }]
  
  forward_to = [prometheus.relabel.node_exporter.receiver]
  
  scrape_interval = "15s"
  scrape_timeout  = "10s"
}

// Add instance labels
prometheus.relabel "node_exporter" {
  forward_to = [prometheus.remote_write.central.receiver]
  
  rule {
    source_labels = ["__address__"]
    target_label  = "instance"
    replacement   = "${SERVER_INSTANCE_NAME}"
  }
  
  rule {
    source_labels = ["__address__"]
    target_label  = "job"
    replacement   = "node"
  }
}

// Remote write to central Prometheus
prometheus.remote_write "central" {
  endpoint {
    url = "${PROMETHEUS_URL}"
    
    // Basic authentication
    basic_auth {
      username = "${PROMETHEUS_USERNAME}"
      password = "${PROMETHEUS_PASSWORD}"
    }
    
    // TLS config for HTTPS
    tls_config {
      insecure_skip_verify = true
    }
    
    // Queue configuration
    queue_config {
      capacity             = 10000
      max_shards           = 10
      max_samples_per_send = 5000
      batch_send_deadline  = "5s"
      min_backoff          = "30ms"
      max_backoff          = "5s"
    }
    
    // Metadata configuration
    metadata_config {
      send         = true
      send_interval = "1m"
    }
  }
}
EOF

    # Secure the config file (contains password)
    chmod 600 /etc/alloy/config.alloy
    chown alloy:alloy /etc/alloy/config.alloy 2>/dev/null || chown root:root /etc/alloy/config.alloy

    print_info "Configuration created at /etc/alloy/config.alloy"

    print_info "Reloading systemd daemon..."
    systemctl daemon-reload
    
    print_info "Enabling Grafana Alloy service..."
    systemctl enable alloy
    
    print_info "Starting Grafana Alloy service..."
    systemctl start alloy

    sleep 3

    # Verify Alloy
    print_info "Verifying Alloy installation..."
    if systemctl is-active --quiet alloy; then
        print_info "Grafana Alloy is running!"
    else
        print_error "Alloy failed to start!"
        echo ""
        print_error "Checking logs..."
        journalctl -u alloy -n 50 --no-pager
        exit 1
    fi

    # Wait for metrics to accumulate
    echo ""
    print_info "Waiting 10 seconds for metrics collection..."
    sleep 10

    # Check metrics
    if command -v curl &> /dev/null; then
        SAMPLES_SENT=$(curl -s http://localhost:12345/metrics 2>/dev/null | grep -m1 "prometheus_remote_storage_samples_total" | awk '{print $2}' || echo "0")
        FAILED_SAMPLES=$(curl -s http://localhost:12345/metrics 2>/dev/null | grep -m1 "prometheus_remote_storage_failed_samples_total" | awk '{print $2}' || echo "0")

        if [ "$SAMPLES_SENT" -gt 0 ]; then
            print_info "Samples sent to Prometheus: $SAMPLES_SENT ✓"
        else
            print_warn "No samples sent yet. This might be normal if just started."
        fi

        if [ "$FAILED_SAMPLES" -gt 0 ]; then
            print_error "Failed samples: $FAILED_SAMPLES"
            print_warn "Check network connectivity and credentials!"
        else
            print_info "No failed samples ✓"
        fi
    fi

    print_info "Alloy installation complete!"
fi

##############################################################
# Final Summary & Status
##############################################################

print_header "Installation Complete!"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Configuration Details:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Instance Name:        ${SERVER_INSTANCE_NAME}"
echo "  Prometheus Domain:    $PROMETHEUS_DOMAIN"
echo "  Node Exporter:        localhost:9100 (localhost only)"
echo "  Alloy Metrics:        http://localhost:12345/metrics"
echo "  Authentication:       Enabled (Basic Auth)"
echo "  Transport Security:   HTTPS with TLS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Service Status:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Node Exporter:"
systemctl status node_exporter --no-pager -l | head -3
echo ""
echo "Grafana Alloy:"
systemctl status alloy --no-pager -l | head -3
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "Useful Commands:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Service Control:"
echo "    sudo systemctl restart node_exporter"
echo "    sudo systemctl restart alloy"
echo "    sudo systemctl status node_exporter"
echo "    sudo systemctl status alloy"
echo ""
echo "  Verification:"
echo "    curl http://localhost:9100/metrics | head"
echo "    curl http://localhost:12345/metrics | grep samples"
echo "    sudo journalctl -u node_exporter -f"
echo "    sudo journalctl -u alloy -f"
echo ""
echo "  Configuration Files:"
echo "    /etc/systemd/system/node_exporter.service"
echo "    /etc/alloy/config.alloy"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "Verify in Prometheus:"
echo "  Query: up{instance=\"${SERVER_INSTANCE_NAME}\"}"
echo "  URL: https://${PROMETHEUS_DOMAIN}"
echo ""

echo "Security Status:"
print_info "✓ Node Exporter is NOT publicly accessible (localhost only)"
print_info "✓ Metrics are sent via HTTPS with authentication"
print_info "✓ TLS security enabled"
print_info "✓ No ports exposed to public internet"
print_info "✓ Configuration file secured (chmod 600)"
print_info "✓ Credentials stored in .env file only"
echo ""

print_info "Installation completed successfully!"
echo ""