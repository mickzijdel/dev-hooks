# Modern Project

A fixture exercising the modern heading and command spellings the audit recognises: an
Install heading (instead of Installation), Claude Code `/plugin` commands, and uv/mise
commands.

## Install

```bash
/plugin marketplace add example/modern
/plugin install modern@modern
```

For a local checkout:

```bash
mise install
uv sync
```

## Usage

```bash
uv run modern --check input.txt
```

## License

MIT. See the LICENSE file for the full text.
