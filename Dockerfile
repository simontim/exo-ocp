# Dockerizing base image for eXo Platform hosting offer with:
#
# - eXo Platform
# - Libre Office
# - Oracle JAI (Java Advanced Imaging) API
# - Oracle JAI (Java Advanced Imaging) Image I/O Tools
# - Oracle JAI (Java Advanced Imaging) ICC Profiles

# Build:    docker build -t exoplatform/exo .
#
# Run:      docker run -ti --rm --name=exo -p 80:8080 exoplatform/exo
#           docker run -d --name=exo -p 80:8080 exoplatform/exo

FROM centos:centos7

MAINTAINER Roberto Cangiamila <roberto.cangiamila@par-tec.it>

ENV NUX_DESKTOP_RELEASE "http://li.nux.ro/download/nux/dextop/el7/x86_64/nux-dextop-release-0-5.el7.nux.noarch.rpm"

# Install the needed packages
RUN yum install -y epel-release
RUN yum install -y ${NUX_DESKTOP_RELEASE}

RUN INSTALL_PACKAGES="unzip wget vim-enhanced tzdata nano gettext nss_wrapper curl sed which less java-1.8.0-openjdk xmlstarlet jq libreoffice-calc libreoffice-draw libreoffice-impress libreoffice-math libreoffice-writer msttcore-fonts-installer" && \
    yum install -y --setopt=tsflags=nodocs $INSTALL_PACKAGES && \
    yum clean all && \
    rm -rf /var/cache/yum

# Check if the released binary was modified and make the build fail if it is the case
RUN wget -q -O /usr/bin/yaml https://github.com/mikefarah/yaml/releases/download/1.10/yaml_linux_amd64 && \
  echo "0e24302f71a14518dcc1bcdc6ff8d7da /usr/bin/yaml" | md5sum -c - \
  || { \
    echo "ERROR: the [/usr/bin/yaml] binary downloaded from a github release was modified while is should not !!"; \
    return 1; \
  } && chmod a+x /usr/bin/yaml

# Build Arguments and environment variables
ARG EXO_VERSION=5.0.0

# this allow to specify an eXo Platform download url
ARG DOWNLOAD_URL
# this allow to specifiy a user to download a protected binary
ARG DOWNLOAD_USER
# allow to override the list of addons to package by default
ARG ADDONS="exo-jdbc-driver-mysql:1.1.0, exo-chat:2.0.0"
# Default base directory on the plf archive
ARG ARCHIVE_BASE_DIR=platform-${EXO_VERSION}

ENV EXO_APP_DIR            /opt/exo
ENV EXO_CONF_DIR           /opt/exo/etc
ENV EXO_DATA_DIR           /opt/exo/data
ENV EXO_SHARED_DATA_DIR    /opt/exo/data/shared
ENV EXO_LOG_DIR            /opt/exo/logs
ENV EXO_TMP_DIR            /opt/exo/exo-tmp

ENV EXO_USER exo

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
# (we use 999 as uid like in official Docker images)
#RUN useradd --create-home -u 999 --user-group --shell /bin/bash ${EXO_USER}

# Install eXo Platform
RUN if [ -n "${DOWNLOAD_USER}" ]; then PARAMS="-u ${DOWNLOAD_USER}"; fi && \
    if [ ! -n "${DOWNLOAD_URL}" ]; then \
      echo "Building an image with eXo Platform version : ${EXO_VERSION}"; \
      EXO_VERSION_SHORT=$(echo ${EXO_VERSION} | awk -F "\." '{ print $1"."$2}'); \
      DOWNLOAD_URL="https://downloads.exoplatform.org/public/releases/platform/${EXO_VERSION_SHORT}/${EXO_VERSION}/platform-${EXO_VERSION}.zip"; \
    fi && \
    curl ${PARAMS} -L -o eXo-Platform-${EXO_VERSION}.zip ${DOWNLOAD_URL} && \
    unzip -q eXo-Platform-${EXO_VERSION}.zip -d /tmp/ && \
    rm -f eXo-Platform-${EXO_VERSION}.zip && \
    mv /tmp/${ARCHIVE_BASE_DIR} ${EXO_APP_DIR} && \
    mkdir -p ${EXO_DATA_DIR} && \ 
    mkdir -p ${EXO_TMP_DIR} && \
    ln -s ${EXO_APP_DIR}/gatein/conf ${EXO_CONF_DIR} && \
    useradd -m -u 1001 -g 0 -m -s /sbin/nologin -d ${EXO_APP_DIR} ${EXO_USER} && \
    cat /etc/passwd > /etc/passwd.template

