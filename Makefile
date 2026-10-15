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
# elixir_make archives the precompiled NIF out of the app priv — $(MIX_APP_PATH)/priv — while this
# Makefile builds into the source priv, which is where every check-* target, the fault-paths harness
# and the tests expect to find it. So the library is built in the source tree and copied into the app
# priv, which is the only thing the archive step needs.
#
# The copy happens only in the pass that `elixir_make.precompile` runs, and that is not a detail of
# style. Doing it on every build — which is what the first version of this did — made `mix ci`
# segfault on Linux at VM shutdown, reproducibly, while passing on macOS: `mix ci` invokes make
# several times inside one VM, and each of those invocations rewrote a file a live VM had mapped.
# Gating it on CC_PRECOMPILER_CURRENT_TARGET — which cc_precompiler sets for the precompile pass and
# for nothing else — takes it out of every ordinary build's path, so `mix ci`, the check-* targets
# and a developer's `mix compile` never touch the app priv at all. A scratch branch and two bisect
# runs are how that was pinned down, after the precompiler's own configuration had been ruled out.
#
# The copy is best effort on purpose: the archive step fails loudly on its own when the library is
# missing, so nothing is hidden here.
APP_PRIV_DIR := $(if $(MIX_APP_PATH),$(MIX_APP_PATH)/priv,$(PRIV_DIR))
# elixir_make.precompile builds one target after another in this same source tree, so the C objects
# and the patched-source copy have to be told apart by target. Without this, the aarch64 pass would
# link the x86_64 objects the previous pass left behind and the archive would carry a library for the
# wrong architecture with nothing in the log to show for it. cc_precompiler sets
# CC_PRECOMPILER_CURRENT_TARGET for each pass and leaves it unset for ordinary builds, so local work
# and every gate keep using priv/obj exactly as before.
OBJ_DIR := $(PRIV_DIR)/obj$(if $(CC_PRECOMPILER_CURRENT_TARGET),/$(CC_PRECOMPILER_CURRENT_TARGET))

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

# The vendored sources are third-party code, pinned byte for byte to the upstream tag and patched in
# a copy rather than fixed in place: their warnings are not ours to remove, and not ours to read
# either. What they get is -w, and only they get it — the compiles below hand the vendored objects
# this variable while our own c_src/*.c keeps the full $(ALL_CFLAGS) set, which is the property that
# matters: a warning in our code still stands out.
#
# This replaces a list of named suppressions (-Wno-unused-parameter, -Wno-sign-compare,
# -Wno-type-limits, -Wno-old-style-declaration) and a seven-line probe that asked the compiler whether
# it knew the gcc-only one. The list only ever grew, one compiler release at a time, about code nobody
# here can edit; the probe existed so clang would not be handed a flag it rejects. -w ends both, and
# if a future compiler finds something real in the vendored parser, the parity and sanitizer gates
# are where its behaviour is judged anyway.
#
# The two harness builds below compile c_src/test/parity_dump.c in the same command as vendored
# sources, so they get -w too — and lose nothing by it: the same file is compiled with the full set by
# $(PARITY_DUMP_BUILD), so its warnings are reported on every run of check-parity regardless.
GUMBO_CFLAGS := $(ALL_CFLAGS) -w

UNAME_S := $(shell uname -s)
# MINGW and MSYS both mean a Windows toolchain under a POSIX shell — the shape a Windows runner and
# an MSYS2 terminal present — and on Windows the artefact has to be .dll for load_nif/2 to find it.
ifneq (,$(findstring MINGW,$(UNAME_S))$(findstring MSYS,$(UNAME_S)))
	NIF_EXT := .dll
	LDSHARED_FLAGS := -shared
else ifeq ($(UNAME_S),Darwin)
	NIF_EXT := .so
	LDSHARED_FLAGS := -bundle -flat_namespace -undefined dynamic_lookup
else
	NIF_EXT := .so
	LDSHARED_FLAGS := -shared
endif

