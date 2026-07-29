# Testing Child Field Addition

This test verifies that new child fields in nested documents (OBJECT fields with `nestedDoc: true`) are automatically added to the index without requiring re-indexing of previous documents.

## Test Steps

### 1. Build the project
```bash
./gradlew clean installDist test
```

### 2. Start the server
```bash
./build/install/nrtsearch/bin/nrtsearch_server
```

### 3. Create the index
```bash
./build/install/nrtsearch/bin/nrtsearch_client createIndex --indexName childFieldTest
```

### 4. Configure settings
```bash
./build/install/nrtsearch/bin/nrtsearch_client settingsV2 -i childFieldTest -f test_child_field_settings.json
```

### 5. Start the index
```bash
./build/install/nrtsearch/bin/nrtsearch_client startIndex -f test_child_field_start_index.json
```

### 6. Register initial fields (3 child fields: ad_bid_id, campaign_id, max_bid_value)
```bash
./build/install/nrtsearch/bin/nrtsearch_client registerFields -f test_child_field_register_initial.json
```

### 7. Add initial documents
```bash
./build/install/nrtsearch/bin/nrtsearch_client addDocuments -i childFieldTest -f test_child_field_docs_initial.csv -t csv
```

### 8. Commit the index
```bash
./build/install/nrtsearch/bin/nrtsearch_client commit -i childFieldTest
```

### 9. Verify initial data was indexed
Search for all documents to see what's in the index:
```bash
cat > test_child_field_search_all.json << 'EOF'
{
  "indexName": "childFieldTest",
  "startHit": 0,
  "topHits": 100,
  "retrieveFields": ["business_id", "ad_bids.ad_bid_id", "ad_bids.campaign_id", "ad_bids.max_bid_value"],
  "query": {
    "matchAllQuery": {}
  }
}
EOF
./build/install/nrtsearch/bin/nrtsearch_client search -f test_child_field_search_all.json
```

**Now manually run the following steps:**

### 10. Update schema to add new child field (dayparting_hours_index)
This step adds a 4th child field without re-registering existing fields:
```bash
./build/install/nrtsearch/bin/nrtsearch_client registerFields -f test_child_field_update_schema.json
```

### 11. Add documents with the new child field
```bash
./build/install/nrtsearch/bin/nrtsearch_client addDocuments -i childFieldTest -f test_child_field_docs_updated.csv -t csv
```

### 12. Commit the index again
```bash
./build/install/nrtsearch/bin/nrtsearch_client commit -i childFieldTest
```

### 13. Search using the new child field
This query searches for documents where `ad_bids.dayparting_hours_index` contains `12` (should match business_id 3):
```bash
./build/install/nrtsearch/bin/nrtsearch_client search -f test_child_field_search.json
```

### 14. Verify all data including new field
```bash
cat > test_child_field_search_all_with_new_field.json << 'EOF'
{
  "indexName": "childFieldTest",
  "startHit": 0,
  "topHits": 100,
  "retrieveFields": ["business_id", "ad_bids.ad_bid_id", "ad_bids.campaign_id", "ad_bids.max_bid_value", "ad_bids.dayparting_hours_index"],
  "query": {
    "matchAllQuery": {}
  }
}
EOF
./build/install/nrtsearch/bin/nrtsearch_client search -f test_child_field_search_all_with_new_field.json
```

## Expected Results

- **Step 9 (registerFields)**: Should succeed without errors. The new `dayparting_hours_index` child field is automatically registered.
- **Step 10 (addDocuments)**: Should successfully index documents with the new child field.
- **Step 12 (search)**: Should return business_id 3 which has `dayparting_hours_index` containing value 12.

## Key Assertions

1. The new child field is automatically available without manual registration
2. Documents indexed before the schema update (business_id 1, 2) remain queryable
3. Documents indexed after the schema update (business_id 3) include the new child field
4. Backward compatibility is maintained - old documents don't need to be re-indexed
