# syntax=docker/dockerfile:1
# Vicidock — image all-in-one VICIdial (calquée sur ViciBox 12.0.2).
# Un tag d'image = une version de VICIdial (build-arg VICIDIAL_SVN_REV).
# Note : pas de modules kernel DAHDI ici — impossibles à compiler portablement
# en conteneur (kernel de l'hôte ≠ headers du conteneur). Le timing passe par
# timerfd via ConfBridge (moteur moderne de VICIdial, remplace MeetMe).
ARG ALMA_RELEASE=9
ARG VICIDIAL_SVN_REV=3939
ARG ASTERISK_TARBALL=asterisk-18.21.0-vici.tar.gz
ARG ASTERISK_SHA256=cadf952504cdf924cdbaa3c636cabb997b9a3a521b6d3459df35c39507103bdc
ARG JANSSON_SHA256=02c31bc16e702b30feb06d18bbfe086c0d8c938e906950980af7adcdb324541b
ARG LAME_SHA256=24346b4158e4af3bd9f2e194bb23eb473c75fb7377011523353196b19b9a23ff
ARG LIBSRTP_SHA256=0302442ed97d34a77abf84617b657e77674bdd8e789d649f1cac0c5f0d0cf5ee
ARG ASTPERL_SHA256=9be1c49c5f5519d90a8937ffef32bbde5c2ff9f565fc2f5f219afcef43ac2fa2

# ---------------- builder : libs + Asterisk ----------------
FROM almalinux:${ALMA_RELEASE} AS builder
ARG ASTERISK_TARBALL
ARG ASTERISK_SHA256
ARG JANSSON_SHA256
ARG LAME_SHA256
ARG LIBSRTP_SHA256
ARG ASTPERL_SHA256
RUN dnf -y install epel-release dnf-plugins-core && \
    dnf config-manager --set-enabled crb && \
    dnf -y groupinstall "Development Tools" && \
    dnf -y install wget tar bzip2 unzip patch perl \
        newt-devel libxml2-devel sqlite-devel libuuid-devel readline-devel \
        openssl-devel alsa-lib-devel libogg-devel libvorbis-devel curl-devel libedit-devel \
        opus-devel speex-devel && \
    dnf clean all && rm -rf /var/cache/dnf
WORKDIR /usr/src
RUN wget -q https://digip.org/jansson/releases/jansson-2.13.tar.gz -O jansson.tar.gz && \
    echo "${JANSSON_SHA256}  jansson.tar.gz" | sha256sum -c - && \
    tar xzf jansson.tar.gz && cd jansson-2.13 && \
    ./configure --prefix=/usr && make -j$(nproc) && make install && ldconfig && cd ..
RUN wget -q "http://downloads.sourceforge.net/project/lame/lame/3.99/lame-3.99.5.tar.gz" -O lame.tar.gz && \
    echo "${LAME_SHA256}  lame.tar.gz" | sha256sum -c - && \
    tar xzf lame.tar.gz && cd lame-3.99.5 && \
    ./configure --prefix=/usr && make -j$(nproc) && make install && ldconfig && cd ..
RUN wget -q https://github.com/cisco/libsrtp/archive/v2.1.0.tar.gz -O libsrtp.tar.gz && \
    echo "${LIBSRTP_SHA256}  libsrtp.tar.gz" | sha256sum -c - && \
    tar xzf libsrtp.tar.gz && cd libsrtp-2.1.0 && \
    ./configure --prefix=/usr --enable-openssl && make shared_library && make install && ldconfig && cd ..
RUN mkdir -p asterisk && cd asterisk && \
    wget -q https://download.vicidial.com/required-apps/${ASTERISK_TARBALL} -O asterisk.tar.gz && \
    echo "${ASTERISK_SHA256}  asterisk.tar.gz" | sha256sum -c - && \
    tar xzf asterisk.tar.gz && cd asterisk-18*/ && \
    ./configure --prefix=/usr --libdir=/usr/lib64 --sysconfdir=/etc --localstatedir=/var \
        --with-gsm=internal --with-ssl --enable-asteriskssl --with-pjproject-bundled --with-jansson-bundled && \
    make menuselect/menuselect menuselect-tree menuselect.makeopts && \
    menuselect/menuselect --enable res_http_websocket menuselect.makeopts && \
    menuselect/menuselect --enable res_srtp menuselect.makeopts && \
    make -j$(nproc) && make install && make install-headers && make samples && \
    sed -i 's|noload = chan_sip.so|;noload = chan_sip.so|g' /etc/asterisk/modules.conf || true && \
    ldconfig && test -x /usr/sbin/asterisk && test -d /usr/include/asterisk && test -f /etc/asterisk/modules.conf
