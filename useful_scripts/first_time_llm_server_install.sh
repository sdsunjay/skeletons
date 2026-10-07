#!/usr/bin/env bash
#
# first_time_llm_server_install.sh
#
# First script to run on a fresh Ubuntu Server install (24.04 / 26.04 LTS) on
# the Intel NUC10i5FNH (i5-10210U, 4 cores / 8 threads, 64GB DDR4-2666) used as
# a headless, CPU-only LLM box.  Run once as root straight after the OS install:
#
#   sudo ./first_time_llm_server_install.sh
#
# No Ollama.  Inference runs on a C++ engine built from source for this exact
# CPU, served by its OpenAI-compatible llama-server under systemd:
#
#   llama.cpp     (default)  mainline.  Runs the MTP speculative-decoding head
#                            that both models below ship with (~1.2x on MoE,
#                            ~82% draft acceptance) and has the newest model
#                            support.
#   ik_llama.cpp  (bench)    fork with faster CPU matmul kernels, fused MoE
#                            (-fmoe) and run-time repacking (-rtr).  No MTP
#                            support, and it may not load a GGUF that carries
#                            an MTP head, so benchmark it with a plain GGUF.
#                            Built too; switching is a one-line edit in
#                            /etc/default/llama-server.
#
# What it does (every step is safe to re-run):
#   - full apt upgrade plus the handful of tools worth having on a headless box
#   - hardware sanity check: confirms both 32GB SODIMMs are seen and prints them
#   - optional Ubuntu Pro attach (interactive; skipped when there is no TTY)
#   - small swap file as a safety net only (models must fit in RAM)
#   - CPU-inference tuning: performance governor, transparent hugepages,
#     low swappiness, unlimited memlock for the server
#   - SSH + ufw (SSH from anywhere, the LLM API from the local subnet only)
#   - unattended security updates
#   - builds ik_llama.cpp and llama.cpp from source with native CPU flags
#   - downloads a first model (optional) and installs llama-server.service
#
# Tunables (environment variables):
#   ENGINE=mainline                mainline | ik  (which build the service runs)
#   BUILD_ENGINES="ik mainline"    which engines to build (both by default)
#   SWAP_SIZE_GB=4                 swap file size in GB
#   EXPOSE_LAN=1                   1 = listen on 0.0.0.0 and allow the LAN subnet
#   LLM_PORT=8080                  llama-server port
#   THREADS=<physical cores>       inference threads (4 on this NUC; never 8)
#   CTX=32768                      context window
#   DOWNLOAD_MODEL=1               0 = skip the ~23GB model download
#   MODEL_URL=<Ornith-1.5-35B-A3B Heretic APEX-I-Quality>   any direct GGUF URL
#
# Model:
#   Default is Ornith-1.5-35B-A3B (Qwen3.5-MoE architecture, ~3B active, MIT),
#   a coding/agent-tuned model that beats Qwen3.6 35B-A3B on SWE-bench and
#   tool-use benchmarks.  Same speed on this box as Qwen3.6.
#
#   The build chosen is SC117's Heretic abliteration.  Of every abliterated
#   Ornith on Hugging Face it is the only one that publishes its divergence
#   from the ORIGINAL model: first-token KL 0.0105 (Heretic MPOA rank-3 on
#   o_proj + down_proj, best of 80 Optuna trials), i.e. the least damage to
#   the model's intelligence.  Trade-off: 11/100 refusals remain, versus
#   2-3/100 for more aggressive builds that either report no divergence at
#   all (huihui-ai, alztrk) or only quant-vs-own-BF16 numbers (PocketAiHub,
#   gbuzhf), or that swap KL for a noisy MMLU delta (dealignai CRACK).
#   The file carries an MTP draft head (blk.40), which is why the service
#   defaults to mainline llama.cpp.
#
#   Second model of interest, kept as a commented-out URL below:
#   peculiar-ragdoll's Cyber-Tiel-Coder-35B-A3B (MTP build) - Ornith on
#   huihui-ai's abliteration, re-quantized with a security/code importance
#   matrix.  Zero refusals (0/84 HarmBench), the community's favourite, but
#   no divergence-from-original measurement and the card itself calls it
#   "slightly unstable" outside security work.  Use it for agentic coding
#   and security work where any refusal is unacceptable; sandbox it.
#
#   The stock Qwen3.6 35B-A3B URL is also kept, commented out, as the
#   general-purpose alternative.
#
# Notes for this hardware:
#   - Memory bandwidth (~40 GB/s) is the bottleneck, not core count.  MoE models
#     with ~3B active parameters (Ornith/Qwen 35B-A3B, Gemma 4 26B) are the
#     sweet spot and land at roughly 5-8 tok/s; dense 30B+ models will crawl.
#   - Threads = physical cores.  Hyperthreads slow memory-bound inference down.
#   - Set the fan/thermal profile to "Performance" in the NUC BIOS (F2) so
#     sustained all-core load does not throttle.  That cannot be done from here.
#   - Re-run /usr/local/bin/llama-update every few weeks: both engines are
#     rolling projects and CPU speed-ups land often.

