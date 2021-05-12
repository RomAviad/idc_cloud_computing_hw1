# IDC Cloud Computing HW1
First homework assignment for Cloud Computing course in IDC Herzliya.

The goal of this assignment is to create a parking-lot management application.
We are required to support two actions:
* Entry (record time, licence plate, and parking lot)
* Exit (return the charge for the time in the parking lot)

The price per hour is 10$, and is increased by 15 minutes increments.

### HTTP Endpoints:
* `POST /entry?plate=123-123-123&parkingLot=382`
  * Returns ticket id
* `POST /exit?ticketId=1234`
  * Returns the license plate, total parked time, the parking lot id and the charge (based
on 15 minutes increments).

### The task:
Build a system that would track and compute cars entry & exit from parking lots, as well as compute their charge. The system should be deployed to AWS in one of two ways:
1. As a serverless solution, covered in Lesson 4.
2. Deployed on an EC2 instance as standard application, covered in Lesson 3.

## My solution
* Python as the language of choice
* For language conventions conversion ("camel-case" as required in the task description vs. Python "kebab-case") I used the `jpsy` package
* For the EC2-based deployment - I used `Flask`
* For data persistence I chose to use a Redis instance on _Elasticache_ - the same  instance serves both the EC2 deployment and the lambda deployment.

## Run instructions
### First-run dependencies:
* If you don't have AWS CLI installed, The `init.sh` script should get you going on a linux machine.

### Setting up all deployments
After you've setup your AWS CLI, Run the `setup.sh` script.