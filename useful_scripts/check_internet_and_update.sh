#!/bin/bash

INTERNET_TEST_URL="https://sunjaydhama.com"
BREW_BIN="/usr/local/bin/brew"
SOFTWAREUPDATE_BIN="/usr/sbin/softwareupdate"

check_internet() {
  local response;
  response=$(curl -s --head --connect-timeout 10 "$INTERNET_TEST_URL" | grep -E '^HTTP/[0-9\.]+\s+200')
  [[ -n "$response" ]]
}

run_macos_updates() {
  if ! "$SOFTWAREUPDATE_BIN" -i -a; then
    printf "Error: macOS software update failed.\n" >&2
    return 1
  fi
  printf "macOS system updates completed successfully.\n"
}

run_brew_updates() {
  if ! "$BREW_BIN" update; then
    printf "Error: Homebrew update failed.\n" >&2
    return 1
  fi

  if ! "$BREW_BIN" upgrade; then
    printf "Error: Homebrew upgrade failed.\n" >&2
    return 1
  fi
  printf "Homebrew packages updated successfully.\n"
}

main() {
  if check_internet; then
    printf "Internet is available. Proceeding with updates...\n"
    run_macos_updates || return 1
    run_brew_updates || return 1
  else
    printf "Error: No internet connectivity detected. Please check your connection and try again.\n" >&2
    return 1
  fi
}

main

