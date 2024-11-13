import requests
import time

def test_jenkins_api(jenkins_url, job_name, username, api_token):
    build_url = f"{jenkins_url}/job/{job_name}/buildWithParameters"
    auth = (username, api_token)

    # Trigger the build
    response = requests.post(build_url, auth=auth)
    if response.status_code == 201:
        print("Build triggered successfully")
    else:
        print(f"Failed to trigger build. Status code: {response.status_code}")
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
    jenkins_url = "http://localhost:8081"
    job_name = "benchmark"
    username = "admin"
    api_token = "113eb9a5c5bd7b17a100dc71576403c8a9"
    test_jenkins_api(jenkins_url, job_name, username, api_token)