/* Differential harness for the patches in c_src/patches/.
 *
 * The patches change how the parser decides what to build, in the one place
 * where a mistake is invisible: a scope query or an "is this node still open"
 * answer that is off by one does not crash, does not leak, and does not trip any
 * assertion in the suite's shape matrix — it silently produces a different tree.
 * So the net is a differential one: the same corpus is parsed by the pinned
 * parser and by the patched one, and the two trees are compared node by node.
 *
 * Both parsers are linked into separate binaries because they export the same
 * symbols; nothing clever is needed beyond running each once per document and
 * diffing the streams. The corpus generator lives here too, seeded, so both
 * binaries see byte-identical input — the only variable is the parser.
 *
 * Modes:
 *   parity_dump corpus [count]   write `count` length-prefixed documents
 *   parity_dump dump             read length-prefixed documents, write
 *                                length-prefixed canonical dumps
 *
 * The dump is deliberately canonical rather than pretty: preorder, with node
 * type, tag name, namespaces, attributes in document order, text bytes, and then
 * a summary of the error vector (type, position, line, column). Error *messages*
 * and tag stacks are excluded on purpose — one of the patches caps how much of
 * the open-element stack an error keeps, which is a documented change and would
 * otherwise swamp a comparison that is about tree construction.
 *
 * Depth is kept to a few thousand tokens: the pinned parser still recurses
 * once per level on teardown, and this program runs on the main thread's 8 MB
 * stack (a few thousand levels is ~100 KB of frames).
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gumbo.h"
#include "error.h" /* GumboError, for the error summary: internal, like the NIF */

/* ---- corpus ------------------------------------------------------------ */

/* xorshift32, so a seed reproduces a corpus exactly on any machine. */
static uint32_t rng_state = 1;

static uint32_t next_rand(void) {
  uint32_t x = rng_state;
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  rng_state = x;
  return x;
}

static unsigned pick(unsigned n) { return (unsigned)(next_rand() % n); }

static const char* kOpeners[] = {
    "<div>", "<span>", "<b>", "<i>", "<a>", "<p>", "<li>", "<dd>", "<dt>",
    "<section>", "<h1>", "<button>", "<form>", "<table>", "<tbody>", "<tr>",
    "<td>", "<th>", "<caption>", "<colgroup>", "<col>", "<template>",
    "<select>", "<option>", "<optgroup>", "<selectedcontent>", "<svg>",
    "<math>", "<ruby>", "<rt>", "<rp>", "<marquee>", "<object>", "<applet>",
    "<pre>", "<listing>", "<hr>", "<frameset>", "<frame>", "<nobr>"};

static const char* kClosers[] = {
    "</div>", "</span>", "</b>", "</i>", "</a>", "</p>", "</li>", "</dd>",
    "</dt>", "</section>", "</h1>", "</button>", "</form>", "</table>",
    "</tbody>", "</tr>", "</td>", "</th>", "</caption>", "</colgroup>",
    "</template>", "</select>", "</option>", "</optgroup>",
    "</selectedcontent>", "</svg>", "</math>", "</ruby>", "</rt>", "</rp>",
    "</nobr>", "</marquee>", "</object>", "</applet>"};

static const char* kRaw[] = {
    "<script>var a = '<div>';</script>", "<style>p{}</style>",
    "<textarea><b></textarea>", "<title><i></title>", "<xmp><u></xmp>",
    "<noscript><p></noscript>", "<noembed><p></noembed>",
    "<noframes><p></noframes>", "<plaintext>",
    "<!-- comment with <div> and </p> -->", "<?pi target?>",
    "<!DOCTYPE html>", "<!DOCTYPE html PUBLIC \"pub\" \"sys\">",
    "<![CDATA[not cdata]]>", "text &amp; more", "  \t\n  ",
    "<div class=\"a\" class=\"b\">", "<div class a=1>", "<div title=>",
    "<b class=\"x\"><i class=\"x\"><b class=\"x\">"};

static void append(char** buf, size_t* len, size_t* cap, const char* s);

/* Elements carrying a pile of attributes, which is where the duplicate check lives:
 * many distinct names, many duplicates of one name, names that differ only in a
 * trailing character, and names long enough that a length check would matter. The
 * corpus stays inside max_attributes on purpose — beyond it the parse is defined to
 * drop attributes, and this comparison is about what the pinned parser builds. */
