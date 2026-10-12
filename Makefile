# Builds priv/gumbo_nif.so — the Gumbo NIF with the vendored gumbo-parser
# library linked in. The vendored sources are compiled from an explicit
# 12-file list copied from c_src/gumbo-parser/meson.build rather than a glob,
# so a file added upstream shows up as an explicit diff here instead of
# silently changing the build.
#
# Those sources are not compiled in place: they are copied to $(GUMBO_SRC_DIR)
# and the patch series under c_src/patches is applied to the copy, because the
# submodule itself has to stay byte-identical to the tag it pins. Everything —
# the vendored objects and our own includes of the vendored internals — builds
# against the copy. See c_src/patches/README.md.

CC ?= cc
ERL ?= erl

GUMBO_DIR := c_src/gumbo-parser
GUMBO_HEADER := $(GUMBO_DIR)/src/gumbo.h
GUMBO_PATCH_DIR := c_src/patches/gumbo-parser
GUMBO_PATCHES := $(sort $(wildcard $(GUMBO_PATCH_DIR)/*.patch))

# Where erl_nif.h lives.
ERTS_INCLUDE_DIR := $(shell $(ERL) -noshell -eval 'io:format("~s/erts-~s/include", [code:root_dir(), erlang:system_info(version)])' -s init stop)

GUMBO_SRCS := \
	$(GUMBO_DIR)/src/attribute.c \
	$(GUMBO_DIR)/src/char_ref.c \
	$(GUMBO_DIR)/src/char_ref_gperf.c \
	$(GUMBO_DIR)/src/error.c \
	$(GUMBO_DIR)/src/parser.c \
	$(GUMBO_DIR)/src/string_buffer.c \
	$(GUMBO_DIR)/src/string_piece.c \
	$(GUMBO_DIR)/src/tag.c \
	$(GUMBO_DIR)/src/tokenizer.c \
	$(GUMBO_DIR)/src/utf8.c \
	$(GUMBO_DIR)/src/util.c \
	$(GUMBO_DIR)/src/vector.c

C_SRCS := $(wildcard c_src/*.c)

PRIV_DIR := priv
OBJ_DIR := $(PRIV_DIR)/obj
NIF_SO := $(PRIV_DIR)/gumbo_nif.so

# The copy the build actually reads, and the stamp that records that it was made
# from the current pin and the current patches. Both live under $(OBJ_DIR),
# which is gitignored, so nothing here can touch what the submodule tracks.
GUMBO_SRC_DIR := $(OBJ_DIR)/gumbo-src
GUMBO_SRC_STAMP := $(GUMBO_SRC_DIR)/.patched
GUMBO_VENDORED := $(wildcard $(GUMBO_DIR)/src/*)

GUMBO_OBJS := $(GUMBO_SRCS:$(GUMBO_DIR)/src/%.c=$(OBJ_DIR)/gumbo-parser/%.o)
NIF_OBJS := $(C_SRCS:c_src/%.c=$(OBJ_DIR)/%.o)
OBJS := $(GUMBO_OBJS) $(NIF_OBJS)

CFLAGS ?= -O2
# -MMD -MP makes the compiler emit one dependency file per object, covering
# our own headers too. Without them, $(OBJS): $(GUMBO_HEADER) below only
# tracked the vendored gumbo.h, so editing c_src/gumbo_handle.h silently
# skipped rebuilds and the link could stitch objects compiled against
# different struct layouts.
ALL_CFLAGS := $(CFLAGS) -std=c99 -fPIC -pthread -Wall -Wextra -MMD -MP \
	-Ic_src -I$(GUMBO_SRC_DIR)/src -I$(ERTS_INCLUDE_DIR)

# The vendored gumbo-parser sources trip -Wunused-parameter and
# -Wsign-compare in several places. They are vendored unpatched by policy,
# so those warnings are unfixable; silence only those two for the vendored
# objects so a warning in our own c_src/*.c still stands out. Our sources
# keep the full $(ALL_CFLAGS) set — do not re-broaden this.
GUMBO_CFLAGS := $(ALL_CFLAGS) -Wno-unused-parameter -Wno-sign-compare

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	LDSHARED_FLAGS := -bundle -flat_namespace -undefined dynamic_lookup
else
	LDSHARED_FLAGS := -shared
endif

all: $(NIF_SO)

# Guard against a missing submodule checkout: fail with the fix instructions
# instead of a confusing compile error about gumbo.h.
$(GUMBO_HEADER):
	@echo "error: vendored gumbo-parser sources are missing ($(GUMBO_HEADER))"
	@echo "Fetch them with one of:"
	@echo "  git submodule update --init --recursive"
	@echo "  make gumbo-fetch"
	@exit 1

$(OBJS): $(GUMBO_SRC_STAMP)

# A submodule bump changes $(GUMBO_VENDORED), and a patch edit changes
# $(GUMBO_PATCHES), so either one rebuilds the copy from scratch rather than
# leaving a tree that mixes patched and unpatched objects. `git apply` needs a
# *relative* --directory and works outside a git repository, which is what a
# build from a tarball, where the submodule is a plain directory, looks like.
$(GUMBO_SRC_STAMP): $(GUMBO_VENDORED) $(GUMBO_PATCHES) | $(GUMBO_HEADER)
	@echo "  vendored: copying $(GUMBO_DIR)/src and applying $(words $(GUMBO_PATCHES)) patch(es)"
	@rm -rf $(GUMBO_SRC_DIR)
	@mkdir -p $(GUMBO_SRC_DIR)
	@cp -R $(GUMBO_DIR)/src $(GUMBO_SRC_DIR)/src
	@for p in $(GUMBO_PATCHES); do \
		git apply -p1 --directory=$(GUMBO_SRC_DIR) "$$p" || { \
			echo "error: $$p does not apply to $(GUMBO_DIR)"; \
			echo "       the pin moved, or the patch needs a rebase: c_src/patches/README.md"; \
			exit 1; \
		}; \
	done
	@touch $@

$(OBJ_DIR)/gumbo-parser/%.o: $(GUMBO_SRC_DIR)/src/%.c $(GUMBO_SRC_STAMP)
	@mkdir -p $(dir $@)
	$(CC) $(GUMBO_CFLAGS) -c -o $@ $<

$(OBJ_DIR)/%.o: c_src/%.c
	@mkdir -p $(dir $@)
	$(CC) $(ALL_CFLAGS) -c -o $@ $<

# The explicit c_src/gumbo_nif.c prerequisite makes a missing NIF source fail
# at build time: OBJS is wildcard-driven, so it cannot detect its own
# emptiness, and a gumbo-only bundle would fail at load time instead.
$(NIF_SO): $(OBJS) c_src/gumbo_nif.c
	@mkdir -p $(PRIV_DIR)
	$(CC) $(LDSHARED_FLAGS) -pthread -o $@ $(OBJS)

# Deterministic teardown probe: parses with a counting allocator, runs the
# destructor's shared teardown pass, and fails unless the allocator balance
# is exactly zero. A second mode is the crash canary: it calls
# gumbo_destroy_output directly — no pass — on a deep document under a
# deliberately small stack and reports whether gumbo's own teardown still
# recurses; a clean survival or a signal death is informational, but a
# canary error exit (parse or allocation failure) fails the build because
# it proves nothing either way.
# The binary lives in priv/obj (gitignored). gumbo_teardown.c is compiled
# explicitly here; it is shared with the NIF, which the wildcard above
# picks up legitimately because the unit has no ERTS dependency.
TEARDOWN_PROBE_SRC := c_src/test/teardown_probe.c
TEARDOWN_PROBE := $(OBJ_DIR)/teardown_probe

$(TEARDOWN_PROBE): $(TEARDOWN_PROBE_SRC) $(GUMBO_OBJS) c_src/gumbo_teardown.c
	@mkdir -p $(dir $@)
	$(CC) $(ALL_CFLAGS) -o $@ $(TEARDOWN_PROBE_SRC) $(GUMBO_OBJS) c_src/gumbo_teardown.c

# A patch that no longer applies must fail the build rather than quietly leave
# the vendored objects unpatched. This runs the same git-apply invocation the
# build does, against a pristine copy, and also asserts the property the copy
# exists to keep: the submodule itself has no tracked modifications.
check-patch: | $(GUMBO_HEADER)
	@rm -rf $(OBJ_DIR)/patch-check
	@mkdir -p $(OBJ_DIR)/patch-check
	@cp -R $(GUMBO_DIR)/src $(OBJ_DIR)/patch-check/src
	@for p in $(GUMBO_PATCHES); do \
		if ! git apply -p1 --directory=$(OBJ_DIR)/patch-check "$$p"; then \
			echo "FAIL: $$p does not apply to the pinned $(GUMBO_DIR)"; \
			exit 1; \
		fi; \
	done
	@rm -rf $(OBJ_DIR)/patch-check
	@if [ -n "$$(git -C $(GUMBO_DIR) status --porcelain --untracked-files=no)" ]; then \
		echo "FAIL: $(GUMBO_DIR) has tracked modifications; patches belong in $(GUMBO_PATCH_DIR)"; \
		git -C $(GUMBO_DIR) status --short; \
		exit 1; \
	fi
	@echo "PASS: $(words $(GUMBO_PATCHES)) patch(es) apply to the pinned $(GUMBO_DIR), which is unmodified"

check-teardown: $(TEARDOWN_PROBE)
	$(TEARDOWN_PROBE) balance
	@echo "--- crash canary: does gumbo's teardown still recurse? ---"
	@( ulimit -s 320; $(TEARDOWN_PROBE) canary 20000 ); \
	  status=$$?; \
	  if [ $$status -eq 0 ]; then \
	    echo "NOTE: teardown survived; gumbo may no longer recurse (the pass stays correct)"; \
	  elif [ $$status -ge 128 ]; then \
	    echo "OK: teardown still recurses, so the teardown pass remains required"; \
	  else \
	    echo "FAIL: canary exited $$status (neither survived nor recursed)"; \
	    exit $$status; \
	  fi

# Pull in the compiler-emitted dependency files: -MMD writes one .d next to
# every object (and the probe's next to its binary), naming the headers each
# translation unit includes, ours as well as the vendored gumbo-parser's.
-include $(OBJS:.o=.d) $(TEARDOWN_PROBE).d

gumbo-fetch:
	rm -rf $(GUMBO_DIR)
	git clone --depth 1 --branch 0.14.1 https://codeberg.org/gumbo-parser/gumbo-parser.git $(GUMBO_DIR)
	rm -rf $(GUMBO_DIR)/.git

# The -MMD dependency files live next to the objects under $(OBJ_DIR) — and
# the probe's next to its binary — so removing the directory removes them.
clean:
	rm -rf $(OBJ_DIR) $(NIF_SO)

.PHONY: all clean gumbo-fetch check-teardown check-patch
