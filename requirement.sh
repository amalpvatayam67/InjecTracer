#!/bin/bash
set -e

echo "[*] Setting up Interactsh (compiled from source) in env/..."

cd "$(dirname "$0")"

if ! command -v go &>/dev/null; then
    echo "[-] Go not found. Please install Go and retry."
    exit 1
fi

if [[ ! -d interactsh ]]; then
    echo "[*] Cloning Interactsh client..."
    git clone https://github.com/projectdiscovery/interactsh.git
fi


cd interactsh/cmd/interactsh-client
go build -o ../../../env/interactsh-client .

cd ../../../env
chmod +x interactsh-client

echo "[+] Build complete. Binary is in $(pwd)/interactsh-client"
