#!/usr/bin/env bash
#
# first_time_llm_server_install.sh
#
# First script to run on a fresh Ubuntu Server install (24.04 / 26.04 LTS) on
# a headless, CPU-only LLM box with 64GB of RAM.  Run once as root straight
# after the OS install, from an interactive terminal:
#
#   sudo ./first_time_llm_server_install.sh
#
# The script is fully interactive.  Every section first prints what it is
# about to do and then asks:
#
#   Run this section? [Y/n]      Enter or y = run it, n = skip it
#
# Every setting is asked for the first time a section needs it:
#
#   LLM port [8080] (Enter = keep, n = change):
#
# Enter keeps the value shown in brackets; n asks for a new one.  Settings
# that a skipped section would have needed are never asked.  If a section
# depends on something an earlier, skipped section would have set up (for
# example building llama.cpp without the build tools installed), the script
# says what is missing and asks whether to run the section anyway [y/N]
# (there, Enter = no).  The risky optional sections (key-only SSH, and swap
# when swap is already active) ask "Run this section? [y/N]": Enter skips.
#
# A section that fails does not stop the run: its error is shown where it
# happens, the script carries on with the next section, and every failure is
# listed again at the end (the script then exits with status 1).  Only
# "Update Ubuntu" and "Install packages" stop the script when they fail,
# because everything after them builds on them.
#
# No Ollama.  Inference runs on a C++ engine built from source for this exact
# CPU, served by its OpenAI-compatible llama-server under systemd:
#
#   llama.cpp     (mainline)  Runs the MTP speculative-decoding head that the
#                             Ornith/Cyber-Tiel models ship with (~1.2x on MoE,
#                             ~82% draft acceptance) and has the newest model
#                             support.
#   ik_llama.cpp  (ik)        fork with faster CPU matmul kernels, fused MoE
#                             (-fmoe) and run-time repacking (-rtr).  No MTP
#                             support, and it may not load a GGUF that carries
#                             an MTP head, so benchmark it with a plain GGUF.
#                             Switching is a one-line edit in
#                             /etc/default/llama-server.
#
# Sections (each one asks first, and is safe to re-run):
#   - full apt upgrade, then the tools worth having on a headless box
#   - everyday tools a minimized install leaves out (ping, an editor, less,
#     man pages...), asked about one package at a time
#   - zsh as the login shell, plus aliases/history/completion defaults in
#     the user's ~/.zshrc (in a marked block that re-runs replace; the block
#     also exports the llama-server API key, so the file is set to mode 600)
#   - clock and timezone check (the timezone is kept unless you change it)
#   - hardware sanity check: confirms the RAM is seen and prints the DIMMs
#   - optional Ubuntu Pro attach (explains the benefits, offers to install
#     the client, skipped automatically if already attached)
#   - swap file (a safety net only; models must fit in RAM)
#   - CPU-inference tuning: swappiness, transparent hugepages, performance
#     CPU governor
#   - SSH + ufw (SSH from anywhere, the LLM API from the local subnet only)
#   - optional key-only SSH (no passwords, no root), skipped unless you say
#     yes; refuses unless your user already has a key, and asks once more
#     before changing anything
#   - optional mDNS (avahi) so the machine answers to <hostname>.local, on
#     one network interface only (the wired one configured in /etc/netplan)
#   - unattended security updates, and a needrestart rule so a package
#     upgrade never restarts llama-server on its own
#   - turns off Canonical's login news and apt news
#   - service user and model directory (name and path are your choice)
#   - builds ik_llama.cpp and/or llama.cpp from source with native CPU flags
#   - an updater script for the engines
#   - model download, chosen from a menu or any GGUF URL
#   - llama-server config (including an API key), wrapper and hardened
#     systemd service, then starts it and waits for it to report healthy
#   - a login message showing the server's state, model, address, memory and
#     CPU temperature
#   - a summary, with hardware health, network and BIOS notes
#
# Environment variables, if set, become the default shown at each prompt
# (you can still accept or change them interactively):
#   ENGINE, BUILD_ENGINES, SWAP_SIZE_GB, SWAPFILE, SWAPPINESS, THP_MODE,
#   SHELL_USER, EXPOSE_LAN, LLM_PORT, THREADS, CTX, MODEL_ALIAS, API_KEY,
#   MODEL_URL, MODEL_DIR, LLM_USER, IK_DIR, MAINLINE_DIR, CONF, WRAPPER,
#   UPDATER, MIN_EXPECTED_RAM_GB, TIMEZONE, SSH_USER, MDNS_DEV
#
# Models in the menu:
#   Ornith-1.5-35B-A3B (Qwen3.5-MoE architecture, ~3B active, MIT) is a
#   coding/agent-tuned model that beats Qwen3.6 35B-A3B on SWE-bench and
#   tool-use benchmarks, in the same size and speed class.
#
#   SC117's Heretic abliteration of it is the only abliterated Ornith on
#   Hugging Face that publishes its divergence from the ORIGINAL model:
#   first-token KL 0.0105 (Heretic MPOA rank-3 on o_proj + down_proj, best of
#   80 Optuna trials), i.e. the least damage to the model's intelligence.
#   Trade-off: 11/100 refusals remain, versus 2-3/100 for more aggressive
#   builds that report no divergence at all (huihui-ai, alztrk), only
#   quant-vs-own-BF16 numbers (PocketAiHub, gbuzhf), or a noisy MMLU delta
#   (dealignai CRACK).  It is offered in two quants (I-Quality, I-Compact).
#   Both carry an MTP draft head (blk.40).
#
#   peculiar-ragdoll's Cyber-Tiel-Coder-35B-A3B (MTP build) is Ornith on
#   huihui-ai's abliteration, re-quantized with a security/code importance
#   matrix.  Zero refusals (0/84 HarmBench) and the community's favourite,
#   but no divergence-from-original measurement, and its card calls it
#   "slightly unstable" outside security work.  Sandbox it.
#
#   Stock Qwen3.6 35B-A3B (Unsloth UD-Q4_K_XL) is the general-purpose pick.
#
# Notes for this hardware:
#   - On a CPU, memory bandwidth is the bottleneck, not core count.  MoE models
#     with ~3B active parameters (Ornith/Qwen 35B-A3B, Gemma 4 26B) are the
#     sweet spot; dense 30B+ models will crawl.
#   - Threads = physical cores.  Hyperthreads slow memory-bound inference down.
#   - If the BIOS has a fan/thermal profile, set it to performance so sustained
#     all-core load does not throttle.  That cannot be done from here.
#   - Also in the BIOS: "After Power Failure" = "Power On" (the server comes
#     back by itself after an outage) and Wi-Fi/Bluetooth off if unused.
#   - Re-run the updater (default /usr/local/bin/llama-update) every few
#     weeks: both engines are rolling projects and CPU speed-ups land often.

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Defaults (environment variables override them as the shown default)
# ---------------------------------------------------------------------------

ENGINE="${ENGINE:-mainline}"
BUILD_ENGINES="${BUILD_ENGINES:-ik mainline}"
SWAP_SIZE_GB="${SWAP_SIZE_GB:-4}"
SWAPFILE="${SWAPFILE:-/swapfile}"
SWAPPINESS="${SWAPPINESS:-10}"
THP_MODE="${THP_MODE:-always}"
EXPOSE_LAN="${EXPOSE_LAN:-1}"
LLM_PORT="${LLM_PORT:-8080}"
THREADS="${THREADS:-}"
CTX="${CTX:-65536}"
MODEL_ALIAS="${MODEL_ALIAS:-ornith}"
API_KEY="${API_KEY:-}"
MODEL_URL="${MODEL_URL:-}"
MIN_EXPECTED_RAM_GB="${MIN_EXPECTED_RAM_GB:-60}"
TIMEZONE="${TIMEZONE:-}"        # empty = keep the current timezone
MDNS_DEV="${MDNS_DEV:-}"        # empty = the wired interface found in netplan

LLM_USER="${LLM_USER:-llama}"
MODEL_DIR="${MODEL_DIR:-/srv/models}"
IK_DIR="${IK_DIR:-/opt/ik_llama.cpp}"
MAINLINE_DIR="${MAINLINE_DIR:-/opt/llama.cpp}"
CONF="${CONF:-/etc/default/llama-server}"
WRAPPER="${WRAPPER:-/usr/local/bin/llama-server-start}"
UPDATER="${UPDATER:-/usr/local/bin/llama-update}"

IK_REPO="https://github.com/ikawrakow/ik_llama.cpp"
MAINLINE_REPO="https://github.com/ggml-org/llama.cpp"
SERVICE_UNIT="/etc/systemd/system/llama-server.service"
# sshd reads its drop-ins in name order and the FIRST value of a setting wins,
# so this one must sort before the others (cloud-init's 50-cloud-init.conf can
# carry "PasswordAuthentication yes").
SSHD_DROPIN="/etc/ssh/sshd_config.d/00-key-only.conf"
NEEDRESTART_CONF="/etc/needrestart/conf.d/50-llama-server.conf"
MOTD_SCRIPT="/etc/update-motd.d/60-llama-server"

# Model menu.  MODEL_MTP: 1 = the GGUF carries an MTP draft head (mainline
# MTP flags are offered by default), 0 = plain GGUF.
MODEL_NAMES=(
    "Ornith-1.5-35B-A3B Heretic, APEX-I-Quality (23.5 GB) - lowest divergence from the original"
    "Ornith-1.5-35B-A3B Heretic, APEX-I-Compact (17.3 GB) - ~25% fewer bytes per token, so faster"
    "Cyber-Tiel-Coder-35B-A3B MTP, UD-Q4_K_XL (22.7 GB) - zero refusals, security/code tuned; sandbox it"
    "Qwen3.6-35B-A3B, Unsloth UD-Q4_K_XL (22.4 GB) - stock general-purpose model"
)
MODEL_URLS=(
    "https://huggingface.co/SC117/Ornith-1.5-35B-A3B-Heretic-MTP-APEX-GGUF/resolve/main/Ornith-1.5-35B-A3B-Heretic-MTP-APEX-I-Quality.gguf"
    "https://huggingface.co/SC117/Ornith-1.5-35B-A3B-Heretic-MTP-APEX-GGUF/resolve/main/Ornith-1.5-35B-A3B-Heretic-MTP-APEX-I-Compact.gguf"
    "https://huggingface.co/peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-GGUF-MTP/resolve/main/Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf"
    "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/main/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf"
)
MODEL_MTP=(1 1 1 0)

# State filled in while the script runs.
declare -A ASKED=()     # settings already asked for, so each is asked once
MODEL_CHOSEN=0          # 1 once the model menu has been answered
MODEL_HAS_MTP=0         # 1 if the chosen model carries an MTP head
MODEL_FILE=""           # full path of the GGUF the service will use
HARDEN_SECCOMP=0        # 1 = also add the seccomp-based unit directives
HARDEN_MDWE=0           # 1 = also add MemoryDenyWriteExecute=yes
DEFAULT_DEV=""          # network interface of the default route (detect_lan)
LAN_CIDR=""             # local subnet the LLM API is opened to (detect_lan)
BASIC_SELECTED=()       # packages picked in "Minimized-install basics"
CURRENT_TZ=""           # timezone found by "Time and timezone"
SECTION_NO=0
SECTION_TITLE=""        # title of the current section, for error messages
SKIPPED=()
DONE=()
FAILED=()               # titles of the sections whose commands failed
FAILED_WHY=()           # same order as FAILED: what failed, for the end report
BODY_DEPTH=0            # subshell depth on_err reports at (see run_body)
FAIL_INFO=""            # file a failing section body leaves its error in
EXIT_INPUT_CLOSED=3     # exit status when the terminal input is closed

# on_err STATUS LINE COMMAND: the ERR trap.  Says which section and command
# failed.  In the main shell the script then stops (errexit).  Inside a
# section body started by run_body only that body stops, and the details are
# left in FAIL_INFO for run_body to record.
on_err() {
    local rc="$1" line="$2" cmd="${3%%$'\n'*}"
    # Report each failure once: not from nested subshells, and not again from
    # the main shell when a section body has failed (run_body reports that).
    ((BASH_SUBSHELL == BODY_DEPTH)) || return 0
    echo >&2
    echo "ERROR: section ${SECTION_NO} (${SECTION_TITLE:-setup}) failed at line ${line} (exit status ${rc})." >&2
    echo "       Failing command: ${cmd}" >&2
    if ((BODY_DEPTH == 0)); then
        echo "       The script cannot continue past this.  Fix the problem and re-run it." >&2
    elif [[ -n "${FAIL_INFO}" ]]; then
        printf 'line %s, exit status %s: %s\n' "${line}" "${rc}" "${cmd}" >"${FAIL_INFO}" || true
    fi
}

trap 'on_err "$?" "${LINENO}" "${BASH_COMMAND}"' ERR

# ---------------------------------------------------------------------------
# Prompt helpers
# ---------------------------------------------------------------------------

# read_line PROMPT VARNAME: read one line from the terminal; abort on EOF.
read_line() {
    if ! IFS= read -r -e -p "$1" "$2"; then
        echo
        echo "Input closed; aborting."
        exit "${EXIT_INPUT_CLOSED}"
    fi
}

# confirm QUESTION: Enter/y = yes (0), n = no (1); anything else re-asks.
confirm() {
    local reply
    while :; do
        read_line "$1 [Y/n]: " reply
        case "${reply,,}" in
            "" | y | yes) return 0 ;;
            n | no) return 1 ;;
            *) echo "  Please answer y or n (Enter = yes)." ;;
        esac
    done
}

