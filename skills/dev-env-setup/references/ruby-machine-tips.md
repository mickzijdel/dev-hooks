# Ruby Machine-Level Tips

These are developer machine optimisations for Ruby projects. They live in global config files, not repos, so they are not part of the per-repo dev-env standard — but they are worth setting up on any machine used for Ruby development.

## Bundler cooldown

Add to `~/.bundle/config`:

```
BUNDLE_COOLDOWN: "3"
```

This tells Bundler to skip re-checking gem sources for 3 days after a successful `bundle install`. On a fast machine with many Ruby projects this is one of the highest-leverage single-line improvements — `bundle install` goes from several seconds to near-instant when dependencies haven't changed.

**Source:** [nateberkopec/dotfiles@af41383](https://github.com/nateberkopec/dotfiles/commit/af41383) (Jun 2026)
