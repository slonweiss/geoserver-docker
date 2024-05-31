# Dockerfile
FROM ubuntu:24.04 as tomcat

ARG TOMCAT_VERSION=9.0.89
ARG CORS_ENABLED=true
ARG CORS_ALLOWED_ORIGINS=*
ARG CORS_ALLOWED_METHODS=GET,POST,PUT,DELETE,HEAD,OPTIONS
ARG CORS_ALLOWED_HEADERS=*
ARG CORS_ALLOW_CREDENTIALS=false

# Environment variables
ENV TOMCAT_VERSION=$TOMCAT_VERSION
ENV CATALINA_HOME=/opt/apache-tomcat-${TOMCAT_VERSION}
ENV EXTRA_JAVA_OPTS="-Xms128m -Xmx756m -XX:SoftRefLRUPolicyMSPerMB=36000 -XX:+UseParNewGC"
ENV CORS_ENABLED=$CORS_ENABLED
ENV CORS_ALLOWED_ORIGINS=$CORS_ALLOWED_ORIGINS
ENV CORS_ALLOWED_METHODS=$CORS_ALLOWED_METHODS
ENV CORS_ALLOWED_HEADERS=$CORS_ALLOWED_HEADERS
ENV CORS_ALLOW_CREDENTIALS=$CORS_ALLOW_CREDENTIALS
ENV DEBIAN_FRONTEND=noninteractive
ENV GEOSERVER_CSRF_DISABLED=true

# see https://docs.geoserver.org/stable/en/user/production/container.html
ENV CATALINA_OPTS="\$EXTRA_JAVA_OPTS \
    -Djava.awt.headless=true -server \
    -Dfile.encoding=UTF-8 \
    -Djavax.servlet.request.encoding=UTF-8 \
    -Djavax.servlet.response.encoding=UTF-8 \
    -Xbootclasspath/a:$CATALINA_HOME/lib/marlin.jar \
    -Dsun.java2d.renderer=sun.java2d.marlin.DMarlinRenderingEngine \
    -Dorg.geotools.coverage.jaiext.enabled=true"

