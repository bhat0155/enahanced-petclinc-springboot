# DevOps CI/CD Roadmap — Spring Petclinic on AKS
### From zero to a working pipeline, one step at a time

This roadmap starts from nothing — no VM, no Jenkins, no Azure resources. Every step has a plain-English explanation of what it is and why it exists, concrete instructions, and a definition of done so you know exactly when to move on.

**Analogy map (for a MERN developer):**
- Azure VM = a Linux server in the cloud (like an EC2 instance)
- Jenkins = self-hosted GitHub Actions — it runs your pipeline on that VM
- ACR = a private Docker Hub owned by you in Azure
- AKS = managed Kubernetes — Azure runs the cluster nodes for you
- Service Principal = a machine account with a username + password (like an API key for Azure)

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
5. **Region**: `East US` (or the one closest to you)
6. Review + Create → Create

#### Definition of done
- Resource group `petclinic-rg` appears in your Resource groups list

---

### Step 2 — Create an Ubuntu VM

#### What it is
This VM is the machine Jenkins will run on. All your pipeline commands (Maven build, Docker build, kubectl deploy) will execute on this machine. Think of it as the server that runs your CI/CD engine.

#### How to do it
1. Azure Portal → search **Virtual Machines** → Create → Azure Virtual Machine
2. **Resource group**: `petclinic-rg`
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

---

### Step 3 — Open Port 8080 on the VM

#### What it is
By default Azure blocks all inbound traffic except SSH. Jenkins runs on port 8080. You need to open that port so you can access Jenkins from your browser.

#### How to do it
1. Go to your `jenkins-vm` → **Networking** → **Add inbound port rule**
2. **Source**: Any
3. **Destination port ranges**: `8080`
4. **Protocol**: TCP
5. **Name**: `Allow-Jenkins`
6. Add

#### Definition of done
- Inbound security rule for port 8080 appears in the Networking tab

---

### Step 4 — SSH into the VM and Run installations.sh

#### What it is
`installations.sh` is a script in your repo that installs every tool the pipeline needs on the VM in one shot: Java, Git, Maven, Jenkins, Docker, Trivy, Azure CLI, and kubectl.

#### How to do it

**On your Mac terminal:**
```bash
# Fix permissions on your .pem key (required by SSH)
chmod 400 ~/path/to/your-key.pem

# SSH into the VM (replace <VM_PUBLIC_IP> with your VM's IP from Azure Portal)
ssh -i ~/path/to/your-key.pem azureuser@<VM_PUBLIC_IP>
```

**Once inside the VM:**
```bash
# Download your installations.sh directly from GitHub
curl -O https://raw.githubusercontent.com/bhat0155/enahanced-petclinc-springboot/main/installations.sh

# Make it executable
chmod +x installations.sh

# Run it (takes 5-10 minutes)
./installations.sh
```

**After it finishes — reboot the VM:**
```bash
sudo reboot
```
The reboot is required so Jenkins picks up its Docker group membership. Without it, Jenkins cannot run Docker commands.

#### Definition of done
- Script finishes with `All tools installed successfully`
- After reboot, SSH back in and run:
  - `java -version` → shows Java 17
  - `mvn -version` → shows Maven
  - `docker --version` → shows Docker
  - `jenkins --version` → shows Jenkins
  - `trivy --version` → shows Trivy
  - `az --version` → shows Azure CLI
  - `kubectl version --client` → shows kubectl

---

### Step 5 — Access Jenkins for the First Time

#### What it is
Jenkins has a web UI. You access it in your browser at `http://<VM_PUBLIC_IP>:8080`. The first time you open it, Jenkins asks for an admin password that was printed at the end of `installations.sh`. If you missed it, SSH into the VM and run:
```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

#### How to do it
1. Open browser → `http://<VM_PUBLIC_IP>:8080`
2. Paste the initial admin password
3. Click **Install suggested plugins** — wait for it to finish
4. Create your admin user (username, password, email)
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
2. Search and install each of the following (check the box, then click Install):
   - `Docker Pipeline`
   - `SonarQube Scanner`
   - `Kubernetes CLI`
3. Check **Restart Jenkins when installation is complete**

#### Definition of done
- All 3 plugins show as Installed in the Installed tab
- Jenkins restarts and you can log back in

---

## PHASE 2 — Jenkins Tool Configuration

---

### Step 7 — Configure Maven in Jenkins

#### What it is
Jenkins needs to know where Maven is installed on the VM so it can call it during the build stage. You tell it by registering Maven as a "tool" in Jenkins settings.

