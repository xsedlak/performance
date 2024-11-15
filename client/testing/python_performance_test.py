

import requests
import time

def test_jenkins_api(jenkins_url, job_name, username, api_token, parameters):
    build_url = f"{jenkins_url}/job/{job_name}/buildWithParameters"

    print(f"Triggering build for job: {job_name} at {build_url}")
    auth = (username, api_token)

    # Trigger the build with parameters
    response = requests.post(build_url, auth=auth, params=parameters)

    if response.status_code == 201:
        print("Build triggered successfully")
        print(f"Response: {response.text}")
    else:
        print(f"Failed to trigger build. Status code: {response.status_code}")
        print(f"Response: {response.text}")
        return

    # Wait for the build to complete
    time.sleep(30)  # Wait for 60 seconds before checking build status
    # TODO - implement the waiting for finishing

    # Check build status
    job_url = f"{jenkins_url}/job/{job_name}/lastBuild/api/json"
    response = requests.get(job_url, auth=auth)

    if response.status_code == 200:
        build_info = response.json()
        print(f"Build result: {build_info['result']}")
    else:
        print(f"Failed to get build info. Status code: {response.status_code}")

if __name__ == "__main__":
    jenkins_url = "http://server:8081/"
    job_name = "benchmark"
    username = "admin"
    api_token = "113eb9a5c5bd7b17a100dc71576403c8a9"

    # Define parameters for the build
    parameters = {
        "BENCHMARKS": "cpu,memory,disk"
    }

    test_jenkins_api(jenkins_url, job_name, username, api_token, parameters)