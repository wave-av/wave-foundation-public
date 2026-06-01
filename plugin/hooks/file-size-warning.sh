#!/bin/bash
# Hook: Large file warning
# Event: PreToolUse (matcher: Read)
set +e
if ! test -t 0; then
  stdin_content=$(cat)
  file_path=$(echo "$stdin_content" | grep -o '"file_path"[^,}]*' | sed 's/.*": *"\([^"]*\)".*/\1/' 2>/dev/null)
fi
if [ -n "$file_path" ] && [ -f "$file_path" ]; then
  file_size=$(stat -f%z "$file_path" 2>/dev/null || echo 0)
  line_count=$(wc -l <"$file_path" 2>/dev/null || echo 0)
  if [ "$file_size" -gt 102400 ] || [ "$line_count" -gt 1000 ]; then
    echo "Large file: $(basename "$file_path") (${line_count} lines, $((file_size / 1024))KB). Use offset/limit for more." >&2
  fi
fi
exit 0