set -euo pipefail

ENGINE="${ENGINE:-mainline}"
BUILD_ENGINES="${BUILD_ENGINES:-ik mainline}"
SWAP_SIZE_GB="${SWAP_SIZE_GB:-4}"
SWAPFILE="/swapfile"
EXPOSE_LAN="${EXPOSE_LAN:-1}"
LLM_PORT="${LLM_PORT:-8080}"
CTX="${CTX:-32768}"
DOWNLOAD_MODEL="${DOWNLOAD_MODEL:-1}"
# Ornith-1.5-35B-A3B, Heretic abliteration (SC117), APEX-I-Quality, 23.5 GB:
# attention Q6_K, shared experts Q8_0, routed experts ~Q4.  Lowest published
# divergence from the original model (first-token KL 0.0105).
MODEL_URL="${MODEL_URL:-https://huggingface.co/SC117/Ornith-1.5-35B-A3B-Heretic-MTP-APEX-GGUF/resolve/main/Ornith-1.5-35B-A3B-Heretic-MTP-APEX-I-Quality.gguf}"
# Same build, APEX-I-Compact (17.3 GB): ~25% fewer bytes per token, so faster:
# MODEL_URL="${MODEL_URL:-https://huggingface.co/SC117/Ornith-1.5-35B-A3B-Heretic-MTP-APEX-GGUF/resolve/main/Ornith-1.5-35B-A3B-Heretic-MTP-APEX-I-Compact.gguf}"
# Cyber-Tiel-Coder-35B-A3B, MTP build, UD-Q4_K_XL (22.7 GB): zero refusals,
# security/code-calibrated quant; see the header for the trade-offs.
# MODEL_URL="${MODEL_URL:-https://huggingface.co/peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-GGUF-MTP/resolve/main/Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf}"
# Stock Qwen3.6 35B-A3B (Unsloth UD-Q4_K_XL, 22.4 GB) - the general-purpose pick:
# MODEL_URL="${MODEL_URL:-https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/main/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf}"
MIN_EXPECTED_RAM_GB=60

LLM_USER="llama"
MODEL_DIR="/srv/models"
IK_DIR="/opt/ik_llama.cpp"
MAINLINE_DIR="/opt/llama.cpp"
IK_REPO="https://github.com/ikawrakow/ik_llama.cpp"
MAINLINE_REPO="https://github.com/ggml-org/llama.cpp"
CONF="/etc/default/llama-server"
WRAPPER="/usr/local/bin/llama-server-start"
UPDATER="/usr/local/bin/llama-update"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root: sudo $0"
    exit 1
fi

case "${ENGINE}" in
    ik|mainline) ;;
    *) echo "ENGINE must be 'ik' or 'mainline' (got '${ENGINE}')"; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive

echo "==> Updating Ubuntu"
apt-get update
apt-get full-upgrade -y

echo "==> Installing required packages"
apt-get install -y \
    build-essential \
    cmake \
    pkg-config \
    libcurl4-openssl-dev \
    curl \
    git \
    tmux \
    htop \
    jq \
    pciutils \
    dmidecode \
    nvme-cli \
    smartmontools \
    lm-sensors \
    zstd \
    openssh-server \
    unattended-upgrades \
    ufw

