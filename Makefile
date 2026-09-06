# The whole development loop, so none of it lives only in somebody's shell history.

.DEFAULT_GOAL := help
SWIFT ?= swift

help: ## List the targets
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  \033[1m%-12s\033[0m %s\n", $$1, $$2}'

build: ## Build the library
	$(SWIFT) build

test: ## Run the Swift tests
	$(SWIFT) test

studio: ## Open the macOS workbench — every parameter on a slider, next to the planet
	$(SWIFT) run PlanetStudio

web-studio: ## The same workbench in a browser, rebuilding as you edit
	@echo "Planet Studio  →  http://127.0.0.1:8791"
	@(sleep 1 && open http://127.0.0.1:8791 >/dev/null 2>&1 &) ; cd web && npm run studio

docs: ## Re-render every image the README uses, from the current shader
	$(SWIFT) run PlanetGallery

web: ## Regenerate the WebGL shader from the Metal source
	cd web && npm run generate

web-check: ## Fail if the checked-in WebGL shader has drifted from the Metal source
	cd web && npm run check:source

web-test: ## Run the web renderer's tests
	cd web && npm test

web-accept: ## Compile the shader in real Chrome and assert every planet paints
	cd web && npm run accept

export: ## Re-export the web port's presets and parity fixtures from Swift
	$(SWIFT) run PlanetExport

check: build test web-check web-test ## Everything CI runs
	@echo "ok"

clean: ## Throw away build products
	rm -rf .build web/node_modules

.PHONY: help build test studio web-studio docs web web-check web-test web-accept export check clean
