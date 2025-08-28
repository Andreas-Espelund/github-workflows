#!/usr/bin/env bash

APPS_BASENAME=$(basename "$PWD")
APPS_REPO_NAME="${REPO_NAME##*/}" # Get the apps repo name: 'x-apps'


if [[ "$LOCAL_DIFFSOURCE" == "true" ]]; then
  LIB_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
  DIFF_SOURCE_PARENT="$LIB_DIR/../.diffsource"
  DIFF_SOURCE_DIR="$DIFF_SOURCE_PARENT/$APPS_REPO_NAME"
else
  DIFF_SOURCE_PARENT="/tmp/$APPS_BASENAME.diffsource"
  DIFF_SOURCE_DIR="$DIFF_SOURCE_PARENT/$APPS_REPO_NAME"
fi

NC='\033[0m' # No Color / format
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
ITALIC='\e[3m'

if [[ $OUTPUT_MARKDOWN == "true" ]]; then
  ADDED_STRING="ADDED"
  DELETED_STRING="remote DELETED"
  DIFF_STRING="DIFF"
  NODIFF_STRING="NO DIFF"
  CLOSE_DETAILS="</details>"
  CLOSE_SUMMARY=" </b></summary>"
  CLOSE_EMPTY_DIFF="${CLOSE_SUMMARY} \n\n \`\`\`diff\n \`\`\`\n ${CLOSE_DETAILS}"
  TITLE_STRING="<details><summary><b>"
  HINT_STRING=""
  INVALID_JSONNET="INVALID JSONNET!"
  INVALID_FORMAT="INVALID FORMAT"
else
  ADDED_STRING="${RED}ADDED${NC}"
  DELETED_STRING="remote ${RED}DELETED${NC}"
  DIFF_STRING="${RED}DIFF${NC}"
  NODIFF_STRING="${GREEN}NO DIFF${NC}"
  TITLE_STRING="Diffing"
  HINT_STRING="Files are not detected on your branch, implies deleted. ${ITALIC}Hint: rebase?${NC}\n"
  INVALID_JSONNET="${RED}INVALID JSONNET${NC}"
  INVALID_FORMAT="${YELLOW}INVALID FORMAT${NC}"
  CLOSE_EMPTY_DIFF=
fi

