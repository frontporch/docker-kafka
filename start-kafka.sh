#!/bin/bash

# $TOPICS is on env variable that needs to be passed into the docker container
# Optional ENV variables:
# * ADVERTISED_HOST: the external ip for the container, e.g. `docker-machine ip \`docker-machine active\``
# * ADVERTISED_PORT: the external port for Kafka, e.g. 9092
# * ZK_CHROOT: the zookeeper chroot that's used by Kafka (without / prefix), e.g. "kafka"
# * LOG_RETENTION_HOURS: the minimum age of a log file in hours to be eligible for deletion (default is 168, for 1 week)
# * LOG_RETENTION_BYTES: configure the size at which segments are pruned from the log, (default is 1073741824, for 1GB)
# * NUM_PARTITIONS: configure the default number of log partitions per topic

# For reference: http://kafka.apache.org/documentation.html#brokerconfigs

function join { local IFS="$1"; shift; echo "$*"; }

# Set sensible defaults for environmental variables where possible
HOST_NAME=${HOST_NAME:-0.0.0.0}
PORT=${PORT:-9092}
# ADVERTISED_HOST=${ADVERTISED_HOST:-192.168.1.1}
ADVERTISED_PORT=${ADVERTISED_PORT:-9092}
BROKER_ID=${BROKER_ID:-1}
ZK_CONNECTION_STRING=${ZK_CONNECTION_STRING:-127.0.0.1:2181}
if [ ! -z "$ZK_CONNECTION_STRING" ]; then
    # Massage into correct format (space delimited array->comma deletion) because Kubernetes
    # doesn't like commas in their env var strings
    ZK_CONNECTION_STRING=( $ZK_CONNECTION_STRING )
    ZK_CONNECTION_STRING=$(join , ${ZK_CONNECTION_STRING[@]})
else
    exit 0;
fi

#LOG_DIRS=${LOG_DIRS:-/tmp/kafka-logs}
#LOG_RETENTION_HOURS=${LOG_RETENTION_HOURS:-168}
#LOG_RETENTION_BYTES=${LOG_RETENTION_BYTES:-1073741824}
NUM_PARTITIONS=${NUM_PARTITIONS:-1}
AUTO_CREATE_TOPICS=${AUTO_CREATE_TOPICS:-true}

readonly INITIALIZATION_TIMEOUT_SECONDS=30
readonly TOPIC_PARTITIONS=${NUM_PARTITIONS}
readonly TOPIC_REPLICATION=1

function update_kafka_config {

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

    # Configure Kafka log directory
    if [ ! -z "$LOG_DIRS" ]; then
        echo "log retention hours: $LOG_DIRS"
        sed -r -i "s/(log.dirs)=(.*)/\1=$LOG_DIRS/g" $KAFKA_HOME/config/server.properties
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
}

function kill_this_container {
    # # If running under Docker should always be PID 1. This
    # # will stop the container and force a restart
    # kill 1;

    # Exit with error
    exit 1;
}

function connect_or_die {
    # Parse parameters
    local readonly TEST_IP=$1
    local readonly TEST_PORT=$2
    local readonly LOOP_TIMEOUT_SECONDS=$3

    # Setup local
    local readonly LOOP_INCREMENT_SECONDS=1
    local LOOP_COUNT_SECONDS=0

    # Test if we can connect to the IP/PORT
    until (echo > /dev/tcp/${TEST_IP}/${TEST_PORT}) > /dev/null 2>&1; do

        # If we've tried too many times
        if (( ${LOOP_COUNT_SECONDS} >= ${LOOP_TIMEOUT_SECONDS} )); then
            echo "Error: Server never started."
            kill_this_container
        fi

        # Increment loop counter
        (( LOOP_COUNT_SECONDS+=1 ))

        # Take a second and think about what you've just done
        sleep ${LOOP_INCREMENT_SECONDS}
    done
}