# Dépendances partagées du binaire (détectées via ldd) + celles des modules
# chargés dynamiquement (pjproject/srtp/jansson/ogg) : recopiées avec leurs
# chemins pour l'image runtime qui ne les a pas.
RUN stage_lib() { \
        dest="/ast-deps$1"; \
        case "$dest" in \
            /ast-deps/lib64/*) dest="/ast-deps/usr/lib64/${dest#/ast-deps/lib64/}";; \
            /ast-deps/lib/*) dest="/ast-deps/usr/lib/${dest#/ast-deps/lib/}";; \
        esac; \
        mkdir -p "$(dirname "$dest")" && cp -L "$1" "$dest"; \
    }; \
    mkdir -p /ast-deps && \
    ldd /usr/sbin/asterisk | awk '/=> \//{print $3}' | while read -r lib; do \
        stage_lib "$lib"; \
    done && \
    for pat in '/usr/lib/libpj*.so*' '/usr/lib64/libpj*.so*' \
               '/usr/lib/libsrtp*.so*' '/usr/lib64/libsrtp*.so*' \
               '/usr/lib/libjansson*.so*' '/usr/lib64/libjansson*.so*' \
               '/usr/lib/libogg*.so*' '/usr/lib64/libogg*.so*' \
               '/usr/lib/libvorbis*.so*' '/usr/lib64/libvorbis*.so*'; do \
        for f in $pat; do \
            [ -e "$f" ] || continue; \
            stage_lib "$f"; \
        done; \
    done && find /ast-deps -name '*.so*' | sort
RUN wget -q http://download.vicidial.com/required-apps/asterisk-perl-0.08.tar.gz -O astperl.tar.gz && \
    echo "${ASTPERL_SHA256}  astperl.tar.gz" | sha256sum -c - && \
    tar xzf astperl.tar.gz && cd asterisk-perl-0.08 && \
    perl Makefile.PL && make -j$(nproc) && make install && cd ..

# ---------------- perldeps : modules CPAN manquants/cassés en RPM ----------------
# EPEL9 ne fournit pas (ou avec dépendances cassées) : IO::Stringy,
# OLE::Storage_Lite, Spreadsheet::*, HTML::Tree/Strip/Formatter,
# Crypt::Eksblowfish. Construits ici (compilateur dispo), copiés ensuite.
FROM almalinux:${ALMA_RELEASE} AS perldeps
RUN dnf -y install epel-release && \
    dnf -y install perl perl-devel perl-App-cpanminus gcc make && \
    dnf clean all && rm -rf /var/cache/dnf
RUN cpanm -n -L /opt/perl5 \
        IO::Stringy OLE::Storage_Lite \
        Spreadsheet::ParseExcel Spreadsheet::WriteExcel Spreadsheet::XLSX Spreadsheet::Read \
        HTML::Tree HTML::Strip HTML::Formatter \
        Crypt::Eksblowfish::Bcrypt && \
    rm -rf /root/.cpanm /tmp/p5-build 2>/dev/null || true

# ---------------- runtime : MariaDB + Apache/PHP + VICIdial ----------------
FROM almalinux:${ALMA_RELEASE}
ARG VICIDIAL_SVN_REV
ENV VICIDIAL_SVN_REV=${VICIDIAL_SVN_REV}
ENV PERL5LIB=/opt/perl5/lib/perl5
RUN dnf -y install epel-release https://rpms.remirepo.net/enterprise/remi-release-9.rpm && \
    dnf module reset -y php mariadb || true && \
    (dnf module enable -y mariadb:10.11 || dnf module enable -y mariadb:10.5) && \
    dnf module enable -y php:remi-8.2 && \
    dnf -y install mariadb-server httpd mod_ssl openssl supervisor subversion screen \
        cronie sox lame wget tar unzip sendmail tzdata procps-ng sqlite \
        perl perl-DBI perl-DBD-MySQL perl-libwww-perl \
        perl-CPAN perl-YAML perl-GD perl-Env perl-Term-ReadLine-Gnu perl-SelfLoader perl-open \
        perl-Net-Telnet perl-Proc-ProcessTable perl-Net-Server \
        perl-Mail-Sendmail perl-Mail-POP3Client perl-Mail-IMAPClient \
        perl-Curses perl-TermReadKey perl-Unicode-Map perl-IO-Socket-SSL perl-Text-CSV \
        perl-HTML-Parser perl-HTML-Tagset perl-MIME-tools perl-Digest-SHA1 \
        perl-Digest-HMAC perl-Net-SSLeay perl-LWP-Protocol-https \
        opus speex \
        php php-cli php-fpm php-gd php-curl php-mysqli php-ldap php-zip php-fileinfo \
        php-opcache php-mbstring php-imap php-xml php-soap php-intl php-bcmath && \
    dnf clean all && rm -rf /var/cache/dnf
COPY --from=perldeps /opt/perl5 /opt/perl5
COPY --from=builder /ast-deps/ /
COPY --from=builder /usr/lib64/asterisk /usr/lib64/asterisk
COPY --from=builder /usr/sbin/asterisk /usr/sbin/asterisk
COPY --from=builder /etc/asterisk /etc/asterisk
COPY --from=builder /var/lib/asterisk /var/lib/asterisk
COPY --from=builder /usr/include/asterisk /usr/include/asterisk
RUN ldconfig && asterisk -V
RUN svn checkout -r ${VICIDIAL_SVN_REV} svn://svn.eflo.net/agc_2-X/trunk /usr/src/astguiclient/trunk && \
    mkdir -p /var/www/html /usr/share/astguiclient /var/spool/asterisk/monitor /var/log/astguiclient && \
    cp -a /usr/src/astguiclient/trunk/www/. /var/www/html/ && \
    cp -a /usr/src/astguiclient/trunk/bin/. /usr/share/astguiclient/ && \
    chown -R apache:apache /var/www/html
RUN cd /var/lib/asterisk/sounds && \
    for s in asterisk-core-sounds-en-ulaw asterisk-extra-sounds-en-ulaw asterisk-moh-opsound-ulaw; do \
        wget -q "https://downloads.asterisk.org/pub/telephony/sounds/${s}-current.tar.gz" && \
        tar xzf "${s}-current.tar.gz"; \
    done && rm -f *.tar.gz && test -f ulaw-followme.ulaw -o -f hello-world.ulaw
COPY docker/supervisord.conf /etc/supervisord.conf
COPY docker/vicidial-crontab /usr/local/share/vicidock/vicidial-crontab
COPY docker/vicidock-php.ini /etc/php.d/50-vicidock.ini
COPY docker/vicidock-mysql.cnf /etc/my.cnf.d/vicidock.cnf
COPY docker/healthcheck.php /var/www/html/healthcheck.php
# php-fpm nettoie l'environnement par défaut (clear_env=yes) : les workers
# ne verraient ni MYSQL_CRON_PASSWORD ni les autres secrets du conteneur.
RUN sed -i 's/^;*clear_env = .*/clear_env = no/' /etc/php-fpm.d/www.conf && \
    grep -q '^clear_env = no' /etc/php-fpm.d/www.conf
COPY docker/entrypoint.sh /usr/local/bin/
COPY docker/vicidial-perl.sh /usr/local/bin/
COPY docker/vicidock-apache.conf /etc/httpd/conf.d/00-vicidock.conf
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/vicidial-perl.sh
# Pas de page d'accueil AlmaLinux : la racine redirige vers VICIdial.
RUN rm -f /etc/httpd/conf.d/welcome.conf
EXPOSE 80 443 5060/tcp 5060/udp 10000-15000/udp
VOLUME ["/var/lib/mysql", "/var/spool/asterisk/monitor"]
# wget, pas curl : curl n'est pas installé dans l'image (conflit curl-minimal).
HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=3 \
    CMD wget -q -O /dev/null http://localhost/healthcheck.php || exit 1
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
