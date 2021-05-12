# debug
# set -o xtrace

RUN_ID=$(date +'%s')
REGION=$(aws ec2 describe-availability-zones | jq -r '.AvailabilityZones[0].RegionName')
AWS_ACCOUNT=$(aws sts get-caller-identity  | jq -r '.Account')


KEY_NAME="cloud-course-$RUN_ID"
KEY_PEM="$KEY_NAME.pem"
echo "create key pair $KEY_PEM to connect to instances and save locally"
aws ec2 create-key-pair --key-name $KEY_NAME \
    | jq -r ".KeyMaterial" > $KEY_PEM

## secure the key pair
chmod 400 $KEY_PEM

SEC_GRP="my-sg-$RUN_ID"

echo "setup firewall $SEC_GRP"
CREATE_GROUP=$(aws ec2 create-security-group   \
    --group-name $SEC_GRP       \
    --description "Access my instances")

SEC_GRP_ID=$(echo $CREATE_GROUP | jq -r '.GroupId')

## figure out my ip
MY_IP=$(curl ipinfo.io/ip)
echo "My IP: $MY_IP"


echo "setup rule allowing SSH access to $MY_IP only"
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP --port 22 --protocol tcp \
    --cidr $MY_IP/32

echo "setup rule allowing HTTP (port 5000) access to $MY_IP only"
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP --port 5000 --protocol tcp \
    --cidr $MY_IP/32

echo "setup rule allowing TCP (port 6379) REDIS access to $SEC_GRP members and $MY_IP"
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP --port 6379 --protocol tcp \
    --source-group $SEC_GRP_ID

aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP --port 6379 --protocol tcp \
    --cidr $MY_IP/32

UBUNTU_20_04_AMI="ami-042e8287309f5df03"

echo "Creating Ubuntu 20.04 instance..."
RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id $UBUNTU_20_04_AMI        \
    --instance-type t3.micro            \
    --key-name $KEY_NAME                \
    --security-groups $SEC_GRP)

INSTANCE_ID=$(echo $RUN_INSTANCES | jq -r '.Instances[0].InstanceId')

echo "Waiting for instance creation..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids $INSTANCE_ID |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

echo "New instance $INSTANCE_ID @ $PUBLIC_IP"


echo "Creating elasticache cluster"
MY_REDIS="cloud-course-cache"

aws elasticache create-cache-cluster      \
    --cache-cluster-id $MY_REDIS          \
    --engine redis                        \
    --num-cache-nodes 1                   \
    --cache-node-type cache.t3.micro      \
    --security-group-ids $SEC_GRP_ID      \


echo "Waiting for elasticache cluster creation..."
aws elasticache wait cache-cluster-available --cache-cluster-id $MY_REDIS

CACHE_DESCRIPTION=$(aws elasticache describe-cache-clusters \
    --cache-cluster-id $MY_REDIS \
    --show-cache-node-info)

CACHE_ADDRESS=$(echo $CACHE_DESCRIPTION | jq -r '.CacheClusters[0].CacheNodes[0].Endpoint.Address')
echo "export REDIS_HOST='$CACHE_ADDRESS'" > REDIS_CONF.txt

echo "deploying code to production"
scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" server.py bl.py database_layer.py requirements.txt REDIS_CONF.txt ubuntu@$PUBLIC_IP:/home/ubuntu/

echo "setup production environment"
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PUBLIC_IP <<EOF
    sudo apt update
    sudo apt install python3-pip -y
    sudo pip3 install -r requirements.txt
    # run app
    source REDIS_CONF.txt
    nohup python3 server.py &>/dev/null &
    exit
EOF