echo
echo "==> Hardware sanity check"
CPU_MODEL="$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo)"
PHYS_CORES="$(lscpu -p=CORE,SOCKET 2>/dev/null | grep -v '^#' | sort -u | wc -l)"
[[ "${PHYS_CORES}" -ge 1 ]] || PHYS_CORES="$(nproc)"
THREADS="${THREADS:-${PHYS_CORES}}"
RAM_GB="$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)"
echo "CPU:            ${CPU_MODEL}"
echo "Physical cores: ${PHYS_CORES}  (inference threads: ${THREADS})"
echo "RAM:            ${RAM_GB} GB"
echo "CPU flags:      $(grep -o -w -E 'avx2|avx512f|fma|f16c|amx_tile' /proc/cpuinfo | sort -u | tr '\n' ' ')"
echo
echo "Installed memory modules:"
dmidecode -t 17 \
    | grep -E '^\s*(Size|Locator|Speed|Configured Memory Speed|Part Number):' \
    | grep -v 'Bank Locator' \
    | sed 's/^\s*/    /' \
    || echo "    (dmidecode could not read DIMM info)"
echo
if [[ "${RAM_GB}" -lt "${MIN_EXPECTED_RAM_GB}" ]]; then
    echo "WARNING: only ${RAM_GB} GB of RAM detected; expected ~64 GB."
    echo "         Check that both SODIMMs are fully seated and that the BIOS sees them (F2)."
    echo
fi

echo "==> Ubuntu Pro"
if command -v pro >/dev/null 2>&1; then
    pro status
else
    echo "Ubuntu Pro client is not installed."
    echo "Install it with:"
    echo "  apt-get install -y ubuntu-advantage-tools"
fi

echo
ATTACH_PRO="n"
if [[ -t 0 ]]; then
    read -r -p "Attach this machine to Ubuntu Pro now? [y/N] " ATTACH_PRO
else
    echo "No TTY; skipping the Ubuntu Pro prompt (run 'sudo pro attach' later)."
fi

if [[ "${ATTACH_PRO,,}" == "y" ]]; then
    if ! command -v pro >/dev/null 2>&1; then
        apt-get install -y ubuntu-advantage-tools
    fi

    echo
    echo "Enter your Ubuntu Pro token when prompted."
    echo "The token will not be stored in this script."
    echo

    pro attach

    echo
    echo "Ubuntu Pro status:"
    pro status
fi

echo
echo "==> Configuring swap (${SWAP_SIZE_GB} GB safety net; models must fit in RAM)"
if ! swapon --show=NAME --noheadings | grep -qx "${SWAPFILE}"; then
    if [[ ! -f "${SWAPFILE}" ]]; then
        fallocate -l "${SWAP_SIZE_GB}G" "${SWAPFILE}"
        chmod 600 "${SWAPFILE}"
        mkswap "${SWAPFILE}"
    fi

    swapon "${SWAPFILE}"
fi

if ! grep -qE '^[[:space:]]*/swapfile[[:space:]]' /etc/fstab; then
    echo "${SWAPFILE} none swap sw 0 0" >> /etc/fstab
fi

echo "==> Configuring kernel memory behaviour"
cat >/etc/sysctl.d/99-llm.conf <<'EOF'
# Only swap as a last resort; if a model is paging the quant is too big.
vm.swappiness=10
EOF

sysctl --system >/dev/null

echo "==> Enabling transparent hugepages (a few percent on large models)"
cat >/etc/tmpfiles.d/transparent-hugepages.conf <<'EOF'
w /sys/kernel/mm/transparent_hugepage/enabled - - - - always
EOF
systemd-tmpfiles --create /etc/tmpfiles.d/transparent-hugepages.conf || true

echo "==> Pinning CPU governor to performance"
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

echo "==> Enabling SSH"
systemctl enable --now ssh

echo "==> Configuring firewall"
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH

LAN_CIDR=""
if [[ "${EXPOSE_LAN}" == "1" ]]; then
    DEFAULT_DEV="$(ip -4 route show default 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
    if [[ -n "${DEFAULT_DEV}" ]]; then
        LAN_CIDR="$(ip -4 route show dev "${DEFAULT_DEV}" scope link 2>/dev/null | awk '{print $1; exit}')"
    fi

    if [[ -n "${LAN_CIDR}" ]]; then
        echo "Allowing the LLM API (${LLM_PORT}/tcp) from ${LAN_CIDR} only"
        ufw allow from "${LAN_CIDR}" to any port "${LLM_PORT}" proto tcp comment 'llama-server API (LAN)'
    else
        echo "Could not detect the LAN subnet; the LLM API will stay on localhost only."
        EXPOSE_LAN=0
    fi
fi

ufw --force enable

echo "==> Configuring automatic updates"
systemctl enable --now unattended-upgrades

echo "==> Creating the ${LLM_USER} service user and ${MODEL_DIR}"
if ! id -u "${LLM_USER}" >/dev/null 2>&1; then
    useradd --system --home-dir "${MODEL_DIR}" --shell /usr/sbin/nologin "${LLM_USER}"
