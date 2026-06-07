# DevOps CI/CD Roadmap — Spring Petclinic on AKS
### From zero to a working pipeline, one step at a time

This roadmap starts from nothing — no VM, no Jenkins, no Azure resources. Every step has a plain-English explanation of what it is and why it exists, concrete instructions, and a definition of done so you know exactly when to move on.

**We install each tool only when we need it.** You will understand why every tool exists because you install it right before you use it.

**Analogy map (for a MERN developer):**
- Azure VM = a Linux server in the cloud (like an EC2 instance)
- Jenkins = self-hosted GitHub Actions — it runs your pipeline on that VM
- Maven = like npm for Java — installs dependencies and builds the project
- Docker = packages your app into a container image
- ACR = a private Docker Hub owned by you in Azure
- AKS = managed Kubernetes — Azure runs the cluster nodes for you
- Service Principal = a machine account with a username + password (like an API key for Azure)
- Trivy = a security scanner that checks your Docker image for known vulnerabilities

---

## PHASE 1 — Azure Infrastructure

---

### Step 1 — Create a Resource Group

#### What it is
A Resource Group is a folder in Azure that holds all your resources (VM, ACR, AKS). When you delete the group, everything inside is deleted too. This makes cleanup easy after the bootcamp.

#### How to do it
1. Go to portal.azure.com → sign in
2. Search for **Resource groups** → Create
3. **Subscription**: your subscription
4. **Resource group name**: `petclinic-rg`
5. **Region**: pick the one closest to you
6. Review + Create → Create

#### Definition of done
- Resource group appears in your Resource groups list

---

### Step 2 — Create an Ubuntu VM

#### What it is
This VM is the machine Jenkins will run on. All your pipeline commands (Maven build, Docker build, kubectl deploy) will execute on this machine. Think of it as the server that runs your CI/CD engine.

#### How to do it
1. Azure Portal → search **Virtual Machines** → Create → Azure Virtual Machine
2. **Resource group**: your resource group from Step 1
3. **Virtual machine name**: `jenkins-vm`
4. **Region**: same as your resource group
5. **Image**: `Ubuntu Server 22.04 LTS`
6. **Size**: `Standard_B2s` (2 vCPUs, 4 GB RAM — enough for Jenkins + Maven + Docker)
7. **Authentication type**: SSH public key
8. **Username**: `azureuser`
9. **SSH public key source**: Generate new key pair → download the `.pem` file and save it safely
10. **Public inbound ports**: Allow SSH (22)
11. Review + Create → Create
12. When prompted to download the key pair — download it, you cannot get it again

#### Definition of done
- VM named `jenkins-vm` appears in Virtual Machines with status `Running`
- You have the `.pem` file saved on your Mac
- Note down your **VM public IP** from the Overview tab — you will use it constantly

---

### Step 3 — Open Port 8080 on the VM

#### What it is
By default Azure blocks all inbound traffic except SSH. Jenkins runs on port 8080. You need to open that port so you can access Jenkins from your browser.

#### How to do it
1. Go to your `jenkins-vm` → **Networking** → **Network settings** → **Add inbound port rule**
2. **Source**: Any
3. **Destination port ranges**: `8080`
4. **Protocol**: TCP
5. **Name**: `Allow-Jenkins`
6. Add

#### Definition of done
- Inbound security rule for port 8080 appears in the Networking tab

---

### Step 4 — SSH into the VM and Install Java + Git + Jenkins

#### Why only these three?
Jenkins is the engine — nothing else runs until Jenkins is up. Jenkins itself needs Java to run. Git is needed so Jenkins can clone your repo. Everything else (Maven, Docker, Trivy, Azure CLI, kubectl) gets installed later, right before you need it.

#### SSH into the VM
On your Mac terminal:
```bash
# Fix permissions on your .pem key (required by SSH)
chmod 400 ~/path/to/your-key.pem

# Connect to the VM
ssh -i ~/path/to/your-key.pem azureuser@<VM_PUBLIC_IP>
```

#### Install Git
```bash
sudo apt-get update -y
sudo apt-get install -y git
git --version
```

#### Install Java 17
Jenkins requires Java to run. Java 17 is the current LTS version.
```bash
sudo apt-get install -y openjdk-17-jdk
java -version
```

#### Install Jenkins
```bash
sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/" | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y jenkins
sudo systemctl enable jenkins
sudo systemctl start jenkins
```

#### Get the initial admin password (you will need this in Step 5)
```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```
Copy this password — you need it to unlock Jenkins in your browser.

