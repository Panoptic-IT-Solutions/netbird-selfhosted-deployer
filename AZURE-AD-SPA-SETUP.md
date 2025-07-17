# Azure AD Configuration for NetBird Self-Hosted

This guide walks you through configuring Azure AD for NetBird authentication across all client types: web dashboard, desktop applications, and mobile devices. This comprehensive setup ensures seamless authentication for your entire NetBird infrastructure.

## 📱 Client Types Supported

- **🌐 Web Dashboard**: Browser-based management interface (SPA with PKCE)
- **💻 Desktop Clients**: NetBird desktop applications (Windows, macOS, Linux)
- **📱 Mobile Apps**: NetBird mobile applications (iOS, Android)
- **🔧 CLI Tools**: Command-line NetBird utilities

## 🎯 Why This Configuration?

- ✅ **Universal Compatibility**: Works with web, desktop, and mobile clients
- ✅ **Enhanced Security**: PKCE prevents authorization code interception attacks
- ✅ **No Client Secrets**: Eliminates the risk of secret exposure in client applications
- ✅ **Modern OAuth**: Follows current OAuth 2.1 best practices
- ✅ **Seamless Experience**: Single configuration for all NetBird clients
- ✅ **Eliminates 400 Errors**: Prevents conflicts between PKCE and client secret authentication

## 🚨 Common Issues This Fixes

| Error | Cause | Fix |
|-------|--------|-----|
| `400 Bad Request` on token exchange | Mixed PKCE + client secret | Configure as SPA (no client secret) |
| `404 Not Found` on `/auth` callback | Nginx SPA routing issue | Automatic nginx fix in deployment script |
| `AADSTS7000218: client_assertion required` | Web app config with PKCE | Switch to SPA platform type |
| Token request failed | Authentication method conflict | Use PKCE-only authentication |

## 📋 Step-by-Step Setup

