#!/bin/bash

echo "======================================"
echo "TinyWebServer 10500并发压测脚本"
echo "======================================"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "步骤1: 检查系统参数"
echo "======================================"

# 检查文件描述符限制
FD_LIMIT=$(ulimit -n)
echo "文件描述符限制: $FD_LIMIT"
if [ $FD_LIMIT -lt 65536 ]; then
    echo -e "${RED}❌ 警告: 文件描述符限制太小！${NC}"
    echo "请执行: ulimit -n 65536"
    exit 1
else
    echo -e "${GREEN}✓ 文件描述符限制充足${NC}"
fi

# 检查TCP参数
SOMAXCONN=$(cat /proc/sys/net/core/somaxconn)
SYN_BACKLOG=$(cat /proc/sys/net/ipv4/tcp_max_syn_backlog)
PORT_RANGE=$(cat /proc/sys/net/ipv4/ip_local_port_range)

echo ""
echo "当前TCP参数："
echo "  somaxconn: $SOMAXCONN"
echo "  tcp_max_syn_backlog: $SYN_BACKLOG"
echo "  ip_local_port_range: $PORT_RANGE"
echo ""

# 检查是否需要优化
NEED_OPTIMIZE=0

if [ $SOMAXCONN -lt 16384 ]; then
    echo -e "${YELLOW}⚠️  建议增大 somaxconn${NC}"
    echo "    sudo sysctl -w net.core.somaxconn=16384"
    NEED_OPTIMIZE=1
fi

if [ $SYN_BACKLOG -lt 16384 ]; then
    echo -e "${YELLOW}⚠️  建议增大 tcp_max_syn_backlog${NC}"
    echo "    sudo sysctl -w net.ipv4.tcp_max_syn_backlog=16384"
    NEED_OPTIMIZE=1
fi

# 检查端口范围
PORT_START=$(echo $PORT_RANGE | awk '{print $1}')
PORT_END=$(echo $PORT_RANGE | awk '{print $2}')
PORT_COUNT=$((PORT_END - PORT_START))

if [ $PORT_COUNT -lt 30000 ]; then
    echo -e "${YELLOW}⚠️  建议增大端口范围${NC}"
    echo "    sudo sysctl -w net.ipv4.ip_local_port_range=\"1024 65535\""
    NEED_OPTIMIZE=1
fi

if [ $NEED_OPTIMIZE -eq 1 ]; then
    echo ""
    read -p "是否继续测试？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""
echo "步骤2: 编译服务器（确保最新代码）"
echo "======================================"
cd /home/kiki/TinyWebServer_clean
make clean > /dev/null 2>&1
make
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ 编译失败！${NC}"
    exit 1
fi
echo -e "${GREEN}✓ 编译成功${NC}"

echo ""
echo "步骤3: 停止旧服务器"
echo "======================================"
pkill -9 server 2>/dev/null
sleep 2
echo -e "${GREEN}✓ 已清理旧进程${NC}"

echo ""
echo "步骤4: 启动服务器（高性能配置）"
echo "======================================"
echo "配置说明："
echo "  -c 1     : 关闭日志（提升性能）"
echo "  -m 1     : LT+ET模式"
echo "  -a 0     : Proactor模型"
echo "  -s 8     : 8个数据库连接（测试静态页面不需要太多）"
echo "  -t 64    : 64个工作线程"
echo ""

./server -c 1 -m 1 -a 0 -s 8 -t 64 &
SERVER_PID=$!
echo "服务器PID: $SERVER_PID"

# 等待服务器启动
sleep 3

# 检查服务器是否运行
if ! ps -p $SERVER_PID > /dev/null; then
    echo -e "${RED}❌ 服务器启动失败！${NC}"
    exit 1
fi
echo -e "${GREEN}✓ 服务器启动成功${NC}"

echo ""
echo "步骤5: 预热测试（1000并发，10秒）"
echo "======================================"
cd test_pressure/webbench-1.5
./webbench -c 1000 -t 10 http://127.0.0.1:9006/judge.html
echo -e "${GREEN}✓ 预热完成${NC}"

echo ""
echo "步骤6: 开始10500并发压力测试（5秒）"
echo "======================================"
echo "测试URL: http://127.0.0.1:9006/judge.html（静态页面）"
echo "并发数: 10500"
echo "时长: 5秒"
echo ""
sleep 2

./webbench -c 10500 -t 5 http://127.0.0.1:9006/judge.html

WEBBENCH_EXIT=$?

echo ""
echo "步骤7: 查看服务器状态"
echo "======================================"

if ps -p $SERVER_PID > /dev/null; then
    echo -e "${GREEN}✓ 服务器仍在运行${NC}"
    echo ""
    echo "服务器资源使用情况："
    ps -p $SERVER_PID -o pid,vsz,rss,%cpu,%mem,cmd
    echo ""
    echo "TCP连接统计："
    ss -s | grep -E "TCP:|estab"
else
    echo -e "${RED}❌ 服务器已崩溃！${NC}"
fi

echo ""
echo "步骤8: 清理"
echo "======================================"
read -p "是否停止服务器？(y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kill $SERVER_PID
    echo -e "${GREEN}✓ 服务器已停止${NC}"
fi

echo ""
echo "======================================"
if [ $WEBBENCH_EXIT -eq 0 ]; then
    echo -e "${GREEN}✓ 压测完成！${NC}"
else
    echo -e "${RED}❌ 压测失败！${NC}"
fi
echo "======================================"

