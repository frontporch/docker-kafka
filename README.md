# Kafka

## Acknowledgements
This container is based heavily on work done by [spotify/docker-kafka](https://github.com/spotify/docker-kafka). However, after using the all-in-one Kafka/Zookeeper container to get up and running, it became necessary to separate Kafka and Zookeeper to allow for multiple instantiations of both.

## Description
Kafka in a Docker container.

### Topic Creation
While Kafka does support the `auto.create.topics` property in the `server.properties` config file, many consumers do not yet support interacting with the topic creation API.  Moreover, subscribing to a topic that does not yet exist but will is an uphill and error-prone undertaking.  This container allows for creation of topic on boot to avoid the aforementioned problems via a space-delimited string of topics passed in via the `TOPICS` environmental variable.

### IP & PORT Settings
Unless your are running this container with the `--net=host` option, it is likely that you'll need to advertise a different host/port than the actual one which Kafka binds to within the container.  For Kafka, the host/port that it binds to can be set via the `HOST_NAME` and `PORT` environmental variables, respectively.  For consumers, the advertised host/port can be set via the `ADVERTISED_HOST` and `ADVERTISED_PORT` environmental variables, respectively.
You might want to start with something like the following:
```
HOST_NAME=0.0.0.0
PORT=9092
ADVERTISED_HOST=<your IP/URI here>
ADVERTISED_PORT=9092
```
This should bind Kafka to all available IPs within the container while still exposing the desired IP/URI to consumers.
