#!/bin/bash
# Proxmox Template Creator - Ansible Module
# Deploy and manage infrastructure using Ansible

set -e

# Script version
VERSION="0.1.0"

# Directory where the script is located
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
export SCRIPT_DIR

# Logging function
log() {
    local level="$1"; shift
    local color=""
    local reset="\033[0m"
    case $level in
        INFO)
            color="\033[0;32m" # Green
            ;;
        WARN)
            color="\033[0;33m" # Yellow
            ;;
        ERROR)
            color="\033[0;31m" # Red
            ;;
        *)
            color=""
            ;;
    esac
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*${reset}"
}

# Error handling function
handle_error() {
    local exit_code="$1"
    local line_no="$2"
    log "ERROR" "An error occurred on line $line_no with exit code $exit_code"
    if [ -t 0 ]; then  # If running interactively
        whiptail --title "Error" --msgbox "An error occurred. Check the logs for details." 10 60 3>&1 1>&2 2>&3
    fi
    exit "$exit_code"
}

# Set up error trap
trap 'handle_error $? $LINENO' ERR

# Parse command line arguments
TEST_MODE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --test)
            TEST_MODE=1
            shift
            ;;
        --help|-h)
            cat << EOF
Proxmox Template Creator - Ansible Module v${VERSION}

Usage: $(basename "$0") [OPTIONS]

Options:
  --test              Run in test mode (no actual deployments)
  --help, -h          Show this help message

Functions:
  - Install Ansible if not present
  - Discover available Ansible playbooks
  - Collect and validate variables
  - Manage Ansible roles
  - Execute playbook workflows

EOF
            exit 0
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            echo "Try '$(basename "$0") --help' for more information."
            exit 1
            ;;
    esac
done

# Configuration
ANSIBLE_PLAYBOOKS_DIR="/opt/ansible/playbooks"
ANSIBLE_ROLES_DIR="/opt/ansible/roles"

# Function to check if Ansible is installed
check_ansible() {
    if command -v ansible >/dev/null 2>&1; then
        local version
        version=$(ansible --version | head -n1 | awk '{print $3}')
        log "INFO" "Ansible is installed (version: $version)"
        return 0
    else
        log "INFO" "Ansible is not installed"
        return 1
    fi
}

# Function to install Ansible
install_ansible() {
    log "INFO" "Installing Ansible..."
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would install Ansible"
        return 0
    fi
    
    # Update package index
    apt-get update
    
    # Install required packages
    apt-get install -y software-properties-common
    
    # Add Ansible PPA and install
    add-apt-repository --yes --update ppa:ansible/ansible
    apt-get install -y ansible
    
    # Install additional useful collections
    ansible-galaxy collection install community.general
    ansible-galaxy collection install ansible.posix
    
    # Verify installation
    if ansible --version >/dev/null 2>&1; then
        log "INFO" "Ansible installed successfully"
        return 0
    else
        log "ERROR" "Ansible installation failed"
        return 1
    fi
}

