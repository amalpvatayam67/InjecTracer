#!/bin/bash

INPUT_FILE="input.json"
PAYLOADS_FILE="payloads.txt"
OUTPUT_FILE="results.json"

echo "[" > "$OUTPUT_FILE"

method=$(jq -r '.method' "$INPUT_FILE" | tr '[:lower:]' '[:upper:]')
url_template=$(jq -r '.url' "$INPUT_FILE")
headers=$(jq -r '.headers // {}' "$INPUT_FILE")
body=$(jq -c '.body // empty' "$INPUT_FILE")

while IFS= read -r payload || [[ -n "$payload" ]]; do

    # Default values
    target_url="$url_template"
    location="path"
    post_data=""

    if [[ "$method" == "GET" ]]; then
        if [[ "$url_template" == *"INJECT_HERE"* ]]; then
            target_url=$(echo "$url_template" | sed "s/INJECT_HERE/$payload/")
        else
            echo "INJECT_HERE missing in URL. Skipping payload: $payload"
            continue
        fi

        if [[ "$target_url" == *"?"* ]]; then location="param"; fi

    elif [[ "$method" == "POST" && -n "$body" ]]; then
        post_data=""
        location="body"

        # Replace INJECT_HERE in body
        for key in $(echo "$body" | jq -r 'keys[]'); do
            val=$(echo "$body" | jq -r --arg k "$key" '.[$k]')
            if [[ "$val" == *"INJECT_HERE"* ]]; then
                val="${val/INJECT_HERE/$payload}"
            fi
            post_data+="${key}=$(printf '%s' "$val" | jq -s -R -r @uri)&"
        done
        post_data=${post_data%&}
    else
        echo "POST body missing or invalid. Skipping: $payload"
        continue
    fi

    # Build curl command
    curl_cmd="curl -s --max-time 15 -X $method"
    for key in $(echo "$headers" | jq -r 'keys[]'); do
        val=$(echo "$headers" | jq -r --arg k "$key" '.[$k]')
        curl_cmd+=" -H \"$key: $val\""
    done

    if [[ "$method" == "POST" ]]; then
        curl_cmd+=" -d \"$post_data\" \"$target_url\""
    else
        curl_cmd+=" \"$target_url\""
    fi

    # Execute
    response=$(eval "$curl_cmd")

    # Extract from <pre> or fallback
    clean_output=$(echo "$response" | perl -0777 -ne 'print $1 if /<pre[^>]*>(.*?)<\/pre>/s')
    [[ -z "$clean_output" ]] && clean_output=$(echo "$response" | sed -e 's/<[^>]*>//g' | sed '/^$/d')
    escaped_output=$(printf '%s' "$clean_output" | jq -Rs '.')

    jq -n \
        --arg payload "$payload" \
        --arg url "$target_url" \
        --arg location "$location" \
        --argjson output "$escaped_output" \
        '{payload: $payload, url: $url, location: $location, output: $output}' >> "$OUTPUT_FILE"

    echo "," >> "$OUTPUT_FILE"
done < "$PAYLOADS_FILE"

# Finalize JSON
sed -i '$ d' "$OUTPUT_FILE"
echo "]" >> "$OUTPUT_FILE"

echo "Scan complete. Output saved to $OUTPUT_FILE"
