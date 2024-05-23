#!/bin/bash

set -e
set -o pipefail

function list_node_versions() {
    nvm ls-remote | grep -i "latest"
}

function install_node_version() {
    local nodeversion="$1"
    printf "Installing Node.js version %s...\n" "$nodeversion"
    if ! nvm install "$nodeversion"; then
        printf "Failed to install Node.js version %s\n" "$nodeversion" >&2
        return 1
    fi
    nvm alias default "$nodeversion"
    nvm use "$nodeversion"
}

function install_aws_cdk_lib() {
    printf "Installing AWS CDK library globally...\n"
    if ! npm install -g aws-cdk-lib; then
        printf "Failed to install AWS CDK library\n" >&2
        return 1
    fi
}

function download_and_install_aws_cli() {
    local aws_cli_pkg="AWSCLIV2.pkg"
    local install_path

    while true; do
        read -p "Where would you like to install $aws_cli_pkg? (Press Enter to use $HOME): " install_path

        # Use $HOME if no path is provided
        if [[ -z "$install_path" ]]; then
            install_path="$HOME"
            break
        fi

        # Check if the path is a valid directory
        if [[ -d "$install_path" ]]; then
            # Confirm the installation path
            printf "The AWS CLI will be installed to: %s\n" "$install_path"
            break
        else
            printf "Invalid directory: %s. Please enter a valid directory.\n\n" "$install_path" >&2
        fi
    done
    # Define the XML content with install_path
    local xml_content
    xml_content=$(cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <array>
    <dict>
      <key>choiceAttribute</key>
      <string>customLocation</string>
      <key>attributeSetting</key>
      <string>${install_path}</string>
      <key>choiceIdentifier</key>
      <string>default</string>
    </dict>
  </array>
</plist>
EOF
)

    # Write the XML content to choices.xml
    if ! printf "%s" "$xml_content" > choices.xml; then
        printf "Error: Failed to write to choices.xml\n" >&2
        return 1
    fi

    printf "The XML content has been written to choices.xml\n"
    local aws_cli_pkg="AWSCLIV2.pkg"
    local aws_cli_url="https://awscli.amazonaws.com/$aws_cli_pkg"

    printf "Downloading AWS CLI...\n"
    if ! curl "$aws_cli_url" -o "$aws_cli_pkg"; then
        printf "Failed to download AWS CLI\n" >&2
        return 1
    fi

    if [[ ! -f "choices.xml" ]]; then
        printf "Missing configuration file: choices.xml\n" >&2
        return 1
    fi

    printf "Installing AWS CLI...\n"
    if ! installer -pkg "$aws_cli_pkg" -target CurrentUserHomeDirectory -applyChoiceChangesXML "choices.xml"; then
        printf "Failed to install AWS CLI\n" >&2
        return 1
    fi

    sudo ln -s "$install_path/aws-cli/aws" /usr/local/bin/aws
    sudo ln -s "$install_path/aws-cli/aws_completer" /usr/local/bin/aws_completer
    which aws
    aws --version
}

function select_programming_language() {
    local language
    local languages=("typescript" "javascript" "python" "java" "csharp" "go")
    while true; do
        printf "Select a programming language:\n"
        select language in "${languages[@]}"; do
            if [[ -n "$language" ]]; then
                printf "Selected language: %s\n" "$language"
                printf "Selected number: %s\n" "$REPLY"
                install_language_sdk "$language"
                return 0
            else
                printf "Invalid selection: %s\n\n" "$REPLY"
                break
            fi
        done
    done
}

function install_language_sdk() {
    local language="$1"
    printf "Installing %s SDK globally...\n\n" "$language"
    if ! npm -g install "$language"; then
        printf "Failed to install %s SDK\n" "$language" >&2
        return 1
    fi
    printf "%s SDK installed successfully.\n" "$language"
}

function configure_aws_cli() {
    printf "Get access key ID and secret access key from IAM AWS console\n"
    printf "https://us-east-1.console.aws.amazon.com/iamv2/home\n"
    read -p "Press enter to run 'aws configure'"
    aws configure
}

function main() {
    list_node_versions
    read -p 'Enter node version to install (e.g., 22.1.0): ' nodeversion
    install_node_version "$nodeversion"
    install_aws_cdk_lib
    # Print the $HOME variable and ask for installation path
    echo "The home directory is: $HOME"

    download_and_install_aws_cli
    select_programming_language
    configure_aws_cli
}

main

