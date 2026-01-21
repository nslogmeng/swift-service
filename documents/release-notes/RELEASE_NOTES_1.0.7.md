# 🔑 ServiceEnv Hashable Support & Documentation Navigation Enhancement

## ServiceEnv Hashable Conformance
`ServiceEnv` now conforms to the `Hashable` protocol, enabling more flexible usage patterns in your codebase.

**What's new:**
- `ServiceEnv` instances can now be used as dictionary keys
- `ServiceEnv` instances can be stored in `Set` collections
- Equality comparison is based on the environment's `name` property
- Hash values are computed from the environment's `name` property

**What's improved:**
- Root path (`/`) automatically redirects to `/documentation/service/`
- Language-specific root paths (e.g., `/zh-Hans/`) redirect to their respective documentation pages
- Redirect logic preserves SPA (Single Page Application) functionality
- Seamless navigation for both English and Chinese documentation

**User experience:**
- Direct access to documentation from the site root
- Consistent behavior across all language versions
- No manual navigation required to reach documentation content

---

**Full changelog:** [View commit history](https://github.com/nslogmeng/swift-service/compare/1.0.6...1.0.7)