#!/usr/bin/env bash
# Flags R functions defined in one directory (default R/) that have no
# reference anywhere else in the project. Dead helper functions accumulate
# silently in a targets pipeline since nothing fails at runtime when one goes
# unused - tar_source() just loads it and moves on.
#
# Usage: find_unused_functions.sh [functions_dir] [project_root]
set -eu

functions_dir="${1:-R}"
project_root="${2:-.}"

if [ ! -d "$functions_dir" ]; then
  echo "No such directory: $functions_dir" >&2
  exit 1
fi

search_files=()
while IFS= read -r f; do
  search_files+=("$f")
done < <(find "$project_root" \
  \( -name "_targets" -o -name ".git" -o -name "renv" -o -name "node_modules" -o -name ".Rproj.user" \) -prune -o \
  -type f \( -name "*.R" -o -name "*.Rmd" -o -name "*.qmd" \) -print)

def_files=()
while IFS= read -r f; do
  def_files+=("$f")
done < <(find "$functions_dir" -name "*.R")

echo "Checking ${#def_files[@]} files in $functions_dir/ against ${#search_files[@]} project files."
echo

any_unused=0

for f in "${def_files[@]}"; do
  while IFS=: read -r lineno match; do
    name=$(printf '%s' "$match" | sed -E 's/^[[:space:]]*([A-Za-z._][A-Za-z0-9._]*).*/\1/')
    total=0
    for sf in "${search_files[@]}"; do
      c=$(grep -ow "$name" "$sf" 2>/dev/null | wc -l | tr -d ' ')
      total=$((total + c))
    done
    if [ "$total" -le 1 ]; then
      echo "possibly unused: $name  ($f:$lineno)"
      any_unused=1
    fi
  done < <(grep -noE '^[[:space:]]*[A-Za-z._][A-Za-z0-9._]*[[:space:]]*(<-|=)[[:space:]]*function[[:space:]]*\(' "$f")
done

if [ "$any_unused" -eq 0 ]; then
  echo "No obviously unused functions found."
fi

echo
echo "Note: this is a plain-text heuristic, not a real R parser. It will misfire on"
echo "functions called via do.call()/get()/match.fun(), S3 methods dispatched by"
echo "naming convention, functions exported for use outside this project, or names"
echo "that happen to also appear in comments or strings elsewhere. Verify each hit"
echo "before recommending removal."
