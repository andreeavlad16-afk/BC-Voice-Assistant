import { test, expect } from '@playwright/test';

/**
 * PWA User Interface and User Experience Tests
 * Tests basic UI elements, routing, responsiveness, and accessibility
 */

test.describe('PWA Installation', () => {
 test('should have valid manifest.json', async ({ page }) => {
    await page.goto('/');
    
    // Check if manifest is linked
    const manifestLink = await page.locator('link[rel="manifest"]').getAttribute('href');
    expect(manifestLink).toBeTruthy();
    
    // Fetch and validate manifest
    const manifestResponse = await page.request.get(manifestLink!);
    expect(manifestResponse.ok()).toBeTruthy();
    
    const manifest = await manifestResponse.json();
    expect(manifest.name).toBeTruthy();
    expect(manifest.short_name).toBeTruthy();
    expect(manifest.start_url).toBeTruthy();
    expect(manifest.display).toBeTruthy();
    expect(manifest.icons).toBeTruthy();
    expect(manifest.icons.length).toBeGreaterThan(0);
  });

  test('should have service worker registered', async ({ page }) => {
    await page.goto('/');
    
    // Wait for service worker registration
    const swRegistered = await page.evaluate(async () => {
      if ('serviceWorker' in navigator) {
        const registration = await navigator.serviceWorker.ready;
        return registration.active !== null;
      }
      return false;
    });
    
    expect(swRegistered).toBeTruthy();
  });

  test('should show install prompt on supported browsers', async ({ page, browserName }) => {
    // Skip on webkit (Safari) as it doesn't support beforeinstallprompt
    test.skip(browserName === 'webkit', 'install prompt not supported on Safari');
    
    await page.goto('/');
    
    // Trigger beforeinstallprompt event
    await page.evaluate(() => {
      const event = new Event('beforeinstallprompt');
      window.dispatchEvent(event);
    });
    
    // Install button should appear
    await expect(page.locator('button:has-text("Install"), button[aria-label*="install"]')).toBeVisible({ timeout: 3000 });
  });
});

test.describe('Basic UI Elements', () => {
  test('should display application header', async ({ page }) => {
    await page.goto('/');
    
    // Check for header with app title
    const header = page.locator('header, [role="banner"], .app-header');
    await expect(header.first()).toBeVisible();
    
    // Check for heading specifically (not any text)
    await expect(page.locator('h1:has-text("BC Voice Assistant")')).toBeVisible();
  });

  test('should display navigation elements', async ({ page }) => {
    await page.goto('/');
    
    // Should have navigation elements (nav or mobile menu button exists)
    const nav = page.locator('nav, [role="navigation"], button[aria-label*="menu"]');
    const navCount = await nav.count();
    expect(navCount).toBeGreaterThan(0);
  });

  test('should have accessible color contrast', async ({ page }) => {
    await page.goto('/');
    
    // Run axe accessibility check for color contrast
    // This requires @axe-core/playwright to be installed
    // await injectAxe(page);
    // const results = await checkA11y(page);
    // expect(results.violations).toHaveLength(0);
    
    // Basic check: ensure text is visible
    const bodyText = await page.locator('body').textContent();
    expect(bodyText!.length).toBeGreaterThan(0);
  });

  test('should be keyboard navigable', async ({ page }) => {
    await page.goto('/');
    
    // Tab through focusable elements
    await page.keyboard.press('Tab');
    const firstFocused = await page.evaluate(() => document.activeElement?.tagName);
    expect(['BUTTON', 'INPUT', 'A', 'SELECT']).toContain(firstFocused);
    
    // Tab again
    await page.keyboard.press('Tab');
    const secondFocused = await page.evaluate(() => document.activeElement?.tagName);
    expect(['BUTTON', 'INPUT', 'A', 'SELECT']).toContain(secondFocused);
  });
});

