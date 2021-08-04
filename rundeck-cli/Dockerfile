
FROM openjdk:8-jdk
COPY --from=gradle:jdk8 /opt/gradle /opt/gradle
RUN ln -s /opt/gradle/bin/gradle /usr/bin/gradle
ARG VERSION
RUN mkdir /root/tools/
RUN mkdir /root/rd && curl -sL https://github.com/rundeck/rundeck-cli/releases/download/v${VERSION}/rd-${VERSION}.zip > /root/rd/rd.zip
RUN cd /root/rd/ \
    && unzip rd.zip
RUN cp -r /root/rd/rd-${VERSION}/bin /root/tools/ && cp -r /root/rd/rd-${VERSION}/lib /root/tools/
    
    # && mv root/rd/rd-${VERSION} /root/tools \
    # && rm -rf /root/rd