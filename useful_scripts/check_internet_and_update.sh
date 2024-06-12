#!/bin/sh

# Function to check internet connectivity
check_internet() {
  local test_url="https://sunjaydhama.com"
  if curl -s --head "$test_url" | grep "200" > /dev/null; then
    return 0
  else
    return 1
  fi
}

# Check internet connectivity
if check_internet; then
  echo "Internet is available. Proceeding with brew update and upgrade..."
   /usr/sbin/softwareupdate -i -a
   /usr/local/bin/brew update && /usr/local/bin/brew upgrade
  echo "Homebrew update and upgrade completed."
else
  echo "No internet connectivity detected. Please check your connection and try again."
fi
