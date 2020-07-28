# Kube Magic

Bringing together [KubeSpray](https://github.com/kubernetes-sigs/kubespray),
[Ceph-Ansible](https://github.com/ceph/ceph-ansible) and
[OpenShift-Ansible](https://github.com/openshift/openshift-ansible)
deploying Kubernetes.

Refer to KubeSpray, OpenShift-Ansible and Ceph-Ansible respective
documentations preparing to deploy your clusters - the main purpose
of this repository being to centralize every inventories involved,
as well as adding third party components such as the EFK stack,
integrating with Nagios based monitoring, ... or some
HAProxy / Keepalived external Load Balancer serving Kubernetes API.

## Inventories Setup

We would start by pulling upstream repositories:

```
$ make init
```

We now have the following Ansible inventories:

 * `custom/hosts`, variables in `custom/group_vars`, with hosts and
   settings specific to this repository
 * `kubespray/inventory/utgb/hosts.yml` and
   `kubespray/inventory/utgb/group_vars`, for everything specific to
   KubeSpray
 * Ceph-Ansible specifics would be in `ceph-ansible/hosts` and
   `ceph-ansible/group_vars`
 * OpenShift would be deployed using `openshift-ansible/hosts` and
   `openshift-ansible/group_vars`.

Depending on what you would want to setup, we would patch the corresponding
inventories, listing servers the servers we would deploy to, and Ansible
variables setting the specifics for our cluster, such as domain names,
proxies, DNS, NTP configuration, ... Or in the case of OpenShift: LDAP
authentication.

## Usage

### Ceph

If you intend to use Ceph, we would first deploying that cluster.

Having customized your inventories, we would run:

```
$ make deploy-ceph
```

### KubeSpray

Then prepare for KubeSpray deployment, setting up External LoadBalancers,
proper Ceph repository, preparing a RBD pool, initializing Ansible
variables for Kubernetes to authenticate againt Ceph, ... using:

```
$ make prep-hosts
```

Then proceed with Kubespray deployment:

```
$ make deploy-kube
```

### OpenShift

Dealing with OpenShift, we would deploy our cluster:

```
$ make deploy-openshift
```

### Post Kubernetes/OpenShift Deployment

Setting up Nagios monitoring, backups, or OpenShift persistent storage
and LDAP Groups sync, we would then use:

```
$ make deploy-post
```

Eventually, we may deploy additional components, such as:

 * Logging stack: `make deploy-logging` (kubespray/openshift)
 * Monitoring stack: `make deploy-prometheus` (kubespray/openshift)
 * Tekton: `make deploy-tekton` (kubespray -- WARNING: some manual fix required afterwards)

#### EFK on Kubernetes

Note that deploying the logging stack on Kubernetes, you will then have to
connect Kibana, go to Settings, Kibana / Index Patterns, close the div on
the right side, as it hides the Create Index Pattern button.

As a pattern, we would enter `logstash-*`, confirm. The more we would wait
before doing so, the more fields we would discover. A few to look for would
be `kuberenetes.container.*`, `kubernetes.labels.*` or `SYSLOG_FACILITY`.

## Feedback

As of June 2020.

### Buildah

The first inconsistency I would find, comparing with OpenShift, is that I can
not run Buildah on unprivileged containers, building my images. Using either
the default or VFS drivers (the latter did help in OCP), which gives different
error messages.

As far as I understand, this would have to do with Apparmor being enabled on
my (Debian buster) nodes. Build fails with a permission denied, writing on
some emptyDir.

Allowing my tekton ServiceAccount to run privileged pod, buildah builds do
work as intended. An to be fair, even openshift tektoncd samples would run
those as root - as reported, openshift/pipelines-catalog#17 . Quite a shame,
considering that unprivileged capbility is one of the main argument buildah
has -- and it's either poorly performing, or not at all ...

Another issue we would encounter with Buildah alongside Containerd, is due
to some wrong metadata dealing with compressed images. Though that bug was
allegedly fixed, latest images still randomly reproduce the issue (not all
of them affected). This could be fixed disabling compression pushing
images - which is definitely not a good solution, though at least it works.

https://github.com/containers/buildah/issues/1589#issuecomment-504504999
https://github.com/containers/buildah/issues/1589#issuecomment-542509369
https://www.mankier.com/1/buildah-push#--disable-compression

In some case, disabling compression did not fix. Noticing the remaining
deployments all used images builds on top of other custom images
(eg: apache -> php -> whitepages), I tried to manually pull base images,
which fixed ... A better solution would then to add some extra option to
buildah (not required on OpenShift, unclear wtf)

https://github.com/containers/image/issues/733#issuecomment-625867772

Overall: quite disappointed by Buildah on Kubernetes - while, to be frank,
it was not that great on OpenShift either.

### CephFS Provisioner

Currently running version 1.2.2 of the cephfs-provisioner, I noticed that
PVC deletion may never complete. While the PVC itself is indeed deleted,
the Secret that was created accessing our Volume would remain in our
Namespace. The Persistent Volume object would remain in a Released state,
despite my StorageClass reclaimPolicy being set to Delete. Both of which
would prevent re-creating a PVC you would have deleted.

### Cert-Manager

The cert-manager operator does not work, as deployed by kube-spray (master
branch, I should have picked a release first, ...). Looks like we're in
between two API versions, the operator is lacking permissions over the
objects it wants to use. If I fix RBAC, the the api server refuses the
objects created by the operator. The operator image is most definitely wrong,
in relation to the RBAC/CRD configuration loaded by kube-spray.

Fixing this is still in my todo, I've been manually generating self-signed
(see `custom/roles/logging`, setting up Kibana Ingress certificate).

### ETCd Quotas

While first deploying kubernetes using those playbooks, I made a mistake in
setting `etcd_quota_backend_bytes` to 20Mi, instead of 20Gi. Realizing this,
I corrected the `/etc/etcd.env` on two out of three masters, leaving the last
one intact, to see what would happend.

About 5 days after initial deployment, while porting an OCP operator to work
in vanilla k8s (lots of objects creation/updates/deletion and do-overs, ...),
I eventually reached a point where any kubectl command that might have written
something into etcd would fail. In most case, the associated error message
would be clear enough, including something like `mvcc: database space exceeded`.

Empirically, we can see that having all three members healthy, yet only one
of them reaching its quota, would result in an alarm being set for the whole
cluster.

Querying etcd cluster status, we can see all members are here. A column mentions
some `20MB`, matching my initial quota.

```
. /etc/etcd.env
ENDPOINTS=$(echo $ETCD_INITIAL_CLUSTER | sed  -e 's|etcd[0-9]=||g' -e 's|2380|2379|g')
ETCDCTL_API=3 etcdctl --cert=$ETCD_PEER_CERT_FILE --key=$ETCD_PEER_KEY_FILE \
    --cacert=$ETCDCTL_CA_FILE --endpoints=$ENDPOINTS endpoint status
```

We could try compating our database, keeping in mind this process should run in
background, so don't hope too much out of this:

```
ETCDCTL_API=3 etcdctl --cert=$ETCD_PEER_CERT_FILE --key=$ETCD_PEER_KEY_FILE \
    --cacert=$ETCDCTL_CA_FILE --endpoints=$ENDPOINTS endpoint status \
    --write-out="json" | egrep -o '"revision":[0-9]*' | egrep -o '[0-9].*'
<returns-a-revision-number>
ETCDCTL_API=3 etcdctl --cert=$ETCD_PEER_CERT_FILE --key=$ETCD_PEER_KEY_FILE \
    --cacert=$ETCDCTL_CA_FILE --endpoints=$ENDPOINTS compact <revision-number>
```

While compaction did not help, I eventually went with defrag, which did:

```
ETCDCTL_API=3 etcdctl --cert=$ETCD_PEER_CERT_FILE --key=$ETCD_PEER_KEY_FILE \
    --cacert=$ETCDCTL_CA_FILE --endpoints=$ENDPOINTS defrag
```

Then, do not forget to clear the alarm:

```
ETCDCTL_API=3 etcdctl --cert=$ETCD_PEER_CERT_FILE --key=$ETCD_PEER_KEY_FILE \
    --cacert=$ETCDCTL_CA_FILE --endpoints=$ENDPOINTS alarm disable
```

Note that while, at that stage, etcd logs would confirm there is no more
quota issue, we may want to restart the whole cluster, forcing all components
to acknowledge this -- I could not kubectl exec, logs, ... restarting a pod
ended up in one being stuck in "terminating" while the other in
"containercreating", ... situation was quite fucked up.

At which point, I would argue there's no "right" value to pass that
`etcd_quota_backend_bytes` variable. It would probably be safer to leave it
undefined and use a dedicated logical volume hosting etcd data - maybe with
asymetrical capacities, making sure they would not get full all at once, and
keeping some space available in the parent volume group, which could fasten
recovery, especially if not everyone in your team knows about etcd operations.

### Pulling Container Images from Insecure Registries

Using containerd runtime, it is not yet possible to pull images from an
insecure registry, unless we have some CA to trust on Kubernetes hosts.
Such registry would remain usable with Tekton and Buildah, though we would
not be able to run containers out of it.

Feature has been added to containerd 1.4.0-beta.0, kube-spray currently ships
with 1.2.13-2 on Debian buster.

In the meantime, when self-signing certificates without a CA, or no way to
easily trust new CAs into Kubernetes hosts (eg: operator), then http registries
could still be used.
