#!/bin/bash
set -e

PR_NUMBER="$1"
HEAD_SHA="$2"
OWNER="vuco19725-jpg"
REPO="cicd-"
RULES_FILE=".github/ai-review-rules.md"
DIFF_FILE="/tmp/pr.diff"
CONTEXT_FILE="/tmp/pr-context.txt"
REVIEW_FILE="/tmp/review-body.md"
RESPONSE_FILE="/tmp/ai-response.json"
INLINE_FILE="/tmp/inline-comments.json"

if [ ! -f "$DIFF_FILE" ]; then
  echo "Diff file not found, skipping AI review"
  exit 0
fi

if [ -z "$DEEPSEEK_API_KEY" ]; then
  echo "DEEPSEEK_API_KEY not set, skipping AI review"
  exit 0
fi

DIFF_SIZE=$(wc -c < "$DIFF_FILE")
echo "=== AI Review Start ==="
echo "Diff size: $DIFF_SIZE bytes ($(wc -l < "$DIFF_FILE") lines)"

# ──────────────────────────────────────────────
# 1. 路径过滤 & 文件分类
# ──────────────────────────────────────────────
classify_file() {
  local f="$1"
  case "$f" in
    *.test.*|*.spec.*|__tests__/*|*.snap|__snapshots__/*) echo "test" ;;
    *.json|*.yaml|*.yml|*.toml|*.ini|*.cfg|Dockerfile*|docker-compose*|*.env*) echo "config" ;;
    *.md|*.rst|*.txt|*.adoc|LICENSE|CHANGELOG*) echo "doc" ;;
    package-lock.json|*.lock|pnpm-lock.yaml|yarn.lock) echo "lock" ;;
    migrations/*|*.sql) echo "migration" ;;
    *) echo "logic" ;;
  esac
}

# Extract file list from diff
CHANGED_FILES=($(grep -E '^\+\+\+ b/' "$DIFF_FILE" | sed 's|^+++ b/||'))
echo "Changed files: ${#CHANGED_FILES[@]} total"

SKIPPED_FILES=()
REVIEW_FILES=()
FILE_CLASSES=()

for f in "${CHANGED_FILES[@]}"; do
  if [ "$f" = "/dev/null" ]; then continue; fi
  cls=$(classify_file "$f")

  skip=0
  if [ "$cls" = "test" ] || [ "$cls" = "lock" ] || [ "$cls" = "migration" ] || [ "$cls" = "doc" ]; then
    skip=1
  fi

  if [ "$skip" -eq 1 ]; then
    SKIPPED_FILES+=("$f")
  else
    REVIEW_FILES+=("$f")
    FILE_CLASSES+=("$cls")
  fi
done

echo "Review files: ${#REVIEW_FILES[@]}"
echo "Skipped files: ${#SKIPPED_FILES[@]}"
for f in "${SKIPPED_FILES[@]}"; do echo "  SKIP: $f"; done

if [ ${#REVIEW_FILES[@]} -eq 0 ]; then
  echo "No files to review after filtering. Done."
  exit 0
fi

# ──────────────────────────────────────────────
# 2. 构建上下文：完整文件内容（上限500行/文件）
# ──────────────────────────────────────────────
echo "" > "$CONTEXT_FILE"

for f in "${REVIEW_FILES[@]}"; do
  if [ ! -f "$f" ]; then continue; fi
  lines=$(wc -l < "$f" 2>/dev/null || echo 0)
  {
    echo ""
    echo "━━━ 文件: $f ($lines 行) ━━━"
    if [ "$lines" -le 500 ]; then
      cat "$f"
    else
      head -n 500 "$f"
      echo ""
      echo "… [文件过长，仅显示前500行，共${lines}行]"
    fi
    echo ""
  } >> "$CONTEXT_FILE"
done

CONTEXT_SIZE=$(wc -c < "$CONTEXT_FILE")
echo "Context built: $CONTEXT_SIZE bytes"

# ──────────────────────────────────────────────
# 3. 大 PR 处理
# ──────────────────────────────────────────────
TOTAL_REVIEW_FILES=${#REVIEW_FILES[@]}

if [ "$TOTAL_REVIEW_FILES" -gt 15 ] || [ "$DIFF_SIZE" -gt 80000 ]; then
  echo "Large PR - reviewing logic files only"
  for i in "${!REVIEW_FILES[@]}"; do
    f="${REVIEW_FILES[$i]}"
    if [ "${FILE_CLASSES[$i]}" = "logic" ]; then
      awk -v file="$f" '
        /^diff --git/ { show=0 }
        $0 ~ "diff --git a/"file { show=1 }
        show { print }
      ' "$DIFF_FILE" >> /tmp/pr-filtered.diff 2>/dev/null || true
    fi
  done
  if [ -f /tmp/pr-filtered.diff ] && [ -s /tmp/pr-filtered.diff ]; then
    mv /tmp/pr-filtered.diff "$DIFF_FILE"
    echo "Filtered diff: $(wc -c < "$DIFF_FILE") bytes"
  fi
fi

# ──────────────────────────────────────────────
# 4. 调用 DeepSeek API
# ──────────────────────────────────────────────
echo "Sending to DeepSeek..."

RULES=$(cat "$RULES_FILE")
CONTEXT=$(cat "$CONTEXT_FILE")
DIFF=$(cat "$DIFF_FILE")

jq -n \
  --arg rules "$RULES" \
  --arg context "$CONTEXT" \
  --arg diff "$DIFF" \
  '{
    model: "deepseek-v4-pro",
    max_tokens: 4096,
    messages: [{
      role: "user",
      content: (
        "你是一个代码审查员。请根据审查规则检查代码变更。\n\n"
        + "## 输出要求\n"
        + "对每个发现的问题，严格按以下格式输出一行：\n"
        + "  [严重程度] 文件:行号 说明\n"
        + "严重程度必须是 CRITICAL / HIGH / MEDIUM / LOW。\n"
        + "如果没有发现问题，输出：未发现问题。\n"
        + "不要输出前言、总结或 markdown 标题。使用中文。\n"
        + "行号必须基于下面提供的完整文件内容确定。\n\n"
        + "## 输出统计\n"
        + "在所有问题之后，附加一行统计：\n"
        + "  ##STATS## files=N logic=N skipped=N crit=N high=N med=N low=N\n\n"
        + "--- 审查规则 ---\n\($rules)\n\n"
        + "--- 修改的文件（完整内容）---\n\($context)\n\n"
        + "--- GIT DIFF ---\n\($diff)"
      )
    }]
  }' \
  | curl -s --max-time 180 \
    https://api.deepseek.com/anthropic/v1/messages \
    -H "x-api-key: $DEEPSEEK_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d @- > "$RESPONSE_FILE"

# ──────────────────────────────────────────────
# 5. 解析响应
# ──────────────────────────────────────────────
REVIEW_TEXT=$(jq -r '
  [.content[] | select(.type == "text") | .text] | join("\n")
' "$RESPONSE_FILE" 2>/dev/null)
if [ -z "$REVIEW_TEXT" ]; then
  REVIEW_TEXT=$(jq -r '
    [.content[] | select(.type == "thinking") | .thinking] | join("\n")
  ' "$RESPONSE_FILE" 2>/dev/null)
fi

if [ -z "$REVIEW_TEXT" ] || [ "$REVIEW_TEXT" = "null" ]; then
  echo "=== AI review failed - raw response ==="
  head -c 3000 "$RESPONSE_FILE"
  ERROR_MSG=$(jq -r '.error.message // "Unknown API error"' "$RESPONSE_FILE" 2>/dev/null)
  echo "AI review API error: $ERROR_MSG"
  echo "AI review skipped due to API error: $ERROR_MSG" > "$REVIEW_FILE"
  gh pr review "$PR_NUMBER" --repo "$OWNER/$REPO" --body-file "$REVIEW_FILE" --comment
  exit 0
fi

echo "$REVIEW_TEXT" > /tmp/review-raw.txt
echo "=== AI Review Result ==="
head -20 /tmp/review-raw.txt

# ──────────────────────────────────────────────
# 6. 解析行级问题，构建 inline comments
# ──────────────────────────────────────────────
echo "[" > "$INLINE_FILE"
first=1

while IFS= read -r line; do
  # Parse: [SEVERITY] path:line description
  if [[ "$line" =~ ^\[(CRITICAL|HIGH|MEDIUM|LOW)\]\ ([^:]+):([0-9]+)\ (.*) ]]; then
    severity="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
    linenum="${BASH_REMATCH[3]}"
    body="${BASH_REMATCH[4]}"

    # Validate file exists (relative to repo root)
    if [ -f "$path" ] && [ "$linenum" -gt 0 ] 2>/dev/null; then
      [ $first -eq 0 ] && echo "," >> "$INLINE_FILE"
      first=0
      jq -n --arg path "$path" --argjson line "$linenum" --arg body "[$severity] $body" \
        '{path: $path, line: $line, body: $body}' >> "$INLINE_FILE"
      echo "  INLINE: $path:$linenum [$severity]"
    else
      echo "  SKIP (file not found): path=[$path] line=$linenum"
    fi
  fi
done < /tmp/review-raw.txt

echo "]" >> "$INLINE_FILE"
COMMENT_COUNT=$(jq 'length' "$INLINE_FILE" 2>/dev/null || echo 0)
echo "Inline comments: $COMMENT_COUNT"

# ──────────────────────────────────────────────
# 7. 组装 review body
# ──────────────────────────────────────────────
grep -v '##STATS##' /tmp/review-raw.txt > "$REVIEW_FILE" 2>/dev/null || true

STATS_LINE=$(grep '##STATS##' /tmp/review-raw.txt 2>/dev/null || echo "")

{
  echo ""
  echo "---"
  echo "### 审查统计"
  echo "- 修改: ${#CHANGED_FILES[@]} 个文件 | 审查: ${#REVIEW_FILES[@]} 个 | 跳过: ${#SKIPPED_FILES[@]} 个"
  if [ -n "$STATS_LINE" ]; then
    echo "- ${STATS_LINE##\#\#STATS\#\# }"
  fi
  echo "- 模型: deepseek-v4-pro"
} >> "$REVIEW_FILE"

echo "=== Review Body ==="
cat "$REVIEW_FILE"

# ──────────────────────────────────────────────
# 8. 发布审查
# ──────────────────────────────────────────────
if [ "$COMMENT_COUNT" -gt 0 ] && [ -n "$HEAD_SHA" ]; then
  echo "Posting review with $COMMENT_COUNT inline comments..."

  jq -n \
    --arg body "$(cat "$REVIEW_FILE")" \
    --arg commit_id "$HEAD_SHA" \
    --argjson comments "$(cat "$INLINE_FILE")" \
    '{body: $body, event: "COMMENT", commit_id: $commit_id, comments: $comments}' \
    > /tmp/review-payload.json

  if gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" \
    --input /tmp/review-payload.json --silent 2>&1; then
    echo "Inline review posted successfully"
  else
    echo "Inline review failed, falling back to plain comment"
    gh pr review "$PR_NUMBER" --repo "$OWNER/$REPO" --body-file "$REVIEW_FILE" --comment
  fi
else
  echo "No inline comments, posting plain review"
  gh pr review "$PR_NUMBER" --repo "$OWNER/$REPO" --body-file "$REVIEW_FILE" --comment
fi

echo "=== AI Review Complete ==="
