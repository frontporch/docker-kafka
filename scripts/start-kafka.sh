#!/bin/sh

# This script should be idempotent since it's run each time supervisord starts Kafka

# Optional ENV variables:
# * ADVERTISED_HOST: the external ip for the container, e.g. `docker-machine ip \`docker-machine active\``
# * ADVERTISED_PORT: the external port for Kafka, e.g. 9092
# * ZK_CHROOT: the zookeeper chroot that's used by Kafka (without / prefix), e.g. "kafka"
# * LOG_RETENTION_HOURS: the minimum age of a log file in hours to be eligible for deletion (default is 168, for 1 week)
# * LOG_RETENTION_BYTES: configure the size at which segments are pruned from the log, (default is 1073741824, for 1GB)
# * NUM_PARTITIONS: configure the default number of log partitions per topic

# For reference: http://kafka.apache.org/documentation.html#brokerconfigs

# Set the internal host and port
if [ ! -z "$HOST_NAME" ]; then
    echo "host name: $HOST_NAME"
    sed -r -i "s/#(host.name)=(.*)/\1=$HOST_NAME/g" $KAFKA_HOME/config/server.properties
fi
if [ ! -z "$PORT" ]; then
    echo "port: $PORT"
    sed -r -i "s/#(port)=(.*)/\1=$PORT/g" $KAFKA_HOME/config/server.properties
fi

# Set the advertised host and port
if [ ! -z "$ADVERTISED_HOST" ]; then
    echo "advertised host: $ADVERTISED_HOST"
    sed -r -i "s/#(advertised.host.name)=(.*)/\1=$ADVERTISED_HOST/g" $KAFKA_HOME/config/server.properties
fi
if [ ! -z "$ADVERTISED_PORT" ]; then
    echo "advertised port: $ADVERTISED_PORT"
    sed -r -i "s/#(advertised.port)=(.*)/\1=$ADVERTISED_PORT/g" $KAFKA_HOME/config/server.properties
fi

if [ ! -z "$BROKER_ID" ]; then
    echo "Broker ID: $BROKER_ID"
    sed -r -i "s/(broker.id)=(.*)/\1=$BROKER_ID/g" $KAFKA_HOME/config/server.properties
fi

if [ ! -z "$ZK_CONNECTION_STRING" ]; then
    # Configure Kafka to connect to not localhost
    sed -r -i "s/(zookeeper.connect)=(.*)/\1=$ZK_CONNECTION_STRING/g" $KAFKA_HOME/config/server.properties
fi

# Allow specification of log retention policies
if [ ! -z "$LOG_RETENTION_HOURS" ]; then
    echo "log retention hours: $LOG_RETENTION_HOURS"
    sed -r -i "s/(log.retention.hours)=(.*)/\1=$LOG_RETENTION_HOURS/g" $KAFKA_HOME/config/server.properties
fi
if [ ! -z "$LOG_RETENTION_BYTES" ]; then
    echo "log retention bytes: $LOG_RETENTION_BYTES"
    sed -r -i "s/#(log.retention.bytes)=(.*)/\1=$LOG_RETENTION_BYTES/g" $KAFKA_HOME/config/server.properties
fi

# Configure the default number of log partitions per topic
if [ ! -z "$NUM_PARTITIONS" ]; then
    echo "default number of partition: $NUM_PARTITIONS"
    sed -r -i "s/(num.partitions)=(.*)/\1=$NUM_PARTITIONS/g" $KAFKA_HOME/config/server.properties
fi

# Enable/disable auto creation of topics
if [ ! -z "$AUTO_CREATE_TOPICS" ]; then
    echo "auto.create.topics.enable: $AUTO_CREATE_TOPICS"

    # If the value currently exists in the settings file
    if grep -Fq "auto.create.topics.enable=" $KAFKA_HOME/config/server.properties; then
        # Replace the current value with the desired value
        sed -r -i "s/(auto.create.topics.enable)=(.*)/\1=${AUTO_CREATE_TOPICS}/g" $KAFKA_HOME/config/server.properties
    else
        # Otherwise just add the line with the desired value
        echo "auto.create.topics.enable=$AUTO_CREATE_TOPICS" >> $KAFKA_HOME/config/server.properties
    fi
fi

# Create topics in background
/usr/bin/create-topics.sh &

# Run Kafka
$KAFKA_HOME/bin/kafka-server-start.sh $KAFKA_HOME/config/server.properties
