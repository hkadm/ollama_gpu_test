#!/bin/bash

# ========= CREATE TEST DIRECTORY =========
mkdir -p /root/gpu_test

# ========= DEFINE MODEL GROUPS AND MEMORY REQUIREMENTS IN GiB =========
declare -A MODEL_VRAM
MODEL_VRAM=(
    ["deepseek-r1:14b"]="15"
    ["deepseek-r1:32b"]="23"
    ["deepseek-r1:70b"]="48"
    ["gpt-oss:20b"]="14"
    ["gpt-oss:120b"]="70"
    ["qwen3:14b"]="15"
    ["qwen3:32b"]="23"
    ["qwen3-coder-next:q4_K_M"]="55"
    ["qwen3-coder-next:q8_0"]="87"
    ["ministral-3:8b"]="7"
    ["ministral-3:14b"]="11"
)

declare -A MODEL_GROUPS
MODEL_GROUPS["deepseekr1"]="deepseek-r1:14b deepseek-r1:32b deepseek-r1:70b"
MODEL_GROUPS["gpt-oss"]="gpt-oss:20b gpt-oss:120b"
MODEL_GROUPS["qwen3"]="qwen3:14b qwen3:32b qwen3-coder-next:q4_K_M qwen3-coder-next:q8_0"
MODEL_GROUPS["ministral3"]="ministral-3:8b ministral-3:14b"

# Validation: ensure all models in groups are defined in MODEL_VRAM
for group in "${!MODEL_GROUPS[@]}"; do
    for model in ${MODEL_GROUPS[$group]}; do
        if [ -z "${MODEL_VRAM[$model]+_}" ]; then
            echo "Error: model '$model' from group '$group' is not listed in MODEL_VRAM."
            exit 1
        fi
    done
done

# Full list of models for reference
ALL_MODELS=("${!MODEL_VRAM[@]}")

# ========= PARSE COMMAND-LINE ARGUMENTS ==========
TEST_MODE="max"
PROMPT="Generate Tetris game on HTML and JS"
SINGLE_MODEL=""
FIXED_CTX=""
SELECTED_GROUP="deepseekr1"  # default

while getopts "ht:p:m:c:g:" opt; do
  case $opt in
    t)
      if [[ "$OPTARG" == "max" || "$OPTARG" == "test" ]]; then
        TEST_MODE="$OPTARG"
      else
        echo "Error: mode '-t $OPTARG' is not supported. Use 'max' or 'test'."
        exit 1
      fi
      ;;
    p)
      PROMPT="$OPTARG"
      ;;
    m)
      SINGLE_MODEL="$OPTARG"
      ;;
    c)
      if [[ "$OPTARG" =~ ^[0-9]+$ ]] && [ "$OPTARG" -gt 0 ]; then
        FIXED_CTX="$OPTARG"
      else
        echo "Error: -c must be a positive integer (e.g., 8192)."
        exit 1
      fi
      ;;
    g)
      if [ -n "${MODEL_GROUPS[$OPTARG]+_}" ]; then
        SELECTED_GROUP="$OPTARG"
      else
        echo "Error: unknown group '-g $OPTARG'."
        echo "Available groups:"
        for g in "${!MODEL_GROUPS[@]}"; do
            echo "  - $g"
        done
        exit 1
      fi
      ;;
    h)
      cat <<EOF
Usage: $0 [-t max|test] [-p "prompt"] [-m model] [-c ctx] [-g group] [-h]

Options:
  -t MODE     Execution mode:
                max   — run the largest model from the group that fits in memory,
                        then test with increasing context (default). Do not create final report file!
                test  — test all models in the group from smallest to largest and write report to test_result.html
  -p PROMPT   Prompt for generation (default: "Generate Tetris game on HTML and JS")
  -m MODEL    Run ONLY the specified model (ignores -t and -g)
  -c CTX      Use a fixed context size
  -g GROUP    Model group: deepseekr1 (default), gpt-oss, qwen3, ministral3
  -h          Show this help and exit
EOF
      exit 0
      ;;
    \?)
      echo "Usage: $0 [-t max|test] [-p \"prompt\"] [-m model] [-c ctx] [-g group] [-h]" >&2
      exit 1
      ;;
  esac
done

