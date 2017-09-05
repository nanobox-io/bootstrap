#!/bin/bash
#
# Boostraps a CI server to run tests or deploy an app with Nanobox
#
# sudo bash -c "$(curl -fsSL https://s3.amazonaws.com/tools.nanobox.io/bootstrap/ci.sh)"

# run_as_root
run_as_root() {
  if [[ "$(whoami)" = "root" ]]; then
    eval "$1"
  else
    sudo bash -c "$1"
  fi
}

# run_as_user
run_as_user() {
  if [[ -n $SUDO_USER ]]; then
    su -c "$1" - $SUDO_USER
  else
    eval "$1"
  fi
}

docker_defaults() {
  echo 'DOCKER_OPTS="--iptables=false --storage-driver=aufs"'
}

# 1 - Install and run docker
# 2 - Download nanobox
# 3 - Chown nanobox
# 4 - Set Nanobox configuration

# 1 - Install Docker
#
# * For the time being this only supports an Ubuntu installation.
#   If there is reason to believe other linux distributions are commonly
#   used for CI/CD solutions, we can switch through them here

if [[ ! -f /usr/bin/docker ]]; then
  # add docker"s gpg key
  run_as_root "apt-key adv \
    --keyserver hkp://p80.pool.sks-keyservers.net:80 \
    --recv-keys 58118E89F3A912897C070ADBF76221572C52609D"

  # ensure lsb-release is installed
  which lsb_release || run_as_root "apt-get -y install lsb-release"

  release=$(lsb_release -cs)
  
  [ -f /usr/lib/apt/methods/https ] || run_as_root "apt-get -y install apt-transport-https"

  # add the source to our apt sources
  run_as_root "echo \
    \"deb https://apt.dockerproject.org/repo ubuntu-${release} main\" \
      > /etc/apt/sources.list.d/docker.list"

  # update the package index
  run_as_root "apt-get -y update"

  # ensure the old repo is purged
  run_as_root "apt-get -y purge lxc-docker docker-engine"

  # set docker defaults
  run_as_root "echo $(docker_defaults) > /etc/default/docker"

  # install docker
  run_as_root "apt-get \
      -y \
      -o Dpkg::Options::=\"--force-confdef\" \
      -o Dpkg::Options::=\"--force-confold\" \
      install \
      docker-engine=1.12.6-0~ubuntu-${release}"

  # allow user to use docker without sudo needs to be conditional
  run_as_root "groupadd docker"
  REAL_USER=${SUDO_USER:-$USER}
  run_as_root "usermod -aG docker $REAL_USER"
fi

# 2 - Download nanobox
run_as_root "curl \
  -f \
  -k \
  -o /usr/local/bin/nanobox \
  https://s3.amazonaws.com/tools.nanobox.io/nanobox/v2/linux/amd64/nanobox"

# 3 - Chown nanobox
run_as_root "chmod +x /usr/local/bin/nanobox"

# 4 - Set nanobox configuration
run_as_user "nanobox config set ci-mode true"

run_as_user "nanobox config set provider native"

echo "Nanobox is ready to go!"
