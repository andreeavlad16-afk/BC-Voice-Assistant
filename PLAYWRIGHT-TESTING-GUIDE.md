# Playwright UI Testing Guide for BC Voice Assistant

## Overview

This guide covers end-to-end UI testing using Playwright for the BC Voice Assistant project, including the PWA, BC web client interactions, and Azure Function endpoints.

## Why Playwright for BC Development?

✅ **Cross-browser testing**: Chrome, Firefox, Safari, Edge
✅ **Mobile emulation**: Test iOS/Android PWA experience
✅ **Visual regression**: Screenshot comparisons
✅ **Network mocking**: Test offline scenarios
✅ **Authentication handling**: BC OAuth flows
✅ **Trace viewer**: Debug test failures with timeline
✅ **CI/CD integration**: Azure DevOps, GitHub Actions

## Installation

### Prerequisites
- Node.js 18+ installed
- VS Code with Playwright extension

### Setup
```bash
# Navigate to project root
cd VOICEACTIVATED-BC

# Install Playwright
npm init playwright@latest

# Install browsers
npx playwright install
```

### VS Code Extension
1. Install: [Playwright Test for VSCode](https://marketplace.visualstudio.com/items?itemName=ms-playwright.playwright)
2. Open Testing panel (flask icon in sidebar)
3. Click "Record new test" to generate tests interactively

## Project Structure

```
VOICEACTIVATED-BC/
├── tests/                      # Playwright tests
│   ├── pwa/                   # PWA-specific tests
│   │   ├── auth.spec.ts      # Authentication flows
│   │   ├── voice.spec.ts     # Voice input tests
│   │   ├── offline.spec.ts   # Offline mode tests
│   │   └── config.spec.ts    # Configuration tests
│   ├── bc-web/               # BC Web Client tests
│   │   ├── pages.spec.ts     # Page interactions
│   │   ├── queries.spec.ts   # Voice query processing
│   │   └── setup.spec.ts     # Setup page tests
│   ├── api/                  # API endpoint tests
│   │   ├── transcribe.spec.ts
│   │   ├── query.spec.ts
│   │   └── negotiate.spec.ts
│   └── fixtures/             # Test fixtures & helpers
│       ├── auth-setup.ts     # BC authentication helper
│       ├── test-data.ts      # Sample data
│       └── mock-audio.ts     # Mock audio files
├── playwright.config.ts      # Playwright configuration
└── .env.test                 # Test environment variables
```

## Configuration

### playwright.config.ts
```typescript
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [
    ['html'],
    ['junit', { outputFile: 'test-results/junit.xml' }],
    ['json', { outputFile: 'test-results/results.json' }]
  ],
  
  use: {
    baseURL: process.env.PWA_URL || 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },

  projects: [
    // Desktop browsers
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
    },

    // Mobile devices
    {
      name: 'Mobile Chrome',
      use: { ...devices['Pixel 5'] },
    },
    {
      name: 'Mobile Safari',
      use: { ...devices['iPhone 13'] },
    },

    // Tablet
    {
      name: 'iPad',
      use: { ...devices['iPad Pro'] },
    },
  ],

  webServer: {
    command: 'cd pwa && npx serve . -l 3000',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
  },
});
```

### .env.test
```env
# PWA Configuration
PWA_URL=http://localhost:3000
BC_ENVIRONMENT_URL=https://businesscentral.dynamics.com/tenant-id/env-name
AZURE_CLIENT_ID=your-client-id
AZURE_TENANT_ID=your-tenant-id

# Azure Function Endpoints
TRANSCRIBE_URL=https://func-bcvoice-prod.azurewebsites.net/api/transcribe
QUERY_URL=https://func-bcvoice-prod.azurewebsites.net/api/query
NEGOTIATE_URL=https://func-bcvoice-prod.azurewebsites.net/api/negotiate

# Test Credentials (use test account!)
TEST_USERNAME=testuser@yourdomain.com
TEST_PASSWORD=your-test-password

# Azure OpenAI (for API tests)
AZURE_OPENAI_ENDPOINT=https://your-openai.openai.azure.com/
AZURE_OPENAI_KEY=your-key
```

## Test Categories

### 1. PWA Tests

#### Authentication Flow
```typescript
// tests/pwa/auth.spec.ts
import { test, expect } from '@playwright/test';

test.describe('PWA Authentication', () => {
  test('should show login screen on first launch', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('text=Sign in to BC')).toBeVisible();
  });

  test('should authenticate with Azure AD', async ({ page, context }) => {
    await page.goto('/');
    await page.click('button:has-text("Sign In")');
    
    // Wait for Azure AD redirect
    await page.waitForURL(/login.microsoftonline.com/);
    
    // Fill credentials
    await page.fill('input[type="email"]', process.env.TEST_USERNAME);
    await page.click('input[type="submit"]');
    await page.fill('input[type="password"]', process.env.TEST_PASSWORD);
    await page.click('input[type="submit"]');
    
    // Should redirect back to PWA
    await expect(page).toHaveURL('/');
    await expect(page.locator('text=Voice Assistant')).toBeVisible();
  });

  test('should persist authentication after page reload', async ({ page, context }) => {
    // Assume already logged in from previous test
    await page.goto('/');
    await expect(page.locator('text=Voice Assistant')).toBeVisible();
    
    await page.reload();
    await expect(page.locator('text=Voice Assistant')).toBeVisible();
  });
});
```

#### Voice Input Tests
```typescript
// tests/pwa/voice.spec.ts
import { test, expect } from '@playwright/test';
import { grantPermissions } from '../fixtures/permissions';

test.describe('Voice Input', () => {
  test.beforeEach(async ({ context }) => {
    // Grant microphone permissions
    await context.grantPermissions(['microphone']);
  });

  test('should show microphone button', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('button[aria-label="Record voice"]')).toBeVisible();
  });

  test('should start recording on button press', async ({ page }) => {
    await page.goto('/');
    const micButton = page.locator('button[aria-label="Record voice"]');
    
    await micButton.click();
    await expect(page.locator('text=Listening...')).toBeVisible();
    
    // Simulate recording for 2 seconds
    await page.waitForTimeout(2000);
    await micButton.click(); // Stop recording
    
    await expect(page.locator('text=Processing...')).toBeVisible();
  });

  test('should handle denied microphone permission', async ({ page, context }) => {
    // Create new context without microphone permission
    await page.goto('/');
    const micButton = page.locator('button[aria-label="Record voice"]');
    
    await micButton.click();
    await expect(page.locator('text=Microphone access denied')).toBeVisible();
  });
});
```

#### Offline Mode Tests
```typescript
// tests/pwa/offline.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Offline Mode', () => {
  test('should show offline indicator when network is down', async ({ page, context }) => {
    await page.goto('/');
    
    // Go offline
    await context.setOffline(true);
    await page.reload();
    
    await expect(page.locator('text=You are offline')).toBeVisible();
  });

  test('should cache queries for offline use', async ({ page, context }) => {
    await page.goto('/');
    
    // Make a query while online
    await page.fill('input[placeholder="Ask a question"]', 'show customers');
    await page.press('input[placeholder="Ask a question"]', 'Enter');
    await expect(page.locator('text=Customers', { timeout: 10000 })).toBeVisible();
    
    // Go offline
    await context.setOffline(true);
    
    // Try same query
    await page.fill('input[placeholder="Ask a question"]', 'show customers');
    await page.press('input[placeholder="Ask a question"]', 'Enter');
    await expect(page.locator('text=Customers')).toBeVisible();
  });

  test('should sync queries when coming back online', async ({ page, context }) => {
    await page.goto('/');
    await context.setOffline(true);
    
    // Make query offline
    await page.fill('input[placeholder="Ask a question"]', 'show vendors');
    await page.press('input[placeholder="Ask a question"]', 'Enter');
    await expect(page.locator('text=Queued for sync')).toBeVisible();
    
    // Go back online
    await context.setOffline(false);
    await page.waitForTimeout(2000); // Wait for sync
    
    await expect(page.locator('text=Synced')).toBeVisible();
  });
});
```

### 2. BC Web Client Tests

```typescript
// tests/bc-web/setup.spec.ts
import { test, expect } from '@playwright/test';
import { loginToBC } from '../fixtures/auth-setup';

test.describe('BC Voice Assistant Setup', () => {
  test.beforeEach(async ({ page }) => {
    await loginToBC(page);
  });

  test('should open Voice Assistant Setup page', async ({ page }) => {
    await page.goto(process.env.BC_ENVIRONMENT_URL);
    
    // Search for Voice Assistant Setup
    await page.click('[aria-label="Search"]');
    await page.fill('input[role="searchbox"]', 'Voice Assistant Setup');
    await page.click('text=Voice Assistant Setup');
    
    await expect(page.locator('text=AI Backend Type')).toBeVisible();
  });

  test('should configure Azure OpenAI settings', async ({ page }) => {
    await page.goto(`${process.env.BC_ENVIRONMENT_URL}?page=50611`);
    
    // Select Azure OpenAI
    await page.click('select[name="AI Backend Type"]');
    await page.selectOption('select[name="AI Backend Type"]', 'Azure OpenAI');
    
    // Fill endpoint
    await page.fill('input[name="Azure OpenAI Endpoint"]', 
                     process.env.AZURE_OPENAI_ENDPOINT);
    
    await page.click('button:has-text("Test Connection")');
    await expect(page.locator('text=Connection successful')).toBeVisible();
  });
});

// tests/bc-web/queries.spec.ts
test.describe('Voice Query Processing', () => {
  test('should process text query', async ({ page }) => {
    await loginToBC(page);
    await page.goto(`${process.env.BC_ENVIRONMENT_URL}?page=50608`);
    
    await page.fill('textarea[name="queryInput"]', 'show me the top 10 customers');
    await page.click('button:has-text("Ask")');
    
    // Wait for response
    await expect(page.locator('text=Here are the top 10 customers')).toBeVisible({ timeout: 15000 });
  });

  test('should handle query execution', async ({ page }) => {
    await loginToBC(page);
    await page.goto(`${process.env.BC_ENVIRONMENT_URL}?page=50608`);
    
    await page.fill('textarea[name="queryInput"]', 'open customer list');
    await page.click('button:has-text("Ask")');
    
    // Should open customer list page
    await expect(page).toHaveURL(/.*page=22.*/);
  });
});
```

### 3. API Endpoint Tests

```typescript
// tests/api/transcribe.spec.ts
import { test, expect } from '@playwright/test';
import * as fs from 'fs';
import FormData from 'form-data';

test.describe('Transcription API', () => {
  test('should accept audio and return transcript', async ({ request }) => {
    const audioBase64 = fs.readFileSync('./tests/fixtures/sample-audio.m4a').toString('base64');
    
    const response = await request.post(process.env.TRANSCRIBE_URL, {
      data: {
        audioData: audioBase64,
        mimeType: 'audio/m4a'
      }
    });
    
    expect(response.ok()).toBeTruthy();
    const body = await response.json();
    expect(body).toHaveProperty('text');
    expect(body.text).toBeTruthy();
  });

  test('should handle invalid audio format', async ({ request }) => {
    const response = await request.post(process.env.TRANSCRIBE_URL, {
      data: {
        audioData: 'invalid-base64',
        mimeType: 'audio/invalid'
      }
    });
    
    expect(response.status()).toBe(400);
  });

  test('should return error for missing audio data', async ({ request }) => {
    const response = await request.post(process.env.TRANSCRIBE_URL, {
      data: {
        mimeType: 'audio/m4a'
      }
    });
    
    expect(response.status()).toBe(400);
    const body = await response.json();
    expect(body.error).toContain('audio');
  });
});
```

## Test Fixtures & Helpers

### Authentication Helper
```typescript
// tests/fixtures/auth-setup.ts
import { Page } from '@playwright/test';

export async function loginToBC(page: Page) {
  await page.goto(process.env.BC_ENVIRONMENT_URL);
  
  // Check if already logged in
  if (await page.locator('[aria-label="User menu"]').isVisible()) {
    return;
  }
  
  // Handle Azure AD login
  await page.fill('input[type="email"]', process.env.TEST_USERNAME);
  await page.click('input[type="submit"]');
  await page.fill('input[type="password"]', process.env.TEST_PASSWORD);
  await page.click('input[type="submit"]');
  
  // Wait for BC to load
  await page.waitForSelector('[aria-label="Navigation menu"]');
}
```

### Mock Audio Generator
```typescript
// tests/fixtures/mock-audio.ts
export function generateMockAudioBase64(durationMs: number = 3000): string {
  // Generate minimal valid WAV file
  const sampleRate = 16000;
  const numChannels = 1;
  const bitsPerSample = 16;
  const numSamples = Math.floor((sampleRate * durationMs) / 1000);
  
  // WAV header + silent audio data
  const buffer = Buffer.alloc(44 + numSamples * 2);
  
  // Write WAV header
  buffer.write('RIFF', 0);
  buffer.writeUInt32LE(36 + numSamples * 2, 4);
  buffer.write('WAVE', 8);
  buffer.write('fmt ', 12);
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);
  buffer.writeUInt16LE(numChannels, 22);
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(sampleRate * numChannels * bitsPerSample / 8, 28);
  buffer.writeUInt16LE(numChannels * bitsPerSample / 8, 32);
  buffer.writeUInt16LE(bitsPerSample, 34);
  buffer.write('data', 36);
  buffer.writeUInt32LE(numSamples * 2, 40);
  
  return buffer.toString('base64');
}
```

## Running Tests

### Command Line
```bash
# Run all tests
npx playwright test

# Run specific test file
npx playwright test tests/pwa/auth.spec.ts

# Run tests in headed mode (see browser)
npx playwright test --headed

# Run tests in specific browser
npx playwright test --project=chromium
npx playwright test --project="Mobile Safari"

# Debug mode (step through tests)
npx playwright test --debug

# Generate test code by recording
npx playwright codegen http://localhost:3000
```

### VS Code Integration
1. Open Testing panel (flask icon)
2. Click ▶️ next to test name to run
3. Click 🐞 to debug with breakpoints
4. View trace files in Test Results

### CI/CD Integration

#### GitHub Actions
```yaml
# .github/workflows/playwright.yml
name: Playwright Tests
on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: 18
      - name: Install dependencies
        run: npm ci
      - name: Install Playwright Browsers
        run: npx playwright install --with-deps
      - name: Run Playwright tests
        run: npx playwright test
        env:
          PWA_URL: ${{ secrets.PWA_URL }}
          BC_ENVIRONMENT_URL: ${{ secrets.BC_ENVIRONMENT_URL }}
          TEST_USERNAME: ${{ secrets.TEST_USERNAME }}
          TEST_PASSWORD: ${{ secrets.TEST_PASSWORD }}
      - uses: actions/upload-artifact@v3
        if: always()
        with:
          name: playwright-report
          path: playwright-report/
          retention-days: 30
```

#### Azure DevOps
```yaml
# azure-pipelines.yml
trigger:
  - main
  - develop

pool:
  vmImage: 'ubuntu-latest'

steps:
- task: NodeTool@0
  inputs:
    versionSpec: '18.x'
  displayName: 'Install Node.js'

- script: npm ci
  displayName: 'Install dependencies'

- script: npx playwright install --with-deps
  displayName: 'Install Playwright browsers'

- script: npx playwright test
  displayName: 'Run Playwright tests'
  env:
    PWA_URL: $(PWA_URL)
    BC_ENVIRONMENT_URL: $(BC_ENVIRONMENT_URL)
    TEST_USERNAME: $(TEST_USERNAME)
    TEST_PASSWORD: $(TEST_PASSWORD)

- task: PublishTestResults@2
  displayName: 'Publish test results'
  inputs:
    testResultsFormat: 'JUnit'
    testResultsFiles: 'test-results/junit.xml'
  condition: always()

- task: PublishPipelineArtifact@1
  displayName: 'Publish Playwright report'
  inputs:
    targetPath: playwright-report
    artifact: playwright-report
  condition: always()
```

## Best Practices

### 1. Test Organization
- Group related tests with `test.describe()`
- Use descriptive test names: `should [action] when [condition]`
- One assertion per test when possible
- Use `beforeEach` for common setup

### 2. Selectors
Prefer in order:
1. `page.getByRole('button', { name: 'Submit' })` - Accessible selectors
2. `page.getByTestId('submit-btn')` - Test IDs
3. `page.getByText('Submit')` - Text content
4. `page.locator('#submit-btn')` - CSS/ID selectors (last resort)

### 3. Waits
- Use `expect()` instead of `waitForTimeout()`
- Set appropriate timeouts for async operations
- Use `waitForLoadState('networkidle')` for heavy pages

### 4. Data Management
- Create test data in `beforeEach`
- Clean up in `afterEach`
- Use fixtures for reusable test data
- Never use production data

### 5. Screenshots & Videos
- Enable for failures only in CI
- Use visual regression for UI changes
- Store in artifacts for debugging

### 6. Mobile Testing
- Test both portrait and landscape
- Test touch gestures
- Test offline mode
- Verify PWA installation flow

## Debugging Tips

### View Test Traces
```bash
npx playwright show-trace trace.zip
```

### Generate HTML Report
```bash
npx playwright show-report
```

### Debug Specific Test
```bash
npx playwright test auth.spec.ts --debug
```

### Inspect Element
```typescript
await page.pause(); // Pauses execution, opens inspector
```

## Coverage Targets

- **PWA Critical Flows**: 100% (auth, voice, config)
- **BC Pages**: 80% (main pages and interactions)
- **API Endpoints**: 100% (all endpoints and error cases)
- **Mobile Devices**: iOS Safari, Android Chrome
- **Browsers**: Chrome, Firefox, Safari

## Resources

- [Playwright Documentation](https://playwright.dev/)
- [VS Code Extension](https://marketplace.visualstudio.com/items?itemName=ms-playwright.playwright)
- [Best Practices](https://playwright.dev/docs/best-practices)
- [Trace Viewer](https://playwright.dev/docs/trace-viewer)
- [Test Generator](https://playwright.dev/docs/codegen)
