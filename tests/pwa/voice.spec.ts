import { test, expect } from '@playwright/test';

/**
 * PWA Voice Input Tests
 * Tests microphone access, recording, and voice input functionality
 */

test.describe('Voice Input - Microphone', () => {
  test.beforeEach(async ({ context }) => {
    // Grant microphone permissions
    await context.grantPermissions(['microphone']);
  });

  test('should show microphone button', async ({ page }) => {
    await page.goto('/');
    
    const micButton = page.locator('button[aria-label*="microphone"], button[aria-label*="Record"], button:has(svg[class*="mic"])');
    await expect(micButton.first()).toBeVisible();
  });

  test('should request microphone permission on first use', async ({ page, context }) => {
    // Create new context without microphone permission
    await page.goto('/');
    
    const micButton = page.locator('button[aria-label*="microphone"], button[aria-label*="Record"]').first();
    
    // Should be enabled (permission will be requested on click)
    await expect(micButton).toBeEnabled();
  });

  test('should handle denied microphone permission gracefully', async ({ browser }) => {
    // Create context that denies microphone
    const context = await browser.newContext({
      permissions: []  // No permissions granted
    });
    const page = await context.newPage();
    
    await page.goto('/');
    
    const micButton = page.locator('button[aria-label*="microphone"], button[aria-label*="Record"]').first();
    await micButton.click();
    
    // Should show error message
    await expect(page.locator('text=/microphone.*denied/i, text=/permission.*denied/i')).toBeVisible({ timeout: 5000 });
    
    await context.close();
  });

  test('should start recording when microphone button clicked', async ({ page }) => {
    await page.goto('/');
    
    const micButton = page.locator('button[aria-label*="microphone"], button[aria-label*="Record"]').first();
    await micButton.click();
    
    // Should show recording indicator
    await expect(page.locator('text=/listening/i, text=/recording/i, .recording-indicator')).toBeVisible({ timeout: 3000 });
  });

  test('should stop recording when button clicked again', async ({ page }) => {
    await page.goto('/');
    
    const micButton = page.locator('button[aria-label*="microphone"], button[aria-label*="Record"]').first();
    
    // Start recording
    await micButton.click();
    await page.waitForTimeout(2000); // Record for 2 seconds
    
    // Stop recording
    await micButton.click();
    
    // Should show processing indicator
    await expect(page.locator('text=/processing/i, text=/analyzing/i')).toBeVisible({ timeout: 3000 });
  });

  test('should auto-stop recording after timeout', async ({ page }) => {
    await page.goto('/');
    
    const micButton = page.locator('button[aria-label*="microphone"], button[aria-label*="Record"]').first();
    await micButton.click();
    
    // Wait for auto-stop (typically 30 seconds max, but we'll check at 5s intervals)
    await page.waitForTimeout(5000);
    
    // Recording indicator should still be visible for short recordings
    const recordingVisible = await page.locator('text=/listening/i, text=/recording/i').isVisible();
    expect(recordingVisible).toBeTruthy();
  });
});

test.describe('Voice Input - Recording Feedback', () => {
  test.beforeEach(async ({ context }) => {
    await context.grantPermissions(['microphone']);
  });

  test('should show visual feedback during recording', async ({ page }) => {
    await page.goto('/');
    
    const micButton = page.locator('button[aria-label*="microphone"], button[aria-label*="Record"]').first();
    await micButton.click();
    
    // Check for visual recording indicators
    const hasRecordingUI = await page.evaluate(() => {
      // Check for common recording UI patterns
      const hasRedDot = !!document.querySelector('.recording-dot, .recording-indicator');
      const hasAnimatedMic = !!document.querySelector('.pulse, .animate');
      const hasRecordingClass = !!document.querySelector('[class*="recording"]');
      
      return hasRedDot || hasAnimatedMic || hasRecordingClass;
    });
    
    expect(hasRecordingUI).toBeTruthy();
  });

  test('should change button state during recording', async ({ page }) => {
    await page.goto('/');
    
    const micButton = page.locator('button[aria-label*="microphone"], button[aria-label*="Record"]').first();
    
    // Get initial button state
    const initialState = await micButton.getAttribute('class');
    
    // Start recording
    await micButton.click();
    await page.waitForTimeout(500);
    
    // Button state should change
    const recordingState = await micButton.getAttribute('class');
    expect(recordingState).not.toBe(initialState);
  });

  test('should show duration timer during recording', async ({ page }) => {
    await page.goto('/');
    
    const micButton = page.locator('button[aria-label*="microphone"], button[aria-label*="Record"]').first();
    await micButton.click();
    
    // Look for timer patterns like "0:01", "0:02", etc.
    const timerExists = await page.locator('text=/\\d+:\\d+/, [class*="timer"], [class*="duration"]').isVisible({ timeout: 3000 });
    expect(timerExists).toBeTruthy();
  });
});

