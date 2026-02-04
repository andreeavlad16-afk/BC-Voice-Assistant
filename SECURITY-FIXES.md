# Security Fixes - February 2026

## Overview
This document details the security vulnerabilities identified and fixed in the BC Voice Assistant repository.

## Critical Security Issues Fixed

### 1. XSS (Cross-Site Scripting) Vulnerability in PWA
**Severity:** HIGH  
**Location:** `pwa/app.js`  
**Issue:** The `addMessage()` function was using `innerHTML` with unsanitized user input and server responses, creating an XSS vulnerability.

**Attack Vector:**
- User voice input containing malicious JavaScript code
- Server responses containing script tags or event handlers
- Example: `<img src=x onerror=alert('XSS')>`

**Fix Applied:**
- Replaced `innerHTML` with `textContent` to safely handle text
- Added DOM manipulation to create elements safely
- All user and server data is now properly escaped

**Before:**
```javascript
messageDiv.innerHTML = `<p>${text}</p>`;
```

**After:**
```javascript
const p = document.createElement('p');
p.textContent = text;
messageDiv.appendChild(p);
```

### 2. Missing Content Security Policy (CSP)
**Severity:** MEDIUM  
**Location:** `pwa/index.html`  
**Issue:** No Content Security Policy headers were configured, allowing potential XSS attacks even if code had vulnerabilities.

**Fix Applied:**
Added comprehensive CSP meta tag with strict policies:
- `default-src 'self'` - Only allow resources from same origin
- `script-src` - Only allow scripts from trusted CDNs (MSAL, SignalR)
- `connect-src` - Only allow connections to Azure, BC, and Microsoft services
- `style-src 'self' 'unsafe-inline'` - Allow inline styles for UI
- Removed `'unsafe-eval'` and other dangerous directives

### 3. Overly Permissive CORS Configuration
**Severity:** MEDIUM  
**Location:** `azure-relay/local.settings.json.example`  
**Issue:** CORS was set to `"*"` allowing any origin to make requests to the Azure Functions.

**Risk:**
- Any malicious website could call your Azure Functions
- Potential for CSRF attacks
- Unauthorized access to API endpoints

**Fix Applied:**
Changed CORS to whitelist only trusted origins:
```json
"CORS": "https://businesscentral.dynamics.com,https://*.dynamics.com,http://localhost:*,https://localhost:*"
```

**Note:** Production deployments should further restrict this to specific domains.

## Additional Security Improvements

### 4. Better Error Messages for 503 Errors
**Location:** `azure-relay/transcribe/index.js`  
**Issue:** Generic error messages made troubleshooting difficult and didn't help users understand the issue.

**Improvement:**
Added specific error handling for common HTTP status codes:
- 503: Service temporarily unavailable (cold start)
- 401/403: Authentication failures
- 429: Rate limiting
- 404: Endpoint misconfiguration

This helps users understand issues without exposing sensitive internal details.

## Security Best Practices Recommendations

### For Production Deployment

1. **API Key Management**
   - Use Azure Key Vault for storing secrets
   - Rotate API keys regularly
   - Never commit secrets to source control
   - Use Managed Identities where possible

2. **CORS Configuration**
   - Further restrict CORS to your specific BC tenant URL
   - Never use `"*"` in production
   - Example: `"CORS": "https://businesscentral.dynamics.com/your-tenant-id/"`

3. **Authentication & Authorization**
   - Implement proper Azure AD authentication on Function Apps
   - Use function keys or system-assigned managed identities
   - Validate JWT tokens on every request
   - Implement rate limiting per user

4. **Input Validation**
   - Validate all audio file sizes (prevent DoS via large files)
   - Limit audio duration (e.g., max 60 seconds)
   - Validate MIME types strictly
   - Sanitize all text responses from AI

5. **Network Security**
   - Deploy Function Apps behind Azure Front Door or App Gateway
   - Enable Private Endpoints for Azure OpenAI
   - Use Azure Private Link for SignalR
   - Enable DDoS protection

6. **Monitoring & Logging**
   - Enable Application Insights for security monitoring
   - Log all authentication failures
   - Monitor for unusual patterns (rate limiting triggers)
   - Set up alerts for security events

7. **Regular Security Audits**
   - Run dependency vulnerability scans (npm audit)
   - Use GitHub Dependabot alerts
   - Perform penetration testing
   - Review Azure Security Center recommendations

## Testing Security Fixes

To verify the XSS fix:
1. Try entering: `<script>alert('XSS')</script>` as voice input
2. Expected: Text appears literally, no script execution
3. Open browser console - no JavaScript errors

To verify CSP:
1. Open browser DevTools > Network tab
2. Check response headers for `Content-Security-Policy`
3. Try loading unauthorized script - should be blocked

To verify CORS:
1. Try accessing Function App from unauthorized origin
2. Should receive CORS error in browser console

## Status
✅ All critical security issues have been addressed  
✅ Best practices documented  
⚠️ Production deployment requires additional hardening (see recommendations)

## Related Files Modified
- `pwa/app.js` - XSS fix
- `pwa/index.html` - CSP added
- `azure-relay/local.settings.json.example` - CORS restricted
- `azure-relay/transcribe/index.js` - Better error handling

---
**Security Review Date:** February 4, 2026  
**Reviewed By:** Automated Security Agent  
**Next Review:** Before production deployment
