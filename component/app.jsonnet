local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rook_mini;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('rook-mini', params.namespace.operator);

{
  'rook-mini': app {
    spec+: {
      syncPolicy+: {
        syncOptions+: [
          'ServerSideApply=true',
        ],
      },
    },
  },
}