# init
RUN apt update \
    && apt -y upgrade \
    && apt install -y --no-install-recommends openssl unzip gdal-bin wget curl openjdk-11-jdk gettext \
    && apt clean \
    && rm -rf /var/cache/apt/* \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/

RUN wget -q https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz \
    && tar xf apache-tomcat-${TOMCAT_VERSION}.tar.gz \
    && rm apache-tomcat-${TOMCAT_VERSION}.tar.gz \
    && rm -rf /opt/apache-tomcat-${TOMCAT_VERSION}/webapps/ROOT \
    && rm -rf /opt/apache-tomcat-${TOMCAT_VERSION}/webapps/docs \
    && rm -rf /opt/apache-tomcat-${TOMCAT_VERSION}/webapps/examples \
    && rm -rf /opt/apache-tomcat-${TOMCAT_VERSION}/webapps/host-manager \
    && rm -rf /opt/apache-tomcat-${TOMCAT_VERSION}/webapps/manager

# cleanup
RUN apt purge -y  \
    && apt autoremove --purge -y \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/*

FROM tomcat as download

ARG GS_VERSION=2.25.1
ARG GS_BUILD=release
ARG WAR_ZIP_URL=https://downloads.sourceforge.net/project/geoserver/GeoServer/${GS_VERSION}/geoserver-${GS_VERSION}-war.zip
ARG JDBC_CONFIG_URL=https://build.geoserver.org/geoserver/2.25.x/community-latest/geoserver-2.25-SNAPSHOT-jdbcconfig-plugin.zip
ARG JDBC_STORE_URL=https://build.geoserver.org/geoserver/main/community-latest/geoserver-2.26-SNAPSHOT-jdbcstore-plugin.zip
ENV GEOSERVER_VERSION=$GS_VERSION
ENV GEOSERVER_BUILD=$GS_BUILD

WORKDIR /tmp

RUN echo "Downloading GeoServer ${GS_VERSION} ${GS_BUILD}" \
    && wget -q -O /tmp/geoserver.zip $WAR_ZIP_URL

RUN echo "Unzipping GeoServer" \
    && unzip geoserver.zip geoserver.war -d /tmp/ \
    && unzip -q /tmp/geoserver.war -d /tmp/geoserver \
    && rm /tmp/geoserver.war

# RUN echo "Downloading JDBCConfig plugin" \
#     && wget -q -O /tmp/jdbcconfig.zip $JDBC_CONFIG_URL \
#     && echo "Unzipping JDBCConfig plugin" \
#     && unzip -q -o /tmp/jdbcconfig.zip -d /tmp/geoserver/WEB-INF/lib/ \
#     && rm /tmp/jdbcconfig.zip

RUN echo "Downloading JDBCStore plugin" \
    && wget -q -O /tmp/jdbcstore.zip $JDBC_STORE_URL \
    && echo "JDBCStore plugin downloaded to /tmp/jdbcstore.zip" \
    && ls -l /tmp/jdbcstore.zip \
    && echo "Unzipping JDBCStore plugin" \
    && unzip -q -o /tmp/jdbcstore.zip -d /tmp/geoserver/WEB-INF/lib/ \
    && rm /tmp/jdbcstore.zip

FROM tomcat as install

ARG GS_VERSION=2.25.1
ARG GS_BUILD=release
ARG STABLE_PLUGIN_URL=https://downloads.sourceforge.net/project/geoserver/GeoServer/${GS_VERSION}/extensions
ARG COMMUNITY_PLUGIN_URL=''

ARG GS_DATA_PATH=./geoserver_data/
ARG ADDITIONAL_LIBS_PATH=./additional_libs/
ARG ADDITIONAL_FONTS_PATH=./additional_fonts/

ENV GEOSERVER_VERSION=$GS_VERSION
ENV GEOSERVER_BUILD=$GS_BUILD
ENV GEOSERVER_DATA_DIR=/opt/geoserver_data/
ENV GEOSERVER_REQUIRE_FILE=$GEOSERVER_DATA_DIR/global.xml
ENV GEOSERVER_LIB_DIR=$CATALINA_HOME/webapps/geoserver/WEB-INF/lib/
ENV INSTALL_EXTENSIONS=true
ENV WAR_ZIP_URL=$WAR_ZIP_URL
ENV STABLE_EXTENSIONS=''
ENV STABLE_PLUGIN_URL=$STABLE_PLUGIN_URL
ENV COMMUNITY_EXTENSIONS=''
ENV COMMUNITY_PLUGIN_URL=$COMMUNITY_PLUGIN_URL
ENV ADDITIONAL_LIBS_DIR=/opt/additional_libs/
ENV ADDITIONAL_FONTS_DIR=/opt/additional_fonts/
ENV SKIP_DEMO_DATA=true
ENV ROOT_WEBAPP_REDIRECT=false
ENV POSTGRES_JNDI_ENABLED=false
ENV CONFIG_DIR=/opt/config
ENV CONFIG_OVERRIDES_DIR=/opt/config_overrides
ENV HEALTHCHECK_URL=http://localhost:8080/geoserver/web/wicket/resource/org.geoserver.web.GeoServerBasePage/img/logo.png

EXPOSE 8080

WORKDIR /tmp

RUN echo "Installing GeoServer $GS_VERSION $GS_BUILD"

COPY --from=download /tmp/geoserver $CATALINA_HOME/webapps/geoserver

RUN mv $CATALINA_HOME/webapps/geoserver/WEB-INF/lib/marlin-*.jar $CATALINA_HOME/lib/marlin.jar \
&& mkdir -p $GEOSERVER_DATA_DIR

RUN mv $CATALINA_HOME/webapps/geoserver/WEB-INF/lib/postgresql-*.jar $CATALINA_HOME/lib/

COPY $GS_DATA_PATH $GEOSERVER_DATA_DIR
COPY $ADDITIONAL_LIBS_PATH $GEOSERVER_LIB_DIR
COPY $ADDITIONAL_FONTS_PATH /usr/share/fonts/truetype/

# cleanup
RUN rm -rf /tmp/*

# Add default configs
COPY config $CONFIG_DIR

# Apply CIS Apache tomcat recommendations regarding server information
# * Alter the advertised server.info String (2.1 - 2.3)
RUN cd $CATALINA_HOME/lib \
    && jar xf catalina.jar org/apache/catalina/util/ServerInfo.properties \
    && sed -i 's/Apache Tomcat\/'"${TOMCAT_VERSION}"'/i_am_a_teapot/g' org/apache/catalina/util/ServerInfo.properties \
    && sed -i 's/'"${TOMCAT_VERSION}"'/x.y.z/g' org/apache/catalina/util/ServerInfo.properties \
    && sed -i 's/^server.built=.*/server.built=/g' org/apache/catalina/util/ServerInfo.properties \
    && jar uf catalina.jar org/apache/catalina/util/ServerInfo.properties \
    && rm -rf org/apache/catalina/util/ServerInfo.properties

# copy scripts
COPY *.sh /opt/

# CIS Docker benchmark: Remove setuid and setgid permissions in the images to prevent privilege escalation attacks within containers.
RUN find / -perm /6000 -type f -exec chmod a-s {} \; || true

# GeoServer user => restrict access to $CATALINA_HOME and GeoServer directories
# See also CIS Docker benchmark and docker best practices
RUN chmod +x /opt/*.sh

ENTRYPOINT ["/opt/startup.sh"]

WORKDIR /opt

HEALTHCHECK --interval=1m --timeout=20s --retries=3 \
  CMD curl --fail $HEALTHCHECK_URL || exit 1

# Add the install-extensions.sh script
COPY install-extensions.sh /opt/

# Run the script to install extensions
RUN chmod +x /opt/install-extensions.sh \
    && /opt/install-extensions.sh
