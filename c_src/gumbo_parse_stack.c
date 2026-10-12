/* gumbo's recursion depth follows the input's nesting depth, and 0.14.1 caps
   neither. Two call sites can reach a depth-proportional recursion:

   1. the destructor, disarmed by gumbo_teardown.c's iterative pass, which
      leaves destroy_node only the document node and so never recurses on the
      tree's depth; and
   2. handle_in_body's <frameset> branch (parser.c), which pops the open
      elements and calls destroy_node on the body node *during the parse*.
      Nothing outside parser.c can disarm that one: it is a static function
      called mid-stream, and the subtree it walks is the input's own nesting.

   So the parse is the remaining hazard, and the defence is to give it a stack
   that covers the worst case its input can produce. That is a budget rather
   than a guess, because depth is bounded by input length: every nesting level
   costs at least one start tag, and the shortest start tag is three bytes.

   Every constant below is measured, not assumed:

     MIN_BYTES_PER_LEVEL  3    "<x>" is the shortest start tag. The densest
                              nesting measured is <b> at 3 bytes per level
                              (<table><tr><td> is 4.25, template contents are
                              5).
     FRAME_BYTES         64    clang -fstack-usage on parser.c. The deepest
                              depth-proportional frame is clone_node_
                              recursively at 64; destroy_node is 48.
     STACK_RESERVE   64 KiB    what is already live when a destroy starts:
                              handle_in_body 2016, gumbo_parse_with_options
                              464, the NIF's own frames, libc, and the
                              per-token handle_in_* cycle.
     STACK_MARGIN         2    headroom over the two estimates above.

   The destroy_node frame is cross-checked against the real cliff: at 48 bytes,
   320 KiB covers 6 826 levels and 160 KiB covers 3 413, and a
   "<!doctype html>" + "<div>"*n + "<frameset>" document dies exactly between
   the measured 6 000/8 000 on a 320 KiB stack and 3 000/6 000 under
   `+sssdcpu 20` (160 KiB).

   A parse whose input needs more stack than the calling thread has left runs
   on a thread of its own, sized by this budget. The caller's stack is measured
   rather than assumed because the same NIF can arrive on a normal scheduler
   thread, a dirty CPU thread, or a dirty I/O thread, each with its own stack
   size, all of them configurable at VM start (+sss, +sssdcpu, +sssdio). When
   the platform will not report the stack, the thread path is taken: it is the
   one that does not need to know. */

#define _GNU_SOURCE 1

#include "gumbo_parse_stack.h"

#include <pthread.h>
#include <unistd.h> /* sysconf(_SC_PAGESIZE) */

/* The largest input this budget will size a stack for, and the largest stack
   it will ask for. 16 MiB needs 16 MiB * 64 * 2 / 3 = 683 MiB at the worst case
   the bounds below allow, which is what we reserve; raising the input cap
   without raising the stack ceiling is a compile error, not a comment.

   The cap is set by what this library has to parse rather than by gumbo: the
   regression corpus in test/gumbo/stack_test.exs parses an 11 MB document (50
   options of 20 000 spans), and the HTML5 spec is ~7 MB. Gumbo's own limit is
   far higher — an `int` buffer length — so the stack budget is what binds. The
   reservation is address space, committed lazily, and measured thread creation
   is flat in it (21 us at 256 KiB, 29 us at 683 MiB), so a generous cap costs
   nothing but a refusal for anything larger. */
#define MAX_INPUT_BYTES (16u * 1024u * 1024u)
#define MAX_PARSE_STACK (768u * 1024u * 1024u)

#define MIN_BYTES_PER_LEVEL 3u
#define FRAME_BYTES 64u
#define STACK_RESERVE_BYTES (64u * 1024u)
#define STACK_MARGIN 2u

#if (MAX_INPUT_BYTES / MIN_BYTES_PER_LEVEL + 1) * FRAME_BYTES * STACK_MARGIN + \
        STACK_RESERVE_BYTES >                                                     \
    MAX_PARSE_STACK
#error "MAX_INPUT_BYTES needs more stack than MAX_PARSE_STACK allows"
#endif

/* The thread's stack still has to run the parser, not only the destroy, even
   when the input is short enough that the depth budget is a rounding error. */
#define THREAD_STACK_FLOOR (256u * 1024u)

/* A stack larger than this is not a scheduler thread's. Treat such a report as
   unusable instead of trusting it: the thread path is correct whatever the
   caller's stack turns out to be, and a bogus report is exactly the case where
   trusting it would reintroduce the crash. This has to sit above any stack a VM
   can be configured with (+sss, +sssdcpu and +sssdio are all settable in MiB,
   and macOS rounds a request up), or the clamp itself would be the thing
   rejecting a legitimate stack — and every parse would pay for a thread. */
#define MAX_PLAUSIBLE_STACK (64u * 1024u * 1024u)

