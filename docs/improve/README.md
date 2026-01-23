# Captain AI Assistant - Improvement Documentation

**Last Updated:** January 23, 2026

This directory contains strategic planning and improvement documentation for Captain, Chatwoot's AI customer service assistant.

---

## 📚 Documentation Index

### [CAPTAIN_IMPROVEMENT_ROADMAP.md](./CAPTAIN_IMPROVEMENT_ROADMAP.md)
**Comprehensive Strategic Roadmap (12-month plan)**

The complete improvement plan covering:
- ✅ Recent performance improvements (91% faster)
- 🎯 Current state analysis with updated capabilities
- 📋 Four-phase implementation plan (Memory, Tools, Learning, Analytics)
- 💰 Cost modeling and ROI analysis
- ⚠️ Common pitfalls and how to avoid them
- ✅ Roadmap validation checklist
- 🏗️ Architectural decisions and trade-offs

**Start here if:** You want the complete strategic picture and long-term plan.

---

## 🔗 Related Documentation

### Setup & Debugging (in `docs/setup/`)

#### [CAPTAIN_DEBUGGING_SESSION.md](../setup/CAPTAIN_DEBUGGING_SESSION.md)
**Detailed Performance Debugging Case Study**

Documents the investigation and resolution of severe performance issues (22s → 2.4s response time):
- Root cause analysis (proxy configuration)
- Investigation methodology
- Solution implementation
- Lessons learned
- Production deployment guidance

**Read this if:** You encounter performance issues or want to understand the debugging approach.

#### [PERFORMANCE_IMPROVEMENTS.md](../setup/PERFORMANCE_IMPROVEMENTS.md)
**Quick Performance Fix Summary**

Condensed version of the debugging session covering:
- The proxy configuration problem
- Files modified
- Performance results
- Testing procedures

**Read this if:** You need a quick reference for the performance improvements.

---

## 🎯 Quick Start Guide

### For Product Managers

1. **Read:** [CAPTAIN_IMPROVEMENT_ROADMAP.md](./CAPTAIN_IMPROVEMENT_ROADMAP.md) - Executive Summary and Gap Analysis sections
2. **Review:** Success metrics and target KPIs (70% resolution rate, <10min avg resolution time)
3. **Validate:** Roadmap Validation Checklist to ensure alignment with business goals
4. **Prioritize:** Review the adjusted priorities post-performance fix

**Key Questions to Answer:**
- What is our expected conversation volume? (affects cost and infrastructure)
- What products will Captain support initially?
- What is our target deflection rate and timeline?
- What integrations are available? (orders, devices, warranty systems)

### For Engineering Leads

1. **Read:** [CAPTAIN_IMPROVEMENT_ROADMAP.md](./CAPTAIN_IMPROVEMENT_ROADMAP.md) - Implementation Sequence and Architectural Decisions
2. **Review:** [CAPTAIN_DEBUGGING_SESSION.md](../setup/CAPTAIN_DEBUGGING_SESSION.md) for recent work context
3. **Assess:** Technical Infrastructure Assessment checklist
4. **Plan:** Quarter 1 priorities (Memory, Search Enhancement, Handoff Package)

**Key Technical Decisions:**
- Customer memory storage: Start with JSON column, migrate to table if needed
- Embedding search: Use pgvector for MVP, evaluate dedicated vector DB at scale
- LLM provider: Architect for multi-provider support, add fallback before production
- Tool authorization: Implement assistant-level permissions from start

### For Developers

1. **Understand:** Read [PERFORMANCE_IMPROVEMENTS.md](../setup/PERFORMANCE_IMPROVEMENTS.md) for recent changes
2. **Explore:** Key implementation files:
   - `enterprise/lib/captain/logger.rb` - Logging infrastructure
   - `enterprise/app/services/captain/llm/assistant_chat_service.rb` - Main chat service
   - `enterprise/app/services/captain/tools/search_documentation_service.rb` - Search with text-first hybrid
3. **Test:** Use `lib/tasks/captain_playground_api.rake` for API testing
4. **Debug:** Check `log/captain.log` for comprehensive timing breakdowns

**Development Workflow:**
```bash
# Test Captain API directly
bundle exec rake "captain:playground_api[,1,,]"

# Monitor performance
tail -f log/captain.log

# Run with proxy (if needed for China-based APIs)
export HTTPS_PROXY=http://your-proxy:port
bundle exec rails s
```

### For QA/Support Teams

1. **Read:** Common Pitfalls section in [CAPTAIN_IMPROVEMENT_ROADMAP.md](./CAPTAIN_IMPROVEMENT_ROADMAP.md)
2. **Understand:** What Captain can and cannot do currently
3. **Prepare:** For handoff package implementation (Phase 1, Weeks 9-12)
4. **Test:** Use playground to validate improvements

**Testing Focus Areas:**
- Response accuracy (citations present?)
- Escalation appropriateness (when should human take over?)
- Conversation flow (does it remember context?)
- Documentation coverage (are common questions answered?)

---

## 📊 Current State Summary

### ✅ Completed (January 2026)

**Performance Optimization:**
- 91% latency reduction (22s → 2.4s)
- Proxy configuration for China-based API access
- Production-ready response times

**Observability Infrastructure:**
- Dedicated Captain logger (`log/captain.log`)
- Comprehensive timing instrumentation
- Request/response tracking
- Tool execution monitoring

**Search Optimization:**
- Hybrid text + embedding search
- Text-first strategy for keyword queries
- Reduced unnecessary embedding API calls

**Testing Tools:**
- API testing rake task
- Direct LLM timing test scripts
- Performance validation framework

### 🔄 In Progress

**Search Enhancement:**
- ✅ Hybrid search (completed)
- ❌ Query expansion (planned Q1)
- ❌ Context-aware reranking (planned Q1)
- ❌ Product/version filtering (planned Q1)

