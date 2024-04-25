# global constants
docker_image_sk = 'public.ecr.aws/labster/swissknife:0.6.8'
docker_image_sk_utils = 'public.ecr.aws/labster/swissknife:utils-0.6.8'
docker_image_dind = 'public.ecr.aws/docker/library/docker:25.0.1-dind-alpine3.19'
docker_image_redis = 'public.ecr.aws/bitnami/redis:6.2'
docker_image_sentry = 'getsentry/sentry-cli:2.31.0'
registry_mirror_ep = 'docker-registry.docker-registry.svc.cluster.local:5000'
registry_cache_ep = 'kube-image-keeper-registry.kuik-system.svc.cluster.local:5000'


# docker settings
docker_env = {
    'DOCKER_HOST': 'tcp://dind:2375',
    'REGISTRY_MIRROR_EP': registry_mirror_ep,
    'REGISTRY_CACHE_EP': registry_cache_ep,
    'DOCKER_ARM64_SKIP': {
        'from_secret': 'docker_arm64_skip',
    },
    'AWS_ACCOUNT_ID': {
        'from_secret': 'aws_account_id',
    },
    'AWS_ACCESS_KEY_ID': {
        'from_secret': 'ecr_access_key',
    },
    'ECR_REGION': {
        'from_secret': 'ecr_region',
    },
    'AWS_SECRET_ACCESS_KEY': {
        'from_secret': 'ecr_secret_key',
    },
    'ECR_REGISTRY_ALIAS': {
        'from_secret': 'ecr_registry_alias',
    },
}


def main(ctx):
    pipelines = []
    return [
        pipeline_clone(),
        pipeline_docker_image('amd64', ['push','tag']),
        pipeline_docker_image('arm64', ['tag']),
        pipeline_docker_manifest(),
        pipeline_artifacts(ctx),
        pipeline_report(),
        pipeline_report_tag_failure(),
        pipeline_cleanup(),
    ]

# request more cpu to use the same instanse for tests and clone
def pipeline_clone(cpu=1500, memory='250Mib'):
    return pipeline_common('github-clone', cpu=cpu, memory=memory) | {
        'steps': [
            step_git_clone(),
            step_save_git_cache(),
        ],
    }

def pipeline_cleanup(cpu=100, memory='250Mib'):
    return pipeline_common('cache-cleanup', cpu=cpu, memory=memory) | {
        'trigger': {
            'status': [
                'success',
                'failure',
            ],
        },
        'depends_on': [
            'artifacts',
            'docker-image-amd64',
            'docker-image-arm64',
            'docker-manifest',
            'report',
            'report-tag-failure'
        ],
        'steps': [
            step_cleanup_git_cache(),
        ],
    }

def pipeline_artifacts(ctx, cpu=250, memory='250Mib'):
    author_login = 'nobody'
    if hasattr(ctx.build, 'author_login'):
        author_login = ctx.build.author_login
    slack_intro_settings = {
        'template': '''Drone reports about `{}`,
changes in `{}` by `{}`.
```{}```
Build {} started.'''.format(
        ctx.repo.name,
        ctx.build.branch,
        author_login,
        ctx.build.message,
        '${DRONE_BUILD_NUMBER}',
        )
    }
    return pipeline_common('artifacts', cpu=cpu, memory=memory) | {
        'trigger': {
            'event': [
                'push',
                'tag',
            ],
        },
        'depends_on': [
            'docker-manifest',
        ],
        'steps': [
            step_restore_git_cache(),
            step_slack(
                step_name='slack-intro', 
                settings=slack_intro_settings,
            ),
            step_prepare(),
            step_helm_chart(),
            step_sentry_release(),
        ],
    }

def pipeline_docker_image(arch, events, cpu=1000, memory='2Gib'):
    return pipeline_common('docker-image-{}'.format(arch), arch, cpu=cpu, memory=memory) | {
        'trigger': {
            'event': events,
            'branch': {
                'exclude': [
                    "master",
                ]
            }
        },
        'depends_on': [
            'github-clone',
        ],
        'services': [
            {
                'name': 'dind',
                'image': docker_image_dind,
                'privileged': True,
                'commands': [
r'''mkdir /root/.docker
echo $${CONFIG_JSON} > /root/.docker/config.json
DOCKER_TLS_CERTDIR='' dockerd-entrypoint.sh --storage-driver=overlay2 --tls=false --experimental'''
                ],
                'environment': {
                    'CONFIG_JSON': {
                        'from_secret': 'docker_config'
                    }
                }
            },
            service_redis(),
        ],
        'steps': [
            step_restore_git_cache(),
            step_prepare(),
            step_docker_image_build(),
            step_docker_image_test(),
            step_docker_image_push(arch),
        ],
    }

