# NetBird Self-Hosted Deployer - Troubleshooting Guide

This guide covers common issues and their solutions when deploying NetBird with Azure AD SPA authentication.

## 🔍 Quick Diagnosis

### 1. Check Deployment Logs
```bash
# View recent deployment logs
journalctl -u docker -f

# Check NetBird container logs
docker-compose logs -f netbird-management
docker-compose logs -f netbird-dashboard
```

### 2. Verify Service Status
```bash
# Check all NetBird services
docker-compose ps

# Check nginx status
sudo systemctl status nginx

# Check SSL certificates
sudo certbot certificates
```

## 🚨 Common Issues

### OAuth Authentication Issues

#### Problem: 400 Bad Request during login
**Symptoms:**
- Users get 400 error when clicking "Login with Azure AD"
- Browser shows "Bad Request" or "invalid_request"
- Console shows CORS or token exchange errors

**Causes & Solutions:**

1. **Client Secret Configuration (Most Common)**
   ```
   Error: AADSTS7000218: The request body must contain the following parameter: 'client_assertion' or 'client_secret'
   ```
   
   **Solution:** Ensure Azure AD app is configured as SPA
   - Go to Azure Portal → App Registrations → Your App
   - Navigate to "Authentication"
   - Remove any "Web" platform configurations
   - Add "Single-page application" platform
   - Set redirect URI to: `https://yourdomain.com/auth`
   - Remove client secret from "Certificates & secrets"

2. **Incorrect Redirect URI**
   ```
   Error: AADSTS50011: The redirect URI specified in the request does not match
   ```
   
   **Solution:** Fix redirect URI configuration
   ```bash
   # Check your current domain configuration
   echo $NETBIRD_DOMAIN
   
   # Azure AD redirect URI should be:
   # https://yourdomain.com/auth
   ```

3. **PKCE Configuration Missing**
   **Solution:** Verify PKCE is enabled in Azure AD
   - App Registrations → Your App → Authentication
   - Under "Advanced settings" ensure:
     - "Allow public client flows" = Yes
     - "Supported account types" = appropriate selection

#### Problem: CORS Errors
**Symptoms:**
- Browser console shows CORS policy errors
- Network tab shows failed preflight requests

**Solution:**
```bash
# Check nginx configuration
sudo nginx -t

# Restart nginx if configuration is valid
sudo systemctl restart nginx

# Verify CORS headers in response
curl -H "Origin: https://yourdomain.com" \
     -H "Access-Control-Request-Method: POST" \
     -H "Access-Control-Request-Headers: X-Requested-With" \
     -X OPTIONS \
     https://yourdomain.com/api/oauth/login
```

### Nginx Configuration Issues

#### Problem: 404 on /auth callbacks
**Symptoms:**
- OAuth login redirects to /auth and shows 404
- Nginx error logs show "File not found"

**Solution:** Verify nginx SPA configuration
```nginx
# Check /etc/nginx/sites-available/netbird
location / {
    try_files $uri $uri.html $uri/ /index.html;
}

# Should NOT be:
# try_files $uri $uri/ =404;
```

**Fix if incorrect:**
```bash
sudo nano /etc/nginx/sites-available/netbird

# Update try_files directive
location / {
    try_files $uri $uri.html $uri/ /index.html;
}

sudo nginx -t
sudo systemctl reload nginx
```

#### Problem: SSL Certificate Issues
**Symptoms:**
- Browser shows "Not Secure" or certificate warnings
- Certbot renewal failures

**Diagnosis:**
```bash
# Check certificate status
sudo certbot certificates

# Check certificate expiration
openssl x509 -in /etc/letsencrypt/live/yourdomain.com/cert.pem -text -noout | grep "Not After"

# Test SSL configuration
openssl s_client -connect yourdomain.com:443 -servername yourdomain.com
```

**Solutions:**
1. **Certificate not issued:**
   ```bash
   # Ensure domain points to server
   nslookup yourdomain.com
   
   # Try manual certificate issuance
   sudo certbot --nginx -d yourdomain.com
   ```

2. **Certificate renewal issues:**
   ```bash
   # Test renewal
   sudo certbot renew --dry-run
   
   # Check renewal service
   sudo systemctl status certbot.timer
   ```

### NetBird Service Issues

#### Problem: Management API not accessible
**Symptoms:**
- Dashboard shows "Failed to connect to management API"
- Management container keeps restarting

