/* The parse, given a C stack that covers the worst case its input can
   produce. See gumbo_parse_stack.c for the budget and where its constants
   come from. This unit includes no ERTS header, so it links into both the NIF
   and any standalone probe. */

#ifndef GUMBO_PARSE_STACK_H_
#define GUMBO_PARSE_STACK_H_

#include <stddef.h>

#include "gumbo.h"

typedef enum {
  /* `output` is the parse result, or NULL if gumbo itself returned none
     (allocation failure); the caller already decides what to do with that. */
  GUMBO_PARSE_STACK_OK = 0,
  /* The input exceeds the largest size the budget will size a stack for.
     Refused rather than parsed on a stack that cannot cover it. */
  GUMBO_PARSE_STACK_TOO_LARGE,
  /* The sized thread could not be created. Never falls back to the caller's
     stack: that stack is exactly what the budget just said is too small. */
  GUMBO_PARSE_STACK_NO_THREAD,
} gumbo_parse_stack_status_t;

GumboOutput* gumbo_parse_on_sized_stack(GumboOptions* options, const char* input,
                                        size_t length,
                                        gumbo_parse_stack_status_t* status);

#endif
