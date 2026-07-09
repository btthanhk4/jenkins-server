###############################################################################
# Jenkins DevOps Enterprise Image
# Base: Jenkins LTS (JDK21) + full DevOps toolchain
###############################################################################
FROM jenkins/jenkins:lts-jdk21

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# OCI metadata
LABEL org.opencontainers.image.title="jenkins-devops" \
      org.opencontainers.image.description="Jenkins LTS all-in-one with Docker/kubectl/Helm/Maven/Node/Terraform/Vault/Sonar/Trivy/AWS/Ansible" \
      org.opencontainers.image.source="https://github.com/btthanhk4/jenkins-server"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

WORKDIR /tmp

###############################################################################
# Base packages
###############################################################################
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash bash-completion ca-certificates curl wget unzip zip \
        git git-lfs vim nano jq tree rsync gettext-base make \
        openssh-client sshpass dnsutils iputils-ping net-tools telnet \
        python3 python3-pip python3-venv build-essential \
        gnupg lsb-release locales tzdata && \
    locale-gen en_US.UTF-8 || true && \
    git lfs install && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

###############################################################################
# Docker CLI (+ buildx + compose plugin)
###############################################################################
RUN . /etc/os-release && \
    install -m0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin docker-compose-plugin && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

###############################################################################
# kubectl (arch-aware)
###############################################################################
RUN ARCH=$(dpkg --print-architecture) && \
    curl -fsSL "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl" \
      -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl && kubectl version --client=true

###############################################################################
# Helm
###############################################################################
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash && \
    helm version

###############################################################################
# yq (YAML processor, arch-aware)
###############################################################################
RUN ARCH=$(dpkg --print-architecture) && \
    curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}" \
      -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

###############################################################################
# NodeJS 22 (+ pnpm)
###############################################################################
ARG NODE_MAJOR=22
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    npm install -g pnpm && \
    npm cache clean --force && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

###############################################################################
# Maven (multi-mirror: CDN -> downloads -> archive)
###############################################################################
ARG MAVEN_VERSION=3.9.11
RUN set -eux; \
    for base in \
        "https://dlcdn.apache.org/maven/maven-3" \
        "https://downloads.apache.org/maven/maven-3" \
        "https://archive.apache.org/dist/maven/maven-3"; do \
      if curl -fsSL "${base}/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" -o /tmp/maven.tar.gz; then \
        echo "Downloaded Maven from ${base}"; break; \
      fi; \
    done; \
    test -s /tmp/maven.tar.gz; \
    tar -xz -f /tmp/maven.tar.gz -C /opt; \
    ln -s /opt/apache-maven-${MAVEN_VERSION}/bin/mvn /usr/local/bin/mvn; \
    rm -f /tmp/maven.tar.gz; \
    mvn -version

###############################################################################
# Terraform (arch-aware)
###############################################################################
ARG TERRAFORM_VERSION=1.13.0
RUN ARCH=$(dpkg --print-architecture) && \
    curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip" \
      -o /tmp/terraform.zip && \
    unzip -o /tmp/terraform.zip -d /usr/local/bin && rm -f /tmp/terraform.zip && \
    terraform version

###############################################################################
# Vault CLI (arch-aware)
###############################################################################
ARG VAULT_VERSION=1.21.0
RUN ARCH=$(dpkg --print-architecture) && \
    curl -fsSL "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_${ARCH}.zip" \
      -o /tmp/vault.zip && \
    unzip -o /tmp/vault.zip -d /usr/local/bin && rm -f /tmp/vault.zip && \
    vault version

###############################################################################
# Sonar Scanner CLI
###############################################################################
ARG SONAR_VERSION=7.2.0.5079
RUN curl -fsSL "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-${SONAR_VERSION}-linux-x64.zip" \
      -o /tmp/sonar.zip && \
    unzip -o /tmp/sonar.zip -d /opt && rm -f /tmp/sonar.zip && \
    ln -s /opt/sonar-scanner-${SONAR_VERSION}-linux-x64/bin/sonar-scanner /usr/local/bin/sonar-scanner

###############################################################################
# Trivy
###############################################################################
RUN curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key \
      | gpg --dearmor -o /usr/share/keyrings/trivy.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
      > /etc/apt/sources.list.d/trivy.list && \
    apt-get update && apt-get install -y --no-install-recommends trivy && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

###############################################################################
# AWS CLI v2 (arch-aware)
###############################################################################
RUN case "$(dpkg --print-architecture)" in \
        amd64) AWS_ARCH=x86_64 ;; \
        arm64) AWS_ARCH=aarch64 ;; \
        *) echo "unsupported arch"; exit 1 ;; \
    esac && \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install && \
    rm -rf /tmp/aws /tmp/awscliv2.zip

###############################################################################
# Ansible (isolated venv on PATH)
###############################################################################
RUN python3 -m pip install --no-cache-dir --break-system-packages ansible

###############################################################################
# Jenkins Home + Plugins
###############################################################################
RUN mkdir -p /var/jenkins_home/casc && \
    chown -R jenkins:jenkins /var/jenkins_home

COPY --chown=jenkins:jenkins plugins/plugins.txt /usr/share/jenkins/ref/plugins.txt

USER jenkins
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt --latest true

###############################################################################
# Configuration as Code + safe defaults
###############################################################################
ENV CASC_JENKINS_CONFIG=/var/jenkins_home/casc/jenkins.yaml \
    JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Djava.awt.headless=true"

WORKDIR /var/jenkins_home
EXPOSE 8080 50000
