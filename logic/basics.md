# What This Project Is About

This project teaches you end-to-end DevOps by taking a real Java web application — Spring Petclinic — and building an automated pipeline that goes all the way from source code to a live, publicly accessible app running on a cloud-based Kubernetes cluster. The application itself is a simple veterinary clinic management system. It is not the point. The app is just a vehicle for learning how real software gets built, scanned, packaged, and deployed in a professional DevOps workflow.

The core idea is this: every time a developer pushes code to GitHub, a series of automated steps should kick off without anyone pressing a button. Those steps check code quality, build the app, scan it for security issues, wrap it in a container, store that container in a cloud registry, and finally tell Kubernetes to run the new version. That entire sequence is called a CI/CD pipeline, and this project teaches you how to wire one up from scratch on Azure.


# The Application and How It Is Built

Inside the `enahanced-petclinc-springboot/` folder is the actual Spring Boot application. The most important file there is `pom.xml`, which is Maven's configuration file. Maven is a build tool for Java — it knows how to download all the libraries the app depends on, compile the Java source code inside `src/main/`, run the tests inside `src/test/`, and finally package everything into a single deployable file called a WAR file. You do not need to understand every line of `pom.xml`, but knowing it exists and that Maven reads it is essential, because Jenkins will run Maven commands against this file during the pipeline.

The `src/` directory follows a standard Java project structure. The application code lives in `src/main/java/`, HTML templates and web assets live in `src/main/webapp/`, and configuration files like database settings live in `src/main/resources/`. When Maven finishes building, it produces a file called `petclinic.war` inside a folder called `target/`. That WAR file is the compiled, ready-to-run version of the app.


# Docker: Packaging the App Into a Container

Once Maven produces the WAR file, the next challenge is making sure the app can run consistently anywhere — on your laptop, on a server, on a cloud VM — without worrying about whether Java is installed or configured correctly. That is what Docker solves. Docker takes your app and bundles it with everything it needs to run into a single self-contained unit called a container image.

The `Dockerfile` at the root of the repo defines exactly how to build that image. It starts from a base image that already has Java and the Jetty web server installed, copies the WAR file Maven produced into the right location inside that image, and exposes port 8080 so traffic can reach the app. When Jenkins runs the Docker build step, it reads this file and produces an image. Understanding the Dockerfile helps you see the bridge between "code that Maven compiled" and "a runnable unit that Kubernetes can deploy."


# ACR: Where the Container Image Lives

After building the Docker image on the Jenkins server, you need to store it somewhere that your Kubernetes cluster can pull it from. Azure Container Registry (ACR) is essentially a private storage location for Docker images, similar to how GitHub is a storage location for code. The Jenkinsfile stores the ACR address in a variable called `ACR_LOGIN_SERVER`, which is set to `springbootdockerreg.azurecr.io`. When Jenkins pushes the image, it tags it with that address so Kubernetes knows exactly where to fetch it later.

To push to ACR, Jenkins needs permission. This is where Azure Entra ID (formerly Active Directory) comes in. You register an application in Entra ID and get a Client ID, Tenant ID, and Secret — essentially a machine identity with a password. Jenkins stores these as credentials and uses them to log in to Azure before every operation that touches ACR or AKS.


# Kubernetes and AKS: Running the App at Scale

Kubernetes is an orchestration platform — it manages containers across multiple machines, restarts them if they crash, and distributes traffic across multiple copies of the same container for reliability. Azure Kubernetes Service (AKS) is Microsoft's managed version where Azure handles the control plane for you and you just define what you want to run.

The `k8s/sprinboot-deployment.yaml` file is where you tell Kubernetes what to run. It has two sections. The first is a Deployment, which tells Kubernetes to run 3 copies (replicas) of the Petclinic container, pulling the image from ACR. The second is a Service of type LoadBalancer, which tells Azure to create a public IP address and route incoming traffic on port 80 to the app containers on port 8080. When Jenkins runs `kubectl apply -f k8s/sprinboot-deployment.yaml`, it sends this file to the AKS cluster and Kubernetes handles the rest. The public IP that Azure assigns to the LoadBalancer Service is what you open in your browser at the end to see the running app.


# Jenkins and the Jenkinsfile: The Orchestrator

Jenkins is the automation server that ties everything together. It watches your GitHub repository, and when you push code, it reads the `Jenkinsfile` and executes every stage defined inside it in order. The Jenkinsfile is written in a language called Groovy and lives at the root of the repo. Each `stage` block inside it corresponds to one step in the pipeline.

Reading through the Jenkinsfile is one of the most valuable things you can do to understand how the pieces connect. The first stage checks out code from GitHub. The Maven Package stage runs `mvn package`, which is what triggers the full build. The Docker Build stage runs the Dockerfile. The Azure Login stages authenticate Jenkins against Azure using the Entra ID credentials. The Docker Push stage tags the image and pushes it to ACR. The Deploy to AKS stage runs `kubectl apply` against the YAML file. You will also notice several stages are commented out — the SonarQube analysis stages. Those are there for you to enable once you have SonarCloud configured, and they show you where code quality analysis fits into the flow.


# SonarQube: Code Quality as a Gate

SonarCloud is a hosted version of SonarQube that analyzes your Java source code and produces a report covering bugs, vulnerabilities, code smells, and test coverage. The commented-out stages in the Jenkinsfile show exactly where this fits: after the Maven build but before Docker. The idea is that if your code does not meet quality thresholds, the pipeline stops and does not produce a Docker image at all. This turns code quality from a suggestion into an enforced gate. The `pom.xml` already has SonarCloud properties configured under the `sonar.organization` and `sonar.host.url` keys, so the wiring is partially done — you just need to supply credentials.


# Trivy: Security Scanning the Container

Trivy is a security scanner that looks at your Docker image and checks all the packages inside it against databases of known vulnerabilities. It fits into the pipeline right after Docker builds the image and before you push it to ACR. Like SonarQube, the idea is to stop the pipeline if a critical vulnerability is found, rather than shipping a vulnerable image to production. The repo's current Jenkinsfile does not yet have a Trivy stage, so adding one is part of the learning exercise — it goes between the Docker Build and Docker Push stages.


# The VM and the installations.sh Script

All of this — Jenkins, Docker, Maven, the Azure CLI, and kubectl — needs to run somewhere. In this project that somewhere is an Ubuntu virtual machine on Azure. The `installations.sh` script (which you will run after SSH-ing into the VM) installs all of those tools in one shot. Understanding what that script installs and why connects the abstract pipeline steps to the real software running on real infrastructure. Jenkins runs on the VM on port 8080, and you access its web UI from your browser to configure the pipeline, add credentials, and trigger builds.


# How It All Fits Together

The flow from start to finish looks like this: you push code to GitHub, the webhook notifies Jenkins, Jenkins reads the Jenkinsfile and starts the pipeline, Maven builds the WAR file, SonarCloud checks code quality, Docker wraps the WAR into an image, Trivy scans that image, Jenkins pushes the image to ACR, and finally Jenkins tells AKS to pull the new image and deploy it. The LoadBalancer in AKS exposes a public IP, and when you open that IP in a browser you see the live Petclinic application. Every file in this repo plays a specific role in that chain, and understanding which file does what is the foundation for everything else you will learn.
