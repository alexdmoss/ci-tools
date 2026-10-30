ARG PLATFORM
# uv: ghcr.io gives Renovate no release timestamps, so the version is tracked via
# GitHub releases (for the 3-day age gate) and the image is pulled by that tag
# renovate: datasource=github-releases depName=astral-sh/uv
ARG UV_VERSION=0.13.5

FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

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

# Go: match the newest go.mod directive in use, so Go jobs don't download a toolchain first
# renovate: datasource=golang-version depName=go
ARG GO_VERSION=1.27.3
ADD https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz /tmp/go-linux-amd64.tar.gz
RUN rm -rf /usr/local/go && \
    tar -C /usr/local -xzf /tmp/go-linux-amd64.tar.gz && \
    rm /tmp/go-linux-amd64.tar.gz
ENV GOROOT=/usr/local/go
ENV PATH=$PATH:$GOROOT/bin

# gcloud (the largest layer). GCLOUD_VERSION is also the image tag. Tracked via
# the Docker Hub image, which carries the same version numbers plus release timestamps
ENV PATH=$PATH:/usr/local/google-cloud-sdk/bin
# renovate: datasource=docker depName=google/cloud-sdk
ARG GCLOUD_VERSION=590.0.0
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
# renovate: datasource=pypi depName=semgrep
ARG SEMGREP_VERSION=1.182.1
RUN python3 -m pip install --no-cache-dir semgrep==${SEMGREP_VERSION} && \
    rm -rf ~/.cache/pip

# Small single-binary tools from here down

# renovate: datasource=github-releases depName=jqlang/jq versioning=regex:^jq-(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$
ARG JQ_VERSION=jq-1.8.2
ADD https://github.com/jqlang/jq/releases/download/${JQ_VERSION}/jq-linux-amd64 jq
RUN chmod +x jq

# install docker credential helper for GCP (pinned: with caching, @latest would never update)
# renovate: datasource=go depName=github.com/GoogleCloudPlatform/docker-credential-gcr/v2
ARG DOCKER_CREDENTIAL_GCR_VERSION=v2.2.1
RUN go install github.com/GoogleCloudPlatform/docker-credential-gcr/v2@${DOCKER_CREDENTIAL_GCR_VERSION} && \
    mv $HOME/go/bin/docker-credential-gcr /usr/local/bin/docker-credential-gcr && \
    go clean -modcache

# Setup Kubernetes CLI - NB: stay within +/-1 of server version (GKE 1.36 on 29 Oct 2026)
# renovate: datasource=github-releases depName=kubernetes/kubernetes
ARG KUBECTL_VERSION=v1.37.1
ADD https://dl.k8s.io/${KUBECTL_VERSION}/kubernetes-client-linux-amd64.tar.gz kubernetes-client.tar.gz
RUN tar -xz -f kubernetes-client.tar.gz --strip-components=3 kubernetes/client/bin/kubectl && rm kubernetes-client.tar.gz
ENV USE_GKE_GCLOUD_AUTH_PLUGIN=True

# kustomize (Go module versions: the GitHub tags are kustomize/vX, which the comment convention can't strip)
# renovate: datasource=go depName=sigs.k8s.io/kustomize/kustomize/v5
ARG KUSTOMIZE_VERSION=v5.8.3
ADD "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" kustomize.tar.gz
RUN tar -xz -f kustomize.tar.gz && rm kustomize.tar.gz

# helm
# renovate: datasource=github-releases depName=helm/helm
ARG HELM_VERSION=v4.3.1
ADD https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz helm.tar.gz
RUN tar -xz -f helm.tar.gz linux-amd64/helm && mv linux-amd64/helm /usr/local/bin/helm && rm -rf helm.tar.gz linux-amd64