# Function to print test results
print_test_summary() {
    local load_sec="$1"
    local eval_sec="$2"
    local total_tokens="$3"
    local tokens_per_sec="$4"
    local gpu_percent="$5"
    local ollama_ps_output="$6"
    local nvidia_smi_output="$7"

    echo "Ollama PS:"
    echo "$ollama_ps_output"

    if [ -n "$nvidia_smi_output" ]; then
        echo "nvidia-smi:"
        echo "$nvidia_smi_output"
    fi

    echo "Results:"
    echo "- Load time: $(printf "%.3f" "$load_sec") sec"
    echo "- Generation time: $(printf "%.3f" "$eval_sec") sec"
    echo "- Tokens: $total_tokens"
    echo "- Speed: $tokens_per_sec tokens/sec"
    echo "- GPU utilization: ${gpu_percent}%"
}

# ========= STEP 0: INSTALL DEPENDENCIES AND OLLAMA ======
# apt update

echo "Testing has started. The system is being prepared."

for cmd in jq bc; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Installing $cmd..."
        apt install -y "$cmd"
    fi
done

if ! command -v ollama >/dev/null 2>&1 || ! systemctl is-active --quiet ollama 2>/dev/null; then
    echo "Install or reinstall Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
fi

service ollama stop

# ========== STEP 1: DETECT AVAILABLE GPU MEMORY ==========

echo "Determining the available video memory size via ollama serve"

log_output=$(ollama serve 2>&1 & sleep 10; pkill -f "ollama serve" 2>/dev/null)

available_memory=($(echo "$log_output" | grep -o 'available="[^"]*"' | grep -o '[0-9.]*'))