### 🎯 Next Priorities (Q1 2026)

1. **Conversation Memory** (Weeks 1-4) - Track state, prevent repeated solutions
2. **Search Enhancement** (Weeks 5-8) - Query expansion, reranking, filtering
3. **Handoff Package** (Weeks 9-12) - Structured summaries for human agents

---

## 📈 Success Metrics

### Target Metrics (6 months post-full implementation)

| Metric | Baseline | Target | Current |
|--------|----------|--------|---------|
| **Resolution Rate** | ~40% | 70% | ~40% (baseline) |
| **Avg Response Time** | ~22s | 2-4s | ✅ 2.4s (achieved!) |
| **CSAT Score** | 3.2/5 | 4.0/5 | Measuring... |
| **Escalation Rate** | ~60% | <30% | ~60% (baseline) |
| **Documentation Coverage** | ~60% | >90% | ~65% (improving) |
| **Hallucination Rate** | ~10% | <3% | Monitoring... |

### Leading Indicators (Track Weekly)

- Search relevance score
- Tool usage rate
- Forced search trigger rate
- Conversation length
- Repeat contact rate (same issue within 7 days)

---

## 💰 Cost & ROI Summary

### Current Costs (Post-Performance Fix)

- **Per Conversation:** ~$0.12 (LLM) + $0.02 (infrastructure) = **$0.14 total**
- **Monthly (1,000 conversations/day):** ~$3,600
- **Annual (1,000 conversations/day):** ~$43,200

### Projected ROI

**Assumptions:**
- Human agent cost: $3.33 per ticket
- Captain deflection rate: 50%
- Daily conversations: 1,000

**Savings:**
- Per deflected conversation: $3.33 - $0.14 = $3.19
- Annual savings: ~$574,000
- Development investment: ~$155,000 (Year 1)
- **ROI: 270% in Year 1**

*Note: ROI heavily depends on achieving target deflection rate. Monitor closely.*

---

## ⚠️ Top 3 Risks to Watch

### 1. Hallucination Despite Safeguards
**Mitigation:** 
- Multi-layer validation already in place
- Add automated quality assurance pipeline (Phase 3.2)
- Human QA review of 5% of conversations

### 2. Cost Overrun from High Volume
**Mitigation:**
- Implement rate limiting per user/account
- Set up cost alerts ($100/day threshold)
- Use model tiering (simple queries → cheaper model)
- Optimize prompts with caching

### 3. Stale Documentation Leading to Wrong Answers
**Mitigation:**
- Timestamp all documentation
- Implement conversation mining to detect gaps (Phase 3.1)
- KB freshness monitoring
- Alert system for outdated content

---

## 🚀 Getting Started with Improvements

### Immediate Actions (This Week)

1. **Validate Roadmap Assumptions**
   - [ ] Complete Roadmap Validation Checklist
   - [ ] Confirm expected conversation volume
   - [ ] Verify integration availability (orders, devices, etc.)
   - [ ] Establish baseline metrics

2. **Assess Team Capacity**
   - [ ] Confirm 1-2 engineers available for Captain work
   - [ ] Identify QA reviewers
   - [ ] Engage KB/content team
   - [ ] Brief support team on upcoming changes

3. **Set Up Monitoring**
   - [ ] Implement basic metrics tracking
   - [ ] Create dashboard for key metrics
   - [ ] Set up alerts for anomalies
   - [ ] Begin collecting baseline data

### Next 30 Days

4. **Begin Phase 1.1: Conversation Memory**
   - [ ] Design conversation state schema
   - [ ] Add `state` JSON column to conversations table
   - [ ] Implement state tracking service
   - [ ] Test with sample conversations

5. **Prepare for Phase 1.2: Search Enhancement**
   - [ ] Audit current documentation quality
   - [ ] Test current search relevance
   - [ ] Design query expansion approach
   - [ ] Plan reranking algorithm

6. **Build Test Set**
   - [ ] Collect 50-100 real support conversations
   - [ ] Categorize by issue type
   - [ ] Create gold standard answers
   - [ ] Document common edge cases

---

## 📞 Questions & Support

### For Roadmap Questions
- Review the comprehensive roadmap document
- Check architectural decisions section
- Consult cost modeling for budget questions

### For Technical Issues
- Check `log/captain.log` for timing and errors
- Use API testing tool: `bundle exec rake "captain:playground_api[,1,,]"`
- Review debugging session doc for investigation methodology

### For Performance Issues
- Verify proxy configuration (if using external APIs)
- Check timing logs to identify bottlenecks
- Refer to `docs/setup/CAPTAIN_DEBUGGING_SESSION.md`

---

## 📝 Document Maintenance

**Update Frequency:**
- Roadmap: Monthly or after major milestones
- README: After significant changes or new documentation added
- Debugging docs: As needed when issues are resolved

**Version History:**
- v2.0 (Jan 23, 2026) - Added performance improvements, updated roadmap with recent work
- v1.0 (Jan 2026) - Initial roadmap creation

**Contributors:**
- Captain Development Team
- Support Team Feedback
- Product Management

---

## 🎯 Vision

**Short-term (3 months):** Production-ready AI assistant with conversation memory, enhanced search, and excellent human handoff.

**Medium-term (6 months):** Intelligent assistant that learns from conversations, accesses live business data, and proactively helps customers.

**Long-term (12 months):** Comprehensive AI support system resolving 70% of issues, continuously improving through feedback loops, with full observability and quality assurance.

**Success looks like:**
- Customers get fast, accurate answers without waiting for humans
- Human agents spend time on complex issues, not repetitive questions
- Support costs decrease while customer satisfaction increases
- The system gets smarter every day through continuous learning
