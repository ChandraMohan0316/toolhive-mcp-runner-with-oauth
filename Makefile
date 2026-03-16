REPO_URL  ?= https://$(GITHUB_OWNER).github.io/$(GITHUB_REPO)
CHARTS_DIR = charts
DIST_DIR   = .cr-release-packages

.PHONY: lint package index clean help

## lint: Run helm lint on all charts (requires helm ≥ 3.10)
lint:
	@for chart in $(CHARTS_DIR)/*/; do \
		echo "==> Linting $$chart"; \
		helm lint "$$chart" \
			--values "$$chart/values-sample.yaml" \
			--set server.bearerToken=dummy \
			--set oauth.azure.clientSecret=dummy \
			--set oauth.azure.tenantId=dummy \
			--set oauth.azure.clientId=dummy \
			--set ingress.host=mcp.example.com \
			--set ingress.certificateArn=arn:aws:acm:us-east-1:000000000000:certificate/dummy; \
	done

## package: Package all charts into $(DIST_DIR)/
package: lint
	@mkdir -p $(DIST_DIR)
	@for chart in $(CHARTS_DIR)/*/; do \
		echo "==> Packaging $$chart"; \
		helm package "$$chart" --destination $(DIST_DIR); \
	done
	@echo "Packaged charts written to $(DIST_DIR)/"

## index: Generate/update index.yaml for the Helm repository (set REPO_URL first)
## Usage: GITHUB_OWNER=<org> GITHUB_REPO=<repo> make index
index: package
	@if [ -z "$(GITHUB_OWNER)" ] || [ -z "$(GITHUB_REPO)" ]; then \
		echo "ERROR: Set GITHUB_OWNER and GITHUB_REPO"; exit 1; \
	fi
	helm repo index $(DIST_DIR) --url $(REPO_URL) --merge index.yaml 2>/dev/null || \
	helm repo index $(DIST_DIR) --url $(REPO_URL)
	cp $(DIST_DIR)/index.yaml index.yaml
	@echo "index.yaml updated. Commit and push to gh-pages branch."

## clean: Remove packaged chart artifacts
clean:
	rm -rf $(DIST_DIR)

## help: Show this help message
help:
	@grep -E '^## ' Makefile | sed 's/## //'
