#!/usr/bin/env bash
set -o errexit

function _usage() {
  echo "Usage:"
  echo "    ./diff-main-all.sh [--show-diff] Send diff content to stdout"
  echo "    ./diff-main-all.sh [--md] Output is formatted with markdown. Diff is wrapped in details sections"
  echo "    ./diff-main-all.sh [--silent-clone] Send clone stdout to /dev/null"
  echo "    ./diff-main-all.sh [--ignore-no-diff] Ignore files that does not have a diff"
  echo "    ./diff-main-all.sh [--use-local-diffsource] Place the diffsource folder in current apps-repo, instead of /tmp/"
  exit 1
}

# Parse parameters
SHOW_DIFF="false"
OUTPUT_MARKDOWN="false"
SILENT_CLONE="false"
IGNORE_NO_DIFF="false"
LOCAL_DIFFSOURCE="false"
SEMANTIC_DIFF="false"

while [[ "$#" -gt 0 ]]; do
  case $1 in
  --show-diff) SHOW_DIFF="true" ;;
  --md) OUTPUT_MARKDOWN="true" ;;
  --silent-clone) SILENT_CLONE="true" ;;
  --ignore-no-diff) IGNORE_NO_DIFF="true" ;;
  --use-local-diffsource) LOCAL_DIFFSOURCE="true" ;;
  --semantic-diff) SEMANTIC_DIFF="true" ;;

  --help) _usage ;;
  *)
    echo "Unknown parameter passed: $1"
    exit 1
    ;;
  esac
  shift
done

set -o nounset

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/scripts/lib.sh"

validate_tooling

# Diffsource
if [[ $SILENT_CLONE == "true" ]]; then
  validate_and_update_diffsource >/dev/null
else
  echo "Parameter --show-diff: $SHOW_DIFF"
  echo "Parameter --md: $OUTPUT_MARKDOWN"
  echo "Parameter --silent-clone: $SILENT_CLONE"
  echo "Parameter --ignore-no-diff: $IGNORE_NO_DIFF"
  echo "Parameter --use-local-diffsource: $LOCAL_DIFFSOURCE"
  echo "Parameter --semantic-diff: $SEMANTIC_DIFF"
  validate_and_update_diffsource
  echo
fi
# Diff
echo
echo "Diff-ing jsonnet-generation against main"
echo
echo DEV

jsonnetfiles_feature=$(find_jsonnet_files "^env/[a-z0-9]\+-dev" "$SCRIPT_DIR")
jsonnetfiles_main=$(find_jsonnet_files "^env/[a-z0-9]\+-dev" "$DIFF_SOURCE_DIR")
compare "$jsonnetfiles_feature" "$jsonnetfiles_main" || true

echo
echo PROD
jsonnetfiles_feature=$(find_jsonnet_files "^env/[a-z0-9]\+-prod" "$SCRIPT_DIR")
jsonnetfiles_main=$(find_jsonnet_files "^env/[a-z0-9]\+-prod" "$DIFF_SOURCE_DIR")
compare "$jsonnetfiles_feature" "$jsonnetfiles_main" || true
