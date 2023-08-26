// main template for rook-mini
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local prom = import 'lib/prometheus.libsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.rook_mini;
local hasPrometheus = std.member(inv.applications, 'prometheus');

local namespaces = [
  kube.Namespace(params.namespace.operator) {
    metadata+: {
      labels+: {
        'pod-security.kubernetes.io/enforce': 'privileged',
      },
    },
  },
  kube.Namespace(params.namespace.cluster) {
    metadata+: {
      labels+: {
        'pod-security.kubernetes.io/enforce': 'privileged',
      },
    },
  },
];

// Define outputs below
{
  '00_namespace': [
    if hasPrometheus then prom.RegisterNamespace(ns) else ns
    for ns in namespaces
  ],
}
