import { test, expect } from '@playwright/test';

/**
 * PWA Authentication and Configuration Tests
 * Tests configuration dialog, authentication flow, and credential management
 */

test.describe('Configuration Dialog', () => {
  test('should show configuration button on initial load', async ({ page }) => {
    await page.goto('/');
    
    // Look for settings/config button (usually a gear icon)
    const configButton = page.locator('button[aria-label*="settings"], button[aria-label*="config"], button:has(svg[class*="settings"]), button:has(svg[class*="gear"])');
    await expect(configButton.first()).toBeVisible();
  });

  test('should open configuration dialog when settings clicked', async ({ page }) => {
    await page.goto('/');
    
    const configButton = page.locator('button[aria-label*="settings"], button[aria-label*="config"]').first();
    await configButton.click();
    
    // Configuration dialog should appear
    await expect(page.locator('dialog, [role="dialog"], .config-dialog, .settings-dialog')).toBeVisible();
  });

  test('should display all required configuration fields', async ({ page }) => {
    await page.goto('/');
    
    const configButton = page.locator('button[aria-label*="settings"], button[aria-label*="config"]').first();
    await configButton.click();
    
    // Check for required fields
    await expect(page.locator('input[name*="url"], input[placeholder*="URL"], label:has-text("URL")')).toBeVisible();
    await expect(page.locator('input[name*="client"], input[placeholder*="Client ID"], label:has-text("Client")')).toBeVisible();
    await expect(page.locator('input[name*="tenant"], input[placeholder*="Tenant"], label:has-text("Tenant")')).toBeVisible();
  });

  test('should validate BC URL format', async ({ page }) => {
    await page.goto('/');
    
    const configButton = page.locator('button[aria-label*="settings"], button[aria-label*="config"]').first();
    await configButton.click();
    
    // Enter invalid URL
    const urlInput = page.locator('input[name*="url"], input[placeholder*="URL"]').first();
    await urlInput.fill('invalid-url');
    
    // Try to save
    const saveButton = page.locator('button:has-text("Save"), button:has-text("Apply")').first();
    await saveButton.click();
    
    // Should show validation error
    await expect(page.locator('text=/invalid.*url/i, text=/url.*format/i, .error')).toBeVisible({ timeout: 3000 });
  });

  test('should accept valid BC URL format', async ({ page }) => {
    await page.goto('/');
    
    const configButton = page.locator('button[aria-label*="settings"], button[aria-label*="config"]').first();
    await configButton.click();
    
    // Enter valid BC URL
    const urlInput = page.locator('input[name*="url"], input[placeholder*="URL"]').first();
    await urlInput.fill('https://businesscentral.dynamics.com/tenant-id/sandbox');
    
    const clientInput = page.locator('input[name*="client"], input[placeholder*="Client ID"]').first();
    await clientInput.fill('00000000-0000-0000-0000-000000000000');
    
    const tenantInput = page.locator('input[name*="tenant"], input[placeholder*="Tenant"]').first();
    await tenantInput.fill('00000000-0000-0000-0000-000000000000');
    
    const saveButton = page.locator('button:has-text("Save"), button:has-text("Apply")').first();
    await saveButton.click();
    
    // Dialog should close (config saved)
    await expect(page.locator('dialog, [role="dialog"]')).not.toBeVisible({ timeout: 5000 });
  });

  test('should persist configuration in localStorage', async ({ page }) => {
    await page.goto('/');
    
    const configButton = page.locator('button[aria-label*="settings"], button[aria-label*="config"]').first();
    await configButton.click();
    
    // Configure
    await page.locator('input[name*="url"], input[placeholder*="URL"]').first().fill('https://businesscentral.dynamics.com/test/prod');
    await page.locator('input[name*="client"]').first().fill('test-client-id');
    await page.locator('input[name*="tenant"]').first().fill('test-tenant-id');
    
    await page.locator('button:has-text("Save"), button:has-text("Apply")').first().click();
    
    // Reload page
    await page.reload();
    
    // Configuration should persist
    await configButton.click();
    const urlValue = await page.locator('input[name*="url"]').first().inputValue();
    expect(urlValue).toContain('businesscentral.dynamics.com');
  });
});

