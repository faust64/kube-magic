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

Using LDAP authentication, we would then schedule LDAP Groups sync with:

```
$ make deploy-ldap-groupsync
```

### Post Kubernetes/OpenShift Deployment

Eventually, we may deploy additional components, such as:

 * Logging stack: `make deploy-logging` (kubespray)
 * Nagios monitoringn: `make deploy-nagios` (kubespray/openshift)
 * Tekton: `make deploy-tekton` (kubespray -- WARNING: some manual fix required afterwards)