# NIF_EXT is why this definition sits after the branch above rather than beside PRIV_DIR: `:=`
# expands on the spot, so naming the library earlier would have produced `priv/gumbo_nif` with no
# extension and a NIF that load_nif/2 cannot find. Everything that touches the library — the rules
# below, `make clean`, the gates — goes through NIF_SO and does not care which extension it has.
NIF_SO := $(PRIV_DIR)/gumbo_nif$(NIF_EXT)

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

# The source file is named through $* rather than listed as a prerequisite. Naming
# it as one cannot work: at the moment make plans, the copy does not exist yet and
# nothing generates it file by file — the stamp rule makes the whole tree at once —
# so make cannot see a path from object to source, silently discards this rule, and
# links before compiling any of the twelve. That is exactly what a clean build did
# until it was found by running `make` after `make clean`. The stamp is a normal
# prerequisite, so a new pin or an edited patch rebuilds all twelve, which is what
# the stamp rule does anyway.
$(OBJ_DIR)/gumbo-parser/%.o: $(GUMBO_SRC_STAMP)
	@mkdir -p $(dir $@)
	$(CC) $(GUMBO_CFLAGS) -c -o $@ $(GUMBO_SRC_DIR)/src/$*.c

$(OBJ_DIR)/%.o: c_src/%.c
	@mkdir -p $(dir $@)
	$(CC) $(ALL_CFLAGS) -c -o $@ $<

# The explicit c_src/gumbo_nif.c prerequisite makes a missing NIF source fail
# at build time: OBJS is wildcard-driven, so it cannot detect its own
# emptiness, and a gumbo-only bundle would fail at load time instead.
$(NIF_SO): $(OBJS) c_src/gumbo_nif.c
	@mkdir -p $(PRIV_DIR)
	$(CC) $(LDSHARED_FLAGS) -pthread -o $@ $(OBJS)
	@if [ -n "$(CC_PRECOMPILER_CURRENT_TARGET)" ]; then \
		mkdir -p "$(APP_PRIV_DIR)" 2>/dev/null; \
		cp -f "$@" "$(APP_PRIV_DIR)/.$(notdir $@).tmp" 2>/dev/null && \
			mv -f "$(APP_PRIV_DIR)/.$(notdir $@).tmp" "$(APP_PRIV_DIR)/$(notdir $@)" 2>/dev/null || true; \
	fi

# Teardown-contract probe, in two modes, and both are hard gates now that the walk
# it exercises is our patch rather than upstream's code.
#
#   balance   parse with a counting allocator and require the destructor's own
#             call — gumbo_destroy_output — to free every allocation. Liveness is
#             not reclamation: the first defect this project shipped was a teardown
#             that survived every test and leaked 70% of the tree.
#   canary    the same call on a 20 000-level document under `ulimit -s 320`, a
#             stack the unpatched recursive walk dies on at 8 000 (measured). The
#             probe cannot assert its own survival, so the status handling below
#             does: after c_src/patches/0001 a signal death can only mean the patch
#             is gone. A non-zero error exit (parse or allocation failure) has to be
#             told apart from a death, because it proves nothing either way.
#
# The binary lives in priv/obj (gitignored).
TEARDOWN_PROBE_SRC := c_src/test/teardown_probe.c
TEARDOWN_PROBE := $(OBJ_DIR)/teardown_probe

$(TEARDOWN_PROBE): $(TEARDOWN_PROBE_SRC) $(GUMBO_OBJS)
	@mkdir -p $(dir $@)
	$(CC) $(ALL_CFLAGS) -o $@ $(TEARDOWN_PROBE_SRC) $(GUMBO_OBJS)

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

