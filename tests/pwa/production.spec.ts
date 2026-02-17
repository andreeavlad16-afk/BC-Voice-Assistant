import { test, expect } from '@playwright/test';

/**
 * Production Configuration Tests
 * Validates production PWA has correct configuration
 * 
 * Run against production with:
 * PWA_URL=https://gray-sand-017a93f03.1.azurestaticapps.net npx playwright test tests/pwa/production.spec.ts
 * 
 * NOTE: Tests verify configuration only. Authentication requires user interaction
 * and is tested manually. Mobile auth uses redirect flow for iOS/Android compatibility.
 */

test.describe('Production Configuration', () => {
  
  test('should load production PWA', async ({ page }) => {
    await page.goto('/');
    
    // Wait for page to be fully loaded
    await page.waitForLoadState('networkidle');
    
    // Check page loaded successfully
    await expect(page).toHaveTitle(/Voice Assistant|BC Voice/i);
    
    // Verify version number is present (v2.2.47)
    const header = page.locator('h1');
    await expect(header).toContainText('v2.2.47');
  });

  test('should have correct BC environment URL in settings', async ({ page }) => {
    await page.goto('/');
    
    // Wait for config.js to load and execute
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);
    
    // Open settings
    const settingsButton = page.getByRole('button', { name: /settings/i });
    await settingsButton.click();
    
    // Check BC Environment URL field
    const bcUrlInput = page.locator('input[placeholder*="businesscentral"], input[value*="businesscentral"]').first();
    
    const bcUrl = await bcUrlInput.inputValue();
    
    // Verify it's GB-Demonstration, not GB-Old
    // Note: BC environment URL is the BASE URL only, API path is appended by app.js
    expect(bcUrl).toContain('GB-Demonstration');
    expect(bcUrl).not.toContain('GB-Old');
    expect(bcUrl).toContain('60d3cd31-aac9-4a19-90f7-4cff0310f993');
    expect(bcUrl).toContain('api.businesscentral.dynamics.com');
  });

  test('should have correct Azure Function URL in settings', async ({ page }) => {
    await page.goto('/');
    
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);
    
    // Open settings
    const settingsButton = page.getByRole('button', { name: /settings/i });
    await settingsButton.click();
    
    // Check Relay URL field
    const relayUrlInput = page.locator('input[placeholder*="transcribe"], input[value*="azurewebsites"]').first();
    
    const relayUrl = await relayUrlInput.inputValue();
    
    // Verify it's func-bcvoice-v2, not func-bcvoice-prod
    expect(relayUrl).toContain('func-bcvoice-v2');
    expect(relayUrl).not.toContain('func-bcvoice-prod');
    expect(relayUrl).toContain('.azurewebsites.net/api/relay');
  });

  test('should have auto-config loaded from config.js', async ({ page }) => {
    await page.goto('/');
    
    await page.waitForLoadState('networkidle');
    
    // Check if config.js auto-populated localStorage
    const configLoaded = await page.evaluate(() => {
      const clientId = localStorage.getItem('bc_clientId');
      const tenantId = localStorage.getItem('bc_tenantId');
      const bcEnv = localStorage.getItem('bc_environment');
      const relayUrl = localStorage.getItem('bc_relayUrl');
      
      return {
        clientId,
        tenantId,
        bcEnv,
        relayUrl
      };
    });
    
    // Verify correct client ID
    expect(configLoaded.clientId).toBe('2dfcd259-35d2-43f4-ad0c-7e8863588472');
    
    // Verify correct tenant ID
    expect(configLoaded.tenantId).toBe('60d3cd31-aac9-4a19-90f7-4cff0310f993');
    
    // Verify GB-Demonstration environment
    expect(configLoaded.bcEnv).toContain('GB-Demonstration');
    
    // Verify func-bcvoice-v2
    expect(configLoaded.relayUrl).toContain('func-bcvoice-v2');
    
    // Verify company parameter will be added by app.js (check config, not API URL)
    expect(configLoaded.bcEnv).toContain('api.businesscentral.dynamics.com');
  });

  test('should have service worker registered', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    
    // Check if service worker is supported and registered
    const swRegistered = await page.evaluate(async () => {
      if ('serviceWorker' in navigator) {
        const registration = await navigator.serviceWorker.getRegistration();
        return registration !== undefined;
      }
      return false;
    });
    
    expect(swRegistered).toBeTruthy();
  });

  test('should have PWA manifest', async ({ page }) => {
    await page.goto('/');
    
    // Check manifest link exists
    const manifestLink = page.locator('link[rel="manifest"]');
    await expect(manifestLink).toHaveCount(1);
    
    // Verify manifest loads successfully
    const manifestHref = await manifestLink.getAttribute('href');
    expect(manifestHref).toBeTruthy();
    
    // Load and validate manifest content
    const manifestResponse = await page.request.get(manifestHref!);
    expect(manifestResponse.ok()).toBeTruthy();
    
    const manifest = await manifestResponse.json();
    expect(manifest.name).toBe('BC Voice Assistant');
    expect(manifest.short_name).toBe('BC Voice');
  });
});
    const bcUrlInput = page.locator('input').filter({ hasText: /businesscentral|GB-Demonstration/i }).first();
    const transcribeUrlInput = page.locator('input').filter({ hasText: /azurewebsites|transcribe/i }).first();
    
    const bcUrl = await bcUrlInput.inputValue();
    const transcribeUrl = await transcribeUrlInput.inputValue();
    
    // All fields should be non-empty
    expect(bcUrl.length).toBeGreaterThan(0);
    expect(transcribeUrl.length).toBeGreaterThan(0);
    
    console.log('Current settings:', {
      bcUrl,
      transcribeUrl
    });
  });

  test('should not have 404 errors on page load', async ({ page }) => {
    const errorRequests: string[] = [];
    
    page.on('response', response => {
      if (response.status() === 404) {
        errorRequests.push(response.url());
      }
    });
    
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    
    // No 404 errors should occur
    expect(errorRequests).toEqual([]);
    
    if (errorRequests.length > 0) {
      console.error('404 errors found:', errorRequests);
    }
  });

  test('should load icon.svg successfully', async ({ page, request }) => {
    const iconResponse = await request.get('/icons/icon.svg');
    
    expect(iconResponse.ok()).toBeTruthy();
    expect(iconResponse.status()).toBe(200);
    
    const contentType = iconResponse.headers()['content-type'];
    expect(contentType).toContain('svg');
  });
});
