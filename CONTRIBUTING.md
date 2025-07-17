# Contributing to NetBird Self-Hosted Deployer

Thank you for your interest in contributing to the NetBird Self-Hosted Deployer! This document outlines the guidelines and processes for contributing to this project.

## 🤝 How to Contribute

We welcome contributions of all kinds, including:

- 🐛 Bug reports and fixes
- ✨ New features and enhancements
- 📚 Documentation improvements
- 🧪 Test coverage improvements
- 💡 Suggestions and feedback
- 🌍 Translations and localization

## 📋 Before You Start

### Prerequisites

- Familiarity with bash scripting
- Experience with Docker and Docker Compose
- Understanding of NetBird architecture
- Basic knowledge of Azure AD and OAuth2
- Access to Hetzner Cloud for testing (optional but recommended)

### Development Environment

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR-USERNAME/netbird-selfhosted-deployer.git
   cd netbird-selfhosted-deployer
   ```
3. **Set up upstream remote**:
   ```bash
   git remote add upstream https://github.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer.git
   ```

## 🔄 Development Workflow

### 1. Create a Feature Branch

```bash
# Update your main branch
git checkout main
git pull upstream main

# Create a feature branch
git checkout -b feature/your-feature-name
# or
git checkout -b bugfix/issue-number-description
```

### 2. Make Your Changes

- Follow our coding standards (see below)
- Write clear, concise commit messages
- Test your changes thoroughly
- Update documentation as needed

### 3. Test Your Changes

```bash
# Run shellcheck on scripts
shellcheck deploy-netbird-selfhosted.sh
shellcheck install.sh

# Test deployment in a controlled environment
# (Use Hetzner Cloud test account if available)
./deploy-netbird-selfhosted.sh --dry-run

# Test installation script
./install.sh
```

### 4. Commit Your Changes

Follow conventional commit standards:

```bash
git add .
git commit -m "feat: add support for custom server locations"
# or
git commit -m "fix: resolve OAuth callback 404 issue"
# or
git commit -m "docs: update Azure AD setup guide"
```

#### Commit Message Format

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

### 5. Push and Create Pull Request

```bash
git push origin feature/your-feature-name
```

Then create a pull request on GitHub with:
- Clear title and description
- Reference to related issues
- Screenshots or logs (if applicable)
- Checklist of changes made

## 📝 Coding Standards

### Bash Scripting Guidelines

1. **Use set -e** for error handling:
   ```bash
   #!/bin/bash
   set -e
   ```

2. **Quote variables** to prevent word splitting:
   ```bash
   echo "Hello, $USER"
   rm -rf "$TEMP_DIR"
   ```

3. **Use functions** for reusable code:
   ```bash
   print_status() {
       echo -e "${BLUE}[INFO]${NC} $1"
   }
   ```

4. **Check command existence**:
   ```bash
   if ! command -v docker >/dev/null 2>&1; then
       print_error "Docker is not installed"
       exit 1
   fi
   ```

5. **Use meaningful variable names**:
   ```bash
   # Good
   SERVER_TYPE="cax11"
   DOMAIN_NAME="nb.example.com"
   
   # Bad
   ST="cax11"
   DN="nb.example.com"
   ```

### Documentation Guidelines

1. **Use clear headings** with emoji for better readability
2. **Include code examples** with proper syntax highlighting
3. **Provide context** for why something is needed
4. **Update relevant sections** when making changes
5. **Use consistent formatting** throughout

### Configuration Files

1. **Use comments** to explain complex configurations
2. **Follow YAML/JSON standards** for formatting
3. **Validate syntax** before committing
4. **Use environment variables** for customizable values

## 🧪 Testing Guidelines

### Manual Testing

1. **Test on clean environment**: Use fresh Ubuntu 24.04 installation
2. **Test different scenarios**:
   - New installation
   - Upgrade from previous version
   - Custom configuration options
   - Error conditions

3. **Validate Azure AD integration**:
   - SPA configuration
   - OAuth flow
   - Token exchange
   - User management

### Automated Testing

1. **Shellcheck validation**: All scripts must pass shellcheck
2. **Syntax validation**: YAML/JSON files must be valid
3. **Link checking**: Documentation links must work
4. **Integration tests**: Core functionality must work end-to-end

## 📋 Pull Request Guidelines

### Before Submitting

- [ ] Code follows project standards
- [ ] All tests pass
- [ ] Documentation is updated
- [ ] Commit messages are clear
- [ ] No merge conflicts with main branch

### Pull Request Template

When creating a pull request, include:

```markdown
## Description
Brief description of changes made.