def pipeline_docker_manifest(cpu=200, memory='250Mib'):
    return pipeline_common('docker-manifest', cpu=cpu, memory=memory) | {
        'trigger': {
            'event': [
                'push',
                'tag',
            ],
            'branch': {
                'exclude': [
                    "master",
                ]
            },
        },
        'depends_on': [
            'docker-image-amd64',
            'docker-image-arm64',
        ],
        'steps': [
            step_restore_git_cache(),
            step_prepare(),
            step_docker_manifest(),
        ],
    }

def pipeline_report(cpu=100, memory='150Mib'):
    return pipeline_common('report', cpu=cpu, memory=memory) | {
        'trigger': {
            'event': [
                'push',
                'tag',
            ],
            'status': [
                'success',
                'failure',
            ]
        },
        'depends_on': [
            'artifacts',
            'docker-image-amd64',
            'docker-image-arm64',
            'docker-manifest',
        ],
        'steps': [
            step_restore_git_cache(),
            step_command(
                step_name='slack-message-prepare',
                commands=['labsterutils/scripts/cicd/slack.sh'],
            ),
            step_slack(
                step_name='slack-report',
                depends_on=['slack-message-prepare'],
            ),
            step_drone_bot_message('Build'),
        ],
    }

def pipeline_report_tag_failure(cpu=100, memory='150Mib'):
    return pipeline_common('report-tag-failure', cpu=cpu, memory=memory) | {
        'trigger': {
            'event': [
                'tag',
            ],
            'status': [
                'failure',
            ],
        },
        'depends_on': [
            'artifacts',
            'docker-image-amd64',
            'docker-image-arm64',
            'docker-manifest',
        ],
        'steps': [
            step_restore_git_cache(),
            step_command(
                step_name='slack-message-prepare',
                commands=['labsterutils/scripts/cicd/slack.sh'],
            ),
            step_slack(
                step_name='slack-report',
                depends_on=['slack-message-prepare'],
                slack_channel_secret_name='portal_slack_failure_channel',
            ),
            step_drone_bot_message('Tag build'),
        ],
    }

def pipeline_common(name, arch='amd64', cpu=100, memory='200MiB'):
    return {
        'kind': 'pipeline',
        'type': 'kubernetes',
        'name': name,
        'platform': {
            'os': 'linux',
            'arch': arch,
        },
        'clone': {
            'disable': True,
        },
        'metadata' : {
            'annotations': {
                'karpenter.sh/do-not-disrupt': 'true',
            },
        },
        'tolerations' : [
            {
                'key': 'drone.io/agent',
                'operator': 'Exists',
                'effect': 'NoSchedule'
            },
        ],
        'node_selector': {
            'role': 'drone-agent',
            'kubernetes.io/arch': arch,
            'topology.kubernetes.io/zone': 'us-east-1a'
        },
        'image_pull_secrets': [
            'docker_config',
        ],
        'resources': {
            'requests': {
                'cpu': cpu,
                'memory': memory,
            },
        },
    }

def step_git_clone(step_name='git-clone', cpu=100):
    return {
        'name': step_name,
        'image': 'plugins/git:1.4.0',
        'settings': {
            'recursive': True,
            'submodule_override': {
                'labsterutils': 'https://github.com/Livit/Livit.Learn.Utils.git',
            },
            'depth': 1,
        },
        'resources': {
            'limits': {
                'cpu': cpu,
            }
        }
    }

def step_slack(step_name='slack', slack_channel_secret_name='', depends_on=['git-clone'], settings={'template': 'file:///drone/src/slack.txt'}, when={}, cpu=100):
    slack_channel_env = {}
    if slack_channel_secret_name:
        slack_channel_env = {
            'PLUGIN_CHANNEL': {
                'from_secret': slack_channel_secret_name
            }
        }
    res = {
        'name': step_name,
        'image': 'plugins/slack:1.4.1',
        'depends_on': depends_on,
        'settings': settings,
        'environment': slack_channel_env | {
            'SLACK_WEBHOOK': {
                'from_secret': 'slack_webhook',
        },
        'resources': {
            'limits': {
                'cpu': cpu,
             }
            }
        },
    }
    if when:
        res = res | {
            'when': when
        }
    return res

def step_command(step_name='command', commands=[], depends_on=['git-clone'], environment={}, when={}, cpu=100):
    res = {
        'name': step_name,
        'image': docker_image_sk,
        'depends_on': depends_on,
        'environment': environment | {
            'APP_NAME': {
                'from_secret': 'app_name',
            },
        },
        'commands': commands,
        'resources': {
            'limits': {
                'cpu': cpu,
            }
        }
    }
    if when:
        res = res | {
            'when': when,
        }
    return res

