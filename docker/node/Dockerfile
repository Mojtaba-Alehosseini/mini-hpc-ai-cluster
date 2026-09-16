# One image for every node: head, compute and GPU.
# Slurm 23.11 comes from the Ubuntu 24.04 packages. The GPU node needs no CUDA
# libraries in the image: the NVIDIA container toolkit injects the driver
# libraries at run time, and the PyTorch Apptainer image carries its own CUDA.
# The image carries only packages and the init logic. Ansible provides the munge
# key, the Slurm configuration, the users and the accounts at "make up".
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive TZ=Europe/Rome

RUN apt-get update && apt-get install -y --no-install-recommends \
        slurm-wlm slurmdbd slurm-wlm-basic-plugins munge supervisor \
        mariadb-client openmpi-bin libopenmpi-dev build-essential git \
        fio nfs-common nfs-kernel-server rpcbind \
        python3 python3-venv python3-pip \
        software-properties-common gnupg \
        curl ca-certificates iproute2 iputils-ping procps less vim-tiny sudo tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/share/zoneinfo/$TZ /etc/localtime

# Apptainer, for running GPU jobs in containers on the GPU node. From the
# official PPA so the setuid components are installed and a non-root user (a job)
# can run "apptainer exec".
RUN add-apt-repository -y ppa:apptainer/ppa \
    && apt-get update && apt-get install -y --no-install-recommends apptainer \
    && rm -rf /var/lib/apt/lists/*

COPY supervisor/ /opt/supervisor/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# A default config so a bare "supervisorctl" (from Ansible, or a person in the
# runbook) finds the running supervisord over its socket. supervisord itself is
# started with the role file in /opt/supervisor.
RUN mkdir -p /etc/supervisor \
    && printf '[unix_http_server]\nfile=/run/supervisor.sock\n\n[supervisorctl]\nserverurl=unix:///run/supervisor.sock\n' \
       > /etc/supervisor/supervisord.conf

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
