resource "aws_cloudfront_distribution" "app" {
  enabled         = true
  is_ipv6_enabled = true
  web_acl_id      = var.waf_web_acl_arn
  aliases         = var.domain_name == null ? [] : [var.domain_name]
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "alb"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = var.alb_uses_https ? "https-only" : "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    forwarded_values {
      query_string = true
      headers      = ["Host", "Authorization", "Origin"]
      cookies {
        forward = "all"
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
resource "aws_route53_record" "app" {
  count   = var.domain_name != null && var.route53_zone_id != null ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.app.domain_name
    zone_id                = aws_cloudfront_distribution.app.hosted_zone_id
    evaluate_target_health = false
  }
}
