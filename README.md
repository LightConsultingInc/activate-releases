# LightCI Activate: install files

Everything you need to install self-hosted Activate, one tag per release. The product source is not
here; this repository holds the Terraform module, the Compose files and the release downloads. Using
them needs a licence key from LightCI (see [LICENSE](LICENSE)).

The current release is **v1.0.5**. Every release has notes, an offline bundle and checksums on the
[Releases](https://github.com/LightConsultingInc/activate-releases/releases) page.

## What you install

| You run       | Where it comes from                                                                         |
| ------------- | ------------------------------------------------------------------------------------------- |
| Images        | `ghcr.io/lightconsultinginc/activate/server:1.0.5` and `.../activate/web:1.0.5`   |
| Helm chart    | `oci://ghcr.io/lightconsultinginc/charts/activate`, version `1.0.5`                    |
| Terraform     | `terraform/aws` in this repository, at tag `v1.0.5`                                    |
| Compose       | `compose/` in this repository (single-node evaluation only)                                 |
| No internet   | `activate-1.0.5-bundle.tgz` on the release: images, chart, Compose, module, SBOMs      |

No registry login is needed. Images, chart and module carry the same version number; install them
together.

## Kubernetes (Helm)

```sh
helm install activate oci://ghcr.io/lightconsultinginc/charts/activate \
  --version 1.0.5 --namespace activate --create-namespace -f values.yaml
```

## AWS (Terraform)

```hcl
module "activate" {
  source = "github.com/LightConsultingInc/activate-releases//terraform/aws?ref=v1.0.5"
  # ...see terraform/aws/README.md for the inputs
}
```

## Evaluation on one machine (Compose)

```sh
curl -fsSLO https://github.com/LightConsultingInc/activate-releases/releases/download/v1.0.5/docker-compose.yml
curl -fsSL -o .env https://github.com/LightConsultingInc/activate-releases/releases/download/v1.0.5/default.env.example
```

## Check what you downloaded

Images and chart are signed by LightCI's release workflow (keyless, Sigstore). Verify before you
install:

```sh
for ref in ghcr.io/lightconsultinginc/activate/server:1.0.5 \
           ghcr.io/lightconsultinginc/activate/web:1.0.5 \
           ghcr.io/lightconsultinginc/charts/activate:1.0.5; do
  cosign verify "$ref" \
    --certificate-identity-regexp '^https://github.com/LightConsultingInc/lightci-activate/' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com > /dev/null && echo "ok $ref"
done
```

For the offline bundle: `sha256sum -c activate-1.0.5-bundle.tgz.sha256`, then inside it
`sha256sum -c SHA256SUMS`. `DIGESTS` lists the image digests the signatures cover.

## Updates

Installed copies read `index.json` from the latest release once a day (nothing is sent) and show
admins a banner when a newer release exists. Set `UPDATE_CHECK_ENABLED=false` (Compose, Terraform) or
`updates.checkEnabled: false` (Helm) on restricted networks.

## Help

support@lightci.com
