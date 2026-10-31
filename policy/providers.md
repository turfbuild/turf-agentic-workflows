# Providers rule

The standing rule for the Terraform providers a configuration runs. The agent evaluates
it against what `init` reports in `providers[]` before the first `up`, on every run. A
provider is a plugin that holds the cloud credentials, so it is checked like any other
dependency.

1. **Source.** Every provider's source is `registry.opentofu.org/hashicorp/<name>` or
   `registry.terraform.io/hashicorp/<name>`. Any other namespace or registry is a deny.
2. **Pinned.** Every provider is recorded in `.terraform.lock.hcl` with a version and
   hashes, which is what `providers[]` shows. A provider with no hashes is a deny.
3. **Advisories.** For every provider, look up the GitHub Advisory Database for its module
   `github.com/hashicorp/terraform-provider-<name>` at the resolved version
   (`list_global_security_advisories`, ecosystem `go`, `affects: "<module>@v<version>"`).
   - An advisory of severity **high** or **critical** whose fixed version is above the
     resolved version, or that has no fixed version, is a **deny**.
   - Anything of lower severity, or already fixed at or below the resolved version, is
     reported in the Providers table and does not block.
   - A lookup that fails is reported as "not checked"; it does not block, but say so.

A deny means the configuration is not opened and nothing is planned. Report the table and
the rule that refused.