static size_t required_stack(size_t length) {
  /* One level even for an empty input: the document node is a level. */
  size_t levels = length / MIN_BYTES_PER_LEVEL + 1;
  return STACK_RESERVE_BYTES + levels * FRAME_BYTES * STACK_MARGIN;
}

/* pthread_attr_setstacksize rejects a size that is not a multiple of the page
   size, with EINVAL rather than by rounding — and on Apple silicon the page is
   16 KiB, not the 4 KiB that assuming would produce. The requirement below is
   an arbitrary number of levels times 128, so it is essentially never aligned
   by accident: unaligned here means the thread is refused and the parse fails.
   Ask the platform for the boundary instead of naming a number. */
static size_t round_up_to_page(size_t size) {
  long page = sysconf(_SC_PAGESIZE);
  size_t boundary = (page > 0) ? (size_t)page : 4096u;
  return (size + boundary - 1) / boundary * boundary;
}

/* Bytes of C stack left below this frame, or 0 when the platform will not say
   (0 means unknown, and unknown takes the thread path). */
static size_t stack_remaining(void) {
  char probe = 0;
  const char* sp = &probe;

#if defined(__APPLE__)
  /* The stack grows down from the address pthread_get_stackaddr_np returns, so
     what is left is the distance from here to the *low* end, and that is
     base - size, not base. (base - sp is the opposite: the bytes used, which is
     near zero at the thread's first frames, so mistaking one for the other
     reports a plausible tiny number rather than an absurd one.) The size is
     what the thread actually got, which is the requested size rounded up. */
  void* base = pthread_get_stackaddr_np(pthread_self());
  size_t size = pthread_get_stacksize_np(pthread_self());
  if (base == NULL || size == 0) {
    return 0;
  }
  const char* low = (const char*)base - size;
  if (sp <= low || sp > (const char*)base) {
    return 0;
  }
  return (size_t)(sp - low);
#elif defined(__linux__)
  pthread_attr_t attr;
  if (pthread_getattr_np(pthread_self(), &attr) != 0) {
    return 0;
  }
  void* low = NULL;
  size_t size = 0;
  int queried = pthread_attr_getstack(&attr, &low, &size);
  pthread_attr_destroy(&attr);
  if (queried != 0 || low == NULL || size == 0) {
    return 0;
  }
  /* pthread_attr_getstack reports the lowest address; the stack grows down
     towards it. */
  const char* high = (const char*)low + size;
  if (sp < (const char*)low || sp >= high) {
    return 0;
  }
  return (size_t)(sp - (const char*)low);
#else
  (void)sp;
  return 0;
#endif
}

static size_t caller_stack_remaining(void) {
  size_t left = stack_remaining();
  return (left > MAX_PLAUSIBLE_STACK) ? 0 : left;
}

typedef struct {
  const GumboOptions* options;
  const char* input;
  size_t length;
  GumboOutput* output;
} gumbo_parse_job_t;

static void* parse_on_this_thread(void* arg) {
  gumbo_parse_job_t* job = arg;
  /* Only gumbo's own allocator runs here (kGumboDefaultOptions' malloc/free;
     the options map overrides six scalars and no allocator), and the input is
     a refc binary's data read-only, so no ERTS API is reachable from this
     thread. */
  job->output = gumbo_parse_with_options(job->options, job->input, job->length);
  return NULL;
}

GumboOutput* gumbo_parse_on_sized_stack(const GumboOptions* options,
                                        const char* input, size_t length,
                                        gumbo_parse_stack_status_t* status) {
  *status = GUMBO_PARSE_STACK_OK;

  if (length > MAX_INPUT_BYTES) {
    *status = GUMBO_PARSE_STACK_TOO_LARGE;
    return NULL;
  }

  size_t required = required_stack(length);

  if (caller_stack_remaining() >= required) {
    /* The calling thread's stack already covers the worst case, so there is
       nothing to hand off. This is the path small documents take, and it costs
       no thread. */
    return gumbo_parse_with_options(options, input, length);
  }

  size_t stack_size = (required < THREAD_STACK_FLOOR) ? THREAD_STACK_FLOOR
                                                      : required;
  stack_size = round_up_to_page(stack_size);

  pthread_attr_t attr;
  if (pthread_attr_init(&attr) != 0) {
    *status = GUMBO_PARSE_STACK_NO_THREAD;
    return NULL;
  }
  if (pthread_attr_setstacksize(&attr, stack_size) != 0) {
    pthread_attr_destroy(&attr);
    *status = GUMBO_PARSE_STACK_NO_THREAD;
    return NULL;
  }

  gumbo_parse_job_t job = {options, input, length, NULL};
  pthread_t thread;
  int created = pthread_create(&thread, &attr, parse_on_this_thread, &job);
  pthread_attr_destroy(&attr);
  if (created != 0) {
    *status = GUMBO_PARSE_STACK_NO_THREAD;
    return NULL;
  }

  pthread_join(thread, NULL);
  return job.output;
}
