#!/bin/bash

# Usage: ./generate_iam_policy_permissions_document.sh <AWS_ACCOUNT_NUMBER> <AWS_REGION> <IAM_USER_NAME>

TEMPLATES_DIR_NAME="cloudtrail_access_analyzer_templates"
GENERATED_FILES_DIR_NAME="script_generated_files"
mkdir -p $TEMPLATES_DIR_NAME
mkdir -p $GENERATED_FILES_DIR_NAME
TEMPLATES_DIR="$PWD/$TEMPLATES_DIR_NAME"
GENERATED_FILES_DIR="$PWD/$GENERATED_FILES_DIR_NAME"
CLOUDTRAIL_DETAILS_ACCESS_ANALYZER_GENERATED_FILE_NAME="$GENERATED_FILES_DIR/cloudtrail-details-access-analyzer.json"

S3_BUCKET_POLICY_FILE="$TEMPLATES_DIR/s3-bucket-policy-template.json"
ACCESS_ANALYZER_ACCESS_ROLE_POLICY="$TEMPLATES_DIR/access-analyzer-access-role-policy-template.json"
CLOUDTRAIL_DETAILS_ACCESS_ANALYZER="$TEMPLATES_DIR/cloudtrail-details-access-analyzer-template.json"

AWS_ACCOUNT_NUMBER=${1:?"AWS account number not set"}
AWS_REGION=${2:?"AWS region not set"}
IAM_USER_NAME=${3:?"IAM user name not set"}

echo "AWS region: $AWS_REGION"
IAM_USER_ARN=$(aws iam get-user --user-name $IAM_USER_NAME --query "User.Arn" --output text)
echo "IAM_USER_ARN: $IAM_USER_ARN"

echo "----------------------------------------------------"

CLOUDTRAIL_S3_BUCKET="$IAM_USER_NAME-cloudtrail-logs-$RANDOM"
TRAIL="$IAM_USER_NAME"

UPDATED_S3_BUCKET_POLICY_FILE="$GENERATED_FILES_DIR/s3-bucket-policy.json"

# Check if the S3 bucket for CloudTrail logs already exists, if not, create new bucket and attach updated s3 policy template file with placeholders replaced
bucket_exists=$(aws s3api list-buckets --query "Buckets[?Name=='$CLOUDTRAIL_S3_BUCKET'].Name" --output text)
if [[ "$bucket_exists" == "$CLOUDTRAIL_S3_BUCKET" ]]; then
    echo "Bucket: $CLOUDTRAIL_S3_BUCKET already exists."
else
  echo "Updating and creating new file for template: $S3_BUCKET_POLICY_FILE"
  S3_BUCKET_POLICY=$(sed -e "s/AWS_REGION/$AWS_REGION/g" \
  -e "s/ACCOUNT_NUMBER/$AWS_ACCOUNT_NUMBER/g" \
  -e "s/TRAIL_NAME/$TRAIL/g" \
  -e "s/BUCKET_NAME/$CLOUDTRAIL_S3_BUCKET/g" \
  "$S3_BUCKET_POLICY_FILE" > "$UPDATED_S3_BUCKET_POLICY_FILE" \
  )

  echo "Creating CloudTrail S3 Bucket: $CLOUDTRAIL_S3_BUCKET"
  bucket=$(aws s3api create-bucket --bucket $CLOUDTRAIL_S3_BUCKET --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION)

  echo "Attaching bucket policy to S3 bucket: $CLOUDTRAIL_S3_BUCKET that allows CloudTrail Trail to write logs"
  bucket_policy=$(aws s3api put-bucket-policy --bucket $CLOUDTRAIL_S3_BUCKET --policy "file://$UPDATED_S3_BUCKET_POLICY_FILE")
fi

echo "----------------------------------------------------"
ACCESS_ANALYZER_ROLE_NAME="$IAM_USER_NAME-access-analyzer-generate-policy-role"
ACCESS_ANALYZER_ASSUME_ROLE_POLICY="$TEMPLATES_DIR/access-analyzer-assume-role-policy.json"

# Check if access analyzer role exists, if not, create role
access_analyzer_role_exists=$(aws iam list-roles --query "Roles[?RoleName=='$ACCESS_ANALYZER_ROLE_NAME'].RoleName" --output text)
if [[ "$access_analyzer_role_exists" == $ACCESS_ANALYZER_ROLE_NAME ]]; then
  echo "Access Analyzer role: $ACCESS_ANALYZER_ROLE_NAME already exists."
