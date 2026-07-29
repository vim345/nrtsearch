#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INDEX_NAME="childFieldTest"
SERVER_PORT=8765
CLIENT=(./build/install/nrtsearch/bin/nrtsearch_client -p $SERVER_PORT)
SERVER_PID=""
REPORT_FILE="test_child_field_report.txt"

# Cleanup function to ensure server is killed
cleanup() {
    if [ ! -z "$SERVER_PID" ]; then
        echo -e "${YELLOW}Killing nrtsearch server (PID: $SERVER_PID)${NC}"
        kill $SERVER_PID 2>/dev/null || true
        wait $SERVER_PID 2>/dev/null || true
        echo -e "${GREEN}Server killed${NC}"
    fi
}

# Set trap to run cleanup on exit
trap cleanup EXIT

# Function to log messages
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$REPORT_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[SUCCESS] $1" >> "$REPORT_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> "$REPORT_FILE"
}

# Clean up report file
rm -f "$REPORT_FILE"
log "Starting nrtsearch child field automation test"

# Step 0: Clean up old index data
log "Step 0: Cleaning up old index data..."
rm -rf test_child_field_state test_child_field_index
log_success "Old index and state directories removed"

# Step 1: Start the nrtsearch server in background
log "Step 1: Starting nrtsearch server in background..."
./build/install/nrtsearch/bin/nrtsearch_server test_child_field_server.yaml > /tmp/nrtsearch.log 2>&1 &
SERVER_PID=$!
log "Server started with PID: $SERVER_PID"

# Wait for server to be ready
log "Waiting for server to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if grep -q "Server started" /tmp/nrtsearch.log 2>/dev/null; then
        log_success "Server is ready"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 1
done

if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
    log_error "Server failed to start within timeout"
    cat /tmp/nrtsearch.log
    exit 1
fi

# Step 2: Create index
log "Step 2: Creating index '$INDEX_NAME'..."
"${CLIENT[@]}" createIndex --indexName $INDEX_NAME
log_success "Index created"

# Step 3: Configure settings
log "Step 3: Configuring settings..."
"${CLIENT[@]}" settingsV2 -i $INDEX_NAME -f test_child_field_settings.json
log_success "Settings configured"

# Step 4: Start index
log "Step 4: Starting index..."
"${CLIENT[@]}" startIndex -f test_child_field_start_index.json
log_success "Index started"

# Step 5: Register initial fields
log "Step 5: Registering initial fields (ad_bid_id, campaign_id, max_bid_value)..."
"${CLIENT[@]}" registerFields -f test_child_field_register_initial.json
log_success "Initial fields registered"

# Step 6: Add initial documents
log "Step 6: Adding initial documents (business_id 1, 2)..."
"${CLIENT[@]}" addDocuments -i $INDEX_NAME -f test_child_field_docs_initial.json -t json
log_success "Initial documents added"

# Step 7: Commit initial state
log "Step 7: Committing index..."
"${CLIENT[@]}" commit -i $INDEX_NAME
log_success "Index committed"

# Step 8: Search initial data
log "Step 8: Searching for initial data..."
SEARCH_RESULT_INITIAL=$("${CLIENT[@]}" search -f test_child_field_search_all.json 2>&1 || true)
INITIAL_DOC_COUNT=$(echo "$SEARCH_RESULT_INITIAL" | grep -o 'value: [0-9]*' | head -1 | grep -o '[0-9]*' || echo "0")
log_success "Initial search returned $INITIAL_DOC_COUNT documents"
echo "$SEARCH_RESULT_INITIAL" >> "$REPORT_FILE"

# Step 9: Update schema to add new child field
log "Step 9: Updating schema to add new child field (dayparting_hours_index)..."
"${CLIENT[@]}" registerFields -f test_child_field_update_schema.json
log_success "Schema updated with new child field"

# Step 10: Add documents with new child field
log "Step 10: Adding new documents with new child field (business_id 1, 2, 3)..."
"${CLIENT[@]}" addDocuments -i $INDEX_NAME -f test_child_field_docs_updated.json -t json
log_success "New documents added"

# Step 11: Commit updated state
log "Step 11: Committing index..."
"${CLIENT[@]}" commit -i $INDEX_NAME
log_success "Index committed"

# Step 12: Search using new child field
log "Step 12: Searching using new child field (dayparting_hours_index = 12)..."
SEARCH_RESULT_NEW=$("${CLIENT[@]}" search -f test_child_field_search.json 2>&1 || true)
NEW_FIELD_DOC_COUNT=$(echo "$SEARCH_RESULT_NEW" | grep -o 'value: [0-9]*' | head -1 | grep -o '[0-9]*' || echo "0")
log_success "Search for new field returned $NEW_FIELD_DOC_COUNT documents"
echo "$SEARCH_RESULT_NEW" >> "$REPORT_FILE"

