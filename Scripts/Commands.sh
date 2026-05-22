#!/bin/bash

# Retrieve secret

aws secretsmanager get-secret-value \
    --secret-id TopSecretInfo

# List secrets

aws secretsmanager list-secrets

# Describe CloudTrail

aws cloudtrail describe-trails

# List CloudWatch alarms

aws cloudwatch describe-alarms

# List SNS topics

aws sns list-topics
