local com = import 'lib/commodore.libjsonnet';
local inv = com.inventory();
// The hiera parameters for the component
local params = inv.parameters.rook_mini;

local ignoreKind = [
  'ClusterRole',
  'ClusterRoleBinding',
  'Role',
  'RoleBinding',
  'StorageClass',
];

local namespacePatch = {
  metadata+: {
    namespace: params.namespace.cluster,
  },
};

local hasIgnoreKind(content) = std.filter(
  function(it) it != null,
  [
    if std.get(content, 'kind') == kind then kind
    for kind in ignoreKind
  ]
);

local listTemplates = [
  {
    name: std.strReplace(name, '.yaml', ''),
    manifest: com.yaml_load_all(std.extVar('output_path') + '/' + name),
  }
  for name in com.list_dir(std.extVar('output_path'), basename=true)
];

local patchTemplate(manifest) = [
  if std.length(hasIgnoreKind(content)) > 0 then
    content
  else
    content + namespacePatch
  for content in manifest
];

{
  [template.name]: patchTemplate(template.manifest)
  for template in listTemplates
  //   'cephblockpool': patchTemplate('cephblockpool'),
  //   'cephcluster': patchTemplate('cephcluster'),
  //   'cephecblockpool': patchTemplate('cephecblockpool'),
  //   'cephfilesystem': patchTemplate('cephfilesystem'),
  //   'cephobjectstore-ingress': patchTemplate('cephobjectstore-ingress'),
  //   'cephobjectstore': patchTemplate('cephobjectstore'),
  //   'configmap': patchTemplate('configmap'),
  //   'deployment': patchTemplate('deployment'),
  //   'ingress': patchTemplate('ingress'),
  //   'prometheusrules': patchTemplate('prometheusrules'),
  //   'rbac': patchTemplate('rbac'),
  //   'securityContextConstraints': patchTemplate('securityContextConstraints'),
  //   'volumesnapshotclass': patchTemplate('volumesnapshotclass'),
}
