#!/bin/bash
echo "Welcome to GeoServer $GEOSERVER_VERSION"

# Create directories and write properties files
mkdir -p /opt/geoserver_data/jdbcconfig /opt/geoserver_data/jdbcstore

cat <<EOF > /opt/geoserver_data/jdbcconfig/jdbcconfig.properties
#Wed May 22 18:22:58 GMT 2024
initdb=false
pool.timeBetweenEvictionRunsMillis=15000
import=false
pool.poolPreparedStatements=true
pool.testWhileIdle=true
pool.validationQuery=SELECT now()
pool.minIdle=4
enabled=true
pool.maxOpenPreparedStatements=50
password=${DB_PASSWORD}
jdbcUrl=jdbc:postgresql://${DB_HOST}\:5432/${DB_NAME_JDBCCONFIG}
driverClassName=org.postgresql.Driver
pool.maxActive=10
initScript=jdbcconfig/scripts/initdb.postgres.sql
debugMode=false
pool.testOnBorrow=false
username=${DB_USER}
repopulate=false
EOF

cat <<EOF > /opt/geoserver_data/jdbcstore/jdbcstore.properties
#Wed May 22 18:22:48 GMT 2024
initdb=false
pool.timeBetweenEvictionRunsMillis=15000
deleteDestinationOnRename=true
import=false
pool.poolPreparedStatements=true
pool.testWhileIdle=true
pool.validationQuery=SELECT now()
pool.minIdle=4
ignoreDirs=data,jdbcstore,jdbcconfig,temp,tmp,logs
enabled=true
pool.maxOpenPreparedStatements=50
password=${DB_PASSWORD}
jdbcUrl=jdbc:postgresql://${DB_HOST}\:5432/${DB_NAME_JDBCSTORE}
driverClassName=org.postgresql.Driver
pool.maxActive=10
initScript=jdbcstore/scripts/init.postgres.sql
pool.testOnBorrow=false
username=${DB_USER}
EOF

# Create logging.xml with specified content
cat <<EOF > /opt/geoserver_data/logging.xml
<logging>
  <level>DEFAULT_LOGGING.properties</level>
  <location>logs/geoserver.log</location>
  <stdOutLogging>true</stdOutLogging>
</logging>
EOF

# function that can be used to copy a custom config file to the catalina conf dir
function copy_custom_config() {
  CONFIG_FILE=$1
  # Use a custom "${CONFIG_FILE}" if the user mounted one into the container
  if [ -d "${CONFIG_OVERRIDES_DIR}" ] && [ -f "${CONFIG_OVERRIDES_DIR}/${CONFIG_FILE}" ]; then
    echo "Installing configuration override for ${CONFIG_FILE} with substituted environment variables"
    envsubst < "${CONFIG_OVERRIDES_DIR}"/"${CONFIG_FILE}" > "${CATALINA_HOME}/conf/${CONFIG_FILE}"
  else
    # Otherwise use the default
    echo "Installing default ${CONFIG_FILE} with substituted environment variables"
    envsubst < "${CONFIG_DIR}"/"${CONFIG_FILE}" > "${CATALINA_HOME}/conf/${CONFIG_FILE}"
  fi
}


## Skip demo data
if [ "${SKIP_DEMO_DATA}" = "true" ]; then
  unset GEOSERVER_REQUIRE_FILE
fi

## Add a permanent redirect (HTTP 301) from the root webapp ("/") to geoserver web interface ("/geoserver/web")
if [ "${ROOT_WEBAPP_REDIRECT}" = "true" ]; then
  if [ ! -d $CATALINA_HOME/webapps/ROOT ]; then
      mkdir $CATALINA_HOME/webapps/ROOT
  fi

  cat > $CATALINA_HOME/webapps/ROOT/index.jsp << EOF
<%
  final String redirectURL = "/geoserver/web/";
  response.setStatus(HttpServletResponse.SC_MOVED_PERMANENTLY);
  response.setHeader("Location", redirectURL);
%>
EOF
fi

