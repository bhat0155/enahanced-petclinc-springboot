#!/bin/bash
set -e

echo "===== Updating system ====="
sudo apt-get update -y
sudo apt-get upgrade -y

# ─── Git ───────────────────────────────────────────────────────────────────────
echo "===== Installing Git ====="
sudo apt-get install -y git
git --version

# ─── Java 17 ──────────────────────────────────────────────────────────────────
echo "===== Installing Java 17 ====="
sudo apt-get install -y openjdk-17-jdk
java -version

# ─── Maven ────────────────────────────────────────────────────────────────────
echo "===== Installing Maven ====="
sudo apt-get install -y maven
mvn -version

# ─── Jenkins ──────────────────────────────────────────────────────────────────
echo "===== Installing Jenkins ====="
sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/" | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y jenkins
sudo systemctl enable jenkins
sudo systemctl start jenkins
echo "Jenkins is running on port 8080"

# ─── Docker ───────────────────────────────────────────────────────────────────
echo "===== Installing Docker ====="
sudo apt-get install -y ca-certificates curl gnupg lsb-release
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
sudo systemctl enable docker
sudo systemctl start docker
# Allow Jenkins and current user to run Docker without sudo
sudo usermod -aG docker jenkins
sudo usermod -aG docker $USER
docker --version

# ─── Trivy ────────────────────────────────────────────────────────────────────
echo "===== Installing Trivy ====="
sudo apt-get install -y wget apt-transport-https gnupg
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | \
  sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] \
  https://aquasecurity.github.io/trivy-repo/deb generic main" | \
  sudo tee /etc/apt/sources.list.d/trivy.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y trivy
trivy --version

# ─── Azure CLI ────────────────────────────────────────────────────────────────
echo "===== Installing Azure CLI ====="
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az --version

# ─── kubectl ──────────────────────────────────────────────────────────────────
echo "===== Installing kubectl ====="
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
kubectl version --client

echo ""
echo "===== All tools installed successfully ====="
echo "NOTE: Log out and back in (or run 'newgrp docker') for Docker group changes to take effect."
echo "Jenkins initial admin password:"
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
