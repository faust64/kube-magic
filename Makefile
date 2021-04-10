CEPH_IV      = ceph-ansible/hosts
CUST_IV      = custom/hosts
KUBESPRAY_IV = kubespray/inventory/utgb/hosts.yml
OPENSHIFT_IV = openshift-ansible/hosts

CEPH_STABLE_REL      = stable-5.0
KUBESPRAY_STABLE_REL = v2.14.2
OPENSHIFT_STABLE_REL = release-3.11

CLUSTER_IS = Kubernetes

-include Makefile.cust

.PHONY: init
init:
	@@if ! test -d kubespray; then \
	    git clone https://github.com/kubernetes-sigs/kubespray; \
	    ( cd kubespray ; git checkout $(KUBESPRAY_STABLE_REL); ); \
	    mkdir -p kubespray/inventory/utgb/; \
	    cp -rp kubespray.ref/* kubespray/inventory/utgb/; \
	fi
	@@if ! test -d ceph-ansible; then \
	    git clone https://github.com/ceph/ceph-ansible; \
	    ( cd ceph-ansible ; git checkout $(CEPH_STABLE_REL); ); \
	    if test -d ceph-ansible/group_vars; then \
		mv ceph-ansible/group_vars \
		   ceph-ansible/group_vars.orig; \
	    fi; \
	    cp -rp ceph-ansible.ref/* ceph-ansible/; \
	fi
	@@if ! test -d openshift-ansible; then \
	    git clone https://github.com/openshift/openshift-ansible; \
	    ( cd openshift-ansible ; git checkout $(OPENSHIFT_STABLE_REL); ); \
	    cp -rp openshift-ansible.ref/* openshift-ansible/; \
	fi
	@@if ! ansible --version >/dev/null 2>&1; then \
	    sed -i 's|ansible==2.9.6|ansible==2.9.7|' \
		kubespray/requirements.txt; \
	    pip install -r kubespray/requirements.txt; \
	fi

.PHONY: check
check: init
	@@if ! ansible -i $(CUST_IV) -i $(KUBESPRAY_IV) \
		-i $(CEPH_IV) -m ping all >/dev/null 2>&1; then \
	    echo FATAL: some hosts are unreachable >&2; \
	    exit 1; \
	else \
	    echo NOTICE: topology checks OK - proceeding; \
	fi

##############################
### Core Components        ###
##############################
.PHONY: prep-hosts
prep-hosts: check
	@@ansible-playbook -i $(CUST_IV) -i $(KUBESPRAY_IV) \
	    -i $(CEPH_IV) custom/cluster-prep.yaml \
	    2>&1 | tee -a cluster-prep.log

.PHONY: deploy-kube
deploy-kube: check
	@@( \
	    cd kubespray; \
	    ansible-playbook -i ../custom/$(CUST_IV) \
		-i ../$(KUBESPRAY_IV) -i ../$(CEPH_IV) \
		./cluster.yml; \
	) 2>&1 | tee -a deploy-kube.log

.PHONY: deploy-openshift
deploy-openshift: check
	@@( \
	    cd openshift-ansible; \
	    ansible-playbook -i ../custom/$(CUST_IV) \
		-i ../$(OPENSHIFT_IV) -i ../$(CEPH_IV) \
		./playbooks/deploy_cluster.yml; \
	) 2>&1 | tee -a deploy-openshift.log

.PHONY: deploy-ceph
deploy-ceph: check
	@@( \
	    cd ceph-ansible; \
	    ansible-playbook -i ../custom/$(CUST_IV) \
		-i ../$(CEPH_IV) ./site.yml; \
	) 2>&1 | tee -a deploy-ceph.log

##############################
### Third-Party Components ###
##############################
.PHONY: deploy-logging
deploy-logging: check
	@@if test "$(CLUSTER_IS)" = Kubernetes; then
	    ansible-playbook -i $(KUBESPRAY_IV) \
		custom/logging.yaml 2>&1 | \
		tee -a deploy-logging.log; \
	else \
	    ( cd openshift-ansible; \
		ansible-playbook -i ../custom/$(CUST_IV) \
		    -i ../$(OPENSHIFT_IV) -i ../$(CEPH_IV) \
		    -e openshift_logging_install_logging=True \
		    ./playbooks/openshift-logging/config.yml; \
	    ) 2>&1 | tee -a deploy-logging.log; \
	fi

.PHONY: deploy-prometheus
deploy-prometheus: check
	@@if test "$(CLUSTER_IS)" = Kubernetes; then
	    ansible-playbook -i $(KUBESPRAY_IV) \
		custom/prometheus.yaml 2>&1 | \
		tee -a deploy-prometheus.log; \
	else \
	    ansible-playbook -i $(OPENSHIFT_IV) \
		custom/prometheus.yaml 2>&1 | \
		tee -a deploy-prometheus.log; \
	fi

.PHONY: deploy-post
deploy-post: check
	@@if test "$(CLUSTER_IS)" = Kubernetes; then \
	    ansible-playbook -i $(CUST_IV) \
		-i $(KUBESPRAY_IV) -i $(CEPH_IV) \
		custom/cluster-post.yaml 2>&1 | \
		tee -a deploy-post.log; \
	else \
	    ansible-playbook -i $(CUST_IV) \
		-i $(OPENSHIFT_IV) -i $(CEPH_IV) \
		custom/cluster-post.yaml 2>&1 | \
		tee -a deploy-post.log; \
	fi

.PHONY: deploy-tekton
deploy-tekton: check
	@@ansible-playbook -i $(KUBESPRAY_IV) \
	    custom/tekton.yaml 2>&1 | tee -a deploy-tekton.log