#### Definition of done
- `git --version` → shows a version number
- `java -version` → shows Java 17
- `sudo systemctl status jenkins` → shows `active (running)`
- You have the initial admin password copied

---

### Step 5 — Access Jenkins for the First Time

#### What it is
Jenkins has a web UI. You access it at `http://<VM_PUBLIC_IP>:8080`. The first time you open it, Jenkins asks for the admin password you copied in Step 4.

#### How to do it
1. Open browser → `http://<VM_PUBLIC_IP>:8080`
2. Paste the initial admin password
3. Click **Install suggested plugins** — wait for it to finish
4. Create your admin user (choose a username, password, and email)
5. Set Jenkins URL to `http://<VM_PUBLIC_IP>:8080` → Save and Finish

#### Definition of done
- You are logged into the Jenkins dashboard
- No error banners on the dashboard

---

### Step 6 — Install Additional Jenkins Plugins

#### What it is
Plugins extend Jenkins with extra capabilities. The pipeline needs plugins for Docker, SonarQube, and Kubernetes that are not in the default install.

#### How to do it
1. Jenkins UI → **Manage Jenkins** → **Plugins** → **Available plugins**
2. Search and install each of the following (tick the checkbox, then click Install):
   - `Docker Pipeline`
   - `SonarQube Scanner`
   - `Kubernetes CLI`
3. Check **Restart Jenkins when installation is complete** and wait for it

#### Definition of done
- All 3 plugins show as Installed under the Installed tab
- Jenkins restarts and you can log back in

---

## PHASE 2 — Jenkins + Maven Setup

---

### Step 7 — Install Maven on the VM + Configure it in Jenkins

#### Why now?
The Maven Build stage needs Maven. Installing it now so you can configure the Jenkins tool and immediately test it in Step 19.

#### Why not `apt-get install maven`?
Ubuntu 22.04's package repository ships Maven **3.6.3**. This project's `pom.xml` has a maven-enforcer rule that requires Maven **3.8.4 or higher** — the build will fail at the very first step with an enforcer error before any code is even compiled. We install Maven manually to get a version that satisfies that constraint.

#### Install Maven on the VM
SSH into your VM and run:
```bash
MVN_VERSION=3.9.9
wget https://downloads.apache.org/maven/maven-3/${MVN_VERSION}/binaries/apache-maven-${MVN_VERSION}-bin.tar.gz
sudo tar -xzf apache-maven-${MVN_VERSION}-bin.tar.gz -C /opt
sudo ln -s /opt/apache-maven-${MVN_VERSION} /opt/maven
echo 'export PATH=/opt/maven/bin:$PATH' | sudo tee /etc/profile.d/maven.sh
source /etc/profile.d/maven.sh
mvn -version
```

#### Configure Maven as a Jenkins tool
Jenkins needs to know where Maven lives on the VM so it can call it during builds.

1. Jenkins UI → **Manage Jenkins** → **Tools**
2. Scroll to **Maven installations** → **Add Maven**
3. **Name**: `maven` (must match exactly — this is what the Jenkinsfile will reference)
4. Uncheck **Install automatically**
5. **MAVEN_HOME**: `/opt/maven`
6. Save

#### Definition of done
- `mvn -version` on the VM shows Maven 3.9.9
- Maven tool named `maven` is saved in Jenkins Tools with MAVEN_HOME `/opt/maven`

---

### Step 8 — Configure SonarQube Scanner in Jenkins

#### What it is
SonarQube Scanner is a command-line tool that analyzes your code and sends results to SonarCloud. You let Jenkins install it automatically — no manual install needed on the VM.

#### How to do it
1. Jenkins UI → **Manage Jenkins** → **Tools**
2. Scroll to **SonarQube Scanner installations** → **Add SonarQube Scanner**
3. **Name**: `Sonar-scanner` (must match exactly)
4. Check **Install automatically** → choose the latest version
5. Save

#### Definition of done
- SonarQube Scanner named `Sonar-scanner` is saved in Jenkins Tools

---

## PHASE 3 — Azure Resources for the Pipeline

---

### Step 9 — Create Azure Container Registry (ACR)

#### What it is
ACR is your private Docker image registry — like a private Docker Hub hosted in Azure. After Jenkins builds your Docker image, it pushes it here. AKS then pulls from here to run the app.

#### How to do it
1. Azure Portal → search **Container registries** → Create
2. **Resource group**: your resource group
3. **Registry name**: choose a unique name e.g. `yournamepetclinic` (globally unique, lowercase only)
4. **Location**: same region as your VM
5. **SKU**: Basic
6. Review + Create → Create

