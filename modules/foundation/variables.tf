variable "name" {
  type = string
}
variable "repositories" {
  type    = set(string)
  default = []
}
variable "tags" {
  type    = map(string)
  default = {}
}
