#!/bin/zsh

# Check if the filename is provided as an argument
if [ $# -eq 0 ]; then
    echo "No filename provided"
    exit 1
fi

filename=$1

# Check if the file exists
if [ ! -f "$filename" ]; then
    echo "File not found!"
    exit 1
fi

# Use sed to remove the last line
sed -i '' '$d' "$filename"

echo "Last line removed from $filename"