# A build from an empty object directory is what every fresh clone, every cold CI
# cache and every hex consumer does, and it is the one path a warm tree cannot
# test: the object rule and the -include handling above were both wrong in ways that
# only ever appeared after `make clean`, and neither the suite nor `make` on a warm
# tree could see it. Cleaning the real tree would work but rebuild it and slow every
# gate run, so this builds a throwaway copy of the build inputs in a temp directory
# instead — which also exercises the tarball case, where git apply has no repository
# to work in and the submodule is a plain directory.
check-clean-build: | $(GUMBO_HEADER)
	@tmp=$$(mktemp -d) || exit 1; \
	trap 'rm -rf "$$tmp"' EXIT INT TERM; \
	cp -R Makefile c_src "$$tmp/"; \
	if ! ( cd "$$tmp" && $(MAKE) --no-print-directory all > build.log 2>&1 ); then \
		echo "FAIL: a build from an empty object dir does not work"; \
		tail -20 "$$tmp/build.log"; \
		exit 1; \
	fi; \
	test -f "$$tmp/priv/gumbo_nif.so" || { echo "FAIL: no shared object was produced"; exit 1; }; \
	test "$$(ls "$$tmp"/priv/obj/gumbo-parser/*.o | wc -l | tr -d ' ')" = "12" || { \
		echo "FAIL: a clean build did not compile all twelve vendored objects"; \
		exit 1; \
	}; \
	echo "PASS: a build from an empty object dir compiles all twelve and links"

# Differential harness: the patches change how the parser decides what to build,
# and a scope query or an is-open answer that is off by one does not crash or leak
# — it silently produces a different tree, which is the one kind of mistake the
# suite's shape matrix cannot see. Both parsers export the same symbols, so they
# are linked into separate binaries and compared stream by stream over a corpus
# this same program generates from a seed: the only variable is the parser.
#
#   pinned   compiled against the submodule's own sources, i.e. exactly what the
#            tag pins, with -I ahead of the patched copy so no header leaks in
#   build    the shipped objects, patches and all
#
# The corpus keeps documents a few thousand tokens deep on purpose (the patched
# hot spots are functions of the open-element stack) but well inside the 8 MB
# main-thread stack, since the pinned parser still recurses once per level when
# it frees the tree.
PARITY_DUMP_SRC := c_src/test/parity_dump.c
PARITY_DUMP_PINNED := $(OBJ_DIR)/parity_dump_pinned
PARITY_DUMP_BUILD := $(OBJ_DIR)/parity_dump_build
PARITY_COUNT ?= 1000

$(PARITY_DUMP_PINNED): $(PARITY_DUMP_SRC) $(GUMBO_SRCS) | $(GUMBO_HEADER)
	@mkdir -p $(dir $@)
	$(CC) -I$(GUMBO_DIR)/src $(GUMBO_CFLAGS) -o $@ $(PARITY_DUMP_SRC) $(GUMBO_SRCS)

$(PARITY_DUMP_BUILD): $(PARITY_DUMP_SRC) $(GUMBO_OBJS)
	@mkdir -p $(dir $@)
	$(CC) $(ALL_CFLAGS) -o $@ $(PARITY_DUMP_SRC) $(GUMBO_OBJS)

# 0007 is the first patch that changes tree construction on purpose, so the parity claim
# is made in two steps rather than one: the pin plus that one patch has to parse the whole
# corpus identically to the shipped build — which is what still catches any of the other
# patches moving a tree — and the pin alone may differ only in the documents whose tree
# holds a select element, which is what bounds 0007's blast radius. The corpus keeps the
# select shapes f57a7e9 added for the scope queries.
#
# The baseline copies the pin and applies that one patch to it, the way the build's copy
# applies the whole series in file-name order, and it compiles against the pin's own
# headers because that is the tree the patch is written against.
BEHAVIOUR_PATCH := $(GUMBO_PATCH_DIR)/0007-select-in-scope.patch
GUMBO_BASELINE_SRC_DIR := $(OBJ_DIR)/gumbo-src-baseline
GUMBO_BASELINE_STAMP := $(GUMBO_BASELINE_SRC_DIR)/.patched
GUMBO_BASELINE_OBJ_DIR := $(OBJ_DIR)/gumbo-parser-baseline
GUMBO_BASELINE_OBJS := $(patsubst $(GUMBO_DIR)/src/%.c,$(GUMBO_BASELINE_OBJ_DIR)/%.o,$(GUMBO_SRCS))
PARITY_DUMP_BASELINE := $(OBJ_DIR)/parity_dump_baseline

