FROM python:3.9-slim

RUN apt-get update && \
  apt-get --quiet --no-install-recommends --yes install \
  curl \
  gettext-base \
  git \
  gnupg2 \
  less \
  openssh-client \
  shellcheck \
  unzip \
  make \
  wget && \
  rm -rf /var/lib/apt/lists/*

# jq
RUN cd /usr/local/bin && \
  wget --no-verbose -O jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 && \
  chmod +x jq

ARG PIPENV_VERSION=2023.3.20
ARG YAMLLINT_VERSION=1.30.0
ARG YQ_VERSION=3.1.1
RUN pip install --upgrade pip
RUN pip --quiet --no-cache-dir install \
  pipenv==${PIPENV_VERSION} \
  yamllint==${YAMLLINT_VERSION} \
  yq==${YQ_VERSION}

# gcloud
ENV PATH=$PATH:/usr/local/google-cloud-sdk/bin
ARG GCLOUD_VERSION=429.0.0
RUN wget --no-verbose -O /tmp/google-cloud-sdk.tar.gz https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-${GCLOUD_VERSION}-linux-x86_64.tar.gz && \
  tar -C /usr/local --keep-old-files -xz -f /tmp/google-cloud-sdk.tar.gz && \
  gcloud config set --installation component_manager/disable_update_check true && \
  gcloud config set --installation core/disable_usage_reporting true && \
  gcloud components install beta --quiet && \
  gcloud components install gke-gcloud-auth-plugin --quiet && \
  rm -f /tmp/google-cloud-sdk.tar.gz && \
  rm -rf /usr/local/google-cloud-sdk/.install/.backup && \
  find /usr/local/google-cloud-sdk -type d -name __pycache__ -exec rm -r {} \+

# kubectl
# checksum from changelog: https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.25.md#client-binaries
ARG KUBECTL_VERSION=1.25.8
ARG KUBECTL_SHA512="e2179fba92c3692ef44377276e109f87c12a7166b1fd93ca826527406a6698f551afbf702d67d9469e2512ef5137a71c5ad809fc0f384dfbf7db53ca83dc3033"
RUN wget --no-verbose -O /tmp/kubernetes-client.tar.gz https://dl.k8s.io/v${KUBECTL_VERSION}/kubernetes-client-linux-amd64.tar.gz && \
  echo "${KUBECTL_SHA512} /tmp/kubernetes-client.tar.gz" | sha512sum -c && \
  tar -C /usr/local/bin -xz -f /tmp/kubernetes-client.tar.gz --strip-components=3 kubernetes/client/bin/kubectl && \
  rm /tmp/kubernetes-client.tar.gz

# kustomize
# checksum from github release: https://github.com/kubernetes-sigs/kustomize/releases/tag/kustomize%2Fv4.1.2
ARG KUSTOMIZE_VERSION=4.1.2
ARG KUSTOMIZE_SHA256="4efb7d0dadba7fab5191c680fcb342c2b6f252f230019cf9cffd5e4b0cad1d12"
RUN cd /usr/local/bin && \
  wget --no-verbose -O /tmp/kustomize.tar.gz "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" && \
  echo "${KUSTOMIZE_SHA256} /tmp/kustomize.tar.gz" | sha256sum -c && \
  tar -C /usr/local/bin -xz -f /tmp/kustomize.tar.gz && \
  rm /tmp/kustomize.tar.gz

# terraform via tfenv
ENV TFENV_AUTO_INSTALL=true
RUN git clone https://github.com/tfutils/tfenv.git ~/.tfenv \
    && ln -s ~/.tfenv/bin/* /usr/local/bin \
    && mkdir ~/.tfenv/versions

CMD ["/bin/bash"]
