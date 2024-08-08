FROM centos:7

ADD tlp-stress-4.0.0m4.tgz /opt/
COPY zing /opt/zing
COPY tlp-stress-run.sh /opt/

ENV TLP_STRESS_HOME=/opt/tlp-stress-4.0.0m4
ENV JAVA_HOME=/opt/zing
ENV PATH=/opt/zing/bin:${PATH}

CMD [ "bash", "/opt/tlp-stress-run.sh" ]