#### How to do it
1. Jenkins UI → **Manage Jenkins** → **Tools**
2. Scroll to **Maven installations** → **Add Maven**
3. **Name**: `maven` (this name must match exactly what the Jenkinsfile will declare)
4. Uncheck "Install automatically"
5. **MAVEN_HOME**: `/usr/share/maven`
6. Save

#### Definition of done
- Maven tool named `maven` is saved in Jenkins Tools

---

### Step 8 — Configure SonarQube Scanner in Jenkins

#### What it is
SonarQube Scanner is a command-line tool that analyzes your code and sends results to SonarCloud. Jenkins needs to know where it is (or install it automatically).

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
2. **Resource group**: `petclinic-rg`
3. **Registry name**: choose a unique name, e.g. `yournamepetclinic` (must be globally unique, lowercase letters and numbers only)
4. **Location**: same region as your VM
5. **SKU**: Basic
6. Review + Create → Create

#### Note your values
- **Registry name**: e.g. `yournamepetclinic`
- **Login server**: e.g. `yournamepetclinic.azurecr.io` (shown in the Overview tab)

#### Definition of done
- ACR appears in Container registries with status Ready
- You can see the Login server URL in the Overview tab

---

### Step 10 — Create AKS Cluster

#### What it is
AKS (Azure Kubernetes Service) is the managed Kubernetes cluster where your app will actually run. Azure handles the control plane (the Kubernetes API server) — you just define what to deploy and Kubernetes runs it across nodes.

#### How to do it
1. Azure Portal → search **Kubernetes services** → Create → Create a Kubernetes cluster
2. **Resource group**: `petclinic-rg`
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
A Service Principal is a machine identity in Azure — like a robot user account with a username (Client ID) and password (Secret). Jenkins uses it to log into Azure and perform actions (push to ACR, deploy to AKS) without a human typing a password.

#### How to do it
The easiest way is via Azure CLI on your Mac or in the VM:

```bash
# Login to Azure
az login

# Create the Service Principal (replace <your-subscription-id>)
az ad sp create-for-rbac --name "jenkins-spn" --role Contributor \
  --scopes /subscriptions/<your-subscription-id>/resourceGroups/petclinic-rg
```

This outputs JSON — **save all four values immediately, you cannot retrieve the password later:**
```json
{
  "appId":       "...",   ← this is the Client ID (username for Jenkins)
  "displayName": "jenkins-spn",
  "password":    "...",   ← this is the Secret (password for Jenkins)
  "tenant":      "..."    ← this is the Tenant ID
}
```

Then give it permission to push to ACR:
```bash
# Get your ACR resource ID
ACR_ID=$(az acr show --name <your-acr-name> --resource-group petclinic-rg --query id -o tsv)

# Assign AcrPush role to the Service Principal
az role assignment create --assignee <appId> --role AcrPush --scope $ACR_ID
```

#### Definition of done
- You have saved: `appId` (Client ID), `password` (Secret), `tenant` (Tenant ID)

---

### Step 12 — Attach ACR to AKS

#### What it is
By default, AKS cannot pull images from your private ACR — it doesn't have credentials. This command grants AKS the `AcrPull` role on your ACR so it can pull images without any extra secrets in your deployment YAML.

#### How to do it
```bash
az aks update \
  --name myAKSCluster \
  --resource-group petclinic-rg \
  --attach-acr <your-acr-name>
```

#### Definition of done
- Command runs without error
- `az aks show --name myAKSCluster --resource-group petclinic-rg --query addonProfiles` shows ACR attached

---

## PHASE 4 — SonarCloud + Jenkins Credentials

---

### Step 13 — Create SonarCloud Account and Project

#### What it is
SonarCloud is the hosted version of SonarQube — no installation needed. It analyzes your Java code for bugs, vulnerabilities, and code smells, then returns a pass/fail quality gate result to Jenkins.

#### How to do it
1. Go to sonarcloud.io → Sign up with GitHub
2. Create an organization — note down the **organization key**
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
6. Select `sonar` from the dropdown
7. Save

#### Definition of done
- SonarQube server named `sonarserver` is saved in Jenkins System config

---

### Step 15 — Add Service Principal to Jenkins Credentials

#### What it is
Jenkins stores secrets (passwords, tokens, keys) in its credential store — your Jenkinsfile references them by ID so the secret never appears in plain text in the code.