#### Note down
- **Registry name** (short name, e.g. `yournamepetclinic`)
- **Login server** (e.g. `yournamepetclinic.azurecr.io`) — visible in the Overview tab

#### Definition of done
- ACR appears in Container registries with status Ready
- You have noted down the registry name and login server URL

---

### Step 10 — Create AKS Cluster

#### What it is
AKS (Azure Kubernetes Service) is the managed Kubernetes cluster where your app will actually run. Azure handles the control plane — you just define what to deploy and Kubernetes runs it.

#### How to do it
1. Azure Portal → search **Kubernetes services** → Create → Create a Kubernetes cluster
2. **Resource group**: your resource group
3. **Cluster name**: `myAKSCluster`
4. **Region**: same as everything else
5. **Node count**: 1 (enough for a bootcamp)
6. **Node size**: `Standard_B2s`
7. Leave everything else as default
8. Review + Create → Create (takes 5-10 minutes)

#### Definition of done
- AKS cluster `myAKSCluster` appears in Kubernetes services with status Running

---

### Step 11 — Create a Service Principal

#### What it is
A Service Principal is a machine identity in Azure — like a robot user with a username (Client ID) and password (Secret). Jenkins uses it to log into Azure and perform actions (push to ACR, deploy to AKS) without a human typing a password each time.

