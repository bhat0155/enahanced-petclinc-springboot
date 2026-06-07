Most tutorials show you a pipeline that works. They skip the part where it fails six times
before working once, and they never explain why. I built a full CI/CD pipeline from zero —
Jenkins on an Azure VM, all the way to a live Spring Boot app running on AKS — and this
is the version that includes the failures.

---

## What Is a CI/CD Pipeline?

A CI/CD pipeline is an automated assembly line for software. Every time code is pushed,
the pipeline takes it through a fixed sequence: build, test, scan, package, deploy.
Nothing ships unless it passes every gate. Think of it like a car factory — the car moves
down the line, each station does one job, and a defect at any station stops the whole line.
What makes Jenkins different from GitHub Actions or GitLab CI is that you host it yourself,
on your own machine, which gives you full control but also full responsibility.

---

## Why Does It Matter?

- **Manual deployments break under pressure** — when you're deploying by hand, you skip
  steps when you're tired or in a hurry. That's when things go to production broken.
- **Security vulnerabilities ship invisibly** — without a scanner like Trivy in the pipeline,
  a Docker image with a known CVE gets pushed to production and nobody notices until it's
  exploited.
- **Code quality degrades silently** — without a quality gate, technical debt accumulates
  commit by commit. By the time someone notices, the codebase is unmaintainable.
- **Rollbacks are impossible without traceability** — if every deployment is manual and
  undocumented, you have no idea what changed between the version that worked and the
  version that didn't.

---

## What I Built

I deployed the Spring Framework PetClinic app — a real Java Spring MVC application, not a
hello world — through a fully automated Jenkins pipeline to Azure Kubernetes Service.
The stack included SonarCloud for code analysis, Trivy for container scanning, Azure
Container Registry for storing Docker images, and AKS for running the app.
Success meant one thing: pushing a code change, running the pipeline, and seeing that
change live at a public IP address with three Kubernetes pods serving it.

```
GitHub Repo
    │
    ▼
Jenkins (Azure VM)
    │
    ├── Maven Build       → compiles code, runs 62 tests, produces petclinic.war
    ├── SonarQube Analysis → uploads code to SonarCloud for analysis
    ├── Quality Gate      → waits for SonarCloud pass/fail verdict
    ├── Docker Build      → bakes petclinic.war into a Jetty container image
    ├── Trivy Scan        → scans image for CVEs
    ├── Push to ACR       → uploads image to Azure Container Registry
    └── Deploy to AKS     → tells Kubernetes to run the new image
                                │
                                ▼
                      http://20.220.241.5 (live app)
```

| Tool | Role |
|------|------|
| Jenkins | Pipeline orchestration |
| Maven 3.9.16 | Build and test |
| SonarCloud | Static code analysis |
| Docker | Container packaging |
| Trivy | CVE scanning |
| Azure Container Registry | Private image registry |
| Azure Kubernetes Service | Container orchestration |
| Service Principal | Machine identity for Azure auth |

---

## How I Implemented It

### 1. Installing Maven — the version trap

Ubuntu's package manager ships Maven 3.6.3. The `pom.xml` enforcer requires 3.8.4 or higher.
`apt-get install maven` silently installs the wrong version and the build fails immediately
with an enforcer error before a single line of code is compiled.

I installed manually:

```bash
MVN_VERSION=3.9.16
wget https://downloads.apache.org/maven/maven-3/${MVN_VERSION}/binaries/apache-maven-${MVN_VERSION}-bin.tar.gz
sudo tar -xzf apache-maven-${MVN_VERSION}-bin.tar.gz -C /opt
sudo ln -s /opt/apache-maven-${MVN_VERSION} /opt/maven
echo 'export PATH=/opt/maven/bin:$PATH' | sudo tee /etc/profile.d/maven.sh
source /etc/profile.d/maven.sh
```

The symlink at `/opt/maven` is the important part — Jenkins is configured to use that path
as `MAVEN_HOME`. If you ever upgrade Maven, you update the symlink, not the Jenkins config.

### 2. SonarQube token injection — two wrappers, not one

This took the most debugging. The naive approach uses `withSonarQubeEnv` alone:

```groovy
// this does NOT reliably pass the token in newer plugin versions
withSonarQubeEnv('sonarserver') {
    sh "mvn sonar:sonar ..."
}
```

`withSonarQubeEnv` injects the token via an encrypted env variable called
`SONARQUBE_SCANNER_PARAMS`. Newer versions of the Maven Sonar plugin stopped reading it
reliably — the scan runs but reports "Project not found" because it authenticated with nothing.

The fix: use both wrappers nested together.

```groovy
stage('SonarQube Analysis') {
    steps {
        withSonarQubeEnv('sonarserver') {        // registers the task ID for waitForQualityGate
            withCredentials([string(credentialsId: 'sonar', variable: 'SONAR_TOKEN')]) {
                sh """
                    mvn sonar:sonar \
                    -f enahanced-petclinc-springboot/pom.xml \
                    -Dsonar.host.url=https://sonarcloud.io \
                    -Dsonar.organization=bhat0155 \
                    -Dsonar.projectKey=bhat0155_enahanced-petclinc-springboot \
                    -Dsonar.token=\$SONAR_TOKEN \
                    -DskipTests
                """
            }
        }
    }
}
```

