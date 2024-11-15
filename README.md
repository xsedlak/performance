# Performance Repository

## Description
This project is designed to test and measure the performance of various components using Python. It includes scripts for running performance tests using JMeter, Python.

## Prerequisites
- Docker
- Python 3.9

## Installation
1. Clone the repository:
    ```sh
    git clone https://github.com/xsedlak/performance.git
    cd performance
    ```

2. Install Python dependencies:
    ```sh
    pip install -r requirements.txt
    ```
   
## Usage
### Running Docker Containers
To build and run the Docker containers, use the following commands:

1. Build the Docker image:
    ```sh
    docker build -t performance .
    ```

2. Run the Docker container:
    ```sh
    docker-compose up
    ```

### Running Tests
To run the performance tests, use the following commands:

1. Run Python tests:
    ```sh
    python testing/python_performance_test.py
    ```

2. Run JMeter tests:
    ```sh
    jmeter -n -t testing/jmeter_test.jmx -l results/jmeter_results.jtl
    ```

3. Run Node.js tests:
    ```sh
    npm test
    ```

## Manual Steps
TODO: Add any manual steps required to set up the environment or configure the tests.