#### How to do it
Run this on your Mac terminal (you need Azure CLI installed — run `brew install azure-cli` if you don't have it):

```bash
# Login to Azure
az login

# Create the Service Principal
az ad sp create-for-rbac --name "jenkins-spn" --role Contributor \
  --scopes /subscriptions/<your-subscription-id>/resourceGroups/<your-resource-group>
```

This outputs JSON — **save all four values immediately, you cannot retrieve the password later:**
```json
{
  "appId":    "...",   ← Client ID  (username Jenkins will use)
  "password": "...",   ← Secret     (password Jenkins will use)
  "tenant":   "..."    ← Tenant ID  (goes into the Jenkinsfile)
}
```

Then give it permission to push to ACR:
```bash
ACR_ID=$(az acr show --name <your-acr-name> --resource-group <your-rg> --query id -o tsv)
az role assignment create --assignee <appId> --role AcrPush --scope $ACR_ID
```

#### Definition of done
- You have saved: `appId` (Client ID), `password` (Secret), `tenant` (Tenant ID)

---

### Step 12 — Attach ACR to AKS

#### What it is
By default, AKS cannot pull images from your private ACR. This command grants AKS the `AcrPull` permission on your ACR so it can pull images without needing a separate Kubernetes secret.

#### How to do it
```bash
az aks update \
  --name myAKSCluster \
  --resource-group <your-resource-group> \
  --attach-acr <your-acr-name>
```

#### Definition of done
- Command completes without error

---

## PHASE 4 — SonarCloud + Jenkins Credentials

---

### Step 13 — Create SonarCloud Account and Project

#### What it is
SonarCloud is the hosted version of SonarQube — no installation needed. It analyzes your Java code for bugs, vulnerabilities, and code smells, then sends a pass/fail quality gate result back to Jenkins.

#### How to do it
1. Go to sonarcloud.io → Sign up with GitHub
2. Create an organization → note down the **organization key**
3. Create a new project → manually → note down the **project key** and **project name**
4. Go to **My Account** → **Security** → **Generate Token** → name it `jenkins` → Generate
5. Copy the token immediately — you will not see it again

#### Definition of done
- You have: organization key, project name, project key, token

---

### Step 14 — Configure SonarCloud Server in Jenkins

#### How to do it
1. Jenkins UI → **Manage Jenkins** → **System**
2. Scroll to **SonarQube servers** → **Add SonarQube**
3. **Name**: `sonarserver`
4. **Server URL**: `https://sonarcloud.io`
5. **Server authentication token** → click Add → Jenkins
   - Kind: **Secret text**
   - Secret: paste your SonarCloud token
   - ID: `sonar`
   - Add
6. Select `sonar` from the dropdown → Save

#### Definition of done
- SonarQube server named `sonarserver` is saved in Jenkins System config

---

### Step 15 — Add Service Principal to Jenkins Credentials

#### What it is
Jenkins stores secrets in its credential store. Your Jenkinsfile references them by ID — the secret never appears in plain text in your code (same idea as environment variables in a `.env` file, but managed by Jenkins).

#### How to do it
1. Jenkins UI → **Manage Jenkins** → **Credentials** → **System** → **Global credentials** → **Add Credentials**
2. **Kind**: Username with password
3. **Username**: your `appId` (Client ID) from Step 11
4. **Password**: your `password` (Secret) from Step 11
5. **ID**: `azure-acr-spn`
6. **Description**: `Azure Service Principal`
7. Create

#### Definition of done
- Credential with ID `azure-acr-spn` appears in the credentials list

---

## PHASE 5 — Update Your k8s Deployment File

---

### Step 16 — Update sprinboot-deployment.yaml

#### What it is
The Kubernetes deployment file tells AKS which Docker image to run and how. It currently has the original author's ACR name hardcoded. You need to change it to point to YOUR ACR.

#### What to change
Open `enahanced-petclinc-springboot/k8s/sprinboot-deployment.yaml` and make two changes:

**Change the image to your ACR:**
```yaml
# From:
image: springbootdockerreg.azurecr.io/springbootapp:latest

# To:
image: <your-acr-name>.azurecr.io/springbootapp:latest
```

**Remove the imagePullSecrets block** — since you attached ACR to AKS in Step 12, AKS can pull images without a separate secret:
```yaml
# Remove these two lines entirely:
imagePullSecrets:
- name: acr-auth
```

#### Definition of done
- Image field points to your ACR login server
- `imagePullSecrets` block is removed
- File is committed and pushed to GitHub

---

## PHASE 6 — Writing the Jenkinsfile from Scratch

### The rule for this entire phase
1. You write the stage yourself
2. You push to GitHub
3. You run the pipeline in Jenkins
4. You confirm the definition of done is met
5. Only then do you add the next stage

The Jenkinsfile at any point should only contain stages you have already tested and passed. Never write ahead.

---

### Step 17 — Replace the Jenkinsfile with the Skeleton

#### What to do first
Open `enahanced-petclinc-springboot/Jenkinsfile`, **select all and delete everything**. The old content is preserved in git history — run `git log` anytime to look back at it.

Then write this from scratch:

#### What to write
```groovy
pipeline {
    agent any
    tools {
        maven 'maven'
    }
    environment {
        IMAGE_NAME       = 'springbootapp'
        IMAGE_TAG        = 'latest'
        TENANT_ID        = '<your-tenant-id>'
        ACR_NAME         = '<your-acr-name>'
        ACR_LOGIN_SERVER = '<your-acr-name>.azurecr.io'
        FULL_IMAGE_NAME  = "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"
        RG               = '<your-resource-group>'
        NAME             = 'myAKSCluster'
    }
    stages {
        // stages go here — add one at a time after each definition of done
    }
}
```

Fill in your own values for `TENANT_ID`, `ACR_NAME`, `ACR_LOGIN_SERVER`, and `RG`.

#### Create the Jenkins pipeline job (do this once)
1. Jenkins UI → **New Item** → name it `petclinic-pipeline` → **Pipeline** → OK
2. Scroll to **Pipeline** → **Definition**: Pipeline script from SCM
3. **SCM**: Git
4. **Repository URL**: `https://github.com/bhat0155/enahanced-petclinc-springboot.git`
5. **Branch**: `*/main`
6. **Script Path**: `enahanced-petclinc-springboot/Jenkinsfile`
7. Save → **Build Now**

#### Definition of done
- Jenkinsfile pushed to GitHub with skeleton only (old content deleted)
- Pipeline job runs green — empty `stages {}` is valid and should pass
- Pipeline job visible on Jenkins dashboard

---

### Step 18 — Stage 1: Git Checkout

#### What it is
Jenkins clones your GitHub repo onto the VM so all other stages have the source code to work with. Think of it as the pipeline's `git clone`.

#### What to write
Add inside `stages {}`:
```groovy
stage('Checkout') {
    steps {
        git branch: 'main',
            url: 'https://github.com/bhat0155/enahanced-petclinc-springboot.git'
    }
}
```

#### Definition of done
- Stage is green in Jenkins
- SSH into VM → `ls /var/lib/jenkins/workspace/petclinic-pipeline/enahanced-petclinc-springboot/` → shows `pom.xml`, `Dockerfile`, `src/`, `k8s/`

---

### Step 19 — Stage 2: Maven Build

#### What it is
Maven reads `pom.xml`, downloads all Java dependencies, compiles the code, runs tests, and packages everything into a single `petclinic.war` file inside `target/`. That WAR file is what gets baked into the Docker image next.

Think of it like `npm install && npm run build` but for Java.

#### What to write
```groovy
stage('Maven Build') {
    steps {
        sh 'mvn package -f enahanced-petclinc-springboot/pom.xml'
    }
}
```

#### Definition of done
- Build logs show `BUILD SUCCESS`
- `enahanced-petclinc-springboot/target/petclinic.war` exists in the Jenkins workspace

---

### Step 20 — Stage 3: SonarQube Analysis

#### What it is
SonarQube Scanner reads your compiled code, checks it for bugs, security vulnerabilities, and bad practices, then sends the results to SonarCloud. This stage uploads the results — it does not pass or fail the pipeline. The next stage does that.

#### What to write
```groovy
stage('SonarQube Analysis') {
    environment {
        SCANNER_HOME = tool 'Sonar-scanner'
    }
    steps {
        withSonarQubeEnv('sonarserver') {
            sh """
                ${SCANNER_HOME}/bin/sonar-scanner \
                -Dsonar.organization=<your-org-key> \
                -Dsonar.projectName=<your-project-name> \
                -Dsonar.projectKey=<your-project-key> \
                -Dsonar.java.binaries=enahanced-petclinc-springboot/target
            """
        }
    }
}
```

Fill in your SonarCloud organization key, project name, and project key from Step 13.

#### Definition of done
- Build logs show analysis uploaded to SonarCloud
- SonarCloud dashboard shows your project with scan results

---

### Step 21 — Stage 4: SonarQube Quality Gate

#### What it is
This stage pauses the pipeline and waits for SonarCloud to respond with pass or fail. If the quality gate fails, `abortPipeline: true` stops the pipeline — no Docker image gets built, nothing gets deployed. This is the guardrail that prevents bad code from shipping.

#### What to write
```groovy
stage('Quality Gate') {
    steps {
        timeout(time: 2, unit: 'MINUTES') {
            waitForQualityGate abortPipeline: true, credentialsId: 'sonar'
        }
    }
}
```

#### Definition of done
- Build logs show `Quality gate status: OK`
- Pipeline continues to next stage

---

### Step 22 — Install Docker on the VM + Stage 5: Docker Build

#### Why install Docker now?
You only need Docker for the Docker Build stage and beyond. Installing it here so you understand exactly what it's for.

#### Install Docker on the VM
SSH into your VM and run:
```bash
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

# Allow Jenkins to run Docker without sudo
sudo usermod -aG docker jenkins

# Restart Jenkins so it picks up the Docker group membership
sudo systemctl restart jenkins
```

#### What the stage does
Jenkins tells Docker to build an image using the `Dockerfile` in the repo. Docker reads it, copies the `petclinic.war` into a Jetty web server image, and saves the result locally on the VM as `springbootapp:latest`.

#### What to write
```groovy
stage('Docker Build') {
    steps {
        script {
            docker.build("${IMAGE_NAME}:${IMAGE_TAG}", "enahanced-petclinc-springboot")
        }
    }
}
```

#### Definition of done
- Build logs show `Successfully built <image-id>`
- SSH into VM → `docker images` → shows `springbootapp:latest`

---

### Step 23 — Install Trivy on the VM + Stage 6: Trivy Scan

#### Why install Trivy now?
Trivy is only needed for the security scan stage. Installing it right before you use it.

#### Install Trivy on the VM
```bash
sudo apt-get install -y wget apt-transport-https gnupg

wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | \
  sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg

echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] \
  https://aquasecurity.github.io/trivy-repo/deb generic main" | \
  sudo tee /etc/apt/sources.list.d/trivy.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y trivy
trivy --version
```

#### What the stage does
Trivy scans the local Docker image for known CVEs (Common Vulnerabilities and Exposures). `--exit-code 1` means Trivy returns a failure if it finds HIGH or CRITICAL vulnerabilities — breaking the pipeline so the image never gets pushed.

#### What to write
```groovy
stage('Trivy Scan') {
    steps {
        sh "trivy image --exit-code 1 --severity HIGH,CRITICAL ${IMAGE_NAME}:${IMAGE_TAG}"
    }
}
```

Note: double quotes are required here — single quotes do not expand `${IMAGE_NAME}`.

#### Definition of done
- Trivy scan output appears in build logs
- If no HIGH/CRITICAL CVEs: stage is green, pipeline continues
- Pipeline breaks here if serious vulnerabilities are found

---

### Step 24 — Install Azure CLI on the VM + Stage 7: ACR Login + Docker Push

#### Why install Azure CLI now?
Azure CLI is needed to log into Azure and push to ACR. Installing it right before the push stage.

#### Install Azure CLI on the VM
```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az --version
```

#### What the stage does
Jenkins logs into Azure using the Service Principal credential, authenticates Docker to talk to ACR, retags the local image with the full ACR address, and pushes it. After this step, the image lives in ACR and AKS can pull it.

#### What to write
```groovy
stage('Push to ACR') {
    steps {
        withCredentials([usernamePassword(
            credentialsId: 'azure-acr-spn',
            usernameVariable: 'AZURE_USERNAME',
            passwordVariable: 'AZURE_PASSWORD'
        )]) {
            sh """
                az login --service-principal \
                    -u \$AZURE_USERNAME \
                    -p \$AZURE_PASSWORD \
                    --tenant ${TENANT_ID}

                az acr login --name ${ACR_NAME}

                docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${FULL_IMAGE_NAME}
                docker push ${FULL_IMAGE_NAME}
            """
        }
    }
}
```

#### Definition of done
- Build logs show `Login Succeeded` and `digest: sha256:...`
- Azure Portal → your ACR → Repositories shows `springbootapp` with tag `latest`

---

### Step 25 — Install kubectl on the VM + Stage 8: Deploy to AKS

#### Why install kubectl now?
kubectl is the command-line tool that talks to Kubernetes. You only need it for the deploy stage.

#### Install kubectl on the VM
```bash
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
kubectl version --client
```

#### What the stage does
Jenkins logs into Azure, fetches the AKS cluster credentials (a kubeconfig file) so `kubectl` knows which cluster to talk to, then runs `kubectl apply`. Kubernetes pulls the image from ACR and runs 3 replicas. A LoadBalancer gets a public IP — that IP is your live app.

#### What to write
```groovy
stage('Deploy to AKS') {
    steps {
        withCredentials([usernamePassword(
            credentialsId: 'azure-acr-spn',
            usernameVariable: 'AZURE_USERNAME',
            passwordVariable: 'AZURE_PASSWORD'
        )]) {
            sh """
                az login --service-principal \
                    -u \$AZURE_USERNAME \
                    -p \$AZURE_PASSWORD \
                    --tenant ${TENANT_ID}

                az aks get-credentials \
                    --resource-group ${RG} \
                    --name ${NAME} \
                    --overwrite-existing

                kubectl apply -f enahanced-petclinc-springboot/k8s/sprinboot-deployment.yaml
            """
        }
    }
}
```

#### Definition of done
- Build logs show `deployment.apps/springboot-app configured` (or `created` on first run)
- SSH into VM and run:
  - `kubectl get pods` → 3 pods in `Running` state
  - `kubectl get svc` → LoadBalancer shows an external IP
- Open that IP in a browser → Petclinic app is live

---

## Full Pipeline Summary

```
PHASE 1: Azure Infrastructure
  Step 1   Create Resource Group
  Step 2   Create Ubuntu VM
  Step 3   Open port 8080
  Step 4   Install Git + Java + Jenkins on VM
  Step 5   Access Jenkins, initial setup
  Step 6   Install Jenkins plugins

PHASE 2: Jenkins + Maven Setup
  Step 7   Install Maven on VM + configure Maven tool in Jenkins
  Step 8   Configure SonarQube Scanner tool in Jenkins

PHASE 3: Azure Resources
  Step 9   Create ACR
  Step 10  Create AKS Cluster
  Step 11  Create Service Principal
  Step 12  Attach ACR to AKS

PHASE 4: SonarCloud + Jenkins Credentials
  Step 13  Create SonarCloud account + project + token
  Step 14  Configure SonarCloud server in Jenkins
  Step 15  Add Service Principal to Jenkins credentials

PHASE 5: k8s YAML
  Step 16  Update sprinboot-deployment.yaml with your ACR name

PHASE 6: Jenkinsfile (write one stage at a time, test before moving on)
  Step 17  Skeleton + environment variables
  Step 18  Stage 1 — Git Checkout
  Step 19  Stage 2 — Maven Build          [Maven already installed — Step 7]
  Step 20  Stage 3 — SonarQube Analysis
  Step 21  Stage 4 — Quality Gate
  Step 22  Install Docker on VM → Stage 5 — Docker Build
  Step 23  Install Trivy on VM  → Stage 6 — Trivy Scan
  Step 24  Install Azure CLI on VM → Stage 7 — ACR Login + Docker Push
  Step 25  Install kubectl on VM → Stage 8 — Deploy to AKS
```