COPY bin/ ${EXO_APP_DIR}/bin

# Install Docker customization file
RUN chmod 755 ${EXO_APP_DIR}/bin/setenv-docker-customize.sh && \
    chown ${EXO_USER}:0 ${EXO_APP_DIR}/bin/setenv-docker-customize.sh && \
    sed -i '/# Load custom settings/i \
\# Load custom settings for docker environment\n\
[ -r "$CATALINA_BASE/bin/setenv-docker-customize.sh" ] \
&& . "$CATALINA_BASE/bin/setenv-docker-customize.sh" \
|| echo "No Docker eXo Platform customization file : $CATALINA_BASE/bin/setenv-docker-customize.sh"\n\
' ${EXO_APP_DIR}/bin/setenv.sh && \
  grep 'setenv-docker-customize.sh' ${EXO_APP_DIR}/bin/setenv.sh

# Install JAI (Java Advanced Imaging) API in the JVM
# We don't install the shared library because the jvm complains about stack guard disabling
# && chmod 755 /tmp/jai-*/lib/*.so \
# && mv -v /tmp/jai-*/lib/*.so "${JAVA_HOME}/jre/lib/amd64/" \
RUN wget -q --no-cookies --no-check-certificate \
  --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" \
  -O "/tmp/jai.tar.gz" "http://download.oracle.com/otn-pub/java/jai/1.1.2_01-fcs/jai-1_1_2_01-lib-linux-i586.tar.gz" \
  && cd "/tmp" \
  && JAVA_HOME="$(dirname $(readlink $(readlink $(which java)))|sed 's/jre\/bin//g')" \
  && tar --no-same-owner -xvf "/tmp/jai.tar.gz" \
  && mv -v /tmp/jai-*/lib/jai_*.jar "$JAVA_HOME/jre/lib/ext/" \
  && mv -v /tmp/jai-*/*-jai.txt "$JAVA_HOME/" \
  && mv -v /tmp/jai-*/UNINSTALL-jai "$JAVA_HOME/" \
  && rm -rf /tmp/*

# Install JAI (Java Advanced Imaging) Image I/O Tools in the JVM
# We don't install the shared library because the jvm complains about stack guard disabling
# && chmod 755 /tmp/jai_imageio-*/lib/*.so \
# && mv /tmp/jai_imageio-*/lib/*.so "${JAVA_HOME}/jre/lib/amd64/" \
RUN wget -q --no-cookies --no-check-certificate \
  --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" \
  -O "/tmp/jai_imageio.tar.gz" "http://download.oracle.com/otn-pub/java/jai_imageio/1.0_01/jai_imageio-1_0_01-lib-linux-i586.tar.gz" \
  && cd "/tmp" \
  && JAVA_HOME="$(dirname $(readlink $(readlink $(which java)))|sed 's/jre\/bin//g')" \
  && tar --no-same-owner -xvf "/tmp/jai_imageio.tar.gz" \
  && mv -v /tmp/jai_imageio-*/lib/jai_*.jar "$JAVA_HOME/jre/lib/ext/" \
  && mv -v /tmp/jai_imageio-*/*-jai_imageio.txt "$JAVA_HOME/" \
  && mv -v /tmp/jai_imageio-*/UNINSTALL-jai_imageio "$JAVA_HOME/" \
  && rm -rf /tmp/*

# Install JAI (Java Advanced Imaging) ICC Profiles in the JVM
RUN wget -q --no-cookies --no-check-certificate \
  --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" \
  -O "/tmp/jai_ccm.tar.gz" "http://download.oracle.com/otn-pub/java/jai_jaicmm/1.0/JAICMM.tar.gz" \
  && cd "/tmp" \
  && JAVA_HOME="$(dirname $(readlink $(readlink $(which java)))|sed 's/jre\/bin//g')" \
  && tar --no-same-owner -xvf "/tmp/jai_ccm.tar.gz" \
  && mv -v /tmp/*.pf "$JAVA_HOME/jre/lib/cmm/" \
  && rm -rf /tmp/*

RUN for a in ${ADDONS}; do echo "Installing addon $a"; /opt/exo/addon install $a; done

RUN chmod -R a+rwx ${EXO_APP_DIR} && \ 
    chown -R exo:0 ${EXO_APP_DIR} && \
    chmod -R g=u /etc/passwd

ENV PATH=$PATH:${EXO_APP_DIR}/bin

USER 1001

WORKDIR ${EXO_APP_DIR}

VOLUME ${EXO_APP_DIR}/data

ENTRYPOINT [ "run_exo" ]
