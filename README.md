# Wraptor

Self-hosted, model-agnostic async inference on GPU Spot EC2.

Drop in your model. Wraptor handles the queue, scaling, S3 I/O, retries, and alerts.

## How it works

```
Client pushes job to SQS
  → EC2 Spot spins up automatically
  → Downloads input from S3
  → Runs your model (run.sh)
  → Uploads results to S3
  → Scales back to zero after 10 min idle
```

- Max 3 instances, min 0 — you only pay when jobs are running
- Failed jobs retry 3x, then go to a Dead Letter Queue with email alert
- Logs in CloudWatch at `/wraptor/{name}/worker`

## Add your model

1. Clone this repo
2. Edit `run.sh` — replace the command with your model's inference command
   - Input is always at `/tmp/input/data{INPUT_EXTENSION}`
   - Write all output files to `/tmp/output/`
3. Edit `Dockerfile` — add your model's pip dependencies
4. Run `./deploy.sh`

### run.sh contract

```bash
# Input  : /tmp/input/data.fasta   (extension set by INPUT_EXTENSION env var)
# Output : write result files to /tmp/output/

vespag predict -i /tmp/input/data.fasta -o /tmp/output --single-csv
```

## Deploy

```bash
./deploy.sh <name> <email> [region]

# examples
./deploy.sh vespag user@example.com
./deploy.sh alphafold user@example.com eu-west-1
```

After deploy, check your email and confirm the SNS subscription to receive failure alerts.

## Push a job

Send a JSON message to the SQS queue printed after deploy:

```json
{
  "job_id":        "any-unique-id",
  "input_s3_path": "s3://<name>-agentic-assets/input/your-file.fasta"
}
```

Results appear at `s3://<name>-agentic-assets/output/{job_id}/`

## S3 layout

Each deployment gets a single bucket, `<name>-agentic-assets`, split by prefix:

| Prefix             | Contents                            |
| ------------------ | ----------------------------------- |
| `input/`           | job inputs you upload               |
| `output/{job_id}/` | results written by the worker       |
| `build/`           | `source.zip` packaged for CodeBuild |

The worker is only permitted to read under `input/` and write under `output/`, so
job inputs must be uploaded to the `input/` prefix.

## Requirements

- AWS CLI configured (`aws configure`)
- Terraform >= 1.0
- Python 3 (used to package the build source)

The worker image is built in **AWS CodeBuild** and pushed to ECR — Docker is not
required on your machine. `deploy.sh` provisions the CodeBuild project, packages
the repo to an S3 source bucket, runs the build, then applies the rest of the
infrastructure. Use `redeploy.sh` to rebuild the image after editing `run.sh`,
the `Dockerfile`, or your model code.
