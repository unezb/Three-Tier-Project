#!/bin/bash
apt update -y
apt install -y docker.io git unzip

systemctl enable docker
systemctl start docker

# Jenkins
wget -q -O - https://pkg.jenkins.io/debian/jenkins.io.key | apt-key add -
echo "deb http://pkg.jenkins.io/debian binary/" > /etc/apt/sources.list.d/jenkins.list

apt update
apt install -y jenkins

systemctl enable jenkins
systemctl start jenkins

# AWS CLI
apt install -y awscli

# kubectl
curl -LO "https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/