## Type of Change
- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update

## Testing
- [ ] Tested on Ubuntu 24.04
- [ ] Tested Azure AD integration
- [ ] Shellcheck passed
- [ ] Documentation links verified

## Screenshots (if applicable)
Include screenshots or logs demonstrating the changes.

## Related Issues
Fixes #(issue number)
```

### Review Process

1. **Automated checks** must pass
2. **Code review** by maintainers
3. **Testing verification** (may require additional testing)
4. **Documentation review** for accuracy and completeness
5. **Approval and merge** by project maintainers

## 🐛 Reporting Issues

### Bug Reports

When reporting bugs, include:

1. **System information**:
   - OS version (Ubuntu 24.04, etc.)
   - Docker version
   - Script version

2. **Steps to reproduce**:
   - Exact commands run
   - Configuration used
   - Expected vs actual behavior

3. **Logs and error messages**:
   - Full error output
   - Relevant log files
   - Screenshots if applicable

4. **Environment details**:
   - Hetzner Cloud region
   - Azure AD tenant type
   - Network configuration

### Feature Requests

For new features, provide:

1. **Use case description**: Why is this feature needed?
2. **Proposed solution**: How should it work?
3. **Alternatives considered**: What other approaches were considered?
4. **Implementation ideas**: Any thoughts on how to implement?

## 🌟 Recognition

Contributors will be recognized in:

- **README.md contributors section**
- **Release notes** for significant contributions
- **GitHub contributors graph**
- **Special mentions** in project announcements

## 📞 Getting Help

### Communication Channels

- **GitHub Issues**: For bugs and feature requests
- **GitHub Discussions**: For questions and general discussion
- **Email**: For private or security-related matters (support@panoptic.ie)

### Maintainer Contact

- **Primary Maintainer**: Panoptic IT Solutions
- **Response Time**: We aim to respond within 48 hours
- **Availability**: Monday-Friday, 9 AM - 5 PM GMT

## 📚 Additional Resources

### Learning Resources

- [NetBird Official Documentation](https://docs.netbird.io/)
- [Azure AD Documentation](https://docs.microsoft.com/en-us/azure/active-directory/)
- [Hetzner Cloud API Documentation](https://docs.hetzner.cloud/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Bash Scripting Guide](https://tldp.org/LDP/Bash-Beginners-Guide/html/)

### Tools and Utilities

- **Shellcheck**: [shellcheck.net](https://www.shellcheck.net/)
- **Markdown Lint**: [markdownlint](https://github.com/markdownlint/markdownlint)
- **YAML Lint**: [yamllint](https://yamllint.readthedocs.io/)
- **JSON Validator**: [jsonlint.com](https://jsonlint.com/)

## 📜 Code of Conduct

### Our Pledge

We are committed to making participation in this project a harassment-free experience for everyone, regardless of age, body size, disability, ethnicity, gender identity and expression, level of experience, nationality, personal appearance, race, religion, or sexual identity and orientation.

### Expected Behavior

- Use welcoming and inclusive language
- Be respectful of differing viewpoints and experiences
- Gracefully accept constructive criticism
- Focus on what is best for the community
- Show empathy towards other community members

### Unacceptable Behavior

- Trolling, insulting/derogatory comments, and personal or political attacks
- Public or private harassment
- Publishing others' private information without explicit permission
- Other conduct which could reasonably be considered inappropriate in a professional setting

### Enforcement

Instances of abusive, harassing, or otherwise unacceptable behavior may be reported by contacting the project team at support@panoptic.ie. All complaints will be reviewed and investigated promptly and fairly.

---

Thank you for contributing to NetBird Self-Hosted Deployer! Your contributions help make secure networking accessible to everyone.