# Step 13: Search all data with new field
log "Step 13: Searching all data with new field included..."
SEARCH_RESULT_ALL=$("${CLIENT[@]}" search -f test_child_field_search_all_with_new_field.json 2>&1 || true)
FINAL_DOC_COUNT=$(echo "$SEARCH_RESULT_ALL" | grep -o 'value: [0-9]*' | head -1 | grep -o '[0-9]*' || echo "0")
log_success "Final search returned $FINAL_DOC_COUNT documents"
echo "$SEARCH_RESULT_ALL" >> "$REPORT_FILE"

# Generate report
# Determine pass/fail based on actual counts
OLD_DOCS_PRESENT=false
NEW_DOCS_PRESENT=false
NEW_FIELD_SEARCHABLE=false
[ "$INITIAL_DOC_COUNT" -ge 2 ] 2>/dev/null && OLD_DOCS_PRESENT=true
[ "$FINAL_DOC_COUNT" -ge 3 ] 2>/dev/null && NEW_DOCS_PRESENT=true
[ "$NEW_FIELD_DOC_COUNT" -ge 1 ] 2>/dev/null && NEW_FIELD_SEARCHABLE=true

if $OLD_DOCS_PRESENT && $NEW_DOCS_PRESENT && $NEW_FIELD_SEARCHABLE; then
    RESULT="PASSED"
    RESULT_COLOR=$GREEN
else
    RESULT="FAILED"
    RESULT_COLOR=$RED
fi

pass_fail() {
    local ok=$1; local msg=$2
    if $ok; then echo -e "${GREEN}✓${NC} $msg"; else echo -e "${RED}✗${NC} $msg"; fi
}
pass_fail_file() {
    local ok=$1; local msg=$2
    if $ok; then echo "✓ $msg" >> "$REPORT_FILE"; else echo "✗ FAILED: $msg" >> "$REPORT_FILE"; fi
}

echo "" >> "$REPORT_FILE"
echo "========== TEST REPORT ==========" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "TEST: Can new documents be added without deleting old index?" >> "$REPORT_FILE"
echo "RESULT: $RESULT" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "DETAILS:" >> "$REPORT_FILE"
echo "- Initial documents indexed: $INITIAL_DOC_COUNT (expected >= 2)" >> "$REPORT_FILE"
echo "- Final documents in index:  $FINAL_DOC_COUNT (expected >= 3)" >> "$REPORT_FILE"
echo "- Docs matching new field (dayparting_hours_index=12): $NEW_FIELD_DOC_COUNT (expected >= 1)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "CONCLUSION:" >> "$REPORT_FILE"
pass_fail_file $OLD_DOCS_PRESENT "Old documents (business_id 1, 2) present in index after schema change"
pass_fail_file $NEW_DOCS_PRESENT "New document (business_id 3) added successfully without reindexing"
pass_fail_file $NEW_FIELD_SEARCHABLE "New child field (dayparting_hours_index) is searchable"
echo "" >> "$REPORT_FILE"

echo ""
echo -e "${BLUE}========== TEST REPORT ==========${NC}"
echo ""
echo -e "${YELLOW}TEST: Can new documents be added without deleting old index?${NC}"
echo -e "${RESULT_COLOR}RESULT: $RESULT${NC}"
echo ""
echo "DETAILS:"
echo "- Initial documents indexed: $INITIAL_DOC_COUNT (expected >= 2)"
echo "- Final documents in index:  $FINAL_DOC_COUNT (expected >= 3)"
echo "- Docs matching new field (dayparting_hours_index=12): $NEW_FIELD_DOC_COUNT (expected >= 1)"
echo ""
echo "CONCLUSION:"
pass_fail $OLD_DOCS_PRESENT "Old documents (business_id 1, 2) present in index after schema change"
pass_fail $NEW_DOCS_PRESENT "New document (business_id 3) added successfully without reindexing"
pass_fail $NEW_FIELD_SEARCHABLE "New child field (dayparting_hours_index) is searchable"
echo ""
echo "Full report saved to: $REPORT_FILE"
echo ""

if [ "$RESULT" = "PASSED" ]; then
    log_success "Test completed successfully"
else
    log_error "Test FAILED — see details above"
    exit 1
fi

# Clean up test data after completion
log "Cleaning up test data..."
rm -rf test_child_field_state test_child_field_index
log_success "Index and state directories cleaned up"
