#!/usr/bin/bash

#在kubeadm初始化k8s集群前，设置必要的环境和参数
#2018.1.18 11:07 v1.2
#2018.1.18 0:17 v1.1

k8s_ver=v1.13.2
ntp_server=192.168.1.8

issetup=-1

li_iscentos=0

ls_curdate=`date +%Y%m%d`

ls_allstep=(setup post_setup install_flannel install_dashboard)

#1.2得到当前脚本所在目录
mydir=$(dirname $(readlink -f "$0"))

#配置信息
cfgfile=$mydir/myhost.cfg

#存放步骤信息
stepfile=$mydir/myhost.step

#---------------函数定义----------------

function iscentos() {
	#判断是否为CentOS
	if [ -f /etc/centos-release ]; then
		ls_mainver=`cat /etc/centos-release | gawk -F . '{print $1}'|gawk '{print $4}'`
		
		if [ $ls_mainver -eq 7 ]; then
			li_iscentos=1
		else
			echo
			echo -e "\tCentOS的版本必须是7。当前版本是$ls_mainver"
			exit 0
		fi
	else
		li_iscentos=0
		
		#如果存在/etc/os-relase文件,则显示此文件内容
		echo -e "\t你的操作系统如下所示:"
		if [ -f /etc/os-release ]; then
			cat /etc/os-release
		fi
	fi
}

function print_usage() {

echo "\

	用法: k8s_setup.sh [OPTIONS]
	
	OPTIONS如下:
	
	--check             检查系统配置情况(缺省)
	--setup             设置基础参数
	--post_setup        安装kubeadm等关键组件
	--install_flannel   安装flannel插件
	--install_dashboard 安装仪表盘
	--show_token				显示登录仪表盘需要的TOKEN值
	--show_join         显示加入MASTER的kubeam join命令
	--help              显示脚本的用法
	"
}

