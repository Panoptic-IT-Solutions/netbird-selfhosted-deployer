## Pull Request Description

### Summary
Brief description of the changes in this pull request.

### Type of Change
Please select the type of change this PR introduces:

- [ ] 🐛 **Bug fix** (non-breaking change that fixes an issue)
- [ ] ✨ **New feature** (non-breaking change that adds functionality)
- [ ] 💥 **Breaking change** (fix or feature that would cause existing functionality to not work as expected)
- [ ] 📚 **Documentation update** (changes to documentation only)
- [ ] 🔧 **Refactoring** (code changes that neither fix bugs nor add features)
- [ ] ⚡ **Performance improvement** (changes that improve performance)
- [ ] 🧪 **Test improvement** (adding or improving tests)
- [ ] 🔒 **Security enhancement** (changes that improve security)
- [ ] 🏗️ **Infrastructure** (changes to build process, CI/CD, etc.)

### Related Issues
- Fixes #(issue number)
- Closes #(issue number)
- Related to #(issue number)

### Changes Made
Please describe the changes made in this PR:

#### Added
- 

#### Changed
- 

#### Removed
- 

#### Fixed
- 

### Testing
Please describe how you tested these changes:

#### Test Environment
- [ ] Tested on Ubuntu 24.04
- [ ] Tested on Ubuntu 22.04
- [ ] Tested with ARM architecture
- [ ] Tested with x86_64 architecture
- [ ] Tested in Hetzner Cloud environment
- [ ] Tested with Azure AD integration

#### Test Scenarios
- [ ] Fresh installation
- [ ] Upgrade from previous version
- [ ] Custom configuration options
- [ ] Error handling scenarios
- [ ] Multi-user scenarios

#### Azure AD Testing
- [ ] SPA configuration works correctly
- [ ] OAuth flow completes successfully
- [ ] Token exchange functions properly
- [ ] User authentication successful
- [ ] Authorization policies work

#### Infrastructure Testing
- [ ] Server provisioning works
- [ ] Firewall rules applied correctly
- [ ] SSL certificates generated
- [ ] Services start successfully
- [ ] Health checks pass

### Code Quality
Please confirm the following:

#### Script Quality
- [ ] Shellcheck passes without errors
- [ ] Code follows project style guidelines
- [ ] Functions are properly documented
- [ ] Error handling is comprehensive
- [ ] Variables are properly quoted

#### Security Review
- [ ] No hardcoded credentials
- [ ] Secure defaults implemented
- [ ] Input validation added where needed
- [ ] File permissions set correctly
- [ ] Network security considered

### Documentation
Please check what documentation has been updated:

- [ ] README.md updated
- [ ] CHANGELOG.md updated
- [ ] Setup guides updated
- [ ] Troubleshooting guide updated
- [ ] Security documentation updated
- [ ] Example configurations updated
- [ ] API documentation updated (if applicable)

### Backward Compatibility
- [ ] This change is backward compatible
- [ ] This change requires migration steps (documented below)
- [ ] This is a breaking change (documented below)

#### Migration Steps (if required)
If this PR introduces breaking changes, please describe the migration steps:

1. 
2. 
3. 

### Performance Impact
- [ ] No performance impact
- [ ] Minor performance improvement
- [ ] Significant performance improvement
- [ ] Minor performance regression (justified below)
- [ ] Major performance impact (requires discussion)

**Performance justification (if applicable):**

### Deployment Impact
- [ ] No deployment changes required
- [ ] Requires configuration update
- [ ] Requires service restart
- [ ] Requires full redeployment
- [ ] Requires database migration

### Screenshots/Logs
If applicable, add screenshots or log outputs that demonstrate the changes:

<details>
<summary>Screenshots</summary>

<!-- Add screenshots here -->

</details>

<details>
<summary>Test Logs</summary>

```bash
# Add relevant test logs here
```

</details>

### Additional Notes
Any additional information that reviewers should know:

### Checklist
Please confirm you have completed the following:

#### Pre-submission
- [ ] I have performed a self-review of my code
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] I have made corresponding changes to the documentation
- [ ] My changes generate no new warnings
- [ ] I have added tests that prove my fix is effective or that my feature works
- [ ] New and existing unit tests pass locally with my changes

#### Testing
- [ ] All automated tests pass
- [ ] Manual testing completed successfully
- [ ] Edge cases have been considered and tested
- [ ] Error scenarios have been tested

#### Documentation
- [ ] Documentation is accurate and up-to-date
- [ ] Examples are working and tested
- [ ] Breaking changes are clearly documented
- [ ] Migration guide provided (if needed)

#### Security
- [ ] Security implications have been considered
- [ ] No sensitive information exposed
- [ ] Authentication/authorization works correctly
- [ ] Input validation implemented where needed

### Reviewer Notes
Special instructions or areas of focus for reviewers:

---

### For Maintainers

#### Review Checklist
- [ ] Code quality and style
- [ ] Security review completed
- [ ] Performance impact assessed
- [ ] Documentation accuracy verified
- [ ] Tests are comprehensive
- [ ] Backward compatibility confirmed
- [ ] Breaking changes properly documented

#### Deployment Checklist
- [ ] Staging deployment successful
- [ ] Production deployment plan reviewed
- [ ] Rollback plan confirmed
- [ ] Monitoring and alerting updated