def step_prepare(cpu=150):
    return {
        'name': 'prepare',
        'image': docker_image_sk_utils,
        'depends_on': ['git-clone'],
        'commands': [
r'''
labsterutils/scripts/cicd/semver.sh | tee .tags
VERSION=$$(cat .tags)
set -a && . ./.drone_flags && set +a
labsterutils/scripts/cicd/slack.sh
if [ $${FLAGS_HELM_CHART} = "true" ]; then
    echo "version: $${VERSION}" >> charts/$${APP_NAME}/Chart.yaml
    if [ $${FLAGS_DOCKER_IMAGE} = "true" ]; then
    labsterutils/scripts/cicd/helm.sh $${APP_NAME} docker charts
    fi
fi
'''
        ],
        'environment': {
            'AWS_ACCOUNT_ID': {
                'from_secret': 'aws_account_id',
            },
            'ECR_REGION': {
                'from_secret': 'ecr_region',
            },
        },
        'resources': {
            'limits': {
                'cpu': cpu,
            }
        }
    }

def step_docker_image_build(cpu=2000):
    return {
        'name': 'docker-image-build',
        'image': docker_image_sk,
        'depends_on': ['prepare'],
        'commands': [
r'''
if [ "$${DOCKER_ARM64_SKIP}" = "true" ] && [ "$${DRONE_STAGE_ARCH}" = "arm64" ]; then
  exit 0
fi

set -a && . ./.drone_flags && set +a
if [ $${FLAGS_DOCKER_IMAGE} = "false" ]; then
  # Docker Image Build not enabled
  exit 0
fi

./labsterutils/scripts/k8s/wait.sh dind 2375
mkdir /root/.docker

cat <<EOF > /tmp/buildx.buildkitd.toml
[registry."docker.io"]
  mirrors = ["$${REGISTRY_MIRROR_EP}"]
  http = true
  insecure = true

[registry."public.ecr.aws"]
  mirrors = ["$${REGISTRY_MIRROR_EP}"]
  http = true
  insecure = true

[registry."$${REGISTRY_MIRROR_EP}"]
  http = true

[registry."$${REGISTRY_CACHE_EP}"]
  http = true
EOF

docker buildx create --name mybuilder --use --bootstrap --driver docker-container --config /tmp/buildx.buildkitd.toml

REG_SETTINGS="type=registry,image-manifest=true,ref=$${REGISTRY_CACHE_EP}/$${APP_NAME}:buildcache-$${DRONE_STAGE_ARCH}"
docker buildx build -o type=docker -t app:$${DRONE_COMMIT_SHA} -t app:latest \\
    --cache-to $${REG_SETTINGS},mode=max \\
    --cache-from $${REG_SETTINGS} \\
    -f Dockerfile .
'''
        ],
        'environment': docker_env,
        'resources': {
            'limits': {
                'cpu': cpu,
            }
        }
    }

def step_docker_image_test(cpu=200):
    return {
        'name': 'docker-image-test',
        'image': docker_image_sk,
        'depends_on': ['docker-image-build'],
        'commands': [
r'''
if [ "$${DOCKER_ARM64_SKIP}" = "true" ] && [ "$${DRONE_STAGE_ARCH}" = "arm64" ]; then
  exit 0
fi
set -a && . ./.drone_flags && set +a
if [ $${FLAGS_DOCKER_IMAGE} = "false" ]; then
  # Docker Image Build not enabled
  exit 0
fi

./scripts/docker-test.sh
'''
        ],
        'environment': docker_env,
        'resources': {
            'limits': {
                'cpu': cpu,
            }
        }
    }

