#      @ SUDOLESS SRL <contact@sudoless.org>
#      This Source Code Form is subject to the
#      terms of the Mozilla Public License, v.
#      2.0. If a copy of the MPL was not
#      distributed with this file, You can
#      obtain one at
#      http://mozilla.org/MPL/2.0/.

MAKEFILE_VERSION = v0.0.1


# PATH
export PATH := $(abspath bin/):${PATH}

# META
PROJECT := $(shell go list -m -mod=readonly)
PROJECT_NAME := $(notdir $(PROJECT))

# META - FMT
FMT_MISC = \033[90;1m
FMT_INFO = \033[94;1m
FMT_OK   = \033[92;1m
FMT_WARN = \033[33;1m
FMT_END  = \033[0m
FMT_PRFX = $(FMT_MISC)=>$(FMT_END)

# GO
export CGO_ENABLED ?= 0
GO ?= GO111MODULE=on go
GO_TAGS ?= timetzdata

# OUTPUT
DIR_OUT   := out
FILE_COV  := $(DIR_OUT)/cover.out

# BUILD
BUILD_HASH ?= $(shell git rev-parse --short HEAD 2>/dev/null)
BUILD_VERSION ?= $(shell git describe --tags --exact-match 2>/dev/null || git symbolic-ref -q --short HEAD)
BUILD_TIME ?= $$(date +%s)

# SOURCE
SOURCE_FILES?=$$(find . -name '*.go' | grep -v pb.go | grep -v vendor)


# DEV - EXTERNAL TOOLS
DEV_EXTERNAL_TOOLS=\
	github.com/golangci/golangci-lint/cmd/golangci-lint@v1.39.0 \
	github.com/securego/gosec/v2/cmd/gosec@v2.7.0 \
	github.com/client9/misspell/cmd/misspell@v0.3.4 \
	github.com/fzipp/gocyclo/cmd/gocyclo@v0.3.1 \
	github.com/jstemmer/go-junit-report@v0.9.1 \
	go install golang.org/x/tools/go/analysis/passes/fieldalignment/cmd/fieldalignment@latest@v0.1.0 \
	go get mvdan.cc/gofumpt@v0.1.1 \
	gotest.tools/gotestsum@1.6.4


all: clean align spelling check lint test


.PHONY: run-%
run-%: build-% ## run the specified target
	@printf "$(FMT_PRFX) running $(FMT_INFO)$*$(FMT_END) from $(FMT_INFO)$(DIR_OUT)/dist/$*_$$(go env GOOS)_$$(go env GOARCH)$(FMT_END)\n"
	@$(DIR_OUT)/dist/$*_$$(go env GOOS)_$$(go env GOARCH)

.PHONY: build-%
build-%: ## build a specific cmd/$(TARGET)/... into $(DIR_OUT)/dist/$(TARGET)...
	@printf "$(FMT_PRFX) building $(FMT_INFO)$*$(FMT_END) version=$(FMT_INFO)$(BUILD_VERSION)$(FMT_END) buildhash=$(FMT_INFO)$(BUILD_HASH)$(FMT_END)\n"
	@$(GO) build -trimpath -tags "$(GO_TAGS)" \
		-ldflags="-w -s \
			-X main._serviceName=$*           \
			-X main._version=$(BUILD_VERSION) \
			-X main._buildTime=$(BUILD_TIME)  \
			-X main._buildHash=$(BUILD_HASH)" \
		-o $(DIR_OUT)/dist/$*_$$(go env GOOS)_$$(go env GOARCH) \
		./cmd/$*/...
	@printf "$(FMT_PRFX) built binary $(FMT_INFO)$(DIR_OUT)/dist/$*_$$(go env GOOS)_$$(go env GOARCH)$(FMT_END)\n"

.PHONY: clean
clean: ## remove build time generated files
	@printf "$(FMT_PRFX) removing output directory\n"
	@rm -rf $(DIR_OUT)/

.PHONY: purge
purge: clean ## remove everything that could cause environment issues
	@printf "$(FMT_PRFX) deleting system32\n"
	$(GO) clean -cache
	$(GO) clean -testcache
	$(GO) clean -modcache

$(DIR_OUT):
	@mkdir -p $(DIR_OUT)

.PHONY: test
test: export CGO_ENABLED=1
test: $(DIR_OUT) ## run unit tests
	@printf "$(FMT_PRFX) running tests\n"
	@gotestsum \
		--junitfile $(FILE_COV).xml \
		--format short -- \
		-race \
		-timeout=30s -parallel=20 -failfast \
		-covermode=atomic -coverpkg=./... -coverprofile=$(FILE_COV).txt \
		./...

.PHONY: test-deps
test-deps: ## run tests with dependencies
	@printf "$(FMT_PRFX) running all tests\n"
	$(GO) test all

.PHONY: bench
bench: ## run benchmarks
	@printf "$(FMT_PRFX) running benchmarks\n"
	$(GO) test -exclude-dir=vendor -exclude-dir=.cache -bench=. -benchmem -benchtime=10s ./...

.PHONY: cover
cover: ## open coverage file in browser
	@printf "$(FMT_PRFX) opening coverage file in browser\n"
	$(GO) tool cover -html=$(FILE_COV).txt

.PHONY: tidy
tidy: ## tidy and verify go modules
	@printf "$(FMT_PRFX) tidying go modules\n"
	$(GO) mod tidy
	$(GO) mod verify

.PHONY: download
download: ## download go modules
	@printf "$(FMT_PRFX) downloading dependencies as modules\n"
	$(GO) mod $(GO_MOD) download -x

.PHONY: vendor
vendor: ## tidy, vendor and verify dependencies
	@printf "$(FMT_PRFX) downloading and creating vendor dependencies\n"
	$(GO) mod tidy -v
	$(GO) mod vendor -v
	$(GO) mod verify

.PHONY: updates
updates: ## display outdated direct dependencies
	@printf "$(FMT_PRFX) checking for direct dependencies updates\n"
	@$(GO) list -u -m -mod=readonly -json all | go-mod-outdated -direct

.PHONY: lint
lint: ## run golangci linter
	@printf "$(FMT_PRFX) running golangci-lint\n"
	@golangci-lint run -v --timeout 10m --skip-dirs=".cache/|vendor/|scripts/|docs/|deployment/"  ./...

.PHONY: check
check: ## run cyclic, security, performance, etc checks
	@printf "$(FMT_PRFX) running cyclic analysis\n"
	@gocyclo -over 16 -ignore ".cache/|vendor/|scripts/|docs/|deployment/" .
	@printf "$(FMT_PRFX) running static security analysis\n"
	@gosec -tests -fmt=json -quiet -exclude-dir=vendor -exclude-dir=.cache -exclude-dir=scripts -exclude-dir=docs -exclude-dir=deployment ./...

.PHONY: align
align: ## align struct fields to use less memory
	@printf "$(FMT_PRFX) checking struct field memory alignment\n"
	@$(GO) list -f '{{.Dir}}' ./... | grep -v /vendor/ | \
		xargs fieldalignment ; if [[ $$? -eq 1 ]]; then  \
			printf "$(FMT_PRFX) $(FMT_WARN)unaligned struct fields detected$(FMT_END), check above output\n"; \
			printf "$(FMT_PRFX) to auto-fix run $(FMT_INFO)make align-fix$(FMT_END)\n"; \
		fi
		@printf "$(FMT_PRFX) $(FMT_OK)ok$(FMT_END)\n"; \

.PHONY: align-fix
align-fix: ## autofix misaligned struct fields
		@printf "$(FMT_PRFX) fixing struct field memory alignment\n"
		@$(GO) list -f '{{.Dir}}' ./... | grep -v /vendor/ | xargs fieldalignment -fix || exit 0;
		@printf "$(FMT_PRFX) aligned above files\n"
		@printf "$(FMT_PRFX) re-running $(FMT_INFO)make align$(FMT_END) to check for stragglers\n"
		@make align

.PHONY: fmt
fmt: ## format source files using gofumpt and goimports
	@printf "$(FMT_PRFX) formatting go files\n"
	@gofumpt -w $(SOURCE_FILES)
	@goimports -local gitlab.com/sudoless -w $(SOURCE_FILES)

.PHONY: spelling
spelling: ## run misspell check
	@printf "$(FMT_PRFX) checking for spelling errors\n"
	@misspell -error pkg/
	@misspell -error cmd/

.PHONY: dev-deps
dev-deps: ## pull developer/ci dependencies
	@printf "$(FMT_PRFX) pulling development/CI dependencies\n"
	@for tool in  $(DEV_EXTERNAL_TOOLS) ; do \
		printf "$(FMT_PRFX) installing/updating: $(FMT_INFO)$$tool$(FMT_END)\n" ; \
		$(GO) install $$tool; \
	done

.PHONY: help
help:
	@grep -h -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: mk-update
mk-update: ## update this Makefile
	true