#### How to do it
1. Jenkins UI → **Manage Jenkins** → **Credentials** → **System** → **Global credentials** → **Add Credentials**
2. **Kind**: Username with password
3. **Username**: paste the `appId` (Client ID) from Step 11
4. **Password**: paste the `password` (Secret) from Step 11
5. **ID**: `azure-acr-spn`
6. **Description**: `Azure Service Principal`
7. Create

#### Definition of done
- Credential with ID `azure-acr-spn` appears in the credentials list

---

## PHASE 5 — Update Your k8s Deployment File

### Step 16 — Update sprinboot-deployment.yaml

#### What it is
The Kubernetes deployment file tells AKS which Docker image to run. It currently has the original ACR name hardcoded. You need to change it to point to YOUR ACR.

#### What to change
Open `enahanced-petclinc-springboot/k8s/sprinboot-deployment.yaml` and update line 20:

```yaml
# Change this:
image: springbootdockerreg.azurecr.io/springbootapp:latest

# To your ACR:
image: <your-acr-name>.azurecr.io/springbootapp:latest
```

Also remove the `imagePullSecrets` block (lines 22-23) — since you attached ACR to AKS in Step 12, AKS can pull images without a separate secret:
```yaml
# Remove these two lines:
imagePullSecrets:
- name: acr-auth
```

#### Definition of done
- The image field points to your ACR login server
- `imagePullSecrets` is removed
- File is committed and pushed to GitHub

---

## PHASE 6 — Writing the Jenkinsfile from Scratch

### How this phase works
The existing Jenkinsfile has all stages already written. You are going to **replace it with just the skeleton** and then add one stage at a time yourself. Git keeps the old version in history so you can always look back at it with `git log`.

**The rule for every step in this phase:**
1. You write the stage
2. You push to GitHub
3. You run the pipeline in Jenkins
4. You confirm the definition of done is met
5. Only then do you add the next stage

The Jenkinsfile at any point in time should only contain stages you have already tested and passed. Never paste ahead.

---

### Step 17 — Replace the Jenkinsfile with the Skeleton

#### What it is
Every Jenkins pipeline starts with a `pipeline {}` block. Inside it you declare:
- `agent any` — run on any available Jenkins agent (your VM)
- `tools {}` — which tools Jenkins should set up (Maven)
- `environment {}` — variables available to every stage (like `.env` in Node)
- `stages {}` — where the actual work happens (empty for now)

**First:** open `enahanced-petclinc-springboot/Jenkinsfile`, select all, and delete everything. Then write this from scratch yourself:

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
        RG               = 'petclinic-rg'
        NAME             = 'myAKSCluster'
    }
    stages {
        // stages go here — add one at a time after each definition of done
    }
}
```

Fill in your own values for `TENANT_ID`, `ACR_NAME`, and `ACR_LOGIN_SERVER`.

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
        RG               = 'petclinic-rg'
        NAME             = 'myAKSCluster'
    }
    stages {
        // stages go here
    }
}
```

Fill in your own values for `TENANT_ID`, `ACR_NAME`, and `ACR_LOGIN_SERVER`.

#### How to create the Jenkins pipeline job (do this once)
1. Jenkins UI → **New Item** → name it `petclinic-pipeline` → **Pipeline** → OK
2. Scroll to **Pipeline** section → **Definition**: Pipeline script from SCM
3. **SCM**: Git
4. **Repository URL**: `https://github.com/bhat0155/enahanced-petclinc-springboot.git`
5. **Branch**: `*/main`
6. **Script Path**: `enahanced-petclinc-springboot/Jenkinsfile`
7. Save → **Build Now**

#### Definition of done
- Jenkinsfile is pushed to GitHub (old content replaced with skeleton)
- Pipeline job runs and shows green — even with empty `stages {}` it should parse without errors
- You can see the pipeline job on the Jenkins dashboard

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
- Pipeline runs this stage and shows it green
- Jenkins workspace on the VM contains `Jenkinsfile`, `pom.xml`, `Dockerfile`, `src/`, `k8s/`

---

### Step 19 — Stage 2: Maven Build

#### What it is
Maven reads `pom.xml`, downloads all Java dependencies, compiles the code, runs tests, and packages everything into a single `petclinic.war` file inside `target/`. That WAR file is what gets baked into the Docker image next.

Think of it like `npm install && npm run build` but for Java.

#### What to write
```groovy
stage('Maven Build') {
    steps {
        sh 'mvn package'
    }
}
```