function setup_env() {

	#如果步骤信息中已经存在当前步骤，则报错并退出
	if [ -f $stepfile ]; then
	
		li_count=`cat $stepfile |grep -w "setup" |wc -l`
		
		if [ $li_count -eq 1 ]; then
			echo
			echo -e "\t不能重复执行setup操作"
			echo
			exit 1
		fi
	fi

	echo -e "\t开始设置..."
	
	#1.2得到本机IP和网卡，由用户确认后保存到myhost.cfg文件
	ls_ip=`ip -h -4 -o address |gawk '{print $4}' |grep -v 127.0|sed 's/\// /'|gawk '{print $1}'`
	
	echo
	read -p "        本机的IP地址是$ls_ip吗?(Y/N)" myanswer
	
	if [ $myanswer = 'Y' ] || [ $myanswer = 'y' ]; then
		echo "ip=$ls_ip" >> $cfgfile
	else
		echo -e "\t无法得到本机IP地址。程序退出"
		exit 1
	fi
	
	#根据IP地址得到网卡名称
	ls_iface=`ip -h -4 -o address | grep $ls_ip |gawk '{print $2}'`
	echo "iface=$ls_iface" >> $cfgfile

#如果未设置DNS，则设置
li_count=`cat /etc/resolv.conf |grep nameserver|wc -l`

if [ $li_count -lt 1 ]; then
	echo "nameserver 61.139.2.69" >> /etc/resolv.conf
fi	

#1.禁止swap:修改 /etc/fstab 文件，注释掉 SWAP 的自动挂载

#1.1如果存在备份文件，则先删除当前文件再拷贝；否则是备份文件
if [ -f /etc/fstab.$ls_curdate ]; then
	rm -f /etc/fstab
	cp -p /etc/fstab.$ls_curdate /etc/fstab
else
	cp -p /etc/fstab /etc/fstab.$ls_curdate
fi

sed -i '/swap/ s/^/#/' /etc/fstab

echo -e "\t禁止swap"

#2.开放端口
#master:TCP:6443,2379-2380,10250-10252
#Worder:TCP:10250,30000-32767
#firewall-cmd --permanent --add-port=6443/tcp >/dev/nul
#firewall-cmd --permanent --add-port=2379-2380/tcp >/dev/nul
#firewall-cmd --permanent --add-port=10250-10252/tcp >/dev/nul
#firewall-cmd --permanent --add-port=30000-32767/tcp >/dev/nul
#FLANNEL #vxlan:8472/udp; udp:8285/udp
#firewall-cmd --permanent --add-port=8472/udp >/dev/nul
#firewall-cmd --permanent --add-port=8285/udp >/dev/nul
#firewall-cmd --reload >/dev/nul



#禁用防火墙
systemctl stop firewalld >/dev/nul
systemctl disable firewalld >/dev/nul

echo -e "\t禁用防火墙"

#3.设置SELinux在permissive模式
if [ -f /etc/selinux/config.$ls_curdate ];then
	rm -f /etc/selinux/config
	cp -p /etc/selinux/config.$ls_curdate /etc/selinux/config
else
	cp -p /etc/selinux/config /etc/selinux/config.$ls_curdate	
fi

sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

echo -e "\t设置SELinux为permissive"

#4.设置网络参数
if [ -f /etc/sysctl.d/k8s.conf ]; then
  rm -f /etc/sysctl.d/k8s.conf
fi
  
echo "net.bridge.bridge-nf-call-ip6tables = 1" >>/etc/sysctl.d/k8s.conf
echo "net.bridge.bridge-nf-call-iptables = 1" >>/etc/sysctl.d/k8s.conf
echo "net.ipv4.ip_forward = 1" >>/etc/sysctl.d/k8s.conf

modprobe br_netfilter
sysctl -p /etc/sysctl.d/k8s.conf > /dev/null

echo -e "\t设置网络参数"

#5.将本机IP和主机名增加到/etc/hosts文件

ls_hostname=`hostname`

#5.1显示当前主机名，提示是否需要改名
read -p "        当前主机名是【$ls_hostname】,需要修改主机名吗?(Y/N)" myanswer

#5.2如果输入选择是,则提示输入新主机名
if [ $myanswer = 'Y' ] || [ $myanswer = 'y' ]; then
	read -p "        请输入新的主机名:" ls_newhostname
	
	read -p "        新的主机名是【$ls_newhostname】,确认要修改吗?(Y/N)" myanswer
	
	#5.3提示是否修改主机名；如果是,则执行修改；否则继续
	if [ $myanswer = 'Y' ] || [ $myanswer = 'y' ]; then
		hostnamectl set-hostname $ls_newhostname
		
		li_count=`echo $?`
		
		if [ $li_count -ne 0 ]; then
				echo -e "\t修改主机名失败。"
				exit 1
		fi
		
	fi
fi

#本机ip
ls_ip=`ip -h -4 -o address |gawk '{print $4}' |grep -v 127.0|sed 's/\// /'|gawk '{print $1}'`
ls_hostname=`hostname`


#修改/etc/hosts文件的内容:新增一行:本机IP和主机名
if [ -f /etc/hosts.$ls_curdate ]; then
	rm -f /etc/hosts
	cp -p /etc/hosts.$ls_curdate /etc/hosts 
else
	cp -p /etc/hosts /etc/hosts.$ls_curdate
fi

echo -e "$ls_ip\t$ls_hostname" >>/etc/hosts

echo -e "\t设置/etc/hosts文件"

#6.为kube-proxy开启ipvs

if [ -f /etc/rc.modules ]; then
	rm -f /etc/rc.modules
fi

echo modprobe -- br_netfilter >> /etc/rc.modules
echo modprobe -- ip_vs >> /etc/rc.modules
echo modprobe -- ip_vs_rr >> /etc/rc.modules
echo modprobe -- ip_vs_wrr >> /etc/rc.modules
echo modprobe -- ip_vs_sh >> /etc/rc.modules
echo modprobe -- nf_conntrack_ipv4 >> /etc/rc.modules
chmod +x /etc/rc.modules

echo -e "\t装载ip_vs模块"

#7.安装docker必须的软件
echo -e "\t安装Docker-ce-18.06.1..."

yum makecache fast > /dev/nul
yum install -y -q curl net-tools telnet yum-utils psmisc unzip expect rsync chrony bash-completion ebtables ethtool wget socat > /dev/nul
yum install -y -q ipset ipvsadm > /dev/nul
yum install -y -q yum-utils device-mapper-persistent-data lvm2 > /dev/nul

#7.1设置NTP
myanswer=n

echo
read -p "是否设置NTP服务器为$ntp_server ?(Y/N)" myanswer

if [ $myanswer = 'Y' ] || [ $myanswer = 'y' ]; then

	if [ -f /etc/chrony.conf.$ls_curdate ]; then
		rm -f /etc/chrony.conf
		cp -p /etc/chrony.conf.$ls_curdate /etc/chrony.conf
	fi
	
	cp -p /etc/chrony.conf /etc/chrony.conf.$ls_curdate
	
	sed -i "/server 0.centos/ s/0.centos.pool.ntp.org/${ntp_server}/" /etc/chrony.conf
	sed -i '/server 1.centos/ s/^/#/' /etc/chrony.conf
	sed -i '/server 2.centos/ s/^/#/' /etc/chrony.conf
	sed -i '/server 3.centos/ s/^/#/' /etc/chrony.conf

	echo "NTP服务器是:$ntp_server"
fi

#8.安装docker

wget https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo \
 -O /etc/yum.repos.d/docker-ce.repo -q

yum makecache fast > /dev/nul

yum install -y -q docker-ce-18.06.1.ce-3.el7 > /dev/nul

systemctl enable docker
systemctl start docker

echo -e "\t安装Docker-ce-18.06.1完毕"

echo "setup" >>$stepfile

#10.提示:是否需要重启服务器? 如果选择Y,则重启服务器,否则退出
read -p "设置完毕。需要重启服务器才生效。是否现在重启(Y/N)" myanswer

if [ $myanswer = 'Y' ] || [ $myanswer = 'y' ]; then
	reboot
else
	echo
	echo "执行reboot重启服务器"
fi

}

