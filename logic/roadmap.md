# Pipeline Roadmap — Spring Petclinic on AKS

This file walks through every step of the CI/CD pipeline in order. Each step has a clear explanation of what happens, how credentials are created and wired up, and a definition of done so you know exactly when a step is complete.

---

## Step 1 — Git Checkout

### What happens
Jenkins checks out the source code from GitHub onto the Jenkins VM. Everything else in the pipeline depends on this — Maven needs the code to build, Sonar needs it to scan, Docker needs the Dockerfile.

### Jenkinsfile reference
- Line 19: `git branch: 'prod', url: 'https://github.com/bkrrajmali/enahanced-petclinc-springboot.git'`
- Change the URL to your own repo if you forked it

### Definition of done
- Jenkins workspace on the VM contains all source files
- `enahanced-petclinc-springboot/` folder and `Dockerfile` are present in the workspace

---

## Step 2 — Maven Build

### What happens
Maven reads `pom.xml`, downloads all Java dependencies, compiles the source code, runs tests, and packages everything into a single file called `petclinic.war` inside the `target/` folder. This WAR file is what gets baked into the Docker image later.

### Jenkinsfile reference
- Line 49: `sh 'mvn package'`
- Maven tool is declared at line 4: `maven 'maven'` — Jenkins must have Maven configured under Global Tool Configuration

### One-time Jenkins setup
1. Jenkins UI → Manage Jenkins → Global Tool Configuration
2. Under Maven → Add Maven → name it `maven` → choose a version → Save

### Definition of done
- Build logs show `BUILD SUCCESS`
- `target/petclinic.war` file exists in the workspace

---

## Step 3 — SonarQube / SonarCloud Analysis + Quality Gate

### What happens
The Sonar Scanner reads your source code and sends it to SonarCloud (the hosted version of SonarQube — no installation on VM needed). SonarCloud analyzes it for bugs, vulnerabilities, code smells, and test coverage. The pipeline then waits for SonarCloud to respond. If the quality gate fails, the pipeline breaks here and nothing after this runs.

### Jenkinsfile reference
- Lines 32-46: `Sonar Analysis` stage (currently commented out — uncomment it)
- Lines 52-58: `Sonar Quality Gate` stage (currently commented out — uncomment it)
- Line 34: `SCANNER_HOME = tool 'Sonar-scanner'` — Jenkins uses a scanner tool installed via Global Tool Configuration
- Line 37: `withSonarQubeEnv('sonarserver')` — Jenkins looks up a SonarQube server named `sonarserver`
- Line 39: `sonar.organization=bkrrajmali` — change this to your SonarCloud org name
- Lines 40-41: `sonar.projectName` and `sonar.projectKey` — change to your project name
- Line 55: `credentialsId: 'sonar'` — Jenkins credential holding your SonarCloud token

### One-time setup — SonarCloud

1. Go to sonarcloud.io and create a free account
2. Create an organization (note down the organization key — e.g. `yourname`)
3. Create a new project inside that organization (note down the project key)
4. Go to My Account → Security → Generate Token → copy the token (you will not see it again)

### One-time setup — Jenkins (SonarQube server)

1. Jenkins UI → Manage Jenkins → Configure System
2. Scroll to SonarQube servers section
3. Click Add SonarQube
4. Name: `sonarserver` (must match exactly what is in the Jenkinsfile line 37)
5. Server URL: `https://sonarcloud.io`
6. Server authentication token: click Add → Jenkins → Kind: Secret text → paste your SonarCloud token → ID: `sonar` → Save
7. Select that token from the dropdown → Save

### One-time setup — Jenkins (Sonar Scanner tool)

1. Jenkins UI → Manage Jenkins → Global Tool Configuration
2. Under SonarQube Scanner → Add SonarQube Scanner → name it `Sonar-scanner` (must match line 34) → Save