echo "Preparing lambda deployment"
mkdir lambda_deployment
touch lambda_deployment/__init__.py
cp lambda*.py lambda_deployment/ && cp bl.py lambda_deployment/ && cp database_layer.py lambda_deployment/
pip3 install --target=lambda_deployment/ -r requirements.txt
zip -r lambda_deployment.zip lambda_deployment/*

ROLE_NAME="lambda-ex-$RUN_ID"
echo "Creating role: $ROLE_NAME"
IAM_CREATE_OUT=$(aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document '{"Version": "2012-10-17", "Statement": [{ "Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}')
aws iam wait role-exists --role-name $ROLE_NAME

ACCESS_POLICY="lambda-access-$RUN_ID"
echo "Creating custom policy $ACCESS_POLICY to allow Lambda to access elasticache"
POLICY_CREATED=$(aws iam create-policy --policy-name $ACCESS_POLICY --policy-document '{"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Action": ["ec2:DescribeNetworkInterfaces","ec2:CreateNetworkInterface","ec2:DeleteNetworkInterface","ec2:DescribeInstances","ec2:AttachNetworkInterface"],"Resource": "*"}]}')
POLICY_ARN=$(echo $POLICY_CREATED | jq -r '.Policy.Arn')
echo "Policy ARN: $POLICY_ARN"


echo "Workaround consistency rules in AWS roles after creation... (sleep 10)"
sleep 10

ROLE_ARN=$(echo $IAM_CREATE_OUT | jq -r '.Role.Arn')
echo "Allowing writes to CloudWatch logs..."
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn $POLICY_ARN
aws iam attach-role-policy --role-name $ROLE_NAME  \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole


SUBNET_ID=$(aws ec2 describe-subnets | jq -r '.Subnets[0].SubnetId')

ENTER_FUNC_NAME="parking_enter_$RUN_ID"
EXIT_FUNC_NAME="parking_exit_$RUN_ID"
aws lambda create-function --function-name $ENTER_FUNC_NAME --role "$ROLE_ARN" --runtime python3.8 --handler lambda_enter.handler --package-type Zip --environment "{\"Variables\":{\"REDIS_HOST\":\"$CACHE_ADDRESS\", \"PYTHONPATH\": \"lambda_deployment\"}}" --vpc-config "{\"SubnetIds\": [\"$SUBNET_ID\"], \"SecurityGroupIds\": [\"$SEC_GRP_ID\"]}" --zip-file fileb://lambda_deployment.zip
aws lambda create-function --function-name $EXIT_FUNC_NAME --role "$ROLE_ARN" --runtime python3.8 --handler lambda_exit.handler --package-type Zip --environment "{\"Variables\":{\"REDIS_HOST\":\"$CACHE_ADDRESS\",\"PYTHONPATH\": \"lambda_deployment\"}}" --vpc-config "{\"SubnetIds\": [\"$SUBNET_ID\"], \"SecurityGroupIds\": [\"$SEC_GRP_ID\"]}" --zip-file fileb://lambda_deployment.zip

echo "labmda functions created. waiting for them to be active..."
aws lambda wait function-active --function-name $ENTER_FUNC_NAME
aws lambda wait function-active --function-name $EXIT_FUNC_NAME

ENTER_FUNC_ARN=$(aws lambda get-function --function-name $ENTER_FUNC_NAME | jq -r .Configuration.FunctionArn)
EXIT_FUNC_ARN=$(aws lambda get-function --function-name $EXIT_FUNC_NAME | jq -r .Configuration.FunctionArn)

echo "Creating API Gateway..."

API_NAME="enter_api_gw_$RUN_ID"
ENTER_API_CREATED=$(aws apigatewayv2 create-api --name $API_NAME --protocol-type HTTP --target $ENTER_FUNC_ARN)
ENTER_API_ID=$(echo $ENTER_API_CREATED | jq -r .ApiId)
ENTER_API_ENDPOINT=$(echo $ENTER_API_CREATED | jq -r .ApiEndpoint)

API_NAME="exit_api_gw_$RUN_ID"
EXIT_API_CREATED=$(aws apigatewayv2 create-api --name $API_NAME --protocol-type HTTP --target $EXIT_FUNC_ARN)
EXIT_API_ID=$(echo $EXIT_API_CREATED | jq -r .ApiId)
EXIT_API_ENDPOINT=$(echo $EXIT_API_CREATED | jq -r .ApiEndpoint)

echo "Enter API endpoint: $ENTER_API_ENDPOINT"
echo "Exit API endpoint: $EXIT_API_ENDPOINT"

ENTER_STMT_ID=$(uuidgen)
EXIT_STMT_ID=$(uuidgen)

aws lambda add-permission --function-name $ENTER_FUNC_NAME \
    --statement-id $ENTER_STMT_ID --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:$REGION:$AWS_ACCOUNT:$ENTER_API_ID/*"

aws lambda add-permission --function-name $EXIT_FUNC_NAME \
    --statement-id $EXIT_STMT_ID --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:$REGION:$AWS_ACCOUNT:$EXIT_API_ID/*"

#aws lambda invoke --function-name "parking_enter" --payload '{"queryStringParameters": {"plate":"1-2-3", "parking_lot": "1232"}}'
#rm -rf lambda_deployment

echo "test that it all worked"
curl  --retry-connrefused --retry 10 --retry-delay 1  http://$PUBLIC_IP:5000  && \
  echo "ALL WORKED... SERVER PUBLIC IP IS $PUBLIC_IP"

export INSTANCE_ID=$INSTANCE_ID
export SEC_GRP=$SEC_GRP
echo "instance id: $INSTANCE_ID ; cluster id: $MY_REDIS"