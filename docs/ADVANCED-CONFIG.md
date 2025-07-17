# NetBird Self-Hosted Deployer - Advanced Configuration Guide

This guide covers advanced configuration options, customizations, and enterprise-level deployments for the NetBird Self-Hosted Deployer.

## 🔧 Configuration Options

### Environment Variables

The deployment script supports various environment variables for customization:

```bash
# Server Configuration
export NETBIRD_SERVER_TYPE="cax11"          # Server type (default: cax11)
export NETBIRD_SERVER_LOCATION="ash"        # Location (default: nbg1)
export NETBIRD_SERVER_IMAGE="ubuntu-22.04"  # OS image (default: ubuntu-24.04)

# Network Configuration
export NETBIRD_DOMAIN="nb.example.com"      # Your domain
export NETBIRD_LETSENCRYPT_EMAIL="admin@example.com"

# Azure AD Configuration
export AZURE_CLIENT_ID="your-client-id"
export AZURE_TENANT_ID="your-tenant-id"

# Advanced Settings
export NETBIRD_TURN_USER="netbird"
export NETBIRD_TURN_PASSWORD="secure-password"
export NETBIRD_LOG_LEVEL="INFO"
```

### Custom Server Specifications

#### Available Server Types

| Type | vCPUs | RAM | Disk | Network | Monthly Cost |
|------|-------|-----|------|---------|--------------|
| cax11 | 2 ARM | 4 GB | 40 GB | 20 TB | €4.15 |
| cax21 | 4 ARM | 8 GB | 80 GB | 20 TB | €8.30 |
| cax31 | 8 ARM | 16 GB | 160 GB | 20 TB | €16.61 |
| cx11 | 1 x86 | 4 GB | 20 GB | 20 TB | €4.15 |
| cx21 | 2 x86 | 8 GB | 40 GB | 20 TB | €8.30 |
| cx31 | 2 x86 | 16 GB | 80 GB | 20 TB | €16.61 |

#### Choosing the Right Server

- **Small Teams (< 50 users):** `cax11` (default)
- **Medium Teams (50-200 users):** `cax21`
- **Large Teams (200+ users):** `cax31`
- **High Performance:** Use x86 types for better single-thread performance

### Location Selection

#### Available Locations

| Code | Location | Description |
|------|----------|-------------|
| ash | Ashburn, VA | US East Coast |
| fsn1 | Falkenstein | Germany (Primary) |
| hel1 | Helsinki | Finland |
| nbg1 | Nuremberg | Germany (Default) |
| sin | Singapore | Asia Pacific |

Choose the location closest to your primary user base for optimal performance.

## 🏢 Enterprise Configurations

### High Availability Setup

For mission-critical deployments, consider a multi-server setup:

```bash
# Primary server deployment
./deploy-netbird-selfhosted.sh --role=primary --region=nbg1

# Backup server deployment
./deploy-netbird-selfhosted.sh --role=backup --region=fsn1 --primary-ip=<primary-server-ip>
```

### Load Balancer Configuration

For high-traffic deployments, add a load balancer:

```nginx
# /etc/nginx/conf.d/netbird-lb.conf
upstream netbird_backend {
    server 10.0.1.10:443 weight=3;
    server 10.0.1.11:443 weight=2;
    server 10.0.1.12:443 backup;
}

server {
    listen 443 ssl http2;
    server_name nb.example.com;

    location / {
        proxy_pass https://netbird_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Database Externalization

For enterprise deployments, use external PostgreSQL:

```yaml
# docker-compose.override.yml
version: '3.8'
services:
  netbird-management:
    environment:
      NETBIRD_STORE_ENGINE: postgres
      NETBIRD_STORE_ENGINE_POSTGRES_DSN: "postgres://netbird:password@postgres.example.com:5432/netbird?sslmode=require"
    depends_on: []

  # Remove the built-in database
  # netbird-management-postgres:
```

## 🔒 Security Hardening

### Advanced Firewall Rules

Create custom firewall rules for enhanced security:

```bash
# Create custom firewall
hcloud firewall create --name netbird-enterprise

# SSH access only from specific IPs
hcloud firewall add-rule netbird-enterprise \
  --direction in --port 22 --protocol tcp \
  --source-ips 203.0.113.0/24,198.51.100.0/24

# HTTP/HTTPS from anywhere
hcloud firewall add-rule netbird-enterprise \
  --direction in --port 80 --protocol tcp --source-ips 0.0.0.0/0,::/0

hcloud firewall add-rule netbird-enterprise \
  --direction in --port 443 --protocol tcp --source-ips 0.0.0.0/0,::/0

# NetBird specific ports
hcloud firewall add-rule netbird-enterprise \
  --direction in --port 3478 --protocol udp --source-ips 0.0.0.0/0,::/0

hcloud firewall add-rule netbird-enterprise \
  --direction in --port 10000 --protocol tcp --source-ips 0.0.0.0/0,::/0
```

### SSL/TLS Configuration

#### Custom SSL Certificates

To use custom SSL certificates instead of Let's Encrypt:

```nginx
# /etc/nginx/sites-available/netbird
server {
    listen 443 ssl http2;
    server_name nb.example.com;

    # Custom certificate paths
    ssl_certificate /etc/ssl/certs/netbird.crt;
    ssl_certificate_key /etc/ssl/private/netbird.key;

    # Enhanced SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_ecdh_curve secp384r1;
    ssl_session_timeout 10m;
    ssl_session_cache shared:SSL:10m;
    ssl_stapling on;
    ssl_stapling_verify on;

    # Security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "strict-origin-when-cross-origin";
}
```

### Fail2Ban Integration

Protect against brute force attacks:

```bash
# Install fail2ban
sudo apt update && sudo apt install -y fail2ban

