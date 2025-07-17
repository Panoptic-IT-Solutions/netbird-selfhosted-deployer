# NetBird Self-Hosted Deployer - Security Best Practices

This guide outlines comprehensive security best practices for deploying and maintaining a secure NetBird self-hosted infrastructure with Azure AD SPA authentication.

## 🔒 Core Security Principles

### 1. Zero Trust Architecture
- **Principle**: Never trust, always verify
- **Implementation**: Every connection requires authentication and authorization
- **NetBird Role**: Creates secure overlay networks with end-to-end encryption

### 2. Defense in Depth
- **Multiple Security Layers**: Network, application, data, and identity security
- **Redundancy**: If one layer fails, others provide protection
- **Continuous Monitoring**: Real-time threat detection and response

### 3. Principle of Least Privilege
- **Minimal Access**: Users and systems get only necessary permissions
- **Regular Reviews**: Periodic access audits and cleanup
- **Just-in-Time Access**: Temporary elevated permissions when needed

## 🛡️ Infrastructure Security

### Server Hardening

#### Operating System Security
```bash
# 1. Update system packages
sudo apt update && sudo apt upgrade -y

# 2. Configure automatic security updates
sudo apt install -y unattended-upgrades
echo 'Unattended-Upgrade::Automatic-Reboot "false";' | sudo tee -a /etc/apt/apt.conf.d/50unattended-upgrades

# 3. Disable root login
sudo passwd -l root

# 4. Configure secure SSH
sudo tee /etc/ssh/sshd_config.d/netbird.conf << EOF
Protocol 2
PermitRootLogin no
PasswordAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
UseDNS no
AllowGroups ssh-users
EOF

# 5. Restart SSH service
sudo systemctl restart sshd
```

#### Firewall Configuration
```bash
# Install and configure UFW
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (restrict to specific IPs in production)
sudo ufw allow from 203.0.113.0/24 to any port 22

# Allow HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow NetBird specific ports
sudo ufw allow 3478/udp  # STUN/TURN
sudo ufw allow 10000/tcp # Signal server

# Enable firewall
sudo ufw --force enable

# Configure fail2ban
sudo apt install -y fail2ban
sudo tee /etc/fail2ban/jail.d/sshd.conf << EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
EOF

sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
```

### Container Security

#### Docker Security Configuration
```bash
# 1. Configure Docker daemon securely
sudo tee /etc/docker/daemon.json << EOF
{
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "seccomp-profile": "/etc/docker/seccomp.json",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

# 2. Restart Docker with new configuration
sudo systemctl restart docker

# 3. Use non-root user for Docker operations
sudo usermod -aG docker $USER
```

#### Docker Compose Security
```yaml
# docker-compose.yml security enhancements
version: '3.8'
services:
  netbird-management:
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp:noexec,nosuid,size=100m
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETGID
      - SETUID
    user: "1000:1000"
    restart: unless-stopped
```

### Network Security

#### TLS/SSL Configuration
```nginx
# Enhanced SSL configuration
server {
    listen 443 ssl http2;
    server_name nb.example.com;
    
    # SSL certificates
    ssl_certificate /etc/letsencrypt/live/nb.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/nb.example.com/privkey.pem;
    
    # SSL protocols and ciphers
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    
    # SSL optimization
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_stapling on;
    ssl_stapling_verify on;
    
    # HSTS and security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self' https://login.microsoftonline.com;" always;
    
    # Hide server information
    server_tokens off;
    more_clear_headers Server;
}
```

## 🔐 Authentication and Authorization

### Azure AD Security Configuration

#### Application Registration Security
```json
{
  "displayName": "NetBird Self-Hosted",
  "signInAudience": "AzureADMyOrg",
  "web": null,
  "spa": {
    "redirectUris": [
      "https://nb.example.com/auth"
    ]
  },
  "requiredResourceAccess": [
    {
      "resourceAppId": "00000003-0000-0000-c000-000000000000",
      "resourceAccess": [
        {
          "id": "e1fe6dd8-ba31-4d61-89e7-88639da4683d",
          "type": "Scope"
        },
        {
          "id": "37f7f235-527c-4136-accd-4a02d197296e",
          "type": "Scope"
        }
      ]
    }
  ],
  "optionalClaims": {
    "idToken": [
      {
        "name": "email",
        "source": null,
        "essential": false,
        "additionalProperties": []
      }
    ]
  }
}
```

