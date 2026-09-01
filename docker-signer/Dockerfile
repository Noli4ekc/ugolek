FROM fedora:44

# Install dependencies
RUN dnf install -y \
    git gcc-c++ make pkgconf-pkg-config openssl-devel \
    python3-devel python3-pip wget curl \
    libusbmuxd libplist libimobiledevice \
    && dnf clean all

# Build zsign
RUN git clone https://github.com/zhlynn/zsign.git /tmp/zsign \
    && cd /tmp/zsign/build/linux && make \
    && cp /tmp/zsign/bin/zsign /usr/local/bin/zsign \
    && rm -rf /tmp/zsign

# Install Python tools
RUN pip3 install --no-cache-dir \
    pymobiledevice3 \
    requests \
    pycryptodome \
    pyelftools \
    unicorn \
    fs \
    certifi \
    urllib3 \
    typing-extensions

# Install Anisette.py (local anisette provider)
RUN git clone https://github.com/malmeloo/Anisette.py.git /opt/anisette \
    && cd /opt/anisette && pip3 install -e .

# Copy signing script
COPY sign.py /usr/local/bin/sign-ipa
RUN chmod +x /usr/local/bin/sign-ipa

WORKDIR /work
ENTRYPOINT ["sign-ipa"]
