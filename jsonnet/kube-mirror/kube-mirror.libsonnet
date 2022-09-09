local defaults = {

  local defaults = self,
  name: 'mirror-proxy',
  namespace: error 'must provide namespace',
  image: error 'must provide image',
  primary: error 'must provide primary',
  mirror: error 'must provide mirror',

  connectTimeout: '1s',
  routeTimeout: '30s',

  maxConnections: 50000,

  imagePullPolicy: 'IfNotPresent',
  resources:: {
    requests: { cpu: '10m', memory: '20Mi' },
    limits: { cpu: '20m', memory: '40Mi' },
  },
  replicas: 1,
  ports: {
    http: 8080,
    admin: 9901,
  },

  commonLabels:: {
    'app.kubernetes.io/name': defaults.name,
    'app.kubernetes.io/instance': defaults.name,
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'envoy',
  },

  podLabelSelector:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if labelName != 'app.kubernetes.io/version'
  },
};


function(params) {
  local km = self,
  config:: defaults + params,

  assert std.isNumber(km.config.replicas) && km.config.replicas >= 0 : 'replicas has to be >= 0',
  assert std.isObject(km.config.resources),
  assert std.isNumber(km.config.mirror.percentage) && km.config.mirror.percentage >= 0 && km.config.mirror.percentage <= 100 : 'mirror.percentage has to be >= 0 and <= 100',

  configmap:
    local conf = {

      admin: {
        address: {
          socket_address: {
            address: '0.0.0.0',
            port_value: 9901,
          },
        },
      },
      static_resources: {
        listeners: [
          {
            name: 'listener',
            address: {
              socket_address: {
                address: '0.0.0.0',
                port_value: km.config.ports.http,
              },
            },

            filter_chains: [
              {
                filters: [
                  {
                    name: 'envoy.filters.network.http_connection_manager',
                    typed_config: {
                      '@type': 'type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager',
                      stat_prefix: 'ingress_http',
                      codec_type: 'AUTO',
                      route_config: {
                        name: 'local_route',
                        virtual_hosts: [
                          {
                            name: 'local_service',
                            domains: [
                              '*',
                            ],
                            routes: [
                              {
                                match: {
                                  prefix: '/',
                                },
                                route: {
                                  timeout: km.config.routeTimeout,
                                  cluster: 'primary',
                                  request_mirror_policies: [
                                    {
                                      cluster: 'mirror',
                                      runtime_fraction: {
                                        default_value: {
                                          numerator: km.config.mirror.percentage,
                                        },
                                      },
                                    },
                                  ],
                                },
                              },
                            ],
                          },
                        ],
                      },
                      access_log: [
                        {
                          name: 'envoy.access_loggers.stdout',
                          typed_config: {
                            '@type': 'type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog',
                          },
                        },
                      ],
                      http_filters: [
                        {
                          name: 'envoy.filters.http.router',
                          typed_config: {
                            '@type': 'type.googleapis.com/envoy.extensions.filters.http.router.v3.Router',
                          },
                        },
                      ],
                    },
                  },
                ],
              },
            ],
          },

        ],
        clusters: [
          {
            name: 'primary',
            type: 'STRICT_DNS',
            connect_timeout: km.config.connectTimeout,
            load_assignment: {
              cluster_name: 'primary',
              endpoints: [
                {
                  lb_endpoints: [
                    {
                      endpoint: {
                        address: {
                          socket_address: {
                            address: km.config.primary.host,
                            port_value: km.config.primary.port,
                          },
                        },
                      },
                    },
                  ],
                },
              ],
            },
            dns_refresh_rate: '5s',
          },
          {
            name: 'mirror',
            type: 'STRICT_DNS',
            connect_timeout: km.config.connectTimeout,
            load_assignment: {
              cluster_name: 'mirror',
              endpoints: [
                {
                  lb_endpoints: [
                    {
                      endpoint: {
                        address: {
                          socket_address: {
                            address: km.config.mirror.host,
                            port_value: km.config.mirror.port,
                          },
                        },
                      },
                    },
                  ],
                },
              ],
            },
            dns_refresh_rate: '5s',
          },
        ],
      },
      layered_runtime: {
        layers: [
          {
            name: 'static_layer_0',
            static_layer: {
              overload: {
                global_downstream_max_connections: km.config.maxConnections,
              },
            },
          },
        ],
      },
    };
    {
      apiVersion: 'v1',
      kind: 'ConfigMap',
      metadata: {
        name: km.config.name,
        namespace: km.config.namespace,
      },
      data: {
        'envoy.yaml': std.manifestYamlDoc(conf),
      },
    },


  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: km.config.name,
      namespace: km.config.namespace,
      labels: km.config.commonLabels,
    },
    spec: {
      ports: [
        {
          assert std.isString(name),
          assert std.isNumber(km.config.ports[name]),
          name: name,
          port: km.config.ports[name],
          targetPort: km.config.ports[name],
        }
        for name in std.objectFields(km.config.ports)
      ],
      selector: km.config.podLabelSelector,
    },
  },

  deployment:

    local container = {
      name: km.config.name,
      image: km.config.image + ':' + km.config.version,
      readinessProbe: {
        httpGet: {
          path: '/ready',
          port: km.config.ports.admin,
        },
        initialDelaySeconds: 5,
        periodSeconds: 5,
      },
      imagePullPolicy: km.config.imagePullPolicy,
      env: [
        {
          name: 'ENVOY_LB_ALG',
          value: 'LEAST_REQUEST',
        },
        {
          name: 'SERVICE_NAME',
          value: km.config.name,
        },
      ],
      ports: [
        { name: name, containerPort: km.config.ports[name] }
        for name in std.objectFields(km.config.ports)
      ],
      resources: if km.config.resources != {} then km.config.resources else {},
      terminationMessagePolicy: 'FallbackToLogsOnError',
      volumeMounts: [{
        mountPath: '/etc/envoy',
        name: 'config',
        readOnly: true,
      }],
    };

    {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: km.config.name,
        namespace: km.config.namespace,
        labels: km.config.commonLabels,
      },
      spec: {
        replicas: km.config.replicas,
        selector: { matchLabels: km.config.podLabelSelector },
        template: {
          metadata: { labels: km.config.commonLabels },
          spec: {
            containers: [container],
            volumes: [{
              name: 'config',
              configMap: { name: km.config.name },
            }],
          },
        },
      },
    },
}
