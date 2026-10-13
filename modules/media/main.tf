resource "aws_s3_bucket" "media" {
  bucket_prefix = "${var.name}-media-"
  force_destroy = false
  tags          = var.tags
}
# public_read turns all four off: the public-read bucket policy below needs
# block_public_policy and restrict_public_buckets off to apply at all.
resource "aws_s3_bucket_public_access_block" "media" {
  bucket                  = aws_s3_bucket.media.id
  block_public_acls       = !var.public_read
  block_public_policy     = !var.public_read
  ignore_public_acls      = !var.public_read
  restrict_public_buckets = !var.public_read
}
resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id
  rule {
    # An S3 bucket key only matters for AES256 here; the KMS default never set one.
    bucket_key_enabled = var.sse_algorithm == "AES256" ? true : null
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.sse_algorithm == "aws:kms" ? var.kms_key_arn : null
      sse_algorithm     = var.sse_algorithm
    }
  }
}
resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_cloudfront_origin_access_control" "media" {
  name                              = "${var.name}-media"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
resource "aws_cloudfront_distribution" "media" {
  count           = var.enable_cloudfront ? 1 : 0
  enabled         = true
  is_ipv6_enabled = true
  web_acl_id      = var.waf_web_acl_arn
  origin {
    domain_name              = aws_s3_bucket.media.bucket_regional_domain_name
    origin_id                = "media-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.media.id
  }
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "media-s3"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = var.cloudfront_acm_certificate_arn == null
    acm_certificate_arn            = var.cloudfront_acm_certificate_arn
    ssl_support_method             = var.cloudfront_acm_certificate_arn == null ? null : "sni-only"
    minimum_protocol_version       = var.cloudfront_acm_certificate_arn == null ? null : "TLSv1.2_2021"
  }
  tags = var.tags
}
# CloudFront's read (enable_cloudfront) and/or anonymous read of every object
# (public_read). The public statement covers p/ too, so private media is
# readable by anyone who has its path; see variables.tf.
resource "aws_s3_bucket_policy" "media" {
  count  = var.enable_cloudfront || var.public_read ? 1 : 0
  bucket = aws_s3_bucket.media.id
  policy = jsonencode({ Version = "2012-10-17", Statement = concat(
    var.enable_cloudfront ? [{ Effect = "Allow", Principal = { Service = "cloudfront.amazonaws.com"
      }, Action = "s3:GetObject", Resource = "${aws_s3_bucket.media.arn}/*", Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.media[0].arn
      }
      }
    }] : [],
    var.public_read ? [{ Sid = "PublicReadAllObjects", Effect = "Allow", Principal = "*", Action = "s3:GetObject", Resource = "${aws_s3_bucket.media.arn}/*" }] : [],
  ) })
  # S3 refuses a public policy while Block Public Access is on.
  depends_on = [aws_s3_bucket_public_access_block.media]
}
# Both became counted with enable_cloudfront; keeps existing state in place.
moved {
  from = aws_cloudfront_distribution.media
  to   = aws_cloudfront_distribution.media[0]
}
moved {
  from = aws_s3_bucket_policy.media
  to   = aws_s3_bucket_policy.media[0]
}
resource "aws_iam_role" "mediaconvert" {
  name = "${var.name}-mediaconvert"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "mediaconvert.amazonaws.com"
    }, Action = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}
resource "aws_iam_role_policy" "mediaconvert" {
  name = "media-access"
  role = aws_iam_role.mediaconvert.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"], Resource = "${aws_s3_bucket.media.arn}/*"
    }]
  })
}
# Application services use an S3-compatible client (access-key/secret pair,
# not the task IAM role), so a dedicated IAM user is provisioned here scoped
# strictly to this bucket.
resource "aws_iam_user" "media" {
  name = "${var.name}-media-app"
  tags = var.tags
}
resource "aws_iam_access_key" "media" {
  user = aws_iam_user.media.name
}
resource "aws_iam_user_policy" "media" {
  name = "media-bucket-access"
  user = aws_iam_user.media.name
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"], Resource = [aws_s3_bucket.media.arn, "${aws_s3_bucket.media.arn}/*"]
    }, { Effect = "Allow", Action = ["kms:GenerateDataKey", "kms:Decrypt"], Resource = var.kms_key_arn
    }]
  })
}
