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

As an FYI, `./terraform-aws` would allow you to easily bootstrap
EC2 instances / VPC / SG / IAM / ELB / ... Based on Kubepsray
terraform samples.

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

Note: the `kubespray.rpi` folder includes inventories deploying
Kubernetes on Raspberry 3 & 4 (armv7). Requires 64b on masters, raspbian
works perfectly.
`kubespray.aws` comes from another deployment (1.20), testing/lab on AWS.

## Usage

### Ceph

If you intend to use Ceph, we would first deploying that cluster.

Having customized your inventories, we would run:

```
$ make deploy-ceph
```

Note: running on ARM, we should pull different images, ... see
`examples/ceph-csi-arm` for a sample working on Raspberry PI. Also note that
arm64 is mandatory for rbdplugin mapper to work. And that Raspbian does not
provide with rbd kernel modules: rbd-nbd should be used instead.

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
 * Tekton: `make deploy-tekton` (kubespray -- WARNING: some manual fix required
   afterwards)

Alternatively, deploying Prometheus on Kubernetes can be done using:
https://github.com/Worteks/k8s-prometheus - which includes ARM support,
missing from kube-state-metrics, as shipped by roles in the playbooks we
have here.

Deploying Kubespray, if you choosed not to deploy one of their supported
ingress controller, you may go with Traefik - see samples in `examples/traefik`.

#### EFK on Kubernetes

Note that deploying the logging stack on Kubernetes, you will then have to
connect Kibana, go to Settings, Kibana / Index Patterns, close the div on
the right side, as it hides the Create Index Pattern button.

As a pattern, we would enter `logstash-*`, confirm. The more we would wait
before doing so, the more fields we would discover. A few to look for would
be `kuberenetes.container.*`, `kubernetes.labels.*` or `SYSLOG_FACILITY`.

## Feedback

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
it was not that great on OpenShift either. Doc's accurate. Does what's
advertised. Builder ships with arm64 images: same confs work on RPI, and x86.

UPDATE: ... While those comments are quite old: as a follow-up, today using
Kaniko, which is great, despite requiring root.

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

More recently, I did apply an officiel release of cert-manager: I have
each CRD twice (in `cert-manager.io` & `certmanager.k8s.io`). Though it
works perfectly.

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

UPDATE: fixed in package, and can be configured in kubespray inventory

### Containerd Snapshots

Seen disk usage grow over time on a given node. After 9 months,
`/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs` was using >30G.
To clean it up:

```
# systemctl stop kubelet
# crictl pods | awk 'NR>1{print $1}' | xargs crictl stopp
# crictl pods | awk 'NR>1{print $1}' | xargs crictl rmp
# crictl ps -a | awk 'NR>1{print $1}' | xargs crictl rm -f
# systemctl stop containerd
# rm -fr /var/lib/containerd/io.containerd.metadata.v1.bolt/*
# rm -fr /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/*
# reboot
```

### Re-Deploying Nodes

After suffering a disk loss, I had to redeploy a master node. This can be done
with the following playbook, having edited your inventory, such as the faulty
nodes are part of some `broken_xxx` hostgroup:

```
$ ansible-playbook -i inventory/my/hosts.yml -l etcd,kube-master \
    -e etcd_retries=300 recover-control-plane.yml
```

Playbook crashed, while dealing with add-ons. I decided to comment them all out
from Ansible group vars, then re-applied the cluster deployment playbook:

```
$ ansible-playbook -i inventory/my/hosts.yml -l etcd,kube-master cluster.yml
```

Everything went fine, though I still had a regular worker to re-deploy, and
decided to use the scale-out playbook, while re-using the same node name:

```
$ ansible-playbook -i inventory/my/hosts.yml scale.yml
```

Outage dit not affect API services and cluster in general, the rest of the nodes
kept running perfectly fine.

### Upgrading Cluster

There's two kind of upgrades we could apply to a cluster deployed with
Kubespray:

- upgrading Kubernetes
- upgrading Kubepsray

Either way, there is an upgrade path to follow. For Kubernetes, starting with
1.x going to the last 1.z, we would have to go through some 1.y. In my case,
starting from 1.18.3, going to 1.20, I would have to apply a 1.19 in the way.
Re-apply the Kubespray cluster upgrade playbook going from one `kube_version`
to the next.

And upgrading Kubernetes would usually imply updating the Kubepsray playbooks
managing your cluster - at the very least, getting the right default image
versions, checksums or deployment configurations for calico, containerd, ...
depending on the Kubernetes version we're upgrading to.
As for Kubernetes, Kubespray has an upgrade path we should follow: each tag
should be applied one after the other (v2.14.0, v2.14.1, v2.14.2, ...). And if,
as me, you started deploying from the master branch: first, we have to guess
which tag to start with ...

Keeping it simple, stick to the default `kube_version` shipping with Kubespray,
and apply the upgrade playbook for each tag until you reach the right Kubernetes
version. Otherwise, make sure your `kube_version` is listed in the download
defaults: `roles/download/defaults/main.yml`.

Upgrading Kubespray, we also have to check the diffs between current and target
version copies of `inventory/sample`, look into the new variables that were
introduced, some that could have changed or others that may have gone away.
Having updated your inventory, make sure your nodes are all healthy. Make sure
no PodDisruptionBudget could prevent a node from being drained. Then apply
the upgrade playbook:

```
$ git checkout v2.14.0
$ git diff <oldtag>..v2.14.0 inventory/sample
$ vi inventory/<mine>/xxx [ update your inventory ]
$ ansible-playbook -i inventory/my/hosts.yml upgrade-cluster.yml
$ git checkout v2.14.1
$ git diff v2.14.0..v2.14.1 inventory/sample
$ vi inventory/<mine>/yyy
$ ansible-playbook -i inventory/my/hosts.yml upgrade-cluster.yml
$ git checkout v2.14.2
[ repeat ]
```

The upgrade process would run some checks, pre-download images and some
assets, then eventually start upgrading etcd, then drain and upgrade your
masters one after the other. After the first master was upgraded, parts of
Kubernetes Apps also are (CSI & RBAC, ...). After all masters were upgraded,
the SDN would be upgraded on all nodes (two by two). Then, the remaining
nodes would be upgraded as well. Goes through the apps again, updating
CoreDS, the metrics server, ...

In the end, I could not see any API failure. Which is kind of amazing, knowing
how painful OpenShift 4 upgrades can be, in terms of SDN components restarting,
API being unavailable, unless that's the OAuth operator that's being redeployed
or the nodes rebooting, ... The process took a little under two hours applying
a new version on 10 nodes. Draining and restarting Pods being quite slow,
don't hesitate to shut down useless deployments or lower the amount of replicas
whenever possible, before going through an upgrade. Pro-tip: marking a node
unschedulable before its being processed by Ansible would skip the draining
steps. One may also want to disable a few apps deployment in Kubespray, in
order to skip those tasks as well. Eg: only re-deploy the registry and ingress
controllers during your last upgrade (or manually, later on).

UPDATE: we don't actually need to apply each kubespray tag. Instead, we should
make sure to go through each minor: we can skip patches.
