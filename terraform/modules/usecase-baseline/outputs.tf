output "tags" {
  value = local.tags
}

output "kms_key_arn" {
  value = aws_kms_key.this.arn
}

output "bucket_name" {
  value = aws_s3_bucket.data.bucket
}
