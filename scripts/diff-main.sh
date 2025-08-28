#!/usr/bin/env bash
set -o errexit

function _usage() {
 echo "Usage:"
  echo "    ./diff-main.sh [--show-diff] Send diff content to stdout"
  echo "    ./diff-main.sh [--md] Output is formatted with markdown. Diff is wrapped in details sections"
  echo "    ./diff-main.sh [--silent-clone] Send clone stdout to /dev/null"
  echo "    ./diff-main.sh [--ignore-no-diff] Ignore files that does not have a diff"
  echo "    ./diff-main.sh [--use-local-diffsource] Place the diffsource folder in current apps-repo, instead of /tmp/"
  echo "    ./diff-main.sh [*] Wildcard for selecting files (including path) to diff. Must be a single word. e.g \`./diff-main.sh dev\` or \`./diff-main.sh klient\`"
 exit 1
}

# Parse parameters
SHOW_DIFF="false"
OUTPUT_MARKDOWN="false"
SILENT_CLONE="false"
IGNORE_NO_DIFF="false"
LOCAL_DIFFSOURCE="false"
SEMANTIC_DIFF="false"
PATTERN=""
while [[ "$#" -gt 0 ]]; do
 case $1 in
 --help) _usage ;;
 --show-diff) SHOW_DIFF="true" ;;
 --md) OUTPUT_MARKDOWN="true" ;;
 --silent-clone) SILENT_CLONE="true" ;;
 --ignore-no-diff) IGNORE_NO_DIFF="true" ;;
 --use-local-diffsource) LOCAL_DIFFSOURCE="true" ;;
 --semantic-diff) SEMANTIC_DIFF="true" ;;
 *) if [[ -n "$PATTERN" ]]; then
  echo "Too many parameters"
  exit 1
 else
  PATTERN="$1"
 fi ;;
 esac
 shift
done
set -o nounset

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/lib.sh"


validate_tooling
if [[ $SILENT_CLONE == "true" ]]; then
 validate_and_update_diffsource >/dev/null
else
 echo "Parameter --show-diff: $SHOW_DIFF"
 echo "Parameter --md: $OUTPUT_MARKDOWN"
 echo "Parameter --silent-clone: $SILENT_CLONE"
 echo "Parameter --ignore-no-diff: $IGNORE_NO_DIFF"
 echo "Parameter --use-local-diffsource: $LOCAL_DIFFSOURCE"
 echo "Parameter --semantic-diff: $SEMANTIC_DIFF"
 echo "Parameter pattern: $PATTERN"
 validate_and_update_diffsource
 echo
fi

if [[ -z "$PATTERN" ]]; then
 #No pattern
 dirs=("env")
 jsonnetfile=$(find "${dirs[@]}" -name "*.jsonnet" | sort)

 #Compare the selected file with the diffsource equivalent.
 compare "$jsonnetfile" "$DIFF_SOURCE_DIR/$jsonnetfile"

else
 jsonnetfiles_feature=$(find_jsonnet_files "$PATTERN" "$SCRIPT_DIR")
 jsonnetfiles_main=$(find_jsonnet_files "$PATTERN" "$DIFF_SOURCE_DIR")
 compare "$jsonnetfiles_feature" "$jsonnetfiles_main"
fi
