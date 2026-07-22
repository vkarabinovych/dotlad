# Homebrew packaging

`dotlad.rb.in` is the upstream formula template. A tagged release renders it
with the archive version and published checksum:

```bash
scripts/render-homebrew-formula.sh \
  v0.9.0 dist/dotlad-0.9.0.sha256 \
  ../homebrew-tap/Formula/dotlad.rb
```

The rendered formula belongs in `vkarabinovych/homebrew-tap`, not this
repository. The tap owns its repository policy and formula validation workflow.
