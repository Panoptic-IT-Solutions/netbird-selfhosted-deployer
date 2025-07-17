---
name: Bug Report
about: Create a report to help us improve the NetBird Self-Hosted Deployer
title: '[BUG] '
labels: ['bug', 'needs-triage']
assignees: ''

---

## Bug Description
A clear and concise description of what the bug is.

## Expected Behavior
A clear and concise description of what you expected to happen.

## Actual Behavior
A clear and concise description of what actually happened.

## Steps to Reproduce
Steps to reproduce the behavior:
1. Run command '...'
2. Configure '...'
3. See error

## Environment Information
**Operating System:**
- OS: [e.g. Ubuntu 24.04]
- Architecture: [e.g. x86_64, ARM64]

**Deployment Details:**
- Script Version: [e.g. v2.2.0]
- Hetzner Server Type: [e.g. cax11]
- Server Location: [e.g. nbg1]

**Software Versions:**
- Docker: [e.g. 24.0.7]
- Docker Compose: [e.g. 2.21.0]
- NetBird Management: [e.g. 0.24.0]
- NetBird Dashboard: [e.g. 2.3.0]

**Azure AD Configuration:**
- Tenant Type: [e.g. Single tenant, Multi-tenant]
- Application Type: [e.g. SPA, Web App]
- Authentication Method: [e.g. PKCE, Client Secret]

## Error Logs
```bash
# Please include relevant error logs here
# You can get logs using:
# docker-compose logs netbird-management
# docker-compose logs netbird-dashboard
# journalctl -u nginx --since "1 hour ago"
```

## Configuration Files
<details>
<summary>Management Configuration (remove sensitive data)</summary>

```json
{
  "HttpConfig": {
    "Address": "0.0.0.0:80",
    "AuthIssuer": "https://login.microsoftonline.com/TENANT-ID/v2.0",
    "AuthAudience": "CLIENT-ID"
  }
}
```
</details>

<details>
<summary>Docker Compose Configuration</summary>

```yaml
# Include your docker-compose.yml (remove passwords/secrets)
```
</details>

<details>
<summary>Nginx Configuration</summary>

```nginx
# Include relevant nginx configuration
```
</details>

## Screenshots
If applicable, add screenshots to help explain your problem.

## Network Information
- Domain: [e.g. nb.example.com]
- DNS Provider: [e.g. Cloudflare, Route53]
- Firewall: [e.g. UFW, Hetzner Cloud Firewall]

## Additional Context
Add any other context about the problem here.

## Attempted Solutions
List any solutions you've already tried:
- [ ] Restarted Docker containers
- [ ] Checked firewall rules
- [ ] Verified DNS resolution
- [ ] Reviewed Azure AD configuration
- [ ] Consulted troubleshooting guide

## Checklist
Before submitting this issue, please confirm:
- [ ] I have searched existing issues for similar problems
- [ ] I have consulted the [troubleshooting guide](../docs/TROUBLESHOOTING.md)
- [ ] I have removed sensitive information from logs and configurations
- [ ] I have provided sufficient information to reproduce the issue
- [ ] I am using a supported version of the deployer script