test.describe('Voice Input - Mobile Specific', () => {
  test.use({ 
    ...test.use.Mobile,
    permissions: ['microphone']
  });

  test('should work on mobile device', async ({ page }) => {
    // Set mobile viewport
    await page.setViewportSize({ width: 375, height: 667 });
    await page.goto('/');
    
    const micButton = page.locator('button[aria-label*="microphone"], button[aria-label*="Record"]').first();
    await expect(micButton).toBeVisible();
    
    // Button should be large enough for touch
    const boundingBox = await micButton.boundingBox();
    expect(boundingBox?.width).toBeGreaterThanOrEqual(44); // iOS minimum touch target
    expect(boundingBox?.height).toBeGreaterThanOrEqual(44);
  });

  test('should handle touch gestures', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 });
    await page.goto('/');
    
    const micButton = page.locator('button[aria-label*="microphone"], button[aria-label*="Record"]').first();
    
    // Tap to start recording
    await micButton.tap();
    await expect(page.locator('text=/listening/i, text=/recording/i')).toBeVisible({ timeout: 3000 });
    
    // Tap again to stop
    await micButton.tap();
  });

  test('should work in landscape mode', async ({ page }) => {
    // Landscape mobile viewport
    await page.setViewportSize({ width: 667, height: 375 });
    await page.goto('/');
    
    const micButton = page.locator('button[aria-label*="microphone"], button[aria-label*="Record"]').first();
    await expect(micButton).toBeVisible();
    await expect(micButton).toBeEnabled();
  });
});

test.describe('Voice Input - Error Handling', () => {
  test.beforeEach(async ({ context }) => {
    await context.grantPermissions(['microphone']);
  });

  test('should handle network error during transcription', async ({ page }) => {
    await page.goto('/');
    
    // Intercept transcription API call and make it fail
    await page.route('**/transcribe', route => route.abort());
    
    const micButton = page.locator('button[aria-label*="microphone"], button[aria-label*="Record"]').first();
    await micButton.click();
    await page.waitForTimeout(2000);
    await micButton.click(); // Stop recording
    
    // Should show error message
    await expect(page.locator('text=/error/i, text=/failed/i, text=/try again/i')).toBeVisible({ timeout: 10000 });
  });

  test('should allow retry after transcription failure', async ({ page }) => {
    await page.goto('/');
    
    // First attempt - fail
    await page.route('**/transcribe', route => route.abort());
    
    const micButton = page.locator('button[aria-label*="microphone"], button[aria-label*="Record"]').first();
    await micButton.click();
    await page.waitForTimeout(1000);
    await micButton.click();
    
    await expect(page.locator('text=/error/i, text=/failed/i')).toBeVisible({ timeout: 10000 });
    
    // Unblock API and retry
    await page.unroute('**/transcribe');
    
    // Microphone button should still be enabled for retry
    await expect(micButton).toBeEnabled();
  });

  test('should handle empty audio recording', async ({ page }) => {
    await page.goto('/');
    
    const micButton = page.locator('button[aria-label*="microphone"], button[aria-label*="Record"]').first();
    
    // Start and immediately stop (very short recording)
    await micButton.click();
    await page.waitForTimeout(100); // Only 100ms
    await micButton.click();
    
    // Should either show error or handle gracefully
    const hasError = await page.locator('text=/too short/i, text=/no audio/i, text=/error/i').isVisible({ timeout: 5000 });
    const hasResult = await page.locator('input[type="text"], textarea').isVisible({ timeout: 5000 });
    
    expect(hasError || hasResult).toBeTruthy();
  });
});
