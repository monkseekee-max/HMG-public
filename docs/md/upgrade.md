# Upgrade to Developer or Enterprise

HMG uses a single binary for all editions. Upgrading does not require
reinstallation or data migration — you enter a license key and restart.

## Edition Comparison

| Feature | Community | Developer | Enterprise |
|---|---|---|---|
| Price | Free | $92/yr or $9/mo | Annual contract |
| Memory storage | ✅ | ✅ | ✅ |
| Memory recall | One-Shot Recall | **One-Shot Recall** | One-Shot + Domain |
| Semantic (vector) search | ❌ | ✅ | ✅ |
| Correction / Governance | ✅ | ✅ | ✅ |
| MCP / HTTP protocol | ✅ | ✅ | ✅ |
| Agent integration | ✅ | ✅ | ✅ |
| Consolidation | Manual only | Automated | Automated + policies |
| Domain Packs | None | software-engineering | + customer-service, compliance |
| Max atoms | 100,000 | Unlimited | Unlimited |
| Max instances | 3 | Unlimited | Unlimited |
| SSO / RBAC | ❌ | ❌ | ✅ SAML/OIDC/SCIM |
| Audit export | ❌ | Basic | Full + retention + legal hold |
| Connectors | ❌ | ❌ | GitHub/GitLab/Jira/Slack/Feishu |

## How to Upgrade

### 1. Obtain a License Key

- **Developer Local**: Purchase at [HMG pricing page](https://hmg1ai.com/pricing)
- **Developer Cloud**: Sign up for a cloud subscription
- **Enterprise**: Contact [security@hmg1ai.com](mailto:security@hmg1ai.com)

### 2. Apply the Key

```bash
# Option A: Environment variable
export HMG_LICENSE_KEY=<your-license-key>
hmg daemon restart

# Option B: License file
mkdir -p ~/.config/hmg
echo "<your-license-key>" > ~/.config/hmg/license.key
hmg daemon restart

# Option C: Cloud token
export HMG_CLOUD_TOKEN=your-cloud-token
hmg daemon restart
```

### 3. Verify

```bash
hmg --version
# hmg 1.7.1-developer

hmg doctor
# ✓ License: Developer (valid)
# ✓ One-Shot Recall: activated
# ✓ Consolidation: automated
# ✓ Domain Pack: software-engineering
```

## Graceful Degradation

If a license expires or becomes invalid:

- The binary continues running as Community Edition
- No data is lost
- Advanced features become unavailable
- Existing memory remains fully accessible
- A 7-day offline grace period applies for cloud licenses

## Data Compatibility

All editions share the same storage format. You can upgrade or downgrade
at any time:

```text
Community storage → Developer key applied → same data, new features
Developer storage → key removed → same data, Community features only
```
