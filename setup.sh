#!/usr/bin/env bash
# Optimized BigPython installation ==> Installing Docker, NPM, and Portainer
set -e
set -o pipefail
# Trap to catch errors and print the line number
trap 'echo -e "\n\033[1;31m💥 Script failed at line $LINENO (Command: $BASH_COMMAND)\033[0m\n"' ERR

# --- Configuration Variables ---
DOCKER_NETWORK="kitzone-net"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Logging Functions
log_info() { echo -e "${BLUE}INFO: $1${NC}"; }
log_success() { echo -e "${GREEN}SUCCESS: $1${NC}"; }
log_warning() { echo -e "${YELLOW}WARNING: $1${NC}"; }
log_error() { echo -e "\n${RED}ERROR: $1${NC}\n"; exit 1; }

# --- Helper Functions ---

print_banner() {
cat << "EOF"

 ╔════════════════════════════════════════════════════╗
 ║         🚀 KITZONE SERVER SETUP v1.1 🚀         ║
 ║      (Docker, NPM, Portainer ONLY)                 ║
 ╚════════════════════════════════════════════════════╝

EOF
}

fix_hostname_resolution() {
    log_info "Fixing hostname resolution in /etc/hosts..."
    local HOSTNAME=$(hostname)
    # Check if a line starting with 127.0.0.1 contains the hostname
    if ! grep -q "^127\.0\.0\.1.*$HOSTNAME" /etc/hosts; then
        echo "127.0.0.1 $HOSTNAME" >> /etc/hosts
        log_success "Hostname $HOSTNAME added to /etc/hosts."
    else
        log_success "Hostname resolution is already correct."
    fi
}

install_prerequisites() {
    log_info "Updating system packages and installing prerequisites (tmux, nano, git, curl, etc.)..."
    
    # Update and Upgrade system
    apt-get update -y
    log_info "System packages updated."
    apt-get upgrade -y
    log_info "System packages upgraded."

    # Install necessary tools
    apt_packages="apt-transport-https ca-certificates curl gnupg lsb-release unzip git python3-pip nano tmux"
    if ! apt-get install -y $apt_packages; then
        log_error "Failed to install general prerequisites: $apt_packages"
    fi
    log_success "Prerequisites installed successfully."
}

install_docker() {
    if command -v docker &> /dev/null && command -v docker compose &> /dev/null; then
        log_success "Docker and Docker Compose Plugin are already installed."
        return
    fi
    log_info "Installing Docker Engine and Docker Compose Plugin..."
    
    # 1. Add Docker's GPG key
    install -m 0755 -d /etc/apt/keyrings
    if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        log_error "Failed to download Docker GPG key."
    fi
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # 2. Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # 3. Install packages
    apt-get update -y
    if ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
        log_error "Failed to install Docker components."
    fi
    
    # 4. Start and enable Docker service
    systemctl enable docker && systemctl start docker
    
    log_success "Docker and Docker Compose Plugin installed and running."
}

create_docker_network() {
    log_info "Creating Docker network '$DOCKER_NETWORK' if it doesn't exist..."
    if ! docker network ls | grep -q "$DOCKER_NETWORK"; then
        if docker network create $DOCKER_NETWORK >/dev/null; then
            log_success "Docker network '$DOCKER_NETWORK' created."
        else
            log_error "Failed to create Docker network '$DOCKER_NETWORK'."
        fi
    else
        log_success "Docker network '$DOCKER_NETWORK' already exists."
    fi
}

install_npm() {
    log_info "Deploying Nginx Proxy Manager (NPM)..."
    
    # Check if NPM is already running
    if docker ps -a --format '{{.Names}}' | grep -q "^npm$"; then
        log_warning "NPM container already exists. Skipping deployment."
        return
    fi

    mkdir -p /opt/npm/letsencrypt
    docker volume create npm-data >/dev/null || true

    docker run -d --name=npm --network=$DOCKER_NETWORK --restart=unless-stopped \
      -p 80:80 -p 81:81 -p 443:443 \
      -v npm-data:/data \
      -v /opt/npm/letsencrypt:/etc/letsencrypt \
      jc21/nginx-proxy-manager:latest

    log_success "Nginx Proxy Manager deployed on ports 80, 81 (Admin), and 443."
}

install_portainer() {
    log_info "Deploying Portainer CE..."
    
    # Check if Portainer is already running
    if docker ps -a --format '{{.Names}}' | grep -q "^portainer$"; then
        log_warning "Portainer container already exists. Skipping deployment."
        return
    fi
    
    docker volume create portainer_data >/dev/null || true

    docker run -d --name=portainer --network=$DOCKER_NETWORK --restart=unless-stopped \
      -p 9000:9000 \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v portainer_data:/data \
      portainer/portainer-ce:latest

    log_success "Portainer CE deployed on port 9000."
}

final_summary() {
    # Try to get the public IP or use the local IP as a fallback
    IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' | head -n 1)
    
    echo -e "\n${GREEN}========================================================${NC}"
    echo -e "${GREEN}✅ Server setup completed successfully!${NC}"
    echo -e "${GREEN}========================================================${NC}\n"

    echo -e "${YELLOW}Docker network: $DOCKER_NETWORK${NC}\n"

    cat <<EOF
${YELLOW}>> Nginx Proxy Manager (NPM):${NC}
  🔗 Access Admin UI: http://$IP:81
  📧 Default Email:   admin@example.com
  🔐 Default Password: changeme
  📝 Please log in and change the default credentials immediately!

${YELLOW}>> Portainer CE (Docker Management):${NC}
  🔗 Access UI: http://$IP:9000
  📝 You will be prompted to create an admin user on first login.

${BLUE}Useful Docker commands:${NC}
  - View all running containers: docker ps
  - View logs for NPM: docker logs -f npm
  - Restart Portainer: docker restart portainer

EOF
}

main() {
    # Check for root privileges
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root. Please use 'sudo bash <script_name>'."
    fi

    print_banner
    fix_hostname_resolution
    install_prerequisites
    install_docker
    create_docker_network
    install_npm
    install_portainer
    final_summary
}

main
