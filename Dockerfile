FROM --platform=linux/amd64 python:3.11-slim

RUN apt-get update && apt-get --quiet --no-install-recommends --yes install \
    build-essential \
    curl \
    gettext-base \
    git \
    gnupg2 \
    less \
    make \
    openssh-client \
    procps \
    shellcheck \
    tar \
    unzip \
    wget \
    && rm -rf /var/lib/apt/lists/*

# put everything custom in here - simplifies some of the bash
WORKDIR /usr/local/bin

ADD https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 jq
RUN chmod +x jq

# Install Go
ADD https://dl.google.com/go/go1.24.3.linux-amd64.tar.gz /tmp/go1.24.3.linux-amd64.tar.gz
RUN echo "3333f6ea53afa971e9078895eaa4ac7204a8c6b5c68c10e6bc9a33e8e391bdd8 /tmp/go1.24.3.linux-amd64.tar.gz" | sha256sum -c && \
    rm -rf /usr/local/go && \
    tar -C /usr/local -xzf /tmp/go1.24.3.linux-amd64.tar.gz
ENV GOROOT=/usr/local/go
ENV PATH=$PATH:$GOROOT/bin

# gcloud
# SHA256 checksum for latest version is found on https://cloud.google.com/sdk/docs/downloads-versioned-archives#installation_instructions
ENV PATH=$PATH:/usr/local/google-cloud-sdk/bin
ARG GCLOUD_VERSION=525.0.0
ADD https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-${GCLOUD_VERSION}-linux-x86_64.tar.gz /tmp/google-cloud-sdk.tar.gz
RUN tar -C /usr/local --keep-old-files -xz -f /tmp/google-cloud-sdk.tar.gz && \
    gcloud config set --installation component_manager/disable_update_check true && \
    gcloud config set --installation core/disable_usage_reporting true && \
    gcloud components install beta --quiet && \
    gcloud components install alpha --quiet && \
    gcloud components install gke-gcloud-auth-plugin --quiet && \
    rm -f /tmp/google-cloud-sdk.tar.gz && \
    rm -rf /usr/local/google-cloud-sdk/.install/.backup && \
    find /usr/local/google-cloud-sdk -type d -name __pycache__ -exec rm -r {} \+

# Setup Kubernetes CLI - NB: stay within +/-1 of server version
ARG KUBECTL_VERSION=1.33.1
ADD https://dl.k8s.io/v${KUBECTL_VERSION}/kubernetes-client-linux-amd64.tar.gz kubernetes-client.tar.gz
RUN tar -xz -f kubernetes-client.tar.gz --strip-components=3 kubernetes/client/bin/kubectl && rm kubernetes-client.tar.gz
ENV USE_GKE_GCLOUD_AUTH_PLUGIN=True

# kustomize
ARG KUSTOMIZE_VERSION=5.4.3
ADD "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" kustomize.tar.gz
RUN tar -xz -f kustomize.tar.gz && rm kustomize.tar.gz

# Setup gcrane
ARG GO_CONTAINERREGISTRY_VERSION=v0.16.1
ADD https://github.com/google/go-containerregistry/releases/download/${GO_CONTAINERREGISTRY_VERSION}/go-containerregistry_Linux_x86_64.tar.gz go-containerregistry.tar.gz
RUN tar -xz -f go-containerregistry.tar.gz gcrane && rm go-containerregistry.tar.gz

# pipenv and yq
RUN pip install --upgrade pip && pip --quiet --no-cache-dir install pipenv yamllint yq

# tfenv
ENV TFENV_AUTO_INSTALL=true
RUN git clone https://github.com/tfutils/tfenv.git ~/.tfenv \
    && ln -s ~/.tfenv/bin/* /usr/local/bin \
    && mkdir ~/.tfenv/versions

# docker
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(awk -F '=' '/VERSION_CODENAME=/ {print $2}' /etc/os-release) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update && apt-get --quiet --no-install-recommends --yes install docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*
RUN gcloud auth configure-docker

# pyenv
RUN git clone https://github.com/pyenv/pyenv.git ~/.pyenv && \
    echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc && \
    echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc && \
    echo 'eval "$(pyenv init -)"' >> ~/.bashrc

# uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# hugo
ARG HUGO_VERSION=0.147.3
ADD https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_Linux-64bit.tar.gz hugo.tar.gz
RUN tar zxf hugo.tar.gz && rm hugo.tar.gz

# snyk
COPY --from=snyk/snyk:python-3.11 /usr/local/bin/snyk /usr/local/bin/snyk

# gitleaks
ARG GITLEAK_VERSION=8.26.0
ADD https://github.com/zricethezav/gitleaks/releases/download/v${GITLEAK_VERSION}/gitleaks_${GITLEAK_VERSION}_linux_x64.tar.gz gitleaks_${GITLEAK_VERSION}_linux_x64.tar.gz
RUN tar -xz -f gitleaks_${GITLEAK_VERSION}_linux_x64.tar.gz && chmod +x gitleaks

CMD ["/bin/bash"]
