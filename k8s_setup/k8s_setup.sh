#!/usr/bin/bash

#在kubeadm初始化k8s集群前，设置必要的环境和参数

issetup=-1
ispost_setup=-1

li_iscentos=0

ls_curdate=`date +%Y%m%d`

#1.2得到当前脚本所在目录
mydir=$(dirname $(readlink -f "$0"))

#---------------函数定义----------------

function iscentos() {
	#判断是否为CentOS
	if [ -f /etc/centos-release ]; then
		li_iscentos=1
	else
		li_iscentos=0
	fi
}

function print_usage() {

echo "\

	用法: k8s_setup.sh [OPTIONS]
	
	OPTIONS如下:
	
	--setup       设置基础参数
	--post_install  安装kubeadm等关键组件
	--check       检查参数是否设置(缺省)
	--help        显示脚本用法
	"
}

function setup_env() {

	#如果同时设置了命令行参数--post_setup,则报错
  if [ $ispost_setup -eq 1 ]; then
  	echo -e "\t命令行参数错误。只能设置一个操作"
  	exit 1
  fi
  
	echo -e "\t开始设置..."

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
firewall-cmd --permanent --add-port=6443/tcp
firewall-cmd --permanent --add-port=2379-2380/tcp
firewall-cmd --permanent --add-port=10250-10252/tcp
firewall-cmd --permanent --add-port=30000-32767/tcp
firewall-cmd --reload

echo -e "\t开放防火墙的相关端口"

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
sysctl -p /etc/sysctl.d/k8s.conf

echo -e "\t设置网络参数"

#5.将本机IP和主机名增加到/etc/hosts文件

ls_hostname=`hostname`

#5.1显示当前主机名，提示是否需要改名
read -p "当前主机名是【$ls_hostname】,需要修改主机名吗?(Y/N)" myanswer

#5.2如果输入选择是,则提示输入新主机名
if [ $myanswer = 'Y' ] || [ $myanswer = 'y' ]; then
	read -p "请输入新的主机名:" ls_newhostname
	
	read -p "新的主机名是【$ls_newhostname】,确认要修改吗?(Y/N)" myanswer
	
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

#8.安装docker

wget https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo \
 -O /etc/yum.repos.d/docker-ce.repo -q

yum makecache fast > /dev/nul

yum install -y -q docker-ce-18.06.1.ce-3.el7 > /dev/nul

systemctl enable docker
systemctl start docker

echo -e "\t安装Docker-ce-18.06.1完毕"

#10.提示:是否需要重启服务器? 如果选择Y,则重启服务器,否则退出
read -p "设置完毕。需要重启服务器才生效。是否现在重启(Y/N)" myanswer

if [ $myanswer = 'Y' ] || [ $myanswer = 'y' ]; then
	reboot
fi

}

function check_env() {

if [ $ispost_setup -eq 1 ]; then
  	echo -e "\t命令行参数错误。只能设置一个操作"
  	exit 1
  fi

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

}

#安装kubeadm等核心组件
function post_setup() {

if [ $issetup -ge 0 ]; then
  	echo -e "\t命令行参数错误。只能设置一个操作"
  	exit 1
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

#输入本机IP地址
li_count=0

while [ $li_count -eq 0 ]
do

read -p "请输入本机IP地址:" myip

#确认输入是否有效
li_count=`ip -h -4 -o address |grep $myip |wc -l`

if [ $li_count -eq 0 ]; then
	echo
	echo -e "\t输入的IP地址无效。请重新输入"
fi

done


#1.设置kubernetes仓库
echo -e "\t安装kubeadm v1.13.2的3个核心组件..."

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

yum install -y -q kubeadm-1.13.2 kubectl-1.13.2 kubelet-1.13.2 > /dev/nul

echo -e "\t安装kubeadm的3个核心组件完毕"

#2.装载pause镜像

docker load --input $mydir/pause-amd64.tar > /dev/nul

#3.执行kubeadm pull拉取基础镜像
echo -e "\t拉取k8s基础镜像..."

#3.1生成缺省配置文件
kubeadm config print init-defaults > $mydir/kubeadm.conf

#3.2替换参数
sed -i 's/imageRepository: k8s.gcr.io/imageRepository: registry.aliyuncs.com\/google_containers/' $mydir/kubeadm.conf

sed -i 's/kubernetesVersion: v1.13.0/kubernetesVersion: v1.13.2/' $mydir/kubeadm.conf

sed -i "s/advertiseAddress: 1.2.3.4/advertiseAddress: ${myip}/" $mydir/kubeadm.conf

sed -i 's/podSubnet: ""/podSubnet: 10.244.0.0\/16/' $mydir/kubeadm.conf

#3.3开始拉取镜像
kubeadm config images pull --config $mydir/kubeadm.conf

ls_images=(apiserver controller-manager proxy scheduler coredns etcd pause)
#3.4检查镜像文件是否拉取成功
for ls_curimage in $ls_images
do
	li_count=`docker images |grep ${ls_curimage} |wc -l`
	
	if [ $li_count -eq 0 ]; then
		echo -e "\t缺少${ls_curimage}镜像"
	fi

done

echo -e "\t拉取k8s基础镜像完毕"

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
	echo "\t当前操作系统不是CentOS，脚本不支持"
	exit 1
fi 

#[读取命令行参数]
optspec=":h-:"
while getopts "$optspec" optchar; do

    case "${optchar}" in
        -)
        case "${OPTARG}" in                
                setup)
                    issetup=1
                    ;;
                post_install)
                		ispost_setup=1
                		;;
                check*)
                    issetup=0
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
        	  #echo abcde:-$OPTARG
        	#echo "OPTARG:${OPTARG},optchar:${optchar}"
        		
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
if [ $issetup -gt 0 ]; then
case $issetup in
0)
	check_env
	;;
1)
	setup_env
	;;
*)
	check_env
	print_usage
	;;
esac

else
 if [ $ispost_setup -eq 1 ]; then
 	 post_setup
 else
   check_env
	 print_usage
 fi
 
fi
