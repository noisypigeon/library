# This module composes other modules only -- no scaleway_* resources of its
# own, so there's nothing to declare under required_providers. versions.tf
# still needs to exist here so template-release.yml's module-discovery
# (which matches on templates/terraform/scaleway/*/*/versions.tf) picks this
# module up for tagging.
terraform {}