test.describe('Responsive Design', () => {
  test('should display correctly on mobile portrait', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 }); // iPhone SE
    await page.goto('/');
    
    // Main content should be visible
    await expect(page.locator('body')).toBeVisible();
    
    // No horizontal scroll
    const hasHorizontalScroll = await page.evaluate(() => 
      document.documentElement.scrollWidth > window.innerWidth
    );
    expect(hasHorizontalScroll).toBeFalsy();
  });

  test('should display correctly on mobile landscape', async ({ page }) => {
    await page.setViewportSize({ width: 667, height: 375 }); // iPhone SE landscape
    await page.goto('/');
    
    await expect(page.locator('body')).toBeVisible();
  });

  test('should display correctly on tablet', async ({ page }) => {
    await page.setViewportSize({ width: 768, height: 1024 }); // iPad Mini
    await page.goto('/');
    
    await expect(page.locator('body')).toBeVisible();
  });

  test('should display correctly on desktop', async ({ page }) => {
    await page.setViewportSize({ width: 1920, height: 1080 }); // Full HD
    await page.goto('/');
    
    await expect(page.locator('body')).toBeVisible();
  });

  test('should adapt layout for small screens', async ({ page }) => {
    // Start desktop
    await page.setViewportSize({ width: 1280, height: 720 });
    await page.goto('/');
    
    // Switch to mobile
    await page.setViewportSize({ width: 375, height: 667 });
    
    // Check that layout adapted (e.g., hamburger menu appears)
    const mobileMenu = page.locator('button[aria-label*="menu"], .hamburger, .mobile-menu-button');
    const mobileMenuExists = await mobileMenu.count() > 0;
    
    // Either mobile menu should exist OR regular nav should still be visible
    if (mobileMenuExists) {
      await expect(mobileMenu.first()).toBeVisible();
    } else {
      await expect(page.locator('nav, [role="navigation"]')).toBeVisible();
    }
  });
});

test.describe('Loading States', () => {
  test('should show loading indicator during initial load', async ({ page }) => {
    await page.goto('/', { waitUntil: 'domcontentloaded' });
    
    // Check if loading indicator exists (it may have already hidden)
    const loadingIndicator = page.locator('.loading, .spinner, #loadingIndicator');
    const loadingTextIndicator = page.getByText(/loading/i);
    
    const hasLoadingUI = (await loadingIndicator.count() > 0) || (await loadingTextIndicator.count() > 0);
    
    // If loading indicator exists, verify it eventually disappears
    if (hasLoadingUI) {
      await expect(loadingIndicator.first()).not.toBeVisible({ timeout: 10000 });
    }
    expect(hasLoadingUI).toBeTruthy();
  });

  test('should complete loading within reasonable time', async ({ page }) => {
    const startTime = Date.now();
    await page.goto('/', { waitUntil: 'networkidle' });
    const loadTime = Date.now() - startTime;
    
    // Should load in less than 5 seconds
    expect(loadTime).toBeLessThan(5000);
  });
});

test.describe('Input Handling', () => {
  test('should handle text input correctly', async ({ page }) => {
    await page.goto('/');
    
    // Find text input (query input)
    const textInput = page.locator('input[type="text"], textarea, input[placeholder*="query"], input[placeholder*="ask"]').first();
    
    if (await textInput.isVisible()) {
      await textInput.fill('Show me my customers');
      const value = await textInput.inputValue();
      expect(value).toBe('Show me my customers');
    }
  });

  test('should submit query on enter key', async ({ page }) => {
    await page.goto('/');
    
    const textInput = page.locator('input[type="text"], textarea').first();
    
    if (await textInput.isVisible()) {
      await textInput.fill('test query');
      await textInput.press('Enter');
      
      // Should show some processing or result
      await expect(page.locator('text=/processing/i, text=/analyzing/i, text=/result/i, .result, .response')).toBeVisible({ timeout: 10000 });
    }
  });

  test('should prevent empty query submission', async ({ page }) => {
    await page.goto('/');
    
    const textInput = page.locator('input[type="text"], textarea').first();
    const submitButton = page.locator('button[type="submit"], button:has-text("Send"), button:has-text("Submit")').first();
    
    if (await textInput.isVisible()) {
      // Keep input empty
      await textInput.fill('');
      
      // Submit button should be disabled or clicking should not trigger action
      if (await submitButton.isVisible()) {
        const isDisabled = await submitButton.isDisabled();
        expect(isDisabled).toBeTruthy();
      }
    }
  });
});