#### Conditional Access Policies
1. **Require MFA**: All NetBird access requires multi-factor authentication
2. **Device Compliance**: Only compliant/managed devices allowed
3. **Location Restrictions**: Restrict access based on geographical locations
4. **Risk-Based Policies**: Block risky sign-ins automatically

### NetBird Access Control

#### User Management
```bash
# Create user groups with specific permissions
# Admin group - full management access
# Users group - limited to own devices
# Guests group - restricted network access

# Example: Create restricted user
curl -X POST "https://nb.example.com/api/users" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "name": "Standard User",
    "role": "user",
    "auto_groups": ["restricted-access"]
  }'
```

#### Network Policies
```json
{
  "name": "Restricted Access Policy",
  "description": "Limited network access for standard users",
  "enabled": true,
  "rules": [
    {
      "name": "Allow HTTP/HTTPS",
      "description": "Allow web browsing",
      "disabled": false,
      "sources": [{"id": "group:standard-users"}],
      "destinations": [{"id": "group:web-servers"}],
      "ports": ["80", "443"],
      "protocol": "tcp",
      "action": "accept"
    },
    {
      "name": "Block Admin Networks",
      "description": "Prevent access to admin resources",
      "disabled": false,
      "sources": [{"id": "group:standard-users"}],
      "destinations": [{"id": "group:admin-networks"}],
      "protocol": "all",
      "action": "drop"
    }
  ]
}
```

## 📊 Monitoring and Logging

### Security Event Monitoring

#### Log Aggregation Setup
```bash
# Install rsyslog for centralized logging
sudo apt install -y rsyslog

# Configure rsyslog for NetBird
sudo tee /etc/rsyslog.d/10-netbird.conf << EOF
# NetBird management logs
local0.*    /var/log/netbird/management.log

# Authentication logs
auth,authpriv.*    /var/log/netbird/auth.log

# Forward logs to SIEM (optional)
*.* @@siem.example.com:514
EOF

sudo systemctl restart rsyslog
```

#### Security Monitoring Script
```bash
#!/bin/bash
# /opt/security-monitor.sh

# Monitor failed login attempts
FAILED_LOGINS=$(grep "authentication failure" /var/log/auth.log | wc -l)
if [ $FAILED_LOGINS -gt 10 ]; then
    echo "ALERT: $FAILED_LOGINS failed login attempts detected" | mail -s "Security Alert" admin@example.com
fi

# Monitor unusual API activity
SUSPICIOUS_API=$(docker-compose logs netbird-management | grep -E "(401|403|429)" | wc -l)
if [ $SUSPICIOUS_API -gt 50 ]; then
    echo "ALERT: Suspicious API activity detected" | mail -s "API Security Alert" admin@example.com
fi

# Check for unauthorized configuration changes
CONFIG_CHANGES=$(docker-compose logs netbird-management | grep -i "config.*changed" | wc -l)
if [ $CONFIG_CHANGES -gt 0 ]; then
    echo "ALERT: Configuration changes detected" | mail -s "Config Change Alert" admin@example.com
fi
```

### Audit Logging
```json
{
  "AuditConfig": {
    "Enabled": true,
    "LogLevel": "INFO",
    "RetentionDays": 90,
    "Events": [
      "user.login",
      "user.logout", 
      "user.created",
      "user.deleted",
      "peer.connected",
      "peer.disconnected",
      "policy.created",
      "policy.modified",
      "policy.deleted"
    ]
  }
}
```

## 🔄 Backup and Recovery Security

### Encrypted Backups
```bash
#!/bin/bash
# Secure backup script with encryption

BACKUP_DIR="/opt/backups/netbird"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
GPG_RECIPIENT="admin@example.com"

# Create encrypted database backup
docker-compose exec -T netbird-management pg_dump -U netbird netbird | \
  gpg --cipher-algo AES256 --compress-algo 2 --symmetric --output $BACKUP_DIR/netbird_db_$TIMESTAMP.sql.gpg

# Create encrypted configuration backup
tar -czf - /opt/netbird /etc/nginx/sites-available/netbird /etc/letsencrypt | \
  gpg --cipher-algo AES256 --compress-algo 2 --symmetric --output $BACKUP_DIR/netbird_config_$TIMESTAMP.tar.gz.gpg

# Secure backup permissions
chmod 600 $BACKUP_DIR/*.gpg
chown root:root $BACKUP_DIR/*.gpg

# Upload to secure cloud storage with client-side encryption
aws s3 cp $BACKUP_DIR/ s3://secure-backup-bucket/netbird/ --recursive --sse aws:kms --sse-kms-key-id alias/backup-key
```