# Create NetBird filter
sudo tee /etc/fail2ban/filter.d/netbird.conf << EOF
[Definition]
failregex = ^<HOST>.*"POST /api/auth.*" (401|403)
ignoreregex =
EOF

# Configure jail
sudo tee /etc/fail2ban/jail.d/netbird.conf << EOF
[netbird]
enabled = true
port = http,https
filter = netbird
logpath = /var/log/nginx/access.log
maxretry = 5
bantime = 3600
findtime = 600
EOF

sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

## 📊 Monitoring and Observability

### Prometheus Integration

Add monitoring to your NetBird deployment:

```yaml
# monitoring/docker-compose.yml
version: '3.8'
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana_data:/var/lib/grafana
    ports:
      - "3000:3000"

volumes:
  prometheus_data:
  grafana_data:
```

### Log Aggregation

Centralize logs with ELK stack:

```yaml
# logging/docker-compose.yml
version: '3.8'
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
    volumes:
      - elasticsearch_data:/usr/share/elasticsearch/data

  logstash:
    image: docker.elastic.co/logstash/logstash:8.11.0
    volumes:
      - ./logstash.conf:/usr/share/logstash/pipeline/logstash.conf

  kibana:
    image: docker.elastic.co/kibana/kibana:8.11.0
    ports:
      - "5601:5601"
    depends_on:
      - elasticsearch

volumes:
  elasticsearch_data:
```

## 🔄 Backup and Disaster Recovery

### Automated Backups

Create automated backup solution:

```bash
#!/bin/bash
# /opt/netbird-backup.sh

BACKUP_DIR="/opt/backups/netbird"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="netbird_backup_$TIMESTAMP.tar.gz"

# Create backup directory
mkdir -p $BACKUP_DIR

# Backup NetBird data
docker-compose exec -T netbird-management pg_dump -U netbird netbird > $BACKUP_DIR/netbird_db_$TIMESTAMP.sql

# Backup configuration files
tar -czf $BACKUP_DIR/$BACKUP_FILE \
  /opt/netbird \
  /etc/nginx/sites-available/netbird \
  /etc/letsencrypt

# Keep only last 30 days of backups
find $BACKUP_DIR -name "netbird_backup_*.tar.gz" -mtime +30 -delete

# Upload to cloud storage (optional)
aws s3 cp $BACKUP_DIR/$BACKUP_FILE s3://your-backup-bucket/netbird/
```

### Disaster Recovery Procedure

1. **Prepare new server:**
   ```bash
   # Deploy fresh NetBird installation
   ./deploy-netbird-selfhosted.sh --restore-mode
   ```

2. **Restore data:**
   ```bash
   # Stop services
   docker-compose down

   # Restore database
   docker-compose exec -T netbird-management psql -U netbird netbird < backup.sql

   # Restore configurations
   tar -xzf netbird_backup.tar.gz -C /

   # Start services
   docker-compose up -d
   ```

## 🌐 Multi-Region Deployment

### Global Setup Architecture

For global organizations, deploy across multiple regions:

```bash
# Primary region (Europe)
REGION=nbg1 ROLE=primary ./deploy-netbird-selfhosted.sh

# Secondary region (US)
REGION=ash ROLE=replica PRIMARY_ENDPOINT=nb-eu.example.com ./deploy-netbird-selfhosted.sh

# Tertiary region (Asia)
REGION=sin ROLE=replica PRIMARY_ENDPOINT=nb-eu.example.com ./deploy-netbird-selfhosted.sh
```

### GeoDNS Configuration

Use DNS-based load balancing for global traffic distribution:

```bash
# Route 53 or similar DNS configuration
nb.example.com IN A 203.0.113.10   ; Europe users
nb.example.com IN A 198.51.100.20  ; US users
nb.example.com IN A 192.0.2.30     ; Asia users
```

## 🔗 Integration Examples

### LDAP/Active Directory Integration

Integrate with existing directory services:

```json
{
  "HttpConfig": {
    "AuthIssuer": "https://login.microsoftonline.com/tenant-id/v2.0",
    "AuthAudience": "client-id",
    "AuthUserIDClaim": "oid",
    "AuthKeysLocation": "https://login.microsoftonline.com/tenant-id/discovery/v2.0/keys"
  },
  "IdpManagerConfig": {
    "ManagerType": "azure",
    "ClientConfig": {
      "Issuer": "https://login.microsoftonline.com/tenant-id/v2.0",
      "TokenEndpoint": "https://login.microsoftonline.com/tenant-id/oauth2/v2.0/token",
      "ClientID": "client-id",
      "ClientSecret": "",
      "GrantType": "authorization_code"
    }
  }
}
```

### API Automation

Automate NetBird management via API:

```bash
# Get API token
TOKEN=$(curl -X POST "https://nb.example.com/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@example.com", "password": "password"}' | jq -r '.access_token')

# Create new user
curl -X POST "https://nb.example.com/api/users" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "name": "New User", "role": "user"}'

# List all peers
curl -X GET "https://nb.example.com/api/peers" \
  -H "Authorization: Bearer $TOKEN"
```

## 📈 Performance Optimization

### Database Tuning

Optimize PostgreSQL for better performance:

```sql
-- postgresql.conf optimizations
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
```

### Nginx Optimization

Optimize nginx for high traffic:

```nginx
# nginx.conf optimizations
worker_processes auto;
worker_connections 1024;

# Enable gzip compression
gzip on;
gzip_vary on;
gzip_min_length 1024;
gzip_types text/plain text/css application/json application/javascript text/xml application/xml;

# Enable caching
location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
}
```

---

This advanced configuration guide provides enterprise-level deployment options. For specific use cases or custom requirements, consult the [GitHub repository](https://github.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer) or contact support.
