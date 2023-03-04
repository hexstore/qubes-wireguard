# Qubes WireGuard

这是一个在Qubes OS中安装WireGuard作为ProxyVM的方案，旨在帮助Qubes OS用户增强网络传输安全，同时它可被用做多重代理。

该项目主仓库在[sourcehut](https://git.sr.ht/~qubes/wireguard)上，并镜像在[GitHub](https://github.com/hexstore/qubes-wireguard)。

## 使用场景

它工作模式如下，也许您有自己的方案！

- sys-net <- sys-firewall <- sys-proxy <- **sys-wireguard** <- AppVM(s)

## 前提条件

- Qubes OS
- WireGuard代理
- 一个支持UDP网络的代理（可选）

注意：如果您在中国或者伊朗等地使用WireGuard，您可能需要借助一个支持UDP网络的代理工具才能成功连接。

## 安装

这里使用的模板是[Debian 11](https://www.qubes-os.org/doc/templates/debian/)，您可以基于自己的模板调整对应的操作指令。

在模板中安装WireGuard，这是使用的官方APT源安装，如果您使用的是不同的系统，可参考WireGuard官方提供的[安装方法](https://www.wireguard.com/install/)。

```bash
[user@dom0 ~]$ qvm-start debian-11
[user@dom0 ~]$ qrexec-client -W -d debian-11 root:'apt install wireguard --no-install--recommends'
[user@dom0 ~]$ qvm-shutdown --wait debian-11
```

创建一个代理qube，它被命名为**sys-wireguard**，基于已经安装了WireGuard的模板**debian-11**。

```bash
[user@dom0 ~]$ qvm-create sys-wireguard --class AppVM --label blue
[user@dom0 ~]$ qvm-prefs sys-wireguard provides_network true
[user@dom0 ~]$ qvm-prefs sys-wireguard autostart true
[user@dom0 ~]$ qvm-prefs sys-wireguard memory 500
[user@dom0 ~]$ qvm-prefs sys-wireguard maxmem 500
```

接下来登入`sys-wireguard`并切换到`root`用户之后再操作。

```bash
[user@dom0 ~]$ qvm-run sys-wireguard gnome-terminal
[user@sys-wireguard ~]$ sudo -i
```

下载设置模板和脚本到本地。

```bash
[root@sys-wireguard ~]# curl -o setup.sh --proto "=https" -tlsv1.2 -SfL https://git.sr.ht/~qubes/wireguard/blob/main/setup.sh
[root@sys-wireguard ~]# curl -o wireguard.conf --proto "=https" -tlsv1.2 -SfL https://git.sr.ht/~qubes/wireguard/blob/main/wireguard.conf.template
```

更改设置模板`wireguard.conf`中的相应WireGuard变量值为自己的，分别是以下选项。

- **WG_PRIVATE_KEY**: WireGuard peer客户端的private key
- **WG_ADDRESS**: WireGuard peer客户端的地址，例如：`10.10.10.2/32`
- **WG_DNS**: WireGuard DNS，默认：`1.1.1.1`
- **WG_PUBLIC_KEY**: WireGuard peer客户端的public key
- **WG_PRESHARED_KEY**: WireGuard peer客户端的preshared key，可选项
- **WG_ENDPOINT**: WireGuard interface服务端的地址，例如：`12.34.56.78:51820`或`example.com:51820`

然后执行设置脚本`bash setup.sh`，没有意外的话，此时的`sys-wireguard`已经被配置为一个ProxyVM，被重启之后它可以实现转发流量到WireGuard服务端。

```bash
[user@dom0 ~]$ qvm-shutdown --wait sys-wireguard
[user@dom0 ~]$ qvm-start sys-wireguard
```

使用`curl ipinfo.io`命令来检查**sys-wireguard**是否成功连通，如果显示的是WireGuard服务端的IP地址，那么恭喜你，你已经成功了。

```bash
[user@dom0 ~]$ qrexec-client -W -d sys-wireguard 'curl ipinfo.io'
```

## 贡献

您在使用这个项目的过程中发现任何问题或疑问，可以随时[创建ticket](https://todo.sr.ht/~qubes/wireguard)，我们将会尽快解答。另外，您有任何改进方案，欢迎提交一个[patch](https://git.sr.ht/~qubes/wireguard/send-email)。

## 相关

- [Qubes OS](https://www.qubes-os.org/)
- [WireGuard](https://www.wireguard.com/)
- [WireGuard with obfuscation support - net4people/bbs](https://github.com/net4people/bbs/issues/88)
- [Obfuscating Wireguard - net4people/bbs](https://github.com/net4people/bbs/issues/223)
- [wangyu-/udp2raw](https://github.com/wangyu-/udp2raw)
- [dndx/phantun](https://github.com/dndx/phantun)
- [ViRb3/wgcf](https://github.com/ViRb3/wgcf)