# Function to discover available Ansible playbooks
discover_playbooks() {
    log "INFO" "Discovering available Ansible playbooks..."
    
    local playbooks_found=()
    
    # Check for playbooks in the project directory
    if [ -d "$SCRIPT_DIR/../ansible" ]; then
        log "INFO" "Found project ansible directory"
        for playbook_file in "$SCRIPT_DIR/../ansible"/*.yml "$SCRIPT_DIR/../ansible"/*.yaml; do
            if [ -f "$playbook_file" ]; then
                local playbook_name
                playbook_name=$(basename "$playbook_file" | sed 's/\.(yml|yaml)$//')
                playbooks_found+=("$playbook_name")
                log "INFO" "Found playbook: $playbook_name"
            fi
        done
    fi
    
    # Check for playbooks in system ansible directory
    if [ -d "$ANSIBLE_PLAYBOOKS_DIR" ]; then
        for playbook_file in "$ANSIBLE_PLAYBOOKS_DIR"/*.yml "$ANSIBLE_PLAYBOOKS_DIR"/*.yaml; do
            if [ -f "$playbook_file" ]; then
                local playbook_name
                playbook_name=$(basename "$playbook_file" | sed 's/\.(yml|yaml)$//')
                playbooks_found+=("$playbook_name")
                log "INFO" "Found system playbook: $playbook_name"
            fi
        done
    fi
    
    if [ ${#playbooks_found[@]} -eq 0 ]; then
        log "WARN" "No Ansible playbooks found"
        return 1
    fi
    
    printf '%s\n' "${playbooks_found[@]}"
    return 0
}

# Function to discover available Ansible roles
discover_roles() {
    log "INFO" "Discovering available Ansible roles..."
    
    local roles_found=()
    
    # Check for roles in the project directory
    if [ -d "$SCRIPT_DIR/../ansible/roles" ]; then
        log "INFO" "Found project ansible roles directory"
        for role_dir in "$SCRIPT_DIR/../ansible/roles"/*; do
            if [ -d "$role_dir" ] && [ -f "$role_dir/tasks/main.yml" ]; then
                local role_name
                role_name=$(basename "$role_dir")
                roles_found+=("$role_name")
                log "INFO" "Found role: $role_name"
            fi
        done
    fi
    
    # Check for roles in system ansible directory
    if [ -d "$ANSIBLE_ROLES_DIR" ]; then
        for role_dir in "$ANSIBLE_ROLES_DIR"/*; do
            if [ -d "$role_dir" ] && [ -f "$role_dir/tasks/main.yml" ]; then
                local role_name
                role_name=$(basename "$role_dir")
                roles_found+=("$role_name")
                log "INFO" "Found system role: $role_name"
            fi
        done
    fi
    
    if [ ${#roles_found[@]} -eq 0 ]; then
        log "WARN" "No Ansible roles found"
        return 1
    fi
    
    printf '%s\n' "${roles_found[@]}"
    return 0
}

# Function to collect variables for a playbook
collect_variables() {
    local playbook_path="$1"
    
    log "INFO" "Collecting variables for playbook: $(basename "$playbook_path")"
    
    # Check for group_vars and host_vars
    local playbook_dir
    playbook_dir=$(dirname "$playbook_path")
    
    local vars_file="$playbook_dir/vars.yml"
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would collect variables for playbook"
        return 0
    fi
    
    # Create basic inventory if it doesn't exist
    local inventory_file="$playbook_dir/inventory.ini"
    if [ ! -f "$inventory_file" ]; then
        log "INFO" "Creating basic inventory file: $inventory_file"
        cat > "$inventory_file" << EOF
[proxmox_hosts]
# Add your Proxmox hosts here
# Example: 192.168.1.100 ansible_user=root

[all:vars]
# Global variables
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF
    fi
    
    # Interactive variable collection using whiptail
    if [ -t 0 ]; then  # If running interactively
        # Ask for basic configuration
        local target_hosts
        target_hosts=$(whiptail --title "Ansible Variables" --inputbox "Enter target hosts (comma-separated IP addresses or hostnames):" 10 60 3>&1 1>&2 2>&3)
        
        if [ $? -eq 0 ] && [ -n "$target_hosts" ]; then
            # Update inventory file
            echo "" >> "$inventory_file"
            echo "# Hosts added by terraform script" >> "$inventory_file"
            IFS=',' read -ra HOSTS <<< "$target_hosts"
            for host in "${HOSTS[@]}"; do
                host=$(echo "$host" | xargs)  # Trim whitespace
                echo "$host" >> "$inventory_file"
            done
            log "INFO" "Added hosts to inventory: $target_hosts"
        fi
        
        # Ask for ansible user
        local ansible_user
        ansible_user=$(whiptail --title "Ansible Variables" --inputbox "Enter Ansible user (default: root):" 10 60 "root" 3>&1 1>&2 2>&3)
        
        if [ $? -eq 0 ] && [ -n "$ansible_user" ]; then
            echo "ansible_user=$ansible_user" >> "$vars_file"
            log "INFO" "Set ansible_user to '$ansible_user'"
        fi
        
        # Ask for SSH key path
        local ssh_key_path
        ssh_key_path=$(whiptail --title "Ansible Variables" --inputbox "Enter SSH private key path (optional):" 10 60 3>&1 1>&2 2>&3)
        
        if [ $? -eq 0 ] && [ -n "$ssh_key_path" ]; then
            echo "ansible_ssh_private_key_file=$ssh_key_path" >> "$vars_file"
            log "INFO" "Set SSH private key path to '$ssh_key_path'"
        fi
    else
        log "WARN" "Running non-interactively, using default configuration"
    fi
    
    return 0
}

# Function to validate Ansible playbook
validate_playbook() {
    local playbook_path="$1"
    
    log "INFO" "Validating Ansible playbook: $playbook_path"
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would validate Ansible playbook"
        return 0
    fi
    
    local playbook_dir
    playbook_dir=$(dirname "$playbook_path")
    
    # Check for inventory file
    local inventory_file="$playbook_dir/inventory.ini"
    if [ ! -f "$inventory_file" ]; then
        log "ERROR" "No inventory file found: $inventory_file"
        return 1
    fi
    
    # Validate playbook syntax
    if ansible-playbook --syntax-check -i "$inventory_file" "$playbook_path"; then
        log "INFO" "Ansible playbook syntax is valid"
        return 0
    else
        log "ERROR" "Ansible playbook syntax validation failed"
        return 1
    fi
}

# Function to run dry-run (check mode)
dry_run_playbook() {
    local playbook_path="$1"
    
    log "INFO" "Running Ansible playbook dry-run..."
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would run Ansible playbook dry-run"
        return 0
    fi
    
    local playbook_dir
    playbook_dir=$(dirname "$playbook_path")
    local inventory_file="$playbook_dir/inventory.ini"
    
    # Run in check mode
    if ansible-playbook --check -i "$inventory_file" "$playbook_path"; then
        log "INFO" "Ansible playbook dry-run completed successfully"
        return 0
    else
        log "ERROR" "Ansible playbook dry-run failed"
        return 1
    fi
}

# Function to execute Ansible playbook
execute_playbook() {
    local playbook_path="$1"
    
    log "INFO" "Executing Ansible playbook..."
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would execute Ansible playbook"
        return 0
    fi
    
    local playbook_dir
    playbook_dir=$(dirname "$playbook_path")
    local inventory_file="$playbook_dir/inventory.ini"
    
    # Execute playbook
    if ansible-playbook -i "$inventory_file" "$playbook_path"; then
        log "INFO" "Ansible playbook executed successfully"
        return 0
    else
        log "ERROR" "Ansible playbook execution failed"
        return 1
    fi
}

# Function to install Ansible role from Ansible Galaxy
install_role() {
    local role_name="$1"
    
    log "INFO" "Installing Ansible role: $role_name"
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would install Ansible role: $role_name"
        return 0
    fi
    
    # Create roles directory if it doesn't exist
    mkdir -p "$ANSIBLE_ROLES_DIR"
    
    # Install role
    if ansible-galaxy install -p "$ANSIBLE_ROLES_DIR" "$role_name"; then
        log "INFO" "Ansible role installed successfully: $role_name"
        return 0
    else
        log "ERROR" "Ansible role installation failed: $role_name"
        return 1
    fi
}

# Function to show Ansible configuration
show_config() {
    log "INFO" "Showing Ansible configuration..."
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would show Ansible configuration"
        return 0
    fi
    
    echo "Ansible Configuration:"
    echo "====================="
    ansible --version
    echo ""
    echo "Ansible Config File:"
    ansible-config view
    echo ""
    echo "Available Collections:"
    ansible-galaxy collection list
    
    return 0
}

# Function to create sample playbook from template
create_sample_playbook() {
    local template_type="$1"
    local output_file="$2"
    local playbook_name="$3"
    
    log "INFO" "Creating sample playbook: $template_type -> $output_file"
    
    # Ensure directory exists
    mkdir -p "$(dirname "$output_file")"
    
    # Create playbook content based on template type
    case "$template_type" in
        "basic-setup")
            cat > "$output_file" << 'EOF'
---
# Basic System Setup Playbook
# This playbook performs basic system setup tasks including package installation,
# user management, and security hardening.

- name: Basic System Setup
  hosts: all
  become: yes
  vars:
    # Common packages to install
    common_packages:
      - curl
      - wget
      - git
      - vim
      - htop
      - unzip
      - software-properties-common
    
    # User configuration
    admin_user: admin
    admin_groups: 
      - sudo
      - docker
    
  tasks:
    - name: Update package cache
      apt:
        update_cache: yes
        cache_valid_time: 3600
      when: ansible_os_family == "Debian"
    
    - name: Install common packages
      package:
        name: "{{ common_packages }}"
        state: present
    
    - name: Create admin user
      user:
        name: "{{ admin_user }}"
        groups: "{{ admin_groups }}"
        shell: /bin/bash
        create_home: yes
        state: present
    
    - name: Configure SSH for admin user
      authorized_key:
        user: "{{ admin_user }}"
        key: "{{ lookup('file', '~/.ssh/id_rsa.pub') }}"
        state: present
      ignore_errors: yes
    
    - name: Set timezone
      timezone:
        name: UTC
    
    - name: Configure firewall (ufw)
      ufw:
        rule: allow
        port: "{{ item }}"
      loop:
        - "22"
        - "80"
        - "443"
      when: ansible_os_family == "Debian"
    
    - name: Enable firewall
      ufw:
        state: enabled
        policy: deny
      when: ansible_os_family == "Debian"
EOF
            ;;
        "docker-deployment")
            cat > "$output_file" << 'EOF'
---
# Docker Container Deployment Playbook
# This playbook installs Docker and deploys containerized applications

- name: Docker Container Deployment
  hosts: all
  become: yes
  vars:
    docker_compose_version: "2.20.0"
    containers:
      - name: nginx
        image: nginx:latest
        ports:
          - "80:80"
        volumes:
          - "/etc/nginx/conf.d:/etc/nginx/conf.d:ro"
      - name: redis
        image: redis:alpine
        ports:
          - "6379:6379"
  
  tasks:
    - name: Install Docker dependencies
      package:
        name:
          - apt-transport-https
          - ca-certificates
          - curl
          - gnupg
          - lsb-release
        state: present
      when: ansible_os_family == "Debian"
    
    - name: Add Docker GPG key
      apt_key:
        url: https://download.docker.com/linux/ubuntu/gpg
        state: present
      when: ansible_os_family == "Debian"
    
    - name: Add Docker repository
      apt_repository:
        repo: "deb [arch=amd64] https://download.docker.com/linux/ubuntu {{ ansible_distribution_release }} stable"
        state: present
      when: ansible_os_family == "Debian"
    
    - name: Install Docker
      package:
        name:
          - docker-ce
          - docker-ce-cli
          - containerd.io
        state: present
        update_cache: yes
      when: ansible_os_family == "Debian"
    
    - name: Start and enable Docker service
      systemd:
        name: docker
        state: started
        enabled: yes
    
    - name: Install Docker Compose
      get_url:
        url: "https://github.com/docker/compose/releases/download/v{{ docker_compose_version }}/docker-compose-{{ ansible_system }}-{{ ansible_architecture }}"
        dest: /usr/local/bin/docker-compose
        mode: '0755'
    
    - name: Deploy containers
      docker_container:
        name: "{{ item.name }}"
        image: "{{ item.image }}"
        ports: "{{ item.ports | default([]) }}"
        volumes: "{{ item.volumes | default([]) }}"
        state: started
        restart_policy: always
      loop: "{{ containers }}"
EOF
            ;;
        "web-server")
            cat > "$output_file" << 'EOF'
---
# Web Server Setup Playbook
# This playbook installs and configures Nginx web server

- name: Web Server Setup
  hosts: all
  become: yes
  vars:
    server_name: example.com
    document_root: /var/www/html
    ssl_enabled: false
  
  tasks:
    - name: Install Nginx
      package:
        name: nginx
        state: present
    
    - name: Create document root
      file:
        path: "{{ document_root }}"
        state: directory
        owner: www-data
        group: www-data
        mode: '0755'
    
    - name: Create default index page
      copy:
        content: |
          <!DOCTYPE html>
          <html>
          <head>
              <title>Welcome to {{ server_name }}</title>
          </head>
          <body>
              <h1>Welcome to {{ server_name }}</h1>
              <p>This server is configured with Ansible!</p>
          </body>
          </html>
        dest: "{{ document_root }}/index.html"
        owner: www-data
        group: www-data
        mode: '0644'
    
    - name: Configure Nginx virtual host
      template:
        src: nginx-vhost.j2
        dest: "/etc/nginx/sites-available/{{ server_name }}"
        backup: yes
      notify: restart nginx
    
    - name: Enable virtual host
      file:
        src: "/etc/nginx/sites-available/{{ server_name }}"
        dest: "/etc/nginx/sites-enabled/{{ server_name }}"
        state: link
      notify: restart nginx
    
    - name: Remove default Nginx site
      file:
        path: /etc/nginx/sites-enabled/default
        state: absent
      notify: restart nginx
    
    - name: Start and enable Nginx
      systemd:
        name: nginx
        state: started
        enabled: yes
    
    - name: Configure firewall for web traffic
      ufw:
        rule: allow
        port: "{{ item }}"
      loop:
        - "80"
        - "443"
      when: ansible_os_family == "Debian"
  
  handlers:
    - name: restart nginx
      systemd:
        name: nginx
        state: restarted
EOF
            ;;
        "database-server")
            cat > "$output_file" << 'EOF'
---
# Database Server Setup Playbook
# This playbook installs and configures MySQL/PostgreSQL database server

- name: Database Server Setup
  hosts: all
  become: yes
  vars:
    db_type: mysql  # mysql or postgresql
    db_root_password: "{{ vault_db_root_password | default('changeme123') }}"
    db_name: myapp
    db_user: appuser
    db_password: "{{ vault_db_password | default('changeme456') }}"
  
  tasks:
    - name: Install MySQL server
      package:
        name:
          - mysql-server
          - mysql-client
          - python3-pymysql
        state: present
      when: db_type == "mysql"
    
    - name: Install PostgreSQL server
      package:
        name:
          - postgresql
          - postgresql-contrib
          - python3-psycopg2
        state: present
      when: db_type == "postgresql"
    
    - name: Start and enable MySQL service
      systemd:
        name: mysql
        state: started
        enabled: yes
      when: db_type == "mysql"
    
    - name: Start and enable PostgreSQL service
      systemd:
        name: postgresql
        state: started
        enabled: yes
      when: db_type == "postgresql"
    
    - name: Set MySQL root password
      mysql_user:
        name: root
        password: "{{ db_root_password }}"
        login_unix_socket: /var/run/mysqld/mysqld.sock
        state: present
      when: db_type == "mysql"
    
    - name: Create application database (MySQL)
      mysql_db:
        name: "{{ db_name }}"
        state: present
        login_user: root
        login_password: "{{ db_root_password }}"
      when: db_type == "mysql"
    
    - name: Create application user (MySQL)
      mysql_user:
        name: "{{ db_user }}"
        password: "{{ db_password }}"
        priv: "{{ db_name }}.*:ALL"
        state: present
        login_user: root
        login_password: "{{ db_root_password }}"
      when: db_type == "mysql"
    
    - name: Create application database (PostgreSQL)
      postgresql_db:
        name: "{{ db_name }}"
        state: present
      become_user: postgres
      when: db_type == "postgresql"
    
    - name: Create application user (PostgreSQL)
      postgresql_user:
        name: "{{ db_user }}"
        password: "{{ db_password }}"
        db: "{{ db_name }}"
        priv: ALL
        state: present
      become_user: postgres
      when: db_type == "postgresql"
    
    - name: Configure firewall for database
      ufw:
        rule: allow
        port: "{{ item }}"
        src: "{{ ansible_default_ipv4.network }}/24"
      loop:
        - "3306"  # MySQL
        - "5432"  # PostgreSQL
      when: ansible_os_family == "Debian"
EOF
            ;;
        "monitoring-setup")
            cat > "$output_file" << 'EOF'
---
# Monitoring Stack Setup Playbook
# This playbook installs Prometheus, Grafana, and Node Exporter

- name: Monitoring Stack Setup
  hosts: all
  become: yes
  vars:
    prometheus_version: "2.45.0"
    grafana_version: "10.0.0"
    node_exporter_version: "1.6.0"
    prometheus_user: prometheus
    grafana_admin_password: "{{ vault_grafana_password | default('admin123') }}"
  
  tasks:
    - name: Create prometheus user
      user:
        name: "{{ prometheus_user }}"
        system: yes
        shell: /bin/false
        home: /etc/prometheus
        create_home: no
    
    - name: Create prometheus directories
      file:
        path: "{{ item }}"
        state: directory
        owner: "{{ prometheus_user }}"
        group: "{{ prometheus_user }}"
        mode: '0755'
      loop:
        - /etc/prometheus
        - /var/lib/prometheus
    
    - name: Download and install Prometheus
      unarchive:
        src: "https://github.com/prometheus/prometheus/releases/download/v{{ prometheus_version }}/prometheus-{{ prometheus_version }}.linux-amd64.tar.gz"
        dest: /tmp
        remote_src: yes
        creates: "/tmp/prometheus-{{ prometheus_version }}.linux-amd64"
    
    - name: Copy Prometheus binaries
      copy:
        src: "/tmp/prometheus-{{ prometheus_version }}.linux-amd64/{{ item }}"
        dest: "/usr/local/bin/{{ item }}"
        owner: "{{ prometheus_user }}"
        group: "{{ prometheus_user }}"
        mode: '0755'
        remote_src: yes
      loop:
        - prometheus
        - promtool
    
    - name: Create Prometheus configuration
      copy:
        content: |
          global:
            scrape_interval: 15s
            evaluation_interval: 15s
          
          scrape_configs:
            - job_name: 'prometheus'
              static_configs:
                - targets: ['localhost:9090']
            
            - job_name: 'node'
              static_configs:
                - targets: ['localhost:9100']
        dest: /etc/prometheus/prometheus.yml
        owner: "{{ prometheus_user }}"
        group: "{{ prometheus_user }}"
        mode: '0644'
      notify: restart prometheus
    
    - name: Create Prometheus systemd service
      copy:
        content: |
          [Unit]
          Description=Prometheus
          Wants=network-online.target
          After=network-online.target
          
          [Service]
          User={{ prometheus_user }}
          Group={{ prometheus_user }}
          Type=simple
          ExecStart=/usr/local/bin/prometheus \
            --config.file /etc/prometheus/prometheus.yml \
            --storage.tsdb.path /var/lib/prometheus/ \
            --web.console.templates=/etc/prometheus/consoles \
            --web.console.libraries=/etc/prometheus/console_libraries \
            --web.listen-address=0.0.0.0:9090 \
            --web.enable-lifecycle
          
          [Install]
          WantedBy=multi-user.target
        dest: /etc/systemd/system/prometheus.service
        mode: '0644'
      notify:
        - reload systemd
        - restart prometheus
    
    - name: Download and install Node Exporter
      unarchive:
        src: "https://github.com/prometheus/node_exporter/releases/download/v{{ node_exporter_version }}/node_exporter-{{ node_exporter_version }}.linux-amd64.tar.gz"
        dest: /tmp
        remote_src: yes
        creates: "/tmp/node_exporter-{{ node_exporter_version }}.linux-amd64"
    
    - name: Copy Node Exporter binary
      copy:
        src: "/tmp/node_exporter-{{ node_exporter_version }}.linux-amd64/node_exporter"
        dest: /usr/local/bin/node_exporter
        owner: "{{ prometheus_user }}"
        group: "{{ prometheus_user }}"
        mode: '0755'
        remote_src: yes
    
    - name: Create Node Exporter systemd service
      copy:
        content: |
          [Unit]
          Description=Node Exporter
          Wants=network-online.target
          After=network-online.target
          
          [Service]
          User={{ prometheus_user }}
          Group={{ prometheus_user }}
          Type=simple
          ExecStart=/usr/local/bin/node_exporter
          
          [Install]
          WantedBy=multi-user.target
        dest: /etc/systemd/system/node_exporter.service
        mode: '0644'
      notify:
        - reload systemd
        - restart node_exporter
    
    - name: Install Grafana
      get_url:
        url: "https://dl.grafana.com/oss/release/grafana_{{ grafana_version }}_amd64.deb"
        dest: "/tmp/grafana_{{ grafana_version }}_amd64.deb"
    
    - name: Install Grafana package
      apt:
        deb: "/tmp/grafana_{{ grafana_version }}_amd64.deb"
        state: present
      when: ansible_os_family == "Debian"
    
    - name: Configure Grafana admin password
      lineinfile:
        path: /etc/grafana/grafana.ini
        regexp: '^;admin_password = admin'
        line: "admin_password = {{ grafana_admin_password }}"
      notify: restart grafana
    
    - name: Start and enable services
      systemd:
        name: "{{ item }}"
        state: started
        enabled: yes
      loop:
        - prometheus
        - node_exporter
        - grafana-server
    
    - name: Configure firewall for monitoring
      ufw:
        rule: allow
        port: "{{ item }}"
      loop:
        - "9090"  # Prometheus
        - "9100"  # Node Exporter
        - "3000"  # Grafana
      when: ansible_os_family == "Debian"
  
  handlers:
    - name: reload systemd
      systemd:
        daemon_reload: yes
    
    - name: restart prometheus
      systemd:
        name: prometheus
        state: restarted
    
    - name: restart node_exporter
      systemd:
        name: node_exporter
        state: restarted
    
    - name: restart grafana
      systemd:
        name: grafana-server
        state: restarted
EOF
            ;;
        "custom")
            cat > "$output_file" << 'EOF'
---
# Custom Ansible Playbook Template
# Customize this template for your specific needs

- name: Custom Playbook
  hosts: all
  become: yes
  vars:
    # Define your variables here
    app_name: myapp
    app_version: "1.0.0"
    app_user: myapp
    app_port: 8080
  
  tasks:
    - name: Ensure required packages are installed
      package:
        name:
          - curl
          - wget
          - git
        state: present
    
    - name: Create application user
      user:
        name: "{{ app_user }}"
        system: yes
        shell: /bin/bash
        create_home: yes
        state: present
    
    - name: Create application directory
      file:
        path: "/opt/{{ app_name }}"
        state: directory
        owner: "{{ app_user }}"
        group: "{{ app_user }}"
        mode: '0755'
    
    - name: Example configuration file
      copy:
        content: |
          # {{ app_name }} Configuration
          app_name={{ app_name }}
          app_version={{ app_version }}
          app_port={{ app_port }}
        dest: "/opt/{{ app_name }}/config.conf"
        owner: "{{ app_user }}"
        group: "{{ app_user }}"
        mode: '0644'
    
    - name: Example service template
      copy:
        content: |
          [Unit]
          Description={{ app_name }} Service
          After=network.target
          
          [Service]
          Type=simple
          User={{ app_user }}
          Group={{ app_user }}
          WorkingDirectory=/opt/{{ app_name }}
          ExecStart=/opt/{{ app_name }}/start.sh
          Restart=always
          
          [Install]
          WantedBy=multi-user.target
        dest: "/etc/systemd/system/{{ app_name }}.service"
        mode: '0644'
      notify: reload systemd
    
    - name: Configure firewall
      ufw:
        rule: allow
        port: "{{ app_port }}"
      when: ansible_os_family == "Debian"
  
  handlers:
    - name: reload systemd
      systemd:
        daemon_reload: yes
    
    - name: restart service
      systemd:
        name: "{{ app_name }}"
        state: restarted
EOF
            ;;
        *)
            log "ERROR" "Unknown template type: $template_type"
            return 1
            ;;
    esac
    
    # Set proper permissions
    chmod 644 "$output_file"
    
    log "INFO" "Sample playbook created successfully: $output_file"
    return 0
}

# Main function to display menu and handle user selection
main() {
    log "INFO" "Starting Ansible Module v${VERSION}"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log "ERROR" "This script must be run as root"
        exit 1
    fi
    
    # Check/install dependencies
    if ! command -v python3 >/dev/null 2>&1; then
        log "INFO" "Installing Python3..."
        apt-get update && apt-get install -y python3 python3-pip
    fi
    
    # Check/install Ansible
    if ! check_ansible; then
        if [ -t 0 ]; then  # If running interactively
            if whiptail --title "Install Ansible" --yesno "Ansible is not installed. Would you like to install it now?" 10 60; then
                install_ansible
            else
                log "ERROR" "Ansible is required but not installed"
                exit 1
            fi
        else
            log "INFO" "Installing Ansible automatically..."
            install_ansible
        fi
    fi
    
    # Main menu loop
    while true; do
        if [ -t 0 ]; then  # If running interactively
            local choice
            choice=$(whiptail --title "Ansible Module v${VERSION}" \
                --menu "Choose an action:" 20 70 12 \
                "1" "Discover Ansible Playbooks" \
                "2" "Discover Ansible Roles" \
                "3" "Execute Playbook" \
                "4" "Dry-run Playbook" \
                "5" "Validate Playbook" \
                "6" "Install Role from Galaxy" \
                "7" "Show Configuration" \
                "8" "Create Sample Playbook" \
                "9" "Exit" \
                3>&1 1>&2 2>&3)
            
            case $choice in
                1)
                    log "INFO" "Discovering Ansible playbooks..."
                    if playbooks=$(discover_playbooks); then
                        if [ -n "$playbooks" ]; then
                            whiptail --title "Available Playbooks" --msgbox "Found playbooks:\n\n$playbooks" 20 60
                        else
                            whiptail --title "No Playbooks" --msgbox "No Ansible playbooks found." 10 60
                        fi
                    else
                        whiptail --title "No Playbooks" --msgbox "No Ansible playbooks found." 10 60
                    fi
                    ;;
                2)
                    log "INFO" "Discovering Ansible roles..."
                    if roles=$(discover_roles); then
                        if [ -n "$roles" ]; then
                            whiptail --title "Available Roles" --msgbox "Found roles:\n\n$roles" 20 60
                        else
                            whiptail --title "No Roles" --msgbox "No Ansible roles found." 10 60
                        fi
                    else
                        whiptail --title "No Roles" --msgbox "No Ansible roles found." 10 60
                    fi
                    ;;
                3)
                    # Execute playbook workflow
                    log "INFO" "Starting playbook execution workflow..."
                    
                    # Get available playbooks
                    if ! playbooks=$(discover_playbooks); then
                        whiptail --title "Error" --msgbox "No Ansible playbooks found." 10 60
                        continue
                    fi
                    
                    # Convert playbooks to menu format
                    local menu_items=()
                    local i=1
                    while IFS= read -r playbook; do
                        menu_items+=("$i" "$playbook")
                        ((i++))
                    done <<< "$playbooks"
                    
                    # Let user select playbook
                    local selected_index
                    selected_index=$(whiptail --title "Select Playbook" \
                        --menu "Choose a playbook to execute:" 20 70 10 \
                        "${menu_items[@]}" \
                        3>&1 1>&2 2>&3)
                    
                    if [ $? -eq 0 ]; then
                        local selected_playbook
                        selected_playbook=$(echo "$playbooks" | sed -n "${selected_index}p")
                        
                        # Find playbook path
                        local playbook_path=""
                        if [ -f "$SCRIPT_DIR/../ansible/$selected_playbook.yml" ]; then
                            playbook_path="$SCRIPT_DIR/../ansible/$selected_playbook.yml"
                        elif [ -f "$SCRIPT_DIR/../ansible/$selected_playbook.yaml" ]; then
                            playbook_path="$SCRIPT_DIR/../ansible/$selected_playbook.yaml"
                        elif [ -f "$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yml" ]; then
                            playbook_path="$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yml"
                        elif [ -f "$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yaml" ]; then
                            playbook_path="$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yaml"
                        fi
                        
                        if [ -n "$playbook_path" ]; then
                            log "INFO" "Selected playbook: $selected_playbook at $playbook_path"
                            
                            # Collect variables
                            collect_variables "$playbook_path"
                            
                            # Validate playbook
                            if validate_playbook "$playbook_path"; then
                                # Execute playbook
                                if execute_playbook "$playbook_path"; then
                                    whiptail --title "Success" --msgbox "Playbook executed successfully!" 10 60
                                else
                                    whiptail --title "Error" --msgbox "Playbook execution failed. Check logs for details." 10 60
                                fi
                            else
                                whiptail --title "Error" --msgbox "Playbook validation failed. Check logs for details." 10 60
                            fi
                        else
                            whiptail --title "Error" --msgbox "Playbook file not found." 10 60
                        fi
                    fi
                    ;;
                4)
                    # Dry-run playbook
                    log "INFO" "Starting playbook dry-run workflow..."
                    
                    # Get available playbooks
                    if ! playbooks=$(discover_playbooks); then
                        whiptail --title "Error" --msgbox "No Ansible playbooks found." 10 60
                        continue
                    fi
                    
                    # Convert playbooks to menu format
                    local menu_items=()
                    local i=1
                    while IFS= read -r playbook; do
                        menu_items+=("$i" "$playbook")
                        ((i++))
                    done <<< "$playbooks"
                    
                    # Let user select playbook
                    local selected_index
                    selected_index=$(whiptail --title "Select Playbook for Dry-run" \
                        --menu "Choose a playbook for dry-run (check mode):" 20 70 10 \
                        "${menu_items[@]}" \
                        3>&1 1>&2 2>&3)
                    
                    if [ $? -eq 0 ]; then
                        local selected_playbook
                        selected_playbook=$(echo "$playbooks" | sed -n "${selected_index}p")
                        
                        # Find playbook path
                        local playbook_path=""
                        if [ -f "$SCRIPT_DIR/../ansible/$selected_playbook.yml" ]; then
                            playbook_path="$SCRIPT_DIR/../ansible/$selected_playbook.yml"
                        elif [ -f "$SCRIPT_DIR/../ansible/$selected_playbook.yaml" ]; then
                            playbook_path="$SCRIPT_DIR/../ansible/$selected_playbook.yaml"
                        elif [ -f "$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yml" ]; then
                            playbook_path="$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yml"
                        elif [ -f "$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yaml" ]; then
                            playbook_path="$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yaml"
                        fi
                        
                        if [ -n "$playbook_path" ]; then
                            log "INFO" "Selected playbook for dry-run: $selected_playbook at $playbook_path"
                            
                            # Collect variables
                            collect_variables "$playbook_path"
                            
                            # Validate playbook first
                            if validate_playbook "$playbook_path"; then
                                # Run dry-run
                                if dry_run_playbook "$playbook_path"; then
                                    whiptail --title "Dry-run Success" --msgbox "Playbook dry-run completed successfully!\n\nNo changes were made to target systems.\nCheck logs for detailed output." 12 70
                                else
                                    whiptail --title "Dry-run Failed" --msgbox "Playbook dry-run failed. Check logs for details." 10 60
                                fi
                            else
                                whiptail --title "Error" --msgbox "Playbook validation failed. Check logs for details." 10 60
                            fi
                        else
                            whiptail --title "Error" --msgbox "Playbook file not found." 10 60
                        fi
                    fi
                    ;;
                5)
                    # Validate playbook
                    log "INFO" "Starting playbook validation workflow..."
                    
                    # Get available playbooks
                    if ! playbooks=$(discover_playbooks); then
                        whiptail --title "Error" --msgbox "No Ansible playbooks found." 10 60
                        continue
                    fi
                    
                    # Convert playbooks to menu format
                    local menu_items=()
                    local i=1
                    while IFS= read -r playbook; do
                        menu_items+=("$i" "$playbook")
                        ((i++))
                    done <<< "$playbooks"
                    
                    # Let user select playbook
                    local selected_index
                    selected_index=$(whiptail --title "Select Playbook for Validation" \
                        --menu "Choose a playbook to validate:" 20 70 10 \
                        "${menu_items[@]}" \
                        3>&1 1>&2 2>&3)
                    
                    if [ $? -eq 0 ]; then
                        local selected_playbook
                        selected_playbook=$(echo "$playbooks" | sed -n "${selected_index}p")
                        
                        # Find playbook path
                        local playbook_path=""
                        if [ -f "$SCRIPT_DIR/../ansible/$selected_playbook.yml" ]; then
                            playbook_path="$SCRIPT_DIR/../ansible/$selected_playbook.yml"
                        elif [ -f "$SCRIPT_DIR/../ansible/$selected_playbook.yaml" ]; then
                            playbook_path="$SCRIPT_DIR/../ansible/$selected_playbook.yaml"
                        elif [ -f "$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yml" ]; then
                            playbook_path="$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yml"
                        elif [ -f "$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yaml" ]; then
                            playbook_path="$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yaml"
                        fi
                        
                        if [ -n "$playbook_path" ]; then
                            log "INFO" "Validating playbook: $selected_playbook at $playbook_path"
                            
                            if validate_playbook "$playbook_path"; then
                                whiptail --title "Validation Success" --msgbox "Playbook validation successful!\n\nPlaybook: $selected_playbook\nSyntax: Valid\nStructure: Valid" 12 70
                            else
                                whiptail --title "Validation Failed" --msgbox "Playbook validation failed for: $selected_playbook\n\nCheck logs for detailed error information." 12 70
                            fi
                        else
                            whiptail --title "Error" --msgbox "Playbook file not found." 10 60
                        fi
                    fi
                    ;;
                6)
                    # Install role from Galaxy
                    local role_name
                    role_name=$(whiptail --title "Install Role" --inputbox "Enter role name from Ansible Galaxy:" 10 60 3>&1 1>&2 2>&3)
                    
                    if [ $? -eq 0 ] && [ -n "$role_name" ]; then
                        install_role "$role_name"
                        if [ $? -eq 0 ]; then
                            whiptail --title "Success" --msgbox "Role installed successfully: $role_name" 10 60
                        else
                            whiptail --title "Error" --msgbox "Role installation failed. Check logs for details." 10 60
                        fi
                    fi
                    ;;
                7)
                    # Show configuration
                    log "INFO" "Displaying Ansible configuration..."
                    
                    # Collect configuration information
                    local config_info=""
                    if [ "$TEST_MODE" ]; then
                        config_info="[TEST MODE] Ansible Configuration Information\n\n"
                        config_info+="Ansible Version: 2.x.x (simulated)\n"
                        config_info+="Config File: /etc/ansible/ansible.cfg\n"
                        config_info+="Module Path: /usr/share/ansible\n"
                        config_info+="Collections: community.general, ansible.posix\n\n"
                        config_info+="Project Ansible Directory: $SCRIPT_DIR/../ansible\n"
                        config_info+="System Playbooks Directory: $ANSIBLE_PLAYBOOKS_DIR\n"
                        config_info+="System Roles Directory: $ANSIBLE_ROLES_DIR"
                    else
                        # Get real configuration information
                        local temp_file
                        temp_file=$(mktemp)
                        {
                            echo "=== ANSIBLE VERSION ==="
                            ansible --version 2>/dev/null || echo "Ansible not installed"
                            echo ""
                            echo "=== ANSIBLE CONFIGURATION ==="
                            ansible-config dump 2>/dev/null | head -20 || echo "No configuration available"
                            echo ""
                            echo "=== INSTALLED COLLECTIONS ==="
                            ansible-galaxy collection list 2>/dev/null | head -10 || echo "No collections found"
                            echo ""
                            echo "=== PROJECT DIRECTORIES ==="
                            echo "Project Ansible Directory: $SCRIPT_DIR/../ansible"
                            echo "System Playbooks Directory: $ANSIBLE_PLAYBOOKS_DIR"
                            echo "System Roles Directory: $ANSIBLE_ROLES_DIR"
                        } > "$temp_file"
                        
                        config_info=$(cat "$temp_file")
                        rm -f "$temp_file"
                    fi
                    
                    # Display in scrollable dialog
                    whiptail --title "Ansible Configuration" --scrolltext --msgbox "$config_info" 25 100
                    ;;
                8)
                    # Create sample playbook
                    log "INFO" "Starting sample playbook creation workflow..."
                    
                    # Define sample playbook templates
                    local templates=(
                        "basic-setup" "Basic System Setup (packages, users, security)"
                        "docker-deployment" "Docker Container Deployment"
                        "web-server" "Web Server Setup (Nginx/Apache)"
                        "database-server" "Database Server Setup (MySQL/PostgreSQL)"
                        "monitoring-setup" "Monitoring Stack Setup (Prometheus/Grafana)"
                        "custom" "Create Custom Playbook Template"
                    )
                    
                    # Show template selection dialog
                    local selected_template
                    if selected_template=$(whiptail --title "Create Sample Playbook" --menu "Choose a playbook template to create:" 20 80 6 "${templates[@]}" 3>&1 1>&2 2>&3); then
                        log "INFO" "Selected template: $selected_template"
                        
                        # Get playbook name
                        local playbook_name
                        if playbook_name=$(whiptail --title "Playbook Name" --inputbox "Enter a name for your playbook:" 10 60 "sample-$selected_template" 3>&1 1>&2 2>&3); then
                            if [ -n "$playbook_name" ]; then
                                # Sanitize playbook name
                                playbook_name=$(echo "$playbook_name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g')
                                local playbook_file="$ANSIBLE_PLAYBOOKS_DIR/${playbook_name}.yaml"
                                
                                # Check if file already exists
                                if [ -f "$playbook_file" ]; then
                                    if ! whiptail --title "File Exists" --yesno "A playbook named '$playbook_name' already exists. Overwrite it?" 10 60; then
                                        log "INFO" "Sample playbook creation cancelled by user"
                                        continue
                                    fi
                                fi
                                
                                # Create playbook based on template
                                if create_sample_playbook "$selected_template" "$playbook_file" "$playbook_name"; then
                                    whiptail --title "Success" --msgbox "Sample playbook created successfully!\n\nFile: $playbook_file\nTemplate: $selected_template\n\nYou can now edit this playbook to customize it for your needs." 15 70
                                    log "INFO" "Sample playbook created: $playbook_file"
                                else
                                    whiptail --title "Error" --msgbox "Failed to create sample playbook. Check logs for details." 10 60
                                    log "ERROR" "Failed to create sample playbook: $playbook_file"
                                fi
                            else
                                whiptail --title "Error" --msgbox "Playbook name cannot be empty." 10 60
                            fi
                        fi
                    fi
                    ;;
                9)
                    log "INFO" "Exiting Ansible module"
                    exit 0
                    ;;
                *)
                    log "ERROR" "Invalid selection"
                    ;;
            esac
        else
            # Non-interactive mode - show available playbooks and exit
            log "INFO" "Running in non-interactive mode"
            discover_playbooks
            exit 0
        fi
    done
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
