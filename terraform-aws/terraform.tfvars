#Global Vars
aws_cluster_name = "sammar"

#VPC Vars
aws_vpc_cidr_block       = "10.250.192.0/18"
aws_cidr_subnets_private = ["10.250.192.0/20", "10.250.208.0/20"]
aws_cidr_subnets_public  = ["10.250.224.0/20", "10.250.240.0/20"]

#Bastion Host
aws_bastion_num = 1
aws_bastion_size = "t3.small"

#Kubernetes Cluster
aws_kube_master_num  = 3
aws_kube_master_size = "t3.medium"
aws_kube_master_disk_size = 50

aws_etcd_num  = 0
aws_etcd_size = "t3.medium"
aws_etcd_disk_size = 50

aws_kube_worker_num  = 3
aws_kube_worker_size = "t3.medium"
aws_kube_worker_disk_size = 50

#Settings AWS ELB
aws_elb_api_port                = 6443
k8s_secure_api_port             = 6443

default_tags = {
  TerraformedBy = "sammar"
}

inventory_file = "../../../inventory/hosts"