fi
mkdir -p "${MODEL_DIR}"
chown "${LLM_USER}:${LLM_USER}" "${MODEL_DIR}"

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

for eng in ${BUILD_ENGINES}; do
    case "${eng}" in
        ik)       build_engine "ik_llama.cpp" "${IK_REPO}" "${IK_DIR}" ;;
        mainline) build_engine "llama.cpp"    "${MAINLINE_REPO}" "${MAINLINE_DIR}" ;;
        *) echo "Unknown engine '${eng}' in BUILD_ENGINES; skipping" ;;
    esac
done

echo "==> Installing updater: ${UPDATER}"
cat >"${UPDATER}" <<EOF
#!/usr/bin/env bash
# Pull and rebuild the inference engines, then restart the server.
set -euo pipefail
[[ "\${EUID}" -eq 0 ]] || { echo "Run as root: sudo \$0"; exit 1; }
for dir in ${IK_DIR} ${MAINLINE_DIR}; do
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

MODEL_FILE="${MODEL_DIR}/$(basename "${MODEL_URL}")"
if [[ "${DOWNLOAD_MODEL}" == "1" ]]; then
    echo "==> Downloading model to ${MODEL_FILE} (resumable; ~23 GB for the default)"
    if sudo -u "${LLM_USER}" curl -fL --retry 5 --retry-delay 10 -C - -o "${MODEL_FILE}" "${MODEL_URL}"; then
        echo "Download complete"
    else
        echo "WARNING: model download failed. The service will not start until a GGUF exists."
        echo "         Put one in ${MODEL_DIR} and set MODEL= in ${CONF}, then:"
        echo "         sudo systemctl restart llama-server"
    fi
else
    echo "==> Skipping model download (DOWNLOAD_MODEL=0)"
fi

echo "==> Writing ${CONF}"
if [[ ! -f "${CONF}" ]]; then
    HOST_BIND="127.0.0.1"
    [[ "${EXPOSE_LAN}" == "1" ]] && HOST_BIND="0.0.0.0"
    cat >"${CONF}" <<EOF
# llama-server configuration.  Edit, then: sudo systemctl restart llama-server
#
# Which engine the service runs: mainline | ik
# (mainline runs the MTP head; ik has no MTP and may not load MTP GGUFs)
ENGINE=${ENGINE}

# Model (GGUF) to serve.  MoE with ~3B active parameters is the sweet spot here.
MODEL=${MODEL_FILE}

HOST=${HOST_BIND}
PORT=${LLM_PORT}

# Physical cores only.  Hyperthreads slow memory-bound inference down.
THREADS=${THREADS}

# Context window.  KV cache is q8_0, so 32K costs a few GB; 128K is fine on 64GB
# but generation slows as the cache fills.
CTX=${CTX}

# Ornith-1.5 recommended sampling (model card): thinking mode is on by default.
# For stock Qwen3.6 non-thinking chat use instead:
#   --temp 0.7 --top-p 0.8 --top-k 20 --min-p 0 --presence-penalty 1.5
SAMPLING_ARGS="--temp 0.6 --top-p 0.95 --top-k 20 --min-p 0"

# ik_llama.cpp only: fused MoE and run-time repacking to row-interleaved
# quants.  Both are pure-CPU wins; -rtr implies the model is read fully into
# RAM (no mmap), which is what --mlock wants anyway.
IK_ARGS="-fmoe -rtr"

# llama.cpp (mainline) only.  The default model ships an MTP draft head, so
# speculative decoding is on (try --spec-draft-n-max 1..6; remove both flags
# for a GGUF without an MTP head).
# To stop the model thinking by default:
#   --chat-template-kwargs {"enable_thinking":false}
# To cap thinking:
#   --reasoning-budget 4096
MAINLINE_ARGS="--spec-type draft-mtp --spec-draft-n-max 2"

# Anything else, passed to either engine verbatim.
EXTRA_ARGS=""
EOF
else
    echo "${CONF} already exists; leaving it alone"
fi

echo "==> Installing service wrapper: ${WRAPPER}"
cat >"${WRAPPER}" <<EOF
#!/usr/bin/env bash
# Starts llama-server from the engine selected in ${CONF}.
set -euo pipefail
# shellcheck disable=SC1091
source "${CONF}"

