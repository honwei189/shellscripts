#!/bin/sh
###
 # @description       : k8s installation script.  To install k8s, must install docker first
 # @version           : "1.0.0" 
 # @creator           : Gordon Lim <honwei189@gmail.com>
 # @created           : 08/04/2020 12:13:12
 # @last modified     : 08/04/2020 15:08:15
 # @last modified by  : Gordon Lim <honwei189@gmail.com>
 ###


echo "br_netfilter" >> /etc/modules-load.d/br_netfilter.conf
modprobe br_netfilter
echo "net.bridge.bridge-nf-call-ip6tables = 1">> /etc/sysctl.d/01-custom.conf
echo "net.bridge.bridge-nf-call-iptables = 1">> /etc/sysctl.d/01-custom.conf
echo "net.bridge.bridge-nf-call-arptables = 1" >> /etc/sysctl.d/01-custom.conf
sysctl -p /etc/sysctl.d/01-custom.conf

dnf install -y yum-utils device-mapper-persistent-data lvm2

cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF

systemctl daemon-reload

cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

dnf install iproute-tc kubeadm kubelet kubectl kubernetes-cni -y

systemctl enable --now kubelet

#To initialize Kubernetes cluster, must disable swap:
swapoff -a 

#To disable swap permanent, edit /etc/fstab
#Comment out the line that starts with /dev/mapper/cl-swap     swap
#or issue this command:
sudo sed -i.bak '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab 


systemctl restart kubelet && systemctl enable kubelet

firewall-cmd --permanent --add-port=6443/tcp
firewall-cmd --permanent --add-port=2379-2380/tcp
firewall-cmd --permanent --add-port=10250/tcp
firewall-cmd --permanent --add-port=10251/tcp
firewall-cmd --permanent --add-port=10252/tcp
firewall-cmd --permanent --add-port=10255/tcp
firewall-cmd --permanent --add-port=8080/tcp
firewall-cmd --reload

#Initialize the Kubernetes Cluster
kubeadm init --pod-network-cidr 192.168.0.0/16 --service-cidr 10.96.0.0/12 --service-dns-domain "k8s" --apiserver-advertise-address192.168.0.0


#Add to a user:

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=$HOME/.kube/config
export KUBECONFIG=$HOME/.kube/config | tee -a ~/.bashrc


#Install at least one network provider on master
kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"


#Nodes: Setup and connect:
#kubeadm join 192.192.192.192:6443 --token ma53bs.fp0uwi2gc9p9efki \
#    --discovery-token-ca-cert-hash sha256:e756d6706e02f45dc1fa5d6254989d86612ed67aa0f6cd2fc2a2fe5462106vfc


#Deploy a POD Network to the Cluster:
kubectl apply -f http://docs.projectcalico.org/v2.3/getting-started/kubernetes/installation/hosted/kubeadm/1.6/calico.yaml


#Install Minikube

cat <<EOF > /etc/yum.repos.d/virtualbox.repo
[virtualbox]
name=Oracle Linux / RHEL / CentOS-7 / x86_64 - VirtualBox
baseurl=https://download.virtualbox.org/virtualbox/rpm/rhel/7/x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://www.virtualbox.org/download/oracle_vbox.asc
EOF
dnf update -y
dnf install VirtualBox
virtualbox --version


#If you got messages about not installed module, you need to build a driver by doing :
#dnf -y install binutils gcc make patch libgomp glibc-headers glibc-devel kernel-headers kernel-devel dkms
#reboot
#/usr/lib/virtualbox/vboxdrv.sh setup
#virtualbox --version


curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 \
&& chmod +x minikube
install minikube /usr/local/bin
minikube start
