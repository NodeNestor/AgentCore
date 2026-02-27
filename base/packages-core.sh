#!/bin/bash
# packages-core.sh — Core apt packages shared across all AgentCore images.
# Sourced by Dockerfiles for Ubuntu 24.04 and Kali. Run as root.
set -e

apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    wget \
    git \
    nano \
    vim \
    htop \
    procps \
    net-tools \
    tmux \
    openssh-server \
    python3 \
    python3-pip \
    python3-venv \
    ca-certificates \
    gnupg \
    software-properties-common \
    unzip \
    zip \
    iputils-ping \
    dnsutils \
    sudo \
    locales \
    jq

locale-gen en_US.UTF-8
rm -rf /var/lib/apt/lists/*
