#!/bin/bash
set -e

PR_NUMBER="$1"
HEAD_SHA="$2"
OWNER="${GITHUB_REPOSITORY%/*}"
REPO="${GITHUB_REPOSITORY#*/}"
RULES_FILE="/tmp/ai-review-rules.md"
# 项目有自定义规则就用项目的，否则用共享默认
if [ -f ".github/ai-review-rules.md" ]; then
  RULES_FILE=".github/ai-review-rules.md"
  echo "Using project-specific review rules"
fi

# ── 语言自动检测 & 动态规则合并 ──
SHARED_RULES_DIR="_shared/rules"
DETECTED_LANGS=""
[ -f "go.mod" ] && DETECTED_LANGS="$DETECTED_LANGS go"
[ -f "package.json" ] && DETECTED_LANGS="$DETECTED_LANGS node"
[ -f "pom.xml" ] || [ -f "build.gradle" ] && DETECTED_LANGS="$DETECTED_LANGS java"
[ -f "requirements.txt" ] || [ -f "pyproject.toml" ] && DETECTED_LANGS="$DETECTED_LANGS python"
[ -f "CMakeLists.txt" ] || [ -f "Makefile" ] || [ -f "meson.build" ] && DETECTED_LANGS="$DETECTED_LANGS c"
echo "Detected languages:${DETECTED_LANGS:- none}"

# 追加语言特定规则
for lang in $DETECTED_LANGS; do
  LANG_RULES_FILE="$SHARED_RULES_DIR/$lang.md"
  if [ -f "$LANG_RULES_FILE" ]; then
    cat "$LANG_RULES_FILE" >> "$RULES_FILE"
    echo "  + appended rules/$lang.md"
  fi
done

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
    max_tokens: 8192,
    messages: [{
      role: "user",
      content: (
        "## 角色\n"
        + "你是资深代码审查专家，15年全栈经验，专注安全漏洞检测、性能优化和代码质量。\n\n"
        + "## 审查范围（只查这些）\n"
        + "1. 安全漏洞：注入攻击、认证缺陷、密钥泄露、不安全反序列化\n"
        + "2. 错误处理：吞错误、敏感信息泄露、输入校验缺失、幂等性\n"
        + "3. 性能问题：N+1查询、缺少索引、无超时的外部调用\n"
        + "4. 代码质量：死代码、魔法数字、过长函数、重复代码\n"
        + "5. 数据库迁移：NOT NULL无默认值、破坏性变更\n"
        + "6. 测试覆盖：未测试的错误分支、边界条件缺失\n\n"
        + "## 不要查（忽略这些）\n"
        + "- 代码格式和风格（已由 linter/formatter 处理）\n"
        + "- 注释是否完整（除非代码会误导人）\n"
        + "- 变量命名偏好（除非单字符非循环变量）\n"
        + "- 无具体理由的'建议使用XX模式'\n\n"
        + "## 输出格式\n"
        + "每个问题一行：[严重程度] 文件:行号 分类 说明\n"
        + "严重程度：CRITICAL | HIGH | MEDIUM | LOW\n"
        + "分类：安全 | 错误处理 | 性能 | 代码质量 | DB迁移 | 测试\n"
        + "无问题时输出：未发现问题。\n"
        + "不要输出前言、总结或markdown标题。使用中文。\n\n"
        + "## 输出统计\n"
        + "最后加一行：##STATS## files=N logic=N skipped=N crit=N high=N med=N low=N\n\n"
        + "## 审查规则\n\($rules)\n\n"
        + "## 修改的文件（完整内容）\n\($context)\n\n"
        + "## GIT DIFF\n\($diff)"
      )
    }]
  }' \
  | curl -s --max-time 300 \
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
# 7. 审查决策 + 组装 review body
# ──────────────────────────────────────────────
grep -v '##STATS##' /tmp/review-raw.txt > "$REVIEW_FILE" 2>/dev/null || true

STATS_LINE=$(grep '##STATS##' /tmp/review-raw.txt 2>/dev/null || echo "")

# ──────────────────────────────────────────────
# 7. 审查决策：统计严重程度，决定 APPROVE / REQUEST_CHANGES / COMMENT
# ──────────────────────────────────────────────
CRIT_COUNT=$(grep -c '^\[CRITICAL\]' /tmp/review-raw.txt 2>/dev/null | tr -d '[:space:]'); CRIT_COUNT=${CRIT_COUNT:-0}
HIGH_COUNT=$(grep -c '^\[HIGH\]' /tmp/review-raw.txt 2>/dev/null | tr -d '[:space:]'); HIGH_COUNT=${HIGH_COUNT:-0}
MED_COUNT=$(grep -c '^\[MEDIUM\]' /tmp/review-raw.txt 2>/dev/null | tr -d '[:space:]'); MED_COUNT=${MED_COUNT:-0}
LOW_COUNT=$(grep -c '^\[LOW\]' /tmp/review-raw.txt 2>/dev/null | tr -d '[:space:]'); LOW_COUNT=${LOW_COUNT:-0}

if [ "$CRIT_COUNT" -eq 0 ] && [ "$HIGH_COUNT" -eq 0 ]; then
  EVENT="APPROVE"
  DECISION="AI审查通过 - 无严重问题，建议合并"
elif [ "$CRIT_COUNT" -gt 0 ]; then
  EVENT="REQUEST_CHANGES"
  DECISION="AI审查阻止 - 存在 ${CRIT_COUNT} 个 CRITICAL 问题，必须修复后重新提交"
else
  EVENT="COMMENT"
  DECISION="AI审查建议 - 存在 ${HIGH_COUNT} 个 HIGH 问题，请人工确认后合并"
fi

{
  echo ""
  echo "---"
  echo "### 审查统计"
  echo "- 修改: ${#CHANGED_FILES[@]} 个文件 | 审查: ${#REVIEW_FILES[@]} 个 | 跳过: ${#SKIPPED_FILES[@]} 个"
  if [ -n "$STATS_LINE" ]; then
    echo "- ${STATS_LINE##\#\#STATS\#\# }"
  fi
  echo "- 模型: deepseek-v4-pro"
  echo ""
  echo "**${DECISION}**"
} >> "$REVIEW_FILE"

echo "Decision: $DECISION (CRIT=$CRIT_COUNT HIGH=$HIGH_COUNT MED=$MED_COUNT LOW=$LOW_COUNT)"

# ──────────────────────────────────────────────
# 8. 发布审查（统一走 Reviews API，确保 APPROVE/REQUEST_CHANGES 生效）
# ──────────────────────────────────────────────
case "$EVENT" in
  APPROVE)          FLAG="--approve" ;;
  REQUEST_CHANGES)  FLAG="--request-changes" ;;
  *)                FLAG="--comment" ;;
esac

echo "Posting review as $EVENT with $COMMENT_COUNT inline comments..."

jq -n \
  --arg body "$(cat "$REVIEW_FILE")" \
  --arg event "$EVENT" \
  --arg commit_id "$HEAD_SHA" \
  --argjson comments "$(cat "$INLINE_FILE")" \
  '{body: $body, event: $event, commit_id: $commit_id, comments: $comments}' \
  > /tmp/review-payload.json

if gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" \
  --input /tmp/review-payload.json --silent 2>&1; then
  echo "Review posted as $EVENT"
else
  echo "Reviews API failed, falling back to gh pr review $FLAG"
  gh pr review "$PR_NUMBER" --repo "$OWNER/$REPO" --body-file "$REVIEW_FILE" $FLAG
fi

echo "=== AI Review Complete ==="
