## docker-library

kubernetes 相关 images 同步

#2019.1.29
1.`k8s_setup.sh` 新增命令行参数` --show_join `用于显示非MASTER节点加入时的命令

2.修改BUG

#2019.1.23
新增部署consul的脚本:consul_setup.sh

考虑到打包文件大，因此没有上传打包文件

# 2019.1.22
1.重新打包所需的文件
2.修改k8s_setup.sh:禁用防火墙

# 2019.1.18

-新增k8s_setup脚本
此脚本基于Centos7,能自动设置部署k8s的基础环境

	检查当前操作系统的配置情况
	./k8s_setup --check
	
	安装基础包和docker
	./k8s_setup --setup
	
	在安装了基础包和docker后，安装kubeadm，并拉取基础镜像
	./k8s_setup --post_install


# 2018.12.4
- 新增 node-problem-detector

# 2018.11.15

新增coredns,版本:1.2.2(因为kubernetes1.12需要这个组件)

修改kube-dns的版本

- k8s-dns-kube-dns-amd64:1.14.13
- k8s-dns-dnsmasq-nanny-amd64:1.14.13
- k8s-dns-sidecar-amd64:1.14.13

免密提交GIT

# 2018.11.14
* 更新kubernetes为1.12,因此同步更新镜像

- etcd-amd64:3.2.24
- kube-apiserver-amd64:v1.12.2
- kube-controller-manager-amd64:v1.12.2
- kube-proxy-amd64:v1.12.2
- kube-scheduler-amd64:v1.12.2
- pause-amd64:3.1
- kubernetes-dashboard-amd64:v1.10.0
- flannel:v0.10.0-amd64

# 2016.6.28
* 新增defaultbackend-amd64镜像。当前版本是1.4

# 2018.6.27
* 新增nginx-ingress-controller .当前版本是0.9.0-beta.15
* k8s核心模块更新到v1.10.5版本,包括:kube-apiserver-amd64,kube-controller-manager-amd64,kube-proxy-amd64,kube-scheduler-amd64,kube-aggregator_amd64

# 2018.2.9

* 将echoserver版本升级到amd64的1.8
* 新增echoserver项目,显示请求的源IP。目前版本是k8s.gcr.io/echoserver:1.4

# 2018.2.2

* 新增google-samples项目,提供helloworld功能。目前版本是gcr.io/google-samples/node-hello:1.0

# 2018.1.25

* 新增node-test项目,用于测试节点是否满足k8s的最低要求,即能否加入k8s集群。目前版本是k8s.gcr.io/node-test:0.2

# 2018.1.5

* 修改k8s-dns三个版本为1.14.7。这个版本是kubernetes v1.9.0用的

# 2018.1.4

* 修改etcd的Dockerfile为3.1.10。这个版本是kubernetes v1.9.0用的

# 2018.1.3

* 新增监控组件heapster v1.5.0
	
	包括两个目录:heapster-amd64和addon-resizer(addon-resizer:1.8.1)

# 2017.12.24
* 将kube的4个组件版本升级到1.9.0
* 将本文采用markdown格式书写
	
# 2017.12.23
* 删除无关的目录
* 新增目录kube-aggregator-amd64
	  
# 2017.12.23

	kube-apiserver-amd64:v1.8.4
	kube-controller-manager-amd64:v1.8.4
	kube-scheduler-amd64:v1.8.4
	kube-proxy-amd64:v1.8.4
	etcd-amd64:3.0.17
	pause-amd64:3.0
	k8s-dns-sidecar-amd64:1.14.5
	k8s-dns-kube-dns-amd64:1.14.5
	k8s-dns-dnsmasq-nanny-amd64:1.14.5
	flannel:v0.9.1-amd64
