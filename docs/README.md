# Chatwoot Documentation

**Last Updated:** January 23, 2026

This directory contains setup guides, debugging documentation, and strategic improvement plans for Chatwoot and its Captain AI assistant.

---

## 📂 Directory Structure

```
docs/
├── setup/              # Setup guides and debugging documentation
│   ├── CAPTAIN_DEBUGGING_SESSION.md
│   ├── PERFORMANCE_IMPROVEMENTS.md
│   ├── LOCAL_SETUP_GUIDE.md
│   ├── WSL_SETUP_GUIDE.md
│   └── ...
│
└── improve/            # Captain improvement roadmap and planning
    ├── README.md
    └── CAPTAIN_IMPROVEMENT_ROADMAP.md
```

---

## 🚀 Quick Navigation

### For New Developers

**Getting Started:**
1. **[Local Setup Guide](./setup/LOCAL_SETUP_GUIDE.md)** - Set up development environment
2. **[WSL Setup Guide](./setup/WSL_SETUP_GUIDE.md)** - Windows WSL2-specific setup
3. Test your setup and explore the codebase

**Understanding Captain:**
4. **[Captain Improvement Roadmap](./improve/CAPTAIN_IMPROVEMENT_ROADMAP.md)** - Understand Captain's architecture and future plans
5. **[Captain Debugging Session](./setup/CAPTAIN_DEBUGGING_SESSION.md)** - Learn debugging methodology

### For Captain Development

**Essential Reading:**
- **[Captain Improvement Roadmap Overview](./improve/README.md)** - Complete guide to Captain improvement plans
- **[Captain Improvement Roadmap (Full)](./improve/CAPTAIN_IMPROVEMENT_ROADMAP.md)** - Detailed 12-month strategic plan
- **[Performance Improvements](./setup/PERFORMANCE_IMPROVEMENTS.md)** - Recent performance optimization work

**Key Implementation Files:**
- `enterprise/lib/captain/logger.rb` - Logging infrastructure
- `enterprise/app/services/captain/llm/assistant_chat_service.rb` - Main chat service
- `enterprise/app/services/captain/tools/search_documentation_service.rb` - Search implementation
- `lib/tasks/captain_playground_api.rake` - API testing tool

### For System Administration

**Deployment & Operations:**
- **[Local Setup Guide](./setup/LOCAL_SETUP_GUIDE.md)** - Development environment setup
- **[Hybrid Setup Complete](./setup/HYBRID_SETUP_COMPLETE.md)** - Hybrid deployment notes
- **[Sync Cloud Data to Local](./setup/SYNC_CLOUD_DATA_TO_LOCAL.md)** - Data synchronization
- **[Quick Sync Commands](./setup/QUICK_SYNC_COMMANDS.md)** - Common sync operations

**Debugging & Troubleshooting:**
- **[Captain Debugging Session](./setup/CAPTAIN_DEBUGGING_SESSION.md)** - Performance debugging case study
- **[Line Endings Explanation](./setup/LINE_ENDINGS_EXPLANATION.md)** - WSL/Linux line ending handling

---

## 🎯 Documentation by Purpose

### Setup & Configuration

| Document | Purpose | Audience |
|----------|---------|----------|
| [LOCAL_SETUP_GUIDE.md](./setup/LOCAL_SETUP_GUIDE.md) | Development environment setup | Developers |
| [WSL_SETUP_GUIDE.md](./setup/WSL_SETUP_GUIDE.md) | Windows WSL2-specific setup | Windows developers |
| [HYBRID_SETUP_COMPLETE.md](./setup/HYBRID_SETUP_COMPLETE.md) | Hybrid deployment configuration | DevOps |

### Captain AI Assistant

| Document | Purpose | Audience |
|----------|---------|----------|
| [improve/README.md](./improve/README.md) | Captain improvement overview | All stakeholders |
| [improve/CAPTAIN_IMPROVEMENT_ROADMAP.md](./improve/CAPTAIN_IMPROVEMENT_ROADMAP.md) | Comprehensive 12-month strategic plan | Product, Engineering |
| [setup/CAPTAIN_DEBUGGING_SESSION.md](./setup/CAPTAIN_DEBUGGING_SESSION.md) | Performance debugging case study | Engineers, DevOps |
| [setup/PERFORMANCE_IMPROVEMENTS.md](./setup/PERFORMANCE_IMPROVEMENTS.md) | Performance optimization summary | Engineers |

