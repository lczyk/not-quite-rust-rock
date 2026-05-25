
.DEFAULT_GOAL := help

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'


DOCKER ?= docker
PLATFORMS := amd64 arm64

.PHONY: build-test-image
build-test-image: tests/hack/Dockerfile.sshd-ubuntu-26.04  ## Build test image for sshd-ubuntu-26.04
	@$(foreach arch,$(PLATFORMS), \
		$(DOCKER) build \
			--tag sshd-ubuntu-26.04-$(arch) \
			--file $< \
			--platform linux/$(arch) . ; )

.PHONY: build
build: rust_1.93.rock  ## Build rust rock package

rust_1.93.rock: rockcraft.yaml
	rockcraft clean && rockcraft pack --verbosity=debug --debug
	mv rust_1.93_*.rock rust_1.93.rock

test: rust_1.93.rock  ## Run tests
	spread

.PHONY: size
size:  ## Show size of rust_1.93.rock if present
	@if [ -f rust_1.93.rock ]; then \
		du -h rust_1.93.rock | cut -f1; \
	else \
		echo "rust_1.93.rock not built"; \
	fi

.PHONY: clean
clean:  ## Remove all built images
# 	@$(foreach arch,$(PLATFORMS), \
# 		$(DOCKER) rmi -f sshd-ubuntu-26.04-$(arch) || true ; )
# 	@docker system prune -f
	rm -f rust_1.93.rock
