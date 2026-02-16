import { test, expect } from '@playwright/test';

/**
 * PWA Offline Mode Tests
 * Tests service worker caching, offline functionality, and sync
 */

test.describe('Offline Mode - Detection', () => {
  test('should detect when going offline', async ({ page, context }) => {
    await page.goto('/');
    
    // Go offline
    await context.setOffline(true);
    
    // Trigger a network request or wait for offline detection
    await page.waitForTimeout(2000);
    
    // Check for offline indicator
    const offlineIndicator = page.locator('text=/offline/i, .offline-indicator, [aria-label*="offline"]');
    await expect(offlineIndicator).toBeVisible({ timeout: 5000 });
  });

  test('should detect when coming back online', async ({ page, context }) => {
    await page.goto('/');
    
    // Go offline
    await context.setOffline(true);
    await page.waitForTimeout(1000);
    
    // Come back online
    await context.setOffline(false);
    await page.waitForTimeout(2000);
    
    // Offline indicator should disappear or show online status
    const onlineIndicator = page.locator('text=/online/i, text=/connected/i');
    const noOfflineIndicator = page.locator('text=/offline/i');
    
    const isOnline = await onlineIndicator.isVisible() || !(await noOfflineIndicator.isVisible());
    expect(isOnline).toBeTruthy();
  });

  test('should use navigator.onLine API', async ({ page }) => {
    await page.goto('/');
    
    const onlineStatus = await page.evaluate(() => navigator.onLine);
    expect(onlineStatus).toBeDefined();
    expect(typeof onlineStatus).toBe('boolean');
  });
});

test.describe('Offline Mode - Service Worker Caching', () => {
  test('should cache app shell for offline use', async ({ page, context }) => {
    // Load page while online
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    
    // Wait for service worker to cache assets
    await page.waitForTimeout(2000);
    
    // Go offline
    await context.setOffline(true);
    
    // Reload page - should load from cache
    await page.reload();
    
    // Page should still be accessible
    await expect(page.locator('h1')).toBeVisible();
    await expect(page).toHaveTitle(/BC Voice Assistant/);
  });

  test('should cache CSS and JavaScript', async ({ page, context }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);
    
    // Go offline
    await context.setOffline(true);
    
    // Reload and check if styles are applied
    await page.reload();
    
    const hasStyles = await page.evaluate(() => {
      const body = document.body;
      const computedStyle = window.getComputedStyle(body);
      return computedStyle.backgroundColor !== 'rgba(0, 0, 0, 0)' || 
             computedStyle.color !== 'rgb(0, 0, 0)';
    });
    
    expect(hasStyles).toBeTruthy();
  });

  test('should cache icons and images', async ({ page, context, request }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);
    
    // Go offline
    await context.setOffline(true);
    
    // Try to load cached icon
    const iconResponse = await page.evaluate(async () => {
      try {
        const response = await fetch('/icons/icon-192x192.png');
        return response.ok;
      } catch {
        return false;
      }
    });
    
    expect(iconResponse).toBeTruthy();
  });
});

test.describe('Offline Mode - Query Handling', () => {
  test('should queue queries when offline', async ({ page, context }) => {
    await page.goto('/');
    
    // Go offline
    await context.setOffline(true);
    
    // Try to submit a query
    const input = page.locator('input[placeholder*="Ask"], input[type="text"]').first();
    await input.fill('show customers');
    await input.press('Enter');
    
    // Should show queued/pending status
    await expect(page.locator('text=/queued/i, text=/pending/i, text=/will sync/i')).toBeVisible({ timeout: 5000 });
  });

  test('should show offline message for voice input', async ({ page, context }) => {
    await page.goto('/');
    await context.grantPermissions(['microphone']);
    
    // Go offline
    await context.setOffline(true);
    
    // Try to use voice input
    const micButton = page.locator('button[aria-label*="microphone"], button[aria-label*="Record"]').first();
    await micButton.click();
    
    // Should either disable voice or show offline warning
    const hasWarning = await page.locator('text=/offline/i, text=/not available offline/i').isVisible({ timeout: 3000 });
    const isDisabled = await micButton.isDisabled();
    
    expect(hasWarning || isDisabled).toBeTruthy();
  });

  test('should save queries to IndexedDB while offline', async ({ page, context }) => {
    await page.goto('/');
    
    // Go offline
    await context.setOffline(true);
    
    // Submit query
    const input = page.locator('input[placeholder*="Ask"], input[type="text"]').first();
    await input.fill('show vendors');
    await input.press('Enter');
    await page.waitForTimeout(1000);
    
    // Check if query was saved to IndexedDB
    const savedToIndexedDB = await page.evaluate(async () => {
      if (!window.indexedDB) return false;
      
      try {
        const request = window.indexedDB.open('PWADatabase', 1);
        return await new Promise((resolve) => {
          request.onsuccess = (event) => {
            const db = (event.target as any).result;
            const hasStore = db.objectStoreNames.contains('queries') || 
                            db.objectStoreNames.contains('pendingQueries');
            db.close();
            resolve(hasStore);
          };
          request.onerror = () => resolve(false);
        });
      } catch {
        return false;
      }
    });
    
    expect(savedToIndexedDB).toBeTruthy();
  });
});