echo "Available GPU memory:"
if [ ${#available_memory[@]} -eq 0 ]; then
    echo "Failed to detect available GPU memory."
    total_available=0
else
    printf '%s GiB\n' "${available_memory[@]}"
    total_available=$(echo "$log_output" | awk -F'available="' '/available="/ { gsub(/".*/, "", $2); sum += $2 } END { print sum+0 }')
fi

echo "Total available memory: $total_available GiB"

sudo service ollama start

echo "Waiting for Ollama API to start..."
timeout 60 bash -c 'until curl -s http://localhost:11434 > /dev/null 2>&1; do sleep 1; done'
if [ $? -ne 0 ]; then
    echo "Error: failed to connect to Ollama API within 60 seconds."
    exit 1
fi

# ========== HELPER FUNCTION: TEST A SINGLE MODEL ==========
test_model() {
    local MODEL="$1"
    local REPORT_MODE="${2:-}"
    local prompt="$PROMPT"
    local min_ctx=4000
    local max_ctx=128000

    if [ -n "$FIXED_CTX" ]; then
        min_ctx="$FIXED_CTX"
        max_ctx="$FIXED_CTX"
    fi

    echo "🚀 Starting model: $MODEL"

    echo "Pulling model..."
    ollama pull "$MODEL" || { echo "❌ Failed to pull model $MODEL"; return 1; }

    echo "Warming up model..."
    curl -s http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d '{
        "model": "'"$MODEL"'",
        "prompt": "Hello",
        "stream": false,
        "options": {
        "num_ctx": 4000
        }
    }' \
    >/dev/null

    local model_results_html=""
    local first_ctx=""

    local num_ctx=$min_ctx
    while [ $num_ctx -le $max_ctx ]; do
        echo
        echo "=== [$MODEL] Testing with num_ctx=$num_ctx ==="

        local response_file="/root/gpu_test/ollama_response_${MODEL//:/_}_ctx${num_ctx}.json"
        curl -s --max-time 300 \
             -H "Content-Type: application/json" \
             -d '{
                 "model": "'"$MODEL"'",
                 "prompt": "'"$prompt"'",
                 "stream": false,
                 "options": {
                     "num_ctx": '"$num_ctx"'
                 }
             }' \
             http://localhost:11434/api/generate > "$response_file"

        if [ ! -s "$response_file" ]; then
            echo "Empty response for $MODEL at num_ctx=$num_ctx"
            break
        fi

        if ! jq empty "$response_file" >/dev/null 2>&1; then
            echo "Invalid JSON for $MODEL at num_ctx=$num_ctx"
            if grep -q "llama runner process has terminated: exit status 2" "$response_file" 2>/dev/null; then
                echo "❗ Fatal error — stopping test for model $MODEL"
            fi
            break
        fi

        local eval_duration_ns=$(jq -r '.eval_duration // 0' "$response_file")
        local load_duration_ns=$(jq -r '.load_duration // 0' "$response_file")
        local total_tokens=$(jq -r '.eval_count // 0' "$response_file")
        local model_response=$(jq -r '.response // ""' "$response_file")

        local eval_sec=$(echo "$eval_duration_ns / 1000000000" | bc -l)
        local load_sec=$(echo "$load_duration_ns / 1000000000" | bc -l)

        local tokens_per_sec=0
        if (( $(echo "$eval_sec > 0.001" | bc -l) )); then
            tokens_per_sec=$(echo "scale=2; $total_tokens / $eval_sec" | bc)
        fi

        local safe_model="${MODEL//:/_}"
        local html_file="/root/gpu_test/tetris_${safe_model}_ctx${num_ctx}.html"
        echo "$model_response" > "$html_file"

        if [ -z "$first_ctx" ]; then
            first_ctx="$num_ctx"
        fi

        local ollama_ps_output=$(ollama ps 2>/dev/null || echo "")
        if echo "$ollama_ps_output" | grep -q 'CPU'; then
            echo "[$MODEL] CPU usage detected — stopping test"
            break
        fi

        local nvidia_smi_output=""
        if command -v nvidia-smi >/dev/null 2>&1; then
        # Retrieving the headers and data separately for alignment purposes.
            data=$(nvidia-smi --query-gpu=index,name,memory.used,memory.total,temperature.gpu,power.draw,power.limit \
                              --format=csv,noheader,nounits 2>/dev/null || echo "")

            if [ -n "$data" ]; then
                nvidia_smi_output=$( {
                    printf "%-4s %-20s %-12s %-12s %-12s %-12s %-12s\n" \
                        "GPU" "Name" "Mem used" "Mem total" "Temp" "Power draw" "Power lim"
                    while IFS=',' read -r idx name mem_used mem_total temp pwr_draw pwr_lim; do
                        printf "%-4s %-20s %-12s %-12s %-12s %-12s %-12s\n" \
                            "$idx" "$name" "${mem_used} MiB" "${mem_total} MiB" "${temp}°C" "${pwr_draw} W" "${pwr_lim} W"
                    done <<< "$data"
                } )
            fi
        fi

        local gpu_line=$(echo "$ollama_ps_output" | tail -n1 | grep -o '[0-9]*% GPU' | head -n1 || "")
        local gpu_percent=$(echo "$gpu_line" | grep -o '^[0-9]*' || "")

        if [ "$total_tokens" -eq 0 ] && [ -z "$gpu_percent" ]; then
            echo "[$MODEL] Empty result at num_ctx=$num_ctx — stopping"
            break
        fi

        print_test_summary "$load_sec" "$eval_sec" "$total_tokens" "$tokens_per_sec" "$gpu_percent" "$ollama_ps_output" "$nvidia_smi_output"

        if [ "$REPORT_MODE" = "report" ]; then
            local escaped_ollama_ps=$(printf '%s' "$ollama_ps_output" | sed 's/&/\&amp;/g; s/</\</g; s/>/\>/g')
            local escaped_nvidia_smi=$(printf '%s' "$nvidia_smi_output" | sed 's/&/\&amp;/g; s/</\</g; s/>/\>/g')

            model_results_html+="
    <tr>
        <td>$MODEL</td>
        <td>$num_ctx</td>
        <td>$(printf "%.3f" $load_sec)</td>
        <td>$(printf "%.3f" $eval_sec)</td>
        <td>$total_tokens</td>
        <td>$tokens_per_sec</td>
        <td><a href=\"$html_file\" target=\"_blank\">View</a></td>
        <td><pre>$escaped_ollama_ps</pre></td>
        <td><pre>$escaped_nvidia_smi</pre></td>
    </tr>"
        fi

        if [ -z "$FIXED_CTX" ]; then
            if [ $num_ctx -lt $max_ctx ]; then
                local new_ctx=$((num_ctx + 4000))
                if [ $new_ctx -gt $max_ctx ]; then new_ctx=$max_ctx; fi
                echo "[$MODEL] Increasing context → $new_ctx"
                num_ctx=$new_ctx
                sleep 3
            else
                break
            fi
        else
            break
        fi
    done

    if [ "$REPORT_MODE" = "report" ] && [ -n "$model_results_html" ]; then
        echo "$model_results_html" >> /root/gpu_test/test_results.tmp
    fi

    echo "Model $MODEL fully tested."
}