else
  echo "Creating Access Analyzer role: $ACCESS_ANALYZER_ROLE_NAME"
  access_analyzer_role=$(aws iam create-role --role-name $ACCESS_ANALYZER_ROLE_NAME \
  --assume-role-policy-document file://$ACCESS_ANALYZER_ASSUME_ROLE_POLICY \
  )
fi

ACCESS_ANALYZER_ROLE_ARN=$(aws iam list-roles --query "Roles[?RoleName=='$ACCESS_ANALYZER_ROLE_NAME'].Arn" --output text)
echo "ACCESS_ANALYZER_ROLE_ARN: $ACCESS_ANALYZER_ROLE_ARN"

echo "----------------------------------------------------"

ACCESS_ANALYZER_ROLE_POLICY_NAME="$IAM_USER_NAME-access-analyzer-generate-policy-role-policy"
UPDATED_ACCESS_ANALYZER_ACCESS_ROLE_POLICY_FILE="$GENERATED_FILES_DIR/access-analyzer-access-role-policy.json"

# Check if access analyzer role policy exists, if not, create access analyzer role policy from updated template (with placeholders replaced), and attach to role
access_analyzer_role_policy_exists=$(aws iam list-policies --query "Policies[?PolicyName=='$ACCESS_ANALYZER_ROLE_POLICY_NAME'].PolicyName" --output text)
if [[ "$access_analyzer_role_policy_exists" == $ACCESS_ANALYZER_ROLE_POLICY_NAME ]]; then
  echo "Access Analyzer role policy: $ACCESS_ANALYZER_ROLE_POLICY_NAME already exists and attached to role: $ACCESS_ANALYZER_ROLE_NAME."
else
  echo "Updating and creating new file for template: $ACCESS_ANALYZER_ACCESS_ROLE_POLICY"
  ACCESS_ANALYZER_ACCESS_ROLE_POLICY=$(sed -e "s/AWS_REGION/$AWS_REGION/g" \
  -e "s/ACCOUNT_NUMBER/$AWS_ACCOUNT_NUMBER/g" \
  -e "s/TRAIL_NAME/$TRAIL/g" \
  -e "s/BUCKET_NAME/$CLOUDTRAIL_S3_BUCKET/g" \
  "$ACCESS_ANALYZER_ACCESS_ROLE_POLICY" > "$UPDATED_ACCESS_ANALYZER_ACCESS_ROLE_POLICY_FILE" \
  )

  echo "Creating IAM policy: $ACCESS_ANALYZER_ROLE_POLICY_NAME for Access Analyzer role: $ACCESS_ANALYZER_ROLE_NAME"
  ACCESS_ANALYZER_POLICY_ARN=$(aws iam create-policy \
  --policy-name $ACCESS_ANALYZER_ROLE_POLICY_NAME \
  --policy-document file://$UPDATED_ACCESS_ANALYZER_ACCESS_ROLE_POLICY_FILE \
  --query "Policy.Arn" \
  --output text \
  )

  echo "Attaching $ACCESS_ANALYZER_ROLE_POLICY_NAME to $ACCESS_ANALYZER_ROLE_NAME"
  role_policy_attachment=$(aws iam attach-role-policy --role-name $ACCESS_ANALYZER_ROLE_NAME --policy-arn $ACCESS_ANALYZER_POLICY_ARN)
fi

echo "----------------------------------------------------"

# Check if the CloudTrail Trail already exists, if not, create Trail using S3 bucket previously created
cloudtrail_trail_exists=$(aws cloudtrail list-trails --query "Trails[?Name=='$TRAIL'].Name" --output text)
if [[ "$cloudtrail_trail_exists" == "$TRAIL" ]]; then
    echo "Trail $TRAIL already exists."
else
  echo "Creating CloudTrail Trail: $TRAIL for Access Analyzer"
  trail=$(aws cloudtrail create-trail --name $TRAIL --s3-bucket-name $CLOUDTRAIL_S3_BUCKET)
fi

TRAIL_ARN=$(aws cloudtrail list-trails --query "Trails[?Name=='$TRAIL'].TrailARN" --output text)
echo "Trail ARN: $TRAIL_ARN"

echo "----------------------------------------------------"
echo "Starting logging on trail: $TRAIL"
aws cloudtrail start-logging --name $TRAIL

# Get trail status
TRAIL_STATUS=$(aws cloudtrail get-trail-status --name $TRAIL --query "IsLogging" --output text)
echo "Trail status: IsLogging = $TRAIL_STATUS"
echo "----------------------------------------------------"

