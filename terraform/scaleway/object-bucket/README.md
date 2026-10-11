# object-bucket

A Scaleway Object Storage bucket (`scaleway_object_bucket`) with a randomized name suffix (or an `exact_name` override for buckets whose name must match something external, e.g. a custom domain), versioning, a standard/glacier storage-class toggle implemented via an immediate lifecycle transition, and optional static-website hosting (`enable_website`) plus public-read ACL (`enable_public_read`).

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_enable_public_read"></a> [enable\_public\_read](#input\_enable\_public\_read) | Grant the bucket a public-read ACL (scaleway\_object\_bucket\_acl) | `bool` | `false` | no |
| <a name="input_enable_versioning"></a> [enable\_versioning](#input\_enable\_versioning) | Object versioning enabled (true/false) | `bool` | `false` | no |
| <a name="input_enable_website"></a> [enable\_website](#input\_enable\_website) | Configure the bucket for static website hosting (scaleway\_object\_bucket\_website\_configuration) | `bool` | `false` | no |
| <a name="input_exact_name"></a> [exact\_name](#input\_exact\_name) | Exact bucket name, bypassing the name\_prefix/random-suffix/name\_suffix scheme entirely — for buckets whose name must match something external (e.g. a custom domain for bucket-website hosting) | `string` | `null` | no |
| <a name="input_expiration_days"></a> [expiration\_days](#input\_expiration\_days) | Delete objects this many days after creation, via a scaleway\_object\_bucket lifecycle\_rule expiration. null (the default) adds no expiration rule at all. Day-granular only -- the S3 lifecycle API this wraps has no finer unit, so a 72-hour retention is expressed as 3. Note this is independent of storage\_class's own 90-day glacier transition: an expiration shorter than 90 days means objects are deleted before that transition could ever fire, so pair a short expiration with storage\_class = "standard". | `number` | `null` | no |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | Boolean that, when set to true, allows the deletion of all objects (including locked objects) when the bucket is destroyed. | `bool` | `false` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Bucket name prefix (ignored if exact\_name is set) | `string` | `null` | no |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Bucket name suffix (ignored if exact\_name is set) | `string` | `null` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Project ID the bucket belongs to (defaults to the provider's own project when unset) | `string` | `null` | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | Storage class for new objects (standard/glacier) | `string` | `"glacier"` | no |
| <a name="input_website_error_document"></a> [website\_error\_document](#input\_website\_error\_document) | Error document key for website hosting (only used when enable\_website is true) | `string` | `"404.html"` | no |
| <a name="input_website_index_document"></a> [website\_index\_document](#input\_website\_index\_document) | Index document suffix for website hosting (only used when enable\_website is true) | `string` | `"index.html"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | Bucket endpoint URL |
| <a name="output_id"></a> [id](#output\_id) | Bucket ID |
| <a name="output_name"></a> [name](#output\_name) | Computed bucket name |
| <a name="output_website_endpoint"></a> [website\_endpoint](#output\_website\_endpoint) | Bucket website endpoint URL (only meaningful when enable\_website is true) |
<!-- END_TF_DOCS -->
