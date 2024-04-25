#!/usr/bin/env bash

VERSION=$($(dirname $0)/semver.sh)

if [ "$1" = "deploy" ]; then
TIER=${2:-"staging"}
PROJECT=${3:-""}
cat <<EOF >> slack.txt
{{#success build.status}}
*CI/CD started deploy* of \`{{repo.name}}\` to \`${PROJECT}/${TIER}\`
for version \`${VERSION}\` initiated by \`{{build.author}}\`.
{{else}}
CI/CD deploy to \`${PROJECT}/${TIER}\` failed for \`{{repo.name}}\`
version \`${VERSION}\` initiated by \`{{build.author}}\`.
<{{build.link}}|Fix me please>.
{{/success}}
EOF

elif [ "$1" = "redeploy" ]; then
TIER=${2:-"staging"}
PROJECT=${3:-""}
cat <<EOF >> slack.txt
{{#success build.status}}
*CI/CD <{{build.link}}|started> redeploy* of \`{{repo.name}}\` to \`${PROJECT}/${TIER}\`.
{{else}}
CI/CD redeploy to \`${PROJECT}/${TIER}\` failed for \`{{repo.name}}\`.
<{{build.link}}|Fix me please>.
{{/success}}
EOF

else
cat <<EOF >> slack.txt
CI/CD build finished for app \`{{repo.name}}\` changes by \`{{build.author}}\`.
{{#success build.status}}
Build \`{{build.number}}\` succeeded. <{{build.link}}|Good job>.
New version is: \`${VERSION}\`. _Took {{since build.created}}_.
{{else}}
Build \`{{build.number}}\` failed. <{{build.link}}|Fix me please>.
{{/success}}
EOF

fi
