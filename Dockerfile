FROM --platform=linux/amd64 python:3.11-slim

RUN apt-get update \
  && apt-get --quiet --no-install-recommends --yes install \
  curl \
  gettext-base \
  git \
  gnupg2 \
  less \
  make \
  openssh-client \
  shellcheck \
  unzip \
  wget \
  procps

RUN cd /usr/local/bin && \
  wget --no-verbose -O jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 && \
  chmod +x jq

# gcloud
# SHA256 checksum for latest version is found on https://cloud.google.com/sdk/docs/downloads-versioned-archives#installation_instructions
ENV PATH=$PATH:/usr/local/google-cloud-sdk/bin
ARG GCLOUD_VERSION=460.0.0
RUN wget --no-verbose -O /tmp/google-cloud-sdk.tar.gz https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-${GCLOUD_VERSION}-linux-x86_64.tar.gz && \
  tar -C /usr/local --keep-old-files -xz -f /tmp/google-cloud-sdk.tar.gz && \
  gcloud config set --installation component_manager/disable_update_check true && \
  gcloud config set --installation core/disable_usage_reporting true && \
  gcloud components install beta --quiet && \
  gcloud components install gke-gcloud-auth-plugin --quiet && \
  rm -f /tmp/google-cloud-sdk.tar.gz && \
  rm -rf /usr/local/google-cloud-sdk/.install/.backup && \
  find /usr/local/google-cloud-sdk -type d -name __pycache__ -exec rm -r {} \+

# Setup Kubernetes CLI - NB: stay within +/-1 of server version
# SHA512 checksum is from the Kubernetes changelog e.g. https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.27.md#client-binaries
ARG KUBECTL_VERSION=1.27.8
ARG KUBECTL_SHA512="d52faf06b8b5499564ddb06836f76e3a330f8f21e0fe7ffee8e6f36a95c40bbed7ef8db8aefd48f867b4d63fe02f1f562a146b71f669e960f1c6ed18820f36dd"
RUN wget --no-verbose -O /tmp/kubernetes-client.tar.gz https://dl.k8s.io/v${KUBECTL_VERSION}/kubernetes-client-linux-amd64.tar.gz && \
  echo "${KUBECTL_SHA512} /tmp/kubernetes-client.tar.gz" | sha512sum -c && \
  tar -C /usr/local/bin -xz -f /tmp/kubernetes-client.tar.gz --strip-components=3 kubernetes/client/bin/kubectl && \
  rm /tmp/kubernetes-client.tar.gz
ENV USE_GKE_GCLOUD_AUTH_PLUGIN=True

# kustomize
# checksum from github release: https://github.com/kubernetes-sigs/kustomize/releases/tag/kustomize%2Fv4.1.2
ARG KUSTOMIZE_VERSION=5.2.1
ARG KUSTOMIZE_SHA256="88346543206b889f9287c0b92c70708040ecd5aad54dd33019c4d6579cd24de8"
RUN cd /usr/local/bin && \
  wget --no-verbose -O /tmp/kustomize.tar.gz "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" && \
  echo "${KUSTOMIZE_SHA256} /tmp/kustomize.tar.gz" | sha256sum -c && \
  tar -C /usr/local/bin -xz -f /tmp/kustomize.tar.gz && \
  rm /tmp/kustomize.tar.gz

# Setup gcrane
# SHA256 checksum is from the checksums.txt file in GitHub release assets https://github.com/google/go-containerregistry/releases
ARG GO_CONTAINERREGISTRY_VERSION=v0.16.1
ARG GO_CONTAINERREGISTRY_SHA256="115dc84d14c5adc89c16e3fa297e94f06a9ec492bb1dc730da624850b77c9be2"
RUN wget --no-verbose -O /tmp/go-containerregistry.tar.gz https://github.com/google/go-containerregistry/releases/download/${GO_CONTAINERREGISTRY_VERSION}/go-containerregistry_Linux_x86_64.tar.gz && \
  echo "${GO_CONTAINERREGISTRY_SHA256} /tmp/go-containerregistry.tar.gz" | sha256sum -c && \
  tar -C /usr/local/bin -xz -f /tmp/go-containerregistry.tar.gz gcrane && \
  rm /tmp/go-containerregistry.tar.gz

ARG PIPENV_VERSION=2023.8.20
ARG YAMLLINT_VERSION=1.32.0
ARG YQ_VERSION=3.2.2
RUN pip install --upgrade pip
RUN pip --quiet --no-cache-dir install \
  pipenv==${PIPENV_VERSION} \
  yamllint==${YAMLLINT_VERSION} \
  yq==${YQ_VERSION}

# tfenv
ENV TFENV_AUTO_INSTALL=true
RUN git clone https://github.com/tfutils/tfenv.git ~/.tfenv \
    && ln -s ~/.tfenv/bin/* /usr/local/bin \
    && mkdir ~/.tfenv/versions

# docker
RUN apt-get update \
      && apt-get --quiet --no-install-recommends --yes install \
      curl \
      && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
      && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(awk -F '=' '/VERSION_CODENAME=/ {print $2}' /etc/os-release) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
      && apt-get update && apt-get --quiet --no-install-recommends --yes install docker-ce-cli \
      && rm -rf /var/lib/apt/lists/*
RUN gcloud auth configure-docker

# pyenv
RUN git clone https://github.com/pyenv/pyenv.git ~/.pyenv && \
    echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc && \
    echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc && \
    echo 'eval "$(pyenv init -)"' >> ~/.bashrc

CMD ["/bin/bash"]
