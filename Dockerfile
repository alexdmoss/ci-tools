ARG PLATFORM
FROM --platform=${PLATFORM:-linux/amd64} python:3.13-slim@sha256:d98cc29d3266e535dd9da1099688d9cb3ca4753813571e071763d17725460962

# Layers are ordered from least to most frequently changing, so a version bump
# only rebuilds the layers after it and everything above comes from the cache.
# Unpinned installs (apt, pip, git clones) refresh when the base digest changes.

# apt packages, including the buildkit dependencies (for alexos-cli build)
RUN apt-get update && apt-get --quiet --no-install-recommends --yes install \
    build-essential \
    curl \
    fuse-overlayfs \
    gettext-base \
    git \
    gnupg2 \
    less \
    make \
    openssh-client \
    procps \
    rootlesskit \
    shellcheck \
    slirp4netns \
    tar \
    uidmap \
    unzip \
    wget \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# docker
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(awk -F '=' '/VERSION_CODENAME=/ {print $2}' /etc/os-release) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update && apt-get --quiet --no-install-recommends --yes install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# pipenv and yq
RUN pip install --upgrade pip && pip --quiet --no-cache-dir install pipenv yamllint yq && \
    rm -rf ~/.cache/pip

# pyenv
RUN git clone --depth 1 https://github.com/pyenv/pyenv.git ~/.pyenv && \
    rm -rf ~/.pyenv/.git && \
    echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc && \
    echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc && \
    echo 'eval "$(pyenv init -)"' >> ~/.bashrc

