#!/usr/bin/env bash
# Sync .ruler/ (AGENTS.md + skills) into every agent's files: CLAUDE.md, .claude/skills, .codex, .cursor, .opencode.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
if command -v npx >/dev/null 2>&1; then
    exec npx -y @intellectronica/ruler apply --no-backup
fi

# The Ada checkout can be maintained without Node. These are the two
# instruction destinations and skill directories used by ruler.toml.
for destination in AGENTS.md CLAUDE.md; do
    {
        printf '<!-- Generated from .ruler/AGENTS.md by scripts/ruler.sh -->\n\n'
        cat .ruler/AGENTS.md
    } > "$destination"
done
for destination in .claude .agents .cursor .opencode; do
    mkdir -p "$destination/skills"
    cp -R .ruler/skills/. "$destination/skills/"
done
printf 'Instructions and skills synchronized with the Bash fallback.\n'
