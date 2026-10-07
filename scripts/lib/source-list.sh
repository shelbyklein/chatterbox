# Sourced by scripts that pass swiftc a hand-written file list. Stops on a file that's missing
# or listed twice, instead of a confusing compiler error (or a build that silently drops it).
check_source_list() {  # check_source_list MANIFEST (paths from the repo root, one per line)
  local missing dupes
  missing=$(while IFS= read -r f; do [[ -z "$f" || -e "$f" ]] || echo "$f"; done < "$1")
  dupes=$(sort "$1" | uniq -d)
  if [[ -n "$missing$dupes" ]]; then
    [[ -n "$missing" ]] && printf 'Source list names files that do not exist:\n%s\n' "$missing" >&2
    [[ -n "$dupes" ]] && printf 'Source list names files twice:\n%s\n' "$dupes" >&2
    return 1
  fi
}
