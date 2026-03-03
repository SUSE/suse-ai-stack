#!/bin/bash
# Script: cleanup_automation_created_dns.sh
# Purpose: Cleanup DNS records created by automation containing 'yarun'

ZONE_ID="70b81a761e0d4f067585d7f6c8c46f95"
API_TOKEN="6F3vWvKr4ZUhqDw12sdkdcrffngVhSd-9VIKg0C6"

deleted_count=0
page=1
per_page=1000

echo "Starting cleanup of yarun DNS records..."

while : ; do
    RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?per_page=$per_page&page=$page" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json")

    COUNT=$(echo "$RESPONSE" | jq '.result | length')
    if [ "$COUNT" -eq 0 ]; then
        break
    fi

    IDS=$(echo "$RESPONSE" | jq -r '.result[] 
        | select((.name|ascii_downcase|contains("yarun")) or (.content|ascii_downcase|contains("yarun"))) 
        | .id')

    for ID in $IDS; do
        curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$ID" \
             -H "Authorization: Bearer $API_TOKEN" \
             -H "Content-Type: application/json" > /dev/null
        echo "Deleted record ID: $ID"
        deleted_count=$((deleted_count+1))
    done

    TOTAL_PAGES=$(echo "$RESPONSE" | jq -r '.result_info.total_pages')
    if [ "$page" -ge "$TOTAL_PAGES" ]; then
        break
    fi
    page=$((page+1))
done

echo "Cleanup complete. Total yarun DNS records deleted: $deleted_count"
