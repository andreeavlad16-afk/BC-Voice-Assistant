# Private Repository Verification Checklist

## Before Making Repository Public

Use this checklist to verify your private repository is safe to make public.

---

## 🔍 Step 1: Clone Fresh Copy

```bash
# Clone to a temporary location (not your work directory)
cd ~/temp
git clone https://github.com/andreeavlad16-afk/BC-Voice-Assistant.git
cd BC-Voice-Assistant
```

---

## 🔐 Step 2: Search for Leaked Credentials

Run these searches - **ALL should return no results:**

```bash
# Azure OpenAI Keys
echo "Checking Azure OpenAI keys..."
grep -r "DM0UFaALfoUW4oJUskgFOWc" . 2>/dev/null
grep -r "5a8133e4939d48bc990d062ebbf0c4f0" . 2>/dev/null

# Storage Keys
echo "Checking Storage keys..."
grep -r "jenYkEXwrhCj3lmeoQxV3bFuWJWR" . 2>/dev/null

# SignalR Keys
echo "Checking SignalR keys..."
grep -r "a6Xct7Gy4xPF8HAHUPcGZNftS0jQVuTC2dCI6GeUncdr4oUUmCL4JQQJ99CAAC5RqLJXJ3w3AAAAASRSUjOS" . 2>/dev/null

# Tenant/Subscription IDs
echo "Checking tenant info..."
grep -r "M365x77295693" . 2>/dev/null
grep -r "0fffce29-cf48-4967-9bba-8a7b0172b531" . 2>/dev/null

# Resource Names
echo "Checking resource names..."
grep -r "stbcvoice9149" . 2>/dev/null
grep -r "openai-bcvoice-2025" . 2>/dev/null
grep -r "func-bcvoice-prod" . 2>/dev/null
grep -r "signalr-bcvoice-1656" . 2>/dev/null
```

**Expected Result:** All searches return "No matches found" or empty results

---

## ✅ Step 3: Verify Required Files

```bash
# Check .app file is present
echo "Checking .app file..."
ls -lh "Nexer Enterprise Applications UK_NXR Voice Assistant_2.1.4.3.app"

# Should show: File exists, approximately 100-500 KB

# Check README
echo "Checking README..."
head -30 README.md

# Should show: Hackathon story, AI-generated badge, etc.

# Check configuration templates have placeholders only
echo "Checking config templates..."
cat azure-relay/local.settings.json | grep -i "YOUR_"
cat infrastructure/deployment-config.json | grep -i "YOUR"

# Should show: YOUR_AZURE_OPENAI_API_KEY_HERE, YOUR-OPENAI-RESOURCE-NAME, etc.
```

---

## 📄 Step 4: Verify Documentation Files

```bash
# Check all docs exist and render correctly
echo "Checking documentation..."
ls -lh README.md SETUP-GUIDE.md SECURITY-AUDIT-REPORT.md GITHUB-PUBLICATION-CHECKLIST.md

# Preview README
head -50 README.md

# Check for broken links
grep -r "](.*)" README.md SETUP-GUIDE.md | grep -v "https://" | grep -v "http://"
```

---

## 🚫 Step 5: Verify Excluded Files

```bash
# Check that sensitive files are NOT in the repo
echo "Verifying excluded files..."

# These should NOT exist
ls local.settings.json 2>/dev/null
ls func-logs/ 2>/dev/null
ls func-logs2/ 2>/dev/null
ls deploy-out/ 2>/dev/null
ls azure-relay-deploy-temp/ 2>/dev/null
ls *.ps1 2>/dev/null

# Each should return: "No such file or directory"

# Check .gitignore is working
git status --ignored | head -20
```

---

## 🌐 Step 6: GitHub Web UI Check

1. **Browse Repository on GitHub**
   - Visit: `https://github.com/andreeavlad16-afk/BC-Voice-Assistant`
   - Check README renders correctly
   - Browse through `/src`, `/azure-relay`, `/infrastructure` folders
   - Verify .app file is visible and downloadable

