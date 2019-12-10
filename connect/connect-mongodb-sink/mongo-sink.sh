#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo "Initialize MongoDB replica set"
docker exec -it mongodb mongo --eval 'rs.initiate({_id: "myuser", members:[{_id: 0, host: "mongodb:27017"}]})'

sleep 5

echo "Create a user profile"
docker exec -i mongodb mongo << EOF
use admin
db.createUser(
{
user: "myuser",
pwd: "mypassword",
roles: ["dbOwner"]
}
)
EOF

sleep 2

echo "Sending messages to topic orders"
docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF

echo "Creating MongoDB sink connector"
docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "mongodb-sink",
               "config": {
                    "connector.class" : "com.mongodb.kafka.connect.MongoSinkConnector",
                    "tasks.max" : "1",
                    "connection.uri" : "mongodb://myuser:mypassword@mongodb:27017",
                    "database":"inventory",
                    "collection":"customers",
                    "topics":"orders"
          }}' \
     http://localhost:8083/connectors | jq .

sleep 10

echo "View record"
docker exec -i mongodb mongo << EOF
use inventory
db.customers.find().pretty();
EOF