function validate_tooling() {
  if ! command -v jsonnet >/dev/null; then
    echo """
    'jsonnet' not found on PATH. It is required for this script to work.
    Install either
    https://github.com/google/go-jsonnet (recommended) or
    https://github.com/google/jsonnet or
    https://github.com/databricks/sjsonnet
  """
    exit 1
  fi
  if ! command -v peco >/dev/null; then
    echo """
    'peco' not found on PATH. It is required for this script to work properly.
    See Github for installation instructions: https://github.com/peco/peco
    (OSX: brew install peco)
  """
    exit 1
  fi
  if ! command -v diff-so-fancy >/dev/null; then
    echo """
    'diff-so-fancy' not found on PATH. It is required for this script to work properly.
    See Github for installation instructions: https://github.com/so-fancy/diff-so-fancy
    (OSX: brew install diff-so-fancy)
  """
    exit 1
  fi
  if ! command -v dyff >/dev/null && [[ "$SEMANTIC_DIFF" == "true" ]]; then
    echo """
    'dyff' not found on PATH. It is required for semantic diffs.
    See Github for installation instructions: https://github.com/homeport/dyff
    (OSX: brew install homeport/tap/dyff)
  """
    exit 1
  fi

}
function print_formatted_diff() {
  local _diff="$1"
  [[ $_diff == "" ]] && return

  if [[ $OUTPUT_MARKDOWN == "true" ]]; then
    echo
    cat <<-EOF

			\`\`\`diff
			${_diff}
			\`\`\`

		EOF
    return
  fi

  echo
  _diff="$(echo "${_diff}" | diff-so-fancy)"
  printf "${_diff}"
  return
}

function validate_jsonnet_file() {
  local jsonnetfile
  jsonnetfile="$1"
  if ! jsonnet "$jsonnetfile" >/dev/null; then
    echo "Validation of main manifests $jsonnetfile: ${INVALID_JSONNET}"
    return 1
  fi
}

function validate_and_update_diffsource() {
  # Check diffsource exists
  if [[ ! -d "$DIFF_SOURCE_PARENT" ]]; then
    mkdir -p "$DIFF_SOURCE_PARENT"
  fi
  cd "$DIFF_SOURCE_PARENT"
  if [[ ! -d "$DIFF_SOURCE_DIR" ]]; then
    echo "Cloning $APPS_REPO_NAME into '$DIFF_SOURCE_PARENT' (for diffing)"
    git clone git@github.com:kartverket/$APPS_REPO_NAME.git
  fi

  # Refresh diffsource
  cd "$DIFF_SOURCE_DIR"
  echo
  echo "Fetching latest from main"
  git fetch
  git reset --hard origin/main
  git submodule update --init
  cd "$SCRIPT_DIR"
}

function find_jsonnet_files() {
  local pattern="$1"
  local root_dir="$2"
  local dirs
  local original_dir="$(pwd)"
  dirs=("env")
  cd "$root_dir"

  find "${dirs[@]}" -name '*.jsonnet' | sort | grep "$pattern"

  cd "$original_dir"
}

function compare() {
  local jsonnet_files_feature="$1"
  local jsonnet_files_main="$2"

  for f in ${jsonnet_files_feature}; do
    #    validate_jsonnet_file "$f"

    # Diff
    if [ -f "$DIFF_SOURCE_DIR/$f" ]; then
      _handle_diff "$f" "$DIFF_SOURCE_DIR/$f" || true
    # Added
    elif [ ! -f "$DIFF_SOURCE_DIR/$f" ]; then
      _handle_diff "$f" "" || true
    fi
  done

  # Set.exlude(_jsonnetfiles_main, _jsonnetfiles_feature)
  # Retrive files that is on the main branch, but not on the feature branch
  _jsonnet_files_not_on_feature_branch=$(comm -23 <(printf "%s\n" "${jsonnet_files_main[@]//"$DIFF_SOURCE_DIR/"/}") <(printf "%s\n" "${jsonnet_files_feature[@]}"))

  # Deleted
  if [[ $_jsonnet_files_not_on_feature_branch != "" ]]; then
    for f in ${_jsonnet_files_not_on_feature_branch}; do
      _handle_diff "" "$DIFF_SOURCE_DIR/$f" || true
    done

    echo ""
    echo -e "${HINT_STRING}"
  fi
}

function print_changes() {
  diff="$1"
  mode="$2"
  file="$3"
  fmt_diff=

  # If deleted or malformed jsonnet, fmt will not work
  if [[ ${mode} != "${DELETED_STRING}" && ${mode} != "${INVALID_JSONNET}" ]]; then
    jsonnetfmt --test "$file" 2>/dev/null || mode="${mode} and ${INVALID_FORMAT}"
    fmt_diff=$(diff -u <(cat "$file") <(jsonnetfmt "$file")) >/dev/null
  fi

  if [[ "${mode}" == "${NODIFF_STRING}" && $IGNORE_NO_DIFF == "true" ]]; then
    # no diff and ok format
    return
  elif [[ "$OUTPUT_MARKDOWN" == "true" ]]; then
    printf "<details><summary><b> ${file} ${mode} </b></summary>"
    printf ""
    if [[ "$SHOW_DIFF" == "true" ]]; then
      if [[ ${mode} == "${INVALID_JSONNET}" ]]; then
        print_formatted_diff "$(jsonnet "$file" 2>&1)"
      else
        print_formatted_diff "$diff" && print_formatted_diff "$fmt_diff"
      fi
    fi
    printf "</details>"

  else
    printf "Diffing ${file}: ${mode}${NC}"
    if [[ "$SHOW_DIFF" == "true" ]]; then
      if [[ ${mode} == "${INVALID_JSONNET}" ]]; then
        print_formatted_diff "$(jsonnet "$file" 2>&1)"
      else
        print_formatted_diff "$diff" && print_formatted_diff "$fmt_diff"
      fi
    fi
  fi
  echo
}

# Input
# 	$1: [required] path to feature-branch's jsonnet file, can be empty string
# 	$2: [required] path to main-branch's jsonnet file, can be empty string
#
# Calls `jsonnet` on input paths, then `diff` on those. If path is empty string `jsonnet` is not used.
function _handle_diff() {
  if [ $# != 2 ]; then
    exit 1
  fi

  set +o errexit
  _exitcode=0

  # Filepath to feature and main jsonnet files
  local jsonnet_file_feature="$1"
  local jsonnet_file_main="$2"

  local jsonnet_fmt_feature=
  local jsonnet_fmt_main=

  # Extract the jsonnet relative path
  # If undefined, strip the temp dir from the main branch jsonnet-file.
  # Used for print.
  jsonnet_common_filename=${jsonnet_file_feature:-"$(echo "$jsonnet_file_main" | sed "s|$DIFF_SOURCE_DIR/||")"}

  # If input-path not empty run `jsonnet` on path.
  if [[ "$jsonnet_file_feature" != "" ]]; then
    jsonnet_fmt_feature=$(jsonnet "$jsonnet_file_feature" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
      print_changes "" "${INVALID_JSONNET}" "$jsonnet_file_feature"
      return 1
    fi
    diff_feature_label="$jsonnet_common_filename"
  elif [[ "$jsonnet_file_feature" == "" ]]; then
    jsonnet_fmt_feature=""
    diff_feature_label="**deleted**" # Assume deleted if not supplied
  fi

  if [[ "$jsonnet_file_main" != "" ]]; then
    jsonnet_fmt_main=$(jsonnet "$jsonnet_file_main")
    diff_main_label="$jsonnet_common_filename"
  elif [[ "$jsonnet_file_main" == "" ]]; then
    jsonnet_fmt_main=""
    diff_main_label="**added**" # Assume added if not supplied
  fi

  # Compare the jsonnet or empty string.
  if [[ "$SEMANTIC_DIFF" == "false" ]]; then
    _diff=$(diff --label="remote $diff_main_label" --label="local  $diff_feature_label" -w -u <(echo "$jsonnet_fmt_main") <(echo "$jsonnet_fmt_feature"))
  else
    _diff=$(dyff between --omit-header --color=on --ignore-order-changes --set-exit-code <(echo "$jsonnet_fmt_main") <(echo "$jsonnet_fmt_feature"))
  fi
  _diff_exit_code=$?

  if [[ $_diff_exit_code -eq 0 ]]; then
    print_changes "$_diff" "${NODIFF_STRING}" "$jsonnet_file_feature"
  elif [[ "$jsonnet_fmt_main" != "" && "$jsonnet_fmt_feature" != "" ]]; then
    print_changes "$_diff" "${DIFF_STRING}" "$jsonnet_common_filename"
  elif [[ "$jsonnet_fmt_main" == "" ]]; then
    print_changes "$_diff" "${ADDED_STRING}" "$jsonnet_common_filename"
  else
    print_changes "$_diff" "${DELETED_STRING}" "$jsonnet_common_filename"
  fi

  set -o errexit # TODO: smaller scope
  return ${_exitcode}
}
