# Builds priv/gumbo_nif.so — the Gumbo NIF with the vendored gumbo-parser
# library linked in. The vendored sources are compiled from an explicit
# 12-file list copied from c_src/gumbo-parser/meson.build rather than a glob,
# so a file added upstream shows up as an explicit diff here instead of
# silently changing the build.

CC ?= cc
ERL ?= erl

GUMBO_DIR := c_src/gumbo-parser
GUMBO_HEADER := $(GUMBO_DIR)/src/gumbo.h

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

GUMBO_OBJS := $(GUMBO_SRCS:$(GUMBO_DIR)/src/%.c=$(OBJ_DIR)/gumbo-parser/%.o)
NIF_OBJS := $(C_SRCS:c_src/%.c=$(OBJ_DIR)/%.o)
OBJS := $(GUMBO_OBJS) $(NIF_OBJS)

CFLAGS ?= -O2
ALL_CFLAGS := $(CFLAGS) -std=c99 -fPIC -Wall -Wextra \
	-Ic_src -I$(GUMBO_DIR)/src -I$(ERTS_INCLUDE_DIR)

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

$(OBJS): $(GUMBO_HEADER)

$(OBJ_DIR)/gumbo-parser/%.o: $(GUMBO_DIR)/src/%.c
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
	$(CC) $(LDSHARED_FLAGS) -o $@ $(OBJS)

gumbo-fetch:
	rm -rf $(GUMBO_DIR)
	git clone --depth 1 --branch 0.14.1 https://codeberg.org/gumbo-parser/gumbo-parser.git $(GUMBO_DIR)
	rm -rf $(GUMBO_DIR)/.git

clean:
	rm -rf $(OBJ_DIR) $(NIF_SO)

.PHONY: all clean gumbo-fetch
