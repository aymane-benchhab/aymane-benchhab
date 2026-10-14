output "tags" {
  description = "Tags à propager sur toutes les ressources applicatives du use-case"
  value       = local.tags
}

output "kms_key_arn" {
  value = aws_kms_key.this.arn
}

output "bucket_name" {
  value = aws_s3_bucket.data.bucket
}

output "workload_role_arn" {
  value = aws_iam_role.workload.arn
}

output "inference_profile_arns" {
  description = "ARN à utiliser comme modelId dans les appels Bedrock (Converse / LangChain)"
  value       = { for k, p in aws_bedrock_inference_profile.this : k => p.arn }
}