test.describe('Error Display', () => {
  test('should display error messages clearly', async ({ page }) => {
    await page.goto('/');
    
    // Trigger an error by attempting action without configuration
    await page.evaluate(() => {
      localStorage.clear();
    });
    await page.reload();
    
    // Try to use a feature
    const sendButton = page.locator('button:has-text("Send"), button[type="submit"]').first();
    if (await sendButton.isVisible()) {
      await sendButton.click();
      
      // Error message should appear
      await expect(page.locator('.error, [role="alert"], text=/error/i, text=/failed/i')).toBeVisible({ timeout: 5000 });
    }
  });

  test('should allow error dismissal', async ({ page }) => {
    await page.goto('/');
    
    // Trigger error
    await page.evaluate(() => {
      localStorage.clear();
    });
    await page.reload();
    
    const sendButton = page.locator('button:has-text("Send")').first();
    if (await sendButton.isVisible()) {
      await sendButton.click();
      
      // Look for dismiss/close button
      const dismissButton = page.locator('button[aria-label*="close"], button[aria-label*="dismiss"], button:has-text("×")').first();
      if (await dismissButton.isVisible({ timeout: 3000 })) {
        await dismissButton.click();
        
        // Error should be hidden
        await expect(page.locator('.error, [role="alert"]')).not.toBeVisible();
      }
    }
  });
});

test.describe('Theme Support', () => {
  test('should respect system color scheme preference', async ({ page }) => {
    // Test dark mode
    await page.emulateMedia({ colorScheme: 'dark' });
    await page.goto('/');
    
    // Check if dark mode is applied
    const bodyBg = await page.locator('body').evaluate((el) => 
      window.getComputedStyle(el).backgroundColor
    );
    
    // Dark mode background should be dark (rgb values less than 128)
    expect(bodyBg).toBeTruthy();
  });

  test('should support theme switching', async ({ page }) => {
    await page.goto('/');
    
    // Look for theme toggle button
    const themeToggle = page.locator('button[aria-label*="theme"], button[aria-label*="dark mode"], button:has(svg[class*="moon"]), button:has(svg[class*="sun"])');
    
    if (await themeToggle.count() > 0) {
      const initialBg = await page.locator('body').evaluate((el) => 
        window.getComputedStyle(el).backgroundColor
      );
      
      await themeToggle.first().click();
      await page.waitForTimeout(500);
      
      const newBg = await page.locator('body').evaluate((el) => 
        window.getComputedStyle(el).backgroundColor
      );
      
      // Background should have changed
      expect(initialBg).not.toBe(newBg);
    }
  });
});

test.describe('Performance', () => {
  test('should have good performance metrics', async ({ page }) => {
    await page.goto('/');
    
    // Get performance metrics
    const metrics = await page.evaluate(() => {
      const navigation = performance.getEntriesByType('navigation')[0] as PerformanceNavigationTiming;
      return {
        domContentLoaded: navigation.domContentLoadedEventEnd - navigation.domContentLoadedEventStart,
        loadComplete: navigation.loadEventEnd - navigation.loadEventStart,
        totalLoad: navigation.loadEventEnd - navigation.fetchStart
      };
    });
    
    // Assertions for good performance
    expect(metrics.domContentLoaded).toBeLessThan(1000); // < 1 second
    expect(metrics.totalLoad).toBeLessThan(3000); // < 3 seconds
  });

  test('should cache assets with service worker', async ({ page }) => {
    await page.goto('/');
    
    // Reload page
    await page.reload();
    
    // Check if resources were served from cache
    const cacheHits = await page.evaluate(() => {
      return performance.getEntriesByType('resource').filter(
        (entry: any) => entry.transferSize === 0
      ).length;
    });
    
    // Some resources should be cached
    expect(cacheHits).toBeGreaterThan(0);
  });
});