## install release data directory if needed before starting tomcat
if [ ! -z "$GEOSERVER_REQUIRE_FILE" ] && [ ! -f "$GEOSERVER_REQUIRE_FILE" ]; then
  echo "Initialize $GEOSERVER_DATA_DIR from data directory included in geoserver.war"
  cp -r $CATALINA_HOME/webapps/geoserver/data/* $GEOSERVER_DATA_DIR
fi

## install GeoServer extensions before starting the tomcat
/opt/install-extensions.sh

# copy additional geoserver libs before starting the tomcat
# we also count whether at least one file with the extensions exists
count=`ls -1 $ADDITIONAL_LIBS_DIR/*.jar 2>/dev/null | wc -l`
if [ -d "$ADDITIONAL_LIBS_DIR" ] && [ $count != 0 ]; then
    cp $ADDITIONAL_LIBS_DIR/*.jar $CATALINA_HOME/webapps/geoserver/WEB-INF/lib/
    echo "Installed $count JAR extension file(s) from the additional libs folder"
fi

# copy additional fonts before starting the tomcat
# we also count whether at least one file with the fonts exists
count=`ls -1 $ADDITIONAL_FONTS_DIR/*.ttf 2>/dev/null | wc -l`
if [ -d "$ADDITIONAL_FONTS_DIR" ] && [ $count != 0 ]; then
    cp $ADDITIONAL_FONTS_DIR/*.ttf /usr/share/fonts/truetype/
    echo "Installed $count TTF font file(s) from the additional fonts folder"
fi

# configure CORS (inspired by https://github.com/oscarfonts/docker-geoserver)
# if enabled, this will add the filter definitions
# to the end of the web.xml
# (this will only happen if our filter has not yet been added before)
if [ "${CORS_ENABLED}" = "true" ]; then
  if ! grep -q DockerGeoServerCorsFilter "$CATALINA_HOME/webapps/geoserver/WEB-INF/web.xml"; then
    echo "Enable CORS for $CATALINA_HOME/webapps/geoserver/WEB-INF/web.xml"

    # Add support for access-control-allow-credentials when the origin is not a wildcard when specified via env var
    if [ "${CORS_ALLOWED_ORIGINS}" != "*" ] && [ "${CORS_ALLOW_CREDENTIALS}" = "true" ]; then
      CORS_ALLOW_CREDENTIALS="true"
    else
      CORS_ALLOW_CREDENTIALS="false"
    fi

    sed -i "\:</web-app>:i\\
    <filter>\n\
      <filter-name>DockerGeoServerCorsFilter</filter-name>\n\
      <filter-class>org.apache.catalina.filters.CorsFilter</filter-class>\n\
      <init-param>\n\
          <param-name>cors.allowed.origins</param-name>\n\
          <param-value>${CORS_ALLOWED_ORIGINS}</param-value>\n\
      </init-param>\n\
      <init-param>\n\
          <param-name>cors.allowed.methods</param-name>\n\
          <param-value>${CORS_ALLOWED_METHODS}</param-value>\n\
      </init-param>\n\
      <init-param>\n\
        <param-name>cors.allowed.headers</param-name>\n\
        <param-value>${CORS_ALLOWED_HEADERS}</param-value>\n\
      </init-param>\n\
      <init-param>\n\
        <param-name>cors.support.credentials</param-name>\n\
        <param-value>${CORS_ALLOW_CREDENTIALS}</param-value>\n\
      </init-param>\n\
    </filter>\n\
    <filter-mapping>\n\
      <filter-name>DockerGeoServerCorsFilter</filter-name>\n\
      <url-pattern>/*</url-pattern>\n\
    </filter-mapping>\n\
    <context-param>\n\
      <param-name>GEOSERVER_CSRF_DISABLED</param-name>\n\
      <param-value>true</param-value>\n\
    </context-param>" "$CATALINA_HOME/webapps/geoserver/WEB-INF/web.xml";
  fi
fi

if [ "${POSTGRES_JNDI_ENABLED}" = "true" ]; then

  # Set up some default values
  if [ -z "${POSTGRES_JNDI_RESOURCE_NAME}" ]; then
    export POSTGRES_JNDI_RESOURCE_NAME="jdbc/postgres"
  fi
  if [ -z "${POSTGRES_PORT}" ]; then
    export POSTGRES_PORT="5432"
  fi

  # Use a custom "context.xml" if the user mounted one into the container
  copy_custom_config context.xml
fi

# Use a custom "server.xml" if the user mounted one into the container
copy_custom_config server.xml

# Use a custom "web.xml" if the user mounted one into the container
if [ -d "${CONFIG_OVERRIDES_DIR}" ] && [ -f "${CONFIG_OVERRIDES_DIR}/web.xml" ]; then
  echo "Installing configuration override for web.xml with substituted environment variables"
  
  if [ "${CORS_ENABLED}" = "true" ]; then 
    echo "Warning: the CORS_ENABLED's changes will be overwritten!"
  fi
  
  envsubst < "${CONFIG_OVERRIDES_DIR}"/web.xml > "${CATALINA_HOME}/webapps/geoserver/WEB-INF/web.xml"
fi

# start the tomcat
# CIS - Tomcat Benchmark recommendations:
# * Turn off session facade recycling
# * Set a nondeterministic Shutdown command value
if [ ! "${ENABLE_DEFAULT_SHUTDOWN}" = "true" ]; then
  REPLACEMENT="$(echo $RANDOM | md5sum | head -c 10)"
  sed -i 's/SHUTDOWN/'"$REPLACEMENT"'/g' "$CATALINA_HOME/conf/server.xml"
  REPLACEMENT=
fi

exec $CATALINA_HOME/bin/catalina.sh run -Dorg.apache.catalina.connector.RECYCLE_FACADES=true
