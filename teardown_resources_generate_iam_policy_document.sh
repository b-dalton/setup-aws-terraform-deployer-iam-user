#!/bin/bash

# Usage: ./teardown_resources_generate_iam_policy_document.sh <IAM_USER_NAME> <S3_BUCKET_NAME>

IAM_USER_NAME=${1:?"IAM user name not set"}
CLOUDTRAIL_S3_BUCKET=${2:?"CloudTrail S3 bucket not set"}

TRAIL="$IAM_USER_NAME"
ACCESS_ANALYZER_ROLE_NAME="$IAM_USER_NAME-access-analyzer-generate-policy-role"
ACCESS_ANALYZER_ROLE_POLICY_NAME="$IAM_USER_NAME-access-analyzer-generate-policy-role-policy"
ACCESS_ANALYZER_ROLE_POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='$ACCESS_ANALYZER_ROLE_POLICY_NAME'].Arn" --output text)

# Check if the S3 bucket for CloudTrail logs exists, if so, delete contents then delete bucket
bucket_exists=$(aws s3api list-buckets --query "Buckets[?Name=='$CLOUDTRAIL_S3_BUCKET'].Name" --output text)
if [[ "$bucket_exists" == "$CLOUDTRAIL_S3_BUCKET" ]]; then
    echo "Bucket: $CLOUDTRAIL_S3_BUCKET exists. Deleting contents."
    delete_contents=$(aws s3 rm s3://$CLOUDTRAIL_S3_BUCKET --recursive)
    echo "Bucket now empty. Deleting bucket: $CLOUDTRAIL_S3_BUCKET."
    delete_bucket=$(aws s3api delete-bucket --bucket $CLOUDTRAIL_S3_BUCKET)
    echo "Bucket deletion complete"
else
  echo "Bucket: $CLOUDTRAIL_S3_BUCKET doesn't exist. Skipping..."
fi

echo "----------------------------------------------------"

# Check if the CloudTrail Trail exists, if so, delete it
cloudtrail_trail_exists=$(aws cloudtrail list-trails --query "Trails[?Name=='$TRAIL'].Name" --output text)
if [[ "$cloudtrail_trail_exists" == "$TRAIL" ]]; then
    echo "Trail: $TRAIL exists. Deleting trail."
    delete_trail=$(aws cloudtrail delete-trail --name $TRAIL)
    echo "Trail deletion complete"
else
  echo "Trail: $TRAIL doesn't exist. Skipping..."
fi

echo "----------------------------------------------------"

# Check if Access Analyzer IAM role exists, if so, detach IAM policies then delete it
access_analyzer_role_exists=$(aws iam list-roles --query "Roles[?RoleName=='$ACCESS_ANALYZER_ROLE_NAME'].RoleName" --output text)
if [[ "$access_analyzer_role_exists" == $ACCESS_ANALYZER_ROLE_NAME ]]; then
  echo "Access Analyzer IAM role: $ACCESS_ANALYZER_ROLE_NAME exists. Detaching IAM policies then deleting IAM role."
  detach_policies=$(aws iam detach-role-policy --role-name $ACCESS_ANALYZER_ROLE_NAME --policy-arn $ACCESS_ANALYZER_ROLE_POLICY_ARN)
  delete_role=$(aws iam delete-role --role-name $ACCESS_ANALYZER_ROLE_NAME)
  echo "Access Analyzer IAM policy detachment and IAM role deletion complete"
else
  echo "Access Analyzer IAM role: $ACCESS_ANALYZER_ROLE_NAME doesn't exist. Skipping..."
fi

echo "----------------------------------------------------"

# Check if Access Analyzer IAM role policy exists, if so, delete it
access_analyzer_role_policy_exists=$(aws iam list-policies --query "Policies[?PolicyName=='$ACCESS_ANALYZER_ROLE_POLICY_NAME'].PolicyName" --output text)
if [[ "$access_analyzer_role_policy_exists" == $ACCESS_ANALYZER_ROLE_POLICY_NAME ]]; then
  echo "Access Analyzer IAM role policy: $ACCESS_ANALYZER_ROLE_POLICY_NAME exists. Deleting IAM policy"
  delete_policy=$(aws iam delete-policy --policy-arn $ACCESS_ANALYZER_ROLE_POLICY_ARN)
  echo "Access Analyzer IAM role policy deletion complete"
else
  echo "Access Analyzer IAM role policy: $ACCESS_ANALYZER_ROLE_POLICY_NAME doesn't exist. Skipping..."
fi

echo "----------------------------------------------------"

echo "All AWS resources that were created during the IAM Policy document generation process have been successfully deleted"