$(GUMBO_BASELINE_STAMP): $(GUMBO_VENDORED) $(BEHAVIOUR_PATCH) | $(GUMBO_HEADER)
	@echo "  vendored: copying $(GUMBO_DIR)/src and applying $(notdir $(BEHAVIOUR_PATCH))"
	@rm -rf $(GUMBO_BASELINE_SRC_DIR)
	@mkdir -p $(GUMBO_BASELINE_SRC_DIR)
	@cp -R $(GUMBO_DIR)/src $(GUMBO_BASELINE_SRC_DIR)/src
	@git apply -p1 --directory=$(GUMBO_BASELINE_SRC_DIR) "$(BEHAVIOUR_PATCH)" || { \
		echo "error: $(notdir $(BEHAVIOUR_PATCH)) does not apply to the pin on its own"; \
		echo "       it is written against the pinned tree: c_src/patches/README.md"; \
		exit 1; \
	}
	@touch $@

$(GUMBO_BASELINE_OBJ_DIR)/%.o: $(GUMBO_BASELINE_STAMP)
	@mkdir -p $(dir $@)
	$(CC) $(ALL_CFLAGS) -w -I$(GUMBO_BASELINE_SRC_DIR)/src -c -o $@ $(GUMBO_BASELINE_SRC_DIR)/src/$*.c

$(PARITY_DUMP_BASELINE): $(PARITY_DUMP_SRC) $(GUMBO_BASELINE_OBJS) | $(GUMBO_HEADER)
	@mkdir -p $(dir $@)
	$(CC) -I$(GUMBO_BASELINE_SRC_DIR)/src -I$(GUMBO_DIR)/src $(GUMBO_CFLAGS) -o $@ $(PARITY_DUMP_SRC) $(GUMBO_BASELINE_OBJS)