# Setup gcrane
# renovate: datasource=github-releases depName=google/go-containerregistry
ARG GO_CONTAINERREGISTRY_VERSION=v0.22.1
ADD https://github.com/google/go-containerregistry/releases/download/${GO_CONTAINERREGISTRY_VERSION}/go-containerregistry_Linux_x86_64.tar.gz go-containerregistry.tar.gz
RUN tar -xz -f go-containerregistry.tar.gz gcrane && rm go-containerregistry.tar.gz

# hugo. NB: held at 0.153 until alexos.dev has a local gist shortcode (Hugo >= 0.156 dropped the built-in one)
# renovate: datasource=github-releases depName=gohugoio/hugo
ARG HUGO_VERSION=v0.153.0
ADD https://github.com/gohugoio/hugo/releases/download/${HUGO_VERSION}/hugo_extended_${HUGO_VERSION#v}_Linux-64bit.tar.gz hugo.tar.gz
RUN tar zxf hugo.tar.gz hugo && rm hugo.tar.gz LICENSE README.md 2>/dev/null || true

# gitleaks
# renovate: datasource=github-releases depName=gitleaks/gitleaks
ARG GITLEAKS_VERSION=v8.30.1
ADD https://github.com/gitleaks/gitleaks/releases/download/${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION#v}_linux_x64.tar.gz gitleaks.tar.gz
RUN tar -xz -f gitleaks.tar.gz gitleaks && \
    chmod +x gitleaks && \
    rm gitleaks.tar.gz

# kubeconform (alexos-cli reference/scripts/validate-manifests.sh)
# renovate: datasource=github-releases depName=yannh/kubeconform
ARG KUBECONFORM_VERSION=v0.8.0
ADD https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz kubeconform.tar.gz
RUN tar -xz -f kubeconform.tar.gz kubeconform && rm kubeconform.tar.gz

# Install buildkit (for alexos-cli build); the daemonless script comes from the same tag
# renovate: datasource=github-releases depName=moby/buildkit
ARG BK_VERSION=v0.34.1
RUN wget -q https://github.com/moby/buildkit/releases/download/${BK_VERSION}/buildkit-${BK_VERSION}.linux-amd64.tar.gz -O /tmp/buildkit.tgz && \
    tar -xzf /tmp/buildkit.tgz -C /tmp && mv /tmp/bin/* /usr/local/bin/ && rm -rf /tmp/buildkit.tgz /tmp/bin && \
    wget -q https://raw.githubusercontent.com/moby/buildkit/${BK_VERSION}/examples/buildctl-daemonless/buildctl-daemonless.sh -O /usr/local/bin/buildctl-daemonless.sh && \
    chmod +x /usr/local/bin/buildctl-daemonless.sh

# uv (version at the top; the plain image holds just the two binaries)
COPY --from=uv /uv /uvx /usr/local/bin/

# kics
COPY --from=checkmarx/kics:v2.2.0@sha256:ef29dbac14b046b1ef65f3280646112e927a61781c5f01bca1aeb723e0b96003 /app/bin/kics /usr/local/bin/kics

# trivy
COPY --from=aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c /usr/local/bin/trivy /usr/local/bin/trivy

# Install alexos-cli (last: the latest release is downloaded on every pipeline)
ADD bin/alexos-cli /usr/local/bin/alexos-cli
RUN chmod +x /usr/local/bin/alexos-cli

# Fail the build if any tool is missing or won't run (a bad download URL after a bump)
RUN set -e; for cmd in "go version" "gcloud --version" "semgrep --version" "jq --version" \
      "docker-credential-gcr version" "kubectl version --client" "kustomize version" "helm version" \
      "gcrane version" "hugo version" "gitleaks version" "kubeconform -v" "buildctl --version" \
      "uv --version" "kics version" "trivy --version" "docker --version" "yq --version" "pipenv --version"; do \
      echo "-> ${cmd}"; ${cmd} > /tmp/out 2>&1 || { cat /tmp/out; exit 1; }; head -1 /tmp/out; \
    done; rm /tmp/out

CMD ["/bin/bash"]