function check_env() {

echo -e "\t开始检查设置情况..."

#1.禁止swap
ls_swap=`free -m | sed -n '3p'|gawk '{print $2}'`

if [ $ls_swap -eq 0 ];then
	echo -e "\t已设置禁止swap"
else
	echo -e "\t【未设置】禁止swap"
fi

#2.端口是否开放
#2.12.1看防火墙服务是否关闭,看返回值是否为active(0)或inactive(非0)
ls_firewall=`systemctl is-active firewalld`

if [ $ls_firewall = 'inactive' ]; then
	echo -e "\t防火墙已关闭"
else
  ls_firewall=`firewall-cmd --list-port |grep 6443|wc -l`
  
  if [ $ls_firewall -eq 1 ]; then
  	echo -e "\t已设置防火墙的相关端口"
  else
  	echo -e "\t【未设置】防火墙的相关端口"
  fi
fi

#3.检查SELinux
ls_selinux=`getenforce`

if [ $ls_selinux = 'Permissive' ]; then
	echo -e "\t已设置SELinux"
else
	echo -e "\t【未设置】SELinux"
fi

#4.检查网络相关参数
sysctl -N net.bridge.bridge-nf-call-ip6tables >/dev/nul 2>&1

ls_net=`echo $?`
if [ $ls_net -eq 0 ]; then
	echo -e "\t已设置网络参数"
else
	echo -e "\t【未设置】网络参数"
fi

#5.检查/etc/hosts文件的内容

ls_hostname=`hostname`

#5.2如果上述文件存在主机名,则认为是OK
ls_count=`cat /etc/hosts |grep $ls_hostname|wc -l`

if [ $ls_count -eq 0 ]; then
	echo -e "\t【未设置】/etc/hosts文件"
else
  echo -e "\t已设置/etc/hosts文件"
fi

#6.检查IP_VS模块是否加载
ls_count=`lsmod | grep -e ip_vs|wc -l`

if [ $ls_count -ge 1 ];then
	echo -e "\t已加载ip_vs模块"
else
	echo -e "\t【未加载】ip_vs模块"
fi

#7.检查安装docker的必备软件是否安装(ipset ipvsadm device-mapper-persistent-data lvm2)
echo -e "\t检查必要的包是否安装..."
ls_pkg=(yum-utils ipset ipvsadm device-mapper-persistent-data lvm2 docker-ce-18.06.1.ce-3.el7 kubeadm kubelet kubectl)
li_ismisspkg=0

for ls_curpkg in ${ls_pkg[@]} 
do
	yum -q -C list installed $ls_curpkg > /dev/nul 2>&1
	
	li_count=`echo $?`
	
	if [ $li_count -gt 0 ]; then
		echo -e "\t【未安装】:$ls_curpkg"
		li_ismisspkg=1
	fi
	
done

if [ $li_ismisspkg -eq 0 ]; then
	echo -e "\t已安装Docker需要的软件包"
fi

#判断docker服务是否启动

ls_count=`systemctl is-active docker`

if [ $ls_count = "active" ]; then
	echo -e "\t已启动Docker服务"
else
	echo -e "\t【未启动】Docker服务"
fi

#显示已经完成的步骤
if [ -f $stepfile ]; then
	echo -e "\t已经完成的步骤:"
	for li_step in `cat $stepfile`
	do
		echo -e "\t  - $li_step"
	done
else
	echo
	echo -e "\t请执行./k8s_setup.sh --setup"
	echo
fi

}

