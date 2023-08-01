resource "template_dir" "persistent" {
  source_dir      = "${path.module}/persistent_manifests"
  destination_dir = "${path.cwd}/persistent"
  vars = {
    namespace    = local.namespace
    coder_domain = var.coder_domain
    username     = local.username
    spacename    = local.spacename
  }
}

resource "template_dir" "ephemeral" {
  source_dir      = "${path.module}/ephemeral_manifests"
  destination_dir = "${path.cwd}/ephemeral"
  vars = {
    namespace    = local.namespace
    coder_domain = var.coder_domain
    username     = local.username
    spacename    = local.spacename
  }
}

# TODO look at https://registry.terraform.io/providers/kbst/kustomization/latest/docs/resources/resource
resource "null_resource" "namespace" {
  depends_on = [
    template_dir.persistent,
    template_dir.ephemeral
  ]
  # We want a per user domain USERNAME.DOMAIN.COM
  # We provision wildcard DNS01 certs for *.USERNAME.DOMAIN.COM
  #                         and *.WORKSPACE.USERNAME.DOMAIN.COM
  provisioner "local-exec" {
    quiet = true
    command = <<COMMAND
curl -L -s \
  -H 'X-API-Key: ${var.pdns_api_key}' -H 'Content-Type: application/json' \
  -D - \
  -d '${templatefile("./create_domain.tpl.json", {
    DOMAIN = "${local.user_domain}.",
    NS1    = "ns.ii.nz",
    NS2    = "ns2.ii.nz",
    ACCOUNTNAME : "${var.pdns_account}",
    KEYNAME : "${var.dns_update_keyname}",
    IP : "${var.public_ip}"
})}' ${var.pdns_api_url}/api/v1/servers/localhost/zones
COMMAND
}
provisioner "local-exec" {
  quiet   = true
  command = <<COMMAND
curl -L -s \
  -H 'X-API-Key: ${var.pdns_api_key}' -H 'Content-Type: application/json' \
  -D - \
  -d '{"kind": "TSIG-ALLOW-DNSUPDATE", "metadata": ["${var.dns_update_keyname}"]}' \
  ${var.pdns_api_url}/api/v1/servers/localhost/zones/${local.user_domain}/metadata
COMMAND
}
# I want to apply a bunch of manifests at once
# HELP WANTED to find a better way
provisioner "local-exec" {
  command = <<COMMAND
../../kubectl version --client || (
  echo installing kubectl:
  curl -s -L https://dl.k8s.io/release/v1.27.3/bin/linux/amd64/kubectl -o ../../kubectl \
  && chmod +x ../../kubectl
)
COMMAND
}
# We have manifests to create the namespace and persist a few things
provisioner "local-exec" {
  depends_on = [
    template_dir.persistent
  ]
  # - the main *.user.DOMAIN cert
  command = "../../kubectl apply -f persistent"
}
# We have manifests to create the namespace
provisioner "local-exec" {
  depends_on = [
    template_dir.ephemeral
  ]
  command = "../../kubectl apply -f ephemeral"
}
# On the way down, just want to use kubectl to remove the epherical k8s objects
provisioner "local-exec" {
  when    = destroy
  command = <<COMMAND
../../kubectl version --client || (
  echo installing kubectl:
  curl -s -L https://dl.k8s.io/release/v1.27.3/bin/linux/amd64/kubectl -o ../../kubectl \
  && chmod +x ../../kubectl
)
COMMAND
}
# We have manifests to create the namespace
provisioner "local-exec" {
  depends_on = [
    template_dir.ephemeral
  ]
  when    = destroy
  command = "../../kubectl delete -f ephemeral"
}
# We could also deloy logstream-kube to show the pod coming up...
#   provisioner "local-exec" {
#     command = <<COMMAND
# ~/helm version --short || (
#   echo installing helm:
#   curl -L https://get.helm.sh/helm-v3.12.1-linux-amd64.tar.gz | tar xvz --strip-components=1 \
#   && mv helm ~/helm \
#   && chmod +x ~/helm
# )
# COMMAND
#   }
# provisioner "local-exec" {
#   command = "~/kubectl -n ${local.namespace} apply -f ${path.module}/manifests/admin-sa.yaml"
# }
#   provisioner "local-exec" {
#     command = <<COMMAND
# ~/helm upgrade --install \
#   --repo https://helm.coder.com/logstream-kube \
#   --namespace ${local.namespace} \
#   --set url=${var.coder_url} \
#   coder-logstream-kube coder-logstream-kube
# COMMAND
#   }
}
resource "coder_metadata" "namespace" {
  resource_id = null_resource.namespace.id
  count       = data.coder_workspace.ii.start_count
  icon        = "/icon/k8s.png"
  # hide        = true
}
