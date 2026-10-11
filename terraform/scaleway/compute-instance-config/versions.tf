# ADR-0153: this module renders a cloud-init document and creates nothing, so
# there are no providers to declare. versions.tf still has to exist for
# template-release.yml's module discovery (which matches on
# templates/terraform/<provider>/<module>/versions.tf) to pick it up for
# tagging -- the same reason pigeon-cluster carried a bare terraform {} block
# while it was composition-only, between ADR-0138 and ADR-0145.
terraform {}
