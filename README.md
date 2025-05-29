# Deploying a Netflix Clone on Kubernetes using DevSecOps methodology

In this project we would be deploying Netflix Clone application on an EKS cluster using DevSecOps methodology. We would be making use of security tools like SonarQube, OWASP Dependency Check and Trivy.
We would also be monitoring our EKS cluster using monitoring tools like Prometheus and Grafana. Most importantly we will be using ArgoCD for the Deployment.

## Step 1: Launch an EC2 Instance and install Jenkins, SonarQube, Docker and Trivy

We would be making use of Terraform to launch the EC2 instance. We would be adding a script as userdata for the installation of Jenkins, SonarQube, Trivy and Docker. 

## Step 2: Access Jenkins at port 8080 and install required plugins

Install the following plugins:

1. NodeJS 
2. Eclipse Temurin Installer
3. SonarQube Scanner
4. OWASP Dependency Check
5. Docker
6. Docker Commons
7. Docker Pipeline
8. Docker API
9. docker-build-step

## Step 3: Set up SonarQube

For the SonarQube Configuration, first access the Sonarqube Dashboard using the url http://elastic_ip:9000

1. Create the token 
Administration -> Security -> Users -> Create a token 

2. Add this token as a credential in Jenkins 

3. Go to Manage Jenkins -> System -> SonarQube installation 
Add URL of SonarQube and for the credential select the one added in step 2.

4. Go to Manage Jenkins -> Tools -> SonarQube Scanner Installations
-> Install automatically.

## Step 4: Set up OWASP Dependency Check 

1. Go to Manage Jenkins -> Tools -> Dependency-Check Installations
-> Install automatically

## Step 5: Set up Docker for Jenkins

1. Go to Manage Jenkins -> Tools -> Docker Installations -> Install automatically

2. And then go to Manage Jenkins -> Credentials -> System -> Global Credentials -> Add credentials. Add username and password for the docker registry (You need to create an account on Dockerhub). 

## Step 6: Create a pipeline in order to build and push the dockerized image securely using multiple security tools

Go to Dashboard -> New Item -> Pipeline 

Use the code below for the Jenkins pipeline. 

```bash
pipeline {
    agent any
    environment {
        SCANNER_HOME = tool 'sonar-scanner'
    }
    stages {
        stage('clean workspace') {
            steps {
                cleanWs()
            }
        }
        stage('Checkout from Git') {
            steps {
                git branch: 'main', credentialsId: 'git-cred', url: 'https://github.com/sathish103/Netflixapp.git'
            }
        }
        stage("Sonarqube Analysis") {
            steps {
                withSonarQubeEnv('sonar-scanner') {
                    sh '''$SCANNER_HOME/bin/sonar-scanner -Dsonar.projectName=Netflix \
                    -Dsonar.projectKey=Netflix'''
                }
            }
        }
        stage('OWASP FS SCAN') {
            steps {
                dependencyCheck additionalArguments: '--scan ./ --disableYarnAudit --disableNodeAudit', odcInstallation: 'OWASP DP-Check'
                dependencyCheckPublisher pattern: '**/dependency-check-report.xml'
            }
        }
        stage('TRIVY FS SCAN') {
            steps {
                script {
                    try {
                        sh "trivy fs . > trivyfs.txt" 
                    }catch(Exception e){
                        input(message: "Are you sure to proceed?", ok: "Proceed")
                    }
                }
            }
        }
        stage("Docker Build Image"){
            steps{
                   
                sh "docker build --build-arg API_KEY=e9277f6b402c670a3a0809250b872939 -t netflix ."
            }
        }
        stage("TRIVY"){
            steps{
                sh "trivy image netflix > trivyimage.txt"
                script{
                    input(message: "Are you sure to proceed?", ok: "Proceed")
                }
            }
        }
        stage("Docker Push"){
            steps{
                script {
                    withDockerRegistry(credentialsId: 'docker-creds', toolName: 'docker'){   
                    sh "docker tag netflix sathish103/netflix:latest "
                    sh "docker push sathish103/netflix:latest"
                    }
                }
            }
        }
    }
}
```

## Step 7: Create an EKS Cluster using Terraform 

Prerequisite: Install kubectl and helm before executing the commands below 

## Step 8: Deploy Prometheus and Grafana on EKS 

In order to access the cluster use the command below:

```
aws eks update-kubeconfig --name "Cluster-Name" --region "Region-of-operation"
```


1. Add prometheus Helm repo

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
```

2. Create Prometheus namespace

```bash
kubectl create namespace prometheus
```

3. Install kube-prometheus stack

```bash
helm install prometheus prometheus-community/kube-prometheus-stack -n prometheus \
  --set prometheus.prometheusSpec.maximumStartupDurationSeconds=120

```

4. Edit the prometheus service and make it LoadBalancer

```bash
kubectl edit svc prometheus-kube-prometheus-prometheus -n prometheus
    OR
kubectl patch svc prometheus-kube-prometheus-prometheus -n prometheus -p '{"spec": {"type": "LoadBalancer"}}'

```

5. Edit the grafana service too to change it to LoadBalancer

```bash
kubectl edit svc prometheus-grafana -n prometheus
    OR
kubectl patch svc prometheus-grafana -n prometheus -p '{"spec": {"type": "LoadBalancer"}}'

```
6. Run this command to get grafana login password (Username-default: admin)

```bash
kubectl get secret --namespace prometheus prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode

```

## Step 9: Deploy ArgoCD on EKS to fetch the manifest files to the cluster

1. Create a namespace argocd
```bash
kubectl create namespace argocd
```

2. Add argocd repo locally
```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.4.7/manifests/install.yaml
```

3. By default, argocd-server is not publically exposed. In this scenario, we will use a Load Balancer to make it usable:
```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

4. We get the load balancer hostname using the command below:
```bash
kubectl get svc argocd-server -n argocd -o json
```

5. Once you get the load balancer hostname details, you can access the ArgoCD dashboard through it.

6. We need to enter the Username and Password for ArgoCD. The username will be admin by default. For the password, we need to run the command below:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```


## Step 10: Configure the Cert-Manager for TLS certificates for (application access)


1. Install cert-manager

```bash
kubectl apply --validate=false -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

kubectl get pods -n cert-manager
```

2. Create ClusterIssuer for Let's Encrypt
# vi cluster-issuer.yaml

```bash
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: your-email@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```
```bash
kubectl apply -f cluster-issuer.yaml

```

3. Cleanup Cert-Manager

```bash
kubectl delete -f cluster-issuer.yaml

kubectl delete -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

```


## Step 11: Configure the openssl for TLS certificates for (application access)

1. Create and navigate to a folder for your cert files

```bash
mkdir -p ~/netflix-tls && cd ~/netflix-tls

```
2. Generate a private key

```bash
openssl genrsa -out netflix-app.key 2048
```
3. Create a CSR with your specific domain as CN

```bash
openssl req -new -key netflix-app.key -out netflix-app.csr -subj "/CN=nexflix-app.devopscicd.xyz"

```

4. Generate a self-signed certificate valid for 1 year (365 days)

```bash
openssl x509 -req -in netflix-app.csr -signkey netflix-app.key -out netflix-app.crt -days 365
```

5. (optional): Verify certificate details

```bash
openssl x509 -in netflix-app.crt -text -noout
```

6. Create Kubernetes TLS secret in netflix-app namespace

```bash
kubectl create secret tls netflix-app-tls --cert=netflix-app.crt --key=netflix-app.key -n netflix-app
```

7. Add this tls secret into ingress yaml file along with your HOST domain











