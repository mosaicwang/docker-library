#!/usr/bin/bash

#脚本化部署consul

helm_ver=v1.12.2
consul_ver=v0.5.0

issetup=-1

li_iscentos=0

ls_curdate=`date +%Y%m%d`

#1.2得到当前脚本所在目录
mydir=$(dirname $(readlink -f "$0"))

#1.3得到当前脚本名称
myexefile=$(basename $(readlink -f "$0")) 

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

	用法: ${myexefile} [OPTIONS]
	
	OPTIONS如下:
	
	--install_helm      安装helm
	--install_tiller    安装tiller
	--install_consul    通过helm安装consul
	--uninstall_consul  卸载consul
	--uninstall_tiller  卸载tiller
	--help              显示脚本的用法
	"
}

#安装helm
function install_helm() {

	local ls_step="install_helm"

	#0.如果已经执行了当前步骤,则报错
	if [ -f $stepfile ]; then
	
		li_count=`cat $stepfile |grep -w ${ls_step} |wc -l`
		
		if [ $li_count -ge 1 ]; then
			echo
			echo -e "\t不能重复执行${ls_step}操作"
			echo
			exit 1
		fi
	fi
	
	echo -e "\t安装helm ${helm_ver}..."
	
	local ls_softlist=(helm-v2.12.2-linux-amd64.tar.gz rbac-config.yaml consul_pv.yaml consul-helm-0.5.0.tar.gz values.yaml)
	local ls_misssoft=( )
	
	li_count=0
	
	#1.检查相关软件是否存在:helm,rbac-config.yaml,consul_pv.yaml,consul-helm-0.5.0.tar.gz
	for ls_soft in ${ls_softlist[@]}
	do
		if [ ! -f $mydir/$ls_soft ]; then
			ls_misssoft[${li_count}]=${ls_soft}
			
			li_count=$(($li_count+1))
		fi
		
	
	done
	
	#显示缺少的文件
	if [ $li_count -gt 0 ]; then
		echo
		echo -e "\t有$li_count个文件未找到,列表如下:"
		
		for ls_soft in ${ls_misssoft[@]}
		do
			echo -e "\t $ls_soft"
		done
		
		exit 1
	fi
	
	#2.解压helm压缩包
	echo -e "\t解压helm软件"
	tar -zvxf $mydir/helm-v2.12.2-linux-amd64.tar.gz -C $mydir >/dev/null
	
	#3.3.得到当前PATH环境变量，,并将压缩包路径追加到PATH和.bashrc中(备份.bashrc)
	local ls_oldpath=`echo $PATH`
	#echo -e "\t旧PATH是$ls_oldpath"
	
	export PATH=$ls_oldpath:$mydir/linux-amd64
	
	#echo -e "\t新PATH是$PATH"
	
	echo "export PATH=$PATH" >> ~/.bashrc
	
	#判断能否找到helm
	which helm >/dev/nul 2>&1
	li_count=`echo $?`
	
	if [ $li_count -eq 0 ];then
			
		#记录步骤到日志
		echo $ls_step >> $stepfile
	
		echo -e "\t安装helm成功.接下来是执行 --install_tiller"
	else
		echo "未找到helm. 安装helm失败"
	fi
}

#安装tiller
function install_tiller() {

	local ls_step="install_tiller"
	
	#0.如果已经执行了当前步骤,则报错
	if [ -f $stepfile ]; then
	
		li_count=`cat $stepfile |grep -w ${ls_step} |wc -l`
		
		if [ $li_count -ge 1 ]; then
			echo
			echo -e "\t不能重复执行${ls_step}操作"
			echo
			exit 1
		fi
	fi
	
	echo -e "\t安装tiller..."

	#4.执行kubectl create -f rbac-config.yaml
	kubectl create -f $mydir/rbac-config.yaml >/dev/nul 2>&1
	
	#5.安装tiller
	helm init --service-account tiller \
	-i registry.aliyuncs.com/google_containers/tiller:${helm_ver} \    
	--stable-repo-url https://kubernetes.oss-cn-hangzhou.aliyuncs.com/charts
	
	#6.查找POD:tiller*，如果状态为Running,则说明tiller安装成功
	li_sec=0
	ls_status=error
	
	echo -e "\t检查toller的部署结果..."
	
	while [ $li_sec -le 60 ]
	do
		ls_status=`kubectl get pods -n kube-system |grep tiller-deploy |gawk '{print $3}'`
		
		if [ $ls_status = 'Running' ]; then
			break
		else
			#延迟5秒
			sleep 5
			li_sec=$(($li_sec+5))
		fi
		
	done
		
	
	if [ $ls_status = 'Running' ]; then 
	
		echo -e "\t启动toller成功.执行helm version或helm ls看执行结果"
		
		#记录步骤到日志
		echo $ls_step >> $stepfile	
	else
		
		echo -e "\t安装tiller疑是失败"
		echo -e "\t请执行kubectl get pods -n kube-system命令来查看tiller的状态"
	fi
	
	
}

#通过helm安装consul

