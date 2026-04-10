.PHONY: all build dev test test-unit test-integ test-e2e test-e2e-suite bench-e2e lint fmt clean install qa

export PATH := $(HOME)/.cargo/bin:$(PATH)
CARGO := cargo
BINARY := fpp2
INSTALL_DIR := $(HOME)/.cargo/bin
ORIGINAL_FPP := $(CURDIR)/PathPicker/fpp

all: lint test build

build:
	$(CARGO) build --release

dev:
	$(CARGO) build

test: test-unit test-integ test-e2e

test-unit:
	$(CARGO) test --bins --lib

test-integ:
	$(CARGO) test --test '*'

test-e2e: build
	@bash tests/e2e/run_e2e.sh

test-e2e-rust: build
	@bash tests/e2e/run_e2e.sh --rust-only

test-e2e-suite: build
	@test -n "$(SUITE)" || (echo "Usage: make test-e2e-suite SUITE=01_basic_parsing"; exit 1)
	@bash tests/e2e/run_e2e.sh --suite=$(SUITE)

test-e2e-update: build
	@bash tests/e2e/run_e2e.sh --update-snapshots

bench-e2e: build
	@bash tests/e2e/bench_e2e.sh

bench-e2e-rust: build
	@bash tests/e2e/bench_e2e.sh --rust-only

lint:
	$(CARGO) fmt -- --check
	$(CARGO) clippy -- -D warnings

fmt:
	$(CARGO) fmt

clean:
	$(CARGO) clean

install: build
	cp target/release/$(BINARY) $(INSTALL_DIR)/$(BINARY)

# QA: compare original PathPicker and Rust implementation
qa: build
	@echo "=== QA: original vs Rust implementation ==="
	@echo "--- git status style input ---"
	@echo " M src/main.rs\n M src/parse.rs\n?? new_file.txt" | target/release/$(BINARY) --no-file-checks --all --non-interactive -c "echo" > /tmp/fpp_rust_out.txt 2>&1 || true
	@echo " M src/main.rs\n M src/parse.rs\n?? new_file.txt" | $(ORIGINAL_FPP) --no-file-checks --all --non-interactive -c "echo" > /tmp/fpp_py_out.txt 2>&1 || true
	@diff /tmp/fpp_rust_out.txt /tmp/fpp_py_out.txt && echo "PASS: git status" || echo "DIFF: git status"
	@echo "--- grep style input ---"
	@echo "src/main.rs:42: fn main()\nsrc/parse.rs:10: use regex" | target/release/$(BINARY) --no-file-checks --all --non-interactive -c "echo" > /tmp/fpp_rust_out.txt 2>&1 || true
	@echo "src/main.rs:42: fn main()\nsrc/parse.rs:10: use regex" | $(ORIGINAL_FPP) --no-file-checks --all --non-interactive -c "echo" > /tmp/fpp_py_out.txt 2>&1 || true
	@diff /tmp/fpp_rust_out.txt /tmp/fpp_py_out.txt && echo "PASS: grep style" || echo "DIFF: grep style"
	@echo "--- empty input ---"
	@echo "" | target/release/$(BINARY) --non-interactive -c "echo" > /tmp/fpp_rust_out.txt 2>&1 || true
	@echo "" | $(ORIGINAL_FPP) --non-interactive -c "echo" > /tmp/fpp_py_out.txt 2>&1 || true
	@diff /tmp/fpp_rust_out.txt /tmp/fpp_py_out.txt && echo "PASS: empty input" || echo "DIFF: empty input"
	@echo "--- special character paths ---"
	@echo "path/to/file with spaces.txt\npath/to/file-name.rs:100" | target/release/$(BINARY) --no-file-checks --all --non-interactive -c "echo" > /tmp/fpp_rust_out.txt 2>&1 || true
	@echo "path/to/file with spaces.txt\npath/to/file-name.rs:100" | $(ORIGINAL_FPP) --no-file-checks --all --non-interactive -c "echo" > /tmp/fpp_py_out.txt 2>&1 || true
	@diff /tmp/fpp_rust_out.txt /tmp/fpp_py_out.txt && echo "PASS: special paths" || echo "DIFF: special paths"
	@echo "=== QA complete ==="
