# Kubernetes on AWS with Terraform

This is a patch of https://github.com/kubernetes-sigs/kubespray/tree/master/contrib/terraform/aws

Refer to their documentation.

Main changes here involve:

 - making etcd deployment optional / collocation with control planes
 - sizing disks / default 8G is just too little to do anything
 - controling how many bastions would be provisioned / lower EIP consumption
 - generating inventory including the `calico_rr` hostgroup
 - removing spurious variables / fixing terraform warnings
