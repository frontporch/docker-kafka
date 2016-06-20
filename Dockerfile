FROM java:openjdk-8-jre

ENV DEBIAN_FRONTEND="noninteractive"
ENV SCALA_VERSION="2.11"
ENV KAFKA_VERSION="0.9.0.1"
ENV KAFKA_HOME=/opt/kafka_"$SCALA_VERSION"-"$KAFKA_VERSION"
ENV PATH="$PATH:$KAFKA_HOME/bin"

# Expose default Kafka port
EXPOSE 9092

# Install Kafka and dependencies
RUN apt-get update > /dev/null && \
    apt-get install -qq wget supervisor dnsutils && \
    rm -rf /var/lib/apt/lists/* && apt-get clean && \
    wget -q http://apache.mirrors.spacedump.net/kafka/"$KAFKA_VERSION"/kafka_"$SCALA_VERSION"-"$KAFKA_VERSION".tgz -O /tmp/kafka_"$SCALA_VERSION"-"$KAFKA_VERSION".tgz && \
    tar xfz /tmp/kafka_"$SCALA_VERSION"-"$KAFKA_VERSION".tgz -C /opt && \
    rm /tmp/kafka_"$SCALA_VERSION"-"$KAFKA_VERSION".tgz

# Copy over supervisor config
ADD supervisor/kafka.conf /etc/supervisor/conf.d/

# Copy over init scripts
COPY scripts/ /usr/bin

# Make startup script executable
RUN chmod 755 /usr/bin/start-kafka.sh && chmod 755 /usr/bin/create-topics.sh

CMD ["supervisord", "-n"]
