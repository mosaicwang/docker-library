## docker-library

kubernetes 相关 images 同步

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