### Integration & Features

| Document | Purpose | Audience |
|----------|---------|----------|
| [setup/DEEPSEEK_V3_2_ARK_NOTES.md](./setup/DEEPSEEK_V3_2_ARK_NOTES.md) | DeepSeek LLM integration notes | Engineers |
| [setup/CLAUDE.md](./setup/CLAUDE.md) | Claude AI integration | Engineers |
| [setup/AGENTS.md](./setup/AGENTS.md) | Agent system documentation | Engineers |
| [setup/BUBBLE_ANIMATIONS_IMPLEMENTATION.md](./setup/BUBBLE_ANIMATIONS_IMPLEMENTATION.md) | UI animation implementation | Frontend developers |

### Operations & Maintenance

| Document | Purpose | Audience |
|----------|---------|----------|
| [setup/SYNC_CLOUD_DATA_TO_LOCAL.md](./setup/SYNC_CLOUD_DATA_TO_LOCAL.md) | Data synchronization procedures | DevOps, Developers |
| [setup/QUICK_SYNC_COMMANDS.md](./setup/QUICK_SYNC_COMMANDS.md) | Quick reference for sync commands | DevOps, Developers |
| [setup/LINE_ENDINGS_EXPLANATION.md](./setup/LINE_ENDINGS_EXPLANATION.md) | Git line ending handling (WSL/Linux) | Developers |

### Project Guidelines

| Document | Purpose | Audience |
|----------|---------|----------|
| [setup/CODE_OF_CONDUCT.md](./setup/CODE_OF_CONDUCT.md) | Community guidelines | All contributors |
| [setup/CONTRIBUTING.md](./setup/CONTRIBUTING.md) | Contribution guidelines | All contributors |
| [setup/SECURITY.md](./setup/SECURITY.md) | Security policies | All contributors |

---

## 📈 Recent Updates & Highlights

### January 2026: Captain Performance Breakthrough ✅

**Achievement:** 91% performance improvement (22s → 2.4s response time)

**Key Changes:**
- Fixed proxy configuration for China-based LLM API access
- Implemented comprehensive logging infrastructure
- Enhanced search with text-first hybrid approach
- Created API testing tools

**Documentation:**
- [Captain Debugging Session](./setup/CAPTAIN_DEBUGGING_SESSION.md) - Detailed case study
- [Performance Improvements](./setup/PERFORMANCE_IMPROVEMENTS.md) - Quick summary
- [Updated Roadmap](./improve/CAPTAIN_IMPROVEMENT_ROADMAP.md) - Adjusted priorities

**Impact:**
- Production-ready latency achieved
- Comprehensive observability in place
- Foundation for next phase of improvements

---

## 🎯 Current Focus Areas

### Captain AI Assistant Improvements (Q1 2026)

**Priority 1: Conversation Memory** (Weeks 1-4)
- Track conversation state
- Prevent repeated failed solutions
- Detect frustration and auto-escalate

**Priority 2: Search Enhancement** (Weeks 5-8)
- Query expansion using LLM
- Context-aware reranking
- Product/version filtering

**Priority 3: Handoff Package** (Weeks 9-12)
- Structured summaries for human agents
- Issue history and steps tried
- Relevant documentation links

See [Captain Improvement Roadmap](./improve/CAPTAIN_IMPROVEMENT_ROADMAP.md) for complete plan.

---

## 🔧 Common Tasks

### Testing Captain Performance
```bash
# Test Captain API directly
bundle exec rake "captain:playground_api[,1,,]"

# Monitor performance logs
tail -f log/captain.log

# Test with proxy (if needed)
export HTTPS_PROXY=http://your-proxy:port
bundle exec rails s
```

### Syncing Data
```bash
# Quick sync from cloud to local
# See QUICK_SYNC_COMMANDS.md for details
```

### Running Tests
```bash
# Run Captain-specific tests
bundle exec rspec enterprise/spec/services/captain/

# Run all enterprise tests
bundle exec rspec enterprise/
```

---

## 📞 Getting Help

### For Setup Issues
1. Check the relevant setup guide ([Local](./setup/LOCAL_SETUP_GUIDE.md) or [WSL](./setup/WSL_SETUP_GUIDE.md))
2. Review common issues in the guide
3. Ask in Discord #dev-help channel

