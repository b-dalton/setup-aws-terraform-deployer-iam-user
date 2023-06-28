#!/bin/bash

# Usage: . ./setup_terraform_iam_user.sh <AWS_ACCOUNT_NUMBER> <AWS_REGION> <AWS_PROFILE_NAME> [<IAM_POLICY_TEMPLATE>] [<IAM_USER_NAME>] [<IAM_POLICY_NAME>]

AWS_ACCOUNT_NUMBER=${1:?"AWS account number not set"}
AWS_REGION=${2:?"AWS region not set"}
AWS_PROFILE_NAME=${3:?"AWS Profile name not set"}
IAM_POLICY_TEMPLATE="${4:-policy_template.json}"
IAM_USER_NAME="${5:-terraform}"
IAM_POLICY_NAME="${6:-TerraformDeployerPolicy}"

# Check if the IAM user already exists
user_exists=$(aws iam list-users --query "Users[?UserName=='$IAM_USER_NAME'].UserName" --output text)
if [[ "$user_exists" == "$IAM_USER_NAME" ]]; then
    echo "IAM user '$IAM_USER_NAME' already exists."
    exit 1
else
  echo "IAM user '$IAM_USER_NAME' will be created"
fi

# Check if the IAM policy already exists
policy_exists=$(aws iam list-policies --query "Policies[?PolicyName=='$IAM_POLICY_NAME'].PolicyName" --output text)
if [[ "$policy_exists" == "$IAM_POLICY_NAME" ]]; then
    echo "IAM policy '$IAM_POLICY_NAME' already exists."
    exit 1
else
  echo "IAM policy '$IAM_POLICY_NAME' will be created"
fi

## Replace AWS Account Number placeholder in IAM policy template
echo "Replacing placeholder 'ACCOUNT_NUMBER' in IAM policy template file: $IAM_POLICY_TEMPLATE"
IAM_POLICY=$(cat "$PWD/$IAM_POLICY_TEMPLATE" | sed "s/ACCOUNT_NUMBER/$AWS_ACCOUNT_NUMBER/g")

## Create the IAM policy
echo "Creating IAM policy from updated template"
policy=$(aws iam create-policy --policy-name "$IAM_POLICY_NAME" --policy-document "$IAM_POLICY")

## Create the IAM user
echo "Creating IAM user: $IAM_USER_NAME"
user=$(aws iam create-user --user-name "$IAM_USER_NAME")

## Attach the policy to the user
echo "Attaching policy to IAM user"
attach_policy=$(aws iam attach-user-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_NUMBER}:policy/${IAM_POLICY_NAME}" --user-name "$IAM_USER_NAME")

echo "IAM user '$IAM_USER_NAME' created and policy '$IAM_POLICY_NAME' attached."
echo "-----------------------------------------"

# Generate IAM user credentials
echo "Generating IAM user security credentials for $IAM_USER_NAME"
USER_CREDENTIALS=$(aws iam create-access-key --user-name $IAM_USER_NAME --output json)

ACCESS_KEY_ID=$(echo $USER_CREDENTIALS | jq .AccessKey.AccessKeyId)
SECRET_ACCESS_KEY=$(echo $USER_CREDENTIALS | jq .AccessKey.SecretAccessKey)

# Add profile to AWS config file
echo "Adding profile and credentials to AWS config and AWS credentials files"
echo -e "\n[profile $AWS_PROFILE_NAME]\nregion=$AWS_REGION\noutput=json" >> ~/.aws/config

# Add credentials to AWS credentials file
echo -e "\n[$AWS_PROFILE_NAME]\naws_access_key_id=$(echo $ACCESS_KEY_ID | xargs)\naws_secret_access_key=$(echo $SECRET_ACCESS_KEY | xargs)" >> ~/.aws/credentials

# Set AWS profile
echo "Setting AWS profile to $AWS_PROFILE_NAME"
export AWS_PROFILE=$AWS_PROFILE_NAME

echo "Credentials generated and stored for IAM User: $IAM_USER_NAME and AWS profile set to $AWS_PROFILE_NAME"
echo "-----------------------------------------"
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
echo "Previously exported admin credentials removed"