**Diagnosis:**
```bash
# Check management container logs
docker-compose logs netbird-management

# Check if management API is listening
curl -k https://localhost:8080/api/status
```

**Common Solutions:**

1. **Database connection issues:**
   ```bash
   # Check if database is running
   docker-compose ps netbird-management
   
   # Reset database if corrupted
   docker-compose down
   docker volume rm netbird_netbird_mgmt
   docker-compose up -d
   ```

2. **Configuration file issues:**
   ```bash
   # Check management configuration
   docker-compose exec netbird-management cat /etc/netbird/management.json
   
   # Verify domain configuration matches
   grep -r "yourdomain.com" ./
   ```

#### Problem: Signal server connectivity
**Symptoms:**
- Peers cannot establish direct connections
- All traffic routes through relay

**Diagnosis:**
```bash
# Check signal server logs
docker-compose logs netbird-signal

# Test signal server connectivity
nc -zv yourdomain.com 10000
```

### Hetzner Cloud Issues

#### Problem: Server creation fails
**Symptoms:**
- "Quota exceeded" errors
- "SSH key not found" errors
- Server creation timeouts

**Solutions:**

1. **Quota issues:**
   ```bash
   # Check current usage in Hetzner Console
   # Upgrade account or request quota increase
   ```

2. **SSH key issues:**
   ```bash
   # List available SSH keys
   hcloud ssh-key list
   
   # Upload new SSH key
   hcloud ssh-key create --name "netbird-key" --public-key-from-file ~/.ssh/id_rsa.pub
   ```

3. **Network connectivity:**
   ```bash
   # Test Hetzner API connectivity
   curl -H "Authorization: Bearer $HCLOUD_TOKEN" https://api.hetzner.cloud/v1/servers
   ```

## 🛠️ Advanced Troubleshooting

### Enable Debug Logging

1. **NetBird Management Debug:**
   ```yaml
   # In docker-compose.yml
   services:
     netbird-management:
       environment:
         NETBIRD_LOG_LEVEL: DEBUG
   ```

2. **Nginx Debug:**
   ```nginx
   # In nginx.conf
   error_log /var/log/nginx/error.log debug;
   ```

3. **Docker Compose Debug:**
   ```bash
   # Run with verbose output
   docker-compose --verbose up -d
   ```

### Network Connectivity Tests

```bash
# Test external connectivity
curl -I https://api.netbird.io/health

# Test internal service connectivity
docker-compose exec netbird-management nc -zv netbird-signal 80

# Test database connectivity
docker-compose exec netbird-management nc -zv 127.0.0.1 5432
```

### Performance Diagnostics

```bash
# Check system resources
htop
df -h
free -m

# Check Docker resource usage
docker stats

# Monitor nginx access patterns
sudo tail -f /var/log/nginx/access.log
```

## 📞 Getting Help

### Information to Collect

When seeking help, please provide:

1. **System Information:**
   ```bash
   # OS version
   lsb_release -a
   
   # Docker version
   docker --version
   docker-compose --version
   
   # NetBird version
   docker-compose exec netbird-management /go/bin/netbird-mgmt --version
   ```

2. **Configuration Details:**
   ```bash
   # Sanitized management config (remove secrets)
   docker-compose exec netbird-management cat /etc/netbird/management.json | jq 'del(.HttpConfig.AuthAudience, .HttpConfig.AuthIssuer)'
   
   # Nginx configuration
   sudo nginx -T
   ```

3. **Recent Logs:**
   ```bash
   # Last 100 lines of relevant logs
   docker-compose logs --tail=100 netbird-management
   docker-compose logs --tail=100 netbird-dashboard
   sudo journalctl -u nginx --since "1 hour ago"
   ```

### Support Channels

- **GitHub Issues:** [Report bugs and feature requests](https://github.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer/issues)
- **GitHub Discussions:** [Community support and questions](https://github.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer/discussions)
- **Email Support:** support@panoptic.ie

### Before Reporting Issues

1. Search existing GitHub issues
2. Try the solutions in this troubleshooting guide
3. Check NetBird official documentation
4. Verify your Azure AD configuration matches our guide
5. Test with a fresh deployment if possible

---

**Remember:** Most OAuth issues are configuration-related. Double-check your Azure AD SPA setup before diving deeper into troubleshooting.