def step_docker_image_push(arch, cpu=200):
    return {
        'name': 'docker-image-push',
        'image': docker_image_sk,
        'depends_on': ['docker-image-test'],
        'commands': [
r'''
if [ "$${DOCKER_ARM64_SKIP}" = "true" ] && [ "$${DRONE_STAGE_ARCH}" = "arm64" ]; then
  exit 0
fi
set -a && . ./.drone_flags && set +a
if [ "$${FLAGS_DOCKER_IMAGE}" = "false" ]; then
  # Docker Image Build not enabled
  exit 0
fi

if [ "$${FLAGS_PUBLIC_ECR}" = "true" ]; then
  aws ecr-public get-login-password --region $${ECR_REGION} | docker login --username AWS --password-stdin public.ecr.aws
  export IMAGE_REPO=public.ecr.aws/$${ECR_REGISTRY_ALIAS}/$${APP_NAME}
else
  ECR_ENDPOINT=$${AWS_ACCOUNT_ID}.dkr.ecr.$${ECR_REGION}.amazonaws.com
  aws ecr get-login-password --region $${ECR_REGION} | docker login --username AWS --password-stdin $${ECR_ENDPOINT}
  export IMAGE_REPO=$${ECR_ENDPOINT}/$${APP_NAME}
fi

VERSION=$$(cat .tags)

if [ "$${FLAGS_HELM_CHART}" = "true" ]; then
  export IMAGE_TAG="docker-$${VERSION}-$${ARCH}"
else
  export IMAGE_TAG="$${VERSION}-$${ARCH}"
fi

docker tag app:$${DRONE_COMMIT_SHA} $${IMAGE_REPO}:$${IMAGE_TAG}
docker push $${IMAGE_REPO}:$${IMAGE_TAG}
IMAGE_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' $${IMAGE_REPO}:$${IMAGE_TAG})
echo "Signing docker image using notation, digest: $${IMAGE_DIGEST}"
notation sign \\
    --plugin "com.amazonaws.signer.notation.plugin" \\
    --plugin-config "aws-region=$${ECR_REGION}" \\
    --id "arn:aws:signer:$${ECR_REGION}:$${AWS_ACCOUNT_ID}:/signing-profiles/notation" \\
    $${IMAGE_DIGEST}
'''
        ],
        'environment': docker_env | {
            'ARCH': arch,
        },
        'resources': {
            'limits': {
                'cpu': cpu,
            }
        }
    }

def step_docker_manifest(cpu=200):
    return {
        'name': 'docker-manifest',
        'image': docker_image_sk,
        'depends_on': [
            'prepare',
        ],
        'environment': docker_env,
        'commands': [
r'''

export DOCKER_CLI_EXPERIMENTAL=enabled

set -a && . ./.drone_flags && set +a
if [ "$${FLAGS_DOCKER_IMAGE}" = "false" ]; then
  # Docker Image Build not enabled
  exit 0
fi

unset DOCKER_HOST

if [ "$${FLAGS_PUBLIC_ECR}" = "true" ]; then
  aws ecr-public get-login-password --region $${ECR_REGION} | docker login --username AWS --password-stdin public.ecr.aws
  export IMAGE_REPO=public.ecr.aws/$${ECR_REGISTRY_ALIAS}/$${APP_NAME}
else
  ECR_ENDPOINT=$${AWS_ACCOUNT_ID}.dkr.ecr.$${ECR_REGION}.amazonaws.com
  aws ecr get-login-password --region $${ECR_REGION} | docker login --username AWS --password-stdin $${ECR_ENDPOINT}
  export IMAGE_REPO=$${ECR_ENDPOINT}/$${APP_NAME}
fi

VERSION=$$(cat .tags)

if [ "$${FLAGS_HELM_CHART}" = "true" ]; then
  export IMAGE_TAG="docker-$${VERSION}"
else
  export IMAGE_TAG="$${VERSION}"
fi

if [ -z "$${DRONE_TAG}" ] || [ "$${DOCKER_ARM64_SKIP}" = "true" ]; then
    docker manifest create $${IMAGE_REPO}:$${IMAGE_TAG} --amend $${IMAGE_REPO}:$${IMAGE_TAG}-amd64
else
    docker manifest create $${IMAGE_REPO}:$${IMAGE_TAG} --amend $${IMAGE_REPO}:$${IMAGE_TAG}-amd64 --amend $${IMAGE_REPO}:$${IMAGE_TAG}-arm64
    docker manifest annotate --arch arm64 $${IMAGE_REPO}:$${IMAGE_TAG} $${IMAGE_REPO}:$${IMAGE_TAG}-arm64
fi
docker manifest annotate --arch amd64 $${IMAGE_REPO}:$${IMAGE_TAG} $${IMAGE_REPO}:$${IMAGE_TAG}-amd64
docker manifest inspect $${IMAGE_REPO}:$${IMAGE_TAG}
docker manifest push $${IMAGE_REPO}:$${IMAGE_TAG}
'''
        ],
        'resources': {
            'limits': {
                'cpu': cpu,
            }
        }
    }

