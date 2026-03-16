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

Copy the default values and fill in your environment-specific values:

```bash
cp helm/aap-mcp/values.yaml helm/aap-mcp/my-values.yaml
```
---


## Step 3 — Create prerequisite Kubernetes secrets

ToolHive's embedded auth server requires two signing secrets. Create them once per cluster (skip if already exist):

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
helm install <release-name> helm/aap-mcp \
  -n toolhive \
  -f helm/aap-mcp/my-values.yaml
```

### Option B — Secrets via --set (recommended for CI/production)

Keep secrets out of the values file and inject at deploy time:

```bash
helm install <release-name> helm/aap-mcp \
  -n toolhive \
  -f helm/aap-mcp/my-values.yaml \
  --set oauth.azure.clientSecret="<client-secret>" \
  --set aap.bearerToken="<aap-token>"
```

---

## Step 5 — Verify the deployment

```bash
# Check all pods are Running
kubectl get pods -n toolhive | grep <release-name>

# Expected output:
# <release-name>-mcp-server-xxx   1/1   Running   0
# <release-name>-proxy-xxx        1/1   Running   0

# Check ingress has an ALB address
kubectl get ingress -n toolhive | grep <release-name>

# Check MCPRemoteProxy and MCPExternalAuthConfig are reconciled
kubectl get mcpremoteproxy,mcpexternalauthconfig -n toolhive | grep <release-name>
```

## Step 6 — Create the DNS record

Get the ALB address from the ingress:

```bash
kubectl get ingress <release-name>-ingress -n toolhive \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

In your DNS provider (Route53 or other), create a **CNAME record**:

```
<your-hostname>  →  <alb-address>.us-east-1.elb.amazonaws.com
```

Wait for DNS propagation (typically 1–5 minutes for Route53).

---

## Step 7 — Register the redirect URI in Azure AD

In the Azure AD app registration, add the callback URL:

```
https://<your-hostname>/oauth/callback
```

**Azure Portal path:** App registrations → your app → Authentication → Add a platform → Web → Redirect URIs

---

## Step 8 — Wait for ALB health check to pass

The ALB performs health checks against the proxy target. It may take **2–3 minutes** after deployment before the target is marked healthy and traffic starts flowing.

```bash
# Watch pod status
kubectl get pods -n toolhive -w | grep <release-name>

# Check proxy logs for startup confirmation
kubectl logs -n toolhive -l app=<release-name>-proxy --tail=20
```

The proxy is ready when you see:
```
Workload started successfully. Press Ctrl+C to stop.
```

---

## Step 9 — Add to MCP client config

Add the server to `~/.claude.json` or the project `.mcp.json`:

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

On first connection the MCP client will show **"not authenticated"**. Select **Authenticate** to open the Azure AD login browser flow. After signing in, the token is stored and future connections are automatic.

---

## Upgrading an existing release

After changing values or templates:

```bash
helm upgrade <release-name> helm/aap-mcp \
  -n toolhive \
  -f helm/aap-mcp/my-values.yaml \
  --set oauth.azure.clientSecret="<client-secret>" \
  --set aap.bearerToken="<aap-token>"
```

---

## Uninstalling

```bash
helm uninstall <release-name> -n toolhive
```

> The shared `toolhive-signing-key` and `toolhive-hmac-key` secrets are NOT deleted by uninstall — they are managed separately.

---