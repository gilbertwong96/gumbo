# Used by "mix format"
[
  inputs: [
    "{mix,.formatter,.credo}.exs",
    "{config,lib,test}/**/*.{ex,exs}",
    # The patch definitions are data, but they are Elixir data, and they are the only
    # things under c_src that anyone edits by hand. mix gumbo.patches --check is what
    # guards their *values*: formatting re-indents a heredoc and its terminator together,
    # which leaves the value alone, and the gate fails if that ever stops being true.
    "c_src/patches/gumbo-parser/*.exs"
  ]
]