test.describe('Authentication Flow', () => {
  test.beforeEach(async ({ page }) => {
    // Set up test configuration
    await page.goto('/');
    await page.evaluate(() => {
      localStorage.setItem('bcConfig', JSON.stringify({
        bcUrl: 'https://businesscentral.dynamics.com/test/sandbox',
        clientId: 'test-client-id',
        tenantId: 'test-tenant-id'
      }));
    });
    await page.reload();
  });

  test('should show login button when not authenticated', async ({ page }) => {
    const loginButton = page.locator('button:has-text("Login"), button:has-text("Sign in"), button:has-text("Connect")');
    await expect(loginButton.first()).toBeVisible();
  });

  test('should initiate OAuth flow on login', async ({ page, context }) => {
    const loginButton = page.locator('button:has-text("Login"), button:has-text("Sign in")').first();
    
    // Listen for popup
    const popupPromise = context.waitForEvent('page');
    await loginButton.click();
    
    const popup = await popupPromise;
    
    // Should redirect to Azure AD login
    await expect(popup).toHaveURL(/login\.microsoftonline\.com|microsoftazuread-sso\.com/);
    
    await popup.close();
  });

  test('should handle authentication cancellation', async ({ page, context }) => {
    const loginButton = page.locator('button:has-text("Login"), button:has-text("Sign in")').first();
    
    const popupPromise = context.waitForEvent('page');
    await loginButton.click();
    
    const popup = await popupPromise;
    await popup.close();  // Simulate user closing the login window
    
    // Should show appropriate message
    await expect(page.locator('text=/authentication.*cancelled/i, text=/login.*cancelled/i')).toBeVisible({ timeout: 5000 });
  });

  test('should store authentication token after successful login', async ({ page }) => {
    // Mock successful authentication
    await page.evaluate(() => {
      localStorage.setItem('bcToken', JSON.stringify({
        accessToken: 'mock-token',
        expiresAt: Date.now() + 3600000
      }));
    });
    await page.reload();
    
    // Should show authenticated state
    await expect(page.locator('button:has-text("Login"), button:has-text("Sign in")')).not.toBeVisible();
    await expect(page.locator('text=/connected/i, text=/authenticated/i, .user-avatar')).toBeVisible();
  });

  test('should display logout button when authenticated', async ({ page }) => {
    // Mock authentication
    await page.evaluate(() => {
      localStorage.setItem('bcToken', JSON.stringify({
        accessToken: 'mock-token',
        expiresAt: Date.now() + 3600000
      }));
    });
    await page.reload();
    
    // Logout button should be visible (might be in menu)
    const logoutButton = page.locator('button:has-text("Logout"), button:has-text("Sign out"), button:has-text("Disconnect")');
    
    // Click settings to reveal logout if it's in menu
    const settingsButton = page.locator('button[aria-label*="settings"]').first();
    if (await settingsButton.isVisible()) {
      await settingsButton.click();
    }
    
    await expect(logoutButton.first()).toBeVisible({ timeout: 5000 });
  });

  test('should clear credentials on logout', async ({ page }) => {
    // Set up authenticated state
    await page.evaluate(() => {
      localStorage.setItem('bcToken', JSON.stringify({
        accessToken: 'mock-token',
        expiresAt: Date.now() + 3600000
      }));
    });
    await page.reload();
    
    // Find and click logout
    const settingsButton = page.locator('button[aria-label*="settings"]').first();
    if (await settingsButton.isVisible()) {
      await settingsButton.click();
    }
    
    const logoutButton = page.locator('button:has-text("Logout"), button:has-text("Sign out")').first();
    await logoutButton.click();
    
    // Check that token was cleared
    const hasToken = await page.evaluate(() => localStorage.getItem('bcToken') !== null);
    expect(hasToken).toBeFalsy();
    
    // Should show login button again
    await expect(page.locator('button:has-text("Login"), button:has-text("Sign in")')).toBeVisible();
  });
});

test.describe('Connection Status', () => {
  test('should show connection status indicator', async ({ page }) => {
    await page.goto('/');
    
    // Should have connection status indicator
    const statusIndicator = page.locator('.connection-status, [data-testid="connection-status"], .status-indicator');
    await expect(statusIndicator.first()).toBeVisible();
  });

  test('should indicate offline status when network is down', async ({ page, context }) => {
    await page.goto('/');
    
    // Simulate offline
    await context.setOffline(true);
    await page.reload();
    
    // Should show offline indicator
    await expect(page.locator('text=/offline/i, .offline-indicator, [data-status="offline"]')).toBeVisible({ timeout: 5000 });
    
    await context.setOffline(false);
  });

  test('should reconnect automatically when network restored', async ({ page, context }) => {
    await page.goto('/');
    
    // Go offline
    await context.setOffline(true);
    await page.waitForTimeout(1000);
    
    // Come back online
    await context.setOffline(false);
    await page.waitForTimeout(2000);
    
    // Should show online/connected status
    await expect(page.locator('text=/online/i, text=/connected/i, [data-status="online"]')).toBeVisible({ timeout: 10000 });
  });
});

test.describe('Error Handling', () => {
  test('should display meaningful error for invalid configuration', async ({ page }) => {
    await page.goto('/');
    
    // Set invalid config
    await page.evaluate(() => {
      localStorage.setItem('bcConfig', JSON.stringify({
        bcUrl: 'not-a-url',
        clientId: '',
        tenantId: ''
      }));
    });
    await page.reload();
    
    // Should show configuration error
    await expect(page.locator('text=/configuration.*invalid/i, text=/please.*configure/i')).toBeVisible({ timeout: 5000 });
  });

  test('should recover gracefully from token expiration', async ({ page }) => {
    // Set expired token
    await page.goto('/');
    await page.evaluate(() => {
      localStorage.setItem('bcToken', JSON.stringify({
        accessToken: 'expired-token',
        expiresAt: Date.now() - 3600000  // 1 hour ago
      }));
      localStorage.setItem('bcConfig', JSON.stringify({
        bcUrl: 'https://businesscentral.dynamics.com/test/sandbox',
        clientId: 'test-client-id',
        tenantId: 'test-tenant-id'
      }));
    });
    await page.reload();
    
    // Should prompt for re-authentication
    await expect(page.locator('button:has-text("Login"), button:has-text("Sign in"), text=/session.*expired/i')).toBeVisible({ timeout: 5000 });
  });
});