### Recovery Security
```bash
# Secure recovery procedure
# 1. Verify backup integrity
gpg --verify backup.sig backup.tar.gz.gpg

# 2. Decrypt backup in secure environment
gpg --output backup.tar.gz --decrypt backup.tar.gz.gpg

# 3. Verify checksums
sha256sum -c backup.sha256

# 4. Restore with proper permissions
tar -xzf backup.tar.gz
chown -R netbird:netbird /opt/netbird
chmod -R 750 /opt/netbird
```

## 🚨 Incident Response

### Security Incident Playbook

#### 1. Detection and Analysis
```bash
# Immediate assessment commands
# Check active connections
ss -tulpn | grep -E "(443|80|22)"

# Review recent authentication events
journalctl -u sshd --since "1 hour ago"

# Check Docker container status
docker-compose ps
docker-compose logs --tail=100

# Review nginx access logs for anomalies
tail -100 /var/log/nginx/access.log | grep -E "(404|401|403|500)"
```

#### 2. Containment
```bash
# Block suspicious IP addresses
sudo ufw insert 1 deny from <suspicious-ip>

# Temporarily disable API access
docker-compose stop netbird-dashboard

# Rotate API tokens
curl -X POST "https://nb.example.com/api/auth/revoke-all-tokens" \
  -H "Authorization: Bearer $ADMIN_TOKEN"
```

#### 3. Eradication and Recovery
```bash
# Update all system packages
sudo apt update && sudo apt upgrade -y

# Rebuild containers with latest images
docker-compose pull
docker-compose up -d --force-recreate

# Verify system integrity
debsums -c
aide --check
```

#### 4. Lessons Learned
- Document the incident timeline
- Identify root cause
- Update security controls
- Review and update incident response procedures

## 🔍 Security Auditing

### Regular Security Assessments

#### Automated Security Scanning
```bash
#!/bin/bash
# Daily security scan script

# Vulnerability scanning with lynis
sudo lynis audit system

# Check for suspicious files
find /var/log -name "*.log" -mtime -1 -exec grep -l "FAILED\|ERROR\|DENIED" {} \;

# Docker security scan
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image netbirdio/management:latest

# SSL certificate check
echo | openssl s_client -connect nb.example.com:443 2>/dev/null | \
  openssl x509 -noout -dates
```

#### Monthly Security Review Checklist
- [ ] Review user access permissions
- [ ] Audit Azure AD conditional access policies
- [ ] Check SSL certificate expiration dates
- [ ] Review firewall rules and logs
- [ ] Verify backup integrity and test recovery
- [ ] Update security documentation
- [ ] Review and test incident response procedures
- [ ] Scan for vulnerabilities and apply patches

### Compliance Considerations

#### GDPR Compliance
- **Data Minimization**: Collect only necessary user data
- **Right to Erasure**: Implement user data deletion procedures
- **Data Portability**: Provide user data export functionality
- **Privacy by Design**: Implement privacy controls from the start

#### SOC 2 Type II Considerations
- **Security**: Implement comprehensive security controls
- **Availability**: Ensure high availability and disaster recovery
- **Processing Integrity**: Maintain data accuracy and completeness
- **Confidentiality**: Protect sensitive information
- **Privacy**: Implement privacy protection measures

## 📋 Security Checklist

### Pre-Deployment Security Checklist
- [ ] Server hardening completed
- [ ] Firewall rules configured and tested
- [ ] SSL/TLS certificates properly configured
- [ ] Azure AD application securely configured
- [ ] Strong passwords and MFA enabled
- [ ] Backup strategy implemented and tested
- [ ] Monitoring and alerting configured
- [ ] Incident response plan documented

### Post-Deployment Security Checklist
- [ ] All default passwords changed
- [ ] Unnecessary services disabled
- [ ] Log monitoring active
- [ ] Regular security updates scheduled
- [ ] Access controls verified
- [ ] Network segmentation tested
- [ ] Backup and recovery tested
- [ ] Security documentation updated

---

## 🆘 Security Support

For security-related questions or to report vulnerabilities:

- **Security Email**: security@panoptic.ie
- **Bug Bounty Program**: Contact us for responsible disclosure
- **Emergency Contact**: Available 24/7 for critical security issues

Remember: Security is not a one-time setup but an ongoing process. Regularly review and update your security posture to address emerging threats and vulnerabilities.