function initialize_or_die {
    # Parse parameters
    local readonly LOOP_TIMEOUT_SECONDS=$1

    # Setup local
    local readonly LOOP_INCREMENT_SECONDS=1
    local readonly KAFKA_LOG_FILE="/var/log/supervisor/kafka-stdout*.log"
    local readonly KAFKA_INITIALIZED_LOG_REGEX="\(INFO \[Kafka Server \)[[:digit:]]\{1,2\}\(\], started (kafka\.server\.KafkaServer)\)"
    local LOOP_COUNT_SECONDS=0

    # If the log contains expected initialized text
    until (cat ${KAFKA_LOG_FILE} | grep -q "${KAFKA_INITIALIZED_LOG_REGEX}"); do

        # If we've tried too many times
        if (( ${LOOP_COUNT_SECONDS} >= ${LOOP_TIMEOUT_SECONDS} )); then
            echo "Error: Server never initialized."
            kill_this_container
        fi

        # Increment loop counter
        (( LOOP_COUNT_SECONDS+=1 ))

        # Take a second and think about what you've just done
        sleep ${LOOP_INCREMENT_SECONDS}
    done
}

function create_topics {
    local readonly ZOOKEEPER_CONNECTION_STRING=$1
    local readonly KAFKA_TOPIC_PARTITIONS=$2
    local readonly KAFKA_TOPIC_REPLICATION=$3
    local readonly ARRAY_OF_TOPICS=($TOPICS)

    echo "Adding topics to Kafka"
    for TOPIC in "${ARRAY_OF_TOPICS[@]}"
    do
        RETRIES=10
        until [ $RETRIES -lt 1 ]; do

            # If the there is a topic prefix specified
            if [ ! -z ${TOPIC_PREFIX} ]; then
                # Prepend it to the topic
                TOPIC=${TOPIC_PREFIX}${TOPIC};
            fi

            # Attempt to create the topic
            echo "Creating topic \"${TOPIC}\"."
            ${KAFKA_HOME}/bin/kafka-topics.sh \
                        --zookeeper ${ZK_CONNECTION_STRING} \
                        --create --partitions ${KAFKA_TOPIC_PARTITIONS} \
                        --replication-factor ${KAFKA_TOPIC_REPLICATION} \
                        --topic ${TOPIC}

            # If we successfully created the topic
            if $KAFKA_HOME/bin/kafka-topics.sh --list --zookeeper ${ZK_CONNECTION_STRING} | grep -q ${TOPIC}; then
                echo "Created topic \"${TOPIC}\"."
                break
            else
                let RETRIES-=1
            fi
        done

        # If we made it through all our retry attempts
        if [ $RETRIES -lt 1 ]; then
            # and were not successful in creating the topic
            if $KAFKA_HOME/bin/kafka-topics.sh --list --zookeeper ${ZK_CONNECTION_STRING} | grep -q ${TOPIC}; then
                kill_this_container
            fi
        fi

    done

    echo "Topics currently in Kafka:"
    ${KAFKA_HOME}/bin/kafka-topics.sh --zookeeper ${ZK_CONNECTION_STRING} --list
}

# First, update Kafka config according to environmental vars passed in
echo "Updating Kafka broker config"
update_kafka_config

# Turn on monitor mode so we can send job to background
# set -m

# Create ENV VARs so it's picked up when starting Kafka server
export JMX_PORT=${JMX_PORT:-9999}
export KAFKA_JMX_OPTS="\
-Dcom.sun.management.jmxremote=true \
-Dcom.sun.management.jmxremote.local.only=false \
-Dcom.sun.management.jmxremote.authenticate=false \
-Dcom.sun.management.jmxremote.ssl=false \
-Djava.rmi.server.hostname=${ADVERTISED_HOST} \
-Dcom.sun.management.jmxremote.rmi.port=9998
"

# Run Kafka (in background for now)
echo "Starting Kafka in background"
$KAFKA_HOME/bin/kafka-server-start.sh ${KAFKA_HOME}/config/server.properties

# UndefineENV VARs so it's not picked up when creating topics
unset JMX_PORT
unset KAFKA_JMX_OPTS

# Make sure Kafka starts by checking expected IP/PORT are available for connection
# echo "Verify Kafka is up"
# connect_or_die ${ADVERTISED_HOST} ${ADVERTISED_PORT} ${INITIALIZATION_TIMEOUT_SECONDS}

# Kafka can start and still fail based on configuration, etc.  Do this to make sure
# Kafka not only starts, but initializes correctly
# echo "Verify Kafka is initialized"
# initialize_or_die ${INITIALIZATION_TIMEOUT_SECONDS}

# If Kafka came up, create the topics
echo "Add topics to Kafka"
create_topics ${ZK_CONNECTION_STRING} ${TOPIC_PARTITIONS} ${TOPIC_REPLICATION}

# Bring Kafka back to foreground
echo "Brining Kafka to foreground"
jobs
fg %1