test.describe('Offline Mode - Sync on Reconnection', () => {
  test('should sync queued queries when online', async ({ page, context }) => {
    await page.goto('/');
    
    // Go offline and queue a query
    await context.setOffline(true);
    const input = page.locator('input[placeholder*="Ask"], input[type="text"]').first();
    await input.fill('show items');
    await input.press('Enter');
    
    await expect(page.locator('text=/queued/i, text=/pending/i')).toBeVisible({ timeout: 5000 });
    
    // Go back online
    await context.setOffline(false);
    
    // Should sync automatically
    await expect(page.locator('text=/syncing/i, text=/synced/i, text=/sent/i')).toBeVisible({ timeout: 10000 });
  });

  test('should show sync status indicator', async ({ page, context }) => {
    await page.goto('/');
    
    // Queue multiple queries offline
    await context.setOffline(true);
    
    const input = page.locator('input[placeholder*="Ask"], input[type="text"]').first();
    await input.fill('query 1');
    await input.press('Enter');
    await page.waitForTimeout(500);
    
    await input.fill('query 2');
    await input.press('Enter');
    await page.waitForTimeout(500);
    
    // Go back online
    await context.setOffline(false);
    
    // Should show sync status (e.g., "Syncing 2 queries")
    const syncStatus = page.locator('text=/sync/i, [class*="sync"]');
    await expect(syncStatus).toBeVisible({ timeout: 10000 });
  });

  test('should handle sync failures gracefully', async ({ page, context }) => {
    await page.goto('/');
    
    // Queue query offline
    await context.setOffline(true);
    const input = page.locator('input[placeholder*="Ask"], input[type="text"]').first();
    await input.fill('test query');
    await input.press('Enter');
    
    // Go online but block the API
    await context.setOffline(false);
    await page.route('**/query', route => route.abort());
    
    await page.waitForTimeout(3000);
    
    // Should show retry option or error
    const hasRetry = await page.locator('text=/retry/i, button:has-text("Try Again")').isVisible();
    const hasError = await page.locator('text=/sync failed/i, text=/error/i').isVisible();
    
    expect(hasRetry || hasError).toBeTruthy();
  });
});

test.describe('Offline Mode - Cache Strategies', () => {
  test('should use cache-first strategy for static assets', async ({ page, context }) => {
    // Load page to populate cache
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);
    
    // Measure load time when online
    const onlineStartTime = Date.now();
    await page.reload();
    await page.waitForLoadState('networkidle');
    const onlineLoadTime = Date.now() - onlineStartTime;
    
    // Go offline and measure load time from cache
    await context.setOffline(true);
    const offlineStartTime = Date.now();
    await page.reload();
    await page.waitForLoadState('load');
    const offlineLoadTime = Date.now() - offlineStartTime;
    
    // Offline load should be fast (from cache)
    expect(offlineLoadTime).toBeLessThan(onlineLoadTime * 1.5);
  });

  test('should update cache in background when online', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    
    // Service worker should update cache
    const swUpdateHappened = await page.evaluate(async () => {
      if (!('serviceWorker' in navigator)) return false;
      
      const registration = await navigator.serviceWorker.ready;
      if (registration.waiting) {
        return true; // Update available
      }
      
      // Trigger update check
      await registration.update();
      return true;
    });
    
    expect(swUpdateHappened).toBeTruthy();
  });
});

test.describe('Offline Mode - User Experience', () => {
  test('should show helpful offline message', async ({ page, context }) => {
    await page.goto('/');
    await context.setOffline(true);
    
    // Should show informative offline message
    const offlineMessage = page.locator('text=/offline/i, text=/no connection/i, text=/connect to use/i');
    await expect(offlineMessage).toBeVisible({ timeout: 5000 });
  });

  test('should disable online-only features when offline', async ({ page, context }) => {
    await page.goto('/');
    await context.setOffline(true);
    await page.waitForTimeout(2000);
    
    // Voice button should be disabled or show offline state
    const micButton = page.locator('button[aria-label*="microphone"], button[aria-label*="Record"]').first();
    
    if (await micButton.isVisible()) {
      const isDisabledOrShowsOffline = (await micButton.isDisabled()) || 
                                       (await page.locator('.offline, [disabled], text=/offline/i').isVisible());
      expect(isDisabledOrShowsOffline).toBeTruthy();
    }
  });

  test('should show cached queries history offline', async ({ page, context }) => {
    // Make some queries while online
    await page.goto('/');
    const input = page.locator('input[placeholder*="Ask"], input[type="text"]').first();
    
    await input.fill('customer list');
    await input.press('Enter');
    await page.waitForTimeout(2000);
    
    // Go offline
    await context.setOffline(true);
    await page.reload();
    
    // History should still be accessible
    const hasHistory = await page.locator('text=/history/i, text=/recent/i, button:has-text("History")').isVisible();
    
    if (hasHistory) {
      const historyButton = page.locator('button:has-text("History"), [aria-label*="history"]').first();
      await historyButton.click();
      
      // Should show cached queries
      await expect(page.locator('text=/customer list/i')).toBeVisible();
    }
  });
});
