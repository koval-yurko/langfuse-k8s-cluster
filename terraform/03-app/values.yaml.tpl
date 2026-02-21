# Langfuse Helm values — rendered via templatefile() in helm.tf (Story 3.3)

langfuse:
  salt:
    value: "${salt}"
  nextauth:
    secret:
      value: "${nextauth_secret}"
    url: "http://localhost:3000"
  encryptionKey:
    value: "${encryption_key}"

  service:
    type: ClusterIP

  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: "${irsa_role_arn}"

  additionalEnv:
    - name: AUTH_DISABLE_SIGNUP
      value: "true"
    - name: LANGFUSE_INIT_ORG_ID
      value: "langfuse-dev-org"
    - name: LANGFUSE_INIT_ORG_NAME
      value: "Dev Org"
    - name: LANGFUSE_INIT_PROJECT_ID
      value: "langfuse-dev-project"
    - name: LANGFUSE_INIT_PROJECT_NAME
      value: "langfuse-dev"
    - name: LANGFUSE_INIT_USER_EMAIL
      value: "${admin_email}"
    - name: LANGFUSE_INIT_USER_NAME
      value: "${admin_name}"
    - name: LANGFUSE_INIT_USER_PASSWORD
      value: "${admin_password}"

postgresql:
  deploy: false
  auth:
    username: "langfuse"
    password: "${rds_password}"
    database: "langfuse"
  host: "${rds_host}"
  directUrl: "postgres://langfuse:${rds_password}@${rds_host}:5432/langfuse"
  shadowDatabaseUrl: ""

s3:
  deploy: false
  bucket: "${s3_bucket}"
  region: "${s3_region}"
  forcePathStyle: false
  eventUpload:
    prefix: "events/"
  mediaUpload:
    prefix: "media/"
  batchExport:
    enabled: true

clickhouse:
  deploy: true
  auth:
    password: "dev-clickhouse-pw"

redis:
  deploy: true
  auth:
    password: "dev-redis-pw"