# Pause script so that Terraform Apply & Destroy can be run and actions logged to trail
echo "Pausing script"
echo "You can now run Terraform apply & then Terraform destroy"
echo "CloudTrail Trail: $TRAIL will log all actions performed & gather IAM permissions needed for IAM user: $IAM_USER_NAME"
echo "----------------------------------------------------"

# Resume after so that the script can start to generate the policy document
read -p "Once Terraform Apply & Destroy has completed, wait 5 minutes and then press enter to continue"
echo "----------------------------------------------------"

# Start time will be 2 hours in the past (format: YYYY-MM-DDThh:mm:ss)
START_TIME="$(date -v-2H "+%FT%T")"
echo "Start time: $START_TIME"

echo "Updating and creating new file for template: $CLOUDTRAIL_DETAILS_ACCESS_ANALYZER"
# Update the CloudTrail details template file and replace all placeholders
CLOUDTRAIL_DETAILS_ACCESS_ANALYZER=$(sed -e "s|ACCESS_ROLE_ARN|$ACCESS_ANALYZER_ROLE_ARN|g" \
-e "s/START_TIME/$START_TIME/g" \
-e "s|TRAIL_ARN|$TRAIL_ARN|g" \
-e "s/AWS_REGION/$AWS_REGION/g" \
"$CLOUDTRAIL_DETAILS_ACCESS_ANALYZER" > "$CLOUDTRAIL_DETAILS_ACCESS_ANALYZER_GENERATED_FILE_NAME" \
)

# Check if CloudTrail logging is on, if yes, turn it off
is_cloudtrail_logging=$(aws cloudtrail get-trail-status --name $TRAIL --query "IsLogging" --output text)
if [[ "$is_cloudtrail_logging" == "True" ]]; then
    echo "Stopping logging on CloudTrail Trail: $TRAIL"
    aws cloudtrail stop-logging --name $TRAIL #
else
  echo "CloudTrail logging already stopped. Continuing..."
fi

echo "CloudTrail Trail: '$TRAIL' logging status: $is_cloudtrail_logging"

echo "----------------------------------------------------"
echo "Starting Access Analyzer policy generation"
# Use the updated CloudTrail details template file to start the Access Analyzer policy generation
ACCESS_ANALYZER_JOB_ID=$(aws accessanalyzer start-policy-generation \
--policy-generation-details principalArn=$IAM_USER_ARN \
--cloud-trail-details file://$CLOUDTRAIL_DETAILS_ACCESS_ANALYZER_GENERATED_FILE_NAME \
--query "jobId" \
--output text \
)

echo "ACCESS_ANALYZER_JOB_ID: $ACCESS_ANALYZER_JOB_ID"

echo "----------------------------------------------------"

# Wait for Access Analyzer policy generation to complete, i.e. JOB_STATUS="SUCCEEDED"
#   Timesout after 5 mins (300 seconds) - at this point something would have gone wrong
NEXT_WAIT_TIME=0
JOB_STATUS=""
until [[ $JOB_STATUS == "SUCCEEDED" ]]; do
    NEXT_WAIT_TIME=$[$NEXT_WAIT_TIME +1]
    # Get status of access analyzer policy generation job"
    JOB_STATUS=$(aws accessanalyzer get-generated-policy --job-id $ACCESS_ANALYZER_JOB_ID --query "jobDetails.status" --output text)
    echo "Policy generation job status: $JOB_STATUS"
    echo "Waiting for: $NEXT_WAIT_TIME seconds"
    sleep $NEXT_WAIT_TIME
    if [[ $NEXT_WAIT_TIME -eq 300 ]]; then
      echo "Timed out after 5 mins waiting for access analyzer job status to change to 'SUCCEEDED'"
      echo "Exiting"
      exit 1
    fi
done

echo "----------------------------------------------------"

GENERATED_POLICY_FILE="$IAM_USER_NAME-generated-policy.json"

echo "Job status now: $JOB_STATUS, getting the generated skeleton policy document and saving to: $GENERATED_POLICY_FILE in current directory"

# Get the generated policy document from Access Analyzer and save to file in current directory
GET_GENERATED_POLICY=$(aws accessanalyzer get-generated-policy \
--job-id $ACCESS_ANALYZER_JOB_ID \
--query "generatedPolicyResult.generatedPolicies[0].policy" \
--output text \
| jq . > "$PWD/$GENERATED_POLICY_FILE"
)

echo "Generated skeleton IAM policy document and saved to: $GENERATED_POLICY_FILE in current directory"

echo "----------------------------------------------------"

echo "Cleaning up resources generated in this script"

./teardown_resources_generate_iam_policy_document.sh $IAM_USER_NAME $CLOUDTRAIL_S3_BUCKET

