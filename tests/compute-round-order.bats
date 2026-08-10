#!/usr/bin/env bats

# Tests for compute-round-order.sh
# Mock gh-graphql.sh and gh via WHOLEWORK_SCRIPT_DIR (modules/tech.md § BATS Mocking Convention).

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/compute-round-order.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    cat > "$MOCK_DIR/gh-graphql.sh" << 'MOCK_EOF'
#!/bin/bash
NUM=""
prev=""
for a in "$@"; do
    if [[ "$prev" == "-F" && "$a" == num=* ]]; then
        NUM="${a#num=}"
    fi
    prev="$a"
done
args=("$@")
JQ_EXPR=""
for i in "${!args[@]}"; do
    if [[ "${args[$i]}" == "--jq" ]]; then
        JQ_EXPR="${args[$((i+1))]}"
    fi
done

case "$NUM" in
    100)
        RESPONSE='{"data":{"repository":{"issue":{"title":"detect-wrapper-anomaly: split pattern","projectItems":{"nodes":[{"fieldValues":{"nodes":[{"field":{"name":"Size"},"value":"XS"},{"field":{"name":"Value"},"value":"5"}]}}]}}}}}'
        ;;
    200)
        RESPONSE='{"data":{"repository":{"issue":{"title":"low roi issue","projectItems":{"nodes":[{"fieldValues":{"nodes":[{"field":{"name":"Size"},"value":"XL"},{"field":{"name":"Value"},"value":"1"}]}}]}}}}}'
        ;;
    300)
        RESPONSE='{"data":{"repository":{"issue":{"title":"neutral fallback issue","projectItems":{"nodes":[{"fieldValues":{"nodes":[]}}]}}}}}'
        ;;
    *)
        RESPONSE='{"data":{"repository":{"issue":{"title":null,"projectItems":{"nodes":[]}}}}}'
        ;;
esac

echo "$RESPONSE" | jq "$JQ_EXPR"
MOCK_EOF
    chmod +x "$MOCK_DIR/gh-graphql.sh"

    # Default gh mock: no labels (used only as fallback when Project fields are absent)
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" ]]; then
    if [[ "$*" == *"labels"* ]]; then
        echo ""
    elif [[ "$*" == *"title"* ]]; then
        echo ""
    fi
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "ROI calculation: Value=5/Size=XS beats Value=1/Size=XL" {
    run bash "$SCRIPT" "100 200"
    [ "$status" -eq 0 ]
    HIGH_ROI=$(echo "$output" | awk -F'\t' '$1==100{print $4}')
    LOW_ROI=$(echo "$output" | awk -F'\t' '$1==200{print $4}')
    [ "$HIGH_ROI" = "5.00" ]
    [ "$LOW_ROI" = "0.20" ]
}

@test "neutral fallback: Value and Size both unset -> roi=1.00" {
    run bash "$SCRIPT" "300"
    [ "$status" -eq 0 ]
    ROI=$(echo "$output" | awk -F'\t' '{print $4}')
    [ "$ROI" = "1.00" ]
}

@test "output preserves input order (no reordering)" {
    run bash "$SCRIPT" "300 100 200"
    [ "$status" -eq 0 ]
    NUMBERS=$(echo "$output" | awk -F'\t' '{print $1}' | tr '\n' ' ')
    [ "$NUMBERS" = "300 100 200 " ]
}

@test "output format: 5 tab-separated columns" {
    run bash "$SCRIPT" "100"
    [ "$status" -eq 0 ]
    COLS=$(echo "$output" | awk -F'\t' '{print NF}')
    [ "$COLS" -eq 5 ]
}

@test "title is included in output" {
    run bash "$SCRIPT" "100"
    [ "$status" -eq 0 ]
    [[ "$output" == *"detect-wrapper-anomaly: split pattern"* ]]
}