#安装kubeadm等核心组件
function post_setup() {

if [ -f $stepfile ]; then
	
		li_count=`cat $stepfile |grep -w "post_setup" |wc -l`
		
		if [ $li_count -eq 1 ]; then
			echo
			echo -e "\t不能重复执行post_setup操作"
			echo
			exit 1
		fi
	fi

ls_count=`systemctl is-active docker`

if [ $ls_count != "active" ]; then	
	echo -e "\tDocker服务未启动。请先执行setup操作"
	exit 1
fi

if [ ! -f $mydir/pause-amd64.tar ]; then
	echo
	echo -e "\t请将官方的pause的镜像文件pause-amd64.tar上载到$mydir目录后，重新执行"
	exit 1
fi

myip=`cat $cfgfile | grep ip|gawk -F '=' '{print $2}'`


#1.设置kubernetes仓库
echo -e "\t安装kubeadm ${k8s_ver} 的3个核心组件..."

cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=http://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=http://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg
EOF

yum makecache fast > /dev/nul

yum install -y -q kubeadm kubectl kubelet > /dev/nul

systemctl enable kubelet > /dev/nul

echo -e "\t安装kubeadm的3个核心组件完毕"

#2.装载pause镜像

docker load --input $mydir/pause-amd64.tar > /dev/nul

#3.执行kubeadm pull拉取基础镜像
echo -e "\t拉取k8s基础镜像..."

#3.1生成缺省配置文件
kubeadm config print init-defaults > $mydir/kubeadm.conf

#3.2替换参数
sed -i 's/imageRepository: k8s.gcr.io/imageRepository: registry.aliyuncs.com\/google_containers/' $mydir/kubeadm.conf

sed -i "s/kubernetesVersion: v1.13.0/kubernetesVersion: ${k8s_ver}/" $mydir/kubeadm.conf

sed -i "s/advertiseAddress: 1.2.3.4/advertiseAddress: ${myip}/" $mydir/kubeadm.conf

sed -i 's/podSubnet: ""/podSubnet: 10.244.0.0\/16/' $mydir/kubeadm.conf

#sed -i 's/serviceSubnet: 10.96.0.0\/12/serviceSubnet: 10.244.0.0\/12/' $mydir/kubeadm.conf

sed -i 's/ttl: 24h0m0s/ttl: "0"/' $mydir/kubeadm.conf

#3.3开始拉取镜像
kubeadm config images pull --config $mydir/kubeadm.conf > /dev/nul

ls_images=(apiserver controller-manager proxy scheduler coredns etcd pause)
li_miss=0
#3.4检查镜像文件是否拉取成功
for ls_curimage in ${ls_images[@]}
do
	li_count=`docker images |grep ${ls_curimage} |wc -l`
	
	if [ $li_count -eq 0 ]; then
		li_miss=$(($li_miss+1))
		echo -e "\t  缺少${ls_curimage}镜像"
	fi

done

if [ $li_miss -gt 0 ]; then
	echo
	echo -e "\t拉取镜像失败。请重新执行--post_setup操作"
	exit 1
fi

#预先修改.bashrc文件的内容
echo "export KUBECONFIG=/etc/kubernetes/admin.conf " >>~/.bashrc
echo "source <(kubectl completion bash)" >>~/.bashrc

#如果.bashrc为非可执行文件,则赋予可执行权限
if [ ! -x /root/.bashrc ]; then
	chmod +x /root/.bashrc
fi

echo "post_setup" >>$stepfile

echo -e "\t拉取k8s基础镜像完毕"

echo
echo -e "\t部署MASTER节点执行:"
echo
echo -e "\tsource ~/.bashrc" 
echo -e "\tkubeadm init --config $mydir/kubeadm.conf"
echo

}