### Definition of done
- Both Sonar stages are uncommented in Jenkinsfile
- Build logs show SonarCloud analysis completed
- SonarCloud dashboard shows your project with a passing quality gate (green)
- If you intentionally introduce bad code, pipeline breaks at this stage

---

## Step 4 — Docker Build

### What happens
Jenkins triggers a Docker build on the VM. Docker reads the `Dockerfile` in the workspace root, takes the `petclinic.war` produced by Maven, and wraps it into a container image using Jetty as the web server. The result is a local Docker image named `springbootapp:latest` sitting on the Jenkins VM.

### Jenkinsfile reference
- Line 7: `IMAGE_NAME = 'springbootapp'` — the image name
- Line 8: `IMAGE_TAG = 'latest'` — the tag
- Line 63: `docker.build("${IMAGE_NAME}:${IMAGE_TAG}")` — triggers the build, produces `springbootapp:latest`
- Dockerfile is picked up automatically from the workspace root

### No extra setup needed
Docker is already installed on the VM via `installations.sh`

### Definition of done
- Build logs show `Successfully built <image-id>`
- Running `docker images` on the VM shows `springbootapp:latest`

---

## Step 5 — Trivy Security Scan

### What happens
Trivy scans the local Docker image `springbootapp:latest` for known vulnerabilities (CVEs). It checks OS packages inside the Jetty base image and dependencies bundled in the WAR file against a public vulnerability database. If critical or high vulnerabilities are found, the pipeline breaks here and the image is never pushed to ACR.

### Jenkinsfile reference
- This stage does not exist yet — you need to add it after the Docker Build stage
- The stage should run: `trivy image ${IMAGE_NAME}:${IMAGE_TAG}`
- Add `--exit-code 1 --severity HIGH,CRITICAL` so the pipeline breaks on serious findings

### What to add to Jenkinsfile
```groovy
stage('Trivy Scan') {
    steps {
        sh 'trivy image --exit-code 1 --severity HIGH,CRITICAL ${IMAGE_NAME}:${IMAGE_TAG}'
    }
}
```

### No extra setup needed
Trivy is already installed on the VM via `installations.sh`. No credentials needed — it scans the local image directly.

### Definition of done
- Trivy stage is added to Jenkinsfile between Docker Build and ACR Login
- Build logs show Trivy scan output
- If no critical/high CVEs: pipeline continues
- If CVEs found: pipeline breaks with a non-zero exit code

---

## Step 6 — ACR Login + Docker Push

### What happens
Jenkins logs into Azure using a Service Principal (a machine identity), then authenticates Docker to talk to Azure Container Registry (ACR). It retags the local image with the full ACR address and pushes it. After this step, the image is stored in ACR and can be pulled by AKS.

### Jenkinsfile reference
- Line 9: `TENANT_ID` — your Azure tenant ID
- Line 10: `ACR_NAME = 'springbootdockerreg'` — your ACR name
- Line 11: `ACR_LOGIN_SERVER = 'springbootdockerreg.azurecr.io'` — full ACR address
- Line 12: `FULL_IMAGE_NAME = "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"` — resolves to `springbootdockerreg.azurecr.io/springbootapp:latest`
- Line 69: `credentialsId: 'azure-acr-spn'` — Jenkins credential holding the Service Principal
- Line 73: `az login --service-principal` — logs Jenkins into Azure
- Line 74: `az acr login --name $ACR_NAME` — authenticates Docker to ACR
- Line 85: `docker tag` — renames local image to full ACR address
- Line 87: `docker push` — uploads image to ACR

### One-time setup — Create Azure Service Principal

A Service Principal is a machine account in Azure with a username (Client ID) and password (Secret). Jenkins uses it to log into Azure without a human typing a password.

