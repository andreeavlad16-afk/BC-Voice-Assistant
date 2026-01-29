# Contributing to BC Voice Assistant

First off, thank you for considering contributing to the BC Voice Assistant! This project was created during the Microsoft Hackathon EMEA 2025, and we welcome contributions from the community.

## 🤝 Code of Conduct

This project adheres to a simple code of conduct: be respectful, inclusive, and constructive in all interactions.

### Our Standards

- **Be Respectful**: Treat everyone with respect and professionalism
- **Be Inclusive**: Welcome developers of all experience levels
- **Be Constructive**: Provide helpful feedback and be open to receiving it
- **Be Collaborative**: Work together toward common goals

### Unacceptable Behavior

- Harassment, discrimination, or offensive comments
- Personal attacks or trolling
- Publishing others' private information
- Any conduct that would be inappropriate in a professional setting

## 🚀 How to Contribute

### Reporting Issues

If you find a bug or have a feature request:

1. **Search existing issues** to avoid duplicates
2. **Create a new issue** with a clear title and description
3. **Include details**:
   - Steps to reproduce (for bugs)
   - Expected vs actual behavior
   - Environment details (BC version, Azure region, etc.)
   - Screenshots or logs if applicable

### Suggesting Enhancements

We welcome suggestions for new features or improvements:

1. **Check the roadmap** in issues/discussions first
2. **Open an issue** with the `enhancement` label
3. **Describe the use case** and benefits
4. **Provide examples** if possible

### Pull Requests

We actively welcome pull requests! Here's the process:

#### 1. Fork and Clone

```bash
# Fork the repo on GitHub, then clone your fork
git clone https://github.com/YOUR-USERNAME/BC-Voice-Assistant.git
cd BC-Voice-Assistant
```

#### 2. Create a Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/your-bug-fix
```

Use descriptive branch names:
- `feature/add-realtime-translation`
- `fix/handle-empty-query`
- `docs/update-setup-guide`

#### 3. Make Your Changes

- **Follow existing code style** in AL, JavaScript, and Bicep files
- **Test thoroughly** before submitting
- **Update documentation** if your changes affect setup or usage
- **Keep commits focused** - one logical change per commit

#### 4. Commit Your Changes

Write clear, descriptive commit messages:

```bash
git commit -m "Add support for multi-language queries"
# or
git commit -m "Fix: Handle null response from Azure OpenAI"
```

Good commit message format:
```
[Type]: Brief description (50 chars or less)

More detailed explanation if needed. Explain what and why,
not how (the code shows how).

Fixes #123
```

Types: `Feature`, `Fix`, `Docs`, `Refactor`, `Test`, `Chore`

#### 5. Push and Submit PR

```bash
git push origin feature/your-feature-name
```

Then open a Pull Request on GitHub with:
- **Clear title** describing the change
- **Description** explaining what and why
- **Reference issues** it addresses (e.g., "Fixes #123")
- **Test results** or verification steps

#### 6. PR Review Process

- Maintainers will review your PR
- Address any feedback or requested changes
- Once approved, your PR will be merged
- Your contribution will be acknowledged in release notes!

## 🏗️ Development Setup

### Prerequisites

Follow the [SETUP-GUIDE.md](SETUP-GUIDE.md) to set up your development environment:

1. Business Central sandbox environment
2. Azure subscription
3. AL Language extension for VS Code
4. Node.js 20 LTS

### Project Structure

```
BC-Voice-Assistant/
├── src/                      # Business Central AL code
│   ├── Pages/               # Voice Assistant page
│   ├── Codeunits/           # Voice processing logic
│   └── ...
├── azure-relay/             # Azure Functions (Node.js)
│   ├── query-processor/     # Query handling function
│   └── ...
├── infrastructure/          # Bicep IaC templates
├── pwa/                     # Progressive Web App
└── web-app/                # Web interface
```

### Testing Your Changes

#### Business Central Changes
- Test in a sandbox environment first
- Verify voice commands work as expected
- Check integration with Azure services

#### Azure Functions Changes
- Test locally with `func start`
- Verify API endpoints with Postman/curl
- Check Azure OpenAI integration

#### Infrastructure Changes
- Validate Bicep files: `az bicep build`
- Test deployment in a separate resource group
- Document any new parameters

## 📝 Coding Guidelines

### AL Code (Business Central)

```al
// Use clear, descriptive names
procedure ProcessVoiceQuery(QueryText: Text): Text

// Add comments for complex logic
// Converts user query to OData filter expression
FilterExpression := BuildODataFilter(QueryText);

// Follow Business Central conventions
local procedure IsValidQuery(Query: Text): Boolean
```

### JavaScript (Azure Functions)

```javascript
// Use async/await for async operations
async function processQuery(query) {
  const result = await openAIClient.chat.completions.create({...});
  return result;
}

// Add JSDoc comments
/**
 * Processes voice query using Azure OpenAI
 * @param {string} query - User's voice query
 * @returns {Promise<string>} AI-generated response
 */
```

### Bicep (Infrastructure)

```bicep
// Use parameters for flexibility
@description('Location for all resources')
param location string = resourceGroup().location

// Use descriptive resource names
resource voiceFunction 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  ...
}
```

## 🎯 Contribution Focus Areas

We especially welcome contributions in these areas:

### High Priority
- **Multi-language support** - Support for languages beyond English
- **Additional data sources** - Integration with more BC tables
- **Error handling** - Improved error messages and recovery
- **Security enhancements** - Additional security features

### Medium Priority
- **Performance optimization** - Faster query processing
- **UI improvements** - Better mobile experience
- **Documentation** - More examples and tutorials
- **Testing** - Automated tests for AL and Azure Functions

### Nice to Have
- **Voice feedback** - Audio responses to queries
- **Query history** - Save and replay queries
- **Analytics dashboard** - Usage statistics
- **Offline support** - PWA offline functionality

## 📜 License

By contributing, you agree that your contributions will be licensed under the MIT License (see [LICENSE](LICENSE) file).

## 🙏 Recognition

All contributors will be acknowledged in:
- Release notes
- Contributors section in README
- Project documentation

## ❓ Questions?

- **Issues**: For bugs and feature requests
- **Discussions**: For questions and ideas
- **Email**: Contact the maintainers (see [README.md](README.md))

## 🎉 Thank You!

Your contributions help make BC Voice Assistant better for everyone. Whether it's a bug fix, new feature, documentation improvement, or just spreading the word - every contribution matters!

---

**Remember**: This project was built 100% using AI assistance during a hackathon. We embrace innovation and experimentation! 🤖✨
