#!/bin/bash

echo "======================================"
echo "TinyWebServer 10500并发压测脚本"
echo "======================================"
echo ""

echo "步骤1: 修改系统TCP参数（需要sudo权限）"
echo "请手动执行以下命令："
echo ""
echo "sudo sysctl -w net.core.somaxconn=16384"
echo "sudo sysctl -w net.ipv4.tcp_max_syn_backlog=16384"
echo "sudo sysctl -w net.ipv4.ip_local_port_range=\"1024 65535\""
echo ""
read -p "修改完成后按回车继续..."

echo ""
echo "步骤2: 验证系统参数"
echo "somaxconn: $(cat /proc/sys/net/core/somaxconn)"
echo "tcp_max_syn_backlog: $(cat /proc/sys/net/ipv4/tcp_max_syn_backlog)"
echo "ip_local_port_range: $(cat /proc/sys/net/ipv4/ip_local_port_range)"
echo ""

if [ $(cat /proc/sys/net/ipv4/tcp_max_syn_backlog) -lt 10240 ]; then
    echo "⚠️ 警告: tcp_max_syn_backlog太小，可能导致测试失败"
    read -p "是否继续？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""
echo "步骤3: 停止旧服务器"
pkill server 2>/dev/null
sleep 2

echo ""
echo "步骤4: 启动服务器（关闭日志，增强配置）"
cd /home/kiki/TinyWebServer_clean
./server -c 1 -m 0 -a 0 -s 32 -t 32 &
SERVER_PID=$!
echo "服务器PID: $SERVER_PID"
sleep 3

echo ""
echo "步骤5: 开始压力测试（10500并发，5秒）"
cd test_pressure/webbench-1.5
./webbench -c 10500 -t 5 http://127.0.0.1:9006/

echo ""
echo "步骤6: 查看服务器状态"
ps -p $SERVER_PID -o pid,vsz,rss,%cpu,%mem,cmd 2>/dev/null || echo "服务器已退出"
ss -s | grep -E "TCP:|estab"

echo ""
echo "======================================"
echo "压测完成！"
echo "======================================"