# confirm_no QUESTION: like confirm, but Enter = no.
confirm_no() {
    local reply
    while :; do
        read_line "$1 [y/N]: " reply
        case "${reply,,}" in
            y | yes) return 0 ;;
            "" | n | no) return 1 ;;
            *) echo "  Please answer y or n (Enter = no)." ;;
        esac
    done
}

# section [--default-no] TITLE LINE...: print what the section does and ask
# whether to run it.  With --default-no the prompt is [y/N] (Enter = skip).
section() {
    local title line ask=confirm
    if [[ "$1" == --default-no ]]; then
        ask=confirm_no
        shift
    fi
    title="$1"
    shift
    SECTION_NO=$((SECTION_NO + 1))
    SECTION_TITLE="${title}"
    echo
    echo "=============================================================="
    echo " ${SECTION_NO}. ${title}"
    echo "=============================================================="
    for line in "$@"; do
        echo "  ${line}"
    done
    echo
    if "${ask}" "Run this section?"; then
        DONE+=("${title}")
        return 0
    fi
    echo "  Skipped: ${title}"
    SKIPPED+=("${title}")
    return 1
}

# deps_ok MISSING...: if anything is missing, list it and ask whether to run
# the section anyway.  Returns 0 to run, 1 to skip.
deps_ok() {
    local item
    [[ $# -eq 0 ]] && return 0
    echo
    echo "  WARNING: this section needs things that are not in place:"
    for item in "$@"; do
        echo "    - ${item}"
    done
    echo "  (Usually because an earlier section was skipped.)"
    if confirm_no "  Run this section anyway?"; then
        return 0
    fi
    echo "  Skipped: ${DONE[-1]} (missing dependencies)"
    SKIPPED+=("${DONE[-1]} (missing dependencies)")
    unset 'DONE[-1]'
    return 1
}

# run_body FUNCTION [ARG...]: run a section's commands in a subshell, so that
# a failure stops only that section.  The failure is shown, recorded in FAILED
# for the end report, and the script continues with the next section.
#
# Each section has two halves.  Everything that asks a question, and every
# variable a later section reads, is handled first, in the main shell (nothing
# set inside the subshell survives it).  The commands that change the machine
# go in a do_* function, run through here.  The two sections everything else
# builds on call their do_* function directly instead, so a failure there
# still stops the script.
#
# Call run_body ONLY as a plain statement, never in if / || / && / !: there
# bash silently turns errexit off inside the subshell.
run_body() {
    local rc why=""
    FAIL_INFO="$(mktemp 2>/dev/null)" || FAIL_INFO=""
    BODY_DEPTH=$((BASH_SUBSHELL + 1))
    set +e
    (
        set -e
        "$@"
    )
    rc=$?
    set -e
    BODY_DEPTH=0
    if [[ -n "${FAIL_INFO}" ]]; then
        why="$(cat "${FAIL_INFO}" 2>/dev/null)" || why=""
        rm -f "${FAIL_INFO}"
        FAIL_INFO=""
    fi
    if ((rc == 0)); then
        return 0
    fi
    # The input was closed at a prompt inside the body (read_line): stop the
    # whole script, as at any other prompt.  A command that merely failed with
    # the same status has left its details in FAIL_INFO.
    if ((rc == EXIT_INPUT_CLOSED)) && [[ -z "${why}" ]]; then
        exit "${EXIT_INPUT_CLOSED}"
    fi
    [[ -n "${why}" ]] || why="exit status ${rc}"
    echo >&2
    echo "  FAILED: ${SECTION_TITLE}.  The error is shown above.  Continuing with the" >&2
    echo "  next section; this failure is listed again at the end." >&2
    FAILED+=("${SECTION_TITLE}")
    FAILED_WHY+=("${why}")
    if ((${#DONE[@]} > 0)) && [[ "${DONE[-1]}" == "${SECTION_TITLE}" ]]; then
        unset 'DONE[-1]'
    fi
}

# fail_body REASON: end a section body as failed after it has already told
# the user what went wrong.  Unlike a failing command it does not trigger
# on_err, so no "Failing command" line is printed; run_body reports it once.
fail_body() {
    [[ -z "${FAIL_INFO}" ]] || printf '%s\n' "$1" >"${FAIL_INFO}" || true
    exit 1
}

# missing_cmds CMD...: print the commands that are not installed.
missing_cmds() {
    local c
    for c in "$@"; do
        command -v "${c}" >/dev/null 2>&1 || echo "command '${c}'"
    done
}

# Validators for ask_value.  Each takes the candidate value.
v_any()      { return 0; }
v_nonempty() { [[ -n "$1" ]]; }
v_posint()   { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }
v_port()     { v_posint "$1" && ((${#1} <= 5)) && ((10#$1 <= 65535)); }
v_0to200()   { [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 <= 200)); }
v_01()       { [[ "$1" == 0 || "$1" == 1 ]]; }
v_engine()   { [[ "$1" == mainline || "$1" == ik ]]; }
v_thp()      { [[ "$1" == always || "$1" == madvise || "$1" == never ]]; }
v_user()     { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }
v_alias()    { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]; }
v_api_key()  { [[ "$1" =~ ^[A-Za-z0-9._-]*$ ]]; }
v_path()     { [[ "$1" =~ ^/[A-Za-z0-9._/-]*[A-Za-z0-9._-]$ && "$1" != *..* ]]; }
v_gguf_name() { [[ "$1" =~ ^[A-Za-z0-9._-]+\.gguf$ ]]; }
v_url()      { [[ "$1" =~ ^https://[^[:space:]]+$ ]]; }
v_engines()  {
    local e seen=0
    [[ -n "$1" ]] || return 1
    for e in $1; do
        [[ "${e}" == ik || "${e}" == mainline ]] || return 1
        seen=1
    done
    ((seen == 1))
}
v_model_choice() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]] && (($1 <= ${#MODEL_URLS[@]} + 2))
}

# ask_value VAR LABEL DEFAULT [VALIDATOR] [HINT]
# Shows "LABEL [DEFAULT] (Enter = keep, n = change):".  Enter keeps the
# default; n asks for a new value.  Each VAR is asked only once per run.
ask_value() {
    local var="$1" label="$2" def="$3" validator="${4:-v_nonempty}" hint="${5:-}"
    local reply val
    [[ -n "${ASKED[${var}]:-}" ]] && return 0
    # No usable default (empty or invalid): ask for the value directly.
    if ! "${validator}" "${def}"; then
        [[ -n "${def}" ]] && echo "  The default '${def}' for ${label} is not valid.${hint:+ ${hint}}"
        while :; do
            read_line "  ${label}: " val
            "${validator}" "${val}" && break
            echo "  '${val}' is not valid.${hint:+ ${hint}}"
        done
        printf -v "${var}" '%s' "${val}"
        ASKED[${var}]=1
        return 0
    fi
    while :; do
        read_line "  ${label} [${def}] (Enter = keep, n = change): " reply
        case "${reply,,}" in
            "")
                val="${def}"
                ;;
            n | no)
                while :; do
                    read_line "  New value for ${label}: " val
                    "${validator}" "${val}" && break
                    echo "  '${val}' is not valid.${hint:+ ${hint}}"
                done
                ;;
            *)
                echo "  Press Enter to keep '${def}', or type n to enter a different value."
                continue
                ;;
        esac
        if "${validator}" "${val}"; then
            break
        fi
        echo "  '${val}' is not valid.${hint:+ ${hint}}  Type n to enter a different value."
    done
    printf -v "${var}" '%s' "${val}"
    ASKED[${var}]=1
}

# shq VALUE: single-quote VALUE for a file that bash will source.
shq() {
    printf "'%s'" "${1//\'/\'\\\'\'}"
}

# gen_api_key: a random 48-character hex key.
gen_api_key() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 24
    else
        od -An -N24 -tx1 /dev/urandom | tr -d ' \n'
    fi
}

# ---------------------------------------------------------------------------
# Setting helpers (each asks once, the first time a section needs it)
# ---------------------------------------------------------------------------

PATH_HINT="Use an absolute path of letters, digits, . _ - and / only (no spaces)."

detect_phys_cores() {
    local n
    n="$(lscpu -p=CORE,SOCKET 2>/dev/null | grep -v '^#' | sort -u | wc -l)" || n=0
    [[ "${n}" -ge 1 ]] || n="$(nproc)"
    echo "${n}"
}

# dev_cidr DEV: print the directly connected IPv4 subnet of interface DEV.
# Prints nothing if it has none.
dev_cidr() {
    ip -4 route show dev "$1" scope link 2>/dev/null | awk '{print $1; exit}'
}

# detect_lan: set DEFAULT_DEV (the interface of the default route) and
# LAN_CIDR (its directly connected subnet).  Both are empty if not found.
detect_lan() {
    DEFAULT_DEV="$(ip -4 route show default 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')" \
        || DEFAULT_DEV=""
    LAN_CIDR=""
    if [[ -n "${DEFAULT_DEV}" ]]; then
        LAN_CIDR="$(dev_cidr "${DEFAULT_DEV}")" || LAN_CIDR=""
    fi
}

# v_netdev NAME: true if NAME is a network interface of this machine.
v_netdev() {
    [[ "$1" =~ ^[A-Za-z0-9_.-]+$ && -e "/sys/class/net/$1" ]]
}

# wired_dev NAME: true if NAME is an interface of this machine and not Wi-Fi.
wired_dev() {
    v_netdev "$1" && [[ "$1" != wl* && ! -e "/sys/class/net/$1/wireless" ]]
}

# netplan_eth_keys TOP: print the interface IDs under "ethernets:" in the
# netplan YAML on stdin.  TOP=1: stdin is the ethernets mapping itself (the
# output of 'netplan get ethernets').  Block-style YAML only; anything else
# prints nothing.
netplan_eth_keys() {
    awk -v in_eth="$1" '
        BEGIN { eth_ind = -1; key_ind = -1 }
        { sub(/[[:space:]]+#.*$/, "") }
        /^[[:space:]]*(#|$)/ { next }
        { ind = match($0, /[^ ]/) - 1 }
        in_eth && ind <= eth_ind { in_eth = 0 }
        !in_eth {
            if (NF == 1 && $1 == "ethernets:") { in_eth = 1; eth_ind = ind; key_ind = -1 }
            next
        }
        key_ind < 0 { key_ind = ind }
        ind == key_ind && NF == 1 {
            k = $1
            gsub(/["\047]/, "", k)
            if (k ~ /^[A-Za-z0-9_.-]+:$/) print substr(k, 1, length(k) - 1)
        }'
}

# netplan_wired: print the wired interfaces configured in netplan, one per
# line: from 'netplan get ethernets', else from the files in /etc/netplan.
# Only names that exist on this machine and are not Wi-Fi are printed.
netplan_wired() {
    local ids="" f d seen=" "
    if command -v netplan >/dev/null 2>&1; then
        ids="$(netplan get ethernets 2>/dev/null | netplan_eth_keys 1)" || ids=""
    fi
    if [[ -z "${ids}" ]]; then
        for f in /etc/netplan/*.yaml; do
            [[ -r "${f}" ]] || continue
            ids+="$(netplan_eth_keys 0 <"${f}" || true)"$'\n'
        done
    fi
    for d in ${ids}; do
        if wired_dev "${d}" && [[ "${seen}" != *" ${d} "* ]]; then
            echo "${d}"
            seen+="${d} "
        fi
    done
    return 0
}

# pkg_installed PACKAGE: true if the package is installed.
pkg_installed() {
    # shellcheck disable=SC2016
    [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" == "install ok installed" ]]
}

# has_ssh_key FILE: true if FILE (an authorized_keys file) holds a public key.
has_ssh_key() {
    [[ -s "$1" ]] \
        && grep -Eq '^[^#]*(ssh-(ed25519|rsa)|ecdsa-sha2-[a-z0-9-]+|sk-[a-z0-9@.-]+) AAAA' "$1" 2>/dev/null
}

# cpu_temp_c: print the CPU package temperature in whole degrees C, read from
# /sys (no extra packages).  Prints nothing if it cannot be read.
cpu_temp_c() {
    local d t=""
    for d in /sys/class/thermal/thermal_zone*; do
        [[ -r "${d}/type" && -r "${d}/temp" ]] || continue
        if [[ "$(cat "${d}/type" 2>/dev/null)" == x86_pkg_temp ]]; then
            t="$(cat "${d}/temp" 2>/dev/null)" || t=""
            break
        fi
    done
    if [[ -z "${t}" ]]; then
        for d in /sys/class/hwmon/hwmon*; do
            [[ -r "${d}/name" && -r "${d}/temp1_input" ]] || continue
            if [[ "$(cat "${d}/name" 2>/dev/null)" == coretemp ]]; then
                t="$(cat "${d}/temp1_input" 2>/dev/null)" || t=""
                break
            fi
        done
    fi
    if [[ "${t}" =~ ^[0-9]+$ ]]; then
        echo $((t / 1000))
    fi
    return 0
}

ask_port() {
    ask_value LLM_PORT "llama-server port" "${LLM_PORT}" v_port "Use a number from 1 to 65535."
}

ask_expose_lan() {
    ask_value EXPOSE_LAN "Expose the LLM API to the local network? (1 = LAN, 0 = localhost only)" \
        "${EXPOSE_LAN}" v_01 "Type 1 or 0."
}

ask_llm_user() {
    ask_value LLM_USER "Service user that runs llama-server" "${LLM_USER}" v_user \
        "Lowercase letters, digits, _ and -, starting with a letter or _."
}

# ask_api_key: the llama-server API key.  The default is API_KEY from the
# environment, else the key already in the config file (so a re-run keeps it),
# else a new random one.  The "Zsh defaults" and "llama-server configuration"
# sections both need it; whichever comes first asks.
ask_api_key() {
    local def="${API_KEY}" old
    [[ -n "${ASKED[API_KEY]:-}" ]] && return 0
    ask_value CONF "Config file path" "${CONF}" v_path "${PATH_HINT}"
    if [[ -z "${def}" ]]; then
        # A config that has API_KEY= (empty) means "no key": keep that.
        old=__unset__
        if [[ -f "${CONF}" ]]; then
            old="$(
                unset API_KEY
                # shellcheck disable=SC1090
                source "${CONF}"
                printf '%s' "${API_KEY-__unset__}"
            )" || old=__unset__
        fi
        if [[ "${old}" == __unset__ ]]; then
            def="$(gen_api_key)"
        else
            def="${old}"
        fi
    fi
    echo "  An API key makes every /v1 request need 'Authorization: Bearer <key>'; /health"
    echo "  stays public.  It goes in ${CONF} (readable by root and the service user only)"
    echo "  and, if you set up ~/.zshrc, in that file as \$LLAMA_API_KEY.  Empty = no key"
    echo "  (only sensible on a network you trust)."
    ask_value API_KEY "API key (empty = none)" "${def}" v_api_key \
        "Letters, digits, . _ - only; empty for no key."
}

ask_model_dir() {
    ask_value MODEL_DIR "Model directory" "${MODEL_DIR}" v_path "${PATH_HINT}"
}

ask_engine_dirs() {
    local e
    for e in ${BUILD_ENGINES}; do
        case "${e}" in
            ik) ask_value IK_DIR "ik_llama.cpp source/build directory" "${IK_DIR}" v_path "${PATH_HINT}" ;;
            mainline) ask_value MAINLINE_DIR "llama.cpp source/build directory" "${MAINLINE_DIR}" v_path "${PATH_HINT}" ;;
        esac
    done
}

ask_engine() {
    ask_value ENGINE "Engine the service runs (mainline or ik)" "${ENGINE}" v_engine "Type mainline or ik."
    case "${ENGINE}" in
        ik) ask_value IK_DIR "ik_llama.cpp source/build directory" "${IK_DIR}" v_path "${PATH_HINT}" ;;
        mainline) ask_value MAINLINE_DIR "llama.cpp source/build directory" "${MAINLINE_DIR}" v_path "${PATH_HINT}" ;;
    esac
}

engine_bin() {
    case "${ENGINE}" in
        ik) echo "${IK_DIR}/build/bin/llama-server" ;;
        mainline) echo "${MAINLINE_DIR}/build/bin/llama-server" ;;
    esac
}

# select_model: menu of known models, a custom URL, or no download.
# Sets MODEL_URL (empty = no download) and MODEL_HAS_MTP.
select_model() {
    local i default_choice custom_no skip_no
    ((MODEL_CHOSEN == 1)) && return 0
    custom_no=$((${#MODEL_URLS[@]} + 1))
    skip_no=$((${#MODEL_URLS[@]} + 2))

    echo
    echo "  Models:"
    for i in "${!MODEL_NAMES[@]}"; do
        echo "    $((i + 1))) ${MODEL_NAMES[$i]}"
    done
    echo "    ${custom_no}) Enter my own GGUF URL"
    echo "    ${skip_no}) No download"

    default_choice=1
    if [[ -n "${MODEL_URL}" ]]; then
        default_choice="${custom_no}"
        for i in "${!MODEL_URLS[@]}"; do
            [[ "${MODEL_URLS[$i]}" == "${MODEL_URL}" ]] && default_choice=$((i + 1))
        done
    fi
    MODEL_SELECTION="${default_choice}"
    ask_value MODEL_SELECTION "Model" "${MODEL_SELECTION}" v_model_choice \
        "Type a number from 1 to ${skip_no}."

    if ((MODEL_SELECTION == skip_no)); then
        MODEL_URL=""
        MODEL_HAS_MTP=0
    elif ((MODEL_SELECTION == custom_no)); then
        ask_value MODEL_URL "GGUF URL (https://...)" "${MODEL_URL}" v_url \
            "It must start with https:// and contain no spaces."
        echo "  A custom model may or may not carry an MTP draft head."
        MODEL_HAS_MTP_ANSWER=0
        ask_value MODEL_HAS_MTP_ANSWER "Does this GGUF carry an MTP draft head? (1 = yes, 0 = no/unsure)" \
            0 v_01 "Type 1 or 0."
        MODEL_HAS_MTP="${MODEL_HAS_MTP_ANSWER}"
    else
        MODEL_URL="${MODEL_URLS[$((MODEL_SELECTION - 1))]}"
        MODEL_HAS_MTP="${MODEL_MTP[$((MODEL_SELECTION - 1))]}"
    fi
    MODEL_CHOSEN=1
}

# model_filename_from_url: the GGUF file name to save MODEL_URL as.
model_filename_from_url() {
    local name="${MODEL_URL%%\?*}"
    name="${name##*/}"
    MODEL_FILENAME="${name}"
    if ! v_gguf_name "${MODEL_FILENAME}"; then
        MODEL_FILENAME="model.gguf"
        echo "  Could not get a usable file name from the URL."
    fi
    ask_value MODEL_FILENAME "Save the model as" "${MODEL_FILENAME}" v_gguf_name \
        "Letters, digits, . _ - only, ending in .gguf."
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root: sudo $0"
    exit 1
fi

if [[ ! -t 0 ]]; then
    echo "This script asks questions as it goes; run it from an interactive terminal."
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "LLM server first-time setup"
echo "Each section explains what it will do and asks before doing it."
echo "Prompts: Enter = yes / keep the value in [brackets], n = no / change it."

# ---------------------------------------------------------------------------
# 1. Ubuntu updates
# ---------------------------------------------------------------------------

# Required: called directly, so a failure here stops the script.
do_update_ubuntu() {
    apt-get update
    apt-get full-upgrade -y
}

if section "Update Ubuntu" \
    "Refreshes the package lists and installs all available updates" \
    "(apt-get update && apt-get full-upgrade -y)."; then
    do_update_ubuntu
fi

# ---------------------------------------------------------------------------
# 2. Packages
# ---------------------------------------------------------------------------

PACKAGES=(
    build-essential cmake pkg-config libcurl4-openssl-dev curl git tmux htop
    jq pciutils dmidecode nvme-cli smartmontools lm-sensors zstd
    openssh-server unattended-upgrades ufw
)

# Required, like the update above.
do_install_packages() {
    apt-get install -y "${PACKAGES[@]}"
}

if section "Install packages" \
    "Installs build tools and admin utilities:" \
    "${PACKAGES[*]}"; then
    do_install_packages
fi

# ---------------------------------------------------------------------------
# 2a. Minimized-install basics
# ---------------------------------------------------------------------------

# Same order in both arrays: the package, and what it is for.
BASIC_PACKAGES=(
    iputils-ping nano less man-db manpages bash-completion rsync ethtool lsof
    unzip bind9-dnsutils
)
BASIC_WHAT=(
    "the ping command"
    "a simple text editor"
    "a pager for reading long output and files"
    "the man command"
    "the Linux manual pages"
    "Tab completion for bash"
    "copying files, e.g. models, from another computer"
    "network card settings and link speed"
    "shows which process has a file or port open"
    "unpacks .zip files"
    "the DNS lookup tools dig and nslookup"
)

do_basic_packages() {
    apt-get install -y "${BASIC_SELECTED[@]}"
}

if section "Minimized-install basics" \
    "A minimized Ubuntu Server install leaves out everyday tools such as ping," \
    "a text editor, less and the man pages.  You are asked about each package" \
    "below, one at a time; the ones you pick are installed together.  (Ubuntu's" \
    "'unminimize' command restores everything instead, including the manual" \
    "pages of packages that are already installed, but pulls in far more; it is" \
    "not run here.)"; then
    BASIC_SELECTED=()
    for i in "${!BASIC_PACKAGES[@]}"; do
        if pkg_installed "${BASIC_PACKAGES[$i]}"; then
            echo "  ${BASIC_PACKAGES[$i]}: already installed."
        elif confirm "  Install ${BASIC_PACKAGES[$i]} (${BASIC_WHAT[$i]})?"; then
            BASIC_SELECTED+=("${BASIC_PACKAGES[$i]}")
        fi
    done
    if ((${#BASIC_SELECTED[@]} == 0)); then
        echo "  Nothing to install."
    else
        echo "  Installing: ${BASIC_SELECTED[*]}"
        run_body do_basic_packages
    fi
fi

# ---------------------------------------------------------------------------
# 2b. Zsh as the default shell
# ---------------------------------------------------------------------------

v_login_user() {
    v_user "$1" && getent passwd "$1" >/dev/null 2>&1
}

ask_shell_user() {
    local def="${SUDO_USER:-}"
    [[ "${def}" == root ]] && def=""
    ask_value SHELL_USER "User whose shell and ~/.zshrc to set up" "${SHELL_USER:-${def}}" v_login_user \
        "Use the name of an existing user (e.g. the one you log in as)."
}

do_zsh_shell() {
    if ! command -v zsh >/dev/null 2>&1; then
        apt-get install -y zsh
    else
        echo "zsh is already installed."
    fi
    ZSH_PATH="$(command -v zsh)"
    grep -qxF "${ZSH_PATH}" /etc/shells || echo "${ZSH_PATH}" >>/etc/shells
    CURRENT_SHELL="$(getent passwd "${SHELL_USER}" | cut -d: -f7)"
    if [[ "${CURRENT_SHELL}" == "${ZSH_PATH}" ]]; then
        echo "${SHELL_USER}'s login shell is already ${ZSH_PATH}."
    else
        chsh -s "${ZSH_PATH}" "${SHELL_USER}"
        echo "${SHELL_USER}'s login shell changed from ${CURRENT_SHELL:-/bin/sh} to ${ZSH_PATH}."
    fi
}

if section "Zsh shell" \
    "Installs zsh (if needed) and makes it the login shell for the user you" \
    "choose (default: the user who ran sudo).  Takes effect at the next login."; then
    ask_shell_user
    run_body do_zsh_shell
fi

# ---------------------------------------------------------------------------
# 2c. ~/.zshrc defaults
# ---------------------------------------------------------------------------

ZSHRC_BEGIN="# >>> first_time_llm_server_install defaults >>>"
ZSHRC_END="# <<< first_time_llm_server_install defaults <<<"

write_zshrc_block() {
    cat <<'ZSHRC'
# --- Useful aliases ---
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias c='clear'
alias h='history'

# --- Safer defaults ---
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'

# --- Ubuntu package management ---
alias update='sudo apt update && sudo apt upgrade'
alias cleanup='sudo apt autoremove'

# --- History ---
HISTSIZE=10000
SAVEHIST=10000
HISTFILE="$HOME/.zsh_history"
setopt HIST_IGNORE_DUPS
setopt HIST_SAVE_NO_DUPS
setopt SHARE_HISTORY

# --- Navigation ---
setopt AUTO_CD
setopt INTERACTIVE_COMMENTS

# --- Completion ---
autoload -Uz compinit
compinit
ZSHRC
    # The llama-server API key, for curl and agents on this box.
    if [[ -n "${API_KEY}" ]]; then
        echo
        echo "# --- llama-server API key (this file is readable by you only) ---"
        printf 'export LLAMA_API_KEY=%s\n' "$(shq "${API_KEY}")"
    fi
}

do_zsh_defaults() {
    USER_GROUP="$(id -gn "${SHELL_USER}")"
    ZSHRC_FILE="${USER_HOME}/.zshrc"
    # Follow a symlinked ~/.zshrc (e.g. into a dotfiles repo) instead of
    # replacing the link with a regular file.
    if [[ -L "${ZSHRC_FILE}" ]]; then
        ZSHRC_FILE="$(readlink -f "${ZSHRC_FILE}")"
        echo "  ~/.zshrc is a symlink; updating its target ${ZSHRC_FILE}"
    fi
    TMP_ZSHRC="$(mktemp)"
    if [[ -f "${ZSHRC_FILE}" ]]; then
        cp -p "${ZSHRC_FILE}" "${ZSHRC_FILE}.bak-$(date +%Y%m%d-%H%M%S)"
        # Keep everything outside a previous block from this script,
        # minus trailing blank lines (so re-runs don't add blank lines).
        awk -v b="${ZSHRC_BEGIN}" -v e="${ZSHRC_END}" '
            $0 == b { skip = 1; next }
            $0 == e { skip = 0; next }
            skip { next }
            /^[[:space:]]*$/ { blanks = blanks $0 "\n"; next }
            { printf "%s", blanks; blanks = ""; print }' "${ZSHRC_FILE}" >"${TMP_ZSHRC}"
        [[ -s "${TMP_ZSHRC}" ]] && echo >>"${TMP_ZSHRC}"
    fi
    {
        echo "${ZSHRC_BEGIN}"
        write_zshrc_block
        echo "${ZSHRC_END}"
    } >>"${TMP_ZSHRC}"
    # The file holds the API key, so only its owner may read it.
    ZSHRC_MODE=644
    [[ -n "${API_KEY}" ]] && ZSHRC_MODE=600
    install -m "${ZSHRC_MODE}" -o "${SHELL_USER}" -g "${USER_GROUP}" "${TMP_ZSHRC}" "${ZSHRC_FILE}"
    rm -f "${TMP_ZSHRC}"
    echo "Updated ${ZSHRC_FILE}"
}

if section "Zsh defaults (~/.zshrc)" \
    "Adds aliases (ll, la, l, .., ..., c, h, safer cp/mv/rm, update, cleanup)," \
    "history settings, AUTO_CD and completion to the chosen user's ~/.zshrc." \
    "The settings go in a marked block: existing lines are kept, and re-running" \
    "replaces only that block.  The current file is backed up first.  The block" \
    "also exports the llama-server API key (asked for here), and then the file" \
    "is set to mode 600."; then
    ask_shell_user
    missing=()
    command -v zsh >/dev/null 2>&1 || missing+=("zsh (from the 'Zsh shell' section)")
    USER_HOME="$(getent passwd "${SHELL_USER}" | cut -d: -f6)"
    if [[ -z "${USER_HOME}" || ! -d "${USER_HOME}" ]]; then
        echo "  ${SHELL_USER} has no home directory (${USER_HOME:-not set}); skipping."
        SKIPPED+=("${DONE[-1]} (no home directory)")
        unset 'DONE[-1]'
    elif deps_ok "${missing[@]}"; then
        ask_api_key
        run_body do_zsh_defaults
    fi
fi

# ---------------------------------------------------------------------------
# 2d. Time and timezone
# ---------------------------------------------------------------------------

v_timezone() {
    [[ "$1" =~ ^[A-Za-z0-9_+/-]+$ ]] && [[ "$1" == "${CURRENT_TZ}" || -f "/usr/share/zoneinfo/$1" ]]
}

do_timezone() {
    if [[ "${TIMEZONE}" == "${CURRENT_TZ}" ]]; then
        echo "Timezone left at ${CURRENT_TZ}."
    else
        timedatectl set-timezone "${TIMEZONE}"
        echo "Timezone changed from ${CURRENT_TZ} to ${TIMEZONE}."
    fi
    NTP_SYNC="$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" || NTP_SYNC=""
    case "${NTP_SYNC}" in
        yes)
            echo "The clock is synchronized over the network."
            ;;
        no)
            echo "WARNING: the clock is NOT synchronized over the network (yet).  It can take"
            echo "         a minute after boot; if it stays that way, check 'timedatectl' and"
            echo "         the network.  A wrong clock breaks HTTPS, e.g. model downloads."
            ;;
        *)
            echo "Could not read whether the clock is synchronized (see 'timedatectl')."
            ;;
    esac
}

if section "Time and timezone" \
    "Shows the clock, the timezone and whether the clock is synchronized over" \
    "the network (a wrong clock breaks HTTPS, e.g. model downloads).  You can" \
    "change the timezone; Enter keeps the current one.  No time-sync software" \
    "is installed or reconfigured."; then
    mapfile -t missing < <(missing_cmds timedatectl)
    if deps_ok "${missing[@]}"; then
        timedatectl 2>/dev/null | sed 's/^ */    /' || echo "  (timedatectl could not read the clock state)"
        CURRENT_TZ="$(timedatectl show -p Timezone --value 2>/dev/null)" || CURRENT_TZ=""
        [[ -n "${CURRENT_TZ}" ]] || CURRENT_TZ="Etc/UTC"
        ask_value TIMEZONE "Timezone" "${TIMEZONE:-${CURRENT_TZ}}" v_timezone \
            "Use a name from 'timedatectl list-timezones', e.g. Etc/UTC or Europe/Paris."
        run_body do_timezone
    fi
fi

# ---------------------------------------------------------------------------
# 3. Hardware check
# ---------------------------------------------------------------------------

do_hardware_check() {
    CPU_MODEL="$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo)"
    PHYS_CORES="$(detect_phys_cores)"
    RAM_GB="$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)"
    echo
    echo "CPU:            ${CPU_MODEL}"
    echo "Physical cores: ${PHYS_CORES}"
    echo "RAM:            ${RAM_GB} GB"
    echo "CPU flags:      $(grep -o -w -E 'avx2|avx512f|fma|f16c|amx_tile' /proc/cpuinfo | sort -u | tr '\n' ' ')"
    echo
    echo "Installed memory modules:"
    if command -v dmidecode >/dev/null 2>&1; then
        dmidecode -t 17 \
            | grep -E '^\s*(Size|Locator|Speed|Configured Memory Speed|Part Number):' \
            | grep -v 'Bank Locator' \
            | sed 's/^\s*/    /' \
            || echo "    (dmidecode could not read DIMM info)"
    else
        echo "    (dmidecode is not installed; skipped)"
    fi
    if [[ "${RAM_GB}" -lt "${MIN_EXPECTED_RAM_GB}" ]]; then
        echo
        echo "WARNING: only ${RAM_GB} GB of RAM detected; expected at least ${MIN_EXPECTED_RAM_GB} GB."
        echo "         Check that every DIMM is fully seated and that the BIOS sees them all."
    fi
}

if section "Hardware sanity check" \
    "Read-only: prints the CPU, physical cores, RAM, CPU features and the" \
    "installed memory modules, and warns if less RAM than expected is seen."; then
    ask_value MIN_EXPECTED_RAM_GB "Warn if total RAM (GB) is below" "${MIN_EXPECTED_RAM_GB}" v_posint \
        "Use a whole number."
    run_body do_hardware_check
fi

# ---------------------------------------------------------------------------
# 4. Ubuntu Pro
# ---------------------------------------------------------------------------

pro_is_attached() {
    command -v pro >/dev/null 2>&1 || return 1
    pro status --format json 2>/dev/null | grep -Eq '"attached"[[:space:]]*:[[:space:]]*true'
}

do_ubuntu_pro() {
    if command -v pro >/dev/null 2>&1; then
        echo "The Ubuntu Pro client is already installed."
        RUN_PRO_ATTACH=1
    else
        echo "The Ubuntu Pro client ('pro' command) is not installed."
        if confirm "Install it now (package ubuntu-pro-client)?"; then
            if apt-cache show ubuntu-pro-client >/dev/null 2>&1; then
                apt-get install -y ubuntu-pro-client
            else
                apt-get install -y ubuntu-advantage-tools
            fi
            RUN_PRO_ATTACH=1
        else
            echo "Not installing the Pro client; skipping attach."
            RUN_PRO_ATTACH=0
        fi
    fi
    if ((RUN_PRO_ATTACH == 1)); then
        if pro_is_attached; then
            echo "Already attached; nothing to do."
        else
            pro status || true
            echo
            echo "Enter your Ubuntu Pro token when prompted."
            if pro attach; then
                pro status || true
            else
                echo "Ubuntu Pro attach did not complete; run 'sudo pro attach' later."
            fi
        fi
    fi
}

if pro_is_attached; then
    SECTION_NO=$((SECTION_NO + 1))
    SECTION_TITLE="Ubuntu Pro"
    echo
    echo "=============================================================="
    echo " ${SECTION_NO}. Ubuntu Pro"
    echo "=============================================================="
    echo "  This machine is already attached to Ubuntu Pro; skipping automatically."
    SKIPPED+=("Ubuntu Pro (already attached)")
elif section "Ubuntu Pro" \
    "Optional.  Ubuntu Pro is free for personal use on up to 5 machines and adds:" \
    "  - security patches for 25,000+ 'universe' packages (ESM), not just 'main'" \
    "  - Livepatch: kernel security fixes applied without a reboot" \
    "  - security coverage for up to 15 years instead of 5" \
    "Attaching needs an Ubuntu One account and a token from ubuntu.com/pro," \
    "and links this machine to that account.  Skip it if you don't need this." \
    "This section installs the Pro client if it's missing, then runs 'pro attach'." \
    "The token is not stored by this script."; then
    run_body do_ubuntu_pro
fi

# ---------------------------------------------------------------------------
# 5. Swap file
# ---------------------------------------------------------------------------

do_swap_file() {
    if swapon --show=NAME --noheadings | grep -qxF "${SWAPFILE}"; then
        echo "${SWAPFILE} is already active; leaving it as is."
    else
        if [[ ! -f "${SWAPFILE}" ]]; then
            fallocate -l "${SWAP_SIZE_GB}G" "${SWAPFILE}"
            chmod 600 "${SWAPFILE}"
            mkswap "${SWAPFILE}"
        else
            echo "${SWAPFILE} already exists; enabling it without resizing."
        fi
        swapon "${SWAPFILE}"
    fi
    if ! awk -v f="${SWAPFILE}" '$1 == f { found = 1 } END { exit !found }' /etc/fstab; then
        echo "${SWAPFILE} none swap sw 0 0" >>/etc/fstab
    fi
    swapon --show
}

CURRENT_SWAP="$(swapon --show --noheadings 2>/dev/null || true)"
# With swap already active (e.g. a swap volume from the installer) a swap file
# is rarely wanted, so the section then defaults to no.
SWAP_ASK=()
SWAP_NOTE=("Swap already active on this machine:" "(none)")
if [[ -n "${CURRENT_SWAP}" ]]; then
    SWAP_ASK=(--default-no)
    mapfile -t SWAP_LINES <<<"${CURRENT_SWAP}"
    SWAP_NOTE=(
        "Swap is already active on this machine (below), so this section defaults"
        "to NO; Enter skips it:"
        "${SWAP_LINES[@]/#/  }"
    )
fi
if section "${SWAP_ASK[@]}" "Swap file" \
    "Creates a swap file and adds it to /etc/fstab.  Swap is only a safety net;" \
    "models must fit in RAM.  You choose the size and path next." \
    "${SWAP_NOTE[@]}"; then
    ask_value SWAPFILE "Swap file path" "${SWAPFILE}" v_path "${PATH_HINT}"
    ask_value SWAP_SIZE_GB "Swap file size in GB" "${SWAP_SIZE_GB}" v_posint "Use a whole number of GB."
    run_body do_swap_file
fi

# ---------------------------------------------------------------------------
# 6. Swappiness
# ---------------------------------------------------------------------------

do_swappiness() {
    cat >/etc/sysctl.d/99-llm.conf <<EOF
# Only swap as a last resort; if a model is paging the quant is too big.
vm.swappiness=${SWAPPINESS}
EOF
    sysctl --system >/dev/null
    echo "vm.swappiness is now $(cat /proc/sys/vm/swappiness)"
}

if section "Swappiness" \
    "Sets vm.swappiness in /etc/sysctl.d/99-llm.conf so the kernel only swaps" \
    "as a last resort (if a model is paging, the quant is too big)."; then
    ask_value SWAPPINESS "vm.swappiness (0-200)" "${SWAPPINESS}" v_0to200 "Use a number from 0 to 200."
    run_body do_swappiness
fi

# ---------------------------------------------------------------------------
# 7. Transparent hugepages
# ---------------------------------------------------------------------------

do_transparent_hugepages() {
    cat >/etc/tmpfiles.d/transparent-hugepages.conf <<EOF
w /sys/kernel/mm/transparent_hugepage/enabled - - - - ${THP_MODE}
EOF
    systemd-tmpfiles --create /etc/tmpfiles.d/transparent-hugepages.conf || true
    cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
}

if section "Transparent hugepages" \
    "Sets transparent hugepages (a few percent faster on large models), now" \
    "and on every boot via /etc/tmpfiles.d/transparent-hugepages.conf."; then
    ask_value THP_MODE "Transparent hugepages mode (always, madvise, never)" "${THP_MODE}" v_thp \
        "Type always, madvise or never."
    run_body do_transparent_hugepages
fi

# ---------------------------------------------------------------------------
# 8. CPU governor
# ---------------------------------------------------------------------------

do_cpu_governor() {
    cat >/etc/systemd/system/cpu-performance.service <<'EOF'
[Unit]
Description=Set CPU frequency governor to performance for LLM inference
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do [ -w "$g" ] && echo performance > "$g"; done; for p in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do [ -w "$p" ] && echo performance > "$p"; done; exit 0'

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now cpu-performance.service
    cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "(no cpufreq)"
}

if section "CPU governor" \
    "Installs cpu-performance.service, which pins every core's frequency" \
    "governor (and energy preference) to performance at boot."; then
    run_body do_cpu_governor
fi

# ---------------------------------------------------------------------------
# 9. SSH
# ---------------------------------------------------------------------------

do_ssh() {
    systemctl enable --now ssh
}

if section "SSH" \
    "Enables and starts the OpenSSH server so you can log in remotely."; then
    missing=()
    [[ -e /usr/sbin/sshd ]] || missing+=("openssh-server (from the 'Install packages' section)")
    if deps_ok "${missing[@]}"; then
        run_body do_ssh
    fi
fi

# ---------------------------------------------------------------------------
# 9a. Key-only SSH logins
# ---------------------------------------------------------------------------

do_ssh_key_only() {
    # Privilege-separation directory sshd needs even for a config check; it is
    # missing while a socket-activated sshd has not been started yet.
    # (-p is not needed: /run always exists.)
    [[ -d /run/sshd ]] || mkdir -m 0755 /run/sshd
    # If the configuration is already broken, stop before touching anything.
    sshd -t
    mkdir -p "$(dirname "${SSHD_DROPIN}")"
    cat >"${SSHD_DROPIN}" <<'EOF'
# Key-only SSH: no password logins, no root logins.
# To undo:  sudo rm <this file> && sudo systemctl reload ssh
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
    chmod 644 "${SSHD_DROPIN}"
    if ! sshd -t; then
        rm -f "${SSHD_DROPIN}"
        echo "sshd rejected the new settings.  ${SSHD_DROPIN} was removed again;" >&2
        echo "SSH is unchanged." >&2
        fail_body "sshd rejected the key-only settings; SSH is unchanged"
    fi
    # Check the settings really are in effect: an earlier value elsewhere in
    # the sshd configuration would win over the drop-in.
    SSHD_EFFECTIVE="$(sshd -T 2>/dev/null)" || SSHD_EFFECTIVE=""
    for want in "passwordauthentication no" "kbdinteractiveauthentication no" "permitrootlogin no"; do
        if ! grep -qix "${want}" <<<"${SSHD_EFFECTIVE}"; then
            rm -f "${SSHD_DROPIN}"
            echo "'${want}' did not take effect (another sshd setting overrides it, or" >&2
            echo "/etc/ssh/sshd_config does not include sshd_config.d).  ${SSHD_DROPIN}" >&2
            echo "was removed again; SSH is unchanged." >&2
            fail_body "'${want}' did not take effect; SSH is unchanged"
        fi
    done
    echo "Wrote ${SSHD_DROPIN}"
    # reload, not restart: sessions that are open stay open.
    if systemctl is-active --quiet ssh; then
        systemctl reload ssh
        echo "SSH reloaded: password and root logins are now off."
    else
        echo "ssh.service is not running right now; the settings apply when it starts."
    fi
    echo
    echo "IMPORTANT: keep this session open.  From the computer you connect from,"
    echo "open a SECOND terminal and check that a new login still works:"
    echo "    ssh ${SSH_USER}@${SSH_ADDR:-<this-host>}"
    echo "Only close this session once that works.  If it does not, undo it here:"
    echo "    sudo rm ${SSHD_DROPIN} && sudo systemctl reload ssh"
}

if section --default-no "Key-only SSH logins" \
    "Turns off password logins and root logins over SSH, so that only an SSH" \
    "key gets in (the firewall lets SSH in from anywhere).  Written to" \
    "${SSHD_DROPIN}, checked with 'sshd -t' before it" \
    "is applied, and SSH is reloaded, not restarted, so the session you are in" \
    "stays open." \
    "CAUTION: on a machine with no screen a mistake here locks you out.  The" \
    "section refuses unless your user already has an SSH key installed, and" \
    "asks once more before it changes anything.  Both questions default to no."; then
    missing=()
    [[ -e /usr/sbin/sshd ]] || missing+=("openssh-server (from the 'Install packages' section)")
    if deps_ok "${missing[@]}"; then
        SSH_USER_DEFAULT="${SSH_USER:-${SHELL_USER:-${SUDO_USER:-}}}"
        [[ "${SSH_USER_DEFAULT}" == root ]] && SSH_USER_DEFAULT=""
        ask_value SSH_USER "User you log in as over SSH" "${SSH_USER_DEFAULT}" v_login_user \
            "Use the name of an existing user (the one you log in as)."
        SSH_KEYS="$(getent passwd "${SSH_USER}" | cut -d: -f6)/.ssh/authorized_keys"
        SSH_ADDR="$(hostname -I 2>/dev/null | awk '{print $1}')" || SSH_ADDR=""
        SSH_REFUSE=""
        if [[ "${SSH_USER}" == root ]]; then
            SSH_REFUSE="root logins would be turned off, so root cannot be the user you log in as"
        elif ! has_ssh_key "${SSH_KEYS}"; then
            SSH_REFUSE="${SSH_USER} has no SSH key in ${SSH_KEYS}"
        fi
        if [[ -n "${SSH_REFUSE}" ]]; then
            echo "  Not changing SSH: ${SSH_REFUSE}."
            echo "  With password logins off you could no longer log in.  Install a key"
            echo "  first, from the computer you connect from:"
            echo "    ssh-copy-id ${SSH_USER}@${SSH_ADDR:-<this-host>}"
            echo "  log in once with it, then re-run this script."
            echo "  Skipped: ${DONE[-1]} (refused)"
            SKIPPED+=("${DONE[-1]} (refused)")
            unset 'DONE[-1]'
        else
            echo "  ${SSH_USER} has $(grep -c . "${SSH_KEYS}" 2>/dev/null || true) line(s) in ${SSH_KEYS}."
            echo "  Say yes only if you have already logged in to this machine WITH that key"
            echo "  (no password asked).  A key that does not work means no way in over SSH."
            if confirm_no "  Turn off SSH password logins and root logins now?"; then
                run_body do_ssh_key_only
            else
                echo "  Skipped: ${DONE[-1]} (not confirmed)"
                SKIPPED+=("${DONE[-1]} (not confirmed)")
                unset 'DONE[-1]'
            fi
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 10. Firewall
# ---------------------------------------------------------------------------

do_firewall() {
    ufw default deny incoming
    ufw default allow outgoing
    if ufw app info OpenSSH >/dev/null 2>&1; then
        ufw allow OpenSSH
    else
        echo "No OpenSSH ufw profile (openssh-server not installed); allowing 22/tcp instead."
        ufw allow 22/tcp
    fi
    # Any other port sshd listens on (see the detection below), so enabling
    # the firewall cannot lock out new SSH logins.
    local p
    for p in "${SSH_PORTS[@]}"; do
        echo "Allowing SSH port ${p}/tcp"
        ufw allow "${p}/tcp"
    done
    if [[ "${EXPOSE_LAN}" == "1" && -n "${LAN_CIDR}" ]]; then
        echo "Allowing the LLM API (${LLM_PORT}/tcp) from ${LAN_CIDR} only"
        ufw allow from "${LAN_CIDR}" to any port "${LLM_PORT}" proto tcp comment 'llama-server API (LAN)'
    fi
    ufw --force enable
    ufw status verbose
}

if section "Firewall (ufw)" \
    "Blocks incoming traffic except SSH (from anywhere) and, optionally, the" \
    "llama-server API from your local subnet only.  Outgoing traffic is allowed."; then
    mapfile -t missing < <(missing_cmds ufw)
    if deps_ok "${missing[@]}"; then
        # Ports sshd really listens on, other than 22 (already allowed above).
        # Empty if sshd is missing or `sshd -T` fails.
        SSH_PORTS=()
        if command -v sshd >/dev/null 2>&1 && sshd_out="$(sshd -T 2>/dev/null)"; then
            mapfile -t SSH_PORTS < <(awk '$1 == "port" && $2 ~ /^[0-9]+$/ && $2 != 22 && !seen[$2]++ {print $2}' <<<"${sshd_out}")
        fi
        if ((${#SSH_PORTS[@]} > 0)); then
            echo "sshd also listens on: ${SSH_PORTS[*]} (will be allowed along with 22)"
        fi
        ask_expose_lan
        # The subnet is detected here, not in do_firewall, because the
        # configuration section reads EXPOSE_LAN later.
        LAN_CIDR=""
        if [[ "${EXPOSE_LAN}" == "1" ]]; then
            ask_port
            detect_lan
            if [[ -z "${LAN_CIDR}" ]]; then
                echo "Could not detect the LAN subnet; the LLM API will stay on localhost only."
                EXPOSE_LAN=0
            fi
        fi
        run_body do_firewall
    fi
fi

# ---------------------------------------------------------------------------
# 10a. mDNS (<hostname>.local)
# ---------------------------------------------------------------------------

do_mdns() {
    apt-get install -y avahi-daemon
    AVAHI_CONF=/etc/avahi/avahi-daemon.conf
    # Answer on the chosen interface only, so a Wi-Fi card that comes up
    # later does not announce the machine too.
    if ! grep -Eq '^#?allow-interfaces=' "${AVAHI_CONF}" 2>/dev/null; then
        # Installing the package starts the daemon; do not leave it
        # announcing on every interface.
        systemctl disable --now avahi-daemon.socket avahi-daemon.service || true
        echo "No allow-interfaces line in ${AVAHI_CONF}, so avahi could not be limited" >&2
        echo "to ${MDNS_DEV}.  avahi-daemon was stopped and disabled." >&2
        fail_body "avahi could not be limited to ${MDNS_DEV}; it was stopped and disabled"
    fi
    [[ -e "${AVAHI_CONF}.orig" ]] || cp -p "${AVAHI_CONF}" "${AVAHI_CONF}.orig"
    sed -i -E "s/^#?allow-interfaces=.*/allow-interfaces=${MDNS_DEV}/" "${AVAHI_CONF}"
    echo "avahi answers on ${MDNS_DEV} only (allow-interfaces in ${AVAHI_CONF})."
    systemctl enable avahi-daemon
    systemctl restart avahi-daemon
    if ((MDNS_UFW == 1)); then
        echo "Allowing mDNS (5353/udp) from ${MDNS_CIDR} only"
        ufw allow from "${MDNS_CIDR}" to any port 5353 proto udp comment 'mDNS (LAN)'
    fi
    echo "This machine now answers to $(hostname).local on the local network."
}

if section "mDNS (<hostname>.local)" \
    "Installs avahi-daemon so other computers on the local network can reach" \
    "this one as $(hostname 2>/dev/null || echo '<hostname>').local instead of by IP address (macOS and most Linux" \
    "desktops resolve .local names out of the box).  It announces this" \
    "machine's hostname and address on the local network, nothing else; skip" \
    "it if you would rather not, and use a DHCP reservation in the router." \
    "avahi is limited to one network interface, so the name is never announced" \
    "on Wi-Fi; the default is the wired interface configured in /etc/netplan." \
    "One small idle daemon; no effect on inference.  If ufw is active, 5353/udp" \
    "is opened to that interface's subnet only."; then
    # The interface comes from the netplan configuration, not only from the
    # default route, and a Wi-Fi interface is never offered as the default.
    detect_lan
    mapfile -t NETPLAN_DEVS < <(netplan_wired)
    MDNS_AUTO=""
    if ((${#NETPLAN_DEVS[@]} > 0)); then
        echo "  Wired interface(s) configured in /etc/netplan: ${NETPLAN_DEVS[*]}"
        MDNS_AUTO="${NETPLAN_DEVS[0]}"
        for dev in "${NETPLAN_DEVS[@]}"; do
            if [[ "${dev}" == "${DEFAULT_DEV}" ]]; then MDNS_AUTO="${dev}"; fi
        done
        if [[ -n "${DEFAULT_DEV}" && "${DEFAULT_DEV}" != "${MDNS_AUTO}" ]]; then
            echo "  NOTE: the default route uses ${DEFAULT_DEV}, not ${MDNS_AUTO}.  Choose the interface"
            echo "  the computers that should find this machine are connected to."
        fi
    elif wired_dev "${DEFAULT_DEV}"; then
        echo "  No wired interface found in /etc/netplan; offering the interface of the"
        echo "  default route instead."
        MDNS_AUTO="${DEFAULT_DEV}"
    else
        echo "  No wired interface found in /etc/netplan or on the default route${DEFAULT_DEV:+ (${DEFAULT_DEV} is Wi-Fi)}."
        echo "  Type the name of the interface to use (see: ip -br link)."
    fi
    ask_value MDNS_DEV "Network interface mDNS answers on" "${MDNS_DEV:-${MDNS_AUTO}}" v_netdev \
        "Use the name of an existing interface (see: ip -br link)."
    if ! wired_dev "${MDNS_DEV}"; then
        echo "  NOTE: ${MDNS_DEV} is a Wi-Fi interface; the hostname will be announced on it."
    fi
    MDNS_CIDR="$(dev_cidr "${MDNS_DEV}")" || MDNS_CIDR=""
    MDNS_UFW=0
    UFW_STATE=""
    if command -v ufw >/dev/null 2>&1; then
        UFW_STATE="$(ufw status 2>/dev/null)" || UFW_STATE=""
    fi
    if [[ "${UFW_STATE}" != "Status: active"* ]]; then
        echo "  ufw is not active, so no firewall rule is needed."
    elif [[ -n "${MDNS_CIDR}" ]]; then
        MDNS_UFW=1
        echo "  ufw is active: 5353/udp will be allowed from ${MDNS_CIDR} (${MDNS_DEV}) only."
    else
        echo "  ufw is active but the subnet of ${MDNS_DEV} could not be detected, so no rule"
        echo "  is added.  If the name does not resolve, add it by hand:"
        echo "    sudo ufw allow from <subnet> to any port 5353 proto udp"
    fi
    run_body do_mdns
fi

# ---------------------------------------------------------------------------
# 11. Automatic security updates
# ---------------------------------------------------------------------------

do_auto_updates() {
    systemctl enable --now unattended-upgrades
}

if section "Automatic security updates" \
    "Enables unattended-upgrades so security updates install on their own."; then
    missing=()
    dpkg -s unattended-upgrades >/dev/null 2>&1 \
        || missing+=("unattended-upgrades package (from the 'Install packages' section)")
    if deps_ok "${missing[@]}"; then
        run_body do_auto_updates
    fi
fi

# ---------------------------------------------------------------------------
# 11a. needrestart policy
# ---------------------------------------------------------------------------

do_needrestart_policy() {
    mkdir -p "$(dirname "${NEEDRESTART_CONF}")"
    cat >"${NEEDRESTART_CONF}" <<'EOF'
# Never restart llama-server automatically after a package upgrade: a restart
# drops the request in progress and reloads the whole model.  needrestart
# still lists it; restart it by hand when it suits:
#   sudo systemctl restart llama-server
$nrconf{override_rc}{qr(^llama-server)} = 0;
EOF
    chmod 644 "${NEEDRESTART_CONF}"
    echo "Wrote ${NEEDRESTART_CONF}"
    if ! pkg_installed needrestart; then
        echo "needrestart is not installed, so nothing restarts services after an upgrade;"
        echo "the file takes effect if it is ever installed."
    fi
    AUTO_REBOOT="$(apt-config dump Unattended-Upgrade::Automatic-Reboot 2>/dev/null)" || AUTO_REBOOT=""
    if [[ "${AUTO_REBOOT}" == *'Automatic-Reboot "true"'* ]]; then
        echo "WARNING: unattended-upgrades is set to reboot this machine automatically"
        echo "         (Unattended-Upgrade::Automatic-Reboot \"true\" under /etc/apt/apt.conf.d)."
        echo "         That stops llama-server without warning; set it to \"false\"."
    else
        echo "Automatic reboots after unattended upgrades are off (the default); left that way."
    fi
}

if section "needrestart policy" \
    "After a package upgrade Ubuntu's needrestart restarts the services that" \
    "use an updated library, on its own when the upgrade is unattended.  For" \
    "llama-server that means a dropped request and a full model reload.  This" \
    "adds ${NEEDRESTART_CONF}, which" \
    "exempts llama-server only; every other service is still restarted." \
    "Automatic reboots after unattended upgrades are left off on purpose: a" \
    "kernel update waits for you to run 'sudo reboot'."; then
    run_body do_needrestart_policy
fi

# ---------------------------------------------------------------------------
# 11b. Canonical news
# ---------------------------------------------------------------------------

do_canonical_news() {
    if [[ -f /etc/default/motd-news ]]; then
        if grep -q '^ENABLED=' /etc/default/motd-news; then
            sed -i 's/^ENABLED=.*/ENABLED=0/' /etc/default/motd-news
        else
            echo 'ENABLED=0' >>/etc/default/motd-news
        fi
        echo "Login news turned off (ENABLED=0 in /etc/default/motd-news)."
    else
        echo "/etc/default/motd-news does not exist; no login news to turn off."
    fi
    if systemctl cat motd-news.timer >/dev/null 2>&1; then
        systemctl disable --now motd-news.timer
    fi
    if command -v pro >/dev/null 2>&1; then
        if pro config set apt_news=false; then
            echo "apt news turned off (pro config set apt_news=false)."
        else
            echo "Could not turn off apt news; try later: sudo pro config set apt_news=false"
        fi
    else
        echo "The 'pro' command is not installed, so there is no apt news to turn off."
    fi
}

if section "Turn off Canonical news" \
    "Ubuntu fetches a news snippet from motd.ubuntu.com for the login message," \
    "and apt fetches 'apt news' from Canonical.  Both are regular outgoing" \
    "requests from this machine that it does not need.  This turns both off;" \
    "package updates are not affected."; then
    run_body do_canonical_news
fi

# ---------------------------------------------------------------------------
# 12. Service user and model directory
# ---------------------------------------------------------------------------

do_service_user() {
    if ((MODEL_DIR_CREATE == 1)); then
        mkdir -p "${MODEL_DIR}"
        echo "Created ${MODEL_DIR}."
    fi

    if id -u "${LLM_USER}" >/dev/null 2>&1; then
        echo "User ${LLM_USER} already exists."
    else
        useradd --system --home-dir "${MODEL_DIR}" --shell /usr/sbin/nologin "${LLM_USER}"
        echo "Created system user ${LLM_USER}."
    fi

    OWNER="$(stat -c %U "${MODEL_DIR}")"
    if [[ "${OWNER}" == "${LLM_USER}" ]]; then
        echo "${MODEL_DIR} is already owned by ${LLM_USER}."
    elif confirm "Make ${LLM_USER} the owner of ${MODEL_DIR} (currently ${OWNER}; the directory itself, not its contents)?"; then
        chown "${LLM_USER}:${LLM_USER}" "${MODEL_DIR}"
    else
        echo "Ownership left as is; ${LLM_USER} may not be able to download into it."
    fi
}

if section "Service user and model directory" \
    "Creates a system user (no login shell) that runs llama-server, and the" \
    "directory models are stored in, owned by that user.  You choose both."; then
    ask_llm_user
    MODEL_DIR_CREATE=0      # 1 = do_service_user creates MODEL_DIR
    while :; do
        ask_model_dir
        case "${MODEL_DIR}/" in
            /home/* | /root/* | /run/user/*)
                echo "  ${MODEL_DIR} is under a home directory.  The service runs with"
                echo "  ProtectHome=true and could not read models there."
                if ! confirm "  Use it anyway?"; then
                    unset 'ASKED[MODEL_DIR]'
                    MODEL_DIR=""
                    continue
                fi
                ;;
        esac
        if [[ -d "${MODEL_DIR}" ]]; then
            echo "  ${MODEL_DIR} exists (owner: $(stat -c %U "${MODEL_DIR}"))."
            break
        fi
        if [[ -e "${MODEL_DIR}" ]]; then
            echo "  ${MODEL_DIR} exists but is not a directory; choose another path."
            unset 'ASKED[MODEL_DIR]'
            MODEL_DIR=""
            continue
        fi
        echo "  ${MODEL_DIR} does not exist."
        if confirm "  Create ${MODEL_DIR}?"; then
            MODEL_DIR_CREATE=1
            break
        fi
        echo "  Choose a different name and path for the model directory."
        unset 'ASKED[MODEL_DIR]'
        MODEL_DIR=""
    done
    run_body do_service_user
fi

# ---------------------------------------------------------------------------
# 13. Build the inference engines
# ---------------------------------------------------------------------------

build_engine() {
    local name="$1" repo="$2" dir="$3"
    echo "==> Building ${name} in ${dir} (native flags for this CPU)"
    if [[ -d "${dir}/.git" ]]; then
        git -C "${dir}" pull --ff-only
    else
        git clone --depth 1 "${repo}" "${dir}"
    fi
    cmake -S "${dir}" -B "${dir}/build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_NATIVE=ON \
        -DBUILD_SHARED_LIBS=OFF
    cmake --build "${dir}/build" --config Release -j "$(nproc)" --target llama-server llama-cli llama-bench
}

do_build_engines() {
    for eng in ${BUILD_ENGINES}; do
        case "${eng}" in
            ik) build_engine "ik_llama.cpp" "${IK_REPO}" "${IK_DIR}" ;;
            mainline) build_engine "llama.cpp" "${MAINLINE_REPO}" "${MAINLINE_DIR}" ;;
        esac
    done
}

if section "Build inference engines" \
    "Clones and builds llama-server from source with native CPU flags:" \
    "  mainline = llama.cpp (runs MTP heads, newest model support)" \
    "  ik       = ik_llama.cpp (faster CPU kernels, no MTP)" \
    "You choose which to build and where.  Takes a while."; then
    mapfile -t missing < <(missing_cmds git cmake c++ make)
    [[ -e /usr/include/curl/curl.h ]] || compgen -G '/usr/include/*/curl/curl.h' >/dev/null \
        || missing+=("libcurl development headers (libcurl4-openssl-dev)")
    if deps_ok "${missing[@]}"; then
        ask_value BUILD_ENGINES "Engines to build (space-separated: mainline, ik)" "${BUILD_ENGINES}" v_engines \
            "Use mainline, ik, or both separated by a space."
        ask_engine_dirs
        run_body do_build_engines
    fi
fi

# ---------------------------------------------------------------------------
# 14. Engine updater
# ---------------------------------------------------------------------------

do_engine_updater() {
    mkdir -p "$(dirname "${UPDATER}")"
    cat >"${UPDATER}" <<EOF
#!/usr/bin/env bash
# Pull and rebuild the inference engines, then restart the server.
set -euo pipefail
[[ "\${EUID}" -eq 0 ]] || { echo "Run as root: sudo \$0"; exit 1; }
for dir in${UPDATE_DIRS}; do
    [[ -d "\${dir}/.git" ]] || continue
    echo "==> Updating \${dir}"
    git -C "\${dir}" pull --ff-only
    cmake -S "\${dir}" -B "\${dir}/build" -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON -DBUILD_SHARED_LIBS=OFF
    cmake --build "\${dir}/build" --config Release -j "\$(nproc)" --target llama-server llama-cli llama-bench
done
systemctl restart llama-server
systemctl --no-pager --full status llama-server || true
EOF
    chmod 755 "${UPDATER}"
    echo "Installed ${UPDATER}"
}

if section "Engine updater script" \
    "Installs a script that pulls and rebuilds the engines, then restarts" \
    "llama-server.  Run it every few weeks."; then
    ask_value UPDATER "Updater script path" "${UPDATER}" v_path "${PATH_HINT}"
    ask_value BUILD_ENGINES "Engines the updater rebuilds (space-separated: mainline, ik)" "${BUILD_ENGINES}" v_engines \
        "Use mainline, ik, or both separated by a space."
    ask_engine_dirs
    UPDATE_DIRS=""
    for eng in ${BUILD_ENGINES}; do
        case "${eng}" in
            ik) UPDATE_DIRS+=" ${IK_DIR}" ;;
            mainline) UPDATE_DIRS+=" ${MAINLINE_DIR}" ;;
        esac
    done
    run_body do_engine_updater
fi

# ---------------------------------------------------------------------------
# 15. Model download
# ---------------------------------------------------------------------------

do_download_model() {
    echo "Free space in ${MODEL_DIR}: $(df -h --output=avail "${MODEL_DIR}" 2>/dev/null | tail -1 | tr -d ' ' || echo unknown)"
    echo "Downloading to ${MODEL_FILE}"
    if runuser -u "${LLM_USER}" -- curl -fL --retry 5 --retry-delay 10 -C - -o "${MODEL_FILE}" "${MODEL_URL}"; then
        echo "Download complete"
    else
        echo "WARNING: model download failed.  Re-run this script to resume, or put a"
        echo "         GGUF in ${MODEL_DIR} and set MODEL= in the llama-server config."
        fail_body "model download failed"
    fi
}

if section "Download a model" \
    "Lets you pick a model from a menu (or paste any GGUF URL) and downloads" \
    "it into the model directory as the service user.  The download is" \
    "resumable; the listed models are 17-24 GB."; then
    select_model
    if [[ -z "${MODEL_URL}" ]]; then
        echo "No model chosen; nothing to download."
    else
        ask_llm_user
        ask_model_dir
        model_filename_from_url
        MODEL_FILE="${MODEL_DIR}/${MODEL_FILENAME}"
        missing=()
        mapfile -t missing < <(missing_cmds curl)
        id -u "${LLM_USER}" >/dev/null 2>&1 \
            || missing+=("user ${LLM_USER} (from the 'Service user and model directory' section)")
        [[ -d "${MODEL_DIR}" ]] \
            || missing+=("directory ${MODEL_DIR} (from the 'Service user and model directory' section)")
        if deps_ok "${missing[@]}"; then
            run_body do_download_model
        fi
    fi
fi

write_conf() {
    if [[ "${EXPOSE_LAN}" == "1" ]]; then HOST_BIND="0.0.0.0"; else HOST_BIND="127.0.0.1"; fi

    if [[ -f "${CONF}" ]]; then
        BACKUP="${CONF}.bak-$(date +%Y%m%d-%H%M%S)"
        cp -p "${CONF}" "${BACKUP}"
        # An old copy may be world-readable; the new config holds the API key.
        chmod 640 "${BACKUP}"
        echo "Backed up the existing config to ${BACKUP}"
    fi
    mkdir -p "$(dirname "${CONF}")"
    # Create it private first, so the key is never readable by others.
    install -m 640 -o root -g root /dev/null "${CONF}"
    cat >"${CONF}" <<EOF
# llama-server configuration.  Edit, then: sudo systemctl restart llama-server
#
# Which engine the service runs: mainline | ik
# (mainline runs MTP heads; ik has no MTP and may not load MTP GGUFs)
ENGINE=$(shq "${ENGINE}")
IK_DIR=$(shq "${IK_DIR}")
MAINLINE_DIR=$(shq "${MAINLINE_DIR}")

# Model (GGUF) to serve.  MoE with ~3B active parameters is the sweet spot here.
MODEL=$(shq "${MODEL_FILE}")

HOST=$(shq "${HOST_BIND}")
PORT=$(shq "${LLM_PORT}")

# Physical cores only.  Hyperthreads slow memory-bound inference down.
THREADS=$(shq "${THREADS}")

# Context window.  KV cache is q8_0, so 64K costs a few GB; 128K is fine on 64GB
# but generation slows as the cache fills.
CTX=$(shq "${CTX}")

# Name the model answers to (clients send this as "model").
MODEL_ALIAS=$(shq "${MODEL_ALIAS}")

# API key.  Empty = no authentication.  Clients send: Authorization: Bearer <key>
# (/health stays public).  Keep this file readable by root and the service user only.
API_KEY=$(shq "${API_KEY}")

# Sampling.  Ornith: --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0
# Stock Qwen3.6 non-thinking chat:
#   --temp 0.7 --top-p 0.8 --top-k 20 --min-p 0 --presence-penalty 1.5
SAMPLING_ARGS=$(shq "${SAMPLING_ARGS}")

# ik_llama.cpp only: fused MoE and run-time repacking (-rtr reads the model
# fully into RAM, no mmap, which is what --mlock wants anyway).
IK_ARGS=$(shq "${IK_ARGS}")

# llama.cpp (mainline) only.
# - --spec-type draft-mtp --spec-draft-n-max N: MTP speculative decoding,
#   only for a GGUF with an MTP head (try N = 1..6).
# - --reasoning-budget N caps thinking per reply (-1 = unlimited, 0 = off).
#   To turn thinking off entirely instead:
#     --chat-template-kwargs {"enable_thinking":false}
MAINLINE_ARGS=$(shq "${MAINLINE_ARGS}")

# Anything else, passed to either engine verbatim.
EXTRA_ARGS=$(shq "${EXTRA_ARGS}")
EOF
    if getent group "${LLM_USER}" >/dev/null 2>&1; then
        chown root:"${LLM_USER}" "${CONF}"
        echo "Wrote ${CONF} (readable by root and ${LLM_USER} only)"
    else
        echo "Wrote ${CONF} (readable by root only: the service user ${LLM_USER} does not"
        echo "exist yet; the 'llama-server systemd service' section gives it access)."
    fi
}

# ---------------------------------------------------------------------------
# 16. llama-server config
# ---------------------------------------------------------------------------

if section "llama-server configuration" \
    "Writes the llama-server settings file (engine, model, address, port," \
    "threads, context size, sampling and engine flags).  You are asked for" \
    "each value, including an API key.  An existing file is backed up before it" \
    "is replaced.  It is readable by root and the service user only."; then
    ask_value CONF "Config file path" "${CONF}" v_path "${PATH_HINT}"
    ask_engine
    ask_model_dir
    if [[ -z "${MODEL_FILE}" ]]; then
        if ((MODEL_CHOSEN == 0)); then
            echo "  Which model will the service run?"
            select_model
        fi
        if [[ -n "${MODEL_URL}" ]]; then
            model_filename_from_url
            MODEL_FILE="${MODEL_DIR}/${MODEL_FILENAME}"
        else
            MODEL_FILE="${MODEL_DIR}/model.gguf"
        fi
    fi
    ask_value MODEL_FILE "Model file (GGUF) to serve" "${MODEL_FILE}" v_path "${PATH_HINT}"
    missing=()
    [[ -x "$(engine_bin)" ]] \
        || missing+=("${ENGINE} engine at $(engine_bin) (from the 'Build inference engines' section)")
    [[ -f "${MODEL_FILE}" ]] || missing+=("model file ${MODEL_FILE} (from the 'Download a model' section)")
    if deps_ok "${missing[@]}"; then
        ask_expose_lan
        ask_port
        [[ -n "${THREADS}" ]] || THREADS="$(detect_phys_cores)"
        ask_value THREADS "Inference threads (physical cores, not hyperthreads)" "${THREADS}" v_posint \
            "Use a whole number."
        ask_value CTX "Context window in tokens (coding agents need 64K+)" "${CTX}" v_posint "Use a whole number."
        ask_value MODEL_ALIAS "Model name clients ask for (--alias)" "${MODEL_ALIAS}" v_alias \
            "Letters, digits, . _ - only."
        ask_llm_user
        ask_api_key

        SAMPLING_ARGS="--temp 0.6 --top-p 0.95 --top-k 20 --min-p 0"
        echo "  Sampling: Ornith recommends '--temp 0.6 --top-p 0.95 --top-k 20 --min-p 0'."
        echo "  For stock Qwen3.6 non-thinking chat use"
        echo "  '--temp 0.7 --top-p 0.8 --top-k 20 --min-p 0 --presence-penalty 1.5'."
        ask_value SAMPLING_ARGS "Sampling flags" "${SAMPLING_ARGS}" v_any

        echo "  (The MTP default below follows the model picked from the menu; adjust it if"
        echo "  you serve a different file.)"
        if ((MODEL_HAS_MTP == 1)); then
            MAINLINE_ARGS="--spec-type draft-mtp --spec-draft-n-max 2 --reasoning-budget 1024"
        else
            MAINLINE_ARGS="--reasoning-budget 1024"
            echo "  The model has no known MTP head, so the MTP flags are left out."
        fi
        echo "  mainline flags: --spec-type draft-mtp --spec-draft-n-max N needs an MTP GGUF;"
        echo "  --reasoning-budget caps thinking tokens per reply (-1 = unlimited, 0 = off)."
        ask_value MAINLINE_ARGS "llama.cpp (mainline) flags" "${MAINLINE_ARGS}" v_any
        IK_ARGS="-fmoe -rtr"
        ask_value IK_ARGS "ik_llama.cpp flags (fused MoE, run-time repacking)" "${IK_ARGS}" v_any
        EXTRA_ARGS=""
        ask_value EXTRA_ARGS "Extra flags for either engine (blank = none)" "${EXTRA_ARGS}" v_any

        run_body write_conf
    fi
fi

# ---------------------------------------------------------------------------
# 17. Service wrapper
# ---------------------------------------------------------------------------

do_start_wrapper() {
    mkdir -p "$(dirname "${WRAPPER}")"
    cat >"${WRAPPER}" <<EOF
#!/usr/bin/env bash
# Starts llama-server from the engine selected in ${CONF}.
set -euo pipefail
# shellcheck disable=SC1091
source "${CONF}"

# Pin the model in RAM: ik takes --mlock; current llama.cpp replaced --mlock
# by --load-mode mlock (and rejects --mlock).
case "\${ENGINE}" in
    ik)
        BIN="\${IK_DIR:-${IK_DIR}}/build/bin/llama-server"
        ENGINE_ARGS="-fa --no-mmap --mlock \${IK_ARGS:-}"
        ;;
    mainline)
        BIN="\${MAINLINE_DIR:-${MAINLINE_DIR}}/build/bin/llama-server"
        ENGINE_ARGS="-fa on --load-mode mlock \${MAINLINE_ARGS:-}"
        ;;
    *)
        echo "ENGINE must be 'ik' or 'mainline' (got '\${ENGINE}')" >&2
        exit 1
        ;;
esac

[[ -x "\${BIN}" ]]  || { echo "\${BIN} not built; run the engine updater" >&2; exit 1; }
[[ -f "\${MODEL}" ]] || { echo "Model not found: \${MODEL} (edit ${CONF})" >&2; exit 1; }

# --api-key only when the config has a key.
API_ARGS=()
if [[ -n "\${API_KEY:-}" ]]; then API_ARGS=(--api-key "\${API_KEY}"); fi

# shellcheck disable=SC2086
exec "\${BIN}" \\
    -m "\${MODEL}" \\
    --host "\${HOST}" --port "\${PORT}" \\
    -t "\${THREADS}" -tb "\${THREADS}" \\
    -c "\${CTX}" -np 1 \\
    --alias "\${MODEL_ALIAS:-ornith}" \\
    --cache-reuse 256 \\
    -ctk q8_0 -ctv q8_0 \\
    --jinja \\
    "\${API_ARGS[@]}" \\
    \${SAMPLING_ARGS:-} \${ENGINE_ARGS} \${EXTRA_ARGS:-}
EOF
    chmod 755 "${WRAPPER}"
    echo "Installed ${WRAPPER}"
}

if section "llama-server start wrapper" \
    "Installs the script systemd runs: it reads the config file and starts" \
    "llama-server from the engine selected there."; then
    ask_value WRAPPER "Wrapper script path" "${WRAPPER}" v_path "${PATH_HINT}"
    ask_value CONF "Config file path" "${CONF}" v_path "${PATH_HINT}"
    [[ -f "${CONF}" ]] || echo "  Note: ${CONF} does not exist yet; the wrapper needs it to start."
    run_body do_start_wrapper
fi

# ---------------------------------------------------------------------------
# 18. systemd service
# ---------------------------------------------------------------------------

do_systemd_service() {
    # The config holds the API key: group it to the service user so the
    # wrapper can read it (covers a config written before the user existed).
    if [[ -f "${CONF}" ]]; then
        chown root:"${LLM_USER}" "${CONF}"
        chmod 640 "${CONF}"
    fi
    cat >"${SERVICE_UNIT}" <<EOF
[Unit]
Description=llama-server (CPU LLM inference, engine chosen in ${CONF})
After=network-online.target cpu-performance.service
Wants=network-online.target

[Service]
Type=simple
User=${LLM_USER}
Group=${LLM_USER}
ExecStart=${WRAPPER}
Restart=on-failure
RestartSec=5
# Let the model weights be pinned in RAM (--mlock / --load-mode mlock).
LimitMEMLOCK=infinity
LimitNOFILE=65536
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadOnlyPaths=-${MODEL_DIR}
# Hardening.  Each directive below installs no seccomp filter and was tested
# with llama-server (mlock, /health and completions all work).
# Capabilities: the service runs as a non-root user and already has none; this
# only empties the bounding set so none can be regained.  mlock needs no
# capability because LimitMEMLOCK=infinity.
CapabilityBoundingSet=
AmbientCapabilities=
# Devices: CPU-only, so allow just the standard pseudo devices.
DevicePolicy=closed
# Read-only /sys/fs/cgroup; hide other users' processes in /proc.
ProtectControlGroups=yes
ProtectProc=invisible
# Own SysV/POSIX IPC namespace, cleaned up on stop; llama-server uses neither.
PrivateIPC=yes
RemoveIPC=yes
# Files the service creates are private to it.
UMask=0077
EOF
    if ((HARDEN_SECCOMP == 1)); then
        cat >>"${SERVICE_UNIT}" <<EOF
# Optional hardening (asked for): these install a seccomp filter, which adds
# about 30 ns to every system call.
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectClock=yes
ProtectHostname=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK
RestrictNamespaces=yes
LockPersonality=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
SystemCallArchitectures=native
EOF
    fi
    if ((HARDEN_MDWE == 1)); then
        cat >>"${SERVICE_UNIT}" <<EOF
# Optional hardening (asked for): no memory can be both writable and executable.
MemoryDenyWriteExecute=yes
EOF
    fi
    cat >>"${SERVICE_UNIT}" <<EOF

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable llama-server
    echo "Installed and enabled llama-server.service"
}

if section "llama-server systemd service" \
    "Installs and enables ${SERVICE_UNIT} so llama-server starts at boot" \
    "as the service user, with the model directory read-only.  The unit is" \
    "hardened: no capabilities, only the standard pseudo devices, read-only" \
    "cgroup files, other users' processes hidden, private IPC, private files." \
    "None of that touches inference speed.  Two more groups are offered below."; then
    ask_llm_user
    ask_model_dir
    ask_value WRAPPER "Wrapper script path" "${WRAPPER}" v_path "${PATH_HINT}"
    ask_value CONF "Config file path" "${CONF}" v_path "${PATH_HINT}"
    echo "  Optional: 12 more directives (private /dev, read-only kernel tunables, no"
    echo "  other address families or namespaces, no realtime...).  They worked with"
    echo "  llama-server but add a seccomp filter: about 30 ns per system call, an"
    echo "  estimated 0.4% or less of generation time (below what could be measured)."
    if confirm_no "  Add those 12 directives?"; then HARDEN_SECCOMP=1; fi
    echo "  Optional: MemoryDenyWriteExecute=yes (no memory both writable and executable)."
    echo "  Tested with mainline only; if the ik build fails to start, remove that line."
    if confirm_no "  Add MemoryDenyWriteExecute=yes?"; then HARDEN_MDWE=1; fi
    missing=()
    id -u "${LLM_USER}" >/dev/null 2>&1 \
        || missing+=("user ${LLM_USER} (from the 'Service user and model directory' section)")
    [[ -d "${MODEL_DIR}" ]] \
        || missing+=("directory ${MODEL_DIR} (from the 'Service user and model directory' section)")
    [[ -x "${WRAPPER}" ]] || missing+=("${WRAPPER} (from the 'llama-server start wrapper' section)")
    for pth in "${MODEL_DIR}" "${WRAPPER}" "${CONF}" "${IK_DIR}" "${MAINLINE_DIR}"; do
        case "${pth}/" in
            /home/* | /root/* | /run/user/*)
                missing+=("${pth} is under a home directory, which the service cannot read (ProtectHome=true)") ;;
        esac
    done
    if deps_ok "${missing[@]}"; then
        run_body do_systemd_service
    fi
fi

# ---------------------------------------------------------------------------
# 19. Start the service
# ---------------------------------------------------------------------------

do_start_service() {
    if systemctl restart llama-server; then
        healthy=0
        # /health is public on both engines, so no API key is needed here.
        for _ in $(seq 1 120); do
            if curl -fsS "http://127.0.0.1:${HEALTH_PORT}/health" >/dev/null 2>&1; then
                healthy=1
                break
            fi
            sleep 2
        done
        if ((healthy == 1)); then
            echo "llama-server is up on port ${HEALTH_PORT}."
        else
            echo "llama-server did not report healthy yet.  Check: journalctl -u llama-server -e"
            fail_body "llama-server did not report healthy"
        fi
    else
        echo "llama-server failed to start.  Last log lines:"
        journalctl -u llama-server -n 20 --no-pager || true
        fail_body "llama-server failed to start"
    fi
}

if section "Start llama-server" \
    "(Re)starts llama-server and waits up to 4 minutes for it to report healthy." \
    "Loading a ~23 GB model into RAM takes a minute or two."; then
    missing=()
    [[ -f "${SERVICE_UNIT}" ]] || missing+=("${SERVICE_UNIT} (from the 'llama-server systemd service' section)")
    command -v curl >/dev/null 2>&1 || missing+=("command 'curl' (needed for the health check)")
    if [[ -f "${CONF}" ]]; then
        # Read the values the service will actually use.
        CONF_VALUES="$(
            # shellcheck disable=SC1090
            source "${CONF}"
            printf '%s\n%s\n%s\n%s\n' "${MODEL:-}" "${PORT:-8080}" "${ENGINE:-mainline}" \
                "$([[ "${ENGINE:-}" == ik ]] && echo "${IK_DIR:-}" || echo "${MAINLINE_DIR:-}")"
        )"
        mapfile -t cv <<<"${CONF_VALUES}"
        [[ -f "${cv[0]}" ]] || missing+=("model file ${cv[0]} (from the 'Download a model' section)")
        [[ -x "${cv[3]}/build/bin/llama-server" ]] \
            || missing+=("${cv[2]} engine at ${cv[3]} (from the 'Build inference engines' section)")
        HEALTH_PORT="${cv[1]}"
    else
        missing+=("${CONF} (from the 'llama-server configuration' section)")
        HEALTH_PORT="${LLM_PORT}"
    fi
    if deps_ok "${missing[@]}"; then
        run_body do_start_service
    fi
fi

# ---------------------------------------------------------------------------
# 19a. Login message
# ---------------------------------------------------------------------------

# write_motd_script: print the login-message script (plain sh).
write_motd_script() {
    cat <<EOF
#!/bin/sh
# Login message: llama-server status.  Installed by
# first_time_llm_server_install.sh; re-running that script replaces this file.
#
# Read-only and quick.  Every step is guarded, so a login is never held up or
# refused because of it.  The API key in the config file is never printed.
CONF=$(shq "${CONF}")
EOF
    cat <<'EOF'

# conf_get KEY: the value of KEY= in the config file, without its quotes.
conf_get() {
    [ -r "$CONF" ] || return 0
    { sed -n "s/^$1=//p" "$CONF" | tail -n 1 | sed -e "s/^[\"']//" -e "s/[\"']\$//"; } 2>/dev/null
}

state="$(systemctl is-active llama-server 2>/dev/null)"
engine="$(conf_get ENGINE)"
model="$(conf_get MODEL)"
model_alias="$(conf_get MODEL_ALIAS)"
host="$(conf_get HOST)"
port="$(conf_get PORT)"

echo
echo "  llama-server: ${state:-unknown}"
if [ -n "$engine$model$port" ]; then
    echo "  Engine:       ${engine:-unknown}"
    echo "  Model:        ${model##*/}${model_alias:+ (answers to: $model_alias)}"
    case "$host" in
        0.0.0.0)
            addr="$(hostname -I 2>/dev/null | awk '{print $1}')"
            reach="local network"
            ;;
        *)
            addr="$host"
            reach="this machine only"
            ;;
    esac
    if [ -n "$addr" ] && [ -n "$port" ]; then
        echo "  API:          http://$addr:$port/v1  ($reach)"
    fi
else
    echo "  Settings:     $CONF (not found, or not readable by this user)"
fi

awk '/^MemTotal:/ {t = $2} /^MemAvailable:/ {a = $2} /^SwapTotal:/ {st = $2} /^SwapFree:/ {sf = $2}
     END { if (t > 0) printf "  Memory:       %.1f of %.1f GB RAM in use, %.1f of %.1f GB swap in use\n",
               (t - a) / 1048576, t / 1048576, (st - sf) / 1048576, st / 1048576 }' /proc/meminfo 2>/dev/null

# CPU temperature straight from /sys: the package sensor, else coretemp.
temp=""
for d in /sys/class/thermal/thermal_zone*; do
    [ -r "$d/type" ] || continue
    if [ "$(cat "$d/type" 2>/dev/null)" = x86_pkg_temp ]; then
        temp="$(cat "$d/temp" 2>/dev/null)"
        break
    fi
done
if [ -z "$temp" ]; then
    for d in /sys/class/hwmon/hwmon*; do
        [ -r "$d/name" ] || continue
        if [ "$(cat "$d/name" 2>/dev/null)" = coretemp ]; then
            temp="$(cat "$d/temp1_input" 2>/dev/null)"
            break
        fi
    done
fi
case "$temp" in
    "" | *[!0-9]*) ;;
    *) echo "  CPU:          $((temp / 1000)) C" ;;
esac
echo
exit 0
EOF
}

do_login_motd() {
    mkdir -p "$(dirname "${MOTD_SCRIPT}")"
    TMP_MOTD="$(mktemp)"
    write_motd_script >"${TMP_MOTD}"
    if [[ -f "${MOTD_SCRIPT}" ]] && cmp -s "${TMP_MOTD}" "${MOTD_SCRIPT}"; then
        echo "${MOTD_SCRIPT} is already up to date."
    else
        if [[ -f "${MOTD_SCRIPT}" ]]; then
            # The backup's name has a dot in it, so it is not run at login
            # (run-parts skips such names); it is made non-executable as well.
            BACKUP="${MOTD_SCRIPT}.bak-$(date +%Y%m%d-%H%M%S)"
            cp -p "${MOTD_SCRIPT}" "${BACKUP}"
            chmod 644 "${BACKUP}"
            echo "Backed up the existing script to ${BACKUP}"
        fi
        install -m 755 "${TMP_MOTD}" "${MOTD_SCRIPT}"
        echo "Installed ${MOTD_SCRIPT}"
    fi
    rm -f "${TMP_MOTD}"
    echo "It adds this to the login message:"
    "${MOTD_SCRIPT}" || true
}

if section "Login message" \
    "Installs ${MOTD_SCRIPT}, which adds a few lines to the" \
    "message shown at each login: whether llama-server is running, the engine" \
    "and model from the config file, the API address, RAM and swap in use, and" \
    "the CPU temperature if the kernel exposes it.  It is read-only and quick," \
    "and never prints the API key.  An existing copy is backed up if it differs."; then
    ask_value CONF "Config file path" "${CONF}" v_path "${PATH_HINT}"
    run_body do_login_motd
fi

# ---------------------------------------------------------------------------
# 20. Summary
# ---------------------------------------------------------------------------

do_summary() {
    # Prefer the values the service actually uses, if the config file exists.
    S_ENGINE="${ENGINE}" S_PORT="${LLM_PORT}" S_HOST="" S_MODEL="${MODEL_FILE}" S_THREADS="${THREADS}"
    S_KEY="${API_KEY}" S_ALIAS="${MODEL_ALIAS}"
    if [[ -f "${CONF}" ]]; then
        mapfile -t cv < <(
            # shellcheck disable=SC1090
            source "${CONF}"
            printf '%s\n' "${ENGINE:-}" "${PORT:-}" "${HOST:-}" "${MODEL:-}" "${THREADS:-}" \
                "${API_KEY:-}" "${MODEL_ALIAS:-}"
        )
        S_ENGINE="${cv[0]:-${S_ENGINE}}" S_PORT="${cv[1]:-${S_PORT}}" S_HOST="${cv[2]:-}"
        S_MODEL="${cv[3]:-${S_MODEL}}" S_THREADS="${cv[4]:-${S_THREADS}}"
        S_KEY="${cv[5]:-}" S_ALIAS="${cv[6]:-${S_ALIAS}}"
    fi
    [[ -n "${S_THREADS}" ]] || S_THREADS="$(detect_phys_cores)"
    if [[ -z "${S_HOST}" ]]; then
        if [[ "${EXPOSE_LAN}" == "1" ]]; then S_HOST="0.0.0.0"; else S_HOST="127.0.0.1"; fi
    fi

    echo
    echo "Sections run:     ${#DONE[@]}"
    echo "Sections failed:  ${#FAILED[@]}"
    for s in "${FAILED[@]}"; do
        echo "  - ${s}"
    done
    echo "Sections skipped: ${#SKIPPED[@]}"
    for s in "${SKIPPED[@]}"; do
        echo "  - ${s}"
    done

    if command -v pro >/dev/null 2>&1; then
        echo
        echo "Ubuntu Pro:"
        pro status || true
    fi

    echo
    echo "Engines:"
    for dir in "${IK_DIR}" "${MAINLINE_DIR}"; do
        if [[ -x "${dir}/build/bin/llama-server" ]]; then
            echo "  ${dir}  ($(git -C "${dir}" log -1 --format='%h %cd' --date=short 2>/dev/null || echo unknown))"
        fi
    done
    echo "  active: ${S_ENGINE}  (change ENGINE= in ${CONF})"

    echo
    echo "llama-server:"
    systemctl --no-pager --full status llama-server 2>/dev/null || true
    echo
    echo "Unit hardening (lower is better):"
    systemd-analyze security llama-server --no-pager 2>/dev/null | tail -n 1 || true

    echo
    echo "Memory/swap:"
    free -h
    swapon --show || true

    echo
    echo "Listening sockets:"
    ss -lntp | grep -E ":(22|${S_PORT})\b" || true

    if command -v ufw >/dev/null 2>&1; then
        echo
        echo "Firewall:"
        ufw status verbose || true
    fi

    HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
    echo
    echo "Try it:"
    if [[ "${S_HOST}" == "0.0.0.0" ]]; then
        echo "  Web UI:  http://${HOST_IP:-<host-ip>}:${S_PORT}/"
        echo "  API:     http://${HOST_IP:-<host-ip>}:${S_PORT}/v1/chat/completions  (OpenAI-compatible)"
    else
        echo "  ssh -L ${S_PORT}:127.0.0.1:${S_PORT} ${HOST_IP:-<host-ip>}   then open http://localhost:${S_PORT}/"
    fi
    if [[ -n "${S_KEY}" ]]; then
        echo
        echo "API key (stored in ${CONF}, readable by root and ${LLM_USER} only):"
        echo "  ${S_KEY}"
        if [[ "${S_HOST}" == "0.0.0.0" ]]; then S_ADDR="${HOST_IP:-<host-ip>}"; else S_ADDR="localhost"; fi
        echo "  curl http://${S_ADDR}:${S_PORT}/v1/chat/completions \\"
        echo "    -H 'Authorization: Bearer ${S_KEY}' -H 'Content-Type: application/json' \\"
        echo "    -d '{\"model\":\"${S_ALIAS}\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}'"
        echo "  /health needs no key.  After your next login \$LLAMA_API_KEY holds the key"
        echo "  if the ~/.zshrc section ran: -H \"Authorization: Bearer \$LLAMA_API_KEY\""
    else
        echo
        echo "No API key is set: anyone who can reach the port can use the server."
    fi

    echo
    echo "Benchmark (stop the service first; MTP speed shows in llama-server, not llama-bench):"
    echo "  sudo systemctl stop llama-server"
    echo "  ${MAINLINE_DIR}/build/bin/llama-bench -m ${S_MODEL:-<model>.gguf} -t ${S_THREADS} -fa 1"
    echo "  # ik_llama.cpp has no MTP support; point it at a GGUF WITHOUT an MTP head:"
    echo "  ${IK_DIR}/build/bin/llama-bench -m <plain>.gguf -t ${S_THREADS} -fa 1 -fmoe 1 -rtr 1"
    echo "  sudo systemctl start llama-server"

    echo
    echo "Hardware health:"
    S_TEMP="$(cpu_temp_c)" || S_TEMP=""
    if [[ -n "${S_TEMP}" ]]; then S_TEMP="${S_TEMP} C"; fi
    echo "  CPU temperature: ${S_TEMP:-not readable}  (under load: watch -n2 sensors)"
    S_THROTTLE=""
    for f in /sys/devices/system/cpu/cpu0/thermal_throttle/{core,package}_throttle_count; do
        [[ -r "${f}" ]] || continue
        S_COUNT="$(cat "${f}" 2>/dev/null)" || S_COUNT="?"
        f="${f##*/}"
        S_THROTTLE+="${S_THROTTLE:+, }${f%%_*} ${S_COUNT}"
    done
    echo "  Thermal throttling since boot: ${S_THROTTLE:-not readable}  (rising under load = improve cooling)"
    if command -v nvme >/dev/null 2>&1; then
        for dev in /dev/nvme[0-9]; do
            [[ -e "${dev}" ]] || continue
            S_NVME="$(nvme smart-log "${dev}" 2>/dev/null \
                | grep -iE '^(critical_warning|temperature|percentage_used|media_errors)[[:space:]]*:' \
                | sed -E 's/[[:space:]]*:[[:space:]]*/ /' | paste -sd ',' - | sed 's/,/, /g')" || S_NVME=""
            echo "  ${dev}: ${S_NVME:-could not read; try: sudo nvme smart-log ${dev}}"
        done
    fi

    detect_lan
    echo
    echo "Network:"
    if [[ -n "${DEFAULT_DEV}" ]]; then
        S_MAC="$(cat "/sys/class/net/${DEFAULT_DEV}/address" 2>/dev/null)" || S_MAC=""
        echo "  ${DEFAULT_DEV}: MAC ${S_MAC:-unknown}, IP ${HOST_IP:-unknown}"
    else
        echo "  IP ${HOST_IP:-unknown}  (MAC: ip -br link)"
    fi
    echo "  Reserve that IP for that MAC in your router (DHCP reservation), so the"
    echo "  address clients and the firewall rule rely on never changes."

    echo
    echo "BIOS settings this script cannot make:"
    echo "  - After Power Failure = Power On (the server returns after an outage)"
    echo "  - Wi-Fi and Bluetooth off, if unused"
    echo "  - fan/cooling profile = performance"
    echo
    echo "Do not install earlyoom: when memory runs low it kills the biggest process,"
    echo "which here is llama-server with its model pinned in RAM."
}

if section "Summary" \
    "Read-only: shows what was done and skipped, Ubuntu Pro, engine versions," \
    "service status and hardening score, memory/swap, listening ports, firewall," \
    "how to connect (with the API key) and how to benchmark, then hardware" \
    "health (temperature, throttling, NVMe), the MAC and IP for a DHCP" \
    "reservation, and BIOS notes."; then
    run_body do_summary
fi

if [[ -f /var/run/reboot-required ]]; then
    echo
    echo "A reboot is required to finish the kernel upgrade: sudo reboot"
fi

# Always printed, even if the Summary section was skipped or failed itself.
echo
if ((${#FAILED[@]} > 0)); then
    echo "Done, but ${#FAILED[@]} section(s) FAILED:"
    for i in "${!FAILED[@]}"; do
        echo "  - ${FAILED[$i]}"
        echo "      ${FAILED_WHY[$i]}"
    done
    echo "The full error output is further up, where each section ran."
    echo "Fix the cause, then re-run the script; answer n to the sections that"
    echo "already worked."
    exit 1
fi
echo "Done."
