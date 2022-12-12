#!/bin/bash
#OSVersion=$(rpm -q centos-release | cut -d - -f 3)

function InfoLog() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") INFO: $1"
}

function WarningLog() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") WARNING: $1"
}

function ErrorLog() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") ERROR: $1"
}


if [[ $(whoami) == root ]]; then
    MdytempDir="/$(whoami)/mdtemp"
else
    ErrorLog "You must use root user to run the script."
    exit 1
fi

if [[ $(date +"%z") != "+0800" ]]; then
    WarningLog "The time zone was: $(timedatectl | grep "Time zone" | awk -F ": " '{print $2}')"
    echo ""
    echo -e '\t You can run this command to adjust the time zone: timedatectl set-timezone "Asia/Shanghai"\n'
fi


if [[ ${OSVersion} -ne 7 ]]; then
    ErrorLog "This system is not CentOS7, this script is only for CentOS7."
    exit 1
fi

function OffFirewall() {
    if [[ $(getenforce) == Enforcing ]]; then
        setenforce 0 &>/dev/null && sed -i s/"^SELINUX=.*$"/"SELINUX=disabled"/g /etc/selinux/config
        InfoLog "SELinux status is Enforcing, has been changed to Permissive and Disabled."
    elif [[ $(getenforce) == Permissive ]]; then
        sed -i s/"^SELINUX=.*$"/"SELINUX=disabled"/g /etc/selinux/config
        InfoLog "SELinux status is Permissive, has been changed to disabled."
    elif [[ $(getenforce) == Disabled ]]; then
        InfoLog "SELinux status is Disabled, doing nothing."
    else
        ErrorLog "SELinux update failed."
        exit 1
    fi

    if systemctl status firewalld | grep "running" &>/dev/null; then
        systemctl stop firewalld &>/dev/null
        systemctl disable firewalld &>/dev/null
        InfoLog "Firewalld has been changed to off."
    else
        systemctl disable firewalld &>/dev/null
        InfoLog "Firewalld status is inactive, doing nothing."
    fi
}

function InstallDocker() {
    DockerFileName="docker-20.10.16.tgz"
    DockerInstallDir="/usr/bin"
    FKernelVersion=$(uname -r | awk -F "." '{print $1}')
    SKernelVersion=$(uname -r | awk -F "-" '{print $2}' | awk -F "." '{print $1}')

    if [[ -z "$1" ]] ;then
        DockerDataDir="/data/docker"
    else
        Parameter1=$(echo "$1" | awk -F "=" '{print $1}')
        DockerDataDir=$(echo "$1" | awk -F "=" '{print $2}')
        if [[ ${Parameter1} != "--data.path" ]]; then
            ErrorLog "You must use the '--data.path' parameter."
            exit 1
        else
            if [[ ! -d ${DockerDataDir} ]]; then
                ErrorLog "Cannot access ${DockerDataDir}: No such file or directory."
                exit 1
            fi
        fi
    fi

    # Docker OverlayFS 存储驱动程序需要系统内核版本为3.10.0-514及以上（默认CentOS7.3及以上版本即可）。
    if [[ ${FKernelVersion} -lt 3 ]]; then
        ErrorLog "The Linux kernel needs to be greater than 3.10.0-514 to install ${DockerFileName%.*}."
        exit 1
    elif [[ ${FKernelVersion} -eq 3 ]]; then
        if [[ ${SKernelVersion} -lt 514 ]]; then
            ErrorLog "The Linux kernel needs to be greater than 3.10.0-514 to install ${DockerFileName%.*}."
            exit 1
        fi
    fi
    if ls /usr/bin/docker* &>/dev/null; then
        WarningLog "Docker already exists."
        exit 2
    elif  [[ $(getenforce) == Enforcing ]]; then
        WarningLog "Please close selinux."
        exit 2
    elif systemctl status firewalld | grep "running" &>/dev/null; then
        WarningLog "Please close firewalld."
        exit 2
    elif [[ ! -f ${MdytempDir}/${DockerFileName} ]]; then
        ErrorLog "Cannot access ${MdytempDir}/${DockerFileName}: No such file or directory."
        exit 1
    fi

    tar xf "${MdytempDir}/${DockerFileName}" -C "${MdytempDir}"
    cp -r "${MdytempDir}/docker/"* "${DockerInstallDir}"

    if [[ ! -d /etc/docker/ ]]; then
        if ! mkdir /etc/docker/ ;then
            ErrorLog "Failed to create /etc/docker/."
            exit 1
        fi
    fi

    cat >/etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://uvlkeb6d.mirror.aliyuncs.com"],
  "data-root": "${DockerDataDir}",
  "max-concurrent-downloads": 10,
  "exec-opts": ["native.cgroupdriver=cgroupfs"],
  "storage-driver": "overlay2",
  "default-address-pools":[{"base":"172.80.0.0/16","size":24}]
}
EOF

    cat >/etc/systemd/system/docker.service <<EOF
[Unit]
Description=Docker
After=network-online.target
Wants=network-online.target
[Service]
Type=notify
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP \$MAINPID
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=0
TimeoutStartSec=0
Delegate=yes
KillMode=process
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    InfoLog "Starting Docker, please wait."
    if systemctl start docker &>/dev/null; then
        systemctl enable docker &>/dev/null
        InfoLog "Docker start successfully."
    else
        ErrorLog "Docker start failed."
        exit 1
    fi

}

case "$1" in
off-filewall)
    OffFirewall
    ;;
install-docker)
    if [ -z "$2" ] ;then
        InstallDocker
    else 
        if [ -z "$3" ] ;then
            InstallDocker "$2"
        else
            ErrorLog "Please check your command."
            exit 1
        fi
    fi
    ;;
*)
    echo "Usage:
        bash offline-install-docker.sh (off-filewall | install-docker --data.path=/your_path/ )"
    ;;
esac