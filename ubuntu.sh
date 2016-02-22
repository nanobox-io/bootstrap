#!/bin/bash

ubuntu_version() {
  lsb_release -sd \
    | awk '{print $2}' \
      | awk -F. '{print $1"."$2}'
}

init_system() {
  if [[ -f /sbin/systemctl ]]; then
    echo "systemd"
  elif [[ -f /sbin/initctl ]]; then
    echo "upstart"
  else
    echo "sysvinit"
  fi
}

install_docker() {
  # install docker if not already installed
  if [[ ! -f /usr/bin/docker ]]; then
    # add docker's gpg key
    apt-key adv \
      --keyserver hkp://p80.pool.sks-keyservers.net:80 \
      --recv-keys 58118E89F3A912897C070ADBF76221572C52609D

    # add the source to our apt sources
    echo \
      "deb https://apt.dockerproject.org/repo ubuntu-trusty main \n" \
        > /etc/apt/sources.list.d/docker.list

    # update the package index
    apt-get -y update

    # ensure the old repo is purged
    apt-get -y purge lxc-docker

    # install docker
    apt-get -y install docker-engine
  fi
}

start_docker() {
  if [[ ! `service docker status | grep start/running` ]]; then
    # start the docker daemon
    service docker start

    # wait for the docker sock file
    while [ ! -S /var/run/docker.sock ]; do
      sleep 1
    done
  fi
}

install_red() {
  if [[ ! -f /usr/bin/red ]]; then
    # fetch packages
    wget -O /tmp/libbframe_1.0.0-1_amd64.deb https://s3.amazonaws.com/nanopack.nanobox.io/deb/libbframe_1.0.0-1_amd64.deb
    wget -O /tmp/libmsgxchng_1.0.0-1_amd64.deb https://s3.amazonaws.com/nanopack.nanobox.io/deb/libmsgxchng_1.0.0-1_amd64.deb
    wget -O /tmp/red_1.0.0-1_amd64.deb https://s3.amazonaws.com/nanopack.nanobox.io/deb/red_1.0.0-1_amd64.deb
    wget -O /tmp/redd_1.0.0-1_amd64.deb https://s3.amazonaws.com/nanopack.nanobox.io/deb/redd_1.0.0-1_amd64.deb

    # update apt
    apt-get -y update

    # install dependencies
    apt-get -y install libmsgpack3 libuv0.10

    # install packages
    dpkg -i /tmp/libbframe_1.0.0-1_amd64.deb
    dpkg -i /tmp/libmsgxchng_1.0.0-1_amd64.deb
    dpkg -i /tmp/red_1.0.0-1_amd64.deb
    dpkg -i /tmp/redd_1.0.0-1_amd64.deb

    # configure redd
    echo "$(redd_conf)" > /etc/redd.conf

    # ensure the redd db path exists
    mkdir -p /var/db/redd

    # create init entry
    if [[ "$(init_system)" = "systemd" ]]; then
      todo
    elif [[ "$(init_system)" = "upstart" ]]; then
      echo "$(redd_upstart_conf)" > /etc/init/redd.conf
    fi

    # remove cruft
    rm -f /tmp/libbframe_1.0.0-1_amd64.deb
    rm -f /tmp/libmsgxchng_1.0.0-1_amd64.deb
    rm -f /tmp/red_1.0.0-1_amd64.deb
    rm -f /tmp/redd_1.0.0-1_amd64.deb
  fi
}

start_redd() {
  if [[ ! `service redd status | grep start/running` ]]; then
    # start the redd daemon
    service redd start

    # wait for the docker sock file
    while [ ! `red ping | grep pong` ]; do
      sleep 1
    done
  fi
}

install_bridgeutils() {
  if [[ ! -f /sbin/brctl ]]; then
    apt-get install -y bridge-utils
  fi
}

create_docker_network() {
  if [[ ! `docker network ls | grep nanobox` ]]; then
    # create a docker network
    docker network create \
      --driver=bridge --subnet=192.168.0.0/16 \
      --opt="com.docker.network.driver.mtu=1450" \
      --opt="com.docker.network.bridge.name=redd0" \
      --gateway=192.168.0.55 \
      nanobox
  fi
}

create_vxlan_bridge() {
  if [[ "$(init_system)" = "systemd" ]]; then
    todo
  elif [[ "$(init_system)" = "upstart" ]]; then
    echo "$(vxlan_upstart_conf)" > /etc/init/vxlan.conf
  fi
}

start_vxlan_bridge() {
  if [[ ! `service vxlan status | grep start/running` ]]; then
    # start the redd daemon
    service vxlan start
  fi
}

redd_conf() {
  cat <<-END
daemonize no
pidfile /var/run/redd.pid
logfile /var/log/redd.log
loglevel warning
port 4470
timeout 0

routing-enabled yes

bind 127.0.0.1
udp-listen-address 127.0.0.1
save-path /var/db/redd
END
}

redd_upstart_conf() {
  cat <<-END
description "Red vxlan daemon"

start on (filesystem and net-device-up IFACE!=lo)
stop on runlevel [!2345]

respawn

kill timeout 20

exec redd /etc/redd.conf

END
}

vxlan_upstart_conf() {
  cat <<-END
description "Red vxlan to docker bridge"

start on runlevel [2345]

pre-start script
  # wait for redd0
  while [ ! \`/sbin/ifconfig | /bin/grep redd0\` ]; do
    sleep 1
  done

  # wait for vxlan0
  while [ ! \`/sbin/ifconfig | /bin/grep vxlan0\` ]; do
    sleep 1
  done
end script

script
  if [ ! \`/sbin/brctl show | /bin/grep redd0 | /bin/grep vxlan0\` ]; then
    # bridge the network onto the red vxlan
    /sbin/brctl addif redd0 vxlan0
  fi
end script

END
}

init_nanoagent() {
  echo
}

init_firewall() {
  echo
}

run() {
  echo "+> $2"
  ($1 2>&1) |  sed -e 's/\r//g;s/^/   /'
}

run install_docker "Installing docker"
run start_docker "Starting docker daemon"

run install_red "Installing red"
run start_redd "Starting red daemon"

run install_bridgeutils "Installing ethernet bridging utilities"
run create_docker_network "Creating isolated docker network"
run create_vxlan_bridge "Creating red vxlan bridge"
run start_vxlan_bridge "Starting red vxlan bridge"



# init_nanoagent
# init_firewall
