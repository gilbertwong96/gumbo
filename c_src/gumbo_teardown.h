#ifndef GUMBO_TEARDOWN_H_
#define GUMBO_TEARDOWN_H_

#include <stddef.h>

#include "gumbo.h"

/* The destructor's disarming pass, shared verbatim between the NIF
   destructor (gumbo_handle_dtor) and the teardown probe
   (c_src/test/teardown_probe.c) so a regression in one cannot go unseen by
   the other. This header is ERTS-free: the pass takes plain gumbo types
   and both callers supply what they hold. */
void gumbo_teardown_pass(const GumboOptions* options, GumboOutput* output,
                         GumboNode** nodes, size_t node_count);

#endif /* GUMBO_TEARDOWN_H_ */
