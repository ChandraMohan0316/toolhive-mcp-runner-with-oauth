# toolhive-mcp Helm Chart

Deploy any remote MCP server behind ToolHive's embedded OAuth 2.0 / Azure AD
authentication proxy on Kubernetes (EKS + AWS ALB).

---

## Helm Repository (GitHub Pages)

```bash
# Add the repo
helm repo add toolhive-mcp https://<GITHUB_OWNER>.github.io/<GITHUB_REPO>
helm repo update

# Search available versions
helm search repo toolhive-mcp

# Install
helm install <release-name> toolhive-mcp/toolhive-mcp \
  -n toolhive \
  -f my-values.yaml \
  --set server.bearerToken="<bearer-token>" \
  --set oauth.azure.clientSecret="<client-secret>"
```

> Replace `<GITHUB_OWNER>` and `<GITHUB_REPO>` with your actual GitHub organization and repository name.

---

## Publishing a New Release

### Option A — GitHub Actions (recommended)

1. Bump `version` in `charts/toolhive-mcp/Chart.yaml`.
2. Commit and push to `main`.
3. In GitHub Actions, select **Release Charts** → **Run workflow**.

chart-releaser packages the chart, creates a GitHub Release, and updates
`index.yaml` on the `gh-pages` branch automatically.

### Option B — Local packaging

```bash
# Requires: helm ≥ 3.10
export GITHUB_OWNER=<your-org>
export GITHUB_REPO=<your-repo>

make package          # lint + package into .cr-release-packages/
make index            # generate/update index.yaml

# Push index.yaml and .tgz files to the gh-pages branch
git checkout gh-pages
cp .cr-release-packages/*.tgz .
cp .cr-release-packages/index.yaml index.yaml
git add .
git commit -m "release: toolhive-mcp-<version>"
git push origin gh-pages
git checkout main
```

---

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| `kubectl` | ≥ 1.26 | Kubernetes CLI |
| `helm` | ≥ 3.10 | Chart deployment |
| `aws` CLI | ≥ 2.x | EKS auth / ECR login |
| AWS credentials | — | EKS cluster access |

Cluster requirements:
- ToolHive Operator installed in the `toolhive` namespace
- AWS Load Balancer Controller installed with proper IAM permissions
- ACM certificate provisioned for the target hostname

---

## Step 1 — Connect to the EKS cluster

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name <your-cluster-name>

# Verify
kubectl get nodes
kubectl get pods -n toolhive
```

---

## Step 2 — Create a values file

```bash
cp charts/toolhive-mcp/values-sample.yaml my-values.yaml
# Edit my-values.yaml and fill in your environment-specific values
```

---

## Step 3 — Create prerequisite Kubernetes secrets

ToolHive's embedded auth server requires two signing secrets. Create them once per
cluster (skip if they already exist):

```bash
# Check if they already exist
kubectl get secret toolhive-signing-key toolhive-hmac-key -n toolhive

# Create signing key (RSA private key for JWT signing)
kubectl create secret generic toolhive-signing-key \
  --from-literal=private-key="$(openssl genrsa 2048)" \
  -n toolhive

# Create HMAC key (for session/token HMAC)
kubectl create secret generic toolhive-hmac-key \
  --from-literal=hmac-key="$(openssl rand -hex 32)" \
  -n toolhive
```

> These secrets are shared across all MCP server deployments in the `toolhive` namespace.

---

## Step 4 — Install the chart

### Option A — Values file only (dev/test)

```bash
helm install <release-name> toolhive-mcp/toolhive-mcp \
  -n toolhive \
  -f my-values.yaml
```

### Option B — Secrets via --set (recommended for CI/production)

```bash
helm install <release-name> toolhive-mcp/toolhive-mcp \
  -n toolhive \
  -f my-values.yaml \
  --set oauth.azure.clientSecret="<client-secret>" \
  --set server.bearerToken="<bearer-token>"
```

---

## Step 5 — Verify the deployment

```bash
# Check all pods are Running
kubectl get pods -n toolhive | grep <release-name>

# Check ingress has an ALB address
kubectl get ingress -n toolhive | grep <release-name>

# Check MCPRemoteProxy and MCPExternalAuthConfig are reconciled
kubectl get mcpremoteproxy,mcpexternalauthconfig -n toolhive | grep <release-name>
```

---

## Step 6 — Create the DNS record

```bash
kubectl get ingress <release-name>-ingress -n toolhive \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

In your DNS provider (Route53 or other), create a **CNAME record**:

```
<your-hostname>  →  <alb-address>.us-east-1.elb.amazonaws.com
```

---

## Step 7 — Register the redirect URI in Azure AD

Add the callback URL in the Azure AD app registration:

```
https://<your-hostname>/oauth/callback
```

**Azure Portal path:** App registrations → your app → Authentication → Add a platform → Web → Redirect URIs

---

## Step 8 — Wait for ALB health check to pass

The ALB health-checks take **2–3 minutes** after deployment:

```bash
kubectl get pods -n toolhive -w | grep <release-name>
kubectl logs -n toolhive -l app=<release-name>-proxy --tail=20
```

The proxy is ready when you see:
```
Workload started successfully. Press Ctrl+C to stop.
```

---

## Step 9 — Add to MCP client config

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

---

## Step 10 — Authenticate

On first connection the MCP client will show **"not authenticated"**. Select
**Authenticate** to open the Azure AD browser login flow.

---

## Upgrade

```bash
helm upgrade <release-name> toolhive-mcp/toolhive-mcp \
  -n toolhive \
  -f my-values.yaml \
  --set oauth.azure.clientSecret="<client-secret>" \
  --set server.bearerToken="<bearer-token>"
```

---

## Uninstall

```bash
helm uninstall <release-name> -n toolhive
```

> The shared `toolhive-signing-key` and `toolhive-hmac-key` secrets are **not** deleted
> by uninstall — they are managed separately.
