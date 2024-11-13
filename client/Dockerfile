FROM python:3.9-slim

# Install necessary tools
RUN apt-get update && apt-get install -y  \
    openjdk-17-jdk \
    curl \
    unzip \
    vim

# Install JMeter
RUN mkdir /jmeter \
    && curl -L https://dlcdn.apache.org//jmeter/binaries/apache-jmeter-5.6.3.tgz | tar xvz -C /jmeter --strip-components=1

# Set JAVA_HOME and PATH
ENV JAVA_HOME /usr/lib/jvm/java-11-openjdk-amd64
ENV PATH $PATH:$JAVA_HOME/bin:/jmeter/bin

# Install Python dependencies
COPY requirements.txt .
RUN pip install -r requirements.txt

# Create work directory and copy test scripts
RUN mkdir /app
COPY testing/python_performance_test.py /app
COPY testing/jmeter_test.jmx /app

WORKDIR /app

CMD ["python", "python_smoke_test.py"]
