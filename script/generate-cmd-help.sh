#!/usr/bin/env bash
# Generates cmdHelpGenerated.swift from the ```synopsis fenced block of each
# docs-md/commands/*.md page.
cd "$(dirname "$0")/.."

out_file="${1:-./Sources/Common/cmdHelpGenerated.swift}"

aerospace_prefix="aerospace-edge"
____usage_prefix="   USAGE:"
_______or_prefix="      OR:"
____strip_prefix="   "

triple_quote='"""'

cat << EOF > "$out_file"
// FILE IS GENERATED FROM docs-md/commands/*.md files
// TO REGENERATE THE FILE RUN script/generate.sh

EOF

for file in docs-md/commands/*.md; do
    subcommand=$(basename "$file" .md | sed 's/-/_/g')
    awk '/^```synopsis$/{f=1;next} /^```$/{f=0} f' "$file" | \
        sed '/^$/ d' | \
        sed "1   s/^$aerospace_prefix/$____usage_prefix/" | \
        sed "2,$ s/^$aerospace_prefix/$_______or_prefix/" | \
        sed     "s/^$____strip_prefix//" | \
        sed "1 s/^/let ${subcommand}_help_generated = $triple_quote\n/" | \
        sed "\$ s/$/\n${triple_quote}/" | \
        sed '2,$ s/^/    /' >> "$out_file"
done
