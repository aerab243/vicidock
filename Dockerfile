# syntax=docker/dockerfile:1
# Vicidock — image all-in-one VICIdial (calquée sur ViciBox 12.0.2).
# Un tag d'image = une version de VICIdial (build-arg VICIDIAL_SVN_REV).
ARG ALMA_RELEASE=9
ARG VICIDIAL_SVN_REV=HEAD
ARG ASTERISK_TARBALL=asterisk-18.21.0-vici.tar.gz

# ---------------- builder : DAHDI + Asterisk ----------------
FROM almalinux:${ALMA_RELEASE} AS builder
ARG ASTERISK_TARBALL
RUN dnf -y install epel-release && \
    dnf -y groupinstall "Development Tools" && \
    dnf -y install kernel-devel kernel-headers wget tar bzip2 unzip patch perl \
        newt-devel libxml2-devel sqlite-devel libuuid-devel readline-devel \
        openssl-devel alsa-lib-devel libogg-devel libvorbis-devel curl-devel && \
    dnf clean all && rm -rf /var/cache/dnf
WORKDIR /usr/src
RUN wget -q https://digip.org/jansson/releases/jansson-2.13.tar.gz && \
    tar xzf jansson-2.13.tar.gz && cd jansson-2.13 && \
    ./configure --prefix=/usr && make -j$(nproc) && make install && ldconfig && cd ..
RUN wget -q http://downloads.sourceforge.net/project/lame/lame/3.99/lame-3.99.5.tar.gz && \
    tar xzf lame-3.99.5.tar.gz && cd lame-3.99.5 && \
    ./configure --prefix=/usr && make -j$(nproc) && make install && ldconfig && cd ..
RUN wget -q https://github.com/cisco/libsrtp/archive/v2.1.0.tar.gz && \
    tar xzf v2.1.0.tar.gz && cd libsrtp-2.1.0 && \
    ./configure --prefix=/usr --enable-openssl && make shared_library && make install && ldconfig && cd ..
RUN wget -q https://downloads.asterisk.org/pub/telephony/libpri/libpri-1.6.1.tar.gz && \
    tar xzf libpri-1.6.1.tar.gz && cd libpri-1.6.1 && \
    make -j$(nproc) && make install && ldconfig && cd ..
RUN wget -q https://downloads.asterisk.org/pub/telephony/dahdi-linux-complete/dahdi-linux-complete-3.4.0+3.4.0.tar.gz && \
    tar xzf dahdi-linux-complete-3.4.0+3.4.0.tar.gz && cd dahdi-linux-complete-3.4.0+3.4.0 && \
    wget -q https://cybur-dial.com/dahdi-9.5-fix.zip && unzip -o dahdi-9.5-fix.zip && \
    make -j$(nproc) && make install && make config && cd ..
RUN mkdir -p asterisk && cd asterisk && \
    wget -q https://download.vicidial.com/required-apps/${ASTERISK_TARBALL} && \
    tar xzf ${ASTERISK_TARBALL} && cd asterisk-18*/ && \
    ./configure --libdir=/usr/lib64 --with-gsm=internal --enable-opus --enable-srtp \
        --with-ssl --enable-asteriskssl --with-pjproject-bundled --with-jansson-bundled && \
    make menuselect/menuselect menuselect-tree menuselect.makeopts && \
    menuselect/menuselect --enable app_meetme menuselect.makeopts && \
    menuselect/menuselect --enable res_http_websocket menuselect.makeopts && \
    menuselect/menuselect --enable res_srtp menuselect.makeopts && \
    make samples && \
    sed -i 's|noload = chan_sip.so|;noload = chan_sip.so|g' /etc/asterisk/modules.conf || true && \
    make -j$(nproc) && make install && make config && ldconfig
RUN wget -q http://download.vicidial.com/required-apps/asterisk-perl-0.08.tar.gz && \
    tar xzf asterisk-perl-0.08.tar.gz && cd asterisk-perl-0.08 && \
    perl Makefile.PL && make -j$(nproc) && make install && cd ..

# ---------------- runtime : MariaDB + Apache/PHP + VICIdial ----------------
FROM almalinux:${ALMA_RELEASE}
ARG VICIDIAL_SVN_REV
ENV VICIDIAL_SVN_REV=${VICIDIAL_SVN_REV}
RUN dnf -y install epel-release https://rpms.remirepo.net/enterprise/remi-release-9.rpm && \
    dnf module reset -y php mariadb || true && \
    (dnf module enable -y mariadb:10.11 || dnf module enable -y mariadb:10.5) && \
    dnf module enable -y php:remi-8.2 && \
    dnf -y install mariadb-server httpd mod_ssl supervisor subversion screen \
        cronie sox lame wget tar unzip \
        perl perl-DBI perl-DBD-MySQL perl-libwww-perl \
        php php-cli php-gd php-curl php-mysqli php-ldap php-zip php-fileinfo \
        php-opcache php-mbstring php-imap php-xml php-soap php-intl php-bcmath && \
    dnf clean all && rm -rf /var/cache/dnf
COPY --from=builder /usr/lib64/asterisk /usr/lib64/asterisk
COPY --from=builder /usr/lib/asterisk /usr/lib/asterisk
COPY --from=builder /usr/sbin/asterisk /usr/sbin/asterisk
COPY --from=builder /usr/sbin/dahdi_cfg /usr/sbin/dahdi_cfg
COPY --from=builder /etc/asterisk /etc/asterisk
COPY --from=builder /etc/dahdi /etc/dahdi
COPY --from=builder /var/lib/asterisk /var/lib/asterisk
COPY --from=builder /usr/include/asterisk /usr/include/asterisk
COPY --from=builder /lib/modules /lib/modules
RUN ldconfig && asterisk -V
RUN svn checkout -r ${VICIDIAL_SVN_REV} svn://svn.eflo.net/agc_2-X/trunk /usr/src/astguiclient/trunk && \
    mkdir -p /var/www/html /usr/share/astguiclient /var/spool/asterisk/monitor /var/log/astguiclient && \
    cp -a /usr/src/astguiclient/trunk/www/. /var/www/html/ && \
    cp -a /usr/src/astguiclient/trunk/bin/. /usr/share/astguiclient/ && \
    chown -R apache:apache /var/www/html
RUN cd /var/lib/asterisk/sounds && \
    wget -q https://downloads.asterisk.org/pub/telephony/sounds/asterisk-core-sounds-en-ulaw-current.tar.gz && \
    tar xzf asterisk-core-sounds-en-ulaw-current.tar.gz && rm -f *.tar.gz
COPY docker/supervisord.conf /etc/supervisord.conf
COPY docker/entrypoint.sh docker/vicidial-run.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/vicidial-run.sh
EXPOSE 80 443 5060/tcp 5060/udp 10000-20000/udp
VOLUME ["/var/lib/mysql", "/var/spool/asterisk/monitor"]
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