### For Captain Issues
1. Check `log/captain.log` for timing and error details
2. Review [Captain Debugging Session](./setup/CAPTAIN_DEBUGGING_SESSION.md) for debugging methodology
3. Test using API tool: `bundle exec rake "captain:playground_api[,1,,]"`
4. Ask in Discord #captain-dev channel

### For Performance Issues
1. Check timing logs in `log/captain.log`
2. Review [Performance Improvements](./setup/PERFORMANCE_IMPROVEMENTS.md)
3. Verify proxy configuration if using external APIs
4. Test LLM API directly using test scripts

### For Strategic Questions
1. Review [Captain Improvement Roadmap](./improve/CAPTAIN_IMPROVEMENT_ROADMAP.md)
2. Check architectural decisions section
3. Consult cost modeling for budget questions
4. Reach out to product team

---

## 🤝 Contributing to Documentation

### When to Update Documentation

**Immediately:**
- Major bugs fixed (create debugging doc like CAPTAIN_DEBUGGING_SESSION.md)
- New features added (update roadmap and relevant guides)
- Setup process changes (update setup guides)
- Configuration changes (update relevant sections)

**Regularly:**
- Roadmap progress (monthly updates)
- Performance metrics (as measured)
- Cost models (when pricing changes)
- Lessons learned (after major milestones)

### Documentation Standards

**Good Documentation Should:**
- ✅ Have clear purpose stated at the top
- ✅ Include last updated date
- ✅ Provide step-by-step instructions for tasks
- ✅ Include code examples where relevant
- ✅ Cross-reference related documents
- ✅ Explain "why" not just "what"

**File Naming:**
- Use SCREAMING_SNAKE_CASE for guides (e.g., `LOCAL_SETUP_GUIDE.md`)
- Be descriptive about content (not just `NOTES.md`)
- Include topic/feature name (e.g., `CAPTAIN_*` prefix for Captain docs)

---

## 📊 Documentation Metrics

**Current State:**
- Total documents: 20+
- Setup guides: 10+
- Captain documentation: 4 major docs
- Last major update: January 23, 2026

**Coverage:**
- ✅ Development setup
- ✅ Captain architecture and roadmap
- ✅ Performance optimization
- ✅ Integration guides
- ⚠️ API documentation (needs expansion)
- ⚠️ Deployment guides (needs consolidation)

---

## 🎯 Documentation Roadmap

### Short-term (Next Month)
- [ ] Create API documentation for Captain endpoints
- [ ] Document deployment procedures for production
- [ ] Add troubleshooting guide for common issues
- [ ] Create video walkthrough for setup

### Medium-term (3-6 Months)
- [ ] Comprehensive architecture documentation
- [ ] Performance tuning guide
- [ ] Security best practices guide
- [ ] Integration cookbook with examples

### Long-term (6-12 Months)
- [ ] Interactive documentation site
- [ ] Developer onboarding checklist
- [ ] Case studies and success stories
- [ ] Community contribution guides

---

## 📝 Document Maintenance

**Ownership:**
- Setup guides: DevOps team
- Captain documentation: Captain development team
- Integration guides: Respective feature owners
- Project guidelines: Core team

**Review Schedule:**
- Setup guides: Quarterly
- Captain roadmap: Monthly
- Integration guides: On feature changes
- Project guidelines: Annually

**Archival Policy:**
- Outdated guides: Move to `docs/archive/` with note
- Superseded documents: Add redirect note at top
- Historical reference: Keep with "Historical" tag

---

## 🔗 External Resources

### Official Chatwoot Documentation
- [Help Center](https://www.chatwoot.com/help-center)
- [API Documentation](https://www.chatwoot.com/developers/api/)
- [Community Forum](https://chatwoot.com/community)

### Development Resources
- [GitHub Repository](https://github.com/chatwoot/chatwoot)
- [Discord Community](https://discord.gg/cJXdrwS)
- [Contributing Guide](./setup/CONTRIBUTING.md)

### Captain-Specific Resources
- [Captain Documentation (Official)](https://chwt.app/captain-docs)
- [Captain Roadmap (This Repo)](./improve/CAPTAIN_IMPROVEMENT_ROADMAP.md)
- Enterprise documentation (in `enterprise/docs/`)

---

**Need something not listed here?** 
- Check the setup/ or improve/ directories directly
- Search GitHub issues for existing discussions
- Ask in Discord #documentation channel
- Create an issue requesting new documentation

---

*Last updated: January 23, 2026*  
*Maintained by: Chatwoot Development Team*