# tfenv
ENV TFENV_AUTO_INSTALL=true
RUN git clone --depth 1 https://github.com/tfutils/tfenv.git ~/.tfenv \
    && ln -s ~/.tfenv/bin/* /usr/local/bin \
    && mkdir ~/.tfenv/versions \
    && rm -rf ~/.tfenv/.git

# put everything custom in here - simplifies some of the bash
WORKDIR /usr/local/bin

# Install Go
ADD https://dl.google.com/go/go1.25.4.linux-amd64.tar.gz /tmp/go-linux-amd64.tar.gz
RUN rm -rf /usr/local/go && \
    tar -C /usr/local -xzf /tmp/go-linux-amd64.tar.gz && \
    rm /tmp/go-linux-amd64.tar.gz
ENV GOROOT=/usr/local/go
ENV PATH=$PATH:$GOROOT/bin

# gcloud (the largest layer). GCLOUD_VERSION is also the image tag.
ENV PATH=$PATH:/usr/local/google-cloud-sdk/bin
ARG GCLOUD_VERSION=564.0.0
ADD https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-${GCLOUD_VERSION}-linux-x86_64.tar.gz /tmp/google-cloud-sdk.tar.gz
RUN tar -C /usr/local --keep-old-files -xz -f /tmp/google-cloud-sdk.tar.gz && \
    gcloud config set --installation component_manager/disable_update_check true && \
    gcloud config set --installation core/disable_usage_reporting true && \
    gcloud components install beta alpha gke-gcloud-auth-plugin --quiet && \
    rm -f /tmp/google-cloud-sdk.tar.gz && \
    rm -rf /usr/local/google-cloud-sdk/.install/.backup && \
    find /usr/local/google-cloud-sdk -type d -name __pycache__ -exec rm -r {} \+
RUN gcloud auth configure-docker

# semgrep
RUN python3 -m pip install --no-cache-dir semgrep==1.159.0 && \
    rm -rf ~/.cache/pip

# Small single-binary tools from here down

ADD https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 jq
RUN chmod +x jq

# install docker credential helper for GCP (pinned: with caching, @latest would never update)
ARG DOCKER_CREDENTIAL_GCR_VERSION=v2.2.1
RUN go install github.com/GoogleCloudPlatform/docker-credential-gcr/v2@${DOCKER_CREDENTIAL_GCR_VERSION} && \
    mv $HOME/go/bin/docker-credential-gcr /usr/local/bin/docker-credential-gcr && \
    go clean -modcache

# Setup Kubernetes CLI - NB: stay within +/-1 of server version
ARG KUBECTL_VERSION=1.35.3
ADD https://dl.k8s.io/v${KUBECTL_VERSION}/kubernetes-client-linux-amd64.tar.gz kubernetes-client.tar.gz
RUN tar -xz -f kubernetes-client.tar.gz --strip-components=3 kubernetes/client/bin/kubectl && rm kubernetes-client.tar.gz
ENV USE_GKE_GCLOUD_AUTH_PLUGIN=True

# kustomize
ARG KUSTOMIZE_VERSION=5.7.1
ADD "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" kustomize.tar.gz
RUN tar -xz -f kustomize.tar.gz && rm kustomize.tar.gz

# helm
ARG HELM_VERSION=4.2.3
ADD https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz helm.tar.gz
RUN tar -xz -f helm.tar.gz linux-amd64/helm && mv linux-amd64/helm /usr/local/bin/helm && rm -rf helm.tar.gz linux-amd64

# Setup gcrane
ARG GO_CONTAINERREGISTRY_VERSION=v0.21.3
ADD https://github.com/google/go-containerregistry/releases/download/${GO_CONTAINERREGISTRY_VERSION}/go-containerregistry_Linux_x86_64.tar.gz go-containerregistry.tar.gz
RUN tar -xz -f go-containerregistry.tar.gz gcrane && rm go-containerregistry.tar.gz

# hugo
ARG HUGO_VERSION=0.153.0
ADD https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_Linux-64bit.tar.gz hugo.tar.gz
RUN tar zxf hugo.tar.gz hugo && rm hugo.tar.gz LICENSE README.md 2>/dev/null || true

# gitleaks
ARG GITLEAK_VERSION=8.30.1
ADD https://github.com/zricethezav/gitleaks/releases/download/v${GITLEAK_VERSION}/gitleaks_${GITLEAK_VERSION}_linux_x64.tar.gz gitleaks_${GITLEAK_VERSION}_linux_x64.tar.gz
RUN tar -xz -f gitleaks_${GITLEAK_VERSION}_linux_x64.tar.gz gitleaks && \
    chmod +x gitleaks && \
    rm gitleaks_${GITLEAK_VERSION}_linux_x64.tar.gz

# Install buildkit (for alexos-cli build)
ARG BK_VERSION="v0.29.0"
RUN wget -q https://github.com/moby/buildkit/releases/download/${BK_VERSION}/buildkit-${BK_VERSION}.linux-amd64.tar.gz -O /tmp/buildkit.tgz && \
    tar -xzf /tmp/buildkit.tgz -C /tmp && mv /tmp/bin/* /usr/local/bin/ && \
    wget -q https://raw.githubusercontent.com/moby/buildkit/master/examples/buildctl-daemonless/buildctl-daemonless.sh -O /usr/local/bin/buildctl-daemonless.sh && \
chmod +x /usr/local/bin/buildctl-daemonless.sh

# uv
COPY --from=ghcr.io/astral-sh/uv:0.11.7-python3.13-trixie@sha256:929560df6a6231d0509739319bc214aaa1e78838ce1f779b1faeb877c23a50d8 /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/

# kics
COPY --from=checkmarx/kics:v2.2.0@sha256:ef29dbac14b046b1ef65f3280646112e927a61781c5f01bca1aeb723e0b96003 /app/bin/kics /usr/local/bin/kics

# trivy
COPY --from=aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c /usr/local/bin/trivy /usr/local/bin/trivy

# Install alexos-cli (last: the latest release is downloaded on every pipeline)
ADD bin/alexos-cli /usr/local/bin/alexos-cli
RUN chmod +x /usr/local/bin/alexos-cli

CMD ["/bin/bash"]
