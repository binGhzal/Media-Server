# Docker Integration

The Proxmox Template Creator provides comprehensive Docker integration, allowing you to create VM templates with pre-configured Docker environments and container workloads.

## Overview

Docker integration includes:

- **Docker Engine Installation**: Automatic Docker CE installation and configuration
- **Docker Compose**: Pre-installed Docker Compose for multi-container applications
- **Container Templates**: Pre-built container stacks for common use cases
- **Registry Integration**: Support for private container registries
- **Monitoring**: Built-in container monitoring with Prometheus and Grafana

## Docker Templates

### Available Templates

| Template          | Description             | Services Included                   |
| ----------------- | ----------------------- | ----------------------------------- |
| `web-server`      | Web application stack   | Nginx, PHP-FPM, MySQL               |
| `development`     | Development environment | VS Code Server, Git, Docker         |
| `monitoring`      | Monitoring stack        | Prometheus, Grafana, AlertManager   |
| `database`        | Database services       | PostgreSQL, Redis, phpMyAdmin       |
| `ci-cd`           | CI/CD pipeline          | Jenkins, GitLab Runner, SonarQube   |
| `media-server`    | Media streaming         | Plex, Jellyfin, qBittorrent         |
| `home-automation` | Smart home              | Home Assistant, Node-RED, Mosquitto |

### Using Docker Templates

#### Interactive Mode

1. Run the script: `./create-template.sh`
2. Select "Docker Template Integration"
3. Choose from available Docker templates
4. Configure container settings
5. Set networking and storage options

#### CLI Mode

```bash
# Create web server template
./create-template.sh --docker-template web-server --template-name docker-web

# Create development environment
./create-template.sh --docker-template development --template-name docker-dev

# Create monitoring stack
./create-template.sh --docker-template monitoring --template-name docker-monitor
```

## Template Structure

### Docker Template Format

Docker templates are stored in `docker/templates/` directory:

```yaml
# docker/templates/web-server.yml
version: "3.8"
services:
  nginx:
    image: nginx:latest
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - web_data:/var/www/html
    depends_on:
      - php

  php:
    image: php:8.2-fpm
    volumes:
      - web_data:/var/www/html
    depends_on:
      - mysql

  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
    volumes:
      - mysql_data:/var/lib/mysql

volumes:
  web_data:
  mysql_data:
```

### Configuration Variables

Templates support environment variables for customization:

```bash
# Web server template variables
MYSQL_ROOT_PASSWORD=secure_password
MYSQL_DATABASE=webapp
DOMAIN_NAME=example.com
SSL_EMAIL=admin@example.com
```

## Custom Docker Templates

### Creating Custom Templates

1. Create a new YAML file in `docker/templates/`:

```yaml
# docker/templates/custom-app.yml
version: "3.8"
services:
  app:
    image: your-app:latest
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
    volumes:
      - app_data:/app/data

volumes:
  app_data:
```

2. Add template metadata:

```yaml
# docker/templates/custom-app.meta.yml
name: "Custom Application"
description: "Custom web application stack"
category: "web"
variables:
  - name: "NODE_ENV"
    description: "Node.js environment"
    default: "production"
  - name: "APP_PORT"
    description: "Application port"
    default: "3000"
```

3. Register the template in the script (automatically discovered)

### Template Validation

The script automatically validates Docker templates:

- YAML syntax validation
- Service dependency checking
- Port conflict detection
- Volume mount validation
- Environment variable validation

## Docker Configuration

### Docker Engine Settings

The script configures Docker with optimal settings:

```json
{
	"log-driver": "json-file",
	"log-opts": {
		"max-size": "10m",
		"max-file": "3"
	},
	"storage-driver": "overlay2",
	"registry-mirrors": [],
	"insecure-registries": []
}
```

### Network Configuration

Docker networks are automatically configured:

- **bridge**: Default bridge network
- **host**: Host networking for performance
- **custom**: Custom bridge networks for service isolation

### Storage Configuration

Docker storage is optimized for Proxmox:

- **LVM thin provisioning**: Efficient disk usage
- **Volume management**: Persistent data volumes
- **Backup integration**: VM template includes container data

## Registry Integration

### Private Registry Support

Configure private container registries:

```bash
# Configure private registry
DOCKER_REGISTRY="registry.example.com"
DOCKER_REGISTRY_USER="username"
DOCKER_REGISTRY_PASS="password"
```

### Registry Authentication

The script handles registry authentication:

1. Docker login configuration
2. Pull secret creation
3. Service account setup
4. Image pull policy configuration

## Monitoring and Logging

### Container Monitoring

Built-in monitoring for Docker containers:

- **Resource usage**: CPU, memory, disk, network
- **Container health**: Health checks and status monitoring
- **Log aggregation**: Centralized log collection
- **Alerting**: Automated alerts for issues

### Integration with Prometheus

Docker templates include Prometheus monitoring:

```yaml
# Prometheus configuration for Docker
services:
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana_data:/var/lib/grafana
```

## Security Best Practices

### Container Security

The script implements Docker security best practices:

- **Non-root users**: Containers run as non-root users
- **Resource limits**: CPU and memory limits for containers
- **Network isolation**: Service-specific networks
- **Secret management**: Secure handling of sensitive data
- **Image scanning**: Vulnerability scanning for images

### Firewall Configuration

Automatic firewall configuration for Docker:

```bash
# UFW rules for Docker
ufw allow from 172.16.0.0/12 to any port 22
ufw allow 80/tcp
ufw allow 443/tcp
```

## Troubleshooting

### Common Issues

#### Docker Service Not Starting

```bash
# Check Docker service status
systemctl status docker

# Restart Docker service
systemctl restart docker
```

#### Container Network Issues

```bash
# Check Docker networks
docker network ls

# Inspect specific network
docker network inspect bridge
```

#### Storage Issues

```bash
# Check Docker disk usage
docker system df

# Clean up unused resources
docker system prune
```

For more troubleshooting, see [Docker Templates](docker-templates.md) and [Troubleshooting Guide](troubleshooting.md).