# ========== STEP 2: SELECT EXECUTION MODE ==========

# Helper: get models from a group sorted by VRAM requirement
get_sorted_models_from_group() {
    local group="$1"
    local models_str="${MODEL_GROUPS[$group]}"
    local -a models=($models_str)
    local -a sorted=()
    for m in "${models[@]}"; do
        echo "${MODEL_VRAM[$m]} $m"
    done | sort -n | cut -d' ' -f2-
}

if [ -n "$SINGLE_MODEL" ]; then
    # Single-model mode
    if [ -z "${MODEL_VRAM[$SINGLE_MODEL]+_}" ]; then
        echo "Model '$SINGLE_MODEL' is not supported."
        echo "Supported models:"
        for m in "${ALL_MODELS[@]}"; do
            echo "  - $m (${MODEL_VRAM[$m]} GiB)"
        done
        exit 1
    fi

    required_vram="${MODEL_VRAM[$SINGLE_MODEL]}"
    if [ "$(echo "$total_available < $required_vram" | bc -l)" = "1" ]; then
        echo "Insufficient memory for model $SINGLE_MODEL (requires $required_vram GiB, available: $total_available GiB)."
        exit 1
    fi

    test_model "$SINGLE_MODEL"
    echo "Done. Results in /root/gpu_test/"

else
    # Group-based mode
    readarray -t models_in_group < <(get_sorted_models_from_group "$SELECTED_GROUP")

    if [ "$TEST_MODE" == "max" ]; then
        SELECTED_MODEL=""
        for model in "${models_in_group[@]}"; do
            if [ "$(echo "$total_available >= ${MODEL_VRAM[$model]}" | bc -l)" = "1" ]; then
                SELECTED_MODEL="$model"
            fi
        done

        if [ -z "$SELECTED_MODEL" ]; then
            echo "❌ Not enough memory for even the smallest model in group '$SELECTED_GROUP'."
            exit 1
        fi

        echo "Selected model from group '$SELECTED_GROUP': $SELECTED_MODEL"
        test_model "$SELECTED_MODEL"
        echo "Done. Results in /root/gpu_test/"

    elif [ "$TEST_MODE" == "test" ]; then
        echo "Testing all models in group '$SELECTED_GROUP'..."

        escaped_prompt=$(printf '%s' "$PROMPT" | sed 's/&/\&amp;/g; s/</\</g; s/>/\>/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g')

        cat > /root/gpu_test/test_result.html <<EOF
<html><head><title>Ollama Test Report — Group: $SELECTED_GROUP</title></head><body>
<h1>Ollama Model Test Report — Group: $SELECTED_GROUP</h1>
<p><strong>Prompt:</strong> $escaped_prompt</p>
<table border='1'><tr>
<th>Model</th>
<th>Context</th>
<th>Load (sec)</th>
<th>Gen (sec)</th>
<th>Tokens</th>
<th>Tokens/sec</th>
<th>HTML</th>
<th>Ollama PS</th>
<th>nvidia-smi</th>
</tr>
EOF

        models_to_run=()
        for model in "${models_in_group[@]}"; do
            if (( $(echo "$total_available >= ${MODEL_VRAM[$model]}" | bc -l) )); then
                models_to_run+=("$model")
            fi
        done

        if [ ${#models_to_run[@]} -eq 0 ]; then
            echo "Not enough memory to run any model from group '$SELECTED_GROUP'."
            echo "<p>Not enough memory to run any model from group '$SELECTED_GROUP'.</p>" >> /root/gpu_test/test_result.html
        else
            > /root/gpu_test/test_results.tmp
            for model in "${models_to_run[@]}"; do
                test_model "$model" "report"
                sleep 5
            done
            cat /root/gpu_test/test_results.tmp >> /root/gpu_test/test_result.html
        fi

        echo "</table></body></html>" >> /root/gpu_test/test_result.html
        echo "Report saved: /root/gpu_test/test_result.html"

    else
        echo "Error: unknown mode '$TEST_MODE'"
        exit 1
    fi
fi