#### Definition of done
- Build logs show `BUILD SUCCESS`
- `target/petclinic.war` exists in the Jenkins workspace

---

### Step 20 — Stage 3: SonarQube Analysis

#### What it is
SonarQube Scanner reads your compiled code, checks it for bugs, security vulnerabilities, and bad practices, then sends the results to SonarCloud. This stage does not pass or fail the pipeline — the next stage does that.

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
                -Dsonar.organization=<your-sonarcloud-org-key> \
                -Dsonar.projectName=<your-project-name> \
                -Dsonar.projectKey=<your-project-key> \
                -Dsonar.java.binaries=.
            """
        }
    }
}
```

Fill in your SonarCloud organization key, project name, and project key from Step 13.

#### Definition of done
- Build logs show analysis uploaded to SonarCloud
- SonarCloud dashboard shows your project with results

---

### Step 21 — Stage 4: SonarQube Quality Gate

#### What it is
This stage pauses the pipeline and waits for SonarCloud to respond with a pass or fail. If the quality gate fails (too many bugs, vulnerabilities, or low coverage), `abortPipeline: true` stops the pipeline here and nothing after this runs — no Docker image gets built, nothing gets deployed. This is the guardrail.

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

### Step 22 — Stage 5: Docker Build

#### What it is
Jenkins tells Docker to build an image using the `Dockerfile` in your repo root. Docker reads the Dockerfile, copies the `petclinic.war` from `target/` into a Jetty web server image, and saves the result locally on the VM as `springbootapp:latest`.

#### What to write
```groovy
stage('Docker Build') {
    steps {
        script {
            docker.build("${IMAGE_NAME}:${IMAGE_TAG}")
        }
    }
}
```

#### Definition of done
- Build logs show `Successfully built <image-id>`
- SSH into the VM and run `docker images` — you see `springbootapp:latest`

---

### Step 23 — Stage 6: Trivy Security Scan

#### What it is
Trivy scans the Docker image you just built for known CVEs (Common Vulnerabilities and Exposures) in the OS packages and Java dependencies. `--exit-code 1` makes Trivy return a failure exit code if it finds any HIGH or CRITICAL vulnerabilities, which breaks the pipeline — the image never gets pushed to ACR.

#### What to write
```groovy
stage('Trivy Scan') {
    steps {
        sh "trivy image --exit-code 1 --severity HIGH,CRITICAL ${IMAGE_NAME}:${IMAGE_TAG}"
    }
}
```

Note: double quotes are required here — single quotes would not expand `${IMAGE_NAME}`.

#### Definition of done
- Build logs show Trivy scan output
- If no HIGH/CRITICAL CVEs: stage is green, pipeline continues
- Pipeline breaks here if serious CVEs are found

---

### Step 24 — Stage 7: ACR Login + Docker Push

#### What it is
Jenkins logs into Azure using the Service Principal credential, authenticates Docker to talk to ACR, retags the local image with the full ACR address, and pushes it. After this, the image lives in ACR and AKS can pull it.

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

### Step 25 — Stage 8: Deploy to AKS

#### What it is
Jenkins logs into Azure again, fetches the AKS credentials (a kubeconfig file) so `kubectl` knows which cluster to talk to, then runs `kubectl apply`. Kubernetes reads the deployment YAML, pulls the image from ACR, and creates 3 running replicas. A LoadBalancer service gets assigned a public IP — that IP is your live app URL.

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
- Open that IP in your browser → Petclinic app is live

---

## Full Pipeline Summary

```
PHASE 1: Azure Infrastructure
  Step 1   Create Resource Group
  Step 2   Create Ubuntu VM
  Step 3   Open port 8080
  Step 4   SSH in + run installations.sh
  Step 5   Access Jenkins, initial setup

PHASE 2: Jenkins Configuration
  Step 6   Install plugins (Docker Pipeline, SonarQube Scanner, Kubernetes CLI)
  Step 7   Configure Maven tool
  Step 8   Configure SonarQube Scanner tool

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

PHASE 6: Jenkinsfile (write one stage at a time)
  Step 17  Pipeline skeleton + environment variables
  Step 18  Stage 1 — Git Checkout
  Step 19  Stage 2 — Maven Build
  Step 20  Stage 3 — SonarQube Analysis
  Step 21  Stage 4 — Quality Gate
  Step 22  Stage 5 — Docker Build
  Step 23  Stage 6 — Trivy Scan
  Step 24  Stage 7 — ACR Login + Docker Push
  Step 25  Stage 8 — Deploy to AKS
```
