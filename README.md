# cloudflare 优选正确姿势！！！

> 作者：端端/Gotchaaa，转载请标明作者，感谢！

#### 帮几位pter做了一下优选，发现很多pter实际上优选姿势很差劲😅 ，特此出这个教程，方便大家在PT路上走的更轻松
#### 该教程适用于linux系统 amd架构的nas或路由器
#### arm架构的设备可以去直接替换掉下面教程中的 amd 的文件名，解压的时候注意也替换一下文件名
#### 我尽量写得详细一些，用到的命令会标出来

## 大更新！真正的自动化
下载 cfst.sh 到任意目录

`wget https://github.com/vanchKong/cloudflare/blob/main/cfst.sh`

直接运行 `bash cfst.sh` 即可，脚本默认有 `UB` 和 `ZM`

后续增加站点，或者任意网站，跑下面的命令，该命令会自动检测网站是否托管在CF下，是的情况下会自动添加记录到hosts

`bash cfst.sh -add example.com`

另外，还有移除优选域名命令： `bash cfst.sh -del example.com`，展示当前优选列表命令：`bash cfst.sh -list`


--- 
<details>
  <summary>以下是旧版教程，依然适用，上面的脚本也是在做差不多同样的事情</summary>

- ### 安装 CloudflareST
> 一般我会把它装在 /opt 目录下，当然，如果你知道自己在做什么，你可以按照自己的习惯来，OK，首先切换到 opt 目录、创建文件夹
> 
> `cd /opt`
> 
> `mkdir CloudflareST && cd CloudflareST`
>
> 然后下载CloudflareST压缩包
>
> `wget -N https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/CloudflareST_linux_amd64.tar.gz`
>
> 如果你是在国内网络环境中下载，那么请使用下面这几个镜像加速之一：
>
> `wget -N https://ghp.ci/https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/CloudflareST_linux_amd64.tar.gz`
>
> `wget -N https://ghproxy.cc/https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/CloudflareST_linux_amd64.tar.gz`
>
> `wget -N https://ghproxy.net/https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/CloudflareST_linux_amd64.tar.gz`
>
> `wget -N https://gh-proxy.com/https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/CloudflareST_linux_amd64.tar.gz`
>
> 如果下载失败的话，尝试删除 -N 参数（如果是为了更新，则记得提前删除旧压缩包 `rm CloudflareST_linux_amd64.tar.gz` ）
>
> 解压
>
> `tar -zxf CloudflareST_linux_amd64.tar.gz`
>
> 赋予目录执行权限
>
> `cd .. && chmod +x CloudflareST && cd CloudflareST`

- ### 如何判断哪些站点可以添加优选IP指向
> 任意打开一个站点，打开控制台切换至 `网络/network` 选项，保证筛选器选择的是 `全部`，刷新网页，在 `网络/network` 选项翻到第一个请求，找到 `响应标头/Response Header`，在里面找 `server`，如果 `server` 是 `cloudflare`，则代表该域名可以添加到 `hosts` 文件当中（注意，当前地址栏中是二级域名就添加二级域名，是顶级域名就添加顶级域名，不要自作聪明）。
> 
> 关于tracker：有些站点的 tracker 挂靠在cf下，有些没有，你可以手动添加一个种子下载，查看具体的 tracker 域名是什么（同样，是二级域名就复制二级域名，是顶级域名就复制顶级域名），将域名复制粘贴到浏览器打开，重复刚刚上面对于站点的步骤即可。

- ### 准备 hosts 初始文件，这里你需要会如何在linux中编辑保存文件
> 你需要编辑的文件是 `/etc/hosts`，一般命令是 `vi /etc/hosts`，进入文件后，按 `i` 进入编辑模式，按 `Esc` 退出编辑模式，退出编辑模式后按 `:wq` 保存退出，按 `:q!` 不保存强制退出
>
> 如果你之前优选过，但是不知道自己在做什么或者比较模棱两可，建议清空自己的优选（注意！不是清空整个hosts文件），以下基于你已经清空的情况
>
> 比如一个站点的域名是 abc.com，经过你的检查，它挂靠在cf下，你可以先随便写个ip，类似这样
>
> `1.1.1.1 abc.com`
>
> 注意中间是有空格的！
>
> 为了方便整理，打个比方这个abc站点的tracker域名是 t.abc.com，且同样挂靠在cf下，那么我们可以这样写
>
> `1.1.1.1 abc.com t.abc.com`

- ### 最后，开始优选
> `bash /opt/CloudflareST/cfst_hosts.sh`
>
> 第一次运行此脚本，会让你填写一个ip，该ip就填写你之前随便写的一个ip，这里就填写 `1.1.1.1`
>
> 接下来就会正常进行优选，并替换掉所有和你填写ip匹配的记录
>
> 后续添加站点：确认好域名是挂靠在cf下之后，将该域名添加到hosts文件，编辑保存即可
>
> 如果你是docker启动的qb、tr、mp、iyuu，优选后，建议重启这些容器。优选周期其实可以拉的很长，所以重启也不会很频繁

</details>
