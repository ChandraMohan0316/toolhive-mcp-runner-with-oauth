# toolhive-mcp-runner

Deploy any remote MCP (Model Context Protocol) server behind ToolHive's embedded OAuth 2.0 / Azure AD authentication proxy on Kubernetes. A single Helm release provisions an `MCPRemoteProxy`, `MCPExternalAuthConfig`, AWS ALB Ingress, and all required Kubernetes Secrets.

## How it works

```
MCP Client  ──HTTPS──►  AWS ALB  ──►  ToolHive Proxy  ──bearer token──►  Upstream MCP Server
                                           │
                                     Azure AD OIDC
                                   (OAuth 2.0 consent)
```

- Clients authenticate via Azure AD before any request reaches the upstream.
- The upstream bearer token is injected by the proxy and is never exposed to clients.
- RSA signing key and HMAC key are auto-generated on first install and preserved across upgrades.

## Prerequisites

| Requirement | Notes |
|---|---|
| Kubernetes ≥ 1.26 | EKS recommended |
| Helm ≥ 3.10 | Required for OCI dependency support |
| AWS Load Balancer Controller | With appropriate IAM permissions |
| ACM certificate | For the target hostname |
| Azure AD app registration | With a client secret and redirect URI configured |

The ToolHive CRDs (`MCPRemoteProxy`, `MCPExternalAuthConfig`) and the ToolHive Operator are **bundled as sub-chart dependencies** and installed automatically by this chart. You do not need to install them separately unless they are already present in the cluster (in which case set `prerequisites.installCRDs: false` and `prerequisites.installOperator: false`).

## Add the Helm repository

```bash
helm repo add toolhive-mcp https://<GITHUB_OWNER>.github.io/<GITHUB_REPO>
helm repo update
```

> Replace `<GITHUB_OWNER>` and `<GITHUB_REPO>` with your GitHub organization and repository name.

## Install

```bash
helm install <release-name> toolhive-mcp/toolhive-mcp \
  --namespace toolhive \
  --create-namespace \
  --values my-values.yaml \
  --set server.bearerToken="<upstream-bearer-token>" \
  --set oauth.azure.clientSecret="<azure-client-secret>"
```

Pass secrets via `--set` rather than storing them in your values file.

## Configuration

Copy `values-sample.yaml` as a starting point:

```bash
helm show values toolhive-mcp/toolhive-mcp > my-values.yaml
```

### Required values

All seven values below must be provided — the chart fails fast with a clear error if any are missing.

| Key | Description |
|---|---|
| `server.remoteUrl` | URL of the upstream MCP server (e.g. `https://api.githubcopilot.com/mcp/`) |
| `server.bearerToken` | Bearer token forwarded to the upstream; never exposed to clients |
| `ingress.host` | Public hostname (e.g. `mcp.example.com`) |
| `ingress.certificateArn` | ACM certificate ARN for TLS termination |
| `oauth.azure.tenantId` | Azure AD tenant ID |
| `oauth.azure.clientId` | Azure AD application (client) ID |
| `oauth.azure.clientSecret` | Azure AD client secret |

### Full values reference

| Key | Default | Description |
|---|---|---|
| `server.remoteUrl` | `""` | Upstream MCP server URL |
| `server.bearerToken` | `""` | Bearer token injected on proxy→upstream leg |
| `ingress.host` | `""` | Public hostname (`https://` prefix is stripped automatically) |
| `ingress.certificateArn` | `""` | ACM certificate ARN |
| `ingress.idleTimeoutSeconds` | `3600` | ALB idle connection timeout |
| `ingress.scheme` | `internet-facing` | ALB scheme: `internet-facing` or `internal` |
| `oauth.accessTokenLifespan` | `1h` | OAuth access token TTL |
| `oauth.refreshTokenLifespan` | `168h` | OAuth refresh token TTL (7 days) |
| `oauth.authCodeLifespan` | `10m` | Authorization code TTL |
| `oauth.azure.tenantId` | `""` | Azure AD tenant ID |
| `oauth.azure.clientId` | `""` | Azure AD app (client) ID |
| `oauth.azure.clientSecret` | `""` | Azure AD client secret |
| `oauth.azure.scopes` | `[openid, profile, email]` | OIDC scopes requested from Azure AD |
| `proxy.image` | `ghcr.io/stacklok/toolhive/proxyrunner:latest` | ToolHive proxy runner image |
| `proxy.port` | `8080` | Proxy listener port |
| `proxy.debug` | `false` | Enable debug logging |
| `namespace` | `toolhive` | Target namespace |
| `prerequisites.installCRDs` | `true` | Install ToolHive CRDs as a sub-chart |
| `prerequisites.installOperator` | `true` | Install ToolHive Operator as a sub-chart |
| `prerequisites.createSigningSecrets` | `true` | Auto-generate RSA and HMAC signing secrets |

### Disabling prerequisites

If ToolHive CRDs or the operator are already installed in your cluster, disable the bundled sub-charts to avoid conflicts:

```yaml
prerequisites:
  installCRDs: false
  installOperator: false
```

## Post-install steps

### 1. Get the ALB hostname

```bash
kubectl get ingress <release-name>-ingress -n toolhive \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### 2. Create a DNS record

In Route 53 (or your DNS provider), create a **CNAME**:

```
<your-hostname>  →  <alb-address>.us-east-1.elb.amazonaws.com
```

### 3. Register the redirect URI in Azure AD

Add the following redirect URI to your Azure AD app registration:

```
https://<your-hostname>/oauth/callback
```

**Azure Portal:** App registrations → your app → Authentication → Add a platform → Web → Redirect URIs

### 4. Add to your MCP client config

```json
{
  "mcpServers": {
    "<your-server-name>": {
      "type": "http",
      "url": "https://<your-hostname>/mcp"
    }
  }
}
```

On first connection the client will prompt for Azure AD authentication.

## Upgrade

```bash
helm upgrade <release-name> toolhive-mcp/toolhive-mcp \
  --namespace toolhive \
  --values my-values.yaml \
  --set server.bearerToken="<upstream-bearer-token>" \
  --set oauth.azure.clientSecret="<azure-client-secret>"
```

Signing secrets are preserved across upgrades — no key rotation occurs unless you delete them manually.

## Uninstall

```bash
helm uninstall <release-name> --namespace toolhive
```

> The `toolhive-signing-key` and `toolhive-hmac-key` secrets are annotated with `helm.sh/resource-policy: keep` and are **not** deleted on uninstall. Remove them manually only if you are decommissioning the entire ToolHive installation.

## Chart dependencies

| Chart | Version | Repository | Condition |
|---|---|---|---|
| `toolhive-operator-crds` | 0.0.106 | `oci://ghcr.io/stacklok/toolhive` | `prerequisites.installCRDs` |
| `toolhive-operator` | 0.5.28 | `oci://ghcr.io/stacklok/toolhive` | `prerequisites.installOperator` |

## Releasing a new version

### Via GitHub Actions (recommended)

1. Bump `version` in `charts/toolhive-mcp/Chart.yaml`.
2. Commit and push to `main`.

`chart-releaser` packages the chart, creates a GitHub Release, and updates `index.yaml` on the `gh-pages` branch automatically.


- [ToolHive](https://github.com/stacklok/toolhive)
- [ToolHive Operator](https://github.com/stacklok/toolhive)