case "\${ENGINE}" in
    ik)
        BIN="${IK_DIR}/build/bin/llama-server"
        ENGINE_ARGS="-fa --no-mmap \${IK_ARGS:-}"
        ;;
    mainline)
        BIN="${MAINLINE_DIR}/build/bin/llama-server"
        ENGINE_ARGS="-fa on \${MAINLINE_ARGS:-}"
        ;;
    *)
        echo "ENGINE must be 'ik' or 'mainline' (got '\${ENGINE}')" >&2
        exit 1
        ;;
esac

[[ -x "\${BIN}" ]]  || { echo "\${BIN} not built; run ${UPDATER}" >&2; exit 1; }
[[ -f "\${MODEL}" ]] || { echo "Model not found: \${MODEL} (edit ${CONF})" >&2; exit 1; }

# shellcheck disable=SC2086
exec "\${BIN}" \\
    -m "\${MODEL}" \\
    --host "\${HOST}" --port "\${PORT}" \\
    -t "\${THREADS}" -tb "\${THREADS}" \\
    -c "\${CTX}" -np 1 \\
    --mlock \\
    -ctk q8_0 -ctv q8_0 \\
    --jinja \\
    \${SAMPLING_ARGS:-} \${ENGINE_ARGS} \${EXTRA_ARGS:-}
EOF
chmod 755 "${WRAPPER}"

echo "==> Installing llama-server.service"
cat >/etc/systemd/system/llama-server.service <<EOF
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
# Let the model weights be pinned in RAM (--mlock).
LimitMEMLOCK=infinity
LimitNOFILE=65536
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadOnlyPaths=${MODEL_DIR}

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable llama-server

if [[ -f "${MODEL_FILE}" ]]; then
    echo "==> Starting llama-server (loading ~23 GB into RAM takes a minute)"
    systemctl restart llama-server
    for _ in $(seq 1 120); do
        curl -fsS "http://127.0.0.1:${LLM_PORT}/health" >/dev/null 2>&1 && break
        sleep 2
    done
else
    echo "==> Not starting llama-server: no model at ${MODEL_FILE}"
fi

echo
echo "========================================"
echo " Installation complete"
echo "========================================"

echo
echo "Ubuntu Pro:"
if command -v pro >/dev/null 2>&1; then
    pro status
fi

echo
echo "Engines:"
for dir in "${IK_DIR}" "${MAINLINE_DIR}"; do
    if [[ -x "${dir}/build/bin/llama-server" ]]; then
        echo "  ${dir}  ($(git -C "${dir}" log -1 --format='%h %cd' --date=short))"
    fi
done
echo "  active: ${ENGINE}  (change ENGINE= in ${CONF})"

echo
echo "llama-server:"
systemctl --no-pager --full status llama-server || true

echo
echo "CPU governor:"
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "(no cpufreq)"

echo
echo "Transparent hugepages:"
cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || echo "(unavailable)"

echo
echo "Memory/swap:"
free -h
swapon --show

echo
echo "Listening sockets:"
ss -lntp | grep -E ":(22|${LLM_PORT})\b" || true

echo
echo "Firewall:"
ufw status verbose

if [[ -f /var/run/reboot-required ]]; then
    echo
    echo "A reboot is required to finish the kernel upgrade: sudo reboot"
fi

NUC_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo
echo "Try it:"
if [[ "${EXPOSE_LAN}" == "1" ]]; then
    echo "  Web UI:  http://${NUC_IP:-<nuc-ip>}:${LLM_PORT}/"
    echo "  API:     http://${NUC_IP:-<nuc-ip>}:${LLM_PORT}/v1/chat/completions  (OpenAI-compatible)"
else
    echo "  ssh -L ${LLM_PORT}:127.0.0.1:${LLM_PORT} ${NUC_IP:-<nuc-ip>}   then open http://localhost:${LLM_PORT}/"
fi
echo
echo "Benchmark (stop the service first; MTP speed shows in llama-server, not llama-bench):"
echo "  sudo systemctl stop llama-server"
echo "  ${MAINLINE_DIR}/build/bin/llama-bench -m ${MODEL_FILE} -t ${THREADS} -fa 1"
echo "  # ik_llama.cpp has no MTP support; point it at a GGUF WITHOUT an MTP head:"
echo "  ${IK_DIR}/build/bin/llama-bench -m <plain>.gguf -t ${THREADS} -fa 1 -fmoe 1 -rtr 1"
echo "  sudo systemctl start llama-server"
