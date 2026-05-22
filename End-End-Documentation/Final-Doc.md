# 🔐 AWS Security Monitoring System

A hands-on cloud security project that demonstrates how to monitor access to sensitive secrets in AWS and receive real-time email alerts when they are accessed.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Services Used](#services-used)
- [Prerequisites](#prerequisites)
- [Stage 1 — Secret & Logging Setup](#stage-1--secret--logging-setup)
  - [Step 1 — Create a Secret in AWS Secrets Manager](#step-1--create-a-secret-in-aws-secrets-manager)
  - [Step 2 — Configure AWS CloudTrail](#step-2--configure-aws-cloudtrail)
  - [Step 3 — Generate & Verify Secret Access Events](#step-3--generate--verify-secret-access-events)
- [Stage 2 — Monitoring & Alerting Setup](#stage-2--monitoring--alerting-setup)
  - [Step 4 — Set Up CloudWatch Logs & Metric Filter](#step-4--set-up-cloudwatch-logs--metric-filter)
  - [Step 5 — Create CloudWatch Alarm & SNS Topic](#step-5--create-cloudwatch-alarm--sns-topic)
  - [Step 6 — Test & Troubleshoot Notifications](#step-6--test--troubleshoot-notifications)
- [Bonus — Direct CloudTrail SNS Notifications](#bonus--direct-cloudtrail-sns-notifications)
- [Cleanup — Delete All Resources](#cleanup--delete-all-resources)
- [Key Takeaways](#key-takeaways)

---

## Overview

This project builds a complete **event-driven security monitoring system** on AWS. The system detects whenever a sensitive secret is accessed in AWS Secrets Manager and immediately sends an email alert to notify you of the activity.

By the end of this project, you will have:

- Securely stored a secret using **AWS Secrets Manager**
- Enabled **AWS CloudTrail** to record all secret access events
- Streamed CloudTrail logs into **Amazon CloudWatch Logs**
- Created a **CloudWatch Metric Filter** to detect `GetSecretValue` API calls
- Configured a **CloudWatch Alarm** and **Amazon SNS** topic to deliver real-time email alerts
- Compared two alerting architectures and understood when to use each

---

## Architecture

```
AWS Secrets Manager
        │
        │  (GetSecretValue API call)
        ▼
AWS CloudTrail  ──────────────────────────────────────►  Amazon S3
        │                                               (Long-term log storage)
        │  (Log delivery)
        ▼
Amazon CloudWatch Logs
        │
        │  (Metric Filter: "GetSecretValue")
        ▼
CloudWatch Metric → CloudWatch Alarm
                            │
                            │  (Alarm state: IN ALARM)
                            ▼
                      Amazon SNS Topic
                            │
                            ▼
                     📧 Email Notification
```

---

## Services Used

| Service | Purpose |
|---|---|
| **AWS Secrets Manager** | Securely store and manage sensitive credentials |
| **AWS CloudTrail** | Record and audit API activity across the AWS account |
| **Amazon CloudWatch Logs** | Centralise and store CloudTrail log streams |
| **Amazon CloudWatch** | Create metric filters and alarms based on log patterns |
| **Amazon SNS** | Deliver real-time email notifications |
| **Amazon S3** | Long-term storage and retention of CloudTrail logs |
| **AWS CLI / CloudShell** | Programmatically access secrets to generate test events |

---

## Prerequisites

- An AWS account with IAM Admin access
- Access to an email inbox to confirm SNS subscription
- Basic familiarity with the AWS Management Console

---

## Stage 1 — Secret & Logging Setup

### Step 1 — Create a Secret in AWS Secrets Manager

1. Log in to the **AWS Management Console** as your IAM Admin user.
2. Search for **Secrets Manager** in the console and open it.
3. Select **Store a new secret**.
4. Under **Choose secret type**, select **Other type of secret**.
5. In the **Key/value** tab, enter:
   - **Key:** `The Secret is`
   - **Value:** Any value you like (e.g. `rice is the best carb`)
6. Leave the default **Encryption key** setting unchanged.
7. Select **Next**.
8. On the **Configure secret** page, enter:
   - **Secret name:** `TopSecretInfo`
   - **Description:** `Secret created for a Security Monitoring System project`
9. Select **Next**, then **Next** again to skip the rotation configuration.
10. Review the settings and select **Store**.
11. In the green confirmation banner, select **View details** to confirm your secret was created.

> **What is AWS Secrets Manager?**  
> Secrets Manager securely stores sensitive information such as passwords, API keys, and credentials — keeping them out of your source code and away from unauthorised access.

---

### Step 2 — Configure AWS CloudTrail

#### Create a New Trail

1. Navigate to the **CloudTrail** console.
2. In the left navigation pane, select **Trails**.
3. Select **Create trail**.
4. Under **Trail name**, enter `secrets-manager-trail`.
5. Under **Storage location**, select **Create new S3 bucket**.
6. Enter a unique bucket name:
   ```
   nextwork-secrets-manager-trail-<your-initials>
   ```
7. **Uncheck** `Log file SSE-KMS encryption` to avoid additional KMS charges.
8. Leave all other settings as default and select **Next**.

#### Configure Log Events

9. On the **Choose log events** page, ensure **Management events** is selected under Event type.
10. Under **API activity**, keep both **Read** and **Write** checked.
11. Check **Exclude AWS KMS events**.
12. Check **Exclude Amazon RDS Data API events**.
13. Select **Next**.

#### Review and Create

14. Review your trail configuration:

| Setting | Value |
|---|---|
| Trail name | `secrets-manager-trail` |
| Multi-region trail | Yes |
| S3 bucket | `nextwork-secrets-manager-trail-<your-initials>` |
| Log file SSE-KMS encryption | Disabled |
| Log file validation | Enabled |
| Management events | Read + Write |
| Exclude KMS events | Yes |
| Exclude RDS Data API events | Yes |

15. Select **Create trail**.

> **Why S3 for CloudTrail logs?**  
> S3 offers virtually unlimited, durable, and cost-effective storage — and integrates easily with analytics services like Athena for future log analysis.

---

### Step 3 — Generate & Verify Secret Access Events

#### Access Your Secret via the Console

1. Navigate back to the **Secrets Manager** console.
2. Open your `TopSecretInfo` secret.
3. Scroll down and select **Retrieve secret value**.
4. View the secret value, then select **Close**.

#### Access Your Secret via AWS CLI (Optional)

1. Open **AWS CloudShell** from the top navigation bar of the AWS Console.
2. Run the following command, replacing `your-region-code` with your actual region (e.g. `us-east-1`):

```bash
aws secretsmanager get-secret-value --secret-id "TopSecretInfo" --region your-region-code
```

3. The command will return the secret value in JSON format.

#### Verify Events in CloudTrail

1. Navigate to the **CloudTrail** console.
2. In the left navigation pane, select **Event history**.
3. Set the **Lookup attribute** dropdown to `Event source`.
4. Enter `secretsmanager.amazonaws.com` in the search bar.
5. Look for a `GetSecretValue` event in the results — this confirms CloudTrail recorded your secret access.

> **What is `GetSecretValue`?**  
> This is the specific API call made every time someone retrieves the value of a secret. Monitoring this event is the core of our alerting system.

---

## Stage 2 — Monitoring & Alerting Setup

### Step 4 — Set Up CloudWatch Logs & Metric Filter

#### Enable CloudWatch Logs for CloudTrail

1. In the **CloudTrail** console, select **Trails** from the left pane.
2. Select your `secrets-manager-trail`.
3. Scroll down to the **CloudWatch Logs** section and select **Edit**.
4. Check the **Enabled** checkbox.
5. Select **New log group** and enter the name:
   ```
   nextwork-secretsmanager-loggroup
   ```
6. Under **IAM Role**, select **New** and enter the role name:
   ```
   CloudTrailRoleForCloudWatchLogs_secrets-manager-trail
   ```
7. Select **Save changes**.

#### Verify Logs are Flowing

1. Navigate to the **CloudWatch** console.
2. In the left pane, expand **Logs** and select **Log groups**.
3. Search for and open `nextwork-secretsmanager-loggroup`.
4. Open any log stream and confirm that log entries are appearing.

> **Note:** If no log entries appear immediately, wait 2–3 minutes and refresh the page. It can take a short time for CloudTrail to deliver the first batch of logs after enabling CloudWatch integration.

#### Create a Metric Filter

1. From your log group page, select **Actions → Create metric filter**.
2. In the **Filter pattern** field, enter:
   ```
   "GetSecretValue"
   ```
3. Select **Next**.
4. Fill in the metric details:

| Field | Value |
|---|---|
| Filter name | `GetSecretsValue` |
| Metric namespace | `SecurityMetrics` |
| Metric name | `Secret is accessed` |
| Metric value | `1` |
| Default value | `0` |

5. Select **Next**, review the settings, then select **Create metric filter**.

> **What is a Metric Filter?**  
> A CloudWatch metric filter automatically scans your logs for a specific pattern and records a numeric value each time it finds a match — turning raw log data into a measurable, monitorable metric.

---

### Step 5 — Create CloudWatch Alarm & SNS Topic

#### Create the Alarm

1. In the **CloudWatch** console, select **Alarms** from the left navigation pane.
2. Select **All alarms**, then navigate back to your log group: go to **Logs → Log groups** and open `nextwork-secretsmanager-loggroup`.
3. Select the **Metric filters** tab at the top of the log group page.
4. Check the box next to the `GetSecretValue` metric filter.
5. Select **Create alarm**.
4. Configure the metric settings:

| Setting | Value |
|---|---|
| Namespace | `SecurityMetrics` |
| Metric name | `Secret is accessed` |
| Statistic | `Average` |
| Period | `5 minutes` |

5. Under **Conditions**, set:
   - **Threshold type:** `Static`
   - **Whenever Secret is accessed is:** `Greater/Equal`
   - **than...:** `1`

6. Select **Next**.

#### Configure SNS Notification

7. On the **Configure actions** page, keep the default **In alarm** state selected.
8. Under **Select an SNS topic**, choose **Create new topic**.
9. Enter the topic name: `SecurityAlarms`
10. Enter your email address under **Email endpoints**.
11. Select **Create topic**, then **Next**.

#### Name and Create the Alarm

12. Enter the alarm details:
    - **Alarm name:** `Secret is accessed`
    - **Alarm description:** `This alarm triggers whenever a secret in Secrets Manager is accessed.`
13. Select **Next**, review the configuration, then select **Create alarm**.

#### Confirm Your SNS Email Subscription

14. Check your email inbox for an email from **AWS Notifications** with the subject:  
    `AWS Notification - Subscription Confirmation`
15. Click **Confirm subscription** in the email.
16. You should see a **Subscription confirmed!** page in your browser.

> **Why confirm the subscription?**  
> AWS requires explicit confirmation before sending notifications to an email address, ensuring you only receive alerts you've opted into.

---

### Step 6 — Test & Troubleshoot Notifications

#### Trigger the Alarm

1. Navigate back to **Secrets Manager** and open `TopSecretInfo`.
2. Select **Retrieve secret value** to generate a new access event.
3. Wait up to **5 minutes** for CloudTrail to log the event, CloudWatch to detect it, and the alarm to trigger.

#### Verify the Alarm State

1. In **CloudWatch**, navigate to your `Secret is accessed` alarm.
2. Confirm the alarm state shows **In alarm**.
3. Check your email inbox for an alert from AWS Notifications with the subject:  
   `ALARM: "Secret is accessed"`

#### Troubleshooting Checklist

If you are not receiving emails, work through these checks in order:

| # | Check | How to Verify |
|---|---|---|
| 1 | **CloudTrail recorded the event** | Check Event History in CloudTrail for a `GetSecretValue` event |
| 2 | **CloudTrail is sending logs to CloudWatch** | Confirm log entries exist in `nextwork-secretsmanager-loggroup` |
| 3 | **Metric filter pattern is correct** | Confirm the filter pattern is exactly `"GetSecretValue"` (with quotes) |
| 4 | **Alarm threshold is configured correctly** | Confirm threshold is `>= 1` with a `5 minute` period |
| 5 | **SNS subscription is confirmed** | Check your inbox — the confirmation email must be clicked before alerts are delivered |

---

## Bonus — Direct CloudTrail SNS Notifications

This section explores a second alerting approach — sending SNS notifications directly from CloudTrail whenever a new log file is delivered to S3 — and compares it to the CloudWatch Alarm approach.

#### Enable Direct CloudTrail SNS Notifications

1. In the **CloudTrail** console, select your `secrets-manager-trail`.
2. Select **Edit** in the **General details** section.
3. Scroll to **SNS notification delivery** and check **Enabled**.
4. Select **Use existing SNS topic** and choose `SecurityAlarms` from the dropdown.
5. Select **Save changes**.

#### Test It

6. Retrieve your `TopSecretInfo` secret value again from Secrets Manager.
7. Wait a few minutes and check your email inbox.

You will notice a large number of emails arriving — one for every log file CloudTrail delivers to S3, regardless of what activity it contains.

#### Disable Direct Notifications

8. Return to the trail's **General details**, select **Edit**, and **uncheck** the SNS notification delivery option.
9. Select **Save changes**.

#### Comparison: CloudWatch Alarm vs. Direct CloudTrail SNS

| Feature | CloudWatch Alarm | Direct CloudTrail SNS |
|---|---|---|
| **Trigger** | Only when `GetSecretValue` is detected | Every time any log file is delivered to S3 |
| **Noise level** | Low — targeted, actionable alerts | High — constant notifications for all activity |
| **Best used for** | Human-facing, specific security alerts | Automated ingestion into SIEM or audit systems |
| **Filtering** | Yes — only notifies on matching events | No — notifies on all account activity |
| **Setup complexity** | Higher | Lower |

> **Conclusion:** The CloudWatch Alarm approach is better suited for specific, human-actionable security alerts. Direct CloudTrail SNS notifications are better suited for programmatic processing by security tools that need all activity logs.

---

## Cleanup — Delete All Resources

To avoid ongoing AWS charges, delete all resources created in this project.

### 1. SNS Topic & Subscription

1. Navigate to the **SNS** console.
2. Select **Topics**, check `SecurityAlarms`, and select **Delete**. Type `delete me` to confirm.
3. Select **Subscriptions**, check your subscription, and select **Delete**.

### 2. CloudWatch Alarm, Log Group & Metric Filter

1. Navigate to **CloudWatch → Alarms**.
2. Select `Secret is accessed` and choose **Actions → Delete**.
3. Navigate to **CloudWatch → Log groups**.
4. Select `nextwork-secretsmanager-loggroup` and choose **Actions → Delete log group**.  
   *(This also removes the metric filter attached to the log group.)*

### 3. IAM Role

1. Navigate to the **IAM** console and select **Roles**.
2. Search for `CloudTrailRoleForCloudWatchLogs_secrets-manager-trail`.
3. Select it and choose **Delete**, then confirm.

### 4. CloudTrail Trail

1. Navigate to the **CloudTrail** console and select **Trails**.
2. Select `secrets-manager-trail` and choose **Delete**.

### 5. S3 Bucket

1. Navigate to the **S3** console.
2. Open the bucket `nextwork-secrets-manager-trail-<your-initials>`.
3. Select all objects, delete them, then delete the bucket itself.

### 6. Secrets Manager Secret

1. Navigate to **Secrets Manager**.
2. Open `TopSecretInfo`, select **Actions → Delete secret**.
3. Set the waiting period to **7 days** (minimum) and confirm deletion.

---

## Key Takeaways

- **AWS Secrets Manager** provides a secure, centralised store for sensitive credentials, keeping them out of code and version control.
- **AWS CloudTrail** creates a full audit trail of API activity — including who accessed what, when, and from where.
- **Amazon CloudWatch Logs** enables real-time log analysis, metric filtering, and alarm-based automation.
- **CloudWatch Metric Filters** translate raw log data into measurable signals that can trigger automated responses.
- **Amazon SNS** delivers notifications to humans or systems the moment a security condition is met.
- Comparing two alerting architectures (CloudWatch vs. direct CloudTrail SNS) shows that **targeted, filtered alerts are more actionable** than broad, high-volume notifications.
- Following **least privilege** principles — such as scoped IAM roles for CloudTrail log delivery — reduces the blast radius of any potential security incident.