def step_helm_chart(cpu=250):
    return {
        'name': 'helm-chart',
        'image': docker_image_sk,
        'depends_on': [
            'prepare',
        ],
        'environment': {
            'AWS_ACCOUNT_ID': {
                'from_secret': 'aws_account_id',
            },
            'AWS_ACCESS_KEY_ID': {
                'from_secret': 'ecr_access_key',
            },
            'AWS_SECRET_ACCESS_KEY': {
                'from_secret': 'ecr_secret_key',
            },      
            'AWS_DEFAULT_REGION': {
                'from_secret': 'helm_s3_region',
            },      
        },
        'when': {
            'branch': {
                'exclude': [
                    'master',
                ]
            }
        },
        'commands': [
r'''
set -a && . ./.drone_flags && set +a
if [ $${FLAGS_HELM_CHART} = "true" ]; then
  helm lint $${HELM_LINTER_OPTIONS} charts/$${APP_NAME}
  export HELM_OUTPUT=$(helm package ./charts/$${APP_NAME} -d /tmp)
  export HELM_CHART_FILE=$(echo $${HELM_OUTPUT} | sed 's/.*: //')
  labsterutils/scripts/cicd/helm-ecr.sh $${APP_NAME} $${HELM_CHART_FILE}
fi
'''
        ],

        'resources': {
            'limits': {
                'cpu': cpu,
            }
        }
    }

def step_sentry_release(cpu=200):
    return {
        'name': 'sentry-release',
        'image': docker_image_sentry,
        'depends_on': [
            'prepare'
        ],
        'environment': {
            'SENTRY_AUTH_TOKEN': {
                'from_secret': 'sentry_auth_token',
            },
            'SENTRY_ORG': {
                'from_secret': 'sentry_org',
            },
            'SENTRY_URL': {
                'from_secret': 'sentry_url',
            },
        },
        'when': {
            'branch': {
                'exclude': [
                    'master',
                ]
            }
        },
        'commands': [
r'''
set -a && . ./.drone_flags && set +a
if [ $${FLAGS_SENTRY_RELEASE} = "true" ]; then
  apk --update add bash
  VERSION=$$(cat .tags)
  export SENTRY_VERSION_PREFIX=$${APP_NAME}
  labsterutils/scripts/cicd/sentry.sh $${APP_NAME} $${VERSION} charts
fi
'''
        ],
        'resources': {
            'limits': {
                'cpu': cpu,
            }
        }
    }

def step_drone_bot_message(message, depends_on=['git-clone'], cpu=200):
    return {
        'name': 'drone-bot-message',
        'image': docker_image_sk_utils,
        'depends_on': depends_on,
        'environment': {
            'ANSIBLE_TOKEN': {
                'from_secret': 'ansible_token',
            },
            'ANSIBLE_URL': {
                'from_secret': 'ansible_url',
            },
        },
        'when': {
            'status': [
                'success',
                'failure',
            ]
        },
        'commands': [
            'labsterutils/scripts/cicd/drone-bot-message.sh "{}"'.format(message),
        ],
        'resources': {
            'limits': {
                'cpu': cpu,
            }
        }
    }

def step_git_cache_common(name, cpu=200):
    return {
        'name': name,
        'image': docker_image_sk_utils,
        'environment': {
            'AWS_ACCESS_KEY_ID': {
                'from_secret': 'cache_clone_s3_access_key',
            },
            'AWS_SECRET_ACCESS_KEY': {
                'from_secret': 'cache_clone_s3_secret_key',
            },
            'S3_BUCKET': {
                'from_secret': 'cache_clone_s3_bucket',
            },
        },
        'resources': {
            'limits': {
                'cpu': cpu,
            }
        }
    }

def step_save_git_cache():
    return step_git_cache_common('save-git-cache') | {
        'commands': [
r'''
labsterutils/scripts/cicd/semver.sh | tee .version
tar cf /tmp/git.tar .
aws s3 cp /tmp/git.tar s3://$${S3_BUCKET}/${DRONE_REPO}/${DRONE_BUILD_NUMBER}/

'''
        ],       
    }

def step_restore_git_cache():
    return step_git_cache_common('git-clone') | {
        'commands': [
r'''
aws s3 cp s3://$${S3_BUCKET}/${DRONE_REPO}/${DRONE_BUILD_NUMBER}/git.tar /tmp
tar xf /tmp/git.tar .
'''
        ],       
    }

def step_cleanup_git_cache():
    return step_git_cache_common('cleanup-git-cache') | {
        'commands': [
r'''
aws s3 rm s3://$${S3_BUCKET}/${DRONE_REPO}/${DRONE_BUILD_NUMBER}/git.tar
'''
        ],       
    }

def service_redis(cpu=200):
    return {
        'name': 'redis',
        'image': docker_image_redis,
        'resources': {
            'limits': {
                'cpu': cpu,
            }
        },
        'environment': {
            'ALLOW_EMPTY_PASSWORD': 'yes',
        }
    }
