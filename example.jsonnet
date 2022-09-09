local mp = import 'jsonnet/kube-mirror/kube-mirror.libsonnet';

local conf = {
    image: 'docker.io/envoyproxy/envoy',
    version: 'v1.23.1',
    name: 'mirror-proxy',
    namespace: 'mirror',
    listenPort: 8080,
    primary: {
        host: 'service-a.mirror.svc.cluster.local',
        port: 8080,
    },
    mirror: {
        host: 'service-b.mirror.svc.cluster.local',
        port: 8080,
        percentage: 100,
    },
};

mp(conf)