check-parity: $(PARITY_DUMP_PINNED) $(PARITY_DUMP_BASELINE) $(PARITY_DUMP_BUILD)
	@docs=$$(mktemp); pinned=$$(mktemp); baseline=$$(mktemp); build=$$(mktemp); \
	split=$$(mktemp -d); \
	trap 'rm -f "$$docs" "$$pinned" "$$baseline" "$$build"; rm -rf "$$split"' EXIT INT TERM; \
	$(PARITY_DUMP_BUILD) corpus $(PARITY_COUNT) > "$$docs" || exit 1; \
	$(PARITY_DUMP_PINNED) dump < "$$docs" > "$$pinned" || exit 1; \
	$(PARITY_DUMP_BASELINE) dump < "$$docs" > "$$baseline" || exit 1; \
	$(PARITY_DUMP_BUILD) dump < "$$docs" > "$$build" || exit 1; \
	if ! cmp -s "$$baseline" "$$build"; then \
		echo "FAIL: a patch other than $(notdir $(BEHAVIOUR_PATCH)) changes tree construction; first divergence:"; \
		diff "$$baseline" "$$build" | head -20; \
		exit 1; \
	fi; \
	if cmp -s "$$pinned" "$$baseline"; then \
		echo "FAIL: $(notdir $(BEHAVIOUR_PATCH)) changed no tree, so nothing here covers it"; \
		exit 1; \
	fi; \
	mkdir -p "$$split/pin" "$$split/base"; \
	for side in pin base; do \
		src="$$pinned"; [ "$$side" = base ] && src="$$baseline"; \
		awk -v out="$$split/$$side" '/^=== document /{ n = $$3 + 0; next } { print > (out "/" n) }' "$$src" || exit 1; \
	done; \
	changed=0; failed=0; \
	for f in "$$split/pin"/*; do \
		i=$$(basename "$$f"); \
		cmp -s "$$f" "$$split/base/$$i" && continue; \
		changed=$$((changed + 1)); \
		grep -q 'tag=112,' "$$f" && continue; \
		failed=1; \
		echo "FAIL: document $$i differs but holds no select element, so $(notdir $(BEHAVIOUR_PATCH)) is not what moved it:"; \
		diff "$$split/base/$$i" "$$f" | head -20; \
	done; \
	[ $$failed -eq 0 ] || exit 1; \
	echo "PASS: $(PARITY_COUNT) documents parse to identical trees with the pin plus $(notdir $(BEHAVIOUR_PATCH)) and with the shipped build, and the pin alone differs only in the $$changed that hold a select"

# The sanitizer gate. It is the only net there is for a memory-safety bug inside
# gumbo itself — residual 2 of the list this project keeps of what could still take
# the VM down — and it is also how the fourth patch's missing initialisation was
# found: the builds without ASan happened to get zeroed pages for the tokenizer
# state, and ASan fills fresh bytes with a pattern instead, which turned a latent
# garbage pointer into an assertion failure.
#
# It builds the standalone harness against the patched sources with
# AddressSanitizer and UndefinedBehaviorSanitizer and runs both the seeded corpus and
# the adversarial shapes through it. `-fno-sanitize-recover=all` makes a finding a
# non-zero exit rather than a report that scrolls past. It does not cover our own
# erl_nif_* plumbing, which cannot be sanitised without instrumenting the VM itself.
#
# The shapes run at a modest depth on the calling thread on purpose: the sanitizers
# enlarge stack frames, and this gate is about memory safety, not about the stack
# cliff that check-teardown and the parse budget cover.
SAN_HARNESS := $(OBJ_DIR)/parity_san
SAN_DEPTH ?= 20000
SAN_SHAPES := div-frameset span-frameset template-frameset table-frameset \
	div-unclosed div-pclose formatting attrs selectedcontent soup

$(SAN_HARNESS): $(PARITY_DUMP_SRC) $(GUMBO_SRC_STAMP) | $(GUMBO_HEADER)
	@mkdir -p $(dir $@)
	$(CC) -O1 -g -std=c99 -fno-omit-frame-pointer -fsanitize=address,undefined \
		-fno-sanitize-recover=all $(GUMBO_CFLAGS) -I$(GUMBO_SRC_DIR)/src \
		-o $@ $(PARITY_DUMP_SRC) $(GUMBO_SRC_DIR)/src/*.c

check-sanitizers: $(SAN_HARNESS)
	@$(SAN_HARNESS) corpus 500 | $(SAN_HARNESS) dump > /dev/null || { \
		echo "FAIL: the sanitizers found something while parsing the corpus"; exit 1; \
	}
	@for shape in $(SAN_SHAPES); do \
		$(SAN_HARNESS) shapes "$$shape" $(SAN_DEPTH) > /dev/null || { \
			echo "FAIL: the sanitizers found something in shape $$shape"; exit 1; \
		}; \
	done
	@echo "PASS: AddressSanitizer and UndefinedBehaviorSanitizer clean on 500 corpus documents and $(words $(SAN_SHAPES)) adversarial shapes at $(SAN_DEPTH)"

# The stack guard is the backstop for the recursion nobody has found: a depth-proportional
# walk whose frame size is unknown cannot be ruled out by arithmetic, so the parse is told
# how much stack it has and stops before it runs out.
#
# What it cannot be tested against any more is a deep *document*, and that is the point:
# with destroy_node iterative and the tree builder using an explicit stack, no document
# makes the C stack grow with its nesting depth, so a 200 000-level shape parses under any
# budget (second case below, which is the control). What is testable is the mechanism, and
# that is what the first case does: a budget smaller than a single frame's worth of parsing
# has to stop the parse, report it, and tear the tree down without crashing.
check-stack-guard: $(PARITY_DUMP_BUILD)
	@$(PARITY_DUMP_BUILD) shapes soup 100 256 > guard.log 2>&1 || { \
		echo "FAIL: a budget too small to parse under did not refuse cleanly"; \
		cat guard.log; rm -f guard.log; exit 1; \
	}
	@grep -q 'too_deep=yes' guard.log || { \
		echo "FAIL: the stack guard did not fire on a budget smaller than one frame"; \
		cat guard.log; rm -f guard.log; exit 1; \
	}
	@$(PARITY_DUMP_BUILD) shapes div-unclosed 200000 > deep.log 2>&1 || { \
		echo "FAIL: a 200 000-level document did not parse without a budget"; \
		cat deep.log; rm -f deep.log; exit 1; \
	}
	@grep -q 'too_deep=no' deep.log || { \
		echo "FAIL: a document that needs no depth recursion reported the guard"; \
		cat deep.log; rm -f deep.log; exit 1; \
	}
	@rm -f guard.log deep.log
	@echo "PASS: the stack guard refuses past its budget, and a 200 000-level document needs no depth recursion to parse"

# Static analysis of our own C, which is the one net there is for the enif_* misuse class:
# a NIF that mishandles a term or an env takes the VM down with it, and AddressSanitizer
# cannot reach it, because instrumenting our NIF means instrumenting the VM. The analyzer
# reads the ERTS headers and does not need to link, so it can. It is also the net that
# covers the C that is newest and least exercised — ours.
#
# The canary next to the probe is a deliberate use-after-free and the gate requires the
# analyzer to report it: on its own, "the analyzer said nothing about our code" cannot be
# told apart from "the analyzer said nothing", and this project has already shipped one
# guard that could never fire. ANALYZER is a variable so a machine whose clang is named
# something else can say so once rather than editing the target.
ANALYZER ?= $(call find_tool,clang)
ANALYZER_CANARY := c_src/test/analyzer_canary.c
ANALYZER_SRCS := $(wildcard c_src/*.c)

check-analyzer: $(GUMBO_SRC_STAMP)
	@command -v $(ANALYZER) > /dev/null || { \
		echo "FAIL: $(ANALYZER) is not installed, and the analyzer is the only net for our own C"; \
		echo "      set ANALYZER=... to a compiler that can --analyze"; \
		exit 1; \
	}
	@for f in $(ANALYZER_SRCS); do \
		out=$$($(ANALYZER) --analyze -std=c99 -Ic_src -I$(GUMBO_SRC_DIR)/src \
			-I$(ERTS_INCLUDE_DIR) "$$f" -o /dev/null 2>&1); \
		if echo "$$out" | grep -q 'warning:'; then \
			echo "FAIL: the analyzer has something to say about $$f"; \
			echo "$$out" | grep 'warning:' | head -10; \
			exit 1; \
		fi; \
	done
	@$(ANALYZER) --analyze -std=c99 $(ANALYZER_CANARY) -o /dev/null 2>&1 \
		| grep -q 'warning:' \
		|| { echo "FAIL: the analyzer found nothing in its own canary, so it proves nothing"; exit 1; }
	@echo "PASS: $(words $(ANALYZER_SRCS)) of our C files are clean under the analyzer, and it still reports its canary"

# The C that this repository owns is formatted the way the C it patches is formatted:
# Google's style, which is what gumbo is written in, so a patch and the file it patches read
# the same way. Only our own files are listed — the vendored copy is pinned, and reformatting
# it would break every patch and the differential harness with it.
#
# clang-format ships inside Xcode's toolchain on macOS and with the clang packages elsewhere,
# hence the fallback: no PATH edits are needed to run this, and a machine with neither gets a
# message instead of a silent pass.
C_FORMAT_FILES := $(wildcard c_src/*.c c_src/*.h c_src/test/*.c)
# mise is where this project declares its toolchain (.mise.toml), and a tool mise manages is on
# PATH only in a mise-activated shell. These gates ask PATH first and mise second, so they behave
# the same whether or not whoever ran them activated it: `make check-c-format` and `mix ci` both
# work from a plain shell.
find_tool = $(shell command -v $(1) > /dev/null 2>&1 && echo $(1) || echo mise exec -- $(1))
CLANG_FORMAT ?= $(call find_tool,clang-format)
CLANG_TIDY ?= $(call find_tool,clang-tidy)

check-c-format:
	@command -v $(word 1,$(CLANG_FORMAT)) > /dev/null 2>&1 || { \
		echo "FAIL: $(CLANG_FORMAT) is not available, so the C style cannot be checked"; \
		exit 1; \
	}
	@for f in $(C_FORMAT_FILES); do \
		$(CLANG_FORMAT) --style=file --dry-run -Werror "$$f" 2>/dev/null \
			|| { echo "FAIL: $$f is not clang-formatted (.clang-format)"; exit 1; }; \
	done
	@echo "PASS: $(words $(C_FORMAT_FILES)) of our C files match .clang-format"

# Warnings as errors on our own C, plus the classes -Wall -Wextra leaves out that matter for
# this code: implicit conversions between signed and unsigned (the ERTS API hands out ints
# where sizes and enum bits are expected), prototype mismatches, and the conversions the
# compiler otherwise takes on our behalf. The vendored files keep their own, narrower set —
# they are not ours to clean, and GUMBO_CFLAGS says so.
C_LINT_WARNINGS := -Wall -Wextra -Werror -Wshadow -Wconversion -Wcast-qual \
	-Wpointer-arith -Wstrict-prototypes -Wmissing-prototypes -Wundef \
	-Wwrite-strings -Wvla -Wdouble-promotion -Wnull-dereference -Wformat=2

check-c-lint: $(GUMBO_SRC_STAMP)
	@for f in $(wildcard c_src/*.c c_src/test/*.c); do \
		$(CC) -fsyntax-only -std=c99 -Ic_src -I$(GUMBO_SRC_DIR)/src \
			-I$(ERTS_INCLUDE_DIR) $(C_LINT_WARNINGS) "$$f" \
			|| { echo "FAIL: $$f does not pass the lint warning set"; exit 1; }; \
	done
	@echo "PASS: $(words $(wildcard c_src/*.c c_src/test/*.c)) of our C files are clean under $(words $(C_LINT_WARNINGS)) warning classes"

# clang-tidy, with the vendored sources and the ERTS headers passed as system headers so that
# findings are attributed to our code and not to theirs — which is where the first run's 125
# signed-bitwise reports came from, all of them inside gumbo.h. The checks are chosen in
# .clang-tidy; the canary is excluded here rather than there, because the deliberate
# use-after-free it contains is exactly what clang-analyzer-unix.Malloc reports, and it is there to
# be reported by the analyzer gate rather than to pass this one.
C_TIDY_SRCS := $(filter-out c_src/test/analyzer_canary.c, $(wildcard c_src/*.c c_src/test/*.c))

# cert-err33-c is on for everything that ships, and off for the two harness programs under
# c_src/test: they print diagnostics to stderr, where the return value of a fprintf has no action to
# take and no caller to inform. The check stays on for every file whose disregard of a return could
# hide something a caller would have wanted to know. It is what found the defect this work exists for.
# The precondition of the crash this work removed: a failure is returned, never stored. A value that
# stands for a failure and travels into a map or a list is read back as a number at best (measured:
# 42) and crashes the emulator's collector at worst (measured: a bare 1, exit 139). Two shapes would
# let one in, and neither exists here now. Both were real: the first is the convention the extractors
# used before they were converted, and the second is what a transform of mine produced at three sites.
check-failure-returns:
	@fail=0; \
	if grep -REn 'enif_make_badarg' c_src/*.c | grep -v 'return enif_make_badarg'; then \
		echo "FAIL: the enif_make_badarg above is not returned; a failure may not be stored or passed"; \
		fail=1; \
	fi; \
	if grep -REn '\*out = [0-9]' c_src/*.c; then \
		echo "FAIL: a numeric literal is stored where a term is expected above; a bare integer is not a term"; \
		fail=1; \
	fi; \
	if grep -REn 'ERL_NIF_TERM [a-z_]+ = [0-9]' c_src/*.c; then \
		echo "FAIL: a numeric literal initializes a term above; a bare integer is not a term"; \
		fail=1; \
	fi; \
	[ $$fail -eq 0 ] || exit 1; \
	echo "PASS: every failure is returned rather than stored, and no literal is used as a term"

check-generators:
	@mix gumbo.patches --check

check-c-tidy: $(GUMBO_SRC_STAMP)
	@command -v $(word 1,$(CLANG_TIDY)) > /dev/null 2>&1 || { \
		echo "FAIL: clang-tidy is not available (mise manages it: mise trust && mise install)"; \
		exit 1; \
	}
	@for f in $(C_TIDY_SRCS); do \
		extra=; \
		case "$$f" in \
			c_src/test/*) \
				extra="--checks=-cert-err33-c"; \
				;; \
		esac; \
		$(CLANG_TIDY) --warnings-as-errors='*' "$$f" $$extra -- -std=c99 -Ic_src -isystem $(GUMBO_SRC_DIR)/src \
			-isystem $(ERTS_INCLUDE_DIR) \
			|| { echo "FAIL: clang-tidy has something to say about $$f"; exit 1; }; \
	done
	@echo "PASS: $(words $(C_TIDY_SRCS)) of our C files are clean under the checks in .clang-tidy"

# The allocation-failure paths are reached only when an allocation fails, which no test can cause,
# so this builds the NIF with the hook compiled in, runs the sweep, and rebuilds it clean. The hook
# is inert without -DGUMBO_TEST_FAULTS, so the rebuilt library is the one that ships.
check-fault-paths: FAULT_FILE := $(CURDIR)/priv/.gumbo-fault-at

# The harness owns its own build and says so: c_src/test/fault-paths.sh builds the library twice and
# runs the sweep twice, because a green sweep only means something once it has been shown failing on
# a swallow caused on purpose. Nothing about it is silent, and the shipping library is put back
# however it ends, including on failure.
check-fault-paths:
	@c_src/test/fault-paths.sh "$(FAULT_FILE)"

check-teardown: $(TEARDOWN_PROBE)
	$(TEARDOWN_PROBE) balance
	@echo "--- crash canary: is the patched teardown still non-recursive? ---"
	@( ulimit -s 320; $(TEARDOWN_PROBE) canary 20000 ); \
	  status=$$?; \
	  if [ $$status -eq 0 ]; then \
	    echo "PASS: teardown survived 20000 levels on a 320 KB stack"; \
	  elif [ $$status -ge 128 ]; then \
	    echo "FAIL: teardown recursed (signal $$status); is c_src/patches applied?"; \
	    exit 1; \
	  else \
	    echo "FAIL: canary exited $$status (neither survived nor recursed)"; \
	    exit $$status; \
	  fi

# Pull in the compiler-emitted dependency files: -MMD writes one .d next to
# every object (and the probe's next to its binary), naming the headers each
# translation unit includes, ours as well as the vendored gumbo-parser's.
#
# The empty rule is not decoration. -include on a file that does not exist yet (a
# clean build) makes make look for a rule to produce it, and it finds GNU make's
# built-in `%: %.o` — "to build X, link X.o" — which chains into the pattern rule
# above with a stem of `vector.d` and tries to compile a source file called
# `vector.d.c`. It only became reachable when the pattern rule stopped naming its
# source as a prerequisite: a prerequisite make cannot make is one it quietly
# gives up on, which is why the missing include used to be silent instead of
# noisy. Saying "a .d is produced as a side effect of compiling, do not build it"
# keeps both the silence and, unlike the old behaviour, a correct object rule.
-include $(OBJS:.o=.d) $(TEARDOWN_PROBE).d

$(OBJS:.o=.d) $(TEARDOWN_PROBE).d: ;

gumbo-fetch:
	rm -rf $(GUMBO_DIR)
	git clone --depth 1 --branch 0.14.1 https://codeberg.org/gumbo-parser/gumbo-parser.git $(GUMBO_DIR)
	rm -rf $(GUMBO_DIR)/.git

# The -MMD dependency files live next to the objects under $(OBJ_DIR) — and
# the probe's next to its binary — so removing the directory removes them.
clean:
	rm -rf $(OBJ_DIR) $(NIF_SO)

.PHONY: all clean gumbo-fetch check-teardown check-patch check-clean-build check-parity check-sanitizers check-stack-guard check-analyzer check-c-format check-c-lint check-c-tidy check-fault-paths check-failure-returns check-generators
