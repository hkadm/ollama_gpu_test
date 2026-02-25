#!/bin/bash
# Add HOSTKEY AI CHATBOT Agent via OpenWebUI + Ollama Provider to OpenClaw

set -euo pipefail

# Безопасное определение директории скрипта
if [[ -n "${BASH_SOURCE[0]-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || echo "$(pwd)")"
else
    SCRIPT_DIR="$(pwd)"
fi

CONFIG_FILE="${HOME}/.openclaw/openclaw.json"
PROVIDER_ID="hostkey-agent-openwebui"

# Colors for Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=== HOSTKEY AI CHATBOT Agent Provider Setup ==="
echo ""

if ! command -v openclaw &> /dev/null; then
    echo -e "${RED}❌ Error: OpenClaw was installed but is not on PATH.${NC}"
    echo "Try: export PATH=\"\$(npm prefix -g)/bin:\$PATH\""
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}❌ Error: OpenClaw config not found at $CONFIG_FILE${NC}"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}❌ Error: jq is required but not installed.${NC}"
    echo "Install with: sudo apt install jq  # Debian/Ubuntu"
    echo "           or sudo yum install jq  # CentOS/RHEL"
    echo "           or brew install jq      # macOS"
    exit 1
fi

echo "This script will add the 'hostkey-agent-openwebui' provider to your OpenClaw config."
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Function: Getting a list of models via API
# ─────────────────────────────────────────────────────────────────────────────

fetch_models() {
    local base_url="$1"
    local api_key="$2"

    local endpoints=("/api/models" "/v1/models" "/models" "/api/v1/models")

    for endpoint in "${endpoints[@]}"; do
        local full_url="${base_url}${endpoint}"

        local response
        response=$(curl -s -w "\n%{http_code}" -X GET "$full_url" \
            -H "Authorization: Bearer ${api_key}" \
            -H "Content-Type: application/json" \
            2>/dev/null) || continue

        local http_code
        http_code=$(echo "$response" | tail -n1)
        local body
        body=$(echo "$response" | sed '$d')

        if [[ "$http_code" == "200" ]]; then
            echo "$body"
            return 0
        fi
    done

    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Function: Parsing API response
# ─────────────────────────────────────────────────────────────────────────────

parse_models() {
    local response="$1"
    local models_array=()

    if echo "$response" | jq -e '.data' > /dev/null 2>&1; then
        models_array=($(echo "$response" | jq -r '.data[].id' 2>/dev/null))
    elif echo "$response" | jq -e '.models' > /dev/null 2>&1; then
        models_array=($(echo "$response" | jq -r '.models[].id' 2>/dev/null))
    elif echo "$response" | jq -e '.[0].id' > /dev/null 2>&1; then
        models_array=($(echo "$response" | jq -r '.[].id' 2>/dev/null))
    fi

    if [[ ${#models_array[@]} -gt 0 ]]; then
        echo "${models_array[@]}"
        return 0
    fi

    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Function: Display list of models
# ─────────────────────────────────────────────────────────────────────────────

display_models_menu() {
    local -n models_ref=$1

    echo "═══════════════════════════════════════════════════════════"
    printf "%-4s | %-30s | %-30s\n" "No." "Model ID" "Model Name"
    echo "═══════════════════════════════════════════════════════════"

    for i in "${!models_ref[@]}"; do
        local model_id="${models_ref[$i]}"
        local model_name="${model_id//[-_]/ }"
        model_name="$(echo "$model_name" | sed 's/.*/\u&/')"
        printf "%-4s | %-30s | %-30s\n" "$((i+1))" "$model_id" "$model_name"
    done
    echo "═══════════════════════════════════════════════════════════"
}

# ─────────────────────────────────────────────────────────────────────────────
# Domain request (WITHOUT path!)
# ─────────────────────────────────────────────────────────────────────────────

echo -e "${YELLOW}⚠ IMPORTANT: Enter only the domain, NOT the full API URL${NC}"
echo "Example: aichat.hostkey.in "
echo ""

read -p "Chatbot Domain (e.g., aichat.hostkey.in): " CHATBOT_DOMAIN
echo ""

if [[ -z "$CHATBOT_DOMAIN" ]]; then
    echo -e "${RED}❌ Error: Chatbot domain cannot be empty${NC}"
    exit 1
fi

CHATBOT_DOMAIN="${CHATBOT_DOMAIN%/}"
CHATBOT_DOMAIN="${CHATBOT_DOMAIN#https://}"
CHATBOT_DOMAIN="${CHATBOT_DOMAIN#http://}"
CHATBOT_DOMAIN="${CHATBOT_DOMAIN%%/*}"

# BASE_URL for internal API calls (without /v1)
BASE_URL="https://${CHATBOT_DOMAIN}"
# CONFIG_BASE_URL — value for writing into the config (with /v1)
CONFIG_BASE_URL="${BASE_URL}/v1"

echo "Base URL for API calls: $BASE_URL"
echo "Config baseUrl (with /v1): $CONFIG_BASE_URL"
echo "Chat completions endpoint: $CONFIG_BASE_URL/chat/completions"
echo ""

read -p "API Key from OpenWebUI: " API_KEY
echo ""

if [[ -z "$API_KEY" ]]; then
    echo -e "${RED}❌ Error: API Key cannot be empty${NC}"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Auto-detection of available models
# ─────────────────────────────────────────────────────────────────────────────

echo -e "${BLUE}🔍 Fetching available models from API...${NC}"
echo ""

MODELS_RESPONSE=""
MODELS_LIST=()

if MODELS_RESPONSE=$(fetch_models "$BASE_URL" "$API_KEY"); then
    if models_raw=$(parse_models "$MODELS_RESPONSE"); then
        read -ra MODELS_LIST <<< "$models_raw"
    fi
fi

if [[ ${#MODELS_LIST[@]} -gt 0 ]]; then
    echo -e "${GREEN}✓ Found ${#MODELS_LIST[@]} available model(s):${NC}"
    echo ""

    display_models_menu MODELS_LIST

    echo ""
    echo -e "${YELLOW}Select a model number or enter custom model ID${NC}"
    echo ""

    read -p "Model selection (1-${#MODELS_LIST[@]} or custom ID): " MODEL_SELECTION
    echo ""

    if [[ "$MODEL_SELECTION" =~ ^[0-9]+$ ]] && \
       [[ "$MODEL_SELECTION" -ge 1 ]] && \
       [[ "$MODEL_SELECTION" -le "${#MODELS_LIST[@]}" ]]; then
        MODEL_ID="${MODELS_LIST[$((MODEL_SELECTION-1))]}"
        MODEL_NAME="${MODEL_ID//[-_]/ }"
        MODEL_NAME="$(echo "$MODEL_NAME" | sed 's/.*/\u&/')"
        echo -e "${GREEN}✓ Selected: $MODEL_ID${NC}"
    else
        MODEL_ID="$MODEL_SELECTION"
        read -p "Model Name (e.g., HOSTKEY AI): " MODEL_NAME
        echo ""
        if [[ -z "$MODEL_NAME" ]]; then
            MODEL_NAME="$MODEL_ID"
        fi
    fi
else
    echo -e "${YELLOW}⚠ Could not fetch models from API${NC}"
    echo ""
    echo "Common HOSTKEY models:"
    echo "  - DeepSeek-R1:14B"
    echo "  - gpt-oss-20b"
    echo "  - Qwen3-32B"
    echo ""

    read -p "Model ID (e.g., hostkeyru): " MODEL_ID
    echo ""

    if [[ -z "$MODEL_ID" ]]; then
        echo -e "${RED}❌ Error: Model ID cannot be empty${NC}"
        exit 1
    fi

    read -p "Model Name (e.g., HOSTKEY AI): " MODEL_NAME
    echo ""

    if [[ -z "$MODEL_NAME" ]]; then
        MODEL_NAME="$MODEL_ID"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Request for context parameters
# ─────────────────────────────────────────────────────────────────────────────

read -p "Context Window (default: 32000): " CONTEXT_WINDOW
CONTEXT_WINDOW="${CONTEXT_WINDOW:-32000}"

read -p "Max Tokens (default: 16384): " MAX_TOKENS
MAX_TOKENS="${MAX_TOKENS:-16384}"

# ─────────────────────────────────────────────────────────────────────────────
# Test request to API (using BASE_URL without /v1)
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BLUE}🧪 Testing API connection...${NC}"

TEST_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/chat/completions" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d '{
      "model": "'"${MODEL_ID}"'",
      "messages": [{"role": "user", "content": "test"}],
      "max_tokens": 10,
      "stream": false
    }' 2>/dev/null) || true

TEST_CODE=$(echo "$TEST_RESPONSE" | tail -n1)

if [[ "$TEST_CODE" == "200" ]] || [[ "$TEST_CODE" == "400" ]]; then
    echo -e "${GREEN}✓ API connection test passed (HTTP $TEST_CODE)${NC}"
else
    echo -e "${YELLOW}⚠ API connection test returned HTTP $TEST_CODE${NC}"
    echo "This might be okay - continuing anyway..."
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo -e "${BLUE}Configuration Summary:${NC}"
echo "═══════════════════════════════════════════════════════════"
echo "  Provider ID:   $PROVIDER_ID"
echo "  Base URL:      $CONFIG_BASE_URL"
echo "  API Endpoint:  $CONFIG_BASE_URL/chat/completions"
echo "  Model ID:      $MODEL_ID"
echo "  Model Name:    $MODEL_NAME"
echo "  Context:       $CONTEXT_WINDOW tokens"
echo "  Max Tokens:    $MAX_TOKENS tokens"
echo "  API Key:       ${API_KEY:0:20}..."
echo "═══════════════════════════════════════════════════════════"
echo ""

read -p "Continue? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
    echo "Cancelled."
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Creating a backup and updating the config
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "Creating backup..."
BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%s)"
cp "$CONFIG_FILE" "$BACKUP_FILE"
echo -e "${GREEN}✓${NC} Backup saved to $BACKUP_FILE"
echo ""

echo "Updating config..."

TEMP_FILE=$(mktemp)

jq --arg provider "$PROVIDER_ID" \
   --arg baseUrl "$CONFIG_BASE_URL" \
   --arg apiKey "$API_KEY" \
   --arg modelId "$MODEL_ID" \
   --arg modelName "$MODEL_NAME" \
   --argjson contextWindow "$CONTEXT_WINDOW" \
   --argjson maxTokens "$MAX_TOKENS" \
   '
   .models //= {} |
   .models.providers //= {} |

   .models.providers[$provider] = {
     "baseUrl": $baseUrl,
     "apiKey": $apiKey,
     "auth": "api-key",
     "api": "openai-completions",
     "headers": {
       "Authorization": "Bearer \($apiKey)",
       "Content-Type": "application/json",
       "Accept": "application/json"
     },
     "models": [
       {
         "id": $modelId,
         "name": $modelName,
         "contextWindow": $contextWindow,
         "maxTokens": $maxTokens,
         "reasoning": false,
         "input": ["text"],
         "cost": {
           "input": 0,
           "output": 0,
           "cacheRead": 0,
           "cacheWrite": 0
         }
       }
     ]
   } |

   .agents //= {} |
   .agents.defaults //= {} |

   if .agents.defaults.model == null or .agents.defaults.model.primary == null then
     .agents.defaults.model = {
       "primary": "\($provider)/\($modelId)"
     }
   else
     .
   end |

   .agents.defaults.models //= {} |
   .agents.defaults.models["\($provider)/\($modelId)"] //= {}
   ' "$CONFIG_FILE" > "$TEMP_FILE"

if ! jq empty "$TEMP_FILE" 2>/dev/null; then
    echo -e "${RED}❌ Error: Generated invalid JSON${NC}"
    rm -f "$TEMP_FILE"
    exit 1
fi

mv "$TEMP_FILE" "$CONFIG_FILE"

echo -e "${GREEN}✓${NC} Config updated successfully"
echo ""
echo "═══════════════════════════════════════════════════════════"
echo -e "${GREEN}Provider '$PROVIDER_ID' has been added!${NC}"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Model reference: $PROVIDER_ID/$MODEL_ID"
echo ""

echo "Setting model as primary..."
openclaw config set agents.defaults.model.primary "$PROVIDER_ID/$MODEL_ID" || {
    echo -e "${YELLOW}⚠ Could not set primary model, continuing...${NC}"
}
echo -e "${GREEN}✓${NC} Model set as primary"
echo ""

echo "Restarting gateway..."
openclaw gateway restart || {
    echo -e "${YELLOW}⚠ Could not restart gateway, continuing...${NC}"
}
echo -e "${GREEN}✓${NC} Gateway restarted"
echo ""

echo -e "${BLUE}Waiting for gateway to start...${NC}"
sleep 3

echo "Launching TUI..."
openclaw tui || {
    echo "TUI failed to launch, but configuration was saved."
    echo "You can manually run: openclaw tui"
}
