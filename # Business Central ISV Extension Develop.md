# Business Central ISV Extension Development Template Guide

**Version:** 1.0  
**Last Updated:** January 12, 2026  
**Based on:** Cue Cards - Configurable KPIs & Cues Project

---

## Purpose of This Document

This guide captures all the learnings, best practices, coding standards, and automated workflows developed across two workspaces for creating a Business Central ISV extension. Use this as a template when starting your next ISV solution to focus purely on **functionality** rather than **technical mechanics**.

---

## Table of Contents

1. [Project Structure & Organization](#1-project-structure--organization)
2. [Initial Setup & Configuration](#2-initial-setup--configuration)
3. [Coding Standards & Conventions](#3-coding-standards--conventions)
4. [Version Management & Build Process](#4-version-management--build-process)
5. [Localization & Internationalization](#5-localization--internationalization)
6. [Testing Strategy](#6-testing-strategy)
7. [Deployment Automation](#7-deployment-automation)
8. [Documentation Standards](#8-documentation-standards)
9. [Pre-Publishing Checklist](#9-pre-publishing-checklist)
10. [What Worked Well](#10-what-worked-well)
11. [What Didn't Work & Limitations](#11-what-didnt-work--limitations)
12. [DevOps & Source Control](#12-devops--source-control)
13. [Quick Start Template](#13-quick-start-template)

---

## 1. Project Structure & Organization

### Standard Directory Structure

```
YourExtension/
├── .vscode/
│   ├── launch.json                 # BC connection settings
│   ├── tasks.json                  # Build & deployment tasks
│   └── rad.json                    # (Optional) Rapid application development settings
├── .alpackages/                    # BC symbols (auto-generated, add to .gitignore)
├── .altestrunner/                  # Test results (auto-generated, add to .gitignore)
├── output/                         # Build artifacts (.app files) - add to .gitignore
│   └── [ExtensionName]_[Version].app
├── src/
│   ├── Codeunits/
│   │   └── [Prefix][Name].Codeunit.al
│   ├── Enums/
│   │   └── [Prefix][Name].Enum.al
│   ├── Pages/
│   │   └── [Prefix][Name].Page.al
│   ├── PageExtensions/            # If extending existing pages
│   │   └── [Prefix][Name].PageExt.al
│   ├── Permissions/
│   │   └── [Prefix][Name].PermissionSet.al
│   └── Tables/
│       └── [Prefix][Name].Table.al
├── Translations/                   # XLIFF translation files
│   ├── [ExtensionName].g.xlf       # Generated base
│   ├── [ExtensionName].de-DE.xlf
│   ├── [ExtensionName].fr-FR.xlf
│   └── ...
├── docs/                           # Detailed documentation
│   ├── DEPLOYMENT.md
│   ├── TESTING.md
│   ├── TRANSLATIONS.md
│   └── ...
├── app.json                        # Extension manifest (CRITICAL)
├── README.md                       # Main user documentation
├── BUILD-GUIDE.md                  # How to build & compile
├── INSTALLATION.md                 # How to install in BC
├── STRUCTURE.md                    # Project structure reference
├── Increment-Version.ps1           # Version increment script
├── Build-WithVersion.ps1           # Build workflow script
└── Deploy-ToProduction.ps1         # Deployment automation script
```

### Object ID Range Management

**CRITICAL:** Reserve a dedicated ID range in `app.json`:

```json
{
  "idRanges": [
    {
      "from": 50000,
      "to": 50099
    }
  ]
}
```

**Allocation Strategy:**
- Tables: 50000-50019
- Pages: 50020-50059
- Codeunits: 50060-50079
- Enums: 50080-50089
- Permission Sets: 50090-50099

**Best Practice:** Document your ID allocation in STRUCTURE.md to avoid conflicts as the extension grows.

---

## 2. Initial Setup & Configuration

### Prerequisites

1. **VS Code** with AL Language extension
2. **Business Central Symbols** (download from BC Admin Center or on-premises server)
3. **PowerShell 7+** (for automation scripts)
4. **Git** for version control

### ⚠️ CRITICAL: New Project Setup Checklist

**Before compiling or deploying a new project, you MUST review and update these files:**

#### 1. Review `.vscode/launch.json`
- **server**: Update to your target BC environment URL
- **serverInstance**: Set correct instance/tenant name
- **authentication**: Verify authentication method (AAD, UserPassword, etc.)
- **startupObjectId**: Set to your main page ID
- **tenant**: Update tenant GUID if using multi-tenant SaaS

#### 2. Review `app.json` - The Extension Manifest
- **id (GUID)**: ⚠️ **MUST be unique for every project!**
  - Generate a new GUID: `[guid]::NewGuid().ToString()` in PowerShell
  - Never reuse GUIDs from template projects
  - Placeholder GUIDs like `12345678-1234-1234-1234-123456789012` will cause deployment conflicts
- **name**: Update to your extension name
- **publisher**: Update to your company/team name
- **version**: Start at `1.0.0.0` for new projects
- **brief/description**: Update for your extension
- **idRanges**: Ensure your ID range doesn't conflict with other extensions
- **platform/application**: Match your target BC environment version

#### 3. Version Numbering Strategy

**Format:** `Major.Minor.Build.Revision` (e.g., `1.0.0.0`)

| Digit | When to Increment |
|-------|-------------------|
| **Revision (rightmost)** | Default for any change - always increment this unless stated otherwise |
| **Build** | Significant bug fixes or internal improvements |
| **Minor** | New features that are backward compatible |
| **Major** | Breaking changes or major releases |

**Rule:** When in doubt, increment the rightmost digit (Revision).

**Examples:**
- `1.0.0.0` → `1.0.0.1` (bug fix, small change)
- `1.0.0.5` → `1.0.1.0` (new feature added)
- `1.2.3.4` → `2.0.0.0` (major rewrite, breaking changes)

### Step 1: Create app.json (The Extension Manifest)

This is the **single most important file**. All extension metadata lives here:

```json
{
    "id": "12345678-1234-1234-1234-123456789012",  // Generate new GUID
    "name": "Your Extension Name",
    "publisher": "Your Company Name",
    "version": "1.0.0.0",
    "brief": "Short description (max 100 chars)",
    "description": "Detailed description of what the extension does",
    "privacyStatement": "https://yourcompany.com/privacy",
    "EULA": "https://yourcompany.com/eula",
    "help": "https://yourcompany.com/help",
    "url": "https://yourcompany.com",
    "dependencies": [],
    "screenshots": [],
    "platform": "26.0.0.0",           // BC platform version
    "application": "26.0.0.0",        // BC application version
    "idRanges": [
        {
            "from": 50000,
            "to": 50099
        }
    ],
    "resourceExposurePolicy": {
        "allowDebugging": true,
        "allowDownloadingSource": false,
        "includeSourceInSymbolFile": false
    },
    "runtime": "12.0",
    "features": [
        "NoImplicitWith",             // Enforce explicit record references
        "TranslationFile"             // Enable multi-language support
    ]
}
```

**Key Decisions:**
- **platform/application versions**: Match your target BC environment (27.0+ recommended for latest features)
- **TranslationFile feature**: ALWAYS enable for multi-language support
- **NoImplicitWith feature**: Enable to enforce modern AL coding standards

### Step 2: Create .vscode/launch.json

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "type": "al",
            "request": "launch",
            "name": "Your BC Dev Server",
            "server": "https://businesscentral.dynamics.com",
            "serverInstance": "your-instance",
            "authentication": "AAD",
            "startupObjectId": 50020,      // Your main setup page
            "startupObjectType": "Page",
            "breakOnError": "All",
            "launchBrowser": true,
            "enableLongRunningSqlStatements": true,
            "enableSqlInformationDebugger": true
        }
    ]
}
```

### Step 3: Download BC Symbols

**Option A: Using VS Code (Recommended)**
1. Open Command Palette (Ctrl+Shift+P)
2. Run: `AL: Download Symbols`
3. Symbols saved to `.alpackages/`

**Option B: From BC Admin Center (SaaS)**
1. Go to BC Admin Center
2. Select environment → Versions tab
3. Download Symbols package
4. Extract to `.alpackages/`

---

## 3. Coding Standards & Conventions

### Naming Conventions

**Object Prefix**
- Choose a 2-4 character prefix (e.g., `CCD`, `XYZ`, `MYCO`)
- Use consistently across ALL objects
- Example: `CCD KPI Definition` (CCD = Cue Cards Definition)

**Object Names**
- Tables: `[Prefix] [Entity Name]` → `CCD KPI Definition`
- Pages: `[Prefix] [Entity Name] [Type]` → `CCD KPI Card`, `CCD KPI List`
- Codeunits: `[Prefix] [Function] [Purpose]` → `CCD KPI Calculation Engine`
- Enums: `[Prefix] [Name]` → `CCD KPI Status`

**Field Names**
- Use full words, not abbreviations (except standard BC abbreviations like "No.")
- Examples: `Last Calculation DateTime`, `Aggregation Type`, `Source Table ID`

**Variable Names**
```al
// Good
var
    KPIDefinition: Record "CCD KPI Definition";
    TempRecordRef: RecordRef;
    IsSuccess: Boolean;

// Avoid
var
    KPI: Record "CCD KPI Definition";    // Too short
    rec: RecordRef;                      // Non-descriptive
    flag: Boolean;                       // Non-descriptive
```

### AL Coding Best Practices

#### 1. Use NoImplicitWith Pattern

```al
// ✅ GOOD: Explicit record reference
procedure CalculateKPI(var KPIDef: Record "CCD KPI Definition"): Decimal
begin
    KPIDef."Last Calculated Value" := 100;
    KPIDef."Last Calculation DateTime" := CurrentDateTime();
    KPIDef.Modify(true);
end;

// ❌ BAD: Implicit with (deprecated)
procedure CalculateKPI(var KPIDef: Record "CCD KPI Definition"): Decimal
begin
    with KPIDef do begin
        "Last Calculated Value" := 100;
        Modify(true);
    end;
end;
```

#### 2. Always Use Labels for User-Facing Strings

```al
// ✅ GOOD: Uses Label (automatically translated)
var
    SuccessMsg: Label 'KPI calculated successfully. Value: %1';
begin
    Message(SuccessMsg, Result);
end;

// ❌ BAD: Hardcoded English string (not translatable)
begin
    Message('KPI calculated successfully. Value: %1', Result);
end;
```

**Why this matters:** Labels are automatically extracted to .xlf translation files. Hardcoded strings are NOT translatable.

#### 3. Always Add XML Documentation Comments

**CRITICAL:** All public objects, procedures, and events MUST have XML documentation comments. This improves code maintainability and enables IntelliSense in VS Code.

**Format:**
```al
/// <summary>
/// Brief description of what the object/procedure does.
/// </summary>
/// <param name="paramName">Description of the parameter.</param>
/// <returns>Description of what the procedure returns (if applicable).</returns>
```

**Examples:**

```al
// ✅ GOOD: Documented Codeunit
/// <summary>
/// Main management codeunit for KPI calculations.
/// Handles calculation scheduling, caching, and result persistence.
/// </summary>
codeunit 50100 "CCD KPI Calculation Engine"
{
    /// <summary>
    /// Calculates a specific KPI and returns the result.
    /// </summary>
    /// <param name="KPIDef">The KPI definition record to calculate.</param>
    /// <returns>The calculated KPI value as a decimal.</returns>
    procedure CalculateKPI(var KPIDef: Record "CCD KPI Definition"): Decimal
    begin
        // Implementation
    end;
}

// ✅ GOOD: Documented Table
/// <summary>
/// Stores configuration for voice assistant AI backends.
/// API keys are stored securely in Isolated Storage, not in table fields.
/// </summary>
table 50200 "Voice Assistant Setup"
{
    // Fields and implementation
}

// ✅ GOOD: Documented Page
/// <summary>
/// Setup page for configuring voice assistant AI backend settings.
/// Allows configuration of OpenAI, Azure OpenAI, or Local LLM connections.
/// </summary>
page 50211 "Voice Assistant Setup"
{
    // Layout and actions
}

// ✅ GOOD: Documented Control Add-in Events
/// <summary>
/// Triggered when voice input is recognized or processed.
/// </summary>
/// <param name="inputText">The recognized text or structured JSON from voice input.</param>
event OnVoiceInput(inputText: Text);
```

**AL-XML-DOC Extension:** Consider installing the AL-XML-DOC extension to enforce documentation standards and auto-generate templates.

#### 4. Configure Spell Checking for Technical Terms

**Problem:** cSpell (Code Spell Checker) will flag technical terms, acronyms, and AL-specific keywords as unknown words.

**Solution:** Add project-specific terms to `.vscode/settings.json`:

```json
{
    "cSpell.words": [
        "EMEA",
        "Hackathon",
        "hackathon",
        "VOICEACTIVATED",
        "Financials",
        "staticwebapp",
        "signalr",
        "functionapp",
        "usercontrol",
        "Belowx"
    ]
}
```

**Common AL Terms to Add:**
- `usercontrol` - Control add-in keyword
- `Belowx`, `xRec` - Standard AL parameter names
- Company/project specific acronyms
- Azure service names (signalr, staticwebapp, functionapp)

**Best Practice:** Add terms as you encounter them rather than ignoring spell checking entirely.

#### 5. Use Enums Instead of Options

```al
// ✅ GOOD: Enum (strongly typed, extensible)
enum 50000 "CCD KPI Status"
{
    Extensible = true;
    
    value(0; Draft) { Caption = 'Draft'; }
    value(1; Active) { Caption = 'Active'; }
    value(2; Inactive) { Caption = 'Inactive'; }
}

// ❌ BAD: Option field (not extensible)
field(10; Status; Option)
{
    OptionMembers = "Draft","Active","Inactive";
    OptionCaption = 'Draft,Active,Inactive';
}
```

#### 6. Implement Comprehensive Error Handling

```al
procedure CalculateKPI(var KPIDef: Record "CCD KPI Definition"): Decimal
var
    SourceTableNotSelectedErr: Label 'Please select a Source Table before calculating.';
    CalculationFailedErr: Label 'KPI calculation failed: %1';
begin
    if KPIDef."Source Table ID" = 0 then
        Error(SourceTableNotSelectedErr);
    
    if not TryCalculate(KPIDef, Result) then
        Error(CalculationFailedErr, GetLastErrorText());
    
    exit(Result);
end;

[TryFunction]
local procedure TryCalculate(KPIDef: Record "CCD KPI Definition"; var Result: Decimal): Boolean
begin
    // Calculation logic that might fail
    Result := PerformCalculation(KPIDef);
end;
```

#### 7. Use Given-When-Then Pattern for Tests

```al
[Test]
procedure TestKPICreation()
var
    KPIDef: Record "CCD KPI Definition";
begin
    // GIVEN: Clean test environment
    KPIDef.DeleteAll();
    
    // WHEN: Creating a new KPI
    CreateTestKPI(KPIDef, 'TEST-KPI-01');
    
    // THEN: Verify properties are set correctly
    Assert.AreEqual('TEST-KPI-01', KPIDef.Code, 'Code should match');
    Assert.AreEqual(KPIDef.Status::Draft, KPIDef.Status, 'Status should be Draft');
end;
```

### Permission Set Standards

Create THREE permission sets for every extension:

**1. Admin Permission Set**
```al
permissionset 50000 "CCD - Admin"
{
    Caption = 'Cue Cards - Admin';
    Assignable = true;
    
    Permissions = 
        tabledata "CCD KPI Definition" = RIMD,        // Read, Insert, Modify, Delete
        tabledata "CCD KPI Assignment" = RIMD,
        table "CCD KPI Definition" = X,               // Execute
        page "CCD KPI List" = X,
        page "CCD KPI Card" = X,
        codeunit "CCD KPI Calculation Engine" = X;
}
```

**2. Designer Permission Set (Create KPIs, not assignments)**
```al
permissionset 50001 "CCD - Designer"
{
    Caption = 'Cue Cards - Designer';
    Assignable = true;
    
    Permissions = 
        tabledata "CCD KPI Definition" = RIMD,
        tabledata "CCD KPI Assignment" = R,           // Read-only for assignments
        // ... rest of objects
}
```

**3. Viewer Permission Set (Read-only)**
```al
permissionset 50002 "CCD - Viewer"
{
    Caption = 'Cue Cards - Viewer';
    Assignable = true;
    
    Permissions = 
        tabledata "CCD KPI Definition" = R,           // Read-only
        tabledata "CCD KPI Assignment" = R,
        table "CCD KPI Definition" = X,
        page "CCD KPI Dashboard" = X,                // View-only pages
        codeunit "CCD KPI Calculation Engine" = X;
}
```

**CRITICAL:** Every new table/page MUST be added to permission sets, or compilation will fail with `PTE0004` error.

---

## 4. Version Management & Build Process

### The Version Management Problem

**Issue:** AL extension build commands (F5, Ctrl+Shift+B, AL: Package) do NOT automatically increment version numbers, even when using task dependencies.

**Root Cause:** The AL extension's native build commands bypass task dependency chains defined in `tasks.json`.

### The Solution: Three PowerShell Scripts

#### Script 1: Increment-Version.ps1

```powershell
# Increment version in app.json before build
$appJsonPath = Join-Path $PSScriptRoot "app.json"
$appJson = Get-Content $appJsonPath -Raw | ConvertFrom-Json

# Parse current version
$version = [version]$appJson.version
$newVersion = [version]::new($version.Major, $version.Minor, $version.Build, $version.Revision + 1)

# Update version
$appJson.version = $newVersion.ToString()

# Save back to file with proper formatting
$appJson | ConvertTo-Json -Depth 10 | Set-Content $appJsonPath -Encoding UTF8

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " VERSION INCREMENTED: $version -> $newVersion" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
```

#### Script 2: Build-WithVersion.ps1

```powershell
# Build script that increments version and compiles
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Building with Version Increment" -ForegroundColor Cyan  
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Increment version
& "$PSScriptRoot\Increment-Version.ps1"

Write-Host ""
Write-Host "Now compile using AL: Package (Ctrl+Shift+B)" -ForegroundColor Yellow
Write-Host "Or use the command palette: AL: Package" -ForegroundColor Yellow
Write-Host ""
```

#### Script 3: Deploy-ToProduction.ps1

```powershell
# Deploy Nexer Cue Cards to BC Production Environment
param(
    [Parameter(Mandatory=$false)]
    [string]$AppFile
)

# Configuration
$TenantId = "your-tenant-id"
$EnvironmentUrl = "https://businesscentral.dynamics.com/$TenantId/Production"
$ExtensionManagementUrl = "$EnvironmentUrl/?page=2500"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Extension - Production Deployment" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Find the latest .app file if not specified
if ([string]::IsNullOrEmpty($AppFile)) {
    Write-Host "Finding latest compiled package..." -ForegroundColor Yellow
    $AppFile = Get-ChildItem -Path $PSScriptRoot -Filter "*.app" | 
               Sort-Object LastWriteTime -Descending | 
               Select-Object -First 1 -ExpandProperty FullName
    
    if ([string]::IsNullOrEmpty($AppFile)) {
        Write-Host "ERROR: No .app file found. Please compile the extension first." -ForegroundColor Red
        exit 1
    }
}

# Verify file exists
if (-not (Test-Path $AppFile)) {
    Write-Host "ERROR: App file not found: $AppFile" -ForegroundColor Red
    exit 1
}

$AppInfo = Get-Item $AppFile
Write-Host "✅ Package Ready for Deployment" -ForegroundColor Green
Write-Host "  File: $($AppInfo.Name)" -ForegroundColor White
Write-Host "  Size: $([math]::Round($AppInfo.Length/1KB,1)) KB" -ForegroundColor White
Write-Host ""

# Open Extension Management page
Start-Process $ExtensionManagementUrl

# Open file explorer to package location
$choice = Read-Host "Open file explorer to package location? (Y/N)"
if ($choice -eq "Y" -or $choice -eq "y") {
    explorer.exe "/select,`"$($AppInfo.FullName)`""
}
```

### Create VS Code Tasks (tasks.json)

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "build",
            "type": "shell",
            "command": "powershell.exe",
            "args": [
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                "& '${workspaceFolder}\\Build-WithVersion.ps1'"
            ],
            "group": {
                "kind": "build",
                "isDefault": true
            },
            "detail": "Increment version and prepare for AL package build"
        },
        {
            "label": "increment-version",
            "type": "shell",
            "command": "powershell.exe",
            "args": [
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                "& '${workspaceFolder}\\Increment-Version.ps1'"
            ],
            "detail": "Increment version number in app.json"
        },
        {
            "label": "Build and Deploy to Production",
            "type": "shell",
            "command": "powershell.exe",
            "args": [
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                "& '${workspaceFolder}\\Deploy-ToProduction.ps1'"
            ],
            "group": "build",
            "dependsOn": ["increment-version"],
            "dependsOrder": "sequence",
            "detail": "Increment version, compile, and open deployment assistant"
        }
    ]
}
```

### Recommended Build Workflow

**For Active Development:**
1. Make code changes
2. Press `Ctrl+Shift+P` → "Tasks: Run Build Task"
3. Select "build"
4. Wait for version increment message
5. Run `AL: Package` from Command Palette (or press F5)

**For Production Releases:**
1. Complete all changes and testing
2. Press `Ctrl+Shift+P` → "Tasks: Run Task"
3. Select "Build and Deploy to Production"
4. Follow deployment prompts

**What Works:**
- ✅ Task-based builds with dependencies work correctly
- ✅ Version increments happen consistently
- ✅ .app files are named with correct version numbers

**What Doesn't Work:**
- ❌ F5 (Debug) does NOT trigger version increment
- ❌ Ctrl+Shift+B does NOT respect task dependencies
- ❌ AL: Package command does NOT run pre-build tasks

---

## 5. Localization & Internationalization

### Architecture Overview

Business Central uses **XLIFF 1.2 format** (.xlf files) for translations. The AL compiler automatically extracts:
- ✅ Table captions
- ✅ Field captions
- ✅ Page captions
- ✅ Enum value captions
- ✅ ToolTip properties
- ✅ **Label constants** (most important!)

**NOT automatically extracted:**
- ❌ Hardcoded strings in `Message()`, `Error()`, `Confirm()` calls
- ❌ Part captions in PageExtensions
- ❌ Dynamic text generated at runtime

### Step 1: Enable Translation Support in app.json

```json
{
    "features": [
        "TranslationFile"
    ]
}
```

### Step 2: Always Use Labels for User-Facing Strings

```al
// ✅ GOOD: Translatable
var
    CalculationSuccessMsg: Label 'KPI calculated successfully. Value: %1';
    SelectTableFirstErr: Label 'Please select a Source Table first.';
    FilterMatchMsg: Label '%1 records match the current filters.';

procedure ShowResults()
begin
    Message(CalculationSuccessMsg, Result);
end;

// ❌ BAD: Not translatable
procedure ShowResults()
begin
    Message('KPI calculated successfully. Value: %1', Result);
end;
```

### Step 3: Generate Base Translation File

When you compile the extension, AL automatically generates:

```
Translations/
└── YourExtensionName.g.xlf    // Base file (DO NOT EDIT)
```

This file contains all extractable strings in XML format:

```xml
<trans-unit id="Table 50000 - Property 2879900210">
    <source>KPI Definition</source>
    <note from="Developer" annotates="general">Caption</note>
    <note from="Xliff Generator">Table - Caption</note>
</trans-unit>
```

### Step 4: Create Language-Specific Files

Copy the `.g.xlf` file for each target language:

```powershell
# PowerShell script to create translation files
$baseFile = ".\Translations\YourExtension.g.xlf"
$languages = @("de-DE", "fr-FR", "es-ES", "ja-JP", "zh-CN")

foreach ($lang in $languages) {
    $targetFile = ".\Translations\YourExtension.$lang.xlf"
    Copy-Item $baseFile $targetFile
    Write-Host "Created $targetFile"
}
```

### Step 5: Add Target Translations

Open each language-specific .xlf file and add `<target>` elements:

```xml
<!-- German translation -->
<trans-unit id="Table 50000 - Property 2879900210">
    <source>KPI Definition</source>
    <target>KPI-Definition</target>
    <note from="Developer" annotates="general">Caption</note>
</trans-unit>

<trans-unit id="Label 12345">
    <source>KPI calculated successfully. Value: %1</source>
    <target>KPI erfolgreich berechnet. Wert: %1</target>
</trans-unit>
```

**CRITICAL:** Preserve parameter placeholders (%1, %2, etc.) in translations!

### Translation Best Practices

✅ **DO:**
- Use Label constants for ALL user-facing strings
- Include context in Label names (`SuccessMsg`, `ErrorMsg`, etc.)
- Test in each target language after translation
- Use standard Business Central terminology where applicable
- Preserve formatting codes (\, \\, etc.)

❌ **DON'T:**
- Hardcode strings in Message/Error calls
- Translate system object names (keep as-is)
- Change parameter order (%1, %2 must stay in same positions)
- Edit the .g.xlf file directly (it gets regenerated)

### Localization Limitations Discovered

**Issue #1: PageExtension Part Captions Not Translatable**

```al
// This caption is NOT in .xlf files and NOT translatable
pageextension 50100 "My Role Center Ext" extends "Business Manager Role Center"
{
    layout
    {
        addlast(RoleCenter)
        {
            part(MyKPIs; "CCD Cue Activities")
            {
                Caption = 'My KPIs';  // ❌ HARDCODED - NOT TRANSLATABLE
            }
        }
    }
}
```

**Workaround Options:**
1. Accept English-only part captions (users see translated KPI tile captions)
2. Use CaptionClass to retrieve caption from a configuration table
3. Create separate PageExtensions for each language (not recommended)

**Issue #2: ToolTips on Dynamic Fields**

If you have dynamic fields (e.g., KPI tiles generated at runtime), ToolTips cannot be easily translated.

**Workaround:** Use generic ToolTips or retrieve from configuration table.

### Language Support Recommendations

**Tier 1 (Essential for European Market):**
- English (US) - en-US
- English (UK) - en-GB
- German - de-DE
- French - fr-FR

**Tier 2 (Broad Market):**
- Spanish - es-ES
- Italian - it-IT
- Dutch - nl-NL
- Danish - da-DK

**Tier 3 (Global Expansion):**
- Japanese - ja-JP
- Chinese (Simplified) - zh-CN
- Swedish - sv-SE
- Norwegian - nb-NO

---

## 6. Testing Strategy

### Test Architecture

Create a dedicated test codeunit with **18+ test scenarios** covering:
- Core functionality
- Edge cases
- Integration points
- Permission enforcement
- Multi-language support (if applicable)

### Test Codeunit Structure

```al
codeunit 50003 "CCD KPI Tests"
{
    Subtype = Test;
    
    // Test 1: Core functionality
    [Test]
    procedure TestKPICreation()
    var
        KPIDef: Record "CCD KPI Definition";
    begin
        // GIVEN: Clean test environment
        Initialize();
        
        // WHEN: Creating a new KPI
        CreateTestKPI(KPIDef, 'TEST-KPI-01');
        
        // THEN: Verify properties
        Assert.AreEqual('TEST-KPI-01', KPIDef.Code, 'Code should match');
        Assert.IsTrue(KPIDef.Status = KPIDef.Status::Draft, 'Status should be Draft');
    end;
    
    // Test 2: Aggregation types
    [Test]
    procedure TestCountAggregation()
    var
        KPIDef: Record "CCD KPI Definition";
        Result: Decimal;
        ExpectedCount: Integer;
    begin
        // GIVEN: Known number of customers
        Initialize();
        ExpectedCount := CreateTestCustomers(5);
        
        // WHEN: Calculating COUNT aggregation
        CreateCountKPI(KPIDef, DATABASE::Customer);
        Result := CalculateKPI(KPIDef);
        
        // THEN: Result matches expected count
        Assert.AreEqual(ExpectedCount, Result, 'Count should match customer records');
    end;
    
    // Test 3: Edge cases
    [Test]
    procedure TestEmptyValueHandling()
    var
        KPIDef: Record "CCD KPI Definition";
        Result: Decimal;
    begin
        // GIVEN: Empty table
        Initialize();
        DeleteAllCustomers();
        
        // WHEN: Calculating on empty table
        CreateCountKPI(KPIDef, DATABASE::Customer);
        Result := CalculateKPI(KPIDef);
        
        // THEN: No error, result is 0
        Assert.AreEqual(0, Result, 'Empty table should return 0');
    end;
    
    // Helper methods
    local procedure Initialize()
    begin
        // Clean up test data
        DeleteAllTestData();
    end;
    
    local procedure CreateTestKPI(var KPIDef: Record "CCD KPI Definition"; Code: Code[20])
    begin
        KPIDef.Init();
        KPIDef.Code := Code;
        KPIDef.Name := 'Test KPI';
        KPIDef.Status := KPIDef.Status::Draft;
        KPIDef.Insert(true);
    end;
}
```

### Test Coverage Requirements

**Minimum 18 Tests:**
1. ✅ TestKPICreation - Basic creation
2. ✅ TestCountAggregation - COUNT logic
3. ✅ TestSumAggregation - SUM logic
4. ✅ TestAverageAggregation - AVERAGE logic
5. ✅ TestMinMaxAggregation - MIN/MAX logic
6. ✅ TestEmptyValueHandling - Null/empty handling
7. ✅ TestFilterApplication - Table filters work
8. ✅ TestUserAssignment - User-specific KPIs
9. ✅ TestProfileAssignment - Profile-based KPIs
10. ✅ TestVisualizationCreation - Cue tiles created
11. ✅ TestCueStyling - Threshold styling logic
12. ✅ TestStatusChangeLogging - Change tracking
13. ✅ TestTemplateUsage - Template-based creation
14. ✅ TestKPISetCreation - Grouping logic
15. ✅ TestMultiCompany - Cross-company queries
16. ✅ TestDimensionFiltering - Dimension filters
17. ✅ TestPermissionEnforcement - Security validation
18. ✅ TestRoleCenterConfiguration - Role center logic

### Running Tests

**Option 1: VS Code AL Test Tool**
1. Press `Ctrl+Shift+P`
2. Select `AL: Run Test`
3. Choose test codeunit
4. View results in Test Results panel

**Option 2: Business Central Test Tool**
1. Search for "Test Tool" in BC
2. Click "Get Test Codeunits"
3. Filter for your test codeunit ID
4. Click "Run" or "Run Selected"

**Option 3: Automated CI/CD**

```yaml
# Azure DevOps example
- task: PowerShell@2
  displayName: 'Run AL Tests'
  inputs:
    targetType: 'inline'
    script: |
      $testResults = Invoke-ALTest `
        -ServerInstance "BC230" `
        -Tenant "default" `
        -CompanyName "CRONUS" `
        -CodeunitId 50003
      if ($testResults.FailedTests -gt 0) {
        throw "Tests failed: $($testResults.FailedTests) failures"
      }
```

### Manual Testing Checklist

Before release, manually test:
- [ ] Fresh installation in clean BC environment
- [ ] Create sample data
- [ ] Create KPI from template
- [ ] Create KPI from scratch
- [ ] Test all aggregation types
- [ ] Assign to user and profile
- [ ] Verify Role Center integration
- [ ] Test permission sets (Admin, Designer, Viewer)
- [ ] Multi-company scenarios
- [ ] Dimension filtering
- [ ] Translations (if multi-language)

---

## 7. Deployment Automation

### Deployment Options

**Option 1: Manual Deployment (AppSource or Partner)**
1. Compile extension to .app file
2. Upload via BC Admin Center
3. Publish and Install
4. Assign permissions

**Option 2: Automated Deployment (PowerShell Script)**

Use the `Deploy-ToProduction.ps1` script created in Section 4.

**Key Benefits:**
- Finds latest .app file automatically
- Opens Extension Management page
- Opens file explorer to package location
- Provides step-by-step instructions
- No credentials stored in source code

**Option 3: CI/CD Pipeline**

```yaml
# GitHub Actions example
name: Build and Deploy BC Extension

on:
  push:
    branches: [ main ]

jobs:
  build-and-deploy:
    runs-on: windows-latest
    
    steps:
    - uses: actions/checkout@v2
    
    - name: Increment Version
      shell: powershell
      run: |
        .\Increment-Version.ps1
    
    - name: Compile Extension
      shell: powershell
      run: |
        $alc = "C:\ProgramData\BcContainerHelper\Extensions\al-*\bin\win32\alc.exe"
        & $alc /project:"." /packagecachepath:".\.alpackages"
    
    - name: Deploy to BC
      shell: powershell
      env:
        BC_TENANT_ID: ${{ secrets.BC_TENANT_ID }}
        BC_ENVIRONMENT: ${{ secrets.BC_ENVIRONMENT }}
      run: |
        # Use BcContainerHelper for automated deployment
        Publish-BcContainerApp `
          -tenantId $env:BC_TENANT_ID `
          -environment $env:BC_ENVIRONMENT `
          -appFile (Get-ChildItem "*.app" | Sort LastWriteTime | Select -Last 1)
```

### Deployment Best Practices

✅ **DO:**
- Test in sandbox environment first
- Increment version before every deployment
- Document breaking changes in release notes
- Backup production environment before major updates
- Verify permissions after deployment

❌ **DON'T:**
- Deploy directly to production without testing
- Store credentials in source code or scripts
- Deploy during business hours (for major changes)
- Skip version increments
- Deploy without change log

---

## 8. Documentation Standards

### Required Documentation Files

Every ISV extension MUST have these files:

#### 1. README.md (Main Documentation)

**Structure:**
```markdown
# Extension Name

**Version:** X.X.X
**Publisher:** Your Company
**BC Compatibility:** BC 27.0+
**Languages:** English (US), English (UK), German, French

## Overview
Brief description of what the extension does

## Key Features
✅ Feature 1
✅ Feature 2
✅ Feature 3

## Quick Start Guide
Step-by-step instructions for first-time users

## Architecture & Object Reference
List of all tables, pages, codeunits with IDs and purposes

## Testing
How to run automated tests

## Support
Contact information and support links
```

#### 2. INSTALLATION.md

- Prerequisites
- Step-by-step installation
- Permission set assignment
- Initial configuration
- Troubleshooting common issues

#### 3. BUILD-GUIDE.md

- How to compile the extension
- Version management workflow
- Build task reference
- Deployment process

#### 4. STRUCTURE.md

- Directory structure
- Object ID allocation
- Naming conventions
- File organization

#### 5. COMPILE.md

- AL compiler usage
- Symbol download instructions
- Command-line compilation
- VS Code integration

#### 6. docs/ Folder (Detailed Documentation)

```
docs/
├── DEPLOYMENT.md         # Deployment workflows
├── TESTING.md           # Test suite documentation
├── TRANSLATIONS.md      # Localization guide
├── ADD_TO_ROLECENTER.md # Role Center integration
└── ...
```

### Documentation Best Practices

✅ **DO:**
- Update version numbers in all docs when releasing
- Include screenshots for UI-heavy features
- Provide code samples for integration scenarios
- Document all breaking changes
- Create troubleshooting sections

❌ **DON'T:**
- Let documentation drift out of sync with code
- Use generic/placeholder text
- Assume users know BC internals
- Skip error message documentation
- Omit upgrade paths

### Inline Code Documentation

```al
/// <summary>
/// Calculates the KPI value based on the configured aggregation type and filters.
/// </summary>
/// <param name="KPIDef">The KPI Definition record to calculate.</param>
/// <returns>The calculated numeric result.</returns>
/// <remarks>
/// This method applies table filters, evaluates the aggregation (Count, Sum, Average, etc.),
/// and updates the Last Calculated Value and Duration fields.
/// </remarks>
procedure CalculateKPI(var KPIDef: Record "CCD KPI Definition"): Decimal
var
    RecRef: RecordRef;
    FieldRef: FieldRef;
    Result: Decimal;
    StartTime: DateTime;
begin
    // Validate source table is selected
    if KPIDef."Source Table ID" = 0 then
        Error(SelectTableFirstErr);
    
    // Open record reference to source table
    RecRef.Open(KPIDef."Source Table ID");
    
    // Apply filters if defined
    if KPIDef."Table Filter" <> '' then
        RecRef.SetView(KPIDef."Table Filter");
    
    // Calculate based on aggregation type
    case KPIDef."Aggregation Type" of
        KPIDef."Aggregation Type"::Count:
            Result := RecRef.Count();
        KPIDef."Aggregation Type"::Sum:
            Result := CalculateSum(RecRef, KPIDef."Aggregation Field ID");
        // ... other cases
    end;
    
    // Update KPI record with results
    KPIDef."Last Calculated Value" := Result;
    KPIDef."Last Calculation DateTime" := CurrentDateTime();
    KPIDef.Modify(true);
    
    exit(Result);
end;
```

---

## 9. Pre-Publishing Checklist

Before publishing to AppSource or deploying to production, validate:

### Code Quality
- [ ] No compilation errors
- [ ] All warnings documented or resolved
- [ ] No hardcoded credentials or API keys
- [ ] All user-facing strings use Labels
- [ ] Permission sets complete for all objects

### Metadata
- [ ] app.json version incremented
- [ ] Publisher name correct
- [ ] Description and brief accurate
- [ ] URLs valid (privacy, EULA, help)
- [ ] ID ranges match objects used
- [ ] Platform/application versions correct

### Testing
- [ ] All automated tests pass (18+ tests)
- [ ] Manual testing complete in clean environment
- [ ] Edge cases tested (empty tables, null values)
- [ ] Permission sets validated (Admin, Designer, Viewer)
- [ ] Multi-company scenarios tested (if applicable)

### Documentation
- [ ] README.md updated with current version
- [ ] INSTALLATION.md accurate
- [ ] All screenshots up-to-date
- [ ] Breaking changes documented
- [ ] Upgrade path provided (if updating)

### Localization
- [ ] All .xlf files updated with translations
- [ ] No hardcoded English strings in code
- [ ] ToolTips present on all fields
- [ ] Tested in at least 2 languages

### Security
- [ ] No sensitive data in logs
- [ ] User permissions enforced
- [ ] GDPR compliance validated

### Performance
- [ ] KPI calculations complete in < 5 seconds
- [ ] Pages load in < 2 seconds
- [ ] No memory leaks in long-running processes

### Package Validation
- [ ] .app file generated successfully
- [ ] File size reasonable (not bloated)
- [ ] Install tested in clean BC environment
- [ ] No PTE errors (PTE0004, PTE0001, etc.)

---

## 10. What Worked Well

### ✅ Automated Version Incrementing

**What:** PowerShell scripts to increment app.json version automatically before each build.

**Why it worked:** Eliminates manual version editing errors, ensures sequential versioning, integrates cleanly with VS Code tasks.

**Keep for next project:** Yes - copy all three scripts (Increment-Version.ps1, Build-WithVersion.ps1, Deploy-ToProduction.ps1)

### ✅ Comprehensive Test Suite (18 Tests)

**What:** Given-When-Then test pattern covering all major features.

**Why it worked:** Caught regression bugs early, validated edge cases, provided confidence before deployment.

**Keep for next project:** Yes - use as template, aim for 15-20 tests minimum

### ✅ Three-Tier Permission Model

**What:** Admin, Designer, Viewer permission sets with clear separation of duties.

**Why it worked:** Matches real-world usage patterns, easy to explain to customers, flexible for different roles.

**Keep for next project:** Yes - standard pattern for all ISV extensions

### ✅ Label Constants for All User Strings

**What:** No hardcoded strings in Message/Error calls - always use Label variables.

**Why it worked:** Made localization straightforward, all strings automatically extracted to .xlf files.

**Keep for next project:** Yes - non-negotiable for multi-language support

### ✅ Modular Sample Data Architecture

**What:** Industry-specific KPI packs (Sales, Finance, Manufacturing, etc.) instead of monolithic sample data.

**Why it worked:** Users only install relevant KPIs, cleaner setup, easier to maintain and extend.

**Keep for next project:** Yes - modular > monolithic for sample/demo data

### ✅ Role Center Configuration Table

**What:** Dedicated table to control which Role Centers show KPIs, with auto-enable logic.

**Why it worked:** Flexible configuration without code changes, easy for admins to manage.

**Keep for next project:** Yes - configuration tables > hardcoded logic

### ✅ Change Log Table

**What:** Audit trail of all KPI modifications (status changes, assignments, etc.).

**Why it worked:** Valuable for troubleshooting, compliance, understanding user behavior.

**Keep for next project:** Yes - consider for any configurable entity

### ✅ Documentation-First Approach

**What:** Created comprehensive documentation (README, BUILD-GUIDE, INSTALLATION, etc.) throughout development.

**Why it worked:** Documentation never fell behind, easy onboarding for new users, reduced support questions.

**Keep for next project:** Yes - write docs as you build, not after

---

## 11. What Didn't Work & Limitations

### ❌ AL Build Commands Ignore Task Dependencies

**Issue:** F5, Ctrl+Shift+B, and "AL: Package" do NOT trigger task dependencies defined in tasks.json.

**Attempted Fix:** Used `dependsOn` and `dependsOrder` in tasks.json - doesn't work with AL extension commands.

**Workaround:** Users must manually run "Tasks: Run Build Task" instead of F5.

**Impact:** Medium - workflow slightly more complex, but manageable with documentation.

**For next project:** Accept limitation, document workflow clearly, create VS Code task aliases.

### ❌ PageExtension Part Captions Not Translatable

**Issue:** When adding a part to a Role Center via PageExtension, the Caption property is NOT extracted to .xlf files.

```al
part(MyKPIs; "CCD Cue Activities")
{
    Caption = 'My KPIs';  // ❌ NOT IN .xlf, NOT TRANSLATABLE
}
```

**Attempted Fix:** Tried CaptionML (deprecated), looked for CaptionClass pattern - no solution found.

**Workaround:** Accept English-only part captions, or create separate PageExtensions per language (not practical).

**Impact:** Low - users primarily see the KPI tile captions (which ARE translatable), not the part caption.

**For next project:** Accept limitation if using PageExtensions, or avoid PageExtensions entirely (use Page Customization instead).

### ❌ Dynamic ToolTips on Runtime-Generated Fields

**Issue:** When generating fields dynamically (e.g., KPI tiles in a CardPart page), ToolTips cannot be easily translated.

**Attempted Fix:** Tried retrieving from configuration table, using CaptionClass - complex and fragile.

**Workaround:** Use generic ToolTips ("Click to view details") or skip ToolTips on dynamic fields.

**Impact:** Low - users can figure out what tiles do from captions.

**For next project:** Avoid dynamic field generation if ToolTips are critical, or accept generic ToolTips.

### ❌ .alpackages Folder Size

**Issue:** BC symbol files are LARGE (100+ MB), bloats repository if committed to Git.

**Attempted Fix:** Added to .gitignore, but users must download symbols manually.

**Workaround:** Document symbol download process clearly in BUILD-GUIDE.md.

**Impact:** Low - one-time setup per developer.

**For next project:** Always add `.alpackages/` to .gitignore, document download process.

### ✅ SOLVED: Build Artifacts Organization

**Issue:** Every build creates a new .app file with incremented version, which can clutter the workspace.

**Solution:** Configure AL compiler to output .app files to dedicated `output/` folder.

**Implementation:**
1. Create `output/` folder in project root
2. AL compiler automatically places all .app files in this folder
3. Add `output/` to .gitignore to keep it out of source control
4. Periodically clean old versions, keep last 3-5 for rollback purposes

**Best Practice:** All build artifacts (.app files) MUST be stored in `output/` folder, never in the root directory. This keeps the workspace clean and makes it clear which files are build outputs versus source files.

**Impact:** Eliminates workspace clutter, improves project organization.

### ❌ Test Data Cleanup Between Tests

**Issue:** Tests can leave residual data if not properly cleaned up, causing intermittent failures.

**Attempted Fix:** Added `Initialize()` method to delete all test data before each test.

**Workaround:** Use table-specific DeleteAll() in Initialize(), ensure unique test codes.

**Impact:** Medium - can cause flaky tests if not handled properly.

**For next project:** Always use test initialization pattern, use unique IDs (GUIDs or timestamps) for test records.

### ❌ FlowField Performance in KPIs

**Issue:** Using FlowFields as aggregation fields can be slow, as BC calculates them on-demand.

**Attempted Fix:** Added warning in UI when FlowField selected.

**Workaround:** Recommend users avoid FlowFields or use alternative approaches (direct table queries).

**Impact:** Medium - can cause slow KPI calculations.

**For next project:** Document performance implications, provide alternatives, consider caching for FlowFields.

---

## 12. DevOps & Source Control

### Git Repository Structure

```
.gitignore
.vscode/
src/
Translations/
docs/
app.json
README.md
*.ps1 scripts
```

### .gitignore Configuration

**CRITICAL:** Always exclude these folders:

```gitignore
# AL Package Cache (BC symbols - large files)
.alpackages/

# Test Results
.altestrunner/

# Compiled packages (keep only in releases)
*.app

# VS Code settings (optional - depends on team preference)
.vscode/settings.json

# Snapshots (debugging)
.snapshots/

# Temporary files
temp_*.csv
temp_*.json
```

### Branching Strategy

**Recommended: GitHub Flow (Simple)**

```
main (production-ready)
  ├── feature/add-kpi-templates
  ├── feature/role-center-config
  └── bugfix/calculation-error
```

**Workflow:**
1. Create feature branch from `main`
2. Develop and test locally
3. Create Pull Request to `main`
4. Code review + automated tests
5. Merge to `main`
6. Tag release: `v1.0.0`

**For larger teams: GitFlow**

```
main (production releases)
develop (integration branch)
  ├── feature/xyz
  ├── release/v1.1.0
  └── hotfix/critical-bug
```

### CI/CD Pipeline Recommendations

**Option 1: Azure DevOps**

```yaml
# azure-pipelines.yml
trigger:
  branches:
    include:
      - main

pool:
  vmImage: 'windows-latest'

steps:
- task: PowerShell@2
  displayName: 'Increment Version'
  inputs:
    filePath: 'Increment-Version.ps1'

- task: PowerShell@2
  displayName: 'Compile AL Extension'
  inputs:
    targetType: 'inline'
    script: |
      $alc = "path\to\alc.exe"
      & $alc /project:"$(Build.SourcesDirectory)" /packagecachepath:".\.alpackages"

- task: PowerShell@2
  displayName: 'Run Tests'
  inputs:
    targetType: 'inline'
    script: |
      # Run AL tests
      Invoke-ALTest -CodeunitId 50003

- task: PublishBuildArtifacts@1
  displayName: 'Publish .app File'
  inputs:
    PathtoPublish: '$(Build.SourcesDirectory)\*.app'
    ArtifactName: 'BC_Extension'
```

**Option 2: GitHub Actions**

```yaml
# .github/workflows/build-and-test.yml
name: Build and Test

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: windows-latest
    
    steps:
    - uses: actions/checkout@v2
    
    - name: Increment Version
      shell: powershell
      run: .\Increment-Version.ps1
    
    - name: Compile Extension
      shell: powershell
      run: |
        # Compile AL code
        # (requires AL compiler setup)
    
    - name: Run Tests
      shell: powershell
      run: |
        # Run automated tests
    
    - name: Upload Artifact
      uses: actions/upload-artifact@v2
      with:
        name: extension-package
        path: '*.app'
```

### Release Management

**Semantic Versioning:** MAJOR.MINOR.BUILD.REVISION

- **MAJOR**: Breaking changes, major feature overhaul
- **MINOR**: New features, backward-compatible
- **BUILD**: Bug fixes, small improvements
- **REVISION**: Auto-incremented on every build

**Example:**
- 1.0.0.0 - Initial release
- 1.0.0.5 - 5 builds later (bug fixes)
- 1.1.0.0 - New feature added (minor)
- 2.0.0.0 - Breaking changes (major)

**Git Tags:**

```bash
# Tag a release
git tag -a v1.0.0 -m "Release version 1.0.0 - Initial public release"
git push origin v1.0.0

# List tags
git tag -l

# Delete tag (if needed)
git tag -d v1.0.0
git push origin --delete v1.0.0
```

---

## 13. Quick Start Template

Use this checklist when starting a new BC ISV extension project:

### Phase 1: Project Setup (Day 1)

- [ ] Create project folder
- [ ] Initialize Git repository
- [ ] Create app.json with:
  - [ ] Unique GUID (generate new)
  - [ ] Extension name and publisher
  - [ ] Version 1.0.0.0
  - [ ] Target BC version (platform/application)
  - [ ] ID range (from, to)
  - [ ] Features: NoImplicitWith, TranslationFile
- [ ] Create .gitignore (exclude .alpackages, .app files)
- [ ] Create folder structure (src/, docs/, Translations/)
- [ ] Download BC symbols to .alpackages/
- [ ] Create .vscode/launch.json (BC connection)
- [ ] Create .vscode/tasks.json (build tasks)

### Phase 2: Core Scripts (Day 1)

- [ ] Create Increment-Version.ps1
- [ ] Create Build-WithVersion.ps1
- [ ] Create Deploy-ToProduction.ps1
- [ ] Test build workflow

### Phase 3: Initial Code (Days 2-3)

- [ ] Create primary table(s) in src/Tables/
- [ ] Create enums in src/Enums/
- [ ] Create list page in src/Pages/
- [ ] Create card page in src/Pages/
- [ ] Create codeunit(s) in src/Codeunits/
- [ ] Create 3 permission sets:
  - [ ] Admin (full RIMD)
  - [ ] Designer (limited)
  - [ ] Viewer (read-only)
- [ ] First compile test

### Phase 4: Testing Foundation (Day 4)

- [ ] Create test codeunit
- [ ] Write first 3 tests:
  - [ ] TestRecordCreation
  - [ ] TestCoreLogic
  - [ ] TestEmptyValueHandling
- [ ] Verify tests pass

### Phase 5: Documentation (Day 5)

- [ ] Create README.md (main documentation)
- [ ] Create INSTALLATION.md
- [ ] Create BUILD-GUIDE.md
- [ ] Create STRUCTURE.md
- [ ] Create docs/ folder with:
  - [ ] TESTING.md
  - [ ] DEPLOYMENT.md

### Phase 6: Localization Setup (Day 6)

- [ ] Verify TranslationFile feature enabled in app.json
- [ ] Ensure all user-facing strings use Labels
- [ ] Compile to generate .g.xlf file
- [ ] Create language-specific .xlf files (de-DE, fr-FR, etc.)
- [ ] Add placeholder translations (or use AI for draft)

### Phase 7: Build Complete Feature Set (Weeks 2-4)

- [ ] Implement remaining functionality
- [ ] Add tests for each feature (target 15-20 total tests)
- [ ] Update documentation as you build
- [ ] Test in sandbox BC environment

### Phase 8: Pre-Release Validation (Week 5)

- [ ] Run full pre-publishing checklist (Section 9)
- [ ] Manual end-to-end testing
- [ ] Translation review (professional translators)
- [ ] Performance testing
- [ ] Security review

### Phase 9: Initial Release (Week 6)

- [ ] Increment version to 1.0.0.0
- [ ] Tag release in Git: v1.0.0
- [ ] Compile final .app file
- [ ] Deploy to production or submit to AppSource
- [ ] Monitor for issues

---

## Conclusion

This template guide captures the collective learnings from developing the Nexer Cue Cards BC extension. By following these patterns, standards, and workflows, you can focus on **building functionality** rather than reinventing the technical infrastructure.

### Key Takeaways

1. **Version Management:** Automate it with PowerShell scripts + VS Code tasks
2. **Localization:** Always use Labels, never hardcode strings
3. **Testing:** Aim for 15-20 automated tests, use Given-When-Then pattern
4. **Permissions:** Three-tier model (Admin, Designer, Viewer)
5. **Documentation:** Write as you build, not after
6. **Structure:** Consistent naming, clear folder organization
7. **Build Process:** Accept AL build quirks, document workflows clearly

### When Starting Your Next ISV Extension

1. Copy this guide to your new project folder
2. Follow Phase 1-9 checklist in Section 13
3. Copy the three PowerShell scripts (Increment, Build, Deploy)
4. Copy tasks.json configuration
5. Copy .gitignore
6. Start building!

### Support & Updates

This guide is based on real-world experience. As BC evolves and new patterns emerge, update this document to reflect new learnings.

**Last Updated:** January 12, 2026  
**BC Version:** 26.0 / 27.0  
**AL Language:** Runtime 12.0

---

**Good luck with your next ISV solution!** 🚀