`withSonarQubeEnv` is still required — not for the token, but because `waitForQualityGate`
reads the task ID that this wrapper registers internally. Remove it and the quality gate
stage crashes immediately with "No previous SonarQube analysis found."

`\$SONAR_TOKEN` — the backslash is not a typo. Without it, Groovy evaluates the variable
before the shell runs, at a point when `withCredentials` hasn't injected it yet.

### 3. Quality Gate — two token stores in Jenkins

Jenkins has two separate places that hold a SonarCloud token and they are not linked:

1. The **credentials store** (used by `withCredentials`)
2. The **SonarQube server config** (used by `waitForQualityGate` when it polls the API)

When I regenerated the SonarCloud token to fix the analysis stage, I updated the credential
but forgot the server config. The quality gate stage then failed with a 404 "Project doesn't
exist" — SonarCloud's way of saying the request was unauthorized.

```groovy
stage('Quality Gate') {
    steps {
        timeout(time: 2, unit: 'MINUTES') {
            waitForQualityGate abortPipeline: true, credentialsId: 'sonar'
        }
    }
}
```

The `timeout` is a ceiling, not a fixed wait. `waitForQualityGate` returns the moment
SonarCloud responds — usually under 30 seconds. The 2-minute cap just prevents the pipeline
from hanging forever if SonarCloud is unreachable.

### 4. Docker Build — Jenkins needs group membership

After installing Docker, Jenkins still cannot run Docker commands. The Docker daemon requires
group membership — not just root access.

```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins  # group membership only applies after restart
```

The restart is the step people skip. Jenkins inherits group memberships at startup.
Adding the group without restarting means Jenkins is still running without it.

### 5. Trivy Scan — exit code decisions

The initial configuration used `--exit-code 1`, which breaks the pipeline on any HIGH or
CRITICAL CVE:

```groovy
sh "trivy image --exit-code 0 --severity HIGH,CRITICAL ${IMAGE_NAME}:${IMAGE_TAG}"
```

The scan found three HIGH CVEs — two in Jetty 11 (the base image) and one in Spring Core.
The Jetty CVEs have no fix in the 11.x line; the fix requires migrating to Jetty 12.
Using `--exit-code 1` would permanently block every pipeline run over a vulnerability
in someone else's code that I cannot patch.

`--exit-code 0` keeps the scan in place — the table prints in the build logs, the findings
are visible — but the pipeline continues. This is the standard approach for base image CVEs
you've triaged and accepted while waiting for an upstream fix.

### 6. ACR Login + Deploy — service principal credential pitfalls

The `azure-acr-spn` credential requires two fields: Client ID (a UUID) and Client Secret
(a string that looks like a password). Azure also gives you a Secret ID (another UUID) when
you create a secret — it is not the secret value.

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

If `az login` returns `AADSTS7000215: Invalid client secret`, you have the Secret ID in the
password field instead of the Secret Value. Reset the credential with
`az ad sp credential reset --id <appId>` and use the `password` field from the output.

### 7. Deploy to AKS — the latest tag problem

`kubectl apply` compares the deployment YAML to the current cluster state. If the YAML
hasn't changed — same image name, same tag — Kubernetes reports `unchanged` and does nothing.
It has no way to know the image content behind `latest` is different.

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

The fix is `kubectl rollout restart deployment/springboot-app` at the end of this stage,
or better: tag each image with the git commit SHA so Kubernetes always sees a new tag and
pulls automatically.

---

## Key Takeaways

- **`apt-get` version ≠ project requirement** — always check what version the package
  manager installs against what your build tool requires. They are often different.
- **Jenkins wrappers have side effects beyond their stated purpose** — `withSonarQubeEnv`
  isn't just for token injection; removing it breaks `waitForQualityGate` for an unrelated
  reason.
- **Two credential stores in Jenkins for SonarQube** — updating one without the other causes
  silent failures that look like permission errors on the SonarCloud side.
- **Docker group membership requires a process restart** — adding a user to a group has no
  effect on already-running processes. Always restart Jenkins after `usermod`.
- **`--exit-code 1` in Trivy is only useful if you can act on every finding** — for base
  image CVEs you don't own, it blocks indefinitely. Triage before choosing your exit code.
- **`latest` tag is invisible to Kubernetes** — if the image content changes but the tag
  doesn't, `kubectl apply` does nothing. Use commit SHAs as tags in production.
- **Service Principal secrets have two IDs** — the Secret ID and the Secret Value are both
  UUIDs but only one authenticates. Putting the wrong one in Jenkins gives a misleading
  error about invalid credentials.

---

## Final Thoughts

What surprised me most was how many of the failures were caused by tool boundaries —
not bugs in the tools themselves, but assumptions baked into one tool that conflicted with
assumptions baked into another. I assumed SonarCloud's token problem was a configuration
issue; it turned out to be a plugin version compatibility problem that required understanding
how two Jenkins wrappers interact at the JVM level. Before this project, I assumed
Kubernetes would automatically pull a new image whenever the pipeline pushed one — the
`latest` tag behavior is obvious in retrospect but genuinely non-obvious the first time.
This post is most useful for developers coming from a frontend or Node.js background who
are building their first Java CI/CD pipeline and hitting walls they don't have the vocabulary
to search for yet.

[GitHub Repository](https://github.com/bhat0155/enahanced-petclinc-springboot)
