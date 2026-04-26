# ============================================================================
# OpenARC From Scratch - Ubuntu Base + Manual Intel Setup
# NOTE: 
#       Newer GPUs require using the `libze` packages instead of `level-zero`.
#       For Battlemage or newer, you should use `Battlemage.Dockerfile` instead.
# ============================================================================
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# ============================================================================
# System Dependencies
# ============================================================================
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    git \
    gpg \
    gpg-agent \
    wget \
    python3 \
    python3-venv \
    python3-dev \
    python3-pip && \
    update-alternatives --install /usr/bin/python python /usr/bin/python3 1 && \
    rm -rf /var/lib/apt/lists/*

# ============================================================================
# Intel GPU Drivers
# ============================================================================
RUN wget -qO - https://repositories.intel.com/gpu/intel-graphics.key | \
    gpg --dearmor --output /usr/share/keyrings/intel-graphics.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu noble client" | \
    tee /etc/apt/sources.list.d/intel-gpu-noble.list && \
    apt-get update && apt-get install -y \
    intel-opencl-icd \
    intel-level-zero-gpu \
    level-zero \
    level-zero-dev && \
    rm -rf /var/lib/apt/lists/*

# ============================================================================
# Intel NPU Driver
# ============================================================================
RUN apt-get update && apt-get install -y \
    cmake \
    build-essential \
    libudev-dev && \
    git clone https://github.com/intel/linux-npu-driver.git /tmp/npu-driver && \
    cd /tmp/npu-driver && \
    git submodule update --init --recursive && \
    mkdir build && cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local .. && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    cd / && rm -rf /tmp/npu-driver /var/lib/apt/lists/*

# ============================================================================
# Install uv package manager
# ============================================================================
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

# ============================================================================
# Clone and setup OpenArc
# ============================================================================
WORKDIR /app
RUN git clone https://github.com/SearchSavior/OpenArc.git . && \
    echo "OpenARC version: $(git describe --tags --always)"

# ============================================================================
# Install Python dependencies with uv
# ============================================================================
RUN uv sync && \
    uv pip install "optimum-intel[openvino] @ git+https://github.com/huggingface/optimum-intel" && \
    uv pip install --pre -U openvino-genai openvino-tokenizers \
        --extra-index-url https://storage.openvinotoolkit.org/simple/wheels/nightly

# Add venv to PATH so openarc command works
ENV PATH="/app/.venv/bin:$PATH"

# ============================================================================
# Runtime Configuration
# ============================================================================
ENV NEOReadDebugKeys=1 \
    OverrideGpuAddressSpace=48 \
    EnableImplicitScaling=1 \
    OPENARC_API_KEY=key \
    OPENARC_AUTOLOAD_MODEL=""

# Create persistent config directory and symlink
RUN mkdir -p /persist && \
    ln -sf /persist/openarc_config.json /app/openarc_config.json

# ============================================================================
# Build Info Logging
# ============================================================================
RUN echo "=== Build Information ===" > /app/BUILD_INFO.txt && \
    echo "Build Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")" >> /app/BUILD_INFO.txt && \
    echo "OpenARC Version: $(git describe --tags --always)" >> /app/BUILD_INFO.txt && \
    echo "" >> /app/BUILD_INFO.txt && \
    echo "=== Intel Package Versions ===" >> /app/BUILD_INFO.txt && \
    uv pip list | grep -E "(openvino|optimum|torch)" >> /app/BUILD_INFO.txt || true && \
    echo "" >> /app/BUILD_INFO.txt && \
    echo "=== System Package Versions ===" >> /app/BUILD_INFO.txt && \
    dpkg -l | grep -E "intel-opencl|level-zero" | awk '{print $2 " " $3}' >> /app/BUILD_INFO.txt || true

# ============================================================================
# Startup Script
# ============================================================================
# Copy the script from your host to the container
COPY entrypoint.sh /usr/local/bin/start-openarc.sh

# Ensure it has execution permissions
RUN chmod +x /usr/local/bin/start-openarc.sh

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD curl -f -H "Authorization: Bearer ${OPENARC_API_KEY}" http://localhost:8000/v1/models || exit 1

CMD ["/usr/local/bin/start-openarc.sh"]
