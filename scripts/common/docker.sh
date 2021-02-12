
function change_cgroup_driver_to_systemd() {
    # Docker uses cgroupfs by default to manage cgroup. On distributions using systemd,
    # i.e. RHEL and Ubuntu, this causes issues because there are now 2 seperate ways
    # to manage resources. For more info see the link below.
    # https://github.com/kubernetes/kubeadm/issues/1394#issuecomment-462878219

    if [ -f /var/lib/kubelet/kubeadm-flags.env ] || [ -f /etc/docker/daemon.json ]; then
        return
    fi

    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
    "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF

    mkdir -p /etc/systemd/system/docker.service.d
}

function install_docker() {
    if [ "$SKIP_DOCKER_INSTALL" != "1" ]; then
        if [ -z "$DOCKER_VERSION" ]; then
            printf "${RED}The installer did not specify a version of Docker to include, but is required by all kURL installation scripts currently. The latest supported version of Docker will be installed.${NC}\n"
            DOCKER_VERSION="19.03.4"
        fi
        change_cgroup_driver_to_systemd
        docker_get_host_packages_online "$DOCKER_VERSION"
        docker_install
        systemctl enable docker
        systemctl start docker
        check_docker_storage_driver "$HARD_FAIL_ON_LOOPBACK"
    fi

    # NOTE: this will not remove the proxy
    if [ -z "$PRESERVE_DOCKER_CONFIG" ] && [ -n "$PROXY_ADDRESS" ]; then
        docker_configure_proxy
    fi
}

function restart_docker() {
    systemctl daemon-reload
    systemctl restart docker
}

function uninstall_docker() {
    if [ "$CONTAINERD_MIGRATION" != "1" ]; then
        return
    fi

    echo "Uninstalling Docker..."
    case "$LSB_DIST" in
        ubuntu)
            export DEBIAN_FRONTEND=noninteractive
            dpkg --remove docker-ce docker-ce-cli
            rm -rf /var/lib/docker
            echo "Docker successfully uninstalled."
            return 0
            ;;

        centos|rhel|amzn)
            rpm --erase --force docker-ce docker-ce-cli
            rm -rf /var/lib/docker
            echo "Docker successfully uninstalled."
            return 0
            ;;
    esac

    printf "Docker uninstall is not supported on ${LSB_DIST} ${DIST_MAJOR}"
}

docker_install() {
   case "$LSB_DIST" in
        ubuntu)
            export DEBIAN_FRONTEND=noninteractive
            dpkg --install --force-depends-version $DIR/packages/docker/${DOCKER_VERSION}/ubuntu-${DIST_VERSION}/*.deb
            DID_INSTALL_DOCKER=1
            return 0
            ;;

        centos|rhel|amzn)
            rpm --upgrade --force --nodeps $DIR/packages/docker/${DOCKER_VERSION}/rhel-7/*.rpm
            DID_INSTALL_DOCKER=1
            return 0
            ;;
    esac

   printf "Offline Docker install is not supported on ${LSB_DIST} ${DIST_MAJOR}"
   exit 1
}

check_docker_storage_driver() {
    if [ "$BYPASS_STORAGEDRIVER_WARNINGS" = "1" ]; then
        return
    fi

    _driver=$(docker info 2>/dev/null | grep 'Storage Driver' | awk '{print $3}' | awk -F- '{print $1}')
    if [ "$_driver" = "devicemapper" ] && docker info 2>/dev/null | grep -Fqs 'Data loop file:' ; then
        printf "${RED}The running Docker daemon is configured to use the 'devicemapper' storage driver \
in loopback mode.\nThis is not recommended for production use. Please see to the following URL for more \
information.\n\nhttps://help.replicated.com/docs/kb/developer-resources/devicemapper-warning/.${NC}\n\n\
"
        # HARD_FAIL_ON_LOOPBACK
        if [ -n "$1" ]; then
            printf "${RED}Please configure a recommended storage driver and try again.${NC}\n\n"
            exit 1
        fi

        printf "Do you want to proceed anyway? "
        if ! confirmN; then
            exit 0
        fi
    fi
}

docker_configure_proxy() {
    local previous_proxy=$(docker info 2>/dev/null | grep -i 'Http Proxy:' | awk '{ print $NF }')
    local previous_no_proxy=$(docker info 2>/dev/null | grep -i 'No Proxy:' | awk '{ print $NF }')
    if [ "$PROXY_ADDRESS" = "$previous_proxy" ] && [ "$NO_PROXY_ADDRESSES" = "$previous_no_proxy" ]; then
        return
    fi

    mkdir -p /etc/systemd/system/docker.service.d
    local file=/etc/systemd/system/docker.service.d/http-proxy.conf

    echo "# Generated by kURL" > $file
    echo "[Service]" >> $file

    if echo "$PROXY_ADDRESS" | grep -q "^https"; then
        echo "Environment=\"HTTPS_PROXY=${PROXY_ADDRESS}\" \"NO_PROXY=${NO_PROXY_ADDRESSES}\"" >> $file
    else
        echo "Environment=\"HTTP_PROXY=${PROXY_ADDRESS}\" \"NO_PROXY=${NO_PROXY_ADDRESSES}\"" >> $file
    fi

    restart_docker
}

function docker_get_host_packages_online() {
    local version="$1"

    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        echo "Fetching docker-${version}.tar.gz"
        curl -LO "$DIST_URL/docker-${version}.tar.gz"
        rm -rf $DIR/packages/docker/${version}                      # Cleanup broken/ incompatible packages from failed runs
        tar xf docker-${version}.tar.gz
        rm docker-${version}.tar.gz
    fi
}

function containerd_get_host_packages_online() {
    local version="$1"

    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        echo "Fetching containerd-${version}.tar.gz"
        curl -LO "$DIST_URL/containerd-${version}.tar.gz"
        rm -rf $DIR/packages/containerd/${version}                  # Cleanup broken/ incompatible packages from failed runs
        tar xf containerd-${version}.tar.gz
        rm containerd-${version}.tar.gz
    fi
}
