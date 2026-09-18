MACOS_DIR := macos
MACOS_TARGETS := generate build release dmg dmg-ci test run reset-onboarding clean open
BUMP_VERSION := $(word 2,$(MAKECMDGOALS))

.PHONY: $(MACOS_TARGETS) bump

$(MACOS_TARGETS):
	$(MAKE) -C $(MACOS_DIR) $@

bump:
	$(MAKE) -C $(MACOS_DIR) bump $(BUMP_VERSION)

ifeq ($(firstword $(MAKECMDGOALS)),bump)
ifneq ($(BUMP_VERSION),)
.PHONY: $(BUMP_VERSION)
$(BUMP_VERSION):
	@:
endif
endif