function install_consul() {

	local ls_step="install_consul"
	
	#0.如果已经执行了当前步骤,则报错
	if [ -f $stepfile ]; then
	
		li_count=`cat $stepfile |grep -w ${ls_step} |wc -l`
		
		if [ $li_count -ge 1 ]; then
			echo
			echo -e "\t不能重复执行${ls_step}操作"
			echo
			exit 1
		fi
	fi
	
	echo -e "\t通过helm安装consul ${consul_ver}..."
	
	#8.创建PV:kubectl create --record -f /root/temp/consul/consul_pv.yaml
	kubectl  create -f $mydir/consul_pv.yaml > /dev/nul 2>&1
	
	#9.解压consul-helm
	tar -zvxf $mydir/consul-helm-0.5.0.tar.gz -C $mydir > /dev/null
	
	#10.替换values.yaml
	cp -p $mydir/values.yaml $mydir/consul-helm-0.5.0/
	
	#11.通过helm安装consul:helm install --name consul ./
	cd $mydir/consul-helm-0.5.0
	
	echo -e "\t开始安装..."
	
	helm install --name consul ./
	
	#12.判断consul的POD是否启动成功:kubectl get pod |grep consul-server|gawk '{print $3}' |grep Running|wc -l
	
	li_sec=0
	ls_status=error
	
	echo -e "\t检查consul的部署结果..."
	
	while [ $li_sec -le 60 ]
	do
		li_count=`kubectl get pods |grep consul-server |grep Running| wc -l`
		
		if [ $li_count -ge 1 ]; then
			
			echo -e "\t部署consul成功."
			
			#记录步骤到日志
			echo $ls_step >> $stepfile
		
			break
		else
			#延迟5秒
			sleep 5
			li_sec=$(($li_sec+5))
		fi
		
	done			
	
	if [ $li_count -eq 0 ]; then
	
		echo -e "\t部署consul可能失败"
		echo -e "\t请执行kubectl get pods 命令来查看consul的状态"
	fi
		
}

#卸载consul
function uninstall_consul() {

	myanswer=ab
	
	echo
	read -p "       是否要卸载consul?(Y/N)" myanswer
	
	if [ $myanswer = 'Y' ] || [ $myanswer = 'y' ]; then
	

	#1.如果日志文件(.step)的最后是consul,修改step文件，去掉此步骤
	local ls_step="install_consul"
	
	li_count=`cat $stepfile |grep -w ${ls_step} |wc -l`
	
	if [ $li_count -ge 1 ]; then
			
		
		#卸载consul
		
		helm del --purge consul
		
		#卸载PV
		#kubectl delete -f $mydir/consul_pv.yaml > /dev/nul 2>&1
		
		sed -i "/${ls_step}/d" $stepfile
		
		echo -e "\t卸载consul完毕"
	else
		
		echo
		echo -e "\t未执行$ls_step,无需卸载"
	fi
	
	else
		echo
		echo -e "\t取消卸载consul"
	fi
		
}

#卸载tiller
function uninstall_tiller() {

	myanswer=ab
	
	echo
	read -p "       是否要卸载consul?(Y/N)" myanswer
	
	if [ $myanswer = 'Y' ] || [ $myanswer = 'y' ]; then
	
	ls_step="install_tiller"
	
	li_count=`cat $stepfile |grep -w ${ls_step} |wc -l`
	
	if [ $li_count -ge 1 ]; then
		#卸载tiller
		helm reset
		
		kubectl delete deployment tiller-deploy --namespace kube-system
		
		rm -rf /root/.helm
		
		#
		kubectl delete -f $mydir/rbac-config.yaml
				
		sed -i "/${ls_step}/d" $stepfile
		
		echo -e "\t卸载tiller完毕"
	else
		
		echo
		echo -e "\t未执行$ls_step,无需卸载"
	fi
	
	else
		echo
		echo -e "\t取消卸载tiller"
	fi
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
        				install_helm)
        					if [ $issetup -ge 0 ]; then
                		echo 
                		echo -e "\t不能带多个选项"
                		exit 1
                	fi
                	
                	issetup=0
                  ;;
                install_tiller)
                	if [ $issetup -ge 0 ]; then
                		echo 
                		echo -e "\t不能带多个选项"
                		exit 1
                	fi
                	
                  issetup=1
                  ;;
                install_consul)
                	if [ $issetup -ge 0 ]; then
                		echo 
                		echo -e "\t不能带多个选项"
                		exit 1
                	fi
                	
                	issetup=2
                	;;
                uninstall_consul)
                	if [ $issetup -ge 0 ]; then
                		echo 
                		echo -e "\t不能带多个选项"
                		exit 1
                	fi
                	
                	issetup=3
                	;;            
                uninstall_tiller)
                	if [ $issetup -ge 0 ]; then
                		echo 
                		echo -e "\t不能带多个选项"
                		exit 1
                	fi
                	
                	issetup=4
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
	install_helm
	;;
1)
	install_tiller
	;;
2)
	install_consul
	;;
3)
	uninstall_consul
	;;
4)
	uninstall_tiller
	;;
*)	
	print_usage
	;;
esac
else	
	print_usage
fi