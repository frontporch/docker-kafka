#!/bin/bash

readonly INITIALIZATION_TIMEOUT_SECONDS=30
# $TOPICS is on env variable that needs to be passed into the docker container
readonly ARRAY_OF_TOPICS=($TOPICS)
readonly TOPIC_PARTITIONS=${NUM_PARTITIONS}
readonly TOPIC_REPLICATION=1

function kill_this_container {
    # If running under Docker should always be PID 1. This
    # will stop the container and force a restart
    kill 1;

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

    echo "Adding topics to Kafka"
    for TOPIC in "${ARRAY_OF_TOPICS[@]}"
    do
        RETRIES=3
        until [ $RETRIES -lt 1 ]; do
            # Attempt to create the topic
            echo "Creating topic \"${TOPIC}\"."
            ${KAFKA_HOME}/bin/kafka-topics.sh \
                        --zookeeper ${ZK_CONNECTION_STRING} \
                        --create --partitions ${KAFKA_TOPIC_PARTITIONS} \
                        --replication-factor ${KAFKA_TOPIC_REPLICATION} \
                        --topic ${TOPIC}

            # If we successfully created the topic
            if $KAFKA_HOME/bin/kafka-topics.sh --list --zookeeper 192.168.33.11:2181 | grep -q ${TOPIC}; then
                echo "Created topic \"${TOPIC}\"."
                break
            else
                let RETRIES-=1
            fi
        done

        # If we made it through all our retry attempts
        if [ $RETRIES -lt 1 ]; then
            # and were not successful in creating the topic
            if $KAFKA_HOME/bin/kafka-topics.sh --list --zookeeper 192.168.33.11:2181 | grep -q ${TOPIC}; then
                kill_this_container
            fi
        fi

    done

    echo "Topics currently in Kafka:"
    ${KAFKA_HOME}/bin/kafka-topics.sh --zookeeper ${ZK_CONNECTION_STRING} --list
}

# Make sure Kafka starts by checking expected IP/PORT are available for connection
echo "Verify Kafka is up"
connect_or_die ${ADVERTISED_HOST} ${ADVERTISED_PORT} ${INITIALIZATION_TIMEOUT_SECONDS}

# Kafka can start and still fail based on configuration, etc.  Do this to make sure
# Kafka not only starts, but initializes correctly
echo "Verify Kafka is initialized"
initialize_or_die ${INITIALIZATION_TIMEOUT_SECONDS}

# If Kafka came up, create the topics
echo "Add topics to Kafka"
create_topics ${ZK_CONNECTION_STRING} ${TOPIC_PARTITIONS} ${TOPIC_REPLICATION}
