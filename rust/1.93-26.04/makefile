
.DEFAULT_GOAL := help

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'


DOCKER ?= docker
PLATFORMS := amd64 arm64

.test-image.stamp: hack/Dockerfile.sshd-ubuntu-26.04
	@$(foreach arch,$(PLATFORMS), \
		$(DOCKER) build \
			--tag sshd-ubuntu-26.04-$(arch) \
			--file $< \
			--platform linux/$(arch) . ; )
	@touch $@

.PHONY: build-test-image
build-test-image: .test-image.stamp  ## Build test image if Dockerfile changed

.PHONY: build
build: rust_1.93.rock  ## Build rust rock package

.PHONY: FORCE
FORCE:

.rock.stamp: FORCE
	@new=$$(hack/hash_inputs.sh) ; \
		cur=$$(cat $@ 2>/dev/null || true) ; \
		[ "$$new" = "$$cur" ] || echo "$$new" > $@

rust_1.93.rock: .rock.stamp
	rockcraft pack --verbosity=debug --debug
	mv rust_1.93_*.rock rust_1.93.rock

test: rust_1.93.rock .test-image.stamp  ## Run tests
	spread

.PHONY: size
size:  ## Show size of rust_1.93.rock if present
	@if [ -f rust_1.93.rock ]; then \
		du -h rust_1.93.rock | cut -f1; \
	else \
		echo "rust_1.93.rock not built"; \
	fi

.PHONY: clean-test-image
clean-test-image:  ## Remove sshd-ubuntu-26.04 test images
	@$(foreach arch,$(PLATFORMS), \
		$(DOCKER) rmi -f sshd-ubuntu-26.04-$(arch) || true ; )
	rm -f .test-image.stamp

.PHONY: clean
clean:  ## Remove all built artifacts
	rm -f rust_1.93.rock .rock.stamp .test-image.stamp