#安装flannel插件
function install_flannel() {

	if [ -f $stepfile ]; then
	
		li_count=`cat $stepfile |grep -w "install_flannel" |wc -l`
		
		if [ $li_count -eq 1 ]; then
			echo
			echo -e "\t不能重复执行install_flannel操作"
			echo
			exit 1
		fi
	fi
	
	echo -e "\t安装flannel插件..."
	
	ls_iface=`cat $cfgfile | grep iface|gawk -F '=' '{print $2}'`
	
	#修改kube-flannel.yml中的iface值
	cp $mydir/kube-flannel.yml.old $mydir/kube-flannel.yml
	
	sed -i "/iface/ s/iface=wht/iface=${ls_iface}/" $mydir/kube-flannel.yml
	
	#装载镜像
	echo -e "\t装载flannel镜像..."
	
	docker load --input $mydir/flannel_v0.10.0-amd64.tar > /dev/nul
	
	#执行部署
	echo -e "\t部署flannel镜像..."
	kubectl apply -f $mydir/kube-flannel.yml > /dev/nul
	
	#检查容器的部署结果
	li_sec=0
	ls_status=error
	
	echo -e "\t检查flannel镜像的部署结果..."
	
	while [ $li_sec -le 60 ]
	do
		ls_status=`kubectl get pods -n kube-system |grep kube-flannel |gawk '{print $3}'`
		
		if [ $ls_status = 'Running' ]; then
			break
		else
			#延迟5秒
			sleep 5
			li_sec=$(($li_sec+5))
		fi
		
	done
	
	if [ $ls_status = 'Running' ]; then 
	
		echo -e "\t安装flannel插件成功"
	
		echo "install_flannel" >>$stepfile
	else
		
		echo -e "\t安装flannel插件疑是失败"
		echo -e "\t请执行kubectl get pods -n kube-system命令来查看flannel的状态"
	fi
	
	
}