static void append_attr_cluster(char** buf, size_t* len, size_t* cap, unsigned seed) {
  char name[40];
  unsigned count = 8u + (seed % 40u);
  append(buf, len, cap, "<div");
  for (unsigned i = 0; i < count; ++i) {
    switch (seed % 4) {
      case 0:
        snprintf(name, sizeof(name), " a%u=1", i);
        break;
      case 1:
        snprintf(name, sizeof(name), " a=1");
        break;
      case 2:
        snprintf(name, sizeof(name), " aaa%u=%u", i % 3, i);
        break;
      default:
        snprintf(name, sizeof(name), " data-attribute-number-%u=1", i);
        break;
    }
    append(buf, len, cap, name);
  }
  append(buf, len, cap, ">");
}

static void append(char** buf, size_t* len, size_t* cap, const char* s) {
  size_t n = strlen(s);
  if (*len + n + 1 > *cap) {
    size_t next = (*cap == 0) ? 256 : *cap;
    while (*len + n + 1 > next) next *= 2;
    char* grown = (char*)realloc(*buf, next);
    if (grown == NULL) {
      fprintf(stderr, "FAIL: out of memory\n");
      exit(1);
    }
    *buf = grown;
    *cap = next;
  }
  memcpy(*buf + *len, s, n);
  *len += n;
  (*buf)[*len] = '\0';
}

/* One document: a random walk over openers, closers, raw chunks and text,
 * biased so that runs of unclosed openers (which is where both patched hot
 * spots live) happen regularly. */
static char* make_document(unsigned tokens, unsigned bias) {
  char* buf = NULL;
  size_t len = 0, cap = 0;
  unsigned depth = 0;

  if (bias % 4 == 0) {
    append(&buf, &len, &cap, "<!doctype html>");
  }
  for (unsigned i = 0; i < tokens; ++i) {
    unsigned roll = pick(100);
    if (roll < 45) {
      append(&buf, &len, &cap, kOpeners[pick(sizeof(kOpeners) / sizeof(*kOpeners))]);
      ++depth;
    } else if (roll < 60 && depth > 0) {
      append(&buf, &len, &cap, kClosers[pick(sizeof(kClosers) / sizeof(*kClosers))]);
      if (depth > 0) --depth;
    } else if (roll < 80) {
      append(&buf, &len, &cap, kRaw[pick(sizeof(kRaw) / sizeof(*kRaw))]);
    } else if (roll < 88) {
      append_attr_cluster(&buf, &len, &cap, next_rand());
      ++depth;
    } else {
      append(&buf, &len, &cap, "x");
    }
  }
  /* Half the corpus closes nothing, which is the unclosed-openers shape. */
  if (bias % 2 == 1 && depth > 0) {
    append(&buf, &len, &cap, "x");
  }
  if (buf == NULL) append(&buf, &len, &cap, "");
  return buf;
}

/* ---- canonical dump ---------------------------------------------------- */

static void dump_text(FILE* out, const char* text) {
  /* Length-prefixed so embedded newlines and quotes cannot be confused with
   * anything structural. */
  size_t n = (text == NULL) ? 0 : strlen(text);
  fprintf(out, "#%zu:", n);
  if (n > 0) fwrite(text, 1, n, out);
  fputc('\n', out);
}

static void dump_slice(FILE* out, const char* text, size_t limit) {
  if (text == NULL) {
    fputs("null", out);
    return;
  }
  fputc('"', out);
  size_t i;
  for (i = 0; i < limit && text[i] != '\0'; ++i) {
    unsigned char c = (unsigned char)text[i];
    if (c == '"' || c == '\\') {
      fprintf(out, "\\%c", c);
    } else if (c >= 0x20 && c < 0x7f) {
      fputc(c, out);
    } else {
      fprintf(out, "\\x%02x", c);
    }
  }
  if (i == limit && text[i] != '\0') fputs("...", out);
  fputc('"', out);
}

