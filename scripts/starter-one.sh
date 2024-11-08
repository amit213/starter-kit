#!/bin/bash

#starter one script here

function __secure_decrypt_help() {
        printf >&2 "\
    Usage: secure_decrypt <encrypted-file-or-url> [options]
    Options:
        -q, --quiet     Suppress status messages
        -h, --help      Show this help message

    Examples:
        secure_decrypt file.enc
        secure_decrypt https://example.com/file.enc
        secure_decrypt file.enc -q
        result=\$(secure_decrypt file.enc)\n"
}

# Main decryption function
function secure_decrypt() {
        local input="" quiet=0 decrypted_content
        local tmp_dir="/dev/shm"
        local tmp_prefix="secure_decrypt_$$"

        # Parse arguments
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -h|--help)
                    __secure_decrypt_help
                    return 0
                    ;;
                -q|--quiet)
                    quiet=1
                    shift
                    ;;
                *)
                    if [[ -z "$input" ]]; then
                        input="$1"
                        shift
                    else
                        echo "Error: Unexpected argument: $1" >&2
                        __secure_decrypt_help
                        return 1
                    fi
                    ;;
            esac
        done

        # Validate input
        [[ -z "$input" ]] && {
            __secure_decrypt_help
            return 1
        }

        # Ensure temp directory exists and is writable
        [[ ! -d "$tmp_dir" ]] && tmp_dir="/tmp"
        [[ ! -w "$tmp_dir" ]] && {
            echo "Error: No writable temporary directory available" >&2
            return 1
        }

        # Set up secure environment
        umask 077
        trap 'rm -f "${tmp_dir}/${tmp_prefix}"* 2>/dev/null' EXIT HUP INT TERM

        # Get password securely
        [[ $quiet -eq 0 ]] && echo -n "Enter decryption key (hidden): " >&2
        read -rs key
        echo "" >&2

        # Process input based on type (URL or file)
        if [[ "$input" =~ ^https?:// ]]; then
            [[ $quiet -eq 0 ]] && echo "Reading from URL..." >&2
            decrypted_content=$(curl -sfL "$input" 2>/dev/null | \
                openssl enc -aes-256-cbc -d -pbkdf2 -iter 330000 -salt -md sha512 -base64 -pass file:<(echo -n "$key") 2>/dev/null | \
                openssl enc -aes-256-cbc -d -pbkdf2 -iter 320000 -salt -md sha512 -base64 -pass file:<(echo -n "$key") 2>/dev/null | \
                openssl enc -aes-256-cbc -d -pbkdf2 -iter 310000 -salt -md sha512 -base64 -pass file:<(echo -n "$key") 2>/dev/null
            ) || {
                echo "Error: URL access or decryption failed" >&2
                return 1
            }
        else
            # Handle local file
            [[ ! -f "$input" ]] && { echo "Error: File not found: $input" >&2; return 1; }
            [[ ! -r "$input" ]] && { echo "Error: Cannot read file: $input" >&2; return 1; }

            decrypted_content=$(cat "$input" 2>/dev/null | \
                openssl enc -aes-256-cbc -d -pbkdf2 -iter 330000 -salt -md sha512 -base64 -pass file:<(echo -n "$key") 2>/dev/null | \
                openssl enc -aes-256-cbc -d -pbkdf2 -iter 320000 -salt -md sha512 -base64 -pass file:<(echo -n "$key") 2>/dev/null | \
                openssl enc -aes-256-cbc -d -pbkdf2 -iter 310000 -salt -md sha512 -base64 -pass file:<(echo -n "$key") 2>/dev/null
            ) || {
                echo "Error: Decryption failed. Please check if the key is correct." >&2
                return 1
            }
        fi

        # Verify decryption result
        [[ -z "$decrypted_content" ]] && {
            echo "Error: Decryption produced empty output" >&2
            return 1
        }

        # Output decrypted content
        echo "$decrypted_content"
        return 0
}

# Pull content from GitHub
function pull_from_github() {
    local file_url="$1"
    local owner
    local repo
    local file_path
    
    # Check if GITHUB_TOKEN is set
    if [ -z "${GITHUB_TOKEN}" ]; then
        echo "Error: GITHUB_TOKEN environment variable is not set" >&2
        echo "Please set it with: export GITHUB_TOKEN='your_github_token'" >&2
        return 1
    fi
    
    # Parse GitHub URL
    if [[ "$file_url" =~ github\.com/([^/]+)/([^/]+)/blob/[^/]+/(.+) ]]; then
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
        file_path="${BASH_REMATCH[3]}"
    else
        echo "Error: Invalid GitHub URL format" >&2
        echo "Expected format: https://github.com/owner/repo/blob/branch/path/to/file" >&2
        return 1
    fi
    
    # Fetch content from GitHub
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$owner/$repo/contents/$file_path")
    
    # Check for errors
    if ! echo "$response" | jq -e '.content' >/dev/null; then
        echo "Error pulling from GitHub:" >&2
        echo "$response" | jq -r '.message' >&2
        return 1
    fi
    
    # Decode and output content
    echo "$response" | jq -r '.content' | base64 -d
}

function set_github_access() {
    # Check if GITHUB_TOKEN is already set
    if [ -z "${GITHUB_TOKEN}" ]; then
        echo "🔑 Setting up GitHub token..."
        GITHUB_TOKEN=$(secure_decrypt https://raw.githubusercontent.com/amit213/starter-kit/refs/heads/main/scripts/ghub-secure.txt)
        export GITHUB_TOKEN
    fi
}

# One-time bootstrap environment preparation
## dependency on secure_decrypt, pull_from_github
function _bootstrap_starter_one() {
    # Check if GITHUB_TOKEN is already set
    if [ -z "${GITHUB_TOKEN}" ]; then
        echo "🔑 Setting up GitHub token..."
        GITHUB_TOKEN=$(secure_decrypt https://raw.githubusercontent.com/amit213/starter-kit/refs/heads/main/scripts/ghub-secure.txt)
        export GITHUB_TOKEN
    fi

    # Source environment var file directly from GitHub
    echo "📥 Loading environment configuration..."
    source <(pull_from_github "https://github.com/amit213/secure-app-folder/blob/main/mytermbin-app/app-config/envfile.env") || {
        echo "❌ Failed to source environment vars configuration" >&2
        return 1
    }

    # Source environment var file directly from GitHub
    #echo "📥 Loading environment configuration..."
    script=$(curl -fsSL bash.apmz.net) && [ -n "$script" ] && eval "$script"

    #source <(pull_from_github "https://github.com/amit213/tools/blob/master/env/myshellrc.rc") || {
    #    echo "❌ Failed to source environment vars configuration" >&2
    #    return 1
    #}

}

set_github_access
_bootstrap_starter_one