2. **Check Security Tab**
   - Go to: Security → Secret scanning
   - Should show: "No secrets detected"
   - If alerts present: **DO NOT make public** - investigate first

3. **Check Code Search**
   - Use GitHub's code search: Try searching for "api" or "key"
   - Verify only template placeholders appear

---

## 📋 Step 7: Test as New User

Simulate a new user experience:

```bash
# 1. Can you download the .app file?
curl -L "https://github.com/andreeavlad16-afk/BC-Voice-Assistant/raw/main/Nexer%20Enterprise%20Applications%20UK_NXR%20Voice%20Assistant_2.1.4.3.app" -o test.app
ls -lh test.app

# 2. Can you read the setup guide?
curl -s "https://raw.githubusercontent.com/andreeavlad16-afk/BC-Voice-Assistant/main/SETUP-GUIDE.md" | head -50

# 3. Are IaC templates accessible?
curl -s "https://raw.githubusercontent.com/andreeavlad16-afk/BC-Voice-Assistant/main/infrastructure/main.bicep" | head -30
```

---

## ✅ Final Checklist

Before making public, confirm:

- [ ] All credential searches returned no results
- [ ] .app file is present and downloadable
- [ ] Configuration files show placeholders only (YOUR_*, PLACEHOLDER)
- [ ] No tenant IDs or subscription IDs in tracked files
- [ ] No PowerShell scripts with sensitive data
- [ ] No func-logs or deployment artifacts
- [ ] README renders correctly on GitHub
- [ ] SETUP-GUIDE shows clear IaC instructions
- [ ] No secret scanning alerts on GitHub
- [ ] Documentation links work correctly
- [ ] Can clone and browse as anonymous user would

---

## 🚀 Make Repository Public

**Only proceed if ALL checks above passed:**

### Option 1: GitHub Web UI

1. Go to: `https://github.com/andreeavlad16-afk/BC-Voice-Assistant/settings`
2. Scroll to "Danger Zone"
3. Click "Change visibility"
4. Select "Make public"
5. Read the warnings
6. Type repository name to confirm: `bc-voice-assistant`
7. Click "I understand, make this repository public"

### Option 2: GitHub CLI

```bash
gh repo edit andreeavlad16-afk/BC-Voice-Assistant --visibility public
```

### Option 3: PowerShell with GitHub API

```powershell
$token = "YOUR_GITHUB_TOKEN"
$repo = "andreeavlad16-afk/BC-Voice-Assistant"

$headers = @{
    "Authorization" = "Bearer $token"
    "Accept" = "application/vnd.github+json"
}

$body = @{
    private = $false
} | ConvertTo-Json

Invoke-RestMethod -Uri "https://api.github.com/repos/$repo" `
    -Method Patch `
    -Headers $headers `
    -Body $body
```

---

## ⚠️ If Issues Found

If any checks fail:

1. **DO NOT make repository public**
2. Delete the problematic files/data from git history:
   ```bash
   # Remove file from all commits
   git filter-branch --force --index-filter \
     "git rm --cached --ignore-unmatch path/to/sensitive-file" \
     --prune-empty --tag-name-filter cat -- --all
   
   # Force push
   git push origin --force --all
   ```
3. Consider deleting and recreating the repository if extensive cleanup needed
4. Re-run this checklist

---

## 📞 Need Help?

If you're unsure about any results:
- Review [SECURITY-AUDIT-REPORT.md](SECURITY-AUDIT-REPORT.md)
- Check [GITHUB-PUBLICATION-CHECKLIST.md](GITHUB-PUBLICATION-CHECKLIST.md)
- When in doubt, **stay private** until verified

---

**Safety First:** Better to spend 10 minutes verifying than to leak credentials publicly!

**Date**: January 29, 2026
