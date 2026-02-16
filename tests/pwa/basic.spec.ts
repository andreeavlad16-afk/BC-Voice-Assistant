import { test, expect } from '@playwright/test';

/**
 * PWA Basic Functionality Tests
 * Tests core PWA features like loading, manifest, service worker
 */

test.describe('PWA Basic Functionality', () => {
  test('should load PWA home page', async ({ page }) => {
    await page.goto('/');
    
    // Check page title
    await expect(page).toHaveTitle(/BC Voice Assistant/);
    
    // Check main heading
    await expect(page.locator('h1')).toContainText('Voice Assistant');
  });

  test('should have valid manifest.json', async ({ page, request }) => {
    const response = await request.get('/manifest.json');
    expect(response.ok()).toBeTruthy();
    
    const manifest = await response.json();
    expect(manifest).toHaveProperty('name');
    expect(manifest).toHaveProperty('short_name');
    expect(manifest).toHaveProperty('start_url');
    expect(manifest).toHaveProperty('display', 'standalone');
    expect(manifest.icons).toBeDefined();
    expect(manifest.icons.length).toBeGreaterThan(0);
  });

  test('should register service worker', async ({ page }) => {
    await page.goto('/');
    
    // Wait for service worker registration
    const swRegistered = await page.evaluate(async () => {
      if ('serviceWorker' in navigator) {
        const registration = await navigator.serviceWorker.ready;
        return registration !== null;
      }
      return false;
    });
    
    expect(swRegistered).toBeTruthy();
  });

  test('should have proper icons', async ({ page, request }) => {
    const iconSizes = ['192x192', '512x512'];
    
    for (const size of iconSizes) {
      const response = await request.get(`/icons/icon-${size}.png`);
      expect(response.ok()).toBeTruthy();
      expect(response.headers()['content-type']).toContain('image/png');
    }
  });

  test('should be responsive on mobile', async ({ page }) => {
    // Set mobile viewport
    await page.setViewportSize({ width: 375, height: 667 });
    await page.goto('/');
    
    // Check that content is visible and not overflowing
    const bodyWidth = await page.evaluate(() => document.body.scrollWidth);
    const viewportWidth = await page.evaluate(() => window.innerWidth);
    
    expect(bodyWidth).toBeLessThanOrEqual(viewportWidth);
  });

  test('should show settings button', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('button[aria-label="Settings"], button:has-text("⚙")')).toBeVisible();
  });
});

test.describe('PWA Configuration', () => {
  test('should open settings modal', async ({ page }) => {
    await page.goto('/');
    
    // Click settings button
    await page.click('button[aria-label="Settings"], button:has-text("⚙")');
    
    // Check settings modal appears
    await expect(page.locator('text=Settings, text=Configuration')).toBeVisible();
  });

  test('should show configuration fields', async ({ page }) => {
    await page.goto('/');
    await page.click('button[aria-label="Settings"], button:has-text("⚙")');
    
    // Check for required configuration fields
    await expect(page.locator('input[placeholder*="BC Environment"], input[name*="environment"]')).toBeVisible();
    await expect(page.locator('input[placeholder*="Client ID"], input[name*="clientId"]')).toBeVisible();
    await expect(page.locator('input[placeholder*="Tenant ID"], input[name*="tenantId"]')).toBeVisible();
  });

  test('should save configuration to localStorage', async ({ page }) => {
    await page.goto('/');
    await page.click('button[aria-label="Settings"], button:has-text("⚙")');
    
    // Fill configuration
    const testConfig = {
      bcUrl: 'https://businesscentral.dynamics.com/test/test',
      clientId: 'test-client-id',
      tenantId: 'test-tenant-id'
    };
    
    await page.fill('input[placeholder*="BC Environment"], input[name*="environment"]', testConfig.bcUrl);
    await page.fill('input[placeholder*="Client ID"], input[name*="clientId"]', testConfig.clientId);
    await page.fill('input[placeholder*="Tenant ID"], input[name*="tenantId"]', testConfig.tenantId);
    
    // Save
    await page.click('button:has-text("Save")');
    
    // Verify saved to localStorage
    const savedConfig = await page.evaluate(() => {
      return {
        bcUrl: localStorage.getItem('bc_environment_url'),
        clientId: localStorage.getItem('azure_client_id'),
        tenantId: localStorage.getItem('azure_tenant_id')
      };
    });
    
    expect(savedConfig.bcUrl).toBe(testConfig.bcUrl);
    expect(savedConfig.clientId).toBe(testConfig.clientId);
    expect(savedConfig.tenantId).toBe(testConfig.tenantId);
  });

  test('should persist configuration after reload', async ({ page }) => {
    await page.goto('/');
    await page.click('button[aria-label="Settings"], button:has-text("⚙")');
    
    const testConfig = {
      bcUrl: 'https://businesscentral.dynamics.com/persist/test',
      clientId: 'persist-client-id',
      tenantId: 'persist-tenant-id'
    };
    
    await page.fill('input[placeholder*="BC Environment"], input[name*="environment"]', testConfig.bcUrl);
    await page.fill('input[placeholder*="Client ID"], input[name*="clientId"]', testConfig.clientId);
    await page.fill('input[placeholder*="Tenant ID"], input[name*="tenantId"]', testConfig.tenantId);
    await page.click('button:has-text("Save")');
    
    // Reload page
    await page.reload();
    
    // Open settings again
    await page.click('button[aria-label="Settings"], button:has-text("⚙")');
    
    // Verify values persisted
    await expect(page.locator('input[placeholder*="BC Environment"], input[name*="environment"]')).toHaveValue(testConfig.bcUrl);
    await expect(page.locator('input[placeholder*="Client ID"], input[name*="clientId"]')).toHaveValue(testConfig.clientId);
    await expect(page.locator('input[placeholder*="Tenant ID"], input[name*="tenantId"]')).toHaveValue(testConfig.tenantId);
  });
});
