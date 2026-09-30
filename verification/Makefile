JOBS ?= 4
ROOT := $(abspath ..)
V := $(abspath .)

ACT_REPO := https://github.com/riscv/riscv-arch-test
ACT_COMMIT := 66ab901
SAIL_URL := https://github.com/riscv/sail-riscv/releases/download/0.14.1/sail-riscv-Linux-x86_64.tar.gz
GCC_URL := https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/2026.08.27/riscv64-elf-ubuntu-24.04-gcc.tar.xz

CONFIG := $(V)/config/inferno-rv32imac/test_config.yaml
WORKDIR := $(V)/build
ELFDIR ?= $(WORKDIR)/inferno-rv32imac/elfs
EXTENSIONS ?=
TESTS ?=
TIMEOUT ?= 20000000

export MISE_DATA_DIR := $(WORKDIR)/tools/mise
export MISE_CACHE_DIR := $(WORKDIR)/tools/mise-cache
export MISE_CONFIG_DIR := $(WORKDIR)/tools/mise-config
export MISE_STATE_DIR := $(WORKDIR)/tools/mise-state
export PATH := $(WORKDIR)/tools/bin:$(PATH)

RTL := $(wildcard $(ROOT)/src/core/*.v) $(ROOT)/src/modules/clint.v $(ROOT)/src/modules/plic.v
SIM := $(WORKDIR)/obj/testbench

.PHONY: all setup elfs sim run clean distclean

all: elfs sim run

setup: $(WORKDIR)/riscv-arch-test/.venv $(WORKDIR)/tools/bin/riscv64-unknown-elf-gcc $(WORKDIR)/tools/bin/sail_riscv_sim

$(WORKDIR)/riscv-arch-test:
	git clone $(ACT_REPO) $@
	git -C $@ checkout -q $(ACT_COMMIT)

$(WORKDIR)/tools/bin/mise:
	mkdir -p $(WORKDIR)/tools/bin
	curl -fsSL https://mise.jdx.dev/install.sh | MISE_INSTALL_PATH=$@ sh

$(WORKDIR)/riscv-arch-test/.venv: | $(WORKDIR)/riscv-arch-test $(WORKDIR)/tools/bin/mise
	cd $(WORKDIR)/riscv-arch-test && mise trust .mise.toml && mise install

$(WORKDIR)/tools/bin/sail_riscv_sim:
	mkdir -p $(WORKDIR)/tools
	curl -fsSL $(SAIL_URL) | tar xz -C $(WORKDIR)/tools --strip-components=1

$(WORKDIR)/tools/bin/riscv64-unknown-elf-gcc:
	mkdir -p $(WORKDIR)/tools
	curl -fsSL $(GCC_URL) | tar xJ -C $(WORKDIR)/tools --strip-components=1

elfs: setup
	cd $(WORKDIR)/riscv-arch-test && mise exec -- $(MAKE) CONFIG_FILES=$(CONFIG) WORKDIR=$(WORKDIR) EXTENSIONS=$(EXTENSIONS) JOBS=$(JOBS)

sim: $(SIM)

$(SIM): testbench.sv $(RTL)
	mkdir -p $(WORKDIR)/obj
	verilator -CFLAGS -O2 --binary --timing -Wno-fatal -j $(JOBS) --top-module sim --Mdir $(WORKDIR)/obj -o testbench testbench.sv $(RTL)

run: $(SIM)
	python3 run_tests.py --sim $(SIM) --elfs $(ELFDIR) --jobs $(JOBS) --timeout $(TIMEOUT) --out $(WORKDIR)/results --xfail expected_failures.txt $(TESTS)

clean:
	rm -rf build $(WORKDIR)/results

distclean: clean
	rm -rf work