#安装仪表盘
function install_dashboard() {
	
	if [ -f $stepfile ]; then
	
		li_count=`cat $stepfile |grep -w "install_dashboard" |wc -l`
		
		if [ $li_count -eq 1 ]; then
			echo
			echo -e "\t不能重复执行install_dashboard操作"
			echo
			exit 1
		fi
	fi
	
	echo -e "\t安装仪表盘..."
	
	ls_ip=`cat $mydir/myhost.cfg |grep ip|gawk -F = '{print $2}'`
	
	dashboard_dir=$mydir/dashboard
	
	if [ ! -d $dashboard_dir ]; then
		mkdir -p $dashboard_dir
	fi
	
	cert_dir=$mydir/certs
	
	if [ ! -d $cert_dir ]; then
		mkdir -p $cert_dir
	fi
	
	echo -e "\t创建CA"
	#1.创建CA
	openssl genrsa -des3 -passout pass:x -out $dashboard_dir/dashboard.pass.key 2048 > /dev/nul
	
	echo -e "\t创建私钥"
	#2.创建私钥
	openssl rsa -passin pass:x -in $dashboard_dir/dashboard.pass.key -out $dashboard_dir/dashboard.key > /dev/nul
	
	#3.创建CSR
	openssl req -new -key $dashboard_dir/dashboard.key -days 3650 \
	-subj "/O=system:masters/CN=kubernetes-admin" \
	-config $mydir/openssl_dashboard.conf.cnf \
	-out $dashboard_dir/dashboard.csr > /dev/nul
	
	echo -e "\t创建公钥"
	
	#4.签署CSR
	openssl x509 -req -sha256 -days 365 -in $dashboard_dir/dashboard.csr \
	-signkey $dashboard_dir/dashboard.key -out $dashboard_dir/dashboard.crt > /dev/nul
	
	#5.创建Secret对象kubernetes-dashboard-certs
	cp -p $dashboard_dir/dashboard.crt $cert_dir/
	cp -p $dashboard_dir/dashboard.key $cert_dir/

	echo -e "\t创建secret对象kubernetes-dashboard-certs"
	kubectl create secret generic kubernetes-dashboard-certs \
	--from-file=$cert_dir -n kube-system > /dev/nul
	
	echo -e "\t创建账号并绑定"
	#7.然后创建ServiceAccount:
	kubectl create -f $mydir/serviceaccount.yaml > /dev/nul
	
	#8.创建ClusterRoleBinding:
	kubectl create -f $mydir/rolebind.yaml > /dev/nul
	
	#打开防火墙的30705
	
	#firewall-cmd --permanent --add-port=30705/tcp >/dev/nul
	#firewall-cmd --reload >/dev/nul
	
	#9.执行部署
	echo -e "\t部署仪表盘"
	
	kubectl apply -f $mydir/kubernetes-dashboard.yaml > /dev/nul
	
		
	
	echo -e "\t检查仪表盘镜像的部署结果..."
	li_sec=0
	ls_status=error
	
	while [ $li_sec -le 60 ]
	do
		ls_status=`kubectl get pods -n kube-system |grep kubernetes-dashboard |gawk '{print $3}'`
		
		if [ $ls_status = 'Running' ]; then
			break
		else
			#延迟5秒
			sleep 5
			li_sec=$(($li_sec+5))
		fi
		
	done
	
	if [ $ls_status = 'Running' ]; then 
	
		echo
		echo -e "\t安装dashboard插件成功"				
	
		#11.提示仪表盘的URL
		ls_url="https://$ls_ip:30705"
	
		echo -e "\t1.仪表盘的URL是:"
		echo -e "\t  $ls_url"
	
		#12.得到令牌Bearer Token
		echo -e "\t2.令牌内容如下:"
		kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}') |grep "token:"
		
		echo "install_dashboard" >>$stepfile
	else
		
		echo
		echo -e "\t安装dashboard插件疑是失败"
		echo -e "\t请执行kubectl get pods -n kube-system命令来查看dashboard的状态"
	fi
		
}

#显示登录仪表盘需要的Token
function show_token() {

	#1.查找是否存在admin-user开头的secret
	li_count=`kubectl -n kube-system get secret | grep admin-user | wc -l`
	
	if [ $li_count -eq 0 ]; then
		echo
		echo "未找到admin-user的安全对象。请确认已经正在安装了仪表盘"
		echo
		exit 1
	else
		echo
		echo -e "\t4.令牌内容如下:"
		kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}') |grep "token:"
	fi
}

