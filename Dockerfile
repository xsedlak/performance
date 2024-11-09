# Use the official Jenkins LTS (Long Term Support) image as a base
FROM jenkins/jenkins:lts

# Switch to root to install additional packages
USER root

# Install the necessary tools
RUN apt-get update && apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg2 \
    software-properties-common

# Install the Docker CLI (for the ability to run Docker commands from Jenkins)
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
RUN add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/debian \
   $(lsb_release -cs) \
   stable"
RUN apt-get update && apt-get install -y docker.io

# Switch back to user jenkins
USER jenkins

# Install some useful Jenkins plugins
RUN jenkins-plugin-cli --plugins \
    workflow-aggregator \
    git \
    docker-workflow

# Expose ports for Jenkins web interface and agents
EXPOSE 8080
EXPOSE 50000

# Run Jenkins
CMD ["jenkins.sh"]
