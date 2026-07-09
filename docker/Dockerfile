###############################################################################
# Jenkins DevOps Enterprise Image
###############################################################################
FROM jenkins/jenkins:lts-jdk21

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

###############################################################################
# Base packages
###############################################################################
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash bash-completion ca-certificates curl wget unzip zip \
        git git-lfs vim nano jq tree rsync gettext-base \
        openssh-client sshpass dnsutils iputils-ping net-tools telnet \
        python3 python3-pip python3-venv build-essential \
        gnupg lsb-release locales tzdata && \
    locale-gen en_US.UTF-8 || true && \
    git lfs install && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

###############################################################################
# Docker CLI
###############################################################################
RUN . /etc/os-release && \
    install -m0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y docker-ce-cli docker-buildx-plugin docker-compose-plugin && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

###############################################################################
# kubectl
###############################################################################
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then KARCH=amd64; else KARCH=arm64; fi && \
    curl -fsSL "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/${KARCH}/kubectl" \
      -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl

###############################################################################
# Helm
###############################################################################
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

###############################################################################
# NodeJS 22
###############################################################################
ARG NODE_MAJOR=22
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g pnpm && \
    npm cache clean --force

###############################################################################
# Maven
###############################################################################
ARG MAVEN_VERSION=3.9.11
# Thử CDN chính thức trước (nhanh, ổn định), fallback sang archive nếu thiếu version.
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
    rm -f /tmp/maven.tar.gz

###############################################################################
# Terraform
###############################################################################
ARG TERRAFORM_VERSION=1.13.0
RUN curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
      -o terraform.zip && \
    unzip terraform.zip && mv terraform /usr/local/bin && rm terraform.zip

###############################################################################
# Vault CLI
###############################################################################
ARG VAULT_VERSION=1.21.0
RUN curl -fsSL https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip \
      -o vault.zip && \
    unzip vault.zip && mv vault /usr/local/bin && rm vault.zip

###############################################################################
# Sonar Scanner
###############################################################################
ARG SONAR_VERSION=7.2.0.5079
RUN curl -fsSL https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-${SONAR_VERSION}-linux-x64.zip \
      -o sonar.zip && \
    unzip sonar.zip -d /opt && \
    ln -s /opt/sonar-scanner-${SONAR_VERSION}-linux-x64/bin/sonar-scanner /usr/local/bin/sonar-scanner && \
    rm sonar.zip

###############################################################################
# Trivy
###############################################################################
RUN curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key \
      | gpg --dearmor -o /usr/share/keyrings/trivy.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
      > /etc/apt/sources.list.d/trivy.list && \
    apt-get update && apt-get install -y trivy && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

###############################################################################
# AWS CLI v2
###############################################################################
RUN curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip && \
    unzip awscliv2.zip && ./aws/install && rm -rf aws awscliv2.zip

###############################################################################
# Ansible
###############################################################################
RUN python3 -m pip install --break-system-packages ansible

###############################################################################
# Jenkins Home + Plugins
###############################################################################
RUN mkdir -p /var/jenkins_home/casc && \
    chown -R jenkins:jenkins /var/jenkins_home

COPY --chown=jenkins:jenkins plugins/plugins.txt /usr/share/jenkins/ref/plugins.txt

USER jenkins
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

###############################################################################
# Configuration as Code
###############################################################################
ENV CASC_JENKINS_CONFIG=/var/jenkins_home/casc/jenkins.yaml
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"

EXPOSE 8080 50000
