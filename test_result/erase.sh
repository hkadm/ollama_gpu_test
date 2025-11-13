#!/bin/bash

# Check if a file has been passed as an argument
if [ $# -ne 1 ]; then
    echo "Usage: $0 <html_file>"
    exit 1
fi

# Set the HTML file path to the first argument
HTML_FILE="$1"

# Verify if the HTML file exists
if [ ! -f "$HTML_FILE" ]; then
    echo "The file $HTML_FILE was not found!"
    exit 1
fi

# Create a temporary file for storing the modified content
TEMP_FILE=$(mktemp)

# Use grep to remove lines containing the specified text pattern
grep -vF '<td><a href="/root/gpu_test/tetris_deepseek-r1'" "$HTML_FILE" > "$TEM_FILE"

# Replace the original HTML file with the temporary file
mv "$TEM_FILE" "$HTML_FILE"

# Inform the user that the processing is complete and that the specified lines have been removed
echo "Processing completed. Lines containing the specified text pattern have been removed from $HTML_FILE."