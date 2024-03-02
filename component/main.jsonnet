// main template for rook-mini
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local prom = import 'lib/prometheus.libsonnet';
local inv = kap.inventory();

// The hiera parameters for the component
local params = inv.parameters.rook_mini;
local hasPrometheus = std.member(inv.applications, 'prometheus');

// Namespaces
local namespaces = [
  kube.Namespace(params.namespace.operator) {
    metadata: {
      labels: {
        'pod-security.kubernetes.io/enforce': 'privileged',
        'app.kubernetes.io/managed-by': 'commodore',
        name: params.namespace.operator,
      },
      name: params.namespace.operator,
    },
  },
  kube.Namespace(params.namespace.cluster) {
    metadata: {
      labels: {
        'pod-security.kubernetes.io/enforce': 'privileged',
        'app.kubernetes.io/managed-by': 'commodore',
        name: params.namespace.cluster,
      },
      name: params.namespace.cluster,
    },
  },
];

// Storage Class
local storageClass(name, spec) = kube._Object('storage.k8s.io/v1', 'StorageClass', name) {
  metadata: {
    annotations: {
      'storageclass.kubernetes.io/is-default-class': if std.get(spec, 'isDefault', false) then 'true' else 'false',
    },
    labels: {
      'app.kubernetes.io/managed-by': 'commodore',
      'app.kubernetes.io/name': name,
    },
    name: name,
  },
  allowVolumeExpansion: true,
  parameters: {
    clusterID: params.namespace.cluster,
    'csi.storage.k8s.io/controller-expand-secret-name': 'rook-csi-%s-provisioner' % spec.type,
    'csi.storage.k8s.io/controller-expand-secret-namespace': params.namespace.cluster,
    'csi.storage.k8s.io/node-stage-secret-name': 'rook-csi-%s-node' % spec.type,
    'csi.storage.k8s.io/node-stage-secret-namespace': params.namespace.cluster,
    'csi.storage.k8s.io/provisioner-secret-name': 'rook-csi-%s-provisioner' % spec.type,
    'csi.storage.k8s.io/provisioner-secret-namespace': params.namespace.cluster,
    'csi.storage.k8s.io/fstype': std.get(spec, 'fsType', 'ext4'),
  } + com.makeMergeable(std.get(spec, 'parameters', {})),
  provisioner: '%s.%s.csi.ceph.com' % [ params.namespace.operator, spec.type ],
  reclaimPolicy: std.get(spec, 'reclaimPolicy', 'Delete'),
  volumeBindingMode: 'Immediate',
};

// Storage Pools
local blockpool = [
  storageClass('ceph-block', params.blockpool { type: 'rbd' }) {
    parameters+: {
      pool: 'ceph-blockpool',
    },
  },
  kube._Object('ceph.rook.io/v1', 'CephBlockPool', 'ceph-blockpool') {
    metadata: {
      labels: {
        'app.kubernetes.io/managed-by': 'commodore',
        'app.kubernetes.io/name': 'ceph-blockpool',
      },
      namespace: params.namespace.cluster,
      name: 'ceph-blockpool',
    },
    spec: params.blockpool.spec,
  },
];

local objectstore = [
  storageClass('ceph-bucket', params.objectstore { type: 'object' }) {
    parameters: {
      objectStoreName: 'ceph-objectstore',
      objectStoreNamespace: params.namespace.cluster,
    } + com.makeMergeable(params.objectstore.parameters),
    provisioner: '%s.ceph.rook.io/bucket' % params.namespace.operator,
  },
  kube._Object('ceph.rook.io/v1', 'CephObjectStore', 'ceph-objectstore') {
    metadata: {
      labels: {
        'app.kubernetes.io/managed-by': 'commodore',
        'app.kubernetes.io/name': 'ceph-objectstore',
      },
      namespace: params.namespace.cluster,
      name: 'ceph-objectstore',
    },
    spec: {
      allowUsersInNamespaces: if std.length(params.objectstore.allowedNamespaces) > 0 then params.objectstore.allowedNamespaces else [ '*' ],
      preservePoolsOnDelete: true,
      gateway: {
        port: 80,
        hostNetwork: false,
        resources: {
          limits: {
            memory: '1Gi',
          },
          requests: {
            cpu: '100m',
            memory: '512Mi',
          },
        },
        instances: 2,
        priorityClassName: 'system-cluster-critical',
      },
    } + com.makeMergeable(params.objectstore.spec),
  },
] + if params.objectstore.ingress.enabled then [
  local ingress = params.objectstore.ingress;
  kube._Object('networking.k8s.io/v1', 'Ingress', 'ceph-objectstore') {
    metadata: {
      annotations: ingress.annotations,
      labels: {
        'app.kubernetes.io/managed-by': 'commodore',
        'app.kubernetes.io/name': 'ceph-objectstore',
      },
      namespace: params.namespace.cluster,
      name: 'ceph-objectstore',
    },
    spec: {
      ingressClassName: ingress.class,
      rules: [ {
        host: ingress.url,
        http: {
          paths: [ {
            backend: {
              service: {
                name: 'rook-ceph-rgw-ceph-objectstore',
                port: { number: 80 },
              },
            },
            path: '/',
            pathType: 'Prefix',
          } ],
        },
      } ],
      [if ingress.tls then 'tls']: [ {
        hosts: [ ingress.url ],
        secretName: 'ceph-objectstore-tls',
      } ],
    },
  },
] else [];

local filesystem = [
  local class = params.filesystem.data[name].class;
  local spec = params.filesystem.data[name];
  storageClass(class, spec { type: 'cephfs' }) {
    parameters+: {
      fsName: 'ceph-fs',
      pool: 'ceph-fs-%s' % name,
    },
  }
  for name in std.objectFields(params.filesystem.data)
  if std.length(params.filesystem.data[name]) > 0
] + [
  kube._Object('ceph.rook.io/v1', 'CephFilesystem', 'ceph-fs') {
    metadata: {
      labels: {
        'app.kubernetes.io/managed-by': 'commodore',
        'app.kubernetes.io/name': 'ceph-fs',
      },
      namespace: params.namespace.cluster,
      name: 'ceph-fs',
    },
    spec: {
      metadataPool: params.filesystem.metadata,
      dataPools: [
        params.filesystem.data[name].spec { name: name }
        for name in std.objectFields(params.filesystem.data)
        if std.length(params.filesystem.data[name]) > 0
      ],
      metadataServer: {
        activeCount: 1,
        activeStandby: true,
        priorityClassName: 'system-cluster-critical',
        resources: {
          limits: {
            memory: '2Gi',
          },
          requests: {
            cpu: '500m',
            memory: '512Mi',
          },
        },
      } + com.makeMergeable(params.filesystem.server),
    },
  },
];

// Define outputs below
{
  '00_namespace': [
    if hasPrometheus then prom.RegisterNamespace(ns) else ns
    for ns in namespaces
  ],
  [if params.blockpool.enabled then '20_blockpool']: blockpool,
  [if params.objectstore.enabled then '30_objectstore']: objectstore,
  [if params.filesystem.enabled then '40_filesystem']: filesystem,
}