1. Open Azure Portal → Azure Active Directory (Entra ID) → App registrations
2. Click New registration → give it a name (e.g. `jenkins-spn`) → Register
3. Note down: **Application (Client) ID** and **Directory (Tenant) ID**
4. Go to Certificates & Secrets → New client secret → copy the **Secret Value** (you will not see it again)
5. Go to your ACR resource → Access Control (IAM) → Add role assignment
6. Role: `AcrPush` → assign to your app registration → Save

### One-time setup — Add credential to Jenkins

1. Jenkins UI → Manage Jenkins → Credentials → System → Global credentials → Add Credentials
2. Kind: Username with password
3. Username: paste the **Client ID** from above
4. Password: paste the **Secret Value** from above
5. ID: `azure-acr-spn` (must match exactly what is in the Jenkinsfile line 69)
6. Save

### One-time setup — Update Jenkinsfile env variables

Update these lines with your own values:
- Line 9: `TENANT_ID` → your Directory (Tenant) ID from Azure
- Line 10: `ACR_NAME` → your ACR name (just the short name, not the full URL)
- Line 11: `ACR_LOGIN_SERVER` → `<your-acr-name>.azurecr.io`

### Definition of done
- Build logs show `Login Succeeded` for ACR
- Build logs show `latest: digest: sha256:...` confirming push succeeded
- Azure Portal → your ACR → Repositories shows `springbootapp` with a `latest` tag

---

## Step 7 — Deploy to AKS

### What happens
Jenkins logs into Azure again using the same Service Principal, fetches the AKS cluster credentials so `kubectl` knows which cluster to talk to, and then applies the deployment file. Kubernetes reads `sprinboot-deployment.yaml`, pulls the image from ACR, runs 3 replicas of the container, and exposes the app via a LoadBalancer. Azure assigns a public IP to that LoadBalancer — that IP is the URL of your live app.

### Jenkinsfile reference
- Line 13: `RG = 'socgen'` — Azure resource group where AKS lives
- Line 14: `NAME = 'myAKSCluster'` — AKS cluster name
- Line 98: `az login --service-principal` — same login as ACR step, same credential
- Line 99: `az aks get-credentials --resource-group $RG --name $NAME` — downloads kubeconfig so kubectl points to your cluster
- Line 112: `kubectl apply -f k8s/sprinboot-deployment.yaml` — sends the deployment file to AKS

### What's inside `sprinboot-deployment.yaml`
- A Deployment telling AKS to run 3 replicas of the container, pulling the image from ACR
- A LoadBalancer Service routing public traffic on port 80 to the container on port 8080
- The image name is hardcoded in this file — `kubectl apply` sends it as-is, K8s reads the image name from inside and pulls it from ACR automatically

### One-time setup — AKS permissions for ACR
AKS needs permission to pull images from ACR. Do this once in Azure:
1. Azure Portal → AKS cluster → Settings → Integrations
2. Under Container registry → attach your ACR → Save
   OR run: `az aks update --name myAKSCluster --resource-group socgen --attach-acr springbootdockerreg`

### One-time setup — Update Jenkinsfile env variables
- Line 13: `RG` → your resource group name
- Line 14: `NAME` → your AKS cluster name

### Definition of done
- Build logs show kubeconfig merged successfully
- Build logs show `deployment.apps/springboot-deployment configured` (or `created` on first run)
- `kubectl get pods` on the cluster shows 3 pods in `Running` state
- `kubectl get svc` shows a LoadBalancer with an external IP assigned
- Opening that IP in a browser shows the Petclinic app

---

## Full Pipeline Summary

```
Step 1: Git Checkout       → source code lands on Jenkins VM
Step 2: Maven Build        → petclinic.war produced in target/
Step 3: SonarQube          → code quality gate (breaks if bad code)
Step 4: Docker Build       → springbootapp:latest image built locally
Step 5: Trivy Scan         → image scanned for CVEs (breaks if critical found)
Step 6: ACR Push           → image uploaded to springbootdockerreg.azurecr.io
Step 7: AKS Deploy         → kubectl apply → app live on public IP
```