static void dump_document(FILE* out, GumboOutput* output) {
  /* Explicit stack: this program parses documents the pinned parser can free
   * only because they are shallow, but it must not add a recursion of its own. */
  unsigned capacity = 1024, count = 0;
  GumboNode** stack = (GumboNode**)malloc(capacity * sizeof(*stack));
  if (stack == NULL) {
    fprintf(stderr, "FAIL: out of memory\n");
    exit(1);
  }
  stack[count++] = output->document;

  while (count > 0) {
    GumboNode* node = stack[--count];
    fprintf(out, "%d:", (int)node->type);
    switch (node->type) {
      case GUMBO_NODE_DOCUMENT: {
        GumboDocument* d = &node->v.document;
        fprintf(out, "children=%u,name=%d,pub=%d,sys=%d,has_doctype=%d,quirks=%d,",
                d->children.length, d->has_doctype, d->name != NULL,
                d->public_identifier != NULL, d->system_identifier != NULL,
                (int)d->doc_type_quirks_mode);
        dump_text(out, d->name);
        GumboVector* kids = &d->children;
        for (unsigned i = kids->length; i-- > 0;) {
          if (count == capacity) {
            capacity *= 2;
            GumboNode** grown = (GumboNode**)realloc(stack, capacity * sizeof(*stack));
            if (grown == NULL) {
              fprintf(stderr, "FAIL: out of memory\n");
              exit(1);
            }
            stack = grown;
          }
          stack[count++] = kids->data[i];
        }
      } break;
      case GUMBO_NODE_ELEMENT:
      case GUMBO_NODE_TEMPLATE: {
        GumboElement* e = &node->v.element;
        fprintf(out, "tag=%d,ns=%d,attrs=%u,children=%u,",
                (int)e->tag, (int)e->tag_namespace, e->attributes.length,
                e->children.length);
        dump_text(out, gumbo_normalized_tagname(e->tag));
        for (unsigned i = 0; i < e->attributes.length; ++i) {
          GumboAttribute* a = (GumboAttribute*)e->attributes.data[i];
          fprintf(out, "  attr ns=%d ", (int)a->attr_namespace);
          dump_text(out, a->name);
          dump_text(out, a->value);
        }
        GumboVector* kids = &e->children;
        for (unsigned i = kids->length; i-- > 0;) {
          if (count == capacity) {
            capacity *= 2;
            GumboNode** grown = (GumboNode**)realloc(stack, capacity * sizeof(*stack));
            if (grown == NULL) {
              fprintf(stderr, "FAIL: out of memory\n");
              exit(1);
            }
            stack = grown;
          }
          stack[count++] = kids->data[i];
        }
      } break;
      default: {
        GumboText* t = &node->v.text;
        fprintf(out, "text pos=%d,%d,orig=%d,", (int)t->start_pos.line,
                (int)t->start_pos.column, t->original_text.length != 0);
        dump_text(out, t->text);
      } break;
    }
  }
  free(stack);

  fprintf(out, "errors=%u\n", output->errors.length);
  for (unsigned i = 0; i < output->errors.length; ++i) {
    GumboError* e = (GumboError*)output->errors.data[i];
    fprintf(out, "  err type=%d offset=%zu line=%u col=%u orig=", (int)e->type,
            (size_t)e->position.offset, e->position.line, e->position.column);
    dump_slice(out, e->original_text, 24);
    fputc('\n', out);
  }
  fflush(out);
}

/* ---- modes ------------------------------------------------------------- */

static void write_length_prefixed(FILE* out, const char* data, size_t n) {
  fwrite(&n, sizeof(n), 1, out);
  fwrite(data, 1, n, out);
}

static int corpus_mode(unsigned count) {
  for (unsigned i = 0; i < count; ++i) {
    rng_state = 0x9e3779b9u + i * 2654435761u;
    unsigned tokens = 5 + pick(600);
    /* Every fourth document is deep on purpose: the patched hot spots are
     * functions of the open-element stack, so shallow corpora cannot see them. */
    if (i % 4 == 3) tokens = 1200 + pick(800);
    char* doc = make_document(tokens, i);
    write_length_prefixed(stdout, doc, strlen(doc));
    free(doc);
  }
  fflush(stdout);
  return 0;
}

static int dump_mode(void) {
  size_t n;
  unsigned index = 0;
  while (fread(&n, sizeof(n), 1, stdin) == 1) {
    char* doc = (char*)malloc(n + 1);
    if (doc == NULL) {
      fprintf(stderr, "FAIL: out of memory\n");
      return 1;
    }
    if (fread(doc, 1, n, stdin) != n) {
      fprintf(stderr, "FAIL: truncated corpus\n");
      return 1;
    }
    doc[n] = '\0';

    GumboOptions options = kGumboDefaultOptions;
    GumboOutput* output = gumbo_parse_with_options(&options, doc, n);
    if (output == NULL) {
      fprintf(stderr, "FAIL: parse returned NULL\n");
      return 1;
    }
    /* Plain text with a per-document header, so a divergence is a readable diff
     * that names the document rather than an offset into a binary stream. */
    printf("=== document %u (%zu bytes) ===\n", index, n);
    dump_document(stdout, output);
    ++index;
    free(doc);

    /* The pinned build recurses once per node here; the corpus stays shallow
     * enough for the main thread's stack on purpose. */
    gumbo_destroy_output(&options, output);
  }
  fflush(stdout);
  return 0;
}

int main(int argc, char** argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s corpus [count] | dump\n", argv[0]);
    return 2;
  }
  if (strcmp(argv[1], "corpus") == 0) {
    return corpus_mode(argc >= 3 ? (unsigned)strtoul(argv[2], NULL, 10) : 500);
  }
  if (strcmp(argv[1], "dump") == 0) {
    return dump_mode();
  }
  fprintf(stderr, "usage: %s corpus [count] | dump\n", argv[0]);
  return 2;
}