### Step 1: Access Azure Portal
1. Go to [https://portal.azure.com](https://portal.azure.com)
2. Navigate to **Azure Active Directory** → **App Registrations**
3. Click **+ New registration**

### Step 2: Basic Application Settings
1. **Name**: `NetBird Self-Hosted` (or your preferred name)
2. **Supported account types**: `Accounts in this organizational directory only`
3. **Redirect URI**: Leave empty for now (we'll configure this in Step 4)
4. Click **Register**

### Step 3: Note Important IDs
From the **Overview** page, copy and save these values:
- **Application (client) ID**: `12345678-1234-1234-1234-123456789012`
- **Directory (tenant) ID**: `87654321-4321-4321-4321-210987654321`
- **Object ID**: `11111111-2222-3333-4444-555555555555`

### Step 4: Configure Application Platforms

⚠️ **CRITICAL**: This step configures authentication for all NetBird client types

#### 4.1: Configure Single Page Application (Web Dashboard)
1. Go to **Authentication** section
2. Under **Platform configurations**:
   - If you see a **Web** platform, click the **trash icon** to delete it
   - Click **+ Add a platform**
   - Select **Single-page application**
3. Add these **Redirect URIs** for the web dashboard:
   ```
   https://your-netbird-domain.com/auth
   https://your-netbird-domain.com/silent-auth
   ```
   Replace `your-netbird-domain.com` with your actual NetBird domain
4. Under **Implicit grant and hybrid flows**:
   - ✅ Check **Access tokens (used for implicit flows)**
   - ✅ Check **ID tokens (used for implicit and hybrid flows)**
5. Click **Configure**

#### 4.2: Configure Mobile and Desktop Applications
1. Still in the **Authentication** section
2. Click **+ Add a platform** again
3. Select **Mobile and desktop applications**
4. Add these **Redirect URIs** for NetBird clients:
   ```
   http://localhost:53000
   http://localhost:54000
   urn:ietf:wg:oauth:2.0:oob
   ```
   These URIs handle authentication for:
   - Desktop applications (localhost ports)
   - Mobile applications (custom schemes)
   - CLI tools (out-of-band flow)
5. Click **Configure**

### Step 5: Advanced Settings
1. Still in the **Authentication** section
2. Scroll down to **Advanced settings**
3. Set **Allow public client flows** to **Yes** ⚠️ **REQUIRED for mobile/desktop clients**
4. Set **Treat application as a public client** to **Yes**
5. Click **Save**

### Step 5.1: Configure Token Configuration (Optional but Recommended)
1. Go to **Token configuration** section
2. Click **+ Add optional claim**
3. Select **ID** token type
4. Add these claims for better user identification:
   - ✅ **email**
   - ✅ **family_name**
   - ✅ **given_name**
   - ✅ **preferred_username**
5. Click **Add**
6. If prompted about Microsoft Graph permissions, click **Yes, add them**

### Step 6: API Permissions
1. Go to **API permissions** section
2. You should see **Microsoft Graph** → **User.Read** (already present)
3. Click **+ Add a permission**
4. Select **Microsoft Graph** → **Delegated permissions**
5. Add: **User.Read.All**
6. **IMPORTANT**: Click **Grant admin consent for [your organization]**
7. Confirm by clicking **Yes**
8. Verify all permissions show **Granted for [organization]**

### Step 7: Expose an API (Required)
⚠️ **REQUIRED**: This prevents AADSTS65005 errors

1. Go to **Expose an API** section
2. Click **Set** next to **Application ID URI**
3. Accept the default: `api://[your-client-id]`
4. Click **Save**
5. Click **+ Add a scope**
6. Configure the scope:
   - **Scope name**: `api`
   - **Who can consent**: `Admins only`
   - **Admin consent display name**: `Access NetBird API`
   - **Admin consent description**: `Allows access to NetBird API`
   - **State**: `Enabled`
7. Click **Add scope**

### Step 8: Final Verification Checklist

Before proceeding, verify these settings:

#### Authentication Section:
- ✅ **Single-page application** platform configured with:
  - `https://your-domain.com/auth`
  - `https://your-domain.com/silent-auth`
- ✅ **Mobile and desktop applications** platform configured with:
  - `http://localhost:53000`
  - `http://localhost:54000`
  - `urn:ietf:wg:oauth:2.0:oob`
- ✅ Access tokens: **Enabled**
- ✅ ID tokens: **Enabled**
- ✅ Allow public client flows: **Yes**
- ✅ Treat application as a public client: **Yes**

#### API Permissions Section:
- ✅ Microsoft Graph → User.Read: **Granted**
- ✅ Microsoft Graph → User.Read.All: **Granted**
- ✅ Admin consent status: **Granted for [organization]**

#### Expose an API Section:
- ✅ Application ID URI: `api://[your-client-id]`
- ✅ Scope 'api': **Created and enabled**

#### Important Notes:
- ❌ **DO NOT create a client secret** - not needed for public clients
- ❌ **DO NOT use Web platform** - use SPA + Mobile/Desktop platforms
- ✅ **PKCE authentication** is handled automatically by all NetBird clients
- ✅ **Multiple platforms** enable universal client support

## 🔧 Configuration Values for NetBird

Use these values in your NetBird deployment:

```bash
# Azure AD Configuration
AZURE_TENANT_ID="your-tenant-id-here"
AZURE_CLIENT_ID="your-client-id-here"  
AZURE_OBJECT_ID="your-object-id-here"
AZURE_CLIENT_SECRET=""  # Empty for SPA configuration

# OAuth Configuration (automatic in deployment script)
AUTH_AUDIENCE="your-client-id-here"
AUTH_AUTHORITY="https://login.microsoftonline.com/your-tenant-id/v2.0"
AUTH_CLIENT_ID="your-client-id-here"
AUTH_CLIENT_SECRET=""  # Empty - no client secret for SPA
AUTH_REDIRECT_URI="/auth"
AUTH_SILENT_REDIRECT_URI="/silent-auth"
AUTH_SUPPORTED_SCOPES="openid profile email offline_access User.Read api://your-client-id/api"
```

## 🚨 Troubleshooting Common Issues

### 400 Bad Request on Token Exchange
**Cause**: Mixed authentication methods (PKCE + client secret)
**Fix**: 
1. Ensure Azure AD app is configured as **Single-page application**
2. Verify `AUTH_CLIENT_SECRET` is empty in NetBird configuration
3. Remove any Web platform configurations

### 404 Not Found on /auth Callback
**Cause**: Nginx not configured for SPA routing
**Fix**: The deployment script automatically applies this fix:
```nginx
# Nginx SPA routing fix
try_files $uri $uri.html $uri/ /index.html;
```

### AADSTS65005: scope 'api' doesn't exist
**Cause**: Missing API scope configuration
**Fix**: 
1. Go to **Expose an API** → Set Application ID URI
2. Add scope named 'api'
3. Ensure scope is enabled

### AADSTS500011: resource principal not found
**Cause**: Missing admin consent
**Fix**:
1. Go to **API permissions**
2. Click **Grant admin consent for [organization]**
3. Verify all permissions show "Granted"

### Token Exchange Still Failing
**Debug Steps**:
1. Check browser Developer Tools → Network tab
2. Look for the token request to `login.microsoftonline.com`
3. Verify the request contains:
   - `grant_type=authorization_code`
   - `code_verifier=...` (PKCE)
   - **NO** `client_secret` parameter
4. If you see both `code_verifier` and `client_secret`, the configuration is wrong

## 📱 Testing Your Configuration

### 1. DNS Test
```bash
dig your-netbird-domain.com +short
# Should return your server IP
```

### 2. HTTPS Test
```bash
curl -I https://your-netbird-domain.com/auth
# Should return: HTTP/1.1 200 OK
```

### 3. Web Dashboard OAuth Test
1. Go to `https://your-netbird-domain.com`
2. Click "Sign in with Microsoft"
3. Complete Azure AD authentication
4. Should redirect back without errors

### 4. Desktop Client Test
1. Install NetBird desktop client
2. Configure with your NetBird management URL
3. Click "Sign in with SSO"
4. Browser should open for Azure AD authentication
5. Should authenticate and return to desktop client

### 5. Mobile Client Test
1. Install NetBird mobile app
2. Configure with your NetBird management URL
3. Tap "Sign in with SSO"
4. In-app browser should handle Azure AD authentication
5. Should complete authentication within the app

### 6. Check Server Logs
```bash
ssh root@your-server 'docker-compose logs netbird-management | grep -i error'
# Should not show PKCE or token exchange errors
```

### 7. Test All Client Types
```bash
# Web dashboard
curl -I https://your-netbird-domain.com

# Management API (used by clients)
curl -I https://your-netbird-domain.com/api/status

# Signal server (used by clients)
curl -I https://your-netbird-domain.com:10000
```

## 🔒 Security Benefits

| Feature | Universal Public Client | Traditional Web App |
|---------|------------------------|-------------------|
| Client Secret | ❌ Not needed | ✅ Required |
| Code Interception Protection | ✅ PKCE prevents attacks | ❌ Vulnerable |
| Cross-Platform Security | ✅ No secrets in any client | ❌ Secrets can be exposed |
| OAuth 2.1 Compliance | ✅ Modern standard | ❌ Legacy approach |
| Mobile App Security | ✅ Native support | ❌ Requires workarounds |
| Desktop App Security | ✅ Local redirect handling | ❌ Complex setup |

## 📋 Platform-Specific Configuration Details

### Web Dashboard (Single Page Application)
- **Authentication Flow**: Authorization Code + PKCE
- **Redirect URIs**: HTTPS URLs on your domain
- **Token Storage**: Browser memory (not localStorage)
- **Security**: No client secrets, PKCE protection

### Desktop Applications
- **Authentication Flow**: Authorization Code + PKCE
- **Redirect URIs**: Localhost URLs (http://localhost:53000, http://localhost:54000)
- **Token Storage**: Secure OS keychain/credential manager
- **Security**: Local redirect handling, no embedded secrets

### Mobile Applications
- **Authentication Flow**: Authorization Code + PKCE
- **Redirect URIs**: Custom app schemes + localhost fallback
- **Token Storage**: Secure mobile keychain (iOS Keychain, Android Keystore)
- **Security**: In-app browser for authentication, secure token storage

### CLI Tools
- **Authentication Flow**: Device Code Flow (urn:ietf:wg:oauth:2.0:oob)
- **Redirect URIs**: Out-of-band redirect for headless environments
- **Token Storage**: Local secure storage
- **Security**: Device-specific authentication codes

## 📚 Additional Resources

- [NetBird Documentation](https://docs.netbird.io/selfhosted/identity-providers#azure-ad-microsoft-entra-id)
- [Microsoft Identity Platform - SPA](https://docs.microsoft.com/en-us/azure/active-directory/develop/scenario-spa-overview)
- [OAuth 2.1 Security Best Practices](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-security-topics)
- [PKCE RFC 7636](https://tools.ietf.org/html/rfc7636)

## ✅ Complete Configuration Checklist

Before deploying NetBird, ensure all platform configurations are complete:

### Azure AD Application Setup
- [ ] Azure AD app configured as **Public client application**
- [ ] **Single-page application** platform added with web redirect URIs:
  - [ ] `https://your-netbird-domain.com/auth`
  - [ ] `https://your-netbird-domain.com/silent-auth`
- [ ] **Mobile and desktop applications** platform added with client redirect URIs:
  - [ ] `http://localhost:53000`
  - [ ] `http://localhost:54000`
  - [ ] `urn:ietf:wg:oauth:2.0:oob`
- [ ] Access tokens and ID tokens enabled
- [ ] Public client flows allowed (**Yes**)
- [ ] Treat application as a public client (**Yes**)
- [ ] Microsoft Graph permissions granted with admin consent
- [ ] API scope 'api' created and enabled
- [ ] NO client secret created or used

### Infrastructure Setup
- [ ] DNS pointing to your NetBird server
- [ ] SSL certificate will be automatically generated
- [ ] Firewall rules configured for all NetBird services

### Client Testing Preparation
- [ ] Web dashboard URL accessible
- [ ] Management API endpoint reachable
- [ ] Signal server endpoint reachable
- [ ] Mobile app download links ready
- [ ] Desktop client installation packages ready

Once all items are checked, proceed with the NetBird deployment script which will automatically handle the OAuth and nginx configuration for all client types.

## 🔧 Client Configuration Examples

After deployment, configure your NetBird clients with these settings:

### Web Dashboard
Automatically configured by the deployment script.

### Desktop Client Configuration
```json
{
  "ManagementURL": "https://your-netbird-domain.com",
  "AdminURL": "https://your-netbird-domain.com",
  "SSO": {
    "Enabled": true,
    "ProviderConfig": {
      "ClientID": "your-azure-client-id",
      "Authority": "https://login.microsoftonline.com/your-tenant-id/v2.0",
      "Audience": "your-azure-client-id",
      "UseIDToken": false,
      "TokenEndpoint": "https://login.microsoftonline.com/your-tenant-id/oauth2/v2.0/token",
      "Scope": "openid profile email offline_access api://your-azure-client-id/api"
    }
  }
}
```

### Mobile App Configuration
Configure through the mobile app settings:
- **Management URL**: `https://your-netbird-domain.com`
- **SSO Provider**: Azure AD / Microsoft Entra ID
- **Client ID**: `your-azure-client-id`
- **Tenant ID**: `your-tenant-id`

### CLI Tool Configuration
```bash
netbird login --management-url https://your-netbird-domain.com \
              --sso-provider azure \
              --client-id your-azure-client-id \
              --tenant-id your-tenant-id
```