#显示加入MASTER的kubeadm join命令
function show_join() {

#1.从myhost.cfg得到master的IP地址
ls_ip=`cat $mydir/myhost.cfg |grep ip|gawk -F = '{print $2}'`

#2.从命令kubeadm token list得到TOKEN的ID:abcdef.0123456789abcdef
ls_tokenid=`kubeadm token list |grep abcdef |gawk '{print $1}'`

#3.从命令得到ca证书的discovery-token-ca-cert-hash
ls_hash=`openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
openssl rsa -pubin -outform der 2>/dev/null | \
openssl dgst -sha256 -hex | sed 's/^.* //'`

#4.合成结果字符串:
ls_joincmd="kubeadm join $ls_ip:6443 --token $ls_tokenid --discovery-token-ca-cert-hash sha256:$ls_hash"

echo
echo -e "\t 加入MASTER的kubeadm join命令如下:"
echo -e "\t $ls_joincmd"
echo
}

#---------------函数完毕-----------------


#1.如果当前用户不是root,则告警并退出
ls_user=`echo $USER`

if [ $ls_user != "root" ]; then
	echo
	echo "\t请以root用户执行本脚本"
	exit 1
fi

#1.1如果不是centos，则告警并退出
iscentos

if [ $li_iscentos -eq 0 ]; then
	echo
	echo "\t本脚本只支持CentOS操作系统"
	exit 1
fi


#1.2检查当前目录下是否存在如下文件

#[读取命令行参数]

optspec=":h-:"
while getopts "$optspec" optchar; do

    case "${optchar}" in
        -)
        case "${OPTARG}" in
        				check)
        					if [ $issetup -ge 0 ]; then
                		echo 
                		echo -e "\t不能带多个选项"
                		exit 1
                	fi
                	
                	issetup=0
                  ;;
                setup)
                	if [ $issetup -ge 0 ]; then
                		echo 
                		echo -e "\t不能带多个选项"
                		exit 1
                	fi
                	
                  issetup=1
                  ;;
                post_setup)
                	if [ $issetup -ge 0 ]; then
                		echo 
                		echo -e "\t不能带多个选项"
                		exit 1
                	fi
                	
                	issetup=2
                	;;
                install_flannel)
                	if [ $issetup -ge 0 ]; then
                		echo 
                		echo -e "\t不能带多个选项"
                		exit 1
                	fi
                	
                	issetup=3
                	;;
                install_dashboard)
                	if [ $issetup -ge 0 ]; then
                		echo 
                		echo -e "\t不能带多个选项"
                		exit 1
                	fi
                	
                	issetup=4
                	;;
                show_token)
                	if [ $issetup -ge 0 ]; then
                		echo 
                		echo -e "\t不能带多个选项"
                		exit 1
                	fi
                	
                	issetup=5                	                	
                	;;
                show_join)
                  if [ $issetup -ge 0 ]; then
                		echo 
                		echo -e "\t不能带多个选项"
                		exit 1
                	fi
                	
                	issetup=6             	                	
                	;;
                help*)
                	print_usage
                	exit
                	;;                
                *)
										echo                 	
                    echo -e "\t不支持的选项 --${OPTARG}" >&2
                    print_usage
                    exit 1
                    ;;
            esac;;
       h)
            print_usage
            exit
            ;;       
        *)
        	  if [ "$OPTERR" != 1 ] || [ "${optspec:0:1}" = ":" ]; then
            	  echo 
                echo "	不支持的参数: '-${OPTARG}'" >&2
                print_usage
                exit 1
            fi
            ;;
    esac
done


#2.如果参数为setup,则执行设置操作
#3.如果参数为check,则执行检查操作
if [ $issetup -ge 0 ]; then
case $issetup in
0)
	check_env
	;;
1)
	setup_env
	;;
2)
	post_setup
	;;
3)
	install_flannel
	;;
4)
	install_dashboard
	;;
5)
	show_token
	;;
6)
	show_join
	;;
*)
	check_env
	print_usage
	;;
esac
else
	#check_env
	print_usage
fi
